from __future__ import annotations

import sys
import unittest
from pathlib import Path

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.inference import EXPECTED_LABELS  # noqa: E402
from app.simulations import simulation_video_path  # noqa: E402


class SimulationVideoTests(unittest.TestCase):
    def test_every_app_target_has_a_simulation_video(self) -> None:
        total_videos = 0
        for category, labels in EXPECTED_LABELS.items():
            for target in labels:
                with self.subTest(category=category, target=target):
                    path = simulation_video_path(category, target)
                    self.assertTrue(path.is_file())
                    self.assertEqual(path.suffix, ".mp4")
                    total_videos += 1
        self.assertEqual(total_videos, 67)

    def test_digit_video_names_are_matched_after_trimming(self) -> None:
        for target in ("8", "9"):
            with self.subTest(target=target):
                path = simulation_video_path("digit", target)
                self.assertEqual(path.stem.strip(), target)

    def test_unknown_category_and_target_are_rejected(self) -> None:
        with self.assertRaises(ValueError):
            simulation_video_path("unknown", "A")
        with self.assertRaises(ValueError):
            simulation_video_path("alphabet", "../a")


if __name__ == "__main__":
    unittest.main()
