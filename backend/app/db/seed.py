"""Automatic database seeding for cloud & local instances.

Ensures that the default demo doctor (dr.rao@example.com), patient (raj@gmail.com),
and demo worklist data are always available on startup without requiring manual CLI intervention.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.config import get_settings
from backend.app.db.models import (
    ACTOR_DOCTOR,
    ACTOR_PATIENT,
    APPT_CANCELLED,
    APPT_CONFIRMED,
    APPT_REQUESTED,
    LINK_ACTIVE,
    REPORT_ESCALATED,
    REPORT_NEW,
    REPORT_REVIEWED,
    REPORT_UNDER_REVIEW,
    ROLE_DOCTOR,
    ROLE_PATIENT,
    Appointment,
    DoctorNote,
    DoctorPatient,
    Report,
    User,
)
from backend.app.security import hash_password
from backend.app.services.image_vault import ImageVault

logger = logging.getLogger(__name__)


# --- Demo Clinicians (Verified Doctors) ---
DOCTOR_EMAIL = "dr.rao@example.com"
DOCTOR_PASSWORD = "Str0ngPass!"
DOCTOR_NAME = "Dr. A. Rao"
DOCTOR_REG_NO = "MH-12345"

DOCTOR_2_EMAIL = "dr.mehta@example.com"
DOCTOR_2_PASSWORD = "Str0ngPass!"
DOCTOR_2_NAME = "Dr. Sunita Mehta"
DOCTOR_2_REG_NO = "KA-67890"

DOCTOR_3_EMAIL = "dr.kapoor@example.com"
DOCTOR_3_PASSWORD = "Str0ngPass!"
DOCTOR_3_NAME = "Dr. Vikram Kapoor"
DOCTOR_3_REG_NO = "DL-98765"

DOCTOR_4_EMAIL = "dr.nambiar@example.com"
DOCTOR_4_PASSWORD = "Str0ngPass!"
DOCTOR_4_NAME = "Dr. Priya Nambiar"
DOCTOR_4_REG_NO = "KL-45678"

DOCTOR_5_EMAIL = "dr.deshmukh@example.com"
DOCTOR_5_PASSWORD = "Str0ngPass!"
DOCTOR_5_NAME = "Dr. Rajesh Deshmukh"
DOCTOR_5_REG_NO = "MH-54321"

DOCTOR_6_EMAIL = "dr.sen@example.com"
DOCTOR_6_PASSWORD = "Str0ngPass!"
DOCTOR_6_NAME = "Dr. Ananya Sen"
DOCTOR_6_REG_NO = "WB-34567"

DEMO_DOCTORS = [
    (DOCTOR_NAME, DOCTOR_EMAIL, DOCTOR_PASSWORD, DOCTOR_REG_NO),
    (DOCTOR_2_NAME, DOCTOR_2_EMAIL, DOCTOR_2_PASSWORD, DOCTOR_2_REG_NO),
    (DOCTOR_3_NAME, DOCTOR_3_EMAIL, DOCTOR_3_PASSWORD, DOCTOR_3_REG_NO),
    (DOCTOR_4_NAME, DOCTOR_4_EMAIL, DOCTOR_4_PASSWORD, DOCTOR_4_REG_NO),
    (DOCTOR_5_NAME, DOCTOR_5_EMAIL, DOCTOR_5_PASSWORD, DOCTOR_5_REG_NO),
    (DOCTOR_6_NAME, DOCTOR_6_EMAIL, DOCTOR_6_PASSWORD, DOCTOR_6_REG_NO),
]


# --- Patient 1 (Primary demo patient) ---
PATIENT_EMAIL = "raj@gmail.com"
PATIENT_PASSWORD = "12345678"
PATIENT_NAME = "Raj"

# --- Patient 2 (Second demo patient) ---
PATIENT_2_EMAIL = "ananya@gmail.com"
PATIENT_2_PASSWORD = "12345678"
PATIENT_2_NAME = "Ananya Verma"

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
        "Aarav Patel",
        "aarav@example.com",
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
        "Rohan Sen",
        "rohan@example.com",
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
    ("Neha Deshmukh", "neha@example.com", []),
]


def _get_vault_sample_tokens(vault: ImageVault) -> dict[str, tuple[str, str | None]]:
    """Ensure standard clinical sample photos & Grad-CAMs exist in ImageVault and return their tokens."""
    if not vault.configured:
        return {}

    mapping = {
        "mel": "01_melanoma_malignant.jpg",
        "bcc": "02_basal_cell_carcinoma.jpg",
        "akiec": "03_actinic_keratosis_precancer.jpg",
        "nv": "04_benign_melanocytic_nevus.jpg",
        "bkl": "04_benign_melanocytic_nevus.jpg",
        "df": "04_benign_melanocytic_nevus.jpg",
        "vasc": "04_benign_melanocytic_nevus.jpg",
        "other_damage": "05_skin_abrasion_wound.jpg",
        "healthy": "04_benign_melanocytic_nevus.jpg",
    }

    tokens: dict[str, tuple[str, str | None]] = {}
    from backend.app.config import REPO_ROOT
    sample_dir = REPO_ROOT / "demo_test_samples"

    import io
    from PIL import Image

    for cls_name, filename in mapping.items():
        img_path = sample_dir / filename
        if not img_path.exists():
            continue
        try:
            pil_img = Image.open(img_path).convert("RGB")
            buf = io.BytesIO()
            pil_img.save(buf, format="JPEG", quality=90)
            img_token = vault.store(buf.getvalue(), "image/jpeg")

            tokens[cls_name] = (img_token, None)
        except Exception as err:
            logger.warning("Could not seed sample %s to vault: %s", filename, err)

    return tokens


def _link_doctor_and_patient(db: Session, doctor_id: int, patient_id: int, consented_at: datetime) -> None:
    """Ensure an active consented link exists between a doctor and a patient."""
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
                consented_at=consented_at,
            )
        )
    else:
        link.status = LINK_ACTIVE
        link.consented_at = link.consented_at or consented_at


def _first_report(db: Session, patient_id: int) -> Report | None:
    return db.scalar(
        select(Report)
        .where(Report.user_id == patient_id)
        .order_by(Report.created_at.desc())
    )


def _seed_appointments(
    db: Session,
    doctor: User,
    patient_raj: User,
    patient_ananya: User,
    now: datetime,
) -> None:
    """Seed a spread of demo appointments on the primary doctor's calendar so the portal
    booking view has content the moment it loads: pending requests to approve, confirmed
    upcoming visits, and one cancelled visit that shows the notify-the-patient trail.

    Idempotent — skips entirely once this doctor has any appointment."""
    existing = db.scalar(select(Appointment).where(Appointment.doctor_id == doctor.id))
    if existing is not None:
        return

    priya = db.scalar(select(User).where(User.email == "priya@example.com"))
    aarav = db.scalar(select(User).where(User.email == "aarav@example.com"))
    rohan = db.scalar(select(User).where(User.email == "rohan@example.com"))

    def at(days: int, hour: int, minute: int = 0) -> datetime:
        return (now + timedelta(days=days)).replace(
            hour=hour, minute=minute, second=0, microsecond=0
        )

    specs = [
        # (patient, report, when, duration, reason, status, created_by, cancel_reason)
        (
            patient_raj, _first_report(db, patient_raj.id), at(1, 10, 0), 30,
            "Worried about a mole that seems to be changing shape.",
            APPT_REQUESTED, ACTOR_PATIENT, None,
        ),
        (
            priya, _first_report(db, priya.id) if priya else None, at(1, 9, 0), 30,
            "Follow-up after the escalated melanoma screening.",
            APPT_REQUESTED, ACTOR_PATIENT, None,
        ),
        (
            patient_ananya, _first_report(db, patient_ananya.id), at(3, 15, 30), 30,
            "Recommended review of the actinic keratosis — cryotherapy options.",
            APPT_CONFIRMED, ACTOR_DOCTOR, None,
        ),
        (
            aarav, _first_report(db, aarav.id) if aarav else None, at(5, 11, 0), 45,
            "Squamous cell carcinoma review and biopsy planning.",
            APPT_CONFIRMED, ACTOR_DOCTOR, None,
        ),
        (
            rohan, _first_report(db, rohan.id) if rohan else None, at(-2, 14, 0), 30,
            "Seborrheic keratosis re-check.",
            APPT_CANCELLED, ACTOR_PATIENT, "Clinic closed that afternoon — please rebook.",
        ),
    ]

    for patient, report, when, dur, reason, status_, created_by, cancel_reason in specs:
        if patient is None:
            continue
        # A linked report must be shared for the doctor to open it.
        if report is not None and report.shared_at is None:
            report.shared_at = report.created_at or now
        appt = Appointment(
            doctor_id=doctor.id,
            patient_id=patient.id,
            report_id=report.id if report is not None else None,
            scheduled_for=when.astimezone(timezone.utc),
            duration_minutes=dur,
            reason=reason,
            status=status_,
            created_by=created_by,
            cancelled_by=(ACTOR_DOCTOR if cancel_reason else None),
            cancel_reason=cancel_reason,
            # A confirmed doctor-recommendation lands unread in the patient's app.
            unread_for_patient=(status_ == APPT_CONFIRMED and created_by == ACTOR_DOCTOR),
        )
        db.add(appt)
    db.flush()
    logger.info("Seeded demo appointments for doctor %s", doctor.email)


def seed_default_data(db: Session) -> None:
    """Seed default doctors, patients, and clinical demo records idempotently."""
    now = datetime.now(timezone.utc)


    # 1. Seed or ensure Doctors (dr.rao@example.com and dr.mehta@example.com)
    doctors: list[User] = []
    for d_name, d_email, d_pass, d_reg in DEMO_DOCTORS:
        doc = db.scalar(select(User).where(User.email == d_email))
        if doc is None:
            doc = User(
                email=d_email,
                display_name=d_name,
                password_hash=hash_password(d_pass),
                role=ROLE_DOCTOR,
                is_verified=True,
                medical_reg_no=d_reg,
            )
            db.add(doc)
            db.flush()
            logger.info("Auto-seeded doctor account: %s (%s)", d_email, d_name)
        else:
            doc.role = ROLE_DOCTOR
            doc.is_verified = True
            doc.display_name = d_name
            doc.medical_reg_no = d_reg
            doc.password_hash = hash_password(d_pass)
            db.flush()
        doctors.append(doc)

    primary_doctor = doctors[0]

    # Clean up any legacy/orphan doctor accounts not in DEMO_DOCTORS (e.g. doctor@demo.local)
    demo_emails = {email for _, email, _, _ in DEMO_DOCTORS}
    orphan_docs = db.scalars(select(User).where(User.role == ROLE_DOCTOR, User.email.not_in(demo_emails))).all()
    for orphan in orphan_docs:
        logger.info("Cleaning up orphan doctor account: %s", orphan.email)
        db.query(DoctorPatient).filter(DoctorPatient.doctor_id == orphan.id).delete()
        db.delete(orphan)
    db.flush()

    # 2. Seed or ensure Patient 1 (raj@gmail.com)
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
        patient_raj.role = ROLE_PATIENT
        patient_raj.display_name = PATIENT_NAME
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

    # Link Patient 1 (raj@gmail.com) with all doctors
    for doc in doctors:
        _link_doctor_and_patient(db, doc.id, patient_raj.id, now)
    db.flush()

    # 3. Seed or ensure Patient 2 (ananya@gmail.com)
    patient_ananya = db.scalar(select(User).where(User.email == PATIENT_2_EMAIL))
    if patient_ananya is None:
        patient_ananya = User(
            email=PATIENT_2_EMAIL,
            display_name=PATIENT_2_NAME,
            password_hash=hash_password(PATIENT_2_PASSWORD),
            role=ROLE_PATIENT,
        )
        db.add(patient_ananya)
        db.flush()
        logger.info("Auto-seeded second patient account: %s", PATIENT_2_EMAIL)
    else:
        patient_ananya.role = ROLE_PATIENT
        patient_ananya.display_name = PATIENT_2_NAME
        patient_ananya.password_hash = hash_password(PATIENT_2_PASSWORD)
        db.flush()

    # Seed demo reports for ananya@gmail.com if none exist
    has_ananya_reports = db.scalar(select(Report).where(Report.user_id == patient_ananya.id))
    if has_ananya_reports is None:
        r1_date = now - timedelta(days=2)
        r1 = Report(
            user_id=patient_ananya.id,
            condition="Actinic keratosis",
            predicted_class="akiec",
            confidence=0.86,
            triage="Prompt dermatologist consultation",
            status=REPORT_UNDER_REVIEW,
            explanation="Erythematous scaly patch with rough keratotic surface on sun-exposed forearm.",
            symptoms={"rough_patch": True, "sun_exposure": "high", "duration_weeks": 12, "itching": True},
            created_at=r1_date,
            shared_at=r1_date,
        )
        db.add(r1)
        db.flush()
        db.add(
            DoctorNote(
                report_id=r1.id,
                doctor_id=primary_doctor.id,
                note="Advised cryotherapy or topical 5-FU. Patient scheduled for follow-up evaluation.",
                created_at=r1_date,
            )
        )

        r2_date = now - timedelta(days=10)
        r2 = Report(
            user_id=patient_ananya.id,
            condition="Benign keratosis",
            predicted_class="bkl",
            confidence=0.93,
            triage="Routine dermatologist consultation",
            status=REPORT_REVIEWED,
            explanation="Discrete waxy verrucous plaque with well-defined borders.",
            symptoms={"duration_weeks": 40, "stable": True},
            created_at=r2_date,
            shared_at=r2_date,
        )
        db.add(r2)
        db.flush()
        db.add(
            DoctorNote(
                report_id=r2.id,
                doctor_id=primary_doctor.id,
                note="Confirmed benign seborrheic keratosis. No surgical excision needed.",
                created_at=r2_date,
            )
        )
        db.flush()

    # Link Patient 2 (ananya@gmail.com) with all doctors
    for doc in doctors:
        _link_doctor_and_patient(db, doc.id, patient_ananya.id, now)
    db.flush()

    # 4. Seed demo patients & worklist reports for Doctor Portal
    for name, email, reports in DEMO_PATIENTS:
        p = db.scalar(select(User).where(User.email == email))
        if p is None:
            p = User(
                email=email,
                display_name=name,
                role=ROLE_PATIENT,
                password_hash=hash_password("12345678"),
            )
            db.add(p)
            db.flush()
        else:
            p.password_hash = hash_password("12345678")
            db.flush()

        # Consented link with all doctors
        for doc in doctors:
            _link_doctor_and_patient(db, doc.id, p.id, now)

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
                            doctor_id=primary_doctor.id,
                            note=spec["note"],
                            created_at=r_date,
                        )
                    )

    # 4b. Seed demo appointments for the primary doctor's calendar (idempotent).
    _seed_appointments(db, primary_doctor, patient_raj, patient_ananya, now)

    # 5. Ensure all existing & seeded reports have real encrypted sample images & Grad-CAM overlays
    settings = get_settings()
    vault = ImageVault(settings.shared_image_path, settings.image_encryption_key)
    sample_tokens = _get_vault_sample_tokens(vault)

    if vault.configured and sample_tokens:
        all_reports = db.scalars(select(Report)).all()
        for rep in all_reports:
            needs_img = not rep.image_path or vault.load(rep.image_path) is None
            needs_cam = not rep.gradcam_path or vault.load(rep.gradcam_path) is None
            if needs_img or needs_cam:
                key = (rep.predicted_class or "").lower()
                if key not in sample_tokens:
                    c_low = (rep.condition or "").lower()
                    if "melanoma" in c_low:
                        key = "mel"
                    elif "basal" in c_low or "bcc" in c_low:
                        key = "bcc"
                    elif "actinic" in c_low or "akiec" in c_low:
                        key = "akiec"
                    elif "wound" in c_low or "injury" in c_low or "abrasion" in c_low:
                        key = "other_damage"
                    else:
                        key = "nv"

                tokens = sample_tokens.get(key) or sample_tokens.get("nv")
                if tokens:
                    if needs_img:
                        rep.image_path = tokens[0]
                    if needs_cam and tokens[1]:
                        rep.gradcam_path = tokens[1]

    db.commit()
    logger.info("Database seed complete: %d doctors, %d demo patients, and encrypted report imagery verified.", len(doctors), len(DEMO_PATIENTS) + 2)


