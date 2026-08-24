"""FastAPI application entry point.

Run it:
    python -m uvicorn backend.app.main:app --reload --port 8000
    # interactive docs at http://localhost:8000/docs
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from backend.app import __version__
from backend.app.config import get_settings
from backend.app.db.seed import seed_default_data
from backend.app.db.session import SessionLocal, init_db
from backend.app.routes import (
    admin,
    auth,
    chat,
    doctor,
    health,
    media,
    patient_sharing,
    portal,
    predict,
    reports,
)
from backend.app.routes.portal import PortalAuthRequired
from backend.app.services.image_vault import ImageVault
from backend.app.services.inference import InferenceService
from backend.app.services.lesion_gate import LesionGate
from backend.app.services.lesion_router import LesionRouter
from backend.app.services.llm import LLMService
from backend.app.services.ood import MahalanobisOOD
from backend.app.services.storage import TemporaryStore
from backend.app.utils.errors import configure_logging, register_exception_handlers

logger = logging.getLogger(__name__)

DESCRIPTION = """
AI-assisted dermatology **screening** support. Not a diagnostic device.

The pipeline separates three concerns deliberately:

| Component | Decides |
|---|---|
| CNN (ResNet-50 / EfficientNet-B0) | which visual category the lesion resembles |
| Deterministic rule layer | the urgency category — auditable, unit-tested Python |
| Open-source LLM | wording and translation only |

The language model never sets urgency and never overrides the safety layer. The medical
disclaimer is produced by this application, not generated.
"""


async def _janitor(store: TemporaryStore, interval_seconds: int = 300) -> None:
    """Periodically delete expired Grad-CAM overlays.

    Writes also purge opportunistically, but a server that goes idle right after a scan
    would otherwise keep that image on disk indefinitely.
    """
    while True:
        try:
            await asyncio.sleep(interval_seconds)
            store.purge_expired()
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - the janitor must never kill the server
            logger.exception("janitor pass failed")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    configure_logging(settings.debug)

    logger.info("Scan4Disease backend %s starting (%s)", __version__, settings.app_env)

    # Create the users/reports tables if they do not exist yet.
    init_db()
    with SessionLocal() as db_session:
        seed_default_data(db_session)

    inference = InferenceService(settings)
    inference.load()

    llm = LLMService(settings)
    await llm.startup()

    store = TemporaryStore(settings.storage_path, settings.storage_ttl_minutes)
    store.purge_expired()

    # Encrypted store for images a patient shares with a doctor. Unconfigured (no key) is a
    # valid startup state -- /predict and metadata-only sharing still work; only an attempt
    # to upload or serve a shared image then fails loudly.
    image_vault = ImageVault(settings.shared_image_path, settings.image_encryption_key)
    if not image_vault.configured:
        logger.warning(
            "IMAGE_ENCRYPTION_KEY not set - patients cannot share report images. Generate "
            'one: python -c "from cryptography.fernet import Fernet; '
            'print(Fernet.generate_key().decode())"'
        )

    # OOD detector. None when disabled or the fitted artifact is absent; the predict
    # route treats None as "gate off" and proceeds without rejecting on distribution.
    ood = MahalanobisOOD.load(settings.ood_stats_file) if settings.ood_enabled else None
    if ood is not None and settings.ood_threshold is not None:
        logger.info(
            "OOD threshold overridden: %.1f -> %.1f (OOD_THRESHOLD)",
            ood.threshold, settings.ood_threshold,
        )
        ood.threshold = float(settings.ood_threshold)
    if settings.ood_enabled and ood is None:
        logger.warning(
            "OOD detection enabled but no stats loaded - non-lesion images will not be "
            "rejected. Run: python -m ml.ood.fit_mahalanobis"
        )

    # Binary lesion-presence gate (the primary defence against skin-but-not-lesion).
    gate = LesionGate.load(settings.lesion_gate_file) if settings.lesion_gate_enabled else None
    if gate is not None and settings.lesion_gate_threshold is not None:
        logger.info(
            "Lesion-gate threshold overridden: %.3f -> %.3f (LESION_GATE_THRESHOLD)",
            gate.threshold, settings.lesion_gate_threshold,
        )
        gate.threshold = float(settings.lesion_gate_threshold)
    if settings.lesion_gate_enabled and gate is None:
        logger.warning(
            "Lesion gate enabled but not fitted - skin-but-not-lesion photos will pass. "
            "Run: python -m ml.ood.fit_lesion_gate"
        )

    # Front-stage router. When present it supersedes the binary gate: healthy skin and
    # wounds get their own outcome instead of a bare "no lesion detected".
    lesion_router = (
        LesionRouter.load(settings.lesion_router_file)
        if settings.lesion_router_enabled
        else None
    )
    if settings.lesion_router_enabled and lesion_router is None:
        logger.warning(
            "Lesion router enabled but not fitted - falling back to the binary lesion gate. "
            "Run: python -m ml.ood.fit_lesion_router"
        )

    app.state.settings = settings
    app.state.inference = inference
    app.state.llm = llm
    app.state.store = store
    app.state.image_vault = image_vault
    app.state.ood = ood
    app.state.lesion_gate = gate
    app.state.lesion_router = lesion_router

    janitor = asyncio.create_task(_janitor(store)) if store.enabled else None

    if not inference.is_loaded:
        if settings.allow_stub_model:
            logger.warning(
                "STUB MODE ACTIVE - /predict returns synthetic values. "
                "Never use this for a demo or evaluation."
            )
        else:
            logger.warning("No model loaded - /predict will return 503 until one is trained.")

    yield

    if janitor is not None:
        janitor.cancel()
        # Awaiting a cancelled task re-raises CancelledError; that is the expected path.
        with contextlib.suppress(asyncio.CancelledError):
            await janitor

    removed = store.purge_all()
    if removed:
        logger.info("removed %d temporary overlay(s) on shutdown", removed)

    await llm.shutdown()
    inference.unload()
    logger.info("shutdown complete")


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title="Scan4Disease — Dermatology Screening API",
        description=DESCRIPTION,
        version=__version__,
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["*"],
    )

    register_exception_handlers(app)

    # A portal page reached without a valid doctor session redirects to the login form,
    # rather than returning the JSON 401/403 the mobile API uses -- the caller is a browser.
    @app.exception_handler(PortalAuthRequired)
    async def _portal_auth_required(_request: Request, _exc: PortalAuthRequired):
        return RedirectResponse("/portal/login", status_code=303)

    # Static assets for the server-rendered portal (local stylesheet only; no CDN).
    static_dir = Path(__file__).resolve().parent / "static"
    app.mount("/portal/static", StaticFiles(directory=str(static_dir)), name="portal-static")

    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(reports.router)
    app.include_router(predict.router)
    app.include_router(chat.router)
    app.include_router(media.router)
    app.include_router(patient_sharing.router)
    app.include_router(doctor.router)
    app.include_router(portal.router)
    app.include_router(admin.router)

    @app.get("/", include_in_schema=False)
    async def root() -> dict[str, str]:
        return {
            "name": "Scan4Disease Dermatology Screening API",
            "version": __version__,
            "docs": "/docs",
            "health": "/health",
            "notice": "AI screening support only. This is not a medical diagnosis.",
        }

    return app


app = create_app()
