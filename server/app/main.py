from __future__ import annotations

import logging
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from starlette.concurrency import run_in_threadpool

from app.inference import (
    CATEGORY_MODELS,
    MAX_FRAME_BYTES,
    SUPPORTED_VIDEO_SUFFIXES,
    GestureInferenceService,
    InvalidVideoError,
)
from app.firebase_auth import (
    initialize_firebase_admin,
    require_firebase_user,
    validate_session_id,
)

MAX_UPLOAD_BYTES = 30 * 1024 * 1024
logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(application: FastAPI):
    service = GestureInferenceService()
    firebase_app = initialize_firebase_admin()
    application.state.inference_service = service
    application.state.firebase_admin_app = firebase_app
    try:
        yield
    finally:
        service.close()


app = FastAPI(
    title="Gestura Gesture Recognition API",
    description=(
        "Inferensi model BISINDO alfabet, digit, dan vocabulary Gestura. "
        "Model masih baseline dan bukan penerjemah bahasa isyarat universal."
    ),
    version="1.0.0",
    lifespan=lifespan,
)


@app.middleware("http")
async def log_prediction_requests(request: Request, call_next):
    if (
        request.method != "POST"
        or not request.url.path.startswith("/api/v1/predict/")
    ):
        return await call_next(request)

    started_at = time.monotonic()
    logger.info("Prediction request received: %s", request.url.path)
    response = await call_next(request)
    elapsed = time.monotonic() - started_at
    logger.info(
        "Prediction request completed: %s status=%s duration=%.2fs",
        request.url.path,
        response.status_code,
        elapsed,
    )
    return response


@app.get("/health")
def health(request: Request) -> dict[str, Any]:
    service = getattr(request.app.state, "inference_service", None)
    if service is None:
        raise HTTPException(status_code=503, detail="Model belum dimuat.")
    return {
        "status": "ok",
        "service": "gestura-inference",
        "categories": list(CATEGORY_MODELS),
    }


@app.post("/api/v1/predict/{category}")
async def predict(
    category: str,
    request: Request,
    video: UploadFile = File(...),
    uid: str = Depends(require_firebase_user),
) -> dict[str, Any]:
    if category not in CATEGORY_MODELS:
        raise HTTPException(
            status_code=404,
            detail="Kategori harus alphabet, digit, atau vocabulary.",
        )
    filename = video.filename or ""
    suffix = Path(filename).suffix.lower()
    if suffix not in SUPPORTED_VIDEO_SUFFIXES:
        raise HTTPException(
            status_code=415,
            detail="Kirim video MP4, MOV, AVI, MKV, atau WEBM.",
        )
    content_length = request.headers.get("content-length")
    if content_length:
        try:
            declared_size = int(content_length)
        except ValueError as error:
            raise HTTPException(
                status_code=400,
                detail="Header ukuran permintaan tidak valid.",
            ) from error
        if declared_size > MAX_UPLOAD_BYTES + 1024 * 1024:
            raise HTTPException(status_code=413, detail="Ukuran video maksimal 30 MB.")

    temporary_path: Path | None = None
    size = 0
    try:
        with tempfile.NamedTemporaryFile(
            prefix="gestura-",
            suffix=suffix,
            delete=False,
        ) as temporary_file:
            temporary_path = Path(temporary_file.name)
            while chunk := await video.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(
                        status_code=413,
                        detail="Ukuran video maksimal 30 MB.",
                    )
                temporary_file.write(chunk)
        if size == 0:
            raise HTTPException(status_code=400, detail="Video yang dikirim kosong.")

        service: GestureInferenceService = request.app.state.inference_service
        return await run_in_threadpool(
            service.predict_video,
            category,
            temporary_path,
        )
    except InvalidVideoError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error
    finally:
        await video.close()
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


@app.post("/api/v1/predict/{category}/frame")
async def predict_frame(
    category: str,
    request: Request,
    frame: UploadFile = File(...),
    session_id: str = Form(...),
    uid: str = Depends(require_firebase_user),
) -> dict[str, Any]:
    if category not in CATEGORY_MODELS:
        raise HTTPException(
            status_code=404,
            detail="Kategori harus alphabet, digit, atau vocabulary.",
        )
    validate_session_id(session_id)
    if frame.content_type not in {"image/jpeg", "image/jpg"}:
        raise HTTPException(status_code=415, detail="Frame harus berupa JPEG.")
    content = await frame.read(MAX_FRAME_BYTES + 1)
    await frame.close()
    if not content:
        raise HTTPException(status_code=400, detail="Frame yang dikirim kosong.")
    if len(content) > MAX_FRAME_BYTES:
        raise HTTPException(status_code=413, detail="Ukuran frame maksimal 5 MB.")

    service: GestureInferenceService = request.app.state.inference_service
    try:
        return await run_in_threadpool(
            service.predict_frame,
            category,
            uid,
            session_id,
            content,
        )
    except InvalidVideoError as error:
        raise HTTPException(status_code=422, detail=str(error)) from error


@app.delete("/api/v1/session/{session_id}")
def clear_session(
    session_id: str,
    request: Request,
    uid: str = Depends(require_firebase_user),
) -> dict[str, str]:
    validate_session_id(session_id)
    service: GestureInferenceService = request.app.state.inference_service
    service.clear_live_session(uid, session_id)
    return {"status": "cleared"}
