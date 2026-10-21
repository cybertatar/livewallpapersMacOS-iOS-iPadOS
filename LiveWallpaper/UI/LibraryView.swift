import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary

    @State private var selection: UUID?
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var filter: PlaylistRef = .all

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
                Button {
                    isImporting = true
                } label: {
                    Label("Добавить видео…", systemImage: "plus")
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
            .onDrop(of: [.movie], isTargeted: $isDropTargeted, perform: handleDrop)

            if let item = library.item(id: selection) {
                Divider().padding(.vertical, 8)
                ItemInspector(item: item) { selection = nil }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.movie],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await library.importVideos(urls) }
            }
        }
    }

    private var sections: [(title: String, items: [WallpaperItem])] {
        var result: [(title: String, items: [WallpaperItem])] = []
        let videos = library.items(in: .videos)
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
                Image(systemName: item.isVideo ? "film" : "wand.and.stars")
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
            if item.isVideo {
                Button("Удалить", role: .destructive) { library.remove(item) }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { return }
                // Временный файл удаляется после выхода из колбэка — копируем сразу.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
                Task { @MainActor in
                    await library.importVideos([copy])
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

            if item.isVideo {
                Button("Удалить", role: .destructive) {
                    library.remove(item)
                    onClose()
                }
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
