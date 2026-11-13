import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum HomeSection: String, CaseIterable {
    case projects = "Projects"
    case profile = "Profile"

    var symbol: String { self == .projects ? "square.grid.2x2.fill" : "person.crop.circle" }
}

private struct LibraryProject: Identifiable, Hashable {
    let url: URL
    var id: String { url.path }
    var isPhoto: Bool { Self.imageExtensions.contains(url.pathExtension.lowercased()) }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
}

private struct LibraryMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: true) { received in
            let destination = try ProjectFileStorage.keepImportedFile(received.file, defaultExtension: "mov")
            return LibraryMovie(url: destination)
        }
    }
}

private struct LibraryPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: true) { received in
            let destination = try ProjectFileStorage.keepImportedFile(received.file, defaultExtension: "jpg")
            return LibraryPhoto(url: destination)
        }
    }
}

struct ProjectsHomeView: View {
    @State private var section: HomeSection = .projects
    @State private var selectedMovie: PhotosPickerItem?
    @State private var projects: [LibraryProject] = []
    @State private var selectedProject: LibraryProject?
    @State private var isImporting = false
    @State private var newestFirst = true
    @State private var pendingDelete: LibraryProject?
    @State private var showDeleteConfirmation = false
    @State private var importError: String?

    private let accent = Color(red: 0.66, green: 1, blue: 0.16)
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.065).ignoresSafeArea()
            Group {
                switch section {
                case .projects: projectsPage
                case .profile: profilePage
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomNavigation }
        .onAppear(perform: reloadProjects)
        .onChange(of: selectedMovie) { _, item in
            guard let item else { return }
            isImporting = true
            Task { await importAsset(item) }
        }
        .fullScreenCover(item: $selectedProject) { project in
            EditorView(initialMediaURL: project.url, onClose: { selectedProject = nil })
                .preferredColorScheme(.dark)
        }
        .confirmationDialog("Delete this video project?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                if let pendingDelete { deleteProject(pendingDelete) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
        .alert("Couldn't add media", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "Please try selecting the photo or video again.")
        }
        .preferredColorScheme(.dark)
    }

    private var projectsPage: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LUT STUDIO")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2.2).foregroundStyle(accent)
                    Text("Projects").font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Menu {
                    Button("Newest first") { newestFirst = true; reloadProjects() }
                    Button("Oldest first") { newestFirst = false; reloadProjects() }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 42, height: 42)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Sort projects")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 20)

            if projects.isEmpty {
                emptyProjects
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(projects) { project in
                            Button { selectedProject = project } label: {
                                projectCard(project)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open Project") { selectedProject = project }
                                Button("Delete Project", role: .destructive) {
                                    pendingDelete = project
                                    showDeleteConfirmation = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }

    private var emptyProjects: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(accent.opacity(0.1)).frame(width: 92, height: 92)
                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .light)).foregroundStyle(accent)
            }
            Text("Your edits, all in one place")
                .font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text("Choose a photo or video to start a project. Your media and edits stay on this iPhone.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center).frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func projectCard(_ project: LibraryProject) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                ProjectThumbnail(url: project.url)
                    .frame(height: 128).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Image(systemName: project.isPhoto ? "photo" : "play.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(7).background(.black.opacity(0.55), in: Circle()).padding(8)
            }
            Text(project.url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.middle)
            HStack(spacing: 4) {
                Text(projectDate(project.url))
                Text("·")
                Text(projectSize(project.url))
            }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.48))
            .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private var profilePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LUT STUDIO").font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(2.2).foregroundStyle(accent)
                        Text("Profile").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 18)

                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 58, weight: .ultraLight)).foregroundStyle(accent)
                    Text("Personal Studio").font(.system(size: 19, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("Private video editing on your iPhone")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 26)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 18)

                VStack(spacing: 0) {
                    profileRow(symbol: "square.grid.2x2", title: "Media projects", value: "\(projects.count)")
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 50)
                    profileRow(symbol: "cube.transparent", title: "Bundled LUTs", value: "\(bundledLUTCount)")
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 50)
                    profileRow(symbol: "iphone", title: "Video processing", value: "On device")
                    Divider().overlay(.white.opacity(0.08)).padding(.leading, 50)
                    profileRow(symbol: "lock.shield", title: "Media storage", value: "This iPhone")
                }
                .padding(.horizontal, 14)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 18)

                Text("LUT Studio · Version \(appVersion)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.38))
                    .padding(.bottom, 24)
            }
        }
    }

    private func profileRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent).frame(width: 28)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 12).padding(.vertical, 15)
    }

    private var bottomNavigation: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedMovie, matching: .any(of: [.images, .videos])) {
                HStack(spacing: 9) {
                    if isImporting { ProgressView().tint(.black) }
                    else { Image(systemName: "plus").font(.system(size: 14, weight: .bold)) }
                Text(isImporting ? "Adding media…" : "New Project")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 48)
                .background(accent, in: Capsule())
            }
            .disabled(isImporting)
            .padding(.horizontal, 18).padding(.top, 10)

            HStack(spacing: 0) {
                ForEach(HomeSection.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 17, weight: .semibold))
                            Text(item.rawValue).font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(section == item ? accent : .white.opacity(0.48))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 4)
        }
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var bundledLUTCount: Int {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Filters", isDirectory: true),
              let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "cube" }.count
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func projectDate(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func projectSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func reloadProjects() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            projects = []
            return
        }
        let supportedExtensions: Set<String> = ["mov", "mp4", "m4v", "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"]
        let media = urls.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        projects = media.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return newestFirst ? left > right : left < right
        }.map { LibraryProject(url: $0) }
    }

    @MainActor private func importAsset(_ item: PhotosPickerItem) async {
        defer {
            selectedMovie = nil
            isImporting = false
        }
        do {
            let destination: URL
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
                guard let photo = try await item.loadTransferable(type: LibraryPhoto.self) else { return }
                destination = photo.url
            } else {
                guard let movie = try await item.loadTransferable(type: LibraryMovie.self) else { return }
                destination = movie.url
            }
            reloadProjects()
            if let project = projects.first(where: { $0.url == destination }) {
                selectedProject = project
            }
        } catch {
            reloadProjects()
            importError = error.localizedDescription
        }
    }

    private func deleteProject(_ project: LibraryProject) {
        projects.removeAll { $0 == project }
        pendingDelete = nil
        let url = project.url
        let settings = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Settings", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent + ".json")
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: settings)
        }
    }
}

private struct ProjectThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "film").font(.system(size: 25, weight: .light)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .clipped()
        .task(id: url) {
            if LibraryProject(url: url).isPhoto {
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                let thumbnailOptions: CFDictionary = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 520,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
                if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
                   let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) {
                    image = UIImage(cgImage: thumbnail)
                }
                return
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 420, height: 560)
            if let frame = try? await generator.image(at: .zero) {
                image = UIImage(cgImage: frame.image)
            }
        }
    }
}
