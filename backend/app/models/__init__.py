"""Runtime model loading.

This package deliberately duplicates a small amount of `ml/` code (the model factory and
the class-mapping loader) rather than importing it. Two reasons:

  * The API server must be deployable without the training package, its notebooks, or
    scikit-learn/matplotlib/pandas. On a free CPU tier that is a meaningful saving.
  * Section 21 of the master specification: training code does not belong in the API server.

The duplication is kept honest by `tests/test_model_parity.py`, which asserts that both
builders produce identical architectures and that both class-mapping loaders agree.
"""

from backend.app.models.classes import ClassMapping, SkinClass, load_class_mapping
from backend.app.models.classifier import build_model, gradcam_target_layer, load_classifier

__all__ = [
    "ClassMapping",
    "SkinClass",
    "build_model",
    "gradcam_target_layer",
    "load_class_mapping",
    "load_classifier",
]
