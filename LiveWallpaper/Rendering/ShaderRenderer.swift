import CoreGraphics
import CoreVideo
import Metal
import simd

/// Должна совпадать со struct Uniforms в Shaders.metal.
struct ShaderUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var pad: Float = 0
}

/// Должна совпадать со struct ImageUniforms в Shaders.metal.
struct ImageUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var flags: Float
    var imageSize: SIMD2<Float>
    var particles: Float
    var characterScale: Float
    var glow: SIMD4<Float>
    var extra: SIMD4<Float>       // x — focusX
}

enum ShaderRenderError: LocalizedError {
    case metalUnavailable
    case textureCreationFailed
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "Metal недоступен на этом Mac."
        case .textureCreationFailed: return "Не удалось подготовить кадр для рендера."
        case .imageUnavailable: return "Не удалось загрузить картинку."
        }
    }
}

/// Текстуры «живой картинки». Один экземпляр — на одно окно или один офлайн-рендер
/// (внутри есть промежуточная текстура для фона-сцены).
final class ImageSceneResources {
    /// Настройки эффектов можно менять на лету; картинка и вырез — нет.
    var scene: ImageScene
    let image: MTLTexture
    let cutout: MTLTexture?
    fileprivate var offscreen: MTLTexture?

    init?(scene: ImageScene, imagesDirectory: URL, renderer: ShaderRenderer) {
        guard let image = renderer.texture(for: imagesDirectory.appendingPathComponent(scene.imageFile)) else {
            return nil
        }
        self.scene = scene
        self.image = image
        self.cutout = scene.cutoutFile.flatMap { renderer.texture(for: imagesDirectory.appendingPathComponent($0)) }
    }
}

/// Что рисовать: процедурную сцену или картинку с эффектами.
enum SceneContent {
    case shader(ShaderKind)
    case image(ImageSceneResources)

    /// Для видео — nil (их рисует AVPlayer).
    init?(item: WallpaperItem, imagesDirectory: URL = WallpaperLibrary.imagesURL) {
        switch item.source {
        case .video:
            return nil
        case .shader(let kind):
            self = .shader(kind)
        case .image(let scene):
            guard let renderer = ShaderRenderer.shared,
                  let resources = ImageSceneResources(scene: scene, imagesDirectory: imagesDirectory, renderer: renderer)
            else { return nil }
            self = .image(resources)
        }
    }
}

/// Общий для живых обоев и офлайн-рендера набор пайплайнов Metal.
/// Пайплайны неизменяемы после инициализации, поэтому их можно использовать с любого потока.
final class ShaderRenderer {
    static let shared: ShaderRenderer? = ShaderRenderer()

    static let pixelFormat: MTLPixelFormat = .bgra8Unorm

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let pipelines: [ShaderKind: MTLRenderPipelineState]
    private let imagePipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState?
    private let emptyTexture: MTLTexture?
    private let textureCache: CVMetalTextureCache
    private let imageCache = NSCache<NSURL, TextureBox>()

    private final class TextureBox {
        let texture: MTLTexture
        init(_ texture: MTLTexture) { self.texture = texture }
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "wallpaper_vertex") else {
            return nil
        }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let cache else { return nil }

        func makePipeline(_ name: String) -> MTLRenderPipelineState? {
            guard let fragment = library.makeFunction(name: name) else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
            do {
                return try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                NSLog("LiveWallpaper: не удалось собрать шейдер \(name): \(error)")
                return nil
            }
        }

        var pipelines: [ShaderKind: MTLRenderPipelineState] = [:]
        for kind in ShaderKind.allCases {
            pipelines[kind] = makePipeline(kind.functionName)
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        let emptyDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        let empty = device.makeTexture(descriptor: emptyDescriptor)
        var zero: UInt32 = 0
        empty?.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &zero, bytesPerRow: 4)

        self.device = device
        self.commandQueue = queue
        self.pipelines = pipelines
        self.imagePipeline = makePipeline("fragment_imageScene")
        self.sampler = device.makeSamplerState(descriptor: samplerDescriptor)
        self.emptyTexture = empty
        self.textureCache = cache
    }

    // MARK: - Кодирование кадра

    /// Кодирует один кадр сцены в переданный render pass.
    func encode(_ content: SceneContent, time: Double, size: CGSize,
                pass: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        switch content {
        case .shader(let kind):
            encode(kind: kind, time: time, size: size, pass: pass, commandBuffer: commandBuffer)
        case .image(let resources):
            encodeImage(resources, time: time, size: size, pass: pass, commandBuffer: commandBuffer)
        }
    }

    func encode(kind: ShaderKind, time: Double, size: CGSize,
                pass: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = pipelines[kind],
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // Время держим в разумных пределах, чтобы не терять точность float на долгих сессиях.
        var uniforms = ShaderUniforms(
            resolution: SIMD2(Float(size.width), Float(size.height)),
            time: Float(time.truncatingRemainder(dividingBy: 10_000))
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeImage(_ resources: ImageSceneResources, time: Double, size: CGSize,
                             pass: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer) {
        let scene = resources.scene
        var background = resources.image

        // Фон — живая сцена: сначала рисуем её в промежуточную текстуру.
        if let kind = scene.backgroundScene, let offscreen = offscreenTexture(for: resources, size: size) {
            let bgPass = MTLRenderPassDescriptor()
            bgPass.colorAttachments[0].texture = offscreen
            bgPass.colorAttachments[0].loadAction = .dontCare
            bgPass.colorAttachments[0].storeAction = .store
            encode(kind: kind, time: time, size: size, pass: bgPass, commandBuffer: commandBuffer)
            background = offscreen
        }

        guard let pipeline = imagePipeline,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        var flags: Float = 0
        if scene.kenBurns { flags += 1 }
        if scene.floating { flags += 2 }
        if scene.lightRays { flags += 4 }
        if resources.cutout != nil { flags += 8 }
        if scene.backgroundScene != nil { flags += 16 }
        if scene.aura != nil { flags += 32 }
        let glow = scene.aura?.rgb ?? SIMD3(0, 0, 0)

        var uniforms = ImageUniforms(
            resolution: SIMD2(Float(size.width), Float(size.height)),
            time: Float(time.truncatingRemainder(dividingBy: 10_000)),
            flags: flags,
            imageSize: SIMD2(Float(resources.image.width), Float(resources.image.height)),
            particles: Float(scene.particles.rawValue),
            characterScale: Float(scene.characterScale),
            glow: SIMD4(glow, 1),
            extra: SIMD4(Float(scene.focusX), 0, 0, 0)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ImageUniforms>.stride, index: 0)
        encoder.setFragmentTexture(background, index: 0)
        encoder.setFragmentTexture(resources.cutout ?? emptyTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func offscreenTexture(for resources: ImageSceneResources, size: CGSize) -> MTLTexture? {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        if let existing = resources.offscreen, existing.width == width, existing.height == height {
            return existing
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        resources.offscreen = device.makeTexture(descriptor: descriptor)
        return resources.offscreen
    }

    // MARK: - Текстуры картинок

    /// Загружает картинку в текстуру RGBA (premultiplied, с мип-уровнями для размытия). Кэшируется.
    func texture(for url: URL) -> MTLTexture? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached.texture }
        guard let image = SubjectLifter.loadImage(url) else { return nil }
        // Очень большие картинки уменьшаем: обоям больше 6K не нужно.
        let maxSide = 6144
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { buffer in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: buffer.baseAddress!, bytesPerRow: width * 4)
        }
        if let commandBuffer = commandQueue.makeCommandBuffer(),
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        imageCache.setObject(TextureBox(texture), forKey: url as NSURL)
        return texture
    }

    // MARK: - Офлайн-рендер

    /// Рисует кадр в CVPixelBuffer формата 32BGRA (Metal-совместимый) и ждёт окончания рендера.
    func render(_ content: SceneContent, time: Double, into pixelBuffer: CVPixelBuffer) throws {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            Self.pixelFormat, width, height, 0, &cvTexture
        )
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ShaderRenderError.textureCreationFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        encode(content, time: time, size: CGSize(width: width, height: height),
               pass: pass, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func render(kind: ShaderKind, time: Double, into pixelBuffer: CVPixelBuffer) throws {
        try render(.shader(kind), time: time, into: pixelBuffer)
    }

    /// Создаёт пиксельный буфер, подходящий для `render(_:time:into:)`.
    static func makePixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                            attributes as CFDictionary, &buffer)
        return buffer
    }
}
