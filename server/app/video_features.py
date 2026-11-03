from __future__ import annotations

import numpy as np

from app.alphabet_pipeline import FEATURES_PER_HAND

VOCABULARY_FEATURE_SIZE = FEATURES_PER_HAND * 6 + 4


def aggregate_video_features(
    frame_features: list[np.ndarray],
    frame_indices: list[int],
    hand_counts: list[int],
) -> np.ndarray:
    if (
        not frame_features
        or len(frame_features) != len(hand_counts)
        or len(frame_features) > len(frame_indices)
    ):
        raise ValueError("Data frame vocabulary tidak konsisten.")
    matrix = np.asarray(frame_features, dtype=np.float32)
    if matrix.ndim != 2 or matrix.shape[1] != FEATURES_PER_HAND * 2:
        raise ValueError(f"Ukuran fitur per frame tidak valid: {matrix.shape}.")
    if not np.isfinite(matrix).all():
        raise ValueError("Fitur frame mengandung NaN atau tak hingga.")

    presence = matrix[:, [FEATURES_PER_HAND - 1, 2 * FEATURES_PER_HAND - 1]]
    aggregate = np.concatenate(
        (
            matrix.mean(axis=0),
            matrix.std(axis=0),
            matrix[-1] - matrix[0],
            np.asarray(
                (
                    len(frame_features) / len(frame_indices),
                    float(np.mean(presence[:, 0] > 0)),
                    float(np.mean(presence[:, 1] > 0)),
                    float(np.mean(hand_counts)),
                ),
                dtype=np.float32,
            ),
        )
    )
    if aggregate.shape != (VOCABULARY_FEATURE_SIZE,):
        raise ValueError(f"Ukuran fitur vocabulary tidak valid: {aggregate.shape}.")
    return aggregate
