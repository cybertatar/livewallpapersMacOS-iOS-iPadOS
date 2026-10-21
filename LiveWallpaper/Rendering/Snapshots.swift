import AVFoundation
import AppKit
import CoreImage
import ImageIO

/// Статичные кадры из обоев: превью в библиотеке и системные обои для Mission Control.
enum Snapshots {
    private static let cache = NSCache<NSString, NSImage>()
    private static let ciContext = CIContext()

    @MainActor
    static func thumbnail(for item: WallpaperItem, videoURL: URL?) async -> NSImage? {
        let key = "\(item.id.uuidString)-\(item.source.hashValue)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cgImage = await cgImage(for: item, videoURL: videoURL,
                                          size: CGSize(width: 480, height: 270)) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }

    static func cgImage(for item: WallpaperItem, videoURL: URL?, size: CGSize) async -> CGImage? {
        switch item.source {
        case .video:
            guard let videoURL else { return nil }
            return await videoFrame(url: videoURL, at: 1.0, maxSize: size)
        case .shader, .image:
            return await Task.detached(priority: .utility) {
                Snapshots.sceneFrame(item: item, time: 20, size: size)
            }.value
        }
    }

    static func videoFrame(url: URL, at seconds: Double, maxSize: CGSize?) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let maxSize { generator.maximumSize = maxSize }
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let time = CMTime(seconds: min(seconds, max(duration / 2, 0)), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }

    /// Точный кадр видео в заданный момент (для «застывших» обоев).
    static func exactVideoFrame(url: URL, at seconds: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// Кадр шейдера или «живой картинки».
    static func sceneFrame(item: WallpaperItem, time: Double, size: CGSize) -> CGImage? {
        guard let content = SceneContent(item: item) else { return nil }
        return sceneFrame(content, time: time, size: size)
    }

    static func sceneFrame(_ content: SceneContent, time: Double, size: CGSize) -> CGImage? {
        guard let renderer = ShaderRenderer.shared,
              let buffer = ShaderRenderer.makePixelBuffer(width: Int(size.width), height: Int(size.height)),
              (try? renderer.render(content, time: time, into: buffer)) != nil else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Сохраняет кадр в PNG для системных обоев. Возвращает путь к файлу.
    static func wallpaperFile(for item: WallpaperItem, videoURL: URL?, size: CGSize,
                              directory: URL) async -> URL? {
        let url = directory.appendingPathComponent(
            "\(item.id.uuidString)-\(Int(size.width))x\(Int(size.height)).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let image = await cgImage(for: item, videoURL: videoURL, size: size) else { return nil }
        return writePNG(image, to: url) ? url : nil
    }
}
