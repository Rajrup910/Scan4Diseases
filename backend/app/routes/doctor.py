"""Doctor-facing portal endpoints: the patients who have shared, and their shared reports.

Every route requires a verified doctor (`get_current_doctor`) and routes every report-level
access decision through `services.access`, which enforces the one rule: the report must be
shared *and* backed by an active, patient-consented link. A doctor therefore can only ever
reach a patient who chose to share, and only the specific reports that patient shared --
this is tested at the HTTP layer, not just in the helper.

No UI here; these are JSON endpoints exercised by curl and pytest. The web portal (Session 4)
renders on top of exactly these rules.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.app.db.models import (
    LINK_ACTIVE,
    DoctorNote,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import get_db
from backend.app.dependencies import get_current_doctor, get_image_vault
from backend.app.schemas.doctor import (
    DoctorNoteOut,
    DoctorReportDetail,
    DoctorReportSummary,
    NoteCreate,
    PatientSummary,
    StatusUpdate,
)
from backend.app.services import audit
from backend.app.services.access import assert_doctor_can_view_report
from backend.app.services.image_vault import ImageVault
from backend.app.utils.errors import AppError

router = APIRouter(prefix="/doctor", tags=["doctor"])


def _active_link(db: Session, doctor: User, patient_id: int) -> DoctorPatient | None:
    return db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor.id,
            DoctorPatient.patient_id == patient_id,
            DoctorPatient.status == LINK_ACTIVE,
            DoctorPatient.consented_at.is_not(None),
        )
    )


@router.get("/patients", response_model=list[PatientSummary])
def list_patients(
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> list[PatientSummary]:
    """Patients with an active, consented link to this doctor, each with a count of the
    reports they currently share. A consented patient with nothing shared still appears
    (count 0), so the doctor can see the relationship exists."""
    # One row per consented patient, left-joined to their *shared* reports for the count.
    shared = (
        select(Report.user_id, func.count(Report.id).label("n"))
        .where(Report.shared_at.is_not(None))
        .group_by(Report.user_id)
        .subquery()
    )
    rows = db.execute(
        select(User, func.coalesce(shared.c.n, 0))
        .join(
            DoctorPatient,
            (DoctorPatient.patient_id == User.id)
            & (DoctorPatient.doctor_id == doctor.id)
            & (DoctorPatient.status == LINK_ACTIVE)
            & (DoctorPatient.consented_at.is_not(None)),
        )
        .join(shared, shared.c.user_id == User.id, isouter=True)
        .order_by(User.id)
    ).all()

    return [
        PatientSummary(
            id=patient.id,
            email=patient.email,
            display_name=patient.display_name,
            shared_report_count=int(count),
        )
        for patient, count in rows
    ]


@router.get("/patients/{patient_id}/reports", response_model=list[DoctorReportSummary])
def list_patient_reports(
    patient_id: int,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> list[Report]:
    """The shared reports of one consented patient. Requires an active link to that patient
    (else 404, which reveals nothing about whether the patient exists), and returns only
    reports the patient has actually shared."""
    if _active_link(db, doctor, patient_id) is None:
        raise AppError("not_found", "Patient not found.", status_code=404)
    rows = db.scalars(
        select(Report)
        .where(Report.user_id == patient_id, Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()
    return list(rows)


def _viewable_report_or_403(db: Session, doctor: User, report_id: int) -> Report:
    """Load a report and assert the doctor may view it.

    A missing report and a forbidden one both raise the same 403 message from
    `assert_doctor_can_view_report`, so a doctor cannot tell an unshared/other-patient
    report apart from a non-existent id (no existence probing).
    """
    report = db.get(Report, report_id)
    if report is None:
        raise AppError("not_authorized", "You do not have access to this report.", status_code=403)
    assert_doctor_can_view_report(db, doctor, report)
    return report


@router.get("/reports/{report_id}", response_model=DoctorReportDetail)
def get_report(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> Report:
    """A single shared report in full, with the doctor's notes attached."""
    report = _viewable_report_or_403(db, doctor, report_id)
    audit.record(
        db, doctor.id, audit.ACTION_REPORT_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return report


@router.patch("/reports/{report_id}/status", response_model=DoctorReportSummary)
def set_report_status(
    report_id: int,
    payload: StatusUpdate,
    request: Request,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> Report:
    """Move a shared report along the review workflow (e.g. new -> under_review -> reviewed)."""
    report = _viewable_report_or_403(db, doctor, report_id)
    report.status = payload.status
    db.commit()
    db.refresh(report)
    audit.record(
        db, doctor.id, audit.ACTION_STATUS_CHANGE,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return report


@router.get("/reports/{report_id}/notes", response_model=list[DoctorNoteOut])
def list_notes(
    report_id: int,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> list[DoctorNote]:
    _viewable_report_or_403(db, doctor, report_id)
    rows = db.scalars(
        select(DoctorNote)
        .where(DoctorNote.report_id == report_id)
        .order_by(DoctorNote.created_at.asc())
    ).all()
    return list(rows)


@router.post(
    "/reports/{report_id}/notes",
    response_model=DoctorNoteOut,
    status_code=status.HTTP_201_CREATED,
)
def add_note(
    report_id: int,
    payload: NoteCreate,
    request: Request,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
) -> DoctorNote:
    """Record a clinician note against a shared report. Notes are the doctor's own working
    record and are never surfaced to the patient as a diagnosis by the app."""
    _viewable_report_or_403(db, doctor, report_id)
    note = DoctorNote(report_id=report_id, doctor_id=doctor.id, note=payload.note.strip())
    db.add(note)
    db.commit()
    db.refresh(note)
    audit.record(
        db, doctor.id, audit.ACTION_NOTE_ADD,
        target_type=audit.TARGET_REPORT, target_id=report_id, ip=audit.client_ip(request),
    )
    return note


def _serve_shared_blob(vault: ImageVault, blob_ref: str | None) -> Response:
    """Decrypt and stream a shared-image blob. Access is assumed already checked by the
    caller via `_viewable_report_or_403`; a missing/undecryptable blob is a 404."""
    if not blob_ref:
        raise AppError("image_not_found", "No image was shared for this report.", status_code=404)
    loaded = vault.load(blob_ref)
    if loaded is None:
        raise AppError("image_not_found", "This image is no longer available.", status_code=404)
    media_type, data = loaded
    return Response(
        content=data,
        media_type=media_type,
        # A medical image must never be cached by a proxy or left in the browser cache.
        headers={"Cache-Control": "private, no-store"},
    )


@router.get("/reports/{report_id}/image")
def get_report_image(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
) -> Response:
    """Stream the decrypted lesion image of a shared report. Gated by exactly the report
    access rule -- an unshared/other-patient/nonexistent report returns the same 403 as
    every other report route, so the image endpoint cannot be used to probe either."""
    report = _viewable_report_or_403(db, doctor, report_id)
    response = _serve_shared_blob(vault, report.image_path)
    audit.record(
        db, doctor.id, audit.ACTION_IMAGE_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return response


@router.get("/reports/{report_id}/gradcam")
def get_report_gradcam(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_current_doctor),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
) -> Response:
    """Stream the decrypted Grad-CAM overlay of a shared report, if the patient shared one.
    Same access gate as the lesion image."""
    report = _viewable_report_or_403(db, doctor, report_id)
    response = _serve_shared_blob(vault, report.gradcam_path)
    audit.record(
        db, doctor.id, audit.ACTION_GRADCAM_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return response
