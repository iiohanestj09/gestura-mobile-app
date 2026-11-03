from __future__ import annotations

import argparse
import sys
from collections import Counter, defaultdict
from pathlib import Path

import mediapipe as mp
import numpy as np
from PIL import Image

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    DEFAULT_DATASET,
    DEFAULT_FEATURES,
    IMAGE_EXTENSIONS,
    LABELS,
    create_landmarker_options,
    ensure_landmarker_asset,
    extract_image_features,
    sha256_file,
    write_json,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Ekstrak landmark tangan MediaPipe dari dataset alfabet Gestura."
    )
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_FEATURES)
    parser.add_argument("--model-asset", type=Path)
    parser.add_argument("--limit-per-class", type=int)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    dataset_root = args.dataset.resolve()
    output_path = args.output.resolve()
    model_path = args.model_asset.resolve() if args.model_asset else ensure_landmarker_asset()

    if args.limit_per_class is not None and args.limit_per_class < 1:
        raise ValueError("--limit-per-class harus lebih besar dari 0.")

    files_by_label: dict[str, list[Path]] = {}
    for label in LABELS:
        folder = dataset_root / label
        if not folder.is_dir():
            raise FileNotFoundError(f"Folder kelas {label} tidak ditemukan: {folder}")
        files = sorted(
            path
            for path in folder.iterdir()
            if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
        )
        if args.limit_per_class:
            files = files[: args.limit_per_class]
        if not files:
            raise ValueError(f"Tidak ada gambar untuk kelas {label}: {folder}")
        files_by_label[label] = files

    print(f"Dataset: {dataset_root}")
    print(f"Model landmark: {model_path}")
    print(f"Jumlah gambar sebelum deduplikasi: {sum(map(len, files_by_label.values()))}")

    digest_records: dict[str, list[tuple[str, Path]]] = defaultdict(list)
    for label, paths in files_by_label.items():
        for path in paths:
            digest_records[sha256_file(path)].append((label, path))

    conflicting_duplicates = {
        digest: records
        for digest, records in digest_records.items()
        if len({label for label, _ in records}) > 1
    }
    if conflicting_duplicates:
        examples = [
            f"{records[0][1].name}: {sorted({label for label, _ in records})}"
            for records in list(conflicting_duplicates.values())[:10]
        ]
        raise ValueError(
            "Gambar identik ditemukan pada label berbeda; periksa label sebelum "
            f"training. Contoh: {examples}"
        )

    unique_records = [
        (records[0][0], records[0][1], digest)
        for digest, records in sorted(digest_records.items())
    ]
    duplicate_count = sum(len(records) - 1 for records in digest_records.values())
    print(
        f"Gambar unik: {len(unique_records)}; "
        f"duplikat identik yang dilewati: {duplicate_count}"
    )

    features: list[np.ndarray] = []
    labels: list[str] = []
    groups: list[str] = []
    paths: list[str] = []
    hand_counts: list[int] = []
    no_hand_counts: Counter[str] = Counter()
    no_hand_paths: dict[str, list[str]] = defaultdict(list)
    extraction_errors: list[str] = []

    options = create_landmarker_options(model_path)
    with mp.tasks.vision.HandLandmarker.create_from_options(options) as landmarker:
        for index, (label, path, digest) in enumerate(unique_records, start=1):
            try:
                feature, detected_hands = extract_image_features(path, landmarker)
            except Exception as error:
                extraction_errors.append(f"{path}: {type(error).__name__}: {error}")
                continue
            if detected_hands == 0:
                no_hand_counts[label] += 1
                no_hand_paths[label].append(str(path.resolve()))
                continue
            features.append(feature)
            labels.append(label)
            groups.append(digest)
            paths.append(str(path.resolve()))
            hand_counts.append(detected_hands)

            if index % 100 == 0 or index == len(unique_records):
                print(f"Diproses {index}/{len(unique_records)} gambar unik...")

    if extraction_errors:
        examples = "\n".join(extraction_errors[:10])
        raise RuntimeError(
            f"Ekstraksi gagal pada {len(extraction_errors)} gambar. "
            f"Contoh error:\n{examples}"
        )

    if not features:
        raise RuntimeError("Tidak ada gambar dengan tangan yang berhasil dideteksi.")

    class_counts = Counter(labels)
    missing_classes = [label for label in LABELS if class_counts[label] == 0]
    report_path = output_path.with_name("alphabet_extraction_report.json")
    report = {
        "dataset_root": dataset_root,
        "total_images_found": sum(map(len, files_by_label.values())),
        "unique_images_after_exact_deduplication": len(unique_records),
        "exact_duplicates_skipped": duplicate_count,
        "images_with_detected_hands": len(features),
        "images_without_detected_hands_by_class": no_hand_counts,
        "images_without_detected_hands_paths": no_hand_paths,
        "hand_count_distribution": Counter(hand_counts),
        "usable_images_by_class": class_counts,
        "missing_usable_classes": missing_classes,
        "feature_schema_version": 1,
        "feature_size": len(features[0]),
        "errors": extraction_errors,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    with temporary_path.open("wb") as output_file:
        np.savez_compressed(
            output_file,
            X=np.asarray(features, dtype=np.float32),
            y=np.asarray(labels, dtype=str),
            groups=np.asarray(groups, dtype=str),
            paths=np.asarray(paths, dtype=str),
            hand_counts=np.asarray(hand_counts, dtype=np.int8),
            schema_version=np.asarray([1], dtype=np.int16),
        )
    temporary_path.replace(output_path)
    write_json(report_path, report)

    print(f"Fitur tersimpan: {output_path}")
    print(f"Laporan ekstraksi: {report_path}")
    print(f"Sampel siap training: {len(features)}")
    print(f"Jumlah kelas tanpa sampel: {len(missing_classes)}")
    if missing_classes:
        print(f"PERINGATAN: kelas tanpa tangan terdeteksi: {', '.join(missing_classes)}")


if __name__ == "__main__":
    main()
