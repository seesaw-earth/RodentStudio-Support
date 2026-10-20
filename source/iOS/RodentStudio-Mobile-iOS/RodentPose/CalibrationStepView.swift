// CalibrationStepView.swift — step 2: arena calibration with draggable handles, zone preview,
// paradigm parameters and a live preview of the result (no re-inference needed).

import SwiftUI

struct CalibrationStepView: View {
    @ObservedObject var flow: SessionFlowModel
    @State private var frameTime: Double = 0
    @State private var showTrajectory = true
    @State private var confirmReset = false

    private var s: Session { flow.session }
    private var cal: ArenaCalibration { flow.session.calibration }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if s.paradigm.arenaKinds.count > 1 {
                    Picker(L10n.tr("场地类型"), selection: Binding(get: { cal.kind }, set: { flow.changeArena($0) })) {
                        ForEach(s.paradigm.arenaKinds) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                canvasCard
                if flow.hasPose { livePreview }
                if cal.kind != .none { dimensionsCard }
                Card {
                    CardHeader(title: L10n.tr("范式参数"), symbol: s.paradigm.symbol) {
                        InfoButton(title: L10n.tr("范式参数")) { ParamsGuide(paradigm: s.paradigm) }
                    }
                    ParamsEditor(paradigm: s.paradigm, phase: s.phase, params: $flow.session.params, hasCue: cal.markers["cue"] != nil)
                }
                Card {
                    CardHeader(title: L10n.tr("分析时间段与预处理"), symbol: "slider.horizontal.3") {
                        InfoButton(title: L10n.tr("分析时间段与预处理")) { CommonParamsGuide(paradigm: s.paradigm) }
                    }
                    CommonParamsEditor(params: $flow.session.params, duration: s.video.duration, paradigm: s.paradigm)
                    Button {
                        flow.resetParams()
                    } label: {
                        Label(L10n.tr("恢复默认参数"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .screenContent()
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { frameTime = s.calibrationTime }
        .confirmationDialog(L10n.tr("把手柄恢复到默认位置？"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L10n.tr("恢复默认位置"), role: .destructive) { flow.resetCalibration() }
        }
    }

    // MARK: Canvas

    private var hint: String {
        switch cal.kind {
        case .none: return L10n.tr("不标定时，坐标、距离和速度以像素为单位。")
        case .rectangle: return s.paradigm == .threeChamber
            ? L10n.tr("黄色 1–4 对齐场地内壁四角；紫色 L/R 分别拖动中箱左右分隔线；青色 L/R 移动杯子。")
            : L10n.tr("拖动黄色手柄 1–4 对齐场地内壁四角（左上、右上、右下、左下）。")
        case .circle: return L10n.tr("C 对准圆心（拖动整体移动），R 拖到场地内缘。")
        case .plusMaze: return L10n.tr("C 对准中央，N / E / S / W 拖到四个臂的末端；青色为开放臂。")
        case .yMaze: return L10n.tr("J 对准三臂交汇中心，A / B / C 拖到三个臂的末端。")
        case .tMaze: return L10n.tr("J 对准选择点，S 为起始臂末端，L / R 为左右臂末端。")
        }
    }

    /// Recognized path (cleaned and smoothed, split at gaps) to check the calibration against
    /// where the animal actually walked.
    private var trajectory: [[NPoint]] {
        showTrajectory ? flow.trailOverview : []
    }

    private var canvasCard: some View {
        Card(padding: 12) {
            CalibrationCanvas(image: flow.frame, frameSize: flow.frameSize, session: $flow.session,
                              zones: flow.zones, mapping: flow.mapping, trajectory: trajectory)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if flow.loadingFrame { ProgressView().padding(10) }
                }
            HStack(alignment: .center, spacing: 8) {
                Group {
                    if cal.kind != .none {
                        handleLegend
                    } else {
                        Text(L10n.tr("不标定（像素）")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                InfoButton(title: L10n.tr("如何标定")) {
                    InfoParagraph(hint)
                    InfoParagraph(L10n.tr("精确对准"), L10n.tr("拖动时对侧上角会出现放大镜；VoiceOver 用户可在操作菜单中逐步微调手柄。"))
                    if flow.hasPose {
                        InfoParagraph(L10n.tr("叠加已识别轨迹"), L10n.tr("橙色线为已识别的身体中心轨迹（去除跳点并平滑，仅用于显示），用来检查标定范围是否与动物的活动范围吻合。"))
                        InfoParagraph(L10n.tr("实时预览"), L10n.tr("移动手柄或修改参数，结果会立即重新计算。"))
                    }
                }
            }
            if s.video.duration > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr("画面时间")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.clock(frameTime)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $frameTime, in: 0...max(0.1, s.video.duration), onEditingChanged: { editing in
                        if !editing { Task { await flow.loadFrame(at: frameTime) } }
                    })
                    .disabled(flow.videoURL == nil)
                    .accessibilityLabel(L10n.tr("画面时间"))
                    .accessibilityValue(Fmt.clock(frameTime))
                }
            }
            HStack {
                if flow.hasPose {
                    Toggle(isOn: $showTrajectory) {
                        Text(L10n.tr("叠加已识别轨迹")).font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .fixedSize()
                }
                Spacer()
                Button {
                    confirmReset = true
                } label: {
                    Label(L10n.tr("重置手柄"), systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
            }
        }
    }

    /// What each handle color means, drawn with the same ring as on the canvas.
    private var handleLegend: some View {
        WrapLayout(spacing: 12) {
            HandleLegendItem(color: .yellow, title: L10n.tr("场地标定点"))
            if s.paradigm == .threeChamber && cal.kind == .rectangle {
                HandleLegendItem(color: .purple, title: L10n.tr("中箱分隔线"))
            }
            if cal.kind == .plusMaze {
                HandleLegendItem(color: .cyan, title: L10n.tr("开放臂"))
            }
            ForEach(s.paradigm.markers) { m in
                HandleLegendItem(color: .cyan, title: "\(m.label) = \(m.title)")
            }
        }
    }

    // MARK: Live preview

    private var livePreview: some View {
        Card(padding: 12) {
            HStack {
                Label(L10n.tr("实时预览"), systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if flow.isAnalyzing { ProgressView().controlSize(.small) }
            }
            if let r = flow.report {
                let shown = Array(([r.primary].compactMap { $0 } + r.metrics.filter { $0.key != r.primary?.key }).prefix(4))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(shown) { m in MetricTile(metric: m) }
                }
            }
        }
    }

    // MARK: Dimensions

    private var dimensionsCard: some View {
        Card {
            CardHeader(L10n.tr("场地尺寸"), symbol: "ruler")
            switch cal.kind {
            case .rectangle:
                NumberField(title: L10n.tr("宽（1 → 2）"), value: $flow.session.calibration.widthCM, unit: "cm", range: 1...500)
                NumberField(title: L10n.tr("高（2 → 3）"), value: $flow.session.calibration.heightCM, unit: "cm", range: 1...500)
            case .circle:
                NumberField(title: L10n.tr("直径"), value: $flow.session.calibration.diameterCM, unit: "cm", range: 1...500)
            case .plusMaze, .yMaze, .tMaze:
                NumberField(title: L10n.tr("臂长（不含中央区）"), value: $flow.session.calibration.armLengthCM, unit: "cm", range: 1...300)
                NumberField(title: L10n.tr("臂宽"), value: $flow.session.calibration.armWidthCM, unit: "cm", range: 1...50)
            case .none:
                EmptyView()
            }
            let ppu = flow.mapping.pxPerUnit
            if flow.mapping.isMetric && ppu.isFinite {
                Text(String(format: L10n.tr("比例约 %.1f 像素 / cm"), ppu))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Canvas with handles

struct CalibrationCanvas: View {
    let image: CGImage?
    let frameSize: V2
    @Binding var session: Session
    let zones: [Zone]
    let mapping: ArenaMapping
    var trajectory: [[NPoint]] = []

    private struct Handle: Identifiable {
        let id: String
        let label: String
        let point: NPoint
        let color: Color
    }

    // Keep every gesture update local to this lightweight canvas. Only one Session
    // write happens at the end, so expensive analysis / persistence stays off the
    // critical touch path and the screen tracks the finger at display refresh rate.
    @State private var draftCalibration: ArenaCalibration?
    @State private var draftParams: AnalysisParams?
    @State private var dragOrigin: [String: NPoint] = [:]
    @State private var activeHandle: String?

    private var calibration: ArenaCalibration { draftCalibration ?? session.calibration }
    private var params: AnalysisParams { draftParams ?? session.params }
    private var paradigm: Paradigm { session.paradigm }
    private var activeMapping: ArenaMapping {
        guard draftCalibration != nil else { return mapping }
        return ArenaMapper.mapping(calibration, frameSize: frameSize)
    }
    private func activeZones(_ m: ArenaMapping) -> [Zone] {
        guard draftCalibration != nil || draftParams != nil else { return zones }
        var preview = session
        preview.calibration = calibration
        preview.params = params
        return ZoneBuilder.zones(preview, mapping: m)
    }

    var body: some View {
        // Computed once per update: the mapping (a homography fit) and the zones are reused by
        // every handle and every drawn point instead of being rebuilt per point.
        let liveMapping = activeMapping
        let liveZones = activeZones(liveMapping)
        let hs = handles(liveMapping)
        return GeometryReader { geo in
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
                    drawOverlay(&ctx, rect, mapping: liveMapping, zones: liveZones)
                }
                .allowsHitTesting(false)
                ForEach(hs) { h in
                    handleView(h)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("calibrationCanvas"))
                                .onChanged { v in
                                    let origin = dragOrigin[h.id] ?? h.point
                                    if dragOrigin[h.id] == nil {
                                        dragOrigin[h.id] = origin
                                        activeHandle = h.id
                                    }
                                    // The gesture coordinates use the fixed canvas rather
                                    // than the moving handle. Preserve the initial finger
                                    // offset to prevent the marker jumping on first touch.
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
                }
                if let id = activeHandle, let h = hs.first(where: { $0.id == id }) {
                    let p = viewPoint(h.point, rect)
                    CalibrationLoupe(image: image, imageRect: rect, point: p, color: h.color)
                        .position(loupeCenter(for: p, in: geo.size))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }
            }
            .coordinateSpace(name: "calibrationCanvas")
            .sensoryFeedback(.impact(weight: .light), trigger: activeHandle) { old, new in old == nil && new != nil }
        }
        .aspectRatio(CGFloat(frameSize.x / max(frameSize.y, 1)), contentMode: .fit)
        .frame(maxHeight: 460)
    }

    // MARK: Handles

    private func handles(_ activeMapping: ArenaMapping) -> [Handle] {
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
            // Each boundary can be positioned independently, with at least 10%
            // central width and 5% of the arena left for either side chamber.
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
        var updated = session
        if let draftCalibration { updated.calibration = draftCalibration }
        if let draftParams { updated.params = draftParams }
        // Commit once after the gesture: this triggers one analysis & save.
        session = updated
        draftCalibration = nil
        draftParams = nil
    }

    /// Loupe goes to the top corner on the other side from the finger (the hand comes from below
    /// the touch point, so the opposite top corner stays visible).
    private func loupeCenter(for p: CGPoint, in size: CGSize) -> CGPoint {
        let r: CGFloat = 58 + 8
        let x = p.x < size.width / 2 ? size.width - r : r
        return CGPoint(x: x, y: min(r, size.height / 2))
    }

    /// Ring with an exact center dot; the label sits outside the ring so the target stays visible.
    private func handleView(_ h: Handle) -> some View {
        let active = activeHandle == h.id
        return ZStack {
            Circle().fill(Color.black.opacity(0.35)).frame(width: 30, height: 30)
            Circle().strokeBorder(h.color, lineWidth: 2.5).frame(width: 24, height: 24)
            Circle().fill(h.color).frame(width: 4, height: 4)
            Text(h.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 16)
                .background(h.color, in: Capsule())
                .offset(x: 17, y: -17)
        }
        .scaleEffect(active ? 1.15 : 1)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("手柄 \(h.label)"))
        .accessibilityHint(L10n.tr("拖动对齐；也可用操作菜单微调位置"))
        .accessibilityAction(named: L10n.tr("向左移动")) { nudge(h, dx: -0.01, dy: 0) }
        .accessibilityAction(named: L10n.tr("向右移动")) { nudge(h, dx: 0.01, dy: 0) }
        .accessibilityAction(named: L10n.tr("向上移动")) { nudge(h, dx: 0, dy: -0.01) }
        .accessibilityAction(named: L10n.tr("向下移动")) { nudge(h, dx: 0, dy: 0.01) }
    }

    /// Small step for VoiceOver / Switch Control users (1 % of the frame).
    private func nudge(_ h: Handle, dx: Double, dy: Double) {
        move(h.id, to: NPoint(h.point.x + dx, h.point.y + dy).clamped())
        commitDrag()
    }

    // MARK: Drawing

    private func viewPoint(_ n: NPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(n.x) * rect.width, y: rect.minY + CGFloat(n.y) * rect.height)
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, _ rect: CGRect, mapping m: ArenaMapping, zones: [Zone]) {
        func arenaToView(_ a: V2) -> CGPoint { viewPoint(m.toNormalized(a), rect) }
        // Zones.
        for z in zones where z.role != .arena {
            let pts = z.outline().map(arenaToView)
            guard pts.count > 2 else { continue }
            var path = Path()
            path.addLines(pts)
            path.closeSubpath()
            let color = Palette.zone(z.role)
            if !z.outlineOnly && z.role != .hole {
                ctx.fill(path, with: .color(color.opacity(0.18)))
            }
            ctx.stroke(path, with: .color(color.opacity(0.95)), style: StrokeStyle(lineWidth: z.outlineOnly ? 1 : 1.5, dash: z.outlineOnly ? [4, 3] : []))
            if z.showsLabel && !z.title.isEmpty {
                let c = arenaToView(z.center)
                let label = Text(z.title).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.9), radius: 1.5))
                    layer.draw(label, at: c)
                }
            }
        }
        // Calibration outline.
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
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(yellow), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
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
        // Recognized trajectory (to check that the calibration matches where the animal walked).
        // One polyline per tracked segment, so gaps are never bridged by straight lines.
        if !trajectory.isEmpty {
            var p = Path()
            for line in trajectory where line.count > 1 {
                p.addLines(line.map { viewPoint($0, rect) })
            }
            ctx.stroke(p, with: .color(Color.orange.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Calibration helpers

struct HandleLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(color, lineWidth: 2.5)
                .background { Circle().fill(Color.black.opacity(0.55)) }
                .frame(width: 14, height: 14)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Magnified view of the frame around the handle being dragged, so the finger does not hide the
/// corner being aligned. GPU-composited (scaled Image), no per-frame redraw of the bitmap.
struct CalibrationLoupe: View {
    let image: CGImage?
    /// Where the video frame is drawn, in canvas coordinates.
    let imageRect: CGRect
    /// Target point, in canvas coordinates.
    let point: CGPoint
    let color: Color
    var diameter: CGFloat = 116
    var zoom: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: diameter / 2 - (point.x - imageRect.minX) * zoom,
                            y: diameter / 2 - (point.y - imageRect.minY) * zoom)
            }
            Canvas { ctx, size in
                let m = CGPoint(x: size.width / 2, y: size.height / 2)
                var cross = Path()
                for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                    cross.move(to: CGPoint(x: m.x + 6 * dx, y: m.y + 6 * dy))
                    cross.addLine(to: CGPoint(x: m.x + 22 * dx, y: m.y + 22 * dy))
                }
                ctx.stroke(cross, with: .color(.black.opacity(0.7)), lineWidth: 3)
                ctx.stroke(cross, with: .color(color), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - 1.5, y: m.y - 1.5, width: 3, height: 3)), with: .color(color))
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}
