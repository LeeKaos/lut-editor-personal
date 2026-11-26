#!/usr/bin/env python3
"""Guard the two-stage LUT pipeline against accidental reordering.

The source-camera transform (Apple Log / S-Log / D-Log to Rec.709) must be
applied first. The creative look LUT and manual grading must be applied after.
"""
from pathlib import Path

source = Path("LumaGrade/RootView.swift").read_text(encoding="utf-8")

required = [
    "private func applySourceProfile(_ profile: String)",
    "onApplySourceProfile: applySourceProfile",
    'Picker("Kaynak profili", selection: $pendingSourceProfile)',
    "Kaynak LUT'unu onayla ve uygula",
    "var sourceProfileConfirmed = false",
    "let isSourceConfirmed: Bool",
    ".disabled(!isSourceConfirmed)",
    "project.settings.sourceProfileConfirmed = true",
    "let sourceTransform = settings.sourceProfileConfirmed ? CubeLUT.sourceTransform(for: settings.source, bundled: allLUTs) : nil",
    "if let sourceLUT { image = apply(sourceLUT, to: image, intensity: 1) }",
    "if let lut { image = apply(lut, to: image, intensity: min(1, max(0, settings.intensity / 100))) }",
]
for item in required:
    if item not in source:
        raise SystemExit(f"Missing required source-LUT pipeline element: {item}")

grade = source.index("static func grade(_ source: CIImage")
source_apply = "if let sourceLUT { image = apply(sourceLUT, to: image, intensity: 1) }"
creative_apply = "if let lut { image = apply(lut, to: image, intensity: min(1, max(0, settings.intensity / 100))) }"
base = source.index(source_apply, grade)
creative = source.index(creative_apply, grade)
if base >= creative:
    raise SystemExit("Incorrect LUT order: creative LUT must follow source conversion")

print("Verified: confirmed camera conversion LUT -> creative LUT -> manual grading")
