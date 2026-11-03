from __future__ import annotations

import hashlib
import io
import math
import random
import threading
import time
from pathlib import Path
from typing import Any

import cv2
import joblib
import mediapipe as mp
import numpy as np
from PIL import Image

from app.alphabet_pipeline import (
    FEATURE_SCHEMA_VERSION,
    FEATURES_PER_HAND,
    PROJECT_ROOT,
    create_landmarker_options,
    ensure_landmarker_asset,
    image_to_features,
)
from app.video_features import (
    VOCABULARY_FEATURE_SIZE,
    aggregate_video_features,
)

CATEGORY_MODELS = {
    "alphabet": "alphabet",
    "digit": "digit",
    "vocabulary": "vocabulary",
}
EXPECTED_FEATURE_SIZES = {
    "alphabet": FEATURES_PER_HAND * 2,
    "digit": FEATURES_PER_HAND * 2,
    "vocabulary": VOCABULARY_FEATURE_SIZE,
}
EXPECTED_LABELS = {
    "alphabet": tuple("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
    "digit": tuple(str(number) for number in range(1, 10)),
    "vocabulary": (
        "Air",
        "Belajar",
        "Cari",
        "Hari",
        "Ingat",
        "Lagi",
        "Maaf",
        "Makan",
        "Motor",
        "Saya",
        "Terima kasih",
        "Tuli",
        "Apa",
        "Siapa",
        "Kapan",
        "Di mana",
        "Mengapa",
        "Bagaimana",
        "Merah",
        "Kuning",
        "Hijau",
        "Hitam",
        "Dengar",
        "Berangkat",
        "Datang",
        "Teman",
        "Keluarga",
        "Rumah",
        "Pagi",
        "Siang",
        "Sore",
        "Malam",
    ),
}
SUPPORTED_VIDEO_SUFFIXES = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
SAMPLES_PER_VIDEO = 12
MIN_VALID_FRAMES = 3
MAX_VIDEO_SECONDS = 30
MAX_VIDEO_FPS = 120
MAX_FRAME_BYTES = 5 * 1024 * 1024
LIVE_HISTORY_FRAMES = 12
LIVE_SESSION_TTL_SECONDS = 600


class InvalidVideoError(ValueError):
    pass


def prediction_from_probabilities(
    category: str,
    probabilities: np.ndarray,
    estimator_classes: tuple[str, ...],
    confidence_threshold: float,
    frame_count: int,
    detected_frame_count: int,
) -> dict[str, Any]:
    if probabilities.ndim != 1 or len(probabilities) != len(estimator_classes):
        raise ValueError("Bentuk probabilitas model tidak sesuai dengan kelas.")
    if not estimator_classes:
        raise ValueError("Model tidak memiliki kelas hasil.")
    if not np.isfinite(probabilities).all():
        raise ValueError("Model menghasilkan confidence yang tidak valid.")

    best_index = int(np.argmax(probabilities))
    confidence = float(probabilities[best_index])
    candidate = estimator_classes[best_index]
    accepted = confidence >= confidence_threshold
    return {
        "category": category,
        "status": "recognized" if accepted else "not_recognized",
        "label": candidate if accepted else None,
        "candidate": candidate,
        "confidence": confidence,
        "threshold": float(confidence_threshold),
        "reason": None if accepted else "Confidence di bawah ambang model.",
        "model": category,
        "sampled_frames": frame_count,
        "detected_frames": detected_frame_count,
    }


class GestureInferenceService:
    def __init__(
        self,
        model_dir: Path | None = None,
        landmarker_asset: Path | None = None,
    ) -> None:
        self._model_dir = model_dir or PROJECT_ROOT / "server" / "trained_models"
        self._models = {
            category: self._load_model(category)
            for category in CATEGORY_MODELS
        }
        asset_path = landmarker_asset or ensure_landmarker_asset()
        self._landmarker = mp.tasks.vision.HandLandmarker.create_from_options(
            create_landmarker_options(asset_path)
        )
        self._landmarker_lock = threading.Lock()
        self._live_sessions: dict[
            tuple[str, str],
            dict[str, Any],
        ] = {}
        self._live_sessions_lock = threading.Lock()

    def _load_model(self, category: str) -> dict[str, Any]:
        model_path = self._model_dir / category / "model.joblib"
        if not model_path.is_file():
            raise FileNotFoundError(
                f"Model {category} belum tersedia di {model_path}. "
                f"Jalankan pipeline training kategori {category} terlebih dahulu."
            )
        artifact = joblib.load(model_path)
        expected_labels = EXPECTED_LABELS[category]
        artifact_labels = tuple(str(label) for label in artifact.get("labels", ()))
        estimator = artifact.get("estimator")
        if estimator is None or not hasattr(estimator, "predict_proba"):
            raise ValueError(f"Artefak model {category} tidak memiliki classifier.")
        if artifact_labels != expected_labels:
            raise ValueError(f"Pemetaan kelas pada model {category} tidak cocok.")
        if artifact.get("feature_schema_version") != FEATURE_SCHEMA_VERSION:
            raise ValueError(f"Versi fitur model {category} tidak cocok.")
        if artifact.get("feature_size", EXPECTED_FEATURE_SIZES[category]) != (
            EXPECTED_FEATURE_SIZES[category]
        ):
            raise ValueError(f"Ukuran fitur model {category} tidak cocok.")
        estimator_classes = tuple(str(label) for label in estimator.classes_)
        if set(estimator_classes) != set(expected_labels):
            raise ValueError(f"Kelas classifier {category} tidak cocok dengan label.")
        if not math.isfinite(float(artifact.get("confidence_threshold", float("nan")))):
            raise ValueError(f"Ambang confidence model {category} tidak valid.")
        return artifact

    def close(self) -> None:
        self._landmarker.close()

    @staticmethod
    def _file_digest(path: Path) -> bytes:
        digest = hashlib.sha256()
        with path.open("rb") as file:
            for chunk in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.digest()

    @staticmethod
    def _sample_video_frames(path: Path) -> list[np.ndarray]:
        capture = cv2.VideoCapture(str(path))
        if not capture.isOpened():
            capture.release()
            raise InvalidVideoError("File tidak dapat dibuka sebagai video.")
        try:
            fps = float(capture.get(cv2.CAP_PROP_FPS))
            reported_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
            if not math.isfinite(fps) or fps <= 0 or fps > MAX_VIDEO_FPS:
                raise InvalidVideoError("FPS video tidak didukung.")
            if reported_frames > 0 and reported_frames / fps > MAX_VIDEO_SECONDS:
                raise InvalidVideoError("Durasi video maksimal 30 detik.")

            rng = random.Random(int.from_bytes(GestureInferenceService._file_digest(path)[:8]))
            sampled: list[tuple[int, np.ndarray]] = []
            frame_count = 0
            maximum_frames = math.ceil(fps * MAX_VIDEO_SECONDS)
            while True:
                ok, frame = capture.read()
                if not ok:
                    break
                height, width = frame.shape[:2]
                if width * height > 16_000_000:
                    raise InvalidVideoError(
                        "Resolusi video terlalu besar; batasnya 16 megapiksel."
                    )
                if frame_count >= maximum_frames:
                    raise InvalidVideoError("Durasi video maksimal 30 detik.")
                if frame_count < SAMPLES_PER_VIDEO:
                    sampled.append((frame_count, frame.copy()))
                else:
                    replacement = rng.randrange(frame_count + 1)
                    if replacement < SAMPLES_PER_VIDEO:
                        sampled[replacement] = (frame_count, frame.copy())
                frame_count += 1

            if frame_count == 0:
                raise InvalidVideoError("Video tidak memiliki frame yang bisa dibaca.")
            sampled.sort(key=lambda item: item[0])
            return [
                cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                for _, frame in sampled
            ]
        except cv2.error as error:
            raise InvalidVideoError("Video rusak atau formatnya tidak didukung.") from error
        finally:
            capture.release()

    def predict_video(self, category: str, path: Path) -> dict[str, Any]:
        if category not in CATEGORY_MODELS:
            raise ValueError(f"Kategori tidak didukung: {category}.")
        if path.suffix.lower() not in SUPPORTED_VIDEO_SUFFIXES:
            raise InvalidVideoError("Format video tidak didukung.")
        frames = self._sample_video_frames(path)
        artifact = self._models[category]
        estimator = artifact["estimator"]
        frame_features: list[np.ndarray] = []
        valid_frame_indices: list[int] = []
        hand_counts: list[int] = []

        with self._landmarker_lock:
            for frame_index, frame in enumerate(frames):
                image = Image.fromarray(frame)
                result = self._landmarker.detect(
                    mp.Image(image_format=mp.ImageFormat.SRGB, data=frame)
                )
                features, detected_hands = image_to_features(image, result)
                if detected_hands:
                    frame_features.append(features)
                    valid_frame_indices.append(frame_index)
                    hand_counts.append(detected_hands)

            if category == "vocabulary":
                if len(frame_features) < MIN_VALID_FRAMES:
                    return self._not_recognized(
                        category,
                        artifact,
                        len(frames),
                        len(frame_features),
                        "Tangan terdeteksi pada kurang dari 3 frame.",
                    )
                feature = aggregate_video_features(
                    frame_features,
                    list(range(len(frames))),
                    hand_counts,
                )
                probabilities = estimator.predict_proba(feature.reshape(1, -1))[0]
            else:
                if not frame_features:
                    return self._not_recognized(
                        category,
                        artifact,
                        len(frames),
                        0,
                        "Tidak ada tangan yang terdeteksi.",
                    )
                center_frame = (len(frames) - 1) / 2
                representative_index = min(
                    range(len(valid_frame_indices)),
                    key=lambda index: abs(valid_frame_indices[index] - center_frame),
                )
                probabilities = estimator.predict_proba(
                    frame_features[representative_index].reshape(1, -1)
                )[0]

        estimator_classes = tuple(str(label) for label in estimator.classes_)
        response = prediction_from_probabilities(
            category=category,
            probabilities=probabilities,
            estimator_classes=estimator_classes,
            confidence_threshold=float(artifact["confidence_threshold"]),
            frame_count=len(frames),
            detected_frame_count=len(frame_features),
        )
        if response["status"] == "not_recognized":
            response["reason"] = (
                "Confidence video di bawah ambang model. "
                "Coba ulang dengan tangan terlihat jelas."
            )
        return response

    def predict_frame(
        self,
        category: str,
        uid: str,
        session_id: str,
        frame_bytes: bytes,
    ) -> dict[str, Any]:
        if category not in CATEGORY_MODELS:
            raise ValueError(f"Kategori tidak didukung: {category}.")
        if not frame_bytes or len(frame_bytes) > MAX_FRAME_BYTES:
            raise InvalidVideoError("Ukuran frame maksimal 5 MB.")

        encoded = np.frombuffer(frame_bytes, dtype=np.uint8)
        bgr_frame = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
        if bgr_frame is None:
            raise InvalidVideoError("Frame JPEG tidak valid.")
        height, width = bgr_frame.shape[:2]
        if width < 32 or height < 32 or width * height > 16_000_000:
            raise InvalidVideoError("Resolusi frame tidak didukung.")
        rgb_frame = cv2.cvtColor(bgr_frame, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb_frame)
        with self._landmarker_lock:
            result = self._landmarker.detect(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            )
            feature, detected_hands = image_to_features(image, result)
            hands = [
                [
                    {"x": float(point.x), "y": float(point.y)}
                    for point in landmarks
                ]
                for landmarks in result.hand_landmarks[:2]
            ]

        now = time.monotonic()
        session_key = (uid, session_id)
        with self._live_sessions_lock:
            self._prune_live_sessions(now)
            state = self._live_sessions.setdefault(
                session_key,
                {
                    "category": category,
                    "frames": [],
                    "last_seen": now,
                    "frame_count": 0,
                },
            )
            if state["category"] != category:
                state.update(
                    {
                        "category": category,
                        "frames": [],
                        "frame_count": 0,
                    }
                )
            state["last_seen"] = now
            state["frame_count"] += 1
            state["frames"].append(
                (feature.copy() if detected_hands else None, detected_hands)
            )
            del state["frames"][:-LIVE_HISTORY_FRAMES]
            recent = tuple(state["frames"])
            frame_count = state["frame_count"]

        artifact = self._models[category]
        if not detected_hands:
            return self._not_recognized(
                category,
                artifact,
                frame_count,
                0,
                "Tangan tidak terdeteksi. Pastikan tangan terlihat jelas.",
                hands=hands,
            )

        if category == "vocabulary":
            valid_frames = [
                (frame, count)
                for frame, count in recent
                if frame is not None and count > 0
            ]
            if len(valid_frames) < MIN_VALID_FRAMES:
                return self._not_recognized(
                    category,
                    artifact,
                    frame_count,
                    len(valid_frames),
                    "Mengumpulkan gerakan kosakata; tahan isyarat sebentar.",
                    hands=hands,
                )
            aggregate = aggregate_video_features(
                [frame for frame, _ in valid_frames],
                list(range(len(recent))),
                [count for _, count in valid_frames],
            )
            feature_batch = aggregate.reshape(1, -1)
            sampled_frame_count = len(recent)
            detected_frame_count = len(valid_frames)
        else:
            feature_batch = feature.reshape(1, -1)
            sampled_frame_count = 1
            detected_frame_count = 1

        probabilities = artifact["estimator"].predict_proba(feature_batch)[0]
        estimator_classes = tuple(
            str(label) for label in artifact["estimator"].classes_
        )
        response = prediction_from_probabilities(
            category=category,
            probabilities=probabilities,
            estimator_classes=estimator_classes,
            confidence_threshold=float(artifact["confidence_threshold"]),
            frame_count=sampled_frame_count,
            detected_frame_count=detected_frame_count,
        )
        response["hands"] = hands
        response["sequence"] = frame_count
        if response["status"] == "not_recognized":
            response["reason"] = "Confidence di bawah ambang model."
        return response

    def clear_live_session(self, uid: str, session_id: str) -> None:
        with self._live_sessions_lock:
            self._live_sessions.pop((uid, session_id), None)

    def _prune_live_sessions(self, now: float) -> None:
        expired = [
            session_key
            for session_key, state in self._live_sessions.items()
            if now - state["last_seen"] > LIVE_SESSION_TTL_SECONDS
        ]
        for session_key in expired:
            del self._live_sessions[session_key]
        while len(self._live_sessions) >= 1000:
            oldest = min(
                self._live_sessions,
                key=lambda session_key: self._live_sessions[session_key]["last_seen"],
            )
            del self._live_sessions[oldest]

    @staticmethod
    def _not_recognized(
        category: str,
        artifact: dict[str, Any],
        frame_count: int,
        detected_frame_count: int,
        reason: str,
        hands: list[list[dict[str, float]]] | None = None,
    ) -> dict[str, Any]:
        return {
            "category": category,
            "status": "not_recognized",
            "label": None,
            "candidate": None,
            "confidence": 0.0,
            "threshold": float(artifact["confidence_threshold"]),
            "reason": reason,
            "model": category,
            "sampled_frames": frame_count,
            "detected_frames": detected_frame_count,
            "hands": hands or [],
            "sequence": frame_count,
        }
