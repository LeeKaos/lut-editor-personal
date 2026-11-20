#!/usr/bin/env python3
"""Convert the official Real-ESRGAN x4plus checkpoint to an iOS 17 Core ML model."""
from pathlib import Path
import sys
import torch
import coremltools as ct

ROOT = Path(__file__).resolve().parents[2]
CODEFORMER = ROOT / "CodeFormer"
WEIGHTS = ROOT / "weights" / "RealESRGAN_x4plus.pth"
OUT = ROOT / "artifacts" / "RealESRGAN_x4plus.mlpackage"
sys.path.insert(0, str(CODEFORMER))

from basicsr.archs.rrdbnet_arch import RRDBNet

def main():
    if not WEIGHTS.is_file():
        raise FileNotFoundError(f"Real-ESRGAN checkpoint missing: {WEIGHTS}")
    torch.set_num_threads(4)
    net = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64,
                  num_block=23, num_grow_ch=32, scale=4)
    checkpoint = torch.load(WEIGHTS, map_location="cpu", weights_only=False)
    state = checkpoint.get("params_ema", checkpoint.get("params", checkpoint))
    net.load_state_dict(state, strict=True)
    net.eval()

    example = torch.zeros(1, 3, 64, 64, dtype=torch.float32)
    print("Tracing Real-ESRGAN x4plus (64x64 -> 256x256)…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(net, example, strict=False, check_trace=False)
    print("Converting Real-ESRGAN to Core ML iOS 17 ML Program…", flush=True)
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.TensorType(name="input", shape=example.shape, dtype=float)],
        outputs=[ct.TensorType(name="output", dtype=float)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    model.short_description = "Real-ESRGAN x4plus; RGB NCHW 64x64 input and 256x256 output, values [0,1]."
    model.save(str(OUT))
    print(f"Saved {OUT} ({sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())} bytes)", flush=True)

if __name__ == "__main__":
    main()
