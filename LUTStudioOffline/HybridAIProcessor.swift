import Foundation
import UIKit
import Vision

enum CloudAIError: LocalizedError {
    case endpointNotConfigured
    case insecureEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            return "Bulut AI sunucu adresi henüz ayarlanmamış."
        case .insecureEndpoint:
            return "Güvenlik için bulut AI adresi HTTPS olmalıdır."
        case .invalidResponse:
            return "Bulut AI sunucusundan geçerli bir görsel yanıtı alınamadı."
        case .server(let message):
            return message
        }
    }
}

struct SmartPhotoAnalysis: Encodable {
    let imageWidth: Int
    let imageHeight: Int
    let faceCount: Int
    let portraitOrientation: Bool
    let sceneLabels: [String]

    enum CodingKeys: String, CodingKey {
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case faceCount = "face_count"
        case portraitOrientation = "portrait_orientation"
        case sceneLabels = "scene_labels"
    }
}

enum SmartImageAnalyzer {
    static func analyze(_ image: UIImage) -> SmartPhotoAnalysis {
        let fallbackWidth = Int(image.size.width * image.scale)
        let fallbackHeight = Int(image.size.height * image.scale)
        let cgImage = image.cgImage ?? UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.cgImage

        guard let cgImage else {
            return SmartPhotoAnalysis(
                imageWidth: fallbackWidth,
                imageHeight: fallbackHeight,
                faceCount: 0,
                portraitOrientation: fallbackHeight >= fallbackWidth,
                sceneLabels: []
            )
        }

        let faceRequest = VNDetectFaceRectanglesRequest()
        let sceneRequest = VNClassifyImageRequest()
        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([faceRequest, sceneRequest])
        } catch {
            // Analysis is advisory; the image can still be processed if Vision classification fails.
        }
        let labels = (sceneRequest.results ?? [])
            .prefix(5)
            .filter { $0.confidence >= 0.15 }
            .map(\.identifier)

        return SmartPhotoAnalysis(
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            faceCount: faceRequest.results?.count ?? 0,
            portraitOrientation: cgImage.height >= cgImage.width,
            sceneLabels: labels
        )
    }
}

/// App-facing contract for a private image-processing backend.
/// Provider API keys must remain on that backend, never in the iOS app.
struct CloudAIClient {
    struct RequestPayload: Encodable {
        let imageBase64: String
        let mimeType: String
        let commands: [String]
        let outputFormat: String
        let analysis: SmartPhotoAnalysis

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
            case mimeType = "mime_type"
            case commands
            case outputFormat = "output_format"
            case analysis
        }
    }

    struct ResponsePayload: Decodable {
        let imageBase64: String?
        let error: String?
        let provider: String?
        let analysisProvider: String?
        let analysisSummary: String?
        let recommendations: [String]?

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
            case error
            case provider
            case analysisProvider = "analysis_provider"
            case analysisSummary = "analysis_summary"
            case recommendations
        }
    }

    struct Output {
        let image: UIImage
        let provider: String?
        let analysisProvider: String?
        let analysisSummary: String?
        let recommendations: [String]
    }

    func process(_ image: UIImage, commands: [AICommand], endpoint: String, accessToken: String) async throws -> Output {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CloudAIError.endpointNotConfigured
        }
        guard url.scheme?.lowercased() == "https" else {
            throw CloudAIError.insecureEndpoint
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.94) else {
            throw LocalAIError.invalidImage
        }

        let payload = RequestPayload(
            imageBase64: jpeg.base64EncodedString(),
            mimeType: "image/jpeg",
            commands: commands.map(\.rawValue),
            outputFormat: "jpeg",
            analysis: SmartImageAnalyzer.analyze(image)
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !accessToken.isEmpty {
            request.setValue(accessToken, forHTTPHeaderField: "X-App-Token")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode(ResponsePayload.self, from: data).error)
                ?? "Bulut AI isteği başarısız oldu (HTTP \(http.statusCode))."
            throw CloudAIError.server(serverMessage)
        }
        let result = try JSONDecoder().decode(ResponsePayload.self, from: data)
        guard let encoded = result.imageBase64,
              let outputData = Data(base64Encoded: encoded),
              let outputImage = UIImage(data: outputData) else {
            throw CloudAIError.invalidResponse
        }
        return Output(
            image: outputImage,
            provider: result.provider,
            analysisProvider: result.analysisProvider,
            analysisSummary: result.analysisSummary,
            recommendations: result.recommendations ?? []
        )
    }
}

struct AIProcessingResult {
    let image: UIImage
    let usedCloud: Bool
    let cloudFallbackMessage: String?
    let cloudProvider: String?
    let analysisProvider: String?
    let analysisSummary: String?
    let recommendations: [String]
}

/// Cloud-first for opted-in, configured requests; deterministic local/Core ML fallback otherwise.
@MainActor
enum HybridAIProcessor {
    static func process(
        _ image: UIImage,
        commands: [AICommand],
        localModels: LocalAIModelStore,
        cloudEndpoint: String,
        allowCloudUpload: Bool,
        cloudAccessToken: String
    ) async throws -> AIProcessingResult {
        var cloudFailure: String?

        if allowCloudUpload {
            if cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cloudFailure = CloudAIError.endpointNotConfigured.localizedDescription
            } else {
                do {
                    let output = try await CloudAIClient().process(image, commands: commands, endpoint: cloudEndpoint, accessToken: cloudAccessToken)
                    return AIProcessingResult(
                        image: output.image,
                        usedCloud: true,
                        cloudFallbackMessage: nil,
                        cloudProvider: output.provider,
                        analysisProvider: output.analysisProvider,
                        analysisSummary: output.analysisSummary,
                        recommendations: output.recommendations
                    )
                } catch {
                    cloudFailure = "Bulut işlemi tamamlanamadı; yerel işlem deneniyor. \(error.localizedDescription)"
                }
            }
        }

        var output = image
        for command in commands {
            switch command {
            case .faceRestore:
                output = try await localModels.enhance(output, using: .codeFormer)
            case .hdReal:
                output = try await localModels.enhance(output, using: .realESRGAN)
            default:
                output = try AICommandEngine.apply(command, to: output)
            }
        }
        return AIProcessingResult(
            image: output,
            usedCloud: false,
            cloudFallbackMessage: cloudFailure,
            cloudProvider: nil,
            analysisProvider: nil,
            analysisSummary: nil,
            recommendations: []
        )
    }
}
