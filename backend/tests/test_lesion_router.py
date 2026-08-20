"""Routing logic of the front-stage LesionRouter.

The safety-critical property is the high-recall lesion override: a photo whose lesion
probability clears the threshold must route to the disease model even if another class is
numerically close, so a lesion is never silently called 'healthy'.
"""

from __future__ import annotations

import numpy as np
import pytest

from backend.app.services.lesion_router import LesionRouter


def _router(lesion_threshold: float = 0.5) -> LesionRouter:
    # 3 features, 3 classes; identity-ish weights so each feature votes for one class.
    # class 0 = lesion, 1 = healthy, 2 = not_skin
    w = np.array([[6.0, 0.0, 0.0],
                  [0.0, 6.0, 0.0],
                  [0.0, 0.0, 6.0]], dtype=np.float64)
    b = np.zeros(3)
    mean = np.zeros(3)
    std = np.ones(3)
    return LesionRouter(
        w=w, b=b, mean=mean, std=std,
        class_names=["lesion", "healthy", "not_skin"],
        lesion_threshold=lesion_threshold,
    )


def test_clear_lesion_routes_to_disease_model():
    r = _router()
    route, probs = r.route(np.array([1.0, 0.0, 0.0]))
    assert route == "lesion"
    assert probs["lesion"] == pytest.approx(max(probs.values()))


def test_clear_healthy_routes_to_healthy():
    r = _router()
    route, _ = r.route(np.array([0.0, 1.0, 0.0]))
    assert route == "healthy"


def test_clear_not_skin_routes_to_not_skin():
    r = _router()
    route, _ = r.route(np.array([0.0, 0.0, 1.0]))
    assert route == "not_skin"


def test_high_recall_override_keeps_borderline_lesion_out_of_healthy():
    # A low threshold means even a modest lesion probability must still route to lesion,
    # never to healthy -- the missed-cancer guard.
    r = _router(lesion_threshold=0.2)
    # Features that make lesion the plurality but not dominant.
    route, probs = r.route(np.array([0.5, 0.45, 0.0]))
    assert probs["lesion"] >= 0.2
    assert route == "lesion"


def test_below_threshold_never_returns_lesion():
    # With a high threshold, a weak lesion signal must fall through to a non-lesion class,
    # not be forced to 'lesion'.
    r = _router(lesion_threshold=0.99)
    route, probs = r.route(np.array([0.2, 0.9, 0.0]))
    assert probs["lesion"] < 0.99
    assert route != "lesion"
    assert route == "healthy"


def test_route_is_always_a_known_class():
    r = _router()
    for _ in range(20):
        route, _ = r.route(np.random.randn(3))
        assert route in {"lesion", "healthy", "not_skin"}


def test_missing_lesion_class_is_rejected():
    with pytest.raises(ValueError, match="no 'lesion' class"):
        LesionRouter(
            w=np.eye(2), b=np.zeros(2), mean=np.zeros(2), std=np.ones(2),
            class_names=["healthy", "not_skin"], lesion_threshold=0.5,
        )
