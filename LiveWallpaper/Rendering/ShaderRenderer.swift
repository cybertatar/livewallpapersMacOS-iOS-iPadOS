import CoreVideo
import Metal
import simd

/// Должна совпадать со struct Uniforms в Shaders.metal.
struct ShaderUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var pad: Float = 0
}

enum ShaderRenderError: LocalizedError {
    case metalUnavailable
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "Metal недоступен на этом Mac."
        case .textureCreationFailed: return "Не удалось подготовить кадр для рендера."
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
    private let textureCache: CVMetalTextureCache

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

        var pipelines: [ShaderKind: MTLRenderPipelineState] = [:]
        for kind in ShaderKind.allCases {
            guard let fragment = library.makeFunction(name: kind.functionName) else { continue }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
            do {
                pipelines[kind] = try device.makeRenderPipelineState(descriptor: descriptor)
            } catch {
                NSLog("LiveWallpaper: не удалось собрать шейдер \(kind.rawValue): \(error)")
            }
        }

        self.device = device
        self.commandQueue = queue
        self.pipelines = pipelines
        self.textureCache = cache
    }

    /// Кодирует один кадр шейдера в переданный render pass.
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

    /// Рисует кадр в CVPixelBuffer формата 32BGRA (Metal-совместимый) и ждёт окончания рендера.
    func render(kind: ShaderKind, time: Double, into pixelBuffer: CVPixelBuffer) throws {
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
        encode(kind: kind, time: time, size: CGSize(width: width, height: height),
               pass: pass, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Создаёт пиксельный буфер, подходящий для `render(kind:time:into:)`.
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
