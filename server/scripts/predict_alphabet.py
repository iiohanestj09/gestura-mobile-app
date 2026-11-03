from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import mediapipe as mp

SERVER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_ROOT))

from app.alphabet_pipeline import (  # noqa: E402
    DEFAULT_MODEL,
    LANDMARKER_ASSET,
    create_landmarker_options,
    ensure_landmarker_asset,
    extract_image_features,
    load_model_artifact,
    predict_feature,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prediksi satu gambar alfabet menggunakan model Gestura."
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--landmarker-asset", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    image_path = args.input.resolve()
    if not image_path.is_file():
        raise FileNotFoundError(f"Gambar input tidak ditemukan: {image_path}")
    model_asset = (
        args.landmarker_asset.resolve()
        if args.landmarker_asset
        else ensure_landmarker_asset(LANDMARKER_ASSET)
    )
    artifact = load_model_artifact(args.model.resolve())
    options = create_landmarker_options(model_asset)
    with mp.tasks.vision.HandLandmarker.create_from_options(options) as landmarker:
        feature, detected_hands = extract_image_features(image_path, landmarker)
    result = predict_feature(feature, artifact)
    result["detected_hands"] = detected_hands
    result["input"] = str(image_path)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
