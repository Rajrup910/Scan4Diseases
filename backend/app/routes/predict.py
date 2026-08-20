"""POST /predict - the main screening endpoint.

    image + questionnaire
        -> validate and decode
        -> image quality gate            (reject early, with actionable advice)
        -> CNN inference                 (class + calibrated confidence)
        -> Grad-CAM                      (heatmap overlay + focus description)
        -> deterministic triage rules    (urgency: this is where it is DECIDED)
        -> LLM                           (explanation only; may fail without breaking anything)
        -> fixed application disclaimer  (always present, never generated)

The ordering is the safety argument. Urgency is fixed before the language model is ever
called, so no generated text can influence it.
"""

from __future__ import annotations

import json
import logging
import uuid

from fastapi import APIRouter, Depends, File, Form, UploadFile, status
from pydantic import ValidationError

from backend.app.config import Settings
from backend.app.dependencies import (
    get_app_settings,
    get_inference_service,
    get_lesion_gate,
    get_lesion_router,
    get_llm_service,
    get_ood,
    get_store,
)
from backend.app.safety.disclaimer import get_disclaimer, outcome_advice, outcome_name
from backend.app.schemas.common import Language, Outcome, TriageCategory
from backend.app.schemas.prediction import (
    ClassProbability,
    ImageQuality,
    PredictionResponse,
    TriageResult,
)
from backend.app.schemas.questionnaire import Questionnaire
from backend.app.services import triage as triage_rules
from backend.app.services.inference import InferenceService, ModelUnavailableError
from backend.app.services.lesion_gate import LesionGate
from backend.app.services.lesion_router import LesionRouter
from backend.app.services.llm import LLMService
from backend.app.services.ood import MahalanobisOOD
from backend.app.services.preprocessing import ImageValidationError, decode_image
from backend.app.services.quality import assess_quality
from backend.app.services.storage import TemporaryStore
from backend.app.utils.errors import HTTP_422_UNPROCESSABLE, AppError

logger = logging.getLogger(__name__)
router = APIRouter(tags=["screening"])


def parse_questionnaire(raw: str | None) -> Questionnaire:
    """Parse the questionnaire from a multipart form field.

    It arrives as a JSON string because the request is multipart (the image is a file), so
    it cannot be a normal JSON body. Absent or empty means "not answered", which is valid.
    """
    if not raw or not raw.strip():
        return Questionnaire()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise AppError(
            "invalid_questionnaire",
            "The symptom answers could not be read. Please try again.",
            HTTP_422_UNPROCESSABLE,
            detail=f"invalid JSON at position {exc.pos}",
        ) from exc

    if not isinstance(data, dict):
        raise AppError(
            "invalid_questionnaire",
            "The symptom answers were not in the expected format.",
            HTTP_422_UNPROCESSABLE,
        )

    try:
        return Questionnaire.model_validate(data)
    except ValidationError as exc:
        fields = ", ".join(str(error["loc"][0]) for error in exc.errors()[:5] if error["loc"])
        raise AppError(
            "invalid_questionnaire",
            "Some symptom answers were not valid. Please review them and try again.",
            HTTP_422_UNPROCESSABLE,
            detail=f"invalid field(s): {fields}" if fields else None,
        ) from exc


def _non_lesion_response(
    outcome: Outcome,
    router_probabilities: dict[str, float],
    request_id: str,
    language: Language,
    answers: Questionnaire,
    quality: ImageQuality,
    model_arch: str | None,
) -> PredictionResponse:
    """Build the response for a `healthy` or `other_damage` routing decision.

    No disease class, no Grad-CAM and no LLM: the guidance is fixed, application-owned text
    (`safety/disclaimer.py`). The triage object is filled with the least-urgent category and
    that same fixed advice so a client that ignores `outcome` still shows something safe --
    but "healthy" is deliberately NOT phrased as an all-clear.
    """
    name = outcome_name(outcome, language)
    advice = outcome_advice(outcome, language)
    triage = TriageResult(
        category=TriageCategory.ROUTINE,
        label=name,
        advice=advice,
        reasons=[],
        rule_ids=[],
        low_confidence=False,
    )
    return PredictionResponse(
        request_id=request_id,
        language=language,
        outcome=outcome,
        router_probabilities={k: round(v, 4) for k, v in router_probabilities.items()},
        predicted_class=outcome.value,
        predicted_name=name,
        confidence=round(float(router_probabilities.get(outcome.value, 0.0)), 4),
        probabilities=[],
        image_quality=quality,
        gradcam_url=None,
        gradcam_focus=None,
        triage=triage,
        questionnaire=answers,
        explanation=None,
        explanation_available=False,
        disclaimer=get_disclaimer(language),
        model_arch=model_arch,
        stub=False,
        inference_ms=None,
    )


@router.post(
    "/predict",
    response_model=PredictionResponse,
    responses={
        422: {"description": "Invalid image or questionnaire"},
        503: {"description": "No trained model is available"},
    },
)
async def predict(
    image: UploadFile = File(..., description="Photograph of the skin lesion (JPEG or PNG)."),
    questionnaire: str | None = Form(
        default=None, description="Symptom answers as a JSON object. Optional."
    ),
    language: Language = Form(default=Language.ENGLISH),
    include_explanation: bool = Form(
        default=True, description="Set false to skip the LLM call and respond faster."
    ),
    settings: Settings = Depends(get_app_settings),
    inference: InferenceService = Depends(get_inference_service),
    llm: LLMService = Depends(get_llm_service),
    store: TemporaryStore = Depends(get_store),
    ood: MahalanobisOOD | None = Depends(get_ood),
    lesion_gate: LesionGate | None = Depends(get_lesion_gate),
    lesion_router: LesionRouter | None = Depends(get_lesion_router),
) -> PredictionResponse:
    request_id = uuid.uuid4().hex[:16]
    answers = parse_questionnaire(questionnaire)

    # --- 1. read and decode ---
    try:
        raw = await image.read()
    finally:
        await image.close()

    try:
        decoded = decode_image(raw, settings.max_upload_bytes)
    except ImageValidationError as exc:
        raise AppError(exc.code, exc.message, HTTP_422_UNPROCESSABLE) from exc

    # --- 2. quality gate, before spending anything on inference ---
    quality = assess_quality(
        decoded,
        min_side=settings.quality_min_side_px,
        blur_threshold=settings.quality_blur_threshold,
        dark_threshold=settings.quality_dark_threshold,
        bright_threshold=settings.quality_bright_threshold,
    )
    if not quality.acceptable:
        raise AppError(
            "image_quality_insufficient",
            "Image quality is insufficient for screening. " + (quality.primary_problem or ""),
            HTTP_422_UNPROCESSABLE,
            detail="; ".join(quality.failures),
        )

    image_quality = ImageQuality(
        acceptable=quality.acceptable,
        blur_score=round(quality.blur_score, 2),
        brightness=round(quality.brightness, 2),
        width=quality.width,
        height=quality.height,
        warnings=quality.warnings,
    )

    # --- 2b. front-stage router. Decide WHAT the photo is (lesion / healthy / other_damage
    # / not_skin) BEFORE the disease model runs. Healthy skin and wounds get their own
    # outcome instead of collapsing to "no lesion detected"; only the lesion route proceeds
    # to classification. The lesion route is high-recall (see LesionRouter), so a real lesion
    # is not siphoned into "healthy". When no router is fitted this is skipped and the legacy
    # binary gate (3b) runs instead. Features are reused by the OOD check below. ---
    router_probabilities: dict[str, float] | None = None
    routed_features = None
    if lesion_router is not None:
        routed_features = inference.penultimate_features(decoded)
        if routed_features is not None:
            route, router_probabilities = lesion_router.route(routed_features)
            logger.info(
                "request %s: router -> %s %s",
                request_id, route, {k: round(v, 3) for k, v in router_probabilities.items()},
            )
            if route == "not_skin":
                raise AppError(
                    "no_lesion_detected",
                    "We couldn't find a skin lesion in this photo. Please take a clear, "
                    "close-up picture of the affected skin and try again.",
                    HTTP_422_UNPROCESSABLE,
                )
            if route in (Outcome.HEALTHY.value, Outcome.OTHER_DAMAGE.value):
                return _non_lesion_response(
                    Outcome(route), router_probabilities, request_id, language,
                    answers, image_quality, inference.arch,
                )
            # route == "lesion": fall through to the disease pipeline.

    # --- 3. classification + Grad-CAM ---
    try:
        result = inference.predict(decoded, with_gradcam=True)
    except ModelUnavailableError as exc:
        raise AppError(
            "model_unavailable",
            "The screening model is not available right now. Please try again later.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    except Exception as exc:  # noqa: BLE001 - a model failure must not leak internals
        logger.exception("inference failed for request %s", request_id)
        raise AppError(
            "inference_failed",
            "Unable to analyse the image. Please upload a clearer image and try again.",
            status.HTTP_500_INTERNAL_SERVER_ERROR,
        ) from exc

    mapping = inference.mapping
    predicted = mapping.by_code(result.predicted_code)

    # --- 3b. lesion-presence checks on the lesion route. The Mahalanobis distance (gross,
    # non-skin OOD) always runs as defence-in-depth. The binary lesion gate runs ONLY when
    # the multi-class router is absent -- when the router is present it already made the
    # skin-but-not-lesion call (as `not_skin` / `healthy`), so running the gate too would
    # double-judge. Features from the router are reused to avoid a second extraction. ---
    use_binary_gate = lesion_gate is not None and lesion_router is None
    if ood is not None or use_binary_gate:
        features = routed_features if routed_features is not None else inference.penultimate_features(decoded)
        if features is not None:
            reject_reason = None

            if use_binary_gate:
                p_lesion = lesion_gate.probability(features)
                gate_reject = p_lesion < lesion_gate.threshold
                logger.info(
                    "request %s: lesion_gate p=%.3f threshold=%.3f -> %s",
                    request_id, p_lesion, lesion_gate.threshold,
                    "REJECT" if gate_reject else "accept",
                )
                if gate_reject:
                    reject_reason = "lesion_gate"

            if ood is not None:
                distance = ood.score(features)
                ood_reject = distance > ood.threshold
                logger.info(
                    "request %s: ood maha=%.1f threshold=%.1f -> %s",
                    request_id, distance, ood.threshold, "REJECT" if ood_reject else "accept",
                )
                if ood_reject and reject_reason is None:
                    reject_reason = "mahalanobis"

            if reject_reason is not None:
                logger.info("request %s: rejected as non-lesion (%s)", request_id, reject_reason)
                raise AppError(
                    "no_lesion_detected",
                    "We couldn't find a skin lesion in this photo. Please take a clear, "
                    "close-up picture of the affected skin and try again.",
                    HTTP_422_UNPROCESSABLE,
                )

    # --- 4. deterministic triage. Urgency is decided HERE, before the LLM exists. ---
    decision = triage_rules.assess(
        predicted_code=result.predicted_code,
        confidence=result.confidence,
        probabilities=result.probabilities,
        malignancy_by_code=mapping.malignancy_by_code(),
        questionnaire=answers,
        low_confidence_threshold=settings.low_confidence_threshold,
    )
    triage = triage_rules.build_triage_result(decision, language)

    # --- 5. persist only the overlay, never the uploaded photograph ---
    gradcam_url = None
    if result.overlay is not None:
        filename = store.save_overlay(result.overlay)
        if filename:
            gradcam_url = f"/gradcam/{filename}"

    # --- 6. explanation. Optional by design: failure here degrades, never breaks. ---
    explanation = None
    explanation_available = False
    if include_explanation:
        llm_result = await llm.explain(
            predicted_name=predicted.short_name(language),
            predicted_code=predicted.code,
            confidence=result.confidence,
            class_description=predicted.description(language),
            triage_category=triage.category.value,
            triage_label=triage.label,
            triage_reasons=triage.reasons,
            low_confidence=triage.low_confidence,
            symptoms=answers.summary_for_llm(),
            gradcam_focus=result.gradcam_focus,
            language=language,
        )
        explanation_available = llm_result.available
        explanation = llm_result.text if llm_result.available else None
        if not llm_result.available:
            logger.info("request %s: explanation unavailable (%s)", request_id, llm_result.error)

    probabilities = sorted(
        (
            ClassProbability(
                code=code,
                name=mapping.by_code(code).short_name(language),
                probability=probability,
                malignancy=mapping.by_code(code).malignancy,
            )
            for code, probability in result.probabilities.items()
        ),
        key=lambda item: item.probability,
        reverse=True,
    )

    logger.info(
        "request %s: %s conf=%.3f triage=%s rules=%s%s",
        request_id,
        result.predicted_code,
        result.confidence,
        triage.category.value,
        ",".join(triage.rule_ids),
        " [STUB]" if result.stub else "",
    )

    return PredictionResponse(
        request_id=request_id,
        language=language,
        outcome=Outcome.LESION,
        router_probabilities=(
            {k: round(v, 4) for k, v in router_probabilities.items()}
            if router_probabilities is not None
            else None
        ),
        predicted_class=result.predicted_code,
        predicted_name=predicted.short_name(language),
        confidence=result.confidence,
        probabilities=probabilities,
        image_quality=image_quality,
        gradcam_url=gradcam_url,
        gradcam_focus=result.gradcam_focus,
        triage=triage,
        questionnaire=answers,
        explanation=explanation,
        explanation_available=explanation_available,
        # Always from the application, never from the model.
        disclaimer=get_disclaimer(language),
        model_arch=inference.arch,
        stub=result.stub,
        inference_ms=round(result.inference_ms, 1),
    )
