"""Deterministic safety / triage layer.

**This module, and only this module, decides medical urgency.**

Master specification, section 25: the LLM must not freely determine urgency. It receives
the category computed here and explains it. That separation is what makes the system
auditable -- every category this file produces can be traced to a numbered rule, and the
rules are unit-tested.

Design principles:

1. **Escalation only.** Rules can raise the urgency, never lower it. Nothing a user
   answers can talk the system down from a malignant classification.
2. **Missing means unknown, not "no".** An unanswered question contributes nothing. It
   never counts as a reassuring answer.
3. **Look past the top-1 prediction.** If the top class is benign but the summed
   probability across malignant classes is meaningful, escalate anyway. A 45% `nv` /
   38% `mel` prediction is not a benign result, and top-1 alone would treat it as one.
4. **Low confidence escalates.** An uncertain benign answer is not a reassuring answer.

The thresholds below are conservative by intent. In a screening tool a false alarm costs
an unnecessary consultation; a missed melanoma costs considerably more.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from backend.app.safety.disclaimer import triage_advice, triage_label
from backend.app.schemas.common import Language, TriageCategory
from backend.app.schemas.prediction import TriageResult
from backend.app.schemas.questionnaire import Duration, Questionnaire, SizeChange

# Summed probability across malignant classes (mel, bcc) that forces escalation even when
# the top-1 prediction is something else.
MALIGNANT_MASS_PROMPT = 0.20
MALIGNANT_MASS_URGENT = 0.40

# Pre-malignant mass is tracked separately and can only reach PROMPT. Folding akiec into
# the malignant mass would make a *confident* akiec prediction urgent, which contradicts
# rule R2 -- actinic keratosis is a "see someone soon", not an emergency.
PREMALIGNANT_MASS_PROMPT = 0.20

# How many symptom red flags push a benign, confident result upward.
RED_FLAGS_FOR_PROMPT = 1
RED_FLAGS_FOR_URGENT = 3


@dataclass
class TriageDecision:
    category: TriageCategory
    reasons: list[str] = field(default_factory=list)
    rule_ids: list[str] = field(default_factory=list)
    low_confidence: bool = False
    red_flags: list[str] = field(default_factory=list)

    def escalate_to(self, category: TriageCategory, rule_id: str, reason: str) -> None:
        """Raise the category if the rule demands more urgency than we already have."""
        if category.severity > self.category.severity:
            self.category = category
        # Record the rule even when it did not change the category -- the reason is still
        # true and the user deserves to see why the system is concerned.
        if rule_id not in self.rule_ids:
            self.rule_ids.append(rule_id)
            self.reasons.append(reason)


def collect_red_flags(questionnaire: Questionnaire | None) -> list[tuple[str, str]]:
    """Symptom answers that raise concern. Returns (rule_id, plain-language reason).

    These are conservative escalation signals, not validated diagnostic criteria, and the
    UI must not present them as such.
    """
    if questionnaire is None:
        return []

    flags: list[tuple[str, str]] = []

    if questionnaire.bleeding is True:
        flags.append(("flag_bleeding", "You reported that the lesion has bled on its own."))
    if questionnaire.size_change is SizeChange.GROWING:
        flags.append(("flag_growing", "You reported that the lesion is growing."))
    if questionnaire.color_change is True:
        flags.append(("flag_colour", "You reported a change in the lesion's colour."))
    if questionnaire.recent_change is True:
        flags.append(("flag_recent_change", "You reported a recent change in the lesion."))
    if questionnaire.pain is True:
        flags.append(("flag_pain", "You reported that the lesion is painful or tender."))

    # A lesion that has persisted for over a year *and* is still changing is a different
    # signal from one that has simply been there a long time.
    if questionnaire.duration is Duration.MORE_THAN_1_YEAR and questionnaire.recent_change is True:
        flags.append(
            (
                "flag_longstanding_change",
                "You reported a long-standing lesion that has recently changed.",
            )
        )

    return flags


def probability_mass(
    probabilities: dict[str, float], malignancy_by_code: dict[str, str], tiers: set[str]
) -> float:
    """Total probability assigned to classes in the given malignancy tiers."""
    return sum(
        probability
        for code, probability in probabilities.items()
        if malignancy_by_code.get(code) in tiers
    )


def malignant_probability_mass(
    probabilities: dict[str, float], malignancy_by_code: dict[str, str]
) -> float:
    """Probability assigned to the cancerous classes only."""
    return probability_mass(probabilities, malignancy_by_code, {"malignant"})


def assess(
    predicted_code: str,
    confidence: float,
    probabilities: dict[str, float],
    malignancy_by_code: dict[str, str],
    questionnaire: Questionnaire | None,
    low_confidence_threshold: float,
) -> TriageDecision:
    """Apply the rules. Pure function -- no I/O, no model, no LLM, fully testable."""
    predicted_malignancy = malignancy_by_code.get(predicted_code, "benign")
    red_flags = collect_red_flags(questionnaire)
    is_low_confidence = confidence < low_confidence_threshold

    decision = TriageDecision(
        category=TriageCategory.ROUTINE,
        low_confidence=is_low_confidence,
        red_flags=[flag_id for flag_id, _ in red_flags],
    )

    # --- Rule 1: the classifier's own verdict ---
    if predicted_malignancy == "malignant":
        decision.escalate_to(
            TriageCategory.URGENT,
            "R1_malignant_class",
            "The screening model's leading category is one that can be cancerous.",
        )
    elif predicted_malignancy == "premalignant":
        decision.escalate_to(
            TriageCategory.PROMPT,
            "R2_premalignant_class",
            "The screening model's leading category is one that can develop into cancer "
            "if untreated.",
        )

    # --- Rules 3/4: probability mass beyond the top-1 prediction ---
    # Catches the case top-1 hides: 45% nv / 42% mel is not a benign result, but argmax
    # alone reports it as one.
    malignant_mass = probability_mass(probabilities, malignancy_by_code, {"malignant"})
    if malignant_mass >= MALIGNANT_MASS_URGENT:
        decision.escalate_to(
            TriageCategory.URGENT,
            "R3_malignant_mass_high",
            "A substantial part of the model's output pointed toward categories that can "
            "be cancerous.",
        )
    elif malignant_mass >= MALIGNANT_MASS_PROMPT:
        decision.escalate_to(
            TriageCategory.PROMPT,
            "R4_malignant_mass_moderate",
            "Part of the model's output pointed toward categories that can be cancerous.",
        )

    premalignant_mass = probability_mass(probabilities, malignancy_by_code, {"premalignant"})
    if premalignant_mass >= PREMALIGNANT_MASS_PROMPT:
        decision.escalate_to(
            TriageCategory.PROMPT,
            "R4b_premalignant_mass",
            "Part of the model's output pointed toward a category that can develop into "
            "cancer if left untreated.",
        )

    # --- Rule 5: low confidence never rests at routine ---
    if is_low_confidence:
        decision.escalate_to(
            TriageCategory.PROMPT,
            "R5_low_confidence",
            "The model was not confident about this image, so this result should be "
            "checked by a professional rather than relied upon.",
        )

    # --- Rule 6/7: symptom red flags ---
    if len(red_flags) >= RED_FLAGS_FOR_URGENT:
        decision.escalate_to(
            TriageCategory.URGENT,
            "R6_multiple_red_flags",
            f"You reported {len(red_flags)} symptoms that warrant prompt attention.",
        )
    elif len(red_flags) >= RED_FLAGS_FOR_PROMPT:
        decision.escalate_to(
            TriageCategory.PROMPT,
            "R7_red_flag",
            "You reported at least one symptom that warrants professional attention.",
        )

    # --- Rule 8: bleeding is escalating on its own ---
    if questionnaire is not None and questionnaire.bleeding is True:
        decision.escalate_to(
            TriageCategory.URGENT,
            "R8_bleeding",
            "A lesion that bleeds without being injured should be examined promptly.",
        )

    # Attach the individual flag reasons so the user sees the specifics, not just a count.
    for flag_id, reason in red_flags:
        if flag_id not in decision.rule_ids:
            decision.rule_ids.append(flag_id)
            decision.reasons.append(reason)

    # --- Rule 9: never return routine with nothing to say ---
    if decision.category is TriageCategory.ROUTINE and not decision.rule_ids:
        decision.rule_ids.append("R9_default_routine")
        decision.reasons.append(
            "Nothing in the image analysis or your answers indicated urgency. This is a "
            "screening result only, not a clearance."
        )

    return decision


def build_triage_result(
    decision: TriageDecision, language: Language = Language.ENGLISH
) -> TriageResult:
    """Turn a decision into the API response object, with fixed localised text."""
    return TriageResult(
        category=decision.category,
        label=triage_label(decision.category, language),
        advice=triage_advice(decision.category, language),
        reasons=decision.reasons,
        rule_ids=decision.rule_ids,
        low_confidence=decision.low_confidence,
    )
