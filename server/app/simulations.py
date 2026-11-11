from __future__ import annotations

from pathlib import Path

from app.inference import EXPECTED_LABELS

SIMULATION_ROOT = Path(__file__).resolve().parents[1] / "simulation"
_CATEGORY_DIRECTORIES = {
    "alphabet": "1_alphabet",
    "vocabulary": "2_vocabulary",
    "digit": "3_number",
}


def simulation_video_path(
    category: str,
    target: str,
    root: Path = SIMULATION_ROOT,
) -> Path:
    labels = EXPECTED_LABELS.get(category)
    if labels is None or target not in labels:
        raise ValueError("Kategori atau target simulasi tidak dikenal.")

    category_directory = root / _CATEGORY_DIRECTORIES[category]
    if category == "alphabet":
        video_path = category_directory / f"{target.lower()}.mp4"
    elif category == "digit":
        matches = [
            path
            for path in category_directory.glob("*.mp4")
            if path.stem.strip() == target
        ]
        if len(matches) != 1:
            raise FileNotFoundError(
                f"Video simulasi angka {target} tidak ditemukan atau duplikat."
            )
        video_path = matches[0]
    else:
        label_index = labels.index(target)
        video_path = category_directory / f"label {label_index}.mp4"

    if not video_path.is_file():
        raise FileNotFoundError(f"Video simulasi {category}/{target} tidak ditemukan.")
    return video_path
