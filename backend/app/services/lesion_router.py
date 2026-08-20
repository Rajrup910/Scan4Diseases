"""Front-stage router: what IS this photo, before the disease model runs.

Loads the multi-class softmax head fitted by `ml/ood/fit_lesion_router.py` and decides
which of a small set of categories a photo belongs to:

    lesion        -> hand the image to the 7-class disease model (unchanged path)
    healthy        -> "no concerning lesion detected" (NOT a medical clearance)
    other_damage   -> "some other kind of skin damage (e.g. a wound)"   [if trained]
    not_skin       -> "please photograph a skin area"

This replaces the binary `LesionGate`'s yes/no with an informative category, so healthy
skin and a wound stop collapsing to the same "no lesion detected".

SAFETY -- routing is not a plain argmax. A lesion misrouted to "healthy" is a missed
cancer, so the lesion route is kept high-recall: if P(lesion) >= `lesion_threshold`
(calibrated at fit time so ~98% of real lesions still pass) the photo goes to the disease
model regardless of the other probabilities. A non-lesion category can only win when the
lesion probability is already below that threshold. The class list is read from the
artifact, so adding a class (e.g. other_damage) needs no code change here.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import numpy as np

logger = logging.getLogger(__name__)

LESION_ROUTE = "lesion"


class LesionRouter:
    def __init__(
        self,
        w: np.ndarray,
        b: np.ndarray,
        mean: np.ndarray,
        std: np.ndarray,
        class_names: list[str],
        lesion_threshold: float,
        meta: dict[str, Any] | None = None,
    ) -> None:
        self.w = np.asarray(w, dtype=np.float64)            # (K, D)
        self.b = np.asarray(b, dtype=np.float64).reshape(-1)  # (K,)
        self.mean = np.asarray(mean, dtype=np.float64).reshape(-1)
        self.std = np.asarray(std, dtype=np.float64).reshape(-1)
        self.class_names = [str(c) for c in class_names]
        self.lesion_threshold = float(lesion_threshold)
        self.meta = meta or {}
        self.feature_dim = int(self.w.shape[1])
        if LESION_ROUTE not in self.class_names:
            raise ValueError(f"router has no '{LESION_ROUTE}' class: {self.class_names}")
        self.lesion_index = self.class_names.index(LESION_ROUTE)

    @classmethod
    def load(cls, path: str | Path) -> LesionRouter | None:
        p = Path(path)
        if not p.is_file():
            logger.warning("Lesion router not found at %s - router disabled", p)
            return None
        try:
            data = np.load(p, allow_pickle=True)
            meta = {}
            if "meta" in data:
                raw = data["meta"]
                meta = raw.item() if raw.dtype == object else dict(raw)
            class_names = [str(c) for c in data["class_names"]]
            router = cls(
                w=data["w"],
                b=data["b"],
                mean=data["mean"],
                std=data["std"],
                class_names=class_names,
                lesion_threshold=float(data["lesion_threshold"]),
                meta=meta,
            )
        except Exception as exc:  # noqa: BLE001 - a bad artifact must not crash startup
            logger.error("Failed to load lesion router from %s: %s", p, exc)
            return None
        logger.info(
            "Loaded lesion router from %s (dim=%d, classes=%s, lesion_threshold=%.3f)",
            p.name, router.feature_dim, router.class_names, router.lesion_threshold,
        )
        return router

    def probabilities(self, features: np.ndarray) -> dict[str, float]:
        """Softmax probability for each category."""
        feat = np.asarray(features, dtype=np.float64).reshape(-1)
        normed = (feat - self.mean) / self.std
        logits = self.w @ normed + self.b
        logits -= logits.max()
        exp = np.exp(logits)
        probs = exp / exp.sum()
        return {name: float(probs[i]) for i, name in enumerate(self.class_names)}

    def route(self, features: np.ndarray) -> tuple[str, dict[str, float]]:
        """Return (route, probabilities).

        High-recall lesion rule: if P(lesion) >= threshold, route to the disease model.
        Otherwise pick the most likely NON-lesion category. `route` is always one of
        `class_names`.
        """
        probs = self.probabilities(features)
        if probs[LESION_ROUTE] >= self.lesion_threshold:
            return LESION_ROUTE, probs
        non_lesion = {k: v for k, v in probs.items() if k != LESION_ROUTE}
        winner = max(non_lesion, key=non_lesion.get)
        return winner, probs
