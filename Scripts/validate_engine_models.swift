import CoreImage
import CoreML
import CoreVideo
import Foundation
import Vision

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let modelNames = ["ZeroDCE", "MIRNetv2LowLightEnhancement", "GFPGAN", "RealESRGAN"]
let extent = CGRect(x: 0, y: 0, width: 512, height: 512)
let context = CIContext(options: [.cacheIntermediates: false])
let sample = CIImage(color: CIColor(red: 0.18, green: 0.2, blue: 0.24)).cropped(to: extent)
guard let cgImage = context.createCGImage(sample, from: extent) else {
    fatalError("Could not create validation image")
}

for name in modelNames {
    let candidates = [
        directory.appendingPathComponent(name).appendingPathExtension("mlmodel"),
        directory.appendingPathComponent(name).appendingPathExtension("mlpackage"),
    ]
    guard let modelURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
        fatalError("Missing Core ML asset: \(name)")
    }
    try autoreleasepool {
        let compiledURL = try MLModel.compileModel(at: modelURL)
        defer { try? FileManager.default.removeItem(at: compiledURL) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        let visionModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard let output = request.results?.compactMap({ ($0 as? VNPixelBufferObservation)?.pixelBuffer }).first,
              CVPixelBufferGetWidth(output) > 0,
              CVPixelBufferGetHeight(output) > 0 else {
            throw NSError(domain: "EngineModelValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "No image output for \(name)"])
        }
        print("Vision inference passed: \(name), \(CVPixelBufferGetWidth(output))x\(CVPixelBufferGetHeight(output))")
    }
}
