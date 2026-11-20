# LumaGrade Engine

Engine runs image-to-image Core ML models locally on the iPhone. It has separate modes for low-light enhancement (Zero-DCE), restoration (MIRNet), face restoration (GFPGAN), and upscaling (Real-ESRGAN). Models are imported by the user and compiled in the app sandbox; they are not bundled in the IPA.

## Adding a model

1. Obtain or convert a model to `.mlmodel` or `.mlpackage` on macOS with a compatible version of `coremltools`.
2. In the editor, open **Engine**, select the matching mode, and choose **Core ML modeli ekle**.
3. Let iOS compile it. Engine keeps the compiled model in `Documents/EngineModels` and runs inference locally.

The imported model must accept an image and return an image through Vision. Tensor-only, multi-input, or face-crop models need a model-specific adapter and are rejected with a visible error instead of producing a misleading preview. The current release processes still photos; per-frame video inference is intentionally not enabled because these models can use substantial memory and heat.

Core ML is configured with `.all`, allowing iOS to select available compute units (including the Neural Engine when the model and device support it). This does not force ANE execution. Model quantization and FP16/INT8 conversion are performed when preparing the model, not at runtime.

## Model notes

- **Zero-DCE**: the official implementation states non-commercial/research-only use. The Core ML model zoo lists a 320 KB converted model.
- **MIRNet**: upstream MIRNet is a PyTorch project that distributes task-specific weights separately. MIRNetv2 is a related, newer architecture, not the same model; the Core ML model zoo lists MIRNetv2 variants under an academic license.
- **GFPGAN**: face restoration is specialized and model input/output behavior varies; a compatible image-to-image export is required.
- **Real-ESRGAN**: the Core ML model zoo lists a 66.9 MB x4 model; large output frames can still require considerable memory.

The app does not download weights from a paid API or silently fetch models. Confirm each model's current license and intended use before importing it. The selected model remains on-device.
