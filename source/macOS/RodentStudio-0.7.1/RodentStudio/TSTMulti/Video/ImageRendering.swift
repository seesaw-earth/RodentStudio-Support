import Foundation
import CoreGraphics
enum TSTImageRendering {

    /// Grayscale CGImage from a GrayImage.
    static func cgImage(_ g: GrayImage) -> CGImage? {
        guard g.width > 0, g.height > 0,
              let provider = CGDataProvider(data: Data(g.pixels) as CFData) else { return nil }
        return CGImage(width: g.width, height: g.height, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: g.width, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Live-analysis preview: frame in gray, chamber outlines, segmented mice tinted orange.
    static func overlay(frame g: GrayImage, rois: [PixelRect], masks: [BinaryMask?], boxes: [PixelRect?] = []) -> CGImage? {
        let w = g.width, h = g.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = g.pixels[i]
            rgba[4 * i] = v; rgba[4 * i + 1] = v; rgba[4 * i + 2] = v
        }
        for (r, m) in zip(rois, masks) {
            if let m {
                for y in 0..<m.height {
                    for x in 0..<m.width where m.bits[y * m.width + x] == 1 {
                        let gx = x + r.x0, gy = y + r.y0
                        guard gx < w, gy < h else { continue }
                        let k = 4 * (gy * w + gx)
                        rgba[k] = UInt8((Int(rgba[k]) + 255) / 2)
                        rgba[k + 1] = UInt8((Int(rgba[k + 1]) + 140) / 2)
                        rgba[k + 2] = UInt8(Int(rgba[k + 2]) / 2)
                    }
                }
                // Solid contour on the edge of the mask, so the fit to the mouse can be judged.
                let mw = m.width, mh = m.height
                for y in 0..<mh {
                    for x in 0..<mw where m.bits[y * mw + x] == 1 {
                        let i: Int = y * mw + x
                        var edge: Bool = x == 0 || y == 0 || x == mw - 1 || y == mh - 1
                        if !edge {
                            let left: UInt8 = m.bits[i - 1], right: UInt8 = m.bits[i + 1]
                            let up: UInt8 = m.bits[i - mw], down: UInt8 = m.bits[i + mw]
                            edge = left == 0 || right == 0 || up == 0 || down == 0
                        }
                        guard edge else { continue }
                        let gx = x + r.x0, gy = y + r.y0
                        guard gx >= 0, gy >= 0, gx < w, gy < h else { continue }
                        let k = 4 * (gy * w + gx)
                        rgba[k] = 255; rgba[k + 1] = 70; rgba[k + 2] = 30
                    }
                }
            }
            // rectangle outline (green)
            for x in max(0, r.x0)..<min(w, r.x1) {
                for y in [r.y0, r.y1 - 1] where y >= 0 && y < h { setGreen(&rgba, w, x, y) }
            }
            for y in max(0, r.y0)..<min(h, r.y1) {
                for x in [r.x0, r.x1 - 1] where x >= 0 && x < w { setGreen(&rgba, w, x, y) }
            }
        }
        // Motion boxes of the box metric (cyan).
        for case let b? in boxes {
            for x in max(0, b.x0)..<min(w, max(b.x0 + 1, b.x1)) {
                for y in [b.y0, b.y1 - 1] where y >= 0 && y < h {
                    let k = 4 * (y * w + x)
                    rgba[k] = 40; rgba[k + 1] = 200; rgba[k + 2] = 255
                }
            }
            for y in max(0, b.y0)..<min(h, max(b.y0 + 1, b.y1)) {
                for x in [b.x0, b.x1 - 1] where x >= 0 && x < w {
                    let k = 4 * (y * w + x)
                    rgba[k] = 40; rgba[k + 1] = 200; rgba[k + 2] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * w,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Frame with chamber walls, selected chambers tinted and detection boxes
    /// (orange = mouse assigned to a selected chamber, grey = elsewhere).
    static func detections(frame g: GrayImage, layout: ChamberLayout, boxes: [DetBox], selected: [Bool]) -> CGImage? {
        let w = g.width, h = g.height
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = g.pixels[i]
            rgba[4 * i] = v; rgba[4 * i + 1] = v; rgba[4 * i + 2] = v
        }
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            guard x >= 0, y >= 0, x < w, y < h else { return }
            let k = 4 * (y * w + x); rgba[k] = c.0; rgba[k + 1] = c.1; rgba[k + 2] = c.2
        }
        for i in 0..<layout.count where i < selected.count && selected[i] {
            let x0 = max(0, Int(layout.walls[i])), x1 = min(w, Int(layout.walls[i + 1]))
            for y in 0..<h { for x in x0..<x1 {
                let k = 4 * (y * w + x)
                rgba[k] = UInt8(Int(rgba[k]) * 85 / 100); rgba[k + 2] = UInt8(Int(rgba[k + 2]) * 85 / 100)
            } }
        }
        for x in layout.walls { for y in 0..<h { put(Int(x.rounded()), y, (255, 255, 255)); put(Int(x.rounded()) + 1, y, (60, 60, 60)) } }
        for b in boxes {
            let inSel = layout.chamberIndex(x: b.cx).map { $0 < selected.count && selected[$0] } ?? false
            let c: (UInt8, UInt8, UInt8) = inSel ? (255, 140, 0) : (150, 150, 150)
            let x0 = Int(b.x0), x1 = Int(b.x1), y0 = Int(b.y0), y1 = Int(b.y1)
            for t in 0..<2 {
                for x in x0...max(x0, x1) { put(x, y0 + t, c); put(x, y1 - t, c) }
                for y in y0...max(y0, y1) { put(x0 + t, y, c); put(x1 - t, y, c) }
            }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * w,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    @inline(__always) private static func setGreen(_ rgba: inout [UInt8], _ w: Int, _ x: Int, _ y: Int) {
        let k = 4 * (y * w + x)
        rgba[k] = 40; rgba[k + 1] = 220; rgba[k + 2] = 90
    }
}
