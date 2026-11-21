# Local AI effects and Core ML models

LUT Studio photo effects run locally on the iPhone. Photos are not uploaded.

## Active slash commands

- `/GLOWUP`, `/BGSTUDIO`, `/SOFTLIGHT`, `/PROSHOT`
- `/OLD2NEW`, `/HDREAL`, `/COLORFIX`, `/NIGHTFIX`
- `/LONGEXPOSURE`, `/MOTIONBLUR`, `/GOLDENHOUR`
- `/FACEFIX`

The first, second, third, fourth, fifth, seventh, eighth, ninth, tenth, and eleventh commands are native Core Image effects and do not need separate neural-network model files. `/HDREAL` uses Real-ESRGAN x4plus for actual super-resolution. `/FACEFIX` uses CodeFormer for face restoration.

## Install the two Core ML models

1. Open a photo and choose **Yapay Zekâ**.
2. Tap **Model ekle** beside Face Fix or HD Real.
3. Select a compatible `.mlpackage`, `.mlmodel`, or compiled `.mlmodelc` from Files.
4. Once installed, tap the corresponding effect button.

The app copies models into Application Support and runs inference using Core ML on-device. It does not download weights automatically.

### Real-ESRGAN x4plus

Use the general-photo RealESRGAN_x4plus conversion. The runtime processes large images in overlapping tiles. Upstream Real-ESRGAN is BSD-3-Clause; retain attribution when redistributing weights or converted packages.

### CodeFormer

Vision detects faces on-device, crops each face, runs Core ML inference, and blends the restored crop into the original photo. The official CodeFormer project uses the NTU S-Lab License 1.0. Review the exact model conversion's license and terms. The repository does not bundle its weights.

## Conversion workflow

The GitHub Actions workflow `.github/workflows/convert-ai-models.yml` creates Core ML packages for CodeFormer and Real-ESRGAN and uploads them as an Actions artifact. Run it from the feature branch, then download `iOS-CoreML-models` and import the two packages through the app.

## Technical notes

- These are still-photo effects. AI processing on video frames is not included.
- Core Image effects are deterministic local filters, not generative AI models.
- Model speed and memory use depend on the iPhone and the exact converted package.
- The app intentionally does not include Ghibli style transfer, object removal, outfit replacement, or background removal.

