from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from sklearn.metrics import accuracy_score, f1_score

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.classifier_training import (  # noqa: E402
    RANDOM_STATE,
    make_candidates,
    train_and_evaluate,
)
from app.alphabet_pipeline import write_json  # noqa: E402

DEFAULT_VOCAB_FEATURES = SERVER_ROOT / "processed" / "vocabulary_landmarks.npz"
DEFAULT_MODEL_DIR = SERVER_ROOT / "trained_models" / "vocabulary"
LABELS = (
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Latih dan evaluasi model video vocabulary BISINDO Gestura."
    )
    parser.add_argument("--features", type=Path, default=DEFAULT_VOCAB_FEATURES)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_MODEL_DIR)
    parser.add_argument("--trees", type=int, default=300)
    parser.add_argument("--confidence-target", type=float, default=0.90)
    parser.add_argument("--minimum-coverage", type=float, default=0.10)
    return parser.parse_args()


def evaluate_leave_one_signer_out(
    X: np.ndarray,
    y: np.ndarray,
    groups: np.ndarray,
    labels: tuple[str, ...],
    tree_count: int,
) -> dict[str, object]:
    held_out_signers = ("signer1", "signer2", "signer3", "signer4")
    report: dict[str, object] = {
        "strategy": (
            "Leave-one-signer-out over signers1-4; signer0 is train-only because "
            "it has no samples for gloss labels 12-31"
        ),
        "random_state": RANDOM_STATE,
        "models": {},
    }

    for model_name in ("random_forest", "rbf_svm"):
        fold_results: dict[str, dict[str, float | int]] = {}
        pooled_actual: list[np.ndarray] = []
        pooled_predictions: list[np.ndarray] = []
        for held_out in held_out_signers:
            test_mask = groups == held_out
            train_mask = ~test_mask
            if not np.any(test_mask):
                raise ValueError(f"Tidak ada data vocabulary untuk {held_out}.")
            estimator = make_candidates(tree_count)[model_name]
            estimator.fit(X[train_mask], y[train_mask])
            predictions = estimator.predict(X[test_mask])
            fold_results[held_out] = {
                "samples": int(test_mask.sum()),
                "accuracy": float(accuracy_score(y[test_mask], predictions)),
                "macro_f1": float(
                    f1_score(
                        y[test_mask],
                        predictions,
                        labels=labels,
                        average="macro",
                        zero_division=0,
                    )
                ),
            }
            pooled_actual.append(y[test_mask])
            pooled_predictions.append(predictions)

        all_actual = np.concatenate(pooled_actual)
        all_predictions = np.concatenate(pooled_predictions)
        report["models"][model_name] = {
            "per_signer": fold_results,
            "pooled_samples": len(all_actual),
            "pooled_accuracy": float(accuracy_score(all_actual, all_predictions)),
            "pooled_macro_f1": float(
                f1_score(
                    all_actual,
                    all_predictions,
                    labels=labels,
                    average="macro",
                    zero_division=0,
                )
            ),
        }

    return report


def main() -> None:
    args = parse_args()
    feature_path = args.features.resolve()
    if not feature_path.is_file():
        raise FileNotFoundError(
            f"Fitur belum tersedia: {feature_path}. "
            "Jalankan extract_vocabulary_landmarks.py terlebih dahulu."
        )
    with np.load(feature_path, allow_pickle=False) as archive:
        required = {"X", "y", "groups", "paths"}
        missing_fields = required.difference(archive.files)
        if missing_fields:
            raise ValueError(
                f"Arsip vocabulary kehilangan kolom: {sorted(missing_fields)}"
            )
        X = archive["X"].astype(np.float32, copy=False)
        y = archive["y"].astype(str)
        groups = archive["groups"].astype(str)
        paths = archive["paths"].astype(str)
    if X.ndim != 2 or X.shape[1] != 400 or not np.isfinite(X).all():
        raise ValueError(f"Fitur video vocabulary tidak valid: {X.shape}.")
    if not (len(X) == len(y) == len(groups) == len(paths)):
        raise ValueError("Jumlah fitur dan metadata video tidak sama.")
    absent_labels = [label for label in LABELS if label not in set(y)]
    if absent_labels:
        raise ValueError(
            "Training dibatalkan; kelas tidak memiliki fitur: "
            + ", ".join(absent_labels)
        )

    train_signers = {"signer0", "signer1", "signer2"}
    validation_signers = {"signer3"}
    test_signers = {"signer4"}
    available_signers = set(groups)
    if not test_signers <= available_signers or not validation_signers <= available_signers:
        raise ValueError(
            "Dataset harus memiliki signer3 untuk validation dan signer4 untuk test."
        )
    train_index = np.flatnonzero(np.isin(groups, tuple(train_signers)))
    validation_index = np.flatnonzero(np.isin(groups, tuple(validation_signers)))
    test_index = np.flatnonzero(np.isin(groups, tuple(test_signers)))
    unknown_signers = available_signers - train_signers - validation_signers - test_signers
    if unknown_signers:
        raise ValueError(f"Signer tidak termasuk split yang didefinisikan: {unknown_signers}")

    signer_class_counts = {
        signer: {
            label: int(np.sum((groups == signer) & (y == label)))
            for label in LABELS
        }
        for signer in sorted(available_signers)
    }
    metadata = {
        "labels": list(LABELS),
        "source_dataset": "server/dataset/2_vocabulary",
        "label_mapping": {str(index): label for index, label in enumerate(LABELS)},
        "split_signers": {
            "train": sorted(train_signers),
            "validation": sorted(validation_signers),
            "test": sorted(test_signers),
        },
        "signer_class_counts": signer_class_counts,
        "feature_definition": (
            "12 evenly sampled video frames; per-video mean, standard deviation, "
            "first-to-last landmark delta, and hand-presence ratios"
        ),
        "limitation": (
            "Only signer4 is used for held-out test; report is not a robust estimate "
            "of generalization across a broad population."
        ),
    }
    evaluation = train_and_evaluate(
        category="vocabulary",
        X=X,
        y=y,
        groups=groups,
        paths=paths,
        labels=LABELS,
        train_index=train_index,
        validation_index=validation_index,
        test_index=test_index,
        split_description=(
            "Signer-held-out split: signer0-2 train, signer3 validation, "
            "signer4 test; no signer appears in multiple splits"
        ),
        output_dir=args.output_dir.resolve(),
        feature_archive=feature_path,
        metadata=metadata,
        target_accuracy=args.confidence_target,
        minimum_coverage=args.minimum_coverage,
        tree_count=args.trees,
    )
    print("Mengukur generalisasi dengan leave-one-signer-out (signer1-4)...")
    signer_cv = evaluate_leave_one_signer_out(
        X,
        y,
        groups,
        LABELS,
        args.trees,
    )
    evaluation["signer_cross_validation"] = signer_cv
    write_json(args.output_dir.resolve() / "evaluation.json", evaluation)
    write_json(
        args.output_dir.resolve() / "signer_cross_validation.json",
        signer_cv,
    )
    for model_name, metrics in signer_cv["models"].items():
        print(
            f"LOSO {model_name}: accuracy={metrics['pooled_accuracy']:.4f}; "
            f"macro F1={metrics['pooled_macro_f1']:.4f}"
        )


if __name__ == "__main__":
    main()
