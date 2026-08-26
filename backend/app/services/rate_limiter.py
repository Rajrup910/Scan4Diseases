"""LLM Rate Limiter service.

Provides:
1. Sliding window rate limiting per client IP (requests per minute).
2. Concurrency limiting across all active LLM generation calls using an asyncio.Semaphore.
"""

from __future__ import annotations

import asyncio
import logging
import threading
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


class FixedWindowRateLimiter:
    """A tiny synchronous sliding-window limiter for the auth endpoints.

    The auth handlers are synchronous (they run in FastAPI's threadpool), so they
    can't use the async LLM limiter above. This one is thread-safe via a plain
    lock and keyed by client IP + purpose ("login", "register"), throttling
    credential-stuffing / brute-force attempts without any external dependency.

    In-process only: on a multi-worker deploy each worker keeps its own window,
    which still meaningfully slows an attacker. For a hard global limit put a
    reverse proxy / WAF in front — this is defence in depth, not the sole gate.
    """

    def __init__(self, max_attempts: int = 8, window_seconds: float = 300.0) -> None:
        self.max_attempts = max_attempts
        self.window_seconds = window_seconds
        self._history: dict[str, list[float]] = defaultdict(list)
        self._lock = threading.Lock()

    def check(self, key: str) -> tuple[bool, int | None]:
        """Return (allowed, retry_after_seconds). Records the attempt when allowed."""
        now = time.monotonic()
        with self._lock:
            times = [t for t in self._history[key] if now - t < self.window_seconds]
            if len(times) >= self.max_attempts:
                oldest = min(times)
                retry_after = int(self.window_seconds - (now - oldest)) + 1
                self._history[key] = times
                return False, max(retry_after, 1)
            times.append(now)
            self._history[key] = times
            return True, None

    def clear(self, key: str) -> None:
        """Forget a key's history — call on a *successful* login so a legitimate
        user who fat-fingered their password a few times isn't then locked out."""
        with self._lock:
            self._history.pop(key, None)

    def reset(self) -> None:
        with self._lock:
            self._history.clear()


# Process-wide limiter shared by the auth routes.
login_rate_limiter = FixedWindowRateLimiter(max_attempts=8, window_seconds=300.0)
