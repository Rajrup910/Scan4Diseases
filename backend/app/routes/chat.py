"""POST /chat — bilingual follow-up conversation about a result.

Stateless: the client echoes back the prediction context and prior turns, so the server
retains nothing about a user's scan between requests. That is a privacy property, not an
inconvenience -- there is no conversation store to leak.

Every response carries the fixed disclaimer, and every response passes through the safety
filter before it is returned.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Request, status

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
    responses={
        429: {"description": "Rate limit exceeded for LLM chat"},
        503: {"description": "The explanation service is unavailable"},
    },
)
async def chat(
    request: ChatRequest,
    raw_request: Request,
    llm: LLMService = Depends(get_llm_service),
) -> ChatResponse:
    client_ip = raw_request.client.host if raw_request.client else "127.0.0.1"
    result = await llm.chat(
        message=request.message,
        history=request.history,
        prediction=request.prediction.model_dump() if request.prediction else None,
        symptoms=request.questionnaire.summary_for_llm() if request.questionnaire else None,
        language=request.language,
        client_key=client_ip,
    )

    if not result.available:
        if result.error and ("rate limit" in result.error.lower() or "rate_limit" in result.error.lower() or "busy" in result.error.lower()):
            raise AppError(
                "rate_limit_exceeded",
                result.error,
                status.HTTP_429_TOO_MANY_REQUESTS,
                detail=result.error,
            )
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
