import SwiftUI
import UIKit

struct EngineView: View {
    @ObservedObject var viewModel: EngineViewModel
    let inputImage: UIImage?
    let settings: GradeSettings
    let lut: CubeLUT?
    let sourceLUT: CubeLUT?
    let isVideo: Bool
    let onApplySettings: (GradeSettings) -> Void

    @State private var pendingSettings: GradeSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI ENGINE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Spacer()
                Label("ON-DEVICE", systemImage: "cpu")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Color(red: 0.66, green: 1.0, blue: 0.16))
            }

            HStack(spacing: 9) {
                previewCard(title: "LOG INPUT", image: inputImage, placeholder: "Fotoğraf / video karesi")
                previewCard(title: "ENGINE RESULT", image: viewModel.generatedImage, placeholder: "Sonuç burada görünecek")
            }
            .frame(height: 88)

            HStack(spacing: 8) {
                Button(action: runEngine) {
                    HStack(spacing: 7) {
                        if viewModel.isProcessing {
                            ProgressView().tint(.black).scaleEffect(0.8)
                            Text("İşleniyor…")
                        } else {
                            Image(systemName: "sparkles")
                            Text("Run Engine")
                        }
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Color(red: 0.66, green: 1.0, blue: 0.16), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(inputImage == nil || viewModel.isProcessing)

                if viewModel.generatedImage != nil, let pendingSettings {
                    Button {
                        onApplySettings(pendingSettings)
                    } label: {
                        Label("Projeye uygula", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minHeight: 40)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.smartPrompt.isEmpty {
                DisclosureGroup {
                    Text(viewModel.smartPrompt)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                } label: {
                    Label("Vision sahne analizi", systemImage: "viewfinder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .tint(Color(red: 0.66, green: 1.0, blue: 0.16))
            } else {
                Text("Vision sahneyi cihazda tanır; görüntü işleme mevcut renk motorunu kullanır.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }

            if isVideo {
                Text("Video için ilk kare analiz edilir; seçilen görünüm klibin tamamına tutarlı uygulanır.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(2)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func previewCard(title: String, image: UIImage?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.62))
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 15))
                        Text(placeholder)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.08), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(7)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func runEngine() {
        guard let inputImage else { return }
        var recipe = ImageRenderer.automaticLook(
            source: inputImage,
            lut: lut,
            lutIntensity: settings.intensity,
            sourceLUT: sourceLUT,
            style: .cinematic
        )
        recipe.autoEnhance = !isVideo
        recipe.source = settings.source
        recipe.lutName = settings.lutName
        recipe.customLUTFileName = settings.customLUTFileName
        recipe.intensity = settings.intensity
        recipe.cropAspect = settings.cropAspect
        recipe.maskEnabled = settings.maskEnabled
        recipe.maskExposure = settings.maskExposure
        recipe.maskRadius = settings.maskRadius
        recipe.maskFeather = settings.maskFeather
        recipe.trimStart = settings.trimStart
        recipe.trimEnd = settings.trimEnd
        recipe.exportCodec = settings.exportCodec
        recipe.exportResolution = settings.exportResolution
        recipe.exportBitrateMode = settings.exportBitrateMode
        recipe.exportBitrateMbps = settings.exportBitrateMbps
        let finalSettings = recipe
        pendingSettings = finalSettings

        let selectedLUT = lut
        let profileLUT = sourceLUT
        viewModel.runEngine(inputImage: inputImage) { image in
            ImageRenderer.grade(image, settings: finalSettings, lut: selectedLUT, sourceLUT: profileLUT)
        }
    }
}
