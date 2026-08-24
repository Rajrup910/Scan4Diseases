"""Automatic database seeding for cloud & local instances.

Ensures that the default demo doctor (dr.rao@example.com), patient (raj@gmail.com),
and demo worklist data are always available on startup without requiring manual CLI intervention.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.db.models import (
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
from backend.app.security import hash_password

logger = logging.getLogger(__name__)

DOCTOR_EMAIL = "dr.rao@example.com"
DOCTOR_PASSWORD = "Str0ngPass!"
DOCTOR_NAME = "Dr. A. Rao"

PATIENT_EMAIL = "raj@gmail.com"
PATIENT_PASSWORD = "12345678"
PATIENT_NAME = "Raj"

DEMO_PATIENTS = [
    (
        "Priya Sharma",
        "priya@example.com",
        [
            dict(
                condition="Melanoma",
                predicted_class="mel",
                confidence=0.91,
                triage="Urgent medical evaluation",
                status=REPORT_ESCALATED,
                days=1,
                explanation="Asymmetric borders with colour variegation and recent change reported.",
                symptoms={"itching": True, "bleeding": True, "duration_weeks": 8, "evolving": True},
                note="Recommend excisional biopsy within one week. Flagged to dermatology.",
            ),
            dict(
                condition="Basal cell carcinoma",
                predicted_class="bcc",
                confidence=0.78,
                triage="Prompt dermatologist consultation",
                status=REPORT_UNDER_REVIEW,
                days=6,
                explanation="Pearly papule with fine telangiectasia.",
                symptoms={"itching": False, "duration_weeks": 20, "bleeds_occasionally": True},
            ),
            dict(
                condition="Benign nevus",
                predicted_class="nv",
                confidence=0.88,
                triage="Routine dermatologist consultation",
                status=REPORT_REVIEWED,
                days=15,
                explanation="Stable, symmetric pigmented lesion.",
                symptoms={"duration_weeks": 104, "stable": True},
            ),
        ],
    ),
    (
        "Sam Rivera",
        "sam@example.com",
        [
            dict(
                condition="Squamous cell carcinoma",
                predicted_class="scc",
                confidence=0.83,
                triage="Urgent medical evaluation",
                status=REPORT_NEW,
                days=2,
                explanation="Keratotic nodule, tender, with reported rapid growth.",
                symptoms={"bleeding": True, "painful": True, "duration_weeks": 5},
            ),
            dict(
                condition="Actinic keratosis",
                predicted_class="akiec",
                confidence=0.66,
                triage="Prompt dermatologist consultation",
                status=REPORT_NEW,
                days=4,
                explanation="Rough, scaly patch on sun-exposed skin.",
                symptoms={"rough_patch": True, "sun_exposure": "high", "duration_weeks": 30},
            ),
        ],
    ),
    (
        "Jordan Lee",
        "jordan@example.com",
        [
            dict(
                condition="Seborrheic keratosis",
                predicted_class="bkl",
                confidence=0.94,
                triage="Routine dermatologist consultation",
                status=REPORT_REVIEWED,
                days=9,
                explanation="Well-demarcated, stuck-on appearance.",
                symptoms={"duration_weeks": 52, "stable": True},
                note="Benign. Reassured; no action needed unless symptomatic.",
            ),
            dict(
                condition="Dermatofibroma",
                predicted_class="df",
                confidence=0.71,
                triage="Routine dermatologist consultation",
                status=REPORT_NEW,
                days=12,
                explanation="Firm dermal nodule, dimples on lateral pressure.",
                symptoms={"firm_nodule": True, "duration_weeks": 60},
            ),
        ],
    ),
    ("Maria Gomez", "maria@example.com", []),
]


def seed_default_data(db: Session) -> None:
    """Seed default doctor, patient, and clinical demo records idempotently."""
    now = datetime.now(timezone.utc)

    # 1. Seed or ensure Doctor (dr.rao@example.com)
    doctor = db.scalar(select(User).where(User.email == DOCTOR_EMAIL))
    if doctor is None:
        doctor = User(
            email=DOCTOR_EMAIL,
            display_name=DOCTOR_NAME,
            password_hash=hash_password(DOCTOR_PASSWORD),
            role=ROLE_DOCTOR,
            is_verified=True,
            medical_reg_no="MH-12345",
        )
        db.add(doctor)
        db.flush()
        logger.info("Auto-seeded default doctor account: %s", DOCTOR_EMAIL)
    else:
        # Ensure role & verification are up-to-date
        doctor.role = ROLE_DOCTOR
        doctor.is_verified = True
        doctor.password_hash = hash_password(DOCTOR_PASSWORD)
        db.flush()

    # 2. Seed or ensure Patient (raj@gmail.com)
    patient_raj = db.scalar(select(User).where(User.email == PATIENT_EMAIL))
    if patient_raj is None:
        patient_raj = User(
            email=PATIENT_EMAIL,
            display_name=PATIENT_NAME,
            password_hash=hash_password(PATIENT_PASSWORD),
            role=ROLE_PATIENT,
        )
        db.add(patient_raj)
        db.flush()
        logger.info("Auto-seeded default patient account: %s", PATIENT_EMAIL)
    else:
        patient_raj.password_hash = hash_password(PATIENT_PASSWORD)
        db.flush()

    # Seed demo reports for raj@gmail.com if none exist
    has_raj_reports = db.scalar(select(Report).where(Report.user_id == patient_raj.id))
    if has_raj_reports is None:
        r1_date = now - timedelta(days=3)
        db.add(
            Report(
                user_id=patient_raj.id,
                condition="Melanocytic nevus",
                predicted_class="nv",
                confidence=0.92,
                triage="Routine dermatologist consultation",
                status=REPORT_NEW,
                explanation="Well-defined, symmetric pigmented lesion with uniform color network.",
                symptoms={"duration_weeks": 52, "stable": True, "itching": False},
                created_at=r1_date,
                shared_at=r1_date,
            )
        )
        r2_date = now - timedelta(days=14)
        db.add(
            Report(
                user_id=patient_raj.id,
                condition="Basal cell carcinoma",
                predicted_class="bcc",
                confidence=0.79,
                triage="Prompt dermatologist consultation",
                status=REPORT_NEW,
                explanation="Pearly nodule with fine telangiectasia observed.",
                symptoms={"duration_weeks": 16, "itching": False, "bleeding": True},
                created_at=r2_date,
                shared_at=r2_date,
            )
        )
        db.flush()

    # Ensure DoctorPatient link exists for raj@gmail.com
    raj_link = db.scalar(
        select(DoctorPatient).where(
            DoctorPatient.doctor_id == doctor.id,
            DoctorPatient.patient_id == patient_raj.id,
        )
    )
    if raj_link is None:
        db.add(
            DoctorPatient(
                doctor_id=doctor.id,
                patient_id=patient_raj.id,
                status=LINK_ACTIVE,
                consented_at=now,
            )
        )
    else:
        raj_link.status = LINK_ACTIVE
        raj_link.consented_at = raj_link.consented_at or now
    db.flush()

    # 3. Seed demo patients & worklist reports for Doctor Portal
    for name, email, reports in DEMO_PATIENTS:
        p = db.scalar(select(User).where(User.email == email))
        if p is None:
            p = User(
                email=email,
                display_name=name,
                role=ROLE_PATIENT,
                password_hash=hash_password("patientpass"),
            )
            db.add(p)
            db.flush()

        # Consented link with doctor
        link = db.scalar(
            select(DoctorPatient).where(
                DoctorPatient.doctor_id == doctor.id,
                DoctorPatient.patient_id == p.id,
            )
        )
        if link is None:
            db.add(
                DoctorPatient(
                    doctor_id=doctor.id,
                    patient_id=p.id,
                    status=LINK_ACTIVE,
                    consented_at=now,
                )
            )
        else:
            link.status = LINK_ACTIVE
            link.consented_at = link.consented_at or now

        # Add reports if patient has none
        has_reports = db.scalar(select(Report).where(Report.user_id == p.id))
        if has_reports is None:
            for spec in reports:
                r_date = now - timedelta(days=spec["days"])
                r = Report(
                    user_id=p.id,
                    condition=spec["condition"],
                    predicted_class=spec["predicted_class"],
                    confidence=spec["confidence"],
                    triage=spec["triage"],
                    status=spec["status"],
                    explanation=spec["explanation"],
                    symptoms=spec.get("symptoms", {}),
                    created_at=r_date,
                    shared_at=r_date,
                )
                db.add(r)
                db.flush()
                if "note" in spec:
                    db.add(
                        DoctorNote(
                            report_id=r.id,
                            doctor_id=doctor.id,
                            note=spec["note"],
                            created_at=r_date,
                        )
                    )

    db.commit()
    logger.info("Initial database seed verified and active.")
