// FlowCalibrationEditor.swift — RodentFlow setup on the desktop: arena shape and dimensions,
// calibration handles with zone preview and markers, and analysis settings. Ported from RodentFlow
// iOS 1.3 SetupView.swift (arena / calibration sections), ArenaCalibrationView.swift and
// ZoneParameterEditor.swift. Desktop changes: pointer dragging keeps the initial offset, a loupe,
// arrow-key nudging, and one write per drag.

import SwiftUI

struct FlowCalibrationEditor: View {
    @Binding var setup: FlowTaskSetup
    let image: CGImage?
    let frameSize: CGSize
    let loadingFrame: Bool
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var frameTime: Double = 0
    @State private var confirmReset = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(calibrationTitle).font(.headline)
                Text(calibrationInstruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                FlowCalibrationCanvas(image: image, frameSize: frameSize, shape: setup.shape, assay: setup.assay,
                                      zone: setup.zone, calibration: $setup.calibration)
                    .overlay(alignment: .topTrailing) {
                        if loadingFrame { ProgressView().controlSize(.small).padding(10) }
                    }
                Text(calibrationFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HandleKeyboardHint()
                if duration > 0 {
                    CalibrationFrameScrubber(time: $frameTime, duration: duration) { t in
                        setup.frameTime = t
                        onSeek(t)
                    }
                }
                HStack {
                    Spacer()
                    Button {
                        confirmReset = true
                    } label: {
                        Label(L("Reset", "重置"), systemImage: "arrow.uturn.backward")
                    }
                }
            }
            .padding(.bottom, 12)
            }
            .frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    arenaCard
                    SetupCard(L("Analysis settings", "分析设置"), symbol: "slider.horizontal.3",
                              subtitle: L("Zones and thresholds are applied after tracking and can be changed later on the result screen without re-analyzing the video.",
                                          "区域和阈值在追踪后才应用，之后可在结果页面修改，无需重新分析视频。")) {
                        FlowZoneEditor(assay: setup.assay, config: $setup.zone)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(width: 340)
        }
        .onAppear { frameTime = setup.frameTime }
        .onChange(of: setup.shape) { _, _ in setup.syncArenaSize() }
        .onChange(of: setup.dimensions) { _, _ in setup.syncArenaSize() }
        .confirmationDialog(L("Reset calibration handles to their default positions?", "把手柄恢复到默认位置？"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Reset positions", "恢复默认位置"), role: .destructive) { setup.calibration = FlowArenaCalibration() }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }

    // MARK: Arena (SetupView "Assay & arena")

    private var arenaCard: some View {
        SetupCard(L("Assay & arena", "实验范式与场地"), symbol: "square.dashed") {
            if setup.assay.videoArenaShapes.count > 1 {
                Picker(L("Arena shape", "场地形状"), selection: $setup.shape) {
                    ForEach(setup.assay.videoArenaShapes) { shape in
                        Text(shape.shortName).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                Label(setup.shape.displayName, systemImage: setup.shape.systemImage).font(.callout)
            }
            switch setup.shape {
            case .rectangle:
                NumberField(title: L("Width", "宽度"), value: $setup.dimensions.arenaWidthCM, unit: "cm", range: 1...500)
                NumberField(title: L("Height", "高度"), value: $setup.dimensions.arenaHeightCM, unit: "cm", range: 1...500)
            case .circle:
                NumberField(title: L("Diameter", "直径"), value: $setup.dimensions.arenaWidthCM, unit: "cm", range: 1...500)
            case .tMaze:
                NumberField(title: L("Start arm length", "起始臂长度"), value: $setup.dimensions.tStartArmLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L("Choice arm length (each side)", "选择臂长度（每侧）"), value: $setup.dimensions.tChoiceArmLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L("Arm width", "臂宽"), value: $setup.dimensions.mazeArmWidthCM, unit: "cm", range: 1...50)
            case .yMaze:
                NumberField(title: L("Arm length", "臂长"), value: $setup.dimensions.yArmLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L("Arm width", "臂宽"), value: $setup.dimensions.mazeArmWidthCM, unit: "cm", range: 1...50)
            case .plusMaze:
                NumberField(title: L("Arm length (excluding center)", "臂长（不含中央区）"), value: $setup.dimensions.plusArmLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L("Arm width", "臂宽"), value: $setup.dimensions.plusArmWidthCM, unit: "cm", range: 1...50)
            }
        }
    }

    // MARK: Texts (SetupView)

    private var calibrationTitle: String {
        switch setup.shape {
        case .rectangle: return L("Arena corners", "场地四角")
        case .circle: return L("Arena circle", "场地圆形")
        case .tMaze: return L("T-maze centerlines", "T 迷宫中线")
        case .yMaze: return L("Y-maze centerlines", "Y 迷宫中线")
        case .plusMaze: return L("Plus-maze centerlines", "十字迷宫中线")
        }
    }

    private var calibrationInstruction: String {
        let base: String
        switch setup.shape {
        case .rectangle: base = L("Drag 1 → 2 → 3 → 4 around the inner floor boundary.", "沿场地底面内边界依次拖动 1 → 2 → 3 → 4。")
        case .circle: base = L("Drag C to the arena center, then drag R to the inner wall boundary.", "将 C 拖到场地中心，再将 R 拖到内壁边界。")
        case .tMaze: base = L("Drag J to the junction, S to the end of the start arm, and L/R to the two choice-arm ends.", "将 J 拖到交汇点，S 拖到起始臂末端，L/R 拖到两条选择臂末端。")
        case .yMaze: base = L("Drag J to the center junction and A/B/C to the three arm ends.", "将 J 拖到中心交汇点，A/B/C 拖到三条臂的末端。")
        case .plusMaze: base = L("Drag C to the maze center and N/E/S/W to the ends of the four arms.", "将 C 拖到迷宫中心，N/E/S/W 拖到四条臂的末端。")
        }
        switch setup.assay {
        case .novelObject: return base + " " + L("Then drag A and B onto the centers of the two objects.", "然后将 A 和 B 拖到两个物体的中心。")
        case .morrisWaterMaze: return base + " " + L("Then drag P onto the platform center.", "然后将 P 拖到平台中心。")
        case .barnesMaze: return base + " " + L("Then drag T onto the target (escape) hole.", "然后将 T 拖到目标（逃避）洞上。")
        default: return base
        }
    }

    private var calibrationFootnote: String {
        switch setup.shape {
        case .rectangle: return L("Coordinates are perspective-corrected before conversion to centimeters.", "坐标会先做透视校正，再换算为厘米。")
        case .circle: return L("Best with a top-down or near-top-down camera. C defines center and R defines radius.", "最适合正上方或接近正上方的摄像角度。C 定义圆心，R 定义半径。")
        case .tMaze: return L("The app builds a lightweight corridor mask from the three centerlines and the entered arm width.", "App 会根据三条中线和输入的臂宽生成简易的通道遮罩。")
        case .yMaze: return L("The app builds a lightweight three-arm corridor mask. Arm entries require 0.25 s of stable zone occupancy.", "App 会生成简易的三臂通道遮罩。稳定停留 0.25 s 才计为进臂。")
        case .plusMaze: return L("Arms are labeled by image direction (N = top). Choose which pair is open in Analysis settings.", "各臂按画面方向标记（N = 上）。请在“分析设置”中选择哪一对是开放臂。")
        }
    }
}

// MARK: - Canvas (RodentFlow ArenaCalibrationView)

struct FlowCalibrationCanvas: View {
    let image: CGImage?
    let frameSize: CGSize
    let shape: FlowArenaShape
    let assay: FlowAssay
    let zone: FlowZoneConfig
    @Binding var calibration: FlowArenaCalibration

    private struct Handle: Identifiable {
        let id: String
        let label: String
        let point: FlowPoint
        let color: Color
    }

    @State private var draft: FlowArenaCalibration?
    @State private var dragOrigin: [String: FlowPoint] = [:]
    @State private var activeHandle: String?
    @State private var selectedHandle: String?
    @FocusState private var focused: Bool

    private var cal: FlowArenaCalibration { draft ?? calibration }

    var body: some View {
        GeometryReader { geo in
            let rect = calibrationFitRect(frameSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                Canvas { ctx, _ in drawOverlay(&ctx, rect) }
                    .allowsHitTesting(false)
                ForEach(handles) { h in
                    CalibrationHandleView(label: h.label, color: h.color,
                                          active: activeHandle == h.id, selected: selectedHandle == h.id)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("flowCalibrationCanvas"))
                                .onChanged { v in
                                    let origin = dragOrigin[h.id] ?? h.point
                                    if dragOrigin[h.id] == nil {
                                        dragOrigin[h.id] = origin
                                        activeHandle = h.id
                                        selectedHandle = h.id
                                        focused = true
                                    }
                                    let dx = Double((v.location.x - v.startLocation.x) / max(rect.width, 1))
                                    let dy = Double((v.location.y - v.startLocation.y) / max(rect.height, 1))
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        move(h.id, to: FlowPoint(x: origin.x + dx, y: origin.y + dy).clamped())
                                    }
                                }
                                .onEnded { _ in
                                    commit()
                                    dragOrigin.removeValue(forKey: h.id)
                                    activeHandle = nil
                                }
                        )
                        .position(viewPoint(h.point, rect))
                        .zIndex(activeHandle == h.id ? 1 : 0)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("Handle \(h.label)", "手柄 \(h.label)"))
                        .accessibilityAction(named: L("Move left", "向左移动")) { nudge(h.id, dx: -0.01, dy: 0) }
                        .accessibilityAction(named: L("Move right", "向右移动")) { nudge(h.id, dx: 0.01, dy: 0) }
                        .accessibilityAction(named: L("Move up", "向上移动")) { nudge(h.id, dx: 0, dy: -0.01) }
                        .accessibilityAction(named: L("Move down", "向下移动")) { nudge(h.id, dx: 0, dy: 0.01) }
                }
                if let id = activeHandle, let h = handles.first(where: { $0.id == id }) {
                    let p = viewPoint(h.point, rect)
                    CalibrationLoupe(image: image, imageRect: rect, point: p, color: h.color)
                        .position(CalibrationLoupe.center(for: p, in: geo.size))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
            .coordinateSpace(name: "flowCalibrationCanvas")
        }
        .aspectRatio(frameSize.width / max(frameSize.height, 1), contentMode: .fit)
        .frame(minHeight: 260, maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            guard let id = selectedHandle else { return .ignored }
            let step = press.modifiers.contains(.shift) ? 0.01 : 0.002
            switch press.key {
            case .leftArrow: nudge(id, dx: -step, dy: 0)
            case .rightArrow: nudge(id, dx: step, dy: 0)
            case .upArrow: nudge(id, dx: 0, dy: -step)
            default: nudge(id, dx: 0, dy: step)
            }
            return .handled
        }
        .onChange(of: shape) { _, _ in selectedHandle = nil }
    }

    // MARK: Handles

    private var handles: [Handle] {
        var hs: [Handle] = []
        switch shape {
        case .rectangle:
            for (i, p) in cal.corners.enumerated() { hs.append(Handle(id: "corner\(i)", label: "\(i + 1)", point: p, color: .yellow)) }
        case .circle:
            hs.append(Handle(id: "center", label: "C", point: cal.circleCenter, color: .yellow))
            hs.append(Handle(id: "edge", label: "R", point: cal.circleEdge, color: .yellow))
        case .tMaze:
            for (i, (l, p)) in zip(["J", "S", "L", "R"], cal.tPoints).enumerated() {
                hs.append(Handle(id: "t\(i)", label: l, point: p, color: .yellow))
            }
        case .yMaze:
            for (i, (l, p)) in zip(["J", "A", "B", "C"], cal.yPoints).enumerated() {
                hs.append(Handle(id: "y\(i)", label: l, point: p, color: .yellow))
            }
        case .plusMaze:
            let openAxis = zone.plusOpenAxis
            for (i, (l, p)) in zip(["C", "N", "E", "S", "W"], cal.plusPoints).enumerated() {
                let isOpen = i > 0 && (openAxis == "EW" ? (i == 2 || i == 4) : (i == 1 || i == 3))
                hs.append(Handle(id: "plus\(i)", label: l, point: p, color: isOpen ? .cyan : .yellow))
            }
        }
        switch assay {
        case .novelObject:
            hs.append(Handle(id: "markerA", label: "A", point: cal.markerA, color: .cyan))
            hs.append(Handle(id: "markerB", label: "B", point: cal.markerB, color: .cyan))
        case .morrisWaterMaze where shape == .circle:
            hs.append(Handle(id: "markerTarget", label: "P", point: cal.markerTarget, color: .cyan))
        case .barnesMaze where shape == .circle:
            hs.append(Handle(id: "markerTarget", label: "T", point: cal.markerTarget, color: .cyan))
        default:
            break
        }
        return hs
    }

    private func move(_ id: String, to p: FlowPoint) {
        var c = cal
        if id.hasPrefix("corner"), let i = Int(id.dropFirst(6)) {
            c.setCorner(i, to: p)
        } else if id == "center" {
            // C moves the whole circle; R keeps its offset (as in RodentFlow).
            let dx = c.circleEdge.x - c.circleCenter.x, dy = c.circleEdge.y - c.circleCenter.y
            c.circleCenter = p
            c.circleEdge = FlowPoint(x: p.x + dx, y: p.y + dy).clamped()
        } else if id == "edge" {
            c.circleEdge = p
        } else if id.hasPrefix("plus"), let i = Int(id.dropFirst(4)) {
            c.setPlusMazePoint(i, to: p)
        } else if id.hasPrefix("t"), let i = Int(id.dropFirst(1)) {
            c.setTMazePoint(i, to: p)
        } else if id.hasPrefix("y"), let i = Int(id.dropFirst(1)) {
            c.setYMazePoint(i, to: p)
        } else if id == "markerA" {
            c.markerA = p
        } else if id == "markerB" {
            c.markerB = p
        } else if id == "markerTarget" {
            c.markerTarget = p
        }
        draft = c
    }

    private func commit() {
        guard let draft else { return }
        calibration = draft
        self.draft = nil
    }

    private func nudge(_ id: String, dx: Double, dy: Double) {
        guard let h = handles.first(where: { $0.id == id }) else { return }
        move(id, to: FlowPoint(x: h.point.x + dx, y: h.point.y + dy).clamped())
        commit()
    }

    // MARK: Drawing

    private func viewPoint(_ p: FlowPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        let yellow = Color.yellow
        let dashed = StrokeStyle(lineWidth: 2, dash: [7, 5])
        let zoneStyle = StrokeStyle(lineWidth: 1.5, dash: [5, 4])

        // Read-only preview of arena-space zones (centre square, light/dark divider, CPP chambers).
        if shape == .rectangle, let h = PlanarHomography.arenaToImage(cal) {
            var path = Path()
            for polyline in rectangleZoneLines(zone) {
                guard let first = polyline.first else { continue }
                let p0 = h.map(first.0, first.1)
                path.move(to: CGPoint(x: rect.minX + CGFloat(p0.0) * rect.width, y: rect.minY + CGFloat(p0.1) * rect.height))
                for q in polyline.dropFirst() {
                    let p = h.map(q.0, q.1)
                    path.addLine(to: CGPoint(x: rect.minX + CGFloat(p.0) * rect.width, y: rect.minY + CGFloat(p.1) * rect.height))
                }
            }
            ctx.stroke(path, with: .color(.cyan), style: zoneStyle)
        } else if shape == .circle && assay == .openField {
            let c = viewPoint(cal.circleCenter, rect), e = viewPoint(cal.circleEdge, rect)
            let r = hypot(e.x - c.x, e.y - c.y) * CGFloat(zone.centerFraction)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.cyan), style: zoneStyle)
        }

        switch shape {
        case .rectangle:
            var p = Path()
            p.addLines(cal.corners.map { viewPoint($0, rect) })
            p.closeSubpath()
            ctx.stroke(p, with: .color(yellow), style: dashed)
        case .circle:
            let c = viewPoint(cal.circleCenter, rect), e = viewPoint(cal.circleEdge, rect)
            let r = hypot(e.x - c.x, e.y - c.y)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(yellow), style: dashed)
            var radius = Path()
            radius.move(to: c)
            radius.addLine(to: e)
            ctx.stroke(radius, with: .color(yellow.opacity(0.8)), lineWidth: 2)
        case .tMaze:
            let pts = cal.tPoints.map { viewPoint($0, rect) }
            var p = Path()
            p.move(to: pts[1]); p.addLine(to: pts[0])
            p.move(to: pts[2]); p.addLine(to: pts[0]); p.addLine(to: pts[3])
            ctx.stroke(p, with: .color(yellow), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))
        case .yMaze, .plusMaze:
            let pts = (shape == .yMaze ? cal.yPoints : cal.plusPoints).map { viewPoint($0, rect) }
            var p = Path()
            for e in pts.dropFirst() {
                p.move(to: pts[0])
                p.addLine(to: e)
            }
            ctx.stroke(p, with: .color(yellow), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))
        }

        if shape == .circle && assay == .morrisWaterMaze {
            // Quadrant boundaries through the platform direction (RodentFlow quadrantLines).
            let c = viewPoint(cal.circleCenter, rect), e = viewPoint(cal.circleEdge, rect), p = viewPoint(cal.markerTarget, rect)
            let r = hypot(e.x - c.x, e.y - c.y)
            let a = atan2(Double(p.y - c.y), Double(p.x - c.x))
            var path = Path()
            for offset in [Double.pi / 4, -Double.pi / 4] {
                let dx = CGFloat(cos(a + offset)) * r, dy = CGFloat(sin(a + offset)) * r
                path.move(to: CGPoint(x: c.x - dx, y: c.y - dy))
                path.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
            }
            ctx.stroke(path, with: .color(.cyan.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
        if shape == .circle && assay == .barnesMaze {
            // Ring of holes through the target hole (RodentFlow holeRing).
            let c = viewPoint(cal.circleCenter, rect), p = viewPoint(cal.markerTarget, rect)
            let ring = hypot(p.x - c.x, p.y - c.y)
            let a = atan2(Double(p.y - c.y), Double(p.x - c.x))
            let count = max(4, zone.holeCount)
            var path = Path()
            for k in 1..<count {
                let angle = a + 2 * Double.pi * Double(k) / Double(count)
                let center = CGPoint(x: c.x + CGFloat(cos(angle)) * ring, y: c.y + CGFloat(sin(angle)) * ring)
                path.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            }
            ctx.stroke(path, with: .color(.cyan.opacity(0.9)), lineWidth: 1.2)
        }
    }

    /// Zone outlines in arena-normalized coordinates for rectangular arenas (RodentFlow rectangleZoneLines).
    private func rectangleZoneLines(_ c: FlowZoneConfig) -> [[(Double, Double)]] {
        switch assay {
        case .openField:
            let a = (1 - c.centerFraction) / 2, b = (1 + c.centerFraction) / 2
            return [[(a, a), (b, a), (b, b), (a, b), (a, a)]]
        case .lightDark:
            let x = c.lightOnLeft ? c.lightFraction : 1 - c.lightFraction
            return x > 0.001 && x < 0.999 ? [[(x, 0), (x, 1)]] : []
        case .placePreference:
            if c.cppChambers >= 3 {
                let a = (1 - c.cppNeutralFraction) / 2, b = (1 + c.cppNeutralFraction) / 2
                return [[(a, 0), (a, 1)], [(b, 0), (b, 1)]]
            }
            return [[(c.cppDivider, 0), (c.cppDivider, 1)]]
        default:
            return []
        }
    }
}

// MARK: - Analysis settings (RodentFlow ZoneParameterEditor)

struct FlowZoneEditor: View {
    let assay: FlowAssay
    @Binding var config: FlowZoneConfig
    var showWindow = true

    @State private var csText = ""
    @State private var csCount = 3
    @State private var csFirst: Double = 120
    @State private var csInterval: Double = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch assay {
            case .openField: openFieldControls
            case .elevatedPlusMaze: plusMazeControls
            case .lightDark: lightDarkControls
            case .placePreference: cppControls
            case .novelObject: norControls
            case .morrisWaterMaze: waterMazeControls
            case .barnesMaze: barnesControls
            case .fearConditioning: fearControls
            case .yMaze, .tMaze: mazeControls
            }
            if showWindow && assay != .fearConditioning {
                windowControls
            }
        }
        .onAppear { csText = OnsetsEditor.format(config.csOnsetsSeconds) }
    }

    private var openFieldControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(L("Center zone size", "中央区大小"), value: $config.centerFraction, range: 0.3...0.8, step: 0.05) { f in
                String(format: L("%.0f%% of side · %.0f%% of area", "边长的 %.0f%% · 面积的 %.0f%%"), f * 100, f * f * 100)
            }
            sliderRow(L("Moving threshold", "运动阈值"), value: $config.movingSpeedCMs, range: 0.5...6, step: 0.5) { String(format: "%.1f cm/s", $0) }
            sliderRow(L("Minimum immobility bout", "最短不动时长"), value: $config.immobilityMinSeconds, range: 0.5...5, step: 0.5) { String(format: "%.1f s", $0) }
            labeled(L("Time bins", "时间段")) {
                Picker(L("Time bins", "时间段"), selection: $config.timeBinSeconds) {
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                    Text("10 min").tag(600.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            entryRow
        }
    }

    private var plusMazeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("Open arms", "开放臂")) {
                Picker(L("Open arms", "开放臂"), selection: $config.plusOpenAxis) {
                    Text(L("N–S (top/bottom)", "北–南（上/下）")).tag("NS")
                    Text(L("E–W (left/right)", "东–西（左/右）")).tag("EW")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            sliderRow(L("Extra center margin", "中央区外扩"), value: $config.plusCenterMarginCM, range: 0...4, step: 0.5) { String(format: "+%.1f cm", $0) }
            entryRow
        }
    }

    private var lightDarkControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("Light compartment", "明箱")) {
                Picker(L("Light compartment", "明箱"), selection: $config.lightOnLeft) {
                    Text(L("Left", "左")).tag(true)
                    Text(L("Right", "右")).tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            sliderRow(L("Light compartment length", "明箱长度"), value: $config.lightFraction, range: 0.3...1.0, step: 0.01) {
                String(format: L("%.0f%% of arena", "场地的 %.0f%%"), $0 * 100)
            }
            Toggle(L("Count unseen samples as dark", "看不到小鼠时计为在暗箱"), isOn: $config.undetectedIsDark)
            Text(L("If only the light compartment was calibrated, use 100%.", "如果只校准了明箱，请设为 100%。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            entryRow
        }
    }

    private var cppControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("Apparatus", "装置")) {
                Picker(L("Apparatus", "装置"), selection: $config.cppChambers) {
                    Text(L("2 chambers", "两箱")).tag(2)
                    Text(L("3 chambers", "三箱")).tag(3)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            if config.cppChambers >= 3 {
                sliderRow(L("Neutral chamber width", "中间箱宽度"), value: $config.cppNeutralFraction, range: 0.05...0.5, step: 0.01) {
                    String(format: L("%.0f%% of arena", "场地的 %.0f%%"), $0 * 100)
                }
            } else {
                sliderRow(L("Divider position", "分隔线位置"), value: $config.cppDivider, range: 0.2...0.8, step: 0.01) {
                    String(format: L("%.0f%% from left", "距左侧 %.0f%%"), $0 * 100)
                }
            }
            labeled(L("Paired (drug / reward) side", "配对（药物 / 奖赏）侧")) {
                Picker(L("Paired (drug / reward) side", "配对（药物 / 奖赏）侧"), selection: $config.cppPairedOnLeft) {
                    Text(L("Left", "左")).tag(true)
                    Text(L("Right", "右")).tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            entryRow
        }
    }

    private var norControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("Novel object", "新物体")) {
                Picker(L("Novel object", "新物体"), selection: $config.novelObject) {
                    Text("A").tag("A")
                    Text("B").tag("B")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            sliderRow(L("Interaction radius (centroid)", "交互半径（质心）"), value: $config.objectZoneRadiusCM, range: 2...14, step: 0.5) { String(format: "%.1f cm", $0) }
            Text(L("Measured from the body centre, which sits ~4–5 cm behind the nose: use about object radius + 5 cm.",
                   "从身体中心算起，身体中心位于鼻尖后约 4–5 cm：建议设为物体半径 + 5 cm 左右。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sliderRow(L("Exclusion criterion (total)", "排除标准（总探索）"), value: $config.minTotalExplorationSeconds, range: 0...30, step: 1) { String(format: "%.0f s", $0) }
            entryRow
        }
    }

    private var waterMazeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(L("Platform zone radius", "平台区半径"), value: $config.targetRadiusCM, range: 3...15, step: 0.5) { String(format: "%.1f cm", $0) }
            sliderRow(L("Trial maximum", "试次最长时间"), value: $config.maxTrialSeconds, range: 30...180, step: 5) { String(format: "%.0f s", $0) }
            sliderRow(L("Must stay on platform", "需在平台停留"), value: $config.platformStaySeconds, range: 0...5, step: 0.5) { String(format: "%.1f s", $0) }
            sliderRow(L("Wall zone width", "贴壁区宽度"), value: $config.wallZoneCM, range: 0...25, step: 1) { String(format: "%.0f cm", $0) }
        }
    }

    private var barnesControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: $config.holeCount, in: 8...40) {
                Text(String(format: L("Holes: %ld", "洞数：%ld"), config.holeCount))
            }
            sliderRow(L("Hole zone radius", "洞区半径"), value: $config.targetRadiusCM, range: 2...14, step: 0.5) { String(format: "%.1f cm", $0) }
            Text(L("Measured from the body centre. During a poke the head disappears into the hole, so the centre stays ~5–7 cm away; visits go to the nearest hole.",
                   "从身体中心算起。探洞时头部伸入洞中，身体中心仍距洞约 5–7 cm；访问计入最近的洞。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            sliderRow(L("Trial maximum", "试次最长时间"), value: $config.maxTrialSeconds, range: 60...600, step: 10) { String(format: "%.0f s", $0) }
            entryRow
        }
    }

    private var mazeControls: some View {
        sliderRow(L("Arm entry criterion", "进臂标准"), value: $config.mazeEntryMinSeconds, range: 0.1...1.5, step: 0.05) {
            String(format: L("%.2f s stable", "稳定 %.2f s"), $0)
        }
    }

    private var fearControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(L("Freezing threshold", "僵直阈值"), value: $config.freezeThresholdPct, range: 0.5...30, step: 0.5) {
                String(format: L("%.1f%% of body changing", "身体面积的 %.1f%% 发生变化"), $0)
            }
            sliderRow(L("Minimum freezing bout", "最短僵直时长"), value: $config.freezeMinSeconds, range: 0.3...3, step: 0.1) { String(format: "%.1f s", $0) }
            numberRow(L("Protocol start in video", "实验程序在视频中的起点"), unit: "s", value: $config.protocolOffsetSeconds)
            numberRow(L("Baseline (pre-CS)", "基线（CS 前）"), unit: "s", value: $config.baselineSeconds)
            numberRow(L("CS duration", "CS 时长"), unit: "s", value: $config.csDurationSeconds)
            numberRow(L("Analyzed length (0 = all)", "分析长度（0 = 全部）"), unit: "s", value: $config.analysisDurationSeconds)
            labeled(L("Time bins", "时间段")) {
                Picker(L("Time bins", "时间段"), selection: $config.fearBinSeconds) {
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("CS onsets (s from protocol start)", "CS 起始时间（自实验程序开始的秒数）")).font(.callout)
                TextField(L("e.g. 120, 210, 300", "如 120, 210, 300"), text: $csText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospacedDigit())
                    .onChange(of: csText) { _, newValue in
                        let parsed = OnsetsEditor.parse(newValue)
                        if parsed != config.csOnsetsSeconds { config.csOnsetsSeconds = parsed }
                    }
                DisclosureGroup(L("Fill evenly", "等间隔填充")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Stepper(value: $csCount, in: 1...30) { Text(String(format: L("CS count: %ld", "CS 次数：%ld"), csCount)) }
                        numberRow(L("First onset", "首次起始"), unit: "s", value: $csFirst)
                        numberRow(L("Onset-to-onset interval", "起始间隔"), unit: "s", value: $csInterval)
                        Button(L("Apply", "应用")) {
                            let onsets = (0..<csCount).map { csFirst + Double($0) * csInterval }
                            config.csOnsetsSeconds = onsets
                            csText = OnsetsEditor.format(onsets)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
            }
            Text(L("Freezing = motion below the threshold for at least the minimum bout. Check the threshold against a few hand-scored clips from your own setup.",
                   "僵直 = 运动低于阈值并持续至少最短时长。请用您自己实验装置中几段人工评分的片段检验阈值。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var windowControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(L("Analysis window", "分析窗口")).font(.callout.weight(.semibold))
            numberRow(assay == .morrisWaterMaze || assay == .barnesMaze ? L("Trial start in video", "试次在视频中的起点") : L("Start after", "起始于"),
                      unit: "s", value: $config.analysisStartSeconds)
            if assay != .morrisWaterMaze && assay != .barnesMaze {
                numberRow(L("Length (0 = to end)", "长度（0 = 到结尾）"), unit: "s", value: $config.analysisDurationSeconds)
            }
        }
    }

    private var entryRow: some View {
        sliderRow(L("Zone entry criterion", "进入区域标准"), value: $config.entryMinSeconds, range: 0...2, step: 0.1) {
            String(format: L("%.1f s stable", "稳定 %.1f s"), $0)
        }
    }

    // MARK: Building blocks

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                           format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                Text(format(value.wrappedValue))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func numberRow(_ title: String, unit: String, value: Binding<Double>) -> some View {
        NumberField(title: title, value: value, unit: unit, range: 0...1_000_000)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            content()
        }
    }
}
