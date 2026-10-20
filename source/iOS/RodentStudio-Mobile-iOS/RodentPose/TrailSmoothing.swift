// TrailSmoothing.swift — display-only trajectories for video overlays (the trail in Review and
// the recognized path on the calibration frame).
//
// Raw detections sometimes land on a reflection, the cup or the other animal for a frame or two.
// Drawn as-is, the trail then "flies" across the arena, and joining every valid point draws long
// straight lines across gaps. Each animal's body-center path is cleaned for display only:
//
//   1. confidence gate (same keypoint threshold as the analysis)
//   2. spike rejection: a point far from the moving 2-D median of its ±0.25 s neighbours
//      (robust MAD scale, floored at ~⅓ body length) is dropped — handles runs of a few frames
//   3. segmentation: a gap longer than the interpolation limit, or a step faster than an animal
//      can move, starts a new segment instead of drawing a connecting line
//   4. linear interpolation of short gaps inside a segment
//   5. Gaussian smoothing inside each segment (σ ≈ 0.08 s), no smoothing across segments
//   6. segments shorter than three samples are not drawn
//
// The analysis (metrics, exports) uses its own preprocessing in Kinematics.swift and is not
// affected by anything here. Foundation only, so it can be tested outside the app.

import Foundation

struct DisplayTrail {
    /// Normalized image coordinates (0…1 of the upright frame) per processed frame; NaN = no point.
    private(set) var x: [Float]
    private(set) var y: [Float]
    /// Samples are joined only when they share a segment id (-1 = not drawn).
    private(set) var segment: [Int32]

    static let empty = DisplayTrail(x: [], y: [], segment: [])

    var count: Int { x.count }
    var isEmpty: Bool { x.isEmpty }

    @inline(__always)
    func point(_ i: Int) -> (x: Double, y: Double)? {
        guard i >= 0, i < x.count, segment[i] >= 0 else { return nil }
        return (Double(x[i]), Double(y[i]))
    }

    /// True when samples `i` and `j` belong to the same drawn segment.
    @inline(__always)
    func connected(_ i: Int, _ j: Int) -> Bool {
        i >= 0 && j >= 0 && i < segment.count && j < segment.count && segment[i] >= 0 && segment[i] == segment[j]
    }

    /// Polylines in normalized coordinates over the whole trail, each with at most about
    /// `maxPoints` samples in total (for static overviews such as the calibration frame).
    func polylines(maxPoints: Int = 1500) -> [[NPoint]] {
        guard count > 1 else { return [] }
        let step = max(1, count / max(1, maxPoints))
        var out: [[NPoint]] = []
        var cur: [NPoint] = []
        for i in 0..<count {
            let s = segment[i]
            guard s >= 0 else {
                if cur.count > 1 { out.append(cur) }
                cur = []
                continue
            }
            let first = i == 0 || segment[i - 1] != s
            let lastInSegment = i == count - 1 || segment[i + 1] != s
            if first {
                if cur.count > 1 { out.append(cur) }
                cur = []
            }
            // Thin long segments, but keep both ends so lines start and stop where the animal did.
            if first || lastInSegment || i % step == 0 {
                cur.append(NPoint(Double(x[i]), Double(y[i])))
            }
        }
        if cur.count > 1 { out.append(cur) }
        return out
    }
}

enum TrailSmoother {
    struct Settings: Equatable {
        /// Keypoint confidence threshold (analysis parameter `kpConf`).
        var minConf: Float = 0.5
        /// Longest gap (s) bridged by interpolation (analysis parameter `maxGap`).
        var maxGap: Double = 0.5
        /// Fastest plausible movement in pixels per second; nil = 15 body lengths per second.
        var maxSpeedPx: Double?
        /// Gaussian smoothing, standard deviation in seconds.
        var sigma: Double = 0.08
        /// Half-width of the moving-median window for spike rejection, seconds.
        var spikeWindow: Double = 0.25
    }

    static func buildAll(track: PoseTrack, settings: Settings) -> [DisplayTrail] {
        (0..<track.animalCount).map { build(track: track, animal: $0, settings: settings) }
    }

    static func build(track: PoseTrack, animal a: Int, keypoint k: Int = KP.bodyCenter.rawValue,
                      settings s: Settings) -> DisplayTrail {
        let n = track.count
        guard n > 0, a >= 0, a < track.animalCount, k >= 0, k < kKeypointCount else { return .empty }
        let t = track.time
        let w = max(track.frameWidth, 1), h = max(track.frameHeight, 1)
        let diag = (w * w + h * h).squareRoot()

        // 1. Confidence gate.
        var px = [Double](repeating: .nan, count: n)
        var py = [Double](repeating: .nan, count: n)
        for i in 0..<n where track.conf(i, a) > 0 {
            let p = track.point(i, a, k)
            guard p.c >= s.minConf, p.x.isFinite, p.y.isFinite else { continue }
            px[i] = Double(p.x)
            py[i] = Double(p.y)
        }

        let dt = medianInterval(t, fallback: 1 / max(track.fps, 1))
        let body = bodyLength(track, animal: a, minConf: s.minConf) ?? 0.06 * diag
        let floorDeviation = max(0.35 * body, 0.003 * diag)

        // 2. Spike rejection.
        let halfWindow = max(2, Int((s.spikeWindow / dt).rounded()))
        rejectSpikes(&px, &py, t: t, halfWindow: halfWindow, maxSpan: s.spikeWindow * 1.5, floor: floorDeviation)

        // 3 + 4. Segments and short-gap interpolation.
        let vmax = s.maxSpeedPx.map { max($0, 1) } ?? 15 * body
        var seg = [Int32](repeating: -1, count: n)
        var current: Int32 = -1
        var last: Int?
        for i in 0..<n where px[i].isFinite {
            var newSegment = true
            if let l = last {
                let gap = t[i] - t[l]
                let d = hypot(px[i] - px[l], py[i] - py[l])
                let allowed = max(vmax * max(gap, dt), floorDeviation)
                newSegment = !(gap > 0 && gap <= s.maxGap && d <= allowed)
                if !newSegment && i - l > 1 {
                    for j in (l + 1)..<i {
                        let f = (t[j] - t[l]) / gap
                        px[j] = px[l] + (px[i] - px[l]) * f
                        py[j] = py[l] + (py[i] - py[l]) * f
                        seg[j] = current
                    }
                }
            }
            if newSegment { current += 1 }
            seg[i] = current
            last = i
        }

        // 6. Drop segments too short to draw.
        if current >= 0 {
            var sizes = [Int](repeating: 0, count: Int(current) + 1)
            for v in seg where v >= 0 { sizes[Int(v)] += 1 }
            for i in 0..<n where seg[i] >= 0 && sizes[Int(seg[i])] < 3 {
                seg[i] = -1
            }
        }

        // 5. Gaussian-weighted local linear fit inside each segment. In the middle of a segment
        //    this equals a Gaussian moving average; at segment ends it does not pull the line
        //    back toward the inside (no lag where the animal stops or tracking resumes).
        let sigmaSamples = s.sigma / dt
        var sx = px, sy = py
        if sigmaSamples >= 0.5 {
            let radius = max(1, Int((2.5 * sigmaSamples).rounded(.up)))
            let weights = (0...radius).map { d -> Double in exp(-Double(d * d) / (2 * sigmaSamples * sigmaSamples)) }
            for i in 0..<n where seg[i] >= 0 {
                var s0 = 0.0, s1 = 0.0, s2 = 0.0, ax = 0.0, ay = 0.0, atx = 0.0, aty = 0.0
                let lo = max(0, i - radius), hi = min(n - 1, i + radius)
                for j in lo...hi where seg[j] == seg[i] {
                    let wj = weights[abs(j - i)]
                    let tau = t[j] - t[i]
                    s0 += wj
                    s1 += wj * tau
                    s2 += wj * tau * tau
                    ax += wj * px[j]
                    ay += wj * py[j]
                    atx += wj * tau * px[j]
                    aty += wj * tau * py[j]
                }
                guard s0 > 0 else { continue }
                let det = s0 * s2 - s1 * s1
                if det > 1e-9 * s0 * s2 && det > 0 {
                    sx[i] = (s2 * ax - s1 * atx) / det
                    sy[i] = (s2 * ay - s1 * aty) / det
                } else {
                    sx[i] = ax / s0
                    sy[i] = ay / s0
                }
            }
        }

        var outX = [Float](repeating: .nan, count: n)
        var outY = [Float](repeating: .nan, count: n)
        for i in 0..<n where seg[i] >= 0 {
            outX[i] = Float(sx[i] / w)
            outY[i] = Float(sy[i] / h)
        }
        return DisplayTrail(x: outX, y: outY, segment: seg)
    }

    // MARK: Steps

    /// Moving 2-D median / MAD outlier test. All decisions use the original values, then the
    /// rejected samples are cleared together.
    static func rejectSpikes(_ x: inout [Double], _ y: inout [Double], t: [Double],
                             halfWindow: Int, maxSpan: Double, floor: Double) {
        let n = x.count
        guard n > 4 else { return }
        var bad = [Bool](repeating: false, count: n)
        var idx: [Int] = []
        var bx: [Double] = [], by: [Double] = [], bd: [Double] = []
        idx.reserveCapacity(2 * halfWindow + 1)
        bx.reserveCapacity(2 * halfWindow + 1)
        by.reserveCapacity(2 * halfWindow + 1)
        bd.reserveCapacity(2 * halfWindow + 1)
        for i in 0..<n where x[i].isFinite {
            idx.removeAll(keepingCapacity: true)
            let lo = max(0, i - halfWindow), hi = min(n - 1, i + halfWindow)
            for j in lo...hi where x[j].isFinite && abs(t[j] - t[i]) <= maxSpan {
                idx.append(j)
            }
            // Too few neighbours to judge (start of a run, sparse detections): keep the point;
            // the speed gate below still stops it from being joined to a distant neighbour.
            guard idx.count >= 5 else { continue }
            bx.removeAll(keepingCapacity: true)
            by.removeAll(keepingCapacity: true)
            for j in idx {
                bx.append(x[j])
                by.append(y[j])
            }
            let mx = median(&bx), my = median(&by)
            bd.removeAll(keepingCapacity: true)
            for j in idx { bd.append(hypot(x[j] - mx, y[j] - my)) }
            let mad = median(&bd)
            let threshold = max(3.0 * 1.4826 * mad, floor)
            if hypot(x[i] - mx, y[i] - my) > threshold { bad[i] = true }
        }
        for i in 0..<n where bad[i] {
            x[i] = .nan
            y[i] = .nan
        }
    }

    /// Median of a small buffer (sorted in place).
    @inline(__always)
    static func median(_ v: inout [Double]) -> Double {
        v.sort()
        let m = v.count / 2
        return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
    }

    static func medianInterval(_ t: [Double], fallback: Double) -> Double {
        guard t.count > 1 else { return max(fallback, 1e-3) }
        let step = max(1, (t.count - 1) / 2000)
        var d: [Double] = []
        d.reserveCapacity(min(t.count, 2001))
        var i = 0
        while i + 1 < t.count {
            let v = t[i + 1] - t[i]
            if v > 0 && v.isFinite { d.append(v) }
            i += step
        }
        guard !d.isEmpty else { return max(fallback, 1e-3) }
        return max(median(&d), 1e-3)
    }

    /// Typical nose → tail-base distance in pixels (sets the scale of "a big jump").
    static func bodyLength(_ track: PoseTrack, animal a: Int, minConf: Float) -> Double? {
        let n = track.count
        guard n > 0 else { return nil }
        let step = max(1, n / 3000)
        let diag = (track.frameWidth * track.frameWidth + track.frameHeight * track.frameHeight).squareRoot()
        var d: [Double] = []
        var i = 0
        while i < n {
            if track.conf(i, a) > 0 {
                let nose = track.point(i, a, KP.nose.rawValue)
                let tail = track.point(i, a, KP.tailBase.rawValue)
                if nose.c >= minConf && tail.c >= minConf {
                    d.append(Double(hypot(nose.x - tail.x, nose.y - tail.y)))
                }
            }
            i += step
        }
        guard d.count >= 10 else { return nil }
        return min(max(median(&d), 0.01 * diag), 0.4 * diag)
    }
}
