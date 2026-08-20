"""Application-level medical safety guardrails.

Nothing in this package calls the LLM, and nothing in it can be overridden by LLM output.
"""

from backend.app.safety.disclaimer import (
    DISCLAIMERS,
    confidence_phrasing,
    get_disclaimer,
    triage_advice,
    triage_label,
)
from backend.app.safety.filters import FilterResult, filter_llm_output

__all__ = [
    "DISCLAIMERS",
    "FilterResult",
    "confidence_phrasing",
    "filter_llm_output",
    "get_disclaimer",
    "triage_advice",
    "triage_label",
]
