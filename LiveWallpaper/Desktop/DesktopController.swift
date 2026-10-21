import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Стабильный идентификатор монитора (не меняется между перезагрузками).
    var displayUUID: String? {
        guard let id = displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Держит по одному окну обоев на каждый монитор.
@MainActor
final class DesktopController: NSObject {
    private unowned let state: AppState
    private var windows: [String: WallpaperWindow] = [:]
    private var lastSyncedItems: [String: UUID] = [:]

    init(state: AppState) {
        self.state = state
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private func screensChanged() { reload() }

    @objc private func spaceChanged() {
        // У каждого Space свои системные обои — подставляем кадр и туда.
        lastSyncedItems.removeAll()
        reload()
    }

    func reload() {
        let prefs = state.preferences
        guard prefs.enabled else {
            windows.values.forEach { $0.tearDown() }
            windows.removeAll()
            return
        }

        let options = RenderOptions(frameRate: prefs.frameRate, shaderScale: prefs.shaderScale)
        var activeIDs = Set<String>()

        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            activeIDs.insert(uuid)

            let window: WallpaperWindow
            if let existing = windows[uuid] {
                window = existing
                if window.frame != screen.frame {
                    window.setFrame(screen.frame, display: true)
                }
            } else {
                window = WallpaperWindow(screen: screen)
                window.onVisibilityChange = { [weak self] in self?.updatePause() }
                windows[uuid] = window
            }

            let item = state.item(forDisplay: uuid)
            let videoURL = item.flatMap { state.library.fileURL(for: $0) }
            window.show(item: item, videoURL: videoURL, options: options)
            window.orderFront(nil)

            if prefs.syncSystemWallpaper, let item, lastSyncedItems[uuid] != item.id {
                lastSyncedItems[uuid] = item.id
                syncSystemWallpaper(item: item, videoURL: videoURL, screen: screen)
            }
        }

        for (uuid, window) in windows where !activeIDs.contains(uuid) {
            window.tearDown()
            windows[uuid] = nil
            lastSyncedItems[uuid] = nil
        }

        updatePause()
    }

    func updatePause() {
        let prefs = state.preferences
        let globallyPaused = state.isManuallyPaused || state.pauseMonitor.shouldPause(prefs)
        for window in windows.values {
            let hidden = prefs.pauseWhenHidden && !window.isVisibleOnScreen
            window.setPaused(globallyPaused || hidden)
        }
    }

    private func syncSystemWallpaper(item: WallpaperItem, videoURL: URL?, screen: NSScreen) {
        let size = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                          height: screen.frame.height * screen.backingScaleFactor)
        let directory = state.library.snapshotsDirectory
        Task {
            guard let url = await Snapshots.wallpaperFile(for: item, videoURL: videoURL,
                                                          size: size, directory: directory) else { return }
            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ]
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                NSLog("LiveWallpaper: не удалось поставить системные обои: \(error)")
            }
        }
    }
}
