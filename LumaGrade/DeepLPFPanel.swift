import SwiftUI
import CoreML
import CoreImage
import CoreVideo
import UIKit

private let deepLPFAccent = Color(red: 0.66, green: 1.0, blue: 0.16)

private enum DeepLPFError: LocalizedError {
    case modelMissing
    case noImageOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing: "DeepLPF modeli uygulama paketinde bulunamadı."
        case .noImageOutput: "DeepLPF bu fotoğraf için görüntü çıktısı üretemedi."
        }
    }
}

private enum DeepLPFModel {
    static var compiledModelURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepLPF", isDirectory: true)
            .appendingPathComponent("DeepLPF.mlmodelc", isDirectory: true)
    }

    static func prepare() async throws -> URL {
        if FileManager.default.fileExists(atPath: compiledModelURL.path) { return compiledModelURL }
        guard let package = Bundle.main.resourceURL?
            .appendingPathComponent("DeepLPFModels", isDirectory: true)
            .appendingPathComponent("DeepLPF.mlpackage", isDirectory: true),
              FileManager.default.fileExists(atPath: package.path) else { throw DeepLPFError.modelMissing }

        return try await Task.detached(priority: .userInitiated) {
            let compiled = try MLModel.compileModel(at: package)
            let directory = compiledModelURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: compiledModelURL)
            try FileManager.default.moveItem(at: compiled, to: compiledModelURL)
            return compiledModelURL
        }.value
    }

    static func enhance(_ image: UIImage) async throws -> UIImage {
        let modelURL = try await prepare()

        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let normalized = Self.normalized(image, maximumDimension: 1920)
                guard let cgImage = normalized.cgImage else { throw DeepLPFError.noImageOutput }
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                let inputBuffer = try Self.pixelBuffer(from: cgImage)
                let input = MLFeatureValue(pixelBuffer: inputBuffer)
                let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
                let result = try model.prediction(from: provider)
                guard let output = result.featureValue(for: "enhanced")?.imageBufferValue else {
                    throw DeepLPFError.noImageOutput
                }
                let ciImage = CIImage(cvPixelBuffer: output)
                let context = CIContext(options: [.cacheIntermediates: false])
                guard let outputCG = context.createCGImage(ciImage, from: ciImage.extent) else {
                    throw DeepLPFError.noImageOutput
                }
                return UIImage(cgImage: outputCG, scale: image.scale, orientation: .up)
            }
        }.value
    }

    private static func normalized(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        let reduction = min(1, maximumDimension / max(1, longestEdge))
        let width = max(32, Int((image.size.width * reduction) / 16) * 16)
        let height = max(32, Int((image.size.height * reduction) / 16) * 16)
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func pixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { throw DeepLPFError.noImageOutput }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { throw DeepLPFError.noImageOutput }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixelBuffer
    }
}

struct DeepLPFPanel: View {
    let sourceImage: UIImage?
    let isVideo: Bool
    let onApply: (UIImage) -> Void

    @State private var enhancedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ÖZEL MOTOR").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.5).foregroundStyle(deepLPFAccent)
                        Text("DeepLPF").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "wand.and.stars").font(.system(size: 19, weight: .semibold)).foregroundStyle(deepLPFAccent)
                }

                HStack(spacing: 8) {
                    filterChip("Cubic", symbol: "point.3.connected.trianglepath.dotted")
                    filterChip("Graduated", symbol: "line.3.horizontal.decrease")
                    filterChip("Elliptical", symbol: "circle.dashed")
                }

                HStack(spacing: 10) {
                    imageTile(title: "GİRİŞ", image: sourceImage)
                    imageTile(title: "DEEP LPF", image: enhancedImage)
                }
                .frame(height: 104)

                Text("DeepLPF fotoğrafı cihazda işler; internet veya ücretli API kullanmaz. Model, uyumlu boyutlarda çalışıp büyük kareleri bellek sınırı için küçültür.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)

                if isVideo {
                    Label("DeepLPF bu sürümde fotoğraflarda çalışır; video kareleri desteklenmez.", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                }

                Button(action: run) {
                    HStack(spacing: 8) {
                        if isProcessing { ProgressView().tint(.black).scaleEffect(0.85) }
                        else { Image(systemName: "sparkles") }
                        Text(isProcessing ? "Fotoğraf iyileştiriliyor…" : "DeepLPF uygula")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(deepLPFAccent, in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.black)
                }
                .disabled(isProcessing || sourceImage == nil || isVideo)
                .opacity((sourceImage == nil || isVideo) ? 0.48 : 1)

                if let enhancedImage {
                    Button { onApply(enhancedImage) } label: {
                        Label("Sonucu yeni proje olarak kullan", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(deepLPFAccent)
                    }
                }
            }
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .alert("DeepLPF", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func filterChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity).frame(height: 27)
            .background(Color.white.opacity(0.075), in: Capsule())
            .foregroundStyle(.white.opacity(0.82))
    }

    private func imageTile(title: String, image: UIImage?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.055))
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: isVideo ? "video" : "photo").foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).padding(6)
                .background(.black.opacity(0.65), in: Capsule()).padding(6)
        }
        .frame(maxWidth: .infinity).clipped()
    }

    private func run() {
        guard let sourceImage, !isVideo else { return }
        isProcessing = true
        Task {
            do { enhancedImage = try await DeepLPFModel.enhance(sourceImage) }
            catch { errorMessage = error.localizedDescription }
            isProcessing = false
        }
    }
}
