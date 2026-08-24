"""Authorisation checks for doctor access to patient reports.

This is the single place that decides whether a doctor may see a given report. Every
doctor-facing route in the portal must route its access decision through here rather than
re-deriving the rule, so the rule cannot drift between endpoints.

The rule (deliberately strict, both conditions required):

  1. The patient has shared *this specific report* -- `Report.shared_at` is set.
  2. There is a live, patient-consented link between the doctor and that patient
     (`DoctorPatient.status == active` and `consented_at` is set).

A revoked link, a pending (un-consented) link, or an unshared report all deny access.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.db.models import LINK_ACTIVE, DoctorPatient, Report, User
from backend.app.utils.errors import AppError


def doctor_can_view_report(db: Session, doctor: User, report: Report) -> bool:
    """True iff `doctor` is allowed to view `report`. No side effects, no raising."""
    if report.shared_at is None:
        return False
    link = db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor.id,
            DoctorPatient.patient_id == report.user_id,
            DoctorPatient.status == LINK_ACTIVE,
            DoctorPatient.consented_at.is_not(None),
        )
    )
    return link is not None


def assert_doctor_can_view_report(db: Session, doctor: User, report: Report) -> None:
    """Raise a uniform 403 unless `doctor` may view `report`.

    The message is deliberately identical whether the report is unshared or the link is
    missing, so a doctor cannot probe which reports a patient has (existence stays hidden).
    """
    if not doctor_can_view_report(db, doctor, report):
        raise AppError(
            "not_authorized", "You do not have access to this report.", status_code=403
        )
