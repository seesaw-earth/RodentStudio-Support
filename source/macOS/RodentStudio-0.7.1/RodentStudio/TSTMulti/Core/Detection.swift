import Foundation

/// A detected mouse, in processed-image pixel coordinates (origin top-left).
public struct DetBox: Codable, Equatable, Sendable {
    public var x0: Double, y0: Double, x1: Double, y1: Double
    public var confidence: Double
    public init(x0: Double, y0: Double, x1: Double, y1: Double, confidence: Double) {
        self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1; self.confidence = confidence
    }
    public var cx: Double { (x0 + x1) / 2 }
    public var cy: Double { (y0 + y1) / 2 }
    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
    public var area: Double { max(0, width) * max(0, height) }

    public func iou(_ o: DetBox) -> Double {
        let ix = max(0, min(x1, o.x1) - max(x0, o.x0)), iy = max(0, min(y1, o.y1) - max(y0, o.y0))
        let inter = ix * iy
        let u = area + o.area - inter
        return u > 0 ? inter / u : 0
    }
}

public enum BoxOps {
    /// Greedy non-maximum suppression.
    public static func nms(_ boxes: [DetBox], iouThreshold: Double) -> [DetBox] {
        var keep: [DetBox] = []
        for b in boxes.sorted(by: { $0.confidence > $1.confidence }) where !keep.contains(where: { $0.iou(b) > iouThreshold }) {
            keep.append(b)
        }
        return keep
    }

    /// Best detection per chamber (detection centre inside the chamber's x-range), or nil.
    public static func assign(_ boxes: [DetBox], to layout: ChamberLayout, minConfidence: Double) -> [DetBox?] {
        var out = [DetBox?](repeating: nil, count: layout.count)
        for b in boxes where b.confidence >= minConfidence {
            guard let i = layout.chamberIndex(x: b.cx) else { continue }
            if out[i].map({ b.confidence > $0.confidence }) ?? true { out[i] = b }
        }
        return out
    }
}

extension ChamberLayout {
    /// Index of the chamber containing x, or nil.
    public func chamberIndex(x: Double) -> Int? {
        guard walls.count >= 2, x >= walls[0], x < walls[walls.count - 1] else { return nil }
        for i in 0..<count where x >= walls[i] && x < walls[i + 1] { return i }
        return nil
    }

    /// Set the vertical analysis band from mouse boxes: union of boxes, padded 60 % of the span above
    /// (mice curl up towards the clip while struggling) and 40 % below.
    public func fittingBand(to boxes: [DetBox]) -> ChamberLayout {
        guard !boxes.isEmpty else { return self }
        var l = self
        let ya = boxes.map { $0.y0 }.min()!, yb = boxes.map { $0.y1 }.max()!
        let span = yb - ya
        l.y0 = max(0, Int((ya - 0.6 * span).rounded()))
        l.y1 = min(imageHeight, Int((yb + 0.4 * span).rounded()))
        return l
    }
}

// MARK: - Classical presence detector (fallback when no YOLO model is available)

/// Per chamber: is there a mouse-sized dark (or light) compact blob? Uses a threshold relative to the
/// chamber's own bright level, so it works before any mouse is present (no Otsu on empty chambers).
public enum ClassicalMouseDetector {
    public static func detect(frame: GrayImage, layout: ChamberLayout, mouseDark: Bool = true,
                              darkFraction: Double = 0.6) -> [DetBox] {
        var out: [DetBox] = []
        let openR = max(1, Int((0.03 * layout.spacing).rounded()))
        for i in 0..<layout.count {
            let r = layout.roi(i, marginFraction: 0.04)
            let roiFull = PixelRect(x0: r.x0, y0: 0, x1: r.x1, y1: frame.height)   // whole height: band unknown yet
            let roi = ImageOps.gaussian5(frame.cropped(roiFull))
            guard roi.width > 4, roi.height > 4 else { continue }
            var vals = roi.pixels
            let level = Double(ImageOps.percentile(&vals, fraction: mouseDark ? 0.75 : 0.25))
            let t: Int = mouseDark ? Int(level * darkFraction) : Int(level + (255 - level) * (1 - darkFraction))
            var m = BinaryMask(threshold: roi, at: t, dark: mouseDark).opened(radius: openR)
            m = m.closed(radius: 2)
            let (_, comps) = Components.label(m)
            let roiArea = Double(roi.width * roi.height)
            let cands = comps.filter { c in
                let bw = Double(c.x1 - c.x0 + 1), bh = Double(c.y1 - c.y0 + 1)
                let a = Double(c.area)
                // mouse-sized, compact, not a full-height edge or a floor/ceiling strip
                return a >= 0.008 * roiArea && a <= 0.35 * roiArea && bh >= 0.08 * Double(roi.height)
                    && bh <= 0.75 * Double(roi.height) && bw <= 0.9 * Double(roi.width)
                    && a >= 0.3 * bw * bh
                    // a hanging mouse sits inside its chamber; hands/arms passing through cross its sides
                    && c.x0 > 0 && c.x1 < roi.width - 1
            }
            guard let best = cands.max(by: { $0.area < $1.area }) else { continue }
            out.append(DetBox(x0: Double(best.x0 + r.x0), y0: Double(best.y0), x1: Double(best.x1 + 1 + r.x0),
                              y1: Double(best.y1 + 1), confidence: 1))
        }
        return out
    }
}

// MARK: - Key frame

public struct KeyFrameSettings: Codable, Equatable, Sendable {
    public var minConfidence: Double = 0.4
    public var stableSec: Double = 3.0     // all selected mice must be seen continuously this long
    public var maxGapSec: Double = 0.75    // detection drop-outs up to this long are bridged
    public var settleSec: Double = 0       // optional offset added after the key frame
    public init() {}
}

public struct KeyFrameResult: Sendable {
    public var times: [Double]
    public var presence: [[Bool]]          // [chamber][time], after gap bridging
    public var selected: [Bool]
    /// Start of the first window in which every selected chamber has a mouse for ≥ stableSec.
    public var keyTime: Double?
    /// Per chamber: start of the first stable presence (≈ when that mouse was hung).
    public var hungAt: [Double?]
    /// First time after the key frame at which some selected mouse is missing for ≥ stableSec (removed).
    public var allPresentEnd: Double?

    public init(times: [Double], presence: [[Bool]], selected: [Bool], keyTime: Double?,
                hungAt: [Double?], allPresentEnd: Double?) {
        self.times = times; self.presence = presence; self.selected = selected
        self.keyTime = keyTime; self.hungAt = hungAt; self.allPresentEnd = allPresentEnd
    }
}

public enum KeyFrameFinder {

    /// - Parameters:
    ///   - times: sample times (s), ascending.
    ///   - detections: per time, best detection per chamber (nil = none).
    public static func find(times: [Double], detections: [[DetBox?]], selected: [Bool],
                            settings: KeyFrameSettings) -> KeyFrameResult {
        let nCh = selected.count
        precondition(detections.count == times.count)
        let dt = times.count > 1 ? (times[times.count - 1] - times[0]) / Double(times.count - 1) : 1
        let maxGap = max(0, Int((settings.maxGapSec / dt).rounded()))
        let stableN = max(1, Int((settings.stableSec / dt).rounded()))

        var presence: [[Bool]] = []
        for c in 0..<nCh {
            let raw = detections.map { c < $0.count && ($0[c].map { $0.confidence >= settings.minConfidence } ?? false) }
            presence.append(bridge(raw, maxGap: maxGap))
        }
        var hungAt: [Double?] = []
        for c in 0..<nCh {
            hungAt.append(firstRun(presence[c], minLength: stableN).map { times[$0] })
        }
        let sel = (0..<nCh).filter { selected[$0] }
        var all = [Bool](repeating: !sel.isEmpty, count: times.count)
        for c in sel { for k in all.indices { all[k] = all[k] && presence[c][k] } }
        let keyIdx = firstRun(all, minLength: stableN)
        var endTime: Double? = nil
        if let k = keyIdx {
            // first index after the key where `all` is false for ≥ stableN samples
            var j = k
            while j < all.count {
                if !all[j] {
                    var e = j
                    while e < all.count && !all[e] { e += 1 }
                    if e - j >= stableN { endTime = times[j]; break }
                    j = e
                } else { j += 1 }
            }
        }
        return KeyFrameResult(times: times, presence: presence, selected: selected,
                              keyTime: keyIdx.map { times[$0] + settings.settleSec },
                              hungAt: hungAt, allPresentEnd: endTime)
    }

    /// Fill false runs of length ≤ maxGap that are surrounded by true on both sides.
    static func bridge(_ b: [Bool], maxGap: Int) -> [Bool] {
        guard maxGap > 0 else { return b }
        var out = b
        var i = 0
        while i < b.count {
            if !b[i] {
                var j = i
                while j < b.count && !b[j] { j += 1 }
                if i > 0 && j < b.count && j - i <= maxGap { for k in i..<j { out[k] = true } }
                i = j
            } else { i += 1 }
        }
        return out
    }

    /// Start index of the first run of `true` with length ≥ minLength.
    static func firstRun(_ b: [Bool], minLength: Int) -> Int? {
        var i = 0
        while i < b.count {
            if b[i] {
                var j = i
                while j < b.count && b[j] { j += 1 }
                if j - i >= minLength { return i }
                i = j
            } else { i += 1 }
        }
        return nil
    }
}
