from __future__ import annotations

import csv
import time
from collections import Counter
from importlib.metadata import version
from pathlib import Path
from typing import Any

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
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

from app.alphabet_pipeline import (
    FEATURE_SCHEMA_VERSION,
    FEATURES_PER_HAND,
    sha256_file,
    write_json,
)

RANDOM_STATE = 42


def make_candidates(tree_count: int = 300) -> dict[str, Any]:
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
    probability_labels: tuple[str, ...],
    target_accuracy: float,
    minimum_coverage: float,
) -> tuple[float, dict[str, float | int]]:
    confidence = probabilities.max(axis=1)
    predicted = np.asarray(probability_labels)[probabilities.argmax(axis=1)]
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


def _class_distribution(
    values: np.ndarray,
    labels: tuple[str, ...],
) -> dict[str, int]:
    counts = Counter(values.tolist())
    return {label: int(counts[label]) for label in labels}


def _write_classification_csv(
    path: Path,
    report: dict[str, Any],
    labels: tuple[str, ...],
) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.writer(file)
        writer.writerow(("class", "precision", "recall", "f1_score", "support"))
        for label in labels:
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


def train_and_evaluate(
    *,
    category: str,
    X: np.ndarray,
    y: np.ndarray,
    groups: np.ndarray,
    paths: np.ndarray,
    labels: tuple[str, ...],
    train_index: np.ndarray,
    validation_index: np.ndarray,
    test_index: np.ndarray,
    split_description: str,
    output_dir: Path,
    feature_archive: Path,
    metadata: dict[str, Any],
    target_accuracy: float = 0.90,
    minimum_coverage: float = 0.10,
    tree_count: int = 300,
) -> dict[str, Any]:
    if not 0 < target_accuracy <= 1:
        raise ValueError("target_accuracy harus berada di antara 0 dan 1.")
    if not 0 < minimum_coverage <= 1:
        raise ValueError("minimum_coverage harus berada di antara 0 dan 1.")
    if tree_count < 50:
        raise ValueError("tree_count minimal 50.")
    if X.ndim != 2 or not np.isfinite(X).all():
        raise ValueError("Matriks fitur harus 2D dan berisi nilai finite.")
    if not (len(X) == len(y) == len(groups) == len(paths)):
        raise ValueError("Jumlah baris fitur dan metadata tidak sama.")
    for name, indices in (
        ("train", train_index),
        ("validation", validation_index),
        ("test", test_index),
    ):
        if len(indices) == 0:
            raise ValueError(f"Split {name} kosong.")
        absent = [label for label in labels if label not in set(y[indices])]
        if absent:
            raise ValueError(
                f"Split {name} tidak memiliki semua kelas; "
                f"kelas tanpa sampel: {', '.join(absent)}"
            )

    group_sets = [
        set(groups[indices].tolist())
        for indices in (train_index, validation_index, test_index)
    ]
    if (
        group_sets[0] & group_sets[1]
        or group_sets[0] & group_sets[2]
        or group_sets[1] & group_sets[2]
    ):
        raise ValueError("Grup bocor di antara train, validation, dan test.")

    candidates = make_candidates(tree_count)
    validation_results: dict[str, dict[str, float]] = {}
    fitted_candidates: dict[str, Any] = {}
    for name, estimator in candidates.items():
        print(
            f"Melatih {category}/{name}: train={len(train_index)}, "
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
                    labels=labels,
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
    validation_estimator = fitted_candidates[selected_name]
    threshold, threshold_metrics = choose_confidence_threshold(
        validation_estimator.predict_proba(X[validation_index]),
        y[validation_index],
        tuple(str(label) for label in validation_estimator.classes_),
        target_accuracy,
        minimum_coverage,
    )

    final_train_index = np.concatenate((train_index, validation_index))
    final_estimator = make_candidates(tree_count)[selected_name]
    print(f"Melatih ulang {category}/{selected_name} pada train + validation...")
    final_estimator.fit(X[final_train_index], y[final_train_index])

    test_probabilities = final_estimator.predict_proba(X[test_index])
    probability_labels = np.asarray(final_estimator.classes_, dtype=str)
    test_predictions = probability_labels[test_probabilities.argmax(axis=1)]
    test_confidence = test_probabilities.max(axis=1)
    accepted = test_confidence >= threshold
    report_dict = classification_report(
        y[test_index],
        test_predictions,
        labels=labels,
        output_dict=True,
        zero_division=0,
    )
    confusion = confusion_matrix(y[test_index], test_predictions, labels=labels)
    test_accuracy = float(accuracy_score(y[test_index], test_predictions))
    test_macro_f1 = float(
        f1_score(
            y[test_index],
            test_predictions,
            labels=labels,
            average="macro",
            zero_division=0,
        )
    )
    selective_accuracy = (
        float(np.mean(test_predictions[accepted] == y[test_index][accepted]))
        if accepted.any()
        else 0.0
    )
    test_metrics_by_group: dict[str, dict[str, float | int]] = {}
    for group in sorted(set(groups[test_index].tolist())):
        group_mask = groups[test_index] == group
        group_report = classification_report(
            y[test_index][group_mask],
            test_predictions[group_mask],
            labels=labels,
            output_dict=True,
            zero_division=0,
        )
        test_metrics_by_group[str(group)] = {
            "samples": int(group_mask.sum()),
            "accuracy": float(
                accuracy_score(y[test_index][group_mask], test_predictions[group_mask])
            ),
            "macro_f1": float(group_report["macro avg"]["f1-score"]),
            "coverage": float(accepted[group_mask].mean()),
            "selective_accuracy": (
                float(
                    np.mean(
                        test_predictions[group_mask][accepted[group_mask]]
                        == y[test_index][group_mask][accepted[group_mask]]
                    )
                )
                if accepted[group_mask].any()
                else 0.0
            ),
        }

    output_dir.mkdir(parents=True, exist_ok=True)
    model_path = output_dir / "model.joblib"
    versions = {
        package: version(package)
        for package in ("mediapipe", "numpy", "scikit-learn", "joblib", "Pillow")
    }
    archive_hash = sha256_file(feature_archive)
    artifact = {
        "category": category,
        "estimator": final_estimator,
        "labels": labels,
        "confidence_threshold": threshold,
        "feature_schema_version": FEATURE_SCHEMA_VERSION,
        "feature_size": int(X.shape[1]),
        "features_per_hand": FEATURES_PER_HAND,
        "model_name": selected_name,
        "random_state": RANDOM_STATE,
        "feature_archive_sha256": archive_hash,
        "library_versions": versions,
        "metadata": metadata,
    }
    temporary_model_path = model_path.with_suffix(".joblib.tmp")
    joblib.dump(artifact, temporary_model_path, compress=3)
    temporary_model_path.replace(model_path)

    _write_classification_csv(
        output_dir / "classification_report.csv",
        report_dict,
        labels,
    )
    np.savetxt(
        output_dir / "confusion_matrix.csv",
        confusion,
        delimiter=",",
        fmt="%d",
        header=",".join(labels),
        comments="",
    )
    figure, axis = plt.subplots(figsize=(max(11, len(labels) * 0.45), 10))
    image = axis.imshow(confusion, cmap="Blues", interpolation="nearest")
    figure.colorbar(image, ax=axis, fraction=0.046, pad=0.04)
    axis.set(
        xticks=np.arange(len(labels)),
        yticks=np.arange(len(labels)),
        xticklabels=labels,
        yticklabels=labels,
        xlabel="Prediksi",
        ylabel="Label sebenarnya",
        title=f"Confusion Matrix {category} ({selected_name})",
    )
    plt.setp(axis.get_xticklabels(), rotation=60, ha="right", rotation_mode="anchor")
    figure.tight_layout()
    figure.savefig(output_dir / "confusion_matrix.png", dpi=160)
    plt.close(figure)

    with (output_dir / "test_predictions.csv").open(
        "w", newline="", encoding="utf-8-sig"
    ) as file:
        writer = csv.writer(file)
        writer.writerow(
            ("path", "group", "actual", "predicted_candidate", "confidence", "accepted")
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
                    groups[index],
                    actual,
                    predicted,
                    f"{confidence:.6f}",
                    bool(is_accepted),
                )
            )

    result = {
        "category": category,
        "feature_archive": feature_archive,
        "feature_archive_sha256": archive_hash,
        "model_path": model_path,
        "selected_model": selected_name,
        "validation_model_comparison": validation_results,
        "split": {
            "strategy": split_description,
            "train_samples": len(train_index),
            "validation_samples": len(validation_index),
            "test_samples": len(test_index),
            "train_groups": len(group_sets[0]),
            "validation_groups": len(group_sets[1]),
            "test_groups": len(group_sets[2]),
            "train_class_distribution": _class_distribution(y[train_index], labels),
            "validation_class_distribution": _class_distribution(
                y[validation_index], labels
            ),
            "test_class_distribution": _class_distribution(y[test_index], labels),
            "random_state": RANDOM_STATE,
        },
        "configuration": {
            "random_forest_trees": tree_count,
            "confidence_target_accuracy": target_accuracy,
            "minimum_confidence_coverage": minimum_coverage,
            "feature_schema_version": FEATURE_SCHEMA_VERSION,
            "feature_size": int(X.shape[1]),
            "library_versions": versions,
        },
        "test": {
            "accuracy": test_accuracy,
            "macro_f1": test_macro_f1,
            "macro_precision": report_dict["macro avg"]["precision"],
            "macro_recall": report_dict["macro avg"]["recall"],
            "confidence_threshold": threshold,
            "rejection_threshold_calibration": threshold_metrics,
            "accepted_samples": int(accepted.sum()),
            "coverage": float(accepted.mean()),
            "selective_accuracy": selective_accuracy,
            "class_metrics": {label: report_dict[label] for label in labels},
            "metrics_by_group": test_metrics_by_group,
        },
        "metadata": metadata,
    }
    write_json(output_dir / "evaluation.json", result)

    print(f"Model {category} terpilih: {selected_name}")
    print(
        f"Test accuracy={test_accuracy:.4f}; macro F1={test_macro_f1:.4f}; "
        f"coverage={accepted.mean():.3f}; selective accuracy={selective_accuracy:.4f}"
    )
    print(f"Artefak dan laporan: {output_dir}")
    return result
