import CoreML
import CoreImage
import CoreVideo
import Foundation
import Vision
import UIKit

enum LocalAIModelKind: String, CaseIterable, Identifiable {
    case codeFormer
    case realESRGAN

    var id: String { rawValue }
    var title: String {
        switch self {
        case .codeFormer: return "CodeFormer"
        case .realESRGAN: return "Real-ESRGAN"
        }
    }
    var detail: String {
        switch self {
        case .codeFormer: return "Yüz detay restorasyonu"
        case .realESRGAN: return "Görüntü büyütme ve detay"
        }
    }
}

@MainActor
final class LocalAIModelStore: ObservableObject {
    @Published private(set) var loadedKinds: Set<LocalAIModelKind> = []
    @Published private(set) var modelNames: [LocalAIModelKind: String] = [:]
    @Published private(set) var isBusy = false

    private var models: [LocalAIModelKind: MLModel] = [:]

    func installModel(from source: URL, for kind: LocalAIModelKind) async throws {
        isBusy = true
        defer { isBusy = false }

        let didAccess = source.startAccessingSecurityScopedResource()
        defer { if didAccess { source.stopAccessingSecurityScopedResource() } }

        let destination = try Self.copyModelToApplicationSupport(source, kind: kind)
        let model = try await Task.detached(priority: .utility) {
            let compiledURL: URL
            if destination.pathExtension == "mlmodelc" {
                compiledURL = destination
            } else {
                compiledURL = try MLModel.compileModel(at: destination)
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }.value

        models[kind] = model
        loadedKinds.insert(kind)
        modelNames[kind] = source.deletingPathExtension().lastPathComponent
    }

    func enhance(_ image: UIImage, using kind: LocalAIModelKind) async throws -> UIImage {
        guard let model = models[kind] else { throw LocalAIError.modelNotInstalled(kind.title) }
        guard let cgImage = image.cgImage else { throw LocalAIError.invalidImage }
        isBusy = true
        defer { isBusy = false }

        let result = try await Task.detached(priority: .userInitiated) {
            try Self.predict(model: model, image: cgImage, kind: kind)
        }.value
        return UIImage(cgImage: result, scale: image.scale, orientation: .up)
    }

    private static func copyModelToApplicationSupport(_ source: URL, kind: LocalAIModelKind) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard ["mlpackage", "mlmodel", "mlmodelc"].contains(ext) else {
            throw LocalAIError.unsupportedModelFile
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAIModels", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(kind.rawValue).appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private nonisolated static func predict(model: MLModel, image: CGImage,
                                            kind: LocalAIModelKind) throws -> CGImage {
        let source = CIImage(cgImage: image)
        let inputDescriptions = model.modelDescription.inputDescriptionsByName
        guard let inputName = inputDescriptions.keys.sorted().first(where: {
            let type = inputDescriptions[$0]?.type
            return type == .image || type == .multiArray
        }), let inputDescription = inputDescriptions[inputName] else {
            throw LocalAIError.incompatibleModel("Modelin girişinde image veya multiArray bulunamadı.")
        }

        var features: [String: MLFeatureValue] = [:]
        for (name, description) in inputDescriptions {
            switch description.type {
            case .image:
                let constraint = description.imageConstraint
                let width = constraint?.pixelsWide ?? image.width
                let height = constraint?.pixelsHigh ?? image.height
                let buffer = try makePixelBuffer(from: source, width: width, height: height)
                features[name] = MLFeatureValue(pixelBuffer: buffer)
            case .multiArray:
                guard let constraint = description.multiArrayConstraint else { continue }
                features[name] = MLFeatureValue(multiArray: try makeTensor(from: source, shape: constraint.shape.map(\.intValue),
                                                                            dataType: constraint.dataType))
            case .double:
                let value = name.lowercased().contains("fidelity") || name.lowercased() == "w" ? 0.7 : 0.0
                features[name] = MLFeatureValue(double: value)
            case .int64:
                features[name] = MLFeatureValue(int64: 0)
            default:
                break
            }
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: features)
        let prediction = try model.prediction(from: provider)
        for outputName in model.modelDescription.outputDescriptionsByName.keys.sorted() {
            guard let output = prediction.featureValue(for: outputName) else { continue }
            if let buffer = output.imageBufferValue {
                let outputImage = CIImage(cvPixelBuffer: buffer)
                let context = CIContext(options: [.cacheIntermediates: false])
                guard let result = context.createCGImage(outputImage, from: outputImage.extent) else {
                    throw LocalAIError.invalidModelOutput
                }
                return result
            }
            if let array = output.multiArrayValue {
                let outputImage = try image(from: array)
                let context = CIContext(options: [.cacheIntermediates: false])
                guard let result = context.createCGImage(outputImage, from: outputImage.extent) else {
                    throw LocalAIError.invalidModelOutput
                }
                return result
            }
        }
        throw LocalAIError.incompatibleModel("Model çıktısı image veya RGB multiArray değil.")
    }

    private nonisolated static func makePixelBuffer(from image: CIImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { throw LocalAIError.invalidImage }
        let fitted = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / image.extent.width,
            y: CGFloat(height) / image.extent.height
        )).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        CIContext(options: [.cacheIntermediates: false]).render(
            fitted, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return buffer
    }

    private nonisolated static func makeTensor(from image: CIImage, shape: [Int],
                                               dataType: MLMultiArrayDataType) throws -> MLMultiArray {
        guard shape.count >= 3 else { throw LocalAIError.incompatibleModel("Tensor boyutu desteklenmiyor.") }
        let channelFirst = shape.count == 4 ? shape[1] == 3 : shape[0] == 3
        let height = shape.count == 4 ? (channelFirst ? shape[2] : shape[1]) : (channelFirst ? shape[1] : shape[0])
        let width = shape.count == 4 ? (channelFirst ? shape[3] : shape[2]) : (channelFirst ? shape[2] : shape[1])
        let channels = shape.count == 4 ? (channelFirst ? shape[1] : shape[3]) : (channelFirst ? shape[0] : shape[2])
        guard channels >= 3, width > 0, height > 0 else {
            throw LocalAIError.incompatibleModel("Model RGB tensor biçiminde değil.")
        }
        let array = try MLMultiArray(shape: shape.map(NSNumber.init(value:)), dataType: dataType)
        let buffer = try makePixelBuffer(from: image, width: width, height: height)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw LocalAIError.invalidImage }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                let rgb: [Float] = [Float(bytes[offset + 2]) / 255,
                                    Float(bytes[offset + 1]) / 255,
                                    Float(bytes[offset]) / 255]
                for channel in 0..<3 {
                    let indices: [NSNumber]
                    if shape.count == 4 {
                        indices = channelFirst
                            ? [0, channel as NSNumber, y as NSNumber, x as NSNumber]
                            : [0, y as NSNumber, x as NSNumber, channel as NSNumber]
                    } else {
                        indices = channelFirst
                            ? [channel as NSNumber, y as NSNumber, x as NSNumber]
                            : [y as NSNumber, x as NSNumber, channel as NSNumber]
                    }
                    array[indices] = NSNumber(value: rgb[channel])
                }
            }
        }
        return array
    }

    private nonisolated static func image(from array: MLMultiArray) throws -> CIImage {
        let shape = array.shape.map(\.intValue)
        guard shape.count >= 3 else { throw LocalAIError.invalidModelOutput }
        let channelFirst = shape.count == 4 ? shape[1] == 3 : shape[0] == 3
        let height = shape.count == 4 ? (channelFirst ? shape[2] : shape[1]) : (channelFirst ? shape[1] : shape[0])
        let width = shape.count == 4 ? (channelFirst ? shape[3] : shape[2]) : (channelFirst ? shape[2] : shape[1])
        let channels = shape.count == 4 ? (channelFirst ? shape[1] : shape[3]) : (channelFirst ? shape[0] : shape[2])
        guard channels >= 3, width > 0, height > 0 else { throw LocalAIError.invalidModelOutput }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                for channel in 0..<3 {
                    let indices: [NSNumber]
                    if shape.count == 4 {
                        indices = channelFirst
                            ? [0, channel as NSNumber, y as NSNumber, x as NSNumber]
                            : [0, y as NSNumber, x as NSNumber, channel as NSNumber]
                    } else {
                        indices = channelFirst
                            ? [channel as NSNumber, y as NSNumber, x as NSNumber]
                            : [y as NSNumber, x as NSNumber, channel as NSNumber]
                    }
                    let raw = array[indices].floatValue
                    let value = raw > 1.5 ? raw / 255 : raw
                    bytes[offset + channel] = UInt8(min(255, max(0, value * 255)))
                }
            }
        }
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8,
                                    bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true,
                                    intent: .defaultIntent) else { throw LocalAIError.invalidModelOutput }
        return CIImage(cgImage: cgImage)
    }
}

enum LocalAIError: LocalizedError {
    case unsupportedModelFile
    case modelNotInstalled(String)
    case invalidImage
    case invalidModelOutput
    case incompatibleModel(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedModelFile:
            return "Core ML modeli .mlpackage, .mlmodel veya .mlmodelc biçiminde olmalı."
        case .modelNotInstalled(let name):
            return "\(name) modeli henüz bu cihaza yüklenmedi."
        case .invalidImage:
            return "Görüntü model için hazırlanamadı."
        case .invalidModelOutput:
            return "Model geçerli bir görüntü çıktısı üretmedi."
        case .incompatibleModel(let reason):
            return reason
        }
    }
}
