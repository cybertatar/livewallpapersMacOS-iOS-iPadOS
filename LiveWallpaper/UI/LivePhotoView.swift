import AVFoundation
import AppKit
import SwiftUI

struct LivePhotoView: View {
    @EnvironmentObject private var library: WallpaperLibrary

    private enum Status {
        case idle
        case working(String, Double?)
        case done(LivePhotoResult, savedToPhotos: Bool)
        case failed(String)
    }

    @State private var sourceID: UUID?
    @State private var preset: DevicePreset = .iPhoneProMax
    @State private var videoDuration = 0.0
    @State private var start = 0.0
    @State private var duration = 3.0
    @State private var cropOffset = 0.5
    @State private var stillPosition = 0.5
    @State private var saveToPhotos = true
    @State private var preview: NSImage?
    @State private var status: Status = .idle

    private var source: WallpaperItem? { library.item(id: sourceID) }

    private var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            CropPreview(image: preview, aspect: preset.size.width / preset.size.height,
                        offset: source?.isVideo == true ? cropOffset : 0.5)
                .frame(width: 240)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Form {
                    Section {
                        Picker("Источник", selection: $sourceID) {
                            Text("Выберите обои").tag(UUID?.none)
                            ForEach(library.items) { item in
                                Text(item.name).tag(UUID?.some(item.id))
                            }
                        }
                        Picker("Устройство", selection: $preset) {
                            ForEach(DevicePreset.allCases) { Text($0.title).tag($0) }
                        }
                    }

                    if let source {
                        Section("Фрагмент") {
                            if source.isVideo {
                                sliderRow("Начало", value: $start, range: 0...max(videoDuration - duration, 0.01),
                                          text: String(format: "%.1f с", start))
                                sliderRow("Кадрирование", value: $cropOffset, range: 0...1,
                                          text: cropOffset < 0.34 ? "слева" : cropOffset > 0.66 ? "справа" : "центр")
                            }
                            sliderRow("Длительность", value: $duration, range: 1...3,
                                      text: String(format: "%.1f с", duration))
                            sliderRow("Обложка", value: $stillPosition, range: 0...1,
                                      text: "\(Int(stillPosition * 100))%")
                        }
                    }

                    Section {
                        Toggle("Сразу добавить в Фото (уйдёт на iPhone/iPad через iCloud)", isOn: $saveToPhotos)
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Button {
                        Task { await generate() }
                    } label: {
                        Label("Создать Live Photo", systemImage: "livephoto")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(source == nil || isWorking)

                    statusView
                    Spacer()
                }
                .padding(.horizontal)

                Text("""
                На iPhone/iPad: Настройки → Обои → «Добавить новые обои» → Фото → выберите снимок. \
                Убедитесь, что включена кнопка Live Photo внизу слева. Анимация проигрывается при пробуждении экрана.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
            }
        }
        .task(id: sourceID) { await loadSource() }
        .task(id: previewKey) { await loadPreview() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .working(let text, let progress):
            if let progress {
                ProgressView(value: progress) { Text(text).font(.caption) }
                    .frame(width: 180)
            } else {
                ProgressView().controlSize(.small)
                Text(text).font(.callout)
            }
        case .done(let result, let saved):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(saved ? "Готово, добавлено в Фото" : "Готово").font(.callout)
            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([result.imageURL, result.videoURL])
            }
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).lineLimit(3)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                           text: String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(text).monospacedDigit().frame(width: 60, alignment: .trailing)
            }
        }
    }

    // MARK: - Превью

    private struct PreviewKey: Equatable {
        var sourceID: UUID?
        var speed: Double
        var preset: DevicePreset
        var time: Double
    }

    private var previewKey: PreviewKey {
        PreviewKey(sourceID: sourceID, speed: source?.speed ?? 1, preset: preset,
                   time: ((start + duration * stillPosition) * 10).rounded() / 10)
    }

    private func loadSource() async {
        status = .idle
        preview = nil
        start = 0
        guard let source, let url = library.fileURL(for: source) else {
            videoDuration = 0
            return
        }
        videoDuration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        duration = min(3, max(1, videoDuration))
    }

    private func loadPreview() async {
        // Небольшая задержка, чтобы не дёргать декодер на каждом шаге слайдера.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled, let source else { return }
        let image: CGImage?
        switch source.source {
        case .video:
            guard let url = library.fileURL(for: source) else { return }
            image = await Snapshots.videoFrame(url: url, at: start + duration * stillPosition,
                                               maxSize: CGSize(width: 1600, height: 1600))
        case .shader(let kind):
            let size = CGSize(width: preset.size.width / 4, height: preset.size.height / 4)
            let time = Self.shaderStartTime + duration * stillPosition * source.speed
            image = await Task.detached { Snapshots.shaderFrame(kind: kind, time: time, size: size) }.value
        }
        guard !Task.isCancelled else { return }
        preview = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    // MARK: - Генерация

    /// С какого момента анимации шейдера начинать фрагмент.
    private static let shaderStartTime = 30.0

    @MainActor
    private func generate() async {
        guard let source else { return }
        let fm = FileManager.default
        var temporaryVideo: URL?
        defer { if let temporaryVideo { try? fm.removeItem(at: temporaryVideo) } }

        do {
            let sourceURL: URL
            var clipStart = start
            switch source.source {
            case .video:
                guard let url = library.fileURL(for: source) else { return }
                sourceURL = url
            case .shader(let kind):
                status = .working("Рендер анимации…", 0)
                let url = fm.temporaryDirectory.appendingPathComponent("shader-\(UUID().uuidString).mov")
                temporaryVideo = url
                try await ShaderVideoRenderer.render(
                    kind: kind, speed: source.speed, startTime: Self.shaderStartTime,
                    duration: duration, size: preset.size, to: url,
                    progress: { value in
                        Task { @MainActor in status = .working("Рендер анимации…", value) }
                    })
                sourceURL = url
                clipStart = 0
            }

            status = .working("Сборка Live Photo…", nil)
            let request = LivePhotoRequest(
                sourceURL: sourceURL, start: clipStart, duration: duration,
                outputSize: preset.size, cropOffset: cropOffset,
                stillPosition: stillPosition, name: source.name)
            let result = try await LivePhotoExporter.export(request, to: library.livePhotosDirectory)

            if saveToPhotos {
                status = .working("Сохранение в Фото…", nil)
                try await LivePhotoExporter.saveToPhotos(result)
            }
            status = .done(result, savedToPhotos: saveToPhotos)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

/// Превью в пропорциях экрана устройства с часами, как на экране блокировки.
private struct CropPreview: View {
    let image: NSImage?
    let aspect: CGFloat
    let offset: Double

    var body: some View {
        GeometryReader { geo in
            let frameHeight = min(geo.size.height, geo.size.width / aspect)
            let frameWidth = frameHeight * aspect
            ZStack(alignment: .topLeading) {
                Color.black
                if let image, image.size.width > 0, image.size.height > 0 {
                    let scale = max(frameWidth / image.size.width, frameHeight / image.size.height)
                    let width = image.size.width * scale
                    let height = image.size.height * scale
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: width, height: height)
                        .offset(x: -(width - frameWidth) * offset, y: -(height - frameHeight) / 2)
                }
                VStack(spacing: 0) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.system(size: frameWidth * 0.055, weight: .semibold))
                    Text(Date.now.formatted(.dateTime.hour().minute())).font(.system(size: frameWidth * 0.28, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 4)
                .frame(width: frameWidth)
                .padding(.top, frameHeight * 0.07)
            }
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: frameWidth * 0.12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
