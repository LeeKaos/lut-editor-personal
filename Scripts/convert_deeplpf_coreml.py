#!/usr/bin/env python3
"""Convert the upstream DeepLPF checkpoint to a flexible-size Core ML image model."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True, help="Cloned deeplpf-image-enhancement repository")
    parser.add_argument("--output", type=Path, required=True, help="Destination DeepLPF.mlpackage")
    args = parser.parse_args()

    source = args.source.resolve()
    sys.path.insert(0, str(source))
    import model  # noqa: E402 - source repository must be on sys.path first

    checkpoint = source / "pretrained_models/adobe_dpe/deeplpf_psnr_24.180_ssim_0.917_model.pt"
    if not checkpoint.is_file():
        raise FileNotFoundError(f"Upstream checkpoint not found: {checkpoint}")

    torch.set_num_threads(2)
    network = model.DeepLPFNet().cpu().eval()
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    network.load_state_dict(state, strict=True)

    sample = torch.rand(1, 3, 512, 512, dtype=torch.float32)
    with torch.inference_mode():
        traced = torch.jit.trace(network, sample, strict=False, check_trace=False)
        for height, width in ((384, 640), (640, 384)):
            output = traced(torch.rand(1, 3, height, width, dtype=torch.float32))
            if tuple(output.shape) != (1, 3, height, width):
                raise RuntimeError(f"Traced model did not preserve {height}x{width}: {tuple(output.shape)}")

    height = ct.RangeDim(lower_bound=32, upper_bound=2048, default=512, symbol="height")
    width = ct.RangeDim(lower_bound=32, upper_bound=2048, default=512, symbol="width")
    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, height, width),
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.ImageType(name="enhanced", color_layout=ct.colorlayout.RGB)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    converted.author = "DeepLPF authors; Core ML conversion by LumaGrade"
    converted.short_description = "DeepLPF local-parametric photo enhancement"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        import shutil

        shutil.rmtree(args.output)
    converted.save(str(args.output))

    # Validate the saved package at two aspect ratios through Core ML itself.
    runtime_model = ct.models.MLModel(str(args.output), compute_units=ct.ComputeUnit.CPU_ONLY)
    for test_height, test_width in ((512, 512), (384, 640)):
        pixels = np.full((test_height, test_width, 3), 96, dtype=np.uint8)
        result = runtime_model.predict({"image": Image.fromarray(pixels, mode="RGB")})["enhanced"]
        if not isinstance(result, Image.Image) or result.size != (test_width, test_height):
            raise RuntimeError(f"Core ML output shape mismatch for {test_width}x{test_height}: {getattr(result, 'size', None)}")
        print(f"DeepLPF Core ML inference passed: {test_width}x{test_height} -> {result.size[0]}x{result.size[1]}", flush=True)

    package_bytes = sum(path.stat().st_size for path in args.output.rglob("*") if path.is_file())
    print(f"DeepLPF.mlpackage: {package_bytes / 1_000_000:.2f} MB", flush=True)


if __name__ == "__main__":
    main()
