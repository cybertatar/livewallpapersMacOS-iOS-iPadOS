import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary

    @State private var selection: UUID?
    @State private var isImporting = false
    @State private var isDropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Видео и процедурные анимации").font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("Добавить видео…", systemImage: "plus")
                }
            }
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(library.items) { item in
                        card(for: item)
                    }
                }
                .padding(4)
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

    private func card(for item: WallpaperItem) -> some View {
        let isDefault = state.defaultItem == item
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
    @State private var speed = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TextField("Название", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .onSubmit(save)

            HStack {
                Text("Скорость")
                Slider(value: $speed, in: 0.25...3, step: 0.25, onEditingChanged: { editing in
                    if !editing { save() }
                })
                .frame(width: 160)
                Text(String(format: "×%.2g", speed)).monospacedDigit().frame(width: 40)
            }

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
        speed = item.speed
    }

    private func save() {
        var updated = item
        updated.name = name.isEmpty ? item.name : name
        updated.speed = speed
        if updated != item { library.update(updated) }
    }
}
