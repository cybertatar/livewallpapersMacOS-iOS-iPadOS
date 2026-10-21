import AppKit
import SwiftUI

@main
struct LiveWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Live Wallpaper", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(state.library)
        }

        Window("Live Wallpaper", id: MainView.windowID) {
            MainView()
                .environmentObject(state)
                .environmentObject(state.library)
        }
        .defaultSize(width: 900, height: 620)
        .defaultLaunchBehavior(.suppressed)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.start()
    }
}
