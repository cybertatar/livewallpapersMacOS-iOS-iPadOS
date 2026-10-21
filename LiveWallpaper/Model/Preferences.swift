import Foundation

enum MotionMode: String, Codable, CaseIterable, Identifiable {
    /// Анимация идёт всё время.
    case continuous
    /// Как у Apple: после разблокировки обои оживают и плавно застывают.
    case settle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .continuous: return "Постоянно"
        case .settle: return "Как у Apple: оживают после разблокировки и застывают"
        }
    }
}

enum RotationSource: String, Codable, CaseIterable, Identifiable {
    /// Одна подборка на весь день.
    case playlist
    /// Своя подборка на утро, день, вечер и ночь.
    case timeOfDay

    var id: String { rawValue }
}

enum RotationOrder: String, Codable, CaseIterable, Identifiable {
    case random, sequential
    var id: String { rawValue }
}

enum DayPeriod: String, Codable, CaseIterable, Identifiable {
    case morning, day, evening, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Утро (6:00–12:00)"
        case .day: return "День (12:00–18:00)"
        case .evening: return "Вечер (18:00–23:00)"
        case .night: return "Ночь (23:00–6:00)"
        }
    }

    static func current(at date: Date = Date()) -> DayPeriod {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<12: return .morning
        case 12..<18: return .day
        case 18..<23: return .evening
        default: return .night
        }
    }
}

/// Автоматическая смена обоев.
struct RotationSettings: Codable, Equatable {
    var enabled = false
    var source: RotationSource = .playlist
    var playlist: PlaylistRef = .all
    var periodPlaylists: [DayPeriod: PlaylistRef] = [:]
    /// Интервал смены в минутах; 0 — не менять по таймеру.
    var intervalMinutes = 30
    var changeOnUnlock = false
    var order: RotationOrder = .random
    /// Разные обои на каждом мониторе.
    var differentPerDisplay = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RotationSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        source = try c.decodeIfPresent(RotationSource.self, forKey: .source) ?? d.source
        playlist = try c.decodeIfPresent(PlaylistRef.self, forKey: .playlist) ?? d.playlist
        periodPlaylists = try c.decodeIfPresent([DayPeriod: PlaylistRef].self, forKey: .periodPlaylists) ?? d.periodPlaylists
        intervalMinutes = try c.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? d.intervalMinutes
        changeOnUnlock = try c.decodeIfPresent(Bool.self, forKey: .changeOnUnlock) ?? d.changeOnUnlock
        order = try c.decodeIfPresent(RotationOrder.self, forKey: .order) ?? d.order
        differentPerDisplay = try c.decodeIfPresent(Bool.self, forKey: .differentPerDisplay) ?? d.differentPerDisplay
    }

    func playlist(for period: DayPeriod) -> PlaylistRef {
        periodPlaylists[period] ?? .all
    }

    /// Подборка, из которой сейчас берутся обои.
    func activePlaylist(at date: Date = Date()) -> PlaylistRef {
        source == .timeOfDay ? playlist(for: DayPeriod.current(at: date)) : playlist
    }
}

struct Preferences: Codable, Equatable {
    /// Показывать ли живые обои вообще.
    var enabled = true
    /// Обои по умолчанию для всех мониторов.
    var defaultItemID: UUID?
    /// Обои для конкретных мониторов: UUID дисплея → id обоев.
    var assignments: [String: UUID] = [:]

    var pauseOnBattery = false
    var pauseOnLowPower = true
    /// Пауза, когда рабочий стол полностью закрыт окнами или полноэкранным приложением.
    var pauseWhenHidden = true

    var frameRate = 30
    /// Доля от нативного разрешения, в которой рендерятся шейдеры (экономит GPU).
    var shaderScale = 0.75
    /// Ставить кадр из живых обоев системными обоями (для Mission Control и экрана входа).
    var syncSystemWallpaper = true

    var motionMode: MotionMode = .continuous
    /// Сколько секунд обои идут с полной скоростью перед замедлением.
    var settleDelay = 1.5
    /// За сколько секунд анимация плавно останавливается.
    var settleDuration = 5.0

    var rotation = RotationSettings()

    init() {}

    // Ручной декодер, чтобы новые поля не ломали уже сохранённые настройки.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        defaultItemID = try c.decodeIfPresent(UUID.self, forKey: .defaultItemID)
        assignments = try c.decodeIfPresent([String: UUID].self, forKey: .assignments) ?? d.assignments
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        pauseOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? d.pauseOnLowPower
        pauseWhenHidden = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenHidden) ?? d.pauseWhenHidden
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? d.frameRate
        shaderScale = try c.decodeIfPresent(Double.self, forKey: .shaderScale) ?? d.shaderScale
        syncSystemWallpaper = try c.decodeIfPresent(Bool.self, forKey: .syncSystemWallpaper) ?? d.syncSystemWallpaper
        motionMode = try c.decodeIfPresent(MotionMode.self, forKey: .motionMode) ?? d.motionMode
        settleDelay = try c.decodeIfPresent(Double.self, forKey: .settleDelay) ?? d.settleDelay
        settleDuration = try c.decodeIfPresent(Double.self, forKey: .settleDuration) ?? d.settleDuration
        rotation = try c.decodeIfPresent(RotationSettings.self, forKey: .rotation) ?? d.rotation
    }

    private static let defaultsKey = "preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
