"""LLM Rate Limiter service.

Provides:
1. Sliding window rate limiting per client IP (requests per minute).
2. Concurrency limiting across all active LLM generation calls using an asyncio.Semaphore.
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import AsyncGenerator

logger = logging.getLogger(__name__)


class LLMRateLimiter:
    def __init__(self, rpm: int = 10, max_concurrent: int = 3, window_seconds: float = 60.0) -> None:
        self.rpm = rpm
        self.max_concurrent = max_concurrent
        self.window_seconds = window_seconds
        
        self._history: dict[str, list[float]] = defaultdict(list)
        self._lock = asyncio.Lock()
        self._semaphore: asyncio.Semaphore | None = None

    def _get_semaphore(self) -> asyncio.Semaphore:
        if self._semaphore is None:
            self._semaphore = asyncio.Semaphore(self.max_concurrent)
        return self._semaphore

    async def check_rate_limit(self, client_key: str = "default") -> tuple[bool, str | None]:
        """Check if client_key is within the sliding window request rate limit."""
        now = time.monotonic()
        async with self._lock:
            timestamps = self._history[client_key]
            # Filter out timestamps older than the sliding window
            valid_timestamps = [t for t in timestamps if now - t < self.window_seconds]
            self._history[client_key] = valid_timestamps
            
            if len(valid_timestamps) >= self.rpm:
                logger.warning("Rate limit exceeded for client '%s': %d requests in %ss", client_key, len(valid_timestamps), self.window_seconds)
                return False, f"Rate limit exceeded ({self.rpm} requests per minute). Please wait before trying again."
            
            # Record current request timestamp
            self._history[client_key].append(now)
            return True, None

    @asynccontextmanager
    async def acquire(self, client_key: str = "default", timeout: float = 0.5) -> AsyncGenerator[tuple[bool, str | None], None]:
        """Acquire rate-limit permit and concurrency lock.
        
        Yields (allowed, error_reason).
        """
        allowed, reason = await self.check_rate_limit(client_key)
        if not allowed:
            yield False, reason
            return

        sem = self._get_semaphore()
        acquired = False
        try:
            try:
                await asyncio.wait_for(sem.acquire(), timeout=timeout)
                acquired = True
            except asyncio.TimeoutError:
                logger.warning("LLM concurrency limit reached (%d max concurrent tasks)", self.max_concurrent)
                yield False, "Server is busy handling other LLM requests. Please try again shortly."
                return

            yield True, None
        finally:
            if acquired:
                sem.release()

    def reset(self) -> None:
        """Reset rate limiter state (useful for tests)."""
        self._history.clear()
        self._semaphore = None
