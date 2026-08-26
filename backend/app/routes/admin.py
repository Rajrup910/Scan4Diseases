"""Admin endpoint: promote a user to verified doctor role.

Protected by ADMIN_SECRET env var. Only active when ADMIN_SECRET is set.
Used for initial seeding of the cloud database.
"""

from __future__ import annotations

import hmac

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.config import Settings, get_settings
from backend.app.db.models import ROLE_DOCTOR, User
from backend.app.db.session import get_db
from backend.app.services import audit
from backend.app.services.rate_limiter import login_rate_limiter

router = APIRouter(prefix="/admin", tags=["admin"])


class PromoteRequest(BaseModel):
    email: EmailStr
    name: str | None = None
    reg_no: str | None = None


@router.post("/promote-doctor", status_code=200)
def promote_doctor(
    payload: PromoteRequest,
    request: Request,
    x_admin_secret: str = Header(..., alias="X-Admin-Secret"),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_settings),
) -> dict:
    """Promote a registered user to verified doctor role.

    Requires the X-Admin-Secret header to match the ADMIN_SECRET env var.
    Returns 403 if the secret is wrong or not set. Throttled per IP and
    compared in constant time so the secret can't be brute-forced or timed.
    """
    ip = audit.client_ip(request) or "unknown"
    allowed, retry_after = login_rate_limiter.check(f"admin-promote:{ip}")
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Too many attempts. Retry in ~{retry_after}s.",
        )

    admin_secret = getattr(settings, "admin_secret", None)
    # Constant-time compare; reject outright when the secret is unset.
    if not admin_secret or not hmac.compare_digest(x_admin_secret, admin_secret):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Invalid admin secret.")

    # Clear the throttle on a correct secret so ops isn't locked out mid-seeding.
    login_rate_limiter.clear(f"admin-promote:{ip}")

    email = payload.email.lower().strip()
    user = db.scalar(select(User).where(User.email == email))
    if user is None:
        raise HTTPException(status_code=404, detail=f"No user found with email {email!r}.")

    user.role = ROLE_DOCTOR
    user.is_verified = True
    if payload.name:
        user.display_name = payload.name
    if payload.reg_no:
        user.medical_reg_no = payload.reg_no

    db.commit()
    db.refresh(user)
    return {
        "ok": True,
        "id": user.id,
        "email": user.email,
        "role": user.role,
        "is_verified": user.is_verified,
        "display_name": user.display_name,
    }
