"""Request/response models for the appointment booking flow.

Two audiences share these, mirroring `schemas.doctor`:

  * the *patient* books a visit with a chosen doctor (optionally linked to a shared report),
    lists their own appointments, and cancels one;
  * the *doctor* reads and acts on those appointments in the web portal (which renders the
    ORM rows directly, so only the patient-facing shapes need to live here).

Whether a booking is allowed at all is still governed elsewhere — a patient may only book a
verified doctor — these models just validate and shape the payloads.
"""

from __future__ import annotations

from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_validator


class AppointmentCreate(BaseModel):
    """A patient's booking request."""

    doctor_id: int
    # Optional link to one of the patient's shared screenings — the "case" the visit is about.
    report_id: int | None = None
    scheduled_for: datetime
    duration_minutes: int = Field(default=30, ge=10, le=180)
    reason: str = Field(default="", max_length=1000)

    @field_validator("scheduled_for")
    @classmethod
    def _future_and_aware(cls, value: datetime) -> datetime:
        # Normalise to an aware UTC datetime; a naive value is assumed to be UTC.
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        # Reject a slot in the past (small grace so a request in flight at the boundary is ok).
        if value < datetime.now(timezone.utc):
            raise ValueError("scheduled_for must be in the future")
        return value


class AppointmentCancel(BaseModel):
    reason: str = Field(default="", max_length=1000)


class AppointmentOut(BaseModel):
    """One appointment as the patient's app sees it, with the counterpart's name flattened in."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    doctor_id: int
    patient_id: int
    report_id: int | None = None
    scheduled_for: datetime
    duration_minutes: int
    reason: str
    status: str
    created_by: str
    cancelled_by: str | None = None
    cancel_reason: str | None = None
    unread_for_patient: bool = False
    created_at: datetime
    updated_at: datetime

    # Denormalised display fields, filled by the route (not columns on the row).
    doctor_name: str | None = None
    patient_name: str | None = None
    report_condition: str | None = None
