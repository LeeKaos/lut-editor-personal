# LumaGrade Engine

Engine runs image-to-image Core ML models locally on the iPhone. The macOS build workflow fetches pre-converted Core ML models, quantizes their weights to 8-bit where supported, and bundles them in the IPA. Modes are Zero-DCE low-light enhancement, MIRNetv2 low-light restoration, GFPGAN face restoration, and Real-ESRGAN upscaling. The MIRNetv2 model is a related newer model, not the original MIRNet model.

## Adding a model

1. The build prepares the selected `.mlmodel`/`.mlpackage` assets using `coremltools` and stages them in the app bundle.
2. On first use, iOS compiles the selected model and stores the compiled model in `Documents/EngineModels`.
3. If the bundled model cannot be used on a device, the matching model can be imported from Files with **Core ML modeli ekle**.

The imported model must accept an image and return an image through Vision. Tensor-only, multi-input, or face-crop models need a model-specific adapter and are rejected with a visible error instead of producing a misleading preview. The current release processes still photos; per-frame video inference is intentionally not enabled because these models can use substantial memory and heat.

Core ML is configured with `.all`, allowing iOS to select available compute units (including the Neural Engine when the model and device support it). This does not force ANE execution. Model quantization and FP16/INT8 conversion are performed when preparing the model, not at runtime.

## Model notes

- **Zero-DCE**: the official implementation states non-commercial/research-only use. The Core ML model zoo lists a 320 KB converted model.
- **MIRNet**: upstream MIRNet is a PyTorch project that distributes task-specific weights separately. MIRNetv2 is a related, newer architecture, not the same model; the Core ML model zoo lists MIRNetv2 variants under an academic license.
- **GFPGAN**: face restoration is specialized and model input/output behavior varies; a compatible image-to-image export is required.
- **Real-ESRGAN**: the Core ML model zoo lists a 66.9 MB x4 model; large output frames can still require considerable memory.

The app does not use a paid API. The build obtains public pre-converted model files from the Core ML model catalog. Confirm each model's current license and intended use before distributing the app. Inference and compiled models remain on-device.
