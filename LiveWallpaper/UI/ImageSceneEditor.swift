import SwiftUI

/// Настройки «живой картинки». По умолчанию всё спокойно: картинка как есть и медленное приближение.
struct ImageSceneEditor: View {
    let item: WallpaperItem
    @EnvironmentObject private var library: WallpaperLibrary

    private var scene: ImageScene { item.imageScene ?? ImageScene(imageFile: "") }
    private var hasCutout: Bool { scene.cutoutFile != nil }
    private var characterLayer: Bool { hasCutout && (scene.separateCharacter || scene.backgroundScene != nil) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Picker("Кадр", selection: binding(\.fit)) {
                    ForEach(ImageFit.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(scene.backgroundScene != nil && hasCutout)
                Toggle("Медленное приближение", isOn: binding(\.kenBurns))
                Toggle("Лучи света", isOn: binding(\.lightRays))
            }
            GridRow {
                Picker("Частицы", selection: binding(\.particles)) {
                    ForEach(ParticleEffect.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Количество") {
                    Slider(value: binding(\.particleAmount), in: 0.1...1)
                }
                .disabled(scene.particles == .none)
                if scene.fit != .whole || scene.backgroundScene != nil {
                    LabeledContent("Центр кадра") {
                        Slider(value: binding(\.focusX), in: 0...1)
                    }
                    .help("По этой точке картинка кадрируется на экране и в Live Photo")
                } else {
                    Color.clear.frame(height: 1)
                }
            }

            if hasCutout {
                Divider().gridCellColumns(3)
                GridRow {
                    Toggle("Отделить персонажа от фона", isOn: binding(\.separateCharacter))
                        .help("Частицы будут пролетать за персонажем — появится глубина")
                    Picker("Свечение по контуру", selection: binding(\.aura)) {
                        Text("Нет").tag(AuraColor?.none)
                        ForEach(AuraColor.allCases) { Text($0.title).tag(AuraColor?.some($0)) }
                    }
                    .disabled(!characterLayer)
                    Picker("Фон", selection: binding(\.backgroundScene)) {
                        Text("Сама картинка").tag(ShaderKind?.none)
                        ForEach(ShaderCollection.allCases) { collection in
                            Section(collection.title) {
                                ForEach(ShaderKind.allCases.filter { $0.collection == collection }) { kind in
                                    Text(kind.title).tag(ShaderKind?.some(kind))
                                }
                            }
                        }
                    }
                    .help("Персонаж встанет поверх живой сцены. Качество зависит от того, насколько чисто он вырезан.")
                }
                if scene.backgroundScene != nil {
                    GridRow {
                        LabeledContent("Размер персонажа") {
                            Slider(value: binding(\.characterScale), in: 0.3...1.3)
                        }
                    }
                }
            } else {
                Text("Персонаж не найден на картинке — эффекты применяются ко всей картинке целиком.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .gridCellColumns(3)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ImageScene, Value>) -> Binding<Value> {
        Binding(
            get: { scene[keyPath: keyPath] },
            set: { newValue in
                guard let current = library.item(id: item.id), var updated = current.imageScene else { return }
                updated[keyPath: keyPath] = newValue
                var newItem = current
                newItem.source = .image(updated)
                library.update(newItem)
            }
        )
    }
}
