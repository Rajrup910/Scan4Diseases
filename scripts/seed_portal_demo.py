"""Seed the local database with demo data so the clinician portal and patient app have demo accounts.

Creates verified doctors, consented patients, and shared screening reports.
Idempotent: re-running does not duplicate accounts or reports.

    .venv/Scripts/python.exe scripts/seed_portal_demo.py

Login afterwards:
  Doctor Portal: http://localhost:8000/portal/login
  Patient API / Mobile: http://localhost:8000/auth/login
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from backend.app.db.seed import (  # noqa: E402
    DEMO_DOCTORS,
    PATIENT_2_EMAIL,
    PATIENT_2_NAME,
    PATIENT_2_PASSWORD,
    PATIENT_EMAIL,
    PATIENT_NAME,
    PATIENT_PASSWORD,
    seed_default_data,
)
from backend.app.db.session import SessionLocal, init_db  # noqa: E402


def main() -> int:
    init_db()
    db = SessionLocal()
    try:
        seed_default_data(db)
    finally:
        db.close()

    print("\n" + "=" * 60)
    print("DEMO USERS SEEDED & READY")
    print("=" * 60)
    print("\nCLINICIAN WEB PORTAL ACCOUNTS (http://localhost:8000/portal/login):")
    for i, (name, email, pwd, reg) in enumerate(DEMO_DOCTORS, 1):
        print(f"  {i}. {name} (Reg: {reg})")
        print(f"     Email:    {email}")
        print(f"     Password: {pwd}")

    print("\nPATIENT MOBILE / API ACCOUNTS (http://localhost:8000/auth/login):")
    print(f"  1. {PATIENT_NAME}")
    print(f"     Email:    {PATIENT_EMAIL}")
    print(f"     Password: {PATIENT_PASSWORD}")
    print(f"  2. {PATIENT_2_NAME}")
    print(f"     Email:    {PATIENT_2_EMAIL}")
    print(f"     Password: {PATIENT_2_PASSWORD}")
    print(f"  3. Demo Patients: priya@example.com, aarav@example.com, rohan@example.com, neha@example.com")
    print(f"     Password: 12345678")
    print("=" * 60 + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


