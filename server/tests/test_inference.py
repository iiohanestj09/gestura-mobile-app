from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.inference import prediction_from_probabilities  # noqa: E402
from app.video_features import aggregate_video_features  # noqa: E402


class InferenceTests(unittest.TestCase):
    def test_prediction_uses_estimator_class_order(self) -> None:
        result = prediction_from_probabilities(
            category="vocabulary",
            probabilities=np.asarray([0.1, 0.9]),
            estimator_classes=("Tuli", "Air"),
            confidence_threshold=0.8,
            frame_count=12,
            detected_frame_count=10,
        )

        self.assertEqual(result["label"], "Air")
        self.assertEqual(result["candidate"], "Air")
        self.assertEqual(result["status"], "recognized")

    def test_low_confidence_is_reported_as_not_recognized(self) -> None:
        result = prediction_from_probabilities(
            category="digit",
            probabilities=np.asarray([0.55, 0.45]),
            estimator_classes=("1", "2"),
            confidence_threshold=0.7,
            frame_count=12,
            detected_frame_count=12,
        )

        self.assertIsNone(result["label"])
        self.assertEqual(result["candidate"], "1")
        self.assertEqual(result["status"], "not_recognized")

    def test_video_aggregation_rejects_mismatched_metadata(self) -> None:
        with self.assertRaises(ValueError):
            aggregate_video_features(
                [np.zeros(132, dtype=np.float32)],
                [0, 1],
                [],
            )


if __name__ == "__main__":
    unittest.main()
