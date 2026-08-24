"""Patient-controlled sharing: who may see my data, and which reports I share.

Access to a patient's screening data is *patient-initiated* by design. The patient grants
a specific verified doctor access (creating/activating a `DoctorPatient` link), and shares
individual reports one at a time (`Report.shared_at`). Both are revocable here. A doctor
never grants themselves access, and an admin never assigns patients to doctors.

Every route is scoped to the authenticated caller's own rows, so one account can only ever
grant access to, or share, its own data -- never another user's.
"""

from __future__ import annotations

import io
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, Request, UploadFile, status
from PIL import Image
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.config import Settings
from backend.app.db.models import (
    LINK_ACTIVE,
    LINK_REVOKED,
    ROLE_DOCTOR,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import get_db
from backend.app.dependencies import get_app_settings, get_current_user, get_image_vault
from backend.app.schemas.doctor import ConsentOut, DoctorDirectoryEntry, SharedImageOut
from backend.app.services import audit
from backend.app.services.image_vault import ImageVault
from backend.app.services.preprocessing import ImageValidationError, decode_image
from backend.app.utils.errors import HTTP_422_UNPROCESSABLE, AppError

router = APIRouter(prefix="/patient", tags=["patient-sharing"])


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _verified_doctor_or_404(db: Session, doctor_id: int) -> User:
    """Resolve a verified doctor, or a 404 that reveals nothing about non-doctor accounts.

    A patient may only grant access to a real, verified doctor. The message stays a plain
    "not found" whether the id is unknown, belongs to a patient, or an unverified doctor,
    so this route cannot be used to enumerate accounts or roles.
    """
    doctor = db.get(User, doctor_id)
    if doctor is None or doctor.role != ROLE_DOCTOR or not doctor.is_verified:
        raise AppError("not_found", "No such doctor.", status_code=404)
    return doctor


@router.get("/doctors", response_model=list[DoctorDirectoryEntry])
def list_available_doctors(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[User]:
    """The verified doctors a patient may share with -- the directory the app's "share with a
    doctor" picker lists. Any signed-in user may read it (a patient has to see the clinicians
    before they can choose one); it exposes only professional identity, never patient data."""
    rows = db.scalars(
        select(User)
        .where(User.role == ROLE_DOCTOR, User.is_verified.is_(True))
        .order_by(User.display_name, User.id)
    ).all()
    return list(rows)


@router.get("/consent", response_model=list[ConsentOut])
def list_my_consents(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[DoctorPatient]:
    """Every access link this patient has, in any state (active, revoked, pending)."""
    rows = db.scalars(
        select(DoctorPatient)
        .where(DoctorPatient.patient_id == user.id)
        .order_by(DoctorPatient.created_at.desc())
    ).all()
    return list(rows)


@router.post("/consent/{doctor_id}", response_model=ConsentOut)
def grant_consent(
    doctor_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DoctorPatient:
    """Grant (or re-activate) a doctor's access to this patient's shared reports.

    Idempotent: a second call, or re-granting after a revoke, simply moves the single link
    for this (doctor, patient) pair back to `active` and stamps `consented_at`. The unique
    constraint guarantees there is only ever one such row.
    """
    doctor = _verified_doctor_or_404(db, doctor_id)

    link = db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor.id,
            DoctorPatient.patient_id == user.id,
        )
    )
    if link is None:
        link = DoctorPatient(doctor_id=doctor.id, patient_id=user.id)
        db.add(link)
    link.status = LINK_ACTIVE
    link.consented_at = _utcnow()
    db.commit()
    db.refresh(link)
    audit.record(
        db, user.id, audit.ACTION_CONSENT_GRANT,
        target_type=audit.TARGET_USER, target_id=doctor.id, ip=audit.client_ip(request),
    )
    return link


@router.delete("/consent/{doctor_id}", response_model=ConsentOut)
def revoke_consent(
    doctor_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DoctorPatient:
    """Withdraw a doctor's access. The link is kept but set to `revoked` with no consent
    timestamp, so the history of having granted-then-revoked is preserved and access is cut
    off immediately (the access rule requires `active` + `consented_at`)."""
    link = db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor_id,
            DoctorPatient.patient_id == user.id,
        )
    )
    if link is None:
        raise AppError("not_found", "No such consent to revoke.", status_code=404)
    link.status = LINK_REVOKED
    link.consented_at = None
    db.commit()
    db.refresh(link)
    audit.record(
        db, user.id, audit.ACTION_CONSENT_REVOKE,
        target_type=audit.TARGET_USER, target_id=doctor_id, ip=audit.client_ip(request),
    )
    return link


def _own_report_or_404(db: Session, report_id: int, user: User) -> Report:
    report = db.get(Report, report_id)
    if report is None or report.user_id != user.id:
        raise AppError("not_found", "Report not found.", status_code=404)
    return report


@router.post("/reports/{report_id}/share", status_code=status.HTTP_204_NO_CONTENT)
def share_report(
    report_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    """Mark one of the patient's own reports as shared. Sharing only flips `shared_at`;
    whether any doctor can then read it still depends on an active consent link. Re-sharing
    an already-shared report leaves the original timestamp untouched."""
    report = _own_report_or_404(db, report_id, user)
    if report.shared_at is None:
        report.shared_at = _utcnow()
        db.commit()
    audit.record(
        db, user.id, audit.ACTION_REPORT_SHARE,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )


@router.delete("/reports/{report_id}/share", status_code=status.HTTP_204_NO_CONTENT)
def unshare_report(
    report_id: int,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
) -> None:
    """Stop sharing a report. Clearing `shared_at` denies every doctor access to it again,
    regardless of any consent link.

    Unsharing also *destroys* any encrypted image the patient uploaded for this report --
    withdrawing the share withdraws the image, so a shared photo never lingers on disk (even
    as ciphertext) after the patient changed their mind."""
    report = _own_report_or_404(db, report_id, user)
    old_image, old_gradcam = report.image_path, report.gradcam_path
    changed = report.shared_at is not None or old_image is not None or old_gradcam is not None
    report.shared_at = None
    report.image_path = None
    report.gradcam_path = None
    if changed:
        db.commit()
    audit.record(
        db, user.id, audit.ACTION_REPORT_UNSHARE,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    # Delete the blobs only after the DB no longer references them, so a crash mid-way
    # never leaves a row pointing at a file that is gone.
    vault.remove(old_image)
    vault.remove(old_gradcam)


async def _validated_image(upload: UploadFile, settings: Settings) -> Image.Image:
    """Read an uploaded file and run it through the same validation `/predict` uses
    (size, format, dimensions, EXIF-orientation fix, RGB). Raises a client-safe 422."""
    try:
        raw = await upload.read()
    finally:
        await upload.close()
    try:
        return decode_image(raw, settings.max_upload_bytes)
    except ImageValidationError as exc:
        raise AppError(exc.code, exc.message, HTTP_422_UNPROCESSABLE) from exc


def _encode(decoded: Image.Image, *, as_png: bool) -> tuple[bytes, str]:
    """Re-encode a decoded image to a clean blob. Re-encoding from the decoded pixels drops
    any original metadata (crucially, camera GPS EXIF) before the image is ever persisted.
    Overlays go to PNG (sharp); photographs to JPEG (compact)."""
    buffer = io.BytesIO()
    if as_png:
        decoded.save(buffer, format="PNG", optimize=True)
        return buffer.getvalue(), "image/png"
    decoded.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue(), "image/jpeg"


@router.post("/reports/{report_id}/image", response_model=SharedImageOut)
async def upload_shared_image(
    report_id: int,
    request: Request,
    image: UploadFile = File(..., description="The lesion photograph to share (JPEG/PNG)."),
    gradcam: UploadFile | None = File(
        default=None, description="Optional Grad-CAM overlay for the same report."
    ),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
    settings: Settings = Depends(get_app_settings),
) -> SharedImageOut:
    """Attach an encrypted image (and optionally its Grad-CAM overlay) to one of the
    patient's own reports, and mark the report shared.

    This is the ONLY path by which a lesion image is persisted (Option B): `/predict` never
    writes it, and a report saved without sharing holds only metadata. The bytes are
    encrypted before they touch disk; the report stores blob references, never a servable
    path. Uploading again replaces the previous blobs. Requires `IMAGE_ENCRYPTION_KEY` to be
    configured, else a 503 -- image sharing fails loudly, never silently in plaintext.
    """
    report = _own_report_or_404(db, report_id, user)

    image_data, image_type = _encode(await _validated_image(image, settings), as_png=False)
    gradcam_name: str | None = None
    if gradcam is not None:
        gradcam_data, gradcam_type = _encode(
            await _validated_image(gradcam, settings), as_png=True
        )

    # Encrypt-and-write only after both uploads validate, so a bad overlay can't leave a
    # half-shared report with an orphaned image blob.
    old_image, old_gradcam = report.image_path, report.gradcam_path
    report.image_path = vault.store(image_data, image_type)
    if gradcam is not None:
        gradcam_name = vault.store(gradcam_data, gradcam_type)
        report.gradcam_path = gradcam_name
    if report.shared_at is None:
        report.shared_at = _utcnow()
    db.commit()
    db.refresh(report)

    # Replaced blobs are removed after the row points at the new ones.
    if old_image and old_image != report.image_path:
        vault.remove(old_image)
    if old_gradcam and old_gradcam != report.gradcam_path:
        vault.remove(old_gradcam)

    # Uploading an image IS a share action (it stamps shared_at), so record it as one.
    audit.record(
        db, user.id, audit.ACTION_REPORT_SHARE,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )

    return SharedImageOut(
        report_id=report.id,
        shared_at=report.shared_at,
        has_image=report.image_path is not None,
        has_gradcam=report.gradcam_path is not None,
    )
