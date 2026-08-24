"""End-to-end tests for the server-rendered doctor web portal (Session 4).

The portal is a browser UI over the same JSON endpoints tested in `test_doctor_portal.py`,
so these tests focus on what is new: cookie-session authentication, the HTML pages render
for the right doctor, the form-based status/note mutations round-trip, images stream through
the cookie-authorised route, and -- most importantly -- the web surface enforces exactly the
same access rule (an unshared/other-patient/missing report is refused, not shown).

Same isolation contract as the sibling test: an in-memory DB via a `get_db` override and
StaticPool, so the real `app.db` is never touched. The TestClient keeps a cookie jar, so a
portal login persists across subsequent requests just as a browser would.
"""

from __future__ import annotations

import io
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.db.models import ROLE_DOCTOR, ROLE_PATIENT, User
from backend.app.db.session import Base, get_db

_TEST_FERNET_KEY = "PvEl9IcG6lbHwYDG0E_wCboCbtN25suuCxsAoxgg5gE="
_PASSWORD = "password123"


@pytest.fixture
def web(tmp_path, monkeypatch):
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


def _register(web, email: str) -> str:
    resp = web.client.post("/auth/register", json={"email": email, "password": _PASSWORD})
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _promote_doctor(web, email: str, *, verified: bool = True) -> int:
    db = web.Session()
    try:
        user = db.query(User).filter(User.email == email).one()
        user.role = ROLE_DOCTOR
        user.is_verified = verified
        db.commit()
        return user.id
    finally:
        db.close()


def _make_report(web, token: str, condition: str = "Melanoma", triage: str = "urgent") -> int:
    resp = web.client.post(
        "/reports",
        headers=_auth(token),
        json={"condition": condition, "triage": triage, "explanation": "please review",
              "confidence": 0.87, "symptoms": {"itching": True, "duration_weeks": 6}},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _png_bytes(color=(120, 30, 30), size=(96, 96)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def _portal_login(web, email: str = "doc@example.com", password: str = _PASSWORD):
    """Log a doctor into the portal (sets the session cookie in the client's jar)."""
    return web.client.post(
        "/portal/login", data={"email": email, "password": password}
    )


def _seed(web):
    """A verified doctor logged into the portal, a consented patient, one shared report.
    Returns (doctor_id, patient_token, patient_id, report_id)."""
    patient_token = _register(web, "pat@example.com")
    patient_id = web.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]
    _register(web, "doc@example.com")
    doctor_id = _promote_doctor(web, "doc@example.com", verified=True)
    report_id = _make_report(web, patient_token)
    web.client.post(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    web.client.post(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    assert _portal_login(web).url.path == "/portal/patients"
    return doctor_id, patient_token, patient_id, report_id


# --- login / session ----------------------------------------------------------------

def test_login_page_renders(web):
    resp = web.client.get("/portal/login")
    assert resp.status_code == 200
    assert "Clinician sign in" in resp.text


def test_login_rejects_bad_credentials(web):
    _register(web, "doc@example.com")
    _promote_doctor(web, "doc@example.com", verified=True)
    resp = _portal_login(web, password="wrong")
    assert resp.status_code == 401
    assert "incorrect" in resp.text.lower()
    # No session cookie was set.
    assert "portal_session" not in web.client.cookies


def test_login_rejects_non_doctor(web):
    _register(web, "pat@example.com")
    resp = _portal_login(web, email="pat@example.com")
    assert resp.status_code == 403
    assert "verified doctors only" in resp.text.lower()
    assert "portal_session" not in web.client.cookies


def test_login_rejects_unverified_doctor(web):
    _register(web, "doc@example.com")
    _promote_doctor(web, "doc@example.com", verified=False)
    resp = _portal_login(web)
    assert resp.status_code == 403
    assert "awaiting verification" in resp.text.lower()


def test_unauthenticated_page_redirects_to_login(web):
    resp = web.client.get("/portal/patients", follow_redirects=False)
    assert resp.status_code == 303
    assert resp.headers["location"] == "/portal/login"


def test_successful_login_sets_cookie_and_lands_on_worklist(web):
    _register(web, "doc@example.com")
    _promote_doctor(web, "doc@example.com", verified=True)
    resp = _portal_login(web)
    assert resp.status_code == 200
    assert resp.url.path == "/portal/patients"
    assert "portal_session" in web.client.cookies


def test_logout_clears_session(web):
    _seed(web)
    assert web.client.get("/portal/patients").status_code == 200
    web.client.post("/portal/logout")
    # Cookie gone; the worklist now bounces to login.
    after = web.client.get("/portal/patients", follow_redirects=False)
    assert after.status_code == 303
    assert after.headers["location"] == "/portal/login"


# --- pages: the happy path ----------------------------------------------------------

def test_worklist_lists_consented_patient(web):
    _seed(web)
    resp = web.client.get("/portal/patients")
    assert resp.status_code == 200
    assert "pat@example.com" in resp.text


def test_patient_reports_page_lists_shared_report(web):
    _, _, patient_id, _ = _seed(web)
    resp = web.client.get(f"/portal/patients/{patient_id}")
    assert resp.status_code == 200
    assert "Melanoma" in resp.text


def test_report_detail_renders(web):
    _, _, _, report_id = _seed(web)
    resp = web.client.get(f"/portal/reports/{report_id}")
    assert resp.status_code == 200
    assert "Melanoma" in resp.text
    assert "please review" in resp.text  # the explanation
    assert "Itching" in resp.text  # a questionnaire key, prettified


# --- pages: form mutations ----------------------------------------------------------

def test_status_update_via_form(web):
    _, _, _, report_id = _seed(web)
    resp = web.client.post(
        f"/portal/reports/{report_id}/status", data={"status": "under_review"}
    )
    assert resp.status_code == 200  # followed the redirect back to the detail page
    assert resp.url.path == f"/portal/reports/{report_id}"
    assert "Under review" in resp.text


def test_tampered_status_is_ignored_not_500(web):
    _, _, _, report_id = _seed(web)
    resp = web.client.post(
        f"/portal/reports/{report_id}/status", data={"status": "banana"}
    )
    assert resp.status_code == 200
    # Status is unchanged from the default.
    assert "New" in resp.text


def test_add_note_via_form(web):
    _, _, _, report_id = _seed(web)
    resp = web.client.post(
        f"/portal/reports/{report_id}/notes",
        data={"note": "Recommend dermoscopy within two weeks."},
    )
    assert resp.status_code == 200
    assert "dermoscopy" in resp.text


def test_empty_note_creates_nothing(web):
    _, _, _, report_id = _seed(web)
    web.client.post(f"/portal/reports/{report_id}/notes", data={"note": "   "})
    detail = web.client.get(f"/portal/reports/{report_id}")
    assert "No notes yet" in detail.text


# --- images through the cookie-authorised route -------------------------------------

def test_image_streams_through_portal(web):
    _, patient_token, _, report_id = _seed(web)
    up = web.client.post(
        f"/patient/reports/{report_id}/image",
        headers=_auth(patient_token),
        files={"image": ("lesion.png", _png_bytes(), "image/png")},
    )
    assert up.status_code == 200

    img = web.client.get(f"/portal/reports/{report_id}/image")
    assert img.status_code == 200
    assert img.headers["content-type"] == "image/jpeg"
    assert img.headers["cache-control"] == "private, no-store"
    assert Image.open(io.BytesIO(img.content)).size == (96, 96)

    # The detail page links to the image.
    detail = web.client.get(f"/portal/reports/{report_id}")
    assert f"/portal/reports/{report_id}/image" in detail.text


def test_image_route_requires_session(web):
    _, patient_token, _, report_id = _seed(web)
    web.client.post(
        f"/patient/reports/{report_id}/image",
        headers=_auth(patient_token),
        files={"image": ("lesion.png", _png_bytes(), "image/png")},
    )
    web.client.post("/portal/logout")
    resp = web.client.get(f"/portal/reports/{report_id}/image", follow_redirects=False)
    assert resp.status_code == 303
    assert resp.headers["location"] == "/portal/login"


# --- the access rule, over the web surface ------------------------------------------

def test_unshared_report_shows_no_access(web):
    _, patient_token, _, report_id = _seed(web)
    web.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    resp = web.client.get(f"/portal/reports/{report_id}")
    # A forbidden report renders the friendly page but carries the report route's 403
    # (a forbidden and a non-existent report are indistinguishable -- no existence probing).
    assert resp.status_code == 403
    assert "No access" in resp.text


def test_doctor_cannot_open_another_patients_report(web):
    _seed(web)  # doctor is logged in, consented only to patient A
    patient_b = _register(web, "b@example.com")
    report_b = _make_report(web, patient_b)
    web.client.post(f"/patient/reports/{report_b}/share", headers=_auth(patient_b))
    resp = web.client.get(f"/portal/reports/{report_b}")
    assert resp.status_code == 403
    assert "No access" in resp.text


def test_patient_reports_page_requires_a_link(web):
    _seed(web)
    stranger = _register(web, "stranger@example.com")
    stranger_id = web.client.get("/auth/me", headers=_auth(stranger)).json()["id"]
    resp = web.client.get(f"/portal/patients/{stranger_id}")
    assert resp.status_code == 404
    assert "No access" in resp.text


def test_missing_report_is_no_access_not_500(web):
    _seed(web)
    resp = web.client.get("/portal/reports/999999")
    # Same 403 as a forbidden report: a missing id must not be distinguishable from one the
    # doctor simply may not see.
    assert resp.status_code == 403
    assert "No access" in resp.text


def test_status_mutation_forbidden_on_unshared_report(web):
    _, patient_token, _, report_id = _seed(web)
    web.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    # The mutation route is gated by the same rule; a raw AppError (403) surfaces here.
    resp = web.client.post(
        f"/portal/reports/{report_id}/status",
        data={"status": "reviewed"},
        follow_redirects=False,
    )
    assert resp.status_code == 403


# --- session / cookie robustness (RBAC negatives) -----------------------------------

def _set_portal_cookie(web, token: str) -> None:
    web.client.cookies.set("portal_session", token, path="/portal")


def test_garbage_cookie_redirects_to_login(web):
    """A tampered/undecodable session cookie must not error out -- it is treated exactly like
    no session at all: a redirect to login, revealing nothing."""
    _set_portal_cookie(web, "not.a.valid.jwt")
    resp = web.client.get("/portal/patients", follow_redirects=False)
    assert resp.status_code == 303
    assert resp.headers["location"] == "/portal/login"


def test_expired_portal_token_redirects_to_login(web):
    """An expired but otherwise well-formed token is rejected the same way -- role and expiry
    are re-checked on every request, so a lapsed session cannot linger."""
    _register(web, "doc@example.com")
    doctor_id = _promote_doctor(web, "doc@example.com", verified=True)

    from backend.app.config import get_settings
    from backend.app.security import create_access_token

    settings = get_settings()
    expired = create_access_token(settings, str(doctor_id), expires_minutes=-1)
    _set_portal_cookie(web, expired)

    resp = web.client.get("/portal/patients", follow_redirects=False)
    assert resp.status_code == 303
    assert resp.headers["location"] == "/portal/login"


def test_demoted_doctor_loses_access_mid_session(web):
    """Role is read from the DB row on every request, not from the token. Flipping the doctor
    back to a patient must therefore cut portal access off immediately, while their existing
    session cookie is still otherwise valid -- proving the role is not trusted from the JWT."""
    _seed(web)
    assert web.client.get("/portal/patients").status_code == 200  # access works now

    # Demote the doctor in the DB; the session cookie is untouched.
    db = web.Session()
    try:
        user = db.query(User).filter(User.email == "doc@example.com").one()
        user.role = ROLE_PATIENT
        db.commit()
    finally:
        db.close()

    after = web.client.get("/portal/patients", follow_redirects=False)
    assert after.status_code == 303
    assert after.headers["location"] == "/portal/login"
