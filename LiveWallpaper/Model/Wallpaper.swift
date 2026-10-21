import Foundation

/// Процедурные анимации, которые рисуются шейдерами Metal (см. Shaders.metal).
enum ShaderKind: String, Codable, CaseIterable, Identifiable {
    case aurora
    case plasma
    case waves
    case starfield

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Северное сияние"
        case .plasma: return "Плазма"
        case .waves: return "Волны"
        case .starfield: return "Звёзды"
        }
    }

    /// Имя fragment-функции в Shaders.metal.
    var functionName: String { "fragment_\(rawValue)" }
}

enum WallpaperSource: Codable, Hashable {
    /// Видео, скопированное в папку библиотеки.
    case video(fileName: String)
    case shader(ShaderKind)
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var source: WallpaperSource
    /// Множитель скорости анимации (для видео — скорость воспроизведения).
    var speed: Double = 1.0

    var isVideo: Bool {
        if case .video = source { return true }
        return false
    }

    var shaderKind: ShaderKind? {
        if case .shader(let kind) = source { return kind }
        return nil
    }
}
