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

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from backend.app.config import get_settings


class Base(DeclarativeBase):
    """Declarative base shared by every ORM model."""


def _build_engine():
    settings = get_settings()
    db_file = settings.database_file
    db_file.parent.mkdir(parents=True, exist_ok=True)
    is_sqlite = settings.database_url.startswith("sqlite")
    connect_args = {"check_same_thread": False, "timeout": 30.0} if is_sqlite else {}
    # A small bounded connection pool. FastAPI runs the sync DB handlers in its
    # threadpool, so several requests can want a connection at once; QueuePool
    # (the default for a file-backed SQLite URL) hands them out and recycles
    # them. pool_pre_ping drops any connection that has gone stale before it is
    # reused, and pool_recycle caps connection age so long-lived workers do not
    # accumulate half-dead handles under sustained traffic.
    pool_kwargs = (
        {"pool_size": 10, "max_overflow": 20, "pool_recycle": 1800}
        if is_sqlite
        else {}
    )
    eng = create_engine(
        settings.database_url,
        connect_args=connect_args,
        pool_pre_ping=True,
        future=True,
        **pool_kwargs,
    )
    if is_sqlite:
        @event.listens_for(eng, "connect")
        def set_sqlite_pragma(dbapi_connection, connection_record):
            cursor = dbapi_connection.cursor()
            # WAL lets readers run concurrently with a single writer, which is
            # what a read-heavy portal + screening workload needs.
            cursor.execute("PRAGMA journal_mode=WAL")
            # NORMAL is durable under WAL and much faster than FULL.
            cursor.execute("PRAGMA synchronous=NORMAL")
            # Under WAL, concurrent writers still serialise; without a busy
            # timeout the second writer fails immediately with "database is
            # locked". Wait up to 30s (matching the connect timeout) so bursts
            # of writes queue gracefully instead of erroring under load.
            cursor.execute("PRAGMA busy_timeout=30000")
            # Enforce declared foreign keys (off by default in SQLite).
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()
    return eng


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
