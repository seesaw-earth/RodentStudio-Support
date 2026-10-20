import Foundation

/// Reviewable observations. QC events are NOT behavioral events.
struct TrackingReviewEvent: Identifiable, Hashable {
    let id: String
    let kind: String
    let source: String
    let firstFrame: Int
    let lastFrame: Int
    let start: Double
    let end: Double
    let detail: String
}

enum TrackingReviewEventBuilder {
    static func short(_ report: NativeTrackingResult, threshold: Double) -> [TrackingReviewEvent] {
        var out: [TrackingReviewEvent] = []
        var kind: String? = nil
        var first = 0
        func push(_ finish: Int) {
            guard let type = kind, finish >= first, !report.frames.isEmpty else { return }
            let a = report.frames[first], b = report.frames[finish]
            out.append(.init(id: "qc_\(a.index)_\(type)", kind: type, source: "Tracking QC",
                             firstFrame: a.index, lastFrame: b.index, start: a.time, end: b.time,
                             detail: "\(finish-first+1) frames · observational quality flag"))
        }
        for (i, frame) in report.frames.enumerated() {
            let now: String?
            if frame.inferenceFailed { now = "Inference failed" }
            else if frame.score <= 0 { now = "No detection" }
            else if frame.score < threshold { now = "Low confidence" }
            else { now = nil }
            if now != kind {
                push(i-1)
                kind = now
                first = i
            }
        }
        push(report.frames.count-1)
        return out
    }

    static func behavior(_ result: AnalysisResult, frames: [NativeTrackedFrame]) -> [TrackingReviewEvent] {
        func frame(for time: Double) -> Int {
            guard !frames.isEmpty else { return 0 }
            var low = 0, high = frames.count
            while low < high {
                let middle = (low+high)/2
                if frames[middle].time < time { low = middle+1 } else { high = middle }
            }
            return min(low, frames.count-1)
        }
        var out: [TrackingReviewEvent] = []
        if let cylinder = result.cylinder {
            for e in cylinder.events {
                out.append(.init(id:"limb_cylinder_\(e.id)", kind: "Cylinder · \(e.label.name)",
                                 source:"RodentLimb analyzer (not validated)", firstFrame: frame(for:e.onset),
                                 lastFrame:frame(for:e.offset),start:e.onset,end:e.offset,
                                 detail:"rear \(e.rear) · \(e.edited ? "edited" : "automatic") · \(e.counted ? "counted" : "excluded")"))
            }
        }
        if let tst = result.tst {
            for (i,e) in tst.bouts.enumerated() {
                out.append(.init(id:"limb_tst_immobility_\(i)",kind:"TST · Immobility",source:"RodentLimb analyzer (not validated)",firstFrame:frame(for:e.start),lastFrame:frame(for:e.end),start:e.start,end:e.end,detail:"immobility bout"))
            }
            for (i,e) in tst.climbing.enumerated() {
                out.append(.init(id:"limb_tst_climb_\(i)",kind:"TST · Tail climbing",source:"RodentLimb analyzer (not validated)",firstFrame:frame(for:e.start),lastFrame:frame(for:e.end),start:e.start,end:e.end,detail:"climbing bout"))
            }
        }
        if let gait = result.gait {
            for (i,s) in gait.strides.enumerated() {
                out.append(.init(id:"limb_gait_stride_\(i)", kind:"Gait · \(s.paw.exportName) stride",source:"RodentLimb analyzer (not validated)",firstFrame:frame(for:s.start),lastFrame:frame(for:s.end),start:s.start,end:s.end,detail:"stance/swing episode"))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    static func longSegments(_ manifest: LongVideoManifest) -> [TrackingReviewEvent] {
        var base = 0
        var events: [TrackingReviewEvent] = []
        for s in manifest.completed.sorted(by: {$0.index < $1.index}) {
            if s.failedFrames > 0 {
                events.append(.init(id:"long_segment_\(s.index)",kind:"Inference failures · segment \(s.index+1)",
                                    source:"Segment QC (not exact events)",firstFrame:base,lastFrame:base+max(0,s.records-1),
                                    start:s.firstPTS,end:s.lastPTS,detail:"\(s.failedFrames) failed frames; inspect segment CSV to locate individual frames"))
            }
            base += s.records
        }
        return events
    }
    /// Index long-video QC events in bounded memory by scanning one completed CSV segment at a time.
    /// Deliberately caps the number of event intervals so pathological videos do not exhaust RAM.
    static func detailedLong(_ manifest: LongVideoManifest, folder: URL, threshold: Double,
                             eventLimit: Int = 25_000) throws -> [TrackingReviewEvent] {
        var result: [TrackingReviewEvent] = []
        var openType: String?
        var firstFrame = 0
        var firstTime = 0.0
        var previousFrame = 0
        var previousTime = 0.0
        func close() {
            guard let openType, result.count < eventLimit else {return}
            result.append(.init(id:"long_qc_\(firstFrame)_\(openType)",kind:openType,
                                source:"Tracking QC",firstFrame:firstFrame,lastFrame:previousFrame,
                                start:firstTime,end:previousTime,
                                detail:"\(previousFrame-firstFrame+1) frames; raw segment CSV is preserved"))
        }
        var base = 0
        var priorSegment: Int?
        for segment in manifest.completed.sorted(by:{$0.index < $1.index}) {
            // A missing segment means there is no contiguous evidence across this boundary.
            if let priorSegment,segment.index != priorSegment+1 { close();openType=nil }
            priorSegment = segment.index
            let rows = try String(contentsOf:folder.appendingPathComponent(segment.file),encoding:.utf8)
            for line in rows.split(whereSeparator: \.isNewline).dropFirst() {
                let cells=line.split(separator:",",omittingEmptySubsequences:false)
                guard cells.count >= 5,let local=Int(cells[0]),let time=Double(cells[1]),
                      let score=Double(cells[3]) else {continue}
                let frame=base+local
                let current:String?
                if cells.last == "1" {current="Inference failed"}
                else if score <= 0 {current="No detection"}
                else if score < threshold {current="Low confidence"}
                else {current=nil}
                if current != openType {
                    close()
                    openType=current
                    firstFrame=frame;firstTime=time
                }
                previousFrame=frame;previousTime=time
                if result.count >= eventLimit {return result}
            }
            base += segment.records
        }
        close()
        return result
    }

}
