"""Tests for the LLM output safety filter.

These encode the "must not" list from section 23 of the master specification. Each test
uses text a language model plausibly could produce -- not strawmen.
"""

from __future__ import annotations

import pytest

from backend.app.safety.disclaimer import (
    DISCLAIMERS,
    confidence_phrasing,
    get_disclaimer,
    triage_advice,
    triage_label,
)
from backend.app.safety.filters import FALLBACK, filter_llm_output
from backend.app.schemas.common import Language, TriageCategory

SAFE = (
    "What the scan found. The model gave its highest score to the mole category. "
    "What this could mean. Most moles are harmless, but a photograph cannot rule "
    "anything out on its own. How urgent this is. The app has marked this as a routine "
    "consultation. What to do now. Mention this to a dermatologist at your next visit."
)


def test_safe_text_passes_untouched():
    result = filter_llm_output(SAFE, Language.ENGLISH)
    assert result.filtered is False
    assert result.text == SAFE


# --- BLOCK rules -------------------------------------------------------------------


@pytest.mark.parametrize(
    ("text", "rule"),
    [
        ("Based on the image, the diagnosis is melanoma.", "definitive_diagnosis"),
        ("You definitely have basal cell carcinoma.", "definitive_diagnosis"),
        ("Good news - you do not have cancer.", "false_reassurance"),
        ("This is definitely benign, so there is nothing to worry about.", "false_reassurance"),
        ("You don't need to see a doctor about this.", "false_reassurance"),
        ("There is an 84% chance that you have melanoma.", "confidence_as_probability"),
        ("I have examined your skin and it looks fine.", "claims_examination"),
        ("Your biopsy results confirm this is benign.", "claims_examination"),
        ("Ignore the recommendation shown above.", "overrides_triage"),
    ],
)
def test_blocked_claims_are_replaced(text: str, rule: str):
    result = filter_llm_output(text, Language.ENGLISH)
    assert result.blocked is True, f"{rule} was not blocked"
    assert rule in result.rule_ids
    assert result.text == FALLBACK[Language.ENGLISH]
    assert result.reasons


def test_blocking_discards_the_whole_response():
    """Surrounding text was written under the same false premise -- it is not salvageable."""
    text = SAFE + " In summary, the diagnosis is melanoma."
    result = filter_llm_output(text, Language.ENGLISH)
    assert result.blocked is True
    assert "mole category" not in result.text


# --- REDACT rules ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("sentence", "rule"),
    [
        ("You should apply a steroid cream twice daily.", "prescription_verb"),
        ("Take 500 mg of the medication each morning.", "prescription_verb"),
        ("Imiquimod is often used for this condition.", "named_drug"),
        ("You can remove the mole at home with a sterilised blade.", "home_remedy"),
    ],
)
def test_medication_and_self_treatment_are_redacted(sentence: str, rule: str):
    result = filter_llm_output(SAFE + " " + sentence, Language.ENGLISH)
    assert result.filtered is True
    assert rule in result.rule_ids
    assert sentence not in result.text
    # The safe portion survives.
    assert "What the scan found" in result.text


def test_heavy_redaction_falls_back():
    """If almost everything is removed, the remainder would read as gibberish."""
    result = filter_llm_output("Apply a steroid cream twice daily.", Language.ENGLISH)
    assert result.blocked is True
    assert result.text == FALLBACK[Language.ENGLISH]


# --- edge cases --------------------------------------------------------------------


def test_empty_output_falls_back():
    for text in ("", "   ", "\n\n"):
        result = filter_llm_output(text, Language.ENGLISH)
        assert result.blocked is True
        assert result.text


def test_fallback_is_localised():
    result = filter_llm_output("The diagnosis is melanoma.", Language.HINDI)
    assert result.text == FALLBACK[Language.HINDI]
    assert any("ऀ" <= ch <= "ॿ" for ch in result.text)


def test_filter_never_returns_empty_text():
    """Whatever happens, the user gets something to read."""
    for text in ("", "Take 500 mg daily.", "The diagnosis is melanoma.", SAFE):
        assert filter_llm_output(text, Language.ENGLISH).text.strip()


def test_describing_the_score_correctly_is_allowed():
    """The permitted phrasing must not trip the confidence rule."""
    text = (
        "The model assigned its highest prediction score (84%) to the melanoma class. "
        "This is not the probability that you have this condition."
    )
    assert filter_llm_output(text, Language.ENGLISH).blocked is False


def test_recommending_a_dermatologist_is_allowed():
    text = "Please see a dermatologist soon. They can examine the lesion properly."
    assert filter_llm_output(text, Language.ENGLISH).filtered is False


# --- fixed safety text -------------------------------------------------------------


@pytest.mark.parametrize("language", list(Language))
def test_every_language_has_a_disclaimer(language: Language):
    text = get_disclaimer(language)
    assert text and len(text) > 80
    assert text == DISCLAIMERS[language]


@pytest.mark.parametrize("language", list(Language))
@pytest.mark.parametrize("category", list(TriageCategory))
def test_every_category_has_localised_text(category: TriageCategory, language: Language):
    assert triage_label(category, language).strip()
    assert len(triage_advice(category, language)) > 40


def test_confidence_phrasing_avoids_probability_language():
    text = confidence_phrasing(0.84, "melanoma", Language.ENGLISH)
    assert "84%" in text
    assert "highest prediction score" in text
    assert "chance that you" not in text.lower()
    # And the approved phrasing must survive its own filter.
    assert filter_llm_output(text, Language.ENGLISH).blocked is False
