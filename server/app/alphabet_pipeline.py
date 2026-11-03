from __future__ import annotations

import hashlib
import json
import urllib.request
from pathlib import Path
from typing import Any

import mediapipe as mp
import numpy as np
from PIL import Image, ImageOps

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET = PROJECT_ROOT / "server" / "dataset" / "1_alphabet"
DEFAULT_FEATURES = PROJECT_ROOT / "server" / "processed" / "alphabet_landmarks.npz"
DEFAULT_MODEL = (
    PROJECT_ROOT / "server" / "trained_models" / "alphabet" / "model.joblib"
)
LANDMARKER_ASSET = (
    PROJECT_ROOT / "server" / ".cache" / "hand_landmarker.task"
)
LANDMARKER_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)
LABELS = tuple("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
FEATURES_PER_HAND = 66
FEATURE_SIZE = FEATURES_PER_HAND * 2
FEATURE_SCHEMA_VERSION = 1
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_landmarker_asset(path: Path = LANDMARKER_ASSET) -> Path:
    if path.is_file() and path.stat().st_size > 1_000_000:
        return path

    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = path.with_suffix(path.suffix + ".download")
    request = urllib.request.Request(
        LANDMARKER_URL,
        headers={"User-Agent": "Gestura-Alphabet-Pipeline/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            with temporary_path.open("wb") as file:
                while chunk := response.read(1024 * 1024):
                    file.write(chunk)
        if temporary_path.stat().st_size <= 1_000_000:
            raise RuntimeError("File model MediaPipe yang diunduh terlalu kecil.")
        temporary_path.replace(path)
    except Exception:
        temporary_path.unlink(missing_ok=True)
        raise
    return path


def create_landmarker_options(
    model_path: Path,
    running_mode: Any = None,
) -> Any:
    if running_mode is None:
        running_mode = mp.tasks.vision.RunningMode.IMAGE
    return mp.tasks.vision.HandLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model_path)),
        running_mode=running_mode,
        num_hands=2,
        min_hand_detection_confidence=0.35,
        min_hand_presence_confidence=0.35,
        min_tracking_confidence=0.35,
    )


def image_to_features(image: Image.Image, result: Any) -> tuple[np.ndarray, int]:
    width, height = image.size
    hands = []
    for landmarks in result.hand_landmarks[:2]:
        coordinates = np.asarray(
            [
                (point.x * width, point.y * height, point.z * width)
                for point in landmarks
            ],
            dtype=np.float32,
        )
        wrist = coordinates[0]
        scale = float(np.linalg.norm(coordinates[9, :2] - wrist[:2]))
        if scale < 1e-6:
            scale = float(np.linalg.norm(coordinates[5, :2] - wrist[:2]))
        if scale < 1e-6:
            continue

        local_coordinates = (coordinates - wrist) / scale
        hand_features = np.concatenate(
            (
                local_coordinates.reshape(-1),
                np.asarray((wrist[0] / width, wrist[1] / height, 1.0)),
            )
        )
        hands.append((float(wrist[0] / width), hand_features))

    hands.sort(key=lambda item: item[0])
    feature = np.zeros(FEATURE_SIZE, dtype=np.float32)
    for index, (_, hand_features) in enumerate(hands):
        start = index * FEATURES_PER_HAND
        feature[start : start + FEATURES_PER_HAND] = hand_features
    return feature, len(hands)


def extract_image_features(
    image_path: Path,
    landmarker: Any,
) -> tuple[np.ndarray, int]:
    with Image.open(image_path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
    image_array = np.asarray(image)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_array)
    result = landmarker.detect(mp_image)
    return image_to_features(image, result)


def load_feature_dataset(path: Path) -> dict[str, np.ndarray]:
    if not path.is_file():
        raise FileNotFoundError(
            f"Fitur belum tersedia: {path}. Jalankan extract_alphabet_landmarks.py."
        )
    with np.load(path, allow_pickle=False) as archive:
        required = {"X", "y", "groups", "paths", "hand_counts", "schema_version"}
        missing = required.difference(archive.files)
        if missing:
            raise ValueError(f"Arsip fitur tidak memiliki kolom: {sorted(missing)}")
        dataset = {name: archive[name] for name in required}

    schema_version = int(dataset["schema_version"][0])
    if schema_version != FEATURE_SCHEMA_VERSION:
        raise ValueError(
            f"Versi fitur {schema_version} tidak cocok dengan pipeline "
            f"{FEATURE_SCHEMA_VERSION}. Ekstrak ulang landmark."
        )
    if dataset["X"].ndim != 2 or dataset["X"].shape[1] != FEATURE_SIZE:
        raise ValueError(
            f"Ukuran fitur tidak valid; diharapkan (N, {FEATURE_SIZE}), "
            f"ditemukan {dataset['X'].shape}."
        )
    if not np.isfinite(dataset["X"]).all():
        raise ValueError("Fitur mengandung nilai NaN atau tak hingga.")
    return dataset


def load_model_artifact(path: Path) -> dict[str, Any]:
    import joblib

    if not path.is_file():
        raise FileNotFoundError(
            f"Model belum tersedia: {path}. Jalankan train_alphabet.py."
        )
    artifact = joblib.load(path)
    if artifact.get("feature_schema_version") != FEATURE_SCHEMA_VERSION:
        raise ValueError("Versi fitur model berbeda dari pipeline saat ini.")
    if tuple(artifact.get("labels", ())) != LABELS:
        raise ValueError("Pemetaan label model bukan alfabet A-Z yang diharapkan.")
    return artifact


def predict_feature(
    feature: np.ndarray,
    artifact: dict[str, Any],
) -> dict[str, Any]:
    if feature.shape != (FEATURE_SIZE,):
        raise ValueError(f"Fitur prediksi harus memiliki {FEATURE_SIZE} nilai.")
    if not np.isfinite(feature).all():
        raise ValueError("Fitur prediksi mengandung NaN atau tak hingga.")
    if feature[FEATURES_PER_HAND - 1] == 0 and feature[-1] == 0:
        return {
            "label": None,
            "candidate": None,
            "confidence": 0.0,
            "threshold": float(artifact["confidence_threshold"]),
            "status": "not_recognized",
            "reason": "Tidak ada tangan yang terdeteksi.",
        }

    probabilities = artifact["estimator"].predict_proba(feature.reshape(1, -1))[0]
    best_index = int(np.argmax(probabilities))
    confidence = float(probabilities[best_index])
    threshold = float(artifact["confidence_threshold"])
    accepted = confidence >= threshold
    return {
        "label": str(artifact["labels"][best_index]) if accepted else None,
        "candidate": str(artifact["labels"][best_index]),
        "confidence": confidence,
        "threshold": threshold,
        "status": "recognized" if accepted else "not_recognized",
        "reason": None if accepted else "Confidence di bawah ambang model.",
    }


def json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    if isinstance(value, (np.integer,)):
        return int(value)
    if isinstance(value, (np.floating,)):
        return float(value)
    if isinstance(value, Path):
        return str(value)
    return value


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(json_safe(payload), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
