"""ORM models: users and the screening reports they save.

Only report *metadata* is stored server-side -- never the lesion image. The photo
stays on the user's device (see the mobile app), which keeps the most sensitive
data off the server and matches the app's privacy stance.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import JSON

from backend.app.db.session import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False
    )

    reports: Mapped[list["Report"]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    condition: Mapped[str] = mapped_column(String(120), nullable=False)
    predicted_class: Mapped[str | None] = mapped_column(String(120), nullable=True)
    confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    triage: Mapped[str] = mapped_column(String(120), nullable=False)
    explanation: Mapped[str] = mapped_column(Text, nullable=False, default="")
    # The structured questionnaire, stored verbatim as JSON.
    symptoms: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=_utcnow, nullable=False, index=True
    )

    user: Mapped["User"] = relationship(back_populates="reports")
