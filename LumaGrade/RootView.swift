import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Photos
import UIKit
import AVFoundation
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
    var vignette = 0.0; var bloom = 0.0; var grain = 0.0
    var source = "Regular"
    enum CodingKeys: String, CodingKey { case lutName, intensity, exposure, contrast, saturation, brightness, temperature, tint, highlights, shadows, whites, blacks, hue, vibrance, sharpness, curveBlack, curveMid, curveWhite, wheelShadows, wheelMidtones, wheelHighlights, vignette, bloom, grain, source }
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
    @State private var project: GradeProject; @State private var tab = 0; @State private var importedLUT: CubeLUT?; @State private var bundledLUTs: [(String, String, URL)] = []; @State private var selectedCategory = "Tümü"; @State private var importing = false; @State private var showShare = false
    private var lutCategories: [String] { ["Tümü"] + Array(Set(bundledLUTs.map { $0.0 })).sorted() }
    private var visibleLUTs: [(String, String, URL)] { selectedCategory == "Tümü" ? bundledLUTs : bundledLUTs.filter { $0.0 == selectedCategory } }
    init(project: GradeProject) { _project = State(initialValue: project) }
    var body: some View { NavigationStack { VStack(spacing: 0) { GeometryReader { proxy in preview.frame(maxWidth: proxy.size.width, maxHeight: .infinity) }.padding(.horizontal, 12); Picker("Düzenleme", selection: $tab) { Text("Filtreler").tag(0); Text("Ayarla").tag(1); Text("Efektler").tag(2) }.pickerStyle(.segmented).padding(); panel.padding(.horizontal).padding(.bottom, 8) }.background(Color.black).navigationTitle(project.settings.lutName).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Kapat") { library.update(project); dismiss() } }; ToolbarItemGroup(placement: .topBarTrailing) { Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }; Button { saveToPhotos() } label: { Image(systemName: "square.and.arrow.up") } } }.onAppear { bundledLUTs = CubeLUT.loadBundled(); if let match = bundledLUTs.first(where: { $0.1 == project.settings.lutName }) { importedLUT = CubeLUT.load(url: match.2) } }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { result in if case let .success(url) = result { importedLUT = CubeLUT.load(url: url); project.settings.lutName = url.deletingPathExtension().lastPathComponent } } } }
    private var preview: some View { Group { if let source = library.image(for: project) { Image(uiImage: ImageRenderer.grade(source, settings: project.settings, lut: importedLUT)).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)) } else { ContentUnavailableView("Original missing", systemImage: "exclamationmark.triangle") } } }
    @ViewBuilder private var panel: some View {
        switch tab {
        case 0:
            FilterBrowser(items: bundledLUTs, categories: lutCategories, selectedCategory: $selectedCategory, selectedName: $project.settings.lutName, selectedLUT: $importedLUT, intensity: $project.settings.intensity, sourceImage: library.image(for: project), settings: project.settings)
        case 1:
            AdjustmentPanel(settings: $project.settings)
        default:
            SliderPanel(settings: $project.settings, labels: [("Vinyet", \GradeSettings.vignette, 0...2), ("Parlama", \GradeSettings.bloom, 0...1), ("Gren", \GradeSettings.grain, 0...1)])
        }
    }
    private func saveToPhotos() { guard let image = library.image(for: project) else { return }; let output = ImageRenderer.grade(image, settings: project.settings, lut: importedLUT); PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in guard status == .authorized || status == .limited else { return }; PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: output) } } }
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

struct AdjustmentPanel: View {
    @Binding var settings: GradeSettings
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
            guard let url = item as? URL, url.pathExtension.lowercased() == "cube" else { return nil }
            let parent = url.deletingLastPathComponent().lastPathComponent
            let category = parent == "LUTs" ? "Kamera" : parent
            return (category, url.deletingPathExtension().lastPathComponent, url)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }
    static func load(url: URL) -> CubeLUT? { let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }; guard let text = try? String(contentsOf: url) else { return nil }; var size: Int?; var values: [Float] = []; for raw in text.components(separatedBy: .newlines) { let line = raw.trimmingCharacters(in: .whitespaces); if line.hasPrefix("LUT_3D_SIZE") { size = Int(line.split(separator: " ").last ?? "") }; let numbers = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }; if numbers.count == 3 { values.append(contentsOf: numbers) } }; guard let dimension = size, values.count == dimension * dimension * dimension * 3 else { return nil }; return CubeLUT(dimension: dimension, values: values) }
}

enum ImageRenderer { static let context = CIContext()
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
}
