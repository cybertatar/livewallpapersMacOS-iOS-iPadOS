import SwiftUI

/// Настройки автоматической смены обоев.
struct AutoChangeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary

    private static let intervals: [(minutes: Int, title: String)] = [
        (0, "Не менять по таймеру"), (5, "Каждые 5 минут"), (15, "Каждые 15 минут"),
        (30, "Каждые 30 минут"), (60, "Каждый час"), (180, "Каждые 3 часа"),
        (360, "Каждые 6 часов"), (1440, "Раз в сутки"),
    ]

    private var rotation: Binding<RotationSettings> { $state.preferences.rotation }

    var body: some View {
        Form {
            Section {
                Toggle("Менять обои автоматически", isOn: rotation.enabled)
            }

            Section("Откуда брать обои") {
                Picker("Источник", selection: rotation.source) {
                    Text("Из одной подборки").tag(RotationSource.playlist)
                    Text("Своя подборка на каждое время суток").tag(RotationSource.timeOfDay)
                }
                .pickerStyle(.radioGroup)

                if state.preferences.rotation.source == .playlist {
                    playlistPicker("Подборка", selection: rotation.playlist)
                } else {
                    ForEach(DayPeriod.allCases) { period in
                        playlistPicker(period.title, selection: Binding(
                            get: { state.preferences.rotation.playlist(for: period) },
                            set: { state.preferences.rotation.periodPlaylists[period] = $0 }
                        ))
                    }
                    Text("Сейчас: \(DayPeriod.current().title). При наступлении нового времени суток обои меняются сразу.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Когда менять") {
                Picker("Таймер", selection: rotation.intervalMinutes) {
                    ForEach(Self.intervals, id: \.minutes) { Text($0.title).tag($0.minutes) }
                }
                Toggle("При каждой разблокировке экрана", isOn: rotation.changeOnUnlock)
            }

            Section("Как выбирать") {
                Picker("Порядок", selection: rotation.order) {
                    Text("Случайно").tag(RotationOrder.random)
                    Text("По порядку").tag(RotationOrder.sequential)
                }
                .pickerStyle(.segmented)
                Toggle("Разные обои на каждом мониторе", isOn: rotation.differentPerDisplay)
            }

            Section {
                HStack {
                    Button("Сменить сейчас") { state.nextWallpaper() }
                    Spacer()
                    let pool = library.items(in: state.preferences.rotation.activePlaylist())
                    Text("В текущей подборке: \(pool.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func playlistPicker(_ title: String, selection: Binding<PlaylistRef>) -> some View {
        Picker(title, selection: selection) {
            ForEach(library.allRefs, id: \.self) { ref in
                Text("\(library.title(for: ref)) (\(library.items(in: ref).count))").tag(ref)
            }
        }
    }
}
