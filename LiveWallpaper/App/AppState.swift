import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let library = WallpaperLibrary()
    let pauseMonitor = PauseMonitor()
    private(set) var desktop: DesktopController!

    @Published var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            preferences.save()
            desktop?.reload()
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
        pauseMonitor.onChange = { [weak self] in self?.desktop.updatePause() }
        // Изменения в библиотеке (удаление, смена скорости) сразу применяются к обоям.
        library.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.desktop.reload() }
            .store(in: &cancellables)
    }

    func start() {
        desktop.reload()
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
