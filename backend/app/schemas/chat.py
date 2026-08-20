"""Request/response schemas for POST /chat."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from backend.app.schemas.common import Language
from backend.app.schemas.questionnaire import Questionnaire


class ChatMessage(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(min_length=1, max_length=4000)


class PredictionContext(BaseModel):
    """The prediction the conversation is about.

    The client echoes this back from the /predict response rather than the server holding
    session state. That keeps the backend stateless and means no scan result is retained
    server-side once the request finishes -- a privacy property worth stating in the report.
    """

    model_config = ConfigDict(protected_namespaces=())

    predicted_class: str
    confidence: float = Field(ge=0.0, le=1.0)
    triage_category: str
    low_confidence: bool = False
    gradcam_focus: str | None = None


class ChatRequest(BaseModel):
    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "message": "What does this result mean?",
                "language": "en",
                "prediction": {
                    "predicted_class": "bcc",
                    "confidence": 0.81,
                    "triage_category": "urgent_evaluation",
                    "low_confidence": False,
                },
                "questionnaire": {"bleeding": True, "duration": "3_to_12_months"},
                "history": [],
            }
        }
    )

    message: str = Field(min_length=1, max_length=2000)
    language: Language = Language.ENGLISH
    prediction: PredictionContext | None = None
    questionnaire: Questionnaire | None = None
    history: list[ChatMessage] = Field(
        default_factory=list,
        max_length=20,
        description="Prior turns, oldest first. Truncated server-side if longer.",
    )


class ChatResponse(BaseModel):
    response: str
    language: Language
    disclaimer: str
    filtered: bool = Field(
        default=False,
        description="True if the safety filter modified or replaced the model's output.",
    )
    filter_reasons: list[str] = Field(default_factory=list)
