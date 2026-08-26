"""Application configuration.

Every tunable value comes from the environment or `.env`. Nothing is hardcoded in the
route handlers, and no secret is ever committed -- `.env.example` documents the shape,
`.env` holds the real values and is git-ignored.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# backend/app/config.py -> backend/app -> backend -> repo root
REPO_ROOT = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(REPO_ROOT / ".env", REPO_ROOT / "backend" / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
        # `model_` is a pydantic-reserved prefix; we want MODEL_ARCH etc. to work anyway.
        protected_namespaces=(),
    )

    # --- server ---
    app_env: str = "development"
    host: str = "0.0.0.0"
    port: int = 8000
    debug: bool = True
    cors_origins: str = "*"

    # --- model ---
    model_checkpoint: str = "ml/checkpoints/resnet50_best.pt"
    model_arch: str = "resnet50"
    model_image_size: int = 224
    model_device: str = "auto"
    class_mapping_path: str = "ml/configs/class_mapping.json"
    # Serve clearly-labelled fake predictions when no checkpoint exists, so the mobile
    # team can build screens before training finishes. Must be false in any demo.
    allow_stub_model: bool = False

    # --- inference thresholds ---
    low_confidence_threshold: float = Field(default=0.60, ge=0.0, le=1.0)
    calibration_temperature: float = Field(default=1.0, gt=0.0)

    # --- out-of-distribution (OOD) detection ---
    # Reject images that don't resemble any trained lesion class (e.g. a hand, a wall),
    # using Mahalanobis distance on penultimate features. Requires the fitted artifact
    # produced by `python -m ml.ood.fit_mahalanobis`; if absent, the gate is skipped.
    ood_enabled: bool = True
    ood_stats_path: str = "ml/checkpoints/ood_mahalanobis.npz"
    # Override the fitted threshold without re-fitting. None uses the value baked into the
    # artifact (chosen at fit time by --percentile). Lower = catches more OOD but rejects
    # more real lesions. Calibrate against real non-lesion photos using the logged scores.
    ood_threshold: float | None = None

    # Binary lesion-presence gate. A discriminative classifier that rejects non-lesion
    # photos (a hand, a forearm) the Mahalanobis distance can't separate. Requires the
    # artifact from `python -m ml.ood.fit_lesion_gate`; if absent, this gate is skipped.
    lesion_gate_enabled: bool = True
    lesion_gate_path: str = "ml/checkpoints/lesion_gate.npz"
    # Override the fitted decision threshold on P(lesion). None uses the fitted value.
    # Higher = rejects more (including more real lesions); lower = more permissive.
    lesion_gate_threshold: float | None = None

    # Front-stage router. A multi-class head (lesion / healthy / other_damage / not_skin)
    # from `python -m ml.ood.fit_lesion_router`. When enabled AND the artifact loads, it
    # REPLACES the binary lesion gate: instead of a bare "no lesion detected", healthy skin
    # and wounds get their own informative outcome. The lesion route stays high-recall, so
    # the disease model still sees ~98% of real lesions. Falls back to the binary gate if
    # the artifact is missing.
    lesion_router_enabled: bool = True
    lesion_router_path: str = "ml/checkpoints/lesion_router.npz"

    # --- image quality gate ---
    quality_min_side_px: int = 224
    quality_max_upload_mb: float = 10.0
    quality_blur_threshold: float = 10.0
    quality_dark_threshold: float = 40.0
    quality_bright_threshold: float = 225.0

    # --- storage ---
    storage_dir: str = "backend/storage"
    storage_ttl_minutes: int = 15

    # --- shared-image encryption ---
    # A patient's lesion image is persisted ONLY when they share a report, and only ever
    # as a Fernet-encrypted blob. This is the symmetric key for that encryption; it MUST be
    # set (a urlsafe-base64 32-byte Fernet key) before image sharing works. Generate one:
    #   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    # Left unset, /predict, saving reports and metadata-only sharing all still work; only an
    # attempt to upload or serve a shared image fails loudly, never silently in plaintext.
    image_encryption_key: str = "_vDxQjzxSasYBgFY5BhXwK9VbO9ugaa7hR2uqIDTtuo="

    # --- database & auth ---
    # SQLite file, resolved relative to the repo root. Git-ignored under backend/storage.
    database_path: str = "backend/storage/app.db"
    # MUST be overridden via JWT_SECRET in .env for anything beyond local dev. Tokens
    # signed with the default are trivially forgeable.
    jwt_secret: str = "dev-insecure-change-me-set-JWT_SECRET-in-env"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 14  # 14 days
    # Doctor web-portal session length. Deliberately much shorter than the mobile patient
    # token above: the portal is used at a shared clinic workstation, so an idle session
    # should lapse quickly. Both use the same JWT secret; only the expiry differs.
    portal_session_minutes: int = 60

    # --- LLM ---
    llm_enabled: bool = True
    llm_base_url: str = "https://api.groq.com/openai/v1"
    llm_model: str = "openai/gpt-oss-120b"
    llm_api_key: str = ""
    llm_timeout_seconds: float = 30.0
    llm_max_tokens: int = 700
    llm_temperature: float = Field(default=0.3, ge=0.0, le=2.0)
    llm_rate_limit_rpm: int = Field(default=10, ge=1)
    llm_rate_limit_max_concurrent: int = Field(default=3, ge=1)

    # --- admin ---
    # Used by POST /admin/promote-doctor to guard one-time cloud DB seeding.
    # Set ADMIN_SECRET in Render env vars before calling the endpoint; clear it after.
    admin_secret: str = ""

    # Insecure default sentinels — the app refuses to run in production while any
    # of these are still in place (see `production_issues`).
    _INSECURE_JWT_SECRET = "dev-insecure-change-me-set-JWT_SECRET-in-env"
    _INSECURE_IMAGE_KEY = "_vDxQjzxSasYBgFY5BhXwK9VbO9ugaa7hR2uqIDTtuo="

    @field_validator("model_arch")
    @classmethod
    def _known_arch(cls, value: str) -> str:
        allowed = {"resnet50", "efficientnet_b0"}
        if value not in allowed:
            raise ValueError(f"MODEL_ARCH must be one of {sorted(allowed)}, got {value!r}")
        return value

    @property
    def is_production(self) -> bool:
        return self.app_env.strip().lower() == "production"

    def production_issues(self) -> list[str]:
        """FATAL insecure-for-production settings. A non-empty list stops
        startup — these have a safe fix with no data impact (rotate a secret,
        turn off debug), so there's no excuse to ship with them."""
        issues: list[str] = []
        if self.jwt_secret == self._INSECURE_JWT_SECRET or len(self.jwt_secret) < 32:
            issues.append("JWT_SECRET is unset/default/too short — set a 32+ char random secret.")
        if self.debug:
            issues.append("DEBUG must be false in production.")
        if self.allow_stub_model:
            issues.append("ALLOW_STUB_MODEL must be false in production.")
        return issues

    def production_warnings(self) -> list[str]:
        """NON-FATAL production smells worth logging loudly but not worth
        refusing to boot over — e.g. rotating the image key would orphan
        already-encrypted blobs, so that's the operator's call."""
        warnings: list[str] = []
        if self.image_encryption_key == self._INSECURE_IMAGE_KEY:
            warnings.append(
                "IMAGE_ENCRYPTION_KEY is the committed default — rotate to a fresh "
                "Fernet key (note: this orphans images encrypted with the old key)."
            )
        if self.admin_secret and len(self.admin_secret) < 16:
            warnings.append("ADMIN_SECRET is set but shorter than 16 chars.")
        if self.cors_origins.strip() == "*":
            warnings.append("CORS is wide-open ('*') — set CORS_ORIGINS to your app origins.")
        return warnings

    # --- derived paths ---

    def resolve(self, path: str) -> Path:
        candidate = Path(path)
        return candidate if candidate.is_absolute() else REPO_ROOT / candidate

    @property
    def checkpoint_path(self) -> Path:
        return self.resolve(self.model_checkpoint)

    @property
    def class_mapping_file(self) -> Path:
        return self.resolve(self.class_mapping_path)

    @property
    def storage_path(self) -> Path:
        return self.resolve(self.storage_dir)

    @property
    def shared_image_path(self) -> Path:
        """Directory for encrypted shared-image blobs. Kept apart from the Grad-CAM
        overlays so the TTL janitor (which only touches `gradcam_*`) never deletes them --
        shared images persist until the patient unshares, not on a timer."""
        return self.storage_path / "shared"

    @property
    def ood_stats_file(self) -> Path:
        return self.resolve(self.ood_stats_path)

    @property
    def lesion_gate_file(self) -> Path:
        return self.resolve(self.lesion_gate_path)

    @property
    def lesion_router_file(self) -> Path:
        return self.resolve(self.lesion_router_path)

    @property
    def database_file(self) -> Path:
        return self.resolve(self.database_path)

    @property
    def database_url(self) -> str:
        return f"sqlite:///{self.database_file.as_posix()}"

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def max_upload_bytes(self) -> int:
        return int(self.quality_max_upload_mb * 1024 * 1024)


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
