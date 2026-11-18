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
    var source = "Regular"
    enum CodingKeys: String, CodingKey { case lutName, intensity, exposure, contrast, saturation, brightness, temperature, tint, highlights, shadows, whites, blacks, hue, vibrance, sharpness, curveBlack, curveMid, curveWhite, wheelShadows, wheelMidtones, wheelHighlights, cropAspect, maskEnabled, maskExposure, maskRadius, maskFeather, trimStart, trimEnd, exportCodec, exportResolution, exportBitrateMode, exportBitrateMbps, vignette, bloom, grain, source }
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
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "Regular"
    }
}

final class ProjectLibrary: ObservableObject {
    @Published var projects: [GradeProject] = [] { didSet { save() } }
    private let key = "lumagrade.projects.v1"
    init() { guard let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode([GradeProject].self, from: data) else { return }; projects = stored }
    func add(image: UIImage, source: String = "Regular") -> GradeProject? { guard let data = image.jpegData(compressionQuality: 0.96) else { return nil }; let name = "\(UUID().uuidString).jpg"; let url = documents.appendingPathComponent(name); do { try data.write(to: url, options: .atomic); var settings = GradeSettings(); settings.source = source; let project = GradeProject(fileName: name, settings: settings); projects.insert(project, at: 0); return project } catch { return nil } }
    func add(video source: URL, profile: String = "Regular") -> GradeProject? { let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension; let name = "\(UUID().uuidString).\(ext)"; let destination = documents.appendingPathComponent(name); do { try FileManager.default.copyItem(at: source, to: destination); var settings = GradeSettings(); settings.source = profile; let project = GradeProject(fileName: name, settings: settings); projects.insert(project, at: 0); return project } catch { return nil } }
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
    @State private var pickerItem: PhotosPickerItem?; @State private var videoItem: PhotosPickerItem?; @State private var editor: GradeProject?; @State private var importing = false; @State private var choosingMedia = false
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]
    var body: some View { NavigationStack { ZStack(alignment: .bottom) { Group { if library.projects.isEmpty { empty } else { ScrollView { LazyVGrid(columns: columns, spacing: 16) { ForEach(library.projects) { project in card(project) } }.padding(16).padding(.bottom, 80) } } }.navigationTitle("Projeler").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { PhotosPicker(selection: $pickerItem, matching: .images) { Label("Fotoğraf Ekle", systemImage: "photo") }; PhotosPicker(selection: $videoItem, matching: .videos) { Label("Video Ekle", systemImage: "video") }; Button { importing = true } label: { Label("LUT İçe Aktar", systemImage: "cube.transparent") } } label: { Image(systemName: "plus") } } }
            Button { choosingMedia = true } label: { Label("Yeni Proje", systemImage: "plus").font(.headline).padding(.horizontal, 20).frame(height: 54).background(accent, in: Capsule()).foregroundStyle(.black) }.padding(.bottom, 18) }
        }.confirmationDialog("Yeni Proje", isPresented: $choosingMedia, titleVisibility: .visible) { PhotosPicker(selection: $pickerItem, matching: .images) { Label("Fotoğraf Seç", systemImage: "photo") }; PhotosPicker(selection: $videoItem, matching: .videos) { Label("Video Seç", systemImage: "video") } }.onChange(of: pickerItem) { _, item in importImage(item) }.onChange(of: videoItem) { _, item in importVideo(item) }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { _ in }.fullScreenCover(item: $editor) { EditorView(project: $0) } }
    private var empty: some View { ContentUnavailableView("İlk düzenlemeni oluştur", systemImage: "camera.filters", description: Text("Fotoğraf seç, LUT uygula ve görünümünü kaydet.")) }
    private func card(_ project: GradeProject) -> some View { Button { editor = project } label: { VStack(alignment: .leading, spacing: 7) { Group { if let image = library.image(for: project) { Image(uiImage: image).resizable().scaledToFill() } else { Color.gray } }.frame(height: 126).clipShape(RoundedRectangle(cornerRadius: 14)); Text(project.settings.lutName).font(.caption.weight(.semibold)).lineLimit(1); Text(project.createdAt, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain).contextMenu { Button(role: .destructive) { library.remove(project) } label: { Label("Delete", systemImage: "trash") } } }
    private func importImage(_ item: PhotosPickerItem?) { Task { guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let project = library.add(image: image, source: SourceDetector.fromImage(data)) else { return }; await MainActor.run { editor = project; pickerItem = nil } } }
    private func importVideo(_ item: PhotosPickerItem?) { Task { guard let movie = try? await item?.loadTransferable(type: PickedMovie.self), let project = library.add(video: movie.url, profile: SourceDetector.fromVideo(movie.url)) else { return }; await MainActor.run { editor = project; videoItem = nil } } }
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
    static let profiles = ["Regular", "D-Log M", "Ace Pro 2 (I-Log)", "Apple Log 2", "Apple Log"]
    private static func profile(from value: String) -> String {
        let s = value.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
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
    static func fromVideo(_ url: URL) -> String {
        let asset = AVURLAsset(url: url)
        let text = asset.commonMetadata.compactMap(\.stringValue).joined(separator: " ")
        return profile(from: text)
    }
}

struct EditorView: View {
    @EnvironmentObject private var library: ProjectLibrary; @Environment(\.dismiss) private var dismiss
    @State private var project: GradeProject; @State private var tab = 0; @State private var importedLUT: CubeLUT?; @State private var bundledLUTs: [(String, String, URL)] = []; @State private var selectedCategory = "Tümü"; @State private var importing = false; @State private var videoPlayer: AVPlayer?; @State private var videoDuration = 0.0; @State private var exportMessage: String?
    @State private var showingOriginal = false; @State private var showingFullscreen = false; @State private var showingExportSettings = false; @State private var isFavorite = false
    @State private var undoStack: [GradeSettings] = []; @State private var redoStack: [GradeSettings] = []; @State private var navigatingHistory = false
    private var isVideo: Bool { ["mov", "mp4", "m4v"].contains(URL(fileURLWithPath: project.fileName).pathExtension.lowercased()) }
    private var lutCategories: [String] { ["Tümü"] + Array(Set(bundledLUTs.map { $0.0 })).sorted() }
    private var visibleLUTs: [(String, String, URL)] { selectedCategory == "Tümü" ? bundledLUTs : bundledLUTs.filter { $0.0 == selectedCategory } }
    init(project: GradeProject) { _project = State(initialValue: project) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { proxy in preview.frame(maxWidth: proxy.size.width, maxHeight: .infinity) }
                    .padding(.horizontal, 12)
                previewActions
                Picker("Düzenleme", selection: $tab) {
                    Text("Filtreler").tag(0); Text("Ayarla").tag(1); Text("Efektler").tag(2)
                }.pickerStyle(.segmented).padding()
                panel.padding(.horizontal).padding(.bottom, 8)
            }
            .background(Color.black)
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
                    Button { saveToPhotos() } label: { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Dışa aktar")
                }
            }
            .onAppear(perform: prepareEditor)
            .onDisappear { videoPlayer?.pause() }
            .onChange(of: project.settings) { oldValue, newValue in
                guard !navigatingHistory, oldValue != newValue else { navigatingHistory = false; return }
                undoStack.append(oldValue)
                if undoStack.count > 100 { undoStack.removeFirst() }
                redoStack.removeAll()
            }
            .onChange(of: project.settings.lutName) { _, name in
                if name == "Original" { importedLUT = nil }
                else if let match = bundledLUTs.first(where: { $0.1 == name }) { importedLUT = CubeLUT.load(url: match.2) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { result in
                if case let .success(url) = result { importedLUT = CubeLUT.load(url: url); project.settings.lutName = url.deletingPathExtension().lastPathComponent }
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
        }
    }
    private var preview: some View {
        Group {
            if isVideo, let videoPlayer { VideoPlayer(player: videoPlayer).clipShape(RoundedRectangle(cornerRadius: 18)) }
            else if isVideo { ProgressView("Video yükleniyor") }
            else if let source = library.image(for: project) {
                let rendered = showingOriginal ? source : ImageRenderer.grade(source, settings: project.settings, lut: importedLUT)
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
        isFavorite = UserDefaults.standard.stringArray(forKey: "lumagrade.favoriteProjects")?.contains(project.id.uuidString) ?? false
        if isVideo {
            let url = library.videoURL(for: project); let asset = AVURLAsset(url: url); videoPlayer = AVPlayer(url: url)
            Task {
                if let duration = try? await asset.load(.duration) {
                    await MainActor.run { videoDuration = CMTimeGetSeconds(duration) }
                }
            }
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
            FilterBrowser(items: bundledLUTs, categories: lutCategories, selectedCategory: $selectedCategory, selectedName: $project.settings.lutName, selectedLUT: $importedLUT, intensity: $project.settings.intensity, sourceImage: library.image(for: project), settings: project.settings)
        case 1:
            AdjustmentPanel(settings: $project.settings, isVideo: isVideo, videoDuration: videoDuration)
        default:
            SliderPanel(settings: $project.settings, labels: [("Vinyet", \GradeSettings.vignette, 0...2), ("Parlama", \GradeSettings.bloom, 0...1), ("Gren", \GradeSettings.grain, 0...1)])
        }
    }
    private func saveToPhotos() {
        if isVideo { exportTrimmedVideo(); return }
        guard let image = library.image(for: project) else { return }
        let graded = ImageRenderer.grade(image, settings: project.settings, lut: importedLUT)
        let output = ImageRenderer.resized(graded, resolution: project.settings.exportResolution)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { DispatchQueue.main.async { exportMessage = "Fotoğraf arşivine ekleme izni verilmedi." }; return }
            PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: output) } completionHandler: { saved, error in
                DispatchQueue.main.async { exportMessage = saved ? "Fotoğraf arşive kaydedildi." : (error?.localizedDescription ?? "Fotoğraf kaydedilemedi.") }
            }
        }
    }
    private func exportTrimmedVideo() {
        let asset = AVURLAsset(url: library.videoURL(for: project))
        Task {
            do {
                let duration = CMTimeGetSeconds(try await asset.load(.duration))
                let start = min(duration, max(0, duration * project.settings.trimStart))
                let end = min(duration, max(start + 0.05, duration * project.settings.trimEnd))
                guard end > start else { throw CocoaError(.fileWriteInvalidFileName) }
                let supported = AVAssetExportSession.exportPresets(compatibleWith: asset)
                let preset = exportPreset(codec: project.settings.exportCodec, resolution: project.settings.exportResolution, supported: supported)
                guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw CocoaError(.fileWriteUnknown) }
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("LumaGrade-\(UUID().uuidString).mov")
                session.outputURL = output; session.outputFileType = .mov
                session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end - start, preferredTimescale: 600))
                let bitrate = effectiveBitrateMbps
                session.fileLengthLimit = Int64((end - start) * bitrate * 1_000_000 / 8)
                let status: AVAssetExportSession.Status = await withCheckedContinuation { continuation in
                    session.exportAsynchronously { continuation.resume(returning: session.status) }
                }
                guard status == .completed else { throw session.error ?? CocoaError(.fileWriteUnknown) }
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
                    guard authorization == .authorized || authorization == .limited else { DispatchQueue.main.async { exportMessage = "Fotoğraf arşivine ekleme izni verilmedi." }; return }
                    PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: output) } completionHandler: { saved, error in
                        try? FileManager.default.removeItem(at: output)
                        DispatchQueue.main.async { exportMessage = saved ? "Kesilmiş video arşive kaydedildi." : (error?.localizedDescription ?? "Video kaydedilemedi.") }
                    }
                }
            } catch { await MainActor.run { exportMessage = error.localizedDescription } }
        }
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

struct AdjustmentPanel: View {
    @Binding var settings: GradeSettings
    var isVideo = false
    var videoDuration = 0.0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Kaynak profili"); Spacer(); Picker("Kaynak profili", selection: $settings.source) { ForEach(SourceDetector.profiles, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                Group {
                    adjust("Pozlama", \.exposure, -4...4)
                    adjust("Gölgeler", \.shadows, -1...1)
                    adjust("Açık alanlar", \.highlights, 0...2)
                    adjust("Beyazlar", \.whites, -1...1)
                    adjust("Siyahlar", \.blacks, -1...1)
                    adjust("Sıcaklık", \.temperature, 2000...12000)
                    adjust("Tint", \.tint, -100...100)
                    adjust("Kontrast", \.contrast, 0...2)
                    adjust("Hue", \.hue, -Double.pi...Double.pi)
                    adjust("HLS · Açıklık", \.brightness, -0.5...0.5)
                    adjust("Canlılık", \.vibrance, -1...1)
                    adjust("Doygunluk", \.saturation, 0...2)
                    adjust("Keskinlik", \.sharpness, 0...2)
                    adjust("Vinyet", \.vignette, 0...2)
                }
                DisclosureGroup("Maske") {
                    Toggle("Merkez maskesini etkinleştir", isOn: $settings.maskEnabled)
                    adjust("Maskeli pozlama", \.maskExposure, -3...3)
                    adjust("Maske boyutu", \.maskRadius, 0.1...1)
                    adjust("Kenar yumuşatma", \.maskFeather, 0.02...0.6)
                }
                DisclosureGroup("Kırpma") {
                    Picker("En-boy oranı", selection: $settings.cropAspect) {
                        ForEach(["Orijinal", "1:1", "4:5", "16:9", "9:16"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if isVideo && videoDuration > 0 {
                    DisclosureGroup("Video kesme · \(time(settings.trimStart * videoDuration)) – \(time(settings.trimEnd * videoDuration))") {
                        VStack(alignment: .leading) {
                            Text("Başlangıç · \(time(settings.trimStart * videoDuration))").font(.caption)
                            Slider(value: Binding(get: { settings.trimStart }, set: { settings.trimStart = min($0, settings.trimEnd) }), in: 0...1).tint(accent)
                            Text("Bitiş · \(time(settings.trimEnd * videoDuration))").font(.caption)
                            Slider(value: Binding(get: { settings.trimEnd }, set: { settings.trimEnd = max($0, settings.trimStart) }), in: 0...1).tint(accent)
                        }
                    }
                }
                DisclosureGroup("Renk tekerleri") {
                    adjust("Gölgeler", \.wheelShadows, -1...1)
                    adjust("Orta tonlar", \.wheelMidtones, -1...1)
                    adjust("Açık alanlar", \.wheelHighlights, -1...1)
                }
                DisclosureGroup("Eğriler") {
                    adjust("Siyah noktası", \.curveBlack, 0...0.25)
                    adjust("Orta nokta", \.curveMid, 0.1...0.9)
                    adjust("Beyaz noktası", \.curveWhite, 0.75...1)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 245)
    }
    private func adjust(_ title: String, _ key: WritableKeyPath<GradeSettings, Double>, _ range: ClosedRange<Double>) -> some View {
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
    private var visibleItems: [(String, String, URL)] { selectedCategory == "Tümü" ? items : items.filter { $0.0 == selectedCategory } }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text("Filtreler").font(.headline); Spacer(); Text("Yoğunluk  \(Int(intensity))% ").font(.caption).foregroundStyle(.secondary) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { name in
                        Button(name) { selectedCategory = name }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedCategory == name ? accent : Color.white.opacity(0.08), in: Capsule())
                            .foregroundStyle(selectedCategory == name ? .black : .white)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    Button { selectedLUT = nil; selectedName = "Original" } label: {
                        LUTTile(name: "Yok", sourceImage: sourceImage, settings: settings, lut: nil, selected: selectedName == "Original")
                    }.buttonStyle(.plain)
                    ForEach(Array(visibleItems.enumerated()), id: \.offset) { pair in
                        let item = pair.element
                        Button { selectedLUT = CubeLUT.load(url: item.2); selectedName = item.1 } label: {
                            LUTTile(name: item.1, sourceImage: sourceImage, settings: settings, lut: CubeLUT.load(url: item.2), selected: selectedName == item.1)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Slider(value: $intensity, in: 0...100)
                .tint(accent)
                .disabled(selectedLUT == nil)
        }
    }
}

struct LUTTile: View {
    let name: String
    let sourceImage: UIImage?
    let settings: GradeSettings
    let lut: CubeLUT?
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let sourceImage {
                    Image(uiImage: ImageRenderer.thumbnail(sourceImage, settings: settings, lut: lut)).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.purple, .orange, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 92, height: 58).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            Text(name).font(.caption2).lineLimit(1).frame(width: 92, alignment: .leading)
        }
        .padding(5)
        .background(selected ? accent.opacity(0.2) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? accent : .clear, lineWidth: 1.5))
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
    static func thumbnail(_ source: UIImage, settings: GradeSettings, lut: CubeLUT?) -> UIImage {
        let target = CGSize(width: 180, height: 112)
        let renderer = UIGraphicsImageRenderer(size: target)
        let small = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: target)) }
        return grade(small, settings: settings, lut: lut)
    }
    static func rgbaData(from rgb: [Float]) -> Data {
        var rgba = [Float](); rgba.reserveCapacity(rgb.count / 3 * 4)
        for index in stride(from: 0, to: rgb.count, by: 3) { rgba.append(rgb[index]); rgba.append(rgb[index + 1]); rgba.append(rgb[index + 2]); rgba.append(1) }
        return rgba.withUnsafeBufferPointer { Data(bytes: $0.baseAddress!, count: $0.count * MemoryLayout<Float>.size) }
    }
    static func grade(_ source: UIImage, settings: GradeSettings, lut: CubeLUT?) -> UIImage {
        guard var image = CIImage(image: source) else { return source }
        image = crop(image, aspect: settings.cropAspect)
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
            tone.shadowAmount = Float(max(0, settings.shadows))
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

        let sharp = CIFilter.sharpenLuminance()
        sharp.inputImage = image
        sharp.sharpness = Float(settings.sharpness)
        image = sharp.outputImage ?? image

        if settings.blacks != 0 || settings.whites != 0 || settings.wheelShadows != 0 || settings.wheelMidtones != 0 || settings.wheelHighlights != 0 || settings.curveBlack != 0 || settings.curveMid != 0.5 || settings.curveWhite != 1 {
            let levels = CIFilter.colorMatrix()
            levels.inputImage = image
            let blackPoint = min(0.45, max(-0.25, settings.blacks * 0.12 + settings.curveBlack))
            let whitePoint = min(1.25, max(0.55, 1 + settings.whites * 0.12 + (settings.curveWhite - 1)))
            let scale = CGFloat(1 / max(0.1, whitePoint - blackPoint))
            levels.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            levels.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            levels.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            let warm = CGFloat(settings.wheelShadows + settings.wheelMidtones + settings.wheelHighlights) * 0.025
            let offset = -blackPoint * scale
            levels.biasVector = CIVector(x: offset + warm, y: offset, z: offset - warm, w: 0)
            image = levels.outputImage ?? image
            if settings.curveMid != 0.5 {
                let gamma = CIFilter.gammaAdjust()
                gamma.inputImage = image
                gamma.power = Float(log(0.5) / log(settings.curveMid))
                image = gamma.outputImage ?? image
            }
        }

        if let lut {
            let cube = CIFilter.colorCube()
            cube.inputImage = image
            cube.cubeDimension = Float(lut.dimension)
            cube.cubeData = rgbaData(from: lut.values)
            let graded = cube.outputImage ?? image
            if settings.intensity < 100 {
                let blend = CIFilter.blendWithMask()
                blend.inputImage = graded
                blend.backgroundImage = image
                let opacity = CGFloat(settings.intensity / 100)
                blend.maskImage = CIImage(color: CIColor(red: opacity, green: opacity, blue: opacity)).cropped(to: image.extent)
                image = blend.outputImage ?? graded
            } else { image = graded }
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
        guard let cg = context.createCGImage(image, from: image.extent) else { return source }
        return UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
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
