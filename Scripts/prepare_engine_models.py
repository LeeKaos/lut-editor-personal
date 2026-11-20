#!/usr/bin/env python3
"""Fetch compatible Core ML image models, quantize weights, and stage them for Xcode."""

from __future__ import annotations

import shutil
import tempfile
from pathlib import Path

import coremltools as ct
import gdown


MODELS = {
    "ZeroDCE": "1-0lxlBNFm8E_y9ImhS2wxq0p1ZJlXyoA",
    "MIRNetv2LowLightEnhancement": "1Yh3FCogRfQ8k7Hh_UIZAnGwwhXHX6k6P",
    "GFPGAN": "1-3fF4aPnh8ygUOmKItIrZ318xI9JGmQx",
    "RealESRGAN": "16JEWh48fgQc8az7avROePOd-PYda0Yi2",
}

DESTINATION = Path(__file__).resolve().parents[1] / "LumaGrade" / "EngineModels"


def model_size(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def is_image_feature(feature) -> bool:
    return feature.type.WhichOneof("Type") == "imageType"


def quantize_model(source: Path, name: str, temporary: Path) -> Path:
    model = ct.models.MLModel(str(source), compute_units=ct.ComputeUnit.CPU_ONLY)
    spec = model.get_spec()
    image_inputs = [feature for feature in spec.description.input if is_image_feature(feature)]
    image_outputs = [feature for feature in spec.description.output if is_image_feature(feature)]
    if not image_inputs or not image_outputs:
        raise RuntimeError(f"{name}: expected an image input and image output for Vision processing")

    model_kind = spec.WhichOneof("Type")
    if model_kind == "mlProgram":
        from coremltools.optimize.coreml import (
            OpLinearQuantizerConfig,
            OptimizationConfig,
            linear_quantize_weights,
        )

        config = OptimizationConfig(
            global_config=OpLinearQuantizerConfig(
                mode="linear_symmetric", dtype="int8", granularity="per_channel"
            )
        )
        optimized = linear_quantize_weights(model, config)
        suffix = ".mlpackage"
    elif model_kind and model_kind.startswith("neuralNetwork"):
        from coremltools.models.neural_network.quantization_utils import quantize_weights

        optimized = quantize_weights(model, nbits=8, quantization_mode="linear")
        suffix = ".mlmodel"
    else:
        raise RuntimeError(f"{name}: unsupported Core ML model type {model_kind!r}")

    destination = temporary / f"{name}{suffix}"
    optimized.save(str(destination))
    if not destination.exists():
        raise RuntimeError(f"{name}: quantizer did not create its output")
    return destination


def main() -> None:
    DESTINATION.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lumagrade-coreml-") as temp_dir:
        temporary = Path(temp_dir)
        for name, file_id in MODELS.items():
            downloaded = temporary / f"{name}-source.mlmodel"
            result = gdown.download(id=file_id, output=str(downloaded), quiet=False)
            if not result or not downloaded.is_file() or downloaded.stat().st_size < 1024:
                raise RuntimeError(f"{name}: download failed or returned an invalid model")

            optimized = quantize_model(downloaded, name, temporary)
            final_path = DESTINATION / optimized.name
            if final_path.exists():
                if final_path.is_dir():
                    shutil.rmtree(final_path)
                else:
                    final_path.unlink()
            if optimized.is_dir():
                shutil.copytree(optimized, final_path)
            else:
                shutil.copy2(optimized, final_path)

            before = downloaded.stat().st_size
            after = model_size(final_path)
            savings = max(0.0, (1 - after / before) * 100)
            print(f"{name}: {before / 1_000_000:.1f} MB -> {after / 1_000_000:.1f} MB ({savings:.1f}% smaller)", flush=True)

    expected = {"ZeroDCE", "MIRNetv2LowLightEnhancement", "GFPGAN", "RealESRGAN"}
    present = {path.name.removesuffix(".mlmodel").removesuffix(".mlpackage") for path in DESTINATION.iterdir()}
    missing = expected - present
    if missing:
        raise RuntimeError(f"Missing model outputs: {', '.join(sorted(missing))}")


if __name__ == "__main__":
    main()
