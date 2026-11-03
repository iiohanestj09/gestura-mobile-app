from __future__ import annotations

import argparse
import csv
import sys
import time
from collections import Counter
from importlib.metadata import version
from pathlib import Path

import joblib
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from sklearn.calibration import CalibratedClassifierCV
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    DEFAULT_FEATURES,
    DEFAULT_MODEL,
    FEATURE_SCHEMA_VERSION,
    FEATURES_PER_HAND,
    LABELS,
    load_feature_dataset,
    sha256_file,
    write_json,
)

RANDOM_STATE = 42
SPLIT_COUNT = 5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Bandingkan Random Forest dan SVM lalu evaluasi model alfabet."
    )
    parser.add_argument("--features", type=Path, default=DEFAULT_FEATURES)
    parser.add_argument("--output-model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--confidence-target", type=float, default=0.95)
    parser.add_argument("--minimum-coverage", type=float, default=0.10)
    parser.add_argument("--trees", type=int, default=300)
    return parser.parse_args()


def make_candidates(tree_count: int) -> dict[str, object]:
    return {
        "random_forest": RandomForestClassifier(
            n_estimators=tree_count,
            max_features="sqrt",
            min_samples_leaf=1,
            class_weight="balanced_subsample",
            n_jobs=-1,
            random_state=RANDOM_STATE,
        ),
        "rbf_svm": CalibratedClassifierCV(
            estimator=make_pipeline(
                StandardScaler(),
                SVC(
                    kernel="rbf",
                    C=10.0,
                    gamma="scale",
                    class_weight="balanced",
                    random_state=RANDOM_STATE,
                    cache_size=512,
                ),
            ),
            method="sigmoid",
            cv=3,
            ensemble=False,
        ),
    }


def choose_confidence_threshold(
    probabilities: np.ndarray,
    true_labels: np.ndarray,
    target_accuracy: float,
    minimum_coverage: float,
) -> tuple[float, dict[str, float | int]]:
    confidence = probabilities.max(axis=1)
    predicted = np.asarray(LABELS)[probabilities.argmax(axis=1)]
    candidates = sorted(set(confidence.tolist()))
    eligible: list[tuple[float, float, int]] = []
    for threshold in candidates:
        accepted = confidence >= threshold
        count = int(accepted.sum())
        coverage = count / len(true_labels)
        if count == 0 or coverage < minimum_coverage:
            continue
        selective_accuracy = float(np.mean(predicted[accepted] == true_labels[accepted]))
        if selective_accuracy >= target_accuracy:
            eligible.append((coverage, float(threshold), count))

    if eligible:
        coverage, threshold, count = max(eligible, key=lambda item: item[0])
    else:
        # If validation cannot support the requested accuracy and coverage,
        # reject all predictions rather than invent a confidence threshold.
        threshold = float(np.nextafter(float(confidence.max()), np.inf))
        coverage = 0.0
        count = 0

    accepted = confidence >= threshold
    selective_accuracy = (
        float(np.mean(predicted[accepted] == true_labels[accepted]))
        if accepted.any()
        else 0.0
    )
    return threshold, {
        "validation_coverage": coverage,
        "validation_selective_accuracy": selective_accuracy,
        "validation_accepted_samples": count,
        "target_accuracy": target_accuracy,
        "minimum_coverage": minimum_coverage,
    }


def write_classification_csv(path: Path, report: dict[str, dict[str, float]]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.writer(file)
        writer.writerow(("class", "precision", "recall", "f1_score", "support"))
        for label in LABELS:
            metrics = report[label]
            writer.writerow(
                (
                    label,
                    metrics["precision"],
                    metrics["recall"],
                    metrics["f1-score"],
                    int(metrics["support"]),
                )
            )
        for key in ("macro avg", "weighted avg"):
            metrics = report[key]
            writer.writerow(
                (
                    key,
                    metrics["precision"],
                    metrics["recall"],
                    metrics["f1-score"],
                    int(metrics["support"]),
                )
            )


def main() -> None:
    args = parse_args()
    if not 0 < args.confidence_target <= 1:
        raise ValueError("--confidence-target harus berada di antara 0 dan 1.")
    if not 0 < args.minimum_coverage <= 1:
        raise ValueError("--minimum-coverage harus berada di antara 0 dan 1.")
    if args.trees < 50:
        raise ValueError("--trees minimal 50 untuk model Random Forest.")

    dataset = load_feature_dataset(args.features.resolve())
    X = dataset["X"].astype(np.float32, copy=False)
    y = dataset["y"].astype(str)
    groups = dataset["groups"].astype(str)
    paths = dataset["paths"].astype(str)

    absent_labels = [label for label in LABELS if label not in set(y)]
    if absent_labels:
        raise ValueError(
            "Training dibatalkan; tidak ada sampel landmark untuk kelas: "
            + ", ".join(absent_labels)
        )
    if len(set(groups)) < SPLIT_COUNT:
        raise ValueError("Jumlah grup unik terlalu kecil untuk evaluasi lima fold.")

    splitter = StratifiedGroupKFold(
        n_splits=SPLIT_COUNT,
        shuffle=True,
        random_state=RANDOM_STATE,
    )
    folds = [
        (train_index, test_index)
        for train_index, test_index in splitter.split(X, y, groups)
    ]
    validation_index = folds[1][1]
    test_index = folds[0][1]
    train_index = np.concatenate([folds[index][1] for index in range(2, SPLIT_COUNT)])

    train_groups = set(groups[train_index])
    validation_groups = set(groups[validation_index])
    test_groups = set(groups[test_index])
    if (
        train_groups & validation_groups
        or train_groups & test_groups
        or validation_groups & test_groups
    ):
        raise RuntimeError("Kebocoran grup terdeteksi antara split data.")
    if set(y[test_index]) != set(LABELS):
        raise RuntimeError("Split test tidak memiliki seluruh kelas A-Z.")

    candidates = make_candidates(args.trees)
    validation_results: dict[str, dict[str, float]] = {}
    fitted_candidates: dict[str, object] = {}
    for name, estimator in candidates.items():
        print(
            f"Melatih {name}: train={len(train_index)}, "
            f"validation={len(validation_index)}, test={len(test_index)}"
        )
        start = time.perf_counter()
        estimator.fit(X[train_index], y[train_index])
        predicted = estimator.predict(X[validation_index])
        validation_results[name] = {
            "accuracy": float(accuracy_score(y[validation_index], predicted)),
            "macro_f1": float(
                f1_score(
                    y[validation_index],
                    predicted,
                    labels=LABELS,
                    average="macro",
                    zero_division=0,
                )
            ),
            "seconds": time.perf_counter() - start,
        }
        fitted_candidates[name] = estimator
        print(
            f"{name}: accuracy={validation_results[name]['accuracy']:.4f}, "
            f"macro_f1={validation_results[name]['macro_f1']:.4f}, "
            f"waktu={validation_results[name]['seconds']:.1f}s"
        )

    selected_name = max(
        validation_results,
        key=lambda name: (
            validation_results[name]["macro_f1"],
            validation_results[name]["accuracy"],
        ),
    )
    selected_estimator = fitted_candidates[selected_name]
    validation_probabilities = selected_estimator.predict_proba(X[validation_index])
    confidence_threshold, rejection_metrics = choose_confidence_threshold(
        validation_probabilities,
        y[validation_index],
        args.confidence_target,
        args.minimum_coverage,
    )

    final_train_index = np.concatenate((train_index, validation_index))
    final_estimator = make_candidates(args.trees)[selected_name]
    print(f"Melatih ulang model terpilih ({selected_name}) pada train + validation...")
    final_estimator.fit(X[final_train_index], y[final_train_index])

    test_probabilities = final_estimator.predict_proba(X[test_index])
    test_predictions = np.asarray(LABELS)[test_probabilities.argmax(axis=1)]
    test_confidence = test_probabilities.max(axis=1)
    accepted = test_confidence >= confidence_threshold
    test_accuracy = float(accuracy_score(y[test_index], test_predictions))
    test_macro_f1 = float(
        f1_score(
            y[test_index],
            test_predictions,
            labels=LABELS,
            average="macro",
            zero_division=0,
        )
    )
    accepted_accuracy = (
        float(np.mean(test_predictions[accepted] == y[test_index][accepted]))
        if accepted.any()
        else 0.0
    )
    report_dict = classification_report(
        y[test_index],
        test_predictions,
        labels=LABELS,
        output_dict=True,
        zero_division=0,
    )
    confusion = confusion_matrix(y[test_index], test_predictions, labels=LABELS)

    artifact = {
        "estimator": final_estimator,
        "labels": LABELS,
        "confidence_threshold": confidence_threshold,
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "features_per_hand": FEATURES_PER_HAND,
        "model_name": selected_name,
        "random_state": RANDOM_STATE,
        "feature_archive_sha256": sha256_file(args.features.resolve()),
        "library_versions": {
            package: version(package)
            for package in ("mediapipe", "numpy", "scikit-learn", "joblib", "Pillow")
        },
    }
    model_path = args.output_model.resolve()
    model_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_model_path = model_path.with_suffix(model_path.suffix + ".tmp")
    joblib.dump(artifact, temporary_model_path, compress=3)
    temporary_model_path.replace(model_path)

    report_dir = model_path.parent
    write_classification_csv(report_dir / "classification_report.csv", report_dict)
    np.savetxt(
        report_dir / "confusion_matrix.csv",
        confusion,
        delimiter=",",
        fmt="%d",
        header=",".join(LABELS),
        comments="",
    )
    figure, axis = plt.subplots(figsize=(13, 11))
    image = axis.imshow(confusion, cmap="Blues", interpolation="nearest")
    figure.colorbar(image, ax=axis, fraction=0.046, pad=0.04)
    axis.set(
        xticks=np.arange(len(LABELS)),
        yticks=np.arange(len(LABELS)),
        xticklabels=LABELS,
        yticklabels=LABELS,
        xlabel="Prediksi",
        ylabel="Label sebenarnya",
        title=f"Confusion Matrix Alfabet ({selected_name})",
    )
    plt.setp(axis.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")
    figure.tight_layout()
    figure.savefig(report_dir / "confusion_matrix.png", dpi=160)
    plt.close(figure)

    with (report_dir / "test_predictions.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as file:
        writer = csv.writer(file)
        writer.writerow(
            ("path", "actual", "predicted_candidate", "confidence", "accepted")
        )
        for index, actual, predicted, confidence, is_accepted in zip(
            test_index,
            y[test_index],
            test_predictions,
            test_confidence,
            accepted,
        ):
            writer.writerow(
                (
                    paths[index],
                    actual,
                    predicted,
                    f"{confidence:.6f}",
                    bool(is_accepted),
                )
            )

    evaluation = {
        "dataset": str(args.features.resolve()),
        "feature_archive_sha256": sha256_file(args.features.resolve()),
        "model_path": model_path,
        "selected_model": selected_name,
        "validation_model_comparison": validation_results,
        "split": {
            "strategy": "StratifiedGroupKFold, 5 folds; group=exact image SHA-256",
            "train_samples": len(train_index),
            "validation_samples": len(validation_index),
            "test_samples": len(test_index),
            "train_unique_groups": len(train_groups),
            "validation_unique_groups": len(validation_groups),
            "test_unique_groups": len(test_groups),
            "random_state": RANDOM_STATE,
        },
        "configuration": {
            "random_forest_trees": args.trees,
            "confidence_target_accuracy": args.confidence_target,
            "minimum_confidence_coverage": args.minimum_coverage,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "library_versions": artifact["library_versions"],
        },
        "test": {
            "accuracy": test_accuracy,
            "macro_f1": test_macro_f1,
            "macro_precision": report_dict["macro avg"]["precision"],
            "macro_recall": report_dict["macro avg"]["recall"],
            "confidence_threshold": confidence_threshold,
            "rejection_threshold_calibration": rejection_metrics,
            "accepted_samples": int(accepted.sum()),
            "coverage": float(accepted.mean()),
            "selective_accuracy": accepted_accuracy,
            "class_metrics": {
                label: report_dict[label] for label in LABELS
            },
        },
        "class_distribution": {
            "all": Counter(y),
            "train": Counter(y[train_index]),
            "validation": Counter(y[validation_index]),
            "test": Counter(y[test_index]),
        },
        "limitations": [
            "Split dikelompokkan berdasarkan hash gambar identik, bukan demonstrator "
            "atau sesi karena metadata tersebut tidak tersedia.",
            "Test adalah evaluasi closed-set pada kelas A-Z yang diketahui. Ambang "
            "confidence belum membuktikan penolakan gesture non-alfabet atau bentuk "
            "gesture di luar dataset; diperlukan sampel negatif untuk validasi itu.",
            "Hasil hanya berlaku pada domain dataset alfabet yang diberikan; "
            "kesesuaian konvensi BISINDO perlu diverifikasi oleh pengajar/penutur.",
            "J dan Z biasanya memerlukan gerakan; model ini hanya mengenali pose "
            "statis yang terdapat pada gambar.",
            "Ambang confidence adalah kalibrasi awal dari validation, bukan jaminan "
            "untuk kamera dan pengguna baru.",
        ],
    }
    write_json(report_dir / "evaluation.json", evaluation)

    print(f"Model terpilih: {selected_name}")
    print(f"Test accuracy: {test_accuracy:.4f}")
    print(f"Test macro F1: {test_macro_f1:.4f}")
    print(
        f"Test coverage (threshold={confidence_threshold:.4f}): "
        f"{accepted.mean():.3f}; selective accuracy={accepted_accuracy:.4f}"
    )
    print(f"Artefak dan laporan tersimpan di: {report_dir}")


if __name__ == "__main__":
    main()
