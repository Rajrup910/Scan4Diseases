"""Admin seed: create (or promote) a verified doctor account.

Doctors are never self-registered -- an administrator creates them out of band. This script
is that out-of-band step, so the doctor endpoints can be exercised end-to-end with curl and
pytest. It writes straight to the app database via the same engine the server uses.

Run from the repo root:

    .venv/Scripts/python.exe scripts/create_doctor.py \
        --email dr.rao@example.com --password "Str0ngPass!" \
        --name "Dr. A. Rao" --reg-no MH-12345

Behaviour:
  * A brand-new email creates a verified doctor.
  * An existing account is promoted to a verified doctor (role -> doctor, is_verified -> 1).
    Its password is only changed if --password is given; otherwise the existing one stands.
  * Nothing is ever deleted, and no other account is touched.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from sqlalchemy import select  # noqa: E402

from backend.app.db.models import ROLE_DOCTOR, User  # noqa: E402
from backend.app.db.session import SessionLocal, init_db  # noqa: E402
from backend.app.security import hash_password  # noqa: E402


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or promote a verified doctor account.")
    parser.add_argument("--email", required=True, help="Doctor's login email.")
    parser.add_argument(
        "--password",
        default=None,
        help="Password (required for a new account; optional when promoting an existing one).",
    )
    parser.add_argument("--name", default=None, help="Display name, e.g. 'Dr. A. Rao'.")
    parser.add_argument("--reg-no", dest="reg_no", default=None, help="Medical registration no.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    email = args.email.lower().strip()

    # Make sure the schema exists (harmless if it already does).
    init_db()

    db = SessionLocal()
    try:
        user = db.scalar(select(User).where(User.email == email))

        if user is None:
            if not args.password:
                print("A new doctor account needs --password.", file=sys.stderr)
                return 2
            if len(args.password) < 8:
                print("Password must be at least 8 characters.", file=sys.stderr)
                return 2
            user = User(
                email=email,
                display_name=(args.name.strip() if args.name else None) or None,
                password_hash=hash_password(args.password),
                role=ROLE_DOCTOR,
                is_verified=True,
                medical_reg_no=args.reg_no,
            )
            db.add(user)
            action = "Created"
        else:
            user.role = ROLE_DOCTOR
            user.is_verified = True
            if args.name:
                user.display_name = args.name.strip() or None
            if args.reg_no:
                user.medical_reg_no = args.reg_no
            if args.password:
                if len(args.password) < 8:
                    print("Password must be at least 8 characters.", file=sys.stderr)
                    return 2
                user.password_hash = hash_password(args.password)
            action = "Promoted"

        db.commit()
        db.refresh(user)
    finally:
        db.close()

    print(
        f"{action} verified doctor: id={user.id} email={user.email} "
        f"name={user.display_name!r} reg_no={user.medical_reg_no!r}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
