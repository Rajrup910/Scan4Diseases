"""Image quality gate.

Master specification, section 19: a simple, reliable check is preferable to an unreliable
extra ML model. So this is deliberately classical computer vision -- two cheap, well
understood measurements and a resolution check:

    blur        variance of the Laplacian. A sharp image has strong second derivatives
                across many pixels; a blurred one has few. Low variance -> blurry.
    exposure    mean luminance. Near 0 the photo is too dark to carry information;
                near 255 it is blown out.
    resolution  an image smaller than the model's input has been upsampled from nothing.

Everything is measured on the decoded image before preprocessing, so the numbers describe
what the user actually captured.

Deliberately *not* attempted: deciding whether the photo contains skin, or whether a
lesion is present. Doing that reliably needs another trained model, which would need its
own dataset, evaluation and failure analysis. An unreliable gate that rejects real lesions
is worse than no gate at all.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from PIL import Image


@dataclass
class QualityAssessment:
    acceptable: bool
    blur_score: float
    brightness: float
    width: int
    height: int
    warnings: list[str]
    failures: list[str]

    @property
    def primary_problem(self) -> str | None:
        return self.failures[0] if self.failures else None


def assess_quality(
    image: Image.Image,
    min_side: int,
    blur_threshold: float,
    dark_threshold: float,
    bright_threshold: float,
) -> QualityAssessment:
    """Measure image quality. Failures block classification; warnings do not."""
    array = np.asarray(image.convert("RGB"))
    grey = cv2.cvtColor(array, cv2.COLOR_RGB2GRAY)

    blur_score = float(cv2.Laplacian(grey, cv2.CV_64F).var())
    brightness = float(grey.mean())
    height, width = grey.shape

    failures: list[str] = []
    warnings: list[str] = []

    if min(width, height) < min_side:
        failures.append(
            f"The image is only {width}x{height} pixels. Please capture at least "
            f"{min_side}x{min_side} so the lesion is properly resolved."
        )

    # Exposure is checked before blur, and a badly exposed image suppresses the blur
    # failure. A black or blown-out frame has almost no gradient anywhere, so it always
    # scores as "blurred" too -- telling the user to hold the camera steady when the real
    # problem is that the room is dark sends them off to fix the wrong thing.
    exposure_failed = False
    if brightness < dark_threshold:
        failures.append("The image is too dark. Please retake it in brighter, even lighting.")
        exposure_failed = True
    elif brightness > bright_threshold:
        failures.append(
            "The image is overexposed. Move away from direct light or turn off the flash and retake it."
        )
        exposure_failed = True
    elif brightness < dark_threshold * 1.5:
        warnings.append("The lighting is dim; more even lighting would give a better result.")
    elif brightness > bright_threshold - 20:
        warnings.append("The image is quite bright; watch for glare on the skin.")

    if blur_score < blur_threshold:
        if not exposure_failed:
            failures.append(
                "The image appears blurred. Hold the camera steady, tap to focus on the lesion, "
                "and try again."
            )
        else:
            warnings.append("Detail is also very low, which is expected at this exposure.")
    elif blur_score < blur_threshold * 2:
        warnings.append("The image is slightly soft; a sharper photograph would give a better result.")

    # A lesion filling a tiny fraction of a large frame gets destroyed by the centre crop.
    aspect = max(width, height) / max(min(width, height), 1)
    if aspect > 2.5:
        warnings.append(
            "The image is very elongated. The lesion may be cropped — centre it in the frame."
        )

    return QualityAssessment(
        acceptable=not failures,
        blur_score=blur_score,
        brightness=brightness,
        width=width,
        height=height,
        warnings=warnings,
        failures=failures,
    )
