import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary

    @State private var selection: UUID?
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var filter: PlaylistRef = .all
    @State private var importingCount = 0

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Показать", selection: $filter) {
                    ForEach(library.allRefs, id: \.self) { ref in
                        Text("\(library.title(for: ref)) (\(library.items(in: ref).count))").tag(ref)
                    }
                }
                .frame(maxWidth: 280)
                Spacer()
                if importingCount > 0 {
                    ProgressView().controlSize(.small)
                    Text("Вырезаю персонажа…").font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Добавить видео или картинку…", systemImage: "plus")
                }
            }
            .padding(.bottom, 10)

            ScrollView {
                if filter == .all {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .padding(.horizontal, 6)
                        grid(section.items)
                    }
                } else {
                    grid(library.items(in: filter))
                }
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                }
            }
            .onDrop(of: [.movie, .image], isTargeted: $isDropTargeted, perform: handleDrop)

            if let item = library.item(id: selection) {
                Divider().padding(.vertical, 8)
                ItemInspector(item: item) { selection = nil }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.movie, .image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await importFiles(urls) }
            }
        }
    }

    private var sections: [(title: String, items: [WallpaperItem])] {
        var result: [(title: String, items: [WallpaperItem])] = []
        let videos = library.items(in: .videos)
        let images = library.items(in: .images)
        if !images.isEmpty { result.append((library.title(for: .images), images)) }
        if !videos.isEmpty { result.append((library.title(for: .videos), videos)) }
        for collection in ShaderCollection.allCases {
            let items = library.items(in: .collection(collection))
            if !items.isEmpty { result.append((collection.title, items)) }
        }
        return result
    }

    private func grid(_ items: [WallpaperItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(items) { item in
                card(for: item)
            }
        }
        .padding(4)
    }

    private func card(for item: WallpaperItem) -> some View {
        let isDefault = state.visibleItems.contains { $0.id == item.id }
        return VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(item: item)
                .overlay(alignment: .topTrailing) {
                    if isDefault {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.multicolor)
                            .font(.title2)
                            .padding(6)
                    }
                }
            HStack {
                Image(systemName: item.isVideo ? "film" : item.isImage ? "person.crop.rectangle" : "wand.and.stars")
                    .foregroundStyle(.secondary)
                Text(item.name).lineLimit(1)
            }
            .font(.callout)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selection == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.applyToAllDisplays(item) }
        .onTapGesture { selection = item.id }
        .contextMenu {
            Button("Поставить на все мониторы") { state.applyToAllDisplays(item) }
            Button("Сделать Live Photo для iPhone/iPad") {
                state.livePhotoSourceID = item.id
                state.mainTab = .livePhoto
            }
            Menu("Добавить в подборку") {
                ForEach(library.playlists) { playlist in
                    Toggle(playlist.name, isOn: Binding(
                        get: { library.contains(item, inPlaylist: playlist.id) },
                        set: { library.setItem(item, inPlaylist: playlist.id, included: $0) }
                    ))
                }
                if !library.playlists.isEmpty { Divider() }
                Button("Новая подборка") {
                    library.createPlaylist(name: "Подборка \(library.playlists.count + 1)", itemIDs: [item.id])
                }
            }
            if item.isVideo || item.isImage {
                Button("Удалить", role: .destructive) { library.remove(item) }
            }
        }
    }

    /// Видео и картинки раскладываем по своим импортёрам.
    private func importFiles(_ urls: [URL]) async {
        let images = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        let videos = urls.filter { !images.contains($0) }
        if !videos.isEmpty { await library.importVideos(videos) }
        if !images.isEmpty {
            importingCount += images.count
            let added = await library.importImages(images)
            importingCount -= images.count
            if let first = added.first { selection = first.id }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            let type: UTType = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? .movie : .image
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return }
                // Временный файл удаляется после выхода из колбэка — копируем сразу.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(4))
                    .appendingPathExtension(url.pathExtension)
                guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
                Task { @MainActor in
                    await importFiles([copy])
                    try? FileManager.default.removeItem(at: copy)
                }
            }
        }
        return true
    }
}

private struct ItemInspector: View {
    let item: WallpaperItem
    let onClose: () -> Void

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                TextField("Название", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onSubmit(save)

                SpeedControl(item: item)
                    .frame(width: 280)

                Spacer()

                Button("На все мониторы") {
                    save()
                    if let updated = library.item(id: item.id) { state.applyToAllDisplays(updated) }
                }
                .buttonStyle(.borderedProminent)

                if item.isVideo || item.isImage {
                    Button("Удалить", role: .destructive) {
                        library.remove(item)
                        onClose()
                    }
                }
            }
            if item.isImage {
                ImageSceneEditor(item: item)
            }
        }
        .onAppear(perform: syncFromItem)
        .onChange(of: item.id) { syncFromItem() }
    }

    private func syncFromItem() {
        name = item.name
    }

    private func save() {
        guard !name.isEmpty, name != item.name else { return }
        var updated = item
        updated.name = name
        library.update(updated)
    }
}
