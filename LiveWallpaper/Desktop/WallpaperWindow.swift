import AppKit

/// Окно без рамки на уровне рабочего стола: под иконками и виджетами, но поверх системных обоев.
final class WallpaperWindow: NSWindow {
    private(set) var item: WallpaperItem?
    private var options: RenderOptions?
    private var content: WallpaperContentView?
    var onVisibilityChange: (() -> Void)?

    convenience init(screen: NSScreen) {
        self.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        setFrame(screen.frame, display: false)

        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionDidChange),
            name: NSWindow.didChangeOcclusionStateNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var isVisibleOnScreen: Bool { occlusionState.contains(.visible) }

    @objc private func occlusionDidChange() {
        onVisibilityChange?()
    }

    /// Показывает обои. Пересоздаёт содержимое только если сменились сами обои
    /// (скорость и название применяются на лету). Возвращает true, если содержимое пересоздано.
    @discardableResult
    func show(item: WallpaperItem?, videoURL: URL?, options: RenderOptions) -> Bool {
        if let content, item?.id == self.item?.id, item?.source == self.item?.source {
            if options != self.options {
                content.apply(options: options)
                self.options = options
            }
            if let item, item.speed != self.item?.speed {
                content.setSpeed(item.speed)
            }
            self.item = item
            return false
        }
        // Поменялись только эффекты «живой картинки» — применяем без пересоздания.
        if let content, let item, item.id == self.item?.id, let scene = item.imageScene,
           content.updateImageScene(scene) {
            self.item = item
            return false
        }
        content?.removeFromSuperview()
        content = nil
        self.item = item
        self.options = options

        guard let item, let contentView else { return true }
        let view: WallpaperContentView?
        switch item.source {
        case .video:
            if let videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
                view = VideoWallpaperView(url: videoURL, speed: item.speed)
            } else {
                view = nil
            }
        case .shader, .image:
            view = SceneContent(item: item).flatMap {
                ShaderWallpaperView(content: $0, speed: item.speed, options: options)
            }
        }
        guard let view else { return true }
        view.frame = contentView.bounds
        view.autoresizingMask = [.width, .height]
        contentView.addSubview(view)
        content = view
        return true
    }

    func setPaused(_ paused: Bool) {
        content?.setPaused(paused)
    }

    func setMotion(_ motion: Double) {
        content?.setMotion(motion)
    }

    var frameTime: Double? { content?.frameTime }

    func tearDown() {
        NotificationCenter.default.removeObserver(self)
        content?.removeFromSuperview()
        content = nil
        orderOut(nil)
        close()
    }
}
