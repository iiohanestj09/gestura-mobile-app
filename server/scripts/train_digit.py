from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.classifier_training import RANDOM_STATE, train_and_evaluate  # noqa: E402
from app.alphabet_pipeline import load_feature_dataset  # noqa: E402

LABELS = tuple(str(number) for number in range(1, 10))
DEFAULT_DIGIT_FEATURES = SERVER_ROOT / "processed" / "digit_landmarks.npz"
DEFAULT_MODEL_DIR = SERVER_ROOT / "trained_models" / "digit"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Latih dan evaluasi classifier angka 1-9 Gestura."
    )
    parser.add_argument("--features", type=Path, default=DEFAULT_DIGIT_FEATURES)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--trees", type=int, default=300)
    parser.add_argument("--confidence-target", type=float, default=0.90)
    parser.add_argument("--minimum-coverage", type=float, default=0.10)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    feature_path = args.features.resolve()
    dataset = load_feature_dataset(feature_path)
    X = dataset["X"].astype(np.float32, copy=False)
    y = dataset["y"].astype(str)
    groups = dataset["groups"].astype(str)
    paths = dataset["paths"].astype(str)
    missing = [label for label in LABELS if label not in set(y)]
    if missing:
        raise ValueError(
            "Training angka dibatalkan; kelas tidak memiliki landmark: "
            + ", ".join(missing)
        )

    train_groups = {f"P{number}" for number in range(1, 9)}
    validation_groups = {"P9"}
    test_groups = {"P10", "sign_source"}
    available_groups = set(groups)
    expected_groups = train_groups | validation_groups | test_groups
    if not expected_groups <= available_groups:
        missing_groups = expected_groups - available_groups
        raise ValueError(
            "Dataset digit tidak memiliki grup sumber yang diharapkan: "
            + ", ".join(sorted(missing_groups))
        )
    train_index = np.flatnonzero(np.isin(groups, tuple(train_groups)))
    validation_index = np.flatnonzero(np.isin(groups, tuple(validation_groups)))
    test_index = np.flatnonzero(np.isin(groups, tuple(test_groups)))
    metadata = {
        "labels": list(LABELS),
        "source_dataset": "server/dataset/3_digit",
        "dataset_classes_available": list(LABELS),
        "missing_expected_class": "0",
        "source_groups": {
            "train": sorted(train_groups),
            "validation": sorted(validation_groups),
            "test": sorted(test_groups),
        },
        "class_semantics": "statis, angka satu sampai sembilan",
    }
    train_and_evaluate(
        category="digit",
        X=X,
        y=y,
        groups=groups,
        paths=paths,
        labels=LABELS,
        train_index=train_index,
        validation_index=validation_index,
        test_index=test_index,
        split_description=(
            "Hold out by filename source: P1-P8 train, P9 validation, "
            "P10 and sign_source test; SHA-256 duplicates removed before split"
        ),
        output_dir=args.output_dir.resolve(),
        feature_archive=feature_path,
        metadata=metadata,
        target_accuracy=args.confidence_target,
        minimum_coverage=args.minimum_coverage,
        tree_count=args.trees,
    )


if __name__ == "__main__":
    main()
