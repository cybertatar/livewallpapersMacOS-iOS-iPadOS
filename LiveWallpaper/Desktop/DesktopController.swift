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

    var pixelSize: CGSize {
        CGSize(width: frame.width * backingScaleFactor, height: frame.height * backingScaleFactor)
    }
}

/// Держит по одному окну обоев на каждый монитор.
@MainActor
final class DesktopController: NSObject {
    private unowned let state: AppState
    private var windows: [String: WallpaperWindow] = [:]
    private var lastSyncedItems: [String: UUID] = [:]

    // Режим «как у Apple»: обои оживают и плавно застывают.
    private var motion = 1.0
    private var isFrozen = false
    private var settleStart: CFTimeInterval?
    private var motionTimer: Timer?
    private var lastMotionMode: MotionMode?

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
        if state.preferences.motionMode == .settle && isFrozen {
            captureFrozenFrames()
        }
    }

    func reload() {
        let prefs = state.preferences
        guard prefs.enabled else {
            windows.values.forEach { $0.tearDown() }
            windows.removeAll()
            stopMotionTimer()
            return
        }

        let options = RenderOptions(frameRate: prefs.frameRate, shaderScale: prefs.shaderScale)
        var activeIDs = Set<String>()
        var contentChanged = false

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
            if window.show(item: item, videoURL: videoURL, options: options) {
                contentChanged = true
                window.setMotion(motion)
            }
            window.orderFront(nil)

            // В режиме «как у Apple» системные обои — это застывший кадр, его ставит captureFrozenFrames().
            if prefs.syncSystemWallpaper, prefs.motionMode == .continuous,
               let item, lastSyncedItems[uuid] != item.id {
                lastSyncedItems[uuid] = item.id
                syncSystemWallpaper(item: item, videoURL: videoURL, screen: screen)
            }
        }

        for (uuid, window) in windows where !activeIDs.contains(uuid) {
            window.tearDown()
            windows[uuid] = nil
            lastSyncedItems[uuid] = nil
        }

        if prefs.motionMode != lastMotionMode {
            lastMotionMode = prefs.motionMode
            lastSyncedItems.removeAll()
            reanimate()
        } else if contentChanged && prefs.motionMode == .settle {
            reanimate()
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

    // MARK: - Оживление и плавная остановка

    /// Запускает обои с полной скорости. В режиме «как у Apple» через паузу они начнут замедляться.
    func reanimate() {
        stopMotionTimer()
        isFrozen = false
        setMotion(1)
        guard state.preferences.motionMode == .settle, !windows.isEmpty else { return }

        settleStart = CACurrentMediaTime() + state.preferences.settleDelay
        let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(motionTick),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    /// Экран блокируется: если обои ещё двигались, останавливаем их на текущем кадре,
    /// чтобы на экране блокировки была та же картинка, с которой потом продолжится движение.
    func freezeForLock() {
        guard state.preferences.motionMode == .settle, !isFrozen else { return }
        stopMotionTimer()
        freeze()
    }

    @objc private func motionTick() {
        guard let settleStart else { return }
        let now = CACurrentMediaTime()
        guard now >= settleStart else { return }
        let duration = max(state.preferences.settleDuration, 0.1)
        let progress = min((now - settleStart) / duration, 1)
        // Скорость падает по smoothstep: без рывка в начале и с мягкой остановкой в конце.
        let eased = progress * progress * (3 - 2 * progress)
        if progress >= 1 {
            stopMotionTimer()
            freeze()
        } else {
            setMotion(1 - eased)
        }
    }

    private func freeze() {
        isFrozen = true
        setMotion(0)
        captureFrozenFrames()
    }

    private func setMotion(_ value: Double) {
        motion = value
        windows.values.forEach { $0.setMotion(value) }
    }

    private func stopMotionTimer() {
        motionTimer?.invalidate()
        motionTimer = nil
        settleStart = nil
    }

    /// Ставит застывший кадр каждого монитора системными обоями (их и показывает экран блокировки).
    private func captureFrozenFrames() {
        guard state.preferences.syncSystemWallpaper else { return }
        let directory = state.library.snapshotsDirectory
        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID, let window = windows[uuid],
                  let item = window.item, let time = window.frameTime else { continue }
            let videoURL = state.library.fileURL(for: item)
            let size = screen.pixelSize
            Task {
                let image: CGImage?
                switch item.source {
                case .video:
                    guard let videoURL else { return }
                    image = await Snapshots.exactVideoFrame(url: videoURL, at: time)
                case .shader(let kind):
                    image = await Task.detached(priority: .userInitiated) {
                        Snapshots.shaderFrame(kind: kind, time: time, size: size)
                    }.value
                }
                guard let image else { return }
                // macOS кэширует обои по пути, поэтому каждый раз новое имя, а старые кадры удаляем.
                let prefix = "frozen-\(uuid)-"
                let url = directory.appendingPathComponent(prefix + "\(Int(Date().timeIntervalSince1970 * 1000)).png")
                let written = await Task.detached(priority: .utility) { Snapshots.writePNG(image, to: url) }.value
                guard written else { return }
                setDesktopImage(url, for: screen)
                removeOldFiles(in: directory, prefix: prefix, keeping: url)
            }
        }
    }

    private func removeOldFiles(in directory: URL, prefix: String, keeping current: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(prefix) && file != current {
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Системные обои

    private func syncSystemWallpaper(item: WallpaperItem, videoURL: URL?, screen: NSScreen) {
        let size = screen.pixelSize
        let directory = state.library.snapshotsDirectory
        Task {
            guard let url = await Snapshots.wallpaperFile(for: item, videoURL: videoURL,
                                                          size: size, directory: directory) else { return }
            setDesktopImage(url, for: screen)
        }
    }

    private func setDesktopImage(_ url: URL, for screen: NSScreen) {
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
