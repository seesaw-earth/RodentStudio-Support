// Ported from RodentFlow iOS 1.3; video algorithm preserved, UIImage switched to NSImage.
import Foundation
import AVFoundation
@preconcurrency import AppKit

struct FlowExtractedFrame: @unchecked Sendable {
    let image: NSImage
    let videoTimeSeconds: Double
}

struct FlowFrameExtractor {
    private struct SendableImage: @unchecked Sendable { let value: NSImage }
    private struct SendableImages: @unchecked Sendable { let value: [NSImage] }

    static func singleFrame(url: URL, at seconds: Double) async throws -> NSImage {
        let boxed = try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = makeGenerator(asset: asset)
            let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return SendableImage(value: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        }.value
        return boxed.value
    }

    static func previewFrames(
        url: URL,
        start: Double,
        duration: Double = 10,
        fps: Double = 10
    ) async throws -> [FlowExtractedFrame] {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = makeGenerator(asset: asset)
            let safeFPS = max(1, fps)
            let count = max(2, Int(floor(duration * safeFPS)))

            var result: [FlowExtractedFrame] = []
            result.reserveCapacity(count)

            for index in 0..<count {
                let relative = Double(index) / safeFPS
                let t = start + relative
                let time = CMTime(seconds: t, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    result.append(FlowExtractedFrame(image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)), videoTimeSeconds: t))
                }
            }
            return result
        }.value
    }

    static func sparseBackgroundFrames(
        url: URL,
        count: Int = 31,
        applyPreferredTransform: Bool = true,
        maxDimension: Int = 960
    ) async throws -> [NSImage] {
        let boxed = try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let durationTime = try await asset.load(.duration)
            let duration = durationTime.seconds
            let generator = makeGenerator(
                asset: asset,
                applyPreferredTransform: applyPreferredTransform,
                maxDimension: maxDimension
            )
            let n = max(5, count | 1) // keep odd for the median

            guard duration > 0 else { return SendableImages(value: []) }

            var images: [NSImage] = []
            images.reserveCapacity(n)

            // Avoid the first/last 1% where handling or camera start/stop artifacts are common.
            for index in 0..<n {
                let fraction = 0.01 + (0.98 * Double(index) / Double(max(1, n - 1)))
                let t = duration * fraction
                let time = CMTime(seconds: t, preferredTimescale: 600)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    images.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                }
            }
            return SendableImages(value: images)
        }.value
        return boxed.value
    }

    private static func makeGenerator(
        asset: AVAsset,
        applyPreferredTransform: Bool = true,
        maxDimension: Int = 960
    ) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = applyPreferredTransform
        let side = max(64, maxDimension)
        generator.maximumSize = CGSize(width: side, height: side)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        return generator
    }
}
