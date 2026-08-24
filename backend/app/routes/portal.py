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
    LINK_ACTIVE,
    REPORT_ESCALATED,
    REPORT_NEW,
    REPORT_REVIEWED,
    REPORT_UNDER_REVIEW,
    ROLE_DOCTOR,
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

def _set_session_cookie(response: Response, settings: Settings, token: str) -> None:
    response.set_cookie(
        key=PORTAL_COOKIE,
        value=token,
        max_age=settings.portal_session_minutes * 60,
        httponly=True,  # not readable by page scripts
        samesite="lax",  # not sent on cross-site POSTs (basic CSRF defence for a demo)
        secure=(settings.app_env == "production"),  # http is fine for the local/offline demo
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

    token = create_access_token(
        settings, str(user.id), expires_minutes=settings.portal_session_minutes
    )
    audit.record(
        db, user.id, audit.ACTION_LOGIN_SUCCESS,
        target_type=audit.TARGET_USER, target_id=user.id, ip=audit.client_ip(request),
    )
    if "application/json" in request.headers.get("accept", ""):
        json_resp = JSONResponse({"ok": True, "redirect": "/portal/patients"})
        _set_session_cookie(json_resp, settings, token)
        return json_resp

    response = RedirectResponse("/portal/patients", status_code=status.HTTP_303_SEE_OTHER)
    _set_session_cookie(response, settings, token)
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
            "status_labels": STATUS_LABELS,
        },
    )


@router.get("/patients/{patient_id}", response_class=HTMLResponse)
def patient_reports_page(
    patient_id: int,
    request: Request,
    doctor: User = Depends(get_portal_doctor),
    db: Session = Depends(get_db),
) -> Response:
    """One consented patient's shared reports. Requires an active link (else a friendly
    'no access' page, matching the JSON route's 404 without existence-probing)."""
    if _active_link(db, doctor, patient_id) is None:
        return _access_denied(request, doctor, status.HTTP_404_NOT_FOUND)

    patient = db.get(User, patient_id)
    reports = db.scalars(
        select(Report)
        .where(Report.user_id == patient_id, Report.shared_at.is_not(None))
        .order_by(Report.created_at.desc())
    ).all()
    return templates.TemplateResponse(
        request,
        "patient_reports.html",
        {
            "doctor": doctor,
            "patient": patient,
            "reports": reports,
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
