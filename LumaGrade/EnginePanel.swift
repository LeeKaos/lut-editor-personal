import SwiftUI
import CoreML
import CoreImage
import Vision
import UniformTypeIdentifiers
import UIKit

private let engineAccent = Color(red: 0.66, green: 1.0, blue: 0.16)

private enum EngineMode: String, CaseIterable, Identifiable {
    case zeroDCE, mirnet, faceRestore, realESRGAN

    var id: String { rawValue }
    var title: String {
        switch self {
        case .zeroDCE: "Zero-DCE"
        case .mirnet: "MIRNet"
        case .faceRestore: "GFPGAN"
        case .realESRGAN: "Real-ESRGAN"
        }
    }
    var symbol: String {
        switch self {
        case .zeroDCE: "sun.max"
        case .mirnet: "camera.macro"
        case .faceRestore: "person.crop.square"
        case .realESRGAN: "arrow.up.left.and.arrow.down.right"
        }
    }
    var description: String {
        switch self {
        case .zeroDCE: "Düşük ışıkta parlaklık ve tonları yerel olarak iyileştirir."
        case .mirnet: "Gürültü azaltma ve görüntü iyileştirme için. MIRNet uyumlu Core ML modeli gerekir."
        case .faceRestore: "Yüz ayrıntılarını onarmaya odaklanır. Yüz işleme modeli gerekir."
        case .realESRGAN: "Fotoğraf ayrıntılarını geliştirip yüksek çözünürlüğe büyütür."
        }
    }
    var modelFileName: String { "\(id).mlmodelc" }
}

private enum EngineModelStore {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EngineModels", isDirectory: true)
    }
    static func modelURL(for mode: EngineMode) -> URL? {
        let url = directory.appendingPathComponent(mode.modelFileName, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static func install(from source: URL, for mode: EngineMode) async throws {
        let hasScope = source.startAccessingSecurityScopedResource()
        defer { if hasScope { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(source.pathExtension)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        let compiled = try await Task.detached(priority: .userInitiated) {
            try MLModel.compileModel(at: staging)
        }.value
        let destination = directory.appendingPathComponent(mode.modelFileName, isDirectory: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: compiled, to: destination)
        // Loading once during install catches corrupt or unsupported model packages before use.
        _ = try MLModel(contentsOf: destination, configuration: MLModelConfiguration())
    }
}

private protocol EngineProvider {
    var mode: EngineMode { get }
    func process(_ image: UIImage) async throws -> UIImage
}

private struct VisionCoreMLProvider: EngineProvider {
    let mode: EngineMode

    func process(_ image: UIImage) async throws -> UIImage {
        guard let modelURL = EngineModelStore.modelURL(for: mode) else {
            throw EngineError.modelMissing(mode.title)
        }
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                let visionModel = try VNCoreMLModel(for: model)
                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .scaleFit
                let normalized = Self.normalizedImage(image, maximumDimension: 1536)
                guard let cgImage = normalized.cgImage else { throw EngineError.invalidImage }
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                guard let pixelBuffer = request.results?.compactMap({ ($0 as? VNPixelBufferObservation)?.pixelBuffer }).first else {
                    throw EngineError.incompatibleModel
                }
                let output = CIImage(cvPixelBuffer: pixelBuffer)
                guard let rendered = CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent) else {
                    throw EngineError.invalidImage
                }
                return UIImage(cgImage: rendered, scale: image.scale, orientation: .up)
            }
        }.value
    }

    private static func normalizedImage(_ image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let oriented: UIImage
        if image.imageOrientation == .up { oriented = image }
        else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            oriented = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        }
        let longest = max(oriented.size.width, oriented.size.height)
        guard longest > maximumDimension else { return oriented }
        let scale = maximumDimension / longest
        let size = CGSize(width: floor(oriented.size.width * scale), height: floor(oriented.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in oriented.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

private enum EngineError: LocalizedError {
    case modelMissing(String), incompatibleModel, invalidImage
    var errorDescription: String? {
        switch self {
        case .modelMissing(let name): return "\(name) Core ML modeli henüz eklenmedi. Bu işlem için uyumlu bir .mlmodel veya .mlpackage dosyası yükleyin."
        case .incompatibleModel: return "Bu model görüntüden görüntüye çıktı vermiyor veya Vision ile uyumlu giriş/çıkış kullanmıyor."
        case .invalidImage: return "Görüntü güvenli biçimde okunamadı."
        }
    }
}

struct EnginePanel: View {
    let sourceImage: UIImage?
    let isVideo: Bool
    let onApply: (UIImage) -> Void

    @State private var selectedMode: EngineMode = .zeroDCE
    @State private var resultImage: UIImage?
    @State private var isProcessing = false
    @State private var isInstalling = false
    @State private var showingImporter = false
    @State private var alertMessage: String?
    @State private var installedModes = Set<EngineMode>()

    private var selectedImage: UIImage? { resultImage ?? sourceImage }
    private var modelAvailable: Bool { installedModes.contains(selectedMode) }
    private var modelContentType: UTType {
        UTType(filenameExtension: "mlpackage") ?? .package
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ON-DEVICE ENGINE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.7).foregroundStyle(engineAccent)
                        Text("Görüntü motorları").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "cpu").font(.system(size: 18, weight: .semibold)).foregroundStyle(engineAccent)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(EngineMode.allCases) { mode in
                            Button { selectedMode = mode } label: {
                                Label(mode.title, systemImage: mode.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(selectedMode == mode ? engineAccent : Color.white.opacity(0.09), in: Capsule())
                                    .foregroundStyle(selectedMode == mode ? .black : .white)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 12) {
                    previewTile(title: resultImage == nil ? "GİRİŞ" : "SONUÇ", image: selectedImage)
                    if resultImage != nil { previewTile(title: "ÖNCE", image: sourceImage) }
                }
                .frame(height: 112)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selectedMode.symbol).foregroundStyle(engineAccent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(selectedMode.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            Spacer()
                            Label(modelAvailable ? "Hazır" : "Model gerekli", systemImage: modelAvailable ? "checkmark.circle.fill" : "arrow.down.circle")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(modelAvailable ? engineAccent : .white.opacity(0.55))
                        }
                        Text(selectedMode.description).font(.system(size: 10)).foregroundStyle(.white.opacity(0.66)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))

                HStack(spacing: 9) {
                    Button { showingImporter = true } label: {
                        Label(modelAvailable ? "Modeli değiştir" : "Core ML modeli ekle", systemImage: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 42)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .disabled(isProcessing || isInstalling)

                    Button(action: run) {
                        HStack(spacing: 7) {
                            if isProcessing { ProgressView().tint(.black).scaleEffect(0.8) }
                            else { Image(systemName: "sparkles") }
                            Text(isProcessing ? "İşleniyor" : "Motoru çalıştır")
                        }
                        .font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity).frame(height: 42)
                        .background(engineAccent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                    }
                    .disabled(isProcessing || isInstalling || !modelAvailable || sourceImage == nil || isVideo)
                    .opacity((!modelAvailable || sourceImage == nil || isVideo) ? 0.5 : 1)
                }

                if isInstalling {
                    HStack(spacing: 8) { ProgressView().tint(engineAccent); Text("Model doğrulanıp cihaza hazırlanıyor…") }
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.75))
                } else if isVideo {
                    Label("Bu sürüm Engine modellerini fotoğraflarda çalıştırır. Video kare işleme ayrıca hazırlanmalı.", systemImage: "info.circle")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                } else if !modelAvailable {
                    Text("Model dosyaları uygulamaya gömülü değil; depolama alanını ve kurulum süresini artırmamak için seçtiğiniz Core ML modelini burada içe aktarın. İşlem tamamen cihazda yapılır.")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                }

                if resultImage != nil {
                    Button { if let resultImage { onApply(resultImage) } } label: {
                        Label("Sonucu yeni proje olarak kullan", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(engineAccent)
                    }
                }
            }
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType(filenameExtension: "mlmodel") ?? .data, modelContentType], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            isInstalling = true
            Task {
                do {
                    try await EngineModelStore.install(from: url, for: selectedMode)
                    installedModes.insert(selectedMode)
                    alertMessage = "\(selectedMode.title) modeli yüklendi ve doğrulandı."
                } catch {
                    alertMessage = "Model eklenemedi: \(error.localizedDescription)"
                }
                isInstalling = false
            }
        }
        .task { refreshInstalledModes() }
        .alert("Engine", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("Tamam", role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
    }

    private func previewTile(title: String, image: UIImage?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.055))
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: isVideo ? "video" : "photo").font(.system(size: 20)).foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.8).padding(6)
                .background(.black.opacity(0.65), in: Capsule()).padding(7)
        }
        .frame(maxWidth: .infinity).clipped()
    }

    private func refreshInstalledModes() {
        installedModes = Set(EngineMode.allCases.filter { EngineModelStore.modelURL(for: $0) != nil })
    }

    private func run() {
        guard let sourceImage, modelAvailable else { return }
        isProcessing = true
        Task {
            do {
                resultImage = try await VisionCoreMLProvider(mode: selectedMode).process(sourceImage)
            } catch {
                alertMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}
