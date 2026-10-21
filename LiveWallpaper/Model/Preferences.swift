import Foundation

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
