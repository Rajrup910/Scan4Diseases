"""End-to-end tests for the appointment booking flow.

Covers the whole loop across both surfaces:
  * the patient books (mobile bearer API) → a `requested` appointment, and a consent link is
    formed so the doctor can see it;
  * the doctor sees it in the portal calendar page and summary JSON, and approves it;
  * the patient's app then sees it `confirmed` and flagged unread, clears the badge, and can
    cancel it;
  * a doctor may recommend a visit directly (created `confirmed`);
  * access is scoped — a second doctor cannot see or act on another doctor's appointment,
    and booking an unknown/unverified doctor is a 404.

Same isolation contract as the sibling portal tests: an in-memory DB via a `get_db` override
and a StaticPool, so the real app DB is never touched. The TestClient keeps a cookie jar, so
a portal login persists like a browser session.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.db.models import ROLE_DOCTOR, User
from backend.app.db.session import Base, get_db

_PASSWORD = "password123"


@pytest.fixture
def ctx(tmp_path, monkeypatch):
    monkeypatch.setenv("ALLOW_STUB_MODEL", "true")
    monkeypatch.setenv("LLM_ENABLED", "false")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.setenv("MODEL_CHECKPOINT", str(tmp_path / "does_not_exist.pt"))

    from backend.app.config import get_settings

    get_settings.cache_clear()

    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(bind=engine)
    TestSession = sessionmaker(bind=engine, expire_on_commit=False)

    from backend.app.main import create_app

    app = create_app()

    def _override_get_db():
        db = TestSession()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = _override_get_db
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, Session=TestSession)
    app.dependency_overrides.clear()
    engine.dispose()
    get_settings.cache_clear()


# --- helpers ------------------------------------------------------------------------

def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _register(ctx, email: str) -> str:
    resp = ctx.client.post("/auth/register", json={"email": email, "password": _PASSWORD})
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _promote_doctor(ctx, email: str, *, verified: bool = True) -> int:
    db = ctx.Session()
    try:
        user = db.query(User).filter(User.email == email).one()
        user.role = ROLE_DOCTOR
        user.is_verified = verified
        db.commit()
        return user.id
    finally:
        db.close()


def _make_report(ctx, token: str) -> int:
    resp = ctx.client.post(
        "/reports",
        headers=_auth(token),
        json={"condition": "Melanoma", "triage": "urgent", "explanation": "please review",
              "confidence": 0.9, "symptoms": {"itching": True}},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _future(days: int = 2, hour: int = 10) -> str:
    when = (datetime.now(timezone.utc) + timedelta(days=days)).replace(
        hour=hour, minute=0, second=0, microsecond=0
    )
    return when.isoformat()


def _portal_login(ctx, email: str = "doc@example.com"):
    return ctx.client.post("/portal/login", data={"email": email, "password": _PASSWORD})


def _arrange(ctx):
    """A verified doctor and a patient with one shared report. Returns ids/tokens."""
    patient_token = _register(ctx, "pat@example.com")
    patient_id = ctx.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]
    _register(ctx, "doc@example.com")
    doctor_id = _promote_doctor(ctx, "doc@example.com")
    report_id = _make_report(ctx, patient_token)
    ctx.client.post(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    return patient_token, patient_id, doctor_id, report_id


# --- patient booking ----------------------------------------------------------------

def test_patient_can_book_and_list(ctx):
    patient_token, _, doctor_id, report_id = _arrange(ctx)

    resp = ctx.client.post(
        "/appointments",
        headers=_auth(patient_token),
        json={"doctor_id": doctor_id, "report_id": report_id,
              "scheduled_for": _future(), "reason": "Changing mole"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["status"] == "requested"
    assert body["created_by"] == "patient"
    assert body["doctor_name"]  # doctor's name is flattened in
    assert body["report_condition"] == "Melanoma"

    listed = ctx.client.get("/appointments", headers=_auth(patient_token))
    assert listed.status_code == 200
    assert len(listed.json()) == 1


def test_booking_forms_a_consent_link(ctx):
    """Booking a doctor grants that doctor access — the doctor's worklist then sees the
    patient without a separate 'share' step."""
    patient_token, patient_id, doctor_id, _ = _arrange(ctx)
    ctx.client.post(
        "/appointments",
        headers=_auth(patient_token),
        json={"doctor_id": doctor_id, "scheduled_for": _future()},
    )
    consents = ctx.client.get("/patient/consent", headers=_auth(patient_token)).json()
    assert any(c["doctor_id"] == doctor_id and c["status"] == "active" for c in consents)


def test_booking_unknown_doctor_is_404(ctx):
    patient_token, patient_id, _, _ = _arrange(ctx)
    # A patient id (not a verified doctor) must not be bookable.
    resp = ctx.client.post(
        "/appointments",
        headers=_auth(patient_token),
        json={"doctor_id": patient_id, "scheduled_for": _future()},
    )
    assert resp.status_code == 404


def test_booking_past_slot_is_rejected(ctx):
    patient_token, _, doctor_id, _ = _arrange(ctx)
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    resp = ctx.client.post(
        "/appointments",
        headers=_auth(patient_token),
        json={"doctor_id": doctor_id, "scheduled_for": past},
    )
    assert resp.status_code == 422


# --- doctor approval (portal) -------------------------------------------------------

def _book(ctx, patient_token, doctor_id, report_id=None) -> int:
    payload = {"doctor_id": doctor_id, "scheduled_for": _future()}
    if report_id is not None:
        payload["report_id"] = report_id
    resp = ctx.client.post("/appointments", headers=_auth(patient_token), json=payload)
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def test_portal_calendar_and_summary(ctx):
    patient_token, patient_id, doctor_id, report_id = _arrange(ctx)
    appt_id = _book(ctx, patient_token, doctor_id, report_id)
    assert _portal_login(ctx).status_code == 200

    page = ctx.client.get("/portal/appointments")
    assert page.status_code == 200
    assert "Appointments" in page.text

    summary = ctx.client.get(f"/portal/appointments/{appt_id}/summary")
    assert summary.status_code == 200
    data = summary.json()
    assert data["appointment"]["can_approve"] is True
    assert data["patient"]["id"] == patient_id
    # The shared report shows up as a linked case, marked as this visit's case.
    linked = [c for c in data["cases"] if c["linked"]]
    assert len(linked) == 1 and linked[0]["id"] == report_id


def test_approve_notifies_patient(ctx):
    patient_token, _, doctor_id, report_id = _arrange(ctx)
    appt_id = _book(ctx, patient_token, doctor_id, report_id)
    _portal_login(ctx)

    resp = ctx.client.post(f"/portal/appointments/{appt_id}/approve")
    assert resp.status_code == 200  # PRG followed to the calendar page

    appts = ctx.client.get("/appointments", headers=_auth(patient_token)).json()
    assert appts[0]["status"] == "confirmed"
    assert appts[0]["unread_for_patient"] is True

    # Badge count reflects the unread response, and mark-seen clears it.
    count = ctx.client.get("/appointments/unread-count", headers=_auth(patient_token)).json()
    assert count["count"] == 1
    ctx.client.post("/appointments/mark-seen", headers=_auth(patient_token))
    after = ctx.client.get("/appointments/unread-count", headers=_auth(patient_token)).json()
    assert after["count"] == 0


def test_decline_records_reason(ctx):
    patient_token, _, doctor_id, _ = _arrange(ctx)
    appt_id = _book(ctx, patient_token, doctor_id)
    _portal_login(ctx)
    ctx.client.post(f"/portal/appointments/{appt_id}/decline", data={"reason": "Fully booked"})
    appt = ctx.client.get("/appointments", headers=_auth(patient_token)).json()[0]
    assert appt["status"] == "declined"
    assert appt["cancel_reason"] == "Fully booked"


def test_patient_can_cancel(ctx):
    patient_token, _, doctor_id, _ = _arrange(ctx)
    appt_id = _book(ctx, patient_token, doctor_id)
    resp = ctx.client.post(
        f"/appointments/{appt_id}/cancel",
        headers=_auth(patient_token),
        json={"reason": "Feeling better"},
    )
    assert resp.status_code == 200
    assert resp.json()["status"] == "cancelled"
    # Cancelling a terminal appointment again is a 409.
    again = ctx.client.post(
        f"/appointments/{appt_id}/cancel", headers=_auth(patient_token), json={"reason": ""}
    )
    assert again.status_code == 409


# --- doctor recommend ---------------------------------------------------------------

def test_doctor_recommend_creates_confirmed(ctx):
    patient_token, patient_id, doctor_id, _ = _arrange(ctx)
    # A consent link is needed before a doctor may recommend; a prior booking makes one,
    # but here we grant it explicitly.
    ctx.client.post(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    _portal_login(ctx)

    resp = ctx.client.post(
        "/portal/appointments/recommend",
        data={"patient_id": patient_id, "scheduled_for": "2099-01-01T09:30",
              "duration_minutes": "45", "reason": "Follow-up"},
    )
    assert resp.status_code == 200
    appts = ctx.client.get("/appointments", headers=_auth(patient_token)).json()
    assert len(appts) == 1
    assert appts[0]["status"] == "confirmed"
    assert appts[0]["created_by"] == "doctor"
    assert appts[0]["unread_for_patient"] is True


# --- access control -----------------------------------------------------------------

def test_other_doctor_cannot_see_appointment(ctx):
    patient_token, _, doctor_id, _ = _arrange(ctx)
    appt_id = _book(ctx, patient_token, doctor_id)

    _register(ctx, "other@example.com")
    _promote_doctor(ctx, "other@example.com")
    _portal_login(ctx, email="other@example.com")

    resp = ctx.client.get(f"/portal/appointments/{appt_id}/summary")
    assert resp.status_code == 404
    act = ctx.client.post(f"/portal/appointments/{appt_id}/approve")
    # Non-owning doctor: the summary is 404; the action redirects without effect.
    assert act.status_code in (200, 404)
    # The appointment is still pending for the patient (never approved by the intruder).
    appt = ctx.client.get("/appointments", headers=_auth(patient_token)).json()[0]
    assert appt["status"] == "requested"
