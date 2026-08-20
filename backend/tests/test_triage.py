"""Tests for the deterministic triage layer.

This is the most important test file in the project. The triage rules are what let the
report claim that medical urgency is auditable and reproducible rather than generated, and
that claim is only worth making if the rules are actually pinned down by tests.

Every test states the clinical intent, not just the expected value.
"""

from __future__ import annotations

import pytest

from backend.app.schemas.common import Language, TriageCategory
from backend.app.schemas.questionnaire import Duration, Questionnaire, SizeChange
from backend.app.services.triage import (
    MALIGNANT_MASS_PROMPT,
    MALIGNANT_MASS_URGENT,
    PREMALIGNANT_MASS_PROMPT,
    assess,
    build_triage_result,
    collect_red_flags,
)

MALIGNANCY = {
    "akiec": "premalignant",
    "bcc": "malignant",
    "bkl": "benign",
    "df": "benign",
    "mel": "malignant",
    "nv": "benign",
    "vasc": "benign",
}

THRESHOLD = 0.60


def probabilities(**overrides: float) -> dict[str, float]:
    """Build a probability dict that sums to 1, defaulting the remainder to `nv`."""
    base = dict.fromkeys(MALIGNANCY, 0.0)
    base.update(overrides)
    remainder = 1.0 - sum(base.values())
    base["nv"] = base.get("nv", 0.0) + max(remainder, 0.0)
    return base


def decide(code: str, confidence: float, questionnaire: Questionnaire | None = None, **probs: float):
    return assess(
        predicted_code=code,
        confidence=confidence,
        probabilities=probabilities(**probs) if probs else probabilities(**{code: confidence}),
        malignancy_by_code=MALIGNANCY,
        questionnaire=questionnaire,
        low_confidence_threshold=THRESHOLD,
    )


# --- classifier-driven rules -------------------------------------------------------


def test_confident_benign_is_routine():
    """A confident mole with no reported symptoms is the only path to routine."""
    decision = decide("nv", 0.92)
    assert decision.category is TriageCategory.ROUTINE
    assert decision.low_confidence is False


def test_malignant_class_is_always_urgent():
    """A malignant leading class escalates unconditionally, however confident."""
    for code in ("mel", "bcc"):
        decision = decide(code, 0.95)
        assert decision.category is TriageCategory.URGENT, code
        assert "R1_malignant_class" in decision.rule_ids


def test_premalignant_is_at_least_prompt():
    decision = decide("akiec", 0.88)
    assert decision.category is TriageCategory.PROMPT
    assert "R2_premalignant_class" in decision.rule_ids


def test_low_confidence_never_stays_routine():
    """An uncertain benign answer is not a reassuring answer."""
    decision = decide("nv", 0.35)
    assert decision.category is TriageCategory.PROMPT
    assert decision.low_confidence is True
    assert "R5_low_confidence" in decision.rule_ids


def test_threshold_boundary_is_exclusive():
    """Exactly at the threshold counts as confident; just below does not."""
    assert decide("nv", THRESHOLD).low_confidence is False
    assert decide("nv", THRESHOLD - 0.001).low_confidence is True


# --- probability-mass rules --------------------------------------------------------


def test_benign_top1_with_high_malignant_mass_is_urgent():
    """The failure mode top-1 hides.

    45% nv / 42% mel is not a benign result, but argmax alone would report it as one.
    """
    decision = decide("nv", 0.45, None, nv=0.45, mel=0.42, bkl=0.13)
    assert decision.category is TriageCategory.URGENT
    assert "R3_malignant_mass_high" in decision.rule_ids


def test_benign_top1_with_moderate_malignant_mass_is_prompt():
    decision = decide("nv", 0.70, None, nv=0.70, mel=0.15, bcc=0.10, bkl=0.05)
    assert decision.category is TriageCategory.PROMPT
    assert "R4_malignant_mass_moderate" in decision.rule_ids


def test_malignant_mass_thresholds_are_ordered():
    assert MALIGNANT_MASS_PROMPT < MALIGNANT_MASS_URGENT


def test_premalignant_mass_escalates_only_to_prompt():
    """akiec mass raises concern, but never to urgent on its own.

    Folding it into the malignant mass would make a *confident* akiec prediction urgent,
    contradicting R2. Actinic keratosis is a "see someone soon", not an emergency.
    """
    decision = decide("nv", 0.72, None, nv=0.72, akiec=0.25, bkl=0.03)
    assert decision.category is TriageCategory.PROMPT
    assert "R4b_premalignant_mass" in decision.rule_ids

    confident = decide("akiec", 0.99)
    assert confident.category is TriageCategory.PROMPT


def test_premalignant_mass_threshold_is_defined():
    assert 0.0 < PREMALIGNANT_MASS_PROMPT <= 1.0


# --- symptom rules -----------------------------------------------------------------


def test_bleeding_alone_is_urgent():
    """A lesion that bleeds unprovoked warrants urgency regardless of the class."""
    decision = decide("nv", 0.95, Questionnaire(bleeding=True))
    assert decision.category is TriageCategory.URGENT
    assert "R8_bleeding" in decision.rule_ids


def test_single_red_flag_is_prompt():
    decision = decide("nv", 0.95, Questionnaire(color_change=True))
    assert decision.category is TriageCategory.PROMPT
    assert "R7_red_flag" in decision.rule_ids


def test_three_red_flags_are_urgent():
    decision = decide(
        "nv", 0.95, Questionnaire(color_change=True, size_change=SizeChange.GROWING, pain=True)
    )
    assert decision.category is TriageCategory.URGENT
    assert "R6_multiple_red_flags" in decision.rule_ids


def test_reassuring_answers_never_reduce_urgency():
    """Escalation only. No answer can talk the system down from a malignant class."""
    calm = Questionnaire(
        bleeding=False,
        pain=False,
        itching=False,
        recent_change=False,
        color_change=False,
        size_change=SizeChange.STABLE,
        duration=Duration.MORE_THAN_1_YEAR,
    )
    assert decide("mel", 0.99, calm).category is TriageCategory.URGENT
    assert decide("akiec", 0.99, calm).category is TriageCategory.PROMPT


def test_unanswered_is_not_treated_as_no():
    """A null answer contributes nothing; it is not a reassuring 'no'."""
    empty = Questionnaire()
    assert collect_red_flags(empty) == []
    assert collect_red_flags(None) == []
    assert decide("nv", 0.95, empty).category is TriageCategory.ROUTINE


def test_missing_questionnaire_still_produces_a_result():
    decision = decide("nv", 0.95, None)
    assert decision.category is TriageCategory.ROUTINE
    assert decision.rule_ids  # never silently empty


def test_longstanding_but_recently_changed_is_flagged():
    flags = collect_red_flags(
        Questionnaire(duration=Duration.MORE_THAN_1_YEAR, recent_change=True)
    )
    ids = [flag_id for flag_id, _ in flags]
    assert "flag_longstanding_change" in ids
    assert "flag_recent_change" in ids


# --- invariants --------------------------------------------------------------------


def test_every_decision_explains_itself():
    """A category with no reason attached is unusable in a UI and unauditable."""
    cases = [
        decide("nv", 0.95),
        decide("mel", 0.9),
        decide("akiec", 0.8),
        decide("nv", 0.3),
        decide("nv", 0.95, Questionnaire(bleeding=True)),
    ]
    for decision in cases:
        assert decision.rule_ids, "no rule ids"
        assert decision.reasons, "no human-readable reasons"
        assert len(decision.rule_ids) == len(decision.reasons)


def test_escalation_is_monotonic():
    """Adding a red flag can only raise the category, never lower it."""
    for code in MALIGNANCY:
        for confidence in (0.3, 0.75, 0.99):
            without = decide(code, confidence, Questionnaire())
            with_flag = decide(code, confidence, Questionnaire(color_change=True))
            assert with_flag.category.severity >= without.category.severity, (code, confidence)


def test_severity_ordering():
    assert (
        TriageCategory.ROUTINE.severity
        < TriageCategory.PROMPT.severity
        < TriageCategory.URGENT.severity
    )


@pytest.mark.parametrize("language", [Language.ENGLISH, Language.HINDI])
def test_result_is_localised_and_never_empty(language: Language):
    result = build_triage_result(decide("mel", 0.9), language)
    assert result.category is TriageCategory.URGENT
    assert result.label.strip()
    assert result.advice.strip()
    assert len(result.advice) > 40


def test_hindi_and_english_differ():
    """Guards against a missing translation silently falling back to English."""
    english = build_triage_result(decide("mel", 0.9), Language.ENGLISH)
    hindi = build_triage_result(decide("mel", 0.9), Language.HINDI)
    assert english.label != hindi.label
    assert english.advice != hindi.advice
    assert english.category is hindi.category  # the decision itself is language-independent


def test_triage_is_pure():
    """Same inputs, same output -- no hidden state, no randomness, no clock."""
    first = decide("nv", 0.55, Questionnaire(pain=True))
    second = decide("nv", 0.55, Questionnaire(pain=True))
    assert first.category is second.category
    assert first.rule_ids == second.rule_ids
