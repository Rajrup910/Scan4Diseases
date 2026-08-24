"""Grad-CAM for the API server.

Same algorithm as `ml/explainability/gradcam.py`, kept separate so the API server does not
depend on the training package or matplotlib -- colour mapping here uses OpenCV, which the
quality gate already requires. `tests/test_gradcam_parity.py` asserts that both
implementations produce numerically identical maps for the same model and input.

See the ml module's docstring for the derivation; the steps are:
feature maps -> gradients -> spatial-average weights -> weighted sum -> ReLU -> normalise.
"""

from __future__ import annotations

from types import TracebackType
from typing import Any

import cv2
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image


class GradCAM:
    """Grad-CAM over a single target layer with zero-overhead backprop."""

    def __init__(self, model: nn.Module, target_layer: nn.Module) -> None:
        self.model = model
        self.target_layer = target_layer
        self._activations: torch.Tensor | None = None
        self._handles: list[Any] = []

    def _save_activations(self, _module: nn.Module, _inputs: Any, output: torch.Tensor) -> None:
        output.requires_grad_(True)
        output.retain_grad()
        self._activations = output

    def __enter__(self) -> GradCAM:
        self._handles.append(self.target_layer.register_forward_hook(self._save_activations))
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        self.close()

    def close(self) -> None:
        for handle in self._handles:
            handle.remove()
        self._handles.clear()
        self._activations = None

    def __call__(
        self, input_tensor: torch.Tensor, class_index: int | None = None
    ) -> tuple[np.ndarray, int, np.ndarray]:
        if not self._handles:
            raise RuntimeError("GradCAM hooks are not registered; use it as a context manager")

        if input_tensor.dim() == 3:
            input_tensor = input_tensor.unsqueeze(0)

        self.model.eval()

        with torch.enable_grad():
            self.model.zero_grad(set_to_none=True)
            logits = self.model(input_tensor)
            probabilities = torch.softmax(logits, dim=1)[0].detach().cpu().numpy()
            if class_index is None:
                class_index = int(logits.argmax(dim=1).item())
            logits[0, class_index].backward()

        if self._activations is None or self._activations.grad is None:
            raise RuntimeError("Grad-CAM captured no activations; is the target layer in this model?")

        activations = self._activations[0].detach()
        gradients = self._activations.grad[0].detach()
        weights = gradients.mean(dim=(1, 2))
        cam = F.relu((weights[:, None, None] * activations).sum(dim=0))

        cam_min, cam_max = cam.min(), cam.max()
        cam = (cam - cam_min) / (cam_max - cam_min) if cam_max > cam_min else torch.zeros_like(cam)

        return cam.cpu().numpy().astype(np.float32), class_index, probabilities


def overlay_heatmap(image: Image.Image, cam: np.ndarray, alpha: float = 0.45) -> Image.Image:
    """Blend the CAM over the original image at its original resolution."""
    base = np.asarray(image.convert("RGB"))
    height, width = base.shape[:2]

    resized = cv2.resize(cam, (width, height), interpolation=cv2.INTER_LINEAR)
    scaled = np.clip(resized * 255, 0, 255).astype(np.uint8)
    # OpenCV colormaps output BGR; convert so the saved PNG is not colour-swapped.
    heatmap = cv2.cvtColor(cv2.applyColorMap(scaled, cv2.COLORMAP_JET), cv2.COLOR_BGR2RGB)

    # Fast and memory-efficient in-place blending without float32 arrays
    blended = cv2.addWeighted(base, 1.0 - alpha, heatmap, alpha, 0.0)
    return Image.fromarray(blended)


def cam_statistics(cam: np.ndarray, border_fraction: float = 0.15) -> dict[str, Any]:
    """Where the heatmap concentrated. See ml/explainability/gradcam.py for the rationale."""
    cam = np.asarray(cam, dtype=np.float32)
    height, width = cam.shape
    total = float(cam.sum())

    band_h = max(1, int(round(height * border_fraction)))
    band_w = max(1, int(round(width * border_fraction)))
    interior = cam[band_h : height - band_h, band_w : width - band_w]

    peak_y, peak_x = divmod(int(np.argmax(cam)), width)
    centre_y, centre_x = (height - 1) / 2, (width - 1) / 2
    max_distance = float(np.hypot(centre_y, centre_x)) or 1.0

    return {
        "border_mass_fraction": float((total - interior.sum()) / total) if total > 0 else 0.0,
        "peak_offset_from_centre": float(np.hypot(peak_y - centre_y, peak_x - centre_x)) / max_distance,
        "is_degenerate": bool(total == 0.0),
    }


def describe_focus(stats: dict[str, Any]) -> str:
    """A short, deliberately non-anatomical description of where the model looked.

    The model has no concept of lesion borders or pigment networks. Describing the heatmap
    in clinical language would be exactly the kind of overclaim the safety layer exists to
    prevent, so this stays geometric.
    """
    if stats["is_degenerate"]:
        return "no clear region of interest"
    if stats["border_mass_fraction"] > 0.5:
        return "spread toward the edges of the image rather than a central region"
    if stats["peak_offset_from_centre"] < 0.3:
        return "concentrated on the central region of the image"
    return "concentrated on an off-centre region of the image"
