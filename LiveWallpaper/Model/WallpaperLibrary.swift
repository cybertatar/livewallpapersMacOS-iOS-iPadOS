import Foundation

/// Список обоев. Видео копируются в ~/Library/Application Support/LiveWallpaper/Videos,
/// поэтому исходные файлы можно потом удалить или переместить.
@MainActor
final class WallpaperLibrary: ObservableObject {
    @Published private(set) var items: [WallpaperItem] = []
    @Published private(set) var playlists: [Playlist] = []

    let baseDirectory: URL
    let videosDirectory: URL
    let imagesDirectory: URL
    let snapshotsDirectory: URL
    let livePhotosDirectory: URL

    private var libraryFile: URL { baseDirectory.appendingPathComponent("library.json") }
    private var playlistsFile: URL { baseDirectory.appendingPathComponent("playlists.json") }

    nonisolated static var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveWallpaper", isDirectory: true)
    }

    nonisolated static var imagesURL: URL { baseURL.appendingPathComponent("Images", isDirectory: true) }

    init() {
        let fm = FileManager.default
        baseDirectory = Self.baseURL
        videosDirectory = baseDirectory.appendingPathComponent("Videos", isDirectory: true)
        imagesDirectory = baseDirectory.appendingPathComponent("Images", isDirectory: true)
        snapshotsDirectory = baseDirectory.appendingPathComponent("Snapshots", isDirectory: true)
        livePhotosDirectory = baseDirectory.appendingPathComponent("LivePhotos", isDirectory: true)
        for dir in [videosDirectory, imagesDirectory, snapshotsDirectory, livePhotosDirectory] {
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

    /// Импорт картинок: копируем в библиотеку и вырезаем персонажа (Vision), это занимает пару секунд.
    @discardableResult
    func importImages(_ urls: [URL]) async -> [WallpaperItem] {
        var added: [WallpaperItem] = []
        let directory = imagesDirectory
        for url in urls {
            let base = UUID().uuidString
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
            let imageFile = "\(base).\(ext)"
            let cutoutFile = "\(base)-cutout.png"
            let lifted: SubjectLifter.Result?
            do {
                lifted = try await Task.detached(priority: .userInitiated) { () throws -> SubjectLifter.Result? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let destination = directory.appendingPathComponent(imageFile)
                    try FileManager.default.copyItem(at: url, to: destination)
                    return SubjectLifter.lift(imageAt: destination,
                                              saveTo: directory.appendingPathComponent(cutoutFile))
                }.value
            } catch {
                NSLog("LiveWallpaper: не удалось импортировать \(url.path): \(error)")
                continue
            }
            var scene = ImageScene(imageFile: imageFile)
            if let lifted {
                scene.cutoutFile = cutoutFile
                scene.focusX = lifted.focusX
                // У картинки без фона своего фона нет — сразу ставим живую сцену.
                if lifted.sourceWasTransparent {
                    scene.backgroundScene = .frierenFlowers
                    scene.separateCharacter = true
                }
            }
            let item = WallpaperItem(id: UUID(), name: url.deletingPathExtension().lastPathComponent,
                                     source: .image(scene))
            items.append(item)
            added.append(item)
        }
        save()
        return added
    }

    func imageURL(_ file: String) -> URL {
        imagesDirectory.appendingPathComponent(file)
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
        if let scene = item.imageScene {
            try? FileManager.default.removeItem(at: imageURL(scene.imageFile))
            if let cutout = scene.cutoutFile { try? FileManager.default.removeItem(at: imageURL(cutout)) }
        }
        items.removeAll { $0.id == item.id }
        for index in playlists.indices {
            playlists[index].itemIDs.removeAll { $0 == item.id }
        }
        save()
        savePlaylists()
    }

    // MARK: - Подборки

    /// Все наборы, из которых можно выбирать: «все», видео, встроенные темы, свои подборки.
    var allRefs: [PlaylistRef] {
        [.all, .images, .videos] + ShaderCollection.allCases.map { .collection($0) } + playlists.map { .custom($0.id) }
    }

    func items(in ref: PlaylistRef) -> [WallpaperItem] {
        switch ref {
        case .all:
            return items
        case .videos:
            return items.filter(\.isVideo)
        case .images:
            return items.filter(\.isImage)
        case .collection(let collection):
            return items.filter { $0.shaderKind?.collection == collection }
        case .custom(let id):
            return playlist(id: id)?.itemIDs.compactMap { item(id: $0) } ?? []
        }
    }

    func title(for ref: PlaylistRef) -> String {
        switch ref {
        case .all: return "Все обои"
        case .videos: return "Мои видео"
        case .images: return "Живые картинки"
        case .collection(let collection): return collection.title
        case .custom(let id): return playlist(id: id)?.name ?? "Удалённая подборка"
        }
    }

    func playlist(id: UUID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    @discardableResult
    func createPlaylist(name: String, itemIDs: [UUID] = []) -> Playlist {
        let playlist = Playlist(id: UUID(), name: name, itemIDs: itemIDs)
        playlists.append(playlist)
        savePlaylists()
        return playlist
    }

    func renamePlaylist(id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[index].name = name
        savePlaylists()
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func contains(_ item: WallpaperItem, inPlaylist id: UUID) -> Bool {
        playlist(id: id)?.itemIDs.contains(item.id) ?? false
    }

    func setItem(_ item: WallpaperItem, inPlaylist id: UUID, included: Bool) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].itemIDs.removeAll { $0 == item.id }
        if included { playlists[index].itemIDs.append(item.id) }
        savePlaylists()
    }

    private func savePlaylists() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(playlists) {
            try? data.write(to: playlistsFile, options: .atomic)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: libraryFile) {
            if let decoded = try? JSONDecoder().decode([WallpaperItem].self, from: data) {
                items = decoded
            } else {
                // Не смогли прочитать — сохраняем копию, чтобы не потерять библиотеку при перезаписи.
                try? data.write(to: libraryFile.appendingPathExtension("bak"), options: .atomic)
            }
        }
        if let data = try? Data(contentsOf: playlistsFile),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
        // Встроенные шейдеры всегда есть в библиотеке.
        for kind in ShaderKind.allCases where !items.contains(where: { $0.shaderKind == kind }) {
            items.append(WallpaperItem(id: UUID(), name: kind.title, source: .shader(kind)))
        }
        addBuiltInImages()
        save()
    }

    /// Встроенные живые картинки (общественное достояние). Добавляются один раз — если их удалить, не вернутся.
    private func addBuiltInImages() {
        let builtIns: [(resource: String, name: String)] = [
            ("GreatWave", "Большая волна в Канагаве (Хокусай)"),
        ]
        let defaults = UserDefaults.standard
        for builtIn in builtIns {
            let key = "seeded-\(builtIn.resource)"
            guard !defaults.bool(forKey: key),
                  let source = Bundle.main.url(forResource: builtIn.resource, withExtension: "jpg") else { continue }
            let file = "builtin-\(builtIn.resource).jpg"
            let destination = imagesDirectory.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { continue }
            }
            var scene = ImageScene(imageFile: file)
            scene.fit = .fill
            scene.focusX = 0.35
            items.append(WallpaperItem(id: UUID(), name: builtIn.name, source: .image(scene)))
            defaults.set(true, forKey: key)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: libraryFile, options: .atomic)
        }
    }
}
