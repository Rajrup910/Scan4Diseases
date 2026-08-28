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
        Groq API (openai/gpt-oss-120b)
                    ↓
              safety filter
                    ↓
       explanation + fixed disclaimer
```

## Cloud Provider: Groq API (`openai/gpt-oss-120b`)

The backend connects to **Groq Cloud API** via its OpenAI-compatible endpoint. Groq's LPU hardware delivers ultra-low latency (<500ms) for real-time patient explanation generation and bilingual English/Hindi support.

Key configurations:
- **Model**: `openai/gpt-oss-120b` (specified via `LLM_MODEL`)
- **Endpoint**: `https://api.groq.com/openai/v1` (via `LLM_BASE_URL`)
- **Authentication**: API key passed via standard Bearer token (`LLM_API_KEY`)
- **Rate Limiting**: Built-in sliding-window limiter (`LLM_RATE_LIMIT_RPM=10`, `LLM_RATE_LIMIT_MAX_CONCURRENT=2`) to manage API quotas smoothly without thrashing.

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

The LLM is **optional infrastructure**. If the cloud API is unreachable or rate-limited:

- `/predict` returns 200 with the classification, heatmap, triage category, triage advice
  and disclaimer, plus `explanation_available: false`.
- `/chat` returns 503 with a clear message. It never fabricates an answer to hide the outage.

`test_disclaimer_present_even_when_llm_is_down` runs with the LLM disabled and asserts the
clinically meaningful fields are all still present. That test is the evidence for the claim
that the safety-relevant output does not depend on the language model.

## Configuration

| Variable | Production Value | Description |
|---|---|---|
| `LLM_ENABLED` | `true` | Enables/disables LLM service |
| `LLM_BASE_URL` | `https://api.groq.com/openai/v1` | Groq Cloud OpenAI-compatible endpoint |
| `LLM_MODEL` | `openai/gpt-oss-120b` | High-parameter instruction-tuned model |
| `LLM_API_KEY` | *(Set via secret)* | Groq API Bearer token |
| `LLM_TEMPERATURE` | `0.3` | Factual, clinical explanation without creative drift |
| `LLM_MAX_TOKENS` | `700` | Max tokens per completion |
| `LLM_TIMEOUT_SECONDS` | `30.0` | API request timeout |
| `LLM_RATE_LIMIT_RPM` | `10` | Requests/minute quota rate limiter |

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
