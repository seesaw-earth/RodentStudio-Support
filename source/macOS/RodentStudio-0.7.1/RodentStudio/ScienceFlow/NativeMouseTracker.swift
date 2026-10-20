// Ported from RodentFlow iOS 1.3; video algorithm preserved, UIImage switched to NSImage.
import Foundation
import AppKit
import CoreGraphics
import CoreVideo
import Darwin

/// Lightweight, dependency-free tracker for fixed-camera, single-mouse open-field videos.
///
/// Pipeline:
/// temporal-median background (with resting-mouse repair) -> absolute difference -> adaptive
/// threshold -> light cleanup -> connected components -> temporal candidate scoring
/// -> contrast-weighted centroid -> arena mapping.
///
/// Once the best mouse component is selected, its centroid weighted by the background difference
/// is used as the tracking point (1.1.1; V0.1–1.1 used the unweighted pixel centroid, which the
/// thin tail pulled ~1 cm backwards at 192-px analysis resolution). No erosion, pose estimation,
/// optical flow, or neural network is used.
enum FlowNativeMouseTracker {
    /// Gray-level change (0–255, full range) that counts a pixel as "moved" for the motion index.
    /// 20 rather than 12: compressed video (B-frames) makes the edges of a completely still mouse
    /// flicker by 12–24 levels at analysis resolution, which broke freezing bouts into pieces,
    /// while real movement of a contrasted mouse changes pixels by far more.
    static let motionPixelThreshold = 20
    static let motionIndexVersion = "frame_difference_v2_fullrange_arena_pixels_delta20_10hz"

    /// Video-range luma (16–235) to full-range gray (0–255). The background comes from
    /// AVAssetImageGenerator RGB images (full range); frames read with AVAssetReader as
    /// 420YpCbCr8BiPlanarVideoRange must be expanded the same way, otherwise every floor pixel
    /// differs from the background by ~0.14·gray − 16 levels and hidden mice produce false blobs.
    static let videoToFullRange: [UInt8] = (0..<256).map { v in
        UInt8(max(0, min(255, Int((Double(v - 16) * 255.0 / 219.0).rounded()))))
    }
    struct Input: @unchecked Sendable {
        let frames: [NSImage]
        let timestamps: [Double]
        let backgroundFrames: [NSImage]
        let calibration: FlowArenaCalibration
        let arenaShape: FlowArenaShape
        let arenaWidthCM: Double
        let arenaHeightCM: Double
        let clipStartSeconds: Double
    }

    struct GrayFrame: @unchecked Sendable {
        let width: Int
        let height: Int
        var pixels: [UInt8]
    }

    /// Minimal temporal state needed to resume the classic-centroid tracker without a jump.
    struct SessionState: Codable, Sendable, Equatable {
        let previousX: Double?
        let previousY: Double?
        let previousArea: Double?
    }

    private struct Component {
        let area: Int
        let x: Double
        let y: Double
        let meanDiff: Double
        let width: Int
        let height: Int
    }

    /// Stateful tracker reused across a whole video. It carries only the previous mouse position
    /// and previous component area; there is no heavy model, optical flow, or neural network.
    final class Session {
        private let background: GrayFrame
        private let arenaIndices: [Int]
        private let arenaArea: Int
        private let processingBounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
        private let mapper: ArenaMapper
        private let arenaWidthCM: Double
        private let arenaHeightCM: Double
        private let clipStartSeconds: Double
        private let diagonal: Double
        private let imagePointMapper: (CGPoint) -> CGPoint
        /// Fraction of the arena whose background was rebuilt because a resting mouse had been
        /// absorbed into the temporal median (0 for ordinary recordings).
        let backgroundRepairedFraction: Double

        // Reused for every frame. Keeping these allocations alive for the whole session avoids
        // tens of thousands of short-lived arrays during long full-video analyses.
        private var diffBuffer: [UInt8]
        private var binaryA: [UInt8]
        private var binaryB: [UInt8]
        private var visitedBuffer: [UInt8]
        private var componentQueue: [Int]

        private var previous: CGPoint?
        private var previousArea: Double?

        // Frame-to-frame motion (for freezing analysis). Only arena pixels are copied/compared.
        private var previousFrameBuffer: [UInt8]
        private var hasPreviousFrame = false

        init(
            backgroundFrames: [GrayFrame],
            calibration: FlowArenaCalibration,
            arenaShape: FlowArenaShape,
            arenaWidthCM: Double,
            arenaHeightCM: Double,
            clipStartSeconds: Double,
            mazeArmWidthCM: Double = 10,
            tStartArmLengthCM: Double = 40,
            tChoiceArmLengthCM: Double = 30,
            yArmLengthCM: Double = 35,
            plusArmLengthCM: Double = 30,
            plusArmWidthCM: Double = 5,
            restoredState: SessionState? = nil,
            imagePointMapper: @escaping (CGPoint) -> CGPoint
        ) throws {
            guard let first = backgroundFrames.first, backgroundFrames.count >= 3 else {
                throw TrackerError.backgroundFailed
            }
            guard backgroundFrames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
                throw TrackerError.invalidFrames
            }

            self.arenaWidthCM = arenaWidthCM
            self.arenaHeightCM = arenaHeightCM
            self.clipStartSeconds = clipStartSeconds
            self.diagonal = hypot(Double(first.width), Double(first.height))
            self.imagePointMapper = imagePointMapper

            let computedMask: [Bool]
            let computedMapper: ArenaMapper
            switch arenaShape {
            case .rectangle:
                let polygon = calibration.corners.map {
                    CGPoint(x: $0.x * Double(first.width - 1), y: $0.y * Double(first.height - 1))
                }
                computedMask = FlowNativeMouseTracker.polygonMask(width: first.width, height: first.height, polygon: polygon)
                computedMapper = .rectangle(try Homography(source: polygon), widthCM: arenaWidthCM, heightCM: arenaHeightCM)

            case .circle:
                let center = CGPoint(
                    x: calibration.circleCenter.x * Double(first.width - 1),
                    y: calibration.circleCenter.y * Double(first.height - 1)
                )
                let edge = CGPoint(
                    x: calibration.circleEdge.x * Double(first.width - 1),
                    y: calibration.circleEdge.y * Double(first.height - 1)
                )
                let radius = hypot(edge.x - center.x, edge.y - center.y)
                guard radius >= 8 else { throw TrackerError.arenaTooSmall }
                computedMask = FlowNativeMouseTracker.circleMask(width: first.width, height: first.height, center: center, radius: radius)
                computedMapper = .circle(center: center, radius: radius, diameterCM: arenaWidthCM)

            case .tMaze:
                let p = calibration.tPoints.map { CGPoint(x: $0.x * Double(first.width - 1), y: $0.y * Double(first.height - 1)) }
                let j = p[0], start = p[1], left = p[2], right = p[3]
                let arms = [
                    MazeArm(imageStart: j, imageEnd: start, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: 0, y: tStartArmLengthCM), widthCM: mazeArmWidthCM, zone: "start"),
                    MazeArm(imageStart: j, imageEnd: left, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: -tChoiceArmLengthCM, y: 0), widthCM: mazeArmWidthCM, zone: "left"),
                    MazeArm(imageStart: j, imageEnd: right, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: tChoiceArmLengthCM, y: 0), widthCM: mazeArmWidthCM, zone: "right")
                ]
                computedMask = FlowNativeMouseTracker.mazeMask(width: first.width, height: first.height, arms: arms)
                computedMapper = .maze(MazeGeometry(arms: arms, paddingCM: mazeArmWidthCM / 2, centerRadiusCM: mazeArmWidthCM * 1.10))

            case .yMaze:
                let p = calibration.yPoints.map { CGPoint(x: $0.x * Double(first.width - 1), y: $0.y * Double(first.height - 1)) }
                let j = p[0], a = p[1], b = p[2], c = p[3]
                let h = sqrt(3.0) / 2.0 * yArmLengthCM
                let arms = [
                    MazeArm(imageStart: j, imageEnd: a, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: 0, y: -yArmLengthCM), widthCM: mazeArmWidthCM, zone: "A"),
                    MazeArm(imageStart: j, imageEnd: b, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: -h, y: yArmLengthCM / 2), widthCM: mazeArmWidthCM, zone: "B"),
                    MazeArm(imageStart: j, imageEnd: c, physicalStart: CGPoint(x: 0, y: 0), physicalEnd: CGPoint(x: h, y: yArmLengthCM / 2), widthCM: mazeArmWidthCM, zone: "C")
                ]
                computedMask = FlowNativeMouseTracker.mazeMask(width: first.width, height: first.height, arms: arms)
                computedMapper = .maze(MazeGeometry(arms: arms, paddingCM: mazeArmWidthCM / 2, centerRadiusCM: mazeArmWidthCM * 1.10))

            case .plusMaze:
                // Arm length is entered excluding the central square; the physical frame runs from the
                // maze center to each arm end, so add half the arm width.
                let p = calibration.plusPoints.map { CGPoint(x: $0.x * Double(first.width - 1), y: $0.y * Double(first.height - 1)) }
                let c = p[0], n = p[1], e = p[2], s = p[3], w = p[4]
                let reach = plusArmLengthCM + plusArmWidthCM / 2
                let origin = CGPoint(x: 0, y: 0)
                let arms = [
                    MazeArm(imageStart: c, imageEnd: n, physicalStart: origin, physicalEnd: CGPoint(x: 0, y: -reach), widthCM: plusArmWidthCM, zone: "N"),
                    MazeArm(imageStart: c, imageEnd: e, physicalStart: origin, physicalEnd: CGPoint(x: reach, y: 0), widthCM: plusArmWidthCM, zone: "E"),
                    MazeArm(imageStart: c, imageEnd: s, physicalStart: origin, physicalEnd: CGPoint(x: 0, y: reach), widthCM: plusArmWidthCM, zone: "S"),
                    MazeArm(imageStart: c, imageEnd: w, physicalStart: origin, physicalEnd: CGPoint(x: -reach, y: 0), widthCM: plusArmWidthCM, zone: "W")
                ]
                computedMask = FlowNativeMouseTracker.mazeMask(width: first.width, height: first.height, arms: arms)
                computedMapper = .maze(MazeGeometry(arms: arms, paddingCM: plusArmWidthCM / 2, centerRadiusCM: plusArmWidthCM * 0.5 + 0.5))
            }

            var activeIndices: [Int] = []
            activeIndices.reserveCapacity(computedMask.count / 2)
            var minX = first.width
            var minY = first.height
            var maxX = 0
            var maxY = 0
            for idx in computedMask.indices where computedMask[idx] {
                activeIndices.append(idx)
                let x = idx % first.width
                let y = idx / first.width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }

            let computedArea = max(1, activeIndices.count)
            let minimumArenaFraction = arenaShape.isMaze ? 0.01 : 0.05
            guard Double(computedArea) > Double(first.width * first.height) * minimumArenaFraction else {
                throw TrackerError.arenaTooSmall
            }

            // Two majority-filter passes can expand a component by at most two pixels beyond
            // the calibrated arena. Scan only that padded region instead of the entire frame.
            let padding = 2
            let bounds = (
                minX: max(0, minX - padding),
                maxX: min(first.width - 1, maxX + padding),
                minY: max(0, minY - padding),
                maxY: min(first.height - 1, maxY + padding)
            )

            self.arenaIndices = activeIndices
            self.processingBounds = bounds
            self.mapper = computedMapper
            self.arenaArea = computedArea
            let robust = FlowNativeMouseTracker.residentRobustBackground(
                backgroundFrames,
                arenaIndices: activeIndices,
                arenaArea: computedArea,
                bounds: bounds
            )
            self.background = robust.background
            self.backgroundRepairedFraction = Double(robust.repairedPixels) / Double(computedArea)

            let pixelCount = first.width * first.height
            self.diffBuffer = [UInt8](repeating: 0, count: pixelCount)
            self.binaryA = [UInt8](repeating: 0, count: pixelCount)
            self.binaryB = [UInt8](repeating: 0, count: pixelCount)
            self.visitedBuffer = [UInt8](repeating: 0, count: pixelCount)
            self.componentQueue = []
            self.componentQueue.reserveCapacity(min(pixelCount, max(4096, computedArea)))
            self.previousFrameBuffer = [UInt8](repeating: 0, count: pixelCount)

            if let restoredState,
               let x = restoredState.previousX,
               let y = restoredState.previousY {
                self.previous = CGPoint(x: x, y: y)
                self.previousArea = restoredState.previousArea
            } else {
                self.previous = nil
                self.previousArea = restoredState?.previousArea
            }
        }

        /// Converts a calibration marker (normalized raw-frame coordinates) to arena centimeters
        /// using exactly the same mapping as the tracked centroid.
        func arenaPoint(rawNormalized p: FlowPoint) -> FlowArenaPoint {
            let pt = CGPoint(x: p.x * Double(background.width - 1), y: p.y * Double(background.height - 1))
            let mapped = mapper.map(pt)
            return FlowArenaPoint(x: mapped.xCM, y: mapped.yCM)
        }

        func checkpointState() -> SessionState {
            SessionState(
                previousX: previous.map { Double($0.x) },
                previousY: previous.map { Double($0.y) },
                previousArea: previousArea
            )
        }

        func process(frame: GrayFrame, frameIndex: Int, timestamp: Double) throws -> FlowTrackingPoint {
            guard frame.width == background.width, frame.height == background.height else {
                throw TrackerError.invalidFrames
            }

            FlowNativeMouseTracker.absoluteDifference(
                frame.pixels,
                background.pixels,
                indices: arenaIndices,
                into: &diffBuffer
            )
            let threshold = FlowNativeMouseTracker.adaptiveThreshold(diffBuffer, indices: arenaIndices)

            FlowNativeMouseTracker.clearBinary(&binaryA, width: frame.width, bounds: processingBounds)
            for idx in arenaIndices {
                binaryA[idx] = diffBuffer[idx] >= threshold ? 1 : 0
            }

            // Same two light majority-filter passes as V0.1, but limited to the arena ROI.
            FlowNativeMouseTracker.majorityFilter(
                binaryA,
                output: &binaryB,
                width: frame.width,
                height: frame.height,
                bounds: processingBounds,
                minimumNeighbors: 3
            )
            FlowNativeMouseTracker.majorityFilter(
                binaryB,
                output: &binaryA,
                width: frame.width,
                height: frame.height,
                bounds: processingBounds,
                minimumNeighbors: 2
            )

            let components = FlowNativeMouseTracker.connectedComponents(
                binary: binaryA,
                diff: diffBuffer,
                width: frame.width,
                height: frame.height,
                arenaArea: arenaArea,
                bounds: processingBounds,
                visited: &visitedBuffer,
                queue: &componentQueue
            )

            var best: Component?
            var bestScore = -Double.infinity
            var bestConfidence = 0.0

            for candidate in components {
                let areaRatio = Double(candidate.area) / Double(arenaArea)
                guard areaRatio >= 0.0007 && areaRatio <= 0.14 else { continue }

                let logRatio = log(max(areaRatio, 1e-6) / 0.012)
                let areaScore = exp(-(logRatio * logRatio) / 2.0)

                let motionScore: Double
                if let previous {
                    let d = hypot(candidate.x - previous.x, candidate.y - previous.y)
                    motionScore = exp(-d / max(1.0, diagonal * 0.16))
                } else {
                    motionScore = 1
                }

                let sizeScore: Double
                if let previousArea {
                    sizeScore = exp(-abs(log(max(1.0, Double(candidate.area)) / previousArea)))
                } else {
                    sizeScore = 1
                }

                let contrastScore = FlowNativeMouseTracker.clamp01((candidate.meanDiff - Double(threshold) + 10) / 55)
                let fill = Double(candidate.area) / Double(max(1, candidate.width * candidate.height))
                let fillScore = FlowNativeMouseTracker.clamp01(fill / 0.45)

                let score = 0.27 * areaScore + 0.28 * motionScore + 0.17 * sizeScore + 0.20 * contrastScore + 0.08 * fillScore
                if score > bestScore {
                    bestScore = score
                    best = candidate
                    bestConfidence = FlowNativeMouseTracker.clamp01(0.30 * motionScore + 0.25 * areaScore + 0.30 * contrastScore + 0.15 * sizeScore)
                }
            }

            // Centroid of the selected mouse blob (contrast-weighted, see connectedComponents).
            let detected = best.map { CGPoint(x: $0.x, y: $0.y) }

            let final: CGPoint
            let interpolated: Bool

            if let detected {
                if let previous {
                    // Mild smoothing only. Enough to reduce single-pixel jitter without hiding movement.
                    final = CGPoint(
                        x: 0.90 * detected.x + 0.10 * previous.x,
                        y: 0.90 * detected.y + 0.10 * previous.y
                    )
                } else {
                    final = detected
                }
                previous = final
                previousArea = best.map { Double($0.area) }
                interpolated = false
            } else if let previous {
                final = previous
                bestConfidence = 0.08
                interpolated = true
            } else {
                final = CGPoint(x: Double(frame.width) / 2, y: Double(frame.height) / 2)
                bestConfidence = 0
                interpolated = true
            }

            let arena = mapper.map(final)
            let displayNormalized = imagePointMapper(final)

            // Motion index: fraction of arena pixels whose gray level changed by at least
            // `motionPixelThreshold` since the previous analyzed (10 Hz) frame. Independent of blob
            // detection, so a perfectly still mouse that blends into the background still scores ~0.
            let pixels = frame.pixels
            var changed = 0
            if hasPreviousFrame {
                let threshold = FlowNativeMouseTracker.motionPixelThreshold
                for idx in arenaIndices {
                    let d = Int(pixels[idx]) - Int(previousFrameBuffer[idx])
                    if d >= threshold || d <= -threshold { changed += 1 }
                }
            }
            for idx in arenaIndices { previousFrameBuffer[idx] = pixels[idx] }
            let motion: Double? = hasPreviousFrame ? Double(changed) / Double(arenaArea) : nil
            hasPreviousFrame = true
            let blobFraction: Double? = best.map { Double($0.area) / Double(arenaArea) }

            return FlowTrackingPoint(
                frameIndex: frameIndex,
                clipTimeSeconds: max(0, timestamp - clipStartSeconds),
                videoTimeSeconds: timestamp,
                imageXNormalized: FlowNativeMouseTracker.clamp01(displayNormalized.x),
                imageYNormalized: FlowNativeMouseTracker.clamp01(displayNormalized.y),
                arenaXNormalized: FlowNativeMouseTracker.clamp01(arena.normalized.x),
                arenaYNormalized: FlowNativeMouseTracker.clamp01(arena.normalized.y),
                xCentimeters: arena.xCM,
                yCentimeters: arena.yCM,
                confidence: bestConfidence,
                interpolated: interpolated,
                zone: arena.zone,
                motionIndex: motion,
                blobAreaFraction: blobFraction
            )
        }
    }

    static func track(_ input: Input) throws -> [FlowTrackingPoint] {
        guard input.frames.count >= 2, input.frames.count == input.timestamps.count else {
            throw TrackerError.invalidFrames
        }

        let first = try grayscale(input.frames[0], maxDimension: 192)
        let targetWidth = first.width
        let targetHeight = first.height

        let bgSource = input.backgroundFrames.count >= 5 ? input.backgroundFrames : input.frames
        var grays: [GrayFrame] = []
        grays.reserveCapacity(min(bgSource.count, 21))
        let step = max(1, bgSource.count / 21)
        var i = 0
        while i < bgSource.count && grays.count < 21 {
            grays.append(try grayscale(bgSource[i], exactWidth: targetWidth, exactHeight: targetHeight))
            i += step
        }
        guard grays.count >= 3 else { throw TrackerError.backgroundFailed }

        let session = try Session(
            backgroundFrames: grays,
            calibration: input.calibration,
            arenaShape: input.arenaShape,
            arenaWidthCM: input.arenaWidthCM,
            arenaHeightCM: input.arenaHeightCM,
            clipStartSeconds: input.clipStartSeconds,
            imagePointMapper: { point in
                CGPoint(
                    x: point.x / Double(max(1, targetWidth - 1)),
                    y: point.y / Double(max(1, targetHeight - 1))
                )
            }
        )

        var output: [FlowTrackingPoint] = []
        output.reserveCapacity(input.frames.count)
        for (frameIndex, image) in input.frames.enumerated() {
            let frame = try grayscale(image, exactWidth: targetWidth, exactHeight: targetHeight)
            output.append(try session.process(frame: frame, frameIndex: frameIndex, timestamp: input.timestamps[frameIndex]))
        }

        guard output.contains(where: { !$0.interpolated }) else { throw TrackerError.noMouseFound }
        return output
    }

    static func grayscale(_ image: NSImage, maxDimension: Int) throws -> GrayFrame {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw TrackerError.imageDecodeFailed }
        let maxSide = max(cg.width, cg.height)
        let scale = min(1.0, Double(maxDimension) / Double(maxSide))
        return try grayscale(
            image,
            exactWidth: max(8, Int((Double(cg.width) * scale).rounded())),
            exactHeight: max(8, Int((Double(cg.height) * scale).rounded()))
        )
    }

    static func grayscale(_ image: NSImage, exactWidth width: Int, exactHeight height: Int) throws -> GrayFrame {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw TrackerError.imageDecodeFailed }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw TrackerError.imageDecodeFailed }

        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayFrame(width: width, height: height, pixels: pixels)
    }

    /// Fast path for AVAssetReader output. If the reader returns bi-planar YCbCr,
    /// the Y plane already is the grayscale signal we need for foreground tracking.
    static func grayscale(_ pixelBuffer: CVPixelBuffer) throws -> GrayFrame {
        let width: Int
        let height: Int
        if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        } else {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
        }
        var frame = GrayFrame(width: width, height: height, pixels: [UInt8](repeating: 0, count: width * height))
        try fillGrayscale(pixelBuffer, into: &frame)
        return frame
    }

    /// Reuses an existing grayscale allocation. Full-video analysis calls this for each selected
    /// 10 Hz frame so the per-frame image buffer is not repeatedly allocated and released.
    static func fillGrayscale(_ pixelBuffer: CVPixelBuffer, into frame: inout GrayFrame) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            guard width == frame.width, height == frame.height else { throw TrackerError.invalidFrames }
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
                throw TrackerError.imageDecodeFailed
            }
            let source = base.assumingMemoryBound(to: UInt8.self)
            let videoRange = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            frame.pixels.withUnsafeMutableBytes { destinationBytes in
                guard let destination = destinationBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                if videoRange {
                    let lut = FlowNativeMouseTracker.videoToFullRange
                    for y in 0..<height {
                        let row = source + y * bytesPerRow
                        let out = destination + y * width
                        for x in 0..<width { out[x] = lut[Int(row[x])] }
                    }
                } else {
                    for y in 0..<height {
                        memcpy(destination + y * width, source + y * bytesPerRow, width)
                    }
                }
            }
            return
        }

        // BGRA fallback for unusual decoders.
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width == frame.width, height == frame.height else { throw TrackerError.invalidFrames }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { throw TrackerError.imageDecodeFailed }
        let source = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let row = source + y * bytesPerRow
            let outputBase = y * width
            for x in 0..<width {
                let b = Int(row[x * 4])
                let g = Int(row[x * 4 + 1])
                let r = Int(row[x * 4 + 2])
                frame.pixels[outputBase + x] = UInt8((29 * b + 150 * g + 77 * r) >> 8)
            }
        }
    }

    private struct SampleBlob {
        let pixels: [Int]
        let signedMean: Double
    }

    /// Temporal-median background with a repair for a mouse that rested at one spot in most of
    /// the sampled frames (long closed-arm sitting in the plus maze, long freezing in one corner,
    /// a long stay on the platform). Such a mouse becomes part of the median, and wherever it is
    /// later the empty floor at that spot appears as a stationary "ghost" blob that can be
    /// tracked instead of the mouse.
    ///
    /// A ghost is recognised in the sample frames themselves: a foreground region that recurs
    /// at the same place in at least two frames, each time together with a second blob of the
    /// opposite polarity (the real mouse somewhere else, darker/brighter than the floor while the
    /// ghost is the reverse). In exactly those frames the region shows the empty floor, so the
    /// background there is replaced by their per-pixel median. Ordinary recordings, where no spot
    /// is occupied in most samples, produce no such pattern and keep the plain median.
    static func residentRobustBackground(
        _ frames: [GrayFrame],
        arenaIndices: [Int],
        arenaArea: Int,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
    ) -> (background: GrayFrame, repairedPixels: Int) {
        var background = temporalMedian(frames)
        guard frames.count >= 5, !arenaIndices.isEmpty else { return (background, 0) }
        let width = background.width
        let height = background.height
        let pixelCount = width * height
        var inArena = [Bool](repeating: false, count: pixelCount)
        for idx in arenaIndices { inArena[idx] = true }
        let minArea = max(6, Int(Double(arenaArea) * 0.0007))
        let maxArea = Int(Double(arenaArea) * 0.14)

        var diff = [UInt8](repeating: 0, count: pixelCount)
        var binaryA = [UInt8](repeating: 0, count: pixelCount)
        var binaryB = [UInt8](repeating: 0, count: pixelCount)
        var label = [Int32](repeating: -1, count: pixelCount)
        var repaired = Set<Int>()

        for _ in 0..<2 {
            // Foreground blobs of every sample frame against the current background.
            var blobs: [[SampleBlob]] = []
            var labels: [[Int32]] = []
            for frame in frames {
                absoluteDifference(frame.pixels, background.pixels, indices: arenaIndices, into: &diff)
                let threshold = max(UInt8(20), adaptiveThreshold(diff, indices: arenaIndices))
                clearBinary(&binaryA, width: width, bounds: bounds)
                for idx in arenaIndices { binaryA[idx] = diff[idx] >= threshold ? 1 : 0 }
                majorityFilter(binaryA, output: &binaryB, width: width, height: height, bounds: bounds, minimumNeighbors: 3)
                majorityFilter(binaryB, output: &binaryA, width: width, height: height, bounds: bounds, minimumNeighbors: 2)

                for i in label.indices { label[i] = -1 }
                var frameBlobs: [SampleBlob] = []
                for y in bounds.minY...bounds.maxY {
                    for x in bounds.minX...bounds.maxX {
                        let seed = y * width + x
                        guard binaryA[seed] != 0, label[seed] == -1 else { continue }
                        var queue = [seed]
                        label[seed] = -2
                        var head = 0
                        while head < queue.count {
                            let idx = queue[head]
                            head += 1
                            let px = idx % width, py = idx / width
                            for ny in max(bounds.minY, py - 1)...min(bounds.maxY, py + 1) {
                                for nx in max(bounds.minX, px - 1)...min(bounds.maxX, px + 1) {
                                    let next = ny * width + nx
                                    if binaryA[next] != 0 && label[next] == -1 {
                                        label[next] = -2
                                        queue.append(next)
                                    }
                                }
                            }
                        }
                        guard queue.count >= minArea && queue.count <= maxArea else { continue }
                        var signed = 0.0
                        for idx in queue {
                            label[idx] = Int32(frameBlobs.count)
                            signed += Double(Int(frame.pixels[idx]) - Int(background.pixels[idx]))
                        }
                        frameBlobs.append(SampleBlob(pixels: queue, signedMean: signed / Double(queue.count)))
                    }
                }
                blobs.append(frameBlobs)
                labels.append(label)
            }

            // Ghost groups: same place in ≥ 2 frames, same polarity, each time with an
            // opposite-polarity companion blob in the same frame.
            var used = Set<String>()
            var groups: [(pixels: Set<Int>, members: [(frame: Int, blob: Int)])] = []
            for k in frames.indices where blobs[k].count >= 2 {
                for (b, blob) in blobs[k].enumerated() where !used.contains("\(k):\(b)") {
                    let sign = blob.signedMean >= 0
                    func hasCompanion(_ frameIndex: Int, excluding blobIndex: Int) -> Bool {
                        blobs[frameIndex].enumerated().contains { $0.offset != blobIndex && ($0.element.signedMean >= 0) != sign }
                    }
                    guard hasCompanion(k, excluding: b) else { continue }
                    var members: [(Int, Int)] = [(k, b)]
                    for j in frames.indices where j != k {
                        var overlap: [Int32: Int] = [:]
                        for idx in blob.pixels where labels[j][idx] >= 0 { overlap[labels[j][idx], default: 0] += 1 }
                        guard let best = overlap.max(by: { $0.value < $1.value }) else { continue }
                        let other = blobs[j][Int(best.key)]
                        let needed = Double(min(blob.pixels.count, other.pixels.count)) * 0.5
                        guard Double(best.value) >= needed, (other.signedMean >= 0) == sign,
                              hasCompanion(j, excluding: Int(best.key)) else { continue }
                        members.append((j, Int(best.key)))
                    }
                    guard members.count >= 2 else { continue }
                    var pixels = Set<Int>()
                    for (j, m) in members {
                        used.insert("\(j):\(m)")
                        pixels.formUnion(blobs[j][m].pixels)
                    }
                    groups.append((pixels, members.map { (frame: $0.0, blob: $0.1) }))
                }
            }
            guard !groups.isEmpty else { break }

            var changed = false
            for group in groups {
                // Two-pixel margin so the blurred edge of the absorbed mouse is replaced too.
                func dilate(_ source: Set<Int>, by r: Int) -> Set<Int> {
                    var out = Set<Int>()
                    for idx in source {
                        let px = idx % width, py = idx / width
                        for ny in max(0, py - r)...min(height - 1, py + r) {
                            for nx in max(0, px - r)...min(width - 1, px + r) where inArena[ny * width + nx] {
                                out.insert(ny * width + nx)
                            }
                        }
                    }
                    return out
                }
                let region = dilate(group.pixels, by: 2)
                let ring = dilate(group.pixels, by: 5).subtracting(region)
                guard !ring.isEmpty else { continue }

                // Confirm it really is a ghost: in each frame the blob's background must stand out
                // from the surrounding floor while the frame itself blends in with it. A real mouse
                // that merely rested there in a few samples is the reverse (frame stands out).
                func median(_ v: [Int]) -> Double {
                    let s = v.sorted()
                    return s.isEmpty ? 0 : Double(s[s.count / 2])
                }
                let ringLevel = median(ring.map { Int(background.pixels[$0]) })
                let ghostLike = group.members.filter { member in
                    // Only pixels that really differ (the cleanup filters also add a rim of
                    // unchanged pixels around every blob).
                    let frame = frames[member.frame].pixels
                    let px = blobs[member.frame][member.blob].pixels.filter {
                        abs(Int(frame[$0]) - Int(background.pixels[$0])) >= 20
                    }
                    guard px.count >= 3 else { return false }
                    let backgroundContrast = abs(median(px.map { Int(background.pixels[$0]) }) - ringLevel)
                    let frameContrast = abs(median(px.map { Int(frames[member.frame].pixels[$0]) }) - ringLevel)
                    return backgroundContrast >= 10 && frameContrast < 0.5 * backgroundContrast
                }
                guard ghostLike.count >= 2, Double(ghostLike.count) >= 0.67 * Double(group.members.count) else { continue }
                let floorFrames = Array(Set(ghostLike.map(\.frame))).sorted()

                changed = true
                var values = [UInt8](repeating: 0, count: floorFrames.count)
                for idx in region {
                    for (n, j) in floorFrames.enumerated() { values[n] = frames[j].pixels[idx] }
                    values.sort()
                    let mid = values.count / 2
                    background.pixels[idx] = values.count % 2 == 1
                        ? values[mid]
                        : UInt8((Int(values[mid - 1]) + Int(values[mid]) + 1) / 2)
                    repaired.insert(idx)
                }
            }
            if !changed { break }
        }
        return (background, repaired.count)
    }

    private static func temporalMedian(_ frames: [GrayFrame]) -> GrayFrame {
        let width = frames[0].width
        let height = frames[0].height
        var out = [UInt8](repeating: 0, count: width * height)
        var values = [UInt8](repeating: 0, count: frames.count)
        for idx in out.indices {
            for j in frames.indices { values[j] = frames[j].pixels[idx] }
            values.sort()
            out[idx] = values[values.count / 2]
        }
        return GrayFrame(width: width, height: height, pixels: out)
    }

    private static func absoluteDifference(
        _ a: [UInt8],
        _ b: [UInt8],
        indices: [Int],
        into output: inout [UInt8]
    ) {
        for i in indices {
            output[i] = UInt8(abs(Int(a[i]) - Int(b[i])))
        }
    }

    private static func adaptiveThreshold(_ values: [UInt8], indices: [Int]) -> UInt8 {
        var sum = 0.0
        var sum2 = 0.0
        let n = Double(indices.count)
        guard n > 0 else { return 24 }
        for i in indices {
            let v = Double(values[i])
            sum += v
            sum2 += v * v
        }
        let mean = sum / n
        let variance = max(0, sum2 / n - mean * mean)
        let threshold = mean + 1.75 * sqrt(variance)
        return UInt8(max(14, min(48, Int(threshold.rounded()))))
    }

    private static func clearBinary(
        _ buffer: inout [UInt8],
        width: Int,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)
    ) {
        for y in bounds.minY...bounds.maxY {
            let base = y * width
            for x in bounds.minX...bounds.maxX {
                buffer[base + x] = 0
            }
        }
    }

    /// Same 3x3 majority rule as V0.1, implemented into a reusable UInt8 buffer and restricted
    /// to the padded arena bounds. Pixels outside the bounds are never candidates for tracking.
    private static func majorityFilter(
        _ input: [UInt8],
        output: inout [UInt8],
        width: Int,
        height: Int,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int),
        minimumNeighbors: Int
    ) {
        guard width > 0, height > 0 else { return }

        // Preserve the original value at image-border pixels, matching the old implementation.
        for y in bounds.minY...bounds.maxY {
            let base = y * width
            for x in bounds.minX...bounds.maxX {
                output[base + x] = input[base + x]
            }
        }

        guard width > 2, height > 2 else { return }
        let minY = max(1, bounds.minY)
        let maxY = min(height - 2, bounds.maxY)
        let minX = max(1, bounds.minX)
        let maxX = min(width - 2, bounds.maxX)
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                var count = 0
                for yy in (y - 1)...(y + 1) {
                    let base = yy * width
                    for xx in (x - 1)...(x + 1) where input[base + xx] != 0 {
                        count += 1
                    }
                }
                output[y * width + x] = count >= minimumNeighbors ? 1 : 0
            }
        }
    }

    private static func connectedComponents(
        binary: [UInt8],
        diff: [UInt8],
        width: Int,
        height: Int,
        arenaArea: Int,
        bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int),
        visited: inout [UInt8],
        queue: inout [Int]
    ) -> [Component] {
        var components: [Component] = []
        let minArea = max(6, Int(Double(arenaArea) * 0.0005))
        let maxArea = Int(Double(arenaArea) * 0.16)

        // Reuse the visited allocation; clear only the region that can contain foreground.
        for y in bounds.minY...bounds.maxY {
            let base = y * width
            for x in bounds.minX...bounds.maxX {
                visited[base + x] = 0
            }
        }

        for y in bounds.minY...bounds.maxY {
            let base = y * width
            for x in bounds.minX...bounds.maxX {
                let seed = base + x
                guard binary[seed] != 0, visited[seed] == 0 else { continue }

                queue.removeAll(keepingCapacity: true)
                queue.append(seed)
                visited[seed] = 1
                var head = 0
                var area = 0
                var sumX = 0.0
                var sumY = 0.0
                var sumDiff = 0.0
                var minComponentX = width
                var minComponentY = height
                var maxComponentX = 0
                var maxComponentY = 0

                while head < queue.count {
                    let idx = queue[head]
                    head += 1
                    let px = idx % width
                    let py = idx / width
                    area += 1
                    // Contrast-weighted centroid: partially covered edge pixels (and the thin tail,
                    // which flickers in and out of the binary mask at analysis resolution) count
                    // in proportion to how much mouse they actually contain.
                    let weight = Double(diff[idx])
                    sumX += Double(px) * weight
                    sumY += Double(py) * weight
                    sumDiff += weight
                    minComponentX = min(minComponentX, px)
                    maxComponentX = max(maxComponentX, px)
                    minComponentY = min(minComponentY, py)
                    maxComponentY = max(maxComponentY, py)
                    if area > maxArea { break }

                    let neighborMinY = max(bounds.minY, py - 1)
                    let neighborMaxY = min(bounds.maxY, py + 1)
                    let neighborMinX = max(bounds.minX, px - 1)
                    let neighborMaxX = min(bounds.maxX, px + 1)
                    for ny in neighborMinY...neighborMaxY {
                        let neighborBase = ny * width
                        for nx in neighborMinX...neighborMaxX where !(nx == px && ny == py) {
                            let next = neighborBase + nx
                            if binary[next] != 0 && visited[next] == 0 {
                                visited[next] = 1
                                queue.append(next)
                            }
                        }
                    }
                }

                if area >= minArea && area <= maxArea {
                    components.append(Component(
                        area: area,
                        x: sumX / max(1, sumDiff),
                        y: sumY / max(1, sumDiff),
                        meanDiff: sumDiff / Double(area),
                        width: max(1, maxComponentX - minComponentX + 1),
                        height: max(1, maxComponentY - minComponentY + 1)
                    ))
                }
            }
        }
        return components
    }

    private static func circleMask(width: Int, height: Int, center: CGPoint, radius: Double) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        let r2 = radius * radius
        for y in 0..<height {
            let dy = (Double(y) + 0.5) - center.y
            for x in 0..<width {
                let dx = (Double(x) + 0.5) - center.x
                mask[y * width + x] = dx * dx + dy * dy <= r2
            }
        }
        return mask
    }

    private static func mazeMask(width: Int, height: Int, arms: [MazeArm]) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        guard !arms.isEmpty else { return mask }
        for y in 0..<height {
            for x in 0..<width {
                let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                var inside = false
                for arm in arms {
                    let projection = arm.projection(of: p)
                    if projection.distancePixels <= arm.halfWidthPixels * 1.08 {
                        inside = true
                        break
                    }
                }
                mask[y * width + x] = inside
            }
        }
        return mask
    }

    private static func polygonMask(width: Int, height: Int, polygon: [CGPoint]) -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                mask[y * width + x] = contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), polygon: polygon)
            }
        }
        return mask
    }

    private static func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i], pj = polygon[j]
            let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
                (point.x < (pj.x - pi.x) * (point.y - pi.y) / ((pj.y - pi.y) == 0 ? 1e-9 : (pj.y - pi.y)) + pi.x)
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func clamp01(_ x: Double) -> Double { max(0, min(1, x)) }

    enum TrackerError: LocalizedError {
        case invalidFrames, backgroundFailed, imageDecodeFailed, arenaTooSmall, noMouseFound
        var errorDescription: String? {
            switch self {
            case .invalidFrames: return flowLoc("The video frames could not be prepared.")
            case .backgroundFailed: return flowLoc("Not enough frames were available to estimate the empty arena background.")
            case .imageDecodeFailed: return flowLoc("A video frame could not be decoded for tracking.")
            case .arenaTooSmall: return flowLoc("The arena calibration defines an area that is too small.")
            case .noMouseFound: return flowLoc("No reliable mouse foreground was found. Try another 10-second preview or adjust the arena calibration.")
            }
        }
    }

    private struct MappedArenaPoint {
        let normalized: CGPoint
        let xCM: Double
        let yCM: Double
        let zone: String
    }

    private struct MazeArm {
        let imageStart: CGPoint
        let imageEnd: CGPoint
        let physicalStart: CGPoint
        let physicalEnd: CGPoint
        let widthCM: Double
        let zone: String

        var imageLength: Double { hypot(imageEnd.x - imageStart.x, imageEnd.y - imageStart.y) }
        var physicalLength: Double { hypot(physicalEnd.x - physicalStart.x, physicalEnd.y - physicalStart.y) }
        var halfWidthPixels: Double {
            guard physicalLength > 0 else { return 4 }
            return max(3, (widthCM / 2) * imageLength / physicalLength)
        }

        func projection(of point: CGPoint) -> (t: Double, distancePixels: Double, signedPerpPixels: Double) {
            let vx = imageEnd.x - imageStart.x
            let vy = imageEnd.y - imageStart.y
            let len2 = max(1e-9, vx * vx + vy * vy)
            let wx = point.x - imageStart.x
            let wy = point.y - imageStart.y
            let tRaw = (wx * vx + wy * vy) / len2
            let t = max(0, min(1, tRaw))
            let px = imageStart.x + t * vx
            let py = imageStart.y + t * vy
            let dx = point.x - px
            let dy = point.y - py
            let imageLen = sqrt(len2)
            let signed = imageLen > 0 ? (-vy * dx + vx * dy) / imageLen : 0
            return (t, hypot(dx, dy), signed)
        }

        func physicalPoint(t: Double, signedPerpPixels: Double) -> CGPoint {
            let vx = physicalEnd.x - physicalStart.x
            let vy = physicalEnd.y - physicalStart.y
            let len = max(1e-9, hypot(vx, vy))
            let cx = physicalStart.x + t * vx
            let cy = physicalStart.y + t * vy
            let pixelsPerCM = max(1e-9, imageLength / len)
            let perpCM = signedPerpPixels / pixelsPerCM
            let nx = -vy / len
            let ny = vx / len
            return CGPoint(x: cx + nx * perpCM, y: cy + ny * perpCM)
        }
    }

    private struct MazeGeometry {
        let arms: [MazeArm]
        let paddingCM: Double
        let centerRadiusCM: Double

        private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
            let xs = arms.flatMap { [Double($0.physicalStart.x), Double($0.physicalEnd.x)] }
            let ys = arms.flatMap { [Double($0.physicalStart.y), Double($0.physicalEnd.y)] }
            return (
                (xs.min() ?? 0) - paddingCM,
                (xs.max() ?? 1) + paddingCM,
                (ys.min() ?? 0) - paddingCM,
                (ys.max() ?? 1) + paddingCM
            )
        }

        func map(_ point: CGPoint) -> MappedArenaPoint {
            guard !arms.isEmpty else {
                return MappedArenaPoint(normalized: CGPoint(x: 0.5, y: 0.5), xCM: 0, yCM: 0, zone: "outside")
            }
            let ranked = arms.map { arm -> (MazeArm, (t: Double, distancePixels: Double, signedPerpPixels: Double), Double) in
                let p = arm.projection(of: point)
                let score = p.distancePixels / max(1, arm.halfWidthPixels)
                return (arm, p, score)
            }.sorted { $0.2 < $1.2 }

            let chosen = ranked[0]
            let physical = chosen.0.physicalPoint(t: chosen.1.t, signedPerpPixels: chosen.1.signedPerpPixels)
            let radialFromJunction = chosen.1.t * chosen.0.physicalLength
            let zone = radialFromJunction <= centerRadiusCM ? "center" : chosen.0.zone
            let b = bounds
            let width = max(1e-9, b.maxX - b.minX)
            let height = max(1e-9, b.maxY - b.minY)
            let nx = (Double(physical.x) - b.minX) / width
            let ny = (Double(physical.y) - b.minY) / height
            return MappedArenaPoint(
                normalized: CGPoint(x: nx, y: ny),
                xCM: Double(physical.x) - b.minX,
                yCM: Double(physical.y) - b.minY,
                zone: zone
            )
        }
    }

    private enum ArenaMapper {
        case rectangle(Homography, widthCM: Double, heightCM: Double)
        case circle(center: CGPoint, radius: Double, diameterCM: Double)
        case maze(MazeGeometry)

        func map(_ point: CGPoint) -> MappedArenaPoint {
            switch self {
            case .rectangle(let homography, let widthCM, let heightCM):
                let p = homography.map(point)
                return MappedArenaPoint(
                    normalized: p,
                    xCM: FlowNativeMouseTracker.clamp01(p.x) * widthCM,
                    yCM: FlowNativeMouseTracker.clamp01(p.y) * heightCM,
                    zone: "arena"
                )
            case .circle(let center, let radius, let diameterCM):
                guard radius > 0 else {
                    return MappedArenaPoint(normalized: CGPoint(x: 0.5, y: 0.5), xCM: diameterCM / 2, yCM: diameterCM / 2, zone: "arena")
                }
                let p = CGPoint(
                    x: 0.5 + (point.x - center.x) / (2 * radius),
                    y: 0.5 + (point.y - center.y) / (2 * radius)
                )
                return MappedArenaPoint(
                    normalized: p,
                    xCM: FlowNativeMouseTracker.clamp01(p.x) * diameterCM,
                    yCM: FlowNativeMouseTracker.clamp01(p.y) * diameterCM,
                    zone: "arena"
                )
            case .maze(let geometry):
                return geometry.map(point)
            }
        }
    }

    private struct Homography {
        let h: [Double]

        init(source p: [CGPoint]) throws {
            guard p.count == 4 else { throw TrackerError.arenaTooSmall }
            let destination = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            var a = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)

            for i in 0..<4 {
                let x = Double(p[i].x), y = Double(p[i].y)
                let u = Double(destination[i].x), v = Double(destination[i].y)
                let r = 2 * i
                a[r][0] = x; a[r][1] = y; a[r][2] = 1
                a[r][6] = -u * x; a[r][7] = -u * y; a[r][8] = u
                a[r + 1][3] = x; a[r + 1][4] = y; a[r + 1][5] = 1
                a[r + 1][6] = -v * x; a[r + 1][7] = -v * y; a[r + 1][8] = v
            }

            for col in 0..<8 {
                var pivot = col
                for row in col..<8 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
                guard abs(a[pivot][col]) > 1e-10 else { throw TrackerError.arenaTooSmall }
                if pivot != col { a.swapAt(pivot, col) }
                let divisor = a[col][col]
                for j in col..<9 { a[col][j] /= divisor }
                for row in 0..<8 where row != col {
                    let factor = a[row][col]
                    guard factor != 0 else { continue }
                    for j in col..<9 { a[row][j] -= factor * a[col][j] }
                }
            }
            h = (0..<8).map { a[$0][8] }
        }

        func map(_ p: CGPoint) -> CGPoint {
            let x = Double(p.x), y = Double(p.y)
            let d = h[6] * x + h[7] * y + 1
            guard abs(d) > 1e-10 else { return CGPoint(x: 0.5, y: 0.5) }
            return CGPoint(
                x: (h[0] * x + h[1] * y + h[2]) / d,
                y: (h[3] * x + h[4] * y + h[5]) / d
            )
        }
    }
}
