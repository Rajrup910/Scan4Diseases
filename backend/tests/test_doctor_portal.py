"""End-to-end HTTP tests for the doctor portal and the patient sharing controls.

These drive the real FastAPI app through a TestClient, but against a throwaway in-memory
database wired in via a `get_db` dependency override -- the app's real `app.db` is never
touched. The point of testing here (rather than only at the helper layer in test_rbac.py)
is to prove the *routes* enforce the access rule: a doctor must not reach another patient's
report even with a valid token, an unverified/non-doctor account must be refused at the
door, and revoking consent must cut access off through the HTTP surface.
"""

from __future__ import annotations

import io
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from PIL import Image, UnidentifiedImageError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.app.db.models import ROLE_DOCTOR, User
from backend.app.db.session import Base, get_db

# A valid Fernet key, fixed so the shared-image tests are deterministic. Test-only; the real
# key lives in .env and is never committed.
_TEST_FERNET_KEY = "PvEl9IcG6lbHwYDG0E_wCboCbtN25suuCxsAoxgg5gE="


@pytest.fixture
def portal(tmp_path, monkeypatch):
    """The app running against an isolated in-memory DB (shared across the test's threads
    via StaticPool), with model/LLM stubbed off so startup is fast and offline."""
    monkeypatch.setenv("ALLOW_STUB_MODEL", "true")
    monkeypatch.setenv("LLM_ENABLED", "false")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.setenv("MODEL_CHECKPOINT", str(tmp_path / "does_not_exist.pt"))
    monkeypatch.setenv("IMAGE_ENCRYPTION_KEY", _TEST_FERNET_KEY)

    from backend.app.config import get_settings

    get_settings.cache_clear()

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
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

def _register(portal, email: str, password: str = "password123") -> str:
    """Register a patient and return their bearer token."""
    resp = portal.client.post("/auth/register", json={"email": email, "password": password})
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _promote_doctor(portal, email: str, *, verified: bool = True) -> int:
    """Flip an existing account to a (optionally verified) doctor. Returns its id."""
    db = portal.Session()
    try:
        user = db.query(User).filter(User.email == email).one()
        user.role = ROLE_DOCTOR
        user.is_verified = verified
        db.commit()
        return user.id
    finally:
        db.close()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _make_report(portal, token: str) -> int:
    resp = portal.client.post(
        "/reports",
        headers=_auth(token),
        json={"condition": "Melanoma", "triage": "urgent", "explanation": "check soon"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


def _png_bytes(color=(120, 30, 30), size=(96, 96)) -> bytes:
    """A small, valid PNG for upload tests (above the 64px minimum decode_image enforces)."""
    buffer = io.BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def _upload_image(portal, token: str, report_id: int, *, with_gradcam: bool = False):
    files = {"image": ("lesion.png", _png_bytes(), "image/png")}
    if with_gradcam:
        files["gradcam"] = ("gradcam.png", _png_bytes(color=(10, 90, 180)), "image/png")
    return portal.client.post(
        f"/patient/reports/{report_id}/image", headers=_auth(token), files=files
    )


def _seed_doctor_with_shared_report(portal):
    """Common arrangement: a verified doctor, a consented patient, one shared report.
    Returns (doctor_token, doctor_id, patient_token, patient_id, report_id)."""
    patient_token = _register(portal, "pat@example.com")
    patient_id = portal.client.get("/auth/me", headers=_auth(patient_token)).json()["id"]

    doctor_token = _register(portal, "doc@example.com")
    doctor_id = _promote_doctor(portal, "doc@example.com", verified=True)

    report_id = _make_report(portal, patient_token)
    # Patient grants consent and shares the report.
    assert portal.client.post(
        f"/patient/consent/{doctor_id}", headers=_auth(patient_token)
    ).status_code == 200
    assert portal.client.post(
        f"/patient/reports/{report_id}/share", headers=_auth(patient_token)
    ).status_code == 204
    return doctor_token, doctor_id, patient_token, patient_id, report_id


# --- role gates at the HTTP door ----------------------------------------------------

def test_patient_is_refused_doctor_area(portal):
    token = _register(portal, "pat@example.com")
    resp = portal.client.get("/doctor/patients", headers=_auth(token))
    assert resp.status_code == 403
    assert resp.json()["error"] == "not_authorized"


def test_unverified_doctor_is_refused(portal):
    _register(portal, "doc@example.com")
    _promote_doctor(portal, "doc@example.com", verified=False)
    token = portal.client.post(
        "/auth/login", json={"email": "doc@example.com", "password": "password123"}
    ).json()["access_token"]
    resp = portal.client.get("/doctor/patients", headers=_auth(token))
    assert resp.status_code == 403
    assert resp.json()["error"] == "account_unverified"


def test_missing_token_is_401(portal):
    assert portal.client.get("/doctor/patients").status_code == 401


# --- doctor directory (the app's "choose a doctor" picker) --------------------------

def test_directory_lists_only_verified_doctors(portal):
    patient_token = _register(portal, "pat@example.com")
    _register(portal, "verified@example.com")
    verified_id = _promote_doctor(portal, "verified@example.com", verified=True)
    _register(portal, "unverified@example.com")
    _promote_doctor(portal, "unverified@example.com", verified=False)
    _register(portal, "other-patient@example.com")  # a plain patient, must not appear

    resp = portal.client.get("/patient/doctors", headers=_auth(patient_token))
    assert resp.status_code == 200
    ids = {d["id"] for d in resp.json()}
    assert ids == {verified_id}
    entry = resp.json()[0]
    # Professional identity only -- no patient data, no password/verification internals.
    assert set(entry) == {"id", "display_name", "email", "medical_reg_no"}


def test_directory_requires_authentication(portal):
    assert portal.client.get("/patient/doctors").status_code == 401


# --- patient consent ----------------------------------------------------------------

def test_consent_to_non_doctor_is_404(portal):
    patient_token = _register(portal, "pat@example.com")
    other_token = _register(portal, "other@example.com")
    other_id = portal.client.get("/auth/me", headers=_auth(other_token)).json()["id"]
    resp = portal.client.post(f"/patient/consent/{other_id}", headers=_auth(patient_token))
    assert resp.status_code == 404


def test_consent_to_unverified_doctor_is_404(portal):
    patient_token = _register(portal, "pat@example.com")
    _register(portal, "doc@example.com")
    doc_id = _promote_doctor(portal, "doc@example.com", verified=False)
    resp = portal.client.post(f"/patient/consent/{doc_id}", headers=_auth(patient_token))
    assert resp.status_code == 404


def test_consent_is_idempotent_and_reactivatable(portal):
    patient_token = _register(portal, "pat@example.com")
    _register(portal, "doc@example.com")
    doc_id = _promote_doctor(portal, "doc@example.com", verified=True)

    first = portal.client.post(f"/patient/consent/{doc_id}", headers=_auth(patient_token)).json()
    assert first["status"] == "active" and first["consented_at"] is not None

    # Revoke, then re-grant: still exactly one link, moved back to active.
    portal.client.delete(f"/patient/consent/{doc_id}", headers=_auth(patient_token))
    again = portal.client.post(f"/patient/consent/{doc_id}", headers=_auth(patient_token)).json()
    assert again["id"] == first["id"]
    assert again["status"] == "active"

    listed = portal.client.get("/patient/consent", headers=_auth(patient_token)).json()
    assert len(listed) == 1


# --- the access rule, over HTTP -----------------------------------------------------

def test_doctor_reads_a_shared_report(portal):
    doctor_token, _, _, patient_id, report_id = _seed_doctor_with_shared_report(portal)
    resp = portal.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token))
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == report_id
    assert body["patient_id"] == patient_id
    assert body["condition"] == "Melanoma"
    assert body["notes"] == []


def test_doctor_patient_list_counts_shared_reports(portal):
    doctor_token, _, patient_token, patient_id, _ = _seed_doctor_with_shared_report(portal)
    rows = portal.client.get("/doctor/patients", headers=_auth(doctor_token)).json()
    assert len(rows) == 1
    assert rows[0]["id"] == patient_id
    assert rows[0]["shared_report_count"] == 1


def test_doctor_cannot_read_unshared_report(portal):
    doctor_token, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    # Patient unshares -> access must be cut off.
    portal.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    resp = portal.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token))
    assert resp.status_code == 403
    assert resp.json()["error"] == "not_authorized"


def test_revoking_consent_cuts_off_access(portal):
    doctor_token, doctor_id, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    portal.client.delete(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    resp = portal.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token))
    assert resp.status_code == 403


def test_doctor_cannot_reach_another_patients_report(portal):
    """The critical negative: doctor consented for patient A must not see patient B's shared
    report, even though the report is genuinely shared."""
    doctor_token, doctor_id, _, _, _ = _seed_doctor_with_shared_report(portal)

    patient_b_token = _register(portal, "b@example.com")
    report_b = _make_report(portal, patient_b_token)
    # B shares the report but never consents to this doctor.
    portal.client.post(f"/patient/reports/{report_b}/share", headers=_auth(patient_b_token))

    resp = portal.client.get(f"/doctor/reports/{report_b}", headers=_auth(doctor_token))
    assert resp.status_code == 403
    # And B must not appear in the doctor's patient list.
    rows = portal.client.get("/doctor/patients", headers=_auth(doctor_token)).json()
    assert all(r["email"] != "b@example.com" for r in rows)


def test_nonexistent_report_is_403_not_404(portal):
    """No existence probing: a missing id returns the same 403 as a forbidden one."""
    doctor_token, *_ = _seed_doctor_with_shared_report(portal)
    resp = portal.client.get("/doctor/reports/999999", headers=_auth(doctor_token))
    assert resp.status_code == 403


def test_patient_reports_listing_requires_a_link(portal):
    doctor_token, _, _, _, _ = _seed_doctor_with_shared_report(portal)
    # A different patient the doctor has no link to.
    stranger_token = _register(portal, "stranger@example.com")
    stranger_id = portal.client.get("/auth/me", headers=_auth(stranger_token)).json()["id"]
    resp = portal.client.get(
        f"/doctor/patients/{stranger_id}/reports", headers=_auth(doctor_token)
    )
    assert resp.status_code == 404


# --- status + notes -----------------------------------------------------------------

def test_status_update_persists_and_validates(portal):
    doctor_token, _, _, _, report_id = _seed_doctor_with_shared_report(portal)
    ok = portal.client.patch(
        f"/doctor/reports/{report_id}/status",
        headers=_auth(doctor_token),
        json={"status": "under_review"},
    )
    assert ok.status_code == 200
    assert ok.json()["status"] == "under_review"

    bad = portal.client.patch(
        f"/doctor/reports/{report_id}/status",
        headers=_auth(doctor_token),
        json={"status": "banana"},
    )
    assert bad.status_code == 422


def test_notes_can_be_added_and_appear_on_the_report(portal):
    doctor_token, doctor_id, _, _, report_id = _seed_doctor_with_shared_report(portal)
    created = portal.client.post(
        f"/doctor/reports/{report_id}/notes",
        headers=_auth(doctor_token),
        json={"note": "Recommend dermoscopy within two weeks."},
    )
    assert created.status_code == 201
    assert created.json()["doctor_id"] == doctor_id

    detail = portal.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token)).json()
    assert len(detail["notes"]) == 1
    assert "dermoscopy" in detail["notes"][0]["note"]


def test_note_rejects_empty_body(portal):
    doctor_token, _, _, _, report_id = _seed_doctor_with_shared_report(portal)
    resp = portal.client.post(
        f"/doctor/reports/{report_id}/notes",
        headers=_auth(doctor_token),
        json={"note": ""},
    )
    assert resp.status_code == 422


def test_status_update_forbidden_on_unshared_report(portal):
    """A mutation route is gated by exactly the same rule as a read route."""
    doctor_token, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    portal.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    resp = portal.client.patch(
        f"/doctor/reports/{report_id}/status",
        headers=_auth(doctor_token),
        json={"status": "reviewed"},
    )
    assert resp.status_code == 403


# --- shared images: encryption at rest + authenticated serving ----------------------

def test_patient_shares_image_and_doctor_fetches_it(portal):
    doctor_token, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)

    up = _upload_image(portal, patient_token, report_id, with_gradcam=True)
    assert up.status_code == 200, up.text
    assert up.json()["has_image"] is True
    assert up.json()["has_gradcam"] is True

    # The report detail advertises the images without leaking any blob filename.
    detail = portal.client.get(f"/doctor/reports/{report_id}", headers=_auth(doctor_token)).json()
    assert detail["has_image"] is True and detail["has_gradcam"] is True
    assert "image_path" not in detail and "gradcam_path" not in detail

    img = portal.client.get(f"/doctor/reports/{report_id}/image", headers=_auth(doctor_token))
    assert img.status_code == 200
    assert img.headers["content-type"] == "image/jpeg"
    assert img.headers["cache-control"] == "private, no-store"
    # The bytes served are a real, openable image (decrypted correctly).
    assert Image.open(io.BytesIO(img.content)).size == (96, 96)

    gc = portal.client.get(f"/doctor/reports/{report_id}/gradcam", headers=_auth(doctor_token))
    assert gc.status_code == 200 and gc.headers["content-type"] == "image/png"


def test_shared_image_blob_on_disk_is_ciphertext(portal, tmp_path):
    _, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    assert _upload_image(portal, patient_token, report_id).status_code == 200

    blobs = list((tmp_path / "storage" / "shared").glob("simg_*.enc"))
    assert len(blobs) == 1
    raw = blobs[0].read_bytes()
    # Not a decodable image, and free of the PNG/JPEG magic bytes -- it is ciphertext.
    with pytest.raises((UnidentifiedImageError, OSError)):
        Image.open(io.BytesIO(raw)).load()
    assert b"\x89PNG" not in raw and b"\xff\xd8\xff" not in raw


def test_uploading_image_marks_report_shared(portal):
    """Uploading an image is itself a share action: no prior /share call needed."""
    patient_token = _register(portal, "pat@example.com")
    _register(portal, "doc@example.com")
    doctor_id = _promote_doctor(portal, "doc@example.com", verified=True)
    portal.client.post(f"/patient/consent/{doctor_id}", headers=_auth(patient_token))
    doctor_token = portal.client.post(
        "/auth/login", json={"email": "doc@example.com", "password": "password123"}
    ).json()["access_token"]
    report_id = _make_report(portal, patient_token)

    assert _upload_image(portal, patient_token, report_id).json()["shared_at"] is not None
    assert portal.client.get(
        f"/doctor/reports/{report_id}", headers=_auth(doctor_token)
    ).status_code == 200


def test_doctor_cannot_fetch_another_patients_image(portal):
    doctor_token, _, _, _, _ = _seed_doctor_with_shared_report(portal)
    patient_b_token = _register(portal, "b@example.com")
    report_b = _make_report(portal, patient_b_token)
    _upload_image(portal, patient_b_token, report_b)  # shared, but no consent to this doctor
    resp = portal.client.get(f"/doctor/reports/{report_b}/image", headers=_auth(doctor_token))
    assert resp.status_code == 403


def test_unsharing_destroys_the_image(portal, tmp_path):
    doctor_token, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    _upload_image(portal, patient_token, report_id)
    assert list((tmp_path / "storage" / "shared").glob("simg_*.enc"))

    portal.client.delete(f"/patient/reports/{report_id}/share", headers=_auth(patient_token))
    # Blob is gone from disk, and the doctor is cut off at the access gate.
    assert not list((tmp_path / "storage" / "shared").glob("simg_*.enc"))
    assert portal.client.get(
        f"/doctor/reports/{report_id}/image", headers=_auth(doctor_token)
    ).status_code == 403


def test_image_endpoint_404_when_report_shared_without_image(portal):
    """A metadata-only share (no upload) exposes the report but has no image to serve."""
    doctor_token, _, _, _, report_id = _seed_doctor_with_shared_report(portal)
    resp = portal.client.get(f"/doctor/reports/{report_id}/image", headers=_auth(doctor_token))
    assert resp.status_code == 404
    assert resp.json()["error"] == "image_not_found"


def test_upload_rejects_a_non_image(portal):
    _, _, patient_token, _, report_id = _seed_doctor_with_shared_report(portal)
    resp = portal.client.post(
        f"/patient/reports/{report_id}/image",
        headers=_auth(patient_token),
        files={"image": ("note.txt", b"this is not an image", "text/plain")},
    )
    assert resp.status_code == 422


def test_cannot_share_image_for_another_users_report(portal):
    _, _, _, _, report_id = _seed_doctor_with_shared_report(portal)
    intruder_token = _register(portal, "intruder@example.com")
    resp = _upload_image(portal, intruder_token, report_id)
    assert resp.status_code == 404


# --- ImageVault contract (unit-level) -----------------------------------------------

def test_image_vault_round_trips_and_conceals(tmp_path):
    from backend.app.services.image_vault import ImageVault

    vault = ImageVault(tmp_path / "vault", _TEST_FERNET_KEY)
    assert vault.configured
    name = vault.store(b"secret-bytes", "image/jpeg")
    on_disk = (tmp_path / "vault" / name).read_bytes()
    assert b"secret-bytes" not in on_disk  # ciphertext at rest
    assert vault.load(name) == ("image/jpeg", b"secret-bytes")
    assert vault.remove(name) is True
    assert vault.load(name) is None


def test_image_vault_without_key_fails_loudly(tmp_path):
    """No key configured must raise a client-safe 503, never silently write plaintext."""
    from backend.app.services.image_vault import ImageVault
    from backend.app.utils.errors import AppError

    vault = ImageVault(tmp_path / "vault", None)
    assert vault.configured is False
    with pytest.raises(AppError) as excinfo:
        vault.store(b"data", "image/png")
    assert excinfo.value.status_code == 503
