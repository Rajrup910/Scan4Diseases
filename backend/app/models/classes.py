"""Class-mapping loader for the API server.

Reads the same version-controlled `ml/configs/class_mapping.json` that training used. The
file is the single source of truth for class order, display names, translations and
malignancy tier -- the last of which the triage layer depends on.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from backend.app.schemas.common import Language


@dataclass(frozen=True)
class SkinClass:
    index: int
    code: str
    names: dict[str, str]
    short_names: dict[str, str]
    plain_language: dict[str, str]
    malignancy: str

    def name(self, language: Language = Language.ENGLISH) -> str:
        return self.names.get(language.value) or self.names["en"]

    def short_name(self, language: Language = Language.ENGLISH) -> str:
        return self.short_names.get(language.value) or self.short_names["en"]

    def description(self, language: Language = Language.ENGLISH) -> str:
        return self.plain_language.get(language.value) or self.plain_language["en"]

    @property
    def is_malignant(self) -> bool:
        return self.malignancy == "malignant"


@dataclass(frozen=True)
class ClassMapping:
    version: str
    classes: tuple[SkinClass, ...]

    @property
    def num_classes(self) -> int:
        return len(self.classes)

    @property
    def codes(self) -> tuple[str, ...]:
        return tuple(c.code for c in self.classes)

    def by_index(self, index: int) -> SkinClass:
        return self.classes[index]

    def by_code(self, code: str) -> SkinClass:
        for skin_class in self.classes:
            if skin_class.code == code:
                return skin_class
        raise KeyError(f"unknown class code {code!r}")

    def malignancy_by_code(self) -> dict[str, str]:
        """Used by the triage layer to decide which classes escalate."""
        return {c.code: c.malignancy for c in self.classes}


@lru_cache(maxsize=4)
def load_class_mapping(path: str | Path) -> ClassMapping:
    file_path = Path(path)
    if not file_path.is_file():
        raise FileNotFoundError(f"class mapping not found at {file_path}")

    raw = json.loads(file_path.read_text(encoding="utf-8"))
    classes = tuple(
        SkinClass(
            index=entry["index"],
            code=entry["code"],
            names=entry["name"],
            short_names=entry["short_name"],
            plain_language=entry["plain_language"],
            malignancy=entry["malignancy"],
        )
        for entry in sorted(raw["classes"], key=lambda e: e["index"])
    )

    if len(classes) != raw["num_classes"]:
        raise ValueError(
            f"class mapping declares num_classes={raw['num_classes']} but lists {len(classes)}"
        )
    if [c.index for c in classes] != list(range(len(classes))):
        raise ValueError("class indices must be contiguous starting at 0")

    return ClassMapping(version=raw["version"], classes=classes)
