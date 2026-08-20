"""Password hashing (bcrypt) and JWT issuing / verification.

bcrypt is used directly rather than through passlib: recent bcrypt releases broke
passlib's version probing, and we only need two calls. JWTs are signed with the
HS256 secret from settings; keep that secret out of the client and out of git.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt

from backend.app.config import Settings

# bcrypt hashes at most the first 72 bytes of a password. Callers cap length at
# the schema layer; truncating here as well keeps a stray long password from
# raising instead of simply being bounded.
_BCRYPT_MAX_BYTES = 72


def _clip(password: str) -> bytes:
    return password.encode("utf-8")[:_BCRYPT_MAX_BYTES]


def hash_password(password: str) -> str:
    return bcrypt.hashpw(_clip(password), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(_clip(password), password_hash.encode("utf-8"))
    except ValueError:
        # Malformed stored hash -- treat as a failed match, never a crash.
        return False


def create_access_token(settings: Settings, subject: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=settings.jwt_expire_minutes)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_token(settings: Settings, token: str) -> dict:
    """Decode and validate a token. Raises jwt.PyJWTError subclasses on failure."""
    return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
