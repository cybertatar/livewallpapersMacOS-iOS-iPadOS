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

    /// Показывает обои. Пересоздаёт содержимое только если сами обои поменялись.
    func show(item: WallpaperItem?, videoURL: URL?, options: RenderOptions) {
        if item == self.item, content != nil {
            if options != self.options {
                content?.apply(options: options)
                self.options = options
            }
            return
        }
        content?.removeFromSuperview()
        content = nil
        self.item = item
        self.options = options

        guard let item, let contentView else { return }
        let view: WallpaperContentView?
        switch item.source {
        case .video:
            if let videoURL, FileManager.default.fileExists(atPath: videoURL.path) {
                view = VideoWallpaperView(url: videoURL, speed: item.speed)
            } else {
                view = nil
            }
        case .shader(let kind):
            view = ShaderWallpaperView(kind: kind, speed: item.speed, options: options)
        }
        guard let view else { return }
        view.frame = contentView.bounds
        view.autoresizingMask = [.width, .height]
        contentView.addSubview(view)
        content = view
    }

    func setPaused(_ paused: Bool) {
        content?.setPaused(paused)
    }

    func tearDown() {
        NotificationCenter.default.removeObserver(self)
        content?.removeFromSuperview()
        content = nil
        orderOut(nil)
        close()
    }
}
