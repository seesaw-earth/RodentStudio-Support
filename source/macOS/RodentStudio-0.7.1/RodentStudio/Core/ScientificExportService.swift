import Foundation
import AppKit
import AVFoundation
import CoreGraphics

/// Explicit exports of observational pose/QC data, NOT validated behavioral endpoints.
struct ScientificExportOptions {
    var rawPoseCSV = true
    var screenedPoseCSV = false
    var frameQCcsv = true
    var provenanceJSON = true
    var annotatedPNG = true
    var trajectoryPNG = true
    var confidencePNG = true
    var annotatedVideo = false // Opt-in only; not included in every export package.
    var copyLongSegments = false
    var longQCtimelinePNG = true
    var longTrajectoryPNG = true
    var anyShort: Bool { rawPoseCSV || screenedPoseCSV || frameQCcsv || provenanceJSON || annotatedPNG || trajectoryPNG || confidencePNG || annotatedVideo }
    var anyLong: Bool { copyLongSegments || frameQCcsv || provenanceJSON || longQCtimelinePNG || longTrajectoryPNG }
}

struct ScientificExportContext: Codable {
    var projectName: String?
    var experimentName: String?
    var assayID: String?
    var animalID: String?
    var group: String?
    var phase: String?
    var day: Int?
    var trial: Int?
    var sex: String?
    var notes: String?
    /// Recording date ("yyyy-MM-dd") and session number (实验次数) of the session.
    var sessionDate: String?
    var sessionNumber: Int?
    var excluded: Bool?
    var exclusionReason: String?
    var calibration: DesktopCalibration?
    var qcDecision: String = "unreviewed"
    var reviewerNotes: String = ""
    var confidenceThreshold: Double = 0.35

    var windowStart: Double { max(0, calibration?.visualParameters.analysisStartSeconds ?? 0) }
    var windowEnd: Double? {
        let duration = calibration?.visualParameters.analysisDurationSeconds ?? 0
        return duration > 0 ? windowStart + duration : nil
    }
}

private struct ScientificQCRecord: Codable {
    let kind: String
    let scientificStatus: String
    let generatedAt: Date
    let sourceVideo: String
    let model: String
    let imageWidth: Int?
    let imageHeight: Int?
    let frameCount: Int
    let validInferenceFrames: Int
    let detectedFrames: Int
    let inferenceFailures: Int
    let noDetectionFrames: Int
    let lowConfidenceFrames: Int
    let longestInvalidRunFrames: Int
    let startTime: Double?
    let endTime: Double?
    let context: ScientificExportContext
    let files: [String]
    let notes: [String]
}

enum ScientificExportError: LocalizedError {
    case missingSource
    case mismatchedModel
    case noSelection
    case failedImage
    case unsupportedVideoExport
    case badFigureRange
    var errorDescription: String? {
        switch self {
        case .missingSource: "Source video not available; annotated screenshot needs access to the original file."
        case .mismatchedModel: "The selected assay and tracking model do not match. No exports were generated."
        case .noSelection: "Select at least one export type."
        case .failedImage: "Image rendering failed."
        case .unsupportedVideoExport: "Optional annotated video export is not implemented in this build. Use the screenshot option, or export raw coordinates to a video editor."
        case .badFigureRange: "Figure frame range is outside the completed tracking data."
        }
    }
}

enum ScientificExportService {
    private static let fileManager = FileManager.default

    static func exportShort(_ report: NativeTrackingResult, context: ScientificExportContext,
                            source: URL?, selectedFrame: Int,
                            options: ScientificExportOptions, into folder: URL,
                            figureFrames: ClosedRange<Int>? = nil) throws -> URL {
        guard options.anyShort else { throw ScientificExportError.noSelection }
        if options.annotatedVideo { throw ScientificExportError.unsupportedVideoExport }
        if let range = figureFrames, (range.lowerBound < 0 || range.upperBound >= report.frames.count) { throw ScientificExportError.badFigureRange }
        // Never relabel RodentLimb poses as RodentPose, or vice versa.
        if let assayID = context.assayID, let assay = StudyAssay(rawValue: assayID),
           assay.modelRoute != report.model { throw ScientificExportError.mismatchedModel }
        let output = try newPackage(in: folder, stem: report.model == .mousePose ? "RodentPose" : "RodentLimb")
        var made: [String] = []
        if options.rawPoseCSV {
            let filename = "raw_pose.csv"
            try report.csv().write(to: output.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            made.append(filename)
        }
        if options.screenedPoseCSV {
            let filename = "qc_screened_pose.csv"
            let header = report.csv().prefix(while: { $0 != "\n" })
            var text = String(header) + ",eligible_for_continuous_qc,qc_reason\n"
            for frame in report.frames {
                let reason = reasonFor(frame, context: context)
                // Keep rejected rows and original coordinates; QC never erases observations.
                text += rawCSVRow(frame) + ",\(reason == "valid" ? 1 : 0),\(reason)\n"
            }
            try text.write(to: output.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            made.append(filename)
        }
        if options.frameQCcsv {
            let filename = "frame_qc.csv"
            var text = "frame_index,time_s,detected,inference_failed,confidence,qc_status\n"
            for frame in report.frames {
                text += "\(frame.index),\(String(format: "%.9f", frame.time)),\(frame.score > 0 && !frame.inferenceFailed ? 1 : 0),\(frame.inferenceFailed ? 1 : 0),\(String(format: "%.7g", frame.score)),\(reasonFor(frame,context:context))\n"
            }
            try text.write(to: output.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            made.append(filename)
        }
        if options.annotatedPNG {
            guard let source else { throw ScientificExportError.missingSource }
            let index = min(max(selectedFrame, 0), max(report.frames.count - 1, 0))
            guard let frame = report.frames.indices.contains(index) ? report.frames[index] : nil else { throw ScientificExportError.failedImage }
            // Export the pose corresponding to the frame actually returned by AVFoundation.
            // When no reliable timestamp match exists, fail rather than mislabel a frame.
            let (jpg, actualPTS) = try imageAt(source, second: report.timeOffset + frame.time)
            guard actualPTS.isFinite else {throw ScientificExportError.failedImage}
            let matching = report.frames.enumerated().min { a,b in
                abs(a.element.time + report.timeOffset - actualPTS) < abs(b.element.time + report.timeOffset - actualPTS)
            }
            guard let matching,
                  abs(matching.element.time + report.timeOffset - actualPTS) <= max(0.012,0.53/max(report.fps,1)),
                  abs(CGFloat(jpg.width) / max(CGFloat(jpg.height),1) - CGFloat(report.videoWidth) / max(CGFloat(report.videoHeight),1)) < 0.015 else {
                throw ScientificExportError.failedImage
            }
            let png = try makeAnnotatedPNG(jpg, frame: matching.element, report: report, context: context)
            let name = "annotated_frame_\(matching.element.index).png"
            try png.write(to: output.appendingPathComponent(name), options: .atomic)
            made.append(name)
        }
        if options.trajectoryPNG {
            let png = try makeTrajectoryPNG(report, context: context, selectedFrames: figureFrames)
            let name = "tracking_path_qc.png"
            try png.write(to: output.appendingPathComponent(name), options: .atomic)
            made.append(name)
        }
        if options.confidencePNG {
            let name = "tracking_confidence_figure.png"
            try makeConfidencePNG(report, selectedFrames: figureFrames).write(to: output.appendingPathComponent(name), options: .atomic)
            made.append(name)
        }
        if options.provenanceJSON {
            let summary = makeShortQC(report, context: context, files: made + ["qc_provenance.json"], figureFrames: figureFrames)
            try writeJSON(summary, to: output.appendingPathComponent("qc_provenance.json"))
            made.append("qc_provenance.json")
        }
        return output
    }

    static func exportLong(_ manifest: LongVideoManifest, context: ScientificExportContext,
                           originalFolder: URL, options: ScientificExportOptions,
                           into destination: URL, figureFrames: ClosedRange<Int>? = nil) throws -> URL {
        guard options.anyLong else { throw ScientificExportError.noSelection }
        let totalFrames = manifest.completed.reduce(0) { $0 + $1.records }
        if let range = figureFrames, (range.lowerBound < 0 || range.upperBound >= totalFrames) { throw ScientificExportError.badFigureRange }
        if let assayID = context.assayID, let assay = StudyAssay(rawValue: assayID),
           assay.modelRoute?.rawValue != manifest.modelName { throw ScientificExportError.mismatchedModel }
        let output = try newPackage(in: destination, stem: "LongVideo")
        var made: [String] = []
        if options.copyLongSegments {
            let sub = output.appendingPathComponent("raw_segments", isDirectory: true)
            try fileManager.createDirectory(at: sub, withIntermediateDirectories: false)
            for seg in manifest.completed {
                try fileManager.copyItem(at: originalFolder.appendingPathComponent(seg.file), to: sub.appendingPathComponent(seg.file))
            }
            made.append("raw_segments/ (\(manifest.completed.count) CSV files)")
        }
        if options.frameQCcsv {
            let file = "segment_qc.csv"
            var text = "segment_index,file,records,failed_frames,first_pts_s,last_pts_s\n"
            for seg in manifest.completed {
                text += "\(seg.index),\(seg.file),\(seg.records),\(seg.failedFrames),\(seg.firstPTS),\(seg.lastPTS)\n"
            }
            try text.write(to: output.appendingPathComponent(file), atomically: true, encoding: .utf8)
            made.append(file)
        }
        if options.longQCtimelinePNG {
            let file = "segment_qc_timeline.png"
            try makeLongTimelinePNG(manifest).write(to: output.appendingPathComponent(file), options: .atomic)
            made.append(file)
        }
        if options.longTrajectoryPNG {
            let name = "trajectory_selected_frames.png"
            try makeLongTrajectoryPNG(manifest, inputFolder: originalFolder, selectedFrames: figureFrames,
                                      threshold: context.confidenceThreshold)
                .write(to: output.appendingPathComponent(name), options: .atomic)
            made.append(name)
        }
        if options.provenanceJSON {
            // Manifest is preserved byte-for-byte as a separate scientific provenance artifact.
            try writeJSON(manifest, to: output.appendingPathComponent("tracking_manifest.json"))
            made.append("tracking_manifest.json")
            let total = manifest.completed.reduce(0) { $0 + $1.records }
            let failed = manifest.completed.reduce(0) { $0 + $1.failedFrames }
            let summary = ScientificQCRecord(kind: "segment_qc", scientificStatus: "raw tracking; behavioral endpoints not validated",
                generatedAt: Date(), sourceVideo: manifest.sourceFile, model: manifest.modelName,
                imageWidth: nil, imageHeight: nil, frameCount: total,
                validInferenceFrames: max(0,total-failed), detectedFrames: 0, inferenceFailures: failed,
                noDetectionFrames: 0, lowConfidenceFrames: 0, longestInvalidRunFrames: 0,
                startTime: 0, endTime: manifest.videoDuration, context: context,
                files: made + ["qc_provenance.json"], notes: ["Segment-level QC only. Missing detections are not counted unless individual CSVs are inspected.",
                    "No inference results are interpolated, and no behavioral score has been calculated.",
                    "Source fingerprint is a fast change detector, NOT a full-file SHA-256.",
                    "Trajectory figure uses selected global frame range \(figureFrames?.lowerBound ?? 0)...\(figureFrames?.upperBound ?? total-1), indexed over completed segment records; no behavioral endpoints are plotted."])
            try writeJSON(summary, to: output.appendingPathComponent("qc_provenance.json"))
            made.append("qc_provenance.json")
        }
        return output
    }

    private static func reasonFor(_ frame: NativeTrackedFrame, context: ScientificExportContext) -> String {
        if frame.inferenceFailed { return "inference_failed" }
        if frame.time < context.windowStart || (context.windowEnd.map { frame.time >= $0 } ?? false) { return "outside_time_window" }
        if frame.score <= 0 { return "no_detection" }
        if frame.score < context.confidenceThreshold { return "low_box_confidence" }
        return "valid"
    }

    private static func rawCSVRow(_ frame: NativeTrackedFrame) -> String {
        var cells = [String(frame.index), String(format: "%.6f", frame.time), frame.score > 0 ? "1" : "0", String(format: "%.7g", frame.score)]
        for p in frame.points {
            if p.x >= 0 && p.y >= 0 && p.x.isFinite && p.y.isFinite {
                cells += [String(format: "%.5f", p.x),String(format: "%.5f", p.y),String(format: "%.7g", p.confidence)]
            } else { cells += ["", "", "0"] }
        }
        cells.append(frame.inferenceFailed ? "1" : "0")
        return cells.joined(separator: ",")
    }

    private static func makeShortQC(_ report: NativeTrackingResult, context: ScientificExportContext, files: [String], figureFrames: ClosedRange<Int>?) -> ScientificQCRecord {
        var noDetection = 0, low = 0, streak = 0, maxStreak = 0
        for frame in report.frames {
            if !frame.inferenceFailed && frame.score <= 0 { noDetection += 1 }
            if !frame.inferenceFailed && frame.score > 0 && frame.score < context.confidenceThreshold { low += 1 }
            if frame.inferenceFailed || frame.score <= 0 { streak += 1; maxStreak = max(maxStreak,streak) } else { streak = 0 }
        }
        return ScientificQCRecord(kind: "per_frame_qc", scientificStatus: "raw tracking; behavioral endpoints not validated",
            generatedAt: Date(), sourceVideo: report.videoFile, model: report.model.rawValue,
            imageWidth: report.videoWidth, imageHeight: report.videoHeight, frameCount: report.frames.count,
            validInferenceFrames: report.frames.count - report.inferenceFailureCount,
            detectedFrames: report.frames.filter { $0.score > 0 && !$0.inferenceFailed }.count,
            inferenceFailures: report.inferenceFailureCount,
            noDetectionFrames: noDetection, lowConfidenceFrames: low, longestInvalidRunFrames: maxStreak,
            startTime: report.frames.first?.time, endTime: report.frames.last?.time, context: context,
            files: files, notes: ["QC screening does not delete or interpolate raw observations.",
                "QC threshold is the bounding-box score; keypoint confidence remains in raw CSV.",
                "The time window is applied to QC eligibility, not to the original tracking output.",
                "PNG figures are QC visualizations, not validated behavioral metrics.",
                "Figure frame range: \(figureFrames?.lowerBound ?? 0)...\(figureFrames?.upperBound ?? max(0, report.frames.count-1)); figures only, raw CSV remains complete."])
    }

    private static func newPackage(in folder: URL, stem: String) throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let path = folder.appendingPathComponent("\(stem)_\(timestamp)_\(UUID().uuidString.prefix(6))", isDirectory: true)
        try fileManager.createDirectory(at: path, withIntermediateDirectories: false)
        return path
    }
    private static func writeJSON<T: Encodable>(_ object: T, to file: URL) throws {
        let coder = JSONEncoder()
        coder.outputFormatting = [.prettyPrinted, .sortedKeys]
        coder.dateEncodingStrategy = .iso8601
        try coder.encode(object).write(to: file, options: .atomic)
    }

    private static func bitmap(_ size: CGSize, painter: (CGContext) -> Void) throws -> Data {
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ScientificExportError.failedImage }
        painter(ctx)
        guard let image = ctx.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScientificExportError.failedImage
        }
        return png
    }
    private static func imageAt(_ video: URL, second: Double) throws -> (CGImage,Double) {
        let access = video.startAccessingSecurityScopedResource()
        defer { if access { video.stopAccessingSecurityScopedResource() } }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var actual=CMTime.invalid
        let cg=try generator.copyCGImage(at: CMTime(seconds: max(0,second), preferredTimescale: 60_000), actualTime: &actual)
        return (cg,CMTimeGetSeconds(actual))
    }
    // Separate drawing helpers avoid an excessively complex CGContext closure that
    // Swift 5/Xcode 26 cannot type-check in a reasonable time. The palette and
    // coordinate transforms are intentionally identical to the preceding release.
    private static let rodentPosePointColors: [CGColor] = [
        CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.95),
        CGColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.95),
        CGColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 0.95),
        CGColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 0.95),
        CGColor(red: 0.0, green: 0.85, blue: 0.9, alpha: 0.95),
        CGColor(red: 0.65, green: 0.0, blue: 0.85, alpha: 0.95)
    ]

    private static let rodentLimbPointColors: [CGColor] = [
        CGColor(red: 30.0/255.0, green: 127.0/255.0, blue: 216.0/255.0, alpha: 0.95),
        CGColor(red: 18.0/255.0, green: 160.0/255.0, blue: 90.0/255.0, alpha: 0.95),
        CGColor(red: 229.0/255.0, green: 64.0/255.0, blue: 79.0/255.0, alpha: 0.95),
        CGColor(red: 138.0/255.0, green: 79.0/255.0, blue: 224.0/255.0, alpha: 0.95),
        CGColor(red: 229.0/255.0, green: 143.0/255.0, blue: 166.0/255.0, alpha: 0.95),
        CGColor(red: 242.0/255.0, green: 165.0/255.0, blue: 0.0, alpha: 0.95),
        CGColor(red: 95.0/255.0, green: 195.0/255.0, blue: 232.0/255.0, alpha: 0.95)
    ]

    private static func drawAnnotatedPoints(in ctx: CGContext,
                                            canvasSize: CGSize,
                                            frame: NativeTrackedFrame,
                                            report: NativeTrackingResult,
                                            minimumConfidence: Double) {
        let sourceWidth = CGFloat(max(1, report.videoWidth))
        let sourceHeight = CGFloat(max(1, report.videoHeight))
        let scaleX: CGFloat = canvasSize.width / sourceWidth
        let scaleY: CGFloat = canvasSize.height / sourceHeight
        let palette: [CGColor] = report.model == .mousePose ? rodentPosePointColors : rodentLimbPointColors

        for (index, point) in frame.points.enumerated() {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= 0, point.y >= 0,
                  point.confidence >= minimumConfidence else { continue }

            let x: CGFloat = CGFloat(point.x) * scaleX
            let y: CGFloat = canvasSize.height - CGFloat(point.y) * scaleY
            let marker = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
            ctx.setFillColor(palette[index % palette.count])
            ctx.fillEllipse(in: marker)
        }
    }

    private static func drawAnnotatedCalibration(in ctx: CGContext,
                                                 canvasSize: CGSize,
                                                 calibration: DesktopCalibration?) {
        guard let calibration else { return }
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 0, alpha: 0.85))
        ctx.setLineWidth(2)
        for handle in calibration.handles.values {
            let x: CGFloat = CGFloat(handle.x) * canvasSize.width
            let y: CGFloat = (1 - CGFloat(handle.y)) * canvasSize.height
            let marker = CGRect(x: x - 7, y: y - 7, width: 14, height: 14)
            ctx.strokeEllipse(in: marker)
        }
    }

    private static func makeAnnotatedPNG(_ source: CGImage,
                                         frame: NativeTrackedFrame,
                                         report: NativeTrackingResult,
                                         context: ScientificExportContext) throws -> Data {
        let canvasSize = CGSize(width: CGFloat(source.width), height: CGFloat(source.height))
        return try bitmap(canvasSize) { ctx in
            ctx.draw(source, in: CGRect(origin: .zero, size: canvasSize))
            drawAnnotatedPoints(in: ctx,
                                canvasSize: canvasSize,
                                frame: frame,
                                report: report,
                                minimumConfidence: context.confidenceThreshold)
            drawAnnotatedCalibration(in: ctx,
                                     canvasSize: canvasSize,
                                     calibration: context.calibration)
        }
    }
    private static func makeTrajectoryPNG(_ report: NativeTrackingResult, context: ScientificExportContext, selectedFrames: ClosedRange<Int>?) throws -> Data {
        let scale = min(1.0, 1600.0 / Double(max(report.videoWidth,report.videoHeight,1)))
        let size = CGSize(width: max(400,CGFloat(report.videoWidth)*scale),height:max(320,CGFloat(report.videoHeight)*scale))
        let factorX = size.width / CGFloat(max(1, report.videoWidth))
        let factorY = size.height / CGFloat(max(1, report.videoHeight))
        return try bitmap(size) { ctx in
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(origin:.zero,size:size))
            ctx.setLineWidth(1.5)
            ctx.setStrokeColor(CGColor(red: 0.10, green: 0.37, blue: 0.70, alpha: 0.75))
            var prev: CGPoint?
            for frame in report.frames {
                if let selectedFrames, !selectedFrames.contains(frame.index) { prev = nil; continue }
                guard reasonFor(frame, context: context) == "valid" else { prev = nil; continue }
                // Observational QC path: Pose body_center, Limb tail_base; NOT an assay-specific gait or contact metric.
                let index = 4
                guard frame.points.indices.contains(index) else { prev = nil; continue }
                let p = frame.points[index]
                guard p.x.isFinite && p.y.isFinite && p.x >= 0 && p.y >= 0 && p.confidence >= context.confidenceThreshold else {prev = nil;continue}
                let current = CGPoint(x: CGFloat(p.x)*factorX,y:size.height-CGFloat(p.y)*factorY)
                if let prev { ctx.move(to: prev);ctx.addLine(to: current);ctx.strokePath() }
                prev = current
            }
            if let cal = context.calibration {
                ctx.setStrokeColor(CGColor(red:0.8,green:0.22,blue:0.24,alpha:0.8))
                for p in cal.handles.values {
                    ctx.strokeEllipse(in:CGRect(x: CGFloat(p.x)*size.width-5,y:(1-CGFloat(p.y))*size.height-5,width:10,height:10))
                }
            }
        }
    }
    /// Explicit native RodentLimb behavioral-event figure; NOT a rodentpose/rodentflow prediction.
    static func exportLimbEventFigure(_ result: AnalysisResult, tracked: NativeTrackingResult,
                                      selectedFrames: ClosedRange<Int>, to file: URL) throws {
        guard tracked.frames.indices.contains(selectedFrames.lowerBound),
              tracked.frames.indices.contains(selectedFrames.upperBound),
              tracked.model == .cylinderV2 else {throw ScientificExportError.badFigureRange}
        let begin=tracked.frames[selectedFrames.lowerBound].time
        let end=tracked.frames[selectedFrames.upperBound].time
        let span=max(0.001,end-begin)
        let size=CGSize(width:1200,height:480)
        let png=try bitmap(size) {ctx in
            ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));ctx.fill(CGRect(origin:.zero,size:size))
            for lane in 0..<4 {
                ctx.setStrokeColor(CGColor(gray:0.85,alpha:1))
                let y=90+CGFloat(lane)*95
                ctx.move(to:CGPoint(x:65,y:y));ctx.addLine(to:CGPoint(x:1150,y:y));ctx.strokePath()
            }
            func paint(_ start:Double,_ stop:Double,_ lane:Int,_ color:CGColor) {
                guard stop >= begin,start <= end else{return}
                let startX=65 + CGFloat(max(begin,start)-begin)/CGFloat(span)*1085
                let stopX=65 + CGFloat(min(end,stop)-begin)/CGFloat(span)*1085
                ctx.setFillColor(color)
                ctx.fill(CGRect(x:startX,y:72+CGFloat(lane)*95,width:max(2,stopX-startX),height:35))
            }
            if let cylinder=result.cylinder {
                for e in cylinder.events {
                    let lane=e.label == .left ? 0 : e.label == .right ? 1 : e.label == .both ? 2 : 3
                    let colors:[CGColor]=[CGColor(red:0.12,green:0.48,blue:0.76,alpha:0.9),CGColor(red:0.83,green:0.3,blue:0.24,alpha:0.9),CGColor(red:0.48,green:0.3,blue:0.75,alpha:0.9),CGColor(gray:0.5,alpha:0.7)]
                    paint(e.onset,e.offset,lane,colors[lane])
                }
            }
            if let tst=result.tst {
                for b in tst.bouts {paint(b.start,b.end,0,CGColor(red:0.1,green:0.5,blue:0.8,alpha:0.85))}
                for b in tst.climbing {paint(b.start,b.end,1,CGColor(red:0.91,green:0.52,blue:0.17,alpha:0.85))}
            }
            if let gait=result.gait {
                for stride in gait.strides {
                    let lane=stride.paw.rawValue
                    paint(stride.start,stride.end,lane%4,CGColor(red:0.12,green:0.5,blue:0.36,alpha:0.75))
                }
            }
        }
        try png.write(to:file,options:.atomic)
    }

    private static func makeConfidencePNG(_ report: NativeTrackingResult, selectedFrames: ClosedRange<Int>?) throws -> Data {
        let selected = selectedFrames ?? 0...max(0, report.frames.count-1)
        let size = CGSize(width: 1200, height: 440)
        return try bitmap(size) { ctx in
            ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1)); ctx.fill(CGRect(origin:.zero,size:size))
            ctx.setStrokeColor(CGColor(gray:0.78,alpha:1)); ctx.setLineWidth(1)
            for n in 0...4 {
                let y = 50 + CGFloat(n) * 80
                ctx.move(to:CGPoint(x:65,y:y));ctx.addLine(to:CGPoint(x:1160,y:y));ctx.strokePath()
            }
            var prior: CGPoint?
            for frame in report.frames where selected.contains(frame.index) {
                if frame.inferenceFailed || frame.score <= 0 { prior = nil; continue }
                let x = 65 + CGFloat(frame.index - selected.lowerBound) / CGFloat(max(1, selected.upperBound-selected.lowerBound)) * 1095
                let y = 50 + CGFloat(min(1,max(0,frame.score))) * 320
                let point = CGPoint(x:x,y:y)
                if let prior {
                    ctx.setStrokeColor(CGColor(red:0.18,green:0.42,blue:0.72,alpha:0.9))
                    ctx.move(to:prior);ctx.addLine(to:point);ctx.strokePath()
                }
                prior=point
            }
        }
    }

    /// Segment-at-a-time CSV scanning: bounded by one 2-minute CSV, never loads an entire long run.
    /// Global indices count concatenated, completed CSV records in segment order.
    private static func scanLong(_ manifest: LongVideoManifest, folder: URL,
                                 selectedFrames: ClosedRange<Int>?, visitor: (Int, [Substring]) -> Void) throws {
        var base = 0
        for segment in manifest.completed.sorted(by: {$0.index < $1.index}) {
            defer { base += segment.records }
            let last = base + segment.records - 1
            if let selectedFrames, (last < selectedFrames.lowerBound || base > selectedFrames.upperBound) { continue }
            let segmentURL = folder.appendingPathComponent(segment.file)
            // A single finished segment is usually < 2 MB and is dropped before the next file.
            let content = try String(contentsOf: segmentURL, encoding:.utf8)
            for line in content.split(whereSeparator: \.isNewline).dropFirst() {
                let columns = line.split(separator:",", omittingEmptySubsequences:false)
                guard let local = Int(columns[0]), columns.count > 4 else { continue }
                let global = base + local
                if selectedFrames?.contains(global) ?? true { visitor(global,columns) }
            }
        }
    }

    /// The completed pose coordinates, not raw image frames, determine the figure.
    private static func makeLongTrajectoryPNG(_ manifest: LongVideoManifest, inputFolder: URL,
                                              selectedFrames: ClosedRange<Int>?, threshold: Double) throws -> Data {
        let selected = selectedFrames ?? (0...max(0,manifest.completed.reduce(0) {$0+$1.records}-1))
        let feature = manifest.modelName == PoseModelKind.mousePose.rawValue ? 4 : 0
        let xi = 4 + feature*3, yi = xi+1, ci = xi+2
        var maxX = 1.0, maxY = 1.0
        func location(_ values: [Substring]) -> CGPoint? {
            guard values.count > ci+1, values.last == "0", Double(values[3]) ?? 0 > 0,
                  let x = Double(values[xi]),let y=Double(values[yi]),let c=Double(values[ci]),
                  x.isFinite,y.isFinite,c>=threshold,x>=0,y>=0 else { return nil }
            return CGPoint(x:x,y:y)
        }
        try scanLong(manifest,folder:inputFolder,selectedFrames:selected) { _,values in
            if let p = location(values) {maxX = max(maxX,Double(p.x)); maxY = max(maxY,Double(p.y))}
        }
        let boundX=maxX,boundY=maxY
        let size=CGSize(width:1200,height:900)
        var scanError: Error?
        let png=try bitmap(size) { ctx in
            ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));ctx.fill(CGRect(origin:.zero,size:size))
            ctx.setStrokeColor(CGColor(red:0.15,green:0.42,blue:0.75,alpha:0.7));ctx.setLineWidth(1)
            var prev: CGPoint?
            do { try scanLong(manifest,folder:inputFolder,selectedFrames:selected) { global,values in
                guard let p=location(values) else {prev=nil;return}
                let now=CGPoint(x:50+CGFloat(Double(p.x)/boundX)*1100,y:50+(1-CGFloat(Double(p.y)/boundY))*800)
                if let prev {ctx.move(to:prev);ctx.addLine(to:now);ctx.strokePath()}
                prev=now
                _=global
            }} catch { scanError = error }
        }
        if let scanError { throw scanError }
        return png
    }

    private static func makeLongTimelinePNG(_ report: LongVideoManifest) throws -> Data {
        let size = CGSize(width: 1300, height: 320)
        return try bitmap(size) { ctx in
            ctx.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));ctx.fill(CGRect(origin:.zero,size:size))
            let total = max(1,Int(ceil(report.videoDuration / max(1,report.chunkDuration))))
            let w = 1200 / CGFloat(total)
            for seg in report.completed {
                let ratio = CGFloat(seg.failedFrames) / CGFloat(max(1,seg.records))
                ctx.setFillColor(CGColor(red: min(1,0.12 + ratio*8),green:max(0,0.7-ratio*4),blue:0.27,alpha:1))
                ctx.fill(CGRect(x: 50 + CGFloat(seg.index)*w, y: 50, width: max(1,w),height:220))
            }
            // Grey bar marks segments missing from the manifest. Do not mistake them for successful zero-error segments.
            for i in 0..<total where !report.completed.contains(where: {$0.index == i}) {
                ctx.setFillColor(CGColor(red:0.7,green:0.7,blue:0.7,alpha:1))
                ctx.fill(CGRect(x:50+CGFloat(i)*w,y:50,width:max(1,w),height:220))
            }
        }
    }
}
