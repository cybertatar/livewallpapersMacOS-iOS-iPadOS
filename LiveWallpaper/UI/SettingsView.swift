import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var library: WallpaperLibrary

    var body: some View {
        Form {
            Section("Общие") {
                Toggle("Показывать живые обои", isOn: $state.preferences.enabled)
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.launchAtLogin = $0 }
                ))
                Toggle(isOn: $state.preferences.syncSystemWallpaper) {
                    Text("Ставить кадр из живых обоев системными обоями")
                    Text("Чтобы в Mission Control и на экране входа была та же картинка.")
                }
            }

            Section("Движение") {
                Picker("Режим", selection: $state.preferences.motionMode) {
                    ForEach(MotionMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)

                if state.preferences.motionMode == .settle {
                    LabeledContent("Полная скорость") {
                        settleSlider(value: $state.preferences.settleDelay, range: 0...5)
                    }
                    LabeledContent("Замедление до остановки") {
                        settleSlider(value: $state.preferences.settleDuration, range: 1...15)
                    }
                    HStack {
                        Button("Оживить сейчас") { state.reanimate() }
                        Spacer()
                    }
                    Text("""
                    После разблокировки или пробуждения обои оживают, затем плавно застывают. \
                    Если включено «Ставить кадр системными обоями», застывший кадр становится системными обоями, поэтому его же видно на экране блокировки, \
                    и после разблокировки движение продолжается с него. Сама анимация на экране блокировки \
                    невозможна: macOS не даёт сторонним приложениям рисовать поверх него.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Пауза анимации") {
                Toggle("При работе от батареи", isOn: $state.preferences.pauseOnBattery)
                Toggle("В режиме энергосбережения", isOn: $state.preferences.pauseOnLowPower)
                Toggle(isOn: $state.preferences.pauseWhenHidden) {
                    Text("Когда рабочий стол не виден")
                    Text("Закрыт окнами или полноэкранным приложением.")
                }
                Text("При сне дисплея и блокировке экрана анимация останавливается всегда.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Качество") {
                Picker("Частота кадров", selection: $state.preferences.frameRate) {
                    Text("24 к/с").tag(24)
                    Text("30 к/с").tag(30)
                    Text("60 к/с").tag(60)
                }
                LabeledContent("Разрешение шейдеров") {
                    HStack {
                        Slider(value: $state.preferences.shaderScale, in: 0.5...1, step: 0.25)
                            .frame(width: 180)
                        Text("\(Int(state.preferences.shaderScale * 100))%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("Частота кадров влияет только на шейдеры; видео играет со своей частотой.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Файлы") {
                Button("Открыть папку библиотеки в Finder") {
                    NSWorkspace.shared.open(library.baseDirectory)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func settleSlider(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Slider(value: value, in: range, step: 0.5)
                .frame(width: 180)
            Text(String(format: "%.1f с", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
