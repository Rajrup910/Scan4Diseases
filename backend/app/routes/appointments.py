"""Patient-facing appointment booking API (mobile client, bearer auth).

A patient books a visit with a verified doctor, optionally about one of their shared
screenings. Booking a doctor forms a care relationship, so — exactly like the "share with a
doctor" flow — it ensures an active consent link exists, and, when a report is linked, marks
that report shared so the clinician opens the visit with the case in hand.

The doctor side (approve / decline / cancel / recommend) lives in the web portal, which acts
on the same rows through a cookie session; nothing here lets a patient act on another
patient's appointments — every query is scoped to `patient_id == user.id`.

CORS on this deployment allows only GET/POST/DELETE, so every mutation here is a POST.
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.db.models import (
    ACTOR_DOCTOR,
    ACTOR_PATIENT,
    APPT_CANCELLED,
    APPT_CONFIRMED,
    APPT_LIVE_STATUSES,
    APPT_REQUESTED,
    LINK_ACTIVE,
    ROLE_DOCTOR,
    Appointment,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import get_db
from backend.app.dependencies import get_current_user
from backend.app.schemas.appointment import (
    AppointmentCancel,
    AppointmentCreate,
    AppointmentOut,
)
from backend.app.services import audit
from backend.app.utils.errors import AppError

router = APIRouter(prefix="/appointments", tags=["appointments"])


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _aware(dt: datetime | None) -> datetime | None:
    """SQLite drops tzinfo on read; the app parses correctly only if we hand back the UTC
    offset we actually stored, so re-attach it to a naive value."""
    if dt is None:
        return None
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def _to_out(db: Session, appt: Appointment) -> AppointmentOut:
    """Shape one row for the app, flattening in the doctor's name and the linked case."""
    doctor = appt.doctor or db.get(User, appt.doctor_id)
    out = AppointmentOut.model_validate(appt)
    # Return tz-aware ISO timestamps (SQLite returns them naive on read).
    out.scheduled_for = _aware(appt.scheduled_for)
    out.created_at = _aware(appt.created_at)
    out.updated_at = _aware(appt.updated_at)
    if doctor is not None:
        out.doctor_name = doctor.display_name or doctor.email
    if appt.patient is not None:
        out.patient_name = appt.patient.display_name or appt.patient.email
    if appt.report_id is not None:
        report = appt.report or db.get(Report, appt.report_id)
        out.report_condition = report.condition if report is not None else None
    return out


def _ensure_active_link(db: Session, doctor_id: int, patient_id: int) -> None:
    """Booking a doctor forms (or re-activates) a consented care link, so the visit and any
    linked case are visible to that clinician — the same effect as the app's share flow."""
    link = db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor_id,
            DoctorPatient.patient_id == patient_id,
        )
    )
    if link is None:
        db.add(
            DoctorPatient(
                doctor_id=doctor_id,
                patient_id=patient_id,
                status=LINK_ACTIVE,
                consented_at=_utcnow(),
            )
        )
    else:
        link.status = LINK_ACTIVE
        link.consented_at = link.consented_at or _utcnow()


@router.get("", response_model=list[AppointmentOut])
def list_my_appointments(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[AppointmentOut]:
    """This patient's appointments, soonest upcoming first then past, any status."""
    rows = db.scalars(
        select(Appointment)
        .where(Appointment.patient_id == user.id)
        .order_by(Appointment.scheduled_for.desc())
    ).all()
    return [_to_out(db, a) for a in rows]


@router.get("/unread-count")
def unread_count(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """How many of this patient's appointments have an unseen doctor response — the badge on
    the app's "Book an appointment" tile."""
    count = db.query(Appointment).filter(
        Appointment.patient_id == user.id,
        Appointment.unread_for_patient.is_(True),
    ).count()
    return {"count": int(count)}


@router.post("/mark-seen")
def mark_seen(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> dict:
    """Clear the unread flags once the patient has opened their appointments list."""
    rows = db.scalars(
        select(Appointment).where(
            Appointment.patient_id == user.id,
            Appointment.unread_for_patient.is_(True),
        )
    ).all()
    for a in rows:
        a.unread_for_patient = False
    if rows:
        db.commit()
    return {"ok": True, "cleared": len(rows)}


@router.post("", response_model=AppointmentOut, status_code=status.HTTP_201_CREATED)
def book_appointment(
    payload: AppointmentCreate,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AppointmentOut:
    """Book a visit with a verified doctor. Created as `requested`, awaiting the doctor's
    approval in the portal. Ensures a consent link, and shares a linked report so the
    clinician can open the case."""
    doctor = db.get(User, payload.doctor_id)
    if doctor is None or doctor.role != ROLE_DOCTOR or not doctor.is_verified:
        raise AppError("not_found", "No such doctor.", status_code=404)

    report: Report | None = None
    if payload.report_id is not None:
        report = db.get(Report, payload.report_id)
        if report is None or report.user_id != user.id:
            raise AppError("not_found", "Report not found.", status_code=404)

    _ensure_active_link(db, doctor.id, user.id)

    # A linked case must be shared for the doctor to view it; booking about it shares it.
    if report is not None and report.shared_at is None:
        report.shared_at = _utcnow()

    appt = Appointment(
        doctor_id=doctor.id,
        patient_id=user.id,
        report_id=report.id if report is not None else None,
        scheduled_for=payload.scheduled_for,
        duration_minutes=payload.duration_minutes,
        reason=payload.reason.strip(),
        status=APPT_REQUESTED,
        created_by=ACTOR_PATIENT,
    )
    db.add(appt)
    db.commit()
    db.refresh(appt)
    audit.record(
        db, user.id, audit.ACTION_APPT_BOOK,
        target_type=audit.TARGET_APPOINTMENT, target_id=appt.id, ip=audit.client_ip(request),
    )
    return _to_out(db, appt)


@router.post("/{appointment_id}/cancel", response_model=AppointmentOut)
def cancel_appointment(
    appointment_id: int,
    payload: AppointmentCancel,
    request: Request,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> AppointmentOut:
    """The patient cancels (or declines a doctor-recommended) appointment of their own. A
    terminal appointment (already cancelled/declined/completed) cannot be cancelled again."""
    appt = db.get(Appointment, appointment_id)
    if appt is None or appt.patient_id != user.id:
        raise AppError("not_found", "Appointment not found.", status_code=404)
    if appt.status not in APPT_LIVE_STATUSES:
        raise AppError("invalid_state", "This appointment can no longer be cancelled.", status_code=409)

    appt.status = APPT_CANCELLED
    appt.cancelled_by = ACTOR_PATIENT
    appt.cancel_reason = payload.reason.strip() or None
    # A patient's own action needs no "responded" badge for the patient.
    appt.unread_for_patient = False
    db.commit()
    db.refresh(appt)
    audit.record(
        db, user.id, audit.ACTION_APPT_CANCEL,
        target_type=audit.TARGET_APPOINTMENT, target_id=appt.id, ip=audit.client_ip(request),
    )
    return _to_out(db, appt)
