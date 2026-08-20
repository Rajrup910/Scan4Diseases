"""FastAPI dependencies.

Services live on `app.state`, created once during the lifespan, so every request reuses
the loaded model and the single HTTP client rather than building its own.
"""

from __future__ import annotations

import jwt
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from backend.app.config import Settings, get_settings
from backend.app.db.models import User
from backend.app.db.session import get_db
from backend.app.security import decode_token
from backend.app.services.inference import InferenceService
from backend.app.services.llm import LLMService
from backend.app.services.storage import TemporaryStore
from backend.app.utils.errors import AppError

# auto_error=False so a missing/invalid header produces our uniform 401 via AppError
# instead of Starlette's default, which would bypass the app's error shape.
_bearer = HTTPBearer(auto_error=False)


def get_inference_service(request: Request) -> InferenceService:
    return request.app.state.inference


def get_llm_service(request: Request) -> LLMService:
    return request.app.state.llm


def get_store(request: Request) -> TemporaryStore:
    return request.app.state.store


def get_ood(request: Request):
    """The fitted Mahalanobis OOD detector, or None when disabled/unfitted."""
    return request.app.state.ood


def get_lesion_gate(request: Request):
    """The fitted binary lesion-presence gate, or None when disabled/unfitted."""
    return request.app.state.lesion_gate


def get_lesion_router(request: Request):
    """The fitted multi-class front-stage router, or None when disabled/unfitted."""
    return request.app.state.lesion_router


def get_app_settings() -> Settings:
    return get_settings()


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    """Resolve the bearer token to a User, or raise a client-safe 401."""
    settings = get_settings()
    if credentials is None or not credentials.credentials:
        raise AppError("not_authenticated", "Please sign in to continue.", status_code=401)
    try:
        payload = decode_token(settings, credentials.credentials)
    except jwt.ExpiredSignatureError as exc:
        raise AppError(
            "token_expired", "Your session has expired. Please sign in again.", status_code=401
        ) from exc
    except jwt.PyJWTError as exc:
        raise AppError(
            "invalid_token", "Your session is invalid. Please sign in again.", status_code=401
        ) from exc

    subject = payload.get("sub")
    user = db.get(User, int(subject)) if subject is not None else None
    if user is None:
        raise AppError("not_authenticated", "Please sign in to continue.", status_code=401)
    return user
