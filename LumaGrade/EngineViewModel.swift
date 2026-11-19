import Combine
import Foundation
import UIKit
import Vision

@MainActor
final class EngineViewModel: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var generatedImage: UIImage?
    @Published private(set) var smartPrompt = ""
    @Published private(set) var errorMessage: String?

    private var processingTask: Task<Void, Never>?

    func generateSmartPrompt(from image: UIImage) -> String {
        guard let cgImage = image.cgImage else {
            return "Cinematic lighting, preserve the original composition, professional color grading, subtle film texture"
        }

        let request = VNClassifyImageRequest()
        request.imageCropAndScaleOption = .scaleFit
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return "Cinematic lighting, preserve the original composition, professional color grading, subtle film texture"
        }

        let tags = (request.results ?? [])
            .filter { $0.confidence >= 0.08 }
            .prefix(4)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        let scene = tags.isEmpty ? "natural scene" : tags.joined(separator: ", ")
        return "\(scene), cinematic lighting, preserve the original scene and composition, detailed natural texture, professional color grading, balanced highlights and shadows, subtle film texture, realistic colors"
    }

    func runEngine(inputImage: UIImage) {
        runEngine(inputImage: inputImage, processor: Self.localPreview)
    }

    func runEngine(inputImage: UIImage, processor: @escaping (UIImage) -> UIImage) {
        processingTask?.cancel()
        isProcessing = true
        generatedImage = nil
        errorMessage = nil
        smartPrompt = generateSmartPrompt(from: inputImage)

        processingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                let result = await Task.detached(priority: .userInitiated) {
                    processor(inputImage)
                }.value
                guard !Task.isCancelled else { return }
                self?.generatedImage = result
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = "Engine önizlemesi oluşturulamadı: \(error.localizedDescription)"
            }
            self?.isProcessing = false
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    private static func localPreview(_ image: UIImage) -> UIImage {
        var recipe = ImageRenderer.automaticLook(
            source: image,
            lut: nil,
            lutIntensity: 100,
            sourceLUT: nil,
            style: .cinematic
        )
        recipe.autoEnhance = true
        return ImageRenderer.grade(image, settings: recipe, lut: nil, sourceLUT: nil)
    }
}
