"""Temporary storage for uploaded images and Grad-CAM overlays.

Master specification, section 29: skin photographs are sensitive. The policy implemented
here is the minimum-retention one:

  * The uploaded photograph is **never written to disk.** It exists only as bytes in
    memory for the duration of the request.
  * Only the Grad-CAM overlay is persisted, because the client has to fetch it over HTTP
    to display it.
  * Overlays are named with an unguessable token, not a sequential id.
  * Everything older than `STORAGE_TTL_MINUTES` is deleted -- opportunistically on each
    write, and by a background task while the server runs.

Setting `STORAGE_TTL_MINUTES=0` disables persistence entirely; `/predict` then returns no
`gradcam_url`. That is the right setting if the deployment cannot guarantee the storage
directory is private.
"""

from __future__ import annotations

import logging
import secrets
import time
from pathlib import Path

from PIL import Image

logger = logging.getLogger(__name__)

GRADCAM_PREFIX = "gradcam_"
GRADCAM_SUFFIX = ".png"


class TemporaryStore:
    def __init__(self, directory: Path, ttl_minutes: int) -> None:
        self.directory = directory
        self.ttl_seconds = max(ttl_minutes, 0) * 60
        self.enabled = ttl_minutes > 0
        if self.enabled:
            self.directory.mkdir(parents=True, exist_ok=True)

    def save_overlay(self, image: Image.Image) -> str | None:
        """Persist an overlay and return its filename, or None if storage is disabled."""
        if not self.enabled:
            return None

        self.purge_expired()
        filename = f"{GRADCAM_PREFIX}{secrets.token_urlsafe(16)}{GRADCAM_SUFFIX}"
        image.save(self.directory / filename, format="PNG", optimize=True)
        return filename

    def path_for(self, filename: str) -> Path | None:
        """Resolve a filename to a path, refusing anything outside the storage directory.

        The filename arrives from a URL, so path traversal (`../../etc/passwd`) has to be
        blocked explicitly rather than assumed away.
        """
        if not self.enabled:
            return None
        if not filename.startswith(GRADCAM_PREFIX) or not filename.endswith(GRADCAM_SUFFIX):
            return None
        if "/" in filename or "\\" in filename or ".." in filename:
            return None

        candidate = (self.directory / filename).resolve()
        try:
            candidate.relative_to(self.directory.resolve())
        except ValueError:
            return None

        return candidate if candidate.is_file() else None

    def purge_expired(self) -> int:
        """Delete overlays past their TTL. Returns how many were removed."""
        if not self.enabled or not self.directory.is_dir():
            return 0

        cutoff = time.time() - self.ttl_seconds
        removed = 0
        for path in self.directory.glob(f"{GRADCAM_PREFIX}*{GRADCAM_SUFFIX}"):
            try:
                if path.stat().st_mtime < cutoff:
                    path.unlink()
                    removed += 1
            except OSError:
                # A file vanishing underneath us is fine -- another request may have
                # purged it. Anything else is not worth failing a prediction over.
                logger.debug("could not remove temporary file %s", path.name)
        if removed:
            logger.info("purged %d expired overlay(s)", removed)
        return removed

    def purge_all(self) -> int:
        """Delete every stored overlay. Called on shutdown."""
        if not self.enabled or not self.directory.is_dir():
            return 0
        removed = 0
        for path in self.directory.glob(f"{GRADCAM_PREFIX}*{GRADCAM_SUFFIX}"):
            try:
                path.unlink()
                removed += 1
            except OSError:
                pass
        return removed
