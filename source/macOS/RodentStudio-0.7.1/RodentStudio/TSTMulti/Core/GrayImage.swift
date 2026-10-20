import Foundation

/// 8-bit single-channel image, row-major.
public struct GrayImage: Sendable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Crop to the half-open rectangle [x0, x1) × [y0, y1) (clamped to the image).
    public func cropped(_ r: PixelRect) -> GrayImage {
        let x0 = max(0, r.x0), y0 = max(0, r.y0)
        let x1 = min(width, r.x1), y1 = min(height, r.y1)
        let w = max(0, x1 - x0), h = max(0, y1 - y0)
        var out = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    let s = (y + y0) * width + x0
                    let d = y * w
                    for x in 0..<w { dst[d + x] = src[s + x] }
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    /// Rotate clockwise by `quarterTurns` × 90°.
    public func rotated(quarterTurns: Int) -> GrayImage {
        let q = ((quarterTurns % 4) + 4) % 4
        if q == 0 { return self }
        let (nw, nh) = q == 2 ? (width, height) : (height, width)
        var out = [UInt8](repeating: 0, count: nw * nh)
        for y in 0..<height {
            for x in 0..<width {
                let v = pixels[y * width + x]
                let (nx, ny): (Int, Int)
                switch q {
                case 1: (nx, ny) = (height - 1 - y, x)            // 90° CW
                case 2: (nx, ny) = (width - 1 - x, height - 1 - y) // 180°
                default: (nx, ny) = (y, width - 1 - x)            // 270° CW
                }
                out[ny * nw + nx] = v
            }
        }
        return GrayImage(width: nw, height: nh, pixels: out)
    }

    /// Area-average downscale (or nearest upscale) to a target width, keeping aspect ratio.
    public func resized(toWidth newWidth: Int) -> GrayImage {
        if newWidth == width || newWidth <= 0 { return self }
        let newHeight = max(1, Int((Double(height) * Double(newWidth) / Double(width)).rounded()))
        var out = [UInt8](repeating: 0, count: newWidth * newHeight)
        let sx = Double(width) / Double(newWidth), sy = Double(height) / Double(newHeight)
        for ny in 0..<newHeight {
            let ya = Int(Double(ny) * sy), yb = max(ya + 1, min(height, Int(Double(ny + 1) * sy)))
            for nx in 0..<newWidth {
                let xa = Int(Double(nx) * sx), xb = max(xa + 1, min(width, Int(Double(nx + 1) * sx)))
                var acc = 0
                for y in ya..<yb { for x in xa..<xb { acc += Int(pixels[y * width + x]) } }
                out[ny * newWidth + nx] = UInt8(acc / ((yb - ya) * (xb - xa)))
            }
        }
        return GrayImage(width: newWidth, height: newHeight, pixels: out)
    }
}

/// Integer rectangle, half-open: [x0, x1) × [y0, y1).
public struct PixelRect: Codable, Equatable, Sendable {
    public var x0: Int, y0: Int, x1: Int, y1: Int
    public init(x0: Int, y0: Int, x1: Int, y1: Int) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }
    public var width: Int { x1 - x0 }
    public var height: Int { y1 - y0 }
    public var area: Int { max(0, width) * max(0, height) }
}
