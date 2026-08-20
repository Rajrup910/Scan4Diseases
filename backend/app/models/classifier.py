"""Build and load the classifier at runtime.

Mirrors `ml/training/common.py`'s model factory, minus everything training-specific.
Weights always come from a checkpoint, so `pretrained=False` is correct here -- there is
no reason for the API server to reach out and download ImageNet weights on boot.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import torch
import torch.nn as nn
from torchvision import models

SUPPORTED_ARCHS = ("resnet50", "efficientnet_b0")


def build_model(arch: str, num_classes: int, dropout: float = 0.3) -> nn.Module:
    if arch not in SUPPORTED_ARCHS:
        raise ValueError(f"arch must be one of {SUPPORTED_ARCHS}, got {arch!r}")

    if arch == "resnet50":
        model = models.resnet50(weights=None)
        in_features = model.fc.in_features
        model.fc = nn.Sequential(nn.Dropout(p=dropout), nn.Linear(in_features, num_classes))
    else:
        model = models.efficientnet_b0(weights=None)
        in_features = model.classifier[1].in_features
        model.classifier = nn.Sequential(nn.Dropout(p=dropout), nn.Linear(in_features, num_classes))

    return model


def gradcam_target_layer(model: nn.Module, arch: str) -> nn.Module:
    """Last convolutional block — where Grad-CAM hooks."""
    if arch == "resnet50":
        return model.layer4[-1]
    return model.features[-1]


def resolve_device(preference: str = "auto") -> torch.device:
    if preference != "auto":
        return torch.device(preference)
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def load_classifier(
    checkpoint_path: str | Path,
    expected_codes: tuple[str, ...],
    device: torch.device | str = "cpu",
) -> tuple[nn.Module, dict[str, Any]]:
    """Load a checkpoint, verifying it matches the class mapping the server is running.

    A mismatch here would mean serving predictions whose labels are quietly wrong -- index
    4 meaning `mel` to the model and something else to the API. Refusing to start is far
    better than being subtly incorrect in a medical context.
    """
    path = Path(checkpoint_path)
    if not path.is_file():
        raise FileNotFoundError(f"no checkpoint at {path}")

    payload = torch.load(path, map_location=device, weights_only=False)

    missing = {"arch", "num_classes", "class_codes", "state_dict"} - set(payload)
    if missing:
        raise ValueError(f"checkpoint is missing key(s): {sorted(missing)}")

    if tuple(payload["class_codes"]) != tuple(expected_codes):
        raise ValueError(
            f"checkpoint was trained on classes {tuple(payload['class_codes'])} but the server's "
            f"class mapping declares {tuple(expected_codes)}. Refusing to load."
        )

    dropout = payload.get("config", {}).get("model", {}).get("dropout", 0.3)
    model = build_model(payload["arch"], payload["num_classes"], dropout=dropout)
    model.load_state_dict(payload["state_dict"])
    model.to(device).eval()

    return model, payload
