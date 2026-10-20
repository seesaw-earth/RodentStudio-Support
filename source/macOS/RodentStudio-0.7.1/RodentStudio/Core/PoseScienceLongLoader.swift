import Foundation
import AVFoundation

/// Reads RodentPose frames from immutable 2-minute CSV segments (runs too long to keep in memory).
/// Independent of Core ML inference. The report window is bounded to protect memory.
enum PoseScienceLongLoader {
    enum LoadError: LocalizedError {
        case wrongModel, empty, tooLong, noVideo
        var errorDescription: String? {
            switch self {
            case .wrongModel: return L("This report needs the RodentPose six-keypoint model.", "该报告需要 RodentPose 六关键点模型。")
            case .empty: return L("No completed tracked frames in the analysis window.", "分析时间段内没有已完成的追踪帧。")
            case .tooLong: return L("The analysis window has more than 216,000 frames. Set a shorter analysis window in Calibrate; the original CSVs remain intact.",
                                    "分析时间段超过 216,000 帧。请在“校准”中设置更短的分析时间段；原始 CSV 不变。")
            case .noVideo: return L("The source video cannot be opened (its frame size is needed).", "无法打开原始视频（需要其画面尺寸）。")
            }
        }
    }

    /// Frames whose time (relative to the first tracked frame) lies in `timeRange`; nil reads every frame.
    static func make(manifest: LongVideoManifest, folder: URL, videoURL: URL?,
                     timeRange: ClosedRange<Double>?) throws -> NativeTrackingResult {
        try make(manifest: manifest, folder: folder, videoURL: videoURL) { _, t in
            timeRange.map { $0.contains(t) } ?? true
        }
    }

    /// Frames with a zero-based index in `range` (Advanced tools).
    static func make(manifest: LongVideoManifest, folder: URL, videoURL: URL?,
                     selected range: ClosedRange<Int>) throws -> NativeTrackingResult {
        guard range.upperBound - range.lowerBound + 1 <= PoseScienceBridge.maxFrames else { throw LoadError.tooLong }
        return try make(manifest: manifest, folder: folder, videoURL: videoURL) { index, _ in range.contains(index) }
    }

    private static func make(manifest: LongVideoManifest, folder: URL, videoURL: URL?,
                             include: (Int, Double) -> Bool) throws -> NativeTrackingResult {
        guard manifest.modelName == PoseModelKind.mousePose.rawValue else { throw LoadError.wrongModel }
        var list: [NativeTrackedFrame] = []
        let sorted = manifest.completed.sorted { $0.index < $1.index }
        let origin = sorted.first?.firstPTS ?? 0
        var offset = 0
        for segment in sorted {
            defer { offset += segment.records }
            let text = try String(contentsOf: folder.appendingPathComponent(segment.file), encoding: .utf8)
            for (local, line) in text.split(whereSeparator: \.isNewline).dropFirst().enumerated() {
                let index = offset + local
                let c = line.split(separator: ",", omittingEmptySubsequences: false)
                guard c.count >= 23, let pts = Double(c[1]) else { continue }
                let t = pts - origin
                guard include(index, t) else { continue }
                if list.count >= PoseScienceBridge.maxFrames { throw LoadError.tooLong }
                var points: [NativeTrackPoint] = []
                points.reserveCapacity(6)
                for k in 0..<6 {
                    let i = 4 + k * 3
                    points.append(NativeTrackPoint(x: Double(c[i]) ?? -1, y: Double(c[i + 1]) ?? -1,
                                                   confidence: Double(c[i + 2]) ?? 0))
                }
                list.append(NativeTrackedFrame(index: index, time: t, score: Double(c[3]) ?? 0,
                                               points: points, inferenceFailed: c[22] == "1"))
            }
        }
        guard !list.isEmpty else { throw LoadError.empty }
        var w = 0, h = 0, fps = 30.0
        if let url = videoURL, let track = AVURLAsset(url: url).tracks(withMediaType: .video).first {
            let rect = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
            w = Int(abs(rect.width).rounded()); h = Int(abs(rect.height).rounded())
            fps = max(1, Double(track.nominalFrameRate))
        }
        guard w > 0, h > 0 else { throw LoadError.noVideo }
        return NativeTrackingResult(model: .mousePose, videoFile: manifest.sourceFile,
                                    videoWidth: w, videoHeight: h, fps: fps, timeOffset: origin,
                                    frames: list, elapsedSeconds: 0)
    }
}
