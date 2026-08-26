"""Security hardening tests.

Covers the production-config guard, the response security headers + portal CSP,
the auth brute-force throttle, and the global body-size ceiling. These run in the
default (development) client so they never trip the production guard themselves.
"""

from __future__ import annotations

import pytest

from backend.app.config import Settings
from backend.app.services.rate_limiter import (
    FixedWindowRateLimiter,
    login_rate_limiter,
)


# --- production config guard ---------------------------------------------------

def test_production_issues_flags_fatal_defaults():
    # _env_file=None so a developer's local .env can't mask the source defaults.
    s = Settings(app_env="production", _env_file=None)
    issues = s.production_issues()
    joined = " ".join(issues).lower()
    # Fatal: forgeable JWT secret + debug on.
    assert any("jwt_secret" in i.lower() for i in issues)
    assert "debug" in joined


def test_committed_image_key_is_a_warning_not_fatal():
    # Rotating the image key orphans encrypted blobs, so it's a warning, not a
    # boot-blocking error.
    s = Settings(app_env="production", _env_file=None)
    assert any("image_encryption_key" in w.lower() for w in s.production_warnings())
    assert not any("image_encryption_key" in i.lower() for i in s.production_issues())


def test_production_issues_clean_when_hardened():
    s = Settings(
        app_env="production",
        _env_file=None,
        jwt_secret="x" * 48,
        debug=False,
        allow_stub_model=False,
    )
    # No FATAL issues once the JWT secret + debug are fixed.
    assert s.production_issues() == []


def test_development_config_is_not_forced_secure():
    # The guard only applies in production; dev keeps its convenient defaults.
    s = Settings(app_env="development", _env_file=None)
    assert s.is_production is False


# --- security headers + CSP ----------------------------------------------------

def test_security_headers_present_on_api(client):
    r = client.get("/health")
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert r.headers.get("X-Frame-Options") == "DENY"
    assert "Referrer-Policy" in r.headers
    assert "Permissions-Policy" in r.headers
    # HSTS is production-only; the dev client must NOT emit it.
    assert "Strict-Transport-Security" not in r.headers


def test_csp_only_on_portal_html(client):
    portal = client.get("/portal/login")
    assert "text/html" in portal.headers.get("content-type", "")
    assert "Content-Security-Policy" in portal.headers
    assert "frame-ancestors 'none'" in portal.headers["Content-Security-Policy"]

    # JSON API responses carry the other headers but no CSP.
    api = client.get("/health")
    assert "Content-Security-Policy" not in api.headers


# --- auth throttle -------------------------------------------------------------

def test_login_throttle_blocks_after_limit(client):
    login_rate_limiter.reset()
    payload = {"email": "nobody@example.com", "password": "wrongpassword"}
    codes = [client.post("/auth/login", json=payload).status_code for _ in range(12)]
    # First 8 are allowed through (and fail auth = 401); later ones are throttled.
    assert 401 in codes
    assert 429 in codes
    login_rate_limiter.reset()


def test_fixed_window_limiter_unit():
    lim = FixedWindowRateLimiter(max_attempts=3, window_seconds=60)
    assert lim.check("k")[0] is True
    assert lim.check("k")[0] is True
    assert lim.check("k")[0] is True
    allowed, retry = lim.check("k")
    assert allowed is False
    assert retry is not None and retry > 0
    # A different key has its own window.
    assert lim.check("other")[0] is True
    # Clearing frees the key again.
    lim.clear("k")
    assert lim.check("k")[0] is True


# --- body-size ceiling ---------------------------------------------------------

def test_oversized_body_rejected(client):
    # Declare a huge Content-Length; the middleware rejects before reading it.
    big = b"x" * (64 * 1024 * 1024)
    r = client.post(
        "/auth/login",
        content=big,
        headers={"Content-Type": "application/json", "Content-Length": str(len(big))},
    )
    assert r.status_code == 413
    assert r.json()["error"] == "payload_too_large"
