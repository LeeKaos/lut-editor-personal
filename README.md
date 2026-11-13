# LUT Editor for iPhone

Personal, on-device iOS video editor project. It has no account, subscription, analytics, or cloud upload code. Video processing and LUT rendering use Apple's AVFoundation and Core Image frameworks on the iPhone.

## Included in this first build

- Video selection from Photos and local playback
- Local project history with saved per-video editing settings
- LUT browser with the bundled `.cube` files and intensity control
- Import of additional `.cube` files
- Adjust panel for hue, exposure, contrast, highlights, shadows, temperature, vibrance, saturation, sharpness, vignette, and curves
- Bloom, grain, and halation controls
- Local saved presets
- Playback scrubber, loop, original comparison, pinch zoom, and full-screen preview
- Highest quality, 1080p, or 720p export to the Photos library

## Build on a Mac

1. Open `LUTStudioOffline.xcodeproj` in Xcode.
2. Select the `LUTStudioOffline` app target and choose a signing team under **Signing & Capabilities**.
3. Connect the iPhone, select it as the run destination, and press **Run**.

The project targets iOS 17 or later. This project has not yet been built in the current Windows workspace.

## Build without owning a Mac

The included GitHub Actions workflow runs the iPhone build on GitHub's hosted macOS runner and saves an unsigned IPA as a workflow artifact. It uploads the app source and bundled LUTs for the build; it does not upload any of your videos. To use it, put this folder in a private GitHub repository and run **Actions → Build iPhone app → Run workflow**.

On Windows, AltServer can sideload the resulting IPA to an iPhone and sign it with the Apple Account you enter in AltServer. Keep your Apple password in AltServer; do not send it in chat. With a free Apple account, the install needs refreshing about every 7 days. AltStore can refresh it when AltServer is running on the same Wi-Fi network or the phone is connected over USB.

The app itself processes the video locally. The hosted build only needs the source project and included LUT files.
