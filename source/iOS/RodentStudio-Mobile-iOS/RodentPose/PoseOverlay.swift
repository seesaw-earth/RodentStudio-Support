// PoseOverlay.swift — drawing skeletons, zones and head direction on top of video frames.

import SwiftUI

enum PoseDrawing {
    /// Draws one or two skeletons. Positions are pixels of the upright frame (`frameSize`),
    /// mapped into `rect` (the displayed image rectangle).
    static func draw(_ ctx: inout GraphicsContext, poses: [AnimalPose], frameSize: V2, rect: CGRect,
                     minConf: Float = 0.3, showHeading: Bool = true, scale: CGFloat = 1) {
        let multi = poses.count > 1
        for (a, pose) in poses.enumerated() where pose.detected {
            func pt(_ k: Int) -> CGPoint {
                CGPoint(x: rect.minX + CGFloat(Double(pose.x[k]) / max(frameSize.x, 1)) * rect.width,
                        y: rect.minY + CGFloat(Double(pose.y[k]) / max(frameSize.y, 1)) * rect.height)
            }
            let boneColor: Color = multi ? (a == 0 ? Palette.okabeBlue : Palette.okabeVermillion) : .white
            // All bones in one path: two strokes per animal instead of two per bone.
            var bones = Path()
            for (i, j) in kBones where pose.kconf[i] >= minConf && pose.kconf[j] >= minConf {
                bones.move(to: pt(i))
                bones.addLine(to: pt(j))
            }
            if !bones.isEmpty {
                ctx.stroke(bones, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
                ctx.stroke(bones, with: .color(boneColor), style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
            }
            if showHeading, pose.kconf[0] >= minConf, pose.kconf[1] >= minConf, pose.kconf[2] >= minConf {
                let base = CGPoint(x: (pt(1).x + pt(2).x) / 2, y: (pt(1).y + pt(2).y) / 2)
                let nose = pt(0)
                let dx = nose.x - base.x, dy = nose.y - base.y
                let len = max(hypot(dx, dy), 1)
                let tip = CGPoint(x: nose.x + dx / len * 18 * scale, y: nose.y + dy / len * 18 * scale)
                var arrow = Path()
                arrow.move(to: nose)
                arrow.addLine(to: tip)
                ctx.stroke(arrow, with: .color(.yellow.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, dash: [3, 2]))
            }
            var outlines = Path()
            for k in 0..<kKeypointCount {
                let c = pt(k)
                let r = 4.2 * scale
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                if pose.kconf[k] >= minConf {
                    ctx.fill(Path(ellipseIn: rect), with: .color(Palette.keypoint(k)))
                    outlines.addEllipse(in: rect)
                } else {
                    ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.keypoint(k).opacity(0.6)), lineWidth: 1 * scale)
                }
            }
            if !outlines.isEmpty {
                ctx.stroke(outlines, with: .color(.white), lineWidth: 1 * scale)
            }
            if multi {
                let label = a == 0 ? "A" : "B"
                let c = pt(KP.bodyCenter.rawValue)
                ctx.draw(Text(label).font(.system(size: 12 * scale, weight: .heavy)).foregroundColor(boneColor), at: CGPoint(x: c.x + 12 * scale, y: c.y - 12 * scale))
            }
        }
    }

    /// Draws the last `samples` points of a smoothed display trail ending at frame `end`, fading
    /// toward the past. Lines are only drawn between samples of the same segment, so a gap or an
    /// implausible jump never becomes a line across the arena.
    static func drawTrail(_ ctx: inout GraphicsContext, trail: DisplayTrail, upTo end: Int, samples: Int,
                          rect: CGRect, color: Color, lineWidth: CGFloat = 2.2) {
        guard !trail.isEmpty, end >= 0 else { return }
        let last = min(end, trail.count - 1)
        let first = max(0, last - max(1, samples))
        guard last > first else { return }
        func vp(_ i: Int) -> CGPoint? {
            guard let p = trail.point(i) else { return nil }
            return CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
        }
        func path(_ a: Int, _ b: Int) -> Path {
            var p = Path()
            var open = false
            for j in a...b {
                guard let q = vp(j) else {
                    open = false
                    continue
                }
                if open && trail.connected(j - 1, j) { p.addLine(to: q) } else { p.move(to: q) }
                open = true
            }
            return p
        }
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        // Dark halo keeps the line visible on bright or white arenas.
        ctx.stroke(path(first, last), with: .color(.black.opacity(0.35)),
                   style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round, lineJoin: .round))
        let bands = 4
        let span = last - first
        for b in 0..<bands {
            let a0 = first + span * b / bands
            let a1 = first + span * (b + 1) / bands
            guard a1 > a0 else { continue }
            let opacity = 0.2 + 0.7 * Double(b + 1) / Double(bands)
            ctx.stroke(path(a0, a1), with: .color(color.opacity(opacity)), style: style)
        }
    }

    /// Draws zone outlines (arena units) mapped to the image.
    static func drawZones(_ ctx: inout GraphicsContext, zones: [Zone], mapping: ArenaMapping, rect: CGRect, labels: Bool = true) {
        func vp(_ a: V2) -> CGPoint {
            let n = mapping.toNormalized(a)
            return CGPoint(x: rect.minX + CGFloat(n.x) * rect.width, y: rect.minY + CGFloat(n.y) * rect.height)
        }
        for z in zones where z.role != .arena {
            let pts = z.outline(segments: 48).map(vp)
            guard pts.count > 2 else { continue }
            var path = Path()
            path.addLines(pts)
            path.closeSubpath()
            let color = Palette.zone(z.role)
            if !z.outlineOnly && z.role != .hole { ctx.fill(path, with: .color(color.opacity(0.14))) }
            ctx.stroke(path, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, dash: z.outlineOnly ? [4, 3] : []))
            if labels && z.showsLabel && !z.title.isEmpty {
                let label = Text(z.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                let at = vp(z.center)
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
                    layer.draw(label, at: at)
                }
            }
        }
    }
}

/// A video frame with skeleton overlay, aspect-fit.
struct FrameWithPose: View {
    let image: CGImage?
    let frameSize: V2
    var poses: [AnimalPose] = []
    var zones: [Zone] = []
    var mapping: ArenaMapping?

    var body: some View {
        GeometryReader { geo in
            let rect = aspectFitRect(CGSize(width: frameSize.x, height: frameSize.y), in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                Canvas { ctx, _ in
                    if let mapping, !zones.isEmpty {
                        PoseDrawing.drawZones(&ctx, zones: zones, mapping: mapping, rect: rect, labels: false)
                    }
                    PoseDrawing.draw(&ctx, poses: poses, frameSize: frameSize, rect: rect)
                }
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(CGFloat(frameSize.x / max(frameSize.y, 1)), contentMode: .fit)
    }
}
