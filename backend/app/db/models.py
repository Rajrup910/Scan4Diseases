"""ORM models: users, the screening reports they save, and the doctor-portal
authorisation tables (doctor accounts, patient-granted access, notes, audit log).

Privacy stance for the *patient* flow is unchanged: `/predict` still never writes the
lesion image to disk. An image is only ever persisted when a patient explicitly shares a
specific report with a doctor -- at that point `Report.image_path` / `gradcam_path` are
set to encrypted-blob references and `shared_at` is stamped. Nothing here weakens the
default: an unshared report stores only metadata, exactly as before.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import JSON

from backend.app.db.session import Base

# --- controlled vocabularies (validated at the app layer; stored as plain strings so
#     SQLite stays simple and values remain human-readable in the file) ---

ROLE_PATIENT = "patient"
ROLE_DOCTOR = "doctor"
ROLE_ADMIN = "admin"
ROLES = frozenset({ROLE_PATIENT, ROLE_DOCTOR, ROLE_ADMIN})

# Patient-granted access link between a doctor and a patient.
LINK_PENDING = "pending"  # doctor requested, patient has not yet consented
LINK_ACTIVE = "active"  # patient has consented; access is live
LINK_REVOKED = "revoked"  # patient withdrew access
LINK_STATUSES = frozenset({LINK_PENDING, LINK_ACTIVE, LINK_REVOKED})

# Where a shared report sits in a doctor's review workflow.
REPORT_NEW = "new"
REPORT_UNDER_REVIEW = "under_review"
REPORT_REVIEWED = "reviewed"
REPORT_ESCALATED = "escalated"
REPORT_STATUSES = frozenset(
    {REPORT_NEW, REPORT_UNDER_REVIEW, REPORT_REVIEWED, REPORT_ESCALATED}
)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)

    # --- role-based access (doctor portal) ---
    # Everyone is a patient unless promoted. Doctors are created by an admin/seed script,
    # never by self-registration, and must be verified before they can sign into the
    # portal. `medical_reg_no` records the council registration for a real verification
    # flow later; it is informational for now.
    role: Mapped[str] = mapped_column(
        String(20), default=ROLE_PATIENT, server_default=ROLE_PATIENT, nullable=False
    )
    is_verified: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="0", nullable=False
    )
    medical_reg_no: Mapped[str | None] = mapped_column(String(64), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    reports: Mapped[list["Report"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    condition: Mapped[str] = mapped_column(String(120), nullable=False)
    predicted_class: Mapped[str | None] = mapped_column(String(120), nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    triage: Mapped[str] = mapped_column(String(120), nullable=False)
    explanation: Mapped[str] = mapped_column(Text, nullable=False, default="")
    # The structured questionnaire, stored verbatim as JSON.
    symptoms: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)

    # --- doctor-review fields ---
    # `status` is the doctor's workflow state. `image_path` / `gradcam_path` are set ONLY
    # when the patient shares this report; they hold encrypted-blob references, never raw
    # paths served statically. `shared_at` records when (and therefore whether) the report
    # was shared -- a doctor may only view a report whose `shared_at` is set.
    status: Mapped[str] = mapped_column(
        String(20), default=REPORT_NEW, server_default=REPORT_NEW, nullable=False
    )
    image_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    gradcam_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    shared_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )

    user: Mapped["User"] = relationship(back_populates="reports")
    notes: Mapped[list["DoctorNote"]] = relationship(
        back_populates="report",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class DoctorPatient(Base):
    """A patient-granted access link between one doctor and one patient.

    Assignment and consent are the same act here: the patient chooses who may see their
    data, so a live link (`status == active`, `consented_at` set) is created by the
    patient's own action and can be revoked by them at any time. No admin assigns
    patients to doctors, and no doctor can create an active link unilaterally.
    """

    __tablename__ = "doctor_patient"
    __table_args__ = (
        UniqueConstraint("doctor_id", "patient_id", name="uq_doctor_patient"),
        Index("ix_doctor_patient_doctor", "doctor_id"),
        Index("ix_doctor_patient_patient", "patient_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    patient_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    status: Mapped[str] = mapped_column(
        String(20), default=LINK_PENDING, server_default=LINK_PENDING, nullable=False
    )
    # Set when the patient consents; NULL means access is not yet (or no longer) granted.
    consented_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )


class DoctorNote(Base):
    """A note a doctor records against a shared report. Never shown as a diagnosis to the
    patient by the model layer; this is the clinician's own working record."""

    __tablename__ = "doctor_notes"
    __table_args__ = (Index("ix_doctor_notes_report", "report_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    report_id: Mapped[int] = mapped_column(
        ForeignKey("reports.id", ondelete="CASCADE"), nullable=False
    )
    doctor_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    note: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    report: Mapped["Report"] = relationship(back_populates="notes")


class AuditLog(Base):
    """Append-only record of security-relevant actions -- who did what, to which object,
    from where. Every doctor access to patient data must write a row here. Wiring the
    writes into the routes happens in a later phase; the table exists from the start so
    that wiring never requires another migration."""

    __tablename__ = "audit_log"
    __table_args__ = (Index("ix_audit_actor_time", "actor_id", "created_at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    # Nullable so a failed/anonymous action (e.g. a rejected login) can still be recorded.
    actor_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    target_type: Mapped[str | None] = mapped_column(String(40), nullable=True)
    target_id: Mapped[int | None] = mapped_column(nullable=True)
    ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )
