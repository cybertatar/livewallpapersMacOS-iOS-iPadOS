import AVFoundation

/// Рендерит процедурные обои в видеофайл (нужно, чтобы сделать из них Live Photo).
enum ShaderVideoRenderer {
    static func render(item: WallpaperItem, speed: Double, startTime: Double, duration: Double,
                       size: CGSize, fps: Int = 30, to url: URL,
                       progress: ((Double) -> Void)? = nil) async throws {
        guard let renderer = ShaderRenderer.shared else { throw ShaderRenderError.metalUnavailable }
        guard let content = SceneContent(item: item) else { throw ShaderRenderError.imageUnavailable }
        let width = Int(size.width)
        let height = Int(size.height)

        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw LivePhotoError.writeFailed(writer.error?.localizedDescription ?? "writer")
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(duration * Double(fps)))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
            }
            guard let pixelBuffer = buffer ?? ShaderRenderer.makePixelBuffer(width: width, height: height) else {
                throw ShaderRenderError.textureCreationFailed
            }
            let time = startTime + Double(frame) / Double(fps) * speed
            try renderer.render(content, time: time, into: pixelBuffer)
            let presentationTime = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw LivePhotoError.writeFailed(writer.error?.localizedDescription ?? "кадр \(frame)")
            }
            progress?(Double(frame + 1) / Double(frameCount))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw LivePhotoError.writeFailed(writer.error?.localizedDescription ?? "writer")
        }
    }
}
