import AVFoundation
import CoreMedia
import Foundation

enum ConversionError: LocalizedError {
    case invalidArguments
    case invalidTargetEdge(String)
    case missingInput(URL)
    case noVideoTrack
    case sourceHasNoAlpha
    case unsupportedPreset
    case unsupportedOutputType
    case exportFailed(String)
    case outputHasNoAlpha

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "用法：alpha-video-converter <input.mov> <output.mov> <target-edge>"
        case .invalidTargetEdge(let value):
            return "输出边长无效：\(value)"
        case .missingInput(let url):
            return "找不到输入文件：\(url.path)"
        case .noVideoTrack:
            return "输入文件中没有视频轨道。"
        case .sourceHasNoAlpha:
            return "输入视频没有 Alpha 透明通道，已停止以避免输出错误素材。"
        case .unsupportedPreset:
            return "当前 macOS 运行器不支持 HEVC with Alpha 导出预设。"
        case .unsupportedOutputType:
            return "当前导出会话不支持 MOV 输出。"
        case .exportFailed(let reason):
            return "导出失败：\(reason)"
        case .outputHasNoAlpha:
            return "输出视频没有 Alpha 透明通道，已拒绝发布。"
        }
    }
}

@main
struct AlphaVideoConverter {
    // QuickTime Animation / qtrle uses the FourCC "rle ". Some FFmpeg-authored
    // ARGB files carry real alpha pixels but omit AVFoundation's track-level
    // containsAlphaChannel characteristic.
    private static let quickTimeAnimationCodec: CMVideoCodecType = 0x726C6520

    static func main() async {
        do {
            try await convert()
        } catch {
            FileHandle.standardError.write(Data("错误：\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func convert() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            throw ConversionError.invalidArguments
        }

        let inputURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        guard let targetEdge = Int(arguments[3]), (256...2048).contains(targetEdge) else {
            throw ConversionError.invalidTargetEdge(arguments[3])
        }
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw ConversionError.missingInput(inputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw ConversionError.noVideoTrack
        }
        guard try await trackContainsAlpha(
            videoTrack,
            acceptedLegacyCodecs: [quickTimeAnimationCodec]
        ) else {
            throw ConversionError.sourceHasNoAlpha
        }

        let preset = AVAssetExportPresetHEVCHighestQualityWithAlpha
        let isCompatible = await AVAssetExportSession.compatibility(
            ofExportPreset: preset,
            with: asset,
            outputFileType: .mov
        )
        guard isCompatible else {
            throw ConversionError.unsupportedPreset
        }
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.unsupportedPreset
        }
        guard exportSession.supportedFileTypes.contains(.mov) else {
            throw ConversionError.unsupportedOutputType
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        let scale = min(
            CGFloat(targetEdge) / orientedSize.width,
            CGFloat(targetEdge) / orientedSize.height
        )
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let offset = CGPoint(
            x: (CGFloat(targetEdge) - scaledSize.width) / 2,
            y: (CGFloat(targetEdge) - scaledSize.height) / 2
        )

        var transform = preferredTransform
        transform = transform.concatenating(CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: offset.x, y: offset.y))

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetEdge, height: targetEdge)
        let safeFrameRate = frameRate > 0 ? frameRate : 24
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(safeFrameRate.rounded()))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        exportSession.videoComposition = composition
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportSession.export(to: outputURL, as: .mov)
        } catch {
            throw ConversionError.exportFailed(error.localizedDescription)
        }

        let outputAsset = AVURLAsset(url: outputURL)
        guard let outputTrack = try await outputAsset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.outputHasNoAlpha
        }
        guard try await trackContainsAlpha(outputTrack) else {
            throw ConversionError.outputHasNoAlpha
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteCount = attributes[.size] as? Int64 ?? 0
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        print("转换完成：\(outputURL.lastPathComponent)")
        print("输出尺寸：\(targetEdge) × \(targetEdge)")
        print("输出大小：\(formatter.string(fromByteCount: byteCount))")
        print("透明通道：已验证")
    }

    private static func trackContainsAlpha(
        _ track: AVAssetTrack,
        acceptedLegacyCodecs: Set<CMVideoCodecType> = []
    ) async throws -> Bool {
        let characteristics = try await track.load(.mediaCharacteristics)
        if characteristics.contains(.containsAlphaChannel) {
            return true
        }

        let descriptions = try await track.load(.formatDescriptions)
        for description in descriptions {
            if let containsAlpha = CMFormatDescriptionGetExtension(
                description,
                extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel
            ) as? Bool, containsAlpha {
                return true
            }

            let codec = CMFormatDescriptionGetMediaSubType(description)
            if acceptedLegacyCodecs.contains(codec) {
                print("提示：输入使用带 ARGB 的 QuickTime Animation/qtrle，按透明母版处理。")
                return true
            }
        }

        return false
    }
}
