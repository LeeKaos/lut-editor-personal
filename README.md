# LumaGrade

LumaGrade is an iOS 17+ photo and video color-grading application built as a clean-room project. It is designed to be signed with a personal Apple developer account and installed through AltStore.

## What is included

- Project library with persistent image projects
- Photos picker, image editing, save/share, and video project placeholders
- Bundled camera and creative LUTs, plus import for standard `.cube` files
- LUT intensity, exposure, contrast, saturation, brightness, warmth, tint, highlights, shadows, vignette, bloom, and grain controls
- Filters / Adjust / Effects editor panel, presets, and a dark, responsive iPhone/iPad layout
- No app groups, push-notification entitlement, private API, tracking SDK, or paid-provisioning requirement

## Build and AltStore installation

1. Run `python3 Scripts/prepare_luts.py` to compile the source `.cube` files into compact runtime LUT resources.
2. Open `LumaGrade.xcodeproj` on a Mac with Xcode 15 or newer.
3. In **Signing & Capabilities**, select your personal team and set a unique bundle identifier (for example `com.yourname.lumagrade`).
4. Select an iPhone running iOS 17 or newer and build once. Grant photo-library permission when prompted.
5. Use **Product → Archive**, export an ad-hoc/development IPA, then install it with AltStore; alternatively use AltStore's IPA signing flow with your Apple ID.

The project deliberately has no App Group or Push Notifications capability, so it works with free developer signing subject to Apple's normal seven-day refresh requirement.

## LUT content

Original `.cube` LUTs are kept under `LUTSource` for review and editing. The build script compiles them to binary16 `.lutf` files under `LumaGrade/LUTs`, preserving their categories while reducing the installed app's resource footprint. Imported LUTs continue to use standard text `.cube` files that declare `LUT_3D_SIZE` and RGB triplets.

## Next implementation milestones

1. Add AVFoundation frame rendering and video export.
2. Add mask/crop/trim controls and Metal implementations of the advanced effects.
3. Add screenshot-based device QA for iPhone SE, standard iPhone, Max iPhone, and iPad.
