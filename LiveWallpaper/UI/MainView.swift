import SwiftUI

struct MainView: View {
    static let windowID = "main"

    private enum Tab: Hashable {
        case library, displays, livePhoto, settings
    }

    @State private var tab: Tab = .library

    var body: some View {
        TabView(selection: $tab) {
            LibraryView()
                .tabItem { Label("Библиотека", systemImage: "square.grid.2x2") }
                .tag(Tab.library)
            DisplaysView()
                .tabItem { Label("Мониторы", systemImage: "display.2") }
                .tag(Tab.displays)
            LivePhotoView()
                .tabItem { Label("Live Photo для iPhone/iPad", systemImage: "livephoto") }
                .tag(Tab.livePhoto)
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .padding()
        .frame(minWidth: 760, minHeight: 520)
    }
}

/// Превью обоев (кадр из видео или шейдера).
struct ThumbnailView: View {
    let item: WallpaperItem
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: item.id) {
            image = await Snapshots.thumbnail(for: item, videoURL: library.fileURL(for: item))
        }
    }
}

/// Скорость анимации обоев; применяется сразу, без перезапуска.
struct SpeedControl: View {
    let item: WallpaperItem
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { item.speed },
                set: { state.setSpeed(($0 * 20).rounded() / 20, for: item) }
            ), in: 0.1...3)
            Image(systemName: "hare").foregroundStyle(.secondary)
            Text(String(format: "×%.2f", item.speed))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .help("Скорость анимации")
    }
}
