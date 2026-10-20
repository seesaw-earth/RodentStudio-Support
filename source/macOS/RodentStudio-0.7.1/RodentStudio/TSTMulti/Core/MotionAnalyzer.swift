import Foundation

/// Raw per-frame measurements for one chamber.
public struct FrameMeasure: Sendable {
    public var time: Double
    public var pixelChange: Double   // changed pixels vs previous frame (NaN for first frame)
    public var shapeChange: Double   // aligned silhouette XOR pixels (NaN if no mouse now or before)
    public var area: Double          // mouse area (0 = not found)
    public var cx: Double            // centroid in processed-image coordinates (NaN if not found)
    public var cy: Double
    /// Box metric: changed pixels in the chamber's motion box after swing alignment (NaN if unknown),
    /// whether the mouse is in the box, and the chamber's reference body size in pixels (normaliser).
    public var boxChange: Double = .nan
    public var boxPresent: Bool = false
    public var boxBody: Double = 0
}

/// Pose of the dark mass in a box: centroid and principal-axis angle, weighted by how much darker than
/// the chamber threshold each pixel is. No segmentation involved.
struct MassPose {
    var cx: Double, cy: Double, theta: Double
}

enum BoxMotion {
    /// Mouse pixels in the box (darker than the threshold for dark mice, brighter for light mice).
    static func mousePixels(_ roi: GrayImage, box b: PixelRect, threshold t: Int, dark: Bool) -> Int {
        var n = 0
        for y in b.y0..<b.y1 {
            let row = y * roi.width
            for x in b.x0..<b.x1 {
                let v = Int(roi.pixels[row + x])
                if dark ? v <= t : v > t { n += 1 }
            }
        }
        return n
    }

    static func pose(_ roi: GrayImage, box b: PixelRect, threshold t: Int, dark: Bool) -> MassPose? {
        var s = 0.0, sx = 0.0, sy = 0.0
        for y in b.y0..<b.y1 {
            let row = y * roi.width
            for x in b.x0..<b.x1 {
                let v = Int(roi.pixels[row + x])
                let wgt = Double(max(0, dark ? t - v : v - t))
                if wgt > 0 { s += wgt; sx += wgt * Double(x); sy += wgt * Double(y) }
            }
        }
        guard s > 0 else { return nil }
        let cx = sx / s, cy = sy / s
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0
        for y in b.y0..<b.y1 {
            let row = y * roi.width
            let dy = Double(y) - cy
            for x in b.x0..<b.x1 {
                let v = Int(roi.pixels[row + x])
                let wgt = Double(max(0, dark ? t - v : v - t))
                if wgt > 0 {
                    let dx = Double(x) - cx
                    mu20 += wgt * dx * dx; mu02 += wgt * dy * dy; mu11 += wgt * dx * dy
                }
            }
        }
        return MassPose(cx: cx, cy: cy, theta: 0.5 * atan2(2 * mu11, mu20 - mu02))
    }

    /// Pixels in the box whose grey level changed by more than `diff` after warping `prev` onto `cur`
    /// (rotation about the centroid + translation, bilinear). Without poses: plain differencing.
    static func change(prev: GrayImage, cur: GrayImage, box b: PixelRect, diff: Int,
                       prevPose: MassPose?, curPose: MassPose?) -> Double {
        let w = cur.width, h = cur.height
        var n = 0
        guard let p = prevPose, let c = curPose else {
            for y in b.y0..<b.y1 {
                let row = y * w
                for x in b.x0..<b.x1 where abs(Int(cur.pixels[row + x]) - Int(prev.pixels[row + x])) > diff { n += 1 }
            }
            return Double(n)
        }
        var d = c.theta - p.theta              // axis angle is defined modulo π
        d = (d + .pi / 2).truncatingRemainder(dividingBy: .pi)
        if d < 0 { d += .pi }
        d -= .pi / 2
        let cs = cos(-d), sn = sin(-d)
        let threshold = Double(diff)
        for y in b.y0..<b.y1 {
            let row = y * w
            let dy = Double(y) - c.cy
            for x in b.x0..<b.x1 {
                let dx = Double(x) - c.cx
                // source point in the previous frame: R(-d)·(p − c_cur) + c_prev, clamped to the image
                let sx = min(Double(w - 1), max(0, cs * dx - sn * dy + p.cx))
                let sy = min(Double(h - 1), max(0, sn * dx + cs * dy + p.cy))
                let x0 = Int(sx), y0 = Int(sy)
                let x1 = min(w - 1, x0 + 1), y1 = min(h - 1, y0 + 1)
                let fx = sx - Double(x0), fy = sy - Double(y0)
                let a = Double(prev.pixels[y0 * w + x0]), bb = Double(prev.pixels[y0 * w + x1])
                let cc = Double(prev.pixels[y1 * w + x0]), dd = Double(prev.pixels[y1 * w + x1])
                let top = a + (bb - a) * fx
                let bottom = cc + (dd - cc) * fx
                let warped = top + (bottom - top) * fy
                if abs(Double(cur.pixels[row + x]) - warped) > threshold { n += 1 }
            }
        }
        return Double(n)
    }
}

/// Mouse silhouette in ROI coordinates plus its pose.
struct Silhouette {
    var mask: BinaryMask
    var area: Int
    var cx: Double, cy: Double
    var theta: Double          // body-axis angle (radians)
    var radius: Double         // max distance of a body pixel from the centroid
    var bbox: PixelRect        // half-open, ROI coordinates
}

public enum MouseSegmenter {
    /// Segment the mouse inside an (already blurred) ROI.
    static func segment(_ roi: GrayImage, threshold t: Int, dark: Bool,
                        openRadius: Int, minArea: Int) -> Silhouette? {
        var m = BinaryMask(threshold: roi, at: t, dark: dark)
        m = m.opened(radius: openRadius)   // strips thin tail / tape / string
        m = m.closed(radius: 3)
        let (labels, comps) = Components.label(m)
        guard let best = comps.max(by: { $0.area < $1.area }), best.area >= minArea else { return nil }
        let filled = Components.filledMask(labels: labels, width: m.width, height: m.height, component: best)
        var n = 0, sx = 0.0, sy = 0.0
        for y in best.y0...best.y1 {
            for x in best.x0...best.x1 where filled.bits[y * m.width + x] == 1 {
                n += 1; sx += Double(x); sy += Double(y)
            }
        }
        let cx = sx / Double(n), cy = sy / Double(n)
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0, r2 = 0.0
        for y in best.y0...best.y1 {
            for x in best.x0...best.x1 where filled.bits[y * m.width + x] == 1 {
                let dx = Double(x) - cx, dy = Double(y) - cy
                mu20 += dx * dx; mu02 += dy * dy; mu11 += dx * dy
                r2 = max(r2, dx * dx + dy * dy)
            }
        }
        let theta = 0.5 * atan2(2 * mu11, mu20 - mu02)
        return Silhouette(mask: filled, area: n, cx: cx, cy: cy, theta: theta, radius: r2.squareRoot(),
                          bbox: PixelRect(x0: best.x0, y0: best.y0, x1: best.x1 + 1, y1: best.y1 + 1))
    }

    /// Geometry-guided segmentation for dark mice hanging in fixed, separate chambers.
    /// A detector box is used as a *prior*, never as the pixel mask.  An optional accepted
    /// previous silhouette keeps the search window on a swinging animal.  In particular,
    /// the entire chamber wall must never win simply because it is the largest dark blob.
    static func segmentTracked(_ roi: GrayImage, threshold globalThreshold: Int, dark: Bool,
                               openRadius: Int, minArea: Int, reference: DetBox?,
                               previous: Silhouette?, refine: Bool = false) -> Silhouette? {
        let w = roi.width, h = roi.height
        guard w >= 12, h >= 12 else { return nil }

        let refX = reference?.cx ?? Double(w) * 0.5
        let refY = reference?.cy ?? Double(h) * 0.5
        let refW = max(8.0, reference?.width ?? Double(w) * 0.27)
        let refH = max(12.0, reference?.height ?? Double(h) * 0.37)
        let centerX = previous?.cx ?? refX
        let centerY = previous?.cy ?? refY
        // Include a normal pendulum swing without opening up the entire chamber.
        let halfX = max(0.23 * Double(w), 1.05 * refW)
        let halfY = max(0.31 * Double(h), 0.87 * refH)
        let search = PixelRect(x0: max(1, Int(floor(centerX - halfX))),
                               y0: max(1, Int(floor(centerY - halfY))),
                               x1: min(w - 1, Int(ceil(centerX + halfX + 1))),
                               y1: min(h - 1, Int(ceil(centerY + halfY + 1))))
        guard search.width >= 5, search.height >= 5 else { return nil }

        // Local Otsu: compute the threshold near the mouse, not from the chamber wall.
        // The global offset is still respected via the caller-provided threshold.
        var localHist = [Int](repeating: 0, count: 256)
        for y in search.y0..<search.y1 {
            let start = y * w
            for x in search.x0..<search.x1 { localHist[Int(roi.pixels[start + x])] += 1 }
        }
        let local = ImageOps.otsu(histogram: localHist)
        let base = dark ? min(globalThreshold, local + 6) : max(globalThreshold, local - 6)
        let steps = dark ? [0, -12, -24, -36, -48] : [0, 12, 24, 36, 48]
        let maxArea = min(0.26 * Double(w * h),
                          reference.map { max(2.1 * $0.area, Double(minArea * 5)) } ?? 0.18 * Double(w * h))
        let expectedArea = reference.map { max(Double(minArea), 0.63 * $0.area) }
        let openR = max(1, min(openRadius, max(1, Int(refW / 7))))

        for delta in steps {
            let t = min(254, max(1, base + delta))
            // Threshold *only* in the predicted local window. Removing boundary-connected
            // components below prevents a dark wall from being called an immobile mouse.
            var raw = BinaryMask(width: w, height: h)
            for y in search.y0..<search.y1 {
                let row = y * w
                for x in search.x0..<search.x1 {
                    let v = Int(roi.pixels[row + x])
                    raw.bits[row + x] = (dark ? v <= t : v > t) ? 1 : 0
                }
            }
            let mask = raw.opened(radius: openR).closed(radius: max(1, min(2, openR)))
            let (labels, components) = Components.label(mask)
            var best: Component?
            var bestScore = -Double.infinity
            for c in components {
                let a = Double(c.area)
                let cw = Double(c.x1 - c.x0 + 1)
                let ch = Double(c.y1 - c.y0 + 1)
                guard a >= Double(minArea), a <= maxArea else { continue }
                guard c.x0 > 1, c.x1 < w - 2, c.y0 > 1, c.y1 < h - 2 else { continue }
                // Also reject candidates glued to the search-window edge; if the mouse
                // moved there we will try to reacquire on later frames, not score a crop.
                guard c.x0 > search.x0 + 1, c.x1 < search.x1 - 2,
                      c.y0 > search.y0 + 1, c.y1 < search.y1 - 2 else { continue }
                guard cw <= 0.75 * Double(w), ch <= 0.94 * Double(h),
                      cw <= 2.35 * refW, ch >= max(4, 0.055 * Double(h)),
                      a / (cw * ch) >= 0.20 else { continue }
                let dx = (c.cx - centerX) / max(7, halfX)
                let dy = (c.cy - centerY) / max(7, halfY)
                guard dx * dx + dy * dy < 0.85 else { continue }
                if let old = previous {
                    let movement = hypot(c.cx - old.cx, c.cy - old.cy)
                    guard movement < max(0.36 * Double(w), 1.30 * refW) else { continue }
                    let ratio = a / Double(old.area)
                    guard ratio >= 0.31 && ratio <= 2.7 else { continue }
                }
                let distancePenalty = 3.8 * (dx * dx + dy * dy)
                let areaPenalty: Double
                if let expectedArea {
                    areaPenalty = abs(log(a / expectedArea))
                } else if let previous {
                    areaPenalty = abs(log(a / Double(previous.area)))
                } else {
                    areaPenalty = 0
                }
                // Score is deliberately independent of raw component area. Otherwise
                // a large piece of a shadowed wall would win against the mouse.
                let score = -distancePenalty - 0.65 * areaPenalty
                if score > bestScore { bestScore = score; best = c }
            }
            if let best {
                let silhouette = makeSilhouette(labels: labels, component: best, width: w, height: h)
                // Filling enclosed holes can grow a ring-shaped wall artifact dramatically.
                // Re-check the *filled* mask before accepting any candidate.
                if silhouette.area >= minArea && Double(silhouette.area) <= maxArea {
                    guard refine else { return silhouette }
                    return refineOutline(silhouette, roi: roi, search: search, coreThreshold: t, dark: dark,
                                         referenceWidth: refW, maxArea: maxArea)
                }
            }
        }
        // No acceptable mouse mask: report missing data, NOT a background patch.
        return nil
    }

    /// Refined outline. The body selected above is reliable (walls and shadows are rejected) but its edge
    /// is not: the square opening that strips the tail also removes everything narrower than 2r+1 px —
    /// limbs, paws, snout, the fur fringe — and leaves a blocky outline. Limb movement is exactly what
    /// separates struggling from immobility, so that loss biases scoring towards "immobile".
    ///
    /// 1. Grow from the selected body into pixels at least halfway from the local background level to
    ///    the local mouse level (the 50 % edge is where a blurred step edge really is), at most `reach`
    ///    px (8-connected), so a connected shadow or the tail cannot be followed far.
    /// 2. Drop 1–2 px threads (tail, tape string) with a radius-1 opening of the grown part only.
    /// 3. Close by 1 px, keep the piece connected to the body, fill holes.
    /// 4. If the result is implausible (smaller than the body, > 2× its area, or above `maxArea`), the
    ///    original silhouette is returned unchanged.
    /// Validated on synthetic frames (scratch Python port): IoU with the true outline 0.85 → 0.93–0.95,
    /// limb pixels kept 3–5 % → 76–80 %, tail excluded; motion of a 20° hind-limb kick 0.01 % → 4.2 %,
    /// still mouse 0 %, passive 4° swing 0.6 %.
    static func refineOutline(_ core: Silhouette, roi: GrayImage, search: PixelRect, coreThreshold t: Int,
                              dark: Bool, referenceWidth refW: Double, maxArea: Double) -> Silhouette {
        let w = roi.width, h = roi.height
        let reach = max(3, min(12, Int((0.4 * refW).rounded())))
        // "Darkness" in which the mouse is always the low end (dark mice as is, light mice inverted).
        func darkness(_ v: UInt8) -> Int { dark ? Int(v) : 255 - Int(v) }
        let coreLimit = dark ? t : 254 - t

        // Mouse and background levels in the search window (split at the local Otsu threshold).
        var hist = [Int](repeating: 0, count: 256)
        for y in search.y0..<search.y1 {
            let row = y * w
            for x in search.x0..<search.x1 { hist[darkness(roi.pixels[row + x])] += 1 }
        }
        let split = ImageOps.otsu(histogram: hist)
        var nMouse = 0, sumMouse = 0, nBack = 0, sumBack = 0
        for v in 0..<256 {
            if v <= split { nMouse += hist[v]; sumMouse += v * hist[v] } else { nBack += hist[v]; sumBack += v * hist[v] }
        }
        guard nMouse > 0, nBack > 0 else { return core }
        let mouseLevel = Double(sumMouse) / Double(nMouse)
        let backgroundLevel = Double(sumBack) / Double(nBack)
        let contrast = backgroundLevel - mouseLevel
        guard contrast >= 10 else { return core }
        let weakLimit = max(coreLimit, min(Int(backgroundLevel - 0.5 * contrast), Int(backgroundLevel) - 6))

        // Work window: the search window plus the reach, kept off the ROI border.
        let wx0 = max(1, search.x0 - reach), wy0 = max(1, search.y0 - reach)
        let wx1 = min(w - 1, search.x1 + reach), wy1 = min(h - 1, search.y1 + reach)
        let ww = wx1 - wx0, wh = wy1 - wy0
        guard ww > 2, wh > 2 else { return core }

        // Breadth-first growth from the body, chessboard distance ≤ reach.
        var dist = [UInt8](repeating: 255, count: ww * wh)
        var queue: [Int] = []
        queue.reserveCapacity(core.area * 2)
        var seed = -1
        for y in wy0..<wy1 {
            let row = y * w
            for x in wx0..<wx1 where core.mask.bits[row + x] == 1 {
                let k = (y - wy0) * ww + (x - wx0)
                dist[k] = 0
                queue.append(k)
                if seed < 0 { seed = k }
            }
        }
        guard seed >= 0 else { return core }
        var head = 0
        while head < queue.count {
            let k = queue[head]
            head += 1
            let dk = Int(dist[k])
            if dk >= reach { continue }
            let x = k % ww, y = k / ww
            for dy in -1...1 {
                let ny = y + dy
                if ny < 0 || ny >= wh { continue }
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx
                    if nx < 0 || nx >= ww { continue }
                    let q = ny * ww + nx
                    if dist[q] != 255 { continue }
                    if darkness(roi.pixels[(ny + wy0) * w + (nx + wx0)]) > weakLimit { continue }
                    dist[q] = UInt8(dk + 1)
                    queue.append(q)
                }
            }
        }

        var grown = BinaryMask(width: ww, height: wh)
        var merged = BinaryMask(width: ww, height: wh)
        for k in 0..<(ww * wh) where dist[k] != 255 {
            grown.bits[k] = 1
            if dist[k] == 0 { merged.bits[k] = 1 }
        }
        let withoutThreads = grown.opened(radius: 1)
        for k in 0..<(ww * wh) where withoutThreads.bits[k] == 1 { merged.bits[k] = 1 }
        merged = merged.closed(radius: 1)
        let (labels, components) = Components.label(merged)
        let seedLabel = labels[seed]
        guard seedLabel > 0, let piece = components.first(where: { $0.label == seedLabel }) else { return core }
        let kept = Components.filledMask(labels: labels, width: ww, height: wh, component: piece)

        var full = BinaryMask(width: w, height: h)
        var n = 0
        for y in 0..<wh {
            for x in 0..<ww where kept.bits[y * ww + x] == 1 {
                full.bits[(y + wy0) * w + (x + wx0)] = 1
                n += 1
            }
        }
        guard n >= core.area, Double(n) <= maxArea, Double(n) <= 2.0 * Double(core.area) else { return core }
        return silhouette(of: full, within: PixelRect(x0: wx0, y0: wy0, x1: wx1, y1: wy1)) ?? core
    }

    /// Silhouette statistics of a mask whose pixels all lie inside `r`.
    private static func silhouette(of mask: BinaryMask, within r: PixelRect) -> Silhouette? {
        let w = mask.width
        var n = 0, sx = 0.0, sy = 0.0
        var bx0 = Int.max, by0 = Int.max, bx1 = Int.min, by1 = Int.min
        for y in r.y0..<r.y1 {
            for x in r.x0..<r.x1 where mask.bits[y * w + x] == 1 {
                n += 1; sx += Double(x); sy += Double(y)
                bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y)
            }
        }
        guard n > 0 else { return nil }
        let cx = sx / Double(n), cy = sy / Double(n)
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0, r2 = 0.0
        for y in by0...by1 {
            for x in bx0...bx1 where mask.bits[y * w + x] == 1 {
                let dx = Double(x) - cx, dy = Double(y) - cy
                mu20 += dx * dx; mu02 += dy * dy; mu11 += dx * dy
                r2 = max(r2, dx * dx + dy * dy)
            }
        }
        return Silhouette(mask: mask, area: n, cx: cx, cy: cy,
                          theta: 0.5 * atan2(2 * mu11, mu20 - mu02), radius: r2.squareRoot(),
                          bbox: PixelRect(x0: bx0, y0: by0, x1: bx1 + 1, y1: by1 + 1))
    }

    private static func makeSilhouette(labels: [Int32], component: Component,
                                       width w: Int, height h: Int) -> Silhouette {
        let best = component
        let filled = Components.filledMask(labels: labels, width: w, height: h, component: best)
        var n = 0, sx = 0.0, sy = 0.0
        for y in best.y0...best.y1 {
            for x in best.x0...best.x1 where filled.bits[y * w + x] == 1 {
                n += 1; sx += Double(x); sy += Double(y)
            }
        }
        let cx = sx / Double(n), cy = sy / Double(n)
        var mu20 = 0.0, mu02 = 0.0, mu11 = 0.0, r2 = 0.0
        for y in best.y0...best.y1 {
            for x in best.x0...best.x1 where filled.bits[y * w + x] == 1 {
                let dx = Double(x) - cx, dy = Double(y) - cy
                mu20 += dx * dx; mu02 += dy * dy; mu11 += dx * dy
                r2 = max(r2, dx * dx + dy * dy)
            }
        }
        return Silhouette(mask: filled, area: n, cx: cx, cy: cy,
                          theta: 0.5 * atan2(2 * mu11, mu20 - mu02), radius: sqrt(r2),
                          bbox: PixelRect(x0: best.x0, y0: best.y0, x1: best.x1 + 1, y1: best.y1 + 1))
    }

    /// Posture change between two silhouettes, in pixels.
    ///
    /// `prev` is moved onto `cur`'s centroid (and, optionally, body-axis angle), which removes the
    /// translation/rotation of a passive pendulum swing. Pixels then count as changed only if they lie
    /// more than `tolerance` px outside the other silhouette — this absorbs 1-px edge jitter from
    /// rounding and video compression, which otherwise gives a few % of "motion" for a still mouse.
    static func shapeChange(prev: Silhouette, cur: Silhouette, alignRotation: Bool, tolerance: Int = 1) -> Double {
        var dang = 0.0
        if alignRotation {
            dang = cur.theta - prev.theta
            // orientation is defined modulo π → wrap to [-π/2, π/2)
            dang = (dang + .pi / 2).truncatingRemainder(dividingBy: .pi)
            if dang < 0 { dang += .pi }
            dang -= .pi / 2
        }
        let c = cos(-dang), s = sin(-dang)
        let w = cur.mask.width, h = cur.mask.height
        // comparison region: cur bbox ∪ disc where the aligned prev can land, + tolerance
        let R = Int(prev.radius.rounded(.up)) + tolerance + 2
        let rx0 = max(0, min(cur.bbox.x0, Int(cur.cx) - R) - tolerance)
        let ry0 = max(0, min(cur.bbox.y0, Int(cur.cy) - R) - tolerance)
        let rx1 = min(w, max(cur.bbox.x1, Int(cur.cx) + R + 1) + tolerance)
        let ry1 = min(h, max(cur.bbox.y1, Int(cur.cy) + R + 1) + tolerance)
        let rw = rx1 - rx0, rh = ry1 - ry0
        guard rw > 0, rh > 0 else { return .nan }
        var a = BinaryMask(width: rw, height: rh)   // aligned prev
        var b = BinaryMask(width: rw, height: rh)   // cur
        prev.mask.bits.withUnsafeBufferPointer { pb in
            cur.mask.bits.withUnsafeBufferPointer { cb in
                for y in 0..<rh {
                    for x in 0..<rw {
                        let gx = x + rx0, gy = y + ry0
                        b.bits[y * rw + x] = cb[gy * w + gx]
                        // source = R(-dang)·(p − c_cur) + c_prev
                        let dx = Double(gx) - cur.cx, dy = Double(gy) - cur.cy
                        let sx = Int((c * dx - s * dy + prev.cx).rounded())
                        let sy = Int((s * dx + c * dy + prev.cy).rounded())
                        if sx >= 0, sy >= 0, sx < w, sy < h { a.bits[y * rw + x] = pb[sy * w + sx] }
                    }
                }
            }
        }
        if tolerance <= 0 {
            var n = 0
            for k in 0..<(rw * rh) where a.bits[k] != b.bits[k] { n += 1 }
            return Double(n)
        }
        let da = a.dilated(radius: tolerance), db = b.dilated(radius: tolerance)
        var n = 0
        for k in 0..<(rw * rh) {
            if b.bits[k] == 1 && da.bits[k] == 0 { n += 1 }   // appeared
            if a.bits[k] == 1 && db.bits[k] == 0 { n += 1 }   // disappeared
        }
        return Double(n)
    }
}

/// All state of one chamber in the streaming analysis. Chambers are independent, so a frame is processed
/// for all chambers in parallel (DispatchQueue.concurrentPerform, one chamber per task). A track is only
/// ever touched by one thread at a time and only reads the shared frame, so no locking is needed and the
/// result is identical to processing the chambers one after another.
final class ChamberTrack {
    let roi: PixelRect
    let enabled: Bool
    let threshold: Int
    let reference: DetBox?
    let motionBox: PixelRect?
    let boxBody: Double
    private(set) var measures: [FrameMeasure] = []
    /// Outline of the last processed frame (live preview).
    private(set) var lastMask: BinaryMask?

    private var prevBlurred: GrayImage?
    private var silHistory: [Silhouette?] = []   // most recent last
    private var prevSilhouette: Silhouette?
    private var missedFrames = 0
    private var lastPixelMask: BinaryMask?
    private var prevPose: MassPose?
    private var prevPresent = false

    init(roi: PixelRect, enabled: Bool, threshold: Int, reference: DetBox?, motionBox: PixelRect?, boxBody: Double) {
        self.roi = roi
        self.enabled = enabled
        self.threshold = threshold
        self.reference = reference
        self.motionBox = motionBox
        self.boxBody = boxBody
    }

    func process(_ frame: GrayImage, time: Double, settings: AnalysisSettings, openRadius: Int, lagFrames: Int) {
        lastMask = nil
        guard enabled else {
            measures.append(FrameMeasure(time: time, pixelChange: .nan, shapeChange: .nan, area: 0, cx: .nan, cy: .nan))
            return
        }
        let r = roi
        let image = ImageOps.gaussian5(frame.cropped(r))
        // B: shape segmentation. Tracking is guided by a detector reference when
        // available, otherwise by the chamber centre and the last accepted silhouette.
        let minArea = max(12, Int(settings.minMouseAreaFraction * Double(r.area)))
        var sil = MouseSegmenter.segmentTracked(
            image, threshold: threshold, dark: settings.mouseDark,
            openRadius: openRadius, minArea: minArea,
            reference: reference, previous: prevSilhouette,
            refine: settings.useRefinedOutline)
        // A stale detector anchor must not make an otherwise visible mouse vanish
        // forever. After a sustained miss, try the conservative chamber-centre prior.
        if sil == nil && missedFrames > max(3, lagFrames * 5) && reference != nil {
            sil = MouseSegmenter.segmentTracked(
                image, threshold: threshold, dark: settings.mouseDark,
                openRadius: openRadius, minArea: minArea,
                reference: nil, previous: nil,
                refine: settings.useRefinedOutline)
        }
        if let s = sil {
            prevSilhouette = s
            missedFrames = 0
        } else {
            missedFrames += 1
            // Drop the old position after a sustained detection gap so that a mouse
            // returning to the image can be reacquired near its original detector box.
            if missedFrames > max(3, lagFrames * 5) { prevSilhouette = nil }
        }
        // A: pixel-change uses ONLY mouse pixels (union of neighbouring silhouettes).
        // In contrast with the old full-ROI difference, wall and camera noise do not
        // inflate the motion score. A gap is unknown (NaN), not false immobility.
        var pix = Double.nan
        if let cur = sil, let last = lastPixelMask, let prev = prevBlurred {
            let support = cur.mask.dilated(radius: 2)
            let oldSupport = last.dilated(radius: 2)
            var n = 0
            for k in image.pixels.indices where support.bits[k] == 1 || oldSupport.bits[k] == 1 {
                if abs(Int(image.pixels[k]) - Int(prev.pixels[k])) > settings.diffThreshold { n += 1 }
            }
            pix = Double(n)
        }
        // C: box metric — frame differencing in the fixed motion box, swing-aligned. A frame without
        // enough mouse pixels in the box (taken down, climbed out) is "no mouse", never "immobile".
        var boxChange = Double.nan
        var present = false
        if let b = motionBox, boxBody > 0 {
            let count = BoxMotion.mousePixels(image, box: b, threshold: threshold, dark: settings.mouseDark)
            present = Double(count) >= 0.3 * boxBody
            let pose = present && settings.alignRotation
                ? BoxMotion.pose(image, box: b, threshold: threshold, dark: settings.mouseDark) : nil
            if present, prevPresent, let prev = prevBlurred {
                boxChange = BoxMotion.change(prev: prev, cur: image, box: b, diff: settings.diffThreshold,
                                             prevPose: settings.alignRotation ? prevPose : nil, curPose: pose)
            }
            prevPose = pose
            prevPresent = present
        }
        prevBlurred = image
        lastPixelMask = sil?.mask
        var shp = Double.nan
        let ref = silHistory.count >= lagFrames ? silHistory[silHistory.count - lagFrames] : nil
        if let s = sil, let p = ref {
            shp = MouseSegmenter.shapeChange(prev: p, cur: s, alignRotation: settings.alignRotation,
                                             tolerance: settings.edgeTolerancePx)
        }
        silHistory.append(sil)
        if silHistory.count > lagFrames { silHistory.removeFirst() }
        lastMask = sil?.mask
        measures.append(FrameMeasure(time: time, pixelChange: pix, shapeChange: shp,
                                     area: Double(sil?.area ?? 0),
                                     cx: sil.map { $0.cx + Double(r.x0) } ?? .nan,
                                     cy: sil.map { $0.cy + Double(r.y0) } ?? .nan,
                                     boxChange: boxChange, boxPresent: present, boxBody: boxBody))
    }
}

/// Streams frames through segmentation + motion measurement for every chamber.
public final class MotionAnalyzer {
    public let layout: ChamberLayout
    public let settings: AnalysisSettings
    public let rois: [PixelRect]
    public let thresholds: [Int]
    /// Box metric: per chamber the motion box (ROI coordinates).
    public let motionBoxes: [PixelRect?]
    private let tracks: [ChamberTrack]
    private var lagFrames: Int = 1
    private let openRadius: Int

    public var measures: [[FrameMeasure]] { tracks.map { $0.measures } }

    /// Motion boxes in processed-image coordinates (for the live preview).
    public var motionRectsInImage: [PixelRect?] {
        zip(rois, motionBoxes).map { r, b in
            b.map { PixelRect(x0: $0.x0 + r.x0, y0: $0.y0 + r.y0, x1: $0.x1 + r.x0, y1: $0.y1 + r.y0) }
        }
    }

    /// `sampleFrames` (same size as analysed frames) are used to fix one Otsu threshold per chamber.
    public init(layout: ChamberLayout, settings: AnalysisSettings, sampleFrames: [GrayImage],
                referenceBoxes: [DetBox?] = [], motionBoxes boxesInImage: [DetBox?] = []) {
        self.layout = layout
        self.settings = settings
        let rois = (0..<layout.count).map { layout.roi($0, marginFraction: settings.wallMarginFraction) }
        self.rois = rois
        let references: [DetBox?] = rois.enumerated().map { i, r in
            guard i < referenceBoxes.count, let b = referenceBoxes[i] else { return nil }
            return DetBox(x0: b.x0 - Double(r.x0), y0: b.y0 - Double(r.y0),
                          x1: b.x1 - Double(r.x0), y1: b.y1 - Double(r.y0), confidence: b.confidence)
        }
        // Blurred chamber crops of the sample frames (used for the thresholds and the body size).
        let crops: [[GrayImage]] = rois.map { r in sampleFrames.map { ImageOps.gaussian5($0.cropped(r)) } }
        var ths: [Int] = []
        for chamberCrops in crops {
            var hist = [Int](repeating: 0, count: 256)
            for crop in chamberCrops {
                for v in crop.pixels { hist[Int(v)] += 1 }
            }
            let t = ImageOps.otsu(histogram: hist)
            ths.append(settings.mouseDark ? t - settings.otsuOffset : t + settings.otsuOffset)
        }
        self.thresholds = ths
        // Motion box per chamber, in ROI coordinates (whole ROI when no detector box is known).
        let boxes: [PixelRect?] = rois.enumerated().map { i, r in
            guard layout.enabled[i] else { return nil }
            if i < boxesInImage.count, let b = boxesInImage[i] {
                let x0 = max(0, Int(floor(b.x0)) - r.x0), y0 = max(0, Int(floor(b.y0)) - r.y0)
                let x1 = min(r.width, Int(ceil(b.x1)) - r.x0), y1 = min(r.height, Int(ceil(b.y1)) - r.y0)
                if x1 - x0 >= 4 && y1 - y0 >= 4 { return PixelRect(x0: x0, y0: y0, x1: x1, y1: y1) }
            }
            return PixelRect(x0: 0, y0: 0, x1: r.width, y1: r.height)
        }
        self.motionBoxes = boxes
        // Reference body size: mouse pixels in the box on frames from the analysed window. The 75th
        // percentile ignores samples where the mouse was already taken down or had climbed out.
        let bodies: [Double] = (0..<rois.count).map { i in
            guard let b = boxes[i], !crops[i].isEmpty else { return 0 }
            let counts = crops[i].map {
                BoxMotion.mousePixels($0, box: b, threshold: ths[i], dark: settings.mouseDark)
            }.sorted()
            let p75 = Double(counts[min(counts.count - 1, Int(Double(counts.count - 1) * 0.75))])
            return p75 >= 12 ? p75 : 0
        }
        self.tracks = (0..<rois.count).map { i in
            ChamberTrack(roi: rois[i], enabled: layout.enabled[i], threshold: ths[i],
                         reference: references[i], motionBox: boxes[i], boxBody: bodies[i])
        }
        let k = settings.tailKernelFraction * layout.spacing
        self.openRadius = max(1, Int((k / 2).rounded()))
    }

    /// Effective analysis frame rate; sets the comparison lag for the shape metric.
    public func setFrameRate(_ fps: Double) {
        lagFrames = max(1, Int((settings.compareLagSec * fps).rounded()))
    }

    /// Process one frame (already rotated/downscaled to the layout's image size), all chambers in parallel.
    /// Returns each chamber's outline for the optional live preview.
    @discardableResult
    public func process(_ frame: GrayImage, time: Double) -> [BinaryMask?] {
        precondition(frame.width == layout.imageWidth && frame.height == layout.imageHeight, "frame size mismatch")
        let tracks = self.tracks
        let settings = self.settings
        let openRadius = self.openRadius
        let lagFrames = self.lagFrames
        if tracks.count > 1 {
            DispatchQueue.concurrentPerform(iterations: tracks.count) { i in
                tracks[i].process(frame, time: time, settings: settings, openRadius: openRadius, lagFrames: lagFrames)
            }
        } else {
            for t in tracks {
                t.process(frame, time: time, settings: settings, openRadius: openRadius, lagFrames: lagFrames)
            }
        }
        return tracks.map { $0.lastMask }
    }

    /// Classify and summarise. `fps` = effective analysis frame rate.
    public func finish(fps: Double) -> TSTMultiAnalysisResult {
        Scorer.score(measures: measures, layout: layout, settings: settings, fps: fps)
    }
}
