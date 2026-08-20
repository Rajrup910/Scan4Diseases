# LLM Integration

**Implementation:** [`backend/app/services/llm.py`](../backend/app/services/llm.py)

## Role

The language model is the **last** component in the pipeline and the **least** authoritative.
By the time it is called, the class, the confidence and the urgency category already exist.
Its job is to turn that into readable English or Hindi.

```
prediction + questionnaire + triage category  (all already decided)
                    ↓
            controlled system prompt
                    ↓
                  Qwen3
                    ↓
              safety filter
                    ↓
       explanation + fixed disclaimer
```

## Why an 8B model, not a 70B

Expect this question in a review. The answer: **this task is writing, not medical
reasoning.** The reasoning lives in the CNN and in the rule layer. An 8B model is entirely
capable of rephrasing a structured JSON object into four short paragraphs, and it fits in
8 GB of VRAM alongside development work. A larger model would produce marginally better
prose and no better medicine.

## Why local, not a hosted API

Three arguments, in order of strength:

1. **Privacy.** Skin photographs and symptom answers never leave the machine. For medical
   data that is an ethical argument, not a nice-to-have.
2. **No recurring cost.** A free app for rural users cannot carry a per-scan bill.
3. **Works without reliable internet** — which is the exact population the project claims
   to serve.

A budget constraint became a design justification. Say it that way in the report.

## Setup

```bash
winget install --id Ollama.Ollama --source winget
```

```bash
ollama pull qwen3:8b
```

Ollama exposes an OpenAI-compatible endpoint at `http://localhost:11434/v1`, so the backend
talks to it with plain HTTP and no vendor SDK. Swapping to a hosted provider is a URL change.

Test Hindi **before** promising bilingual support in the report:

```bash
ollama run qwen3:8b "एक तिल और मेलेनोमा में क्या अंतर है? दो वाक्यों में बताइए।"
```

On an 8 GB card, do not train and run the LLM simultaneously. If VRAM is tight during
development, use `qwen3:4b` and switch to 8B for the demo.

## Input

The model receives structured JSON, never free text. Every field is something already
computed; there is nothing for it to infer.

```json
{
  "predicted_category": "bcc",
  "predicted_category_name": "Basal cell carcinoma",
  "what_this_category_is": "The most common form of skin cancer...",
  "model_confidence_percent": 81,
  "model_was_uncertain": false,
  "safety_category": "urgent_evaluation",
  "safety_category_label": "Urgent medical evaluation",
  "why_this_safety_category": ["The screening model's leading category is one that can be cancerous."],
  "symptoms_the_user_reported": {"bleeding": true, "duration": "3_to_12_months"},
  "where_the_heatmap_focused": "concentrated on the central region of the image"
}
```

**Only answered questionnaire fields are included.** A model shown `"bleeding": null` will
sometimes write "you reported no bleeding" — a fabricated symptom claim. Omitting the key
removes the opportunity.

## System prompt

The full text is `SYSTEM_PROMPT` in `llm.py`. Its structure:

- **What you are given** — the model has already classified; here is the output.
- **Your job** — explain it simply.
- **Hard rules** — do not invent symptoms; do not convert confidence into disease
  probability; do not name medication; use the supplied safety category; do not claim to
  have examined the user; never say a doctor is unnecessary.
- **Structure** — four fixed headings: *What the scan found* / *What this could mean* /
  *How urgent this is* / *What to do now*. Under 250 words.
- **Language** — respond entirely in the requested language, but keep the category name and
  the numeric confidence exactly as given.

That last clause matters: translation must not silently alter numbers.

A separate, shorter prompt governs `/chat`, with the same prohibitions and an instruction to
decline questions it cannot responsibly answer (prognosis, treatment choice, "do I have
cancer") by redirecting to a dermatologist.

## Handling reasoning tokens

Qwen3 wraps its chain of thought in `<think>...</think>`. That is internal scratch work,
written for itself rather than the user, and it does not follow the four-section structure.
`_strip_reasoning()` removes it before anything else happens.

## Output filtering

Every generated response passes through
[`backend/app/safety/filters.py`](../backend/app/safety/filters.py) before reaching the
client. The system prompt is a request; the filter is the check. See
[`docs/safety.md`](safety.md).

## Failure behaviour

The LLM is **optional infrastructure**. If Ollama is not running:

- `/predict` returns 200 with the classification, heatmap, triage category, triage advice
  and disclaimer, plus `explanation_available: false`.
- `/chat` returns 503 with a clear message. It never fabricates an answer to hide the outage.

`test_disclaimer_present_even_when_llm_is_down` runs with the LLM disabled and asserts the
clinically meaningful fields are all still present. That test is the evidence for the claim
that the safety-relevant output does not depend on the language model.

## Configuration

| Variable | Default |
|---|---|
| `LLM_ENABLED` | `true` |
| `LLM_BASE_URL` | `http://localhost:11434/v1` |
| `LLM_MODEL` | `qwen3:8b` |
| `LLM_TEMPERATURE` | `0.3` — low, because this is explanation, not creative writing |
| `LLM_MAX_TOKENS` | `700` |
| `LLM_TIMEOUT_SECONDS` | `60` |

## Evaluating the explanations

Prompt engineering is not finished when the output "looks fine". Planned evaluation, which
is itself a reportable contribution:

1. Sample ~100 predictions spanning all classes, both confidence regimes, and all three
   triage categories.
2. Three raters score each explanation on: factual consistency with the structured input,
   absence of invented content, correct handling of the confidence number, preservation of
   the triage category, and readability for a non-medical reader.
3. Report inter-rater agreement (Cohen's κ) and the failure taxonomy.
4. Repeat for Hindi, checking specifically that numbers and category names survive
   translation unchanged.

Record how often the safety filter fires and on which rules — that count is a finding, not
an embarrassment. A filter that never fires has not been tested hard enough.
