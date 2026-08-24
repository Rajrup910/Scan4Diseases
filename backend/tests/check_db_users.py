from backend.app.db.session import SessionLocal
from backend.app.db.models import User

print("=== LOCAL DATABASE (Direct Query) ===")
with SessionLocal() as db:
    users = db.query(User).all()
    for u in users:
        print(f"ID={u.id:<3} | Role={u.role:<8} | Email={u.email:<25} | Name={u.display_name}")

