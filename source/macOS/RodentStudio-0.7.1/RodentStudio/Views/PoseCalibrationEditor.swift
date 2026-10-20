// PoseCalibrationEditor.swift — RodentPose calibration step on the desktop. Ported from RodentPose iOS
// 1.0 CalibrationStepView.swift (arena picker, canvas with handles, zone preview, legend, dimensions)
// and ParamsEditor.swift (paradigm parameters, analysis window and preprocessing). Desktop changes:
// pointer dragging with a loupe, arrow-key nudging, and a settings column beside the frame.

import SwiftUI

struct PoseCalibrationEditor: View {
    @Binding var setup: PoseTaskSetup
    let phase: String
    let image: CGImage?
    let loadingFrame: Bool
    let duration: Double
    let onSeek: (Double) -> Void

    @State private var frameTime: Double = 0
    @State private var confirmReset = false

    private var cal: ArenaCalibration { setup.calibration }
    private var paradigm: Paradigm { setup.paradigm }
    private var mapping: ArenaMapping { ArenaMapper.mapping(setup.calibration, frameSize: setup.frameSize) }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if paradigm.arenaKinds.count > 1 {
                    Picker(L("Arena type", "场地类型"), selection: Binding(get: { cal.kind }, set: { changeArena($0) })) {
                        ForEach(paradigm.arenaKinds) { k in Text(k.title).tag(k) }
                    }
                    .pickerStyle(.segmented)
                }
                PoseCalibrationCanvas(image: image, phase: phase, setup: $setup)
                    .overlay(alignment: .topTrailing) {
                        if loadingFrame { ProgressView().controlSize(.small).padding(10) }
                    }
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if cal.kind != .none {
                    handleLegend
                    HandleKeyboardHint()
                }
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
                        Label(L("Reset handles", "重置手柄"), systemImage: "arrow.uturn.backward")
                    }
                    .disabled(cal.kind == .none)
                }
            }
            .padding(.bottom, 12)
            }
            .frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if cal.kind != .none { dimensionsCard }
                    SetupCard(L("Assay parameters", "范式参数"), symbol: paradigm.symbol) {
                        PoseParamsEditor(paradigm: paradigm, phase: phase, params: $setup.params,
                                         hasCue: cal.markers["cue"] != nil)
                    }
                    SetupCard(L("Analysis window and preprocessing", "分析时间段与预处理"), symbol: "slider.horizontal.3") {
                        PoseCommonParamsEditor(params: $setup.params, duration: duration, paradigm: paradigm)
                        Button {
                            setup.params = AnalysisParams.defaults(for: paradigm)
                        } label: {
                            Label(L("Reset parameters to defaults", "恢复默认参数"), systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(width: 340)
        }
        .onAppear { frameTime = setup.frameTime }
        .confirmationDialog(L("Reset calibration handles to their default positions?", "把手柄恢复到默认位置？"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Reset positions", "恢复默认位置"), role: .destructive) { resetCalibration() }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }

    // MARK: Actions (RodentPose AppModel.changeArena / resetCalibration)

    private func changeArena(_ kind: ArenaKind) {
        guard kind != setup.calibration.kind else { return }
        setup.calibration = ArenaCalibration.makeDefault(paradigm: paradigm, kind: kind, frameSize: setup.frameSize)
    }

    private func resetCalibration() {
        var updated = setup
        updated.calibration = ArenaCalibration.makeDefault(paradigm: paradigm, kind: setup.calibration.kind, frameSize: setup.frameSize)
        if paradigm == .threeChamber {
            // The movable dividers belong to the calibration controls too.
            updated.params.centerChamberFraction = 1.0 / 3.0
            updated.params.centerChamberOffset = 0
        }
        setup = updated
    }

    // MARK: Texts

    private var hint: String {
        switch cal.kind {
        case .none: return L("Without calibration, coordinates, distance and speed are measured in pixels.", "不标定时，坐标、距离和速度以像素为单位。")
        case .rectangle: return paradigm == .threeChamber
            ? L("Align yellow handles 1–4 to the arena corners. Drag purple L/R handles to set the center-chamber dividers independently; cyan L/R move the cups.", "黄色 1–4 对齐场地内壁四角；紫色 L/R 分别拖动中箱左右分隔线；青色 L/R 移动杯子。")
            : L("Drag yellow handles 1–4 to the arena's inside corners (top-left, top-right, bottom-right, bottom-left).", "拖动黄色手柄 1–4 对齐场地内壁四角（左上、右上、右下、左下）。")
        case .circle: return L("Place C at the circle center (drag to move together) and R on the arena's inner edge.", "C 对准圆心（拖动整体移动），R 拖到场地内缘。")
        case .plusMaze: return L("Place C at the center and N / E / S / W at the arm tips; cyan denotes open arms.", "C 对准中央，N / E / S / W 拖到四个臂的末端；青色为开放臂。")
        case .yMaze: return L("Place J at the three-arm junction and A / B / C at the arm tips.", "J 对准三臂交汇中心，A / B / C 拖到三个臂的末端。")
        case .tMaze: return L("Place J at the choice point, S at the start arm, and L / R at left and right arm tips.", "J 对准选择点，S 为起始臂末端，L / R 为左右臂末端。")
        }
    }

    private var handleLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
            HandleLegendItem(color: .yellow, title: L("Arena calibration points", "场地标定点"))
            if paradigm == .threeChamber && cal.kind == .rectangle {
                HandleLegendItem(color: .purple, title: L("Center-chamber dividers", "中箱分隔线"))
            }
            if cal.kind == .plusMaze {
                HandleLegendItem(color: .cyan, title: L("Open arm", "开放臂"))
            }
            ForEach(paradigm.markers) { m in
                HandleLegendItem(color: .cyan, title: "\(m.label) = \(m.title)")
            }
        }
    }

    private var dimensionsCard: some View {
        SetupCard(L("Arena dimensions", "场地尺寸"), symbol: "ruler") {
            switch cal.kind {
            case .rectangle:
                NumberField(title: L("Width (1 → 2)", "宽（1 → 2）"), value: $setup.calibration.widthCM, unit: "cm", range: 1...500)
                NumberField(title: L("Height (2 → 3)", "高（2 → 3）"), value: $setup.calibration.heightCM, unit: "cm", range: 1...500)
            case .circle:
                NumberField(title: L("Diameter", "直径"), value: $setup.calibration.diameterCM, unit: "cm", range: 1...500)
            case .plusMaze, .yMaze, .tMaze:
                NumberField(title: L("Arm length (excluding center)", "臂长（不含中央区）"), value: $setup.calibration.armLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L("Arm width", "臂宽"), value: $setup.calibration.armWidthCM, unit: "cm", range: 1...50)
            case .none:
                EmptyView()
            }
            let ppu = mapping.pxPerUnit
            if mapping.isMetric && ppu.isFinite {
                Text(String(format: L("Scale ≈ %.1f pixels/cm", "比例约 %.1f 像素 / cm"), ppu))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Canvas with handles (RodentPose CalibrationCanvas)

struct PoseCalibrationCanvas: View {
    let image: CGImage?
    var phase: String = ""
    @Binding var setup: PoseTaskSetup

    private struct Handle: Identifiable {
        let id: String
        let label: String
        let point: NPoint
        let color: Color
    }

    // Every pointer update stays local to this canvas; one write to `setup` happens when the drag ends.
    @State private var draftCalibration: ArenaCalibration?
    @State private var draftParams: AnalysisParams?
    @State private var dragOrigin: [String: NPoint] = [:]
    @State private var activeHandle: String?
    @State private var selectedHandle: String?
    @FocusState private var focused: Bool

    private var frameSize: V2 { setup.frameSize }
    private var calibration: ArenaCalibration { draftCalibration ?? setup.calibration }
    private var params: AnalysisParams { draftParams ?? setup.params }
    private var paradigm: Paradigm { setup.paradigm }
    private var activeMapping: ArenaMapping { ArenaMapper.mapping(calibration, frameSize: frameSize) }
    private var activeZones: [Zone] {
        ZoneBuilder.zones(paradigm: paradigm, phase: phase, calibration: calibration, params: params, mapping: activeMapping)
    }

    var body: some View {
        GeometryReader { geo in
            let rect = calibrationFitRect(CGSize(width: frameSize.x, height: frameSize.y), in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                Canvas { ctx, _ in
                    drawOverlay(&ctx, rect)
                }
                .allowsHitTesting(false)
                ForEach(handles) { h in
                    CalibrationHandleView(label: h.label, color: h.color,
                                          active: activeHandle == h.id, selected: selectedHandle == h.id)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("poseCalibrationCanvas"))
                                .onChanged { v in
                                    let origin = dragOrigin[h.id] ?? h.point
                                    if dragOrigin[h.id] == nil {
                                        dragOrigin[h.id] = origin
                                        activeHandle = h.id
                                        selectedHandle = h.id
                                        focused = true
                                    }
                                    // Keep the initial pointer offset so the marker does not jump on first contact.
                                    let dx = Double((v.location.x - v.startLocation.x) / max(rect.width, 1))
                                    let dy = Double((v.location.y - v.startLocation.y) / max(rect.height, 1))
                                    let point = NPoint(origin.x + dx, origin.y + dy).clamped()
                                    var transaction = Transaction(animation: nil)
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) { move(h.id, to: point) }
                                }
                                .onEnded { _ in
                                    commitDrag()
                                    dragOrigin.removeValue(forKey: h.id)
                                    activeHandle = nil
                                }
                        )
                        .position(viewPoint(h.point, rect))
                        .zIndex(activeHandle == h.id ? 1 : 0)
                        .help(L("Handle \(h.label)", "手柄 \(h.label)"))
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
            .coordinateSpace(name: "poseCalibrationCanvas")
        }
        .aspectRatio(CGFloat(frameSize.x / max(frameSize.y, 1)), contentMode: .fit)
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
        .onChange(of: setup.calibration.kind) { _, _ in selectedHandle = nil }
    }

    // MARK: Handles

    private var handles: [Handle] {
        var hs: [Handle] = []
        let yellow = Color.yellow
        switch calibration.kind {
        case .none:
            break
        case .rectangle:
            for (i, c) in calibration.corners.enumerated() {
                hs.append(Handle(id: "corner\(i)", label: "\(i + 1)", point: c, color: yellow))
            }
        case .circle:
            hs.append(Handle(id: "center", label: "C", point: calibration.circleCenter, color: yellow))
            hs.append(Handle(id: "edge", label: "R", point: calibration.circleEdge, color: yellow))
        case .plusMaze, .yMaze, .tMaze:
            let labels = calibration.kind.mazeLabels
            let open = ZoneBuilder.openArmIndices(params)
            for (i, p) in calibration.mazePoints.enumerated() where i < labels.count {
                let isOpen = calibration.kind == .plusMaze && i > 0 && open.contains(i - 1)
                hs.append(Handle(id: "maze\(i)", label: labels[i], point: p, color: isOpen ? .cyan : yellow))
            }
        }
        if paradigm == .threeChamber && calibration.kind == .rectangle {
            let b = ZoneBuilder.threeChamberBounds(params)
            let e = activeMapping.extent
            for (id, label, x) in [("dividerL", "L", b.left), ("dividerR", "R", b.right)] {
                let point = activeMapping.toNormalized(V2(x * e.x, 0.24 * e.y))
                hs.append(Handle(id: id, label: label, point: point, color: .purple))
            }
        }
        for m in paradigm.markers {
            if let p = calibration.markers[m.key] {
                hs.append(Handle(id: "marker_" + m.key, label: m.label, point: p, color: .cyan))
            }
        }
        return hs
    }

    private func move(_ id: String, to point: NPoint) {
        if id == "dividerL" || id == "dividerR" {
            var p = params
            let bounds = ZoneBuilder.threeChamberBounds(p)
            let e = activeMapping.extent
            guard e.x > 0 else { return }
            let localX = activeMapping.toArena(point).x / e.x
            guard localX.isFinite else { return }
            // Each boundary moves independently, keeping at least 10% for the centre and 5% per side.
            let left = id == "dividerL" ? clamp(localX, max(0.05, bounds.right - 0.80), bounds.right - 0.10) : bounds.left
            let right = id == "dividerR" ? clamp(localX, bounds.left + 0.10, min(0.95, bounds.left + 0.80)) : bounds.right
            p.centerChamberFraction = right - left
            p.centerChamberOffset = (left + right) / 2 - 0.5
            draftParams = p
            return
        }
        var c = calibration
        if id.hasPrefix("corner"), let i = Int(id.dropFirst(6)), i < c.corners.count {
            c.corners[i] = point
        } else if id == "center" {
            let dx = c.circleEdge.x - c.circleCenter.x, dy = c.circleEdge.y - c.circleCenter.y
            c.circleCenter = point
            c.circleEdge = NPoint(point.x + dx, point.y + dy)
        } else if id == "edge" {
            c.circleEdge = point
        } else if id.hasPrefix("maze"), let i = Int(id.dropFirst(4)), i < c.mazePoints.count {
            c.mazePoints[i] = point
        } else if id.hasPrefix("marker_") {
            c.markers[String(id.dropFirst(7))] = point
        }
        draftCalibration = c
    }

    private func commitDrag() {
        guard draftCalibration != nil || draftParams != nil else { return }
        var updated = setup
        if let draftCalibration { updated.calibration = draftCalibration }
        if let draftParams { updated.params = draftParams }
        setup = updated
        draftCalibration = nil
        draftParams = nil
    }

    private func nudge(_ id: String, dx: Double, dy: Double) {
        guard let h = handles.first(where: { $0.id == id }) else { return }
        move(id, to: NPoint(h.point.x + dx, h.point.y + dy).clamped())
        commitDrag()
    }

    // MARK: Drawing

    private func viewPoint(_ n: NPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(n.x) * rect.width, y: rect.minY + CGFloat(n.y) * rect.height)
    }

    private func arenaToView(_ a: V2, _ rect: CGRect) -> CGPoint {
        viewPoint(activeMapping.toNormalized(a), rect)
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, _ rect: CGRect) {
        for z in activeZones where z.role != .arena {
            let pts = z.outline().map { arenaToView($0, rect) }
            guard pts.count > 2 else { continue }
            var path = Path()
            path.addLines(pts)
            path.closeSubpath()
            let color = ZonePalette.color(z.role)
            if !z.outlineOnly && z.role != .hole {
                ctx.fill(path, with: .color(color.opacity(0.18)))
            }
            ctx.stroke(path, with: .color(color.opacity(0.95)),
                       style: StrokeStyle(lineWidth: z.outlineOnly ? 1 : 1.5, dash: z.outlineOnly ? [4, 3] : []))
            if z.showsLabel && !z.title.isEmpty {
                let c = arenaToView(z.center, rect)
                let label = Text(z.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
                    layer.draw(label, at: c)
                }
            }
        }
        let yellow = Color.yellow
        switch calibration.kind {
        case .rectangle:
            var p = Path()
            p.addLines(calibration.corners.map { viewPoint($0, rect) })
            p.closeSubpath()
            ctx.stroke(p, with: .color(yellow), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        case .circle:
            let c = viewPoint(calibration.circleCenter, rect)
            let e = viewPoint(calibration.circleEdge, rect)
            let r = hypot(e.x - c.x, e.y - c.y)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(yellow), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            var radius = Path()
            radius.move(to: c)
            radius.addLine(to: e)
            ctx.stroke(radius, with: .color(yellow.opacity(0.7)), lineWidth: 1.5)
        case .plusMaze, .yMaze, .tMaze:
            let pts = calibration.mazePoints.map { viewPoint($0, rect) }
            if let c = pts.first {
                var p = Path()
                for e in pts.dropFirst() {
                    p.move(to: c)
                    p.addLine(to: e)
                }
                ctx.stroke(p, with: .color(yellow), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5]))
            }
        case .none:
            break
        }
    }
}

// MARK: - Paradigm parameters (RodentPose ParamsEditor)

struct PoseParamsEditor: View {
    let paradigm: Paradigm
    let phase: String
    @Binding var params: AnalysisParams
    var hasCue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch paradigm {
            case .openField: openFieldRows
            case .spatialExploration: spatialExplorationRows
            case .headDirection: headDirectionRows
            case .threeChamber: threeChamberRows
            case .socialInteraction: socialInteractionRows
            case .dyadicSocial: dyadicSocialRows
            case .elevatedPlusMaze: elevatedPlusMazeRows
            case .lightDark: lightDarkRows
            case .novelObject: novelObjectRows
            case .barnesMaze: barnesMazeRows
            case .yMaze: entryRule
            case .tMaze: tMazeRows
            case .fearConditioning: fearConditioningRows
            case .looming: loomingRows
            case .rotation: rotationRows
            case .poseOnly: poseOnlyRows
            }
        }
    }

    @ViewBuilder
    private var openFieldRows: some View {
        PercentSlider(title: L("Center zone size (fraction of side)", "中央区大小（边长比例）"), value: $params.centerFraction, range: 0.2...0.8)
        freezeRows(title: L("Immobility criterion", "静止判定"))
    }

    @ViewBuilder
    private var spatialExplorationRows: some View {
        NumberField(title: L("Occupancy-map bin size", "占据图方格"), value: $params.spatialBin, unit: "cm", range: 0.5...20)
        NumberField(title: L("Minimum dwell time for coverage", "覆盖判定最短停留"), value: $params.coverageMinTime, unit: "s", range: 0...10)
        NumberField(title: L("Movement speed threshold", "运动速度阈值"), value: $params.moveSpeed, unit: "cm/s", range: 0...50)
    }

    @ViewBuilder
    private var headDirectionRows: some View {
        SegmentRow(title: L("0° reference", "0° 参考方向"), selection: $params.hdReference,
                   options: [("image", L("Arena right", "场地右方")), ("cue", L("Cue card Q", "提示卡 Q"))])
        if params.hdReference == "cue" && !hasCue {
            Label(L("Cue-card handle Q not found; arena right will be used.", "没有找到提示卡手柄 Q，将使用场地右方。"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
        SegmentRow(title: L("Direction bin size", "方向分格"), selection: $params.hdBinDeg,
                   options: [(3.0, "3°"), (6.0, "6°"), (10.0, "10°"), (15.0, "15°")])
        NumberField(title: L("Minimum dwell time for coverage", "覆盖判定最短停留"), value: $params.hdMinBinTime, unit: "s", range: 0...30)
    }

    @ViewBuilder
    private var threeChamberRows: some View {
        SegmentRow(title: phase == "Social novelty" ? L("Cup with novel stranger", "新陌生鼠所在杯")
                        : (phase == "Habituation" ? L("Reference cup (index numerator)", "参照杯（指数分子）") : L("Cup with stranger mouse", "陌生鼠所在杯")),
                   selection: $params.stimSide, options: [("L", L("Left cup L", "左杯 L")), ("R", L("Right cup R", "右杯 R"))])
        NumberField(title: L("Cup radius", "杯子半径"), value: $params.cupRadius, unit: "cm", range: 1...20)
        NumberField(title: L("Investigation distance (from cup edge)", "嗅探距离（杯外缘）"), value: $params.exploreMargin, unit: "cm", range: 0...10)
        NumberField(title: L("Head-direction tolerance", "头朝向容差"), value: $params.headTolerance, unit: "°", range: 5...180)
        PercentSlider(title: L("Center-chamber width (fraction of total)", "中箱宽度（占总长）"), value: $params.centerChamberFraction, range: 0.1...0.8)
        Text(L("You can also drag the two center-chamber boundaries (purple L/R handles) independently to adjust their positions and the chamber width.",
               "也可直接拖动视频上的两条中箱边界（紫色 L/R 控制点），分别调整位置和宽度。"))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var socialInteractionRows: some View {
        SegmentRow(title: L("Enclosure wall (image orientation)", "网罩靠哪面墙（画面方向）"), selection: $params.enclosureWall,
                   options: [("top", L("Top", "上")), ("bottom", L("Bottom", "下")), ("left", L("Left", "左")), ("right", L("Right", "右"))])
        NumberField(title: L("Interaction-zone width (along wall)", "互动区宽（沿墙）"), value: $params.izWidth, unit: "cm", range: 1...100)
        NumberField(title: L("Interaction-zone depth (from wall)", "互动区深（离墙）"), value: $params.izDepth, unit: "cm", range: 1...100)
        NumberField(title: L("Enclosure width", "网罩宽"), value: $params.enclosureWidth, unit: "cm", range: 1...50)
        NumberField(title: L("Enclosure depth", "网罩深"), value: $params.enclosureDepth, unit: "cm", range: 1...50)
        NumberField(title: L("Corner-zone side length", "角落区边长"), value: $params.cornerSize, unit: "cm", range: 1...50)
    }

    @ViewBuilder
    private var dyadicSocialRows: some View {
        NumberField(title: L("Nose-to-nose distance", "鼻–鼻距离"), value: $params.noseNoseDist, unit: "cm", range: 0.5...10)
        NumberField(title: L("Nose-to-tail-base (anogenital) distance", "鼻–尾根（肛殖区）距离"), value: $params.anogenitalDist, unit: "cm", range: 0.5...10)
        NumberField(title: L("Nose-to-body distance", "鼻–身体距离"), value: $params.bodySniffDist, unit: "cm", range: 0.5...10)
        NumberField(title: L("Proximity (body center)", "近距离（身体中心）"), value: $params.proximityDist, unit: "cm", range: 1...50)
        DisclosureGroup(L("Following criteria", "跟随判定")) {
            VStack(spacing: 10) {
                NumberField(title: L("Maximum distance", "最大间距"), value: $params.followDist, unit: "cm", range: 1...60)
                NumberField(title: L("Minimum speed", "最低速度"), value: $params.followSpeed, unit: "cm/s", range: 0...50)
                NumberField(title: L("Orientation tolerance", "朝向容差"), value: $params.followAngle, unit: "°", range: 5...90)
                NumberField(title: L("Minimum duration", "最短持续"), value: $params.followMin, unit: "s", range: 0...10)
            }
            .padding(.top, 8)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var elevatedPlusMazeRows: some View {
        SegmentRow(title: L("Open-arm axis", "开放臂方向"), selection: $params.openAxis,
                   options: [("NS", L("N–S (top/bottom)", "N–S（上下）")), ("EW", L("E–W (left/right)", "E–W（左右）"))])
        entryRule
        DisclosureGroup(L("Head dips and stretch-attend posture", "探头与伸展评估姿势")) {
            VStack(spacing: 10) {
                NumberField(title: L("Head-dip reach (past arm edge)", "探头范围（臂边缘外）"), value: $params.headDipReach, unit: "cm", range: 1...20)
                NumberField(title: L("Minimum head-dip duration", "探头最短持续"), value: $params.headDipMin, unit: "s", range: 0...3)
                NumberField(title: L("SAP body elongation factor", "SAP 身体伸长倍数"), value: $params.sapElongation, unit: "×", range: 1.05...2)
                NumberField(title: L("Maximum SAP speed", "SAP 最高速度"), value: $params.sapSpeed, unit: "cm/s", range: 0...30)
                NumberField(title: L("Minimum SAP duration", "SAP 最短持续"), value: $params.sapMin, unit: "s", range: 0...5)
            }
            .padding(.top, 8)
        }
        .font(.callout)
    }

    @ViewBuilder
    private var lightDarkRows: some View {
        SegmentRow(title: L("Light compartment location", "明箱在画面"), selection: $params.lightOnLeft,
                   options: [(true, L("Left side", "左侧")), (false, L("Right side", "右侧"))])
        PercentSlider(title: L("Light-side fraction of chamber length", "明箱占总长"), value: $params.lightFraction, range: 0.2...0.8)
        NumberField(title: L("Minimum head-dip duration", "探头最短持续"), value: $params.pokeMin, unit: "s", range: 0...3)
    }

    @ViewBuilder
    private var novelObjectRows: some View {
        if phase != "Training" {
            SegmentRow(title: L("Novel object", "新物体"), selection: $params.novelObject, options: [("A", "A"), ("B", "B")])
        }
        NumberField(title: L("Object radius", "物体半径"), value: $params.objectRadius, unit: "cm", range: 0.5...20)
        NumberField(title: L("Investigation radius beyond object edge", "探索距离（物体外缘）"), value: $params.exploreMargin, unit: "cm", range: 0...10)
        NumberField(title: L("Head-direction tolerance", "头朝向容差"), value: $params.headTolerance, unit: "°", range: 5...180)
    }

    @ViewBuilder
    private var barnesMazeRows: some View {
        NumberField(title: L("Number of holes", "洞的数量"),
                    value: Binding(get: { Double(params.holeCount) }, set: { params.holeCount = max(4, Int($0.rounded())) }),
                    unit: L("items", "个"), range: 4...60)
        NumberField(title: L("Hole radius", "洞半径"), value: $params.holeRadius, unit: "cm", range: 0.5...10)
        NumberField(title: L("Hole investigation margin", "探洞判定余量"), value: $params.pokeMargin, unit: "cm", range: 0...5)
        NumberField(title: L("Minimum hole-probe duration", "探洞最短持续"), value: $params.holePokeMin, unit: "s", range: 0...2)
    }

    @ViewBuilder
    private var tMazeRows: some View {
        NumberField(title: L("Choice-point radius (× arm width)", "选择点半径（× 臂宽）"), value: $params.choiceRadiusFactor, unit: "×", range: 0.5...3)
        NumberField(title: L("VTE zIdPhi threshold", "VTE 阈值 zIdPhi"), value: $params.vteZ, unit: "", range: -2...5)
    }

    @ViewBuilder
    private var fearConditioningRows: some View {
        OnsetsEditor(title: L("CS onset times", "CS 开始时间"), onsets: $params.csOnsets,
                     hint: L("Seconds since video start, comma-separated, e.g., 180, 260, 340", "相对于视频开头的秒数，逗号分隔，如 180, 260, 340"))
        NumberField(title: L("CS duration", "CS 时长"), value: $params.csDuration, unit: "s", range: 1...600)
        freezeRows(title: L("Freezing detection", "僵直判定"))
        SegmentRow(title: L("Plot bin size", "曲线分段"), selection: $params.timeBin,
                   options: [(20.0, "20 s"), (30.0, "30 s"), (60.0, "1 min"), (120.0, "2 min")])
    }

    @ViewBuilder
    private var loomingRows: some View {
        OnsetsEditor(title: L("Stimulus onset times", "刺激出现时间"), onsets: $params.stimOnsets,
                     hint: L("Seconds since video start, separated by commas", "相对于视频开头的秒数，逗号分隔"))
        NumberField(title: L("Shelter radius", "巢穴半径"), value: $params.shelterRadius, unit: "cm", range: 1...40)
        DisclosureGroup(L("Response detection", "反应判定")) {
            VStack(spacing: 10) {
                NumberField(title: L("Speed multiplier (× baseline)", "速度倍数（× 基线）"), value: $params.flightFactor, unit: "×", range: 1...20)
                NumberField(title: L("Minimum escape speed", "最低逃跑速度"), value: $params.flightMinSpeed, unit: "cm/s", range: 1...100)
                NumberField(title: L("Response window", "反应窗口"), value: $params.escapeWindow, unit: "s", range: 1...60)
                NumberField(title: L("Baseline window", "基线窗口"), value: $params.baselineWindow, unit: "s", range: 1...60)
            }
            .padding(.top, 8)
        }
        .font(.callout)
        freezeRows(title: L("Freezing detection", "僵直判定"))
    }

    @ViewBuilder
    private var rotationRows: some View {
        SegmentRow(title: L("Lesion side", "损伤侧"), selection: $params.lesionSide,
                   options: [("none", L("Not set", "未设置")), ("left", L("Left side", "左侧")), ("right", L("Right side", "右侧"))])
        Toggle(L("Recorded from below (mirrored image)", "从下方拍摄（画面左右镜像）"), isOn: $params.cameraBelow).font(.callout)
        SegmentRow(title: L("Time bins", "分段"), selection: $params.rotationBin,
                   options: [(60.0, "1 min"), (300.0, "5 min"), (600.0, "10 min")])
    }

    @ViewBuilder
    private var poseOnlyRows: some View {
        Text(L("Pose-only export has no assay-specific parameters.", "仅导出姿态，没有范式参数。")).font(.callout).foregroundStyle(.secondary)
    }

    private var entryRule: some View {
        SegmentRow(title: L("Arm-entry criterion", "进入臂的判定"), selection: $params.entryRule,
                   options: [("full", L("Body center + tail base", "身体+尾根")), ("body", L("Body center", "身体中心")), ("nose", L("Nose", "鼻尖"))])
    }

    @ViewBuilder
    private func freezeRows(title: String) -> some View {
        Text(title).font(.callout.weight(.semibold)).padding(.top, 4)
        NumberField(title: L("Movement threshold", "运动阈值"), value: $params.freezeSpeed, unit: "cm/s",
                    help: L("Core keypoint displacement below this speed in a 0.5 s window counts as immobility.", "核心关键点 0.5 s 窗口位移速度低于此值视为不动"),
                    range: 0.1...10)
        NumberField(title: L("Minimum duration", "最短持续"), value: $params.freezeMin, unit: "s", range: 0...10)
    }
}

// MARK: - Common settings (RodentPose CommonParamsEditor)

struct PoseCommonParamsEditor: View {
    @Binding var params: AnalysisParams
    let duration: Double
    let paradigm: Paradigm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NumberField(title: L("Analysis start", "分析起点"), value: $params.windowStart, unit: "s", range: 0...max(0, duration))
            NumberField(title: L("Analysis duration (0 = to end)", "分析时长（0 = 到结尾）"), value: $params.windowLength, unit: "s",
                        help: windowHelp, range: 0...max(0, duration))
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("Keypoint confidence threshold", "关键点置信度阈值")).font(.callout)
                    Spacer()
                    Text(String(format: "%.2f", params.kpConf)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $params.kpConf, in: 0.1...0.9, step: 0.05)
            }
            NumberField(title: L("Smoothing window", "平滑窗口"), value: $params.smoothing, unit: "s",
                        help: L("Moving average; 0 = no smoothing", "滑动平均；0 = 不平滑"), range: 0...1)
            NumberField(title: L("Maximum interpolation gap", "最长插值缺口"), value: $params.maxGap, unit: "s", range: 0...5)
            if paradigm != .fearConditioning && paradigm != .rotation {
                SegmentRow(title: L("Time binning", "时间分段"), selection: $params.timeBin,
                           options: [(30.0, "30 s"), (60.0, "1 min"), (120.0, "2 min"), (300.0, "5 min")])
            }
        }
    }

    private var windowHelp: String {
        switch paradigm {
        case .socialInteraction: return L("Golden 2011 standard: 150 s", "Golden 2011 标准为 150 s")
        case .elevatedPlusMaze: return L("Typical: 5 min (300 s)", "常用 5 min（300 s）")
        case .yMaze: return L("Typical: 8 min (480 s)", "常用 8 min（480 s）")
        default: return L("Analyze only this period; saved detections are unchanged.", "只统计这段时间；不影响已识别的数据")
        }
    }
}
