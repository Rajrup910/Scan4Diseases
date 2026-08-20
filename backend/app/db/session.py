"""Database engine and session management (SQLAlchemy 2.0, SQLite).

A single synchronous engine is created from the configured path. Route handlers
that touch the database are declared `def` (not `async def`) so FastAPI runs them
in its threadpool, which keeps the blocking SQLite and bcrypt work off the event
loop that serves inference and the LLM.

SQLite is intentional here: zero-config, single-file, git-ignored under
`backend/storage`. Swapping to Postgres later is a one-line URL change plus a
driver install -- nothing in the models or routes assumes SQLite.
"""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from backend.app.config import get_settings


class Base(DeclarativeBase):
    """Declarative base shared by every ORM model."""


def _build_engine():
    settings = get_settings()
    db_file = settings.database_file
    db_file.parent.mkdir(parents=True, exist_ok=True)
    # check_same_thread=False: FastAPI's threadpool may hand a session to a
    # different thread than the one that created it. Sessions are still used by
    # one request at a time, so this is safe.
    return create_engine(
        settings.database_url,
        connect_args={"check_same_thread": False},
        future=True,
    )


engine = _build_engine()

SessionLocal = sessionmaker(
    bind=engine,
    class_=Session,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
)


def init_db() -> None:
    """Create tables if they do not yet exist. Called once during startup."""
    # Import the models module so the mappers register on Base.metadata before
    # create_all runs. The import is local to avoid a circular import at module load.
    from backend.app.db import models  # noqa: F401

    Base.metadata.create_all(bind=engine)


def get_db() -> Iterator[Session]:
    """FastAPI dependency: yield a session and always close it."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
