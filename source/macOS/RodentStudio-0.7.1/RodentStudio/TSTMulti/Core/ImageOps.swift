import Foundation

// MARK: - Filtering

public enum ImageOps {

    /// Separable 5-tap Gaussian blur ([1 4 6 4 1] / 16), edges clamped.
    public static func gaussian5(_ img: GrayImage) -> GrayImage {
        let w = img.width, h = img.height
        if w == 0 || h == 0 { return img }
        var tmp = [UInt16](repeating: 0, count: w * h)
        var out = [UInt8](repeating: 0, count: w * h)
        img.pixels.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { t in
                for y in 0..<h {
                    let row = y * w
                    for x in 0..<w {
                        let xm2 = row + max(0, x - 2), xm1 = row + max(0, x - 1)
                        let xp1 = row + min(w - 1, x + 1), xp2 = row + min(w - 1, x + 2)
                        let s = UInt16(src[xm2]) + 4 * UInt16(src[xm1]) + 6 * UInt16(src[row + x])
                            + 4 * UInt16(src[xp1]) + UInt16(src[xp2])
                        t[row + x] = s  // max 16*255 = 4080
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { t in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let ym2 = max(0, y - 2) * w, ym1 = max(0, y - 1) * w, y0 = y * w
                    let yp1 = min(h - 1, y + 1) * w, yp2 = min(h - 1, y + 2) * w
                    for x in 0..<w {
                        let s = UInt32(t[ym2 + x]) + 4 * UInt32(t[ym1 + x]) + 6 * UInt32(t[y0 + x])
                            + 4 * UInt32(t[yp1 + x]) + UInt32(t[yp2 + x])
                        dst[y0 + x] = UInt8((s + 128) >> 8)
                    }
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    // MARK: - Thresholding

    public static func histogram<C: Collection>(_ values: C) -> [Int] where C.Element == UInt8 {
        var hist = [Int](repeating: 0, count: 256)
        for v in values { hist[Int(v)] += 1 }
        return hist
    }

    /// Otsu threshold. Pixels `<= t` form the darker class.
    public static func otsu(histogram hist: [Int]) -> Int {
        let total = Double(hist.reduce(0, +))
        var sumAll = 0.0
        for t in 0..<256 { sumAll += Double(t * hist[t]) }
        var wb = 0.0, sb = 0.0, best = -1.0, tBest = 127
        for t in 0..<256 {
            wb += Double(hist[t])
            if wb == 0 { continue }
            let wf = total - wb
            if wf == 0 { break }
            sb += Double(t * hist[t])
            let mb = sb / wb, mf = (sumAll - sb) / wf
            let between = wb * wf * (mb - mf) * (mb - mf)
            if between > best { best = between; tBest = t }
        }
        return tBest
    }

    /// k-th smallest of a small array (copies and sorts).
    @inline(__always) static func percentile(_ v: inout [UInt8], fraction: Double) -> UInt8 {
        v.sort()
        let idx = min(v.count - 1, max(0, Int((fraction * Double(v.count - 1)).rounded())))
        return v[idx]
    }

    /// Per-pixel percentile across a stack of equally sized images.
    public static func percentileImage(_ stack: [GrayImage], fraction: Double) -> GrayImage {
        precondition(!stack.isEmpty)
        let w = stack[0].width, h = stack[0].height, n = stack.count
        var out = [UInt8](repeating: 0, count: w * h)
        var buf = [UInt8](repeating: 0, count: n)
        for i in 0..<(w * h) {
            for k in 0..<n { buf[k] = stack[k].pixels[i] }
            out[i] = percentile(&buf, fraction: fraction)
        }
        return GrayImage(width: w, height: h, pixels: out)
    }
}

// MARK: - Binary masks

public struct BinaryMask: Sendable {
    public let width: Int
    public let height: Int
    public var bits: [UInt8]   // 0 or 1

    public init(width: Int, height: Int, bits: [UInt8]) {
        self.width = width; self.height = height; self.bits = bits
    }
    public init(width: Int, height: Int) {
        self.init(width: width, height: height, bits: [UInt8](repeating: 0, count: width * height))
    }

    /// `dark == true`: pixel <= threshold is foreground; otherwise pixel > threshold.
    public init(threshold img: GrayImage, at t: Int, dark: Bool) {
        var b = [UInt8](repeating: 0, count: img.width * img.height)
        img.pixels.withUnsafeBufferPointer { src in
            b.withUnsafeMutableBufferPointer { dst in
                if dark { for i in 0..<src.count { dst[i] = Int(src[i]) <= t ? 1 : 0 } }
                else    { for i in 0..<src.count { dst[i] = Int(src[i]) >  t ? 1 : 0 } }
            }
        }
        self.init(width: img.width, height: img.height, bits: b)
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 { bits[y * width + x] }

    public var count: Int { bits.reduce(0) { $0 + Int($1) } }

    // Separable square min/max filter with radius r (kernel 2r+1). Out-of-image pixels are
    // treated as background for dilation and as foreground for erosion (no border shrink).
    private func filtered(radius r: Int, dilate: Bool) -> BinaryMask {
        if r <= 0 { return self }
        let w = width, h = height
        var tmp = [UInt8](repeating: 0, count: w * h)
        var out = [UInt8](repeating: 0, count: w * h)
        let hit: UInt8 = dilate ? 1 : 0
        bits.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { t in
                for y in 0..<h {
                    let row = y * w
                    // running count of `hit` pixels inside the window
                    var cnt = 0
                    for x in 0...min(w - 1, r) where src[row + x] == hit { cnt += 1 }
                    for x in 0..<w {
                        t[row + x] = cnt > 0 ? hit : 1 - hit
                        let leaving = x - r, entering = x + r + 1
                        if leaving >= 0, src[row + leaving] == hit { cnt -= 1 }
                        if entering < w, src[row + entering] == hit { cnt += 1 }
                    }
                }
            }
        }
        tmp.withUnsafeBufferPointer { t in
            out.withUnsafeMutableBufferPointer { o in
                for x in 0..<w {
                    var cnt = 0
                    for y in 0...min(h - 1, r) where t[y * w + x] == hit { cnt += 1 }
                    for y in 0..<h {
                        o[y * w + x] = cnt > 0 ? hit : 1 - hit
                        let leaving = y - r, entering = y + r + 1
                        if leaving >= 0, t[leaving * w + x] == hit { cnt -= 1 }
                        if entering < h, t[entering * w + x] == hit { cnt += 1 }
                    }
                }
            }
        }
        return BinaryMask(width: w, height: h, bits: out)
    }

    public func dilated(radius: Int) -> BinaryMask { filtered(radius: radius, dilate: true) }
    public func eroded(radius: Int) -> BinaryMask { filtered(radius: radius, dilate: false) }
    public func opened(radius: Int) -> BinaryMask { eroded(radius: radius).dilated(radius: radius) }
    public func closed(radius: Int) -> BinaryMask { dilated(radius: radius).eroded(radius: radius) }
}

// MARK: - Connected components

public struct Component: Sendable {
    public var label: Int32
    public var area: Int
    public var sumX: Double
    public var sumY: Double
    public var x0: Int, y0: Int, x1: Int, y1: Int   // inclusive bounds
    public var cx: Double { sumX / Double(area) }
    public var cy: Double { sumY / Double(area) }
}

public enum Components {
    /// 4-connected labelling. Returns label image (0 = background) and component stats.
    public static func label(_ m: BinaryMask) -> (labels: [Int32], components: [Component]) {
        let w = m.width, h = m.height
        var labels = [Int32](repeating: 0, count: w * h)
        var comps: [Component] = []
        var stack: [Int] = []
        stack.reserveCapacity(1024)
        var cur: Int32 = 0
        m.bits.withUnsafeBufferPointer { b in
            labels.withUnsafeMutableBufferPointer { lab in
                for start in 0..<(w * h) where b[start] == 1 && lab[start] == 0 {
                    cur += 1
                    lab[start] = cur
                    stack.append(start)
                    var c = Component(label: cur, area: 0, sumX: 0, sumY: 0,
                                      x0: start % w, y0: start / w, x1: start % w, y1: start / w)
                    while let p = stack.popLast() {
                        let x = p % w, y = p / w
                        c.area += 1; c.sumX += Double(x); c.sumY += Double(y)
                        if x < c.x0 { c.x0 = x }; if x > c.x1 { c.x1 = x }
                        if y < c.y0 { c.y0 = y }; if y > c.y1 { c.y1 = y }
                        if x > 0,     b[p - 1] == 1, lab[p - 1] == 0 { lab[p - 1] = cur; stack.append(p - 1) }
                        if x < w - 1, b[p + 1] == 1, lab[p + 1] == 0 { lab[p + 1] = cur; stack.append(p + 1) }
                        if y > 0,     b[p - w] == 1, lab[p - w] == 0 { lab[p - w] = cur; stack.append(p - w) }
                        if y < h - 1, b[p + w] == 1, lab[p + w] == 0 { lab[p + w] = cur; stack.append(p + w) }
                    }
                    comps.append(c)
                }
            }
        }
        return (labels, comps)
    }

    /// Mask containing only `component`, with interior holes filled.
    public static func filledMask(labels: [Int32], width w: Int, height h: Int, component c: Component) -> BinaryMask {
        var out = BinaryMask(width: w, height: h)
        // Work inside the bounding box padded by 1 so the outside is connected.
        let bx0 = c.x0 - 1, by0 = c.y0 - 1
        let bw = c.x1 - c.x0 + 3, bh = c.y1 - c.y0 + 3
        var outside = [UInt8](repeating: 0, count: bw * bh)   // 1 = reachable background
        @inline(__always) func isComp(_ bx: Int, _ by: Int) -> Bool {
            let x = bx + bx0, y = by + by0
            if x < 0 || y < 0 || x >= w || y >= h { return false }
            return labels[y * w + x] == c.label
        }
        var stack = [0]
        outside[0] = 1
        while let p = stack.popLast() {
            let x = p % bw, y = p / bw
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < bw && ny < bh {
                let q = ny * bw + nx
                if outside[q] == 0 && !isComp(nx, ny) { outside[q] = 1; stack.append(q) }
            }
        }
        for by in 1..<(bh - 1) {
            for bx in 1..<(bw - 1) where outside[by * bw + bx] == 0 {
                let x = bx + bx0, y = by + by0
                if x >= 0, y >= 0, x < w, y < h { out.bits[y * w + x] = 1 }
            }
        }
        return out
    }
}
