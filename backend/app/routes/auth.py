"""Authentication routes: register, login, and the current user.

These handlers are synchronous (`def`), so FastAPI runs them in its threadpool.
That is deliberate: bcrypt hashing and SQLite access both block, and the pool
keeps them off the event loop that serves inference and the LLM.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.config import Settings
from backend.app.db.models import User
from backend.app.db.session import get_db
from backend.app.dependencies import get_app_settings, get_current_user
from backend.app.schemas.auth import LoginRequest, Token, UserCreate, UserOut
from backend.app.security import create_access_token, hash_password, verify_password
from backend.app.services import audit
from backend.app.services.rate_limiter import login_rate_limiter
from backend.app.utils.errors import AppError

router = APIRouter(prefix="/auth", tags=["auth"])


def _throttle(request: Request, purpose: str) -> None:
    """Raise 429 if this client IP has made too many auth attempts recently.
    Keyed by socket IP (never a spoofable forwarded header) + purpose."""
    ip = audit.client_ip(request) or "unknown"
    allowed, retry_after = login_rate_limiter.check(f"{purpose}:{ip}")
    if not allowed:
        raise AppError(
            "too_many_attempts",
            "Too many attempts. Please wait a few minutes and try again.",
            status_code=429,
            detail=f"retry after ~{retry_after}s",
        )


@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
def register(
    payload: UserCreate,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> Token:
    _throttle(request, "register")
    email = payload.email.lower().strip()
    if db.scalar(select(User).where(User.email == email)) is not None:
        raise AppError("email_taken", "An account with this email already exists.", status_code=409)

    display_name = payload.display_name.strip() if payload.display_name else None
    user = User(
        email=email,
        display_name=display_name or None,
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token(settings, str(user.id))
    return Token(access_token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=Token)
def login(
    payload: LoginRequest,
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> Token:
    _throttle(request, "login")
    email = payload.email.lower().strip()
    user = db.scalar(select(User).where(User.email == email))
    # Verify a hash even when the user is missing would be ideal to equalise timing;
    # for this app the simpler branch is acceptable and the message stays generic.
    if user is None or not verify_password(payload.password, user.password_hash):
        raise AppError("invalid_credentials", "Email or password is incorrect.", status_code=401)

    # Successful login clears this IP's throttle window so a legitimate user who
    # mistyped a few times isn't then locked out.
    ip = audit.client_ip(request) or "unknown"
    login_rate_limiter.clear(f"login:{ip}")

    token = create_access_token(settings, str(user.id))
    return Token(access_token=token, user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)) -> UserOut:
    return UserOut.model_validate(user)
