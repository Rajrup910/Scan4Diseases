"""Saved screening reports, scoped to the authenticated user.

Every route requires a valid token and only ever touches rows owned by that user,
so one account can never read or delete another's history.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.app.db.models import Report, User
from backend.app.db.session import get_db
from backend.app.dependencies import get_current_user
from backend.app.schemas.report import ReportCreate, ReportOut
from backend.app.utils.errors import AppError

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("", response_model=list[ReportOut])
def list_reports(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[Report]:
    rows = db.scalars(
        select(Report).where(Report.user_id == user.id).order_by(Report.created_at.desc())
    ).all()
    return list(rows)


@router.post("", response_model=ReportOut, status_code=status.HTTP_201_CREATED)
def create_report(
    payload: ReportCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Report:
    report = Report(
        user_id=user.id,
        condition=payload.condition,
        predicted_class=payload.predicted_class,
        confidence=payload.confidence,
        triage=payload.triage,
        explanation=payload.explanation,
        symptoms=payload.symptoms,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return report


@router.delete("/{report_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_report(
    report_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    report = db.get(Report, report_id)
    if report is None or report.user_id != user.id:
        raise AppError("not_found", "Report not found.", status_code=404)
    db.delete(report)
    db.commit()
