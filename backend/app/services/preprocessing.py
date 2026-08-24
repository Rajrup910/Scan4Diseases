"""Image validation and preprocessing for inference.

    upload bytes
        -> size / format validation
        -> decode
        -> EXIF orientation fix
        -> RGB conversion
        -> resize + centre crop
        -> tensor
        -> ImageNet normalisation
        -> model

The transform must match `ml/preprocessing/transforms.py::build_eval_transform` exactly.
A mismatch between training-time and serving-time preprocessing is a classic silent
accuracy killer: nothing errors, the model just gets quietly worse.
`tests/test_preprocessing_parity.py` asserts the two produce identical tensors.
"""

from __future__ import annotations

import io

import torch
from PIL import Image, ImageOps, UnidentifiedImageError
from torchvision import transforms

# Must match ml/preprocessing/transforms.py
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)
RESIZE_RATIO = 256 / 224

ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP", "BMP"}
MIN_DIMENSION = 64

# Pillow raises above this, which stops a crafted image from exhausting server memory.
Image.MAX_IMAGE_PIXELS = 100_000_000


class ImageValidationError(Exception):
    """Raised when an upload cannot be used. The message is safe to show a user."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


def decode_image(data: bytes, max_bytes: int) -> Image.Image:
    """Decode and normalise an uploaded image, or raise ImageValidationError.

    Every failure mode listed in section 30 of the master specification is handled here:
    empty upload, oversized upload, unsupported format, corrupt file, tiny image.
    """
    if not data:
        raise ImageValidationError("empty_upload", "No image was received. Please try again.")

    if len(data) > max_bytes:
        limit_mb = max_bytes / 1024 / 1024
        raise ImageValidationError(
            "file_too_large",
            f"The image is larger than the {limit_mb:.0f} MB limit. Please use a smaller image.",
        )

    try:
        image = Image.open(io.BytesIO(data))
        image.load()  # force full decode; truncated files fail here, not later
    except UnidentifiedImageError as exc:
        raise ImageValidationError(
            "unsupported_format",
            "This file is not a supported image. Please upload a JPEG or PNG photograph.",
        ) from exc
    except OSError as exc:
        raise ImageValidationError(
            "corrupt_image",
            "The image could not be read. It may be incomplete or damaged. Please try again.",
        ) from exc

    if image.format and image.format.upper() not in ALLOWED_FORMATS:
        raise ImageValidationError(
            "unsupported_format",
            f"{image.format} images are not supported. Please upload a JPEG or PNG photograph.",
        )

    # Phone cameras store rotation in EXIF rather than rotating the pixels. Without this,
    # a portrait photo arrives sideways and the model sees a rotated lesion.
    image = ImageOps.exif_transpose(image)

    # Protect cloud memory on free-tier containers: cap max dimension to 1024px
    # while preserving full aspect ratio and crisp lesion details.
    if max(image.size) > 1024:
        image.thumbnail((1024, 1024), Image.Resampling.LANCZOS)

    if min(image.size) < MIN_DIMENSION:
        raise ImageValidationError(
            "image_too_small",
            f"The image is too small ({image.width}x{image.height}). Please capture a "
            f"photograph of at least {MIN_DIMENSION}x{MIN_DIMENSION} pixels.",
        )

    return image.convert("RGB")


def build_eval_transform(image_size: int) -> transforms.Compose:
    """Deterministic inference transform. Identical to the training-time eval transform."""
    resize_to = int(round(image_size * RESIZE_RATIO))
    return transforms.Compose(
        [
            transforms.Resize(resize_to),
            transforms.CenterCrop(image_size),
            transforms.ToTensor(),
            transforms.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
        ]
    )


def to_tensor(image: Image.Image, image_size: int) -> torch.Tensor:
    """Preprocess a PIL image into a (1, 3, H, W) batch."""
    return build_eval_transform(image_size)(image).unsqueeze(0)
