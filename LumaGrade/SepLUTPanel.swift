import SwiftUI
import CoreML
import CoreImage
import CoreVideo
import UIKit

private let sepLUTAccent = Color(red: 0.66, green: 1.0, blue: 0.16)
private let sepLUTSize = 17

private enum SepLUTError: LocalizedError {
    case modelMissing
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing: "SepLUT modeli uygulama paketinde bulunamadı."
        case .invalidOutput: "SepLUT geçerli bir renk tablosu üretemedi."
        }
    }
}

private struct SepLUTPrediction {
    let oneD: [Float]
    let threeD: [Float]

    func cube(intensity: Double = 1) -> CubeLUT {
        let size = sepLUTSize
        let strength = Float(min(1, max(0, intensity)))
        var rgb = [Float](repeating: 0, count: size * size * size * 3)

        func sample1D(_ channel: Int, _ value: Float) -> Float {
            let position = min(Float(size - 1), max(0, value)) * Float(size - 1)
            let lower = Int(position)
            let upper = min(size - 1, lower + 1)
            let fraction = position - Float(lower)
            return oneD[channel * size + lower] * (1 - fraction) + oneD[channel * size + upper] * fraction
        }

        func sample3D(_ channel: Int, _ red: Float, _ green: Float, _ blue: Float) -> Float {
            let r = min(Float(size - 1), max(0, red)) * Float(size - 1)
            let g = min(Float(size - 1), max(0, green)) * Float(size - 1)
            let b = min(Float(size - 1), max(0, blue)) * Float(size - 1)
            let r0 = Int(r), g0 = Int(g), b0 = Int(b)
            let r1 = min(size - 1, r0 + 1), g1 = min(size - 1, g0 + 1), b1 = min(size - 1, b0 + 1)
            let fr = r - Float(r0), fg = g - Float(g0), fb = b - Float(b0)

            func value(_ ri: Int, _ gi: Int, _ bi: Int) -> Float {
                threeD[((channel * size + bi) * size + gi) * size + ri]
            }
            func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

            let z0 = mix(mix(value(r0, g0, b0), value(r1, g0, b0), fr), mix(value(r0, g1, b0), value(r1, g1, b0), fr), fg)
            let z1 = mix(mix(value(r0, g0, b1), value(r1, g0, b1), fr), mix(value(r0, g1, b1), value(r1, g1, b1), fr), fg)
            return mix(z0, z1, fb)
        }

        // SepLUT cascades independent 1D curves into its 3D table. Fuse both
        // into one 17³ cube so full-resolution images need only one CIColorCube.
        for blueIndex in 0..<size {
            for greenIndex in 0..<size {
                for redIndex in 0..<size {
                    let input = [Float(redIndex), Float(greenIndex), Float(blueIndex)].map { $0 / Float(size - 1) }
                    let after1D = (0..<3).map { sample1D($0, input[$0]) }
                    let offset = ((blueIndex * size + greenIndex) * size + redIndex) * 3
                    for channel in 0..<3 {
                        let enhanced = sample3D(channel, after1D[0], after1D[1], after1D[2])
                        rgb[offset + channel] = input[channel] * (1 - strength) + enhanced * strength
                    }
                }
            }
        }
        return CubeLUT(dimension: size, values: rgb)
    }
}

private enum SepLUTCoreML {
    private static let inputSize = 256

    static var compiledModelURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SepLUT", isDirectory: true)
            .appendingPathComponent("SepLUT.mlmodelc", isDirectory: true)
    }

    static func generate(from image: UIImage, sourceLUT: CubeLUT?) async throws -> SepLUTPrediction {
        let modelURL = try await prepare()
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                guard let source = CIImage(image: image) else { throw SepLUTError.invalidOutput }
                let neutralSettings = GradeSettings()
                let displayImage = ImageRenderer.grade(source, settings: neutralSettings, lut: nil, sourceLUT: sourceLUT)
                let extent = displayImage.extent
                guard extent.width > 0, extent.height > 0 else { throw SepLUTError.invalidOutput }
                let scaled = displayImage.transformed(by: CGAffineTransform(
                    scaleX: CGFloat(inputSize) / extent.width,
                    y: CGFloat(inputSize) / extent.height
                ))
                let target = CGRect(x: 0, y: 0, width: inputSize, height: inputSize)
                let normalized = scaled.transformed(by: CGAffineTransform(
                    translationX: -scaled.extent.minX,
                    y: -scaled.extent.minY
                )).cropped(to: target)
                guard let cgImage = ImageRenderer.context.createCGImage(normalized, from: target) else {
                    throw SepLUTError.invalidOutput
                }
                let inputBuffer = try pixelBuffer(from: cgImage)
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                let input = MLFeatureValue(pixelBuffer: inputBuffer)
                let provider = try MLDictionaryFeatureProvider(dictionary: ["image": input])
                let result = try model.prediction(from: provider)
                guard let oneD = result.featureValue(for: "lut1d")?.multiArrayValue,
                      let threeD = result.featureValue(for: "lut3d")?.multiArrayValue else {
                    throw SepLUTError.invalidOutput
                }

                var oneDValues = [Float](repeating: 0, count: 3 * sepLUTSize)
                for channel in 0..<3 {
                    for index in 0..<sepLUTSize {
                        let indices = [NSNumber(value: 0), NSNumber(value: channel), NSNumber(value: index)]
                        oneDValues[channel * sepLUTSize + index] = oneD[indices].floatValue
                    }
                }
                var threeDValues = [Float](repeating: 0, count: 3 * sepLUTSize * sepLUTSize * sepLUTSize)
                for channel in 0..<3 {
                    for blue in 0..<sepLUTSize {
                        for green in 0..<sepLUTSize {
                            for red in 0..<sepLUTSize {
                                let offset = ((channel * sepLUTSize + blue) * sepLUTSize + green) * sepLUTSize + red
                                let indices = [NSNumber(value: 0), NSNumber(value: channel), NSNumber(value: blue), NSNumber(value: green), NSNumber(value: red)]
                                threeDValues[offset] = threeD[indices].floatValue
                            }
                        }
                    }
                }
                guard oneDValues.allSatisfy(\.isFinite), threeDValues.allSatisfy(\.isFinite) else {
                    throw SepLUTError.invalidOutput
                }
                return SepLUTPrediction(oneD: oneDValues, threeD: threeDValues)
            }
        }.value
    }

    private static func prepare() async throws -> URL {
        if FileManager.default.fileExists(atPath: compiledModelURL.path) { return compiledModelURL }
        guard let package = Bundle.main.resourceURL?
            .appendingPathComponent("SepLUTModels", isDirectory: true)
            .appendingPathComponent("SepLUT.mlpackage", isDirectory: true),
              FileManager.default.fileExists(atPath: package.path) else { throw SepLUTError.modelMissing }
        return try await Task.detached(priority: .userInitiated) {
            let compiled = try MLModel.compileModel(at: package)
            let directory = compiledModelURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: compiledModelURL)
            try FileManager.default.moveItem(at: compiled, to: compiledModelURL)
            return compiledModelURL
        }.value
    }

    private static func pixelBuffer(from image: CGImage) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, inputSize, inputSize, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw SepLUTError.invalidOutput }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base,
                width: inputSize,
                height: inputSize,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { throw SepLUTError.invalidOutput }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: inputSize, height: inputSize))
        return buffer
    }
}

struct SepLUTPanel: View {
    let sourceImage: UIImage?
    let isVideo: Bool
    let settings: GradeSettings
    let sourceLUT: CubeLUT?
    let onApply: (CubeLUT, Double) -> Void

    @State private var prediction: SepLUTPrediction?
    @State private var outputPreview: UIImage?
    @State private var intensity = 100.0
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("IMAGE-ADAPTIVE COLOR").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2).foregroundStyle(sepLUTAccent)
                        Text("SepLUT").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "cube.transparent").font(.system(size: 19, weight: .semibold)).foregroundStyle(sepLUTAccent)
                }

                HStack(spacing: 8) {
                    chip("Öğrenilmiş 1D", symbol: "line.3.horizontal.decrease")
                    chip("Öğrenilmiş 3D", symbol: "cube")
                    chip("Cihaz içi", symbol: "iphone")
                }

                HStack(spacing: 10) {
                    imageTile(title: "GİRİŞ", image: sourceImage)
                    imageTile(title: "SEPLUT", image: outputPreview)
                }
                .frame(height: previewTileHeight)

                Text("SepLUT küçük bir önizlemeden içeriğe özel 1D/3D LUT üretir. CNN küçük girdide çalışır; renk tablosu görüntünün tam çözünürlüğüne Core Image ile uygulanır.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)

                if isVideo {
                    Label("Bu SepLUT aracı fotoğraf projelerinde çalışır.", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                }

                Button(action: run) {
                    HStack(spacing: 8) {
                        if isProcessing { ProgressView().tint(.black).scaleEffect(0.85) }
                        else { Image(systemName: "sparkles") }
                        Text(isProcessing ? "Uyarlanabilir LUT üretiliyor…" : "SepLUT üret")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(sepLUTAccent, in: RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.black)
                }
                .disabled(isProcessing || sourceImage == nil || isVideo)
                .opacity((sourceImage == nil || isVideo) ? 0.48 : 1)

                if prediction != nil {
                    VStack(spacing: 5) {
                        HStack {
                            Text("Yoğunluk").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            Text("\(Int(intensity))%").font(.system(size: 11, weight: .semibold)).foregroundStyle(sepLUTAccent)
                        }
                        Slider(value: $intensity, in: 0...100, step: 1).tint(sepLUTAccent)
                    }
                    Button { if let prediction { onApply(prediction.cube(), intensity) } } label: {
                        Label("SepLUT'u projeye uygula", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(sepLUTAccent)
                    }
                }
            }
            .padding(.vertical, 7)
        }
        .scrollIndicators(.hidden)
        .onChange(of: intensity) { _, _ in updatePreview() }
        .alert("SepLUT", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func chip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 8, weight: .semibold)).lineLimit(1)
            .frame(maxWidth: .infinity).frame(height: 27)
            .background(Color.white.opacity(0.075), in: Capsule()).foregroundStyle(.white.opacity(0.82))
    }

    private func imageTile(title: String, image: UIImage?) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.055))
            if let image {
                // Fit the whole frame inside each card. Fill crops most of a
                // portrait 9:16 image when two previews share the available width.
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: isVideo ? "video" : "photo").foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(title).font(.system(size: 8, weight: .bold)).tracking(0.7).padding(6)
                .background(.black.opacity(0.65), in: Capsule()).padding(6)
        }
        .frame(maxWidth: .infinity).clipped()
    }

    private var previewTileHeight: CGFloat {
        guard let image = sourceImage else { return 104 }
        let width = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let height = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        return width > 0 && height / width > 1.25 ? 168 : 104
    }

    private func run() {
        guard let sourceImage, !isVideo else { return }
        isProcessing = true
        Task {
            do {
                prediction = try await SepLUTCoreML.generate(from: sourceImage, sourceLUT: sourceLUT)
                updatePreview()
            } catch { errorMessage = error.localizedDescription }
            isProcessing = false
        }
    }

    private func updatePreview() {
        guard let sourceImage, let prediction else { return }
        let currentIntensity = intensity
        var previewSettings = settings
        previewSettings.intensity = currentIntensity
        Task {
            outputPreview = try await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    let reduced = Self.previewImage(sourceImage, maxDimension: 960)
                    return ImageRenderer.grade(reduced, settings: previewSettings, lut: prediction.cube(), sourceLUT: sourceLUT)
                }
            }.value
        }
    }

    nonisolated private static func previewImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let scale = min(1, maxDimension / max(1, max(pixelWidth, pixelHeight)))
        let size = CGSize(width: max(1, pixelWidth * scale), height: max(1, pixelHeight * scale))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
