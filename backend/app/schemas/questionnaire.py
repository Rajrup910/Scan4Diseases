"""The structured symptom questionnaire.

Deliberately short. Every field feeds the deterministic triage rules in
`services/triage.py`; nothing is collected "just in case". No name, phone number,
address or identifier is requested anywhere (master spec, section 29).

These answers are **not** validated diagnostic criteria. They are conservative
escalation signals: they can raise the urgency category, never lower it below what the
classifier alone would produce.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field


class Duration(StrEnum):
    LESS_THAN_1_MONTH = "less_than_1_month"
    ONE_TO_THREE_MONTHS = "1_to_3_months"
    THREE_TO_TWELVE_MONTHS = "3_to_12_months"
    MORE_THAN_1_YEAR = "more_than_1_year"
    UNKNOWN = "unknown"


class SizeChange(StrEnum):
    GROWING = "growing"
    STABLE = "stable"
    SHRINKING = "shrinking"
    UNKNOWN = "unknown"


class Questionnaire(BaseModel):
    """Answers to the symptom questions. Every field is optional.

    A user who skips the questionnaire still gets a result -- the triage layer simply has
    fewer escalation signals and falls back to the classifier output alone. Missing
    answers are treated as "not reported", never as "no".
    """

    model_config = ConfigDict(
        extra="forbid",
        json_schema_extra={
            "example": {
                "duration": "3_to_12_months",
                "recent_change": True,
                "itching": False,
                "pain": True,
                "bleeding": False,
                "size_change": "growing",
                "color_change": True,
                "family_history": False,
                "sun_exposure": "high",
            }
        },
    )

    duration: Duration | None = Field(default=None, description="How long the lesion has been present.")
    recent_change: bool | None = Field(default=None, description="Has it changed noticeably in recent weeks?")
    itching: bool | None = None
    pain: bool | None = Field(default=None, description="Is it painful or tender?")
    bleeding: bool | None = Field(default=None, description="Has it bled without being knocked or scratched?")
    size_change: SizeChange | None = None
    color_change: bool | None = Field(default=None, description="Has its colour changed or become uneven?")
    family_history: bool | None = Field(default=None, description="Family history of skin cancer.")
    sun_exposure: str | None = Field(
        default=None,
        description="Self-reported lifetime sun exposure: low | moderate | high | unknown.",
    )

    def answered_count(self) -> int:
        return sum(1 for value in self.model_dump().values() if value is not None)

    def summary_for_llm(self) -> dict[str, object]:
        """Only the answered fields, so the LLM cannot mistake a null for a 'no'.

        This matters: an LLM shown `"bleeding": null` will sometimes write "you reported
        no bleeding", which is a fabricated symptom claim.
        """
        return {key: value for key, value in self.model_dump(mode="json").items() if value is not None}
