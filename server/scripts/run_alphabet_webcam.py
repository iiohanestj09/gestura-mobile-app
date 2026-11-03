from __future__ import annotations

import argparse
import sys
import time
from collections import Counter, deque
from pathlib import Path
from typing import Any

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    DEFAULT_MODEL,
    LANDMARKER_ASSET,
    create_landmarker_options,
    ensure_landmarker_asset,
    image_to_features,
    load_model_artifact,
    predict_feature,
)

WINDOW_NAME = "Gestura - Uji Alfabet Webcam"


class PredictionSmoother:
    def __init__(self, window_size: int, required_votes: int) -> None:
        if window_size < 1:
            raise ValueError("window_size harus lebih besar dari 0.")
        if required_votes < 1 or required_votes > window_size:
            raise ValueError("required_votes harus antara 1 dan window_size.")
        self._window: deque[tuple[str | None, float]] = deque(maxlen=window_size)
        self._required_votes = required_votes

    def reset(self) -> None:
        self._window.clear()

    def update(self, result: dict[str, Any]) -> tuple[str | None, float]:
        if result["status"] == "recognized":
            self._window.append((result["candidate"], result["confidence"]))
        else:
            self._window.append((None, 0.0))

        votes = Counter(label for label, _ in self._window if label is not None)
        if not votes:
            return None, 0.0
        label, count = votes.most_common(1)[0]
        if count < self._required_votes:
            return None, 0.0

        confidences = [
            confidence
            for candidate, confidence in self._window
            if candidate == label
        ]
        return label, float(sum(confidences) / len(confidences))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Uji model alfabet Gestura secara lokal menggunakan webcam laptop."
        )
    )
    parser.add_argument("--camera", type=int, default=0, help="Indeks webcam.")
    parser.add_argument("--width", type=int, default=960, help="Lebar frame.")
    parser.add_argument("--height", type=int, default=720, help="Tinggi frame.")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--landmarker-asset", type=Path)
    parser.add_argument(
        "--window-size",
        type=int,
        default=7,
        help="Jumlah frame terakhir untuk stabilisasi prediksi.",
    )
    parser.add_argument(
        "--required-votes",
        type=int,
        default=5,
        help="Jumlah prediksi sama yang diperlukan agar huruf ditampilkan stabil.",
    )
    parser.add_argument(
        "--no-mirror",
        action="store_true",
        help="Jangan membalik frame webcam secara horizontal.",
    )
    return parser.parse_args()


def open_camera(index: int, width: int, height: int) -> cv2.VideoCapture:
    if index < 0:
        raise ValueError("--camera harus berupa indeks nol atau lebih.")
    if width < 1 or height < 1:
        raise ValueError("--width dan --height harus lebih besar dari 0.")

    backends = []
    if hasattr(cv2, "CAP_DSHOW"):
        backends.append(cv2.CAP_DSHOW)
    if hasattr(cv2, "CAP_MSMF"):
        backends.append(cv2.CAP_MSMF)
    backends.append(cv2.CAP_ANY)

    for backend in backends:
        capture = cv2.VideoCapture(index, backend)
        if capture.isOpened():
            capture.set(cv2.CAP_PROP_FRAME_WIDTH, width)
            capture.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
            return capture
        capture.release()

    raise RuntimeError(
        f"Webcam indeks {index} tidak dapat dibuka. Tutup aplikasi lain yang "
        "memakai kamera dan periksa izin Camera di Windows Settings."
    )


def draw_landmarks(
    frame: np.ndarray,
    result: Any,
) -> None:
    height, width = frame.shape[:2]
    for hand in result.hand_landmarks:
        for point in hand:
            center = (int(point.x * width), int(point.y * height))
            cv2.circle(frame, center, 3, (70, 235, 120), -1, cv2.LINE_AA)


def draw_panel(
    frame: np.ndarray,
    result: dict[str, Any],
    stable_label: str | None,
    stable_confidence: float,
    hand_count: int,
    fps: float,
    mirrored: bool,
) -> None:
    panel_height = 142
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (frame.shape[1], panel_height), (18, 22, 30), -1)
    cv2.addWeighted(overlay, 0.82, frame, 0.18, 0, frame)

    if stable_label:
        headline = (
            f"HURUF STABIL: {stable_label}  "
            f"({stable_confidence * 100:.1f}%)"
        )
        color = (90, 245, 130)
    elif result["status"] == "recognized":
        headline = f"Menstabilkan: {result['candidate']} - tahan gesture"
        color = (0, 220, 255)
    elif hand_count == 0:
        headline = "TANGAN TIDAK TERDETEKSI"
        color = (80, 150, 255)
    else:
        headline = (
            f"TIDAK DIKENALI | kandidat {result['candidate']} "
            f"({result['confidence'] * 100:.1f}%)"
        )
        color = (80, 150, 255)

    cv2.putText(
        frame,
        headline,
        (18, 42),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.86,
        color,
        2,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        (
            f"Tangan: {hand_count} | FPS: {fps:.1f} | "
            f"Confidence minimum: {result['threshold'] * 100:.1f}% | "
            f"Mirror: {'ON' if mirrored else 'OFF'}"
        ),
        (18, 78),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (235, 238, 245),
        1,
        cv2.LINE_AA,
    )
    cv2.putText(
        frame,
        "Q: keluar   M: mirror on/off   R: reset stabilisasi",
        (18, 112),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (235, 238, 245),
        1,
        cv2.LINE_AA,
    )


def main() -> None:
    args = parse_args()
    smoother = PredictionSmoother(args.window_size, args.required_votes)
    model_path = args.model.resolve()
    asset_path = (
        args.landmarker_asset.resolve()
        if args.landmarker_asset
        else ensure_landmarker_asset(LANDMARKER_ASSET)
    )
    artifact = load_model_artifact(model_path)
    options = create_landmarker_options(
        asset_path,
        running_mode=mp.tasks.vision.RunningMode.VIDEO,
    )
    capture = open_camera(args.camera, args.width, args.height)
    mirrored = not args.no_mirror
    last_timestamp_ms = 0
    frame_times: deque[float] = deque(maxlen=30)

    print(f"Model: {model_path}")
    print(f"Webcam: indeks {args.camera}")
    print("Tekan Q untuk keluar, M untuk toggle mirror, R untuk reset.")

    try:
        with mp.tasks.vision.HandLandmarker.create_from_options(options) as landmarker:
            cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
            while True:
                ok, camera_frame = capture.read()
                if not ok:
                    raise RuntimeError(
                        "Gagal membaca frame webcam. Coba webcam lain dengan --camera."
                    )

                if mirrored:
                    camera_frame = cv2.flip(camera_frame, 1)
                rgb_frame = cv2.cvtColor(camera_frame, cv2.COLOR_BGR2RGB)
                mp_image = mp.Image(
                    image_format=mp.ImageFormat.SRGB,
                    data=rgb_frame,
                )
                timestamp_ms = max(
                    int(time.monotonic() * 1000),
                    last_timestamp_ms + 1,
                )
                last_timestamp_ms = timestamp_ms
                detection = landmarker.detect_for_video(mp_image, timestamp_ms)

                frame_image = Image.fromarray(rgb_frame)
                features, hand_count = image_to_features(frame_image, detection)
                prediction = predict_feature(features, artifact)
                stable_label, stable_confidence = smoother.update(prediction)

                draw_landmarks(camera_frame, detection)
                now = time.perf_counter()
                frame_times.append(now)
                fps = (
                    (len(frame_times) - 1) / (frame_times[-1] - frame_times[0])
                    if len(frame_times) > 1 and frame_times[-1] > frame_times[0]
                    else 0.0
                )
                draw_panel(
                    camera_frame,
                    prediction,
                    stable_label,
                    stable_confidence,
                    hand_count,
                    fps,
                    mirrored,
                )
                cv2.imshow(WINDOW_NAME, camera_frame)

                key = cv2.waitKey(1) & 0xFF
                if key == ord("q") or key == 27:
                    break
                if key == ord("m"):
                    mirrored = not mirrored
                    smoother.reset()
                if key == ord("r"):
                    smoother.reset()
    finally:
        capture.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
