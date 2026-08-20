"""Tests for the ML pipeline that do not need the dataset on disk.

The leakage test is the important one here. It builds a synthetic manifest with the same
structure as HAM10000 -- several images per lesion -- and asserts that the split never puts
one lesion on both sides of the train/test boundary. That property is the basis of every
number the final report will quote, so it is worth pinning down with a test rather than
trusting the implementation to stay correct.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest
import torch

from ml.evaluation.metrics import (
    compute_metrics,
    expected_calibration_error,
    format_report,
)
from ml.paths import load_class_mapping, load_training_config
from ml.preprocessing.split_dataset import (
    assert_no_leakage,
    check_stratification_feasible,
    lesion_table,
    split_lesions,
)
from ml.preprocessing.transforms import build_transforms
from ml.training.common import (
    build_model,
    compute_class_weights,
    count_parameters,
    set_backbone_frozen,
    set_seed,
)

CODES = ("akiec", "bcc", "bkl", "df", "mel", "nv", "vasc")


def synthetic_manifest(
    lesions_per_class: int = 30, seed: int = 0
) -> pd.DataFrame:
    """A manifest shaped like HAM10000: multiple images share a lesion_id."""
    rng = np.random.default_rng(seed)
    rows = []
    for class_index, code in enumerate(CODES):
        for lesion in range(lesions_per_class):
            lesion_id = f"HAM_{code}_{lesion:04d}"
            for image in range(int(rng.integers(1, 5))):
                rows.append(
                    {
                        "image_id": f"ISIC_{code}_{lesion:04d}_{image}",
                        "lesion_id": lesion_id,
                        "dx": code,
                        "class_code": code,
                        "class_index": class_index,
                        "path": f"data/{code}/{lesion}_{image}.jpg",
                    }
                )
    return pd.DataFrame(rows)


# --- split integrity ---------------------------------------------------------------


def test_no_lesion_crosses_a_split_boundary():
    manifest = synthetic_manifest()
    lesions = lesion_table(manifest, "lesion_id", "dx")
    assigned = split_lesions(lesions, "dx", {"train": 0.7, "val": 0.15, "test": 0.15}, seed=42)

    images = manifest.merge(assigned[["lesion_id", "split"]], on="lesion_id", validate="many_to_one")
    assert_no_leakage(images, "lesion_id")  # raises if any lesion is shared

    train = set(images.loc[images["split"] == "train", "lesion_id"])
    test = set(images.loc[images["split"] == "test", "lesion_id"])
    val = set(images.loc[images["split"] == "val", "lesion_id"])
    assert not (train & test) and not (train & val) and not (val & test)


def test_leakage_check_actually_catches_leakage():
    """A test that only ever passes proves nothing. Verify it fails when it should."""
    images = pd.DataFrame(
        {
            "image_id": ["a", "b", "c"],
            "lesion_id": ["L1", "L1", "L2"],
            "split": ["train", "test", "train"],  # L1 spans train and test
        }
    )
    with pytest.raises(AssertionError, match="LEAKAGE"):
        assert_no_leakage(images, "lesion_id")


def test_every_image_is_assigned_exactly_once():
    manifest = synthetic_manifest()
    lesions = lesion_table(manifest, "lesion_id", "dx")
    assigned = split_lesions(lesions, "dx", {"train": 0.7, "val": 0.15, "test": 0.15}, seed=42)
    images = manifest.merge(assigned[["lesion_id", "split"]], on="lesion_id", validate="many_to_one")

    assert len(images) == len(manifest)
    assert images["split"].notna().all()
    assert set(images["split"]) == {"train", "val", "test"}


def test_all_classes_appear_in_every_split():
    """Stratification must not leave a rare class absent from the test set."""
    manifest = synthetic_manifest()
    lesions = lesion_table(manifest, "lesion_id", "dx")
    assigned = split_lesions(lesions, "dx", {"train": 0.7, "val": 0.15, "test": 0.15}, seed=42)
    images = manifest.merge(assigned[["lesion_id", "split"]], on="lesion_id", validate="many_to_one")

    for split in ("train", "val", "test"):
        present = set(images.loc[images["split"] == split, "class_code"])
        assert present == set(CODES), f"{split} is missing {set(CODES) - present}"


def test_split_is_reproducible():
    manifest = synthetic_manifest()
    lesions = lesion_table(manifest, "lesion_id", "dx")
    fractions = {"train": 0.7, "val": 0.15, "test": 0.15}

    first = split_lesions(lesions, "dx", fractions, seed=42).sort_values("lesion_id")
    second = split_lesions(lesions, "dx", fractions, seed=42).sort_values("lesion_id")
    assert list(first["split"]) == list(second["split"])

    different = split_lesions(lesions, "dx", fractions, seed=7).sort_values("lesion_id")
    assert list(first["split"]) != list(different["split"])


def test_split_proportions_are_approximately_respected():
    manifest = synthetic_manifest(lesions_per_class=60)
    lesions = lesion_table(manifest, "lesion_id", "dx")
    assigned = split_lesions(lesions, "dx", {"train": 0.7, "val": 0.15, "test": 0.15}, seed=42)

    shares = assigned["split"].value_counts(normalize=True)
    assert shares["train"] == pytest.approx(0.70, abs=0.03)
    assert shares["val"] == pytest.approx(0.15, abs=0.03)
    assert shares["test"] == pytest.approx(0.15, abs=0.03)


def test_fractions_must_sum_to_one():
    lesions = lesion_table(synthetic_manifest(), "lesion_id", "dx")
    with pytest.raises(ValueError, match="sum to 1.0"):
        split_lesions(lesions, "dx", {"train": 0.8, "val": 0.15, "test": 0.15}, seed=42)


def test_lesion_with_conflicting_labels_is_rejected():
    """One lesion cannot have two diagnoses -- grouped splitting would be undefined."""
    manifest = synthetic_manifest(lesions_per_class=5)
    manifest.loc[0, "dx"] = "mel"
    manifest.loc[1, "dx"] = "nv"
    manifest.loc[0, "lesion_id"] = "SHARED"
    manifest.loc[1, "lesion_id"] = "SHARED"

    with pytest.raises(ValueError, match="more than one value"):
        lesion_table(manifest, "lesion_id", "dx")


def test_too_rare_class_is_refused_not_silently_dropped():
    manifest = synthetic_manifest(lesions_per_class=10)
    manifest = manifest[~((manifest["dx"] == "df") & (manifest["lesion_id"] != "HAM_df_0000"))]
    lesions = lesion_table(manifest, "lesion_id", "dx")

    with pytest.raises(ValueError, match="fewer than 3 lesions"):
        check_stratification_feasible(lesions, "dx")


# --- class weighting ---------------------------------------------------------------


def test_class_weights_are_inverse_to_frequency():
    counts = [327, 514, 1099, 115, 1113, 6705, 142]  # HAM10000-like
    weights = compute_class_weights(counts, "effective_number", 0.999)

    assert weights is not None
    # The rarest class (df, index 3) must outweigh the most common (nv, index 5).
    assert weights[3] > weights[5]
    assert weights.mean() == pytest.approx(1.0, abs=1e-5)


def test_effective_number_is_gentler_than_inverse_frequency():
    """The reason effective-number is the default: inverse frequency is too extreme."""
    counts = [327, 514, 1099, 115, 1113, 6705, 142]
    inverse = compute_class_weights(counts, "inverse")
    effective = compute_class_weights(counts, "effective_number", 0.999)

    inverse_spread = float(inverse.max() / inverse.min())
    effective_spread = float(effective.max() / effective.min())
    assert effective_spread < inverse_spread


def test_no_weighting_returns_none():
    assert compute_class_weights([10, 20], "none") is None


def test_absent_class_gets_zero_weight_not_an_error():
    """A dataset covering only a subset of the fixed class space (e.g. PAD-UFES has no
    df/vasc) must still train. The absent class -- which never appears as a target -- gets
    weight 0, and normalisation is over the present classes so the loss scale is unchanged."""
    weights = compute_class_weights([10, 0, 5], "effective_number")
    assert weights is not None
    assert float(weights[1]) == 0.0
    present = weights[[0, 2]]
    assert float(present.mean()) == pytest.approx(1.0, abs=1e-5)


def test_all_zero_counts_is_an_error():
    with pytest.raises(ValueError, match="no class has any training samples"):
        compute_class_weights([0, 0, 0], "effective_number")


def test_unknown_scheme_is_rejected():
    with pytest.raises(ValueError, match="unknown class_weighting"):
        compute_class_weights([10, 20], "magic")


# --- model construction ------------------------------------------------------------


@pytest.mark.parametrize("arch", ["resnet50", "efficientnet_b0"])
def test_model_outputs_match_the_class_count(arch: str):
    mapping = load_class_mapping()
    model = build_model(arch, mapping.num_classes, pretrained=False).eval()

    with torch.no_grad():
        logits = model(torch.randn(2, 3, 224, 224))

    assert logits.shape == (2, mapping.num_classes)
    probabilities = torch.softmax(logits, dim=1)
    assert torch.allclose(probabilities.sum(dim=1), torch.ones(2), atol=1e-5)


@pytest.mark.parametrize("arch", ["resnet50", "efficientnet_b0"])
def test_freezing_leaves_only_the_head_trainable(arch: str):
    model = build_model(arch, 7, pretrained=False)
    total = count_parameters(model)["total"]

    set_backbone_frozen(model, arch, frozen=True)
    frozen_trainable = count_parameters(model)["trainable"]
    assert 0 < frozen_trainable < total * 0.01  # head only

    set_backbone_frozen(model, arch, frozen=False)
    assert count_parameters(model)["trainable"] == total


def test_efficientnet_is_much_smaller_than_resnet():
    """The premise of the whole model-comparison experiment."""
    resnet = count_parameters(build_model("resnet50", 7, pretrained=False))["total"]
    efficientnet = count_parameters(build_model("efficientnet_b0", 7, pretrained=False))["total"]
    assert efficientnet < resnet / 4


def test_unknown_arch_is_rejected():
    with pytest.raises(ValueError, match="arch must be one of"):
        build_model("vgg16", 7)


def test_seeding_makes_initialisation_reproducible():
    set_seed(123)
    first = build_model("efficientnet_b0", 7, pretrained=False).state_dict()
    set_seed(123)
    second = build_model("efficientnet_b0", 7, pretrained=False).state_dict()

    for key, tensor in first.items():
        assert torch.equal(tensor, second[key]), key


# --- transforms --------------------------------------------------------------------


def test_train_transform_is_random_and_eval_transform_is_not():
    from PIL import Image

    config = load_training_config()
    pipelines = build_transforms(224, config["augmentation"])
    image = Image.fromarray(
        np.random.default_rng(3).integers(0, 255, (400, 400, 3), dtype=np.uint8)
    )

    assert not torch.equal(pipelines["train"](image), pipelines["train"](image))
    assert torch.equal(pipelines["test"](image), pipelines["test"](image))
    assert torch.equal(pipelines["val"](image), pipelines["test"](image))


# --- metrics -----------------------------------------------------------------------


def test_metrics_expose_the_majority_class_trap():
    """A model that always predicts `nv` should look good on accuracy and bad on macro F1."""
    mapping = load_class_mapping()
    nv = mapping.index_of("nv")

    y_true = np.array([nv] * 670 + [mapping.index_of("mel")] * 330)
    y_pred = np.full_like(y_true, nv)

    metrics = compute_metrics(y_true, y_pred)

    assert metrics["accuracy"] == pytest.approx(0.67, abs=0.01)
    assert metrics["macro_f1"] < 0.20
    assert metrics["balanced_accuracy"] == pytest.approx(0.5, abs=0.01)
    assert metrics["per_class"]["mel"]["recall"] == 0.0
    assert metrics["clinical"]["binary_sensitivity"] == 0.0
    assert metrics["clinical"]["missed_serious_cases"] == 330


def test_perfect_predictions_score_one():
    y_true = np.array([0, 1, 2, 3, 4, 5, 6] * 4)
    metrics = compute_metrics(y_true, y_true.copy())

    assert metrics["accuracy"] == 1.0
    assert metrics["macro_f1"] == 1.0
    assert metrics["balanced_accuracy"] == 1.0
    assert metrics["clinical"]["missed_serious_cases"] == 0


def test_confusion_matrix_shape_and_totals():
    rng = np.random.default_rng(5)
    y_true = rng.integers(0, 7, 200)
    y_pred = rng.integers(0, 7, 200)

    matrix = np.array(compute_metrics(y_true, y_pred)["confusion_matrix"])
    assert matrix.shape == (7, 7)
    assert matrix.sum() == 200


def test_calibration_error_bounds():
    correct = np.ones(100)
    perfect = np.ones(100)  # always 100% confident, always right
    assert expected_calibration_error(perfect, correct) == pytest.approx(0.0, abs=1e-6)

    overconfident = np.ones(100)
    wrong = np.zeros(100)  # always 100% confident, always wrong
    assert expected_calibration_error(overconfident, wrong) == pytest.approx(1.0, abs=1e-6)


def test_classification_report_uses_class_codes():
    y_true = np.array([0, 1, 2, 3, 4, 5, 6])
    report = format_report(y_true, y_true.copy())
    for code in CODES:
        assert code in report
