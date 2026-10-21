import SwiftUI

/// Настройки «живой картинки»: фон, частицы, свечение, движение.
struct ImageSceneEditor: View {
    let item: WallpaperItem
    @EnvironmentObject private var library: WallpaperLibrary

    private var scene: ImageScene { item.imageScene ?? ImageScene(imageFile: "") }
    private var hasCutout: Bool { scene.cutoutFile != nil }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
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
                .disabled(!hasCutout)
                .help(hasCutout ? "Персонаж встанет поверх живой сцены" : "Нужен вырезанный персонаж")

                Picker("Частицы", selection: binding(\.particles)) {
                    ForEach(ParticleEffect.allCases) { Text($0.title).tag($0) }
                }

                Picker("Свечение", selection: binding(\.aura)) {
                    Text("Без свечения").tag(AuraColor?.none)
                    ForEach(AuraColor.allCases) { Text($0.title).tag(AuraColor?.some($0)) }
                }
                .disabled(!hasCutout)
            }
            GridRow {
                Toggle("Плавное движение камеры", isOn: binding(\.kenBurns))
                    .disabled(scene.backgroundScene != nil)
                Toggle("Персонаж «дышит»", isOn: binding(\.floating))
                    .disabled(!hasCutout)
                Toggle("Лучи света", isOn: binding(\.lightRays))
            }
            GridRow {
                LabeledContent("Центр персонажа") {
                    Slider(value: binding(\.focusX), in: 0...1)
                }
                .help("По этой точке картинка кадрируется на экране и в Live Photo")
                if scene.backgroundScene != nil {
                    LabeledContent("Размер персонажа") {
                        Slider(value: binding(\.characterScale), in: 0.3...1.3)
                    }
                }
            }
            if !hasCutout {
                Text("Персонажа вырезать не удалось — эффекты применяются ко всей картинке. Можно добавить PNG с прозрачным фоном.")
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
