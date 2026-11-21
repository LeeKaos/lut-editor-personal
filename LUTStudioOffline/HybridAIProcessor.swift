import Foundation
import UIKit

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

/// App-facing contract for a private image-processing backend.
/// Provider API keys must remain on that backend, never in the iOS app.
struct CloudAIClient {
    struct RequestPayload: Encodable {
        let imageBase64: String
        let mimeType: String
        let commands: [String]
        let outputFormat: String

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
            case mimeType = "mime_type"
            case commands
            case outputFormat = "output_format"
        }
    }

    struct ResponsePayload: Decodable {
        let imageBase64: String?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case imageBase64 = "image_base64"
            case error
        }
    }

    func process(_ image: UIImage, commands: [AICommand], endpoint: String) async throws -> UIImage {
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
            outputFormat: "jpeg"
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
        return outputImage
    }
}

struct AIProcessingResult {
    let image: UIImage
    let usedCloud: Bool
    let cloudFallbackMessage: String?
}

/// Cloud-first for opted-in, configured requests; deterministic local/Core ML fallback otherwise.
@MainActor
enum HybridAIProcessor {
    static func process(
        _ image: UIImage,
        commands: [AICommand],
        localModels: LocalAIModelStore,
        cloudEndpoint: String,
        allowCloudUpload: Bool
    ) async throws -> AIProcessingResult {
        var cloudFailure: String?

        if allowCloudUpload, !cloudEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                let output = try await CloudAIClient().process(image, commands: commands, endpoint: cloudEndpoint)
                return AIProcessingResult(image: output, usedCloud: true, cloudFallbackMessage: nil)
            } catch {
                cloudFailure = "Bulut işlemi tamamlanamadı; yerel işlem deneniyor. \(error.localizedDescription)"
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
        return AIProcessingResult(image: output, usedCloud: false, cloudFallbackMessage: cloudFailure)
    }
}
