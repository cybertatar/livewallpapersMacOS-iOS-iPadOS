import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary
    @Environment(\.openWindow) private var openWindow

    private static let speedPresets: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3]

    var body: some View {
        Toggle("Живые обои", isOn: $state.preferences.enabled)
        Toggle("Пауза", isOn: $state.isManuallyPaused)
            .disabled(!state.preferences.enabled)

        Divider()

        Picker("Скорость анимации", selection: Binding(
            get: { state.visibleSpeed },
            set: { state.setVisibleSpeed($0) }
        )) {
            ForEach(Self.speedPresets, id: \.self) { speed in
                Text(String(format: "×%g", speed)).tag(speed)
            }
        }
        .pickerStyle(.menu)

        if state.preferences.motionMode == .settle {
            Button("Оживить обои") { state.reanimate() }
        }

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
