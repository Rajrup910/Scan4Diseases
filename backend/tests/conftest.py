"""Shared test fixtures.

Tests run without a trained checkpoint and without Ollama. That is deliberate: the suite
has to pass on a fresh clone and in CI, where neither exists.
"""

from __future__ import annotations

import io
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def sharp_image() -> Image.Image:
    """A synthetic image that passes the quality gate.

    Random noise gives a high Laplacian variance (sharp) and mid-range brightness, which
    is exactly what the gate wants. It is not a lesion, but the gate does not claim to
    detect lesions -- see services/quality.py.
    """
    rng = np.random.default_rng(1234)
    base = rng.integers(90, 190, size=(600, 600, 3), dtype=np.uint8)
    return Image.fromarray(base)


@pytest.fixture
def blurred_image() -> Image.Image:
    from PIL import ImageFilter

    rng = np.random.default_rng(99)
    base = Image.fromarray(rng.integers(90, 190, size=(600, 600, 3), dtype=np.uint8))
    return base.filter(ImageFilter.GaussianBlur(radius=12))


@pytest.fixture
def dark_image() -> Image.Image:
    return Image.new("RGB", (600, 600), (5, 5, 6))


@pytest.fixture
def overexposed_image() -> Image.Image:
    return Image.new("RGB", (600, 600), (252, 252, 250))


@pytest.fixture
def tiny_image() -> Image.Image:
    return Image.new("RGB", (40, 40), (150, 120, 110))


def encode(image: Image.Image, fmt: str = "JPEG") -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format=fmt, quality=95)
    return buffer.getvalue()


@pytest.fixture
def image_bytes(sharp_image: Image.Image) -> bytes:
    return encode(sharp_image)


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    """App in stub mode with the LLM disabled, storage in a temp directory."""
    monkeypatch.setenv("ALLOW_STUB_MODEL", "true")
    monkeypatch.setenv("LLM_ENABLED", "false")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.setenv("STORAGE_TTL_MINUTES", "15")
    monkeypatch.setenv("MODEL_CHECKPOINT", str(tmp_path / "does_not_exist.pt"))

    from backend.app.config import get_settings

    get_settings.cache_clear()

    from backend.app.main import create_app

    with TestClient(create_app()) as test_client:
        yield test_client

    get_settings.cache_clear()


@pytest.fixture
def strict_client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    """App with stub mode OFF and no checkpoint -- /predict must return 503."""
    monkeypatch.setenv("ALLOW_STUB_MODEL", "false")
    monkeypatch.setenv("LLM_ENABLED", "false")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.setenv("MODEL_CHECKPOINT", str(tmp_path / "does_not_exist.pt"))

    from backend.app.config import get_settings

    get_settings.cache_clear()

    from backend.app.main import create_app

    with TestClient(create_app()) as test_client:
        yield test_client

    get_settings.cache_clear()
