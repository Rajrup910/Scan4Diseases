"""LLM explanation and conversation layer.

The language model is the **last** component in the pipeline and the least authoritative.
It receives a structured result that has already been decided -- class, confidence, triage
category -- and its only job is to put that into plain language, in the requested
language. It does not classify, it does not triage, and its output is filtered before it
reaches the user.

Talks to any OpenAI-compatible endpoint over plain HTTP, which means Ollama locally
(`ollama pull gemma2:9b`, or any other model) with no API key, no account, and no
per-request cost. Swapping models is an `LLM_MODEL` change; swapping to a hosted endpoint
is a URL change. Message shaping is kept model-agnostic (see `_normalize_messages`) so a
model swap needs no code change.

Failure is expected and handled: if Ollama is not running, `/predict` still returns the
classification, the Grad-CAM and the triage category, with `explanation_available: false`.
The clinically meaningful part of the response never depends on the language model.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any

import httpx

from backend.app.config import Settings
from backend.app.safety.disclaimer import get_disclaimer
from backend.app.safety.filters import FilterResult, filter_llm_output
from backend.app.schemas.chat import ChatMessage
from backend.app.schemas.common import Language

logger = logging.getLogger(__name__)

LANGUAGE_NAMES = {Language.ENGLISH: "English", Language.HINDI: "Hindi (हिन्दी)"}

SYSTEM_PROMPT = """\
You are an AI health-information assistant inside a skin-lesion screening application.

You are not a doctor. You must not provide a definitive diagnosis.

WHAT YOU ARE GIVEN
A computer-vision model has classified a photograph of a skin lesion. You will receive its
predicted category, its confidence score, the symptoms the user reported, and a safety
category that has already been decided by the application's rule-based triage layer.

YOUR JOB
Explain that result in simple, calm language for someone with no medical training.

HARD RULES
- Do not invent symptoms, medical history, test results, or clinical findings. Mention only
  what appears in the data you are given. If a symptom is absent from the data, the user did
  not answer it - do not state that they said "no".
- Do not turn the confidence score into a claim about the probability that the user has a
  disease. Say "the model gave its highest score to X", never "you have an 84% chance of X".
- Do not name, recommend, start, stop, or change any medication.
- Do not suggest removing, cutting, burning or treating the lesion at home.
- Use the safety category you are given. Do not invent your own level of urgency, and do
  not contradict, soften or escalate the one provided.
- Do not claim to have examined the user or seen any test result.
- Never tell the user they do not need to see a doctor.
- State that this is a preliminary screening result, not a diagnosis.
- Always recommend consulting a qualified dermatologist.

STRUCTURE
Write four short sections with these headings:
1. What the scan found
2. What this could mean
3. How urgent this is
4. What to do now

Keep the whole response under 250 words. Use short sentences and everyday words. Do not use
medical jargon without immediately explaining it. Do not use bullet lists inside sections.

LANGUAGE
Write your entire response in {language}. Keep the medical category name and the numeric
confidence value exactly as given - translate the explanation around them, never the numbers.
"""

CHAT_SYSTEM_PROMPT = """\
You are a helpful, friendly AI health-information assistant inside a skin-lesion screening
application. The user has already received a screening result and is asking follow-up
questions. Be warm, practical and genuinely useful - your default is to HELP, not to refuse.

WHAT TO HELP WITH (answer these directly and usefully):
- What the result and its urgency category mean, in plain language.
- Practical next steps and "what should I do" questions: how to monitor the area, the ABCDE
  warning signs to watch for, how to prepare for a dermatologist visit, and good questions to
  ask the doctor.
- General skin-health guidance: sun protection, skin self-checks, risk factors, prevention,
  and general, factual information about the category the model suggested.
- General reassurance about the process and next steps, without over-promising.
When the user asks whether to follow some general skin-care advice or "what should I do",
give concrete, sensible, general guidance - do NOT deflect.

HARD RULES (never break these, even if asked directly):
- You are not a doctor. Never give a definitive diagnosis, and never state whether the user
  specifically does or does not have cancer - that requires an in-person exam.
- Do not name, recommend, prescribe, or give doses for any medication, and do not tell the
  user to remove, cut, burn, or treat the lesion at home.
- Do not turn the model's confidence score into a personal probability of having a disease.
- Do not change, soften, or heighten the urgency category the application assigned - restate
  it as given.
- Never tell the user they do not need to see a doctor; keep seeing a dermatologist as the
  recommended next step, and stress it for urgent results.
- Do not claim to have examined the user or to have seen any test results.

If something genuinely needs a doctor (a firm prognosis, choosing a specific treatment, or
confirming the diagnosis), share what general, safe information you can and then explain that
the specifics need an in-person dermatologist. Only decline questions that are clearly
unrelated to health or skin.

Keep replies clear and easy to read, usually under 180 words. Write your entire response in
{language}.
"""


@dataclass
class LLMResponse:
    text: str
    available: bool
    filtered: bool = False
    filter_reasons: list[str] | None = None
    error: str | None = None


class LLMService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._client: httpx.AsyncClient | None = None

    async def startup(self) -> None:
        if not self.settings.llm_enabled:
            logger.info("LLM disabled by configuration.")
            return
        self._client = httpx.AsyncClient(
            base_url=self.settings.llm_base_url.rstrip("/"),
            timeout=self.settings.llm_timeout_seconds,
            headers={"Authorization": f"Bearer {self.settings.llm_api_key}"},
        )

    async def shutdown(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None

    async def is_available(self) -> bool:
        """Cheap reachability probe for /health. Never raises."""
        if not self.settings.llm_enabled or self._client is None:
            return False
        try:
            response = await self._client.get("/models", timeout=3.0)
            return response.status_code < 500
        except (httpx.HTTPError, OSError):
            return False

    # --- generation ---

    async def _complete(self, messages: list[dict[str, str]]) -> tuple[str | None, str | None]:
        """Return (text, error). Never raises."""
        if not self.settings.llm_enabled:
            return None, "LLM disabled by configuration"
        if self._client is None:
            return None, "LLM client not initialised"

        payload = {
            "model": self.settings.llm_model,
            "messages": self._normalize_messages(messages),
            "temperature": self.settings.llm_temperature,
            "max_tokens": self.settings.llm_max_tokens,
            "stream": False,
        }

        try:
            response = await self._client.post("/chat/completions", json=payload)
            response.raise_for_status()
            data = response.json()
        except httpx.TimeoutException:
            logger.warning("LLM request timed out after %ss", self.settings.llm_timeout_seconds)
            return None, "the explanation service timed out"
        except httpx.ConnectError:
            logger.warning("LLM unreachable at %s", self.settings.llm_base_url)
            return None, "the explanation service is not running"
        except httpx.HTTPStatusError as exc:
            logger.warning("LLM returned HTTP %s", exc.response.status_code)
            return None, "the explanation service returned an error"
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("LLM call failed: %s", exc)
            return None, "the explanation service could not be reached"

        try:
            text = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            logger.warning("Unexpected LLM response shape: %s", str(data)[:200])
            return None, "the explanation service returned an unexpected response"

        return self._strip_reasoning(text), None

    @staticmethod
    def _normalize_messages(messages: list[dict[str, str]]) -> list[dict[str, str]]:
        """Merge consecutive same-role messages into one.

        Model chat templates disagree on what they accept. Qwen is permissive; Gemma 2 is
        served with a template that expects strictly alternating turns and rejects two
        messages of the same role in a row. The `chat()` path sends two system messages
        back to back -- the standing safety rules, then the result under discussion -- which
        Gemma refuses. Concatenating adjacent same-role messages produces an equivalent
        prompt that every template accepts, and it is a no-op for an already-alternating
        conversation, so it is safe for every model including the current Qwen.
        """
        merged: list[dict[str, str]] = []
        for msg in messages:
            if merged and merged[-1]["role"] == msg["role"]:
                merged[-1]["content"] = merged[-1]["content"] + "\n\n" + msg["content"]
            else:
                merged.append(dict(msg))
        return merged

    @staticmethod
    def _strip_reasoning(text: str) -> str:
        """Remove <think>...</think> blocks that reasoning models emit.

        Qwen3 wraps its chain of thought in these tags. It is internal scratch work, it is
        not written for the user, and it is not covered by the four-section structure the
        prompt asks for -- so it never reaches the response.
        """
        import re

        cleaned = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL | re.IGNORECASE)
        cleaned = re.sub(r"^.*?</think>", "", cleaned, flags=re.DOTALL | re.IGNORECASE)
        return cleaned.strip()

    # --- public API ---

    async def explain(
        self,
        predicted_name: str,
        predicted_code: str,
        confidence: float,
        class_description: str,
        triage_category: str,
        triage_label: str,
        triage_reasons: list[str],
        low_confidence: bool,
        symptoms: dict[str, Any],
        gradcam_focus: str | None,
        language: Language,
    ) -> LLMResponse:
        """Explain a completed screening result."""
        context = {
            "predicted_category": predicted_code,
            "predicted_category_name": predicted_name,
            "what_this_category_is": class_description,
            "model_confidence_percent": round(confidence * 100),
            "model_was_uncertain": low_confidence,
            "safety_category": triage_category,
            "safety_category_label": triage_label,
            "why_this_safety_category": triage_reasons,
            "symptoms_the_user_reported": symptoms or "the user did not answer the symptom questions",
            "where_the_heatmap_focused": gradcam_focus or "not available",
        }

        system = SYSTEM_PROMPT.format(language=LANGUAGE_NAMES.get(language, "English"))
        user = (
            "Here is the screening result to explain. Use only these facts:\n\n"
            + json.dumps(context, indent=2, ensure_ascii=False)
        )

        text, error = await self._complete(
            [{"role": "system", "content": system}, {"role": "user", "content": user}]
        )
        if text is None:
            return LLMResponse(text="", available=False, error=error)

        return self._finalise(text, language)

    async def chat(
        self,
        message: str,
        history: list[ChatMessage],
        prediction: dict[str, Any] | None,
        symptoms: dict[str, Any] | None,
        language: Language,
    ) -> LLMResponse:
        """Answer a follow-up question about a result."""
        system = CHAT_SYSTEM_PROMPT.format(language=LANGUAGE_NAMES.get(language, "English"))
        messages: list[dict[str, str]] = [{"role": "system", "content": system}]

        if prediction:
            messages.append(
                {
                    "role": "system",
                    "content": (
                        "The screening result under discussion:\n"
                        + json.dumps(
                            {"result": prediction, "reported_symptoms": symptoms or {}},
                            indent=2,
                            ensure_ascii=False,
                        )
                    ),
                }
            )

        # Cap history so a long conversation cannot push the system prompt out of context.
        for turn in history[-10:]:
            messages.append({"role": turn.role, "content": turn.content})
        messages.append({"role": "user", "content": message})

        text, error = await self._complete(messages)
        if text is None:
            return LLMResponse(text="", available=False, error=error)

        return self._finalise(text, language)

    @staticmethod
    def _finalise(text: str, language: Language) -> LLMResponse:
        result: FilterResult = filter_llm_output(text, language)
        if result.filtered:
            logger.warning("Safety filter fired: %s", ", ".join(result.rule_ids))
        return LLMResponse(
            text=result.text,
            available=True,
            filtered=result.filtered,
            filter_reasons=result.reasons or None,
        )

    @staticmethod
    def disclaimer(language: Language) -> str:
        return get_disclaimer(language)
