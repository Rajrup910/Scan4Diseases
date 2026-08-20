"""GET /health — liveness and component status."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from backend.app import __version__
from backend.app.dependencies import (
    get_inference_service,
    get_lesion_gate,
    get_lesion_router,
    get_llm_service,
    get_ood,
)
from backend.app.schemas.common import HealthResponse
from backend.app.services.inference import InferenceService
from backend.app.services.lesion_gate import LesionGate
from backend.app.services.lesion_router import LesionRouter
from backend.app.services.llm import LLMService
from backend.app.services.ood import MahalanobisOOD

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health(
    inference: InferenceService = Depends(get_inference_service),
    llm: LLMService = Depends(get_llm_service),
    ood: MahalanobisOOD | None = Depends(get_ood),
    lesion_gate: LesionGate | None = Depends(get_lesion_gate),
    lesion_router: LesionRouter | None = Depends(get_lesion_router),
) -> HealthResponse:
    """Report what is actually working.

    Always 200 — the point is to describe component status, not to fail. A monitor that
    cares about the model specifically should read `model_loaded`, because the API is up
    and useful for `/chat` even when no checkpoint has been trained yet.
    """
    status_info = inference.health()
    return HealthResponse(
        status="ok",
        version=__version__,
        model_loaded=status_info["model_loaded"],
        model_arch=status_info["model_arch"],
        class_mapping_version=status_info["class_mapping_version"],
        num_classes=status_info["num_classes"],
        llm_available=await llm.is_available(),
        device=status_info["device"],
        stub_mode=status_info["stub_mode"],
        ood_available=ood is not None,
        lesion_gate_available=lesion_gate is not None,
        lesion_router_available=lesion_router is not None,
    )
