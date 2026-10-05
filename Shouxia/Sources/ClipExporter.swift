import Foundation
import AVFoundation

struct ClipRange {
    let start: Double
    let end: Double
    var length: Double { end - start }
    init(start: Double, end: Double, duration: Double) throws {
        guard start.isFinite, end.isFinite, duration.isFinite, start >= 0, end > start, end <= duration else {
            throw AppError.message("开始时间必须早于结束时间，且不能超出视频时长。")
        }
        self.start = start; self.end = end
    }
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var result = 0.0
        for (index, part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value = Double(part), value.isFinite, value >= 0,
                  (index == 0 || value < 60), (index == parts.count - 1 || value.rounded() == value) else { return nil }
            result = result * 60 + value
        }
        return result.isFinite ? result : nil
    }
    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 1e10 else { return "00:00:00.000" }
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }
}

@MainActor final class ClipExporter {
    private static var busy = false
    private var session: AVAssetExportSession?
    private var cancelled = false
    var progress: Double { Double(session?.progress ?? 0) }
    func cancel() { cancelled = true; session?.cancelExport() }
    func export(source: URL, target: URL, range: ClipRange, speed: Double = 1) async throws {
        guard speed.isFinite, (0.25...2).contains(speed) else { throw AppError.message("导出倍速必须在 0.25 到 2 之间。") }
        guard !Self.busy else { throw AppError.message("已有片段正在导出，请等待完成。") }
        Self.busy = true; cancelled = false
        defer { session = nil; Self.busy = false }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path), source.standardizedFileURL != target.standardizedFileURL else {
            throw AppError.message("该文件已存在，请换一个文件名，原视频不会被覆盖。")
        }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        _ = try ClipRange(start: range.start, end: range.end, duration: duration)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else { throw AppError.message("此文件没有可导出的视频轨道。") }
        guard !cancelled else { throw CancellationError() }
        let selectedRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60000), duration: CMTime(seconds: range.length, preferredTimescale: 60000))
        let composition = AVMutableComposition()
        try await composition.insertTimeRange(selectedRange, of: asset, at: .zero)
        let sourceTracks = try await asset.loadTracks(withMediaType: .video)
        let outputTracks = composition.tracks(withMediaType: .video)
        for (sourceTrack, outputTrack) in zip(sourceTracks, outputTracks) {
            outputTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
        }
        let outputDuration = CMTime(seconds: range.length / speed, preferredTimescale: 60000)
        composition.scaleTimeRange(CMTimeRange(start: .zero, duration: selectedRange.duration), toDuration: outputDuration)
        guard !cancelled else { throw CancellationError() }
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality), export.supportedFileTypes.contains(.mp4) else {
            throw AppError.message("此视频暂不支持导出为 MP4，请选择其他视频。")
        }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".video-extractor-clip-\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: temporary) }
        session = export
        export.outputURL = temporary; export.outputFileType = .mp4
        export.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
        export.audioTimePitchAlgorithm = .timeDomain
        if #available(macOS 15.0, *) {
            do { try await export.export(to: temporary, as: .mp4) }
            catch { if cancelled { throw CancellationError() }; throw error }
        } else {
            try await exportLegacy(export)
        }
        guard !cancelled else { throw CancellationError() }
        try fm.moveItem(at: temporary, to: target)
    }
    @available(macOS, introduced: 10.15, deprecated: 15.0)
    private func exportLegacy(_ export: AVAssetExportSession) async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard !cancelled, export.status != .cancelled else { throw CancellationError() }
        guard export.status == .completed else { throw export.error ?? AppError.message("导出未完成，请检查视频格式和剩余磁盘空间。") }
    }
}
