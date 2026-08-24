"""Security audit log: an append-only record of who did what, to which object, from where.

The `AuditLog` table has existed since the schema was first written; this module is the one
place that writes to it, so the set of audited actions stays in a single, reviewable vocab
(the `ACTION_*` constants below) rather than being spelled out ad hoc at each call site.

Commit semantics (deliberate, and the reason this is a service and not an inline `db.add`):

* `record()` **commits its own row on the caller's session.** Callers therefore invoke it
  *after* their business `db.commit()` (or when there is no business write at all, e.g. a
  rejected login). The audit row then lands in its own transaction -- it never rides on, and
  is never rolled back with, the business transaction. A business rollback cannot silently
  discard the audit trail, and (below) an audit failure cannot roll back real work.
* It is **non-fatal.** Any database error while writing the audit row is caught, rolled back
  (clearing the failed row so the request's session is usable again) and logged in full with
  `logger.exception` -- it must fail loudly in the logs but must never turn a real 2xx/4xx
  request into a 500. The security record is important, but losing one entry is preferable to
  failing the user's action or, worse, masking what actually happened.

The client IP is read straight from the connection (`request.client.host`); no proxy header
(`X-Forwarded-For` etc.) is trusted, because nothing in this deployment sits behind a proxy
that sets one -- trusting it unconditionally would let any caller spoof the recorded IP.
"""

from __future__ import annotations

import logging

from fastapi import Request
from sqlalchemy.orm import Session

from backend.app.db.models import AuditLog

logger = logging.getLogger(__name__)

# --- action vocabulary (stable strings; stored verbatim, so treat them as an API) --------

ACTION_LOGIN_SUCCESS = "login_success"
ACTION_LOGIN_FAILURE = "login_failure"  # actor_id is NULL: the caller never authenticated
ACTION_LOGOUT = "logout"
ACTION_REPORT_VIEW = "report_view"
ACTION_IMAGE_VIEW = "image_view"
ACTION_GRADCAM_VIEW = "gradcam_view"
ACTION_STATUS_CHANGE = "status_change"
ACTION_NOTE_ADD = "note_add"
ACTION_CONSENT_GRANT = "consent_grant"
ACTION_CONSENT_REVOKE = "consent_revoke"
ACTION_REPORT_SHARE = "report_share"
ACTION_REPORT_UNSHARE = "report_unshare"

# --- target-type vocabulary --------------------------------------------------------------

TARGET_USER = "user"
TARGET_REPORT = "report"


def client_ip(request: Request | None) -> str | None:
    """The peer IP for this request, or None. Reads only the socket -- never a forwarded-for
    header -- so the recorded value cannot be spoofed by a client that sets one."""
    if request is None or request.client is None:
        return None
    return request.client.host


def record(
    db: Session,
    actor_id: int | None,
    action: str,
    *,
    target_type: str | None = None,
    target_id: int | None = None,
    ip: str | None = None,
) -> None:
    """Write one audit row and commit it, on its own transaction. Never raises.

    Call this *after* the business commit (or when there is no business write). `actor_id` is
    NULL for anonymous/failed actions such as a rejected login. See the module docstring for
    the commit and failure semantics.
    """
    try:
        db.add(
            AuditLog(
                actor_id=actor_id,
                action=action,
                target_type=target_type,
                target_id=target_id,
                ip=ip,
            )
        )
        db.commit()
    except Exception:  # noqa: BLE001 - an audit failure must never break the real request
        # Fail loudly in the logs, quietly to the caller. Roll back so the failed INSERT does
        # not leave the session unusable for whatever the handler does next.
        logger.exception(
            "audit write failed (action=%s target=%s:%s actor=%s)",
            action, target_type, target_id, actor_id,
        )
        try:
            db.rollback()
        except Exception:  # noqa: BLE001
            logger.exception("audit rollback also failed")
