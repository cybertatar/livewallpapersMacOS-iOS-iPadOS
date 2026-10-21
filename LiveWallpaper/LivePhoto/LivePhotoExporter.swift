import AVFoundation
import CoreMedia
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Размеры экранов, под которые режется Live Photo.
enum DevicePreset: String, CaseIterable, Identifiable {
    case iPhoneProMax = "iphone-69"
    case iPhonePro = "iphone-63"
    case iPadPro13 = "ipad-13"
    case iPadPro11 = "ipad-11"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iPhoneProMax: return "iPhone 6,9″ (Pro Max)"
        case .iPhonePro: return "iPhone 6,3″ (Pro)"
        case .iPadPro13: return "iPad Pro 13″"
        case .iPadPro11: return "iPad Pro 11″"
        }
    }

    /// Портретное разрешение в пикселях.
    var size: CGSize {
        switch self {
        case .iPhoneProMax: return CGSize(width: 1320, height: 2868)
        case .iPhonePro: return CGSize(width: 1206, height: 2622)
        case .iPadPro13: return CGSize(width: 2064, height: 2752)
        case .iPadPro11: return CGSize(width: 1668, height: 2420)
        }
    }
}

struct LivePhotoRequest {
    var sourceURL: URL
    /// Начало фрагмента в исходном видео, секунды.
    var start: Double
    /// Длина фрагмента, секунды (для обоев лучше не больше 3).
    var duration: Double
    var outputSize: CGSize
    /// Горизонтальное смещение кадрирования: 0 — левый край, 1 — правый.
    var cropOffset: Double = 0.5
    /// Позиция статичного кадра внутри фрагмента: 0…1.
    var stillPosition: Double = 0.5
    var name: String
}

struct LivePhotoResult {
    let imageURL: URL
    let videoURL: URL
}

enum LivePhotoError: LocalizedError {
    case noVideoTrack
    case exportFailed(String)
    case writeFailed(String)
    case photosAccessDenied

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "В файле нет видеодорожки."
        case .exportFailed(let reason): return "Не удалось обрезать видео: \(reason)"
        case .writeFailed(let reason): return "Не удалось записать Live Photo: \(reason)"
        case .photosAccessDenied:
            return "Нет доступа к Фото. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Фото."
        }
    }
}

/// Собирает Live Photo из видео: JPEG + MOV, связанные общим идентификатором
/// (MakerApple «17» в картинке и com.apple.quicktime.content.identifier в видео).
enum LivePhotoExporter {
    static func export(_ request: LivePhotoRequest, to directory: URL) async throws -> LivePhotoResult {
        let identifier = UUID().uuidString
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("livephoto-\(identifier)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let croppedURL = workDir.appendingPathComponent("cropped.mov")
        try await cropAndTrim(request, to: croppedURL)

        let croppedAsset = AVURLAsset(url: croppedURL)
        let clipDuration = try await croppedAsset.load(.duration)
        let stillTime = CMTimeMultiplyByFloat64(clipDuration, multiplier: min(max(request.stillPosition, 0), 0.98))

        let baseName = sanitized(request.name) + "-" + String(identifier.prefix(8))
        let imageURL = directory.appendingPathComponent(baseName + ".jpg")
        let videoURL = directory.appendingPathComponent(baseName + ".mov")

        try await writeStillImage(from: croppedAsset, at: stillTime, identifier: identifier, to: imageURL)
        try await writePairedVideo(from: croppedAsset, identifier: identifier, stillTime: stillTime, to: videoURL)
        return LivePhotoResult(imageURL: imageURL, videoURL: videoURL)
    }

    static func saveToPhotos(_ result: LivePhotoResult) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else { throw LivePhotoError.photosAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: result.imageURL, options: nil)
            request.addResource(with: .pairedVideo, fileURL: result.videoURL, options: nil)
        }
    }

    // MARK: - Шаг 1: обрезка по времени и кадрирование под экран

    private static func cropAndTrim(_ request: LivePhotoRequest, to output: URL) async throws {
        let asset = AVURLAsset(url: request.sourceURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoError.noVideoTrack
        }
        let (naturalSize, transform, frameRate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let assetDuration = try await asset.load(.duration)

        // Размер кадра с учётом поворота.
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let sourceWidth = abs(oriented.width)
        let sourceHeight = abs(oriented.height)
        let outWidth = request.outputSize.width
        let outHeight = request.outputSize.height

        let scale = max(outWidth / sourceWidth, outHeight / sourceHeight)
        let overflowX = sourceWidth * scale - outWidth
        let overflowY = sourceHeight * scale - outHeight
        let cropOffset = min(max(request.cropOffset, 0), 1)

        let layerTransform = transform
            .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: -overflowX * cropOffset, y: -overflowY * 0.5))

        let fps = frameRate > 0 ? min(Int32(frameRate.rounded()), 60) : 30
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: outWidth, height: outHeight)
        composition.frameDuration = CMTime(value: 1, timescale: fps)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(layerTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        let start = min(max(request.start, 0), max(assetDuration.seconds - 0.1, 0))
        let length = min(request.duration, assetDuration.seconds - start)
        let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                    duration: CMTime(seconds: length, preferredTimescale: 600))

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw LivePhotoError.exportFailed("экспорт HEVC недоступен")
        }
        session.videoComposition = composition
        session.timeRange = timeRange
        do {
            try await session.export(to: output, as: .mov)
        } catch {
            throw LivePhotoError.exportFailed(error.localizedDescription)
        }
    }

    // MARK: - Шаг 2: статичная картинка

    private static func writeStillImage(from asset: AVAsset, at time: CMTime,
                                        identifier: String, to url: URL) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: time).image

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LivePhotoError.writeFailed("не удалось создать JPEG")
        }
        let properties: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: ["17": identifier],
            kCGImageDestinationLossyCompressionQuality as String: 0.95,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw LivePhotoError.writeFailed("не удалось сохранить JPEG")
        }
    }

    // MARK: - Шаг 3: видео с метаданными Live Photo

    private static func writePairedVideo(from asset: AVAsset, identifier: String,
                                         stillTime: CMTime, to url: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LivePhotoError.noVideoTrack
        }
        let (formatDescriptions, transform) = try await track.load(.formatDescriptions, .preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [contentIdentifierItem(identifier)]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                            sourceFormatHint: formatDescriptions.first)
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        let metadataInput = try stillImageTimeInput()
        let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        writer.add(metadataInput)

        guard writer.startWriting() else {
            throw LivePhotoError.writeFailed(writer.error?.localizedDescription ?? "writer")
        }
        guard reader.startReading() else {
            throw LivePhotoError.writeFailed(reader.error?.localizedDescription ?? "reader")
        }
        writer.startSession(atSourceTime: .zero)

        _ = metadataAdaptor.append(AVTimedMetadataGroup(
            items: [stillImageTimeItem()],
            timeRange: CMTimeRange(start: stillTime, duration: CMTime(value: 1, timescale: 100))))
        metadataInput.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let queue = DispatchQueue(label: "LivePhotoExporter.copy")
            var finished = false
            videoInput.requestMediaDataWhenReady(on: queue) {
                guard !finished else { return }
                while videoInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        if !videoInput.append(sample) {
                            reader.cancelReading()
                            break
                        }
                    } else {
                        break
                    }
                }
                if reader.status != .reading || writer.status != .writing {
                    finished = true
                    videoInput.markAsFinished()
                    continuation.resume()
                }
            }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw LivePhotoError.writeFailed(reader.error?.localizedDescription ?? "reader")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw LivePhotoError.writeFailed(writer.error?.localizedDescription ?? "writer")
        }
    }

    private static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = "com.apple.quicktime.content.identifier" as NSString
        item.value = identifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    private static func stillImageTimeItem() -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = "com.apple.quicktime.still-image-time" as NSString
        item.value = 0 as NSNumber
        item.dataType = kCMMetadataBaseDataType_SInt8 as String
        return item
    }

    private static func stillImageTimeInput() throws -> AVAssetWriterInput {
        let spec: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
                "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
                kCMMetadataBaseDataType_SInt8 as String,
        ]
        var description: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [spec] as CFArray,
            formatDescriptionOut: &description)
        guard status == noErr, let description else {
            throw LivePhotoError.writeFailed("метаданные still-image-time (\(status))")
        }
        return AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
    }

    private static func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.unicodeScalars.filter { allowed.contains($0) })
        return cleaned.isEmpty ? "LivePhoto" : cleaned
    }
}
