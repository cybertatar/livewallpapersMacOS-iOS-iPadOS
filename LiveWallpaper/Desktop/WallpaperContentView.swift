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
    func setSpeed(_ speed: Double) {}
    /// Множитель движения 0…1 для плавной остановки (0 — кадр застыл).
    func setMotion(_ motion: Double) {}
    /// Текущая позиция анимации: секунды видео или время шейдера.
    var frameTime: Double { 0 }
}

// MARK: - Видео

final class VideoWallpaperView: WallpaperContentView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var speed: Double
    private var motion = 1.0
    private var isPaused = false

    init(url: URL, speed: Double) {
        self.speed = speed
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

        applyRate()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override var frameTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    override func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        applyRate()
    }

    override func setSpeed(_ speed: Double) {
        self.speed = speed
        applyRate()
    }

    override func setMotion(_ motion: Double) {
        self.motion = motion
        applyRate()
    }

    private func applyRate() {
        let rate = isPaused ? 0 : Float(max(speed, 0.1) * motion)
        if rate < 0.02 {
            if player.rate != 0 { player.pause() }
        } else if player.rate == 0 {
            player.playImmediately(atRate: rate)
        } else {
            player.rate = rate
        }
    }
}

// MARK: - Шейдер

final class ShaderWallpaperView: WallpaperContentView, MTKViewDelegate {
    private let renderer: ShaderRenderer
    private let mtkView: MTKView
    private let kind: ShaderKind
    private var speed: Double
    private var scale: Double
    private var motion = 1.0
    private var isPausedExternally = false
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

    // Размер drawable меняем вне layout(): изменение drawableSize само запускает layout MTKView.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDrawableSize()
        redrawIfStopped()
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
            redrawIfStopped()
        }
    }

    override var frameTime: Double { elapsed }

    override func setPaused(_ paused: Bool) {
        isPausedExternally = paused
        updateRunning()
    }

    override func setSpeed(_ speed: Double) {
        self.speed = speed
    }

    override func setMotion(_ motion: Double) {
        self.motion = motion
        updateRunning()
    }

    private func updateRunning() {
        let stopped = isPausedExternally || motion <= 0
        guard mtkView.isPaused != stopped else { return }
        mtkView.isPaused = stopped
        lastTimestamp = nil
        redrawIfStopped()
    }

    /// Остановленный MTKView ничего не рисует сам — дорисовываем текущий кадр вручную,
    /// иначе при старте на паузе или после смены размера будет чёрный экран.
    private func redrawIfStopped() {
        guard mtkView.isPaused, window != nil else { return }
        mtkView.draw()
    }

    override func apply(options: RenderOptions) {
        mtkView.preferredFramesPerSecond = options.frameRate
        scale = options.shaderScale
        updateDrawableSize()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if !view.isPaused {
            let now = CACurrentMediaTime()
            if let lastTimestamp {
                elapsed += min(now - lastTimestamp, 0.25) * speed * motion
            }
            lastTimestamp = now
        }

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
        renderer.encode(kind: kind, time: elapsed, size: view.drawableSize,
                        pass: pass, commandBuffer: commandBuffer)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
