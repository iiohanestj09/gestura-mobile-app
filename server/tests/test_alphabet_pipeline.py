from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np
from PIL import Image

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    FEATURE_SIZE,
    FEATURES_PER_HAND,
    image_to_features,
    predict_feature,
)


def make_hand(offset_x: float) -> list[SimpleNamespace]:
    landmarks = []
    for index in range(21):
        landmarks.append(
            SimpleNamespace(
                x=offset_x + 0.01 * (index % 5),
                y=0.2 + 0.015 * (index // 5),
                z=0.002 * index,
            )
        )
    landmarks[0] = SimpleNamespace(x=offset_x, y=0.2, z=0.0)
    landmarks[9] = SimpleNamespace(x=offset_x + 0.08, y=0.23, z=0.018)
    return landmarks


class FixedEstimator:
    def predict_proba(self, features: np.ndarray) -> np.ndarray:
        probabilities = np.zeros((len(features), 26), dtype=np.float32)
        probabilities[:, 1] = 0.92
        probabilities[:, 0] = 0.08
        return probabilities


class AlphabetPipelineTests(unittest.TestCase):
    def test_feature_shape_and_hand_slots_are_stable(self) -> None:
        image = Image.new("RGB", (640, 640))
        result = SimpleNamespace(
            hand_landmarks=[make_hand(0.7), make_hand(0.1)]
        )

        features, detected_hands = image_to_features(image, result)

        self.assertEqual(features.shape, (FEATURE_SIZE,))
        self.assertEqual(detected_hands, 2)
        self.assertAlmostEqual(float(features[63]), 0.1, places=5)
        self.assertEqual(float(features[65]), 1.0)
        self.assertAlmostEqual(
            float(features[FEATURES_PER_HAND + 63]), 0.7, places=5
        )
        self.assertEqual(float(features[-1]), 1.0)
        self.assertTrue(np.isfinite(features).all())

    def test_missing_hand_is_not_recognized(self) -> None:
        features, detected_hands = image_to_features(
            Image.new("RGB", (640, 640)),
            SimpleNamespace(hand_landmarks=[]),
        )
        result = predict_feature(
            features,
            {
                "estimator": FixedEstimator(),
                "labels": tuple("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
                "confidence_threshold": 0.5,
            },
        )

        self.assertEqual(detected_hands, 0)
        self.assertEqual(result["status"], "not_recognized")
        self.assertIsNone(result["label"])

    def test_low_confidence_returns_not_recognized(self) -> None:
        features, _ = image_to_features(
            Image.new("RGB", (640, 640)),
            SimpleNamespace(hand_landmarks=[make_hand(0.2)]),
        )
        result = predict_feature(
            features,
            {
                "estimator": FixedEstimator(),
                "labels": tuple("ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
                "confidence_threshold": 0.95,
            },
        )

        self.assertEqual(result["status"], "not_recognized")
        self.assertEqual(result["candidate"], "B")
        self.assertIsNone(result["label"])


if __name__ == "__main__":
    unittest.main()
