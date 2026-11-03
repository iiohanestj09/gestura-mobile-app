from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.classifier_training import choose_confidence_threshold  # noqa: E402
from app.video_features import (  # noqa: E402
    VOCABULARY_FEATURE_SIZE,
    aggregate_video_features,
)


class VocabularyFeatureTests(unittest.TestCase):
    def test_temporal_features_have_expected_shape_and_capture_motion(self) -> None:
        first = np.zeros(132, dtype=np.float32)
        first[0] = 0.25
        first[65] = 1.0
        last = first.copy()
        last[0] = 0.75
        result = aggregate_video_features(
            [first, last],
            [0, 10, 20],
            [1, 1],
        )

        self.assertEqual(result.shape, (VOCABULARY_FEATURE_SIZE,))
        self.assertAlmostEqual(float(result[0]), 0.5)
        self.assertGreater(float(result[132]), 0.0)
        self.assertAlmostEqual(float(result[264]), 0.5)
        self.assertAlmostEqual(float(result[-4]), 2 / 3)
        self.assertAlmostEqual(float(result[-1]), 1.0)
        self.assertTrue(np.isfinite(result).all())

    def test_invalid_hand_count_metadata_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            aggregate_video_features(
                [np.zeros(132, dtype=np.float32)],
                [0],
                [],
            )

    def test_confidence_calibration_respects_estimator_class_order(self) -> None:
        estimator_classes = ("Apa", "Air")
        probabilities = np.asarray([[0.95, 0.05], [0.05, 0.95]])
        true_labels = np.asarray(["Apa", "Air"])

        threshold, metrics = choose_confidence_threshold(
            probabilities,
            true_labels,
            estimator_classes,
            target_accuracy=1.0,
            minimum_coverage=0.5,
        )

        self.assertLessEqual(threshold, 0.95)
        self.assertEqual(metrics["validation_selective_accuracy"], 1.0)
        self.assertEqual(metrics["validation_coverage"], 1.0)


if __name__ == "__main__":
    unittest.main()
