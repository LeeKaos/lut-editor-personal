import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

enum AICommand: String, CaseIterable {
    case glowUp, beStudio, softLight, proShot
    case old2New, hdReal, colorFix, nightFix
    case ghibli, outfit, removeObject, bgCinematic
    case mistyHills, stormCoast, goldenCoast
    case faceRestore, upscale

    var title: String {
        switch self {
        case .glowUp: return "GlowUp"
        case .beStudio: return "Be Studio"
        case .softLight: return "Soft Light"
        case .proShot: return "ProShot"
        case .old2New: return "Old2New"
        case .hdReal: return "HD Real"
        case .colorFix: return "Color Fix"
        case .nightFix: return "Night Fix"
        case .ghibli: return "Ghibli"
        case .outfit: return "Outfit"
        case .removeObject: return "Nesne Silme"
        case .bgCinematic: return "BG Cinematic"
        case .mistyHills: return "Misty Hills"
        case .stormCoast: return "Storm Coast"
        case .goldenCoast: return "Golden Coast"
        case .faceRestore: return "Yüz Restorasyonu"
        case .upscale: return "4× Büyütme"
        }
    }

    var requiresGenerativeModel: Bool {
        switch self {
        case .ghibli, .outfit, .removeObject, .bgCinematic, .mistyHills, .stormCoast, .goldenCoast:
            return true
        default:
            return false
        }
    }
}

enum AICommandError: LocalizedError {
    case modelRequired(String)
    case unsupportedInput

    var errorDescription: String? {
        switch self {
        case .modelRequired(let name):
            return "\(name) için uygun üretken Core ML modeli henüz yüklenmedi. Bu işlem yalnızca komut adıyla taklit edilmez."
        case .unsupportedInput:
            return "Fotoğraf bu efekt için okunamadı."
        }
    }
}

enum AICommandEngine {
    private static let aliases: [String: AICommand] = [
        "GLOWUP": .glowUp, "GLOW-UP": .glowUp,
        "BGSTUDIO": .beStudio, "BE-STUDIO": .beStudio,
        "SOFTLIGHT": .softLight, "SOFT-LIGHT": .softLight,
        "PROSHOT": .proShot, "PRO-SHOT": .proShot,
        "OLD2NEW": .old2New, "HDREAL": .hdReal, "COLORFIX": .colorFix,
        "NIGHTFIX": .nightFix, "GHIBLI": .ghibli, "OUTFIT": .outfit,
        "REMOVEOBJECT": .removeObject, "OBJECT-REMOVE": .removeObject,
        "BGCINEMATIC": .bgCinematic, "MISTY-HILLS": .mistyHills,
        "STORM-COAST": .stormCoast, "GOLDEN-COAST": .goldenCoast,
        "FACEFIX": .faceRestore, "CODEFORMER": .faceRestore,
        "UPSCALE4X": .upscale, "HDUP": .upscale
    ]

    static func commands(from raw: String) -> [AICommand] {
        raw.split(whereSeparator: { $0.isWhitespace }).compactMap { part in
            let token = String(part)
            let normalized = token.hasPrefix("/") ? String(token.dropFirst()) : token
            return aliases[normalized.uppercased()]
        }
    }

    static func apply(_ command: AICommand, to image: UIImage) throws -> UIImage {
        guard !command.requiresGenerativeModel else {
            throw AICommandError.modelRequired(command.title)
        }
        guard let normalized = normalizedCGImage(image) else {
            throw AICommandError.unsupportedInput
        }
        var output = CIImage(cgImage: normalized)
        let extent = output.extent

        func filter(_ name: String, _ values: [String: Any]) {
            guard let effect = CIFilter(name: name) else { return }
            effect.setValue(output, forKey: kCIInputImageKey)
            for (key, value) in values { effect.setValue(value, forKey: key) }
            output = effect.outputImage?.cropped(to: extent) ?? output
        }

        switch command {
        case .glowUp:
            filter("CIExposureAdjust", ["inputEV": 0.18])
            filter("CIHighlightShadowAdjust", ["inputShadowAmount": 0.28, "inputHighlightAmount": 0.92])
            filter("CIColorControls", [kCIInputContrastKey: 1.08, kCIInputSaturationKey: 1.04])
            filter("CIUnsharpMask", ["inputRadius": 1.1, "inputIntensity": 0.38])
        case .beStudio:
            filter("CIExposureAdjust", ["inputEV": 0.22])
            filter("CIHighlightShadowAdjust", ["inputShadowAmount": 0.18, "inputHighlightAmount": 0.82])
            filter("CIColorControls", [kCIInputContrastKey: 1.12, kCIInputSaturationKey: 0.96])
            filter("CIVignette", ["inputIntensity": 0.22, "inputRadius": 1.8])
        case .softLight:
            filter("CIHighlightShadowAdjust", ["inputShadowAmount": 0.24, "inputHighlightAmount": 0.95])
            filter("CIBloom", ["inputRadius": 14.0, "inputIntensity": 0.22])
            filter("CIColorControls", [kCIInputContrastKey: 0.98, kCIInputSaturationKey: 1.02])
        case .proShot:
            filter("CIExposureAdjust", ["inputEV": 0.12])
            filter("CIColorControls", [kCIInputContrastKey: 1.12, kCIInputSaturationKey: 1.05])
            filter("CIUnsharpMask", ["inputRadius": 1.4, "inputIntensity": 0.48])
            filter("CIVignette", ["inputIntensity": 0.18, "inputRadius": 2.0])
        case .old2New:
            filter("CIColorControls", [kCIInputSaturationKey: 1.08, kCIInputContrastKey: 1.06])
            filter("CIHighlightShadowAdjust", ["inputShadowAmount": 0.2, "inputHighlightAmount": 0.9])
            filter("CIUnsharpMask", ["inputRadius": 1.0, "inputIntensity": 0.3])
        case .hdReal:
            filter("CISharpenLuminance", ["inputSharpness": 0.45, "inputRadius": 1.0])
        case .colorFix:
            let auto = output.autoAdjustmentFilters(options: [.enhance: true, .redEye: false])
            for effect in auto {
                effect.setValue(output, forKey: kCIInputImageKey)
                output = effect.outputImage?.cropped(to: extent) ?? output
            }
        case .nightFix:
            filter("CIExposureAdjust", ["inputEV": 0.55])
            filter("CIHighlightShadowAdjust", ["inputShadowAmount": 0.72, "inputHighlightAmount": 0.8])
            filter("CIColorControls", [kCIInputSaturationKey: 1.08, kCIInputContrastKey: 1.04])
        default:
            throw AICommandError.modelRequired(command.title)
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(output, from: extent) else {
            throw AICommandError.unsupportedInput
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }

    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage { return cgImage }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }.cgImage
    }
}
