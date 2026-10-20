// ReviewSupport.swift — pieces shared by the frame review of every module: reading a window of saved
// tracking without loading the whole run, the saved RodentFlow runs, security-scoped access to the source
// video while a view is open, and the RodentFlow centroid overlay.

import SwiftUI
import AVFoundation
import AppKit

/// Loads a window of saved tracking without loading the whole run.
enum FrameWindowLoader {
    /// RodentPose / RodentLimb frames with zero-based indices in `range`, read from the segment CSVs
    /// (same parsing and numbering as SegmentedRunLoader). Times are relative to the first tracked frame;
    /// `origin` is that frame's presentation time.
    static func frames(manifest: LongVideoManifest, folder: URL, range: ClosedRange<Int>) throws -> (frames: [NativeTrackedFrame], origin: Double) {
        guard let model = PoseModelKind(rawValue: manifest.modelName) else { throw SegmentedRunLoader.LoadError.unknownModel(manifest.modelName) }
        let pointCount = model == .mousePose ? 6 : 7
        let failedColumn = 4 + pointCount * 3
        let sorted = manifest.completed.sorted { $0.index < $1.index }
        var origin: Double? = sorted.first.map { $0.firstPTS }.flatMap { $0.isFinite ? $0 : nil }
        var out: [NativeTrackedFrame] = []
        var offset = 0
        for segment in sorted {
            defer { offset += segment.records }
            let segmentRange = offset...max(offset, offset + segment.records - 1)
            // The first segment is always read when the origin is unknown.
            guard segmentRange.overlaps(range) || origin == nil else { continue }
            let text = try String(contentsOf: folder.appendingPathComponent(segment.file), encoding: .utf8)
            var index = offset
            var header = true
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if header { header = false; continue }
                let cells = line.split(separator: ",", omittingEmptySubsequences: false)
                guard cells.count >= failedColumn, let pts = Double(cells[1]) else { continue }
                if origin == nil { origin = pts }
                defer { index += 1 }
                guard range.contains(index) else { continue }
                var points: [NativeTrackPoint] = []
                points.reserveCapacity(pointCount)
                for k in 0..<pointCount {
                    let b = 4 + k * 3
                    if let x = Double(cells[b]), let y = Double(cells[b + 1]) {
                        points.append(NativeTrackPoint(x: x, y: y, confidence: Double(cells[b + 2]) ?? 0))
                    } else {
                        points.append(.missing)
                    }
                }
                let failed = cells.count > failedColumn && cells[failedColumn] == "1"
                out.append(NativeTrackedFrame(index: index, time: pts - (origin ?? pts), score: Double(cells[3]) ?? 0,
                                              points: points, inferenceFailed: failed))
            }
        }
        return (out, origin ?? 0)
    }
}

/// Saved RodentFlow runs, kept while their file is unchanged (Results, frame review and task summaries share them).
@MainActor
enum FlowRunCache {
    private static var entries: [String: (modified: Date, run: FlowSavedRun)] = [:]

    static func load(_ folder: URL) async throws -> FlowSavedRun {
        let file = folder.appendingPathComponent(FlowDesktopRun.filename)
        let modified = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date) ?? .distantPast
        if let hit = entries[folder.path], hit.modified == modified { return hit.run }
        let run = try await Task.detached(priority: .userInitiated) { try FlowDesktopRun.load(from: folder) }.value
        entries[folder.path] = (modified, run)
        return run
    }

    static func invalidate(_ folder: URL) { entries[folder.path] = nil }
}

/// Keeps security-scoped access to a bookmarked video while the view is open.
final class ScopedVideoAccess {
    let url: URL
    private let granted: Bool
    let generator: AVAssetImageGenerator

    init(url: URL) {
        self.url = url
        granted = url.startAccessingSecurityScopedResource()
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        generator = g
    }

    deinit {
        if granted { url.stopAccessingSecurityScopedResource() }
    }
}
/// Centroid of a RodentFlow sample drawn on its video frame (display-normalized image coordinates),
/// with the preceding 2 s as a trail, in RodentFlow's trajectory colors.
struct FlowCentroidOverlay: View {
    let image: NSImage
    let point: FlowTrackingPoint
    let trail: [FlowTrackingPoint]
    let showsPoint: Bool

    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: max(1, image.size.width), height: max(1, image.size.height))
            let fit = NativeTrackingCanvas.fitRect(size, inside: geo.size)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
                if showsPoint {
                    Canvas { ctx, _ in
                        func location(_ p: FlowTrackingPoint) -> CGPoint {
                            CGPoint(x: fit.minX + CGFloat(p.imageXNormalized) * fit.width,
                                    y: fit.minY + CGFloat(p.imageYNormalized) * fit.height)
                        }
                        var path = Path()
                        var penDown = false
                        for p in trail {
                            if p.interpolated { penDown = false; continue }
                            if penDown { path.addLine(to: location(p)) } else { path.move(to: location(p)); penDown = true }
                        }
                        ctx.stroke(path, with: .color(.black.opacity(0.6)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        ctx.stroke(path, with: .color(.orange.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        let c = location(point)
                        let r: CGFloat = 6
                        let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                        ctx.fill(dot, with: .color(point.interpolated ? Color.gray : Color.orange))
                        ctx.stroke(dot, with: .color(.white), lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
