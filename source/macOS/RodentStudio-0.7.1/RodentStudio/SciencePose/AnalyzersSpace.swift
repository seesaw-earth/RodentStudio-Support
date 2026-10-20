// RodentPose iOS 1.0 scientific algorithm port; only PoseTrack name and localization/zone invocation adapted.
// AnalyzersSpace.swift — head direction, spatial exploration, open field, rotation, pose only.

import Foundation

enum SpaceAnalyzers {

    // MARK: Shared pieces

    /// Times of completed 360° turns of an unwrapped angle series (counter-clockwise, clockwise).
    /// Each direction is counted separately: turning back by more than `maxBacktrack` degrees
    /// restarts the count in that direction (as in common tracking software).
    static func rotations(_ unwrapped: [Double], _ tb: TimeBase, sign: Double = 1, maxBacktrack: Double = 90) -> (ccw: [Double], cw: [Double]) {
        var ccw: [Double] = [], cw: [Double] = []
        var started = false
        var anchorCCW = 0.0, peakCCW = 0.0
        var anchorCW = 0.0, troughCW = 0.0
        for i in 0..<min(unwrapped.count, tb.count) where tb.inWindow[i] && unwrapped[i].isFinite {
            let v = unwrapped[i] * sign
            if !started {
                started = true
                anchorCCW = v; peakCCW = v
                anchorCW = v; troughCW = v
                continue
            }
            // Counter-clockwise
            if v > peakCCW { peakCCW = v }
            if peakCCW - v > maxBacktrack { anchorCCW = v; peakCCW = v }
            while v - anchorCCW >= 360 { ccw.append(tb.t[i]); anchorCCW += 360 }
            // Clockwise
            if v < troughCW { troughCW = v }
            if v - troughCW > maxBacktrack { anchorCW = v; troughCW = v }
            while anchorCW - v >= 360 { cw.append(tb.t[i]); anchorCW -= 360 }
        }
        return (ccw, cw)
    }

    /// Head direction occupancy (seconds per bin) relative to `reference` degrees.
    static func hdOccupancy(_ c: AnalysisContext, hd: [Double], binDeg: Double) -> [Double] {
        let bins = max(4, Int((360 / max(binDeg, 1)).rounded()))
        var occ = [Double](repeating: 0, count: bins)
        for i in 0..<c.n where c.tb.inWindow[i] && hd[i].isFinite {
            let b = min(bins - 1, Int(RPAngle.wrap360(hd[i]) / 360 * Double(bins)))
            occ[b] += c.tb.dur[i]
        }
        return occ
    }

    /// Histogram as a line (x = bin centers).
    static func histogram(_ values: [Double], weights: [Double]? = nil, from lo: Double, to hi: Double, bin: Double) -> [LinePoint] {
        let count = max(1, Int(((hi - lo) / bin).rounded()))
        var h = [Double](repeating: 0, count: count)
        for (j, v) in values.enumerated() where v.isFinite && v >= lo && v < hi {
            let b = min(count - 1, Int((v - lo) / bin))
            h[b] += weights?[j] ?? 1
        }
        return h.enumerated().map { LinePoint(x: lo + (Double($0.offset) + 0.5) * bin, y: $0.element) }
    }

    // MARK: Head direction

    static func headDirection(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let a = c.a0
        let tb = c.tb

        var reference = 0.0
        var refNote = RPTexts.tr("0° = 场地右方（左上 → 右上角方向），逆时针为正")
        if p.hdReference == "cue", let cue = c.zone("cue") {
            reference = (cue.center - c.extent / 2).screenAngleDeg
            refNote = RPTexts.tr("0° = 指向提示卡的方向，逆时针为正")
        }
        let hd = a.hd.map { $0.isFinite ? RPAngle.wrap360($0 - reference) : .nan }
        let occ = hdOccupancy(c, hd: hd, binDeg: p.hdBinDeg)
        let covered = occ.filter { $0 >= p.hdMinBinTime }.count
        let coverage = Double(covered) / Double(max(1, occ.count)) * 100

        var angs: [Double] = [], wts: [Double] = []
        for i in 0..<c.n where tb.inWindow[i] && hd[i].isFinite { angs.append(hd[i]); wts.append(tb.dur[i]) }
        let cm = RPAngle.circularMean(angles: angs, weights: wts)

        let ahvVals = c.values(a.ahv)
        let absAHV = ahvVals.map(abs)
        let ccwTurn = tb.total(c.mask(a.ahv) { $0 > 30 })
        let cwTurn = tb.total(c.mask(a.ahv) { $0 < -30 })
        let hbAbs = c.values(a.headBody).map(abs)
        let hdValid = c.percent(Double(angs.count), Double((0..<c.n).filter { tb.inWindow[$0] }.count))

        r.metrics = [
            c.m("hd_coverage", RPTexts.tr("方向覆盖度"), coverage, "%", 0, info: RPTexts.tr("停留 ≥ \(AnalysisContext.num(p.hdMinBinTime)) s 的 \(AnalysisContext.num(p.hdBinDeg))° 方向格比例")),
            c.m("hd_mrl", RPTexts.tr("占据平均向量长度"), cm?.r, "", 3, info: RPTexts.tr("0 = 各方向均匀；越大越偏向某一方向")),
            c.m("hd_mean", RPTexts.tr("占据平均方向"), cm?.mean, "°", 0),
            c.m("hd_valid", RPTexts.tr("头朝向有效帧"), hdValid, "%", 1),
            c.m("ahv_median", RPTexts.tr("|AHV| 中位数"), absAHV.finiteMedian, "°/s", 0),
            c.m("ahv_p95", RPTexts.tr("|AHV| 95 分位"), absAHV.percentile(0.95), "°/s", 0),
            c.m("turn_bias", RPTexts.tr("转头偏向"), c.index(ccwTurn, cwTurn), "", 2, info: RPTexts.tr("(逆时针 − 顺时针) ÷ 总转头时间，|AHV| > 30°/s")),
            c.m("head_body_abs", RPTexts.tr("|头–身夹角| 均值"), hbAbs.finiteMean, "°", 1)
        ] + c.locomotionMetrics()

        r.blocks.append(ReportBlock(title: RPTexts.tr("头朝向占据"), caption: refNote, kind: .polar(PolarData(values: occ, unit: "s", meanAngle: cm?.mean, resultantLength: cm?.r, referenceAngle: nil, color: .accent))))

        // Sampled head-direction arrows on the trajectory.
        var arrows: [PlotArrow] = []
        let every = max(1, Int((2.0 / tb.dt).rounded()))
        var i = 0
        let len = c.fs.isMetric ? 4.0 : c.extent.x / 25
        while i < c.n && arrows.count < 220 {
            if tb.inWindow[i], let base = a.headBase(i), a.hd[i].isFinite {
                let rad = a.hd[i] * Double.pi / 180
                arrows.append(PlotArrow(from: base, to: base + V2(cos(rad), -sin(rad)) * len, color: .accent))
            }
            i += every
        }
        var paths = [PlotPath(color: .neutral, segments: c.segments(), width: 0.8, opacity: 0.45)]
        if let cue = c.zone("cue"), p.hdReference == "cue" {
            paths.append(PlotPath(color: .warning, segments: [[c.extent / 2, cue.center]], width: 1.5, opacity: 0.9))
        }
        r.blocks.append(ReportBlock(title: RPTexts.tr("头朝向采样"), caption: RPTexts.tr("每 2 s 一个箭头（两耳中点 → 鼻尖方向）"),
                                    kind: .arena(c.arenaPlot(paths: paths, arrows: arrows))))

        let ahvHist = histogram(ahvVals, from: -720, to: 720, bin: 30).map { LinePoint(x: $0.x, y: $0.y * tb.dt) }
        r.blocks.append(ReportBlock(title: RPTexts.tr("角速度 AHV 分布"), caption: RPTexts.tr("正值为逆时针转头"), kind: .line(LineData(series: [LineSeries(name: "AHV", color: .accent, points: ahvHist)], xLabel: "°/s", yLabel: "s", referenceX: 0))))
        let hbHist = histogram(c.values(a.headBody), from: -90, to: 90, bin: 10).map { BarItem(label: String(format: "%.0f", $0.x), value: $0.y * tb.dt, color: .series2) }
        r.blocks.append(ReportBlock(title: RPTexts.tr("头–身夹角分布"), caption: RPTexts.tr("正值 = 头偏向身体左侧（逆时针）"), kind: .bars(BarData(items: hbHist, unit: "s"))))

        if coverage < 80 {
            r.warnings.append(String(format: RPTexts.tr("方向覆盖度只有 %.0f%%：部分方向采样不足，调谐曲线在这些方向上不可靠。"), coverage))
        }
        if let m = cm?.r, m > 0.3 {
            r.warnings.append(String(format: RPTexts.tr("头朝向占据明显不均匀（平均向量长度 %.2f），计算调谐曲线时务必按占据归一化。"), m))
        }
        r.frameColumns = [("hd_rel_deg", hd), ("ahv_deg_s", a.ahv)]
        r.methods.append(RPTexts.tr("头朝向为两耳中点 → 鼻尖向量的方向（鼻尖或两耳缺失时用颈部 → 鼻尖）；\(refNote)。角速度 AHV 为展开后头朝向的中心差分。占据按 \(AnalysisContext.num(p.hdBinDeg))° 分格累计停留时间。"))
        return r
    }

    // MARK: Spatial exploration

    static func spatial(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let a = c.a0
        let tb = c.tb
        let grid = c.heatGrid(cell: c.fs.isMetric ? p.spatialBin : nil)
        let inside = grid.values.filter { $0.isFinite }
        let visited = inside.filter { $0 >= p.coverageMinTime }.count
        let coverage = Double(visited) / Double(max(1, inside.count)) * 100
        let moving = c.movingMask()
        let runT = tb.total(moving)

        // Occupancy uniformity: normalized entropy over arena cells.
        let total = inside.reduce(0, +)
        var entropy = 0.0
        if total > 0 {
            for v in inside where v > 0 { let q = v / total; entropy -= q * log(q) }
        }
        let uniformity = inside.count > 1 ? entropy / log(Double(inside.count)) : nil

        r.metrics = [
            c.m("coverage", RPTexts.tr("覆盖度"), coverage, "%", 1, info: RPTexts.tr("停留 ≥ \(AnalysisContext.num(p.coverageMinTime)) s 的 \(AnalysisContext.num(p.spatialBin)) \(c.u) 方格比例")),
            c.m("uniformity", RPTexts.tr("占据均匀度"), uniformity, "", 2, info: RPTexts.tr("归一化熵：1 = 完全均匀")),
            c.m("run_pct", RPTexts.tr("运动时间"), c.percent(runT, tb.windowDuration), "%", 1, info: RPTexts.tr("速度 > \(AnalysisContext.num(p.moveSpeed)) \(c.u)/s")),
            c.m("run_speed", RPTexts.tr("运动时平均速度"), c.mean(a.speed, onlyWhere: moving), c.u + "/s", 1)
        ] + c.locomotionMetrics()

        r.blocks.append(c.heatBlock(RPTexts.tr("占据图"), caption: RPTexts.tr("身体中心停留时间；方格 \(AnalysisContext.num(grid.cell)) \(c.u)"), cell: grid.cell))
        r.blocks.append(c.trajectoryBlock(RPTexts.tr("轨迹")))

        // Coverage growth over time.
        var occ = [Double](repeating: 0, count: grid.columns * grid.rows)
        var growth: [LinePoint] = [LinePoint(x: 0, y: 0)]
        let idx = (0..<c.n).filter { tb.inWindow[$0] }
        let step = max(1, idx.count / 120)
        var count = 0
        let s0 = tb.windowStartTime
        for (j, i) in idx.enumerated() {
            if let q = a.pos(.bodyCenter, i) {
                let cx = Int(q.x / grid.cell), cy = Int(q.y / grid.cell)
                if cx >= 0, cy >= 0, cx < grid.columns, cy < grid.rows, grid.values[cy * grid.columns + cx].isFinite {
                    let k = cy * grid.columns + cx
                    let before = occ[k]
                    occ[k] += tb.dur[i]
                    if before < p.coverageMinTime && occ[k] >= p.coverageMinTime { count += 1 }
                }
            }
            if j % step == 0 || j == idx.count - 1 {
                growth.append(LinePoint(x: (tb.t[i] - s0) / 60, y: Double(count) / Double(max(1, inside.count)) * 100))
            }
        }
        r.blocks.append(ReportBlock(title: RPTexts.tr("覆盖度增长"), caption: RPTexts.tr("曲线趋于平台说明采样基本充分"), kind: .line(LineData(series: [LineSeries(name: RPTexts.tr("覆盖度"), color: .accent, points: growth)], xLabel: "min", yLabel: "%", yRange: 0...100))))

        let edges: [Double] = [0, 2, 5, 10, 20, .infinity]
        let labels = ["0–2", "2–5", "5–10", "10–20", "> 20"]
        var items: [BarItem] = []
        for k in 0..<labels.count {
            let lo = edges[k], hi = edges[k + 1]
            let t = tb.total(c.mask(a.speed) { $0 >= lo && $0 < hi })
            items.append(BarItem(label: labels[k], value: c.percent(t, tb.windowDuration) ?? 0, color: k == 0 ? .neutral : .accent))
        }
        r.blocks.append(ReportBlock(title: RPTexts.tr("速度分布"), caption: RPTexts.tr("单位 \(c.u)/s"), kind: .bars(BarData(items: items, unit: "%"))))
        if let b = c.distanceBinsBlock() { r.blocks.append(b) }

        if coverage < 70 { r.warnings.append(String(format: RPTexts.tr("覆盖度 %.0f%%：场地部分区域采样不足，放电野可能不完整。"), coverage)) }
        r.frameColumns = [("running", AnalysisContext.flag(moving))]
        r.methods.append(RPTexts.tr("占据图按 \(AnalysisContext.num(p.spatialBin)) \(c.u) 方格累计身体中心停留时间；运动时段定义为身体中心速度 > \(AnalysisContext.num(p.moveSpeed)) \(c.u)/s。"))
        return r
    }

    // MARK: Open field

    static func openField(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        let center = c.zone("center")
        let inCenter = center.map { c.mask(.bodyCenter, in: $0) } ?? [Bool](repeating: false, count: c.n)
        let centerT = tb.total(inCenter)
        let freeze = c.freezingMask()
        let rot = rotations(a.bodyU, tb)
        let d = c.distance()
        let dCenter = c.distance(onlyWhere: inCenter)

        r.metrics = [
            c.m("center_pct", RPTexts.tr("中央区时间"), c.percent(centerT, tb.windowDuration), "%", 1),
            c.m("center_time", RPTexts.tr("中央区时间"), centerT, "s", 1),
            c.m("center_entries", RPTexts.tr("中央区进入次数"), Double(Bouts.entries(inCenter, tb)), "", 0),
            c.m("center_latency", RPTexts.tr("首次进入中央区"), tb.firstTime(inCenter), "s", 1),
            c.m("center_distance_pct", RPTexts.tr("中央区路程占比"), c.percent(dCenter, d), "%", 1)
        ] + c.locomotionMetrics() + [
            c.m("immobile_time", RPTexts.tr("静止时间"), tb.total(freeze), "s", 1, info: RPTexts.tr("关键点运动 < \(AnalysisContext.num(p.freezeSpeed)) \(c.u)/s 持续 ≥ \(AnalysisContext.num(p.freezeMin)) s")),
            c.m("rot_ccw", RPTexts.tr("逆时针转圈"), Double(rot.ccw.count), "", 0),
            c.m("rot_cw", RPTexts.tr("顺时针转圈"), Double(rot.cw.count), "", 0)
        ]
        r.blocks.append(c.trajectoryBlock())
        r.blocks.append(c.heatBlock())
        if let b = c.distanceBinsBlock() { r.blocks.append(b) }
        let tracks = [TimelineTrack(name: RPTexts.tr("中央区"), color: .center, bouts: Bouts.find(inCenter, tb)),
                      TimelineTrack(name: RPTexts.tr("静止"), color: .freezing, bouts: Bouts.find(freeze, tb))]
        r.blocks.append(ReportBlock(title: RPTexts.tr("时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("in_center", AnalysisContext.flag(inCenter)), ("immobile", AnalysisContext.flag(freeze))]
        r.methods.append(RPTexts.tr("中央区为场地中心 \(Int(p.centerFraction * 100))%（按边长）区域，按身体中心判断。"))
        return r
    }

    // MARK: Rotation

    static func rotation(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let sign = p.cameraBelow ? -1.0 : 1.0
        let rot = rotations(c.a0.bodyU, tb, sign: sign)
        let minutes = tb.windowDuration / 60
        // Viewed from above: counter-clockwise = the animal turns left.
        let left = rot.ccw, right = rot.cw
        let lesion = p.lesionSide
        let hasLesion = lesion == "left" || lesion == "right"
        let ipsi = lesion == "left" ? left : right
        let contra = lesion == "left" ? right : left

        r.metrics = [
            c.m("rot_ccw", RPTexts.tr("逆时针（左转）"), Double(left.count), RPTexts.tr("圈"), 0),
            c.m("rot_cw", RPTexts.tr("顺时针（右转）"), Double(right.count), RPTexts.tr("圈"), 0)
        ]
        if hasLesion {
            let net = Double(ipsi.count - contra.count)
            r.metrics = [
                c.m("net_per_min", RPTexts.tr("净旋转"), minutes > 0 ? net / minutes : nil, RPTexts.tr("圈/min"), 2, info: RPTexts.tr("（同侧 − 对侧）÷ 分钟")),
                c.m("net", RPTexts.tr("净旋转（同侧 − 对侧）"), net, RPTexts.tr("圈"), 0),
                c.m("ipsi", RPTexts.tr("同侧旋转"), Double(ipsi.count), RPTexts.tr("圈"), 0),
                c.m("contra", RPTexts.tr("对侧旋转"), Double(contra.count), RPTexts.tr("圈"), 0),
                c.m("ipsi_pct", RPTexts.tr("同侧占比"), c.percent(Double(ipsi.count), Double(ipsi.count + contra.count)), "%", 1)
            ] + r.metrics
        } else {
            let net = Double(left.count - right.count)
            r.metrics = [
                c.m("net_per_min", RPTexts.tr("净旋转"), minutes > 0 ? net / minutes : nil, RPTexts.tr("圈/min"), 2, info: RPTexts.tr("（逆时针 − 顺时针）÷ 分钟；设置损伤侧后改为同侧 − 对侧")),
                c.m("net", RPTexts.tr("净旋转（逆 − 顺）"), net, RPTexts.tr("圈"), 0)
            ] + r.metrics
        }
        r.metrics += c.locomotionMetrics()

        // Per-bin counts.
        let bins = c.timeBins(p.rotationBin)
        var items: [BarItem] = []
        let first: (String, [Double], ColorKey) = hasLesion ? (RPTexts.tr("同侧"), ipsi, .cw) : (RPTexts.tr("逆时针"), left, .ccw)
        let second: (String, [Double], ColorKey) = hasLesion ? (RPTexts.tr("对侧"), contra, .ccw) : (RPTexts.tr("顺时针"), right, .cw)
        for (k, (a, b)) in bins.enumerated() {
            let label = c.binLabel(k, a, b)
            items.append(BarItem(label: first.0, value: Double(first.1.filter { $0 >= a && $0 < b }.count), color: first.2, group: label))
            items.append(BarItem(label: second.0, value: Double(second.1.filter { $0 >= a && $0 < b }.count), color: second.2, group: label))
        }
        if !items.isEmpty {
            r.blocks.append(ReportBlock(title: RPTexts.tr("分段旋转数"), caption: RPTexts.tr("每 \(AnalysisContext.durationText(p.rotationBin))（横轴单位 min）"), kind: .bars(BarData(items: items, unit: RPTexts.tr("圈"), decimals: 0))))
        }
        // Cumulative net rotations.
        let events = (first.1.map { ($0, 1.0) } + second.1.map { ($0, -1.0) }).sorted { $0.0 < $1.0 }
        let s0 = tb.windowStartTime
        var acc = 0.0
        var pts = [LinePoint(x: 0, y: 0)]
        for (t, v) in events { acc += v; pts.append(LinePoint(x: (t - s0) / 60, y: acc)) }
        pts.append(LinePoint(x: tb.windowDuration / 60, y: acc))
        r.blocks.append(ReportBlock(title: RPTexts.tr("累计净旋转"), caption: hasLesion ? RPTexts.tr("同侧 − 对侧") : RPTexts.tr("逆时针 − 顺时针"), kind: .line(LineData(series: [LineSeries(name: RPTexts.tr("净旋转"), color: .accent, points: pts)], xLabel: "min", yLabel: RPTexts.tr("圈"), referenceY: 0))))
        r.blocks.append(c.trajectoryBlock(RPTexts.tr("轨迹")))
        r.reviewTracks = [
            TimelineTrack(name: first.0, color: first.2, bouts: first.1.map { Bout(start: $0 - 0.3, end: $0 + 0.3, i0: 0, i1: 0) }),
            TimelineTrack(name: second.0, color: second.2, bouts: second.1.map { Bout(start: $0 - 0.3, end: $0 + 0.3, i0: 0, i1: 0) })
        ]
        r.frameColumns = [("body_angle_unwrapped_deg", c.a0.bodyU.map { $0 * sign })]
        r.methods.append(RPTexts.tr("身体轴向为尾根 → 颈部向量；对展开后的角度分方向累计，每转过完整 360° 记一圈，反向回转超过 90° 时该方向重新计数。俯拍时画面逆时针对应动物左转\(p.cameraBelow ? RPTexts.tr("；本会话为从下方拍摄，方向已镜像") : "")。"))
        return r
    }

    // MARK: Pose only

    static func poseOnly(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let tb = c.tb
        let a = c.a0
        let win = (0..<c.n).filter { tb.inWindow[$0] }
        let det = Double(win.filter { a.detected[$0] }.count) / Double(max(1, win.count)) * 100
        r.metrics = [
            c.m("detection_rate", RPTexts.tr("检出率"), det, "%", 1),
            c.m("frames", RPTexts.tr("分析帧数"), Double(win.count), "", 0),
            c.m("body_length", RPTexts.tr("身体长度中位数"), c.values(a.bodyLength).finiteMedian, c.u, 1, info: RPTexts.tr("鼻尖 → 尾根"))
        ]
        for k in KP.allCases {
            let rate = Double(win.filter { a.rawValid[k.rawValue][$0] }.count) / Double(max(1, win.count)) * 100
            r.metrics.append(c.m("kp_\(k.key)", RPTexts.tr("\(k.title)有效"), rate, "%", 1))
        }
        r.metrics += c.locomotionMetrics()
        let items = KP.allCases.map { k in
            BarItem(label: k.title, value: Double(win.filter { a.rawValid[k.rawValue][$0] }.count) / Double(max(1, win.count)) * 100, color: .accent)
        }
        r.blocks.append(ReportBlock(title: RPTexts.tr("各关键点有效比例"), caption: RPTexts.tr("置信度 ≥ \(AnalysisContext.num(c.p.kpConf))"), kind: .bars(BarData(items: items, unit: "%", referenceLine: 80))))
        r.blocks.append(c.trajectoryBlock(RPTexts.tr("轨迹（身体中心）")))
        let occ = hdOccupancy(c, hd: a.hd, binDeg: 10)
        r.blocks.append(ReportBlock(title: RPTexts.tr("头朝向占据"), caption: RPTexts.tr("0° = 画面右方，逆时针为正"), kind: .polar(PolarData(values: occ, unit: "s", meanAngle: nil, resultantLength: nil))))
        return r
    }
}
