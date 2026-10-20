import Foundation
import AVFoundation
import Vision
import CoreML
import CoreGraphics
import CryptoKit
import AppKit
import CoreImage

/// Streaming raw-pose extraction. Does not calculate experimental endpoints.
/// Each finished CSV segment is immutable; only verified completed segments are resumed.
/// Uses O(frame-size + model working set + bounded write buffer) RAM rather than
/// holding the entire raw trajectory in NativeTrackingResult.frames.
struct LongVideoManifest: Codable {
    struct Segment: Codable {
        let index: Int
        let file: String
        let records: Int
        let firstPTS: Double
        let lastPTS: Double
        let failedFrames: Int // inference error, not an ordinary no-detection frame
    }
    let formatVersion: Int
    let sourceFile: String
    let sourceSize: UInt64
    let sourceModification: Double
    let sourceFingerprint: String
    let modelName: String
    let chunkDuration: Double
    let videoDuration: Double
    var completed: [Segment]
}

struct NativeLivePreview {
    let image: NSImage
    let points: [NativeTrackPoint]
    let model: PoseModelKind
    let frameWidth: Int
    let frameHeight: Int
    let presentationTime: Double
}

struct LongVideoProgress {
    let completedSegments: Int
    let totalSegments: Int
    let currentSegment: Int
    let processedInSegment: Int
    var sourceTime: Double? = nil
    var sourceDuration: Double? = nil
    var livePreview: NativeLivePreview? = nil
}

/// Sample one downscaled frame occasionally; do not accumulate a video in memory.
private enum LiveSnapshot {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func make(_ pixel: CVPixelBuffer, transform: CGAffineTransform,
                     pts: Double, points: [NativeTrackPoint], model: PoseModelKind) -> NativeLivePreview? {
        let rawW = CVPixelBufferGetWidth(pixel), rawH = CVPixelBufferGetHeight(pixel)
        let rawRect = CGRect(x: 0, y: 0, width: CGFloat(rawW), height: CGFloat(rawH))
        let displayRect = rawRect.applying(transform)
        let w = abs(displayRect.width), h = abs(displayRect.height)
        guard w > 0, h > 0 else { return nil }
        // Same orientation correction and origin shift as the tracked keypoints.
        var corrected = CIImage(cvPixelBuffer: pixel).transformed(by: transform)
        corrected = corrected.transformed(by: CGAffineTransform(translationX: -displayRect.minX, y: -displayRect.minY))
        let ratio = min(1, 640 / max(w, h))
        let displayed = corrected.transformed(by: CGAffineTransform(scaleX: ratio, y: ratio))
        let bounds = CGRect(x: 0, y: 0, width: w * ratio, height: h * ratio)
        guard let cg = context.createCGImage(displayed, from: bounds) else { return nil }
        return NativeLivePreview(image:NSImage(cgImage:cg,size:NSSize(width:CGFloat(cg.width),height:CGFloat(cg.height))),
                                 points:points,model:model,frameWidth:Int(w.rounded()),frameHeight:Int(h.rounded()),presentationTime:pts)
    }
}


enum LongVideoTrackingEngine {
    static let formatVersion = 2
    static let manifestName = "long_video_manifest.json"
    static let headerFields = ["frame_in_segment", "presentation_time_s", "detected", "box_conf"]

    /// Fast change detector, not a whole-file scientific SHA-256. Includes size/mtime and
    /// the first/last MiB. A full-file hash is recommended for publication provenance.
    private static func fingerprint(_ url: URL, size: UInt64, modification: Double) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        digest.update(data: Data("\(size):\(modification)".utf8))
        let n = min(size, 1_048_576)
        digest.update(data: try file.read(upToCount: Int(n)) ?? Data())
        if size > n {
            try file.seek(toOffset: size - n)
            digest.update(data: try file.read(upToCount: Int(n)) ?? Data())
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func names(for kind: PoseModelKind) -> [String] {
        if kind == .mousePose {
            return ["nose", "left_ear", "right_ear", "neck", "body_center", "tail_base"]
        }
        return Kp.allCases.map(\.exportName)
    }
    private static func header(kind: PoseModelKind) -> String {
        (headerFields + names(for: kind).flatMap { ["\($0)_x", "\($0)_y", "\($0)_conf"] } + ["inference_failed"])
            .joined(separator: ",") + "\n"
    }
    private static func csvRow(frame: Int, pts: Double, score: Double, points: [NativeTrackPoint], inferenceFailed: Bool = false) -> String {
        var s = "\(frame)," + String(format: "%.9f", pts) + ",\(score > 0 ? 1 : 0)," + String(format: "%.7g", score)
        for p in points {
            if p.x.isFinite && p.y.isFinite && p.x >= 0 && p.y >= 0 {
                s += String(format: ",%.5f,%.5f,%.7g", p.x, p.y, p.confidence)
            } else { s += ",,,0" }
        }
        return s + (inferenceFailed ? ",1\n" : ",0\n")
    }
    private static func saveManifest(_ m: LongVideoManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(m).write(to: url, options: .atomic)
    }

    /// User must choose the video and destination via OS panels for sandbox access.
    /// On cancellation completed segments remain committed and can be resumed.
    static func run(videoURL: URL, destination: URL, kind: PoseModelKind,
                    segmentSeconds: Double = 120,
                    cancellation: NativeTrackingCancellation,
                    progress: @escaping (LongVideoProgress) -> Void) throws -> LongVideoManifest {
        guard segmentSeconds >= 10, segmentSeconds <= 1800 else {
            throw NativeTrackingError.invalidVideo("Segment duration must be between 10 and 1800 seconds")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        let sourceSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let sourceModification = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let sourceFingerprint = try fingerprint(videoURL, size: sourceSize, modification: sourceModification)
        let asset = AVURLAsset(url: videoURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw NativeTrackingError.invalidVideo("No video track")
        }
        let duration = CMTimeGetSeconds(asset.duration)
        guard duration.isFinite, duration > 0 else {
            throw NativeTrackingError.invalidVideo("Cannot resolve video duration")
        }
        let segmentCount = Int(ceil(duration / segmentSeconds))
        guard segmentCount > 0, segmentCount < 5_000_000 else {
            throw NativeTrackingError.invalidVideo("Invalid segment count")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifestURL = destination.appendingPathComponent(manifestName)
        var manifest: LongVideoManifest
        if manager.fileExists(atPath: manifestURL.path) {
            manifest = try JSONDecoder().decode(LongVideoManifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.formatVersion == formatVersion,
                  manifest.sourceFile == videoURL.lastPathComponent,
                  manifest.sourceSize == sourceSize,
                  manifest.sourceModification == sourceModification,
                  manifest.sourceFingerprint == sourceFingerprint,
                  manifest.modelName == kind.rawValue,
                  manifest.chunkDuration == segmentSeconds,
                  abs(manifest.videoDuration - duration) < 0.001 else {
                throw NativeTrackingError.invalidVideo("Existing result folder belongs to a different video/model/settings. Choose an empty destination.")
            }
        } else {
            guard (try manager.contentsOfDirectory(atPath: destination.path)).isEmpty else {
                throw NativeTrackingError.invalidVideo("Choose an empty result folder, or an existing folder with a matching manifest.")
            }
            manifest = LongVideoManifest(formatVersion: formatVersion,
                                         sourceFile: videoURL.lastPathComponent,
                                         sourceSize: sourceSize,
                                         sourceModification: sourceModification,
                                         sourceFingerprint: sourceFingerprint,
                                         modelName: kind.rawValue,
                                         chunkDuration: segmentSeconds,
                                         videoDuration: duration, completed: [])
            try saveManifest(manifest, to: manifestURL)
        }

        // Model and Vision request are reused between chunks and only one frame is in-flight.
        let ml = try NativeModelCatalog.load(kind)
        let predictor = try NativeResilientVisionPredictor(model: ml)
        let transform = track.preferredTransform
        let completed = Dictionary(uniqueKeysWithValues: manifest.completed.map { ($0.index, $0) })
        for segmentIndex in 0..<segmentCount {
            if cancellation.isCancelled { throw NativeTrackingError.cancelled }
            let csvName = String(format: "segment_%06d.csv", segmentIndex)
            let finalURL = destination.appendingPathComponent(csvName)
            if completed[segmentIndex] != nil && manager.fileExists(atPath: finalURL.path) {
                progress(LongVideoProgress(completedSegments: manifest.completed.count, totalSegments: segmentCount,
                                           currentSegment: segmentIndex, processedInSegment: completed[segmentIndex]?.records ?? 0))
                continue
            }
            let temporaryURL = destination.appendingPathComponent(csvName + ".partial")
            if manager.fileExists(atPath: temporaryURL.path) { try manager.removeItem(at: temporaryURL) }
            manager.createFile(atPath: temporaryURL.path, contents: Data(header(kind: kind).utf8))
            let handle = try FileHandle(forWritingTo: temporaryURL)
            defer { try? handle.close() }
            try handle.seekToEnd()

            let begin = Double(segmentIndex) * segmentSeconds
            let end = min(duration, begin + segmentSeconds)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            reader.timeRange = CMTimeRange(start: CMTime(seconds: begin, preferredTimescale: 60000),
                                           duration: CMTime(seconds: end - begin, preferredTimescale: 60000))
            guard reader.startReading() else {
                throw NativeTrackingError.invalidVideo(reader.error?.localizedDescription ?? "Cannot start segment reader")
            }
            var count = 0
            var failedFrames = 0
            var consecutiveInferenceFailures = 0
            var lastLiveSample = -Double.infinity
            var firstPTS = Double.nan
            var lastPTS = Double.nan
            var buffered = Data()
            buffered.reserveCapacity(32_768)
            while let sample = output.copyNextSampleBuffer() {
                if cancellation.isCancelled {
                    reader.cancelReading()
                    throw NativeTrackingError.cancelled
                }
                let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
                // Half-open ranges avoid duplicate timestamps at segment boundaries.
                guard pts.isFinite, pts >= begin - 0.000001, pts < end - 0.000001 else { continue }
                guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                // The entire Vision + decoder operation is inside the per-frame
                // pool so long videos cannot accumulate temporary predictions.
                let samplePreview = ProcessInfo.processInfo.systemUptime - lastLiveSample >= 1.0
                var sampledPoints: [NativeTrackPoint]? = nil
                let line: String = try autoreleasepool {
                    do {
                        let tensor = try predictor.infer(imageBuffer)
                        let rawW = CVPixelBufferGetWidth(imageBuffer)
                        let rawH = CVPixelBufferGetHeight(imageBuffer)
                        let d = try NativePoseDecoder.decode(tensor, kind: kind, imageWidth: rawW, imageHeight: rawH)
                        let rect = CGRect(x: 0, y: 0, width: CGFloat(rawW), height: CGFloat(rawH)).applying(transform)
                        let p = d.points.map { point -> NativeTrackPoint in
                            guard point.x >= 0, point.y >= 0 else { return .missing }
                            let r = CGPoint(x: point.x, y: point.y).applying(transform)
                            return NativeTrackPoint(x: Double(r.x - rect.minX), y: Double(r.y - rect.minY), confidence: point.confidence)
                        }
                        consecutiveInferenceFailures = 0
                        if samplePreview { sampledPoints = p }
                        return csvRow(frame: count, pts: pts, score: d.score, points: p)
                    } catch {
                        failedFrames += 1
                        consecutiveInferenceFailures += 1
                        NSLog("Rodent long-video segment %d frame %d PTS %.6f: %@", segmentIndex, count, pts, error.localizedDescription)
                        if consecutiveInferenceFailures >= 5 || failedFrames >= 30 {
                            throw NativeTrackingError.invalidVideo("Too many Core ML inference failures in segment \(segmentIndex) (total \(failedFrames), consecutive \(consecutiveInferenceFailures)). Completed segments are safe; restart from the same folder after diagnosing the video.")
                        }
                        return csvRow(frame: count, pts: pts, score: 0,
                                      points: Array(repeating: .missing, count: kind == .mousePose ? 6 : 7),
                                      inferenceFailed: true)
                    }
                }
                buffered.append(contentsOf: line.utf8)
                count += 1
                if !firstPTS.isFinite { firstPTS = pts }
                lastPTS = pts
                if buffered.count >= 32_768 {
                    try handle.write(contentsOf: buffered)
                    buffered.removeAll(keepingCapacity: true)
                }
                if count % 60 == 0 || sampledPoints != nil {
                    let thumbnail = sampledPoints.flatMap {
                        LiveSnapshot.make(imageBuffer, transform:transform, pts:pts, points:$0, model:kind)
                    }
                    if thumbnail != nil { lastLiveSample = ProcessInfo.processInfo.systemUptime }
                    progress(LongVideoProgress(completedSegments: manifest.completed.count,
                                               totalSegments: segmentCount,
                                               currentSegment: segmentIndex, processedInSegment: count,
                                               sourceTime:pts, sourceDuration:duration,livePreview:thumbnail))
                }
            }
            guard reader.status == .completed else {
                throw NativeTrackingError.invalidVideo(reader.error?.localizedDescription ?? "Video reader stopped before segment completion")
            }
            if !buffered.isEmpty { try handle.write(contentsOf: buffered) }
            try handle.synchronize()
            try handle.close()
            // A completed segment is first renamed, then checkpointed atomically.
            if manager.fileExists(atPath: finalURL.path) { try manager.removeItem(at: finalURL) }
            try manager.moveItem(at: temporaryURL, to: finalURL)
            let item = LongVideoManifest.Segment(index: segmentIndex, file: csvName,
                                                  records: count, firstPTS: firstPTS, lastPTS: lastPTS,
                                                  failedFrames: failedFrames)
            manifest.completed.removeAll { $0.index == segmentIndex }
            manifest.completed.append(item)
            manifest.completed.sort { $0.index < $1.index }
            try saveManifest(manifest, to: manifestURL)
            progress(LongVideoProgress(completedSegments: manifest.completed.count,
                                       totalSegments: segmentCount,
                                       currentSegment: segmentIndex, processedInSegment: count))
        }
        return manifest
    }
}
