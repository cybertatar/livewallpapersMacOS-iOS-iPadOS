import SwiftUI

/// Встроенные и свои подборки: просмотр, создание, состав.
struct PlaylistsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var selection: PlaylistRef? = .collection(.frieren)

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                Section("Встроенные") {
                    ForEach([PlaylistRef.all, .images, .videos] + ShaderCollection.allCases.map { .collection($0) }, id: \.self) { ref in
                        row(ref)
                    }
                }
                Section("Мои подборки") {
                    ForEach(library.playlists) { playlist in
                        row(.custom(playlist.id))
                    }
                    Button {
                        let playlist = library.createPlaylist(name: "Подборка \(library.playlists.count + 1)")
                        selection = .custom(playlist.id)
                    } label: {
                        Label("Новая подборка", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)

            Divider()

            if let selection {
                PlaylistDetail(ref: selection) { self.selection = $0 }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Text("Выберите подборку").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func row(_ ref: PlaylistRef) -> some View {
        HStack {
            Text(library.title(for: ref))
            Spacer()
            Text("\(library.items(in: ref).count)").foregroundStyle(.secondary).monospacedDigit()
        }
        .tag(ref)
    }
}

private struct PlaylistDetail: View {
    let ref: PlaylistRef
    let onSelect: (PlaylistRef?) -> Void

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var name = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)]

    private var customID: UUID? {
        if case .custom(let id) = ref { return id }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let customID {
                    TextField("Название", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(maxWidth: 260)
                        .onSubmit { library.renamePlaylist(id: customID, to: name) }
                } else {
                    Text(library.title(for: ref)).font(.title2.weight(.semibold))
                }
                Spacer()
                Button("Автосмена из этой подборки") {
                    var prefs = state.preferences
                    prefs.rotation.enabled = true
                    prefs.rotation.source = .playlist
                    prefs.rotation.playlist = ref
                    state.preferences = prefs
                }
                if customID == nil {
                    Button("Скопировать в свою") {
                        let copy = library.createPlaylist(name: library.title(for: ref),
                                                          itemIDs: library.items(in: ref).map(\.id))
                        onSelect(.custom(copy.id))
                    }
                } else if let customID {
                    Button("Удалить", role: .destructive) {
                        library.deletePlaylist(id: customID)
                        onSelect(nil)
                    }
                }
            }

            if customID != nil {
                Text("Отметьте обои, которые входят в подборку.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(customID == nil ? library.items(in: ref) : library.items) { item in
                        card(item)
                    }
                }
                .padding(2)
            }
        }
        .onAppear { name = library.title(for: ref) }
        .onChange(of: ref) { name = library.title(for: ref) }
    }

    private func card(_ item: WallpaperItem) -> some View {
        let included = customID.map { library.contains(item, inPlaylist: $0) } ?? true
        return VStack(alignment: .leading, spacing: 4) {
            ThumbnailView(item: item)
                .opacity(included ? 1 : 0.45)
                .overlay(alignment: .topTrailing) {
                    if customID != nil {
                        Image(systemName: included ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(included ? Color.accentColor : Color.white)
                            .shadow(radius: 2)
                            .padding(5)
                    }
                }
            Text(item.name).font(.caption).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let customID {
                library.setItem(item, inPlaylist: customID, included: !included)
            }
        }
        .contextMenu {
            Button("Поставить на все мониторы") { state.applyToAllDisplays(item) }
        }
    }
}
