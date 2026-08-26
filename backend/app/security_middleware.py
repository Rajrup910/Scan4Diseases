"""HTTP hardening middleware for production.

Two concerns, both defence-in-depth on top of the per-route logic:

1. `SecurityHeadersMiddleware` stamps a conservative set of security headers on
   every response — clickjacking, MIME-sniffing, referrer-leak and transport
   protections — plus a Content-Security-Policy on the server-rendered portal
   HTML (every portal asset is same-origin, so the policy can be tight). The API
   docs (`/docs`, `/redoc`) load Swagger/ReDoc from a CDN, so the CSP is scoped
   to portal HTML and never applied to those pages.

2. `MaxBodySizeMiddleware` rejects a request whose declared `Content-Length`
   exceeds a hard ceiling before the body is read, so an oversized upload cannot
   exhaust memory. The image-quality gate already caps lesion uploads; this is a
   blanket backstop for every other endpoint.
"""

from __future__ import annotations

import logging

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

logger = logging.getLogger(__name__)

# Content-Security-Policy for the server-rendered portal. Every asset (CSS, JS,
# fonts, media, images) is served from the same origin, so the only concession
# is 'unsafe-inline' for the pre-paint theme script and the inline style
# attributes / onerror handlers the templates use. That still blocks injected
# external scripts, framing, and form-hijacking.
_PORTAL_CSP = (
    "default-src 'self'; "
    "script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; "
    "media-src 'self'; "
    "font-src 'self'; "
    "connect-src 'self'; "
    "object-src 'none'; "
    "base-uri 'self'; "
    "form-action 'self'; "
    "frame-ancestors 'none'"
)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Adds security headers to every response. HSTS is only emitted in
    production (over HTTPS) so it never poisons a local http:// session."""

    def __init__(self, app, *, production: bool = False) -> None:
        super().__init__(app)
        self._production = production

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)

        # Applies everywhere, cheap, never breaks a legitimate client.
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        response.headers.setdefault(
            "Permissions-Policy",
            "camera=(), microphone=(), geolocation=(), interest-cohort=()",
        )
        response.headers.setdefault("Cross-Origin-Opener-Policy", "same-origin")

        # Only lock transport in production — a local http demo must stay usable.
        if self._production:
            response.headers.setdefault(
                "Strict-Transport-Security",
                "max-age=31536000; includeSubDomains",
            )

        # CSP only on portal HTML: /docs and /redoc need CDN scripts, and the
        # JSON API returns no markup to protect.
        path = request.url.path
        is_portal_html = (
            path.startswith("/portal")
            and not path.startswith("/portal/static")
            and "text/html" in response.headers.get("content-type", "")
        )
        if is_portal_html:
            response.headers.setdefault("Content-Security-Policy", _PORTAL_CSP)

        return response


class MaxBodySizeMiddleware(BaseHTTPMiddleware):
    """Reject a request whose Content-Length header exceeds `max_bytes` before
    the body is read. A chunked request without a length still streams to the
    route, where per-route limits (e.g. the image quality gate) apply."""

    def __init__(self, app, *, max_bytes: int) -> None:
        super().__init__(app)
        self._max_bytes = max_bytes

    async def dispatch(self, request: Request, call_next) -> Response:
        raw_length = request.headers.get("content-length")
        if raw_length is not None:
            try:
                declared = int(raw_length)
            except ValueError:
                declared = None
            if declared is not None and declared > self._max_bytes:
                logger.warning(
                    "Rejected oversized request: %d bytes > %d cap (%s %s)",
                    declared, self._max_bytes, request.method, request.url.path,
                )
                return JSONResponse(
                    status_code=413,
                    content={
                        "error": "payload_too_large",
                        "message": "The uploaded content is too large.",
                        "detail": None,
                    },
                )
        return await call_next(request)
