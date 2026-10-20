// Kinematics.swift — from raw keypoints to clean, arena-unit time series:
// confidence mask → jump filter → short-gap interpolation → smoothing → derived features
// (speed, head direction, angular head velocity, body axis, body length, motion index).

import Foundation

// MARK: - Time base

struct TimeBase {
    let t: [Double]
    /// Duration represented by each sample (time to the next sample, capped for gaps).
    let dur: [Double]
    let inWindow: [Bool]
    let start: Double
    let end: Double
    /// Median sample interval.
    let dt: Double

    var count: Int { t.count }

    /// Total time where `mask` is true inside the analysis window.
    func total(_ mask: [Bool]) -> Double {
        var s = 0.0
        for i in 0..<min(mask.count, count) where mask[i] && inWindow[i] { s += dur[i] }
        return s
    }

    var windowDuration: Double {
        var s = 0.0
        for i in 0..<count where inWindow[i] { s += dur[i] }
        return s
    }

    /// First time (relative to the window start) where `mask` is true inside the window.
    func firstTime(_ mask: [Bool]) -> Double? {
        for i in 0..<min(mask.count, count) where mask[i] && inWindow[i] { return t[i] - windowStartTime }
        return nil
    }

    /// Time of the first sample inside the window (the reference for latencies).
    var windowStartTime: Double {
        for i in 0..<count where inWindow[i] { return max(start, t[i]) }
        return start
    }

    /// First index with t ≥ time.
    func index(atOrAfter time: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if t[mid] < time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Indices with start ≤ t < end, clipped to the analysis window.
    func indices(from a: Double, to b: Double) -> Range<Int> {
        let i0 = index(atOrAfter: a)
        let i1 = index(atOrAfter: b)
        return i0 ..< max(i0, i1)
    }

    static func make(times: [Double], windowStart: Double, windowLength: Double) -> TimeBase {
        let n = times.count
        var diffs: [Double] = []
        diffs.reserveCapacity(max(0, n - 1))
        for i in 0..<max(0, n - 1) { diffs.append(times[i + 1] - times[i]) }
        let dt = max(diffs.finiteMedian ?? (1.0 / 30.0), 1e-4)
        var dur = [Double](repeating: dt, count: n)
        for i in 0..<max(0, n - 1) { dur[i] = min(max(0, times[i + 1] - times[i]), 3 * dt) }
        let end = windowLength > 0 ? windowStart + windowLength : Double.infinity
        let inWin = times.map { $0 >= windowStart - 1e-9 && $0 < end }
        return TimeBase(t: times, dur: dur, inWindow: inWin, start: windowStart, end: end, dt: dt)
    }
}

// MARK: - Series

struct Series2 {
    var x: [Double]
    var y: [Double]

    init(count: Int) {
        x = [Double](repeating: .nan, count: count)
        y = [Double](repeating: .nan, count: count)
    }

    init(x: [Double], y: [Double]) { self.x = x; self.y = y }

    @inline(__always)
    func p(_ i: Int) -> V2? {
        let a = x[i], b = y[i]
        return a.isFinite && b.isFinite ? V2(a, b) : nil
    }

    @inline(__always)
    func v(_ i: Int) -> V2 { V2(x[i], y[i]) }

    var count: Int { x.count }
}

// MARK: - Per-animal features

struct AnimalFeatures {
    var kp: [Series2]
    /// Keypoint present (confidence above threshold) before interpolation.
    var rawValid: [[Bool]]
    var detected: [Bool]
    var earMid: Series2
    var speed: [Double]
    var noseSpeed: [Double]
    var motion: [Double]
    var hd: [Double]
    var hdU: [Double]
    var ahv: [Double]
    var body: [Double]
    var bodyU: [Double]
    var headBody: [Double]
    var bodyLength: [Double]

    @inline(__always)
    func pos(_ k: KP, _ i: Int) -> V2? { kp[k.rawValue].p(i) }

    /// Base of the head vector (ear midpoint, else neck).
    func headBase(_ i: Int) -> V2? { earMid.p(i) ?? pos(.neck, i) }

    var count: Int { speed.count }
}

struct FeatureSet {
    let tb: TimeBase
    let animals: [AnimalFeatures]
    let mapping: ArenaMapping
    let frameIndex: [Int]
    var unit: String { mapping.unit }
    var isMetric: Bool { mapping.isMetric }
}

// MARK: - Builder

enum Kinematics {
    static func build(track: PoseTrack, session: Session) -> FeatureSet {
        let mapping = ArenaMapper.mapping(session.calibration, frameSize: track.frameSize)
        let p = session.params
        let tb = TimeBase.make(times: track.time, windowStart: p.windowStart, windowLength: p.windowLength)
        var animals: [AnimalFeatures] = []
        for a in 0..<track.animalCount {
            animals.append(buildAnimal(track: track, animal: a, mapping: mapping, tb: tb, params: p))
        }
        return FeatureSet(tb: tb, animals: animals, mapping: mapping, frameIndex: track.frameIndex.map(Int.init))
    }

    static func buildAnimal(track: PoseTrack, animal a: Int, mapping: ArenaMapping, tb: TimeBase, params p: AnalysisParams) -> AnimalFeatures {
        let n = track.count
        let conf = Float(p.kpConf)
        var series: [Series2] = []
        var rawValid: [[Bool]] = []
        let detected = (0..<n).map { track.conf($0, a) > 0 }
        let smoothFrames = max(1, Int((p.smoothing / tb.dt).rounded()))
        let window = smoothFrames % 2 == 0 ? smoothFrames + 1 : smoothFrames

        for k in 0..<kKeypointCount {
            var s = Series2(count: n)
            var valid = [Bool](repeating: false, count: n)
            for i in 0..<n where detected[i] {
                let pt = track.point(i, a, k)
                guard pt.c >= conf else { continue }
                let q = mapping.toArena(V2(Double(pt.x), Double(pt.y)))
                guard q.isFinite else { continue }
                s.x[i] = q.x
                s.y[i] = q.y
                valid[i] = true
            }
            if mapping.isMetric && p.maxJumpSpeed > 0 {
                jumpFilter(&s, &valid, t: tb.t, maxSpeed: p.maxJumpSpeed)
            }
            interpolate(&s, t: tb.t, maxGap: p.maxGap)
            if window > 1 { s = smooth(s, window: window) }
            series.append(s)
            rawValid.append(valid)
        }

        // Ear midpoint.
        var earMid = Series2(count: n)
        for i in 0..<n {
            if let l = series[KP.leftEar.rawValue].p(i), let r = series[KP.rightEar.rawValue].p(i) {
                let m = V2.mid(l, r)
                earMid.x[i] = m.x
                earMid.y[i] = m.y
            }
        }

        let bodyS = series[KP.bodyCenter.rawValue]
        let noseS = series[KP.nose.rawValue]
        let speed = derivativeSpeed(bodyS, t: tb.t)
        let noseSpeed = derivativeSpeed(noseS, t: tb.t)

        // Motion index for freezing: displacement over a 0.5 s window, averaged over core points.
        let half = max(1, Int((0.25 / tb.dt).rounded()))
        let core: [Series2] = [noseS, earMid, bodyS, series[KP.tailBase.rawValue]]
        var motion = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let i0 = max(0, i - half), i1 = min(n - 1, i + half)
            guard i1 > i0 else { continue }
            let dtw = tb.t[i1] - tb.t[i0]
            guard dtw > 0 else { continue }
            var sum = 0.0, m = 0.0
            for s in core {
                if let a0 = s.p(i0), let a1 = s.p(i1) {
                    sum += a0.distance(to: a1) / dtw
                    m += 1
                }
            }
            if m > 0 { motion[i] = sum / m }
        }

        // Head direction, body axis, head–body angle, body length.
        var hd = [Double](repeating: .nan, count: n)
        var body = [Double](repeating: .nan, count: n)
        var headBody = [Double](repeating: .nan, count: n)
        var bodyLength = [Double](repeating: .nan, count: n)
        let neckS = series[KP.neck.rawValue]
        let tailS = series[KP.tailBase.rawValue]
        for i in 0..<n {
            if let nose = noseS.p(i) {
                if let base = earMid.p(i) ?? neckS.p(i) {
                    let v = nose - base
                    if v.length > 1e-6 { hd[i] = v.screenAngleDeg }
                }
            }
            var axis: V2?
            if let tail = tailS.p(i) {
                if let neck = neckS.p(i) { axis = neck - tail } else if let b = bodyS.p(i) { axis = b - tail }
            } else if let b = bodyS.p(i), let neck = neckS.p(i) {
                axis = neck - b
            }
            if let axis, axis.length > 1e-6 { body[i] = axis.screenAngleDeg }
            if hd[i].isFinite && body[i].isFinite { headBody[i] = Angle.wrap180(hd[i] - body[i]) }
            if let nose = noseS.p(i), let tail = tailS.p(i) { bodyLength[i] = nose.distance(to: tail) }
        }
        let hdU = Angle.unwrap(hd)
        let bodyU = Angle.unwrap(body)
        let ahv = derivative(hdU, t: tb.t)

        return AnimalFeatures(kp: series, rawValid: rawValid, detected: detected, earMid: earMid,
                              speed: speed, noseSpeed: noseSpeed, motion: motion,
                              hd: hd, hdU: hdU, ahv: ahv, body: body, bodyU: bodyU,
                              headBody: headBody, bodyLength: bodyLength)
    }

    // MARK: Steps

    /// Removes points that would require an implausible speed relative to the last accepted point.
    static func jumpFilter(_ s: inout Series2, _ valid: inout [Bool], t: [Double], maxSpeed: Double) {
        var last: (V2, Double)?
        for i in 0..<s.count {
            guard let p = s.p(i) else { continue }
            if let (q, tq) = last {
                let dt = t[i] - tq
                if dt > 0 && dt < 0.5 && p.distance(to: q) / dt > maxSpeed {
                    s.x[i] = .nan
                    s.y[i] = .nan
                    valid[i] = false
                    continue
                }
            }
            last = (p, t[i])
        }
    }

    /// Linear interpolation across gaps no longer than `maxGap` seconds.
    static func interpolate(_ s: inout Series2, t: [Double], maxGap: Double) {
        let n = s.count
        var prev: Int?
        var i = 0
        while i < n {
            if s.x[i].isFinite {
                if let p = prev, i - p > 1, t[i] - t[p] <= maxGap {
                    let span = t[i] - t[p]
                    for j in (p + 1)..<i {
                        let f = span > 0 ? (t[j] - t[p]) / span : 0
                        s.x[j] = s.x[p] + (s.x[i] - s.x[p]) * f
                        s.y[j] = s.y[p] + (s.y[i] - s.y[p]) * f
                    }
                }
                prev = i
            }
            i += 1
        }
    }

    /// Centered moving average over finite neighbours; missing samples stay missing.
    static func smooth(_ s: Series2, window: Int) -> Series2 {
        let n = s.count
        let h = window / 2
        var out = Series2(count: n)
        for i in 0..<n where s.x[i].isFinite {
            var sx = 0.0, sy = 0.0, m = 0.0
            for j in max(0, i - h)...min(n - 1, i + h) where s.x[j].isFinite {
                sx += s.x[j]; sy += s.y[j]; m += 1
            }
            out.x[i] = sx / m
            out.y[i] = sy / m
        }
        return out
    }

    /// Speed (units/s) by central difference, falling back to one-sided differences.
    static func derivativeSpeed(_ s: Series2, t: [Double]) -> [Double] {
        let n = s.count
        var v = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            let a = i > 0 ? s.p(i - 1) : nil
            let b = i + 1 < n ? s.p(i + 1) : nil
            if let a, let b, t[i + 1] > t[i - 1] {
                v[i] = a.distance(to: b) / (t[i + 1] - t[i - 1])
            } else if let c = s.p(i) {
                if let b, t[i + 1] > t[i] { v[i] = c.distance(to: b) / (t[i + 1] - t[i]) }
                else if let a, t[i] > t[i - 1] { v[i] = a.distance(to: c) / (t[i] - t[i - 1]) }
            }
        }
        return v
    }

    /// Derivative of a scalar series (units/s).
    static func derivative(_ x: [Double], t: [Double]) -> [Double] {
        let n = x.count
        var v = [Double](repeating: .nan, count: n)
        guard n > 2 else { return v }
        for i in 1..<(n - 1) where x[i - 1].isFinite && x[i + 1].isFinite && t[i + 1] > t[i - 1] {
            v[i] = (x[i + 1] - x[i - 1]) / (t[i + 1] - t[i - 1])
        }
        return v
    }
}

// MARK: - Bouts

struct Bout: Hashable {
    var start: Double
    var end: Double
    var i0: Int
    var i1: Int
    var duration: Double { end - start }
}

enum Bouts {
    /// Contiguous runs of `mask` inside the analysis window. Gaps ≤ `mergeGap` are merged first,
    /// then bouts shorter than `minDuration` are dropped.
    static func find(_ mask: [Bool], _ tb: TimeBase, minDuration: Double = 0, mergeGap: Double = 0) -> [Bout] {
        var raw: [Bout] = []
        var i = 0
        let n = min(mask.count, tb.count)
        while i < n {
            if mask[i] && tb.inWindow[i] {
                let s = i
                while i + 1 < n && mask[i + 1] && tb.inWindow[i + 1] { i += 1 }
                raw.append(Bout(start: tb.t[s], end: tb.t[i] + tb.dur[i], i0: s, i1: i))
            }
            i += 1
        }
        var merged: [Bout] = []
        for b in raw {
            if var last = merged.last, b.start - last.end <= mergeGap {
                last.end = b.end
                last.i1 = b.i1
                merged[merged.count - 1] = last
            } else {
                merged.append(b)
            }
        }
        return merged.filter { $0.duration >= minDuration - 1e-9 }
    }

    /// Frame mask covered by the bouts.
    static func mask(_ bouts: [Bout], count: Int) -> [Bool] {
        var m = [Bool](repeating: false, count: count)
        for b in bouts { for i in b.i0...min(b.i1, count - 1) { m[i] = true } }
        return m
    }

    /// Keeps only runs lasting at least `minDuration` (merging gaps ≤ `mergeGap`).
    static func sustained(_ mask: [Bool], _ tb: TimeBase, minDuration: Double, mergeGap: Double = 0) -> [Bool] {
        Self.mask(find(mask, tb, minDuration: minDuration, mergeGap: mergeGap), count: mask.count)
    }

    /// Number of false → true transitions inside the window (entries). Starting inside the zone
    /// is not counted as an entry.
    static func entries(_ mask: [Bool], _ tb: TimeBase) -> Int {
        var count = 0
        var prev: Bool?
        for i in 0..<min(mask.count, tb.count) where tb.inWindow[i] {
            if let p = prev, !p, mask[i] { count += 1 }
            prev = mask[i]
        }
        return count
    }
}
