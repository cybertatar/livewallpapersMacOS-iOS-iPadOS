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

/// Частицы поверх «живой картинки».
enum ParticleEffect: Int, Codable, CaseIterable, Identifiable {
    case none = 0, petals, leaves, snow, fireflies, sparkles, rain, stars

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "Без частиц"
        case .petals: return "Лепестки сакуры"
        case .leaves: return "Осенние листья"
        case .snow: return "Снег"
        case .fireflies: return "Светлячки"
        case .sparkles: return "Магические искры"
        case .rain: return "Дождь"
        case .stars: return "Звёзды"
        }
    }
}

/// Цвет свечения вокруг персонажа.
enum AuraColor: String, Codable, CaseIterable, Identifiable {
    case magic, gold, pink, green, violet, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magic: return "Голубое"
        case .gold: return "Золотое"
        case .pink: return "Розовое"
        case .green: return "Зелёное"
        case .violet: return "Фиолетовое"
        case .white: return "Белое"
        }
    }

    var rgb: SIMD3<Float> {
        switch self {
        case .magic: return SIMD3(0.45, 0.80, 1.00)
        case .gold: return SIMD3(1.00, 0.80, 0.40)
        case .pink: return SIMD3(1.00, 0.55, 0.75)
        case .green: return SIMD3(0.50, 1.00, 0.55)
        case .violet: return SIMD3(0.70, 0.50, 1.00)
        case .white: return SIMD3(0.95, 0.95, 1.00)
        }
    }
}

/// «Живая картинка»: изображение пользователя, вырезанный с него персонаж и эффекты.
struct ImageScene: Codable, Hashable {
    /// Исходная картинка в папке Images библиотеки.
    var imageFile: String
    /// Персонаж с прозрачным фоном (PNG), если его удалось вырезать.
    var cutoutFile: String?
    /// Горизонтальный центр персонажа на картинке (0…1) — по нему кадрируется экран.
    var focusX: Double = 0.5
    /// nil — фон из самой картинки, иначе живая сцена.
    var backgroundScene: ShaderKind?
    var particles: ParticleEffect = .sparkles
    var aura: AuraColor? = .magic
    var kenBurns = true
    var floating = true
    var lightRays = false
    /// Высота персонажа относительно экрана, когда фон — живая сцена.
    var characterScale = 0.85
}

enum WallpaperSource: Codable, Hashable {
    /// Видео, скопированное в папку библиотеки.
    case video(fileName: String)
    case shader(ShaderKind)
    case image(ImageScene)
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

    var isImage: Bool {
        if case .image = source { return true }
        return false
    }

    var imageScene: ImageScene? {
        if case .image(let scene) = source { return scene }
        return nil
    }

    var shaderKind: ShaderKind? {
        if case .shader(let kind) = source { return kind }
        return nil
    }
}
