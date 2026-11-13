import AVFoundation
import AVKit
import CoreImage
import ImageIO
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTab: String, CaseIterable {
    case filters = "Filters"
    case adjust = "Adjust"
    case effects = "Effects"
}

private struct LUTPreset: Identifiable, Hashable {
    let name: String
    let category: String
    let url: URL
    var id: String { url.path }
}

private enum Adjustment: String, CaseIterable, Identifiable {
    case hue = "Hue"
    case exposure = "Exposure"
    case contrast = "Contrast"
    case highlights = "Highlights"
    case shadows = "Shadows"
    case temperature = "Temperature"
    case vibrance = "Vibrance"
    case saturation = "Saturation"
    case sharpness = "Sharpness"
    case vignette = "Vignette"
    case curves = "Curves"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .hue: return "circle.lefthalf.filled"
        case .exposure: return "sun.max"
        case .contrast: return "circle.lefthalf.striped.horizontal"
        case .highlights: return "sun.max.fill"
        case .shadows: return "moon.fill"
        case .temperature: return "thermometer.medium"
        case .vibrance: return "sun.max"
        case .saturation: return "drop.fill"
        case .sharpness: return "triangle"
        case .vignette: return "viewfinder"
        case .curves: return "point.3.connected.trianglepath.dotted"
        }
    }
}

private enum FilmEffect: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case bloom = "Bloom"
    case grain = "Grain"
    case halation = "Halation"
    case softGlow = "Soft Glow"
    case lightLeak = "Light Leak"
    var id: String { rawValue }
}

private struct GradeSettings: Codable, Equatable {
    var lutURL: URL?
    var lutIntensity: Float = 1
    var hue: Float = 0
    var exposure: Float = 0
    var contrast: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var temperature: Float = 0
    var vibrance: Float = 0
    var saturation: Float = 0
    var sharpness: Float = 0
    var vignette: Float = 0
    var curves: Float = 0
    var curvePoints: [Double] = [0, 0.25, 0.5, 0.75, 1]
    var effect: FilmEffect = .none
    var effectIntensity: Float = 0.5
    var roughness: Float = 0.35
    var size: Float = 0.55
    var smartEnhance: Bool? = nil
}

private struct UserPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var settings: GradeSettings
}

enum ProjectFileStorage {
    static var projectsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
    }

    static func keepImportedFile(_ source: URL, defaultExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: projectsFolder, withIntermediateDirectories: true)
        let fileExtension = source.pathExtension.isEmpty ? defaultExtension : source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent
        let destination = projectsFolder
            .appendingPathComponent("\(UUID().uuidString)_\(baseName)")
            .appendingPathExtension(fileExtension)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}

private struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: true) { received in
            let destination = try ProjectFileStorage.keepImportedFile(received.file, defaultExtension: "mov")
            return ImportedMovie(url: destination)
        }
    }
}

private struct ImportedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: true) { received in
            let destination = try ProjectFileStorage.keepImportedFile(received.file, defaultExtension: "jpg")
            return ImportedPhoto(url: destination)
        }
    }
}

struct EditorView: View {
    private let initialMediaURL: URL?
    private let onClose: (() -> Void)?
    @State private var selectedMovie: PhotosPickerItem?
    @State private var isImportingMedia = false
    @State private var isShowingOriginal = false
    @State private var compositionUpdateTask: Task<Void, Never>?
    @State private var compositionGeneration = 0
    @State private var photoRenderGeneration = 0
    @State private var player: AVPlayer?
    @State private var filteredComposition: AVVideoComposition?
    @State private var movieURL: URL?
    @State private var imageURL: URL?
    @State private var photoPreview: UIImage?
    @State private var originalPhotoPreview: UIImage?
    @State private var recentMovies: [URL] = []
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var showFullscreen = false
    @State private var videoScale: CGFloat = 1
    @State private var lastVideoScale: CGFloat = 1
    @State private var videoOffset = CGSize.zero
    @State private var lastVideoOffset = CGSize.zero
    @State private var tab: EditorTab = .filters
    @State private var category = "Cinematic"
    @State private var selectedAdjustment: Adjustment = .saturation
    @State private var settings = GradeSettings()
    @State private var presets: [LUTPreset] = []
    @State private var savedPresets: [UserPreset] = []
    @State private var exporting = false
    @State private var importingCube = false
    @State private var showExportQuality = false
    @State private var showPresetSheet = false
    @State private var presetName = ""
    @State private var exportMessage: String?
    @State private var showExportMessage = false

    private let accent = Color(red: 0.66, green: 1, blue: 0.16)
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    init(initialMediaURL: URL? = nil, onClose: (() -> Void)? = nil) {
        self.initialMediaURL = initialMediaURL
        self.onClose = onClose
        _movieURL = State(initialValue: initialMediaURL.flatMap { Self.isImageFile($0) ? nil : $0 })
        _imageURL = State(initialValue: initialMediaURL.flatMap { Self.isImageFile($0) ? $0 : nil })
    }

    private var hasMedia: Bool { movieURL != nil || imageURL != nil }

    private static func isImageFile(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"].contains(url.pathExtension.lowercased())
    }

    private var categories: [String] {
        (savedPresets.isEmpty ? [] : ["My Presets"]) + ["Cinematic", "Social", "Clean", "Daily", "Essentials", "Dark", "Movies", "LUTs"]
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Color.black
                if let player {
                    VideoPlayer(player: player)
                        .scaleEffect(videoScale)
                        .offset(videoOffset)
                        .gesture(MagnifyGesture()
                            .onChanged { value in videoScale = min(4, max(0.4, lastVideoScale * value.magnification)) }
                            .onEnded { _ in lastVideoScale = videoScale })
                        .simultaneousGesture(DragGesture()
                            .onChanged { value in
                                videoOffset = CGSize(width: lastVideoOffset.width + value.translation.width,
                                                     height: lastVideoOffset.height + value.translation.height)
                            }
                            .onEnded { _ in lastVideoOffset = videoOffset })
                        .onAppear { player.play() }
                } else if let image = isShowingOriginal ? originalPhotoPreview : photoPreview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else if imageURL != nil {
                    ProgressView("Preparing photo…").tint(.white).foregroundStyle(.white)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 44)).foregroundStyle(.white.opacity(0.65))
                        Text("Choose a photo or video to start editing")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        PhotosPicker(selection: $selectedMovie, matching: .any(of: [.images, .videos])) {
                            Label("Choose Media", systemImage: "plus")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .background(accent, in: Capsule())
                        }
                        if !recentMovies.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(recentMovies, id: \.path) { url in
                                        Button(url.deletingPathExtension().lastPathComponent) { openProject(url) }
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 11).padding(.vertical, 8)
                                            .background(.white.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.white)
                                            .contextMenu { Button("Delete Project", role: .destructive) { deleteProject(url) } }
                                    }
                                }.padding(.horizontal, 18)
                            }.frame(maxWidth: 330)
                        }
                    }
                }
                HStack {
                    if hasMedia {
                        Button {
                            if let onClose { onClose() } else { clearMovie() }
                        } label: {
                            Image(systemName: onClose == nil ? "chevron.left" : "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38).background(.black.opacity(0.65), in: Circle())
                        }
                    } else {
                        Color.clear.frame(width: 38, height: 38)
                    }
                    Spacer()
                    if hasMedia {
                        PhotosPicker(selection: $selectedMovie, matching: .any(of: [.images, .videos])) {
                            Group {
                                if isImportingMedia { ProgressView().tint(.white) }
                                else { Image(systemName: "plus.rectangle.on.rectangle") }
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38).background(.black.opacity(0.65), in: Circle())
                        }
                        .disabled(isImportingMedia)
                        .accessibilityLabel("Add or replace media")
                        Button { toggleOriginalPreview() } label: {
                            Label(isShowingOriginal ? "Original" : "Compare", systemImage: "circle.lefthalf.filled")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 11).padding(.vertical, 9)
                                .background(isShowingOriginal ? accent : .black.opacity(0.65), in: Capsule())
                                .foregroundStyle(isShowingOriginal ? .black : .white)
                        }
                    }
                    Button { showExportQuality = true } label: {
                        if exporting { ProgressView().tint(.white) }
                        else { Text("Export").font(.system(size: 13, weight: .semibold)) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.black.opacity(0.7), in: Capsule())
                    .disabled(!hasMedia || exporting)
                }
                .foregroundStyle(.white).padding(.horizontal, 16).padding(.top, 14)
            }
            .frame(maxWidth: .infinity).frame(height: 330)

            if movieURL != nil {
                HStack {
                    Button { togglePlayback() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15)).frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    Text(timeString(currentTime) + " / " + timeString(duration))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                    Slider(value: $currentTime, in: 0...max(duration, 0.01), onEditingChanged: { editing in
                        if !editing { player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                    }).tint(.white)
                    Button { presetName = ""; showPresetSheet = true } label: {
                        Image(systemName: "bookmark").frame(width: 32, height: 32)
                    }
                    Button { showFullscreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 40, height: 40).background(Color.white.opacity(0.1), in: Circle())
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 8)
            }

            HStack(spacing: 0) {
                ForEach(EditorTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tab == item ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(tab == item ? Color.white : .clear, in: Capsule())
                    }
                }
            }
            .padding(4).background(Color(white: 0.22), in: Capsule()).padding(.horizontal, 18).padding(.top, 8)

            Group {
                switch tab {
                case .filters: filtersPanel
                case .adjust: adjustmentsPanel
                case .effects: effectsPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 14)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08).ignoresSafeArea())
        .onAppear {
            loadPresets()
            loadSavedPresets()
            loadRecentMovies()
            if let initialMediaURL {
                if Self.isImageFile(initialMediaURL) { configurePhoto(for: initialMediaURL) }
                else if player == nil { configurePlayer(for: initialMediaURL) }
            }
        }
        .onChange(of: selectedMovie) { _, item in
            guard let item else { return }
            isImportingMedia = true
            Task { await importMedia(item) }
        }
        .onChange(of: movieURL) { _, url in
            if let url { configurePlayer(for: url) }
        }
        .onChange(of: settings) { _, _ in
            if movieURL != nil { scheduleCompositionUpdate() }
            if imageURL != nil { schedulePhotoPreviewUpdate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            player?.seek(to: .zero)
            player?.play()
            currentTime = 0
            isPlaying = true
        }
        .fileImporter(isPresented: $importingCube, allowedContentTypes: [.data]) { result in
            do {
                let source = try result.get()
                guard source.pathExtension.lowercased() == "cube" else {
                    throw ImportError.notCube
                }
                let hasAccess = source.startAccessingSecurityScopedResource()
                defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
                let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Imported LUTs", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                loadPresets()
                category = "LUTs"
                settings.lutURL = destination
            } catch {
                exportMessage = error.localizedDescription
                showExportMessage = true
            }
        }
        .confirmationDialog("Export quality", isPresented: $showExportQuality, titleVisibility: .visible) {
            if imageURL != nil {
                Button("Save edited photo") { exportPhoto() }
            } else {
                Button("Highest available quality") { exportVideo(preset: AVAssetExportPresetHighestQuality) }
                Button("1080p") { exportVideo(preset: AVAssetExportPreset1920x1080) }
                Button("720p") { exportVideo(preset: AVAssetExportPreset1280x720) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("LUT Editor", isPresented: $showExportMessage) {
            Button("OK", role: .cancel) { }
        } message: { Text(exportMessage ?? "") }
        .sheet(isPresented: $showPresetSheet) {
            VStack(spacing: 18) {
                Text("Save Preset").font(.headline)
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 24)
                HStack {
                    Button("Cancel") { showPresetSheet = false }
                    Spacer()
                    Button("Save") { savePreset() }.fontWeight(.semibold).tint(accent)
                }.padding(.horizontal, 24)
            }
            .padding(.vertical, 24).presentationDetents([.height(190)])
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let player { VideoPlayer(player: player).ignoresSafeArea() }
                else if let image = isShowingOriginal ? originalPhotoPreview : photoPreview {
                    Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea()
                }
                Button { showFullscreen = false } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 40, height: 40)
                        .background(.black.opacity(0.6), in: Circle())
                }.padding(20)
            }.preferredColorScheme(.dark)
        }
        .onDisappear {
            player?.pause()
            removeTimeObserver()
            compositionUpdateTask?.cancel()
            photoRenderGeneration += 1
        }
    }

    private var filtersPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(categories, id: \.self) { item in
                        Button { category = item } label: {
                            Text(item).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(category == item ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(category == item ? accent : .clear, in: Capsule())
                        }
                    }
                }.padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if category == "My Presets" {
                        ForEach(savedPresets) { preset in
                            Button { settings = preset.settings } label: {
                                VStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(LinearGradient(colors: [accent.opacity(0.5), .black, .gray], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .overlay(Image(systemName: "bookmark.fill").foregroundStyle(.white.opacity(0.6)))
                                        .frame(width: 76, height: 86)
                                    Text(preset.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                }.foregroundStyle(.white)
                            }
                            .contextMenu { Button("Delete Preset", role: .destructive) { deletePreset(preset) } }
                        }
                    } else {
                    ForEach(presets.filter { categoryFor($0.category) == category }) { preset in
                        Button { settings.lutURL = preset.url } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [.gray, .black, accent.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    Image(systemName: "photo").foregroundStyle(.white.opacity(0.45))
                                    if settings.lutURL == preset.url {
                                        RoundedRectangle(cornerRadius: 9).stroke(accent, lineWidth: 2)
                                    }
                                }.frame(width: 76, height: 86)
                                Text(preset.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    Button { importingCube = true } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 76, height: 86)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            Text("Import LUT").font(.system(size: 10, weight: .medium))
                        }.foregroundStyle(.white.opacity(0.85))
                    }
                    }
                }.padding(.horizontal, 14)
            }.frame(height: 116)
            sliderRow(title: "Intensity", value: $settings.lutIntensity, range: 0...1)
        }
    }

    private var adjustmentsPanel: some View {
        VStack(spacing: 16) {
            Button {
                settings.smartEnhance = settings.smartEnhance != true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text("Smart Enhance · On device")
                    Spacer()
                    Text(settings.smartEnhance == true ? "ON" : "AUTO")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.smartEnhance == true ? .black : .white)
                .padding(.horizontal, 14).frame(height: 38)
                .background(settings.smartEnhance == true ? accent : .white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            Spacer(minLength: 18)
            HStack {
                Text(selectedAdjustment.rawValue).font(.system(size: 12, weight: .medium))
                Spacer()
                if selectedAdjustment != .curves {
                    Text(adjustmentValue, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
            }.padding(.horizontal, 24)
            if selectedAdjustment == .curves {
                CurveGraph(points: $settings.curvePoints)
                    .frame(height: 150).padding(.horizontal, 20)
            } else {
                Slider(value: sliderBinding(binding(for: selectedAdjustment)),
                       in: Double(range(for: selectedAdjustment).lowerBound)...Double(range(for: selectedAdjustment).upperBound))
                    .tint(.white).padding(.horizontal, 24)
            }
            Spacer(minLength: 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Adjustment.allCases) { adjustment in
                        Button { selectedAdjustment = adjustment } label: {
                            VStack(spacing: 5) {
                                Image(systemName: adjustment.symbol).font(.system(size: 16))
                                Text(adjustment.rawValue).font(.system(size: 8)).lineLimit(1)
                            }
                            .foregroundStyle(selectedAdjustment == adjustment ? accent : .white.opacity(0.55))
                            .frame(width: 54)
                        }
                    }
                }.padding(.horizontal, 10)
            }.padding(.bottom, 12)
        }
        .foregroundStyle(.white)
    }

    private var effectsPanel: some View {
        VStack(spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FilmEffect.allCases) { effect in
                        Button { settings.effect = effect } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
                                    Image(systemName: effectSymbol(effect))
                                        .font(.system(size: 21)).foregroundStyle(.white.opacity(0.8))
                                    if settings.effect == effect { RoundedRectangle(cornerRadius: 10).stroke(accent, lineWidth: 2) }
                                }.frame(width: 66, height: 70)
                                Text(effect.rawValue).font(.system(size: 10, weight: .medium))
                            }.foregroundStyle(.white)
                        }
                    }
                }.padding(.horizontal, 16)
            }.frame(height: 96)
            sliderRow(title: "Intensity", value: $settings.effectIntensity, range: 0...1)
            sliderRow(title: "Roughness", value: $settings.roughness, range: 0...1)
            sliderRow(title: "Size", value: $settings.size, range: 0...1)
        }
    }

    private func sliderRow(title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 11)).frame(width: 62, alignment: .leading)
            Slider(value: sliderBinding(value), in: Double(range.lowerBound)...Double(range.upperBound)).tint(.white)
        }.foregroundStyle(.white).padding(.horizontal, 20)
    }

    private func sliderBinding(_ value: Binding<Float>) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) })
    }

    private func effectSymbol(_ effect: FilmEffect) -> String {
        switch effect {
        case .none: return "circle.slash"
        case .bloom: return "sparkles"
        case .grain: return "circle.dotted"
        case .halation: return "sun.max"
        case .softGlow: return "sun.haze.fill"
        case .lightLeak: return "sun.max.fill"
        }
    }

    private var adjustmentValue: Float { binding(for: selectedAdjustment).wrappedValue * 100 }

    private func binding(for adjustment: Adjustment) -> Binding<Float> {
        switch adjustment {
        case .hue: return $settings.hue
        case .exposure: return $settings.exposure
        case .contrast: return $settings.contrast
        case .highlights: return $settings.highlights
        case .shadows: return $settings.shadows
        case .temperature: return $settings.temperature
        case .vibrance: return $settings.vibrance
        case .saturation: return $settings.saturation
        case .sharpness: return $settings.sharpness
        case .vignette: return $settings.vignette
        case .curves: return $settings.curves
        }
    }

    private func range(for adjustment: Adjustment) -> ClosedRange<Float> {
        switch adjustment {
        case .hue: return -1...1
        case .exposure: return -2...2
        case .temperature: return -1...1
        case .contrast, .highlights, .shadows: return -1...1
        case .vibrance, .saturation, .sharpness, .vignette, .curves: return -1...1
        }
    }

    private func categoryFor(_ raw: String) -> String {
        if raw == "Social" { return "Social" }
        if raw == "Movies" { return "Movies" }
        if categories.contains(raw) { return raw }
        return "LUTs"
    }

    private func loadPresets() {
        var roots: [URL] = []
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Filters", isDirectory: true) {
            roots.append(bundled)
        }
        let imported = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imported LUTs", isDirectory: true)
        if FileManager.default.fileExists(atPath: imported.path) { roots.append(imported) }
        presets = roots.flatMap { root -> [LUTPreset] in
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
            return files.compactMap { item in
                guard let url = item as? URL, url.pathExtension.lowercased() == "cube" else { return nil }
                let relative = String(url.path.dropFirst(root.path.count + 1))
                let pieces = relative.split(separator: "/")
                let group = pieces.count > 1 ? String(pieces[0]) : "LUTs"
                return LUTPreset(name: url.deletingPathExtension().lastPathComponent, category: group, url: url)
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let first = presets.first(where: { categoryFor($0.category) == category }) { settings.lutURL = first.url }
    }

    private func savedPresetsFile() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SavedPresets.json")
    }

    private func loadSavedPresets() {
        guard let data = try? Data(contentsOf: savedPresetsFile()),
              let saved = try? JSONDecoder().decode([UserPreset].self, from: data) else { return }
        savedPresets = saved
    }

    private func savePreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        savedPresets.insert(UserPreset(name: name, settings: settings), at: 0)
        persistSavedPresets()
        category = "My Presets"
        presetName = ""
        showPresetSheet = false
    }

    private func deletePreset(_ preset: UserPreset) {
        savedPresets.removeAll { $0.id == preset.id }
        persistSavedPresets()
        if savedPresets.isEmpty { category = "Cinematic" }
    }

    private func persistSavedPresets() {
        guard let data = try? JSONEncoder().encode(savedPresets) else { return }
        try? data.write(to: savedPresetsFile(), options: .atomic)
    }

    @MainActor private func importMedia(_ item: PhotosPickerItem) async {
        defer {
            selectedMovie = nil
            isImportingMedia = false
        }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
                guard let photo = try await item.loadTransferable(type: ImportedPhoto.self) else { return }
                configurePhoto(for: photo.url)
            } else {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else { return }
                movieURL = movie.url
                loadRecentMovies()
            }
        } catch {
            exportMessage = "Could not open this media: \(error.localizedDescription)"
            showExportMessage = true
        }
    }

    private func clearMovie() {
        player?.pause()
        removeTimeObserver()
        player = nil
        filteredComposition = nil
        movieURL = nil
        imageURL = nil
        photoPreview = nil
        originalPhotoPreview = nil
        photoRenderGeneration += 1
        selectedMovie = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        videoScale = 1
        lastVideoScale = 1
        videoOffset = .zero
        lastVideoOffset = .zero
        isShowingOriginal = false
    }

    private func openProject(_ url: URL) {
        if Self.isImageFile(url) { configurePhoto(for: url) }
        else { movieURL = url }
    }

    private func deleteProject(_ url: URL) {
        if movieURL == url || imageURL == url { clearMovie() }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: settingsFile(for: url))
        loadRecentMovies()
    }

    private func loadRecentMovies() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        recentMovies = files.compactMap { $0 as? URL }
            .filter { Self.isImageFile($0) || ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) }
            .sorted { first, second in
                let a = (try? first.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? second.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }.prefix(8).map { $0 }
    }

    private func configurePlayer(for url: URL) {
        player?.pause()
        removeTimeObserver()
        imageURL = nil
        photoPreview = nil
        originalPhotoPreview = nil
        photoRenderGeneration += 1
        loadSettings(for: url)
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 1.5
        let nextPlayer = AVPlayer(playerItem: item)
        nextPlayer.automaticallyWaitsToMinimizeStalling = false
        player = nextPlayer
        isShowingOriginal = false
        currentTime = 0
        duration = 0
        isPlaying = false
        Task {
            let asset = AVURLAsset(url: url)
            if let loadedDuration = try? await asset.load(.duration) {
                await MainActor.run { duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0 }
            }
        }
        timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { time in
            if time.seconds.isFinite { currentTime = time.seconds }
            isPlaying = player?.timeControlStatus == .playing
        }
        updateVideoComposition()
    }

    private func configurePhoto(for url: URL) {
        player?.pause()
        removeTimeObserver()
        player = nil
        filteredComposition = nil
        movieURL = nil
        imageURL = url
        photoPreview = nil
        originalPhotoPreview = nil
        isShowingOriginal = false
        currentTime = 0
        duration = 0
        loadSettings(for: url)
        schedulePhotoPreviewUpdate()
    }

    private func removeTimeObserver() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if duration > 0 && currentTime >= duration {
                player.seek(to: .zero)
                currentTime = 0
            }
            player.play()
            isPlaying = true
        }
    }

    private func toggleOriginalPreview() {
        isShowingOriginal.toggle()
        if movieURL != nil {
            player?.currentItem?.videoComposition = isShowingOriginal ? nil : filteredComposition
        }
    }

    private func timeString(_ time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let seconds = max(0, Int(time))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func updateVideoComposition() {
        guard let movieURL, let item = player?.currentItem else { return }
        let asset = AVURLAsset(url: movieURL)
        let snapshot = settings
        let currentURL = movieURL
        compositionGeneration += 1
        let generation = compositionGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let cube = snapshot.lutURL.flatMap { CubeLUT.cached(url: $0) }
            let composition = AVVideoComposition(asset: asset) { request in
                let image = Self.grade(request.sourceImage, settings: snapshot, cube: cube)
                request.finish(with: image, context: nil)
            }
            DispatchQueue.main.async {
                guard self.compositionGeneration == generation,
                      self.movieURL == currentURL,
                      self.player?.currentItem === item else { return }
                self.filteredComposition = composition
                item.videoComposition = self.isShowingOriginal ? nil : composition
                self.saveSettings(for: currentURL)
            }
        }
    }

    private func schedulePhotoPreviewUpdate() {
        guard let imageURL else { return }
        photoRenderGeneration += 1
        let generation = photoRenderGeneration
        let snapshot = settings
        DispatchQueue.global(qos: .userInitiated).async {
            guard let fullImage = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]) else { return }
            let longestSide = max(fullImage.extent.width, fullImage.extent.height)
            let scale = min(1, 1600 / max(longestSide, 1))
            let previewSource = fullImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let cube = snapshot.lutURL.flatMap { CubeLUT.cached(url: $0) }
            let graded = Self.grade(previewSource, settings: snapshot, cube: cube)
            guard let originalCG = Self.imageContext.createCGImage(previewSource, from: previewSource.extent),
                  let gradedCG = Self.imageContext.createCGImage(graded, from: previewSource.extent) else { return }
            let original = UIImage(cgImage: originalCG)
            let adjusted = UIImage(cgImage: gradedCG)
            DispatchQueue.main.async {
                guard self.photoRenderGeneration == generation, self.imageURL == imageURL else { return }
                self.originalPhotoPreview = original
                self.photoPreview = adjusted
            }
        }
    }

    private func scheduleCompositionUpdate() {
        compositionUpdateTask?.cancel()
        compositionUpdateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            updateVideoComposition()
        }
    }

    private func settingsFile(for url: URL) -> URL {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(url.lastPathComponent + ".json")
    }

    private func loadSettings(for url: URL) {
        settings = GradeSettings(lutURL: presets.first(where: { categoryFor($0.category) == "Cinematic" })?.url)
        guard let data = try? Data(contentsOf: settingsFile(for: url)),
              var saved = try? JSONDecoder().decode(GradeSettings.self, from: data) else { return }
        if saved.curvePoints.count != 5 { saved.curvePoints = [0, 0.25, 0.5, 0.75, 1] }
        if let lut = saved.lutURL, !FileManager.default.fileExists(atPath: lut.path) {
            saved.lutURL = presets.first(where: { categoryFor($0.category) == "Cinematic" })?.url
        }
        settings = saved
    }

    private func saveSettings(for url: URL) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile(for: url), options: .atomic)
    }

    private static func grade(_ source: CIImage, settings: GradeSettings, cube: CubeLUT?) -> CIImage {
        var image = source
        if settings.smartEnhance == true {
            let options: [CIImageAutoAdjustmentOption: Any] = [
                .enhance: true,
                .redEye: false,
                .crop: false,
                .level: false
            ]
            for filter in image.autoAdjustmentFilters(options: options) {
                filter.setValue(image, forKey: kCIInputImageKey)
                if let adjusted = filter.outputImage { image = adjusted }
            }
        }
        if let cube, settings.lutIntensity > 0,
           let lutFilter = CIFilter(name: "CIColorCubeWithColorSpace") {
            lutFilter.setValue(image, forKey: kCIInputImageKey)
            lutFilter.setValue(cube.dimension, forKey: "inputCubeDimension")
            lutFilter.setValue(cube.data, forKey: "inputCubeData")
            lutFilter.setValue(CGColorSpace(name: CGColorSpace.sRGB)!, forKey: "inputColorSpace")
            if let lutImage = lutFilter.outputImage,
               let blend = CIFilter(name: "CIDissolveTransition") {
                blend.setValue(image, forKey: "inputImage")
                blend.setValue(lutImage, forKey: "inputTargetImage")
                blend.setValue(settings.lutIntensity, forKey: "inputTime")
                image = blend.outputImage ?? lutImage
            }
        }
        if let filter = CIFilter(name: "CIHueAdjust") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(settings.hue * .pi, forKey: kCIInputAngleKey)
            image = filter.outputImage ?? image
        }
        if settings.exposure != 0, let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(settings.exposure, forKey: "inputEV")
            image = filter.outputImage ?? image
        }
        if let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(max(0, 1 + settings.saturation), forKey: kCIInputSaturationKey)
            filter.setValue(max(0.1, 1 + settings.contrast), forKey: kCIInputContrastKey)
            image = filter.outputImage ?? image
        }
        if settings.vibrance != 0, let filter = CIFilter(name: "CIVibrance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(settings.vibrance, forKey: "inputAmount")
            image = filter.outputImage ?? image
        }
        if settings.highlights != 0 || settings.shadows != 0,
           let filter = CIFilter(name: "CIHighlightShadowAdjust") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(1 - settings.shadows, forKey: "inputShadowAmount")
            filter.setValue(1 - settings.highlights, forKey: "inputHighlightAmount")
            image = filter.outputImage ?? image
        }
        if settings.temperature != 0, let filter = CIFilter(name: "CITemperatureAndTint") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter.setValue(CIVector(x: CGFloat(6500 + settings.temperature * 2800), y: CGFloat(settings.temperature * 20)), forKey: "inputTargetNeutral")
            image = filter.outputImage ?? image
        }
        if settings.sharpness != 0, let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(settings.sharpness * 1.5, forKey: kCIInputSharpnessKey)
            image = filter.outputImage ?? image
        }
        if settings.vignette != 0, let filter = CIFilter(name: "CIVignette") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(settings.vignette * 2, forKey: kCIInputIntensityKey)
            filter.setValue(max(source.extent.width, source.extent.height) * 0.7, forKey: kCIInputRadiusKey)
            image = filter.outputImage ?? image
        }
        if let filter = CIFilter(name: "CIToneCurve") {
            filter.setValue(image, forKey: kCIInputImageKey)
            let points = settings.curvePoints.count == 5 ? settings.curvePoints : [0, 0.25, 0.5, 0.75, 1]
            for index in 0..<5 {
                filter.setValue(CIVector(x: CGFloat(index) / 4, y: CGFloat(points[index])), forKey: "inputPoint\(index)")
            }
            image = filter.outputImage ?? image
        }
        let amount = settings.effectIntensity
        switch settings.effect {
        case .none: break
        case .bloom:
            if let filter = CIFilter(name: "CIBloom") {
                filter.setValue(image, forKey: kCIInputImageKey)
                filter.setValue(amount * 2, forKey: kCIInputIntensityKey)
                filter.setValue(settings.size * 40 + 4, forKey: kCIInputRadiusKey)
                image = filter.outputImage ?? image
            }
        case .grain:
            if let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: source.extent),
               let controls = CIFilter(name: "CIColorControls"), let blend = CIFilter(name: "CISoftLightBlendMode"),
               let mix = CIFilter(name: "CIDissolveTransition") {
                controls.setValue(noise, forKey: kCIInputImageKey)
                controls.setValue(0, forKey: kCIInputSaturationKey)
                controls.setValue(settings.roughness * 2 + 0.1, forKey: kCIInputContrastKey)
                blend.setValue(controls.outputImage, forKey: kCIInputImageKey)
                blend.setValue(image, forKey: kCIInputBackgroundImageKey)
                mix.setValue(image, forKey: "inputImage")
                mix.setValue(blend.outputImage, forKey: "inputTargetImage")
                mix.setValue(amount * 0.4, forKey: "inputTime")
                image = mix.outputImage ?? image
            }
        case .halation:
            if let bloom = CIFilter(name: "CIBloom") {
                bloom.setValue(image, forKey: kCIInputImageKey)
                bloom.setValue(amount * 1.5, forKey: kCIInputIntensityKey)
                bloom.setValue(settings.size * 30 + 3, forKey: kCIInputRadiusKey)
                let glow = bloom.outputImage ?? image
                image = glow.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.2, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 0.48, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0.22, w: 0)
                ])
            }
        case .softGlow:
            if let glow = CIFilter(name: "CIBloom"), let mix = CIFilter(name: "CIDissolveTransition") {
                glow.setValue(image, forKey: kCIInputImageKey)
                glow.setValue(amount * 1.2, forKey: kCIInputIntensityKey)
                glow.setValue(settings.size * 50 + 8, forKey: kCIInputRadiusKey)
                mix.setValue(image, forKey: "inputImage")
                mix.setValue(glow.outputImage ?? image, forKey: "inputTargetImage")
                mix.setValue(amount, forKey: "inputTime")
                image = mix.outputImage ?? image
            }
        case .lightLeak:
            let extent = source.extent
            let radius = max(extent.width, extent.height) * 0.9
            let center = CIVector(x: extent.minX + extent.width * 0.16, y: extent.minY + extent.height * 0.83)
            if let leak = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": 0,
                "inputRadius1": radius,
                "inputColor0": CIColor(red: 1, green: 0.44, blue: 0.18, alpha: 0.72),
                "inputColor1": CIColor(red: 1, green: 0.28, blue: 0.06, alpha: 0)
            ])?.outputImage?.cropped(to: extent),
               let screen = CIFilter(name: "CIScreenBlendMode"),
               let mix = CIFilter(name: "CIDissolveTransition") {
                screen.setValue(leak, forKey: kCIInputImageKey)
                screen.setValue(image, forKey: kCIInputBackgroundImageKey)
                mix.setValue(image, forKey: "inputImage")
                mix.setValue(screen.outputImage ?? image, forKey: "inputTargetImage")
                mix.setValue(amount, forKey: "inputTime")
                image = mix.outputImage ?? image
            }
        }
        return image.cropped(to: source.extent)
    }

    private func exportPhoto() {
        guard let imageURL else { return }
        exporting = true
        let snapshot = settings
        Task {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("LUTStudio-\(UUID().uuidString)")
                .appendingPathExtension("jpg")
            do {
                try await Task.detached(priority: .userInitiated) {
                    guard let source = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]) else {
                        throw ExportError.photoUnavailable
                    }
                    let cube = snapshot.lutURL.flatMap { CubeLUT.cached(url: $0) }
                    let graded = Self.grade(source, settings: snapshot, cube: cube).cropped(to: source.extent)
                    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw ExportError.photoUnavailable }
                    try Self.imageContext.writeJPEGRepresentation(of: graded, to: output, colorSpace: colorSpace)
                }.value
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: output)
                }
                try? FileManager.default.removeItem(at: output)
                exporting = false
                exportMessage = "Edited photo saved to Photos."
                showExportMessage = true
            } catch {
                try? FileManager.default.removeItem(at: output)
                exporting = false
                exportMessage = error.localizedDescription
                showExportMessage = true
            }
        }
    }

    private func exportVideo(preset: String = AVAssetExportPresetHighestQuality) {
        guard let movieURL else { return }
        exporting = true
        Task {
            do {
                let asset = AVURLAsset(url: movieURL)
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                    throw ExportError.cannotCreateSession
                }
                let snapshot = settings
                let cube = await Task.detached(priority: .userInitiated) {
                    snapshot.lutURL.flatMap { CubeLUT.cached(url: $0) }
                }.value
                session.videoComposition = AVVideoComposition(asset: asset) { request in
                    request.finish(with: Self.grade(request.sourceImage, settings: snapshot, cube: cube), context: nil)
                }
                session.outputURL = output
                session.outputFileType = .mov
                await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume() }
                }
                guard session.status == .completed else { throw session.error ?? ExportError.failed }
                try await saveToPhotos(output)
                await MainActor.run {
                    exporting = false
                    exportMessage = "Video saved to Photos."
                    showExportMessage = true
                }
            } catch {
                await MainActor.run {
                    exporting = false
                    exportMessage = error.localizedDescription
                    showExportMessage = true
                }
            }
        }
    }

    private func saveToPhotos(_ url: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    private enum ExportError: LocalizedError {
        case cannotCreateSession
        case failed
        case photoUnavailable
        var errorDescription: String? {
            switch self {
            case .cannotCreateSession: return "Could not start video export."
            case .failed: return "Video export failed."
            case .photoUnavailable: return "Could not read or render this photo."
            }
        }
    }

    private enum ImportError: LocalizedError {
        case notCube
        var errorDescription: String? { "Please choose a .cube LUT file." }
    }
}

private struct CubeLUT {
    let dimension: Int
    let data: Data
    private static let cache: NSCache<NSURL, CubeLUTCacheEntry> = {
        let cache = NSCache<NSURL, CubeLUTCacheEntry>()
        cache.countLimit = 10
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func cached(url: URL) -> CubeLUT? {
        let key = url as NSURL
        if let entry = cache.object(forKey: key) { return entry.value }
        guard let value = CubeLUT(url: url) else { return nil }
        cache.setObject(CubeLUTCacheEntry(value), forKey: key, cost: value.data.count)
        return value
    }

    init?(url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var size = 0
        var values: [Float] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") || line.hasPrefix("DOMAIN_") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.first == "LUT_3D_SIZE", parts.count > 1 { size = Int(parts[1]) ?? 0; continue }
            if parts.count >= 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                values.append(contentsOf: [r, g, b, 1])
            }
        }
        guard size > 1, values.count == size * size * size * 4 else { return nil }
        dimension = size
        data = values.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
    }
}

private final class CubeLUTCacheEntry {
    let value: CubeLUT
    init(_ value: CubeLUT) { self.value = value }
}

private struct CurveGraph: View {
    @Binding var points: [Double]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, canvasSize in
                    var grid = Path()
                    for step in 1...3 {
                        let x = canvasSize.width * CGFloat(step) / 4
                        let y = canvasSize.height * CGFloat(step) / 4
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: canvasSize.height))
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
                Path { path in
                    for index in 0..<5 {
                        let point = CGPoint(x: size.width * CGFloat(index) / 4,
                                            y: size.height * (1 - CGFloat(points[index])))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(0..<5, id: \.self) { index in
                    Circle().fill(.white).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                        .position(x: size.width * CGFloat(index) / 4,
                                  y: size.height * (1 - CGFloat(points[index])))
                }
            }
            .coordinateSpace(name: "curveGraph")
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curveGraph"))
                .onChanged { value in
                    let index = Int((value.location.x / max(size.width, 1) * 4).rounded())
                    guard index > 0, index < 4 else { return }
                    points[index] = min(1, max(0, 1 - Double(value.location.y / max(size.height, 1))))
                })
        }
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}
