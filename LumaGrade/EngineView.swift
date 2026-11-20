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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header
                engineChoice
                preview
                if let analysis = viewModel.analysis {
                    analysisCard(analysis)
                }
                actionRow
                optionalModules
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ENGINE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(engineAccent)
                Text("Görüntünü cihazda işle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Label("ÇEVRİMDIŞI", systemImage: "cpu")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(engineAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(engineAccent.opacity(0.1), in: Capsule())
        }
    }

    private var engineChoice: some View {
        Button {
            viewModel.selectBlendedAutoEngine()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(engineAccent, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Harmanlanmış Auto Engine")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Vision + Core Image + mevcut LUT ve ayarlar")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: viewModel.selectedEngine == .blendedAuto ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(engineAccent)
            }
            .padding(10)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(engineAccent.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Harmanlanmış Auto Engine seç")
    }

    private var preview: some View {
        HStack(spacing: 8) {
            previewCard(title: "ÖNCE", image: inputImage, placeholder: "Medya seçilmedi")
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(engineAccent)
            previewCard(title: "SONRA", image: viewModel.generatedImage, placeholder: "İşlem sonrası önizleme")
        }
        .frame(height: 100)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: runEngine) {
                HStack(spacing: 7) {
                    if viewModel.isProcessing {
                        ProgressView().tint(.black).scaleEffect(0.8)
                        Text("İşleniyor…")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Otomatik düzenle")
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(engineAccent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(inputImage == nil || viewModel.isProcessing)

            if let result = viewModel.result {
                Button {
                    onApplySettings(result.editStack.outputSettings)
                } label: {
                    Label("Projeye uygula", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 40)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var optionalModules: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("İSTEĞE BAĞLI MODÜLLER")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.5))
            moduleRow(
                title: "GPUImage özel efektleri",
                detail: "Yalnızca GPU efekti seçildiğinde çalışır",
                symbol: "cpu",
                available: EngineOptionalModules.gpuImage.isAvailable,
                reason: EngineOptionalModules.gpuImage.unavailableReason
            )
            moduleRow(
                title: "Derin Detay / Core ML",
                detail: "Varsayılan kapalı · yerel model gerektirir",
                symbol: "viewfinder",
                available: EngineOptionalModules.deepDetail.isAvailable,
                reason: EngineOptionalModules.deepDetail.unavailableReason
            )
            moduleRow(
                title: "Inpainting",
                detail: "Varsayılan kapalı · model ve maske aracı gerektirir",
                symbol: "eraser",
                available: EngineOptionalModules.inpainting.isAvailable,
                reason: EngineOptionalModules.inpainting.unavailableReason
            )
            Text("Bu modüller seçilmediği sürece hiçbir ek işlem başlatılmaz.")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }

    private func moduleRow(title: String, detail: String, symbol: String, available: Bool, reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(available ? engineAccent : .white.opacity(0.42))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(available ? 0.9 : 0.55))
                Text(available ? detail : reason)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.43))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: available ? "checkmark.circle" : "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func analysisCard(_ analysis: EngineSceneAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("\(analysis.scene.title) sahne", systemImage: analysis.scene.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(engineAccent)
                Spacer()
                Text("Vision")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            if !analysis.labels.isEmpty {
                Text(analysis.labels.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.67))
                    .lineLimit(2)
            }
            if let result = viewModel.result {
                ForEach(result.editStack.steps) { step in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(engineAccent)
                        Text(step.title)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.62))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private func previewCard(title: String, image: UIImage?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.6))
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").font(.system(size: 15))
                        Text(placeholder).font(.system(size: 8)).lineLimit(1)
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
        viewModel.runBlendedAutoEngine(
            image: inputImage,
            settings: settings,
            lut: lut,
            sourceLUT: sourceLUT,
            isVideo: isVideo
        )
    }

    private var engineAccent: Color { Color(red: 0.66, green: 1, blue: 0.16) }
}
