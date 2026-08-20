"""Request/response models for saved screening reports."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class ReportCreate(BaseModel):
    condition: str = Field(max_length=120)
    predicted_class: str | None = Field(default=None, max_length=120)
    confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    triage: str = Field(max_length=120)
    explanation: str = ""
    symptoms: dict[str, Any] = Field(default_factory=dict)


class ReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    condition: str
    predicted_class: str | None = None
    confidence: float | None = None
    triage: str
    explanation: str
    symptoms: dict[str, Any]
    created_at: datetime
