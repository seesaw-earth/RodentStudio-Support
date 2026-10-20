import Foundation
import AVFoundation
import CoreML
import Vision
import CoreGraphics

// Stage 2: native full-video pose extraction. No behavioural scores are produced here.
// RodentLimb raw-head interpretation follows the original iOS PoseDecoder.swift.
// MousePose decoding follows the existing RodentPose end-to-end decoder.
// Scientific parity with iOS/desktop metrics is NOT established yet.

enum NativeTrackingError: LocalizedError {
    case unsupportedTensor([Int], String)
    case invalidVideo(String)
    case missingOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedTensor(let shape, let name): return "Unexpected \(name) output tensor: \(shape)"
        case .invalidVideo(let reason): return "Video processing failed: \(reason)"
        case .missingOutput: return "Model did not return an MLMultiArray pose output."
        case .cancelled: return "Processing cancelled."
        }
    }
}

final class NativeTrackingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopRequested = false
    func cancel() { lock.lock(); stopRequested = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }
}

struct NativeTrackPoint {
    let x: Double
    let y: Double
    let confidence: Double
    static let missing = NativeTrackPoint(x: -1, y: -1, confidence: 0)
}

struct NativeTrackedFrame: Identifiable {
    let index: Int
    let time: Double   // relative to first decoded video frame
    let score: Double
    let points: [NativeTrackPoint] // in upright display-frame pixels
    var inferenceFailed: Bool = false // Distinct from a valid no-detection frame.
    var id: Int { index }
}

struct NativeTrackingResult {
    let model: PoseModelKind
    let videoFile: String
    let videoWidth: Int
    let videoHeight: Int
    let fps: Double
    let timeOffset: Double
    let frames: [NativeTrackedFrame]
    let elapsedSeconds: Double

    var names: [String] {
        switch model {
        case .mousePose: return ["nose", "left_ear", "right_ear", "neck", "body_center", "tail_base"]
        case .cylinderV2: return Kp.allCases.map(\.exportName)
        }
    }

    var inferenceFailureCount: Int { frames.filter(\.inferenceFailed).count }

    var detectionFraction: Double {
        guard !frames.isEmpty else { return 0 }
        let valid = frames.count - inferenceFailureCount
        guard valid > 0 else { return 0 }
        return Double(frames.filter { !$0.inferenceFailed && $0.score > 0 }.count) / Double(valid)
    }

    func csv() -> String {
        let header = (["frame_index", "time_s", "detected", "box_conf"] + names.flatMap { name in
            ["\(name)_x", "\(name)_y", "\(name)_conf"]
        } + ["inference_failed"]).joined(separator: ",")
        var result = header + "\n"
        for f in frames {
            var cells = [String(f.index), String(format: "%.6f", f.time), f.score > 0 ? "1" : "0", String(format: "%.7g", f.score)]
            for p in f.points {
                if p.x >= 0 && p.y >= 0 && p.x.isFinite && p.y.isFinite {
                    cells.append(contentsOf: [String(format: "%.5f", p.x), String(format: "%.5f", p.y), String(format: "%.7g", p.confidence)])
                } else { cells.append(contentsOf: ["", "", "0"]) }
            }
            cells.append(f.inferenceFailed ? "1" : "0")
            result += cells.joined(separator: ",") + "\n"
        }
        return result
    }

    /// Only Cylinder/TST/Gait: compatible with the original iOS Swift PoseTrack layout.
    /// Does NOT imply that contact, gait or TST metrics have been scientifically validated.
    func limbPoseTrack() -> PoseTrack? {
        guard model == .cylinderV2 else { return nil }
        var out = PoseTrack(width: videoWidth, height: videoHeight, fps: fps,
                            duration: frames.last?.time ?? 0,
                            modelName: model.rawValue, modelVersion: "native-video-stage2")
        out.reserve(frames.count)
        out.timeOffset = timeOffset
        for frame in frames {
            out.times.append(frame.time)
            out.boxConfidence.append(Float(frame.score))
            for k in 0..<7 {
                let p = frame.points[k]
                out.x[k].append(Float(p.x))
                out.y[k].append(Float(p.y))
                out.c[k].append(Float(p.confidence))
            }
        }
        return out
    }
}

/// Shape+stride-aware multiarray access avoids thousands of NSNumber allocations per frame.
private struct PoseTensorAccessor {
    let tensor: MLMultiArray
    let candidates: Int
    let features: Int
    private let candidateStride: Int
    private let featureStride: Int

    init(_ tensor: MLMultiArray, features expected: Int) throws {
        let d = tensor.shape.map(\.intValue)
        let s = tensor.strides.map(\.intValue)
        guard d.count == 3, d[0] == 1 else {
            throw NativeTrackingError.unsupportedTensor(d, "pose")
        }
        if d[2] == expected {
            candidates = d[1]; features = d[2]
            candidateStride = s[1]; featureStride = s[2]
        } else if d[1] == expected {
            candidates = d[2]; features = d[1]
            candidateStride = s[2]; featureStride = s[1]
        } else {
            throw NativeTrackingError.unsupportedTensor(d, "pose (expected \(expected) features)")
        }
        guard candidates > 0 else { throw NativeTrackingError.unsupportedTensor(d, "empty pose") }
        self.tensor = tensor
    }

    @inline(__always) func get(_ candidate: Int, _ feature: Int) -> Double {
        let index = candidate * candidateStride + feature * featureStride
        switch tensor.dataType {
        case .float16:
            let bits = tensor.dataPointer.assumingMemoryBound(to: UInt16.self)[index]
            let sign = UInt32(bits & 0x8000) << 16
            let exponent = UInt32((bits >> 10) & 0x1F)
            let fraction = UInt32(bits & 0x03FF)

            if exponent == 0 {
                if fraction == 0 {
                    return Double(Float(bitPattern: sign))
                }
                let value = Double(fraction) / 16_777_216.0
                return sign == 0 ? value : -value
            }

            let exponent32: UInt32 = exponent == 31
                ? 0x7F80_0000
                : (exponent + 112) << 23

            return Double(Float(bitPattern: sign | exponent32 | (fraction << 13)))
        case .float32:
            return Double(tensor.dataPointer.assumingMemoryBound(to: Float.self)[index])
        case .double:
            return tensor.dataPointer.assumingMemoryBound(to: Double.self)[index]
        default:
            return Double.nan
        }
    }
}

enum NativePoseDecoder {
    static func decode(_ tensor: MLMultiArray, kind: PoseModelKind, imageWidth: Int, imageHeight: Int) throws -> (score: Double, points: [NativeTrackPoint]) {
        let count = kind == .mousePose ? 6 : 7
        let expected = kind == .mousePose ? 24 : 26
        let size = kind == .mousePose ? 960.0 : 640.0
        let data = try PoseTensorAccessor(tensor, features: expected)
        let scale = min(size / Double(imageWidth), size / Double(imageHeight))
        let padX = (size - Double(imageWidth) * scale) / 2
        let padY = (size - Double(imageHeight) * scale) / 2
        var bestIndex: Int? = nil
        var bestScore = 0.25
        var validDetections = 0
        for i in 0..<data.candidates {
            let c = data.get(i, 4)
            guard c.isFinite, c > 0.25 else { continue }
            if c > bestScore { bestIndex = i; bestScore = c }
            // RodentPose end-to-end: evaluate only first 30 passing detections in output order.
            if kind == .mousePose {
                validDetections += 1
                if validDetections == 30 { break }
            }
        }
        guard let chosen = bestIndex else {
            return (0, Array(repeating: .missing, count: count))
        }
        let start = kind == .mousePose ? 6 : 5
        var points: [NativeTrackPoint] = []
        points.reserveCapacity(count)
        for k in 0..<count {
            let px = (data.get(chosen, start + k * 3) - padX) / scale
            let py = (data.get(chosen, start + k * 3 + 1) - padY) / scale
            let probability = data.get(chosen, start + k * 3 + 2)
            if px.isFinite && py.isFinite && probability.isFinite,
               px >= 0 && py >= 0 && px < Double(imageWidth) && py < Double(imageHeight) {
                points.append(NativeTrackPoint(x: px, y: py, confidence: max(0, min(1, probability))))
            } else { points.append(.missing) }
        }
        return (bestScore, points)
    }
}

/// Reuses the same loaded MLModel and crop/scale setting. On an isolated Vision
/// error, resets the Vision request and retries once on the SAME pixel buffer.
/// It never substitutes a different pose model or changes the compute backend.
final class NativeResilientVisionPredictor {
    private let visionModel: VNCoreMLModel
    private var request: VNCoreMLRequest

    init(model: MLModel) throws {
        visionModel = try VNCoreMLModel(for: model)
        request = Self.makeRequest(visionModel)
    }

    private static func makeRequest(_ model: VNCoreMLModel) -> VNCoreMLRequest {
        let r = VNCoreMLRequest(model: model)
        r.imageCropAndScaleOption = .scaleFit
        return r
    }

    func infer(_ imageBuffer: CVPixelBuffer) throws -> MLMultiArray {
        var diagnostic = "Unknown Vision failure"
        for attempt in 0..<2 {
            do {
                try VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .up, options: [:]).perform([request])
                guard let tensor = (request.results ?? [])
                    .compactMap({ $0 as? VNCoreMLFeatureValueObservation })
                    .compactMap({ $0.featureValue.multiArrayValue }).first else {
                    throw NativeTrackingError.missingOutput
                }
                return tensor
            } catch {
                let ns = error as NSError
                let nested = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)
                diagnostic = "\(ns.domain) code=\(ns.code): \(ns.localizedDescription)"
                if let nested { diagnostic += " (underlying: \(nested.domain) \(nested.code) \(nested.localizedDescription))" }
                NSLog("Rodent Core ML attempt %d failed: %@", attempt + 1, diagnostic)
                // Clear any retained observations and make a fresh request before retrying.
                request = Self.makeRequest(visionModel)
            }
        }
        throw NativeTrackingError.invalidVideo("Vision/Core ML failed twice on one frame: \(diagnostic)")
    }
}

enum NativeVideoTrackingEngine {
    /// Reads the entire video sequentially, without seeking and without frame dropping.
    /// Image orientation is applied *after* inference, matching RodentLimb's iOS approach.
    static func run(url: URL, kind: PoseModelKind, cancellation: NativeTrackingCancellation,
                    onProgress: @escaping (Int, Int) -> Void) throws -> NativeTrackingResult {
        let startTime = ProcessInfo.processInfo.systemUptime
        let ml = try NativeModelCatalog.load(kind)
        let predictor = try NativeResilientVisionPredictor(model: ml)
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw NativeTrackingError.invalidVideo("No video track")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw NativeTrackingError.invalidVideo(reader.error?.localizedDescription ?? "Cannot open video")
        }
        defer { if reader.status == .reading { reader.cancelReading() } }
        let transform = track.preferredTransform
        let fps = Double(track.nominalFrameRate) > 0 ? Double(track.nominalFrameRate) : 30.0
        let estimated = max(1, Int(CMTimeGetSeconds(asset.duration) * fps))
        var rawWidth = 0
        var rawHeight = 0
        var displayWidth = 0
        var displayHeight = 0
        var displayRect = CGRect.zero
        var firstPTS: Double?
        var frames: [NativeTrackedFrame] = []
        frames.reserveCapacity(min(estimated, 500_000))
        onProgress(0, estimated)
        var consecutiveInferenceFailures = 0
        while let sample = output.copyNextSampleBuffer() {
            if cancellation.isCancelled { throw NativeTrackingError.cancelled }
            guard let pixel = CMSampleBufferGetImageBuffer(sample) else { continue }
            if rawWidth == 0 {
                rawWidth = CVPixelBufferGetWidth(pixel)
                rawHeight = CVPixelBufferGetHeight(pixel)
                guard rawWidth > 0 && rawHeight > 0 else { throw NativeTrackingError.invalidVideo("Invalid frame size") }
                displayRect = CGRect(x: 0, y: 0, width: CGFloat(rawWidth), height: CGFloat(rawHeight)).applying(transform)
                displayWidth = Int(abs(displayRect.width).rounded())
                displayHeight = Int(abs(displayRect.height).rounded())
            }
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
            if firstPTS == nil { firstPTS = pts.isFinite ? pts : 0 }
            let seconds = pts.isFinite ? max(0, pts - (firstPTS ?? 0)) : Double(frames.count) / fps
            // Keep Vision observations, tensor and decoder temporaries inside one
            // autorelease pool. Preserve an explicit missing row if inference fails.
            var decoded: (score: Double, points: [NativeTrackPoint]) =
                (0, Array(repeating: .missing, count: kind == .mousePose ? 6 : 7))
            var inferenceFailed = false
            do {
                decoded = try autoreleasepool {
                    let tensor = try predictor.infer(pixel)
                    return try NativePoseDecoder.decode(tensor, kind: kind, imageWidth: rawWidth, imageHeight: rawHeight)
                }
                consecutiveInferenceFailures = 0
            } catch {
                inferenceFailed = true
                consecutiveInferenceFailures += 1
                NSLog("Rodent frame %d time %.6f: inference failed after retry: %@", frames.count, seconds, error.localizedDescription)
                // Do not convert persistent failures into seemingly valid tracks.
                if consecutiveInferenceFailures >= 5 {
                    throw NativeTrackingError.invalidVideo("5 consecutive Core ML failures; last frame \(frames.count). See Xcode console. Switch to Long-video tracking and inspect the failing region.")
                }
            }
            var points = decoded.points
            if decoded.score > 0 {
                points = decoded.points.map { point in
                    guard point.x >= 0 && point.y >= 0 else { return .missing }
                    let rotated = CGPoint(x: point.x, y: point.y).applying(transform)
                    return NativeTrackPoint(x: Double(rotated.x - displayRect.minX),
                                            y: Double(rotated.y - displayRect.minY),
                                            confidence: point.confidence)
                }
            }
            frames.append(NativeTrackedFrame(index: frames.count, time: seconds, score: decoded.score, points: points, inferenceFailed: inferenceFailed))
            if frames.count % 15 == 0 { onProgress(frames.count, max(estimated, frames.count)) }
        }
        guard reader.status == .completed else {
            throw NativeTrackingError.invalidVideo(reader.error?.localizedDescription ?? "Reader stopped unexpectedly")
        }
        guard !frames.isEmpty else { throw NativeTrackingError.invalidVideo("No decodable frames") }
        onProgress(frames.count, frames.count)
        return NativeTrackingResult(model: kind, videoFile: url.lastPathComponent,
                                    videoWidth: displayWidth, videoHeight: displayHeight,
                                    fps: fps, timeOffset: firstPTS ?? 0,
                                    frames: frames, elapsedSeconds: ProcessInfo.processInfo.systemUptime - startTime)
    }
}
