"""Doctor-portal authorisation tests.

These are the tests that matter most for this feature: a doctor must never reach a patient
they were not granted access to, an unverified or non-doctor account must never reach the
portal at all, and revoking consent must actually cut access off.

They run against a throwaway in-memory SQLite database, never the app's real one, so they
neither depend on nor pollute existing data.
"""

from __future__ import annotations

from datetime import datetime, timezone

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from backend.app.db.models import (
    LINK_ACTIVE,
    LINK_PENDING,
    LINK_REVOKED,
    REPORT_NEW,
    ROLE_ADMIN,
    ROLE_DOCTOR,
    ROLE_PATIENT,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import Base
from backend.app.dependencies import get_current_admin, get_current_doctor
from backend.app.services.access import assert_doctor_can_view_report, doctor_can_view_report
from backend.app.utils.errors import AppError


@pytest.fixture
def db() -> Session:
    """A fresh in-memory database with the full current schema, isolated per test."""
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    session = sessionmaker(bind=engine, expire_on_commit=False)()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


def _user(db: Session, email: str, *, role: str = ROLE_PATIENT, verified: bool = False) -> User:
    user = User(email=email, password_hash="x", role=role, is_verified=verified)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _report(db: Session, owner: User, *, shared: bool) -> Report:
    report = Report(
        user_id=owner.id,
        condition="Melanoma",
        triage="urgent",
        shared_at=datetime.now(timezone.utc) if shared else None,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


def _link(db: Session, doctor: User, patient: User, *, status: str, consented: bool) -> None:
    db.add(
        DoctorPatient(
            doctor_id=doctor.id,
            patient_id=patient.id,
            status=status,
            consented_at=datetime.now(timezone.utc) if consented else None,
        )
    )
    db.commit()


# --- model defaults -----------------------------------------------------------------

def test_new_user_defaults_to_unverified_patient(db: Session) -> None:
    user = _user(db, "a@example.com")
    assert user.role == ROLE_PATIENT
    assert user.is_verified is False
    assert user.medical_reg_no is None


def test_new_report_defaults_to_new_and_unshared(db: Session) -> None:
    owner = _user(db, "p@example.com")
    report = _report(db, owner, shared=False)
    assert report.status == REPORT_NEW
    assert report.shared_at is None
    assert report.image_path is None


# --- role gates ---------------------------------------------------------------------

def test_patient_is_refused_the_doctor_area(db: Session) -> None:
    patient = _user(db, "pat@example.com", role=ROLE_PATIENT)
    with pytest.raises(AppError) as exc:
        get_current_doctor(user=patient)
    assert exc.value.status_code == 403
    assert exc.value.code == "not_authorized"


def test_unverified_doctor_is_refused_until_verified(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=False)
    with pytest.raises(AppError) as exc:
        get_current_doctor(user=doctor)
    assert exc.value.status_code == 403
    assert exc.value.code == "account_unverified"


def test_verified_doctor_is_admitted(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    assert get_current_doctor(user=doctor) is doctor


def test_only_admin_passes_admin_gate(db: Session) -> None:
    admin = _user(db, "admin@example.com", role=ROLE_ADMIN)
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    assert get_current_admin(user=admin) is admin
    with pytest.raises(AppError) as exc:
        get_current_admin(user=doctor)
    assert exc.value.status_code == 403


def test_patient_is_refused_the_admin_gate(db: Session) -> None:
    patient = _user(db, "pat@example.com", role=ROLE_PATIENT)
    with pytest.raises(AppError) as exc:
        get_current_admin(user=patient)
    assert exc.value.status_code == 403
    assert exc.value.code == "not_authorized"


def test_admin_is_refused_the_doctor_area(db: Session) -> None:
    """The doctor gate checks `role == doctor` explicitly, not merely "not a patient" -- an
    admin account is not a clinician and must not fall through into the patient-data area."""
    admin = _user(db, "admin@example.com", role=ROLE_ADMIN, verified=True)
    with pytest.raises(AppError) as exc:
        get_current_doctor(user=admin)
    assert exc.value.status_code == 403
    assert exc.value.code == "not_authorized"


# --- report access: the rule that matters -------------------------------------------

def test_access_granted_only_with_share_and_active_consent(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient = _user(db, "pat@example.com")
    report = _report(db, patient, shared=True)
    _link(db, doctor, patient, status=LINK_ACTIVE, consented=True)
    assert doctor_can_view_report(db, doctor, report) is True
    assert_doctor_can_view_report(db, doctor, report)  # does not raise


def test_no_access_to_unshared_report_even_with_consent(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient = _user(db, "pat@example.com")
    report = _report(db, patient, shared=False)
    _link(db, doctor, patient, status=LINK_ACTIVE, consented=True)
    assert doctor_can_view_report(db, doctor, report) is False


def test_no_access_without_a_link(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient = _user(db, "pat@example.com")
    report = _report(db, patient, shared=True)
    assert doctor_can_view_report(db, doctor, report) is False


def test_pending_link_is_not_access(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient = _user(db, "pat@example.com")
    report = _report(db, patient, shared=True)
    _link(db, doctor, patient, status=LINK_PENDING, consented=False)
    assert doctor_can_view_report(db, doctor, report) is False


def test_revoked_link_cuts_access_off(db: Session) -> None:
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient = _user(db, "pat@example.com")
    report = _report(db, patient, shared=True)
    # A row that was consented but later revoked: status wins, access is denied.
    _link(db, doctor, patient, status=LINK_REVOKED, consented=True)
    assert doctor_can_view_report(db, doctor, report) is False
    with pytest.raises(AppError) as exc:
        assert_doctor_can_view_report(db, doctor, report)
    assert exc.value.status_code == 403


def test_doctor_cannot_reach_another_patients_report(db: Session) -> None:
    """Doctor A is consented for patient A only; must not see patient B's shared report."""
    doctor = _user(db, "doc@example.com", role=ROLE_DOCTOR, verified=True)
    patient_a = _user(db, "a@example.com")
    patient_b = _user(db, "b@example.com")
    _link(db, doctor, patient_a, status=LINK_ACTIVE, consented=True)
    report_b = _report(db, patient_b, shared=True)
    assert doctor_can_view_report(db, doctor, report_b) is False
