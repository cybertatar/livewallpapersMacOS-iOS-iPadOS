import AVFoundation
import AppKit
import MetalKit

struct RenderOptions: Equatable {
    var frameRate: Int
    var shaderScale: Double
}

/// Базовый класс для содержимого окна обоев.
class WallpaperContentView: NSView {
    func setPaused(_ paused: Bool) {}
    func apply(options: RenderOptions) {}
}

// MARK: - Видео

final class VideoWallpaperView: WallpaperContentView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private let rate: Float
    private var isPaused = false

    init(url: URL, speed: Double) {
        rate = Float(max(speed, 0.1))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)

        player.playImmediately(atRate: rate)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        if paused {
            player.pause()
        } else {
            player.playImmediately(atRate: rate)
        }
    }
}

// MARK: - Шейдер

final class ShaderWallpaperView: WallpaperContentView, MTKViewDelegate {
    private let renderer: ShaderRenderer
    private let mtkView: MTKView
    private let kind: ShaderKind
    private let speed: Double
    private var scale: Double
    private var elapsed: Double
    private var lastTimestamp: CFTimeInterval?

    init?(kind: ShaderKind, speed: Double, options: RenderOptions) {
        guard let renderer = ShaderRenderer.shared else { return nil }
        self.renderer = renderer
        self.kind = kind
        self.speed = speed
        self.scale = options.shaderScale
        // Случайная стартовая точка, чтобы мониторы не показывали одинаковую картинку.
        self.elapsed = Double.random(in: 0...300)
        mtkView = MTKView(frame: .zero, device: renderer.device)
        super.init(frame: .zero)

        mtkView.colorPixelFormat = ShaderRenderer.pixelFormat
        mtkView.framebufferOnly = true
        mtkView.autoResizeDrawable = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.preferredFramesPerSecond = options.frameRate
        mtkView.delegate = self
        mtkView.autoresizingMask = [.width, .height]
        mtkView.frame = bounds
        addSubview(mtkView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let backing = window?.backingScaleFactor ?? 2
        let factor = backing * scale
        let size = CGSize(width: max(1, (bounds.width * factor).rounded()),
                          height: max(1, (bounds.height * factor).rounded()))
        if mtkView.drawableSize != size {
            mtkView.drawableSize = size
        }
    }

    override func setPaused(_ paused: Bool) {
        guard mtkView.isPaused != paused else { return }
        mtkView.isPaused = paused
        if paused { lastTimestamp = nil }
    }

    override func apply(options: RenderOptions) {
        mtkView.preferredFramesPerSecond = options.frameRate
        scale = options.shaderScale
        updateDrawableSize()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if let lastTimestamp {
            elapsed += min(now - lastTimestamp, 0.25) * speed
        }
        lastTimestamp = now

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
        renderer.encode(kind: kind, time: elapsed, size: view.drawableSize,
                        pass: pass, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
