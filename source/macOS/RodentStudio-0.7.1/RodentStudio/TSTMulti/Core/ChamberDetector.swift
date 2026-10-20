import Foundation

/// Layout of side-by-side chambers in processed-image coordinates.
public struct ChamberLayout: Codable, Equatable, Sendable {
    /// N+1 x-positions of the walls (left edge, N-1 dividers, right edge), ascending.
    public var walls: [Double]
    /// Vertical analysis band shared by all chambers (half-open).
    public var y0: Int
    public var y1: Int
    /// Per chamber: true if no mouse was found there during detection.
    public var empty: [Bool]
    /// Per chamber: whether the user wants it analysed.
    public var enabled: [Bool]
    public var imageWidth: Int
    public var imageHeight: Int
    /// Typical chamber pitch in pixels.
    public var spacing: Double
    /// Per-column wall-edge strength, used to snap walls when the user changes the count.
    public var wallProfile: [Double]
    /// Detection notes (shown to the user).
    public var notes: [String]

    public var count: Int { max(0, walls.count - 1) }

    /// ROI of chamber `i` with `marginFraction` of the chamber width trimmed from both sides.
    public func roi(_ i: Int, marginFraction: Double) -> PixelRect {
        let a = walls[i], b = walls[i + 1]
        let m = marginFraction * (b - a)
        let x0 = Int((a + m).rounded()), x1 = Int((b - m).rounded())
        return PixelRect(x0: max(0, x0), y0: y0, x1: min(imageWidth, max(x0 + 1, x1)), y1: y1)
    }

    /// Simple equal split of the whole frame (fallback / manual start).
    public static func equalSplit(width: Int, height: Int, count: Int) -> ChamberLayout {
        let n = max(1, count)
        let walls = (0...n).map { Double($0) * Double(width - 1) / Double(n) }
        return ChamberLayout(walls: walls, y0: 0, y1: height, empty: Array(repeating: false, count: n),
                             enabled: Array(repeating: true, count: n), imageWidth: width, imageHeight: height,
                             spacing: Double(width) / Double(n), wallProfile: [], notes: ["equal split"])
    }
}

/// Finds chambers automatically from frames sampled across the session.
///
/// 1. Mouse occupancy: 25th-percentile image (a pixel is "mouse" if it is dark in ≥25 % of samples),
///    Otsu threshold, connected components filtered by size/shape → one blob per occupied chamber.
/// 2. Wall profile: per column, the 70th percentile over rows of |∂I/∂x| of the median image.
///    Long vertical walls survive; short mouse/string edges are suppressed.
/// 3. Count = number of mice + gaps that are ~2× the typical pitch (empty chambers)
///    + chambers beyond the outermost mice if another wall-like edge and chamber-like brightness exist.
/// 4. Each divider = strongest wall-profile column inside the free gap between neighbouring mice.
public enum ChamberDetector {

    /// - Parameters:
    ///   - frames: grayscale frames sampled across the video (same size).
    ///   - detections: optional mouse boxes per sampled frame (e.g. from YOLO). When given, the
    ///     occupancy map is built from boxes seen in ≥ 20 % of samples instead of from dark pixels,
    ///     which is robust to hands, shadows and dark rig parts.
    /// Falls back to wall-only detection when no mice are found.
    public static func detect(frames: [GrayImage], mouseDark: Bool = true,
                              detections: [[DetBox]]? = nil) -> ChamberLayout? {
        guard let first = frames.first else { return nil }
        let w = first.width, h = first.height
        let med = frames.count == 1 ? first : ImageOps.percentileImage(frames, fraction: 0.5)
        var occ: BinaryMask
        var source = "dark-pixel occupancy"
        if let detections, detections.contains(where: { !$0.isEmpty }) {
            occ = boxOccupancy(detections, width: w, height: h, minFraction: 0.2)
            source = "detector boxes"
        } else {
            let pimg = ImageOps.percentileImage(frames, fraction: mouseDark ? 0.25 : 0.75)
            let t = ImageOps.otsu(histogram: ImageOps.histogram(pimg.pixels))
            occ = BinaryMask(threshold: pimg, at: t, dark: mouseDark)
        }
        // opening strips tails / strings / thin rig edges so a body is not connected to the clip bar
        occ = occ.opened(radius: max(1, w / 300))
        let (_, comps) = Components.label(occ)

        // --- mouse blobs
        let imgArea = Double(w * h)
        var mice = comps.filter { c in
            let bw = c.x1 - c.x0 + 1, bh = c.y1 - c.y0 + 1
            let touches = c.x0 == 0 || c.x1 == w - 1 || c.y0 == 0 || c.y1 == h - 1
            if Double(c.area) < 0.0015 * imgArea || Double(c.area) > 0.15 * imgArea || touches { return false }
            if Double(bw) > 0.5 * Double(w) || Double(bh) < 0.08 * Double(h) { return false }
            return true
        }.sorted { $0.cx < $1.cx }
        // merge pieces of one mouse that overlap in x
        var merged: [Component] = []
        for c in mice {
            if var m = merged.last, c.x0 <= m.x1 + 2 {
                m.area += c.area; m.sumX += c.sumX; m.sumY += c.sumY
                m.x0 = min(m.x0, c.x0); m.y0 = min(m.y0, c.y0); m.x1 = max(m.x1, c.x1); m.y1 = max(m.y1, c.y1)
                merged[merged.count - 1] = m
            } else {
                merged.append(c)
            }
        }
        if !merged.isEmpty {
            let medArea = median(merged.map { Double($0.area) })
            merged = merged.filter { Double($0.area) >= 0.25 * medArea }
        }
        mice = merged

        // --- wall profile
        let prof = wallProfile(med)
        guard !mice.isEmpty else { return detectWallsOnly(median: med, frames: frames, mouseDark: mouseDark) }

        let centers = mice.map { $0.cx }
        let spacing: Double = centers.count >= 2
            ? median(zip(centers.dropFirst(), centers).map { $0 - $1 })
            : Double(w) / 2

        // --- slots (mouse or inferred empty chamber)
        var slots: [(cx: Double, mouse: Component?)] = []
        for (i, m) in mice.enumerated() {
            if i > 0 {
                let gap = m.cx - mice[i - 1].cx
                let missing = Int((gap / spacing).rounded()) - 1
                if missing > 0 {
                    for k in 1...missing {
                        slots.append((mice[i - 1].cx + gap * Double(k) / Double(missing + 1), nil))
                    }
                }
            }
            slots.append((m.cx, m))
        }

        func strongest(_ lo: Double, _ hi: Double) -> Double {
            let a = Int(max(0, lo.rounded(.down))), b = Int(min(Double(w - 1), hi.rounded(.up)))
            if b <= a { return (Double(a) + Double(b)) / 2 }
            var best = a
            for x in a...b where prof[x] > prof[best] { best = x }
            return Double(best)
        }

        // --- inner walls
        var walls: [Double] = []
        for i in 0..<(slots.count - 1) {
            let (ca, ma) = slots[i], (cb, mb) = slots[i + 1]
            // free gap between the two occupants, keeping a margin from each mouse (limbs/tail
            // were removed from the occupancy blob by the opening and would otherwise look like edges)
            let pad = 0.08 * spacing
            var lo = ma.map { Double($0.x1 + 1) + pad } ?? ca + 0.25 * spacing
            var hi = mb.map { Double($0.x0 - 1) - pad } ?? cb - 0.25 * spacing
            if hi - lo < 3 {   // mice swing close to each other → drop the margin
                lo = ma.map { Double($0.x1 + 1) } ?? ca + 0.25 * spacing
                hi = mb.map { Double($0.x0 - 1) } ?? cb - 0.25 * spacing
            }
            walls.append(hi - lo < 3 ? (ca + cb) / 2 : strongest(lo, hi))
        }
        // --- outer walls
        let (firstC, firstM) = slots[0], (lastC, lastM) = slots[slots.count - 1]
        let halfL = walls.first.map { abs($0 - firstC) } ?? spacing / 2
        let padO = 0.08 * spacing
        let left = strongest(max(0, firstC - 1.3 * halfL), Double(firstM.map { $0.x0 } ?? Int(firstC)) - 1 - padO)
        let halfR = walls.last.map { abs(lastC - $0) } ?? spacing / 2
        let right = strongest(Double(lastM.map { $0.x1 } ?? Int(lastC)) + 1 + padO, min(Double(w - 1), lastC + 1.3 * halfR))
        walls = [left] + walls + [right]
        var empty = slots.map { $0.mouse == nil }
        var notes: [String] = ["\(mice.count) mice found (\(source))"]
        if empty.contains(true) { notes.append("\(empty.filter { $0 }.count) empty chamber(s) inferred between mice") }

        // --- empty chambers beyond the outermost mice
        let ya = mice.map { $0.y0 }.min()!, yb = mice.map { $0.y1 }.max()! + 1
        func regionMedian(_ a: Double, _ b: Double) -> Double {
            let xa = Int(min(a, b).rounded()), xb = Int(max(a, b).rounded())
            var vals: [UInt8] = []
            vals.reserveCapacity((xb - xa + 1) * (yb - ya))
            for y in ya..<yb { for x in max(0, xa)...min(w - 1, xb) { vals.append(med[x, y]) } }
            return Double(ImageOps.percentile(&vals, fraction: 0.5))
        }
        let ref = walls.count > 2 ? median(walls[1..<(walls.count - 1)].map { prof[Int($0.rounded())] }) : (prof.max() ?? 0)
        let typical = median((0..<(walls.count - 1)).map { regionMedian(walls[$0], walls[$0 + 1]) })
        func extend(_ edge: Double, _ dir: Double) -> Double? {
            let a = edge + dir * 0.55 * spacing, b = edge + dir * 1.25 * spacing
            let lo = max(0, min(a, b)), hi = min(Double(w - 1), max(a, b))
            if hi - lo < 1 { return nil }
            let x = strongest(lo, hi)
            if prof[Int(x)] < 0.5 * ref { return nil }
            if abs(regionMedian(edge, x) - typical) > 0.12 * typical { return nil }
            return x
        }
        var added = 0
        for _ in 0..<4 { guard let x = extend(walls[0], -1) else { break }; walls.insert(x, at: 0); empty.insert(true, at: 0); added += 1 }
        for _ in 0..<4 { guard let x = extend(walls[walls.count - 1], 1) else { break }; walls.append(x); empty.append(true); added += 1 }
        if added > 0 { notes.append("\(added) empty chamber(s) inferred at the ends") }

        // --- vertical band (mice curl up towards the clip while struggling → pad more above)
        let span = yb - ya
        let y0 = max(0, ya - Int(0.6 * Double(span))), y1 = min(h, yb + Int(0.4 * Double(span)))

        return ChamberLayout(walls: walls, y0: y0, y1: y1, empty: empty,
                             enabled: empty.map { !$0 }, imageWidth: w, imageHeight: h,
                             spacing: spacing, wallProfile: prof, notes: notes)
    }

    /// Re-fit the layout to a user-chosen chamber count, keeping the outer walls and snapping
    /// dividers to the strongest wall edges near an even split.
    public static func refit(_ layout: ChamberLayout, count n: Int) -> ChamberLayout {
        guard n >= 1, let left = layout.walls.first, let right = layout.walls.last else { return layout }
        var out = layout
        let pitch = (right - left) / Double(n)
        var walls = [left]
        for k in 1..<max(1, n) where n > 1 {
            let expected = left + Double(k) * pitch
            if layout.wallProfile.isEmpty {
                walls.append(expected)
            } else {
                let a = Int(max(0, expected - 0.3 * pitch)), b = Int(min(Double(layout.wallProfile.count - 1), expected + 0.3 * pitch))
                var best = a
                if b > a { for x in a...b where layout.wallProfile[x] > layout.wallProfile[best] { best = x } }
                walls.append(Double(best))
            }
        }
        walls.append(right)
        out.walls = walls
        out.spacing = pitch
        // keep emptiness info only if the count did not change
        if n != layout.count {
            out.empty = Array(repeating: false, count: n)
            out.enabled = Array(repeating: true, count: n)
            out.notes.append("count set manually to \(n)")
        }
        return out
    }

    /// Per-column wall-edge strength: 70th percentile over rows of the horizontal gradient, lightly smoothed.
    /// An edge must be present in ≥30 % of rows: divider panels seen in perspective often cover only the
    /// lower part of the frame, while a mouse in the median image covers much less.
    public static func wallProfile(_ img: GrayImage, exclude: BinaryMask? = nil) -> [Double] {
        let w = img.width, h = img.height
        var prof = [Double](repeating: 0, count: w)
        var col: [UInt8] = []
        col.reserveCapacity(h)
        if w >= 3 {
            for x in 1..<(w - 1) {
                col.removeAll(keepingCapacity: true)
                for y in 0..<h {
                    if let e = exclude, e.bits[y * w + x] == 1 { continue }
                    col.append(UInt8(min(255, abs(Int(img[x + 1, y]) - Int(img[x - 1, y])) / 2)))
                }
                prof[x] = col.count > h / 4 ? Double(ImageOps.percentile(&col, fraction: 0.7)) : 0
            }
        }
        return boxBlur(prof, radius: max(1, w / 400))
    }

    /// Pixels covered by a box in at least `minFraction` of the sampled frames.
    static func boxOccupancy(_ dets: [[DetBox]], width w: Int, height h: Int, minFraction: Double) -> BinaryMask {
        var count = [Int32](repeating: 0, count: w * h)
        for frameDets in dets {
            for d in frameDets {
                let x0 = max(0, Int(d.x0.rounded())), x1 = min(w, Int(d.x1.rounded()))
                let y0 = max(0, Int(d.y0.rounded())), y1 = min(h, Int(d.y1.rounded()))
                guard x1 > x0, y1 > y0 else { continue }
                for y in y0..<y1 { for x in x0..<x1 { count[y * w + x] += 1 } }
            }
        }
        let need = Int32(max(1, Int((minFraction * Double(dets.count)).rounded())))
        return BinaryMask(width: w, height: h, bits: count.map { $0 >= need ? 1 : 0 })
    }

    // MARK: - Wall-only fallback (no mice visible, e.g. empty rig)

    /// Periodic-wall detection: pitch from the autocorrelation of the wall profile (mouse-like blobs
    /// excluded), phase from a comb fit, longest run of wall-strength candidates, then brightness-checked
    /// trimming and extension at the ends.
    public static func detectWallsOnly(median med: GrayImage, frames: [GrayImage], mouseDark: Bool) -> ChamberLayout? {
        let w = med.width, h = med.height
        guard w >= 32, h >= 8 else { return nil }
        let excl = mouseExclusion(frames: frames.isEmpty ? [med] : frames, mouseDark: mouseDark)
        let prof = wallProfile(med, exclude: excl)
        let mean = prof.reduce(0, +) / Double(w)
        let p = prof.map { $0 - mean }
        let lo = max(3, w / 16), hi = w / 2
        guard hi > lo + 2 else { return nil }
        var ac = [Double](repeating: 0, count: hi + 1)
        for lag in 0...hi {
            var s = 0.0
            for x in 0..<(w - lag) { s += p[x] * p[x + lag] }
            ac[lag] = s
        }
        guard ac[0] > 0 else { return nil }
        for i in ac.indices { ac[i] /= ac[0] }
        let peaks = ((lo + 1)..<(hi - 1)).filter { ac[$0] >= ac[$0 - 1] && ac[$0] >= ac[$0 + 1] && ac[$0] > 0.05 }
        guard let best = peaks.map({ ac[$0] }).max() else { return nil }
        let pitch = Double(peaks.first { ac[$0] >= 0.6 * best }!)
        let win = max(2, Int(0.15 * pitch))
        func localMax(_ x: Double) -> Int {
            let a = max(0, Int(x.rounded()) - win), b = min(w - 1, Int(x.rounded()) + win)
            var bi = a
            for i in a...b where prof[i] > prof[bi] { bi = i }
            return bi
        }
        var bestScore = -1.0, bestPhi = 0
        for phi in 0..<Int(pitch) {
            var s = 0.0
            for x in stride(from: Double(phi), to: Double(w), by: pitch) { s += prof[localMax(x)] }
            if s > bestScore { bestScore = s; bestPhi = phi }
        }
        let cands = Array(Set(stride(from: Double(bestPhi), to: Double(w), by: pitch).map(localMax))).sorted()
        let strength = cands.map { prof[$0] }
        let ref = median(strength)
        let ok = strength.map { $0 >= 0.35 * ref }
        var runs: [(Int, Int)] = []
        var i = 0
        while i < ok.count {
            if ok[i] { var j = i; while j < ok.count && ok[j] { j += 1 }; runs.append((i, j)); i = j } else { i += 1 }
        }
        guard let run = runs.max(by: { a, b in
            (a.1 - a.0, strength[a.0..<a.1].reduce(0, +)) < (b.1 - b.0, strength[b.0..<b.1].reduce(0, +))
        }) else { return nil }
        var walls = cands[run.0..<run.1].map(Double.init)

        func regionMedian(_ a: Double, _ b: Double) -> Double {
            let xa = max(0, Int(min(a, b).rounded())), xb = min(w - 1, Int(max(a, b).rounded()))
            var vals: [UInt8] = []
            for y in (h / 4)..<(3 * h / 4) { for x in xa...xb { vals.append(med[x, y]) } }
            return vals.isEmpty ? 0 : Double(ImageOps.percentile(&vals, fraction: 0.5))
        }
        // drop end chambers that do not look like the others
        while walls.count >= 4 {
            let meds = (0..<(walls.count - 1)).map { regionMedian(walls[$0], walls[$0 + 1]) }
            let typ = median(meds)
            if abs(meds[0] - typ) > 0.12 * typ { walls.removeFirst(); continue }
            if abs(meds[meds.count - 1] - typ) > 0.12 * typ { walls.removeLast(); continue }
            break
        }
        guard walls.count >= 1 else { return nil }
        let typical = walls.count >= 2
            ? median((0..<(walls.count - 1)).map { regionMedian(walls[$0], walls[$0 + 1]) })
            : regionMedian(0, Double(w - 1))
        let wallRef = median(walls.map { prof[Int($0)] })
        func extend(_ edge: Double, _ dir: Double) -> Double? {
            let a = edge + dir * 0.45 * pitch, b = edge + dir * 1.25 * pitch
            let lo = max(0, min(a, b)), hi = min(Double(w - 1), max(a, b))
            if hi - lo < 1 { return nil }
            var bx = Int(lo)
            for x in Int(lo)...Int(hi) where prof[x] > prof[bx] { bx = x }
            if prof[bx] < 0.4 * wallRef { return nil }
            if abs(regionMedian(edge, Double(bx)) - typical) > 0.12 * typical { return nil }
            return Double(bx)
        }
        for _ in 0..<3 { guard let x = extend(walls[0], -1) else { break }; walls.insert(x, at: 0) }
        for _ in 0..<3 { guard let x = extend(walls[walls.count - 1], 1) else { break }; walls.append(x) }
        guard walls.count >= 2 else { return nil }
        let n = walls.count - 1
        return ChamberLayout(walls: walls, y0: 0, y1: h, empty: Array(repeating: false, count: n),
                             enabled: Array(repeating: true, count: n), imageWidth: w, imageHeight: h,
                             spacing: pitch, wallProfile: prof,
                             notes: ["no mice visible – chambers from wall pattern only (check!)"])
    }

    /// Compact dark blobs (mice) in the 25th-percentile image, dilated. Thin full-height edges and long
    /// horizontal rig edges are not excluded.
    static func mouseExclusion(frames: [GrayImage], mouseDark: Bool) -> BinaryMask {
        let src = frames.count == 1 ? frames[0] : ImageOps.percentileImage(frames, fraction: mouseDark ? 0.25 : 0.75)
        let w = src.width, h = src.height
        let t = ImageOps.otsu(histogram: ImageOps.histogram(src.pixels))
        let m = BinaryMask(threshold: src, at: t, dark: mouseDark)
        let (labels, comps) = Components.label(m)
        var keep = Set<Int32>()
        for c in comps {
            let bw = c.x1 - c.x0 + 1, bh = c.y1 - c.y0 + 1
            if Double(c.area) < 0.001 * Double(w * h) || Double(bw) > 0.3 * Double(w) || Double(bh) > 0.8 * Double(h)
                || Double(bw) < max(3, 0.015 * Double(w)) { continue }
            keep.insert(c.label)
        }
        var out = BinaryMask(width: w, height: h)
        for k in 0..<(w * h) where keep.contains(labels[k]) { out.bits[k] = 1 }
        return out.dilated(radius: max(2, w / 120))
    }

    static func boxBlur(_ v: [Double], radius r: Int) -> [Double] {
        if r <= 0 || v.isEmpty { return v }
        var c = [0.0]; c.reserveCapacity(v.count + 1)
        for x in v { c.append(c.last! + x) }
        return (0..<v.count).map { i in
            let a = max(0, i - r), b = min(v.count, i + r + 1)
            return (c[b] - c[a]) / Double(b - a)
        }
    }
}

func median(_ v: [Double]) -> Double {
    if v.isEmpty { return .nan }
    let s = v.sorted(), n = s.count
    return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
}
