// AnalysisCore.swift — shared analysis context, helpers and the dispatcher.

import Foundation

struct AnalysisContext {
    let session: Session
    let fs: FeatureSet
    let zones: [Zone]
    /// Metrics of a paired session (e.g. the "no target" run of the social interaction test).
    let companion: [String: Double]

    var tb: TimeBase { fs.tb }
    var p: AnalysisParams { session.params }
    var a0: AnimalFeatures { fs.animals[0] }
    var u: String { fs.unit }
    var n: Int { tb.count }
    var extent: V2 { fs.mapping.extent }

    func zone(_ id: String) -> Zone? { zones.first { $0.id == id } }

    // MARK: Masks

    /// Frames where keypoint `k` of `animal` satisfies `test`. Missing positions keep the
    /// previous state (`hold`), so a short tracking gap does not create a fake exit / entry.
    func mask(_ k: KP, animal: Int = 0, hold: Bool = true, _ test: (V2) -> Bool) -> [Bool] {
        let f = fs.animals[animal]
        var m = [Bool](repeating: false, count: n)
        var last = false
        for i in 0..<n {
            if let q = f.pos(k, i) {
                last = test(q)
                m[i] = last
            } else {
                m[i] = hold ? last : false
            }
        }
        return m
    }

    func mask(_ k: KP, in zone: Zone, animal: Int = 0, hold: Bool = true) -> [Bool] {
        mask(k, animal: animal, hold: hold) { zone.contains($0) }
    }

    /// Frames where a series is finite and satisfies `test`.
    func mask(_ series: [Double], _ test: (Double) -> Bool) -> [Bool] {
        series.map { $0.isFinite && test($0) }
    }

    static func and(_ a: [Bool], _ b: [Bool]) -> [Bool] { zip(a, b).map { $0 && $1 } }
    static func or(_ a: [Bool], _ b: [Bool]) -> [Bool] { zip(a, b).map { $0 || $1 } }
    static func not(_ a: [Bool]) -> [Bool] { a.map { !$0 } }

    /// Frames with valid body position inside the window.
    func trackedMask(animal: Int = 0) -> [Bool] {
        (0..<n).map { fs.animals[animal].pos(.bodyCenter, $0) != nil }
    }

    /// Immobility / freezing: motion index below threshold, sustained for the minimum duration.
    func freezingMask(animal: Int = 0) -> [Bool] {
        let raw = mask(fs.animals[animal].motion) { $0 < p.freezeSpeed }
        return Bouts.sustained(raw, tb, minDuration: p.freezeMin)
    }

    func movingMask(animal: Int = 0) -> [Bool] {
        mask(fs.animals[animal].speed) { $0 > p.moveSpeed }
    }

    // MARK: Quantities

    /// Path length of a keypoint inside the window (optionally only where `onlyWhere` is true).
    func distance(_ k: KP = .bodyCenter, animal: Int = 0, onlyWhere: [Bool]? = nil) -> Double {
        let f = fs.animals[animal]
        var d = 0.0
        guard n > 1 else { return 0 }
        for i in 1..<n where tb.inWindow[i] && tb.inWindow[i - 1] {
            if let w = onlyWhere, !w[i] { continue }
            guard tb.t[i] - tb.t[i - 1] <= 0.5, let a = f.pos(k, i - 1), let b = f.pos(k, i) else { continue }
            d += a.distance(to: b)
        }
        return d
    }

    /// Mean of a series over window frames where `onlyWhere` (if any) is true.
    func mean(_ s: [Double], onlyWhere: [Bool]? = nil) -> Double? {
        var sum = 0.0, c = 0.0
        for i in 0..<min(n, s.count) where tb.inWindow[i] && s[i].isFinite {
            if let w = onlyWhere, !w[i] { continue }
            sum += s[i]; c += 1
        }
        return c > 0 ? sum / c : nil
    }

    func values(_ s: [Double], onlyWhere: [Bool]? = nil) -> [Double] {
        var out: [Double] = []
        for i in 0..<min(n, s.count) where tb.inWindow[i] && s[i].isFinite {
            if let w = onlyWhere, !w[i] { continue }
            out.append(s[i])
        }
        return out
    }

    func percent(_ part: Double, _ whole: Double) -> Double? { whole > 0 ? part / whole * 100 : nil }

    /// (a − b) / (a + b), nil when both are zero.
    func index(_ a: Double, _ b: Double) -> Double? { a + b > 0 ? (a - b) / (a + b) : nil }

    /// Window time bins [start, end).
    func timeBins(_ size: Double) -> [(Double, Double)] {
        let s = tb.windowStartTime
        var lastT = s
        for i in stride(from: n - 1, through: 0, by: -1) where tb.inWindow[i] { lastT = tb.t[i] + tb.dur[i]; break }
        let bin = max(size, 1)
        var out: [(Double, Double)] = []
        var a = s
        while a < lastT - 1e-6 && out.count < 2000 {
            out.append((a, min(a + bin, lastT)))
            a += bin
        }
        return out
    }

    /// Total time where mask is true inside [a, b).
    func total(_ mask: [Bool], from a: Double, to b: Double) -> Double {
        var s = 0.0
        for i in tb.indices(from: a, to: b) where tb.inWindow[i] && mask[i] { s += tb.dur[i] }
        return s
    }

    func windowTime(from a: Double, to b: Double) -> Double {
        var s = 0.0
        for i in tb.indices(from: a, to: b) where tb.inWindow[i] { s += tb.dur[i] }
        return s
    }

    // MARK: Plot helpers

    /// Downsampled polylines of a keypoint inside the window (optionally only where mask is true).
    /// For drawing only: a step faster than an animal can move (a residual tracking jump) starts
    /// a new polyline instead of being drawn as a long straight line across the arena.
    func segments(_ k: KP = .bodyCenter, animal: Int = 0, onlyWhere: [Bool]? = nil, maxPoints: Int = 4000, from a: Double = -.infinity, to b: Double = .infinity) -> [[V2]] {
        let f = fs.animals[animal]
        let step = max(1, n / maxPoints)
        let span = max(extent.x, extent.y)
        func plausible(_ from: V2, _ to: V2, _ dt: Double) -> Bool {
            let d = from.distance(to: to)
            if fs.isMetric && p.maxJumpSpeed > 0 { return d <= p.maxJumpSpeed * max(dt, tb.dt) * 1.25 + 2 }
            return d <= span * (0.05 + 1.5 * max(dt, tb.dt))
        }
        var segs: [[V2]] = []
        var cur: [V2] = []
        var lastT = 0.0
        var i = 0
        while i < n {
            let inRange = tb.inWindow[i] && tb.t[i] >= a && tb.t[i] < b && (onlyWhere?[i] ?? true)
            if inRange, let q = f.pos(k, i) {
                if let prev = cur.last, !plausible(prev, q, tb.t[i] - lastT) {
                    if cur.count > 1 { segs.append(cur) }
                    cur = []
                }
                cur.append(q)
                lastT = tb.t[i]
            } else if !cur.isEmpty {
                if cur.count > 1 { segs.append(cur) }
                cur = []
            }
            i += step
        }
        if cur.count > 1 { segs.append(cur) }
        return segs
    }

    func dots(_ k: KP, animal: Int = 0, where m: [Bool], color: ColorKey, maxDots: Int = 1500, radius: Double = 1.4) -> [PlotDot] {
        let f = fs.animals[animal]
        let idx = (0..<n).filter { m[$0] && tb.inWindow[$0] && f.pos(k, $0) != nil }
        let step = max(1, idx.count / maxDots)
        return stride(from: 0, to: idx.count, by: step).compactMap { j in
            f.pos(k, idx[j]).map { PlotDot(p: $0, color: color, radius: radius) }
        }
    }

    func heatGrid(_ k: KP = .bodyCenter, animal: Int = 0, cell: Double? = nil) -> HeatGrid {
        let e = extent
        let c = cell ?? (fs.isMetric ? max(0.5, p.spatialBin) : max(e.x, e.y) / 40)
        let cols = max(1, Int((e.x / c).rounded(.up)))
        let rows = max(1, Int((e.y / c).rounded(.up)))
        var v = [Double](repeating: 0, count: cols * rows)
        let f = fs.animals[animal]
        for i in 0..<n where tb.inWindow[i] {
            guard let q = f.pos(k, i) else { continue }
            let cx = Int(q.x / c), cy = Int(q.y / c)
            guard cx >= 0, cy >= 0, cx < cols, cy < rows else { continue }
            v[cy * cols + cx] += tb.dur[i]
        }
        if let arena = ZoneBuilder.arenaZone(session.calibration, mapping: fs.mapping),
           session.calibration.kind == .rectangle || session.calibration.kind == .circle {
            for r in 0..<rows {
                for col in 0..<cols where !arena.contains(V2((Double(col) + 0.5) * c, (Double(r) + 0.5) * c)) {
                    v[r * cols + col] = .nan
                }
            }
        }
        return HeatGrid(columns: cols, rows: rows, cell: c, values: v)
    }

    func arenaPlot(paths: [PlotPath]? = nil, dots: [PlotDot] = [], arrows: [PlotArrow] = [], heat: HeatGrid? = nil, zones z: [Zone]? = nil) -> ArenaPlotData {
        let defaultPaths: [PlotPath] = fs.animals.indices.map { a in
            PlotPath(color: fs.animals.count > 1 ? (a == 0 ? .animalA : .animalB) : .accent, segments: segments(animal: a))
        }
        return ArenaPlotData(extent: extent, arena: ZoneBuilder.arenaZone(session.calibration, mapping: fs.mapping),
                             zones: z ?? zones, paths: paths ?? defaultPaths, dots: dots, arrows: arrows, heat: heat, unit: u)
    }

    func trajectoryBlock(_ title: String = L10n.tr("轨迹与区域"), caption: String? = nil, dots: [PlotDot] = [], paths: [PlotPath]? = nil) -> ReportBlock {
        ReportBlock(title: title, caption: caption, kind: .arena(arenaPlot(paths: paths, dots: dots)))
    }

    func heatBlock(_ title: String = L10n.tr("停留热图"), caption: String? = nil, cell: Double? = nil) -> ReportBlock {
        ReportBlock(title: title, caption: caption, kind: .arena(arenaPlot(paths: [], heat: heatGrid(cell: cell))))
    }

    /// Distance per time bin.
    func distanceBinsBlock(animal: Int = 0) -> ReportBlock? {
        let bins = timeBins(p.timeBin)
        guard bins.count > 1 else { return nil }
        let f = fs.animals[animal]
        var items: [BarItem] = []
        for (k, (a, b)) in bins.enumerated() {
            var d = 0.0
            let r = tb.indices(from: a, to: b)
            for i in r where i > 0 && tb.inWindow[i] && tb.inWindow[i - 1] {
                guard tb.t[i] - tb.t[i - 1] <= 0.5, let x = f.pos(.bodyCenter, i - 1), let y = f.pos(.bodyCenter, i) else { continue }
                d += x.distance(to: y)
            }
            items.append(BarItem(label: binLabel(k, a, b), value: fs.isMetric ? d / 100 : d, color: .accent))
        }
        return ReportBlock(title: L10n.tr("分段路程"), caption: L10n.tr("每 \(Self.durationText(p.timeBin)) 的移动距离"), kind: .bars(BarData(items: items, unit: fs.isMetric ? "m" : "px", decimals: 2)))
    }

    func binLabel(_ k: Int, _ a: Double, _ b: Double) -> String {
        let s = tb.windowStartTime
        let x0 = (a - s) / 60, x1 = (b - s) / 60
        if p.timeBin >= 60 { return String(format: "%.0f–%.0f", x0, x1) }
        return String(format: "%.0f–%.0fs", a - s, b - s)
    }

    static func durationText(_ s: Double) -> String {
        if s >= 60 && abs(s.truncatingRemainder(dividingBy: 60)) < 0.01 { return "\(Int(s / 60)) min" }
        return String(format: "%.0f s", s)
    }

    /// Timeline over the analysis window.
    func timeline(_ tracks: [TimelineTrack], epochs: [Epoch] = []) -> TimelineData {
        var end = tb.windowStartTime
        for i in stride(from: n - 1, through: 0, by: -1) where tb.inWindow[i] { end = tb.t[i] + tb.dur[i]; break }
        return TimelineData(start: tb.windowStartTime, end: end, tracks: tracks, epochs: epochs)
    }

    // MARK: Metric helpers

    func m(_ key: String, _ title: String, _ value: Double?, _ unit: String = "", _ decimals: Int = 1, info: String? = nil) -> MetricValue {
        MetricValue(key: key, title: title, value: value, unit: unit, decimals: decimals, info: info)
    }

    /// Distance traveled, mean speed and moving time for one animal.
    func locomotionMetrics(animal: Int = 0, prefix: String = "", titlePrefix: String = "") -> [MetricValue] {
        let d = distance(animal: animal)
        let moving = tb.total(movingMask(animal: animal))
        let win = tb.windowDuration
        let distMetric = fs.isMetric
            ? m(prefix + "distance", titlePrefix + L10n.tr("总路程"), d / 100, "m", 2)
            : m(prefix + "distance", titlePrefix + L10n.tr("总路程"), d, "px", 0)
        return [
            distMetric,
            m(prefix + "mean_speed", titlePrefix + L10n.tr("平均速度"), win > 0 ? d / win : nil, u + "/s", 1),
            m(prefix + "moving_pct", titlePrefix + L10n.tr("运动时间"), percent(moving, win), "%", 1, info: L10n.tr("速度 > \(Self.num(p.moveSpeed)) \(u)/s"))
        ]
    }

    static func num(_ v: Double) -> String {
        abs(v - v.rounded()) < 1e-9 ? String(format: "%.0f", v) : String(format: "%g", v)
    }

    // MARK: Quality

    func quality() -> QualityInfo {
        var q = QualityInfo()
        q.frames = n
        let win = (0..<n).filter { tb.inWindow[$0] }
        q.framesInWindow = win.count
        q.windowSeconds = tb.windowDuration
        q.unit = u
        q.pxPerUnit = fs.mapping.pxPerUnit
        q.sampleRate = tb.dt > 0 ? 1 / tb.dt : 0
        guard !win.isEmpty else { return q }
        let det = win.filter { a0.detected[$0] }.count
        q.detectionRate = Double(det) / Double(win.count)
        q.keypointRates = (0..<kKeypointCount).map { k in
            Double(win.filter { a0.rawValid[k][$0] }.count) / Double(win.count)
        }
        q.headDirectionRate = Double(win.filter { a0.hd[$0].isFinite }.count) / Double(win.count)
        return q
    }

    func commonWarnings(_ q: QualityInfo) -> [String] {
        var w: [String] = []
        if q.framesInWindow < 10 {
            w.append(L10n.tr("分析时间段内的帧太少，请检查“分析起点 / 时长”是否超出了已识别的范围。"))
            return w
        }
        if q.detectionRate < 0.8 {
            w.append(String(format: L10n.tr("检出率只有 %.0f%%：结果可能偏差较大。请检查光照、遮挡，或在回看中确认。"), q.detectionRate * 100))
        }
        if !fs.isMetric && session.paradigm != .poseOnly && session.paradigm != .rotation {
            w.append(L10n.tr("未标定：距离和速度以像素为单位，基于厘米的阈值不适用。"))
        }
        if fs.animals.count > 1 {
            let both = (0..<n).filter { tb.inWindow[$0] && fs.animals[0].detected[$0] && fs.animals[1].detected[$0] }.count
            let frac = Double(both) / Double(max(1, q.framesInWindow))
            if frac < 0.8 {
                w.append(String(format: L10n.tr("只有 %.0f%% 的帧同时检出两只鼠；双鼠贴近或重叠时可能漏检或身份交换。"), frac * 100))
            }
        }
        return w
    }

    // MARK: Base per-frame columns

    /// Flags exported in the frame-by-frame CSV.
    static func flag(_ m: [Bool]) -> [Double] { m.map { $0 ? 1 : 0 } }
}

// MARK: - Dispatcher

enum Analyzer {
    static func run(session: Session, track: PoseTrack, companion: [String: Double] = [:]) -> AnalysisReport {
        run(session: session, features: Kinematics.build(track: track, session: session), companion: companion)
    }

    static func run(session: Session, features fs: FeatureSet, companion: [String: Double] = [:]) -> AnalysisReport {
        let zones = ZoneBuilder.zones(session, mapping: fs.mapping)
        let ctx = AnalysisContext(session: session, fs: fs, zones: zones, companion: companion)
        var r: AnalysisReport
        if fs.tb.count == 0 {
            r = AnalysisReport()
            r.warnings = [L10n.tr("还没有姿态数据。")]
            r.zones = zones
            r.primaryKey = session.paradigm.primaryMetricKey
            return r
        }
        switch session.paradigm {
        case .threeChamber: r = SocialAnalyzers.threeChamber(ctx)
        case .socialInteraction: r = SocialAnalyzers.socialInteraction(ctx)
        case .dyadicSocial: r = SocialAnalyzers.dyadic(ctx)
        case .headDirection: r = SpaceAnalyzers.headDirection(ctx)
        case .spatialExploration: r = SpaceAnalyzers.spatial(ctx)
        case .openField: r = SpaceAnalyzers.openField(ctx)
        case .rotation: r = SpaceAnalyzers.rotation(ctx)
        case .poseOnly: r = SpaceAnalyzers.poseOnly(ctx)
        case .elevatedPlusMaze: r = AnxietyAnalyzers.epm(ctx)
        case .lightDark: r = AnxietyAnalyzers.lightDark(ctx)
        case .novelObject: r = MemoryAnalyzers.novelObject(ctx)
        case .barnesMaze: r = MemoryAnalyzers.barnes(ctx)
        case .yMaze: r = MemoryAnalyzers.yMaze(ctx)
        case .tMaze: r = MemoryAnalyzers.tMaze(ctx)
        case .fearConditioning: r = MemoryAnalyzers.fear(ctx)
        case .looming: r = MemoryAnalyzers.looming(ctx)
        }
        if r.zones.isEmpty { r.zones = zones }
        if r.primaryKey.isEmpty { r.primaryKey = session.paradigm.primaryMetricKey }
        if let i = r.metrics.firstIndex(where: { $0.key == r.primaryKey }) { r.metrics[i].highlight = true }
        r.quality = ctx.quality()
        r.warnings = ctx.commonWarnings(r.quality) + r.warnings
        r.methods.insert(methodsPreamble(ctx), at: 0)
        return r
    }

    static func methodsPreamble(_ c: AnalysisContext) -> String {
        let s = c.session
        let step = s.inference.stride > 1 ? L10n.tr("每 \(s.inference.stride) 帧") : L10n.tr("逐帧")
        let gray = s.inference.grayscale ? L10n.tr("（先转灰度）") : ""
        return L10n.tr("姿态由 RodentStudio（YOLO pose，6 个关键点：鼻尖、左耳、右耳、颈部、身体中心、尾根）在设备上\(step)识别\(gray)；置信度 < \(AnalysisContext.num(s.params.kpConf)) 的关键点视为缺失，≤ \(AnalysisContext.num(s.params.maxGap)) s 的缺失做线性插值，并以 \(AnalysisContext.num(s.params.smoothing)) s 滑动平均平滑。")
    }

    /// Headline metrics cached in the session for lists and summary tables.
    static func cache(_ report: AnalysisReport, into s: inout Session) {
        var values: [String: Double] = [:]
        var labels: [String: String] = [:]
        var order: [String] = []
        for m in report.metrics {
            order.append(m.key)
            labels[m.key] = L10n.metricLabel(m.exportHeader, key: m.key)
            if let v = m.value, v.isFinite { values[m.key] = v }
        }
        s.metrics = values
        s.metricOrder = order
        s.metricLabels = labels
        s.primaryTitle = report.primary.map { L10n.metricLabel($0.title, key: $0.key) } ?? ""
        s.primaryDisplay = report.primary.map { m in
            guard m.value != nil else { return "—" }
            return m.unit.isEmpty ? m.formatted : "\(m.formatted) \(L10n.reportText(m.unit))"
        } ?? ""
    }
}
