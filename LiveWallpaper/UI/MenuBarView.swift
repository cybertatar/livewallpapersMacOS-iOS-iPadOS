import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Живые обои", isOn: $state.preferences.enabled)
        Toggle("Пауза", isOn: $state.isManuallyPaused)
            .disabled(!state.preferences.enabled)

        Divider()

        Menu("Обои на всех мониторах") {
            ForEach(library.items) { item in
                Button(item.name) { state.applyToAllDisplays(item) }
            }
        }

        Divider()

        Button("Открыть Live Wallpaper…") {
            openWindow(id: MainView.windowID)
            NSApp.activate()
        }
        .keyboardShortcut(",")

        Button("Выйти") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
