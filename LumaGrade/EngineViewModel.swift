import Combine
import Foundation
import UIKit

@MainActor
final class EngineViewModel: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var generatedImage: UIImage?
    @Published private(set) var analysis: EngineSceneAnalysis?
    @Published private(set) var result: EngineProcessingResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedEngine: EngineMode = .blendedAuto

    private let provider: any EngineProvider = HarmonizedAutoEngineProvider()
    private var processingTask: Task<Void, Never>?
    private var requestID = UUID()

    func selectBlendedAutoEngine() {
        selectedEngine = .blendedAuto
        errorMessage = nil
    }

    func runBlendedAutoEngine(image: UIImage, settings: GradeSettings, lut: CubeLUT?, sourceLUT: CubeLUT?, isVideo: Bool) {
        processingTask?.cancel()
        requestID = UUID()
        let currentRequestID = requestID
        let request = EngineProcessingRequest(
            image: image,
            settings: settings,
            creativeLUT: lut,
            sourceLUT: sourceLUT,
            isVideo: isVideo
        )
        let provider = self.provider
        selectedEngine = .blendedAuto
        isProcessing = true
        generatedImage = nil
        analysis = nil
        result = nil
        errorMessage = nil

        processingTask = Task { [weak self] in
            let outcome: Result<EngineProcessingResult, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = autoreleasepool {
                        Result { try provider.process(request) }
                    }
                    continuation.resume(returning: result)
                }
            }
            guard let self, self.requestID == currentRequestID else { return }
            self.isProcessing = false
            switch outcome {
            case .success(let processed):
                self.result = processed
                self.generatedImage = processed.previewImage
                self.analysis = processed.analysis
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func resetResult() {
        processingTask?.cancel()
        requestID = UUID()
        isProcessing = false
        generatedImage = nil
        analysis = nil
        result = nil
        errorMessage = nil
    }
}
