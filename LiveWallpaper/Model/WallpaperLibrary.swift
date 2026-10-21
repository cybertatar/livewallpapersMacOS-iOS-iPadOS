import Foundation

/// Список обоев. Видео копируются в ~/Library/Application Support/LiveWallpaper/Videos,
/// поэтому исходные файлы можно потом удалить или переместить.
@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var items: [WallpaperItem] = []

    let baseDirectory: URL
    let videosDirectory: URL
    let snapshotsDirectory: URL
    let livePhotosDirectory: URL

    private var libraryFile: URL { baseDirectory.appendingPathComponent("library.json") }

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseDirectory = support.appendingPathComponent("LiveWallpaper", isDirectory: true)
        videosDirectory = baseDirectory.appendingPathComponent("Videos", isDirectory: true)
        snapshotsDirectory = baseDirectory.appendingPathComponent("Snapshots", isDirectory: true)
        livePhotosDirectory = baseDirectory.appendingPathComponent("LivePhotos", isDirectory: true)
        for dir in [videosDirectory, snapshotsDirectory, livePhotosDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        load()
    }

    func item(id: UUID?) -> WallpaperItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func fileURL(for item: WallpaperItem) -> URL? {
        guard case .video(let fileName) = item.source else { return nil }
        return videosDirectory.appendingPathComponent(fileName)
    }

    @discardableResult
    func importVideos(_ urls: [URL]) async -> [WallpaperItem] {
        var added: [WallpaperItem] = []
        for url in urls {
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
            let fileName = "\(UUID().uuidString).\(ext)"
            let destination = videosDirectory.appendingPathComponent(fileName)
            do {
                try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: url, to: destination)
                }.value
            } catch {
                NSLog("LiveWallpaper: не удалось импортировать \(url.path): \(error)")
                continue
            }
            let item = WallpaperItem(
                id: UUID(),
                name: url.deletingPathExtension().lastPathComponent,
                source: .video(fileName: fileName)
            )
            items.append(item)
            added.append(item)
        }
        save()
        return added
    }

    func add(_ item: WallpaperItem) {
        items.append(item)
        save()
    }

    func update(_ item: WallpaperItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        save()
    }

    func remove(_ item: WallpaperItem) {
        if let url = fileURL(for: item) {
            try? FileManager.default.removeItem(at: url)
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        if let data = try? Data(contentsOf: libraryFile),
           let decoded = try? JSONDecoder().decode([WallpaperItem].self, from: data) {
            items = decoded
        }
        // Встроенные шейдеры всегда есть в библиотеке.
        for kind in ShaderKind.allCases where !items.contains(where: { $0.shaderKind == kind }) {
            items.append(WallpaperItem(id: UUID(), name: kind.title, source: .shader(kind)))
        }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: libraryFile, options: .atomic)
        }
    }
}
