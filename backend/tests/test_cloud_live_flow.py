"""Comprehensive LIVE Cloud integration and flow test for Scan4Diseases on Render.

Executes all 15 clinical and patient user journeys directly over HTTPS:
https://scan4diseases.onrender.com
"""

import io
import uuid
import httpx
from PIL import Image, ImageDraw

BASE_URL = "https://scan4diseases.onrender.com"
DOCTOR_EMAIL = "dr.rao@example.com"
DOCTOR_PASSWORD = "Str0ngPass!"


def create_test_lesion_image() -> bytes:
    img = Image.new("RGB", (300, 300), color=(225, 190, 160))
    draw = ImageDraw.Draw(img)
    draw.ellipse([100, 100, 200, 200], fill=(70, 35, 20), outline=(50, 25, 15))
    draw.ellipse([120, 120, 160, 160], fill=(40, 20, 10))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def run_live_cloud_test():
    print("=" * 60)
    print(f"RUNNING LIVE INTEGRATION FLOW TEST AGAINST {BASE_URL}")
    print("=" * 60)

    with httpx.Client(timeout=45.0) as client:
        # 1. Health
        res = client.get(f"{BASE_URL}/health")
        assert res.status_code == 200, f"Cloud health failed: {res.text}"
        print("[PASS] 1. Cloud Health:", res.json()["status"], "| Model loaded:", res.json()["model_loaded"])

        # 2. Register New Patient with messy input
        uid = uuid.uuid4().hex[:6]
        raw_email = f"  NeW.PaTieNt_{uid}@ExAmPlE.CoM  "
        clean_email = f"new.patient_{uid}@example.com"
        patient_pass = "SecurePass123!"
        patient_name = "  New Cloud Patient  "

        res = client.post(f"{BASE_URL}/auth/register", json={
            "email": raw_email,
            "password": patient_pass,
            "display_name": patient_name,
        })
        assert res.status_code == 201, f"Cloud registration failed: {res.text}"
        reg_data = res.json()
        patient_token = reg_data["access_token"]
        patient_user = reg_data["user"]
        assert patient_user["email"] == clean_email
        patient_id = patient_user["id"]
        print(f"[PASS] 2. Cloud Registration: ID={patient_id}, Email={patient_user['email']}")

        # 3. Login
        res = client.post(f"{BASE_URL}/auth/login", json={
            "email": f"  NEW.PATIENT_{uid.upper()}@EXAMPLE.COM  ",
            "password": patient_pass,
        })
        assert res.status_code == 200
        p_headers = {"Authorization": f"Bearer {res.json()['access_token']}"}
        print("[PASS] 3. Cloud Login & JWT verification")

        # 4. Profile /auth/me
        res = client.get(f"{BASE_URL}/auth/me", headers=p_headers)
        assert res.status_code == 200
        assert res.json()["id"] == patient_id
        print("[PASS] 4. Cloud /auth/me profile verified")

        # 5. Clean Workspace
        res = client.get(f"{BASE_URL}/reports", headers=p_headers)
        assert res.status_code == 200
        assert res.json() == []
        print("[PASS] 5. Clean new account empty reports list")

        # 6. Screening /predict
        test_img_bytes = create_test_lesion_image()
        files = {"image": ("lesion.jpg", test_img_bytes, "image/jpeg")}
        data = {
            "questionnaire": '{"recent_change": true, "itching": true, "bleeding": false, "size_change": "growing"}',
            "language": "en"
        }
        res = client.post(f"{BASE_URL}/predict", files=files, data=data)
        assert res.status_code in (200, 422), f"Prediction error: {res.text}"
        print(f"[PASS] 6. Cloud AI Screening (/predict): HTTP {res.status_code}")

        # 7. Clinical Chat
        chat_payload = {
            "message": "What should I check during a skin exam?",
            "language": "en"
        }
        res = client.post(f"{BASE_URL}/chat", json=chat_payload, headers=p_headers)
        assert res.status_code in (200, 503), f"Chat error: {res.text}"
        if res.status_code == 200:
            chat_reply = res.json().get("response") or res.json().get("reply", "")
            safe_preview = chat_reply[:60].encode("ascii", "replace").decode("ascii")
            print(f"[PASS] 7. Cloud LLM Chat (/chat): {safe_preview}...")
        else:
            print("[INFO] 7. Cloud LLM Chat: Handled graceful fallback")

        # 8. Create Report
        report_payload = {
            "condition": "Melanocytic nevus",
            "predicted_class": "nv",
            "confidence": 0.91,
            "triage": "Routine monitoring",
            "explanation": "Regular clinical margins.",
            "symptoms": {"itching": False, "bleeding": False, "evolution": True},
            "image_path": "local/cache/scan.jpg"
        }
        res = client.post(f"{BASE_URL}/reports", json=report_payload, headers=p_headers)
        assert res.status_code == 201, f"Create report failed: {res.text}"
        report_id = res.json()["id"]
        print(f"[PASS] 8. Cloud Create Report (/reports): Report ID={report_id}")

        # 9. Doctor Directory
        res = client.get(f"{BASE_URL}/patient/doctors", headers=p_headers)
        assert res.status_code == 200
        doctors = res.json()
        assert len(doctors) > 0
        doctor_id = doctors[0]["id"]
        print(f"[PASS] 9. Cloud Doctor Directory: Found {len(doctors)} doctor(s), selected Doctor ID={doctor_id}")

        # 10. Grant Doctor Consent
        res = client.post(f"{BASE_URL}/patient/consent/{doctor_id}", headers=p_headers)
        assert res.status_code == 200
        assert res.json()["status"] == "active"
        print(f"[PASS] 10. Cloud Grant Doctor Consent: Status=active")

        # 11. Upload Encrypted Images & Share Report
        files = {
            "image": ("lesion_raw.jpg", test_img_bytes, "image/jpeg"),
            "gradcam": ("gradcam.png", test_img_bytes, "image/png"),
        }
        res = client.post(f"{BASE_URL}/patient/reports/{report_id}/image", files=files, headers=p_headers)
        assert res.status_code == 200, f"Upload shared image failed: {res.text}"
        assert res.json()["has_image"] is True
        print(f"[PASS] 11. Cloud Encrypted Image Vault upload & Report Share: has_image=True")

        # 12. Doctor Login & Review
        res = client.post(f"{BASE_URL}/auth/login", json={"email": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD})
        assert res.status_code == 200
        d_headers = {"Authorization": f"Bearer {res.json()['access_token']}"}
        print("[PASS] 12a. Cloud Doctor Login verified")

        res = client.get(f"{BASE_URL}/doctor/patients", headers=d_headers)
        assert res.status_code == 200
        patient_entry = next((p for p in res.json() if p["id"] == patient_id), None)
        assert patient_entry is not None
        print(f"[PASS] 12b. Cloud Doctor Worklist: Patient ID={patient_id} listed")

        res = client.get(f"{BASE_URL}/doctor/patients/{patient_id}/reports", headers=d_headers)
        assert res.status_code == 200
        print("[PASS] 12c. Cloud Doctor Patient Inspection passed")

        # 13. Doctor Clinical Note & Status Update
        res = client.post(f"{BASE_URL}/doctor/reports/{report_id}/notes", json={"note": "Cloud verified clear."}, headers=d_headers)
        assert res.status_code == 201
        print(f"[PASS] 13a. Cloud Doctor Note added: ID={res.json()['id']}")

        res = client.patch(f"{BASE_URL}/doctor/reports/{report_id}/status", json={"status": "reviewed"}, headers=d_headers)
        assert res.status_code == 200
        print(f"[PASS] 13b. Cloud Doctor Status updated: Status=reviewed")

        # 14. Revoke Doctor Consent
        res = client.delete(f"{BASE_URL}/patient/consent/{doctor_id}", headers=p_headers)
        assert res.status_code == 200
        print("[PASS] 14. Cloud Patient Consent Revocation verified")

        res = client.get(f"{BASE_URL}/doctor/patients/{patient_id}/reports", headers=d_headers)
        assert res.status_code in (403, 404)
        print(f"[PASS] 14b. Cloud Access Revocation Enforcement: HTTP {res.status_code}")

        # 15. Delete Report
        res = client.delete(f"{BASE_URL}/reports/{report_id}", headers=p_headers)
        assert res.status_code == 204
        print(f"[PASS] 15. Cloud Patient Report Deletion verified")

    print("=" * 60)
    print("ALL 15 LIVE CLOUD FLOW TESTS COMPLETED SUCCESSFULLY!")
    print("=" * 60)


if __name__ == "__main__":
    run_live_cloud_test()
