// PoseGeometry.swift — ported unchanged from RodentPose iOS 1.0 Geometry.swift (OriginalAppSources).
// Only change: `Angle` is renamed `RPAngle` so it cannot shadow SwiftUI.Angle in this module, and the
// Array<Double> statistics helpers (not used by calibration) are left out.
// Foundation only (no UIKit), so the analysis engine can be unit-tested anywhere.

import Foundation

// MARK: - Vector

struct V2: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(x: Double, y: Double) { self.x = x; self.y = y }

    static let zero = V2(0, 0)

    static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
    static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
    static func * (a: V2, s: Double) -> V2 { V2(a.x * s, a.y * s) }
    static func * (s: Double, a: V2) -> V2 { V2(a.x * s, a.y * s) }
    static func / (a: V2, s: Double) -> V2 { V2(a.x / s, a.y / s) }

    var length: Double { (x * x + y * y).squareRoot() }
    var isFinite: Bool { x.isFinite && y.isFinite }
    var normalized: V2 { let l = length; return l > 1e-12 ? self / l : V2(0, 0) }
    /// Perpendicular (rotated 90°).
    var perp: V2 { V2(-y, x) }

    func dot(_ o: V2) -> Double { x * o.x + y * o.y }
    func cross(_ o: V2) -> Double { x * o.y - y * o.x }
    func distance(to o: V2) -> Double { (self - o).length }

    /// Direction of this vector in degrees, 0° = image right, counter-clockwise positive as seen
    /// on screen (image y points down, so y is flipped). Range 0..<360.
    var screenAngleDeg: Double { RPAngle.wrap360(atan2(-y, x) * 180 / .pi) }

    static func mid(_ a: V2, _ b: V2) -> V2 { V2((a.x + b.x) / 2, (a.y + b.y) / 2) }
}

enum RPAngle {
    static func wrap360(_ d: Double) -> Double {
        guard d.isFinite else { return d }
        var r = d.truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        return r
    }

    /// Wrap to -180..<180.
    static func wrap180(_ d: Double) -> Double {
        guard d.isFinite else { return d }
        var r = (d + 180).truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        return r - 180
    }

    /// Absolute angular difference in degrees (0...180).
    static func diff(_ a: Double, _ b: Double) -> Double { abs(wrap180(a - b)) }

    /// Unwraps an angle series (degrees) so that consecutive values never jump by more than 180°.
    /// NaN gaps are kept as NaN; the series continues from the last valid value after a gap.
    static func unwrap(_ a: [Double]) -> [Double] {
        var out = [Double](repeating: .nan, count: a.count)
        var last: Double?
        var lastRaw: Double?
        for i in a.indices {
            let v = a[i]
            guard v.isFinite else { continue }
            if let l = last, let lr = lastRaw {
                let u = l + wrap180(v - lr)
                out[i] = u
                last = u
            } else {
                out[i] = v
                last = v
            }
            lastRaw = v
        }
        return out
    }

    /// Circular mean (degrees) and mean resultant length of weighted angles.
    static func circularMean(angles: [Double], weights: [Double]? = nil) -> (mean: Double, r: Double)? {
        var sx = 0.0, sy = 0.0, sw = 0.0
        for (i, a) in angles.enumerated() where a.isFinite {
            let w = weights?[i] ?? 1
            guard w.isFinite, w > 0 else { continue }
            let rad = a * .pi / 180
            sx += w * cos(rad)
            sy += w * sin(rad)
            sw += w
        }
        guard sw > 0 else { return nil }
        let mean = wrap360(atan2(sy, sx) * 180 / .pi)
        return (mean, (sx * sx + sy * sy).squareRoot() / sw)
    }
}

// MARK: - Homography

/// 3×3 projective transform (row-major), maps (x, y) → (x', y').
struct Homography: Codable, Equatable {
    var m: [Double]   // 9 values

    func map(_ p: V2) -> V2 {
        let w = m[6] * p.x + m[7] * p.y + m[8]
        guard abs(w) > 1e-12 else { return V2(.nan, .nan) }
        return V2((m[0] * p.x + m[1] * p.y + m[2]) / w, (m[3] * p.x + m[4] * p.y + m[5]) / w)
    }

    /// Homography taking the four `src` points to the four `dst` points (DLT, h33 = 1).
    static func fit(src: [V2], dst: [V2]) -> Homography? {
        guard src.count == 4, dst.count == 4 else { return nil }
        var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = (src[i].x, src[i].y)
            let (u, v) = (dst[i].x, dst[i].y)
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        guard let h = solveLinear(a) else { return nil }
        return Homography(m: h + [1])
    }

    var inverse: Homography? {
        let a = m
        let det = a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])
        guard abs(det) > 1e-15 else { return nil }
        let inv = [
            (a[4] * a[8] - a[5] * a[7]), -(a[1] * a[8] - a[2] * a[7]), (a[1] * a[5] - a[2] * a[4]),
            -(a[3] * a[8] - a[5] * a[6]), (a[0] * a[8] - a[2] * a[6]), -(a[0] * a[5] - a[2] * a[3]),
            (a[3] * a[7] - a[4] * a[6]), -(a[0] * a[7] - a[1] * a[6]), (a[0] * a[4] - a[1] * a[3])
        ].map { $0 / det }
        return Homography(m: inv)
    }

    /// Gaussian elimination with partial pivoting on an augmented n×(n+1) matrix.
    private static func solveLinear(_ input: [[Double]]) -> [Double]? {
        var a = input
        let n = a.count
        for col in 0..<n {
            var pivot = col
            for r in col..<n where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            if pivot != col { a.swapAt(pivot, col) }
            let p = a[col][col]
            for c in col...n { a[col][c] /= p }
            for r in 0..<n where r != col {
                let f = a[r][col]
                if f != 0 { for c in col...n { a[r][c] -= f * a[col][c] } }
            }
        }
        return a.map { $0[n] }
    }
}

// MARK: - Normalized image point

/// Point in normalized image coordinates of the upright video frame (0…1, origin top-left).
struct NPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(x: Double, y: Double) { self.x = x; self.y = y }

    func pixels(_ size: V2) -> V2 { V2(x * size.x, y * size.y) }
    static func from(pixels p: V2, size: V2) -> NPoint {
        NPoint(size.x > 0 ? p.x / size.x : 0, size.y > 0 ? p.y / size.y : 0)
    }
    func clamped() -> NPoint { NPoint(min(max(0, x), 1), min(max(0, y), 1)) }
}

// MARK: - Image → arena mapping

/// Converts upright-frame pixel coordinates into arena coordinates (cm when calibrated).
/// Arena coordinates keep the image orientation (x right, y down) so that drawings match the video.
struct ArenaMapping {
    enum Kind {
        case homography(Homography, Homography)            // image px → cm, cm → image px
        case similarity(cmPerPx: Double, originPx: V2, offsetCM: V2)
        case pixels
    }

    let kind: Kind
    /// Size of the plotting frame in arena units (cm, or px when uncalibrated).
    let extent: V2
    /// Upright frame size in pixels.
    let frameSize: V2

    var isMetric: Bool {
        if case .pixels = kind { return false }
        return true
    }

    var unit: String { isMetric ? "cm" : "px" }

    /// Approximate pixels per arena unit at the arena center (for display).
    var pxPerUnit: Double {
        switch kind {
        case .pixels: return 1
        case .similarity(let s, _, _): return s > 0 ? 1 / s : 1
        case .homography(_, let inv):
            let c = extent / 2
            let a = inv.map(c), b = inv.map(c + V2(1, 0)), d = inv.map(c + V2(0, 1))
            return ((a.distance(to: b) + a.distance(to: d)) / 2)
        }
    }

    func toArena(_ px: V2) -> V2 {
        switch kind {
        case .pixels: return px
        case .similarity(let s, let o, let off): return (px - o) * s + off
        case .homography(let h, _): return h.map(px)
        }
    }

    func toImage(_ a: V2) -> V2 {
        switch kind {
        case .pixels: return a
        case .similarity(let s, let o, let off): return s > 0 ? (a - off) / s + o : a
        case .homography(_, let inv): return inv.map(a)
        }
    }

    /// Normalized image point → arena units.
    func toArena(_ n: NPoint) -> V2 { toArena(n.pixels(frameSize)) }

    /// Arena units → normalized image point.
    func toNormalized(_ a: V2) -> NPoint { NPoint.from(pixels: toImage(a), size: frameSize) }

    static func pixelsOnly(frameSize: V2) -> ArenaMapping {
        ArenaMapping(kind: .pixels, extent: frameSize, frameSize: frameSize)
    }
}

// MARK: - Small numeric helpers

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }

/// Distance from point p to segment ab, and the projection parameter t (0 at a, 1 at b).
func pointSegment(_ p: V2, _ a: V2, _ b: V2) -> (distance: Double, t: Double) {
    let ab = b - a
    let len2 = ab.dot(ab)
    guard len2 > 1e-12 else { return (p.distance(to: a), 0) }
    let t = (p - a).dot(ab) / len2
    let tc = clamp(t, 0, 1)
    return (p.distance(to: a + ab * tc), t)
}

/// Even-odd point-in-polygon test.
func polygonContains(_ poly: [V2], _ p: V2) -> Bool {
    guard poly.count >= 3 else { return false }
    var inside = false
    var j = poly.count - 1
    for i in 0..<poly.count {
        let a = poly[i], b = poly[j]
        if (a.y > p.y) != (b.y > p.y) {
            let xCross = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
            if p.x < xCross { inside.toggle() }
        }
        j = i
    }
    return inside
}
