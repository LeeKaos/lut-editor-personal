import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Photos
import UIKit
import AVFoundation
import AVKit
import ImageIO

private let accent = Color(red: 0.66, green: 1.0, blue: 0.16)

struct GradeProject: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var fileName: String
    var settings: GradeSettings
    init(id: UUID = UUID(), createdAt: Date = .now, fileName: String, settings: GradeSettings = .init()) { self.id = id; self.createdAt = createdAt; self.fileName = fileName; self.settings = settings }
}

struct GradeSettings: Codable, Equatable {
    var lutName = "Original"; var intensity = 100.0; var exposure = 0.0; var contrast = 1.0; var saturation = 1.0; var brightness = 0.0
    var temperature = 6500.0; var tint = 0.0; var highlights = 1.0; var shadows = 0.0; var whites = 0.0; var blacks = 0.0
    var hue = 0.0; var vibrance = 0.0; var sharpness = 0.0; var curveBlack = 0.0; var curveMid = 0.5; var curveWhite = 1.0
    var wheelShadows = 0.0; var wheelMidtones = 0.0; var wheelHighlights = 0.0
    var cropAspect = "Orijinal"; var maskEnabled = false; var maskExposure = 0.0; var maskRadius = 0.55; var maskFeather = 0.25
    var trimStart = 0.0; var trimEnd = 1.0
    var exportCodec = "HEVC"; var exportResolution = "Orijinal"; var exportBitrateMode = "Otomatik"; var exportBitrateMbps = 20.0
    var vignette = 0.0; var bloom = 0.0; var grain = 0.0
    var brilliance = 0.0; var blackPoint = 0.0; var definition = 0.0; var noiseReduction = 0.0; var autoEnhance = false
    var source = "Regular"
    enum CodingKeys: String, CodingKey { case lutName, intensity, exposure, contrast, saturation, brightness, temperature, tint, highlights, shadows, whites, blacks, hue, vibrance, sharpness, curveBlack, curveMid, curveWhite, wheelShadows, wheelMidtones, wheelHighlights, cropAspect, maskEnabled, maskExposure, maskRadius, maskFeather, trimStart, trimEnd, exportCodec, exportResolution, exportBitrateMode, exportBitrateMbps, vignette, bloom, grain, brilliance, blackPoint, definition, noiseReduction, autoEnhance, source }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lutName = try c.decodeIfPresent(String.self, forKey: .lutName) ?? "Original"
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 100
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500
        tint = try c.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 1
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try c.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try c.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        hue = try c.decodeIfPresent(Double.self, forKey: .hue) ?? 0
        vibrance = try c.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        curveBlack = try c.decodeIfPresent(Double.self, forKey: .curveBlack) ?? 0
        curveMid = try c.decodeIfPresent(Double.self, forKey: .curveMid) ?? 0.5
        curveWhite = try c.decodeIfPresent(Double.self, forKey: .curveWhite) ?? 1
        wheelShadows = try c.decodeIfPresent(Double.self, forKey: .wheelShadows) ?? 0
        wheelMidtones = try c.decodeIfPresent(Double.self, forKey: .wheelMidtones) ?? 0
        wheelHighlights = try c.decodeIfPresent(Double.self, forKey: .wheelHighlights) ?? 0
        cropAspect = try c.decodeIfPresent(String.self, forKey: .cropAspect) ?? "Orijinal"
        maskEnabled = try c.decodeIfPresent(Bool.self, forKey: .maskEnabled) ?? false
        maskExposure = try c.decodeIfPresent(Double.self, forKey: .maskExposure) ?? 0
        maskRadius = try c.decodeIfPresent(Double.self, forKey: .maskRadius) ?? 0.55
        maskFeather = try c.decodeIfPresent(Double.self, forKey: .maskFeather) ?? 0.25
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd) ?? 1
        exportCodec = try c.decodeIfPresent(String.self, forKey: .exportCodec) ?? "HEVC"
        exportResolution = try c.decodeIfPresent(String.self, forKey: .exportResolution) ?? "Orijinal"
        exportBitrateMode = try c.decodeIfPresent(String.self, forKey: .exportBitrateMode) ?? "Otomatik"
        exportBitrateMbps = try c.decodeIfPresent(Double.self, forKey: .exportBitrateMbps) ?? 20
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0
        bloom = try c.decodeIfPresent(Double.self, forKey: .bloom) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        brilliance = try c.decodeIfPresent(Double.self, forKey: .brilliance) ?? 0
        blackPoint = try c.decodeIfPresent(Double.self, forKey: .blackPoint) ?? 0
        definition = try c.decodeIfPresent(Double.self, forKey: .definition) ?? 0
        noiseReduction = try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0
        autoEnhance = try c.decodeIfPresent(Bool.self, forKey: .autoEnhance) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "Regular"
    }
}

final class ProjectLibrary: ObservableObject {
    @Published var projects: [GradeProject] = [] { didSet { save() } }
    private let key = "lumagrade.projects.v1"
    init() { guard let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode([GradeProject].self, from: data) else { return }; projects = stored }
    func add(imageData data: Data, fileExtension: String, source: String = "Regular") throws -> GradeProject {
        let safeExtension = fileExtension.isEmpty ? "jpg" : fileExtension
        let name = "\(UUID().uuidString).\(safeExtension)"
        try data.write(to: documents.appendingPathComponent(name), options: .atomic)
        var settings = GradeSettings(); settings.source = source
        let project = GradeProject(fileName: name, settings: settings)
        projects.insert(project, at: 0)
        return project
    }
    func add(video source: URL, profile: String = "Regular") throws -> GradeProject {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        try FileManager.default.copyItem(at: source, to: documents.appendingPathComponent(name))
        var settings = GradeSettings(); settings.source = profile
        let project = GradeProject(fileName: name, settings: settings)
        projects.insert(project, at: 0)
        return project
    }
    func videoURL(for project: GradeProject) -> URL { documents.appendingPathComponent(project.fileName) }
    func image(for project: GradeProject) -> UIImage? { UIImage(contentsOfFile: documents.appendingPathComponent(project.fileName).path) }
    func update(_ project: GradeProject) { guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }; projects[index] = project }
    func remove(_ project: GradeProject) { try? FileManager.default.removeItem(at: documents.appendingPathComponent(project.fileName)); projects.removeAll { $0.id == project.id } }
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func save() { if let data = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(data, forKey: key) } }
}

struct RootView: View {
    @State private var selectedTab = 0
    var body: some View { TabView(selection: $selectedTab) { ProjectsView().tabItem { Label("Projeler", systemImage: "square.grid.2x2.fill") }.tag(0); SettingsView().tabItem { Label("Profil", systemImage: "person.crop.circle") }.tag(1) }.tint(accent).preferredColorScheme(.dark).task { if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined { PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in } } } }
}

struct ProjectsView: View {
    @EnvironmentObject private var library: ProjectLibrary
    @State private var pickerItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var editor: GradeProject?
    @State private var importingLUT = false
    @State private var choosingMedia = false
    @State private var showingImagePicker = false
    @State private var showingVideoPicker = false
    @State private var isImportingMedia = false
    @State private var importError: String?
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if library.projects.isEmpty { empty }
                    else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(library.projects) { project in card(project) }
                            }.padding(16).padding(.bottom, 80)
                        }
                    }
                }
                Button { choosingMedia = true } label: {
                    Label("Yeni Proje", systemImage: "plus")
                        .font(.headline).padding(.horizontal, 20).frame(height: 54)
                        .background(accent, in: Capsule()).foregroundStyle(.black)
                }
                .padding(.bottom, 18)
                .disabled(isImportingMedia)
                if isImportingMedia {
                    Color.black.opacity(0.42).ignoresSafeArea()
                    ProgressView("Medya içe aktarılıyor…")
                        .padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("LUT STUDIO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(2).foregroundStyle(accent)
                        Text("Projeler").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showingImagePicker = true } label: { Label("Fotoğraf Ekle", systemImage: "photo") }
                        Button { showingVideoPicker = true } label: { Label("Video Ekle", systemImage: "video") }
                        Button { importingLUT = true } label: { Label("LUT İçe Aktar", systemImage: "cube.transparent") }
                    } label: { Image(systemName: "plus") }
                    .disabled(isImportingMedia)
                }
            }
            .confirmationDialog("Yeni Proje", isPresented: $choosingMedia, titleVisibility: .visible) {
                Button("Fotoğraf Seç", systemImage: "photo") { showingImagePicker = true }
                Button("Video Seç", systemImage: "video") { showingVideoPicker = true }
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $pickerItem, matching: .images)
            .photosPicker(isPresented: $showingVideoPicker, selection: $videoItem, matching: .videos)
            .onChange(of: pickerItem) { _, item in if let item { importImage(item) } }
            .onChange(of: videoItem) { _, item in if let item { importVideo(item) } }
            .fileImporter(isPresented: $importingLUT, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { _ in }
            .fullScreenCover(item: $editor) { EditorView(project: $0) }
            .alert("Medya eklenemedi", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Tamam", role: .cancel) { importError = nil }
            } message: { Text(importError ?? "Fotoğraf veya video içe aktarılamadı.") }
        }
    }
    private var empty: some View { ContentUnavailableView("İlk düzenlemeni oluştur", systemImage: "camera.filters", description: Text("Fotoğraf seç, LUT uygula ve görünümünü kaydet.")) }
    private func card(_ project: GradeProject) -> some View {
        let isVideo = ["mov", "mp4", "m4v"].contains(URL(fileURLWithPath: project.fileName).pathExtension.lowercased())
        return Button { editor = project } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomLeading) {
                    MediaProjectThumbnail(url: library.videoURL(for: project), isVideo: isVideo)
                        .frame(height: 126).frame(maxWidth: .infinity).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    Label(isVideo ? "VİDEO" : "FOTOĞRAF", systemImage: isVideo ? "play.fill" : "photo")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(project.settings.lutName == "Original" ? (isVideo ? "Video projesi" : "Fotoğraf projesi") : project.settings.lutName)
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
                HStack(spacing: 4) {
                    Text(project.createdAt, format: .dateTime.month(.abbreviated).day())
                    Text("·")
                    Text(project.settings.source)
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button(role: .destructive) { library.remove(project) } label: { Label("Projeyi sil", systemImage: "trash") } }
    }
    private func importImage(_ item: PhotosPickerItem) {
        Task { @MainActor in
            isImportingMedia = true
            defer { isImportingMedia = false; pickerItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw MediaImportError.imageDataUnavailable
                }
                guard UIImage(data: data) != nil else { throw MediaImportError.invalidImage }
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let project = try library.add(imageData: data, fileExtension: ext, source: SourceDetector.fromImage(data))
                editor = project
            } catch {
                importError = "Fotoğraf alınamadı: \(error.localizedDescription)"
            }
        }
    }
    private func importVideo(_ item: PhotosPickerItem) {
        Task { @MainActor in
            isImportingMedia = true
            defer { isImportingMedia = false; videoItem = nil }
            do {
                let movie = try await item.loadTransferable(type: PickedMovie.self)
                guard let movie else { throw MediaImportError.videoDataUnavailable }
                let sourceProfile = await SourceDetector.fromVideo(movie.url)
                let project = try library.add(video: movie.url, profile: sourceProfile)
                editor = project
            } catch {
                importError = "Video alınamadı: \(error.localizedDescription)"
            }
        }
    }
}

private enum MediaImportError: LocalizedError {
    case imageDataUnavailable
    case invalidImage
    case videoDataUnavailable
    var errorDescription: String? {
        switch self {
        case .imageDataUnavailable: return "Fotoğraf verisi Fotoğraflar’dan alınamadı."
        case .invalidImage: return "Seçilen dosya geçerli bir fotoğraf olarak açılamadı."
        case .videoDataUnavailable: return "Video dosyası Fotoğraflar’dan alınamadı."
        }
    }
}

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: false) { received in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}

enum SourceDetector {
    static let profiles = ["Regular", "Sony S-Log3 Cine", "Sony S-Log2", "OSMO Pocket 4 Pro (D-Log2)", "OSMO Pocket 4 Pro (D-Log)", "OSMO Pocket 4 (D-Log)", "D-Log M", "DJI Mini 4 Pro (D-Log M)", "Ace Pro 2 (I-Log)", "GO Ultra (I-Log)", "Luna Ultra (I-Log)", "Apple Log 2", "Apple Log"]
    private static func profile(from value: String) -> String {
        let s = value.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        if s.contains("s log3") || s.contains("slog3") { return "Sony S-Log3 Cine" }
        if s.contains("s log2") || s.contains("slog2") { return "Sony S-Log2" }
        if s.contains("pocket 4p") && s.contains("d log2") { return "OSMO Pocket 4 Pro (D-Log2)" }
        if s.contains("pocket 4p") && s.contains("d log") { return "OSMO Pocket 4 Pro (D-Log)" }
        if s.contains("pocket 4") && s.contains("d log") { return "OSMO Pocket 4 (D-Log)" }
        if s.contains("mini 4 pro") && (s.contains("d log m") || s.contains("dlogm")) { return "DJI Mini 4 Pro (D-Log M)" }
        if s.contains("go ultra") && (s.contains("i log") || s.contains("ilog")) { return "GO Ultra (I-Log)" }
        if s.contains("luna ultra") && (s.contains("i log") || s.contains("ilog")) { return "Luna Ultra (I-Log)" }
        if s.contains("d log m") || s.contains("dlogm") { return "D-Log M" }
        if s.contains("ace pro 2") || (s.contains("insta360") && s.contains("i log")) { return "Ace Pro 2 (I-Log)" }
        if s.contains("apple log 2") || s.contains("applelog2") { return "Apple Log 2" }
        if s.contains("apple log") || s.contains("applelog") { return "Apple Log" }
        return "Regular"
    }
    static func fromImage(_ data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return "Regular" }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        return profile(from: "\(tiff[kCGImagePropertyTIFFModel] ?? "") \(tiff[kCGImagePropertyTIFFSoftware] ?? "") \(exif[kCGImagePropertyExifUserComment] ?? "")")
    }
    static func fromVideo(_ url: URL) async -> String {
        let asset = AVURLAsset(url: url)
        var text = (try? await asset.load(.commonMetadata))?.compactMap(\.stringValue).joined(separator: " ") ?? ""
        if let tracks = try? await asset.loadTracks(withMediaType: .video) {
            for track in tracks {
                if let descriptions = try? await track.load(.formatDescriptions) {
                    for description in descriptions {
                        text += " \(CMFormatDescriptionGetExtensions(description))"
                    }
                }
            }
        }
        return profile(from: text)
    }
}

private struct MediaProjectThumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.white.opacity(0.06))
                    .overlay(Image(systemName: isVideo ? "film" : "photo").font(.system(size: 24, weight: .light)).foregroundStyle(accent.opacity(0.8)))
            }
        }
        .task(id: url) {
            if !isVideo {
                image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
                return
            }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            if let (cgImage, _) = try? await generator.image(at: .zero) { image = UIImage(cgImage: cgImage) }
        }
    }
}

struct EditorView: View {
    @EnvironmentObject private var library: ProjectLibrary; @Environment(\.dismiss) private var dismiss
    @State private var project: GradeProject; @State private var tab = 0; @State private var importedLUT: CubeLUT?; @State private var sourceLUT: CubeLUT?; @State private var bundledLUTs: [(String, String, URL)] = []; @State private var selectedCategory = "Cinematic"; @State private var importing = false; @State private var videoPlayer: AVPlayer?; @State private var videoDuration = 0.0; @State private var exportMessage: String?
    @State private var lutLoadError: String?; @State private var sourcePreviewImage: UIImage?
    @State private var showingOriginal = false; @State private var showingFullscreen = false; @State private var showingExportSettings = false; @State private var isFavorite = false
    @State private var undoStack: [GradeSettings] = []; @State private var redoStack: [GradeSettings] = []; @State private var navigatingHistory = false
    @State private var isExporting = false; @State private var exportProgress = 0.0
    private var isVideo: Bool { ["mov", "mp4", "m4v"].contains(URL(fileURLWithPath: project.fileName).pathExtension.lowercased()) }
    private var lutCategories: [String] {
        let available = Set(bundledLUTs.map { $0.0 })
        let preferred = ["Cinematic", "Social", "Clean", "Daily", "Essentials", "Movies", "Dark", "Kamera"]
        return preferred.filter { available.contains($0) } + available.subtracting(preferred).sorted()
    }
    private var visibleLUTs: [(String, String, URL)] { selectedCategory == "Tümü" ? bundledLUTs : bundledLUTs.filter { $0.0 == selectedCategory } }
    init(project: GradeProject) { _project = State(initialValue: project) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in preview.frame(maxWidth: proxy.size.width, maxHeight: .infinity) }
                    .frame(height: 330)
                    .padding(.horizontal, 12)
                previewActions
                HStack(spacing: 0) {
                    editorTab("Filtreler", symbol: "camera.filters", value: 0)
                    editorTab("Ayarla", symbol: "slider.horizontal.3", value: 1)
                    editorTab("Efektler", symbol: "sparkles", value: 2)
                }
                .padding(4)
                .background(Color(red: 0.27, green: 0.27, blue: 0.29), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .padding(.horizontal, 18).padding(.vertical, 10)
                panel.padding(.horizontal).padding(.bottom, 8)
            }
            .background(Color.black)
            .overlay { exportOverlay }
            .navigationTitle(project.settings.lutName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { library.update(project); videoPlayer?.pause(); dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingExportSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Dışa aktarma ayarları")
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                    Button { saveToPhotos() } label: { exportButtonLabel }
                        .accessibilityLabel("Dışa aktar")
                        .disabled(isExporting)
                }
            }
            .onAppear(perform: prepareEditor)
            .onDisappear { videoPlayer?.pause() }
            .onChange(of: project.settings) { oldValue, newValue in
                updateVideoComposition()
                guard !navigatingHistory, oldValue != newValue else { navigatingHistory = false; return }
                undoStack.append(oldValue)
                if undoStack.count > 100 { undoStack.removeFirst() }
                redoStack.removeAll()
            }
            .onChange(of: project.settings.lutName) { _, name in
                if name == "Original" { importedLUT = nil }
                else if let match = bundledLUTs.first(where: { $0.1 == name }) { importedLUT = CubeLUT.load(url: match.2) }
                updateVideoComposition()
            }
            .onChange(of: project.settings.source) { _, source in
                sourceLUT = CubeLUT.sourceTransform(for: source, bundled: bundledLUTs)
                updateVideoComposition()
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { result in
                if case let .success(url) = result {
                    guard let lut = CubeLUT.load(url: url) else { lutLoadError = "Bu LUT dosyası okunamadı. .cube dosyasının geçerli bir 3D LUT olduğundan emin olun."; return }
                    importedLUT = lut
                    project.settings.lutName = url.deletingPathExtension().lastPathComponent
                }
            }
            .sheet(isPresented: $showingExportSettings) {
                ExportSettingsView(settings: $project.settings, videoDuration: videoDuration)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showingFullscreen) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    preview.padding(12)
                    Button { showingFullscreen = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title).padding()
                    }.tint(.white).accessibilityLabel("Tam ekrandan çık")
                }
            }
            .alert("Dışa aktarma", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
                Button("Tamam", role: .cancel) { exportMessage = nil }
            } message: { Text(exportMessage ?? "") }
            .alert("LUT yüklenemedi", isPresented: Binding(get: { lutLoadError != nil }, set: { if !$0 { lutLoadError = nil } })) {
                Button("Tamam", role: .cancel) { lutLoadError = nil }
            } message: { Text(lutLoadError ?? "") }
        }
    }
    private func editorTab(_ title: String, symbol: String, value: Int) -> some View {
        Button { tab = value } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: tab == value ? .bold : .regular, design: .rounded))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(tab == value ? .black : .white.opacity(0.94))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(tab == value ? Color.white : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
    @ViewBuilder private var exportOverlay: some View {
        if isExporting {
            ZStack {
                Color.black.opacity(0.72).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView(value: exportProgress).tint(accent).frame(width: 220)
                    Text("Dışa aktarılıyor · %\(Int(exportProgress * 100))")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(isVideo ? "Video hazırlanıyor, uygulamayı açık tutun." : "Fotoğraf işleniyor…")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                }
                .padding(24).background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.1), lineWidth: 1))
            }
        }
    }
    @ViewBuilder private var exportButtonLabel: some View {
        if isExporting { ProgressView().tint(accent) }
        else { Image(systemName: "square.and.arrow.up") }
    }
    private var preview: some View {
        Group {
            if isVideo, let videoPlayer {
                VideoPlayer(player: videoPlayer)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .onLongPressGesture(minimumDuration: 0.12, pressing: { pressing in
                        showingOriginal = pressing
                        guard let item = videoPlayer.currentItem else { return }
                        item.videoComposition = pressing ? nil : makeVideoComposition(asset: item.asset)
                    }, perform: {})
                    .overlay(alignment: .top) {
                        if showingOriginal {
                            Text("ORİJİNAL").font(.caption.bold()).padding(8)
                                .background(.black.opacity(0.7), in: Capsule()).padding(.top, 10)
                        }
                    }
            }
            else if isVideo { ProgressView("Video yükleniyor") }
            else if let source = library.image(for: project) {
                let rendered = showingOriginal ? source : ImageRenderer.grade(source, settings: project.settings, lut: importedLUT, sourceLUT: sourceLUT)
                Image(uiImage: rendered).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18))
                    .onLongPressGesture(minimumDuration: 0.12, pressing: { pressing in showingOriginal = pressing }, perform: {})
                    .overlay(alignment: .top) { if showingOriginal { Text("ORİJİNAL").font(.caption.bold()).padding(8).background(.black.opacity(0.7), in: Capsule()).padding(.top, 10) } }
            } else { ContentUnavailableView("Orijinal dosya bulunamadı", systemImage: "exclamationmark.triangle") }
        }
    }
    private var previewActions: some View {
        HStack(spacing: 28) {
            Button(action: undo) { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty).accessibilityLabel("Geri al")
            Button(action: redo) { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty).accessibilityLabel("İleri al")
            Button { toggleFavorite() } label: { Image(systemName: isFavorite ? "heart.fill" : "heart") }.tint(isFavorite ? .pink : .white).accessibilityLabel(isFavorite ? "Favorilerden çıkar" : "Favoriye ekle")
            Button { showingFullscreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Tam ekran")
        }
        .font(.system(size: 18, weight: .semibold))
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }
    private func prepareEditor() {
        bundledLUTs = CubeLUT.loadBundled()
        if let match = bundledLUTs.first(where: { $0.1 == project.settings.lutName }) { importedLUT = CubeLUT.load(url: match.2) }
        sourceLUT = CubeLUT.sourceTransform(for: project.settings.source, bundled: bundledLUTs)
        if bundledLUTs.isEmpty { lutLoadError = "Uygulama paketinde LUT bulunamadı. Filtre dosyaları yüklenemedi." }
        isFavorite = UserDefaults.standard.stringArray(forKey: "lumagrade.favoriteProjects")?.contains(project.id.uuidString) ?? false
        if isVideo {
            let url = library.videoURL(for: project); let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.videoComposition = makeVideoComposition(asset: asset)
            videoPlayer = AVPlayer(playerItem: item)
            Task {
                if let duration = try? await asset.load(.duration) {
                    videoDuration = CMTimeGetSeconds(duration)
                }
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 720, height: 720)
                if let (frame, _) = try? await generator.image(at: .zero) { sourcePreviewImage = UIImage(cgImage: frame) }
            }
        }
    }
    private func updateVideoComposition() {
        guard isVideo, let item = videoPlayer?.currentItem else { return }
        let asset = item.asset
        item.videoComposition = makeVideoComposition(asset: asset)
    }
    private func makeVideoComposition(asset: AVAsset) -> AVVideoComposition {
        let settings = project.settings
        let lut = importedLUT
        let profileLUT = sourceLUT
        return AVVideoComposition(asset: asset) { request in
            let output = ImageRenderer.grade(request.sourceImage, settings: settings, lut: lut, sourceLUT: profileLUT)
            request.finish(with: output, context: ImageRenderer.context)
        }
    }
    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project.settings); navigatingHistory = true; project.settings = previous
    }
    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project.settings); navigatingHistory = true; project.settings = next
    }
    private func toggleFavorite() {
        var favorites = Set(UserDefaults.standard.stringArray(forKey: "lumagrade.favoriteProjects") ?? [])
        if isFavorite { favorites.remove(project.id.uuidString) } else { favorites.insert(project.id.uuidString) }
        UserDefaults.standard.set(Array(favorites), forKey: "lumagrade.favoriteProjects")
        isFavorite.toggle()
    }
    @ViewBuilder private var panel: some View {
        switch tab {
        case 0:
            FilterBrowser(items: bundledLUTs, categories: lutCategories, selectedCategory: $selectedCategory, selectedName: $project.settings.lutName, selectedLUT: $importedLUT, intensity: $project.settings.intensity, sourceImage: sourcePreviewImage ?? library.image(for: project), settings: project.settings, sourceLUT: sourceLUT, loadError: $lutLoadError)
        case 1:
            AdjustmentPanel(settings: $project.settings, isVideo: isVideo, videoDuration: videoDuration)
        default:
            SliderPanel(settings: $project.settings, labels: [("Vinyet", \GradeSettings.vignette, 0...2), ("Parlama", \GradeSettings.bloom, 0...1), ("Gren", \GradeSettings.grain, 0...1)])
        }
    }
    private func saveToPhotos() {
        if isVideo { exportTrimmedVideo(); return }
        guard let image = library.image(for: project) else { return }
        let settings = project.settings; let lut = importedLUT; let profileLUT = sourceLUT
        isExporting = true; exportProgress = 0.05
        Task { @MainActor in
            await Task.yield()
            let output = await Task.detached(priority: .userInitiated) {
                let graded = ImageRenderer.grade(image, settings: settings, lut: lut, sourceLUT: profileLUT)
                return ImageRenderer.resized(graded, resolution: settings.exportResolution)
            }.value
            exportProgress = 0.8
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else { DispatchQueue.main.async { isExporting = false; exportMessage = "Fotoğraf arşivine ekleme izni verilmedi." }; return }
                PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: output) } completionHandler: { saved, error in
                    DispatchQueue.main.async { isExporting = false; exportProgress = 1; exportMessage = saved ? "Fotoğraf arşive kaydedildi." : (error?.localizedDescription ?? "Fotoğraf kaydedilemedi.") }
                }
            }
        }
    }
    @MainActor private func exportTrimmedVideo() {
        let asset = AVURLAsset(url: library.videoURL(for: project))
        Task { await exportVideo(asset) }
    }
    @MainActor private func exportVideo(_ asset: AVAsset) async {
        do {
                isExporting = true; exportProgress = 0.02
                let duration = CMTimeGetSeconds(try await asset.load(.duration))
                let start = min(duration, max(0, duration * project.settings.trimStart))
                let end = min(duration, max(start + 0.05, duration * project.settings.trimEnd))
                guard end > start else { throw CocoaError(.fileWriteInvalidFileName) }
                let supported = AVAssetExportSession.exportPresets(compatibleWith: asset)
                let preset = exportPreset(codec: project.settings.exportCodec, resolution: project.settings.exportResolution, supported: supported)
                guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw CocoaError(.fileWriteUnknown) }
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("LumaGrade-\(UUID().uuidString).mov")
                session.outputURL = output; session.outputFileType = .mov
                session.videoComposition = makeVideoComposition(asset: asset)
                session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
                let bitrate = effectiveBitrateMbps
                if project.settings.exportBitrateMode == "El ile", project.settings.exportCodec != "ProRes" {
                    session.fileLengthLimit = Int64((end - start) * bitrate * 1_000_000 / 8 * 1.08)
                }
                let progressTask = Task { @MainActor in
                    while ![AVAssetExportSession.Status.completed, .failed, .cancelled].contains(session.status) {
                        exportProgress = max(exportProgress, Double(session.progress) * 0.94)
                        try? await Task.sleep(for: .milliseconds(180))
                    }
                }
                let status: AVAssetExportSession.Status = await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume(returning: session.status) }
                }
                progressTask.cancel()
                guard status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
                    guard authorization == .authorized || authorization == .limited else { DispatchQueue.main.async { isExporting = false; exportMessage = "Fotoğraf arşivine ekleme izni verilmedi." }; return }
                    PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: output) } completionHandler: { saved, error in
                        try? FileManager.default.removeItem(at: output)
                        DispatchQueue.main.async { isExporting = false; exportProgress = 1; exportMessage = saved ? "Düzenlenmiş video arşive kaydedildi." : (error?.localizedDescription ?? "Video kaydedilemedi.") }
                    }
                }
        } catch { isExporting = false; exportProgress = 0; exportMessage = error.localizedDescription }
    }
    private var effectiveBitrateMbps: Double {
        if project.settings.exportBitrateMode == "El ile" { return project.settings.exportBitrateMbps }
        switch project.settings.exportResolution {
        case "540p": return 5
        case "720p": return 8
        case "1080p": return 16
        case "1440p": return 28
        default: return project.settings.exportCodec == "ProRes" ? 300 : 20
        }
    }
    private func exportPreset(codec: String, resolution: String, supported: [String]) -> String {
        if codec == "ProRes" {
            let proRes = "AVAssetExportPresetAppleProRes422LPCM"
            if supported.contains(proRes) { return proRes }
        } else if codec == "HEVC" {
            let hevcSizePreset: String?
            switch resolution {
            case "1080p": hevcSizePreset = "AVAssetExportPresetHEVC1920x1080"
            case "1440p": hevcSizePreset = "AVAssetExportPresetHEVC3840x2160"
            default: hevcSizePreset = nil
            }
            if let hevcSizePreset, supported.contains(hevcSizePreset) { return hevcSizePreset }
            if supported.contains(AVAssetExportPresetHEVCHighestQuality) { return AVAssetExportPresetHEVCHighestQuality }
        } else {
            let h264SizePreset: String?
            switch resolution {
            case "540p": h264SizePreset = "AVAssetExportPreset960x540"
            case "720p": h264SizePreset = "AVAssetExportPreset1280x720"
            case "1080p": h264SizePreset = "AVAssetExportPreset1920x1080"
            default: h264SizePreset = nil
            }
            if let h264SizePreset, supported.contains(h264SizePreset) { return h264SizePreset }
            if supported.contains(AVAssetExportPresetHighestQuality) { return AVAssetExportPresetHighestQuality }
        }
        return supported.first ?? AVAssetExportPresetHighestQuality
    }
}

struct SliderPanel: View { @Binding var settings: GradeSettings; let labels: [(String, WritableKeyPath<GradeSettings, Double>, ClosedRange<Double>)]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Kaynak profili"); Spacer(); Picker("Kaynak profili", selection: $settings.source) { ForEach(SourceDetector.profiles, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(labels.indices, id: \.self) { index in
                        let item = labels[index]
                        VStack(alignment: .leading) {
                            Text(item.0).font(.caption)
                            Slider(value: Binding(get: { settings[keyPath: item.1] }, set: { settings[keyPath: item.1] = $0 }), in: item.2).frame(width: 160)
                            Text(settings[keyPath: item.1], format: .number.precision(.fractionLength(2))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 4)
            }
        }
    }
}

struct ExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: GradeSettings
    let videoDuration: Double
    private var suggestedBitrate: Double {
        if settings.exportCodec == "ProRes" { return 300 }
        switch settings.exportResolution {
        case "540p": return 5
        case "720p": return 8
        case "1080p": return 16
        case "1440p": return 28
        default: return 20
        }
    }
    private var bitrateRange: ClosedRange<Double> { settings.exportCodec == "ProRes" ? 50...600 : 2...100 }
    private var activeBitrate: Double { settings.exportBitrateMode == "Otomatik" ? suggestedBitrate : settings.exportBitrateMbps }
    private var estimatedMegabytes: Double { max(0, videoDuration) * activeBitrate / 8 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Video çıktısı") {
                    Picker("Codec", selection: $settings.exportCodec) {
                        ForEach(["HEVC", "H.264", "ProRes"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Çözünürlük", selection: $settings.exportResolution) {
                        ForEach(["540p", "720p", "1080p", "1440p", "Orijinal"], id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Bitrate") {
                    Picker("Bitrate modu", selection: $settings.exportBitrateMode) {
                        Text("Önerilen").tag("Otomatik")
                        Text("El ile").tag("El ile")
                    }.pickerStyle(.segmented)
                    if settings.exportBitrateMode == "El ile" {
                        HStack {
                            Text("Mbps")
                            Slider(value: $settings.exportBitrateMbps, in: bitrateRange, step: 1)
                            Text("\(Int(settings.exportBitrateMbps))").monospacedDigit().frame(minWidth: 38, alignment: .trailing)
                        }
                    } else {
                        LabeledContent("Önerilen bitrate", value: "\(Int(suggestedBitrate)) Mbps")
                    }
                }
                Section("Tahmini dosya boyutu") {
                    if videoDuration > 0 {
                        LabeledContent("Video", value: String(format: "%.1f MB", estimatedMegabytes))
                        Text("Tahmin, seçilen bitrate ve kesilmiş video süresine göre hesaplanır.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Fotoğraf dışa aktarımında dosya boyutu kaynak fotoğrafa ve seçilen çözünürlüğe göre değişir.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Dışa aktarma")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Bitti") { dismiss() } } }
        }
    }
}

private enum AdjustmentControl: String, CaseIterable, Identifiable {
    case auto = "Otomatik", brilliance = "Pırıldama", exposure = "Pozlama", shadows = "Gölgeler", highlights = "Açık alanlar", whites = "Beyazlar", blacks = "Siyahlar", blackPoint = "Siyah noktası"
    case temperature = "Sıcaklık", tint = "Tint", contrast = "Kontrast", hue = "Hue", lightness = "HLS Açıklık"
    case vibrance = "Canlılık", saturation = "Doygunluk", sharpness = "Keskinlik", definition = "Tanım", noiseReduction = "Gürültü azaltma", vignette = "Vinyet"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .brilliance: return "sparkles"
        case .exposure: return "sun.max"
        case .shadows: return "moon"
        case .highlights: return "sun.max.fill"
        case .whites: return "circle.lefthalf.filled"
        case .blacks: return "circle.lefthalf.striped.horizontal"
        case .blackPoint: return "circle.bottomhalf.filled"
        case .temperature: return "thermometer.medium"
        case .tint: return "drop.halffull"
        case .contrast: return "circle.lefthalf.filled"
        case .hue: return "circle.hexagongrid"
        case .lightness: return "sun.horizon"
        case .vibrance: return "sparkles"
        case .saturation: return "drop.fill"
        case .sharpness: return "triangle"
        case .definition: return "viewfinder"
        case .noiseReduction: return "circle.dotted"
        case .vignette: return "viewfinder"
        }
    }
    var keyPath: WritableKeyPath<GradeSettings, Double>? {
        switch self {
        case .auto: return nil
        case .brilliance: return \.brilliance
        case .exposure: return \.exposure
        case .shadows: return \.shadows
        case .highlights: return \.highlights
        case .whites: return \.whites
        case .blacks: return \.blacks
        case .blackPoint: return \.blackPoint
        case .temperature: return \.temperature
        case .tint: return \.tint
        case .contrast: return \.contrast
        case .hue: return nil
        case .lightness: return \.brightness
        case .vibrance: return \.vibrance
        case .saturation: return \.saturation
        case .sharpness: return \.sharpness
        case .definition: return \.definition
        case .noiseReduction: return \.noiseReduction
        case .vignette: return \.vignette
        }
    }
    var range: ClosedRange<Double> {
        switch self {
        case .auto: return 0...1
        case .brilliance: return -1...1
        case .exposure: return -4...4
        case .shadows: return -1...1
        case .highlights: return 0...2
        case .whites, .blacks, .vibrance: return -1...1
        case .blackPoint: return -1...1
        case .temperature: return 2000...12000
        case .tint: return -100...100
        case .contrast, .saturation: return 0...2
        case .hue: return -180...180
        case .lightness: return -0.5...0.5
        case .sharpness, .definition, .noiseReduction, .vignette: return 0...2
        }
    }
    var defaultValue: Double {
        switch self {
        case .auto: return 0
        case .highlights: return 1
        case .temperature: return 6500
        case .contrast, .saturation: return 1
        default: return 0
        }
    }
}

struct AdjustmentPanel: View {
    @Binding var settings: GradeSettings
    var isVideo = false
    var videoDuration = 0.0
    @State private var selected: AdjustmentControl = .exposure

    private var value: Binding<Double> {
        if selected == .auto { return Binding(get: { settings.autoEnhance ? 1 : 0 }, set: { settings.autoEnhance = $0 >= 0.5 }) }
        if selected == .hue {
            return Binding(get: { settings.hue * 180 / Double.pi }, set: { settings.hue = $0 * Double.pi / 180 })
        }
        let key = selected.keyPath!
        return Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 })
    }
    private var valueText: String {
        let number = selected == .temperature ? String(Int(value.wrappedValue)) : String(format: "%.2f", value.wrappedValue)
        if selected == .hue { return "\(Int(value.wrappedValue.rounded()))°" }
        if selected == .temperature { return "\(number) K" }
        return number
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Kaynak profili", systemImage: "camera.aperture").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 8)
                    Button {
                        settings.autoEnhance.toggle()
                        selected = .auto
                    } label: {
                        Label("Otomatik", systemImage: "wand.and.stars")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(settings.autoEnhance ? .black : accent)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(settings.autoEnhance ? accent : accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Picker("Kaynak profili", selection: $settings.source) {
                        ForEach(SourceDetector.profiles, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden().tint(accent).font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))

                VStack(spacing: 8) {
                    HStack {
                        Text(selected.rawValue).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(valueText).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(accent)
                        Button { value.wrappedValue = selected.defaultValue } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                                .frame(width: 28, height: 28).background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(selected.rawValue) sıfırla")
                    }
                    Slider(value: value, in: selected.range).tint(accent)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(AdjustmentControl.allCases) { control in
                            Button {
                                if control == .auto { settings.autoEnhance.toggle() }
                                else { selected = control }
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: control.symbol).font(.system(size: 16, weight: .medium))
                                    Text(control.rawValue).font(.system(size: 8, weight: .medium)).lineLimit(1)
                                }
                                .foregroundStyle((selected == control || (control == .auto && settings.autoEnhance)) ? accent : .white.opacity(0.55))
                                .frame(width: 54).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 4).padding(.vertical, 3)
                }

                DisclosureGroup("Renk tekerleri") {
                    settingSlider("Gölgeler", \.wheelShadows, -1...1)
                    settingSlider("Orta tonlar", \.wheelMidtones, -1...1)
                    settingSlider("Açık alanlar", \.wheelHighlights, -1...1)
                }
                DisclosureGroup("Eğriler") {
                    settingSlider("Siyah noktası", \.curveBlack, 0...0.25)
                    settingSlider("Orta nokta", \.curveMid, 0.1...0.9)
                    settingSlider("Beyaz noktası", \.curveWhite, 0.75...1)
                }
                DisclosureGroup("Maske") {
                    Toggle("Merkez maskesini etkinleştir", isOn: $settings.maskEnabled).tint(accent)
                    settingSlider("Maskeli pozlama", \.maskExposure, -3...3)
                    settingSlider("Maske boyutu", \.maskRadius, 0.1...1)
                    settingSlider("Kenar yumuşatma", \.maskFeather, 0.02...0.6)
                }
                DisclosureGroup("Kırpma") {
                    Picker("En-boy oranı", selection: $settings.cropAspect) {
                        ForEach(["Orijinal", "1:1", "4:5", "16:9", "9:16"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if isVideo && videoDuration > 0 {
                    DisclosureGroup("Video kesme · \(time(settings.trimStart * videoDuration)) – \(time(settings.trimEnd * videoDuration))") {
                        Text("Başlangıç · \(time(settings.trimStart * videoDuration))").font(.caption)
                        Slider(value: Binding(get: { settings.trimStart }, set: { settings.trimStart = min($0, settings.trimEnd) }), in: 0...1).tint(accent)
                        Text("Bitiş · \(time(settings.trimEnd * videoDuration))").font(.caption)
                        Slider(value: Binding(get: { settings.trimEnd }, set: { settings.trimEnd = max($0, settings.trimStart) }), in: 0...1).tint(accent)
                    }
                }
            }
            .font(.system(size: 12)).foregroundStyle(.white)
            .padding(.vertical, 6)
        }
        .frame(maxHeight: 245)
    }

    private func settingSlider(_ title: String, _ key: WritableKeyPath<GradeSettings, Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack { Text(title).font(.caption); Spacer(); Text(settings[keyPath: key], format: .number.precision(.fractionLength(2))).font(.caption2).foregroundStyle(.secondary) }
            Slider(value: Binding(get: { settings[keyPath: key] }, set: { settings[keyPath: key] = $0 }), in: range).tint(accent)
        }
    }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60) }
}

struct FilterBrowser: View {
    let items: [(String, String, URL)]
    let categories: [String]
    @Binding var selectedCategory: String
    @Binding var selectedName: String
    @Binding var selectedLUT: CubeLUT?
    @Binding var intensity: Double
    let sourceImage: UIImage?
    let settings: GradeSettings
    let sourceLUT: CubeLUT?
    @Binding var loadError: String?
    private var visibleItems: [(String, String, URL)] { items.filter { $0.0 == selectedCategory } }
    private var tileWidth: CGFloat { min(max(UIScreen.main.bounds.width * 0.38, 136), 286) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories, id: \.self) { name in
                        Button { selectedCategory = name } label: {
                            HStack(spacing: 7) {
                                Text(name)
                                if selectedCategory == name { Circle().fill(.black).frame(width: 8, height: 8) }
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(selectedCategory == name ? .black : .white)
                            .padding(.horizontal, selectedCategory == name ? 15 : 11).padding(.vertical, 10)
                            .background(selectedCategory == name ? accent : .clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 45)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    Button { selectedLUT = nil; selectedName = "Original" } label: {
                        LUTTile(name: "Yok", sourceImage: sourceImage, settings: settings, lut: nil, sourceLUT: sourceLUT, selected: selectedName == "Original", width: tileWidth)
                    }.buttonStyle(.plain)
                    ForEach(Array(visibleItems.enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        Button {
                            guard let lut = CubeLUT.load(url: item.2) else {
                                loadError = "\(item.1) LUT dosyası okunamadı. Uygulamayı güncelleyip tekrar deneyin."
                                return
                            }
                            selectedLUT = lut
                            selectedName = item.1
                        } label: {
                            LUTTile(name: item.1, sourceImage: sourceImage, settings: settings, lut: CubeLUT.load(url: item.2), sourceLUT: sourceLUT, selected: selectedName == item.1, width: tileWidth)
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: 16) {
                Text("Yoğunluk").font(.system(size: 16, weight: .regular, design: .rounded)).frame(width: 92, alignment: .leading)
                Slider(value: $intensity, in: 0...100).tint(.white).disabled(selectedLUT == nil)
                Text("\(Int(intensity.rounded()))%").font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.6)).frame(width: 38, alignment: .trailing)
            }
            .foregroundStyle(.white)
        }
        .padding(.top, 3)
    }
}

struct LUTTile: View {
    let name: String
    let sourceImage: UIImage?
    let settings: GradeSettings
    let lut: CubeLUT?
    let sourceLUT: CubeLUT?
    let selected: Bool
    let width: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let sourceImage {
                    Image(uiImage: ImageRenderer.thumbnail(sourceImage, settings: settings, lut: lut, sourceLUT: sourceLUT)).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.purple, .orange, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: width, height: min(width * 0.96, 250)).clipped()
            Text(name)
                .font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                .foregroundStyle(selected ? .black : .white)
                .frame(width: width, height: 45)
                .background(selected ? accent : Color(red: 0.105, green: 0.105, blue: 0.12))
        }
        .frame(width: width)
        .background(Color(red: 0.105, green: 0.105, blue: 0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(selected ? accent.opacity(0.75) : .white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("LumaGrade") {
                    LabeledContent("Sürüm", value: "1.0")
                    Text("Kişisel renk düzenleme alanınız.")
                }
                Section("Gizlilik") {
                    Text("Fotoğraf ve videolarınız bu aygıtta kalır.")
                    Button("Fotoğraflar için tam erişim ayarları") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
            }
            .navigationTitle("Profil")
        }
    }
}

struct CubeLUT { let dimension: Int; let values: [Float]
    static func sourceTransform(for profile: String, bundled: [(String, String, URL)]) -> CubeLUT? {
        let candidates: [String]
        switch profile {
        case "D-Log M": candidates = ["D-LogM"]
        case "DJI Mini 4 Pro (D-Log M)": candidates = ["DJI Mini 4 Pro D-Log M to Rec709", "D-LogM"]
        case "OSMO Pocket 4 Pro (D-Log2)": candidates = ["DJI OSMO Pocket 4P D-Log2 to Rec.709"]
        case "OSMO Pocket 4 Pro (D-Log)": candidates = ["DJI OSMO Pocket 4 D-Log to Rec.709"]
        case "OSMO Pocket 4 (D-Log)": candidates = ["DJI OSMO Pocket 4 D-Log to Rec.709"]
        case "Sony S-Log2": candidates = ["Sony S-Log2 to Rec709"]
        case "Sony S-Log3 Cine": candidates = ["Sony S-Log3 Cine to Rec709"]
        case "Ace Pro 2 (I-Log)": candidates = ["AcePro2_I-Log"]
        case "GO Ultra (I-Log)": candidates = ["GO Ultra_I-Log"]
        case "Luna Ultra (I-Log)": candidates = ["Luna_Ultra_I-Log"]
        case "Apple Log 2": candidates = ["AppleLog2"]
        case "Apple Log": candidates = ["AppleLog"]
        default: return nil
        }
        guard let match = bundled.first(where: { candidates.contains($0.1) }) else { return nil }
        return load(url: match.2)
    }
    static func loadBundled() -> [(String, String, URL)] {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("LUTs", isDirectory: true),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { item -> (String, String, URL)? in
            guard let url = item as? URL, url.pathExtension.lowercased() == "lutf" else { return nil }
            let parent = url.deletingLastPathComponent().lastPathComponent
            let category = parent == "LUTs" ? "Kamera" : parent
            return (category, url.deletingPathExtension().lastPathComponent, url)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
    static func load(url: URL) -> CubeLUT? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.lowercased() == "lutf" {
            guard let data = try? Data(contentsOf: url), data.count >= 8,
                  data.prefix(4) == Data([0x4c, 0x55, 0x54, 0x46]) else { return nil }
            let dimension = Int(data[4]) | Int(data[5]) << 8 | Int(data[6]) << 16 | Int(data[7]) << 24
            let valueCount = dimension * dimension * dimension * 3
            guard dimension > 1, data.count == 8 + valueCount * 2 else { return nil }
            var values = [Float](); values.reserveCapacity(valueCount)
            for index in 0..<valueCount {
                let offset = 8 + index * 2
                let bits = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
                values.append(Float(Float16(bitPattern: bits)))
            }
            return CubeLUT(dimension: dimension, values: values)
        }
        guard let text = try? String(contentsOf: url) else { return nil }
        var size: Int?; var values: [Float] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("LUT_3D_SIZE") { size = Int(line.split(separator: " ").last ?? "") }
            let numbers = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }
            if numbers.count == 3 { values.append(contentsOf: numbers) }
        }
        guard let dimension = size, values.count == dimension * dimension * dimension * 3 else { return nil }
        return CubeLUT(dimension: dimension, values: values)
    }
}

enum ImageRenderer { static let context = CIContext()
    static func resized(_ image: UIImage, resolution: String) -> UIImage {
        let longestEdge: CGFloat
        switch resolution {
        case "540p": longestEdge = 960
        case "720p": longestEdge = 1280
        case "1080p": longestEdge = 1920
        case "1440p": longestEdge = 2560
        default: return image
        }
        let pixelWidth = CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let pixelHeight = CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
        let factor = min(1, longestEdge / max(pixelWidth, pixelHeight))
        let target = CGSize(width: max(1, pixelWidth * factor), height: max(1, pixelHeight * factor))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    static func thumbnail(_ source: UIImage, settings: GradeSettings, lut: CubeLUT?, sourceLUT: CubeLUT? = nil) -> UIImage {
        let target = CGSize(width: 180, height: 112)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in
            let scale = max(target.width / source.size.width, target.height / source.size.height)
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let rect = CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height)
            source.draw(in: rect)
        }
        return grade(small, settings: settings, lut: lut, sourceLUT: sourceLUT)
    }
    static func rgbaData(from rgb: [Float], dimension: Int) -> Data {
        // Resolve .cube data already varies red fastest, as CIColorCube expects.
        var rgba = [Float](repeating: 1, count: dimension * dimension * dimension * 4)
        for index in 0..<(dimension * dimension * dimension) {
            let source = index * 3
            let target = index * 4
            rgba[target] = rgb[source]
            rgba[target + 1] = rgb[source + 1]
            rgba[target + 2] = rgb[source + 2]
            rgba[target + 3] = 1
        }
        return rgba.withUnsafeBufferPointer { Data(bytes: $0.baseAddress!, count: $0.count * MemoryLayout<Float>.size) }
    }
    static func grade(_ source: UIImage, settings: GradeSettings, lut: CubeLUT?, sourceLUT: CubeLUT? = nil) -> UIImage {
        guard let input = CIImage(image: source) else { return source }
        let image = grade(input, settings: settings, lut: lut, sourceLUT: sourceLUT)
        guard let cg = context.createCGImage(image, from: image.extent) else { return source }
        return UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
    }
    static func grade(_ source: CIImage, settings: GradeSettings, lut: CubeLUT?, sourceLUT: CubeLUT? = nil) -> CIImage {
        var image = source
        image = crop(image, aspect: settings.cropAspect)

        if let sourceLUT { image = apply(sourceLUT, to: image, intensity: 1) }

        if let lut { image = apply(lut, to: image, intensity: min(1, max(0, settings.intensity / 100))) }

        if settings.autoEnhance {
            let options: [CIImageAutoAdjustmentOption: Any] = [.enhance: true, .redEye: false]
            for filter in image.autoAdjustmentFilters(options: options) {
                filter.setValue(image, forKey: kCIInputImageKey)
                if let corrected = filter.outputImage { image = corrected }
            }
        }

        if settings.brilliance != 0 {
            let brilliance = CIFilter.highlightShadowAdjust()
            brilliance.inputImage = image
            brilliance.shadowAmount = Float(1 + settings.brilliance * 0.32)
            brilliance.highlightAmount = Float(1 - settings.brilliance * 0.22)
            image = brilliance.outputImage ?? image
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.saturation = Float(settings.saturation)
        controls.brightness = Float(settings.brightness)
        controls.contrast = Float(settings.contrast)
        image = controls.outputImage ?? image

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(settings.exposure)
        image = exposure.outputImage ?? image

        if settings.shadows != 0 || settings.highlights != 1 {
            let tone = CIFilter.highlightShadowAdjust()
            tone.inputImage = image
            tone.shadowAmount = Float(settings.shadows)
            tone.highlightAmount = Float(settings.highlights)
            image = tone.outputImage ?? image
        }

        let tempTint = CIFilter.temperatureAndTint()
        tempTint.inputImage = image
        tempTint.neutral = CIVector(x: 6500, y: 0)
        if settings.temperature != 6500 || settings.tint != 0 {
            tempTint.targetNeutral = CIVector(x: CGFloat(settings.temperature), y: CGFloat(settings.tint))
            image = tempTint.outputImage ?? image
        }

        let hueFilter = CIFilter.hueAdjust()
        hueFilter.inputImage = image
        hueFilter.angle = Float(settings.hue)
        image = hueFilter.outputImage ?? image

        let vibranceFilter = CIFilter.vibrance()
        vibranceFilter.inputImage = image
        vibranceFilter.amount = Float(settings.vibrance)
        image = vibranceFilter.outputImage ?? image

        if settings.noiseReduction > 0 {
            let denoise = CIFilter(name: "CINoiseReduction")
            denoise?.setValue(image, forKey: kCIInputImageKey)
            denoise?.setValue(Float(settings.noiseReduction) * 0.08, forKey: "inputNoiseLevel")
            denoise?.setValue(Float(1 - settings.noiseReduction * 0.7), forKey: "inputSharpness")
            image = denoise?.outputImage ?? image
        }
        let sharp = CIFilter.unsharpMask()
        sharp.inputImage = image
        sharp.radius = Float(1 + settings.definition * 2)
        sharp.intensity = Float(settings.sharpness * 0.65 + settings.definition * 0.5)
        image = sharp.outputImage ?? image

        if settings.blacks != 0 || settings.blackPoint != 0 || settings.whites != 0 || settings.wheelShadows != 0 || settings.wheelMidtones != 0 || settings.wheelHighlights != 0 || settings.curveBlack != 0 || settings.curveMid != 0.5 || settings.curveWhite != 1 {
            let levels = CIFilter.colorMatrix()
            levels.inputImage = image
            let blackPoint = min(0.45, max(-0.25, settings.blacks * 0.12 + settings.blackPoint * 0.12 + settings.curveBlack))
            let whitePoint = min(1.25, max(0.55, 1 + settings.whites * 0.12 + (settings.curveWhite - 1)))
            let scale = CGFloat(1 / max(0.1, whitePoint - blackPoint))
            levels.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            levels.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            levels.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            let offset = -blackPoint * scale
            let redBalance = CGFloat(settings.wheelShadows * 0.025 + settings.wheelMidtones * 0.035 + settings.wheelHighlights * 0.045)
            let greenBalance = CGFloat(-settings.wheelShadows * 0.005 + settings.wheelMidtones * 0.004 - settings.wheelHighlights * 0.005)
            let blueBalance = CGFloat(-settings.wheelShadows * 0.035 - settings.wheelMidtones * 0.025 - settings.wheelHighlights * 0.045)
            levels.biasVector = CIVector(x: offset + redBalance, y: offset + greenBalance, z: offset + blueBalance, w: 0)
            image = levels.outputImage ?? image
            if settings.curveMid != 0.5 {
                let gamma = CIFilter.gammaAdjust()
                gamma.inputImage = image
                gamma.power = Float(log(0.5) / log(settings.curveMid))
                image = gamma.outputImage ?? image
            }
        }

        if settings.maskEnabled && settings.maskExposure != 0 {
            let radius = Float(min(image.extent.width, image.extent.height) * settings.maskRadius * 0.5)
            let feather = Float(min(image.extent.width, image.extent.height) * settings.maskFeather * 0.5)
            let radial = CIFilter.radialGradient()
            radial.center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            radial.radius0 = radius
            radial.radius1 = radius + max(1, feather)
            radial.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
            radial.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            let mask = radial.outputImage?.cropped(to: image.extent)
            let localExposure = CIFilter.exposureAdjust()
            localExposure.inputImage = image
            localExposure.ev = Float(settings.maskExposure)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = localExposure.outputImage ?? image
            blend.backgroundImage = image
            blend.maskImage = mask
            image = blend.outputImage ?? image
        }
        if settings.bloom > 0 {
            let bloom = CIFilter.bloom(); bloom.inputImage = image; bloom.intensity = Float(settings.bloom); bloom.radius = 8
            image = bloom.outputImage ?? image
        }
        if settings.vignette > 0 {
            let vignette = CIFilter.vignette(); vignette.inputImage = image; vignette.intensity = Float(settings.vignette); vignette.radius = 1.4
            image = vignette.outputImage ?? image
        }
        if settings.grain > 0, let noise = CIFilter.randomGenerator().outputImage?.cropped(to: image.extent) {
            let monochrome = CIFilter.colorControls()
            monochrome.inputImage = noise
            monochrome.saturation = 0
            let softLight = CIFilter.softLightBlendMode()
            softLight.inputImage = monochrome.outputImage ?? noise
            softLight.backgroundImage = image
            if let textured = softLight.outputImage {
                let blend = CIFilter.blendWithMask()
                blend.inputImage = textured
                blend.backgroundImage = image
                let amount = CGFloat(min(1, max(0, settings.grain)) * 0.35)
                blend.maskImage = CIImage(color: CIColor(red: amount, green: amount, blue: amount)).cropped(to: image.extent)
                image = blend.outputImage ?? textured
            }
        }
        return image
    }

    private static func apply(_ lut: CubeLUT, to image: CIImage, intensity: Double) -> CIImage {
        guard let cube = CIFilter(name: "CIColorCubeWithColorSpace"),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        cube.setValue(image, forKey: kCIInputImageKey)
        cube.setValue(Float(lut.dimension), forKey: "inputCubeDimension")
        cube.setValue(rgbaData(from: lut.values, dimension: lut.dimension), forKey: "inputCubeData")
        cube.setValue(colorSpace, forKey: "inputColorSpace")
        guard let graded = cube.outputImage else { return image }
        guard intensity < 1 else { return graded }
        let blend = CIFilter.blendWithMask()
        blend.inputImage = graded
        blend.backgroundImage = image
        let opacity = CGFloat(intensity)
        blend.maskImage = CIImage(color: CIColor(red: opacity, green: opacity, blue: opacity)).cropped(to: image.extent)
        return blend.outputImage ?? image
    }

    private static func crop(_ image: CIImage, aspect: String) -> CIImage {
        let targetRatio: CGFloat
        switch aspect {
        case "1:1": targetRatio = 1
        case "4:5": targetRatio = 4.0 / 5.0
        case "16:9": targetRatio = 16.0 / 9.0
        case "9:16": targetRatio = 9.0 / 16.0
        default: return image
        }
        let extent = image.extent
        let sourceRatio = extent.width / extent.height
        let rect: CGRect
        if sourceRatio > targetRatio {
            let width = extent.height * targetRatio
            rect = CGRect(x: extent.midX - width / 2, y: extent.minY, width: width, height: extent.height)
        } else {
            let height = extent.width / targetRatio
            rect = CGRect(x: extent.minX, y: extent.midY - height / 2, width: extent.width, height: height)
        }
        return image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }
}
