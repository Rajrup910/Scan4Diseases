"""Uniform error handling.

Master specification, sections 22 and 30: never silently fail, and never leak filesystem
paths, secrets, internal state or stack traces to the client. Every error the client sees
has a stable machine-readable `error` code and a `message` that is safe to display.

Unexpected exceptions are logged in full server-side and reduced to a generic message on
the way out.
"""

from __future__ import annotations

import logging
import uuid

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from starlette.exceptions import HTTPException as StarletteHTTPException

from backend.app.schemas.common import ErrorResponse

logger = logging.getLogger(__name__)

# Starlette renamed HTTP_422_UNPROCESSABLE_ENTITY to ..._CONTENT and deprecated the old
# name. Using the plain integer keeps this working across versions without a warning.
HTTP_422_UNPROCESSABLE = 422


class AppError(Exception):
    """An error with a client-safe message."""

    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = status.HTTP_400_BAD_REQUEST,
        detail: str | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.detail = detail


def error_response(
    code: str, message: str, status_code: int, detail: str | None = None
) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content=jsonable_encoder(ErrorResponse(error=code, message=message, detail=detail)),
    )


from pathlib import Path
from starlette.templating import Jinja2Templates

def register_exception_handlers(app: FastAPI) -> None:
    templates_dir = Path(__file__).resolve().parent.parent / "templates"
    templates = Jinja2Templates(directory=str(templates_dir))

    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError) -> Response:
        logger.info("AppError %s: %s", exc.code, exc.message)
        if exc.status_code == 404 and "text/html" in request.headers.get("accept", ""):
            return templates.TemplateResponse(request, "404.html", {}, status_code=404)
        return error_response(exc.code, exc.message, exc.status_code, exc.detail)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_request: Request, exc: RequestValidationError) -> JSONResponse:
        # Report which fields were wrong, but not the submitted values -- those could
        # contain user data we have no reason to echo back.
        fields = []
        for error in exc.errors():
            location = ".".join(str(part) for part in error["loc"] if part != "body")
            fields.append(f"{location}: {error['msg']}" if location else error["msg"])

        return error_response(
            "invalid_request",
            "Some of the submitted information was not valid. Please check and try again.",
            HTTP_422_UNPROCESSABLE,
            detail="; ".join(fields[:5]) or None,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException) -> Response:
        if exc.status_code == 404 and "text/html" in request.headers.get("accept", ""):
            return templates.TemplateResponse(request, "404.html", {}, status_code=404)
        codes = {
            404: ("not_found", "The requested resource was not found."),
            405: ("method_not_allowed", "That operation is not supported here."),
            413: ("payload_too_large", "The uploaded file is too large."),
        }
        code, message = codes.get(
            exc.status_code, ("request_failed", str(exc.detail) or "The request could not be completed.")
        )
        return error_response(code, message, exc.status_code)

    @app.exception_handler(Exception)
    async def _unhandled(_request: Request, exc: Exception) -> JSONResponse:
        # Correlate the user-facing message with the server log without exposing anything.
        incident = uuid.uuid4().hex[:12]
        logger.exception("Unhandled error [%s]: %s", incident, exc)
        return error_response(
            "internal_error",
            "Something went wrong while processing your request. Please try again.",
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"reference: {incident}",
        )


def configure_logging(debug: bool) -> None:
    logging.basicConfig(
        level=logging.DEBUG if debug else logging.INFO,
        format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
    )
    # These log every request line; useful in debug, noise otherwise.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("PIL").setLevel(logging.WARNING)
