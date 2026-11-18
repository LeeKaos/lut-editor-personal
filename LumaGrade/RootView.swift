import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Photos

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
    var temperature = 6500.0; var tint = 0.0; var highlights = 1.0; var shadows = 0.0; var vignette = 0.0; var bloom = 0.0; var grain = 0.0
}

final class ProjectLibrary: ObservableObject {
    @Published var projects: [GradeProject] = [] { didSet { save() } }
    private let key = "lumagrade.projects.v1"
    init() { guard let data = UserDefaults.standard.data(forKey: key), let stored = try? JSONDecoder().decode([GradeProject].self, from: data) else { return }; projects = stored }
    func add(image: UIImage) -> GradeProject? { guard let data = image.jpegData(compressionQuality: 0.96) else { return nil }; let name = "\(UUID().uuidString).jpg"; let url = documents.appendingPathComponent(name); do { try data.write(to: url, options: .atomic); let project = GradeProject(fileName: name); projects.insert(project, at: 0); return project } catch { return nil } }
    func image(for project: GradeProject) -> UIImage? { UIImage(contentsOfFile: documents.appendingPathComponent(project.fileName).path) }
    func update(_ project: GradeProject) { guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }; projects[index] = project }
    func remove(_ project: GradeProject) { try? FileManager.default.removeItem(at: documents.appendingPathComponent(project.fileName)); projects.removeAll { $0.id == project.id } }
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private func save() { if let data = try? JSONEncoder().encode(projects) { UserDefaults.standard.set(data, forKey: key) } }
}

struct RootView: View {
    @State private var selectedTab = 0
    var body: some View { TabView(selection: $selectedTab) { ProjectsView().tabItem { Label("Projects", systemImage: "square.grid.2x2.fill") }.tag(0); SettingsView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(1) }.tint(accent).preferredColorScheme(.dark) }
}

struct ProjectsView: View {
    @EnvironmentObject private var library: ProjectLibrary
    @State private var pickerItem: PhotosPickerItem?; @State private var editor: GradeProject?; @State private var importing = false
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]
    var body: some View { NavigationStack { ZStack(alignment: .bottom) { Group { if library.projects.isEmpty { empty } else { ScrollView { LazyVGrid(columns: columns, spacing: 16) { ForEach(library.projects) { project in card(project) } }.padding(16).padding(.bottom, 80) } } }.navigationTitle("Projects").toolbar { ToolbarItem(placement: .topBarTrailing) { Menu { PhotosPicker(selection: $pickerItem, matching: .images) { Label("Import Photo", systemImage: "photo") }; Button { importing = true } label: { Label("Import LUT", systemImage: "cube.transparent") } } label: { Image(systemName: "plus") } } }
            PhotosPicker(selection: $pickerItem, matching: .images) { Label("New Project", systemImage: "plus").font(.headline).padding(.horizontal, 20).frame(height: 54).background(accent, in: Capsule()).foregroundStyle(.black) }.padding(.bottom, 18) }
        }.onChange(of: pickerItem) { _, item in importImage(item) }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { _ in }.fullScreenCover(item: $editor) { EditorView(project: $0) } }
    private var empty: some View { ContentUnavailableView("Create your first grade", systemImage: "camera.filters", description: Text("Import a photo, apply a LUT, then save the finished look.")) }
    private func card(_ project: GradeProject) -> some View { Button { editor = project } label: { VStack(alignment: .leading, spacing: 7) { Group { if let image = library.image(for: project) { Image(uiImage: image).resizable().scaledToFill() } else { Color.gray } }.frame(height: 126).clipShape(RoundedRectangle(cornerRadius: 14)); Text(project.settings.lutName).font(.caption.weight(.semibold)).lineLimit(1); Text(project.createdAt, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary) }.contentShape(Rectangle()) }.buttonStyle(.plain).contextMenu { Button(role: .destructive) { library.remove(project) } label: { Label("Delete", systemImage: "trash") } } }
    private func importImage(_ item: PhotosPickerItem?) { Task { guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data), let project = library.add(image: image) else { return }; await MainActor.run { editor = project; pickerItem = nil } } }
}

struct EditorView: View {
    @EnvironmentObject private var library: ProjectLibrary; @Environment(\.dismiss) private var dismiss
    @State private var project: GradeProject; @State private var tab = 0; @State private var importedLUT: CubeLUT?; @State private var importing = false; @State private var showShare = false
    init(project: GradeProject) { _project = State(initialValue: project) }
    var body: some View { NavigationStack { VStack(spacing: 0) { GeometryReader { proxy in preview.frame(maxWidth: proxy.size.width, maxHeight: .infinity) }.padding(.horizontal, 12); Picker("Panel", selection: $tab) { Text("Filters").tag(0); Text("Adjust").tag(1); Text("Effects").tag(2) }.pickerStyle(.segmented).padding(); panel.padding(.horizontal).padding(.bottom, 8) }.background(Color.black).navigationTitle(project.settings.lutName).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { library.update(project); dismiss() } }; ToolbarItemGroup(placement: .topBarTrailing) { Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }; Button { saveToPhotos() } label: { Image(systemName: "square.and.arrow.up") } } }.fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cube")!]) { result in if case let .success(url) = result { importedLUT = CubeLUT.load(url: url); project.settings.lutName = url.deletingPathExtension().lastPathComponent } } } }
    private var preview: some View { Group { if let source = library.image(for: project) { Image(uiImage: ImageRenderer.grade(source, settings: project.settings, lut: importedLUT)).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)) } else { ContentUnavailableView("Original missing", systemImage: "exclamationmark.triangle") } } }
    @ViewBuilder private var panel: some View { switch tab { case 0: VStack(spacing: 10) { HStack { Text(importedLUT == nil ? "Original look" : "Custom LUT"); Spacer(); Text("\(Int(project.settings.intensity))%") }; Slider(value: $project.settings.intensity, in: 0...100); Text("Use the download button to import a licensed .cube LUT.").font(.caption).foregroundStyle(.secondary) }; case 1: SliderPanel(settings: $project.settings, labels: [("Exposure", \GradeSettings.exposure, -2...2), ("Contrast", \GradeSettings.contrast, 0...2), ("Saturation", \GradeSettings.saturation, 0...2), ("Brightness", \GradeSettings.brightness, -0.25...0.25), ("Highlights", \GradeSettings.highlights, 0...2), ("Shadows", \GradeSettings.shadows, -1...1)]); default: SliderPanel(settings: $project.settings, labels: [("Vignette", \GradeSettings.vignette, 0...2), ("Bloom", \GradeSettings.bloom, 0...1), ("Grain", \GradeSettings.grain, 0...1)]) } }
    private func saveToPhotos() { guard let image = library.image(for: project) else { return }; let output = ImageRenderer.grade(image, settings: project.settings, lut: importedLUT); PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in guard status == .authorized || status == .limited else { return }; PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: output) } } }
}

struct SliderPanel: View { @Binding var settings: GradeSettings; let labels: [(String, WritableKeyPath<GradeSettings, Double>, ClosedRange<Double>)]
    var body: some View { ScrollView(.horizontal, showsIndicators: false) { HStack(alignment: .top, spacing: 18) { ForEach(labels, id: \.0) { item in VStack(alignment: .leading) { Text(item.0).font(.caption); Slider(value: Binding(get: { settings[keyPath: item.1] }, set: { settings[keyPath: item.1] = $0 }), in: item.2).frame(width: 160); Text(settings[keyPath: item.1], format: .number.precision(.fractionLength(2))).font(.caption2).foregroundStyle(.secondary) } } }.padding(.vertical, 4) } }

struct SettingsView: View { var body: some View { NavigationStack { Form { Section("LumaGrade") { LabeledContent("Version", value: "1.0"); Text("A private, AltStore-ready color grading workspace.") } Section("Privacy") { Text("Media stays on this device. No account, tracking SDK, remote configuration, push notifications, or application groups are used.") } }.navigationTitle("Profile") } } }

struct CubeLUT { let dimension: Int; let values: [Float]
    static func load(url: URL) -> CubeLUT? { guard url.startAccessingSecurityScopedResource() else { return nil }; defer { url.stopAccessingSecurityScopedResource() }; guard let text = try? String(contentsOf: url) else { return nil }; var size: Int?; var values: [Float] = []; for raw in text.components(separatedBy: .newlines) { let line = raw.trimmingCharacters(in: .whitespaces); if line.hasPrefix("LUT_3D_SIZE") { size = Int(line.split(separator: " ").last ?? "") }; let numbers = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Float($0) }; if numbers.count == 3 { values.append(contentsOf: numbers) } }; guard let dimension = size, values.count == dimension * dimension * dimension * 3 else { return nil }; return CubeLUT(dimension: dimension, values: values) }
}

enum ImageRenderer { static let context = CIContext()
    static func grade(_ source: UIImage, settings: GradeSettings, lut: CubeLUT?) -> UIImage { guard var image = CIImage(image: source) else { return source }; let controls = CIFilter.colorControls(); controls.inputImage = image; controls.saturation = Float(settings.saturation); controls.brightness = Float(settings.brightness); controls.contrast = Float(settings.contrast); image = controls.outputImage ?? image; let exposure = CIFilter.exposureAdjust(); exposure.inputImage = image; exposure.ev = Float(settings.exposure); image = exposure.outputImage ?? image; if let lut { let cube = CIFilter.colorCube(); cube.inputImage = image; cube.cubeDimension = Float(lut.dimension); cube.cubeData = lut.values.withUnsafeBufferPointer { Data(buffer: $0) }; let graded = cube.outputImage ?? image; if settings.intensity < 100 { let blend = CIFilter.blendWithMask(); blend.inputImage = graded; blend.backgroundImage = image; blend.maskImage = CIImage(color: CIColor(red: Float(settings.intensity / 100), green: Float(settings.intensity / 100), blue: Float(settings.intensity / 100))).cropped(to: image.extent); image = blend.outputImage ?? graded } else { image = graded } }; if settings.bloom > 0 { let bloom = CIFilter.bloom(); bloom.inputImage = image; bloom.intensity = Float(settings.bloom); bloom.radius = 8; image = bloom.outputImage ?? image }; if settings.vignette > 0 { let v = CIFilter.vignette(); v.inputImage = image; v.intensity = Float(settings.vignette); v.radius = 1.4; image = v.outputImage ?? image }; guard let cg = context.createCGImage(image, from: image.extent) else { return source }; return UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation) } }
