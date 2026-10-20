import AVFoundation
import Accelerate
import CoreGraphics
struct TSTVideoInfo: Sendable {
    let url: URL
    let duration: Double          // seconds
    let fps: Double               // nominal frame rate
    let encodedWidth: Int         // pixel buffer size as stored
    let encodedHeight: Int
    let quarterTurns: Int         // clockwise 90° turns needed for display orientation

    var orientedWidth: Int { quarterTurns % 2 == 0 ? encodedWidth : encodedHeight }
    var orientedHeight: Int { quarterTurns % 2 == 0 ? encodedHeight : encodedWidth }
}

enum TSTVideoError: LocalizedError {
    case noVideoTrack
    case cannotRead(String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return L("The file has no video track.", "该文件没有视频轨道。")
        case .cannotRead(let s): return L("Could not read the video: ", "无法读取视频：") + s
        case .noFrames: return L("No frames could be decoded in the selected time window.", "在所选时间窗内无法解码任何画面。")
        }
    }
}

/// Decodes video frames straight to 8-bit luma (the Y plane – no colour conversion), downscales with
/// vImage and rotates to display orientation. Sample frames and analysed frames go through exactly the
/// same path, so thresholds learned on samples apply to the analysis.
final class TSTVideoFrameReader: @unchecked Sendable {
    let info: TSTVideoInfo
    /// Size of the processed (oriented, downscaled) frames.
    let outWidth: Int
    let outHeight: Int
    // size of the downscaled frame before rotation
    private let scaledW: Int
    private let scaledH: Int

    init(info: TSTVideoInfo, processingWidth: Int) {
        self.info = info
        let target = min(processingWidth, info.orientedWidth)
        let scale = Double(target) / Double(info.orientedWidth)
        let sw = max(1, Int((Double(info.encodedWidth) * scale).rounded()))
        let sh = max(1, Int((Double(info.encodedHeight) * scale).rounded()))
        scaledW = sw; scaledH = sh
        outWidth = info.quarterTurns % 2 == 0 ? sw : sh
        outHeight = info.quarterTurns % 2 == 0 ? sh : sw
    }

    static func loadInfo(url: URL) async throws -> TSTVideoInfo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TSTVideoError.noVideoTrack }
        let (size, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let angle = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
        let q = ((Int((angle / 90).rounded()) % 4) + 4) % 4
        return TSTVideoInfo(url: url, duration: duration, fps: fps > 0 ? Double(fps) : 30,
                         encodedWidth: Int(size.width.rounded()), encodedHeight: Int(size.height.rounded()),
                         quarterTurns: q)
    }

    private func makeReader(start: Double, end: Double) async throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
        let asset = AVURLAsset(url: info.url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TSTVideoError.noVideoTrack }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw TSTVideoError.cannotRead(error.localizedDescription) }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw TSTVideoError.cannotRead("unsupported track") }
        reader.add(output)
        let s = CMTime(seconds: max(0, start), preferredTimescale: 600)
        let e = CMTime(seconds: max(start + 0.05, end), preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: s, end: e)
        guard reader.startReading() else {
            throw TSTVideoError.cannotRead(reader.error?.localizedDescription ?? "unknown error")
        }
        return (reader, output)
    }

    /// Luma plane → downscale → rotate.
    func grayImage(from sample: CMSampleBuffer) -> GrayImage? {
        guard let pb = CMSampleBufferGetImageBuffer(sample) else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        var src = vImage_Buffer(data: base,
                                height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(pb, 0)),
                                width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(pb, 0)),
                                rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pb, 0))
        var out = [UInt8](repeating: 0, count: scaledW * scaledH)
        let err = out.withUnsafeMutableBytes { ptr -> vImage_Error in
            var dst = vImage_Buffer(data: ptr.baseAddress, height: vImagePixelCount(scaledH),
                                    width: vImagePixelCount(scaledW), rowBytes: scaledW)
            return vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageNoFlags))
        }
        guard err == kvImageNoError else { return nil }
        return GrayImage(width: scaledW, height: scaledH, pixels: out).rotated(quarterTurns: info.quarterTurns)
    }

    /// One frame at (or just after) each requested time.
    func sampleFrames(at times: [Double]) async throws -> [GrayImage] {
        var frames: [GrayImage] = []
        for t in times {
            try Task.checkCancellation()
            let (reader, output) = try await makeReader(start: t, end: min(info.duration, t + 1.0))
            if let sb = output.copyNextSampleBuffer(), let g = autoreleasepool(invoking: { grayImage(from: sb) }) {
                frames.append(g)
            }
            reader.cancelReading()
        }
        if frames.isEmpty { throw TSTVideoError.noFrames }
        return frames
    }

    /// One frame at (or just after) time t.
    func frame(at t: Double) async throws -> GrayImage {
        guard let f = try await sampleFrames(at: [min(max(0, t), max(0, info.duration - 0.05))]).first else {
            throw TSTVideoError.noFrames
        }
        return f
    }

    /// Sequentially decode [start, end), handing every `step`-th frame to `onFrame` with its time
    /// relative to `start`. Decoding and `onFrame` run on the calling task's thread.
    func readSequential(start: Double, end: Double, step: Int,
                        onFrame: (GrayImage, Double) throws -> Void) async throws {
        let (reader, output) = try await makeReader(start: start, end: end)
        var index = 0
        while let sb = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            defer { index += 1 }
            if index % max(1, step) != 0 { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds - start
            guard let g = autoreleasepool(invoking: { grayImage(from: sb) }) else { continue }
            try onFrame(g, max(0, t))
        }
        if reader.status == .failed {
            throw TSTVideoError.cannotRead(reader.error?.localizedDescription ?? "decode failed")
        }
    }
}
