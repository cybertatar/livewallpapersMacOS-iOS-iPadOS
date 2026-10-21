import AppKit
import SwiftUI

struct DisplaysView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var screens: [ScreenInfo] = []

    private struct ScreenInfo: Identifiable {
        let id: String
        let name: String
        let details: String
    }

    var body: some View {
        Form {
            Section {
                Text("По умолчанию на всех мониторах: \(state.defaultItem?.name ?? "—"). Здесь можно выбрать отдельные обои для каждого монитора.")
                    .foregroundStyle(.secondary)
            }
            ForEach(screens) { screen in
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        if let item = state.item(forDisplay: screen.id) {
                            ThumbnailView(item: item).frame(width: 200)
                        }
                        VStack(alignment: .leading) {
                            Picker("Обои", selection: assignment(for: screen.id)) {
                                Text("Как на всех").tag(UUID?.none)
                                Divider()
                                ForEach(library.items) { item in
                                    Text(item.name).tag(UUID?.some(item.id))
                                }
                            }
                            Text(screen.details).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(screen.name)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refresh()
        }
    }

    private func assignment(for uuid: String) -> Binding<UUID?> {
        Binding(
            get: { state.preferences.assignments[uuid] },
            set: { state.assign($0, toDisplay: uuid) }
        )
    }

    private func refresh() {
        screens = NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            let scale = screen.backingScaleFactor
            let width = Int(screen.frame.width * scale)
            let height = Int(screen.frame.height * scale)
            return ScreenInfo(id: uuid, name: screen.localizedName, details: "\(width) × \(height) пикс.")
        }
    }
}
