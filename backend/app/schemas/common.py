"""Shared enums and small response models."""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field


class Language(StrEnum):
    """Supported response languages.

    Adding a language means adding a member here and a translation in
    `backend/app/safety/disclaimer.py` and `ml/configs/class_mapping.json`. The disease
    names and the disclaimer are never left to the LLM to translate on the fly.
    """

    ENGLISH = "en"
    HINDI = "hi"


class TriageCategory(StrEnum):
    """The three controlled urgency categories.

    Set exclusively by the deterministic rules in `services/triage.py`. The LLM receives
    the resulting category and explains it; it never chooses one.
    """

    ROUTINE = "routine_consultation"
    PROMPT = "prompt_consultation"
    URGENT = "urgent_evaluation"

    @property
    def severity(self) -> int:
        return {"routine_consultation": 0, "prompt_consultation": 1, "urgent_evaluation": 2}[
            self.value
        ]


class Outcome(StrEnum):
    """What the front-stage router decided the photo IS.

    Only these three reach a 200 response. `LESION` runs the full disease pipeline
    (class + triage + Grad-CAM). `HEALTHY` and `OTHER_DAMAGE` short-circuit it with fixed,
    application-owned guidance. A fourth router category, `not_skin`, never becomes an
    outcome -- it is rejected as `no_lesion_detected` like any non-skin photo.
    """

    LESION = "lesion"
    HEALTHY = "healthy"
    OTHER_DAMAGE = "other_damage"


class HealthResponse(BaseModel):
    status: str = Field(examples=["ok"])
    version: str
    model_loaded: bool
    model_arch: str | None = None
    class_mapping_version: str | None = None
    num_classes: int | None = None
    llm_available: bool
    device: str | None = None
    stub_mode: bool = False
    ood_available: bool = False
    lesion_gate_available: bool = False
    lesion_router_available: bool = False


class ErrorResponse(BaseModel):
    """Uniform error shape.

    `message` is safe to display to a user. Internal detail, filesystem paths and stack
    traces never reach the client (master spec, section 22).
    """

    error: str = Field(description="Stable machine-readable code, e.g. `image_quality_insufficient`.")
    message: str = Field(description="User-facing text, safe to display verbatim.")
    detail: str | None = Field(default=None, description="Optional non-sensitive extra context.")
