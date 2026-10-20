// LimbCalibrationEditor.swift — RodentLimb calibration on the desktop. Ported from RodentLimb iOS 1.1.2
// CalibrationView.swift: cylinder rim (bottom view: drag inside to move, drag the edge to resize),
// floor line (side view) or a cm ruler (gait and tail suspension), loupe, auto-fit from tracking;
// and ParamsSheet.swift for the assay parameters. Coordinates are upright-frame pixels.

import SwiftUI

struct LimbCalibrationEditor: View {
    @Binding var setup: LimbTaskSetup
    let image: CGImage?
    let shownTime: Double
    let loadingFrame: Bool
    let duration: Double
    /// Pose of a finished run of this video, if any (keypoints drawn to help placement; auto-fit).
    var track: PoseTrack? = nil
    let onSeek: (Double) -> Void

    @State private var frameTime: Double = 0
    @State private var circle = CircleCal(cx: 960, cy: 540, r: 400)
    @State private var floorY: Double = 900
    @State private var ruler = ScaleCal(x1: 600, y1: 900, x2: 1300, y2: 900, cm: 10)
    @State private var loupe: CGPoint?
    @State private var dragMode: DragMode?
    @State private var dragStart: (CircleCal, ScaleCal, Double)?
    @State private var loaded = false

    private enum DragMode { case move, resize, rulerA, rulerB, floor }

    private var videoSize: CGSize { CGSize(width: max(setup.frameWidth, 1), height: max(setup.frameHeight, 1)) }
    private var mode: LimbTaskSetup.Mode { setup.mode }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                canvas
                    .overlay(alignment: .topTrailing) {
                        if loadingFrame { ProgressView().controlSize(.small).padding(10) }
                    }
                if duration > 0 {
                    CalibrationFrameScrubber(time: $frameTime, duration: max(0.1, duration - 0.05)) { t in
                        setup.frameTime = t
                        onSeek(t)
                    }
                }
                if let from = setup.calibration.copiedFrom, setup.assay != .tailSuspension {
                    Label(String(format: L("Calibration reused from %@ — check it.", "标定沿用自 %@，请检查。"), from),
                          systemImage: "doc.on.doc")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.bottom, 12)
            }
            .frame(minWidth: 380, maxWidth: .infinity, alignment: .topLeading)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if setup.assay == .cylinder {
                        SetupCard(L("Camera", "拍摄视角"), symbol: "camera") {
                            Picker(L("Camera", "拍摄视角"), selection: Binding(get: { setup.params.cylinder.view }, set: { changeView($0) })) {
                                ForEach(CylinderViewMode.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }
                    }
                    controls
                    SetupCard(L("Parameters", "参数"), symbol: "slider.horizontal.3",
                              subtitle: L("Use the same parameters for every animal in a study. Values are written to each session's methods export.",
                                          "同一研究中所有动物应使用相同参数。参数值会写入每条记录导出的方法描述中。")) {
                        LimbParamsEditor(assay: setup.assay, params: $setup.params)
                        Button(L("Reset to defaults", "恢复默认值")) {
                            var d = AssayParams.defaults(for: setup.assay)
                            d.cylinder.lesion = setup.params.cylinder.lesion
                            d.cylinder.view = setup.params.cylinder.view
                            setup.params = d
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(width: 340)
        }
        .onAppear(perform: loadState)
        .onChange(of: setup.frameWidth) { _, _ in loadState() }
    }

    private var instruction: String {
        switch mode {
        case .circle:
            return L("Drag inside the circle to move it, drag its edge to resize. Match the inner rim of the cylinder floor.",
                     "在圆内拖动可移动，拖动圆边可调整大小。使其与圆筒底面内缘重合。")
        case .floor:
            return L("Drag the dashed line onto the cylinder floor.", "将虚线拖到圆筒底面位置。")
        case .ruler:
            return L("Drag both ends onto marks of a known distance (e.g. a ruler or the walkway width), then enter that distance.",
                     "将两端拖到已知距离的标记上（如标尺或步道宽度），然后输入该距离。")
        }
    }

    // MARK: State

    private func loadState() {
        let w = videoSize.width, h = videoSize.height
        circle = setup.calibration.circle ?? LimbTaskSetup.defaultCircle(w: w, h: h)
        floorY = setup.calibration.floorY ?? LimbTaskSetup.defaultFloor(h: h)
        ruler = setup.calibration.scale ?? LimbTaskSetup.defaultRuler(w: w, h: h)
        if !loaded { frameTime = setup.frameTime }
        loaded = true
    }

    /// Switching the cylinder camera changes what must be calibrated (RodentLimb Session.isCalibrated).
    private func changeView(_ view: CylinderViewMode) {
        guard view != setup.params.cylinder.view else { return }
        setup.params.cylinder.view = view
        if view == .bottom && setup.calibration.circle == nil { setup.calibration.circle = circle }
        if view == .side && setup.calibration.floorY == nil { setup.calibration.floorY = floorY }
    }

    private func commitDrag() {
        setup.calibration.copiedFrom = nil
        switch mode {
        case .circle: setup.calibration.circle = circle
        case .floor: setup.calibration.floorY = floorY
        case .ruler: setup.calibration.scale = ruler.pxPerCm != nil ? ruler : nil
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let rect = calibrationFitRect(videoSize, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                Canvas { ctx, _ in drawOverlay(ctx, rect: rect) }
                    .allowsHitTesting(false)
                if let loupe {
                    let s = rect.width / max(1, videoSize.width)
                    let p = CGPoint(x: rect.minX + loupe.x * s, y: rect.minY + loupe.y * s)
                    CalibrationLoupe(image: image, imageRect: rect, point: p, color: .yellow)
                        .position(CalibrationLoupe.center(for: p, in: geo.size))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(drag(rect: rect))
        }
        .aspectRatio(videoSize.width / max(1, videoSize.height), contentMode: .fit)
        .frame(minHeight: 260, maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(L("Calibration frame", "标定画面"))
    }

    private func drawOverlay(_ ctx: GraphicsContext, rect: CGRect) {
        let s = rect.width / max(1, videoSize.width)
        func v(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }

        // Pose of this frame, to help placement (track pixels rescaled to the calibration frame).
        if let t = track, let i = t.frameIndex(atPlayerTime: shownTime) {
            let kx = Double(videoSize.width) / Double(max(t.width, 1)), ky = Double(videoSize.height) / Double(max(t.height, 1))
            for k in Kp.allCases {
                guard let p = t.point(k, i, threshold: 0.3) else { continue }
                let c = v(Double(p.x) * kx, Double(p.y) * ky)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(.mint))
            }
        }

        let accent = Color.yellow
        switch mode {
        case .circle:
            let c = v(circle.cx, circle.cy), r = circle.r * s
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(accent), lineWidth: 2.5)
            let ri = r * (1 - setup.params.cylinder.wallMargin)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - ri, y: c.y - ri, width: 2 * ri, height: 2 * ri)), with: .color(accent.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(accent))
            let h = CGPoint(x: c.x + r, y: c.y)
            ctx.fill(Path(ellipseIn: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)), with: .color(accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: h.x - 11, y: h.y - 11, width: 22, height: 22)), with: .color(.black.opacity(0.5)), lineWidth: 1)
        case .floor:
            let y = rect.minY + floorY * s
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
            ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - 11, y: y - 11, width: 22, height: 22)), with: .color(accent))
        case .ruler:
            let a = v(ruler.x1, ruler.y1), b = v(ruler.x2, ruler.y2)
            let isSet = setup.calibration.scale != nil
            var p = Path()
            p.move(to: a)
            p.addLine(to: b)
            ctx.stroke(p, with: .color(isSet ? accent : accent.opacity(0.55)), style: StrokeStyle(lineWidth: 2.5, dash: isSet ? [] : [6, 4]))
            for q in [a, b] {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 11, y: q.y - 11, width: 22, height: 22)), with: .color(accent.opacity(0.35)))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 11, y: q.y - 11, width: 22, height: 22)), with: .color(accent), lineWidth: 2)
                var cross = Path()
                cross.move(to: CGPoint(x: q.x - 6, y: q.y)); cross.addLine(to: CGPoint(x: q.x + 6, y: q.y))
                cross.move(to: CGPoint(x: q.x, y: q.y - 6)); cross.addLine(to: CGPoint(x: q.x, y: q.y + 6))
                ctx.stroke(cross, with: .color(.black), lineWidth: 1)
            }
        }
    }

    private func drag(rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let s = rect.width / max(1, videoSize.width)
                func toVideo(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - rect.minX) / s, y: (p.y - rect.minY) / s) }
                let start = toVideo(g.startLocation), now = toVideo(g.location)
                if dragMode == nil {
                    dragStart = (circle, ruler, floorY)
                    let touchSlop = 30 / s
                    switch mode {
                    case .circle:
                        let d = hypot(start.x - circle.cx, start.y - circle.cy)
                        dragMode = abs(d - circle.r) < touchSlop ? .resize : .move
                    case .floor:
                        dragMode = .floor
                    case .ruler:
                        let da = hypot(start.x - ruler.x1, start.y - ruler.y1), db = hypot(start.x - ruler.x2, start.y - ruler.y2)
                        dragMode = da <= db ? .rulerA : .rulerB
                    }
                }
                guard let ds = dragStart else { return }
                let (c0, r0, f0) = ds
                let dx = now.x - start.x, dy = now.y - start.y
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    switch dragMode {
                    case .move:
                        circle.cx = c0.cx + dx; circle.cy = c0.cy + dy
                        loupe = nil
                    case .resize:
                        circle.r = max(20, hypot(now.x - circle.cx, now.y - circle.cy))
                        loupe = now
                    case .floor:
                        floorY = min(max(0, f0 + dy), videoSize.height)
                        loupe = CGPoint(x: now.x, y: floorY)
                    case .rulerA:
                        ruler.x1 = r0.x1 + dx; ruler.y1 = r0.y1 + dy
                        loupe = CGPoint(x: ruler.x1, y: ruler.y1)
                    case .rulerB:
                        ruler.x2 = r0.x2 + dx; ruler.y2 = r0.y2 + dy
                        loupe = CGPoint(x: ruler.x2, y: ruler.y2)
                    case .none:
                        break
                    }
                }
            }
            .onEnded { _ in
                if dragMode != nil { commitDrag() }
                dragMode = nil
                dragStart = nil
                loupe = nil
            }
    }

    // MARK: Controls (RodentLimb CalibrationView.controls)

    @ViewBuilder
    private var controls: some View {
        switch mode {
        case .circle:
            SetupCard(L("Cylinder rim", "圆筒边缘"), symbol: "circle.dashed") {
                InfoRow(key: L("Center", "圆心"), value: String(format: "%.0f, %.0f px", circle.cx, circle.cy))
                InfoRow(key: L("Radius", "半径"), value: String(format: "%.0f px", circle.r))
                if track != nil {
                    Button { autoCircle() } label: { Label(L("Auto-fit from tracking", "根据追踪自动拟合"), systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                }
            }
        case .floor:
            SetupCard(L("Floor line", "地面线"), symbol: "line.horizontal.3") {
                InfoRow(key: L("Floor line", "地面线"), value: String(format: "y = %.0f px", floorY))
                if track != nil {
                    Button { autoFloor() } label: { Label(L("Estimate from hind paws", "根据后爪位置估计"), systemImage: "wand.and.stars") }
                        .buttonStyle(.bordered)
                }
            }
        case .ruler:
            SetupCard(L("Scale", "比例"), symbol: "ruler",
                      subtitle: setup.calibration.scale == nil
                        ? L("Not set — distances are reported in body lengths.", "未设置——距离以体长为单位。") : nil) {
                NumberField(title: L("Known distance", "已知距离"),
                            value: Binding(get: { ruler.cm }, set: { ruler.cm = $0; commitDrag() }),
                            unit: "cm", range: 0.1...1000)
                InfoRow(key: L("Length on screen", "画面长度"), value: String(format: "%.0f px", ruler.pixels))
                InfoRow(key: L("Scale", "比例"), value: setup.calibration.scale?.pxPerCm.map { String(format: "%.2f px/cm", $0) } ?? "—")
                if setup.calibration.scale != nil {
                    Button(L("Remove scale (use body lengths)", "移除标尺（使用体长单位）"), role: .destructive) {
                        setup.calibration.scale = nil
                    }
                }
            }
        }
    }

    // MARK: Auto-fit (RodentLimb CalibrationView)

    private func percentile(_ v: [Double], _ q: Double) -> Double? {
        let s = v.sorted()
        guard !s.isEmpty else { return nil }
        return s[min(s.count - 1, max(0, Int(Double(s.count - 1) * q)))]
    }

    private func autoCircle() {
        guard let t = track else { return }
        let kx = Double(videoSize.width) / Double(max(t.width, 1)), ky = Double(videoSize.height) / Double(max(t.height, 1))
        var xs: [Double] = [], ys: [Double] = []
        for k in Kp.allCases {
            for i in stride(from: 0, to: t.frameCount, by: 2) where t.c[k.rawValue][i] >= 0.5 && t.x[k.rawValue][i] >= 0 {
                xs.append(Double(t.x[k.rawValue][i]) * kx)
                ys.append(Double(t.y[k.rawValue][i]) * ky)
            }
        }
        guard let x0 = percentile(xs, 0.005), let x1 = percentile(xs, 0.995),
              let y0 = percentile(ys, 0.005), let y1 = percentile(ys, 0.995), x1 > x0, y1 > y0 else { return }
        circle = CircleCal(cx: (x0 + x1) / 2, cy: (y0 + y1) / 2, r: max(x1 - x0, y1 - y0) / 2 * 1.02)
        commitDrag()
    }

    private func autoFloor() {
        guard let t = track else { return }
        let ky = Double(videoSize.height) / Double(max(t.height, 1))
        var ys: [Double] = []
        for k in [Kp.lh, .rh] {
            for i in 0..<t.frameCount where t.c[k.rawValue][i] >= 0.5 && t.y[k.rawValue][i] >= 0 {
                ys.append(Double(t.y[k.rawValue][i]) * ky)
            }
        }
        if let y = percentile(ys, 0.95) {
            floorY = y
            commitDrag()
        }
    }
}

// MARK: - Parameters (RodentLimb ParamsSheet)

struct LimbParamsEditor: View {
    let assay: Assay
    @Binding var params: AssayParams

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch assay {
            case .tailSuspension: tstSection
            case .cylinder: cylinderSection
            case .gait: gaitSection
            }
            DisclosureGroup(L("Pose cleaning (advanced)", "姿态预处理（高级）")) {
                VStack(alignment: .leading, spacing: 10) {
                    ParamSlider(title: L("Keypoint confidence", "关键点置信度"), value: $params.common.keypointThreshold, range: 0.05...0.9, step: 0.01,
                                help: L("Keypoints below this are treated as missing.", "低于该值的关键点视为缺失。"))
                    ParamSlider(title: L("Fill gaps up to", "填补缺口上限"), value: $params.common.maxGap, range: 0...1, step: 0.05, unit: "s")
                    ParamSlider(title: L("Position smoothing", "位置平滑"), value: $params.common.smoothing, range: 0...0.5, step: 0.01, unit: "s")
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.callout.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
    }

    private var tstSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("Analysis window", "分析窗口"))
            ParamSlider(title: L("Window start", "窗口起点"), value: $params.tst.windowStart, range: 0...600, step: 10, unit: "s", decimals: 0)
            ParamSlider(title: L("Window end", "窗口终点"), value: $params.tst.windowEnd, range: 30...900, step: 10, unit: "s", decimals: 0,
                        help: L("Standard: score minutes 2–6 of a 6-min test (120–360 s).", "标准做法：6 分钟测试中统计第 2–6 分钟（120–360 秒）。"))
            header(L("Immobility", "不动判定"))
            ParamSlider(title: L("Motion threshold", "运动阈值"), value: $params.tst.motionThreshold, range: 0.05...1.0, step: 0.01, unit: "BL/s",
                        help: L("Below this, the mouse counts as immobile. Raise it if small breathing movements are scored as mobile.",
                                "低于该值视为不动。若呼吸等微动被判为挣扎，可调高。"))
            ParamSlider(title: L("Minimum bout", "最短不动时长"), value: $params.tst.minBout, range: 0.2...5, step: 0.1, unit: "s", decimals: 1)
            ParamSlider(title: L("Motion smoothing", "运动平滑"), value: $params.tst.motionSmoothing, range: 0...1, step: 0.05, unit: "s")
            header(L("Clasping & climbing", "抱握与爬尾"))
            ParamSlider(title: L("Clasping window", "抱握评估时长"), value: $params.tst.claspWindow, range: 3...60, step: 1, unit: "s", decimals: 0,
                        help: L("Seconds from the start of suspension (Guyenet et al. use ~10 s).", "从悬挂开始计算的秒数（Guyenet 等人约 10 秒）。"))
            ParamSlider(title: L("Partial clasp distance", "部分抱握距离"), value: $params.tst.claspPartial, range: 0.05...0.6, step: 0.01, unit: "BL")
            ParamSlider(title: L("Full clasp distance", "完全抱握距离"), value: $params.tst.claspFull, range: 0.02...0.4, step: 0.01, unit: "BL")
            ParamSlider(title: L("Tail-climbing ratio", "爬尾判定比例"), value: $params.tst.climbRatio, range: 0.2...0.9, step: 0.05, unit: "BL",
                        help: L("Nose closer to the tail base than this = climbing.", "鼻尖到尾根距离小于该值视为爬尾。"))
        }
    }

    private var cylinderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("Setup", "设置"))
            Picker(L("Lesioned hemisphere", "损伤半球"), selection: $params.cylinder.lesion) {
                ForEach(LesionSide.allCases) { Text($0.label).tag($0) }
            }
            if params.cylinder.lesion != .none {
                Text(String(format: L("Contralateral (impaired) paw: %@", "对侧（受损）爪：%@"),
                            params.cylinder.lesion == .left ? L("right", "右爪") : L("left", "左爪")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(L("Scoring", "计分方式"), selection: $params.cylinder.scoring) {
                ForEach(CylinderScoring.allCases) { Text($0.label).tag($0) }
            }
            Toggle(L("Swap left/right labels", "交换左右标签"), isOn: $params.cylinder.swapLR)
            Text(L("Swap left/right if the model's L/R labels refer to image sides rather than the animal's body (e.g. mirrored bottom view).",
                   "若模型的左/右指的是画面左右而非动物自身左右（如镜像的仰视画面），请交换。"))
                .font(.caption).foregroundStyle(.secondary)
            header(L("Contact detection", "触壁检测"))
            if params.cylinder.view == .bottom {
                ParamSlider(title: L("Wall zone", "触壁区域"), value: $params.cylinder.wallMargin, range: 0.03...0.4, step: 0.01, unit: "× r",
                            help: L("A paw this close to the rim (fraction of radius) is at the wall.", "爪距边缘在该比例半径内即视为在壁上。"))
            } else {
                ParamSlider(title: L("Paw height", "爪离地高度"), value: $params.cylinder.elevation, range: 0.1...1.0, step: 0.01, unit: "BL")
            }
            ParamSlider(title: L("Still paw speed", "爪静止速度"), value: $params.cylinder.stillSpeed, range: 0.2...3, step: 0.05, unit: "BL/s")
            ParamSlider(title: L("Minimum contact", "最短触壁"), value: $params.cylinder.minContact, range: 0.03...0.6, step: 0.01, unit: "s")
            ParamSlider(title: L("Simultaneous window", "同时判定窗口"), value: $params.cylinder.simultaneity, range: 0.03...0.6, step: 0.01, unit: "s",
                        help: L("Left and right placed within this time = both.", "左右爪在此时间内先后触壁 = 双爪。"))
            ParamSlider(title: L("Rear gap", "竖立间隔"), value: $params.cylinder.rearGap, range: 0.1...2, step: 0.05, unit: "s")
            header(L("Limits", "上限"))
            ParamSlider(title: L("Score first", "仅统计前"), value: $params.cylinder.timeLimit, range: 0...900, step: 30, unit: "s", decimals: 0,
                        help: L("0 = whole video.", "0 = 整段视频。"))
            Stepper(value: $params.cylinder.contactLimit, in: 0...100) {
                HStack {
                    Text(L("Contact limit", "触壁次数上限"))
                    Spacer()
                    Text(params.cylinder.contactLimit == 0 ? L("None", "不限") : "\(params.cylinder.contactLimit)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text(L("Some protocols score the first 20 contacts or the first 3–5 minutes.", "部分方案仅统计前 20 次触壁或前 3–5 分钟。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var gaitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(L("Stance / swing", "支撑相 / 摆动相"))
            ParamSlider(title: L("Stance speed ratio", "支撑相速度比"), value: $params.gait.stanceRatio, range: 0.1...1.2, step: 0.05, unit: "× body",
                        help: L("Paw slower than this fraction of body speed = stance.", "爪速低于身体速度的该比例 = 支撑相。"))
            ParamSlider(title: L("Stance speed floor", "支撑相速度下限"), value: $params.gait.stanceFloor, range: 0.1...3, step: 0.05, unit: "BL/s")
            ParamSlider(title: L("Minimum phase", "最短相位"), value: $params.gait.minPhase, range: 0...0.15, step: 0.005, unit: "s", decimals: 3)
            Toggle(L("Swap left/right labels", "交换左右标签"), isOn: $params.gait.swapLR)
            header(L("Which strides count", "步幅筛选"))
            ParamSlider(title: L("Minimum walking speed", "最低行走速度"), value: $params.gait.minBodySpeed, range: 0.2...5, step: 0.1, unit: "BL/s", decimals: 1,
                        help: L("Strides are analyzed only while the mouse walks at least this fast.", "只分析行走速度不低于该值时的步幅。"))
            ParamSlider(title: L("Maximum turning rate", "最大转向角速度"), value: $params.gait.maxTurnRate, range: 5...120, step: 5, unit: "°/s", decimals: 0,
                        help: L("Strides taken while turning faster than this are excluded (Sheppard et al. 2022 used ±20 °/s).",
                                "转向快于该值时的步幅会被排除（Sheppard 等 2022 使用 ±20 °/s）。"))
            Toggle(L("Drop first and last stride of each run", "去掉每段行走的首尾步幅"), isOn: $params.gait.trimRunEnds)
            ParamSlider(title: L("Maximum stride", "最长步幅时长"), value: $params.gait.maxStride, range: 0.2...2, step: 0.05, unit: "s")
            Text(L("Acceleration at the start and end of a run changes stride timing, so those strides are dropped by default.",
                   "每段行走开始和结束时的加减速会改变步态时序，因此默认排除。"))
                .font(.caption).foregroundStyle(.secondary)
            header(L("Speed matching", "速度匹配"))
            ParamSlider(title: L("Reference speed", "参考速度"), value: $params.gait.referenceSpeed, range: 0.5...5, step: 0.1, unit: "BL/s", decimals: 1,
                        help: L("Speed-matched values are read off each animal's stride-vs-speed fit at this speed. Use the same value for every animal in a study.",
                                "速度匹配值取自每只动物“步幅指标—速度”拟合线在该速度处的数值。同一研究中所有动物请使用相同的值。"))
        }
    }
}
