# Safety Architecture

The central design claim of this project:

> The parts of the output that matter medically are **not generated text.**

A language model is a good writer and an unreliable clinician. So it is given the job of
writing, and none of the job of deciding. This document describes how that separation is
enforced and how to verify it.

---

## Layer 1 — Deterministic triage

**File:** [`backend/app/services/triage.py`](../backend/app/services/triage.py)
**Tests:** [`backend/tests/test_triage.py`](../backend/tests/test_triage.py)

`assess()` is a pure function: no I/O, no model, no clock, no randomness. Given the same
prediction and questionnaire it always returns the same category, and every category comes
with the list of rule ids that produced it.

### The three categories

| Category | Meaning |
|---|---|
| `routine_consultation` | Nothing indicated urgency. Mention at the next routine visit. |
| `prompt_consultation` | See a dermatologist soon rather than waiting. |
| `urgent_evaluation` | Seek evaluation without delay. |

### The rules

| id | Condition | Result |
|---|---|---|
| `R1_malignant_class` | Top-1 class is `mel` or `bcc` | **urgent** |
| `R2_premalignant_class` | Top-1 class is `akiec` | prompt |
| `R3_malignant_mass_high` | Σ P(malignant classes) ≥ 0.40 | **urgent** |
| `R4_malignant_mass_moderate` | Σ P(malignant classes) ≥ 0.20 | prompt |
| `R4b_premalignant_mass` | Σ P(pre-malignant) ≥ 0.20 | prompt |
| `R5_low_confidence` | Top score < 0.60 | prompt |
| `R6_multiple_red_flags` | ≥ 3 symptom red flags | **urgent** |
| `R7_red_flag` | ≥ 1 symptom red flag | prompt |
| `R8_bleeding` | Lesion bled unprovoked | **urgent** |
| `R9_default_routine` | Nothing above fired | routine |

Red flags: unprovoked bleeding, growth, colour change, recent change, pain, and a
long-standing lesion that has recently changed.

### Four invariants, each with a test

1. **Escalation only.** Rules raise the category; nothing lowers it. A user answering "no"
   to everything cannot talk the system down from a malignant classification.
   → `test_reassuring_answers_never_reduce_urgency`, `test_escalation_is_monotonic`

2. **Missing ≠ no.** An unanswered question contributes nothing. It is never read as a
   reassuring answer.
   → `test_unanswered_is_not_treated_as_no`

3. **Top-1 is not the whole story.** A 45% `nv` / 42% `mel` prediction is not benign, but
   argmax alone reports it as one. The probability-mass rules catch it.
   → `test_benign_top1_with_high_malignant_mass_is_urgent`

4. **Every decision explains itself.** A category with no attached reason is unusable in a
   UI and unauditable in a report.
   → `test_every_decision_explains_itself`

### Why pre-malignant mass is tracked separately

An early version summed malignant and pre-malignant probability into one mass. That made a
*confident* `akiec` prediction (0.99) trip the 0.40 urgent threshold and contradict R2,
which classifies it as prompt. Actinic keratosis warrants seeing someone soon, not an
emergency. The masses are now separate, and pre-malignant mass can only reach prompt.

This was found by a test, not by review. Worth mentioning in the report: the rule layer is
testable precisely *because* it is deterministic, and that caught a real inconsistency that
a prompt-based approach would have hidden.

### Calibration

The thresholds are conservative by intent. In a screening tool a false alarm costs an
unnecessary consultation; a missed melanoma costs considerably more. Expect a high
escalation rate. If clinical review later says the system over-refers, the thresholds are
three constants at the top of one file — and changing them re-runs 30 tests.

---

## Layer 2 — Output filter

**File:** [`backend/app/safety/filters.py`](../backend/app/safety/filters.py)
**Tests:** [`backend/tests/test_safety.py`](../backend/tests/test_safety.py)

The system prompt tells the model what not to say. This layer checks whether it complied,
because a prompt is a request, not a guarantee.

| Severity | Behaviour |
|---|---|
| `BLOCK` | The entire response is replaced with a safe fallback |
| `REDACT` | The offending sentence is removed, the rest is kept |

### Blocking rules

| id | Catches |
|---|---|
| `definitive_diagnosis` | "the diagnosis is melanoma", "you definitely have..." |
| `false_reassurance` | "you do not have cancer", "no need to see a doctor" |
| `confidence_as_probability` | "there is an 84% chance that you have..." |
| `claims_examination` | "I have examined your skin", "your biopsy results show" |
| `overrides_triage` | "ignore the recommendation above" |

A BLOCK discards everything, not just the offending sentence — text written around a false
diagnosis was written under the same false premise and is not worth salvaging.

### Redaction rules

| id | Catches |
|---|---|
| `prescription_verb` | "take 500 mg", "apply the cream twice daily" |
| `named_drug` | imiquimod, fluorouracil, clobetasol, … |
| `home_remedy` | "you can remove the mole at home" |

If redaction leaves under 40 characters, the fallback is used instead — a shredded response
reads as gibberish.

Regexes are blunt and will occasionally fire on harmless text. That trade is deliberate: an
over-cautious filter costs a little fluency; an under-cautious one lets a screening app tell
someone to take a drug.

---

## Layer 3 — Fixed disclaimer

**File:** [`backend/app/safety/disclaimer.py`](../backend/app/safety/disclaimer.py)

Every string is a constant. Nothing is generated, and nothing — **including the Hindi
version** — passes through the language model.

That last point matters more than it looks. If the model translated the disclaimer per
request, an unlucky sample could soften "this is not a medical diagnosis" into something
weaker, and nobody would notice for months.

The disclaimer is attached to every `/predict` and every `/chat` response, and
`test_disclaimer_present_even_when_llm_is_down` proves it survives with the LLM disabled.

### Confidence phrasing

Approved:

> The model assigned its highest prediction score (84%) to the melanoma class. This score
> describes how strongly the image matched that category in the model's training data. It
> is not the probability that you have this condition.

Forbidden, and blocked by the filter:

> There is an 84% chance that you have melanoma.

---

## What the LLM is allowed to do

| Allowed | Forbidden |
|---|---|
| Explain the result in plain language | Diagnose |
| Define medical terms | Invent symptoms or test results |
| Explain why the assigned urgency was assigned | Choose or change the urgency |
| Translate the explanation | Alter numbers during translation |
| Answer general follow-up questions | Name or recommend medication |
| Say it cannot answer something | Claim to have examined the user |

---

## Privacy

- The uploaded photograph is **never written to disk**. It exists as bytes in memory for the
  duration of the request.
- Only the Grad-CAM overlay is persisted, under a 128-bit random name, deleted after the TTL
  (default 15 minutes), on shutdown, and opportunistically on every write.
- `STORAGE_TTL_MINUTES=0` disables persistence entirely.
- `/chat` is stateless — no conversation history is stored server-side.
- No name, phone number, address or identifier is collected anywhere. The questionnaire asks
  only about the lesion.
- Overlays are served `Cache-Control: private, no-store`.

---

## Failure behaviour

Nothing fails silently.

| Failure | Behaviour |
|---|---|
| No checkpoint | `/predict` → 503 `model_unavailable`. Never a fabricated prediction. |
| Model raises | 500 `inference_failed`, full trace logged server-side, nothing leaked. |
| Ollama down | `/predict` succeeds with `explanation_available: false`. `/chat` → 503. |
| LLM times out | Same as above. |
| Bad image | 422 with a specific, actionable message. |
| Stub mode on | Every response flagged `"stub": true`, warning logged per call, `/health` reports it. |

---

## Verifying these claims

```bash
.venv/Scripts/python.exe -m pytest backend/tests/test_triage.py backend/tests/test_safety.py -v
```

If the report claims urgency is deterministic and auditable, that command is the evidence.
