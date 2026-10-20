// Ported from RodentFlow iOS 1.3; video algorithm preserved, UIImage switched to NSImage.
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics

/// Sequential whole-video analysis at 10 Hz.
/// AVAssetReader follows the original media timeline, while the lightweight tracker
/// runs only on the source frame nearest each 100 ms sampling target.
struct FlowFullVideoAnalyzer {
    static let analysisMaxDimension = 192
    static let analysisHz = 10.0
    static let defaultCheckpointSamples = 300   // ~30 seconds at 10 Hz

    struct RangeOutput {
        let startSeconds: Double
        let durationSeconds: Double
        let analysisHz: Double
        let points: [FlowTrackingPoint]
        var markersCM: [String: FlowArenaPoint] = [:]
    }

    struct ResumeSnapshot: Sendable {
        let existingPoints: [FlowTrackingPoint]
        let nextTargetTimeSeconds: Double
        let trackerState: FlowNativeMouseTracker.SessionState
        let nextCheckpointIndex: Int
    }

    struct CheckpointSnapshot: Sendable {
        let checkpointIndex: Int
        let points: [FlowTrackingPoint]
        let completedSamples: Int
        let lastVideoTimeSeconds: Double
        let nextTargetTimeSeconds: Double
        let trackerState: FlowNativeMouseTracker.SessionState
    }

    /// A very small thread-safe signal used by the app lifecycle to ask the analysis loop
    /// to persist its current in-memory chunk at the next safe frame boundary.
    final class CheckpointSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var requested = false

        func request() {
            lock.lock()
            requested = true
            lock.unlock()
        }

        func consume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let value = requested
            requested = false
            return value
        }
    }

    static func analyze(
        videoURL: URL,
        arenaShape: FlowArenaShape,
        arenaWidthCM: Double,
        arenaHeightCM: Double,
        calibration: FlowArenaCalibration,
        mazeArmWidthCM: Double,
        tStartArmLengthCM: Double,
        tChoiceArmLengthCM: Double,
        yArmLengthCM: Double,
        plusArmLengthCM: Double = 30,
        plusArmWidthCM: Double = 5,
        resume: ResumeSnapshot? = nil,
        checkpointSignal: CheckpointSignal? = nil,
        checkpointEverySamples: Int = defaultCheckpointSamples,
        checkpoint: (@Sendable (CheckpointSnapshot) throws -> Void)? = nil,
        progress: @escaping @Sendable (FlowAnalysisProgressSnapshot) -> Void = { _ in }
    ) async throws -> FlowFullAnalysisResult {
        let output = try await analyzeRange(
            videoURL: videoURL,
            startSeconds: 0,
            durationSeconds: nil,
            arenaShape: arenaShape,
            arenaWidthCM: arenaWidthCM,
            arenaHeightCM: arenaHeightCM,
            calibration: calibration,
            mazeArmWidthCM: mazeArmWidthCM,
            tStartArmLengthCM: tStartArmLengthCM,
            tChoiceArmLengthCM: tChoiceArmLengthCM,
            yArmLengthCM: yArmLengthCM,
            plusArmLengthCM: plusArmLengthCM,
            plusArmWidthCM: plusArmWidthCM,
            resume: resume,
            checkpointSignal: checkpointSignal,
            checkpointEverySamples: checkpointEverySamples,
            checkpoint: checkpoint,
            progress: progress
        )
        return FlowFullAnalysisResult(
            durationSeconds: output.durationSeconds,
            processingFPS: output.analysisHz,
            points: output.points,
            mazeEvents: FlowMazeEventAnalyzer.events(points: output.points, arenaShape: arenaShape),
            markersCM: output.markersCM
        )
    }

    static func analyzeRange(
        videoURL: URL,
        startSeconds: Double,
        durationSeconds requestedDuration: Double?,
        arenaShape: FlowArenaShape,
        arenaWidthCM: Double,
        arenaHeightCM: Double,
        calibration: FlowArenaCalibration,
        mazeArmWidthCM: Double,
        tStartArmLengthCM: Double,
        tChoiceArmLengthCM: Double,
        yArmLengthCM: Double,
        plusArmLengthCM: Double = 30,
        plusArmWidthCM: Double = 5,
        resume: ResumeSnapshot? = nil,
        checkpointSignal: CheckpointSignal? = nil,
        checkpointEverySamples: Int = defaultCheckpointSamples,
        checkpoint: (@Sendable (CheckpointSnapshot) throws -> Void)? = nil,
        progress: @escaping @Sendable (FlowAnalysisProgressSnapshot) -> Void = { _ in }
    ) async throws -> RangeOutput {
        let wallStart = ProcessInfo.processInfo.systemUptime
        let asset = AVURLAsset(url: videoURL)
        let durationTime = try await asset.load(.duration)
        let assetDuration = max(0, durationTime.seconds)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw FullAnalysisError.noVideoTrack }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFPS = Double(try await track.load(.nominalFrameRate))
        guard naturalSize.width > 0, naturalSize.height > 0 else { throw FullAnalysisError.invalidVideoSize }

        let start = max(0, min(startSeconds, assetDuration))
        let available = max(0, assetDuration - start)
        let rangeDuration = min(available, max(0, requestedDuration ?? available))
        guard rangeDuration > 0 else { throw FullAnalysisError.invalidTimeRange }
        let end = start + rangeDuration

        let displayRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        guard displayRect.width > 0, displayRect.height > 0 else { throw FullAnalysisError.invalidVideoSize }
        let inverseTransform = preferredTransform.inverted()
        let rawCalibration = calibrationMappedToRaw(
            calibration,
            naturalSize: naturalSize,
            displayRect: displayRect,
            inverseTransform: inverseTransform
        )

        let maxRawSide = max(naturalSize.width, naturalSize.height)
        let scale = min(1.0, CGFloat(analysisMaxDimension) / maxRawSide)
        func evenDimension(_ value: Int) -> Int {
            let safe = max(32, value)
            return safe.isMultiple(of: 2) ? safe : safe - 1
        }
        let targetWidth = evenDimension(Int((naturalSize.width * scale).rounded()))
        let targetHeight = evenDimension(Int((naturalSize.height * scale).rounded()))
        let estimatedSamples = max(1, Int(ceil(rangeDuration * analysisHz)))
        let existingCount = resume?.existingPoints.count ?? 0
        let initialTimelineFraction = min(1, max(0, ((resume?.nextTargetTimeSeconds ?? start) - start) / rangeDuration))
        progress(snapshot(
            fraction: max(0.02, 0.08 + 0.92 * initialTimelineFraction),
            samples: existingCount,
            total: estimatedSamples,
            wallStart: wallStart
        ))

        // Fixed background from sparse frames across the whole recording.
        // A mouse that remains still is therefore not gradually learned as background.
        let backgroundFrames: [FlowNativeMouseTracker.GrayFrame]
        do {
            let backgroundImages = try await FlowFrameExtractor.sparseBackgroundFrames(
                url: videoURL,
                count: 21,
                applyPreferredTransform: false,
                maxDimension: analysisMaxDimension
            )
            backgroundFrames = try backgroundImages.map {
                try FlowNativeMouseTracker.grayscale($0, exactWidth: targetWidth, exactHeight: targetHeight)
            }
        }
        guard backgroundFrames.count >= 3 else { throw FullAnalysisError.backgroundFailed }

        progress(snapshot(
            fraction: max(0.08, 0.08 + 0.92 * initialTimelineFraction),
            samples: existingCount,
            total: estimatedSamples,
            wallStart: wallStart
        ))

        let imagePointMapper: (CGPoint) -> CGPoint = { point in
            let rawX = CGFloat(point.x) / CGFloat(max(1, targetWidth - 1)) * max(1, naturalSize.width - 1)
            let rawY = CGFloat(point.y) / CGFloat(max(1, targetHeight - 1)) * max(1, naturalSize.height - 1)
            let transformed = CGPoint(x: rawX, y: rawY).applying(preferredTransform)
            let localX = transformed.x - displayRect.minX
            let localY = transformed.y - displayRect.minY
            return CGPoint(x: Double(localX / displayRect.width), y: Double(localY / displayRect.height))
        }

        let tracker = try FlowNativeMouseTracker.Session(
            backgroundFrames: backgroundFrames,
            calibration: rawCalibration,
            arenaShape: arenaShape,
            arenaWidthCM: arenaWidthCM,
            arenaHeightCM: arenaHeightCM,
            clipStartSeconds: start,
            mazeArmWidthCM: mazeArmWidthCM,
            tStartArmLengthCM: tStartArmLengthCM,
            tChoiceArmLengthCM: tChoiceArmLengthCM,
            yArmLengthCM: yArmLengthCM,
            plusArmLengthCM: plusArmLengthCM,
            plusArmWidthCM: plusArmWidthCM,
            restoredState: resume?.trackerState,
            imagePointMapper: imagePointMapper
        )

        let markersCM: [String: FlowArenaPoint] = [
            "A": tracker.arenaPoint(rawNormalized: rawCalibration.markerA),
            "B": tracker.arenaPoint(rawNormalized: rawCalibration.markerB),
            "T": tracker.arenaPoint(rawNormalized: rawCalibration.markerTarget)
        ]

        let interval = 1.0 / analysisHz
        let halfSourceFrame = nominalFPS > 0 ? 0.5 / nominalFPS : 0.0
        var nextTargetTime = max(start, resume?.nextTargetTimeSeconds ?? start)
        // Resume slightly before the target so the same nearest-frame policy is preserved.
        let readerStart = max(start, min(end, nextTargetTime - halfSourceFrame - 0.010))
        let readerDuration = max(0, end - readerStart)
        guard readerDuration > 0 || nextTargetTime >= end - interval else { throw FullAnalysisError.invalidTimeRange }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: readerStart, preferredTimescale: 600),
            duration: CMTime(seconds: max(0.001, readerDuration), preferredTimescale: 600)
        )

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw FullAnalysisError.readerConfigurationFailed }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? FullAnalysisError.readerStartFailed }

        var points = resume?.existingPoints ?? []
        points.reserveCapacity(estimatedSamples + 2)
        var pendingCheckpointStart = points.count
        var checkpointIndex = resume?.nextCheckpointIndex ?? 1

        var reusableGrayFrame = FlowNativeMouseTracker.GrayFrame(
            width: targetWidth,
            height: targetHeight,
            pixels: [UInt8](repeating: 0, count: targetWidth * targetHeight)
        )

        var sampleIndex = points.count
        var lastReportedFraction = max(0.08, 0.08 + 0.92 * initialTimelineFraction)
        let safeCheckpointSamples = max(1, checkpointEverySamples)

        func persistPendingCheckpoint(force: Bool) throws {
            guard let checkpoint else { return }
            let pendingCount = points.count - pendingCheckpointStart
            guard pendingCount > 0, force || pendingCount >= safeCheckpointSamples else { return }
            let chunk = Array(points[pendingCheckpointStart..<points.count])
            let lastTime = chunk.last?.videoTimeSeconds ?? points.last?.videoTimeSeconds ?? start
            try checkpoint(CheckpointSnapshot(
                checkpointIndex: checkpointIndex,
                points: chunk,
                completedSamples: points.count,
                lastVideoTimeSeconds: lastTime,
                nextTargetTimeSeconds: nextTargetTime,
                trackerState: tracker.checkpointState()
            ))
            pendingCheckpointStart = points.count
            checkpointIndex += 1
        }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                // A user pause/background transition is a save boundary, not a data-loss event.
                try persistPendingCheckpoint(force: true)
                reader.cancelReading()
                throw CancellationError()
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard pts.isFinite,
                  pts >= readerStart - 0.001,
                  pts <= end + 0.001,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            guard pts + halfSourceFrame >= nextTargetTime else { continue }

            try FlowNativeMouseTracker.fillGrayscale(pixelBuffer, into: &reusableGrayFrame)
            points.append(try tracker.process(frame: reusableGrayFrame, frameIndex: sampleIndex, timestamp: pts))
            sampleIndex += 1

            repeat { nextTargetTime += interval } while nextTargetTime <= pts + halfSourceFrame

            let lifecycleFlush = checkpointSignal?.consume() ?? false
            try persistPendingCheckpoint(force: lifecycleFlush)

            let timelineFraction = min(1, max(0, (pts - start) / rangeDuration))
            let fraction = 0.08 + 0.92 * timelineFraction
            if fraction - lastReportedFraction >= 0.004 || sampleIndex % 10 == 0 {
                progress(snapshot(fraction: fraction, samples: sampleIndex, total: estimatedSamples, wallStart: wallStart))
                lastReportedFraction = fraction
            }
        }

        if reader.status == .failed { throw reader.error ?? FullAnalysisError.readerFailed }

        // Persist the tail before final export. If export/archive fails afterwards, a complete
        // recoverable tracking result still exists on disk.
        try persistPendingCheckpoint(force: true)

        guard points.contains(where: { !$0.interpolated }) else { throw FlowNativeMouseTracker.TrackerError.noMouseFound }

        progress(snapshot(fraction: 1, samples: points.count, total: estimatedSamples, wallStart: wallStart))
        return RangeOutput(
            startSeconds: start,
            durationSeconds: rangeDuration,
            analysisHz: analysisHz,
            points: points,
            markersCM: markersCM
        )
    }

    private static func snapshot(
        fraction rawFraction: Double,
        samples: Int,
        total: Int?,
        wallStart: Double
    ) -> FlowAnalysisProgressSnapshot {
        let fraction = max(0, min(1, rawFraction))
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - wallStart)
        let remaining: Double?
        if fraction >= 0.10 && fraction < 0.999 && elapsed > 0.2 {
            remaining = max(0, elapsed * (1 - fraction) / fraction)
        } else if fraction >= 0.999 {
            remaining = 0
        } else {
            remaining = nil
        }
        return FlowAnalysisProgressSnapshot(
            fraction: fraction,
            processedSamples: samples,
            estimatedTotalSamples: total,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining
        )
    }

    private static func calibrationMappedToRaw(
        _ calibration: FlowArenaCalibration,
        naturalSize: CGSize,
        displayRect: CGRect,
        inverseTransform: CGAffineTransform
    ) -> FlowArenaCalibration {
        func map(_ point: FlowPoint) -> FlowPoint {
            let displayLocal = CGPoint(x: CGFloat(point.x) * displayRect.width, y: CGFloat(point.y) * displayRect.height)
            let transformedCoordinate = CGPoint(x: displayLocal.x + displayRect.minX, y: displayLocal.y + displayRect.minY)
            let raw = transformedCoordinate.applying(inverseTransform)
            return FlowPoint(
                x: clamp01(Double(raw.x / naturalSize.width)),
                y: clamp01(Double(raw.y / naturalSize.height))
            )
        }

        var result = calibration
        result.topLeft = map(calibration.topLeft)
        result.topRight = map(calibration.topRight)
        result.bottomRight = map(calibration.bottomRight)
        result.bottomLeft = map(calibration.bottomLeft)
        result.circleCenter = map(calibration.circleCenter)
        result.circleEdge = map(calibration.circleEdge)
        result.tJunction = map(calibration.tJunction)
        result.tStart = map(calibration.tStart)
        result.tLeft = map(calibration.tLeft)
        result.tRight = map(calibration.tRight)
        result.yJunction = map(calibration.yJunction)
        result.yA = map(calibration.yA)
        result.yB = map(calibration.yB)
        result.yC = map(calibration.yC)
        result.plusCenter = map(calibration.plusCenter)
        result.plusN = map(calibration.plusN)
        result.plusE = map(calibration.plusE)
        result.plusS = map(calibration.plusS)
        result.plusW = map(calibration.plusW)
        result.markerA = map(calibration.markerA)
        result.markerB = map(calibration.markerB)
        result.markerTarget = map(calibration.markerTarget)
        return result
    }

    private static func clamp01(_ value: Double) -> Double { max(0, min(1, value)) }

    enum FullAnalysisError: LocalizedError {
        case noVideoTrack
        case invalidVideoSize
        case invalidTimeRange
        case backgroundFailed
        case readerConfigurationFailed
        case readerStartFailed
        case readerFailed

        var errorDescription: String? {
            switch self {
            case .noVideoTrack: return flowLoc("The selected file does not contain a readable video track.")
            case .invalidVideoSize: return flowLoc("The video dimensions could not be read.")
            case .invalidTimeRange: return flowLoc("The requested video time range is empty.")
            case .backgroundFailed: return flowLoc("The app could not estimate a stable arena background from this video.")
            case .readerConfigurationFailed: return flowLoc("The video reader could not be configured on this device.")
            case .readerStartFailed: return flowLoc("The video reader could not start.")
            case .readerFailed: return flowLoc("The video reader stopped before reaching the end of the recording.")
            }
        }
    }
}
