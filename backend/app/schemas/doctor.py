"""Request/response models for the doctor portal and the patient-side sharing controls.

Two audiences share this module:

  * the *patient* grants/revokes a doctor's access and shares/unshares individual reports
    (`ConsentOut`, and the plain report routes reuse `schemas.report`);
  * the *doctor* lists the patients who have shared with them and reads those patients'
    shared reports (`PatientSummary`, `DoctorReportSummary`, `DoctorReportDetail`).

Nothing here decides *whether* a doctor may see a report -- that single rule lives in
`services.access`. These models only shape the data once access has been granted.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field, computed_field, field_validator

from backend.app.db.models import REPORT_STATUSES

# --- patient side: consent links ----------------------------------------------------

class ConsentOut(BaseModel):
    """A doctor<->patient access link as the patient sees it."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    doctor_id: int
    patient_id: int
    status: str
    consented_at: datetime | None = None
    created_at: datetime


class SharedImageOut(BaseModel):
    """Result of a patient uploading (encrypted) image(s) for one of their reports."""

    model_config = ConfigDict(from_attributes=True)

    report_id: int
    shared_at: datetime | None = None
    has_image: bool = False
    has_gradcam: bool = False


class DoctorDirectoryEntry(BaseModel):
    """A verified doctor as a patient sees them when choosing who to share a report with.

    This is the professional directory the patient picks from -- name and registration
    number identify the clinician; no patient data and nothing account-sensitive is exposed.
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    display_name: str | None = None
    # Plain str, not EmailStr: emails are validated at registration, and the seeded demo
    # doctor uses a `.local` address that EmailStr rejects on output (would 500 the list).
    email: str
    medical_reg_no: str | None = None


# --- doctor side: patients and their shared reports ---------------------------------

class PatientSummary(BaseModel):
    """One patient who has an active, consented link with the requesting doctor."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    display_name: str | None = None
    # How many of this patient's reports are currently shared with the doctor. Lets the
    # portal show a count without a second request; 0 means consented but nothing shared.
    shared_report_count: int = 0


class DoctorNoteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    report_id: int
    doctor_id: int
    note: str
    created_at: datetime


class DoctorReportSummary(BaseModel):
    """A shared report in a list -- enough for the doctor's worklist, without notes."""

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)

    id: int
    # On the ORM row the patient is `Report.user_id`; expose it under the name the doctor
    # actually uses. The alias lets `model_validate(report)` read it straight off the row.
    patient_id: int = Field(validation_alias="user_id")
    condition: str
    predicted_class: str | None = None
    confidence: float | None = None
    triage: str
    status: str
    shared_at: datetime | None = None
    created_at: datetime

    # Read off the ORM row but never serialized: the encrypted-blob filenames are internal
    # references, not something a client should ever see. They back the `has_*` flags below,
    # which is all the portal needs to decide whether to render an image link.
    image_path: str | None = Field(default=None, exclude=True)
    gradcam_path: str | None = Field(default=None, exclude=True)

    @computed_field
    @property
    def has_image(self) -> bool:
        return self.image_path is not None

    @computed_field
    @property
    def has_gradcam(self) -> bool:
        return self.gradcam_path is not None


class DoctorReportDetail(DoctorReportSummary):
    """A single shared report with its full body and the doctor's notes."""

    explanation: str = ""
    symptoms: dict[str, Any] = Field(default_factory=dict)
    notes: list[DoctorNoteOut] = Field(default_factory=list)


# --- doctor side: mutations ---------------------------------------------------------

class StatusUpdate(BaseModel):
    status: str

    @field_validator("status")
    @classmethod
    def _known_status(cls, value: str) -> str:
        if value not in REPORT_STATUSES:
            raise ValueError(f"status must be one of {sorted(REPORT_STATUSES)}")
        return value


class NoteCreate(BaseModel):
    note: str = Field(min_length=1, max_length=5000)
