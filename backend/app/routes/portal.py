"""The doctor web portal: a server-rendered UI over the exact JSON endpoints in `doctor.py`.

Same origin, no client framework, no CDN (offline demo). Pages are Jinja2 templates styled
with a small local stylesheet; the two interactive actions -- setting a review status and
adding a note -- are plain HTML forms that POST and redirect (Post/Redirect/Get), so the
portal works with JavaScript disabled.

Authentication here is a short-lived, HttpOnly session **cookie** (not the Authorization
header the mobile client uses), because a browser follows plain links and cannot attach a
bearer token to them. The cookie carries the same JWT, signed with the same secret, but with
the shorter `portal_session_minutes` lifetime and scoped to the `/portal` path. Every
authorisation decision still funnels through `services.access` via the helpers in
`doctor.py`, so the web portal cannot see anything the JSON API would not also allow.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

import jwt
from fastapi import APIRouter, Depends, Form, Request, Response, status
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.app.config import Settings
from backend.app.db.models import (
    ACTOR_DOCTOR,
    APPT_CANCELLED,
    APPT_COMPLETED,
    APPT_CONFIRMED,
    APPT_DECLINED,
    APPT_LIVE_STATUSES,
    APPT_REQUESTED,
    LINK_ACTIVE,
    REPORT_ESCALATED,
    REPORT_NEW,
    REPORT_REVIEWED,
    REPORT_UNDER_REVIEW,
    ROLE_DOCTOR,
    Appointment,
    DoctorNote,
    DoctorPatient,
    Report,
    User,
)
from backend.app.db.session import get_db
from backend.app.dependencies import get_app_settings, get_image_vault, get_llm_service
from backend.app.safety.disclaimer import get_disclaimer, llm_unavailable_notice
from backend.app.schemas.chat import ChatMessage
from backend.app.schemas.common import Language
from backend.app.services.llm import LLMService
from backend.app.routes.doctor import (
    _active_link,
    _serve_shared_blob,
    _viewable_report_or_403,
)
from backend.app.schemas.doctor import NoteCreate, StatusUpdate
from backend.app.security import create_access_token, decode_token, verify_password
from backend.app.services import audit
from backend.app.services.image_vault import ImageVault
from backend.app.utils.errors import AppError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/portal", tags=["portal"], include_in_schema=False)

_TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "templates"
templates = Jinja2Templates(directory=str(_TEMPLATES_DIR))

PORTAL_COOKIE = "portal_session"

# The review workflow in display order (the frozenset in models.py is unordered). The status
# <select> and the badge colours both key off this list.
STATUS_ORDER = [REPORT_NEW, REPORT_UNDER_REVIEW, REPORT_REVIEWED, REPORT_ESCALATED]
STATUS_LABELS = {
    REPORT_NEW: "New",
    REPORT_UNDER_REVIEW: "Under review",
    REPORT_REVIEWED: "Reviewed",
    REPORT_ESCALATED: "Escalated",
}

# Appointment status → (human label, tone class used for badges/dots on the calendar).
APPT_STATUS_META = {
    APPT_REQUESTED: ("Awaiting approval", "pending"),
    APPT_CONFIRMED: ("Confirmed", "ok"),
    APPT_DECLINED: ("Declined", "muted"),
    APPT_CANCELLED: ("Cancelled", "muted"),
    APPT_COMPLETED: ("Completed", "info"),
}


def triage_tone(value: str | None) -> str:
    """Collapse a free-text triage label to one of three tones, matching the mobile app's
    substring logic (see `reportScreen.dart`): the stored value may be a short category
    (``"urgent"``) or a full label (``"Urgent medical evaluation"``)."""
    t = (value or "").lower()
    if "urgent" in t:
        return "urgent"
    if "prompt" in t or "soon" in t:
        return "soon"
    return "routine"


class PortalAuthRequired(Exception):
    """Raised when a portal page is reached without a valid doctor session. The registered
    handler turns it into a redirect to the login page rather than a JSON 401/403, because
    the caller is a browser, not the mobile API client."""


# --- session cookie ------------------------------------------------------------------

def _request_is_https(request: Request | None) -> bool:
    """Whether the browser reached us over HTTPS, honouring a terminating proxy.

    A reverse proxy (Render, nginx) terminates TLS and forwards the original
    scheme in `X-Forwarded-Proto`, so trust that first; fall back to the socket
    scheme for a direct connection."""
    if request is None:
        return False
    forwarded = request.headers.get("x-forwarded-proto", "")
    if forwarded:
        # May be a comma-separated list ("https, http"); the client-facing one is first.
        return forwarded.split(",")[0].strip().lower() == "https"
    return request.url.scheme == "https"


def _set_session_cookie(
    response: Response, settings: Settings, token: str, request: Request | None = None
) -> None:
    # The `Secure` flag must track the ACTUAL scheme the browser used, not the
    # app_env: a `Secure` cookie is silently discarded over plain HTTP, so tying
    # it to "production" meant a doctor opening the portal from another device
    # over http (a LAN IP, a tunnel) was accepted but never got a session and
    # bounced back to the login page. Over HTTPS it stays Secure; over HTTP the
    # cookie is set without Secure so the session actually persists.
    response.set_cookie(
        key=PORTAL_COOKIE,
        value=token,
        max_age=settings.portal_session_minutes * 60,
        httponly=True,  # not readable by page scripts
        samesite="lax",  # not sent on cross-site POSTs (basic CSRF defence for a demo)
        secure=_request_is_https(request),
        path="/portal",  # never sent to the JSON API paths
    )


def _clear_session_cookie(response: Response) -> None:
    response.delete_cookie(PORTAL_COOKIE, path="/portal")


def get_portal_doctor(
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> User:
    """Resolve the session cookie to a verified doctor, or raise `PortalAuthRequired`.

    Mirrors `get_current_doctor` exactly (role read from the DB row, verification required),
    but sources the token from the cookie and treats *every* failure the same way -- a
    redirect to login -- so the portal never leaks whether a session was missing, expired,
    or belonged to a non-doctor.
    """
    token = request.cookies.get(PORTAL_COOKIE)
    if not token:
        raise PortalAuthRequired
    try:
        payload = decode_token(settings, token)
    except jwt.PyJWTError as exc:
        raise PortalAuthRequired from exc
    subject = payload.get("sub")
    user = db.get(User, int(subject)) if subject is not None else None
    if user is None or user.role != ROLE_DOCTOR or not user.is_verified:
        raise PortalAuthRequired
    return user


def _current_doctor_or_none(
    request: Request, db: Session, settings: Settings
) -> User | None:
    """Non-raising variant, for the login page's "already signed in" check."""
    try:
        return get_portal_doctor(request, db, settings)
    except PortalAuthRequired:
        return None


# --- login / logout ------------------------------------------------------------------

@router.get("/login", response_class=HTMLResponse)
def login_form(
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> Response:
    if _current_doctor_or_none(request, db, settings) is not None:
        return RedirectResponse("/portal/patients", status_code=status.HTTP_303_SEE_OTHER)
    return templates.TemplateResponse(request, "login.html", {"error": None})


@router.post("/login", response_class=HTMLResponse)
def login_submit(
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> Response:
    # Brute-force throttle on the browser login form, keyed by socket IP.
    from backend.app.services.rate_limiter import login_rate_limiter
    _ip = audit.client_ip(request) or "unknown"
    _allowed, _retry = login_rate_limiter.check(f"portal-login:{_ip}")
    if not _allowed:
        msg = "Too many sign-in attempts. Please wait a few minutes and try again."
        if "application/json" in request.headers.get("accept", ""):
            return JSONResponse({"error": msg}, status_code=429)
        return templates.TemplateResponse(request, "login.html", {"error": msg}, status_code=429)

    email = email.lower().strip()
    user = db.scalar(select(User).where(User.email == email))

    def _reject(message: str, code: int) -> Response:
        # Re-render the form with a message; never reveal which of the checks failed beyond
        # what the doctor typed themselves. A rejected sign-in is recorded with actor_id NULL
        # (the caller never authenticated); the target is the account that was tried, if it
        # exists, so a run of failures against one account is visible in the log.
        audit.record(
            db, None, audit.ACTION_LOGIN_FAILURE,
            target_type=audit.TARGET_USER if user is not None else None,
            target_id=user.id if user is not None else None,
            ip=audit.client_ip(request),
        )
        return templates.TemplateResponse(
            request, "login.html", {"error": message}, status_code=code
        )

    if user is None or not verify_password(password, user.password_hash):
        if "application/json" in request.headers.get("accept", ""):
            audit.record(
                db, None, audit.ACTION_LOGIN_FAILURE,
                target_type=audit.TARGET_USER if user is not None else None,
                target_id=user.id if user is not None else None,
                ip=audit.client_ip(request),
            )
            return JSONResponse({"error": "Email or password is incorrect."}, status_code=status.HTTP_401_UNAUTHORIZED)
        return _reject("Email or password is incorrect.", status.HTTP_401_UNAUTHORIZED)
    if user.role != ROLE_DOCTOR:
        if "application/json" in request.headers.get("accept", ""):
            audit.record(
                db, None, audit.ACTION_LOGIN_FAILURE,
                target_type=audit.TARGET_USER,
                target_id=user.id,
                ip=audit.client_ip(request),
            )
            return JSONResponse({"error": "This portal is for verified doctors only."}, status_code=status.HTTP_403_FORBIDDEN)
        return _reject("This portal is for verified doctors only.", status.HTTP_403_FORBIDDEN)
    if not user.is_verified:
        if "application/json" in request.headers.get("accept", ""):
            audit.record(
                db, None, audit.ACTION_LOGIN_FAILURE,
                target_type=audit.TARGET_USER,
                target_id=user.id,
                ip=audit.client_ip(request),
            )
            return JSONResponse({"error": "Your doctor account is awaiting verification by an administrator."}, status_code=status.HTTP_403_FORBIDDEN)
        return _reject(
            "Your doctor account is awaiting verification by an administrator.",
            status.HTTP_403_FORBIDDEN,
        )

    # Clear the throttle window for this IP on a clean sign-in.
    login_rate_limiter.clear(f"portal-login:{_ip}")

    token = create_access_token(
        settings, str(user.id), expires_minutes=settings.portal_session_minutes
    )
    audit.record(
        db, user.id, audit.ACTION_LOGIN_SUCCESS,
        target_type=audit.TARGET_USER, target_id=user.id, ip=audit.client_ip(request),
    )
    if "application/json" in request.headers.get("accept", ""):
        json_resp = JSONResponse({"ok": True, "redirect": "/portal/patients"})
        _set_session_cookie(json_resp, settings, token, request)
        return json_resp

    response = RedirectResponse("/portal/patients", status_code=status.HTTP_303_SEE_OTHER)
    _set_session_cookie(response, settings, token, request)
    return response


@router.post("/logout")
def logout(
    request: Request,
    db: Session = Depends(get_db),
    settings: Settings = Depends(get_app_settings),
) -> Response:
    # Resolve the session (non-raising) only to attribute the logout in the audit log; an
    # already-expired/absent session still clears the cookie and redirects, just with a NULL
    # actor. Logging out is never blocked by a bad session.
    doctor = _current_doctor_or_none(request, db, settings)
    response = RedirectResponse("/portal/login", status_code=status.HTTP_303_SEE_OTHER)
    _clear_session_cookie(response)
    audit.record(
        db, doctor.id if doctor else None, audit.ACTION_LOGOUT,
        target_type=audit.TARGET_USER if doctor else None,
        target_id=doctor.id if doctor else None,
        ip=audit.client_ip(request),
    )
    return response


# --- pages ---------------------------------------------------------------------------

@router.get("/", include_in_schema=False)
def portal_root() -> Response:
    return RedirectResponse("/portal/patients", status_code=status.HTTP_303_SEE_OTHER)


@router.get("/patients", response_class=HTMLResponse)
def patients_page(
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """The doctor's worklist: every consented patient and how many reports they share.

    Uses the same query shape as the JSON `GET /doctor/patients`, kept here so the page can
    render the ORM rows without a round-trip through pydantic."""
    consented = (
        (DoctorPatient.patient_id == User.id)
        & (DoctorPatient.doctor_id == doctor.id)
        & (DoctorPatient.status == LINK_ACTIVE)
        & (DoctorPatient.consented_at.is_not(None))
    )

    shared = (
        select(Report.user_id, func.count(Report.id).label("n"))
        .where(Report.shared_at.is_not(None))
        .group_by(Report.user_id)
        .subquery()
    )
    rows = db.execute(
        select(User, func.coalesce(shared.c.n, 0))
        .join(DoctorPatient, consented)
        .join(shared, shared.c.user_id == User.id, isouter=True)
        .order_by(User.id)
    ).all()
    patients = [{"user": user, "count": int(count)} for user, count in rows]

    # Report-level aggregates for the worklist dashboard. Same access rule as everything
    # else: only shared reports belonging to a consented patient are ever counted.
    report_rows = db.execute(
        select(Report, User)
        .join(User, User.id == Report.user_id)
        .join(DoctorPatient, consented)
        .where(Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()

    triage_counts = {"urgent": 0, "soon": 0, "routine": 0}
    status_counts = {s: 0 for s in STATUS_ORDER}
    needs_attention: list[dict] = []
    for report, patient in report_rows:
        tone = triage_tone(report.triage)
        triage_counts[tone] += 1
        if report.status in status_counts:
            status_counts[report.status] += 1
        # "Needs attention": anything escalated, or an unreviewed urgent lesion.
        unreviewed = report.status in (REPORT_NEW, REPORT_UNDER_REVIEW)
        if report.status == REPORT_ESCALATED or (unreviewed and tone == "urgent"):
            needs_attention.append({"report": report, "patient": patient, "tone": tone})

    # Triage donut segments, using the pathLength=100 trick so lengths are plain percentages.
    total_reports = len(report_rows)
    donut_segments: list[dict] = []
    offset = 0.0
    for tone in ("urgent", "soon", "routine"):
        n = triage_counts[tone]
        if not n:
            continue
        pct = n / total_reports * 100 if total_reports else 0
        donut_segments.append({"tone": tone, "n": n, "pct": pct, "offset": offset})
        offset += pct

    stats = {
        "patients": len(patients),
        "reports": total_reports,
        "attention": len(needs_attention),
        "escalated": status_counts[REPORT_ESCALATED],
    }

    all_reports = [
        {
            "report": report,
            "patient": patient,
            "tone": triage_tone(report.triage),
            "date_str": report.created_at.strftime("%d %b %Y"),
            "confidence_pct": round(report.confidence * 100) if report.confidence is not None else None,
        }
        for report, patient in report_rows
    ]

    return templates.TemplateResponse(
        request,
        "patients.html",
        {
            "doctor": doctor,
            "patients": patients,
            "stats": stats,
            "triage_counts": triage_counts,
            "status_counts": status_counts,
            "donut_segments": donut_segments,
            "total_reports": total_reports,
            "needs_attention": needs_attention[:6],
            "recent": report_rows[:6],
            "all_reports": all_reports,
            "status_labels": STATUS_LABELS,
        },
    )


@router.get("/search")
def portal_search(
    request: Request,
    q: str = "",
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """Fast search endpoint for the Command Palette (Ctrl+K / Cmd+K)."""
    q_str = q.strip().lower()
    consented = (
        (DoctorPatient.patient_id == User.id)
        & (DoctorPatient.doctor_id == doctor.id)
        & (DoctorPatient.status == LINK_ACTIVE)
        & (DoctorPatient.consented_at.is_not(None))
    )

    patients = db.scalars(
        select(User)
        .join(DoctorPatient, consented)
        .order_by(User.display_name, User.email)
    ).all()

    report_rows = db.execute(
        select(Report, User)
        .join(User, User.id == Report.user_id)
        .join(DoctorPatient, consented)
        .where(Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()

    matching_patients = []
    for p in patients:
        name = p.display_name or ""
        email = p.email or ""
        if not q_str or q_str in name.lower() or q_str in email.lower():
            matching_patients.append({
                "id": p.id,
                "name": name or email.split("@")[0],
                "email": email,
                "url": f"/portal/patients/{p.id}",
            })

    matching_reports = []
    for r, p in report_rows:
        cond = r.condition or ""
        p_name = p.display_name or p.email
        triage = r.triage or ""
        status = STATUS_LABELS.get(r.status, r.status)
        if (
            not q_str
            or q_str in cond.lower()
            or q_str in p_name.lower()
            or q_str in triage.lower()
            or q_str in status.lower()
            or q_str == f"#{r.id}"
            or q_str == str(r.id)
        ):
            matching_reports.append({
                "id": r.id,
                "condition": cond,
                "patient": p_name,
                "confidence": round(r.confidence * 100) if r.confidence is not None else None,
                "triage": triage,
                "status": status,
                "tone": triage_tone(r.triage),
                "date": r.created_at.strftime("%d %b %Y"),
                "url": f"/portal/reports/{r.id}",
            })

    return JSONResponse({
        "patients": matching_patients[:10],
        "reports": matching_reports[:25],
    })


@router.get("/patients/{patient_id}", response_class=HTMLResponse)
def patient_reports_page(
    patient_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """One consented patient's shared reports. Requires an active link (else a friendly
    'no access' page, matching the JSON route's 404 without existence-probing)."""
    link = _active_link(db, doctor, patient_id)
    if link is None:
        return _access_denied(request, doctor, status.HTTP_404_NOT_FOUND)

    patient = db.get(User, patient_id)
    reports = db.scalars(
        select(Report)
        .where(Report.user_id == patient_id, Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()

    # Profile-hero stats — computed from the shared reports and the consent link.
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc)
    escalated = sum(1 for r in reports if r.status == REPORT_ESCALATED)
    linked_at = link.consented_at or link.created_at
    days_linked = None
    if linked_at is not None:
        la = linked_at if linked_at.tzinfo else linked_at.replace(tzinfo=timezone.utc)
        days_linked = max((now - la).days, 0)
    last_report = reports[0].created_at if reports else None
    days_since_last = None
    if last_report is not None:
        lr = last_report if last_report.tzinfo else last_report.replace(tzinfo=timezone.utc)
        days_since_last = max((now - lr).days, 0)

    profile = {
        "reports": len(reports),
        "escalated": escalated,
        "days_linked": days_linked,
        "days_since_last": days_since_last,
        "linked_at": linked_at,
    }

    # This patient's appointments with this doctor, surfaced right on the profile so
    # the doctor can see and act on visits without leaving the patient. Upcoming
    # (live) visits first, then anything already past/closed.
    appt_rows = db.scalars(
        select(Appointment)
        .where(
            Appointment.doctor_id == doctor.id,
            Appointment.patient_id == patient_id,
        )
        .order_by(Appointment.scheduled_for)
    ).all()
    appts_upcoming: list[dict] = []
    appts_past: list[dict] = []
    for a in appt_rows:
        view = _appt_view(db, a)
        if a.status in APPT_LIVE_STATUSES and not view["is_past"]:
            appts_upcoming.append(view)
        else:
            appts_past.append(view)
    appts_past.reverse()  # most-recent past first
    patient_appointments = {
        "upcoming": appts_upcoming,
        "past": appts_past,
        "count": len(appt_rows),
        "pending": sum(1 for a in appt_rows if a.status == APPT_REQUESTED),
    }

    return templates.TemplateResponse(
        request,
        "patient_reports.html",
        {
            "doctor": doctor,
            "patient": patient,
            "reports": reports,
            "profile": profile,
            "appointments": patient_appointments,
            "status_labels": STATUS_LABELS,
        },
    )


@router.get("/reports/{report_id}", response_class=HTMLResponse)
def report_detail_page(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """A single shared report in full: prediction, triage, questionnaire, images, the review
    status control and the doctor's notes. All access checks flow through the shared helper."""
    try:
        report = _viewable_report_or_403(db, doctor, report_id)
    except AppError as exc:
        return _access_denied(request, doctor, exc.status_code)

    audit.record(
        db, doctor.id, audit.ACTION_REPORT_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return templates.TemplateResponse(
        request,
        "report_detail.html",
        {
            "doctor": doctor,
            "report": report,
            "patient": report.user,
            "notes": sorted(report.notes, key=lambda n: n.created_at),
            "symptoms": report.symptoms or {},
            "status_order": STATUS_ORDER,
            "status_labels": STATUS_LABELS,
        },
    )


# --- AI assistant chat (JSON; themed chat panel on the report page) -------------------

class _PortalChatTurn(BaseModel):
    role: str = Field(pattern="^(user|assistant)$")
    content: str = Field(min_length=1, max_length=4000)


class _PortalChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    history: list[_PortalChatTurn] = Field(default_factory=list)


class _PortalCompareChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    # The compare panel lets the doctor pick as many reports as they like; the
    # earlier max_length=4 rejected any batch larger than four with a silent
    # 422. Bump to 12 so a full worklist still fits, and clamp on the server
    # side rather than in the schema.
    report_ids: list[int] = Field(min_length=2, max_length=12)
    history: list[_PortalChatTurn] = Field(default_factory=list)


@router.post("/reports/{report_id}/chat")
async def report_chat(
    report_id: int,
    request: Request,
    body: _PortalChatRequest,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    llm: LLMService = Depends(get_llm_service),
) -> Response:
    """Answer a clinician's follow-up question about one shared report.

    Reuses the existing safety-filtered [LLMService]; the model is the least-authoritative
    layer and only puts the already-decided result into words. Access is checked exactly
    like every other report route, so a doctor can only discuss reports shared with them."""
    try:
        report = _viewable_report_or_403(db, doctor, report_id)
    except AppError as exc:
        return JSONResponse({"available": False, "response": "", "error": "forbidden"}, status_code=exc.status_code)

    prediction = {
        "predicted_category_name": report.condition,
        "predicted_category": report.predicted_class or report.condition,
        "model_confidence_percent": round((report.confidence or 0) * 100),
        "safety_category_label": report.triage,
        "existing_explanation": report.explanation or "",
    }
    history = [ChatMessage(role=t.role, content=t.content) for t in body.history[-10:]]

    try:
        result = await llm.chat(
            message=body.message,
            history=history,
            prediction=prediction,
            symptoms=report.symptoms or {},
            language=Language.ENGLISH,
        )
        response_text = result.text or llm._clinical_fallback_response(
            body.message, prediction, report.symptoms or {}, Language.ENGLISH
        )
    except Exception as err:
        logger.warning("Error in report_chat: %s", err)
        response_text = llm._clinical_fallback_response(
            body.message, prediction, report.symptoms or {}, Language.ENGLISH
        )

    return JSONResponse(
        {
            "available": True,
            "response": response_text,
            "filtered": False,
            "disclaimer": get_disclaimer(Language.ENGLISH),
        }
    )


@router.post("/compare/chat")
async def compare_chat(
    request: Request,
    body: _PortalCompareChatRequest,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    llm: LLMService = Depends(get_llm_service),
) -> Response:
    """Answer a follow-up question that compares two or more reports.

    Access is enforced per report — a doctor can only ask about reports that were
    actually shared with them. The reports' predictions are folded into a single
    'compare' prediction dict which is handed to the standard chat pipeline, so
    the same guardrails and rate limits apply."""
    reports: list[Report] = []
    for report_id in body.report_ids:
        try:
            reports.append(_viewable_report_or_403(db, doctor, report_id))
        except AppError as exc:
            return JSONResponse(
                {"available": False, "response": "", "error": "forbidden"},
                status_code=exc.status_code,
            )

    def _snap(r: Report, tag: str) -> dict:
        return {
            "tag": tag,
            "report_id": r.id,
            "predicted_category_name": r.condition,
            "predicted_category": r.predicted_class or r.condition,
            "model_confidence_percent": round((r.confidence or 0) * 100),
            "safety_category_label": r.triage,
            "review_status": r.status,
            "reported_symptoms": r.symptoms or {},
        }

    # Any batch size up to the schema cap needs a tag — the previous fixed
    # list of four raised IndexError once the doctor picked five or more
    # reports, which is what surfaced as "I couldn't reach the assistant".
    def _tag(i: int) -> str:
        return "Report " + (chr(ord("A") + i) if i < 26 else str(i + 1))

    snapshots = [_snap(r, _tag(i)) for i, r in enumerate(reports)]
    prediction = {
        "mode": "compare",
        "reports": snapshots,
        "clinician_question": body.message,
    }

    # First report drives the language/symptoms context; the others land in the
    # prediction dict so the assistant sees the whole picture.
    lead = reports[0]
    history = [ChatMessage(role=t.role, content=t.content) for t in body.history[-10:]]

    guided = (
        "This question is about a side-by-side comparison of the reports listed in "
        "the prediction context. Answer with concrete numbers (confidence delta, "
        "triage agreement) and refer to each report by its tag (Report A, B, ...). "
        "Do not restate a diagnosis for either lesion — only compare what the model "
        "and the safety layer already said.\n\nClinician's question: "
        + body.message
    )

    try:
        result = await llm.chat(
            message=guided,
            history=history,
            prediction=prediction,
            symptoms=lead.symptoms or {},
            language=Language.ENGLISH,
        )
        response_text = result.text or llm._clinical_fallback_response(
            body.message, prediction, lead.symptoms or {}, Language.ENGLISH
        )
    except Exception as err:
        logger.warning("Error in compare_chat: %s", err)
        response_text = llm._clinical_fallback_response(
            body.message, prediction, lead.symptoms or {}, Language.ENGLISH
        )

    return JSONResponse(
        {
            "available": True,
            "response": response_text,
            "report_ids": [r.id for r in reports],
            "disclaimer": get_disclaimer(Language.ENGLISH),
        }
    )



# --- appointments (calendar page + summary widget + doctor actions) ------------------

def _aware(dt: datetime) -> datetime:
    """SQLite drops tzinfo on read; treat a naive stored time as the UTC we wrote."""
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


def _as_local(dt: datetime) -> datetime:
    """Render a stored (UTC-aware) time in the server's local zone for display."""
    return _aware(dt).astimezone()


def _appt_view(db: Session, a: Appointment) -> dict:
    """A JSON-able summary of one appointment for the calendar grid and agenda list.

    Times are pre-formatted server-side in local time so the client never has to guess a
    timezone; `date_key` buckets the appointment into a calendar cell."""
    local = _as_local(a.scheduled_for)
    label, tone = APPT_STATUS_META.get(a.status, (a.status.title(), "muted"))
    patient = a.patient or db.get(User, a.patient_id)
    p_name = (patient.display_name or patient.email) if patient else "Patient"
    condition = None
    if a.report_id is not None:
        report = a.report or db.get(Report, a.report_id)
        condition = report.condition if report is not None else None
    return {
        "id": a.id,
        "patient_id": a.patient_id,
        "patient_name": p_name,
        "report_id": a.report_id,
        "condition": condition,
        "status": a.status,
        "status_label": label,
        "tone": tone,
        "created_by": a.created_by,
        "reason": a.reason or "",
        "date_key": local.strftime("%Y-%m-%d"),
        "time_label": local.strftime("%H:%M"),
        "day_label": local.strftime("%a %d %b"),
        "duration": a.duration_minutes,
        "is_past": _aware(a.scheduled_for) < datetime.now(timezone.utc),
    }


def _doctor_appointment_or_404(db: Session, doctor: User, appt_id: int) -> Appointment:
    a = db.get(Appointment, appt_id)
    if a is None or a.doctor_id != doctor.id:
        raise AppError("not_found", "Appointment not found.", status_code=404)
    return a


def _consented_patients(db: Session, doctor: User) -> list[User]:
    consented = (
        (DoctorPatient.patient_id == User.id)
        & (DoctorPatient.doctor_id == doctor.id)
        & (DoctorPatient.status == LINK_ACTIVE)
        & (DoctorPatient.consented_at.is_not(None))
    )
    return list(
        db.scalars(
            select(User).join(DoctorPatient, consented).order_by(User.display_name, User.email)
        ).all()
    )


@router.get("/appointments", response_class=HTMLResponse)
def appointments_page(
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """The doctor's appointment calendar: every booked visit mapped onto a month grid, with a
    slide-in summary widget (built client-side) for the one they click. Requests awaiting
    approval are surfaced up top so the approval flow is one glance away."""
    rows = db.scalars(
        select(Appointment)
        .where(Appointment.doctor_id == doctor.id)
        .order_by(Appointment.scheduled_for)
    ).all()
    views = [_appt_view(db, a) for a in rows]

    now = datetime.now(timezone.utc)
    awaiting = [v for v, a in zip(views, rows) if a.status == APPT_REQUESTED]
    upcoming_confirmed = [
        v for v, a in zip(views, rows)
        if a.status == APPT_CONFIRMED and _aware(a.scheduled_for) >= now
    ]
    cancelled = [v for v, a in zip(views, rows) if a.status in ("cancelled", "declined")]
    # Agenda rail: the next things needing eyes — pending requests first, then upcoming.
    agenda = awaiting + upcoming_confirmed

    stats = {
        "awaiting": len(awaiting),
        "upcoming": len(upcoming_confirmed),
        "cancelled": len(cancelled),
        "total": len(views),
    }

    return templates.TemplateResponse(
        request,
        "appointments.html",
        {
            "doctor": doctor,
            "appointments": views,
            "agenda": agenda,
            "stats": stats,
            "patients": _consented_patients(db, doctor),
            "today_key": _as_local(now).strftime("%Y-%m-%d"),
        },
    )


@router.get("/appointments/{appointment_id}/summary")
def appointment_summary(
    appointment_id: int,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """JSON powering the slide-in summary widget: the visit, the patient, and every case
    (shared report) linked to that patient — the one attached to this visit marked."""
    a = _doctor_appointment_or_404(db, doctor, appointment_id)
    patient = a.patient or db.get(User, a.patient_id)
    local = _as_local(a.scheduled_for)
    label, tone = APPT_STATUS_META.get(a.status, (a.status.title(), "muted"))

    reports = db.scalars(
        select(Report)
        .where(Report.user_id == a.patient_id, Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()
    cases = [
        {
            "id": r.id,
            "condition": r.condition,
            "triage": r.triage,
            "tone": triage_tone(r.triage),
            "status": STATUS_LABELS.get(r.status, r.status),
            "confidence": round(r.confidence * 100) if r.confidence is not None else None,
            "date": _as_local(r.created_at).strftime("%d %b %Y"),
            "url": f"/portal/reports/{r.id}",
            "linked": (r.id == a.report_id),
        }
        for r in reports
    ]
    escalated = sum(1 for r in reports if r.status == REPORT_ESCALATED)

    return JSONResponse(
        {
            "appointment": {
                "id": a.id,
                "status": a.status,
                "status_label": label,
                "tone": tone,
                "created_by": a.created_by,
                "date_label": local.strftime("%A, %d %B %Y"),
                "time_label": local.strftime("%H:%M"),
                "duration": a.duration_minutes,
                "reason": a.reason or "",
                "cancel_reason": a.cancel_reason or "",
                "cancelled_by": a.cancelled_by,
                "report_id": a.report_id,
                "can_approve": a.status == APPT_REQUESTED,
                "can_decline": a.status == APPT_REQUESTED,
                # A pending request is closed with Decline; only a confirmed visit is Cancelled.
                "can_cancel": a.status == APPT_CONFIRMED,
                "is_past": _aware(a.scheduled_for) < datetime.now(timezone.utc),
            },
            "patient": {
                "id": a.patient_id,
                "name": (patient.display_name or patient.email) if patient else "Patient",
                "email": patient.email if patient else "",
                "url": f"/portal/patients/{a.patient_id}",
                "report_count": len(reports),
                "escalated": escalated,
            },
            "cases": cases,
        }
    )


def _back_to_appointments(flash: str | None = None, hl: int | None = None, redirect_to: str | None = None) -> RedirectResponse:
    url = redirect_to if (redirect_to and redirect_to.startswith("/portal")) else "/portal/appointments"
    params = []
    if flash:
        params.append(f"flash={flash}")
    if hl is not None:
        params.append(f"hl={hl}")
    if params:
        sep = "&" if "?" in url else "?"
        url += sep + "&".join(params)
    return RedirectResponse(url, status_code=status.HTTP_303_SEE_OTHER)


@router.post("/appointments/{appointment_id}/approve")
def approve_appointment(
    appointment_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """Approve a patient's booking request → confirmed, and flag it unread so the patient's
    app shows 'your doctor approved this visit'."""
    a = _doctor_appointment_or_404(db, doctor, appointment_id)
    if a.status != APPT_REQUESTED:
        return _back_to_appointments(hl=a.id)
    a.status = APPT_CONFIRMED
    a.unread_for_patient = True
    db.commit()
    audit.record(
        db, doctor.id, audit.ACTION_APPT_APPROVE,
        target_type=audit.TARGET_APPOINTMENT, target_id=a.id, ip=audit.client_ip(request),
    )
    return _back_to_appointments(flash="approved", hl=a.id)


@router.post("/appointments/{appointment_id}/decline")
def decline_appointment(
    appointment_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    reason: str = Form(default=""),
) -> Response:
    """Decline a booking request → declined, with an optional reason the patient will see."""
    a = _doctor_appointment_or_404(db, doctor, appointment_id)
    if a.status != APPT_REQUESTED:
        return _back_to_appointments(hl=a.id)
    a.status = APPT_DECLINED
    a.cancelled_by = ACTOR_DOCTOR
    a.cancel_reason = (reason or "").strip() or None
    a.unread_for_patient = True
    db.commit()
    audit.record(
        db, doctor.id, audit.ACTION_APPT_DECLINE,
        target_type=audit.TARGET_APPOINTMENT, target_id=a.id, ip=audit.client_ip(request),
    )
    return _back_to_appointments(flash="declined", hl=a.id)


@router.post("/appointments/{appointment_id}/cancel")
def cancel_appointment_portal(
    appointment_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    reason: str = Form(default=""),
) -> Response:
    """Cancel a live appointment and notify the patient — the cancel reason and the unread
    flag are what the patient's app surfaces as 'your doctor cancelled this visit'."""
    a = _doctor_appointment_or_404(db, doctor, appointment_id)
    if a.status not in APPT_LIVE_STATUSES:
        return _back_to_appointments(hl=a.id)
    a.status = APPT_CANCELLED
    a.cancelled_by = ACTOR_DOCTOR
    a.cancel_reason = (reason or "").strip() or None
    a.unread_for_patient = True
    db.commit()
    audit.record(
        db, doctor.id, audit.ACTION_APPT_CANCEL,
        target_type=audit.TARGET_APPOINTMENT, target_id=a.id, ip=audit.client_ip(request),
    )
    return _back_to_appointments(flash="cancelled", hl=a.id)


@router.post("/appointments/recommend")
def recommend_appointment(
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    patient_id: int = Form(...),
    scheduled_for: str = Form(...),
    duration_minutes: int = Form(default=30),
    reason: str = Form(default=""),
    report_id: str = Form(default=""),
    redirect_to: str = Form(default=""),
) -> Response:
    """The doctor recommends a visit to a consented patient. Created already confirmed (a
    recommendation is an offer of a slot) and flagged unread so it lands in the patient's app.
    A tampered/invalid form value is ignored rather than 500 — the page just reloads."""
    # The patient must be one who has consented to this doctor.
    link = _active_link(db, doctor, patient_id)
    if link is None:
        return _back_to_appointments(redirect_to=redirect_to)

    try:
        # datetime-local sends "YYYY-MM-DDTHH:MM" (naive, local). astimezone() on a naive
        # value assumes the server's local zone; converting to UTC gives what we store.
        when = datetime.fromisoformat(scheduled_for).astimezone(timezone.utc)
    except (ValueError, TypeError):
        return _back_to_appointments(redirect_to=redirect_to)

    dur = max(10, min(180, int(duration_minutes or 30)))

    linked_report_id: int | None = None
    rid = (report_id or "").strip()
    if rid.isdigit():
        report = db.get(Report, int(rid))
        # Only link a report that belongs to this patient and is shared.
        if report is not None and report.user_id == patient_id and report.shared_at is not None:
            linked_report_id = report.id

    a = Appointment(
        doctor_id=doctor.id,
        patient_id=patient_id,
        report_id=linked_report_id,
        scheduled_for=when,
        duration_minutes=dur,
        reason=(reason or "").strip(),
        status=APPT_CONFIRMED,
        created_by=ACTOR_DOCTOR,
        unread_for_patient=True,
    )
    db.add(a)
    db.commit()
    audit.record(
        db, doctor.id, audit.ACTION_APPT_RECOMMEND,
        target_type=audit.TARGET_APPOINTMENT, target_id=a.id, ip=audit.client_ip(request),
    )
    return _back_to_appointments(flash="recommended", hl=a.id, redirect_to=redirect_to)


# --- mutations (form POST -> redirect back) ------------------------------------------

@router.post("/reports/{report_id}/status")
def update_status(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    new_status: str = Form(..., alias="status"),
) -> Response:
    """Set the review status from the detail-page dropdown, then redirect back to it."""
    report = _viewable_report_or_403(db, doctor, report_id)
    try:
        validated = StatusUpdate(status=new_status)
    except ValueError:
        # A tampered form value: ignore it rather than 500, and return to the page. Nothing
        # changed, so nothing is audited.
        return _back_to_report(report_id)
    report.status = validated.status
    db.commit()
    audit.record(
        db, doctor.id, audit.ACTION_STATUS_CHANGE,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return _back_to_report(report_id)


@router.post("/reports/{report_id}/notes")
def add_note(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    note: str = Form(...),
) -> Response:
    """Append a clinician note from the detail-page form, then redirect back to it."""
    report = _viewable_report_or_403(db, doctor, report_id)
    text = note.strip()
    if text:  # an empty submission simply returns without creating a blank note
        try:
            validated = NoteCreate(note=text)
        except ValueError:
            return _back_to_report(report_id)
        db.add(DoctorNote(report_id=report.id, doctor_id=doctor.id, note=validated.note))
        db.commit()
        audit.record(
            db, doctor.id, audit.ACTION_NOTE_ADD,
            target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
        )
    return _back_to_report(report_id)


# --- authenticated image serving -----------------------------------------------------

@router.get("/reports/{report_id}/image")
def report_image(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
) -> Response:
    """Stream the decrypted lesion image for an `<img>` tag on the detail page. Gated by the
    same access rule as everything else; the session cookie (path=/portal) authorises it."""
    report = _viewable_report_or_403(db, doctor, report_id)
    response = _serve_shared_blob(vault, report.image_path)
    audit.record(
        db, doctor.id, audit.ACTION_IMAGE_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return response


@router.get("/reports/{report_id}/gradcam")
def report_gradcam(
    report_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
    vault: ImageVault = Depends(get_image_vault),
) -> Response:
    report = _viewable_report_or_403(db, doctor, report_id)
    response = _serve_shared_blob(vault, report.gradcam_path)
    audit.record(
        db, doctor.id, audit.ACTION_GRADCAM_VIEW,
        target_type=audit.TARGET_REPORT, target_id=report.id, ip=audit.client_ip(request),
    )
    return response


# --- helpers -------------------------------------------------------------------------

def _back_to_report(report_id: int) -> RedirectResponse:
    return RedirectResponse(
        f"/portal/reports/{report_id}", status_code=status.HTTP_303_SEE_OTHER
    )


def _access_denied(request: Request, doctor: User, code: int) -> Response:
    """Render the friendly 'no access' page. A forbidden report and a non-existent one both
    land here, so the portal reveals no more than the JSON API does."""
    return templates.TemplateResponse(
        request, "no_access.html", {"doctor": doctor}, status_code=code
    )
