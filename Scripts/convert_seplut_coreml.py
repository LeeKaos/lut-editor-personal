#!/usr/bin/env python3
"""Convert the official SepLUT FiveK-sRGB checkpoint into a compact Core ML LUT generator."""

from __future__ import annotations

import argparse
import shutil
import urllib.request
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image


SOURCE_REVISION = "49d8bc3f42c5dfc09140786d0da1e47e3adb0619"
CHECKPOINT_URL = (
    "https://raw.githubusercontent.com/ImCharlesY/SepLUT/"
    f"{SOURCE_REVISION}/pretrained/SepLUT-FiveK-sRGB-M8%233D17%231D17.pth"
)
N_VERTICES = 17
N_RANKS = 3
INPUT_SIZE = 256


class BasicBlock(nn.Sequential):
    def __init__(self, in_channels: int, out_channels: int, stride: int, norm: bool):
        layers: list[nn.Module] = [
            nn.Conv2d(in_channels, out_channels, kernel_size=3, stride=stride, padding=1),
            nn.LeakyReLU(0.2),
        ]
        if norm:
            layers.append(nn.InstanceNorm2d(out_channels, affine=True))
        super().__init__(*layers)


class LightBackbone(nn.Sequential):
    """SepLUT's official 5-layer light backbone, with matching checkpoint keys."""

    def __init__(self) -> None:
        blocks: list[nn.Module] = [BasicBlock(3, 8, stride=2, norm=True)]
        channels = 8
        for _ in range(3):
            blocks.append(BasicBlock(channels, channels * 2, stride=2, norm=True))
            channels *= 2
        blocks.extend([BasicBlock(channels, channels, stride=2, norm=False), nn.Dropout(p=0.5), nn.AdaptiveAvgPool2d(2)])
        super().__init__(*blocks)
        self.out_channels = channels * 4

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        # SepLUT's LightBackbone resizes all inputs to 256x256 before this stack.
        return super().forward(image).flatten(1)


class LUT1DGenerator(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.lut1d_generator = nn.Linear(256, 3 * N_VERTICES)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        return self.lut1d_generator(features).view(features.shape[0], 3, N_VERTICES).sigmoid()


class LUT3DGenerator(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.weights_generator = nn.Linear(256, N_RANKS)
        self.basis_luts_bank = nn.Linear(N_RANKS, 3 * N_VERTICES**3, bias=False)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        weights = self.weights_generator(features)
        return self.basis_luts_bank(weights).view(features.shape[0], 3, N_VERTICES, N_VERTICES, N_VERTICES)


class SepLUTGenerator(nn.Module):
    """Return only the learned 1D and 3D transforms; Core Image handles full-res pixels."""

    def __init__(self) -> None:
        super().__init__()
        self.backbone = LightBackbone()
        self.lut1d_generator = LUT1DGenerator()
        self.lut3d_generator = LUT3DGenerator()

    def forward(self, image: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        features = self.backbone(image)
        return self.lut1d_generator(features), self.lut3d_generator(features)


def load_checkpoint(network: nn.Module, path: Path) -> None:
    try:
        checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    except Exception:
        # This is a pinned checkpoint from the official public SepLUT repository.
        checkpoint = torch.load(path, map_location="cpu", weights_only=False)
    if isinstance(checkpoint, dict) and "state_dict" in checkpoint:
        checkpoint = checkpoint["state_dict"]
    if not isinstance(checkpoint, dict):
        raise TypeError("SepLUT checkpoint does not contain a state dictionary")
    state = {key.removeprefix("module."): value for key, value in checkpoint.items()}
    network.load_state_dict(state, strict=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True, help="Destination SepLUT.mlpackage")
    parser.add_argument("--work", type=Path, required=True, help="Temporary directory for the checkpoint")
    args = parser.parse_args()

    args.work.mkdir(parents=True, exist_ok=True)
    checkpoint_path = args.work / "SepLUT-FiveK-sRGB-M8-3D17-1D17.pth"
    if not checkpoint_path.exists():
        urllib.request.urlretrieve(CHECKPOINT_URL, checkpoint_path)
    if checkpoint_path.stat().st_size != 486_462:
        raise RuntimeError(f"Unexpected SepLUT checkpoint size: {checkpoint_path.stat().st_size}")

    torch.set_num_threads(2)
    network = SepLUTGenerator().cpu().eval()
    load_checkpoint(network, checkpoint_path)
    sample = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE, dtype=torch.float32)
    with torch.inference_mode():
        traced = torch.jit.trace(network, sample, strict=True, check_trace=False)
        lut1d, lut3d = traced(sample)
        if tuple(lut1d.shape) != (1, 3, N_VERTICES) or tuple(lut3d.shape) != (1, 3, N_VERTICES, N_VERTICES, N_VERTICES):
            raise RuntimeError(f"Unexpected generated LUT shapes: {tuple(lut1d.shape)}, {tuple(lut3d.shape)}")
        if not torch.isfinite(lut1d).all() or not torch.isfinite(lut3d).all():
            raise RuntimeError("SepLUT generated non-finite LUT values")

    converted = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="lut1d"), ct.TensorType(name="lut3d")],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    converted.author = "SepLUT authors; Core ML conversion by LumaGrade"
    converted.short_description = "Image-adaptive 1D and 3D LUT generator"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        shutil.rmtree(args.output)
    converted.save(str(args.output))

    runtime_model = ct.models.MLModel(str(args.output), compute_units=ct.ComputeUnit.CPU_ONLY)
    pixels = np.full((INPUT_SIZE, INPUT_SIZE, 3), 112, dtype=np.uint8)
    result = runtime_model.predict({"image": Image.fromarray(pixels, mode="RGB")})
    one_d = result["lut1d"]
    three_d = result["lut3d"]
    if tuple(one_d.shape) != (1, 3, N_VERTICES) or tuple(three_d.shape) != (1, 3, N_VERTICES, N_VERTICES, N_VERTICES):
        raise RuntimeError(f"Core ML LUT output shapes are invalid: {one_d.shape}, {three_d.shape}")
    if not np.isfinite(one_d).all() or not np.isfinite(three_d).all():
        raise RuntimeError("Core ML SepLUT inference returned non-finite values")

    package_bytes = sum(path.stat().st_size for path in args.output.rglob("*") if path.is_file())
    print(f"SepLUT Core ML inference passed; 1D={one_d.shape}, 3D={three_d.shape}", flush=True)
    print(f"SepLUT.mlpackage: {package_bytes / 1_000_000:.2f} MB", flush=True)


if __name__ == "__main__":
    main()
