from __future__ import annotations

import argparse
import hashlib
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from random import Random

import cv2
import mediapipe as mp
import numpy as np
from PIL import Image

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    create_landmarker_options,
    ensure_landmarker_asset,
    image_to_features,
    write_json,
)
from app.video_features import (  # noqa: E402
    VOCABULARY_FEATURE_SIZE,
    aggregate_video_features,
)

DEFAULT_DATASET = SERVER_ROOT / "dataset" / "2_vocabulary"
DEFAULT_OUTPUT = SERVER_ROOT / "processed" / "vocabulary_landmarks.npz"
LABELS_BY_ID = (
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
)
LABELS = LABELS_BY_ID
VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
SAMPLES_PER_VIDEO = 12
MIN_VALID_FRAMES = 3
FILENAME_PATTERN = re.compile(
    r"^signer(?P<signer>\d+)_label(?P<label>\d+)_sample(?P<sample>\d+)$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ekstrak fitur temporal landmark dari video vocabulary Gestura."
    )
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--model-asset", type=Path)
    parser.add_argument("--frames-per-video", type=int, default=SAMPLES_PER_VIDEO)
    parser.add_argument("--limit-per-class", type=int)
    return parser.parse_args()


def extract_video(
    path: Path,
    landmarker: Any,
    samples_per_video: int,
    timestamp_offset_ms: int,
) -> tuple[np.ndarray | None, dict[str, Any]]:
    capture = cv2.VideoCapture(str(path))
    if not capture.isOpened():
        capture.release()
        raise RuntimeError(f"Video tidak dapat dibuka: {path}")
    try:
        reported_frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = float(capture.get(cv2.CAP_PROP_FPS))
        if not np.isfinite(fps) or fps <= 0:
            raise ValueError(f"FPS video tidak valid ({fps}): {path}")

        seed = int.from_bytes(
            hashlib.sha256(str(path.resolve()).encode("utf-8")).digest()[:8],
            byteorder="big",
        )
        rng = Random(seed)
        sampled_frames: list[tuple[int, np.ndarray]] = []
        frame_count = 0
        while True:
            ok, frame = capture.read()
            if not ok:
                break
            if frame_count < samples_per_video:
                sampled_frames.append((frame_count, frame.copy()))
            else:
                replacement_index = rng.randrange(frame_count + 1)
                if replacement_index < samples_per_video:
                    sampled_frames[replacement_index] = (frame_count, frame.copy())
            frame_count += 1
        if frame_count < 1:
            raise ValueError(f"Video tidak memiliki frame yang dapat dibaca: {path}")

        sampled_frames.sort(key=lambda item: item[0])
        frame_features: list[np.ndarray] = []
        hand_counts: list[int] = []
        last_timestamp_ms = timestamp_offset_ms - 1
        for frame_index, frame in sampled_frames:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            timestamp_ms = max(
                timestamp_offset_ms + int(frame_index * 1000 / fps),
                last_timestamp_ms + 1,
            )
            last_timestamp_ms = timestamp_ms
            result = landmarker.detect_for_video(
                mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame),
                timestamp_ms,
            )
            features, detected_hands = image_to_features(
                Image.fromarray(rgb_frame),
                result,
            )
            if detected_hands:
                frame_features.append(features)
                hand_counts.append(detected_hands)

        details = {
            "frame_count": frame_count,
            "reported_frame_count": reported_frame_count,
            "fps": fps,
            "duration_seconds": frame_count / fps,
            "next_timestamp_offset_ms": (
                timestamp_offset_ms + int(frame_count * 1000 / fps) + 1
            ),
            "sampled_frame_count": len(sampled_frames),
            "valid_hand_frame_count": len(frame_features),
            "hand_count_distribution": Counter(hand_counts),
        }
        if len(frame_features) < MIN_VALID_FRAMES:
            return None, details
        return (
            aggregate_video_features(
                frame_features,
                [index for index, _ in sampled_frames],
                hand_counts,
            ),
            details,
        )
    finally:
        capture.release()


def main() -> None:
    args = parse_args()
    dataset_root = args.dataset.resolve()
    output_path = args.output.resolve()
    if args.frames_per_video < MIN_VALID_FRAMES:
        raise ValueError(
            f"--frames-per-video minimal {MIN_VALID_FRAMES}."
        )
    if args.limit_per_class is not None and args.limit_per_class < 1:
        raise ValueError("--limit-per-class harus lebih besar dari 0.")
    model_path = (
        args.model_asset.resolve()
        if args.model_asset
        else ensure_landmarker_asset()
    )

    records: list[tuple[int, str, Path]] = []
    for label_id, gloss in enumerate(LABELS_BY_ID):
        folder = dataset_root / f"label{label_id}"
        if not folder.is_dir():
            raise FileNotFoundError(f"Folder label{label_id} tidak ditemukan.")
        videos = sorted(
            path
            for path in folder.iterdir()
            if path.is_file() and path.suffix.lower() in VIDEO_EXTENSIONS
        )
        if args.limit_per_class:
            videos = videos[: args.limit_per_class]
        if not videos:
            raise ValueError(f"Folder label{label_id} tidak memiliki video.")
        for path in videos:
            match = FILENAME_PATTERN.match(path.stem)
            if not match:
                raise ValueError(f"Nama video tidak sesuai format signer/label: {path}")
            if int(match.group("label")) != label_id:
                raise ValueError(
                    f"Nomor label pada nama video tidak cocok dengan folder: {path}"
                )
            records.append((label_id, gloss, path))

    records.sort(key=lambda item: (item[0], item[2].name))
    print(
        f"Dataset: {dataset_root}; jumlah video={len(records)}; "
        f"frame sampel/video={args.frames_per_video}"
    )

    X: list[np.ndarray] = []
    y: list[str] = []
    groups: list[str] = []
    paths: list[str] = []
    label_ids: list[int] = []
    valid_frame_counts: list[int] = []
    skipped_no_hand: dict[str, list[str]] = defaultdict(list)
    video_details: dict[str, dict[str, Any]] = {}
    timestamp_offset_ms = 0
    options = create_landmarker_options(
        model_path,
        running_mode=mp.tasks.vision.RunningMode.VIDEO,
    )
    with mp.tasks.vision.HandLandmarker.create_from_options(options) as landmarker:
        for index, (label_id, gloss, path) in enumerate(records, start=1):
            match = FILENAME_PATTERN.match(path.stem)
            if match is None:
                raise RuntimeError(f"Nama video tidak valid: {path}")
            signer = f"signer{match.group('signer')}"
            try:
                feature, details = extract_video(
                    path,
                    landmarker,
                    args.frames_per_video,
                    timestamp_offset_ms,
                )
            except Exception as error:
                raise RuntimeError(
                    f"Gagal memproses video {path}: {type(error).__name__}: {error}"
                ) from error
            timestamp_offset_ms = details["next_timestamp_offset_ms"]
            video_details[str(path.resolve())] = details
            if feature is None:
                skipped_no_hand[gloss].append(str(path.resolve()))
                continue
            X.append(feature)
            y.append(gloss)
            groups.append(signer)
            paths.append(str(path.resolve()))
            label_ids.append(label_id)
            valid_frame_counts.append(details["valid_hand_frame_count"])
            if index % 50 == 0 or index == len(records):
                print(f"Diproses {index}/{len(records)} video...")

    if not X:
        raise RuntimeError("Tidak ada video dengan landmark yang cukup.")

    usable_counts = Counter(y)
    missing_classes = [gloss for gloss in LABELS if not usable_counts[gloss]]
    if missing_classes and args.limit_per_class is None:
        raise RuntimeError(
            "Kelas vocabulary tanpa video landmark yang cukup: "
            + ", ".join(missing_classes)
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    with temporary_path.open("wb") as file:
        np.savez_compressed(
            file,
            X=np.asarray(X, dtype=np.float32),
            y=np.asarray(y, dtype=str),
            groups=np.asarray(groups, dtype=str),
            paths=np.asarray(paths, dtype=str),
            label_ids=np.asarray(label_ids, dtype=np.int8),
            valid_frame_counts=np.asarray(valid_frame_counts, dtype=np.int8),
            schema_version=np.asarray([1], dtype=np.int16),
        )
    temporary_path.replace(output_path)
    write_json(
        output_path.with_name("vocabulary_extraction_report.json"),
        {
            "category": "vocabulary",
            "dataset_root": dataset_root,
            "total_videos_found": len(records),
            "videos_with_usable_landmarks": len(X),
            "videos_skipped_for_insufficient_landmarks": sum(
                len(items) for items in skipped_no_hand.values()
            ),
            "skipped_videos_by_gloss": skipped_no_hand,
            "usable_videos_by_gloss": usable_counts,
            "missing_usable_glosses": missing_classes,
            "usable_videos_by_signer": Counter(groups),
            "usable_videos_by_signer_and_gloss": {
                signer: Counter(
                    gloss
                    for current_signer, gloss in zip(groups, y)
                    if current_signer == signer
                )
                for signer in sorted(set(groups))
            },
            "frame_sampling": {
                "frames_per_video": args.frames_per_video,
                "minimum_valid_frames": MIN_VALID_FRAMES,
                "feature_size": VOCABULARY_FEATURE_SIZE,
                "features": [
                    "mean normalized landmark positions",
                    "standard deviation across sampled frames",
                    "last-minus-first sampled landmark positions",
                    "valid-frame and hand-presence ratios",
                ],
            },
            "label_mapping": {
                str(index): gloss for index, gloss in enumerate(LABELS_BY_ID)
            },
            "video_details": video_details,
        },
    )
    print(f"Fitur tersimpan: {output_path}")
    print(f"Laporan ekstraksi: {output_path.with_name('vocabulary_extraction_report.json')}")
    print(f"Video siap training: {len(X)}; per signer: {Counter(groups)}")


if __name__ == "__main__":
    main()
