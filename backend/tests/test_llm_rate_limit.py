"""Unit and integration tests for LLM rate limiting."""

from __future__ import annotations

import asyncio
import pytest
from fastapi.testclient import TestClient
from backend.app.config import Settings
from backend.app.services.rate_limiter import LLMRateLimiter
from backend.app.services.llm import LLMService, LLMResponse
from backend.app.schemas.common import Language


@pytest.mark.asyncio
async def test_rate_limiter_rpm_limit():
    limiter = LLMRateLimiter(rpm=3, max_concurrent=2, window_seconds=60.0)

    # First 3 requests should pass
    ok1, err1 = await limiter.check_rate_limit("client_1")
    assert ok1 is True and err1 is None

    ok2, err2 = await limiter.check_rate_limit("client_1")
    assert ok2 is True and err2 is None

    ok3, err3 = await limiter.check_rate_limit("client_1")
    assert ok3 is True and err3 is None

    # 4th request from same client should fail
    ok4, err4 = await limiter.check_rate_limit("client_1")
    assert ok4 is False
    assert "Rate limit exceeded" in err4

    # Different client IP should still be allowed
    ok_other, err_other = await limiter.check_rate_limit("client_2")
    assert ok_other is True


@pytest.mark.asyncio
async def test_rate_limiter_concurrency_limit():
    limiter = LLMRateLimiter(rpm=10, max_concurrent=1, window_seconds=60.0)

    # Acquire lock in first task
    async with limiter.acquire("client_a") as (allowed1, err1):
        assert allowed1 is True
        
        # Second simultaneous acquire should fail with concurrency timeout
        async with limiter.acquire("client_b", timeout=0.05) as (allowed2, err2):
            assert allowed2 is False
            assert "busy" in err2.lower() or "concurrent" in err2.lower()


@pytest.mark.asyncio
async def test_llm_service_explain_rate_limit():
    settings = Settings(llm_enabled=True, llm_rate_limit_rpm=2)
    service = LLMService(settings)

    # First 2 explain calls should pass (will fail with connection error or empty response since no server, but not rate limit)
    res1 = await service.explain(
        predicted_name="Melanoma",
        predicted_code="mel",
        confidence=0.8,
        class_description="Skin cancer",
        triage_category="urgent",
        triage_label="Urgent",
        triage_reasons=["Malignant"],
        low_confidence=False,
        symptoms={},
        gradcam_focus=None,
        language=Language.ENGLISH,
        client_key="test_ip",
    )
    assert res1.error != "Rate limit exceeded (2 requests per minute). Please wait before trying again."

    res2 = await service.explain(
        predicted_name="Melanoma",
        predicted_code="mel",
        confidence=0.8,
        class_description="Skin cancer",
        triage_category="urgent",
        triage_label="Urgent",
        triage_reasons=["Malignant"],
        low_confidence=False,
        symptoms={},
        gradcam_focus=None,
        language=Language.ENGLISH,
        client_key="test_ip",
    )

    # 3rd explain call should return rate limit error
    res3 = await service.explain(
        predicted_name="Melanoma",
        predicted_code="mel",
        confidence=0.8,
        class_description="Skin cancer",
        triage_category="urgent",
        triage_label="Urgent",
        triage_reasons=["Malignant"],
        low_confidence=False,
        symptoms={},
        gradcam_focus=None,
        language=Language.ENGLISH,
        client_key="test_ip",
    )
    assert res3.available is False
    assert "Rate limit exceeded" in (res3.error or "")
