import AppKit

/// Автоматическая смена обоев: по таймеру, по времени суток и при разблокировке.
@MainActor
final class RotationController: NSObject {
    private unowned let state: AppState
    private var timer: Timer?
    private var lastChange = Date()
    private var lastPeriod: DayPeriod?
    /// Позиция для последовательного режима, отдельно для каждой подборки.
    private var sequenceIndex: [PlaylistRef: Int] = [:]

    init(state: AppState) {
        self.state = state
        super.init()
        let timer = Timer(timeInterval: 20, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var settings: RotationSettings { state.preferences.rotation }

    /// Настройки поменялись: начинаем отсчёт заново, а время суток проверяем сразу.
    func settingsChanged() {
        lastChange = Date()
        lastPeriod = nil
        // Вызывается из didSet настроек — саму смену делаем на следующем шаге run loop.
        perform(#selector(tick), with: nil, afterDelay: 0)
    }

    func handleUnlock() {
        guard settings.enabled, settings.changeOnUnlock else { return }
        advance()
    }

    @objc private func tick() {
        guard settings.enabled, state.preferences.enabled else { return }
        let now = Date()
        if settings.source == .timeOfDay {
            let period = DayPeriod.current(at: now)
            if period != lastPeriod {
                let changed = lastPeriod != nil
                lastPeriod = period
                // При первом запуске меняем, только если текущие обои не из подборки этого времени суток.
                let pool = state.library.items(in: settings.playlist(for: period))
                let visibleInPool = state.visibleItems.allSatisfy { item in pool.contains { $0.id == item.id } }
                if changed || !visibleInPool {
                    advance()
                    return
                }
            }
        }
        if settings.intervalMinutes > 0,
           now.timeIntervalSince(lastChange) >= Double(settings.intervalMinutes) * 60 {
            advance()
        }
    }

    /// Ставит следующие обои из активной подборки (или из всей библиотеки, если автосмена выключена).
    func advance() {
        lastChange = Date()
        let ref = settings.enabled ? settings.activePlaylist() : .all
        let pool = state.library.items(in: ref)
        guard !pool.isEmpty else { return }

        let displays = NSScreen.screens.compactMap(\.displayUUID)
        let count = settings.differentPerDisplay ? max(displays.count, 1) : 1
        let picked = pick(count: count, from: pool, ref: ref)
        guard let first = picked.first else { return }

        var prefs = state.preferences
        prefs.defaultItemID = first.id
        prefs.assignments.removeAll()
        if settings.differentPerDisplay {
            for (index, uuid) in displays.enumerated() {
                prefs.assignments[uuid] = picked[index % picked.count].id
            }
        }
        state.preferences = prefs
    }

    private func pick(count: Int, from pool: [WallpaperItem], ref: PlaylistRef) -> [WallpaperItem] {
        switch settings.order {
        case .random:
            // Стараемся не повторять то, что уже на экране.
            let visible = Set(state.visibleItems.map(\.id))
            var candidates = pool.filter { !visible.contains($0.id) }.shuffled()
            if candidates.count < count {
                candidates += pool.filter { visible.contains($0.id) }.shuffled()
            }
            return Array(candidates.prefix(count))
        case .sequential:
            var index = sequenceIndex[ref] ?? {
                let current = state.visibleItems.first?.id
                return pool.firstIndex { $0.id == current }.map { $0 + 1 } ?? 0
            }()
            var result: [WallpaperItem] = []
            for _ in 0..<min(count, pool.count) {
                result.append(pool[index % pool.count])
                index += 1
            }
            sequenceIndex[ref] = index % pool.count
            return result
        }
    }
}
