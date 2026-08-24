"""One-off, idempotent upgrade of an EXISTING SQLite database to the doctor-portal schema.

Fresh databases need nothing: `create_all()` (run at app startup and in the test suite)
builds the full current schema, new columns and tables included. This script exists only
to bring an *already-populated* dev database up to the new schema without losing rows --
SQLite's `create_all` creates missing tables but never adds columns to existing ones.

What it does, safely and repeatably:
  1. Copies the database to a timestamped `.bak` first.
  2. Adds any missing columns to `users` and `reports` (skips ones already present).
  3. Creates the new tables (`doctor_patient`, `doctor_notes`, `audit_log`) via
     `create_all`, which is a no-op for tables that already exist.

Run from the repo root:

    .venv/Scripts/python.exe scripts/upgrade_db_doctor_portal.py

Running it twice is harmless.
"""

from __future__ import annotations

import shutil
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from backend.app.config import get_settings  # noqa: E402

# column name -> SQLite column definition (NOT NULL columns carry a constant DEFAULT so
# existing rows get a valid value, which SQLite's ADD COLUMN requires).
_NEW_COLUMNS: dict[str, dict[str, str]] = {
    "users": {
        "role": "VARCHAR(20) NOT NULL DEFAULT 'patient'",
        "is_verified": "BOOLEAN NOT NULL DEFAULT 0",
        "medical_reg_no": "VARCHAR(64)",
    },
    "reports": {
        "status": "VARCHAR(20) NOT NULL DEFAULT 'new'",
        "image_path": "VARCHAR(255)",
        "gradcam_path": "VARCHAR(255)",
        "shared_at": "DATETIME",
    },
}


def _existing_columns(cur: sqlite3.Cursor, table: str) -> set[str]:
    return {row[1] for row in cur.execute(f"PRAGMA table_info({table})").fetchall()}


def _existing_tables(cur: sqlite3.Cursor) -> set[str]:
    return {
        row[0]
        for row in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
    }


def main() -> int:
    settings = get_settings()
    db_path = settings.database_file

    if not db_path.exists():
        print(f"No existing database at {db_path}.")
        print("Nothing to migrate -- a fresh one gets the full schema from create_all().")
        return 0

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup = db_path.with_suffix(db_path.suffix + f".bak-{stamp}")
    shutil.copy2(db_path, backup)
    print(f"Backed up {db_path.name} -> {backup.name}")

    added: list[str] = []
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        tables = _existing_tables(cur)
        for table, columns in _NEW_COLUMNS.items():
            if table not in tables:
                # Table itself is missing; create_all below will build it in full.
                continue
            present = _existing_columns(cur, table)
            for name, ddl in columns.items():
                if name in present:
                    continue
                cur.execute(f"ALTER TABLE {table} ADD COLUMN {name} {ddl}")
                added.append(f"{table}.{name}")
        conn.commit()
    finally:
        conn.close()

    if added:
        print("Added columns: " + ", ".join(added))
    else:
        print("No columns to add (already up to date).")

    # Create the new tables. create_all only builds what is missing, so existing tables
    # (and their data) are untouched.
    from backend.app.db.session import Base, engine  # noqa: E402
    from backend.app.db import models  # noqa: F401,E402  (register mappers)

    before = _tables_via_engine(engine)
    Base.metadata.create_all(bind=engine)
    after = _tables_via_engine(engine)
    created = sorted(after - before)
    if created:
        print("Created tables: " + ", ".join(created))
    else:
        print("No tables to create (already present).")

    print("\nFinal schema:")
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        for table in sorted(_existing_tables(cur)):
            if table == "sqlite_sequence":
                continue
            cols = ", ".join(sorted(_existing_columns(cur, table)))
            print(f"  {table}: {cols}")
    finally:
        conn.close()

    print(f"\nDone. Backup kept at {backup.name} -- delete it once you have verified the app.")
    return 0


def _tables_via_engine(engine) -> set[str]:
    from sqlalchemy import inspect

    return set(inspect(engine).get_table_names())


if __name__ == "__main__":
    raise SystemExit(main())
