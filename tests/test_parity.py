"""Parity tests between the `ml` and `backend` packages.

The backend deliberately reimplements three small things rather than importing them from
`ml`, so that the API server can be deployed without the training stack:

    model factory        ml/training/common.py     <-> backend/app/models/classifier.py
    eval preprocessing   ml/preprocessing/...      <-> backend/app/services/preprocessing.py
    Grad-CAM             ml/explainability/...     <-> backend/app/services/gradcam.py

Duplication is only acceptable if it cannot drift. These tests are what stop it drifting.
A preprocessing mismatch in particular is the nastiest bug in this whole project: nothing
errors, the model just quietly gets worse in production than it was in evaluation.
"""

from __future__ import annotations

import numpy as np
import pytest
import torch
from PIL import Image

from backend.app.models import classifier as backend_models
from backend.app.models.classes import load_class_mapping as backend_mapping
from backend.app.services import gradcam as backend_gradcam
from backend.app.services import preprocessing as backend_pre
from ml.explainability import gradcam as ml_gradcam
from ml.paths import CLASS_MAPPING_PATH
from ml.paths import load_class_mapping as ml_mapping
from ml.preprocessing import transforms as ml_transforms
from ml.training import common as ml_common

ARCHS = ("resnet50", "efficientnet_b0")


@pytest.fixture(scope="module")
def sample_image() -> Image.Image:
    rng = np.random.default_rng(7)
    return Image.fromarray(rng.integers(60, 200, size=(480, 640, 3), dtype=np.uint8))


# --- class mapping -----------------------------------------------------------------


def test_class_mappings_agree():
    ml_map = ml_mapping()
    api_map = backend_mapping(CLASS_MAPPING_PATH)

    assert ml_map.version == api_map.version
    assert ml_map.codes == api_map.codes
    assert ml_map.num_classes == api_map.num_classes

    for skin_class in ml_map.classes:
        api_class = api_map.by_code(skin_class.code)
        assert api_class.index == skin_class.index
        assert api_class.malignancy == skin_class.malignancy


def test_mapping_declares_every_translation():
    """A missing Hindi string would silently fall back to English at runtime."""
    api_map = backend_mapping(CLASS_MAPPING_PATH)
    for skin_class in api_map.classes:
        for field in (skin_class.names, skin_class.short_names, skin_class.plain_language):
            assert field.get("en", "").strip(), skin_class.code
            assert field.get("hi", "").strip(), skin_class.code
            assert field["en"] != field["hi"], f"{skin_class.code} translation is untranslated"


def test_malignancy_tiers_are_valid():
    api_map = backend_mapping(CLASS_MAPPING_PATH)
    valid = {"malignant", "premalignant", "benign"}
    for skin_class in api_map.classes:
        assert skin_class.malignancy in valid
    # Sanity: the classes everyone knows are cancerous must be tagged as such.
    assert api_map.by_code("mel").malignancy == "malignant"
    assert api_map.by_code("bcc").malignancy == "malignant"
    assert api_map.by_code("nv").malignancy == "benign"


# --- preprocessing -----------------------------------------------------------------


@pytest.mark.parametrize("image_size", [224, 256])
def test_eval_preprocessing_is_identical(sample_image: Image.Image, image_size: int):
    """The tensor fed to the model at serving time must equal the one used in evaluation."""
    ml_tensor = ml_transforms.build_eval_transform(image_size)(sample_image)
    api_tensor = backend_pre.build_eval_transform(image_size)(sample_image)

    assert ml_tensor.shape == api_tensor.shape
    assert torch.equal(ml_tensor, api_tensor)


def test_normalisation_constants_match():
    assert ml_transforms.IMAGENET_MEAN == backend_pre.IMAGENET_MEAN
    assert ml_transforms.IMAGENET_STD == backend_pre.IMAGENET_STD
    assert ml_transforms.RESIZE_RATIO == backend_pre.RESIZE_RATIO


def test_to_tensor_produces_a_batch(sample_image: Image.Image):
    tensor = backend_pre.to_tensor(sample_image, 224)
    assert tensor.shape == (1, 3, 224, 224)


# --- model factory -----------------------------------------------------------------


@pytest.mark.parametrize("arch", ARCHS)
def test_model_architectures_match(arch: str):
    ml_model = ml_common.build_model(arch, num_classes=7, pretrained=False)
    api_model = backend_models.build_model(arch, num_classes=7)

    assert list(ml_model.state_dict().keys()) == list(api_model.state_dict().keys())
    for key, tensor in ml_model.state_dict().items():
        assert tensor.shape == api_model.state_dict()[key].shape, key


@pytest.mark.parametrize("arch", ARCHS)
def test_backend_can_load_a_training_checkpoint(arch: str, tmp_path):
    """The real contract: a checkpoint written by training must load in the API server."""
    mapping = ml_mapping()
    model = ml_common.build_model(arch, mapping.num_classes, pretrained=False)

    path = tmp_path / f"{arch}.pt"
    ml_common.Checkpoint(
        arch=arch,
        num_classes=mapping.num_classes,
        class_codes=list(mapping.codes),
        class_mapping_version=mapping.version,
        image_size=224,
        state_dict=model.state_dict(),
        epoch=5,
        monitor_metric="macro_f1",
        monitor_value=0.72,
    ).save(path)

    loaded, payload = backend_models.load_classifier(path, mapping.codes, "cpu")
    assert payload["arch"] == arch
    assert payload["epoch"] == 5
    for key, tensor in model.state_dict().items():
        assert torch.equal(tensor, loaded.state_dict()[key]), key


def test_checkpoint_with_wrong_classes_is_rejected(tmp_path):
    """Loading a mismatched checkpoint would mean serving quietly mislabelled predictions."""
    mapping = ml_mapping()
    model = ml_common.build_model("resnet50", mapping.num_classes, pretrained=False)

    path = tmp_path / "wrong.pt"
    ml_common.Checkpoint(
        arch="resnet50",
        num_classes=mapping.num_classes,
        class_codes=["a", "b", "c", "d", "e", "f", "g"],
        class_mapping_version="0.0.1",
        image_size=224,
        state_dict=model.state_dict(),
        epoch=1,
        monitor_metric="macro_f1",
        monitor_value=0.5,
    ).save(path)

    with pytest.raises(ValueError, match="Refusing to load"):
        backend_models.load_classifier(path, mapping.codes, "cpu")


@pytest.mark.parametrize("arch", ARCHS)
def test_gradcam_target_layers_match(arch: str):
    ml_model = ml_common.build_model(arch, 7, pretrained=False)
    api_model = backend_models.build_model(arch, 7)

    ml_layer = ml_common.gradcam_target_layer(ml_model, arch)
    api_layer = backend_models.gradcam_target_layer(api_model, arch)
    assert type(ml_layer) is type(api_layer)


# --- Grad-CAM ----------------------------------------------------------------------


@pytest.mark.parametrize("arch", ARCHS)
def test_gradcam_implementations_agree(arch: str, sample_image: Image.Image):
    """Both implementations must produce the same map for the same weights and input."""
    torch.manual_seed(0)
    model = ml_common.build_model(arch, 7, pretrained=False).eval()
    for parameter in model.parameters():
        parameter.requires_grad_(False)  # as loaded for inference

    tensor = backend_pre.to_tensor(sample_image, 224)

    with ml_gradcam.GradCAM(model, ml_common.gradcam_target_layer(model, arch)) as engine:
        ml_cam, ml_index, ml_probs = engine(tensor)

    with backend_gradcam.GradCAM(model, backend_models.gradcam_target_layer(model, arch)) as engine:
        api_cam, api_index, api_probs = engine(tensor)

    assert ml_index == api_index
    np.testing.assert_allclose(ml_probs, api_probs, rtol=1e-5, atol=1e-6)
    np.testing.assert_allclose(ml_cam, api_cam, rtol=1e-5, atol=1e-6)


def test_gradcam_statistics_agree(sample_image: Image.Image):
    torch.manual_seed(1)
    model = ml_common.build_model("efficientnet_b0", 7, pretrained=False).eval()
    tensor = backend_pre.to_tensor(sample_image, 224)

    with ml_gradcam.GradCAM(model, ml_common.gradcam_target_layer(model, "efficientnet_b0")) as engine:
        cam, _, _ = engine(tensor)

    ml_stats = ml_gradcam.cam_statistics(cam)
    api_stats = backend_gradcam.cam_statistics(cam)

    for key in ("border_mass_fraction", "peak_offset_from_centre", "is_degenerate"):
        assert ml_stats[key] == pytest.approx(api_stats[key]), key
    assert ml_gradcam.describe_focus(ml_stats) == backend_gradcam.describe_focus(api_stats)


def test_gradcam_output_is_normalised(sample_image: Image.Image):
    torch.manual_seed(2)
    model = ml_common.build_model("resnet50", 7, pretrained=False).eval()
    tensor = backend_pre.to_tensor(sample_image, 224)

    with ml_gradcam.GradCAM(model, ml_common.gradcam_target_layer(model, "resnet50")) as engine:
        cam, _, probs = engine(tensor)

    assert cam.min() >= 0.0 and cam.max() <= 1.0
    assert probs.sum() == pytest.approx(1.0, abs=1e-5)


def test_gradcam_hooks_are_removed(sample_image: Image.Image):
    """A leaked forward hook on a long-lived server model is a slow memory leak."""
    model = ml_common.build_model("efficientnet_b0", 7, pretrained=False).eval()
    layer = ml_common.gradcam_target_layer(model, "efficientnet_b0")
    before = len(layer._forward_hooks)

    engine = ml_gradcam.GradCAM(model, layer)
    with engine:
        assert len(layer._forward_hooks) == before + 1
        engine(backend_pre.to_tensor(sample_image, 224))

    assert len(layer._forward_hooks) == before


def test_gradcam_requires_context_manager(sample_image: Image.Image):
    model = ml_common.build_model("efficientnet_b0", 7, pretrained=False).eval()
    engine = ml_gradcam.GradCAM(model, ml_common.gradcam_target_layer(model, "efficientnet_b0"))
    with pytest.raises(RuntimeError, match="hooks are not registered"):
        engine(backend_pre.to_tensor(sample_image, 224))


def test_overlay_preserves_original_resolution(sample_image: Image.Image):
    cam = np.random.default_rng(0).random((7, 7)).astype(np.float32)
    assert ml_gradcam.overlay_heatmap(sample_image, cam).size == sample_image.size
    assert backend_gradcam.overlay_heatmap(sample_image, cam).size == sample_image.size
