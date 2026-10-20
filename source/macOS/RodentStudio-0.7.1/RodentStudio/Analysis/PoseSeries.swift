// PoseSeries.swift — cleaned keypoint trajectories shared by all analyzers.
//
// Pipeline per keypoint: confidence filter → linear interpolation of short gaps (≤ maxGap) →
// 3-point median (removes single-frame jumps) → centered moving average (NaN-aware).
// Missing samples are NaN. Body length = median nose–tail-base distance, the scale every
// threshold in the app is expressed in, so parameters transfer between cameras and zoom levels.

import Foundation

struct P: Hashable {
    var x: Double
    var y: Double
    static func + (a: P, b: P) -> P { P(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: P, b: P) -> P { P(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: P, s: Double) -> P { P(x: a.x * s, y: a.y * s) }
    var length: Double { hypot(x, y) }
    func dist(_ o: P) -> Double { hypot(x - o.x, y - o.y) }
    var unit: P? { let l = length; return l > 1e-9 ? P(x: x / l, y: y / l) : nil }
    func dot(_ o: P) -> Double { x * o.x + y * o.y }
    func cross(_ o: P) -> Double { x * o.y - y * o.x }
}

enum Signal {
    /// Linear interpolation across NaN runs no longer than `maxGap` samples (interior only).
    static func fillGaps(_ v: [Double], maxGap: Int) -> [Double] {
        guard maxGap > 0, v.count > 2 else { return v }
        var out = v
        var i = 0
        let n = v.count
        while i < n {
            if out[i].isNaN {
                var j = i
                while j < n && out[j].isNaN { j += 1 }
                let gap = j - i
                if i > 0 && j < n && gap <= maxGap {
                    let a = out[i - 1], b = out[j]
                    for k in i..<j {
                        let f = Double(k - i + 1) / Double(gap + 1)
                        out[k] = a + (b - a) * f
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return out
    }

    /// 3-point median, NaN-aware (needs all three finite to change a value).
    static func median3(_ v: [Double]) -> [Double] {
        guard v.count >= 3 else { return v }
        var out = v
        for i in 1..<(v.count - 1) {
            let a = v[i - 1], b = v[i], c = v[i + 1]
            guard a.isFinite, b.isFinite, c.isFinite else { continue }
            out[i] = max(min(a, b), min(max(a, b), c))
        }
        return out
    }

    /// Centered moving average over `window` samples (odd), ignoring NaN; NaN stays NaN.
    static func smooth(_ v: [Double], window: Int) -> [Double] {
        let w = max(1, window | 1)
        guard w > 1, v.count > 2 else { return v }
        let h = w / 2
        let n = v.count
        var sum = [Double](repeating: 0, count: n + 1)
        var cnt = [Int](repeating: 0, count: n + 1)
        for i in 0..<n {
            let ok = v[i].isFinite
            sum[i + 1] = sum[i] + (ok ? v[i] : 0)
            cnt[i + 1] = cnt[i] + (ok ? 1 : 0)
        }
        var out = v
        for i in 0..<n where v[i].isFinite {
            let lo = max(0, i - h), hi = min(n, i + h + 1)
            let c = cnt[hi] - cnt[lo]
            if c > 0 { out[i] = (sum[hi] - sum[lo]) / Double(c) }
        }
        return out
    }

    /// Central-difference derivative using real timestamps.
    static func derivative(_ v: [Double], t: [Double]) -> [Double] {
        let n = v.count
        guard n > 1 else { return [Double](repeating: .nan, count: n) }
        var out = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let a = max(0, i - 1), b = min(n - 1, i + 1)
            let dt = t[b] - t[a]
            if dt > 0, v[a].isFinite, v[b].isFinite { out[i] = (v[b] - v[a]) / dt }
        }
        return out
    }

    static func median(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }.sorted()
        guard !f.isEmpty else { return nil }
        let m = f.count / 2
        return f.count % 2 == 1 ? f[m] : (f[m - 1] + f[m]) / 2
    }

    static func mean(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }
        guard !f.isEmpty else { return nil }
        return f.reduce(0, +) / Double(f.count)
    }

    static func sd(_ v: [Double]) -> Double? {
        let f = v.filter { $0.isFinite }
        guard f.count > 1, let m = mean(f) else { return nil }
        return sqrt(f.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(f.count - 1))
    }

    /// Runs of `true` as half-open index ranges.
    static func runs(_ mask: [Bool]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, m) in mask.enumerated() {
            if m, start == nil { start = i }
            if !m, let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<mask.count) }
        return out
    }

    /// Down-sample a series to at most `maxPoints` points (bin means) for charts.
    static func downsample(t: [Double], v: [Double], maxPoints: Int) -> [SeriesPoint] {
        let n = min(t.count, v.count)
        guard n > 0 else { return [] }
        let step = max(1, Int(ceil(Double(n) / Double(maxPoints))))
        var out: [SeriesPoint] = []
        out.reserveCapacity(n / step + 1)
        var i = 0
        while i < n {
            let j = min(n, i + step)
            var s = 0.0, c = 0
            for k in i..<j where v[k].isFinite { s += v[k]; c += 1 }
            if c > 0 { out.append(SeriesPoint(t: t[i], v: s / Double(c))) }
            i = j
        }
        return out
    }

    /// Circular mean of phases in [0, 1) and the resultant length R (0 = random, 1 = locked).
    static func circular(_ phases: [Double]) -> (mean: Double, r: Double)? {
        let f = phases.filter { $0.isFinite }
        guard !f.isEmpty else { return nil }
        var s = 0.0, c = 0.0
        for p in f { s += sin(2 * .pi * p); c += cos(2 * .pi * p) }
        s /= Double(f.count); c /= Double(f.count)
        var m = atan2(s, c) / (2 * .pi)
        if m < 0 { m += 1 }
        return (m, hypot(s, c))
    }
}

struct PoseSeries {
    let n: Int
    let t: [Double]
    let fps: Double
    let dt: Double
    private(set) var x: [[Double]]
    private(set) var y: [[Double]]
    /// Fraction of frames where the keypoint passed the confidence threshold (before filling).
    let visibility: [Double]
    let bodyLength: Double
    let bodyLengthEstimated: Bool

    init(track: PoseTrack, params: CommonParams) {
        n = track.frameCount
        t = track.times
        let rawFps = track.fps > 1 ? track.fps : 30
        var diffs: [Double] = []
        if n > 1 { for i in 1..<min(n, 600) { diffs.append(track.times[i] - track.times[i - 1]) } }
        let mdt = Signal.median(diffs.filter { $0 > 0 }) ?? (1 / rawFps)
        dt = mdt
        fps = 1 / mdt
        let gap = Int((params.maxGap / mdt).rounded())
        let win = Int((params.smoothing / mdt).rounded())
        var xs: [[Double]] = [], ys: [[Double]] = [], vis: [Double] = []
        for k in Kp.allCases {
            var vx = [Double](repeating: .nan, count: n)
            var vy = [Double](repeating: .nan, count: n)
            var seen = 0
            for i in 0..<n {
                let c = Double(track.c[k.rawValue][i])
                let px = Double(track.x[k.rawValue][i]), py = Double(track.y[k.rawValue][i])
                if c >= params.keypointThreshold, px >= 0, py >= 0 {
                    vx[i] = px; vy[i] = py; seen += 1
                }
            }
            vis.append(n > 0 ? Double(seen) / Double(n) : 0)
            vx = Signal.smooth(Signal.median3(Signal.fillGaps(vx, maxGap: gap)), window: win)
            vy = Signal.smooth(Signal.median3(Signal.fillGaps(vy, maxGap: gap)), window: win)
            xs.append(vx); ys.append(vy)
        }
        x = xs; y = ys; visibility = vis

        var lengths: [Double] = []
        lengths.reserveCapacity(n)
        let nose = Kp.nose.rawValue, tail = Kp.tail.rawValue
        for i in 0..<n where xs[nose][i].isFinite && xs[tail][i].isFinite {
            lengths.append(hypot(xs[nose][i] - xs[tail][i], ys[nose][i] - ys[tail][i]))
        }
        if lengths.count >= max(10, n / 20), let m = Signal.median(lengths), m > 5 {
            bodyLength = m
            bodyLengthEstimated = false
        } else {
            // Fallback: 1/8 of the shorter frame side — flagged in the result notes.
            bodyLength = Double(min(track.width, track.height)) / 8
            bodyLengthEstimated = true
        }
    }

    func p(_ k: Kp, _ i: Int) -> P? {
        let vx = x[k.rawValue][i], vy = y[k.rawValue][i]
        return vx.isFinite && vy.isFinite ? P(x: vx, y: vy) : nil
    }

    /// Speed magnitude in px/s (NaN where unknown).
    func speed(_ k: Kp) -> [Double] {
        let vx = Signal.derivative(x[k.rawValue], t: t)
        let vy = Signal.derivative(y[k.rawValue], t: t)
        return zip(vx, vy).map { hypot($0, $1) }
    }

    /// Per-frame paw displacement speed using the smaller of the backward and forward steps
    /// (px/s). A frame at touch-down or lift-off is then still counted as stationary, which
    /// removes the systematic stance under-estimate of a central difference.
    func stepSpeed(_ k: Kp) -> [Double] {
        var out = [Double](repeating: .nan, count: n)
        let xs = x[k.rawValue], ys = y[k.rawValue]
        for i in 0..<n where xs[i].isFinite {
            var best = Double.infinity
            for j in [i - 1, i + 1] where j >= 0 && j < n && xs[j].isFinite {
                let dt = abs(t[j] - t[i])
                if dt > 0 { best = min(best, hypot(xs[j] - xs[i], ys[j] - ys[i]) / dt) }
            }
            if best.isFinite { out[i] = best }
        }
        return out
    }

    func samples(_ seconds: Double) -> Int { max(1, Int((seconds / dt).rounded())) }

    /// Frame range covering [a, b) seconds.
    func indices(from a: Double, to b: Double) -> Range<Int> {
        let lo = t.firstIndex { $0 >= a } ?? n
        let hi = t.firstIndex { $0 >= b } ?? n
        return lo..<max(lo, hi)
    }

    /// Converts a run of frames to a time interval (end = start of the following frame).
    func interval(_ r: Range<Int>) -> Interval {
        Interval(start: t[r.lowerBound], end: t[r.upperBound - 1] + dt)
    }
}
