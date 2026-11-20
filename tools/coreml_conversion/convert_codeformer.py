#!/usr/bin/env python3
"""Convert the official CodeFormer checkpoint to an iOS 17 Core ML ML Program.

The checkpoint is downloaded by the workflow from the official CodeFormer release.
The exported interface is one RGB float32 tensor [1, 3, 512, 512] normalized to [-1, 1]
and one RGB float32 tensor [1, 3, 512, 512] normalized to [-1, 1].
Fidelity (w=0.7) and AdaIN are baked into the traced graph.
"""
from pathlib import Path
import sys
import torch
import coremltools as ct

ROOT = Path(__file__).resolve().parents[2]
CODEFORMER = ROOT / "CodeFormer"
WEIGHTS = CODEFORMER / "weights" / "CodeFormer" / "codeformer.pth"
OUT = ROOT / "artifacts" / "CodeFormer.mlpackage"
sys.path.insert(0, str(CODEFORMER))

# Importing this module registers the CodeFormer architecture in BasicSR.
import basicsr.archs.codeformer_arch  # noqa: F401
from basicsr.utils.registry import ARCH_REGISTRY

class ExportWrapper(torch.nn.Module):
    def __init__(self, network):
        super().__init__()
        self.network = network

    def forward(self, image):
        restored = self.network(image, w=0.7, adain=True)[0]
        return restored

def main():
    if not WEIGHTS.is_file():
        raise FileNotFoundError(f"Official checkpoint missing: {WEIGHTS}")
    torch.set_num_threads(4)
    print("Creating official CodeFormer architecture…", flush=True)
    net = ARCH_REGISTRY.get("CodeFormer")(
        dim_embd=512, codebook_size=1024, n_head=8, n_layers=9,
        connect_list=["32", "64", "128", "256"]
    )
    checkpoint = torch.load(WEIGHTS, map_location="cpu", weights_only=False)
    state = checkpoint.get("params_ema", checkpoint.get("params", checkpoint))
    net.load_state_dict(state, strict=True)
    net.eval()

    wrapper = ExportWrapper(net).eval()
    example = torch.zeros(1, 3, 512, 512, dtype=torch.float32)
    print("Tracing CodeFormer (512x512)…", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example, strict=False, check_trace=False)
    print("Converting traced graph to Core ML iOS 17 ML Program…", flush=True)
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[ct.TensorType(name="input", shape=example.shape, dtype=float)],
        outputs=[ct.TensorType(name="output", dtype=float)],
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    model.short_description = "CodeFormer face restoration; RGB NCHW 512x512, input/output range [-1,1], fidelity w=0.7."
    model.save(str(OUT))
    print(f"Saved {OUT} ({sum(p.stat().st_size for p in OUT.rglob('*') if p.is_file())} bytes)", flush=True)

if __name__ == "__main__":
    main()
