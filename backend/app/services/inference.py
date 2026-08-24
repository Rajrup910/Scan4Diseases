"""Model lifecycle and prediction.

One `InferenceService` is created at application start-up and reused for every request.
Loading a 90 MB checkpoint per request would be absurd, and a per-request Grad-CAM hook
registration that never gets removed is a slow memory leak -- both are handled here.

**Stub mode.** If no checkpoint exists and `ALLOW_STUB_MODEL=true`, the service serves
obviously-synthetic predictions so the mobile team can build screens before training
finishes. Every stubbed response is flagged `"stub": true`, `/health` reports
`stub_mode: true`, and a warning is logged on every call. It must never be enabled for a
demo or evaluation.
"""

from __future__ import annotations

import hashlib
import logging
import time
from dataclasses import dataclass, field
from typing import Any

import numpy as np
import torch
from PIL import Image

from backend.app.config import Settings
from backend.app.models.classes import ClassMapping, load_class_mapping
from backend.app.models.classifier import gradcam_target_layer, load_classifier, resolve_device
from backend.app.services.gradcam import GradCAM, cam_statistics, describe_focus, overlay_heatmap
from backend.app.services.ood import extract_features
from backend.app.services.preprocessing import to_tensor

logger = logging.getLogger(__name__)


class ModelUnavailableError(RuntimeError):
    """No usable model. The route turns this into a 503."""


@dataclass
class InferenceResult:
    predicted_code: str
    predicted_index: int
    confidence: float
    probabilities: dict[str, float]
    gradcam: np.ndarray | None = None
    gradcam_focus: str | None = None
    gradcam_stats: dict[str, Any] = field(default_factory=dict)
    overlay: Image.Image | None = None
    inference_ms: float = 0.0
    stub: bool = False


class InferenceService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.mapping: ClassMapping = load_class_mapping(settings.class_mapping_file)
        self.device = resolve_device(settings.model_device)

        self.model: torch.nn.Module | None = None
        self.checkpoint_meta: dict[str, Any] = {}
        self.arch: str | None = None
        self.image_size: int = settings.model_image_size
        self.load_error: str | None = None

    # --- lifecycle ---

    def load(self) -> None:
        """Load the checkpoint. Never raises -- a failed load leaves the service degraded
        so `/health` can report the problem instead of the process refusing to start."""
        path = self.settings.checkpoint_path
        if not path.is_file():
            self.load_error = f"no checkpoint at {path.name}"
            level = logger.warning if self.settings.allow_stub_model else logger.error
            level(
                "Model not loaded: %s. %s",
                self.load_error,
                "Serving STUB predictions." if self.settings.allow_stub_model
                else "/predict will return 503 until a checkpoint is trained.",
            )
            return

        try:
            model, payload = load_classifier(path, self.mapping.codes, self.device)
        except Exception as exc:  # noqa: BLE001 - report, don't crash the server
            self.load_error = str(exc)
            logger.error("Failed to load checkpoint %s: %s", path.name, exc)
            return

        # Freeze parameters to optimize memory during serving
        for p in model.parameters():
            p.requires_grad = False

        self.model = model
        self.checkpoint_meta = {k: v for k, v in payload.items() if k not in ("state_dict", "config", "history")}
        self.arch = payload["arch"]
        self.image_size = payload.get("image_size", self.settings.model_image_size)
        self.load_error = None

        logger.info(
            "Loaded %s from %s (epoch %s, val %s=%.4f) on %s",
            self.arch,
            path.name,
            payload.get("epoch"),
            payload.get("monitor_metric"),
            payload.get("monitor_value", float("nan")),
            self.device,
        )

    def unload(self) -> None:
        self.model = None
        if self.device.type == "cuda":
            torch.cuda.empty_cache()

    @property
    def is_loaded(self) -> bool:
        return self.model is not None

    @property
    def stub_mode(self) -> bool:
        return not self.is_loaded and self.settings.allow_stub_model

    def penultimate_features(self, image: Image.Image) -> np.ndarray | None:
        """Penultimate feature vector for OOD scoring, or None if no model is loaded.

        Uses the same preprocessing and the same layer the fitted OOD statistics were
        built from, so the two are directly comparable.
        """
        if not self.is_loaded:
            return None
        assert self.model is not None
        tensor = to_tensor(image, self.image_size).to(self.device)
        return extract_features(self.model, tensor)[0]

    # --- prediction ---

    def predict(self, image: Image.Image, with_gradcam: bool = True) -> InferenceResult:
        if not self.is_loaded:
            if self.settings.allow_stub_model:
                return self._stub_predict(image)
            raise ModelUnavailableError(
                self.load_error or "no model is loaded"
            )

        started = time.perf_counter()
        tensor = to_tensor(image, self.image_size).to(self.device)

        if with_gradcam:
            result = self._predict_with_gradcam(image, tensor)
        else:
            with torch.no_grad():
                logits = self.model(tensor)
                probabilities = self._softmax(logits)
            result = self._build_result(probabilities)

        result.inference_ms = (time.perf_counter() - started) * 1000
        return result

    def _predict_with_gradcam(self, image: Image.Image, tensor: torch.Tensor) -> InferenceResult:
        assert self.model is not None and self.arch is not None
        target_layer = gradcam_target_layer(self.model, self.arch)

        with GradCAM(self.model, target_layer) as cam_engine:
            cam, class_index, raw_probabilities = cam_engine(tensor)

        probabilities = self._apply_temperature_to_probs(raw_probabilities)
        result = self._build_result(probabilities)

        # Grad-CAM explains the class the raw model chose. Temperature scaling cannot
        # change the argmax, so these always agree -- but assert rather than assume.
        if class_index != result.predicted_index:
            logger.warning(
                "Grad-CAM class %s differs from reported class %s", class_index, result.predicted_index
            )

        stats = cam_statistics(cam)
        result.gradcam = cam
        result.gradcam_stats = stats
        result.gradcam_focus = describe_focus(stats)
        result.overlay = overlay_heatmap(image, cam)
        return result

    def _softmax(self, logits: torch.Tensor) -> np.ndarray:
        scaled = logits / self.settings.calibration_temperature
        return torch.softmax(scaled, dim=1)[0].detach().cpu().numpy()

    def _apply_temperature_to_probs(self, probabilities: np.ndarray) -> np.ndarray:
        """Re-apply temperature to probabilities produced without it.

        Grad-CAM returns softmax(logits); recovering logits by log() and rescaling is exact
        up to an additive constant, which softmax is invariant to.
        """
        temperature = self.settings.calibration_temperature
        if temperature == 1.0:
            return probabilities
        logits = np.log(np.clip(probabilities, 1e-12, None)) / temperature
        exponentiated = np.exp(logits - logits.max())
        return exponentiated / exponentiated.sum()

    def _build_result(self, probabilities: np.ndarray) -> InferenceResult:
        index = int(np.argmax(probabilities))
        skin_class = self.mapping.by_index(index)
        return InferenceResult(
            predicted_code=skin_class.code,
            predicted_index=index,
            confidence=float(probabilities[index]),
            probabilities={
                self.mapping.by_index(i).code: float(p) for i, p in enumerate(probabilities)
            },
        )

    # --- stub ---

    def _stub_predict(self, image: Image.Image) -> InferenceResult:
        """Deterministic fake prediction, derived from the image bytes so the same image
        always yields the same answer (which makes UI development sane)."""
        logger.warning("STUB MODE: returning a synthetic prediction, not a real one.")

        digest = hashlib.blake2b(image.tobytes()[:4096], digest_size=8).digest()
        rng = np.random.default_rng(int.from_bytes(digest, "big"))

        weights = rng.random(self.mapping.num_classes) + 0.1
        probabilities = weights / weights.sum()

        result = self._build_result(probabilities)
        result.stub = True
        result.gradcam_focus = "stub mode — no heatmap was computed"
        return result

    # --- introspection ---

    def health(self) -> dict[str, Any]:
        return {
            "model_loaded": self.is_loaded,
            "model_arch": self.arch,
            "class_mapping_version": self.mapping.version,
            "num_classes": self.mapping.num_classes,
            "device": str(self.device),
            "stub_mode": self.stub_mode,
            "load_error": self.load_error,
        }
