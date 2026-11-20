# Local AI models (Core ML)

The **Özel** panel can load Core ML models directly on the iPhone. The model files are copied into the app's Application Support directory and inference runs with Apple's Core ML runtime (`computeUnits = .all`). Photos are not uploaded.

## Install a model

1. Open a photo in LUT Studio and choose **Özel**.
2. Tap **Model ekle** beside CodeFormer or Real-ESRGAN.
3. Select a compatible `.mlpackage`, `.mlmodel`, or compiled `.mlmodelc` from Files.
4. After the model is loaded, use the corresponding local processing button.

The app does not download model weights. Keep model files in the Files app or another local storage location and import them when needed.

## Model interface requirements

The runtime supports Core ML models with an image input or an RGB `MLMultiArray` input (NCHW or NHWC, 3 channels), and an image or RGB `MLMultiArray` output. Optional scalar inputs are initialized conservatively: a parameter named `w` or containing `fidelity` receives 0.7; other numeric scalar inputs receive zero.

### Real-ESRGAN

Use a Core ML conversion of the general-photo RealESRGAN_x4plus or x2plus model. The runtime reads the model's fixed input tensor dimensions and processes the source photo in overlapping tiles, then assembles the output at the model's scale. This avoids stretching the entire photo into a square model input.

The upstream Real-ESRGAN project is BSD-3-Clause. Preserve its license and attribution when redistributing model weights or converted packages.

### CodeFormer

CodeFormer is used only for face restoration. Vision detects faces on-device, expands each face to a square crop, runs the Core ML model on the crop, and blends the restored result into the original photo with a soft mask. No face is synthesized when no face is detected.

CodeFormer Core ML conversions are not interchangeable: use a conversion whose input/output tensor names and shapes match the interface above. The official CodeFormer project is distributed under the NTU S-Lab License 1.0. Review that license and the terms for the exact converted weights before copying or distributing a model. This repository intentionally does not bundle CodeFormer weights.

## Important

- This integration is for still-photo processing. Video-frame AI processing is not enabled; existing video grading/export remains on-device through AVFoundation and Core Image.
- Core ML model interfaces vary by converter. A model that uses unsupported feature types or custom multi-input preprocessing will be rejected with an explanatory error rather than silently producing a misleading result.
- Model quality, memory use, and speed depend on the exact conversion and iPhone hardware. Test with copies of original photos first.