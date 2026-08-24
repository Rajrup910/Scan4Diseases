"""Tests for the security audit log (Session 5).

Two layers:

* The `record()` service in isolation -- it commits its own row, and a write failure is
  swallowed (logged, never raised) so an audit problem can never 500 a real request.
* The wiring: every security-relevant route writes the expected `(actor, action, target)`
  row -- portal login success *and* failure (failure with `actor_id IS NULL`), logout, a
  doctor viewing a report (both the JSON endpoint and the portal detail page), image and
  Grad-CAM fetches, status change, note add, and the patient-side consent and share/unshare.

Same isolation contract as the sibling suites: an in-memory DB via a `get_db` override and
StaticPool, so the real `app.db` is never touched.
"""

from __future__ import annotations

import io
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.db.models import ROLE_DOCTOR, AuditLog, User
from backend.app.db.session import Base, get_db
from backend.app.services import audit

_TEST_FERNET_KEY = "PvEl9IcG6lbHwYDG0E_wCboCbtN25suuCxsAoxgg5gE="
_PASSWORD = "password123"


@pytest.fixture
def app_ctx(tmp_path, monkeypatch):
    monkeypatch.setenv("ALLOW_STUB_MODEL", "true")
    monkeypatch.setenv("LLM_ENABLED", "false")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.setenv("MODEL_CHECKPOINT", str(tmp_path / "does_not_exist.pt"))
    monkeypatch.setenv("IMAGE_ENCRYPTION_KEY", _TEST_FERNET_KEY)

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
        json={"condition": "Melanoma", "triage": "urgent", "explanation": "please review"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _png_bytes(color=(120, 30, 30), size=(96, 96)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def _rows(ctx, action: str) -> list[AuditLog]:
    db = ctx.Session()
    try:
        return list(
            db.scalars(select(AuditLog).where(AuditLog.action == action)).all()
        )
    finally:
        db.close()


def _one(ctx, action: str) -> AuditLog:
    rows = _rows(ctx, action)
    assert len(rows) == 1, f"expected exactly one {action!r} row, got {len(rows)}"
    return rows[0]


def _seed(ctx):
    """A verified doctor logged into the portal, a consented patient, one shared report.
    Returns (doctor_id, doctor_token, patient_token, patient_id, report_id)."""
    patient_token = _register(ctx, "pat@example.com")
    patient_id = ctx.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]
    doctor_token = _register(ctx, "doc@example.com")
    doctor_id = _promote_doctor(ctx, "doc@example.com", verified=True)
    report_id = _make_report(ctx, patient_token)
    ctx.client.post(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    ctx.client.post(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    ctx.client.post("/portal/login", data={"email": "doc@example.com", "password": _PASSWORD})
    return doctor_id, doctor_token, patient_token, patient_id, report_id


# --- record() service, in isolation -------------------------------------------------

def test_record_writes_a_row(app_ctx):
    db = app_ctx.Session()
    try:
        audit.record(db, 7, audit.ACTION_LOGOUT, target_type="user", target_id=7, ip="1.2.3.4")
    finally:
        db.close()
    row = _one(app_ctx, audit.ACTION_LOGOUT)
    assert (row.actor_id, row.target_type, row.target_id, row.ip) == (7, "user", 7, "1.2.3.4")


def test_record_is_non_fatal_when_the_write_fails(app_ctx, caplog):
    """A commit failure inside record() must be swallowed (logged, not raised): an audit
    problem can never be allowed to 500 the real request it rode along with."""
    db = app_ctx.Session()

    def _boom():
        raise RuntimeError("db is on fire")

    db.commit = _boom  # type: ignore[method-assign]
    try:
        # Must not raise, despite commit blowing up.
        audit.record(db, None, audit.ACTION_LOGIN_FAILURE)
    finally:
        db.rollback()
        db.close()
    assert "audit write failed" in caplog.text


def test_client_ip_handles_no_client():
    assert audit.client_ip(None) is None


# --- login / logout -----------------------------------------------------------------

def test_login_success_is_audited(app_ctx):
    _register(app_ctx, "doc@example.com")
    doctor_id = _promote_doctor(app_ctx, "doc@example.com", verified=True)
    app_ctx.client.post("/portal/login", data={"email": "doc@example.com", "password": _PASSWORD})
    row = _one(app_ctx, audit.ACTION_LOGIN_SUCCESS)
    assert row.actor_id == doctor_id
    assert row.target_id == doctor_id
    assert row.ip == "testclient"  # TestClient's synthetic peer host


def test_failed_login_is_audited_with_null_actor(app_ctx):
    _register(app_ctx, "doc@example.com")
    doctor_id = _promote_doctor(app_ctx, "doc@example.com", verified=True)
    resp = app_ctx.client.post(
        "/portal/login", data={"email": "doc@example.com", "password": "wrong"}
    )
    assert resp.status_code == 401
    row = _one(app_ctx, audit.ACTION_LOGIN_FAILURE)
    # actor is NULL (nobody authenticated); the account that was tried is the target.
    assert row.actor_id is None
    assert row.target_id == doctor_id
    assert _rows(app_ctx, audit.ACTION_LOGIN_SUCCESS) == []


def test_failed_login_unknown_email_has_null_actor_and_target(app_ctx):
    resp = app_ctx.client.post(
        "/portal/login", data={"email": "nobody@example.com", "password": "wrong"}
    )
    assert resp.status_code == 401
    row = _one(app_ctx, audit.ACTION_LOGIN_FAILURE)
    assert row.actor_id is None
    assert row.target_id is None  # no account to point at


def test_logout_is_audited(app_ctx):
    doctor_id, *_ = _seed(app_ctx)
    app_ctx.client.post("/portal/logout")
    row = _one(app_ctx, audit.ACTION_LOGOUT)
    assert row.actor_id == doctor_id


# --- report access ------------------------------------------------------------------

def test_portal_report_view_is_audited(app_ctx):
    doctor_id, _, _, _, report_id = _seed(app_ctx)
    app_ctx.client.get(f"/portal/reports/{report_id}")
    row = _one(app_ctx, audit.ACTION_REPORT_VIEW)
    assert row.actor_id == doctor_id
    assert row.target_type == audit.TARGET_REPORT
    assert row.target_id == report_id


def test_json_report_view_is_audited(app_ctx):
    doctor_id, doctor_token, _, _, report_id = _seed(app_ctx)
    resp = app_ctx.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token))
    assert resp.status_code == 200
    row = _one(app_ctx, audit.ACTION_REPORT_VIEW)
    assert row.actor_id == doctor_id
    assert row.target_id == report_id


def test_forbidden_report_view_is_not_audited(app_ctx):
    """A refused access attempt raises before the view is recorded, so no report_view row is
    written for a report the doctor may not see."""
    _, doctor_token, patient_token, _, report_id = _seed(app_ctx)
    app_ctx.client.delete(
        f"/patient/reports/{report_id}/share", headers=_auth(patient_token)
    )
    resp = app_ctx.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token))
    assert resp.status_code == 403
    assert _rows(app_ctx, audit.ACTION_REPORT_VIEW) == []


def test_image_and_gradcam_fetches_are_audited(app_ctx):
    doctor_id, _, patient_token, _, report_id = _seed(app_ctx)
    app_ctx.client.post(
        f"/patient/reports/{report_id}/image",
        headers=_auth(patient_token),
        files={
            "image": ("lesion.png", _png_bytes(), "image/png"),
            "gradcam": ("cam.png", _png_bytes(color=(10, 90, 180)), "image/png"),
        },
    )
    assert app_ctx.client.get(f"/portal/reports/{report_id}/image").status_code == 200
    assert app_ctx.client.get(f"/portal/reports/{report_id}/gradcam").status_code == 200
    assert _one(app_ctx, audit.ACTION_IMAGE_VIEW).target_id == report_id
    assert _one(app_ctx, audit.ACTION_GRADCAM_VIEW).target_id == report_id


# --- mutations ----------------------------------------------------------------------

def test_status_change_is_audited(app_ctx):
    doctor_id, _, _, _, report_id = _seed(app_ctx)
    app_ctx.client.post(
        f"/portal/reports/{report_id}/status", data={"status": "under_review"}
    )
    row = _one(app_ctx, audit.ACTION_STATUS_CHANGE)
    assert row.actor_id == doctor_id
    assert row.target_id == report_id


def test_tampered_status_writes_no_audit_row(app_ctx):
    _, _, _, _, report_id = _seed(app_ctx)
    app_ctx.client.post(f"/portal/reports/{report_id}/status", data={"status": "banana"})
    assert _rows(app_ctx, audit.ACTION_STATUS_CHANGE) == []


def test_note_add_is_audited(app_ctx):
    doctor_id, _, _, _, report_id = _seed(app_ctx)
    app_ctx.client.post(
        f"/portal/reports/{report_id}/notes", data={"note": "Recommend dermoscopy."}
    )
    row = _one(app_ctx, audit.ACTION_NOTE_ADD)
    assert row.actor_id == doctor_id
    assert row.target_id == report_id


def test_empty_note_writes_no_audit_row(app_ctx):
    _, _, _, _, report_id = _seed(app_ctx)
    app_ctx.client.post(f"/portal/reports/{report_id}/notes", data={"note": "   "})
    assert _rows(app_ctx, audit.ACTION_NOTE_ADD) == []


# --- patient-side consent and sharing -----------------------------------------------

def test_consent_grant_and_revoke_are_audited(app_ctx):
    patient_token = _register(app_ctx, "pat@example.com")
    patient_id = app_ctx.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]
    _register(app_ctx, "doc@example.com")
    doctor_id = _promote_doctor(app_ctx, "doc@example.com", verified=True)

    app_ctx.client.post(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    grant = _one(app_ctx, audit.ACTION_CONSENT_GRANT)
    assert grant.actor_id == patient_id
    assert grant.target_type == audit.TARGET_USER
    assert grant.target_id == doctor_id

    app_ctx.client.delete(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    revoke = _one(app_ctx, audit.ACTION_CONSENT_REVOKE)
    assert revoke.actor_id == patient_id
    assert revoke.target_id == doctor_id


def test_share_and_unshare_are_audited(app_ctx):
    patient_token = _register(app_ctx, "pat@example.com")
    patient_id = app_ctx.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]
    report_id = _make_report(app_ctx, patient_token)

    app_ctx.client.post(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    share = _one(app_ctx, audit.ACTION_REPORT_SHARE)
    assert share.actor_id == patient_id
    assert share.target_type == audit.TARGET_REPORT
    assert share.target_id == report_id

    app_ctx.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    unshare = _one(app_ctx, audit.ACTION_REPORT_UNSHARE)
    assert unshare.actor_id == patient_id
    assert unshare.target_id == report_id
