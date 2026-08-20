"""POST /chat — bilingual follow-up conversation about a result.

Stateless: the client echoes back the prediction context and prior turns, so the server
retains nothing about a user's scan between requests. That is a privacy property, not an
inconvenience -- there is no conversation store to leak.

Every response carries the fixed disclaimer, and every response passes through the safety
filter before it is returned.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, status

from backend.app.dependencies import get_llm_service
from backend.app.safety.disclaimer import get_disclaimer, llm_unavailable_notice
from backend.app.schemas.chat import ChatRequest, ChatResponse
from backend.app.services.llm import LLMService
from backend.app.utils.errors import AppError

logger = logging.getLogger(__name__)
router = APIRouter(tags=["chat"])


@router.post(
    "/chat",
    response_model=ChatResponse,
    responses={503: {"description": "The explanation service is unavailable"}},
)
async def chat(
    request: ChatRequest,
    llm: LLMService = Depends(get_llm_service),
) -> ChatResponse:
    result = await llm.chat(
        message=request.message,
        history=request.history,
        prediction=request.prediction.model_dump() if request.prediction else None,
        symptoms=request.questionnaire.summary_for_llm() if request.questionnaire else None,
        language=request.language,
    )

    if not result.available:
        # 503 rather than a fabricated answer. An offline LLM must look offline.
        raise AppError(
            "llm_unavailable",
            llm_unavailable_notice(request.language),
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=result.error,
        )

    return ChatResponse(
        response=result.text,
        language=request.language,
        disclaimer=get_disclaimer(request.language),
        filtered=result.filtered,
        filter_reasons=result.filter_reasons or [],
    )
