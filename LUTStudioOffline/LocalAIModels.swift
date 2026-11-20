import Combine
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
            try Self.loadModel(at: destination)
        }.value

        models[kind] = model
        loadedKinds.insert(kind)
        modelNames[kind] = source.deletingPathExtension().lastPathComponent
    }

    func loadInstalledModels() async {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalAIModels", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        for kind in LocalAIModelKind.allCases {
            guard let url = files.first(where: {
                $0.deletingPathExtension().lastPathComponent == kind.rawValue
            }) else { continue }
            do {
                let model = try await Task.detached(priority: .utility) {
                    try Self.loadModel(at: url)
                }.value
                models[kind] = model
                loadedKinds.insert(kind)
                modelNames[kind] = url.deletingPathExtension().lastPathComponent
            } catch {
                modelNames[kind] = "Yüklenemedi: \(error.localizedDescription)"
            }
        }
    }

    private nonisolated static func loadModel(at url: URL) throws -> MLModel {
        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try MLModel.compileModel(at: url)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
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

    private nonisolated static func copyModelToApplicationSupport(_ source: URL, kind: LocalAIModelKind) throws -> URL {
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
        if kind == .codeFormer {
            return try restoreDetectedFaces(model: model, image: image)
        }
        return try upscaleInTiles(model: model, image: image)
    }

    private nonisolated static func upscaleInTiles(model: MLModel, image: CGImage) throws -> CGImage {
        let descriptions = model.modelDescription.inputDescriptionsByName
        guard let description = descriptions.values.first(where: {
            $0.type == .image || $0.type == .multiArray
        }) else { throw LocalAIError.incompatibleModel("Real-ESRGAN giriş tensörü bulunamadı.") }

        let tileWidth: Int
        let tileHeight: Int
        if let constraint = description.imageConstraint {
            tileWidth = constraint.pixelsWide
            tileHeight = constraint.pixelsHigh
        } else if let constraint = description.multiArrayConstraint {
            let shape = constraint.shape.map(\.intValue)
            guard shape.count >= 3 else { throw LocalAIError.incompatibleModel("Real-ESRGAN giriş boyutu desteklenmiyor.") }
            let channelFirst = shape.count == 4 ? shape[1] == 3 : shape[0] == 3
            tileHeight = shape.count == 4 ? (channelFirst ? shape[2] : shape[1]) : (channelFirst ? shape[1] : shape[0])
            tileWidth = shape.count == 4 ? (channelFirst ? shape[3] : shape[2]) : (channelFirst ? shape[2] : shape[1])
        } else {
            throw LocalAIError.incompatibleModel("Real-ESRGAN giriş biçimi desteklenmiyor.")
        }
        guard tileWidth > 0, tileHeight > 0 else { throw LocalAIError.incompatibleModel("Model giriş ölçüleri geçersiz.") }

        let source = CIImage(cgImage: image)
        let width = Int(source.extent.width)
        let height = Int(source.extent.height)
        let overlapX = min(16, max(0, tileWidth / 8))
        let overlapY = min(16, max(0, tileHeight / 8))
        let xs = tileOrigins(length: width, tile: tileWidth, overlap: overlapX)
        let ys = tileOrigins(length: height, tile: tileHeight, overlap: overlapY)
        let context = CIContext(options: [.cacheIntermediates: false])
        var canvas: CIImage?
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1

        for row in ys.indices {
            for column in xs.indices {
                let x = xs[column]
                let y = ys[row]
                let tileRect = CGRect(x: x, y: y, width: tileWidth, height: tileHeight)
                let tile = source.clampedToExtent().cropped(to: tileRect)
                guard let tileCG = context.createCGImage(tile, from: tileRect) else {
                    throw LocalAIError.invalidImage
                }
                let outputCG = try predictSingle(model: model, image: tileCG, kind: .realESRGAN)
                scaleX = CGFloat(outputCG.width) / CGFloat(tileWidth)
                scaleY = CGFloat(outputCG.height) / CGFloat(tileHeight)

                let left = column == 0 ? 0 : (xs[column - 1] + tileWidth + x) / 2
                let right = column == xs.count - 1 ? width : (x + tileWidth + xs[column + 1]) / 2
                let bottom = row == 0 ? 0 : (ys[row - 1] + tileHeight + y) / 2
                let top = row == ys.count - 1 ? height : (y + tileHeight + ys[row + 1]) / 2
                let localCrop = CGRect(x: CGFloat(left - x) * scaleX,
                                       y: CGFloat(bottom - y) * scaleY,
                                       width: CGFloat(right - left) * scaleX,
                                       height: CGFloat(top - bottom) * scaleY)
                let placed = CIImage(cgImage: outputCG)
                    .cropped(to: localCrop)
                    .transformed(by: CGAffineTransform(translationX: CGFloat(left) * scaleX - localCrop.minX,
                                                       y: CGFloat(bottom) * scaleY - localCrop.minY))
                let outputBounds = CGRect(x: 0, y: 0, width: CGFloat(width) * scaleX,
                                          height: CGFloat(height) * scaleY)
                let base = canvas ?? CIImage(color: .clear).cropped(to: outputBounds)
                canvas = placed.composited(over: base)
            }
        }
        guard let result = canvas,
              let output = context.createCGImage(result, from: result.extent) else {
            throw LocalAIError.invalidModelOutput
        }
        return output
    }

    private nonisolated static func tileOrigins(length: Int, tile: Int, overlap: Int) -> [Int] {
        guard length > tile else { return [0] }
        let stride = max(1, tile - overlap * 2)
        var origins = Array(Swift.stride(from: 0, to: max(1, length - tile + 1), by: stride))
        let last = length - tile
        if origins.last != last { origins.append(last) }
        return origins
    }

    private nonisolated static func restoreDetectedFaces(model: MLModel, image: CGImage) throws -> CGImage {
        let request = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let faces = request.results, !faces.isEmpty else {
            throw LocalAIError.noFaceDetected
        }

        let source = CIImage(cgImage: image)
        let imageBounds = source.extent
        var composed = source
        let context = CIContext(options: [.cacheIntermediates: false])

        for face in faces {
            let box = face.boundingBox
            let faceRect = CGRect(x: box.minX * imageBounds.width,
                                  y: box.minY * imageBounds.height,
                                  width: box.width * imageBounds.width,
                                  height: box.height * imageBounds.height)
            let side = min(max(faceRect.width, faceRect.height) * 1.8,
                           min(imageBounds.width, imageBounds.height))
            let center = CGPoint(x: faceRect.midX, y: faceRect.midY)
            let cropRect = CGRect(x: center.x - side / 2, y: center.y - side / 2,
                                  width: side, height: side).intersection(imageBounds)
            guard cropRect.width > 8, cropRect.height > 8,
                  let cropCG = context.createCGImage(source.cropped(to: cropRect), from: cropRect) else {
                continue
            }

            let restoredCG = try predictSingle(model: model, image: cropCG, kind: .codeFormer)
            let restored = CIImage(cgImage: restoredCG)
                .transformed(by: CGAffineTransform(scaleX: cropRect.width / CGFloat(restoredCG.width),
                                                   y: cropRect.height / CGFloat(restoredCG.height)))
                .transformed(by: CGAffineTransform(translationX: cropRect.minX, y: cropRect.minY))
                .cropped(to: cropRect)
            let originalCrop = source.cropped(to: cropRect)
            let mask = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: cropRect.midX, y: cropRect.midY),
                "inputRadius0": min(cropRect.width, cropRect.height) * 0.18,
                "inputRadius1": max(cropRect.width, cropRect.height) * 0.58,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.clear
            ])?.outputImage?.cropped(to: cropRect)
            if let mask, let blend = CIFilter(name: "CIBlendWithMask") {
                blend.setValue(restored, forKey: kCIInputImageKey)
                blend.setValue(originalCrop, forKey: kCIInputBackgroundImageKey)
                blend.setValue(mask, forKey: kCIInputMaskImageKey)
                composed = (blend.outputImage ?? restored).composited(over: composed)
            } else {
                composed = restored.composited(over: composed)
            }
        }

        guard let result = context.createCGImage(composed.cropped(to: imageBounds), from: imageBounds) else {
            throw LocalAIError.invalidModelOutput
        }
        return result
    }

    private nonisolated static func predictSingle(model: MLModel, image: CGImage, kind: LocalAIModelKind) throws -> CGImage {
        let source = CIImage(cgImage: image)
        let inputDescriptions = model.modelDescription.inputDescriptionsByName
        guard inputDescriptions.values.contains(where: {
            $0.type == .image || $0.type == .multiArray
        }) else {
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
                                                                            dataType: constraint.dataType, kind: kind))
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
                let outputImage = try ciImage(from: array, kind: kind)
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
                                               dataType: MLMultiArrayDataType, kind: LocalAIModelKind) throws -> MLMultiArray {
        guard shape.count >= 3 else { throw LocalAIError.incompatibleModel("Tensor boyutu desteklenmiyor.") }
        let channelFirst = shape.count == 4 ? shape[1] == 3 : shape[0] == 3
        let height = shape.count == 4 ? (channelFirst ? shape[2] : shape[1]) : (channelFirst ? shape[1] : shape[0])
        let width = shape.count == 4 ? (channelFirst ? shape[3] : shape[2]) : (channelFirst ? shape[2] : shape[1])
        let channels = shape.count == 4 ? (channelFirst ? shape[1] : shape[3]) : (channelFirst ? shape[0] : shape[2])
        guard channels >= 3, width > 0, height > 0 else {
            throw LocalAIError.incompatibleModel("Model RGB tensor biçiminde değil.")
        }
        let array = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: dataType)
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
                    let normalized = kind == .codeFormer ? rgb[channel] * 2 - 1 : rgb[channel]
                    array[indices] = NSNumber(value: normalized)
                }
            }
        }
        return array
    }

    private nonisolated static func ciImage(from array: MLMultiArray, kind: LocalAIModelKind) throws -> CIImage {
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
                    let value: Float = kind == .codeFormer ? (raw + 1) / 2 : (raw > 1.5 ? raw / 255 : raw)
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
    case noFaceDetected

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
        case .noFaceDetected:
            return "Fotoğrafta CodeFormer için uygun bir yüz algılanamadı."
        }
    }
}
