"""Seed the local database with demo data so the clinician portal has something to show.

Creates one verified doctor, a few consented patients, and a spread of shared reports
(varied condition / triage / confidence / status) plus a couple of notes -- enough to
populate the worklist dashboard, the triage donut, the status filter and the report detail.

Idempotent: re-running does not duplicate. Reports are only added to a patient who has none.

    .venv/Scripts/python.exe scripts/seed_portal_demo.py

Login afterwards at  http://localhost:8000/portal/login  with the credentials it prints.
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from sqlalchemy import select  # noqa: E402

from backend.app.db.models import (  # noqa: E402
    LINK_ACTIVE,
    REPORT_ESCALATED,
    REPORT_NEW,
    REPORT_REVIEWED,
    REPORT_UNDER_REVIEW,
    ROLE_DOCTOR,
    ROLE_PATIENT,
    DoctorNote,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import SessionLocal, init_db  # noqa: E402
from backend.app.security import hash_password  # noqa: E402

DOCTOR_EMAIL = "dr.rao@example.com"
DOCTOR_PASSWORD = "demopassword"
DOCTOR_NAME = "Dr. A. Rao"

now = datetime.now(timezone.utc)


def _ago(days: int) -> datetime:
    return now - timedelta(days=days)


# (display_name, email, [reports]); each report is a dict of fields.
PATIENTS = [
    ("Priya Sharma", "priya@example.com", [
        dict(condition="Melanoma", predicted_class="mel", confidence=0.91,
             triage="Urgent medical evaluation", status=REPORT_ESCALATED, days=1,
             explanation="Asymmetric borders with colour variegation and recent change reported.",
             symptoms={"itching": True, "bleeding": True, "duration_weeks": 8, "evolving": True},
             note="Recommend excisional biopsy within one week. Flagged to dermatology."),
        dict(condition="Basal cell carcinoma", predicted_class="bcc", confidence=0.78,
             triage="Prompt dermatologist consultation", status=REPORT_UNDER_REVIEW, days=6,
             explanation="Pearly papule with fine telangiectasia.",
             symptoms={"itching": False, "duration_weeks": 20, "bleeds_occasionally": True}),
        dict(condition="Benign nevus", predicted_class="nv", confidence=0.88,
             triage="Routine dermatologist consultation", status=REPORT_REVIEWED, days=15,
             explanation="Stable, symmetric pigmented lesion.",
             symptoms={"duration_weeks": 104, "stable": True}),
    ]),
    ("Sam Rivera", "sam@example.com", [
        dict(condition="Squamous cell carcinoma", predicted_class="scc", confidence=0.83,
             triage="Urgent medical evaluation", status=REPORT_NEW, days=2,
             explanation="Keratotic nodule, tender, with reported rapid growth.",
             symptoms={"bleeding": True, "painful": True, "duration_weeks": 5}),
        dict(condition="Actinic keratosis", predicted_class="akiec", confidence=0.66,
             triage="Prompt dermatologist consultation", status=REPORT_NEW, days=4,
             explanation="Rough, scaly patch on sun-exposed skin.",
             symptoms={"rough_patch": True, "sun_exposure": "high", "duration_weeks": 30}),
    ]),
    ("Jordan Lee", "jordan@example.com", [
        dict(condition="Seborrheic keratosis", predicted_class="bkl", confidence=0.94,
             triage="Routine dermatologist consultation", status=REPORT_REVIEWED, days=9,
             explanation="Well-demarcated, stuck-on appearance.",
             symptoms={"duration_weeks": 52, "stable": True},
             note="Benign. Reassured; no action needed unless symptomatic."),
        dict(condition="Dermatofibroma", predicted_class="df", confidence=0.71,
             triage="Routine dermatologist consultation", status=REPORT_NEW, days=12,
             explanation="Firm dermal nodule, dimples on lateral pressure.",
             symptoms={"firm_nodule": True, "duration_weeks": 60}),
    ]),
    ("Maria Gomez", "maria@example.com", []),  # linked, but nothing shared yet
]


def _get_or_create_user(db, *, email, name, role, verified, password=None) -> User:
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        user = User(
            email=email, display_name=name, role=role, is_verified=verified,
            password_hash=hash_password(password or "patientpass"),
        )
        db.add(user)
        db.flush()
    return user


def main() -> int:
    init_db()
    db = SessionLocal()
    created_reports = 0
    try:
        doctor = _get_or_create_user(
            db, email=DOCTOR_EMAIL, name=DOCTOR_NAME, role=ROLE_DOCTOR,
            verified=True, password=DOCTOR_PASSWORD,
        )
        doctor.role = ROLE_DOCTOR
        doctor.is_verified = True

        for name, email, reports in PATIENTS:
            patient = _get_or_create_user(
                db, email=email, name=name, role=ROLE_PATIENT, verified=True,
            )
            # consented, active link
            link = db.scalar(
                select(DoctorPatient).where(
                    DoctorPatient.doctor_id == doctor.id,
                    DoctorPatient.patient_id == patient.id,
                )
            )
            if link is None:
                db.add(DoctorPatient(
                    doctor_id=doctor.id, patient_id=patient.id,
                    status=LINK_ACTIVE, consented_at=now,
                ))
            else:
                link.status = LINK_ACTIVE
                link.consented_at = link.consented_at or now

            # add reports only if this patient has none (idempotent)
            existing = db.scalar(select(Report).where(Report.user_id == patient.id))
            if existing is None:
                for r in reports:
                    ts = _ago(r["days"])
                    report = Report(
                        user_id=patient.id,
                        condition=r["condition"],
                        predicted_class=r.get("predicted_class"),
                        confidence=r.get("confidence"),
                        triage=r["triage"],
                        explanation=r.get("explanation", ""),
                        symptoms=r.get("symptoms", {}),
                        status=r["status"],
                        shared_at=ts,
                        created_at=ts,
                    )
                    db.add(report)
                    db.flush()
                    if r.get("note"):
                        db.add(DoctorNote(report_id=report.id, doctor_id=doctor.id, note=r["note"]))
                    created_reports += 1

        db.commit()
    finally:
        db.close()

    print("Demo data ready.")
    print(f"  Added {created_reports} new report(s).")
    print("  Sign in at http://localhost:8000/portal/login")
    print(f"    email:    {DOCTOR_EMAIL}")
    print(f"    password: {DOCTOR_PASSWORD}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
