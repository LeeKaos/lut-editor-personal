import CoreImage
import Foundation
import UIKit
import Vision

enum EngineMode: String, Identifiable {
    case blendedAuto
    var id: String { rawValue }
    var title: String { "Harmanlanmış Auto Engine" }
}

enum EngineScene: String {
    case portrait
    case landscape
    case general

    var title: String {
        switch self {
        case .portrait: return "Portre"
        case .landscape: return "Manzara"
        case .general: return "Genel"
        }
    }

    var symbol: String {
        switch self {
        case .portrait: return "person.crop.square"
        case .landscape: return "mountain.2.fill"
        case .general: return "viewfinder"
        }
    }
}

struct EngineSceneAnalysis {
    let scene: EngineScene
    let labels: [String]
}

struct EngineProcessingRequest {
    let image: UIImage
    let settings: GradeSettings
    let creativeLUT: CubeLUT?
    let sourceLUT: CubeLUT?
    let isVideo: Bool
}

struct EngineEditStep: Identifiable {
    let id: String
    let title: String
}

/// A parameter-only edit document. Rendering always starts from the source image.
struct EngineEditStack {
    let baseSettings: GradeSettings
    let outputSettings: GradeSettings
    let steps: [EngineEditStep]
}

struct EngineProcessingResult {
    let previewImage: UIImage
    let analysis: EngineSceneAnalysis
    let editStack: EngineEditStack
}

protocol EngineSceneAnalyzing {
    func analyze(_ image: UIImage) throws -> EngineSceneAnalysis
}

protocol EngineProvider {
    var mode: EngineMode { get }
    func process(_ request: EngineProcessingRequest) throws -> EngineProcessingResult
}

protocol NonDestructiveEngineAdapting {
    func makeStack(request: EngineProcessingRequest, automaticSettings: GradeSettings) -> EngineEditStack
    func render(_ image: UIImage, stack: EngineEditStack, lut: CubeLUT?, sourceLUT: CubeLUT?) -> UIImage
}

protocol OptionalEngineProvider {
    var identifier: String { get }
    var isAvailable: Bool { get }
    var unavailableReason: String { get }
    func process(image: UIImage, mask: CIImage?) throws -> UIImage
}

struct AppleVisionSceneAnalyzer: EngineSceneAnalyzing {
    func analyze(_ image: UIImage) throws -> EngineSceneAnalysis {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(uiImage: image, options: [:]).perform([request])
        let observations = (request.results ?? []).filter { $0.confidence >= 0.06 }
        let labels = observations.prefix(5).map {
            $0.identifier.replacingOccurrences(of: "_", with: " ")
        }
        let identifiers = observations.map { $0.identifier.lowercased() }
        let portraitTerms = ["person", "people", "face", "portrait", "human", "man", "woman", "child"]
        let landscapeTerms = ["landscape", "mountain", "ocean", "sea", "beach", "forest", "sky", "nature", "outdoor"]
        let hasPortrait = identifiers.contains { label in portraitTerms.contains(where: label.contains) }
        let hasLandscape = identifiers.contains { label in landscapeTerms.contains(where: label.contains) }
        let scene: EngineScene = hasPortrait ? .portrait : (hasLandscape ? .landscape : .general)
        return EngineSceneAnalysis(scene: scene, labels: labels)
    }
}

/// Bridges the app's persisted GradeSettings/LUT renderer to a parameter-stack API.
/// This leaves a narrow seam for Brightroom's EditingStack without requiring its
/// Swift 6.3 package in this Swift 5 target.
struct BrightroomCompatibleAdapter: NonDestructiveEngineAdapting {
    func makeStack(request: EngineProcessingRequest, automaticSettings: GradeSettings) -> EngineEditStack {
        var output = EngineSettingsComposer.merge(automaticSettings, into: request.settings)
        output.autoEnhance = request.settings.autoEnhance || !request.isVideo

        var steps: [EngineEditStep] = []
        if request.sourceLUT != nil {
            steps.append(EngineEditStep(id: "source-profile", title: "Kaynak profili: \(request.settings.source)"))
        }
        if request.creativeLUT != nil {
            steps.append(EngineEditStep(id: "creative-lut", title: "LUT: \(request.settings.lutName) · %\(Int(request.settings.intensity))"))
        }
        steps.append(EngineEditStep(id: "vision-scene", title: "Vision sahne sınıflandırması"))
        steps.append(EngineEditStep(id: "core-image-auto", title: "Core Image dengeli ton ve renk düzeltmesi"))
        steps.append(EngineEditStep(id: "adjustments", title: "Mevcut ayarlar korunarak tahribatsız düzenleme"))
        return EngineEditStack(baseSettings: request.settings, outputSettings: output, steps: steps)
    }

    func render(_ image: UIImage, stack: EngineEditStack, lut: CubeLUT?, sourceLUT: CubeLUT?) -> UIImage {
        ImageRenderer.grade(image, settings: stack.outputSettings, lut: lut, sourceLUT: sourceLUT)
    }
}

struct HarmonizedAutoEngineProvider: EngineProvider {
    let mode: EngineMode = .blendedAuto
    private let sceneAnalyzer: any EngineSceneAnalyzing = AppleVisionSceneAnalyzer()
    private let editAdapter: any NonDestructiveEngineAdapting = BrightroomCompatibleAdapter()

    func process(_ request: EngineProcessingRequest) throws -> EngineProcessingResult {
        let safeImage = EngineImageSizer.previewImage(request.image, maximumDimension: 2048)
        let scene = try sceneAnalyzer.analyze(safeImage)
        var automatic = ImageRenderer.automaticLook(
            source: safeImage,
            lut: request.creativeLUT,
            lutIntensity: request.settings.intensity,
            sourceLUT: request.sourceLUT,
            style: .automatic
        )
        switch scene.scene {
        case .portrait:
            automatic.saturation = min(1.08, automatic.saturation)
            automatic.vibrance = min(0.08, automatic.vibrance)
        case .landscape:
            automatic.vibrance = min(0.22, automatic.vibrance + 0.025)
        case .general:
            break
        }
        let stack = editAdapter.makeStack(request: request, automaticSettings: automatic)
        let preview = editAdapter.render(safeImage, stack: stack, lut: request.creativeLUT, sourceLUT: request.sourceLUT)
        return EngineProcessingResult(previewImage: preview, analysis: scene, editStack: stack)
    }
}

enum EngineOptionalModules {
    static let gpuImageProvider = GPUImageEngineProviderAdapter()
    static let deepDetailProvider = CoreMLDetailEngineProviderAdapter()
    static let inpaintingProvider = InpaintingCoreMLProviderAdapter()

    static var gpuImage: OptionalModuleState { state(for: gpuImageProvider) }
    static var deepDetail: OptionalModuleState { state(for: deepDetailProvider) }
    static var inpainting: OptionalModuleState { state(for: inpaintingProvider) }

    private static func state(for provider: any OptionalEngineProvider) -> OptionalModuleState {
        OptionalModuleState(
            identifier: provider.identifier,
            isAvailable: provider.isAvailable,
            unavailableReason: provider.unavailableReason
        )
    }
}

struct OptionalModuleState: OptionalEngineProvider {
    let identifier: String
    let isAvailable: Bool
    let unavailableReason: String

    func process(image: UIImage, mask: CIImage?) throws -> UIImage {
        guard isAvailable else { throw EngineProviderError.moduleUnavailable(unavailableReason) }
        return image
    }
}

/// Supply a GPUImage3 filter operation when the optional package is added.
struct GPUImageEngineProviderAdapter: OptionalEngineProvider {
    let filter: ((UIImage) throws -> UIImage)?
    init(filter: ((UIImage) throws -> UIImage)? = nil) { self.filter = filter }
    var identifier: String { "gpuimage" }
    var isAvailable: Bool { filter != nil }
    var unavailableReason: String { "GPUImage3 bağımlılığı projeye eklenmedi; efekt adaptör noktası hazır." }
    func process(image: UIImage, mask: CIImage?) throws -> UIImage {
        guard let filter else { throw EngineProviderError.moduleUnavailable(unavailableReason) }
        return try filter(image)
    }
}

/// The injected operation owns model-specific Core ML input/output conversion.
struct CoreMLDetailEngineProviderAdapter: OptionalEngineProvider {
    let inference: ((UIImage) throws -> UIImage)?
    init(inference: ((UIImage) throws -> UIImage)? = nil) { self.inference = inference }
    var identifier: String { "coreml-detail" }
    var isAvailable: Bool { inference != nil }
    var unavailableReason: String { "Derin Detay Core ML model ağırlıkları uygulama paketinde yok." }
    func process(image: UIImage, mask: CIImage?) throws -> UIImage {
        guard let inference else { throw EngineProviderError.moduleUnavailable(unavailableReason) }
        return try inference(image)
    }
}

/// Inpainting is opt-in and requires both a bundled model and a user-drawn mask.
struct InpaintingCoreMLProviderAdapter: OptionalEngineProvider {
    let inference: ((UIImage, CIImage) throws -> UIImage)?
    init(inference: ((UIImage, CIImage) throws -> UIImage)? = nil) { self.inference = inference }
    var identifier: String { "coreml-inpainting" }
    var isAvailable: Bool { inference != nil }
    var unavailableReason: String { "Inpainting modeli ve maske çizim aracı henüz ekli değil." }
    func process(image: UIImage, mask: CIImage?) throws -> UIImage {
        guard let inference else { throw EngineProviderError.moduleUnavailable(unavailableReason) }
        guard let mask else { throw EngineProviderError.moduleUnavailable("Inpainting için önce maske çizilmesi gerekir.") }
        return try inference(image, mask)
    }
}

enum EngineProviderError: LocalizedError {
    case moduleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .moduleUnavailable(let reason): return reason
        }
    }
}

private enum EngineImageSizer {
    static func previewImage(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let largestEdge = max(image.size.width, image.size.height)
        guard largestEdge > maximumDimension, largestEdge > 0 else { return image }
        let scale = maximumDimension / largestEdge
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private enum EngineSettingsComposer {
    static func merge(_ automatic: GradeSettings, into base: GradeSettings) -> GradeSettings {
        var output = base
        output.exposure = min(3, max(-3, base.exposure + automatic.exposure))
        output.contrast = min(2, max(0.5, base.contrast * automatic.contrast))
        output.saturation = min(2, max(0, base.saturation * automatic.saturation))
        output.temperature = min(12000, max(2000, base.temperature + automatic.temperature - 6500))
        output.tint = min(150, max(-150, base.tint + automatic.tint))
        output.highlights = min(2, max(0, base.highlights - (1 - automatic.highlights)))
        output.shadows = min(2, max(0, base.shadows + automatic.shadows))
        output.vibrance = min(1, max(-1, base.vibrance + automatic.vibrance))
        output.brilliance = min(1, max(-1, base.brilliance + automatic.brilliance))
        output.wheelShadows = min(1, max(-1, base.wheelShadows + automatic.wheelShadows))
        output.wheelHighlights = min(1, max(-1, base.wheelHighlights + automatic.wheelHighlights))
        output.vignette = min(2, max(0, base.vignette + automatic.vignette))
        output.bloom = min(1, max(0, base.bloom + automatic.bloom))
        output.sharpness = min(1, max(0, base.sharpness + automatic.sharpness))
        output.definition = min(1, max(0, base.definition + automatic.definition))
        return output
    }
}
