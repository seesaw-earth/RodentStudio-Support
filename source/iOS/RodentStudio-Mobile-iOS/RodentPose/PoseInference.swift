// PoseInference.swift — model loading and frame-by-frame pose inference on a video.
// The per-frame pipeline is unchanged from MousePose 1.0 (upright CIImage → optional grayscale →
// YOLO pose → highest-confidence detection). New: time range, resume after a pause, optional
// two-animal mode, throttled progress and a live preview frame.
//
// Speed: UltralyticsYOLO's `predictOnImage` for pose also renders an annotated copy of every
// frame (a new CIContext, a full-resolution CGImage and a UIKit drawing pass) that this app never
// uses. `DirectPoseModel` runs the same Vision request on the same model and decodes the same
// output with the same arithmetic, without that rendering. The first frames of every run are
// computed both ways and compared; on any difference the run continues with the package.

import AVFoundation
import CoreImage
import CoreML
import SwiftUI
import UIKit
import UltralyticsYOLO
import Vision

// MARK: - Model

@MainActor
final class PoseEngine: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private(set) var yolo: YOLO?
    /// Faster path for the same model (nil until loaded, or if this model layout is not supported).
    private(set) var direct: DirectPoseModel?

    var isReady: Bool { state == .ready }

    init() { load() }

    func load() {
        state = .loading
        yolo = YOLO(kModelName, task: .pose) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.state = .ready
                    self.loadDirect()
                case .failure(let error):
                    self.state = .failed(L10n.tr("模型加载失败：\(error.localizedDescription)。请确认 \(kModelName).mlpackage 在 RodentStudio 工程资源中并已加入 App target。"))
                }
            }
        }
    }

    private func loadDirect() {
        guard direct == nil else { return }
        Task { [weak self] in
            let model = await Task.detached(priority: .utility) { DirectPoseModel.load(named: kModelName) }.value
            self?.direct = model
        }
    }
}

// MARK: - Direct Vision path

/// Runs the bundled end-to-end pose model ([1, N, 6 + 3·K] output) through Vision exactly like
/// UltralyticsYOLO 8.9 does (`.scaleFit`, same letterbox arithmetic, confidence > 0.25, first 30
/// detections), but without rendering an annotated image for every frame.
final class DirectPoseModel: @unchecked Sendable {
    let model: VNCoreMLModel
    let inputWidth: Int
    let inputHeight: Int
    /// UltralyticsYOLO defaults.
    let confidenceThreshold: Float = 0.25
    let maxDetections = 30

    private init(model: VNCoreMLModel, inputWidth: Int, inputHeight: Int) {
        self.model = model
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
    }

    /// Loads the compiled model from the app bundle; nil if it is missing or has another layout.
    static func load(named name: String) -> DirectPoseModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine   // same choice as UltralyticsYOLO (useGpu: true)
        guard let ml = try? MLModel(contentsOf: url, configuration: config) else { return nil }
        let description = ml.modelDescription
        guard let image = description.inputDescriptionsByName.values.compactMap(\.imageConstraint).first,
              image.pixelsWide > 0, image.pixelsHigh > 0 else { return nil }
        // Only the end-to-end pose head is decoded here: [1, detections, 6 + 3 × keypoints].
        let shapes = description.outputDescriptionsByName.values.compactMap { $0.multiArrayConstraint?.shape.map(\.intValue) }
        guard shapes.count == 1, let shape = shapes.first, shape.count == 3, shape[2] < shape[1],
              (shape[2] - 6) % 3 == 0, (shape[2] - 6) / 3 == kKeypointCount else { return nil }
        guard let vn = try? VNCoreMLModel(for: ml) else { return nil }
        return DirectPoseModel(model: vn, inputWidth: image.pixelsWide, inputHeight: image.pixelsHigh)
    }

    /// One request per run (requests are not shared between threads).
    func makeRequest() -> VNCoreMLRequest {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        return request
    }

    /// Detections above the confidence threshold in model order, keypoints in pixels of
    /// `frameSize`. nil when Vision fails or the output is not as expected.
    func detect(_ image: CIImage, request: VNCoreMLRequest, frameSize: CGSize) -> [AnimalPose]? {
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let array = (request.results as? [VNCoreMLFeatureValueObservation])?.first?.featureValue.multiArrayValue else {
            return nil
        }
        return decode(array, inputSize: image.extent.size, frameSize: frameSize)
    }

    func decode(_ array: MLMultiArray, inputSize: CGSize, frameSize: CGSize) -> [AnimalPose]? {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count == 3, strides.count == 3, array.dataType == .float32 else { return nil }
        let layout = PoseDecoding.Layout(detections: shape[1], fields: shape[2], detectionStride: strides[1], fieldStride: strides[2])
        let modelSize = (width: inputWidth, height: inputHeight)
        let threshold = confidenceThreshold, limit = maxDetections
        return array.withUnsafeBufferPointer(ofType: Float.self) { p in
            PoseDecoding.decode(p, layout: layout, inputSize: inputSize, modelSize: modelSize, frameSize: frameSize,
                                threshold: threshold, limit: limit)
        }
    }

    /// True when two detection lists describe the same animals (within 0.5 % of the frame).
    static func agree(_ a: [AnimalPose], _ b: [AnimalPose], frameSize: CGSize) -> Bool {
        func top(_ list: [AnimalPose]) -> [AnimalPose] {
            Array(list.filter(\.detected).sorted { $0.conf > $1.conf }.prefix(2))
        }
        let ta = top(a), tb = top(b)
        guard ta.count == tb.count else { return false }
        let w = Float(max(frameSize.width, 1)), h = Float(max(frameSize.height, 1))
        for (p, q) in zip(ta, tb) {
            guard abs(p.conf - q.conf) <= 0.01 else { return false }
            for k in 0..<kKeypointCount {
                if abs(p.x[k] - q.x[k]) / w > 0.005 || abs(p.y[k] - q.y[k]) / h > 0.005 || abs(p.kconf[k] - q.kconf[k]) > 0.02 {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - Cancellation and progress

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

struct InferenceProgress: Equatable {
    var fraction: Double = 0
    var processedFrames = 0
    var estimatedFrames = 0
    var videoTime: Double = 0
    var elapsed: Double = 0
    var remaining: Double?
    var msPerFrame: Double = 0
}

/// Latest frame shown while the model runs.
struct LiveFrame {
    var image: CGImage
    var poses: [AnimalPose]
    var frameSize: V2
    var time: Double
}

// MARK: - Processor

enum VideoPoseProcessor {

    /// Runs the model over the requested part of the video. When `resume` is given, frames after
    /// its last processed time are appended to it; otherwise a new track is created.
    nonisolated static func run(
        url: URL, yolo: YOLO, direct: DirectPoseModel?, settings: InferenceSettings, resume: PoseTrack?, token: CancelToken,
        progress: @escaping @Sendable (InferenceProgress) -> Void,
        preview: @escaping @Sendable (LiveFrame) -> Void
    ) async throws -> PoseTrack {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "RodentPose", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("这个文件里没有视频画面")])
        }
        let transform = try await videoTrack.load(.preferredTransform)
        let fps = Double(try await videoTrack.load(.nominalFrameRate))
        let natural = try await videoTrack.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let orientation = imageOrientation(from: transform)
        let upright = natural.applying(transform)
        let frameSize = CGSize(width: abs(upright.width), height: abs(upright.height))
        let safeFPS = fps > 0 ? fps : 30

        var track = resume ?? PoseTrack(animalCount: settings.animalCount, fps: safeFPS,
                                        frameWidth: Double(frameSize.width), frameHeight: Double(frameSize.height),
                                        frameStride: settings.stride)
        let animalCount = track.animalCount
        let step = max(1, track.frameStride)

        let rangeEnd = settings.endTime > 0 ? min(settings.endTime, duration) : duration
        let resumeAfter: Double? = resume.flatMap { $0.count > 0 ? $0.processedUntil : nil }
        let rangeStart = resumeAfter.map { $0 + 0.5 / safeFPS } ?? max(0, settings.startTime)
        guard rangeEnd > rangeStart else {
            track.complete = true
            return track
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        if rangeStart > 0.001 || rangeEnd < duration - 0.001 {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: rangeStart, preferredTimescale: 600),
                                           end: CMTime(seconds: rangeEnd, preferredTimescale: 600))
        }
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "RodentPose", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法读取视频")])
        }

        let estimated = max(1, Int(((rangeEnd - rangeStart) * safeFPS / Double(step)).rounded()))
        track.reserveCapacity(additionalFrames: estimated + 2)
        var directModel = direct
        let directRequest = direct?.makeRequest()
        var directChecksLeft = 3
        var seq = 0
        var frameOffset: Int?
        var inferSeconds = 0.0
        var inferred = 0
        let previousMs = track.msPerFrame
        let previousCount = track.count
        var cancelled = false
        var lastCentroids: [V2?] = [nil, nil]
        if animalCount > 1, let last = (0..<track.count).last {
            lastCentroids = (0..<animalCount).map { track.pose(last, $0).centroid() }
        }
        let started = CFAbsoluteTimeGetCurrent()
        var lastProgress = 0.0
        var lastPreview = -10.0
        let ciContext = CIContext(options: [.cacheIntermediates: false])

        while let sample = output.copyNextSampleBuffer() {
            if token.isCancelled { reader.cancelReading(); cancelled = true; break }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let after = resumeAfter, time <= after + 1e-4 { continue }
            if frameOffset == nil {
                frameOffset = resumeAfter == nil ? Int((time * safeFPS).rounded()) : track.lastFrameIndex + 1
            }
            let i = seq
            seq += 1
            guard i % step == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let frameNumber = (frameOffset ?? 0) + i

            var poses: [AnimalPose] = []
            var snapshot: CGImage?
            let now = CFAbsoluteTimeGetCurrent()
            let wantsPreview = now - lastPreview >= 1.0
            autoreleasepool {
                var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
                if settings.grayscale {
                    image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
                }
                let t0 = CFAbsoluteTimeGetCurrent()
                var detections: [AnimalPose]
                if let model = directModel, let request = directRequest,
                   let fast = model.detect(image, request: request, frameSize: frameSize) {
                    inferSeconds += CFAbsoluteTimeGetCurrent() - t0
                    if directChecksLeft > 0 {
                        // Cross-check the first frames against the package; keep its result
                        // for these frames and fall back to it for the run on any difference.
                        // Only frames with an animal count as a confirmation.
                        let reference = allPoses(yolo(image), frameSize: frameSize)
                        if DirectPoseModel.agree(fast, reference, frameSize: frameSize) {
                            if reference.contains(where: { $0.detected }) { directChecksLeft -= 1 }
                        } else {
                            directModel = nil
                        }
                        detections = reference
                    } else {
                        detections = fast
                    }
                } else {
                    directModel = nil
                    detections = allPoses(yolo(image), frameSize: frameSize)
                    inferSeconds += CFAbsoluteTimeGetCurrent() - t0
                }
                if animalCount > 1 {
                    poses = IdentityTracker.assign(detections, previous: lastCentroids)
                } else {
                    poses = [best(detections)]
                }
                if wantsPreview {
                    let extent = image.extent
                    let scale = min(1, 540 / max(extent.width, extent.height, 1))
                    let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    snapshot = ciContext.createCGImage(small, from: small.extent)
                }
            }
            inferred += 1
            if animalCount > 1 {
                for a in 0..<min(animalCount, poses.count) {
                    if let c = poses[a].centroid() { lastCentroids[a] = c }
                }
            }
            track.append(frame: frameNumber, time: time, animals: poses)
            track.processedUntil = time

            if let snapshot {
                lastPreview = now
                preview(LiveFrame(image: snapshot, poses: poses, frameSize: V2(Double(frameSize.width), Double(frameSize.height)), time: time))
            }
            if now - lastProgress >= 0.2 {
                lastProgress = now
                progress(makeProgress(time: time, start: rangeStart, end: rangeEnd, started: started, inferred: inferred,
                                      estimated: estimated, inferSeconds: inferSeconds))
            }
        }
        if !cancelled && reader.status == .failed {
            throw reader.error ?? NSError(domain: "RodentPose", code: 3, userInfo: [NSLocalizedDescriptionKey: L10n.tr("读取视频时出错")])
        }
        let ms = inferred > 0 ? inferSeconds / Double(inferred) * 1000 : 0
        let total = previousCount + inferred
        track.msPerFrame = total > 0 ? (previousMs * Double(previousCount) + ms * Double(inferred)) / Double(total) : 0
        track.complete = !cancelled
        if !cancelled { track.processedUntil = max(track.processedUntil, rangeEnd) }
        var final = makeProgress(time: cancelled ? track.processedUntil : rangeEnd, start: rangeStart, end: rangeEnd, started: started,
                                 inferred: inferred, estimated: estimated, inferSeconds: inferSeconds)
        if !cancelled { final.fraction = 1; final.remaining = 0 }
        progress(final)
        return track
    }

    nonisolated static func makeProgress(time: Double, start: Double, end: Double, started: CFAbsoluteTime,
                                         inferred: Int, estimated: Int, inferSeconds: Double) -> InferenceProgress {
        var p = InferenceProgress()
        p.fraction = min(1, max(0, (time - start) / max(end - start, 1e-6)))
        p.processedFrames = inferred
        p.estimatedFrames = estimated
        p.videoTime = time
        p.elapsed = CFAbsoluteTimeGetCurrent() - started
        p.remaining = p.fraction > 0.01 ? p.elapsed / p.fraction * (1 - p.fraction) : nil
        p.msPerFrame = inferred > 0 ? inferSeconds / Double(inferred) * 1000 : 0
        return p
    }

    /// Highest-confidence detection (same rule as MousePose 1.0; the first one on ties).
    nonisolated static func best(_ detections: [AnimalPose]) -> AnimalPose {
        var top = AnimalPose.missing
        for d in detections where d.detected && d.conf > top.conf { top = d }
        return top
    }

    /// All detections (for the two-animal mode).
    nonisolated static func allPoses(_ result: YOLOResult, frameSize: CGSize) -> [AnimalPose] {
        let n = min(result.boxes.count, result.keypointsList.count)
        return (0..<n).map { pose(from: result.keypointsList[$0], conf: result.boxes[$0].conf, frameSize: frameSize) }
    }

    /// Keypoints in pixels of the upright frame, from the normalized coordinates.
    nonisolated static func pose(from kp: Keypoints, conf: Float, frameSize: CGSize) -> AnimalPose {
        guard kp.xyn.count == kKeypointCount, kp.conf.count == kKeypointCount else { return .missing }
        let w = Float(frameSize.width), h = Float(frameSize.height)
        return AnimalPose(conf: max(conf, 1e-4),
                          x: kp.xyn.map { $0.x * w },
                          y: kp.xyn.map { $0.y * h },
                          kconf: kp.conf)
    }

    /// Phone videos store pixels sideways and mark the orientation with preferredTransform.
    nonisolated static func imageOrientation(from t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}

// MARK: - Video helpers

enum VideoTools {
    static func readMeta(url: URL) async throws -> VideoMeta {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "RodentPose", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("这个文件里没有视频画面")])
        }
        let (natural, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let upright = natural.applying(transform)
        var meta = VideoMeta()
        meta.duration = duration.isFinite ? duration : 0
        meta.fps = fps > 0 ? Double(fps) : 30
        meta.width = Double(abs(upright.width))
        meta.height = Double(abs(upright.height))
        if let item = try? await asset.load(.creationDate), let date = try? await item.load(.dateValue) {
            meta.creationDate = date
        }
        meta.fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return meta
    }

    /// Upright frame at `time` (seconds).
    static func frame(url: URL, at time: Double, maxSize: CGFloat = 1600) async -> CGImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        return try? await gen.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600)).image
    }
}

// MARK: - Importing a video

/// Video from the photo library, copied into the app's temporary folder.
struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return ImportedMovie(url: dst)
        }
    }
}
