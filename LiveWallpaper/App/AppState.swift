import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let library = WallpaperLibrary()
    let pauseMonitor = PauseMonitor()
    private(set) var desktop: DesktopController!
    private(set) var rotation: RotationController!

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            desktop?.reload()
            if preferences.rotation != oldValue.rotation {
                rotation?.settingsChanged()
            }
        }
    }

    /// Ручная пауза из меню (не сохраняется между запусками).
    @Published var isManuallyPaused = false {
        didSet { desktop?.updatePause() }
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        preferences = Preferences.load()
        desktop = DesktopController(state: self)
        rotation = RotationController(state: self)
        pauseMonitor.onChange = { [weak self] in self?.desktop.updatePause() }
        pauseMonitor.onBlock = { [weak self] in self?.desktop.freezeForLock() }
        pauseMonitor.onUnblock = { [weak self] in
            self?.rotation.handleUnlock()
            self?.desktop.reanimate()
        }
        // Изменения в библиотеке (удаление, смена скорости) сразу применяются к обоям.
        library.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.desktop.reload() }
            .store(in: &cancellables)
    }

    func start() {
        desktop.reload()
        rotation.settingsChanged()
    }

    /// Следующие обои (из подборки автосмены, если она включена).
    func nextWallpaper() {
        rotation.advance()
    }

    /// Обои по умолчанию для всех мониторов.
    var defaultItem: WallpaperItem? {
        library.item(id: preferences.defaultItemID) ?? library.items.first
    }

    /// Обои для монитора: персональные, иначе общие по умолчанию.
    func item(forDisplay uuid: String) -> WallpaperItem? {
        library.item(id: preferences.assignments[uuid]) ?? defaultItem
    }

    func applyToAllDisplays(_ item: WallpaperItem) {
        var prefs = preferences
        prefs.defaultItemID = item.id
        prefs.assignments.removeAll()
        preferences = prefs
    }

    func assign(_ itemID: UUID?, toDisplay uuid: String) {
        preferences.assignments[uuid] = itemID
    }

    // MARK: - Скорость

    /// Обои, которые сейчас показаны хотя бы на одном мониторе.
    var visibleItems: [WallpaperItem] {
        var seen = Set<UUID>()
        return NSScreen.screens
            .compactMap { $0.displayUUID.flatMap(item(forDisplay:)) }
            .filter { seen.insert($0.id).inserted }
    }

    /// Скорость обоев на экране (если на мониторах разные обои — у первых).
    var visibleSpeed: Double { visibleItems.first?.speed ?? 1 }

    func setSpeed(_ speed: Double, for item: WallpaperItem) {
        guard let current = library.item(id: item.id), current.speed != speed else { return }
        var updated = current
        updated.speed = speed
        library.update(updated)
    }

    func setVisibleSpeed(_ speed: Double) {
        visibleItems.forEach { setSpeed(speed, for: $0) }
    }

    func reanimate() {
        desktop.reanimate()
    }

    // MARK: - Автозапуск

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LiveWallpaper: не удалось изменить автозапуск: \(error)")
            }
        }
    }
}
