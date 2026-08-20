"""Out-of-distribution (OOD) detection via Mahalanobis distance on penultimate features.

The classifier is closed-set: seven skin-lesion classes and a softmax that must sum to
one across them. Given a photo of something that is not a lesion (a hand, a wall), it is
forced to pick a class and does so with misleadingly high softmax confidence -- almost
always `nv`, the 67% majority class. Softmax cannot flag this; the feature space can.

Method (Lee et al., 2018, "A Simple Unified Framework for Detecting OOD Samples"):

  * Offline, over the training set, take the model's penultimate features (the global
    pooled vector before the final linear layer) and fit one Gaussian per class: a class
    mean, and a single covariance shared across classes (tied covariance).
  * At inference, take the same features for the uploaded image and compute the squared
    Mahalanobis distance to the nearest class mean. A real lesion lands close to some
    class; an off-distribution image lands far from all of them.
  * A high distance (above a threshold chosen from the in-distribution score
    distribution) means "this does not look like anything the model was trained on".

The fit and the threshold live in a saved artifact produced by
`ml/ood/fit_mahalanobis.py`. This module only loads and scores.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np
import torch
import torch.nn as nn

logger = logging.getLogger(__name__)


def pooling_layer(model: nn.Module) -> nn.Module:
    """The global-average-pooling layer whose output is the penultimate feature vector.

    torchvision's ResNet and EfficientNet both expose it as `.avgpool`; its output is
    (B, C, 1, 1), flattened to (B, C) -- 2048 for resnet50, 1280 for efficientnet_b0.
    """
    if not hasattr(model, "avgpool"):
        raise AttributeError("model has no `avgpool` layer to hook penultimate features")
    return model.avgpool


class _CaptureFeatures:
    """Context manager that records the flattened output of the pooling layer."""

    def __init__(self, model: nn.Module) -> None:
        self._layer = pooling_layer(model)
        self._handle = None
        self.value: torch.Tensor | None = None

    def __enter__(self) -> "_CaptureFeatures":
        self._handle = self._layer.register_forward_hook(self._hook)
        return self

    def _hook(self, _module: nn.Module, _inputs: Any, output: torch.Tensor) -> None:
        self.value = torch.flatten(output, 1)

    def __exit__(self, *_exc: object) -> None:
        if self._handle is not None:
            self._handle.remove()
            self._handle = None


@torch.no_grad()
def extract_features(model: nn.Module, batch: torch.Tensor) -> np.ndarray:
    """Run a forward pass and return penultimate features as a (B, D) numpy array.

    Used by both the offline fit script and the live inference service, so the training
    statistics and the serving features are guaranteed to come from the same layer.
    """
    with _CaptureFeatures(model) as capture:
        model(batch)
    if capture.value is None:  # pragma: no cover - defensive
        raise RuntimeError("penultimate features were not captured during the forward pass")
    return capture.value.detach().cpu().numpy()


class MahalanobisOOD:
    """Scores features against fitted per-class Gaussians with a shared covariance."""

    def __init__(
        self,
        means: np.ndarray,
        precision: np.ndarray,
        threshold: float,
        meta: dict[str, Any] | None = None,
    ) -> None:
        # means: (C, D) class centroids; precision: (D, D) inverse tied covariance.
        self.means = means.astype(np.float64)
        self.precision = precision.astype(np.float64)
        self.threshold = float(threshold)
        self.meta = meta or {}
        self.feature_dim = int(means.shape[1])

    @classmethod
    def load(cls, path: str | Path) -> "MahalanobisOOD | None":
        """Load a fitted artifact, or return None if it is missing/unreadable."""
        p = Path(path)
        if not p.is_file():
            logger.warning("OOD stats not found at %s - OOD detection disabled", p)
            return None
        try:
            data = np.load(p, allow_pickle=True)
            meta = {}
            if "meta" in data:
                raw = data["meta"]
                meta = raw.item() if raw.dtype == object else dict(raw)
            instance = cls(
                means=data["means"],
                precision=data["precision"],
                threshold=float(data["threshold"]),
                meta=meta,
            )
        except Exception as exc:  # noqa: BLE001 - a bad artifact must not crash startup
            logger.error("Failed to load OOD stats from %s: %s", p, exc)
            return None
        logger.info(
            "Loaded OOD stats from %s (dim=%d, threshold=%.1f, arch=%s)",
            p.name,
            instance.feature_dim,
            instance.threshold,
            instance.meta.get("arch"),
        )
        return instance

    def score(self, features: np.ndarray) -> float:
        """Squared Mahalanobis distance to the nearest class mean. Higher = more OOD."""
        feat = np.asarray(features, dtype=np.float64).reshape(-1)
        diffs = self.means - feat[None, :]  # (C, D)
        # (diff @ precision) . diff, per class, without forming a (C, D, D) tensor.
        left = diffs @ self.precision  # (C, D)
        distances = np.einsum("cd,cd->c", left, diffs)  # (C,)
        return float(distances.min())

    def is_ood(self, features: np.ndarray) -> bool:
        return self.score(features) > self.threshold
