from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import mediapipe as mp
import numpy as np
from PIL import Image

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    IMAGE_EXTENSIONS,
    create_landmarker_options,
    ensure_landmarker_asset,
    extract_image_features,
    sha256_file,
    write_json,
)

DEFAULT_DATASET = SERVER_ROOT / "dataset" / "3_digit"
DEFAULT_OUTPUT = SERVER_ROOT / "processed" / "digit_landmarks.npz"
LABELS = tuple(str(number) for number in range(1, 10))
PERSON_PATTERN = re.compile(r"^P(?P<person>\d+)_(?P<label>[1-9])_(?P<sample>\d+)$")
SIGN_PATTERN = re.compile(r"^Sign (?P<label>[1-9]) \((?P<sample>\d+)\)$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ekstrak landmark MediaPipe untuk dataset angka Gestura."
    )
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--model-asset", type=Path)
    parser.add_argument("--limit-per-class", type=int)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    dataset_root = args.dataset.resolve()
    output_path = args.output.resolve()
    model_path = (
        args.model_asset.resolve()
        if args.model_asset
        else ensure_landmarker_asset()
    )
    if args.limit_per_class is not None and args.limit_per_class < 1:
        raise ValueError("--limit-per-class harus lebih besar dari 0.")

    files_by_label: dict[str, list[Path]] = {}
    for label in LABELS:
        folder = dataset_root / label
        if not folder.is_dir():
            raise FileNotFoundError(f"Folder kelas angka {label} tidak ditemukan.")
        files = sorted(
            path
            for path in folder.iterdir()
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        )
        if args.limit_per_class:
            files = files[: args.limit_per_class]
        if not files:
            raise ValueError(f"Tidak ada gambar untuk kelas angka {label}.")
        files_by_label[label] = files

    digest_records: dict[str, list[tuple[str, Path]]] = defaultdict(list)
    for label, paths in files_by_label.items():
        for path in paths:
            digest_records[sha256_file(path)].append((label, path))

    cross_class_duplicates = [
        records
        for records in digest_records.values()
        if len({label for label, _ in records}) > 1
    ]
    if cross_class_duplicates:
        examples = [
            f"{records[0][1].name}: {sorted({label for label, _ in records})}"
            for records in cross_class_duplicates[:10]
        ]
        raise ValueError(
            "Gambar identik ditemukan pada kelas digit berbeda. Contoh: "
            + "; ".join(examples)
        )

    records: list[tuple[str, Path, str, str]] = []
    for digest, found in sorted(digest_records.items()):
        label, path = found[0]
        person_match = PERSON_PATTERN.fullmatch(path.stem)
        sign_match = SIGN_PATTERN.fullmatch(path.stem)
        if person_match:
            if person_match.group("label") != label:
                raise ValueError(f"Label filename tidak sesuai folder: {path}")
            group = f"P{person_match.group('person')}"
        elif sign_match:
            if sign_match.group("label") != label:
                raise ValueError(f"Label filename tidak sesuai folder: {path}")
            group = "sign_source"
        else:
            raise ValueError(
                f"Nama file tidak menyatakan sumber/demonstrator yang dikenal: {path}"
            )
        records.append((label, path, digest, group))
    duplicate_count = sum(len(found) - 1 for found in digest_records.values())
    print(
        f"Dataset: {dataset_root}; gambar={sum(map(len, files_by_label.values()))}; "
        f"unik={len(records)}; duplikat identik dilewati={duplicate_count}"
    )

    features: list[np.ndarray] = []
    labels: list[str] = []
    groups: list[str] = []
    source_groups: list[str] = []
    paths: list[str] = []
    hand_counts: list[int] = []
    no_hand_counts: Counter[str] = Counter()
    no_hand_paths: dict[str, list[str]] = defaultdict(list)
    errors: list[str] = []

    with mp.tasks.vision.HandLandmarker.create_from_options(
        create_landmarker_options(model_path)
    ) as landmarker:
        for index, (label, path, digest, source_group) in enumerate(records, start=1):
            try:
                feature, detected_hands = extract_image_features(path, landmarker)
            except Exception as error:
                errors.append(f"{path}: {type(error).__name__}: {error}")
                continue
            if not detected_hands:
                no_hand_counts[label] += 1
                no_hand_paths[label].append(str(path.resolve()))
                continue
            features.append(feature)
            labels.append(label)
            groups.append(digest)
            source_groups.append(source_group)
            paths.append(str(path.resolve()))
            hand_counts.append(detected_hands)
            if index % 250 == 0 or index == len(records):
                print(f"Diproses {index}/{len(records)} gambar...")

    if errors:
        raise RuntimeError(
            f"{len(errors)} gambar gagal diproses. Contoh: " + "\n".join(errors[:10])
        )
    if not features:
        raise RuntimeError("Tidak ada landmark yang berhasil diekstrak.")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    with temporary_path.open("wb") as file:
        np.savez_compressed(
            file,
            X=np.asarray(features, dtype=np.float32),
            y=np.asarray(labels, dtype=str),
            groups=np.asarray(source_groups, dtype=str),
            content_hashes=np.asarray(groups, dtype=str),
            paths=np.asarray(paths, dtype=str),
            hand_counts=np.asarray(hand_counts, dtype=np.int8),
            schema_version=np.asarray([1], dtype=np.int16),
        )
    temporary_path.replace(output_path)

    report = {
        "category": "digit",
        "dataset_root": dataset_root,
        "total_images_found": sum(map(len, files_by_label.values())),
        "unique_images_after_exact_deduplication": len(records),
        "exact_duplicates_skipped": duplicate_count,
        "images_with_detected_hands": len(features),
        "images_without_detected_hands_by_class": no_hand_counts,
        "images_without_detected_hands_paths": no_hand_paths,
        "usable_images_by_class": Counter(labels),
        "usable_images_by_source_group": Counter(source_groups),
        "usable_images_by_source_group_and_class": {
            source: Counter(
                label
                for current_source, label in zip(source_groups, labels)
                if current_source == source
            )
            for source in sorted(set(source_groups))
        },
        "missing_usable_classes": [label for label in LABELS if label not in labels],
        "feature_schema_version": 1,
        "feature_size": len(features[0]),
    }
    write_json(
        output_path.with_name("digit_extraction_report.json"),
        report,
    )
    print(f"Fitur tersimpan: {output_path}")
    print(f"Sampel siap training: {len(features)}; kelas: {Counter(labels)}")


if __name__ == "__main__":
    main()
