"""GET /gradcam/{filename} — serve a temporary Grad-CAM overlay.

Overlays are short-lived and named with an unguessable token. Path traversal is blocked in
`TemporaryStore.path_for`, which refuses anything that does not resolve inside the storage
directory.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from fastapi.responses import FileResponse

from backend.app.dependencies import get_store
from backend.app.services.storage import TemporaryStore
from backend.app.utils.errors import AppError

router = APIRouter(tags=["media"])


@router.get("/gradcam/{filename}", response_class=FileResponse)
async def get_gradcam(
    filename: str,
    store: TemporaryStore = Depends(get_store),
) -> FileResponse:
    path = store.path_for(filename)
    if path is None:
        raise AppError(
            "gradcam_not_found",
            "This heatmap is no longer available. Heatmaps are deleted a short time after "
            "a scan for privacy. Please run the scan again.",
            status.HTTP_404_NOT_FOUND,
        )

    return FileResponse(
        path,
        media_type="image/png",
        # Do not let a proxy or the client cache a medical image beyond its lifetime.
        headers={"Cache-Control": "private, no-store"},
    )
