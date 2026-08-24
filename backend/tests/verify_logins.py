"""Verification script to test and validate logins for all demo doctors and demo patients.

Tests:
1. Patient 1 (raj@gmail.com) login via /auth/login
2. Patient 2 (ananya@gmail.com) login via /auth/login
3. Doctor 1 (dr.rao@example.com) login via /auth/login and /portal/login
4. Doctor 2 (dr.mehta@example.com) login via /auth/login and /portal/login
5. Patient report retrieval for both patients
6. Doctor worklist retrieval for both doctors
7. Security rejection tests (invalid credentials, patient trying to access doctor portal)
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from fastapi.testclient import TestClient
from backend.app.main import app
from backend.app.db.session import init_db, SessionLocal
from backend.app.db.seed import (
    DEMO_DOCTORS,
    PATIENT_2_EMAIL,
    PATIENT_2_NAME,
    PATIENT_2_PASSWORD,
    PATIENT_EMAIL,
    PATIENT_NAME,
    PATIENT_PASSWORD,
    seed_default_data,
)


def verify_all_logins():
    print("=" * 70)
    print("VERIFYING ALL DEMO DOCTOR & PATIENT LOGINS ACROSS API & WEB PORTAL")
    print("=" * 70)

    # 1. Seed database
    init_db()
    with SessionLocal() as db:
        seed_default_data(db)

    client = TestClient(app)

    # --- Test 1: Patient 1 API Login (raj@gmail.com) ---
    res_p1 = client.post("/auth/login", json={"email": PATIENT_EMAIL, "password": PATIENT_PASSWORD})
    assert res_p1.status_code == 200, f"Patient 1 login failed: {res_p1.text}"
    data_p1 = res_p1.json()
    token_p1 = data_p1["access_token"]
    user_p1 = data_p1["user"]
    assert user_p1["email"] == PATIENT_EMAIL
    assert user_p1["role"] == "patient"
    print(f"[PASS] Patient 1 API Login: {user_p1['display_name']} ({user_p1['email']}) -> Role: {user_p1['role']}")

    # Patient 1 reports check
    rep_p1 = client.get("/reports", headers={"Authorization": f"Bearer {token_p1}"})
    assert rep_p1.status_code == 200
    print(f"       -> Retrieved {len(rep_p1.json())} reports for {user_p1['display_name']}")

    # --- Test 2: Patient 2 API Login (ananya@gmail.com) ---
    res_p2 = client.post("/auth/login", json={"email": PATIENT_2_EMAIL, "password": PATIENT_2_PASSWORD})
    assert res_p2.status_code == 200, f"Patient 2 login failed: {res_p2.text}"
    data_p2 = res_p2.json()
    token_p2 = data_p2["access_token"]
    user_p2 = data_p2["user"]
    assert user_p2["email"] == PATIENT_2_EMAIL
    assert user_p2["role"] == "patient"
    print(f"[PASS] Patient 2 API Login: {user_p2['display_name']} ({user_p2['email']}) -> Role: {user_p2['role']}")

    # Patient 2 reports check
    rep_p2 = client.get("/reports", headers={"Authorization": f"Bearer {token_p2}"})
    assert rep_p2.status_code == 200
    print(f"       -> Retrieved {len(rep_p2.json())} reports for {user_p2['display_name']}")

    # --- Test 3: Comprehensive Login Verification for ALL DEMO DOCTORS ---
    print(f"\nVerifying {len(DEMO_DOCTORS)} Demo Doctors:")
    for idx, (doc_name, doc_email, doc_pass, doc_reg) in enumerate(DEMO_DOCTORS, 1):
        # API Login
        res_doc = client.post("/auth/login", json={"email": doc_email, "password": doc_pass})
        assert res_doc.status_code == 200, f"Doctor {idx} ({doc_email}) API login failed: {res_doc.text}"
        data_doc = res_doc.json()
        token_doc = data_doc["access_token"]
        user_doc = data_doc["user"]
        assert user_doc["email"] == doc_email
        assert user_doc["role"] == "doctor"

        # Web Portal Form Login
        portal_res = client.post(
            "/portal/login",
            data={"email": doc_email, "password": doc_pass},
            follow_redirects=False,
        )
        assert portal_res.status_code == 303, f"Doctor {idx} portal login expected 303 redirect, got {portal_res.status_code}"
        assert "portal_session" in portal_res.cookies, f"Doctor {idx} ({doc_email}) portal session cookie not set"

        # Doctor Worklist check
        worklist_res = client.get("/doctor/patients", headers={"Authorization": f"Bearer {token_doc}"})
        assert worklist_res.status_code == 200

        print(f"[PASS] Doctor {idx}: {doc_name} ({doc_email}) -> API & Portal Logins OK, Worklist sees {len(worklist_res.json())} patients")

    # --- Test 4: Doctor Directory Verification & 100% Login Validation ---
    doc_res = client.get("/patient/doctors", headers={"Authorization": f"Bearer {token_p1}"})
    assert doc_res.status_code == 200, f"Doctor directory query failed: {doc_res.text}"
    doctor_list = doc_res.json()
    assert len(doctor_list) == len(DEMO_DOCTORS), f"Expected exactly {len(DEMO_DOCTORS)} verified doctors, but found {len(doctor_list)}"
    print(f"\n[PASS] Doctor Directory Verification: Found exactly {len(doctor_list)} verified doctors available for sharing:")
    for d in doctor_list:
        print(f"       -> ID={d['id']} | Name={d.get('display_name')} | Reg={d.get('medical_reg_no')} | Email={d['email']}")
        # Ensure every doctor in the directory can log in
        d_login = client.post("/auth/login", json={"email": d["email"], "password": "Str0ngPass!"})
        assert d_login.status_code == 200, f"Doctor directory entry {d['email']} failed to log in!"

    # --- Test 5: Security / RBAC Rejection Checks ---
    # Invalid password check
    bad_login = client.post("/auth/login", json={"email": "dr.rao@example.com", "password": "WrongPassword123"})
    assert bad_login.status_code == 401
    print("[PASS] Security Check: Incorrect password correctly returns 401 Unauthorized")

    # Patient cannot access doctor portal
    patient_portal = client.post(
        "/portal/login",
        data={"email": PATIENT_2_EMAIL, "password": PATIENT_2_PASSWORD},
        follow_redirects=False,
    )
    assert patient_portal.status_code == 403 or "portal_session" not in patient_portal.cookies
    print("[PASS] RBAC Check: Patient account correctly denied clinician portal access")

    print("\n" + "=" * 70)
    print("ALL DEMO LOGIN & DIRECTORY VERIFICATIONS PASSED SUCCESSFULLY!")
    print("=" * 70 + "\n")


if __name__ == "__main__":
    verify_all_logins()
