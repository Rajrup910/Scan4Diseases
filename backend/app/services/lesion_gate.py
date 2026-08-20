"""Binary lesion-presence gate.

Loads the logistic head fitted by `ml/ood/fit_lesion_gate.py` and scores whether an
image's penultimate features look like a close-up skin lesion. Unlike the Mahalanobis
distance, this is a *discriminative* boundary trained on real non-lesion photos, so it can
reject skin-that-isn't-a-lesion (a forearm, a hand) that the distance metric cannot.

Reject when P(lesion) < threshold, where the threshold was chosen at fit time to keep a
high fraction (default 98%) of genuine lesions passing.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)


class LesionGate:
    def __init__(
        self,
        w: np.ndarray,
        b: float,
        mean: np.ndarray,
        std: np.ndarray,
        threshold: float,
        meta: dict[str, Any] | None = None,
    ) -> None:
        self.w = w.astype(np.float64).reshape(-1)
        self.b = float(b)
        self.mean = mean.astype(np.float64).reshape(-1)
        self.std = std.astype(np.float64).reshape(-1)
        self.threshold = float(threshold)
        self.meta = meta or {}
        self.feature_dim = int(self.w.shape[0])

    @classmethod
    def load(cls, path: str | Path) -> "LesionGate | None":
        p = Path(path)
        if not p.is_file():
            logger.warning("Lesion gate not found at %s - lesion gate disabled", p)
            return None
        try:
            data = np.load(p, allow_pickle=True)
            meta = {}
            if "meta" in data:
                raw = data["meta"]
                meta = raw.item() if raw.dtype == object else dict(raw)
            gate = cls(
                w=data["w"],
                b=float(data["b"]),
                mean=data["mean"],
                std=data["std"],
                threshold=float(data["threshold"]),
                meta=meta,
            )
        except Exception as exc:  # noqa: BLE001 - a bad artifact must not crash startup
            logger.error("Failed to load lesion gate from %s: %s", p, exc)
            return None
        logger.info(
            "Loaded lesion gate from %s (dim=%d, threshold=%.3f, keeps %.0f%% lesions)",
            p.name, gate.feature_dim, gate.threshold,
            float(gate.meta.get("val_lesion_pass", 0.0)) * 100,
        )
        return gate

    def probability(self, features: np.ndarray) -> float:
        """P(image is a close-up lesion)."""
        feat = np.asarray(features, dtype=np.float64).reshape(-1)
        normed = (feat - self.mean) / self.std
        logit = float(normed @ self.w + self.b)
        return 1.0 / (1.0 + np.exp(-logit))

    def is_not_lesion(self, features: np.ndarray) -> bool:
        return self.probability(features) < self.threshold
