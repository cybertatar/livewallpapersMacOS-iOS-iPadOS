import Foundation

/// Тематические подборки встроенных анимаций.
enum ShaderCollection: String, Codable, CaseIterable, Identifiable {
    case frieren, zelda, cyberpunk, anime, abstract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frieren: return "Фрирен"
        case .zelda: return "Зельда"
        case .cyberpunk: return "Киберпанк"
        case .anime: return "Аниме"
        case .abstract: return "Абстракция"
        }
    }
}

/// Процедурные анимации, которые рисуются шейдерами Metal (Rendering/Shaders/*.h).
/// rawValue совпадает с именем сцены `scene_<rawValue>` и сохраняется в библиотеке — не переименовывать.
enum ShaderKind: String, Codable, CaseIterable, Identifiable {
    case aurora, plasma, waves, starfield
    case frierenFlowers, frierenSpell, frierenMeteor, frierenAutumn
    case hyruleFields, skyIslands, ancientTech, lostWoods
    case neonCity, synthwave, digitalRain, neonTunnel
    case sakura, summerSky, fireflies, lanterns, oceanSunset

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: return "Северное сияние"
        case .plasma: return "Плазма"
        case .waves: return "Волны"
        case .starfield: return "Звёзды"
        case .frierenFlowers: return "Поле голубых цветов"
        case .frierenSpell: return "Магический круг"
        case .frierenMeteor: return "Звездопад"
        case .frierenAutumn: return "Осенний путь"
        case .hyruleFields: return "Поля Хайрула"
        case .skyIslands: return "Небесные острова"
        case .ancientTech: return "Древняя технология"
        case .lostWoods: return "Затерянный лес"
        case .neonCity: return "Неоновый город"
        case .synthwave: return "Синтвейв"
        case .digitalRain: return "Цифровой дождь"
        case .neonTunnel: return "Неоновый тоннель"
        case .sakura: return "Сакура"
        case .summerSky: return "Летнее небо"
        case .fireflies: return "Светлячки"
        case .lanterns: return "Небесные фонарики"
        case .oceanSunset: return "Закат у моря"
        }
    }

    var collection: ShaderCollection {
        switch self {
        case .aurora, .plasma, .waves, .starfield: return .abstract
        case .frierenFlowers, .frierenSpell, .frierenMeteor, .frierenAutumn: return .frieren
        case .hyruleFields, .skyIslands, .ancientTech, .lostWoods: return .zelda
        case .neonCity, .synthwave, .digitalRain, .neonTunnel: return .cyberpunk
        case .sakura, .summerSky, .fireflies, .lanterns, .oceanSunset: return .anime
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
