import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Вырезает главный объект (персонажа) с картинки — так же, как «Поднять объект» в «Фото».
enum SubjectLifter {
    struct Result {
        /// PNG с прозрачным фоном того же размера, что и исходник.
        let cutoutURL: URL
        /// Горизонтальный центр объекта, 0…1.
        let focusX: Double
        /// Исходная картинка уже была без фона.
        let sourceWasTransparent: Bool
    }

    private static let ciContext = CIContext()

    /// Возвращает nil, если объект не найден.
    static func lift(imageAt url: URL, saveTo cutoutURL: URL) -> Result? {
        // Картинка уже с прозрачным фоном — используем её как есть.
        if let image = loadImage(url), hasTransparency(image) {
            guard writePNG(image, to: cutoutURL) else { return nil }
            return Result(cutoutURL: cutoutURL, focusX: alphaCenterX(image) ?? 0.5, sourceWasTransparent: true)
        }

        let handler = VNImageRequestHandler(url: url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = ciContext.createCGImage(
                ciImage, from: ciImage.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
            guard writePNG(cgImage, to: cutoutURL) else { return nil }
            return Result(cutoutURL: cutoutURL, focusX: alphaCenterX(cgImage) ?? 0.5, sourceWasTransparent: false)
        } catch {
            NSLog("LiveWallpaper: не удалось вырезать объект: \(error)")
            return nil
        }
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Уменьшенная копия картинки в RGBA для анализа альфы.
    private static func smallAlpha(_ image: CGImage, size: Int = 64) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return ok ? pixels : nil
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        guard let pixels = smallAlpha(image) else { return false }
        let transparent = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] < 16 }.count
        return transparent > pixels.count / 4 / 20     // хотя бы 5% прозрачных пикселей
    }

    private static func alphaCenterX(_ image: CGImage) -> Double? {
        let size = 64
        guard let pixels = smallAlpha(image, size: size) else { return nil }
        var sum = 0.0
        var weight = 0.0
        for y in 0..<size {
            for x in 0..<size {
                let a = Double(pixels[(y * size + x) * 4 + 3]) / 255
                sum += a * (Double(x) + 0.5) / Double(size)
                weight += a
            }
        }
        return weight > 0 ? sum / weight : nil
    }
}
