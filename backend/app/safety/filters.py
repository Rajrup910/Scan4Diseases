"""Post-generation safety filter for LLM output.

The system prompt tells the model what not to say. This module checks whether it complied,
because a prompt is a request and not a guarantee. Master specification, section 23: the
LLM must not give a definitive diagnosis, recommend prescription medication, claim to have
examined the patient, or convert a confidence score into a medical probability.

Two severities:

    BLOCK    the whole response is discarded and replaced with a safe fallback
    REDACT   the offending sentence is removed and the rest is kept

Regexes are blunt instruments and will occasionally fire on harmless text. That trade is
deliberate: in a medical screening tool, an over-cautious filter costs a little fluency,
while an under-cautious one lets the system tell a user to take a drug.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import StrEnum

from backend.app.schemas.common import Language


class Severity(StrEnum):
    BLOCK = "block"
    REDACT = "redact"


@dataclass(frozen=True)
class Rule:
    id: str
    pattern: re.Pattern[str]
    severity: Severity
    description: str


def _compile(pattern: str) -> re.Pattern[str]:
    return re.compile(pattern, re.IGNORECASE)


RULES: tuple[Rule, ...] = (
    # --- prescription / treatment instructions ---
    Rule(
        id="prescription_verb",
        pattern=_compile(
            r"\b(take|apply|use|start|stop|increase|decrease|discontinue)\b[^.!?\n]{0,60}"
            r"\b(mg|ml|tablet|capsule|ointment|cream|antibiotic|steroid|chemotherapy|"
            r"immunotherapy|prescription|medication|medicine|dose|dosage)\b"
        ),
        severity=Severity.REDACT,
        description="Instruction to start, stop or change medication.",
    ),
    Rule(
        id="named_drug",
        pattern=_compile(
            r"\b(imiquimod|fluorouracil|5-fu|isotretinoin|methotrexate|prednisolone|"
            r"prednisone|hydrocortisone|betamethasone|clobetasol|pembrolizumab|nivolumab|"
            r"vemurafenib|dabrafenib|interferon)\b"
        ),
        severity=Severity.REDACT,
        description="Names a specific drug.",
    ),
    Rule(
        id="home_remedy",
        pattern=_compile(
            r"\b(remove|cut|burn|freeze|scrape|excise)\b[^.!?\n]{0,40}\b(it|the lesion|the mole)\b"
            r"|\bat home\b[^.!?\n]{0,40}\b(remove|treat)\b"
        ),
        severity=Severity.REDACT,
        description="Suggests self-treatment or lesion removal at home.",
    ),
    # --- definitive diagnosis ---
    Rule(
        id="definitive_diagnosis",
        pattern=_compile(
            r"\b(you (definitely|certainly|clearly) have|this is (definitely|certainly) "
            r"(cancer|melanoma)|i (can )?diagnose|the diagnosis is|you are diagnosed with)\b"
        ),
        severity=Severity.BLOCK,
        description="States a definitive diagnosis.",
    ),
    Rule(
        id="false_reassurance",
        pattern=_compile(
            r"\b(you (do not|don't) have (cancer|melanoma)|this is (definitely|certainly) "
            r"(not cancer|benign|harmless)|there is nothing to worry about|no need to see a doctor|"
            r"you (do not|don't) need to see a (doctor|dermatologist))\b"
        ),
        severity=Severity.BLOCK,
        description="Rules out disease or discourages seeking care.",
    ),
    # --- confidence misuse ---
    Rule(
        id="confidence_as_probability",
        pattern=_compile(
            r"\b(\d{1,3}\s?%|\d\.\d+)\s*(chance|probability|likelihood|risk)\s*(that\s*)?(you|of you)\b"
            r"|\bthere is an? \d{1,3}\s?% (chance|probability|risk) (that )?you\b"
        ),
        severity=Severity.BLOCK,
        description="Converts model confidence into a personal disease probability.",
    ),
    # --- fabricated clinical activity ---
    Rule(
        id="claims_examination",
        pattern=_compile(
            r"\b(i (have )?(examined|inspected|looked at) (you|your (skin|body))|"
            r"(during|at) (your|the) (examination|consultation|appointment)|"
            r"(your|the) (biopsy|blood test|lab) results? (show|indicate|confirm))\b"
        ),
        severity=Severity.BLOCK,
        description="Claims to have examined the patient or seen test results.",
    ),
    Rule(
        id="overrides_triage",
        pattern=_compile(
            r"\b(ignore|disregard|do not follow) (the|this) (recommendation|advice|guidance|urgency)\b"
            r"|\bthis is (not urgent|less urgent than|more urgent than) (stated|indicated|shown)\b"
        ),
        severity=Severity.BLOCK,
        description="Contradicts the deterministic triage category.",
    ),
)

FALLBACK: dict[Language, str] = {
    Language.ENGLISH: (
        "A written explanation could not be provided safely for this result.\n\n"
        "Please rely on the classification, the guidance shown above, and the advice of a "
        "qualified dermatologist. A professional examination can assess this lesion in ways "
        "a photograph cannot."
    ),
    Language.HINDI: (
        "इस परिणाम के लिए सुरक्षित रूप से लिखित व्याख्या उपलब्ध नहीं कराई जा सकी।\n\n"
        "कृपया वर्गीकरण, ऊपर दिए गए मार्गदर्शन और किसी योग्य त्वचा रोग विशेषज्ञ की सलाह पर भरोसा करें। "
        "पेशेवर जाँच इस घाव का ऐसा आकलन कर सकती है जो तस्वीर से संभव नहीं है।"
    ),
}

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?।])\s+")


@dataclass
class FilterResult:
    text: str
    filtered: bool = False
    blocked: bool = False
    reasons: list[str] = field(default_factory=list)
    rule_ids: list[str] = field(default_factory=list)


def filter_llm_output(text: str, language: Language = Language.ENGLISH) -> FilterResult:
    """Check generated text against the safety rules.

    A BLOCK rule anywhere replaces the entire response -- if the model asserted a
    diagnosis, the surrounding text was written under the same false premise and is not
    worth salvaging. A REDACT rule removes only the offending sentence.
    """
    if not text or not text.strip():
        return FilterResult(text=FALLBACK[language], filtered=True, blocked=True, reasons=["empty response"], rule_ids=["empty"])

    for rule in RULES:
        if rule.severity is Severity.BLOCK and rule.pattern.search(text):
            return FilterResult(
                text=FALLBACK.get(language, FALLBACK[Language.ENGLISH]),
                filtered=True,
                blocked=True,
                reasons=[rule.description],
                rule_ids=[rule.id],
            )

    kept: list[str] = []
    reasons: list[str] = []
    rule_ids: list[str] = []

    for sentence in _SENTENCE_SPLIT.split(text):
        offending = next(
            (r for r in RULES if r.severity is Severity.REDACT and r.pattern.search(sentence)),
            None,
        )
        if offending is None:
            kept.append(sentence)
        elif offending.id not in rule_ids:
            reasons.append(offending.description)
            rule_ids.append(offending.id)

    if not rule_ids:
        return FilterResult(text=text)

    remaining = " ".join(kept).strip()
    if len(remaining) < 40:
        # Almost everything was redacted; what is left would read as gibberish.
        return FilterResult(
            text=FALLBACK.get(language, FALLBACK[Language.ENGLISH]),
            filtered=True,
            blocked=True,
            reasons=reasons + ["too little text remained after redaction"],
            rule_ids=rule_ids,
        )

    return FilterResult(text=remaining, filtered=True, reasons=reasons, rule_ids=rule_ids)
