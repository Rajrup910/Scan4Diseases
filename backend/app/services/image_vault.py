"""Encrypted, persistent store for patient-shared images.

This is the counterpart to `TemporaryStore`, and its opposite in intent. `TemporaryStore`
holds short-lived Grad-CAM overlays in the clear and deletes them on a timer. The vault
holds the images a patient has *chosen* to share with a doctor, and:

  * writes them **encrypted** (Fernet / AES-128-CBC + HMAC) -- the bytes on disk are
    ciphertext and are useless without the key, so a leaked `backend/storage` directory
    does not leak patient photographs;
  * keeps them until the patient **unshares** (no TTL), because a doctor may open a shared
    report at any later time;
  * names each blob with an unguessable token, never a sequential id or a patient-derived
    name, and refuses any filename that would escape the vault directory;
  * self-describes its content type, so serving does not have to guess whether a blob is a
    JPEG photo or a PNG overlay.

The key comes from `IMAGE_ENCRYPTION_KEY` (see `config.py`). If it is unset the vault is
*unconfigured*: it starts fine, but any store/load raises loudly rather than silently
falling back to writing plaintext.
"""

from __future__ import annotations

import logging
import secrets
from pathlib import Path

from cryptography.fernet import Fernet, InvalidToken

from backend.app.utils.errors import AppError

logger = logging.getLogger(__name__)

BLOB_PREFIX = "simg_"
BLOB_SUFFIX = ".enc"
# The content type is stored as the first line of the plaintext, before the image bytes,
# so a blob is self-describing without a sidecar file or a parallel DB column.
_HEADER_SEP = b"\n"


class ImageVault:
    """Fernet-encrypted blob store for shared patient images."""

    def __init__(self, directory: Path, key: str | None) -> None:
        self.directory = directory
        self._fernet: Fernet | None = None
        if key:
            try:
                self._fernet = Fernet(key)
            except (ValueError, TypeError) as exc:
                # A malformed key is a deployment error, not a per-request one. Log it and
                # stay unconfigured so the app still starts; the first image op will 500.
                logger.error("IMAGE_ENCRYPTION_KEY is not a valid Fernet key: %s", exc)
                self._fernet = None
        if self._fernet is not None:
            self.directory.mkdir(parents=True, exist_ok=True)

    @property
    def configured(self) -> bool:
        return self._fernet is not None

    def _require(self) -> Fernet:
        if self._fernet is None:
            raise AppError(
                "image_encryption_unavailable",
                "Sharing images is not available on this server right now.",
                status_code=503,
                detail="IMAGE_ENCRYPTION_KEY is not set or is invalid",
            )
        return self._fernet

    def store(self, data: bytes, media_type: str) -> str:
        """Encrypt `data` and write it under a fresh token filename; return that filename.

        The returned name is what belongs in `Report.image_path` / `gradcam_path` -- a blob
        reference, never a servable path.
        """
        fernet = self._require()
        plaintext = media_type.encode("ascii") + _HEADER_SEP + data
        token = fernet.encrypt(plaintext)
        filename = f"{BLOB_PREFIX}{secrets.token_urlsafe(24)}{BLOB_SUFFIX}"
        (self.directory / filename).write_bytes(token)
        return filename

    def _path_for(self, filename: str) -> Path | None:
        """Resolve a stored blob filename to a path inside the vault, or None.

        The filename comes off a DB row we wrote, but it is still validated the same way a
        URL segment would be: right prefix/suffix, no separators, and it must resolve inside
        the vault directory (defence-in-depth against traversal).
        """
        if not filename.startswith(BLOB_PREFIX) or not filename.endswith(BLOB_SUFFIX):
            return None
        if "/" in filename or "\\" in filename or ".." in filename:
            return None
        candidate = (self.directory / filename).resolve()
        try:
            candidate.relative_to(self.directory.resolve())
        except ValueError:
            return None
        return candidate if candidate.is_file() else None

    def load(self, filename: str) -> tuple[str, bytes] | None:
        """Decrypt a stored blob, returning `(media_type, image_bytes)`, or None if the blob
        is missing or unreadable. A corrupt/forged blob (bad HMAC) returns None, not bytes."""
        fernet = self._require()
        path = self._path_for(filename)
        if path is None:
            return None
        try:
            plaintext = fernet.decrypt(path.read_bytes())
        except (InvalidToken, OSError) as exc:
            logger.warning("could not decrypt shared image %s: %s", filename, exc)
            return None
        media_type, _, data = plaintext.partition(_HEADER_SEP)
        return media_type.decode("ascii", "replace"), data

    def remove(self, filename: str | None) -> bool:
        """Delete a stored blob if it exists. Safe to call with None or an unknown name;
        used when a patient unshares so the plaintext image never lingers encrypted-at-rest
        past the moment consent is withdrawn."""
        if not filename:
            return False
        path = self._path_for(filename)
        if path is None:
            return False
        try:
            path.unlink()
            return True
        except OSError:
            logger.debug("could not remove shared image %s", filename)
            return False
