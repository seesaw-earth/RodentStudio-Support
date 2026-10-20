import SwiftUI
import AppKit
/// Frame with the chambers. Click a chamber to mark whether it holds a mouse; drag the white handles to
/// move walls; on the key-frame step the yellow handles set the vertical analysis band.
///
/// The body is split into small views with explicitly typed values so the Swift type-checker handles it
/// quickly (one large GeometryReader expression exceeds its time limit).
struct TSTChamberEditor: View {
    @Environment(TSTAppModel.self) private var model
    let image: CGImage
    let layout: ChamberLayout
    var showBand: Bool = false
    /// Motion boxes of the box metric (image coordinates), drawn dashed; not interactive.
    var motionBoxes: [DetBox?] = []

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
    }

    private func content(size: CGSize) -> some View {
        let scale: CGFloat = size.width / CGFloat(max(1, layout.imageWidth))
        let bandTop: CGFloat = showBand ? CGFloat(layout.y0) * scale : 0
        let bandBottom: CGFloat = showBand ? CGFloat(layout.y1) * scale : size.height
        return ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .frame(width: size.width, height: size.height)
            chambers(scale: scale, top: bandTop, bottom: bandBottom)
            boxOverlay(scale: scale)
            walls(scale: scale, height: size.height)
            if showBand {
                bandHandles(scale: scale, width: size.width, top: bandTop, bottom: bandBottom)
            }
        }
        .coordinateSpace(.named("editor"))
    }

    private func chambers(scale: CGFloat, top: CGFloat, bottom: CGFloat) -> some View {
        ForEach(0..<layout.count, id: \.self) { (i: Int) in
            let x0: CGFloat = CGFloat(layout.walls[i]) * scale
            let x1: CGFloat = CGFloat(layout.walls[i + 1]) * scale
            let on: Bool = i < layout.enabled.count && layout.enabled[i]
            TSTChamberCell(number: i + 1, isOn: on)
                .frame(width: max(2, x1 - x0), height: max(2, bottom - top))
                .offset(x: x0, y: top)
                .onTapGesture { model.toggleChamber(i) }
        }
    }

    private func boxOverlay(scale: CGFloat) -> some View {
        let rects: [CGRect] = motionBoxes.compactMap { box -> CGRect? in
            guard let b = box else { return nil }
            return CGRect(x: CGFloat(b.x0) * scale, y: CGFloat(b.y0) * scale,
                          width: CGFloat(b.x1 - b.x0) * scale, height: CGFloat(b.y1 - b.y0) * scale)
        }
        return ForEach(rects.indices, id: \.self) { (k: Int) in
            Rectangle()
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: rects[k].width, height: rects[k].height)
                .offset(x: rects[k].minX, y: rects[k].minY)
                .allowsHitTesting(false)
        }
    }

    private func walls(scale: CGFloat, height: CGFloat) -> some View {
        ForEach(0..<layout.walls.count, id: \.self) { (j: Int) in
            let x: CGFloat = CGFloat(layout.walls[j]) * scale
            WallHandle(height: height)
                .position(x: x, y: height / 2)
                .gesture(wallDrag(j, scale: scale))
        }
    }

    private func wallDrag(_ j: Int, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("editor"))
            .onChanged { (v: DragGesture.Value) in
                model.moveWall(j, to: Double(v.location.x / scale))
            }
    }

    @ViewBuilder
    private func bandHandles(scale: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat) -> some View {
        BandHandle(width: width)
            .position(x: width / 2, y: top)
            .gesture(bandDrag(top: true, scale: scale))
        BandHandle(width: width)
            .position(x: width / 2, y: bottom)
            .gesture(bandDrag(top: false, scale: scale))
    }

    private func bandDrag(top: Bool, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("editor"))
            .onChanged { (v: DragGesture.Value) in
                model.moveBand(top: top, to: Double(v.location.y / scale))
            }
    }
}

/// One chamber: tinted when analysed, darkened when skipped, with its number on top.
private struct TSTChamberCell: View {
    let number: Int
    let isOn: Bool

    private var fill: Color { isOn ? Color.orange.opacity(0.12) : Color.black.opacity(0.45) }
    private var stroke: Color { isOn ? Color.orange : Color.gray }
    private var helpText: String {
        isOn ? L("Click to skip this chamber", "点击以跳过此格") : L("Click to analyse this chamber", "点击以分析此格")
    }
    private var accessibilityText: String {
        let name: String = String(format: L("Chamber %d", "第 %d 格"), number)
        let state: String = isOn ? L("analysed", "分析") : L("skipped", "跳过")
        return name + ", " + state
    }

    var body: some View {
        Rectangle()
            .fill(fill)
            .overlay(Rectangle().stroke(stroke, lineWidth: 1.5))
            .overlay(alignment: .top) { badge }
            .contentShape(Rectangle())
            .help(helpText)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var badge: some View {
        HStack(spacing: 3) {
            Text("\(number)").font(.caption.bold())
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
            if !isOn {
                Text(L("skip", "跳过")).font(.caption2)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        .padding(.top, 3)
    }
}

private struct WallHandle: View {
    let height: CGFloat
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white).frame(width: 2, height: height).shadow(radius: 1)
            Circle().fill(Color.white).frame(width: 16, height: 16).shadow(radius: 2)
            Image(systemName: "arrow.left.and.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.black)
        }
        .frame(width: 32, height: height)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .help(L("Drag onto the wall between two chambers", "拖到两格之间的隔板上"))
    }
}

private struct BandHandle: View {
    let width: CGFloat
    var body: some View {
        ZStack {
            Rectangle().fill(Color.yellow).frame(width: width, height: 2)
                .allowsHitTesting(false)        // only the grip is draggable; chambers stay clickable
            Capsule().fill(Color.yellow).frame(width: 40, height: 12)
                .frame(width: 88, height: 30)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                .help(L("Drag to set the top / bottom of the analysed band", "拖动设置分析带的上沿／下沿"))
        }
        .frame(width: width, height: 30)
    }
}
