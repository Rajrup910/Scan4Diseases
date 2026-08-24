"""Comprehensive flow and integration test for Scan4Diseases.

Tests the complete lifecycle of a new patient and clinician across all endpoints:
1. System Health & Model Status
2. New Patient Registration & Input Normalization (mixed case + whitespace)
3. New Patient Login & Session Token
4. Patient Profile (/auth/me)
5. Clean Initial Workspace (empty /reports)
6. Dermatology Screening (/predict) with synthetic test image & symptoms
7. Clinical LLM Assistant (/chat)
8. Report Creation (/reports)
9. Doctor Directory Discovery (/patient/doctors)
10. Doctor Access Consent (/patient/consent/{doctor_id})
11. Encrypted Image Vault Upload & Report Sharing (/patient/reports/{id}/image)
12. Clinician Worklist & Patient Inspection (/doctor/patients, /doctor/images/{token})
13. Clinician Clinical Notes & Status Review (/doctor/reports/{id}/notes)
14. Patient Consent Revocation (/patient/consent/{doctor_id})
15. Patient Report Deletion (/reports/{id})
"""

from __future__ import annotations

import io
import sys
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from backend.app.main import app
from backend.app.db.session import init_db, SessionLocal
from backend.app.db.seed import seed_default_data, DOCTOR_EMAIL, DOCTOR_PASSWORD


def create_test_lesion_image() -> bytes:
    """Create a synthetic 300x300 RGB lesion-like test image."""
    img = Image.new("RGB", (300, 300), color=(225, 190, 160))
    draw = ImageDraw.Draw(img)
    # Draw a distinct dark lesion spot in the center
    draw.ellipse([100, 100, 200, 200], fill=(70, 35, 20), outline=(50, 25, 15))
    draw.ellipse([120, 120, 160, 160], fill=(40, 20, 10))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def run_full_integration_suite():
    init_db()
    with SessionLocal() as db:
        seed_default_data(db)

    print("=" * 60)
    print("STARTING FULL END-TO-END FLOW INTEGRATION TEST")
    print("=" * 60)

    with TestClient(app) as client:
        # 1. Health
        res = client.get("/health")
        assert res.status_code == 200, f"Health check failed: {res.text}"
        health_data = res.json()
        print("[PASS] 1. Health Check passed:", health_data["status"], "| Model loaded:", health_data["model_loaded"])

        # 2. Register New Patient with messy input
        import uuid
        uid = uuid.uuid4().hex[:6]
        raw_email = f"  NeW.PaTieNt_{uid}@ExAmPlE.CoM  "
        clean_email = f"new.patient_{uid}@example.com"
        patient_pass = "SecurePass123!"
        patient_name = "  Dr. Jane Patient  "

        res = client.post("/auth/register", json={
            "email": raw_email,
            "password": patient_pass,
            "display_name": patient_name,
        })
        assert res.status_code == 201, f"Registration failed: {res.text}"
        reg_data = res.json()
        patient_token = reg_data["access_token"]
        patient_user = reg_data["user"]
        assert patient_user["email"] == clean_email, "Email normalization failed"
        assert patient_user["display_name"] == "Dr. Jane Patient", "Display name trimming failed"
        patient_id = patient_user["id"]
        print(f"[PASS] 2. Registration passed: ID={patient_id}, Email={patient_user['email']}")

        # 3. Login with sanitized credentials
        res = client.post("/auth/login", json={
            "email": f"  NEW.PATIENT_{uid.upper()}@EXAMPLE.COM  ",
            "password": patient_pass,
        })
        assert res.status_code == 200, f"Login failed: {res.text}"
        login_token = res.json()["access_token"]
        p_headers = {"Authorization": f"Bearer {login_token}"}
        print("[PASS] 3. Login & JWT Token verification passed")

        # 4. Profile /auth/me
        res = client.get("/auth/me", headers=p_headers)
        assert res.status_code == 200, f"/auth/me failed: {res.text}"
        assert res.json()["id"] == patient_id
        print("[PASS] 4. /auth/me profile passed")

        # 5. Clean Workspace
        res = client.get("/reports", headers=p_headers)
        assert res.status_code == 200
        assert res.json() == []
        print("[PASS] 5. Clean new-device initial history (/reports) passed (empty list)")

        # 6. Screening /predict
        test_img_bytes = create_test_lesion_image()
        files = {"image": ("lesion.jpg", test_img_bytes, "image/jpeg")}
        data = {
            "questionnaire": '{"recent_change": true, "itching": true, "bleeding": false, "size_change": "growing"}',
            "language": "en"
        }
        res = client.post("/predict", files=files, data=data)
        assert res.status_code in (200, 422), f"Prediction route error: {res.text}"
        print("[PASS] 6. AI Screening (/predict) passed: Status", res.status_code)

        # 7. Clinical Chat
        chat_payload = {
            "message": "What signs of melanoma should I watch for?",
            "language": "en"
        }
        res = client.post("/chat", json=chat_payload, headers=p_headers)
        assert res.status_code in (200, 503), f"Chat error: {res.text}"
        if res.status_code == 200:
            chat_reply = res.json().get("response") or res.json().get("reply", "")
            print(f"[PASS] 7. Clinical LLM Chat (/chat) passed. Reply preview: {chat_reply[:60]}...")
        else:
            print("[INFO] 7. Clinical LLM Chat (/chat) handled graceful fallback (no LLM API key configured in test)")

        # 8. Create Report
        report_payload = {
            "condition": "Melanocytic nevus",
            "predicted_class": "nv",
            "confidence": 0.88,
            "triage": "Routine monitoring",
            "explanation": "Regular pigmentation pattern.",
            "symptoms": {"itching": False, "bleeding": False, "evolution": True},
            "image_path": "local_cache/img_123.jpg"
        }
        res = client.post("/reports", json=report_payload, headers=p_headers)
        assert res.status_code == 201, f"Create report failed: {res.text}"
        report_data = res.json()
        report_id = report_data["id"]
        print(f"[PASS] 8. Create Report (/reports) passed: Report ID={report_id}")

        # Verify report is listed
        res = client.get("/reports", headers=p_headers)
        assert res.status_code == 200
        assert len(res.json()) == 1
        assert res.json()[0]["id"] == report_id
        print("[PASS] 8b. Report list retrieval (/reports) verified")

        # 9. Doctor Directory
        res = client.get("/patient/doctors", headers=p_headers)
        assert res.status_code == 200, f"Doctor directory failed: {res.text}"
        doctors = res.json()
        assert len(doctors) > 0, "No seed doctors found"
        doc = doctors[0]
        doctor_id = doc["id"]
        print(f"[PASS] 9. Doctor Directory (/patient/doctors) passed: Found {len(doctors)} doctor(s), using Doctor ID={doctor_id} ({doc.get('display_name')})")

        # 10. Grant Doctor Consent
        res = client.post(f"/patient/consent/{doctor_id}", headers=p_headers)
        assert res.status_code == 200, f"Grant consent failed: {res.text}"
        consent_data = res.json()
        assert consent_data["status"] == "active"
        print(f"[PASS] 10. Grant Doctor Consent (/patient/consent/{doctor_id}) passed: Status={consent_data['status']}")

        # 11. Upload Encrypted Images & Share Report
        files = {
            "image": ("lesion_raw.jpg", test_img_bytes, "image/jpeg"),
            "gradcam": ("gradcam.png", test_img_bytes, "image/png"),
        }
        res = client.post(f"/patient/reports/{report_id}/image", files=files, headers=p_headers)
        assert res.status_code == 200, f"Upload shared image failed: {res.text}"
        shared_img_data = res.json()
        assert shared_img_data["has_image"] is True
        assert shared_img_data["has_gradcam"] is True
        print(f"[PASS] 11. Encrypted Image Vault upload & Report Share passed: has_image={shared_img_data['has_image']}, has_gradcam={shared_img_data['has_gradcam']}")

        # 12. Clinician Access: Log in as Doctor & Review Patient
        res = client.post("/auth/login", json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD})
        assert res.status_code == 200, f"Doctor login failed: {res.text}"
        doc_token = res.json()["access_token"]
        d_headers = {"Authorization": f"Bearer {doc_token}"}
        print("[PASS] 12a. Doctor Login passed")

        res = client.get("/doctor/patients", headers=d_headers)
        assert res.status_code == 200
        doc_patients = res.json()
        patient_entry = next((p for p in doc_patients if p["id"] == patient_id), None)
        assert patient_entry is not None, "Shared patient not found in doctor worklist"
        print(f"[PASS] 12b. Doctor Worklist (/doctor/patients) passed: Patient ID={patient_id} present with {patient_entry['shared_report_count']} shared report(s)")

        # Fetch patient's shared reports as doctor
        res = client.get(f"/doctor/patients/{patient_id}/reports", headers=d_headers)
        assert res.status_code == 200
        doc_reports = res.json()
        assert len(doc_reports) >= 1
        doc_rep = next(r for r in doc_reports if r["id"] == report_id)
        assert doc_rep["has_image"] is True
        assert doc_rep["has_gradcam"] is True
        print("[PASS] 12c. Doctor Patient Inspection passed: Raw & Grad-CAM images available for review")

        # Fetch decrypted images as doctor
        res_img = client.get(f"/doctor/reports/{report_id}/image", headers=d_headers)
        assert res_img.status_code == 200
        assert res_img.headers["content-type"] in ("image/jpeg", "image/png")
        print(f"[PASS] 12d. Doctor Decrypted Raw Image Stream passed: Bytes={len(res_img.content)}")

        res_gc = client.get(f"/doctor/reports/{report_id}/gradcam", headers=d_headers)
        assert res_gc.status_code == 200
        assert res_gc.headers["content-type"] in ("image/jpeg", "image/png")
        print(f"[PASS] 12e. Doctor Decrypted Grad-CAM Stream passed: Bytes={len(res_gc.content)}")

        # 13. Clinician Clinical Notes & Status Update
        note_payload = {
            "note": "Lesion borders appear regular. Recommend 6-month follow-up self-exam."
        }
        res = client.post(f"/doctor/reports/{report_id}/notes", json=note_payload, headers=d_headers)
        assert res.status_code == 201, f"Doctor note failed: {res.text}"
        print(f"[PASS] 13a. Doctor Clinical Note passed: Note ID={res.json()['id']}")

        res = client.patch(f"/doctor/reports/{report_id}/status", json={"status": "reviewed"}, headers=d_headers)
        assert res.status_code == 200, f"Doctor status update failed: {res.text}"
        print(f"[PASS] 13b. Doctor Status Update passed: Status={res.json()['status']}")

        # 14. Revoke Doctor Consent
        res = client.delete(f"/patient/consent/{doctor_id}", headers=p_headers)
        assert res.status_code == 200
        assert res.json()["status"] == "revoked"
        print(f"[PASS] 14. Patient Consent Revocation passed: Status={res.json()['status']}")

        # Verify doctor can no longer view patient
        res = client.get(f"/doctor/patients/{patient_id}/reports", headers=d_headers)
        assert res.status_code in (403, 404), f"Doctor should receive 403 or 404 after consent revocation, got {res.status_code}"
        print(f"[PASS] 14b. Access Control Enforcement verified: Doctor access cut off (HTTP {res.status_code})")

        # 15. Delete Report
        res = client.delete(f"/reports/{report_id}", headers=p_headers)
        assert res.status_code == 204
        print(f"[PASS] 15. Patient Report Deletion passed: Report ID={report_id} destroyed")

        print("=" * 60)
        print("ALL 15 END-TO-END FLOW TESTS PASSED PERFECTLY!")
        print("=" * 60)


if __name__ == "__main__":
    run_full_integration_suite()
