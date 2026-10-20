// AnalyzersMemory.swift — novel object recognition, Barnes maze, Y-maze alternation, T-maze VTE,
// fear conditioning (freezing) and looming escape.

import Foundation

enum MemoryAnalyzers {

    // MARK: Novel object recognition

    static func novelObject(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        guard let za = c.zone("objA"), let zb = c.zone("objB") else {
            r.warnings.append(L10n.tr("请在标定页把 A / B 手柄放到两个物体的中心。"))
            r.metrics = c.locomotionMetrics()
            return r
        }
        let training = c.session.phase == "Training"
        let expA = c.investigationMask(target: za.center, radius: p.objectRadius, reach: p.exploreMargin)
        let expB = c.investigationMask(target: zb.center, radius: p.objectRadius, reach: p.exploreMargin)
        let novelIsB = p.novelObject != "A"
        let nMask = training ? expB : (novelIsB ? expB : expA)
        let fMask = training ? expA : (novelIsB ? expA : expB)
        let nName = training ? L10n.tr("物体 B") : L10n.tr("新物体")
        let fName = training ? L10n.tr("物体 A") : L10n.tr("旧物体")
        let nColor: ColorKey = training ? .series2 : .novel
        let fColor: ColorKey = training ? .series1 : .familiar

        let tN = tb.total(nMask), tF = tb.total(fMask)
        let total = tN + tF
        let bN = c.bouts(nMask), bF = c.bouts(fMask)

        // Time to 20 s of total exploration and DI at that point.
        var t20: Double?
        var di20: Double?
        var accN = 0.0, accF = 0.0
        for i in 0..<c.n where tb.inWindow[i] {
            if nMask[i] { accN += tb.dur[i] }
            if fMask[i] { accF += tb.dur[i] }
            if accN + accF >= 20 {
                t20 = tb.t[i] + tb.dur[i] - tb.windowStartTime
                di20 = c.index(accN, accF)
                break
            }
        }

        let diTitle = training ? L10n.tr("位置偏好指数") : L10n.tr("辨别指数 DI")
        r.metrics = [
            c.m("di", diTitle, c.index(tN, tF), "", 2, info: training ? L10n.tr("(B − A) ÷ (B + A)，用于检查位置偏好") : L10n.tr("(新 − 旧) ÷ (新 + 旧)")),
            c.m("ri", training ? L10n.tr("B 占比") : L10n.tr("识别指数 RI"), c.percent(tN, total), "%", 1),
            c.m(training ? "exp_b" : "exp_novel", L10n.tr("探索\(nName)"), tN, "s", 1),
            c.m(training ? "exp_a" : "exp_familiar", L10n.tr("探索\(fName)"), tF, "s", 1),
            c.m("exp_total", L10n.tr("总探索时间"), total, "s", 1),
            c.m(training ? "bouts_b" : "bouts_novel", L10n.tr("\(nName)探索次数"), Double(bN.count), "", 0),
            c.m(training ? "bouts_a" : "bouts_familiar", L10n.tr("\(fName)探索次数"), Double(bF.count), "", 0),
            c.m(training ? "latency_b" : "latency_novel", L10n.tr("首次探索\(nName)"), tb.firstTime(nMask), "s", 1),
            c.m(training ? "latency_a" : "latency_familiar", L10n.tr("首次探索\(fName)"), tb.firstTime(fMask), "s", 1),
            c.m("time_to_20s", L10n.tr("达到 20 s 探索"), t20, "s", 0),
            c.m("di_20s", L10n.tr("前 20 s 探索的 DI"), di20, "", 2)
        ] + c.locomotionMetrics()

        r.blocks.append(c.trajectoryBlock(caption: L10n.tr("彩色点为探索时的鼻尖位置；虚线圈为 \(AnalysisContext.num(p.exploreMargin)) cm 判定范围"),
                                          dots: c.dots(.nose, where: nMask, color: nColor, radius: 1.8) + c.dots(.nose, where: fMask, color: fColor, radius: 1.8)))
        r.blocks.append(ReportBlock(title: L10n.tr("探索时间"), caption: diTitle + " = " + (c.index(tN, tF).map { String(format: "%.2f", $0) } ?? "—"),
                                    kind: .bars(BarData(items: [BarItem(label: nName, value: tN, color: nColor), BarItem(label: fName, value: tF, color: fColor)], unit: "s"))))
        r.blocks.append(ReportBlock(title: L10n.tr("累计探索时间"), caption: nil, kind: .line(LineData(series: [
            LineSeries(name: nName, color: nColor, points: c.cumulative(nMask)),
            LineSeries(name: fName, color: fColor, points: c.cumulative(fMask))], xLabel: "min", yLabel: "s"))))

        // Cumulative DI over time.
        var diPts: [LinePoint] = []
        accN = 0; accF = 0
        let idx = (0..<c.n).filter { tb.inWindow[$0] }
        let step = max(1, idx.count / 240)
        for (j, i) in idx.enumerated() {
            if nMask[i] { accN += tb.dur[i] }
            if fMask[i] { accF += tb.dur[i] }
            if (j % step == 0 || j == idx.count - 1), accN + accF >= 2, let d = c.index(accN, accF) {
                diPts.append(LinePoint(x: (tb.t[i] - tb.windowStartTime) / 60, y: d))
            }
        }
        if !diPts.isEmpty {
            r.blocks.append(ReportBlock(title: L10n.tr("累计 \(training ? L10n.tr("位置偏好") : "DI") 曲线"), caption: L10n.tr("累计探索 ≥ 2 s 后开始绘制"), kind: .line(LineData(series: [LineSeries(name: "DI", color: .accent, points: diPts)], xLabel: "min", yLabel: "DI", yRange: -1...1, referenceY: 0))))
        }
        let tracks = [TimelineTrack(name: L10n.tr("探索\(nName)"), color: nColor, bouts: bN), TimelineTrack(name: L10n.tr("探索\(fName)"), color: fColor, bouts: bF)]
        r.blocks.append(ReportBlock(title: L10n.tr("探索时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        if total < 20 {
            r.warnings.append(String(format: L10n.tr("总探索时间 %.1f s，不足 20 s（许多研究以此作为纳入标准）。"), total))
        }
        r.frameColumns = [("explore_A", AnalysisContext.flag(expA)), ("explore_B", AnalysisContext.flag(expB))]
        r.methods.append(L10n.tr("物体探索定义为鼻尖距物体外缘（半径 \(AnalysisContext.num(p.objectRadius)) cm）≤ \(AnalysisContext.num(p.exploreMargin)) cm、头朝向与物体方向夹角 ≤ \(AnalysisContext.num(p.headTolerance))°，且身体中心不在物体上（排除攀爬）。"))
        return r
    }

    // MARK: Barnes maze

    struct PokeEvent {
        var hole: Int
        var start: Double
        var end: Double
        var i0: Int
    }

    static func barnes(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let g = BarnesGeometry.from(c.session.calibration, params: p, mapping: c.fs.mapping) else {
            r.warnings.append(L10n.tr("需要圆形平台标定，并把 T 手柄放到目标洞。"))
            r.metrics = c.locomotionMetrics()
            return r
        }
        let reach = g.holeRadius + p.pokeMargin
        var holeAt = [Int](repeating: -1, count: c.n)
        for i in 0..<c.n {
            guard let nose = a.pos(.nose, i) else { continue }
            var best = -1
            var bd = reach
            for (k, h) in g.holes.enumerated() {
                let d = nose.distance(to: h)
                if d <= bd { bd = d; best = k }
            }
            holeAt[i] = best
        }
        // Group into poke events per hole.
        var events: [PokeEvent] = []
        for k in g.holes.indices {
            let mask = holeAt.map { $0 == k }
            for b in Bouts.find(mask, tb, minDuration: p.holePokeMin, mergeGap: 0.2) {
                events.append(PokeEvent(hole: k, start: b.start, end: b.end, i0: b.i0))
            }
        }
        events.sort { $0.start < $1.start }
        let s0 = tb.windowStartTime
        let firstTarget = events.first { $0.hole == 0 }
        let primaryErrors = events.filter { $0.hole != 0 && (firstTarget == nil || $0.start < firstTarget!.start) }.count
        let totalErrors = events.filter { $0.hole != 0 }.count

        // Path length until the first target poke.
        var pathToTarget: Double?
        if let ft = firstTarget {
            let m = (0..<c.n).map { tb.t[$0] <= ft.start }
            pathToTarget = c.distance(onlyWhere: m)
        }

        // Escape: tracking lost ≥ 2 s right next to the target after finding it.
        var escapeLatency: Double?
        if let ft = firstTarget {
            var i = ft.i0
            while i < c.n {
                if !a.detected[i] {
                    var j = i
                    while j < c.n && !a.detected[j] { j += 1 }
                    let gap = (j < c.n ? tb.t[j] : tb.t[c.n - 1] + tb.dur[c.n - 1]) - tb.t[i]
                    if gap >= 2, i > 0, let last = (stride(from: i - 1, through: max(0, i - 30), by: -1).lazy.compactMap { a.pos(.bodyCenter, $0) }.first),
                       last.distance(to: g.holes[0]) <= g.holeRadius + 6 {
                        escapeLatency = tb.t[i] - s0
                        break
                    }
                    i = j
                } else {
                    i += 1
                }
            }
        }

        // Initial heading error: direction after the first 10 cm of travel vs direction to the target.
        var headingError: Double?
        if let i0 = (0..<c.n).first(where: { tb.inWindow[$0] && a.pos(.bodyCenter, $0) != nil }), let start = a.pos(.bodyCenter, i0) {
            for i in i0..<c.n where tb.inWindow[i] {
                guard let q = a.pos(.bodyCenter, i), q.distance(to: start) >= 10 else { continue }
                headingError = Angle.diff((q - start).screenAngleDeg, (g.holes[0] - start).screenAngleDeg)
                break
            }
        }

        let quad = c.zone("quadrant")
        let inQuad = quad.map { c.mask(.bodyCenter, in: $0) } ?? [Bool](repeating: false, count: c.n)
        r.metrics = [
            c.m("primary_latency", L10n.tr("首次潜伏期"), firstTarget.map { $0.start - s0 }, "s", 1, info: L10n.tr("鼻尖首次探入目标洞")),
            c.m("primary_errors", L10n.tr("首次错误数"), firstTarget == nil ? Double(totalErrors) : Double(primaryErrors), "", 0),
            c.m("total_errors", L10n.tr("总错误数"), Double(totalErrors), "", 0),
            c.m("target_pokes", L10n.tr("目标洞探洞次数"), Double(events.filter { $0.hole == 0 }.count), "", 0),
            c.m("path_to_target", L10n.tr("到目标路径长度"), pathToTarget.map { $0 / 100 }, "m", 2),
            c.m("escape_latency", L10n.tr("进入逃逸箱"), escapeLatency, "s", 1, info: L10n.tr("目标洞附近追踪消失 ≥ 2 s 的时刻")),
            c.m("heading_error", L10n.tr("起始朝向误差"), headingError, "°", 0, info: L10n.tr("最初 10 cm 移动方向与目标方向的夹角")),
            c.m("target_quadrant_pct", L10n.tr("目标象限时间"), c.percent(tb.total(inQuad), tb.windowDuration), "%", 1)
        ] + c.locomotionMetrics()

        let dots = events.compactMap { e -> PlotDot? in
            a.pos(.nose, e.i0).map { PlotDot(p: $0, color: e.hole == 0 ? .target : .error, radius: 2.4) }
        }
        r.blocks.append(c.trajectoryBlock(caption: L10n.tr("绿点 = 探入目标洞，红点 = 错误（探入其他洞）"), dots: dots))
        var perHole: [Int: Int] = [:]
        for e in events { perHole[g.offset(e.hole), default: 0] += 1 }
        let offsets = Array(-(g.holes.count / 2 - (g.holes.count % 2 == 0 ? 1 : 0))...(g.holes.count / 2))
        let items = offsets.map { o in BarItem(label: "\(o)", value: Double(perHole[o] ?? 0), color: o == 0 ? .target : .neutral) }
        r.blocks.append(ReportBlock(title: L10n.tr("各洞探洞次数"), caption: L10n.tr("横轴为相对目标洞的位置（0 = 目标）"), kind: .bars(BarData(items: items, unit: L10n.tr("次"), decimals: 0))))
        if !events.isEmpty {
            let rows = events.prefix(60).enumerated().map { (k, e) -> [String] in
                [String(k + 1), String(format: "%.1f", e.start - s0), e.hole == 0 ? L10n.tr("目标") : "\(g.offset(e.hole))", e.hole == 0 ? "✓" : L10n.tr("错误")]
            }
            r.blocks.append(ReportBlock(title: L10n.tr("探洞记录"), caption: events.count > 60 ? L10n.tr("仅显示前 60 次") : nil,
                                        kind: .table(TableData(columns: ["#", L10n.tr("时间 (s)"), L10n.tr("洞"), L10n.tr("类型")], rows: rows, rowColors: events.prefix(60).map { $0.hole == 0 ? .target : nil }))))
        }
        let targetBouts = events.filter { $0.hole == 0 }.map { Bout(start: $0.start, end: $0.end, i0: $0.i0, i1: $0.i0) }
        let errorBouts = events.filter { $0.hole != 0 }.map { Bout(start: $0.start, end: $0.end, i0: $0.i0, i1: $0.i0) }
        let tracks = [TimelineTrack(name: L10n.tr("目标洞"), color: .target, bouts: targetBouts), TimelineTrack(name: L10n.tr("错误"), color: .error, bouts: errorBouts)]
        r.blocks.append(ReportBlock(title: L10n.tr("探洞时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("nose_in_hole", holeAt.map { Double($0) })]
        r.methods.append(L10n.tr("探洞定义为鼻尖进入洞口（半径 \(AnalysisContext.num(g.holeRadius)) cm + \(AnalysisContext.num(p.pokeMargin)) cm）持续 ≥ \(AnalysisContext.num(p.holePokeMin)) s；错误为探入非目标洞，同一洞 0.2 s 内的连续探入合并为一次。"))
        if firstTarget == nil { r.warnings.append(L10n.tr("分析时间段内没有检测到探入目标洞。")) }
        return r
    }

    // MARK: Y-maze

    /// Arm index (0…), or −1 for the center / off-maze.
    static func armOf(_ m: MazeGeometry, _ q: V2?) -> Int {
        guard let q else { return -1 }
        return m.armIndex(q, tolerance: 1.25) ?? -1
    }

    /// Arm occupancy with entry rule: "full" = body center and tail base in the same arm, "body", "nose".
    /// Leaving is decided by the body center.
    static func armStates(_ c: AnalysisContext, _ m: MazeGeometry, rule: String) -> [Int] {
        let a = c.a0
        var state = [Int](repeating: -1, count: c.n)
        var cur = -1
        var lastBody = -1
        for i in 0..<c.n {
            let bq = a.pos(.bodyCenter, i)
            var b = armOf(m, bq)
            if bq == nil { b = lastBody } else { lastBody = b }
            if cur >= 0 {
                if bq != nil && b != cur { cur = -1 }
            }
            if cur < 0 {
                switch rule {
                case "full":
                    if b >= 0, armOf(m, a.pos(.tailBase, i)) == b { cur = b }
                case "nose":
                    let nq = armOf(m, a.pos(.nose, i))
                    if nq >= 0 { cur = nq }
                default:
                    if b >= 0 { cur = b }
                }
            }
            state[i] = cur
        }
        return state
    }

    static func yMaze(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let m = MazeGeometry.from(c.session.calibration, mapping: c.fs.mapping), m.ends.count == 3 else {
            r.warnings.append(L10n.tr("需要 Y 迷宫标定（J、A、B、C）。"))
            return r
        }
        let state = armStates(c, m, rule: p.entryRule)
        var entries: [(arm: Int, time: Double)] = []
        var prev = -1
        for i in 0..<c.n where tb.inWindow[i] {
            if state[i] >= 0 && state[i] != prev { entries.append((state[i], tb.t[i])) }
            prev = state[i]
        }
        var alternations = 0
        var altFlags = [Bool](repeating: false, count: entries.count)
        if entries.count >= 3 {
            for k in 2..<entries.count where Set([entries[k].arm, entries[k - 1].arm, entries[k - 2].arm]).count == 3 {
                alternations += 1
                altFlags[k] = true
            }
        }
        var sameArm = 0
        if entries.count >= 2 { for k in 1..<entries.count where entries[k].arm == entries[k - 1].arm { sameArm += 1 } }

        // Head probes: nose enters an arm while the body is in the center, then withdraws.
        var probes = 0
        var probeArm = -1
        var probeStart = 0.0
        for i in 0..<c.n where tb.inWindow[i] {
            let noseArm = armOf(m, a.pos(.nose, i))
            if state[i] >= 0 {
                probeArm = -1
                continue
            }
            if probeArm < 0 {
                if noseArm >= 0 { probeArm = noseArm; probeStart = tb.t[i] }
            } else if noseArm != probeArm {
                if tb.t[i] - probeStart >= 0.2 { probes += 1 }
                probeArm = noseArm >= 0 ? noseArm : -1
                probeStart = tb.t[i]
            }
        }

        let possible = max(0, entries.count - 2)
        r.metrics = [
            c.m("alternation_pct", L10n.tr("交替率"), possible > 0 ? Double(alternations) / Double(possible) * 100 : nil, "%", 1, info: L10n.tr("交替次数 ÷（总进入次数 − 2）")),
            c.m("alternations", L10n.tr("交替次数"), Double(alternations), "", 0),
            c.m("entries_total", L10n.tr("总进入次数"), Double(entries.count), "", 0),
            c.m("same_arm_returns", L10n.tr("重复进入同一臂"), Double(sameArm), "", 0),
            c.m("head_probes", L10n.tr("探头未进入"), Double(probes), "", 0, info: L10n.tr("鼻尖进入某臂而身体未进入"))
        ]
        for k in 0..<3 {
            r.metrics.append(c.m("entries_\(m.labels[k])", L10n.tr("进入臂 \(m.labels[k])"), Double(entries.filter { $0.arm == k }.count), "", 0))
        }
        for k in 0..<3 {
            r.metrics.append(c.m("time_\(m.labels[k])", L10n.tr("臂 \(m.labels[k]) 时间"), tb.total(state.map { $0 == k }), "s", 1))
        }
        r.metrics += c.locomotionMetrics()

        r.blocks.append(c.trajectoryBlock())
        let colors: [ColorKey] = [.series1, .series2, .series3]
        r.blocks.append(ReportBlock(title: L10n.tr("各臂进入次数"), caption: nil, kind: .bars(BarData(items: (0..<3).map { k in
            BarItem(label: L10n.tr("臂 \(m.labels[k])"), value: Double(entries.filter { $0.arm == k }.count), color: colors[k]) }, unit: L10n.tr("次"), decimals: 0))))
        if !entries.isEmpty {
            let s0 = tb.windowStartTime
            let rows = entries.prefix(80).enumerated().map { (k, e) -> [String] in
                [String(k + 1), String(format: "%.1f", e.time - s0), m.labels[e.arm], altFlags[k] ? "✓" : ""]
            }
            r.blocks.append(ReportBlock(title: L10n.tr("进臂序列"), caption: L10n.tr("✓ = 与前两次构成一次交替") + (entries.count > 80 ? L10n.tr("；仅显示前 80 次") : ""),
                                        kind: .table(TableData(columns: ["#", L10n.tr("时间 (s)"), L10n.tr("臂"), L10n.tr("交替")], rows: rows, rowColors: altFlags.prefix(80).map { $0 ? .accent : nil }))))
        }
        let tracks = (0..<3).map { k in TimelineTrack(name: L10n.tr("臂 \(m.labels[k])"), color: colors[k], bouts: Bouts.find(state.map { $0 == k }, tb)) }
        r.blocks.append(ReportBlock(title: L10n.tr("进臂时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("arm_index", state.map { Double($0) })]
        r.methods.append(entryRuleText(p.entryRule) + L10n.tr("连续三次进入三条不同的臂记为一次交替。"))
        return r
    }

    static func entryRuleText(_ rule: String) -> String {
        switch rule {
        case "full": return L10n.tr("进入臂的判定为身体中心和尾根都在臂内（近似四爪进入），身体中心离开即为退出；")
        case "nose": return L10n.tr("进入臂的判定为鼻尖进入臂内；")
        default: return L10n.tr("进入臂按身体中心判断；")
        }
    }

    // MARK: T-maze VTE

    struct Pass {
        var from: Int
        var to: Int
        var i0: Int
        var i1: Int
        var t0: Double
        var t1: Double
        var idPhiHead: Double = 0
        var idPhiPath: Double = 0
        var z: Double?
    }

    static func tMaze(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let m = MazeGeometry.from(c.session.calibration, mapping: c.fs.mapping), m.ends.count == 3,
              let choice = c.zone("choice") else {
            r.warnings.append(L10n.tr("需要 T 迷宫标定（J、S、L、R）。"))
            return r
        }
        // 0 = start arm, 1 = left, 2 = right, 3 = choice zone, −1 = unknown.
        var loc = [Int](repeating: -1, count: c.n)
        var last = -1
        for i in 0..<c.n {
            if let q = a.pos(.bodyCenter, i) {
                if choice.contains(q) { last = 3 } else if let k = m.armIndex(q, tolerance: 1.3) { last = k }
            }
            loc[i] = last
        }
        var passes: [Pass] = []
        var lastArm = -1
        var enter: Int?
        for i in 0..<c.n where tb.inWindow[i] {
            let l = loc[i]
            if l == 3 {
                if enter == nil { enter = i }
            } else if l >= 0 {
                if let e = enter, lastArm >= 0 {
                    passes.append(Pass(from: lastArm, to: l, i0: e, i1: i, t0: tb.t[e], t1: tb.t[i]))
                }
                enter = nil
                lastArm = l
            }
        }
        // IdPhi for trials (start arm → left/right).
        var trials = passes.filter { $0.from == 0 && ($0.to == 1 || $0.to == 2) }
        for k in trials.indices {
            var sumH = 0.0, sumP = 0.0
            var lastH: Double?, lastHeading: Double?
            var lastPos: V2?
            for i in trials[k].i0...trials[k].i1 {
                if a.hdU[i].isFinite {
                    if let h = lastH { sumH += abs(a.hdU[i] - h) }
                    lastH = a.hdU[i]
                }
                if let q = a.pos(.bodyCenter, i) {
                    if let lp = lastPos, q.distance(to: lp) > 0.05 {
                        let heading = (q - lp).screenAngleDeg
                        if let lh = lastHeading { sumP += Angle.diff(heading, lh) }
                        lastHeading = heading
                        lastPos = q
                    } else if lastPos == nil {
                        lastPos = q
                    }
                }
            }
            trials[k].idPhiHead = sumH
            trials[k].idPhiPath = sumP
        }
        let ids = trials.map { $0.idPhiHead }
        if ids.count >= 3, let mean = ids.finiteMean {
            let sd = (ids.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(ids.count - 1)).squareRoot()
            for k in trials.indices { trials[k].z = sd > 1e-9 ? (trials[k].idPhiHead - mean) / sd : 0 }
        }
        let vte = trials.filter { ($0.z ?? -.infinity) >= p.vteZ }
        var alternations = 0
        if trials.count >= 2 { for k in 1..<trials.count where trials[k].to != trials[k - 1].to { alternations += 1 } }
        let left = trials.filter { $0.to == 1 }.count

        r.metrics = [
            c.m("vte_pct", L10n.tr("VTE 比例"), trials.count >= 3 ? Double(vte.count) / Double(trials.count) * 100 : nil, "%", 1, info: L10n.tr("zIdPhi ≥ \(AnalysisContext.num(p.vteZ))；至少 3 次选择才计算")),
            c.m("trials", L10n.tr("选择次数"), Double(trials.count), "", 0),
            c.m("vte_count", L10n.tr("VTE 次数"), Double(vte.count), "", 0),
            c.m("idphi_mean", L10n.tr("IdPhi 均值（头朝向）"), ids.finiteMean, "°", 0),
            c.m("idphi_path_mean", L10n.tr("IdPhi 均值（轨迹）"), trials.map { $0.idPhiPath }.finiteMean, "°", 0),
            c.m("left_pct", L10n.tr("选左比例"), trials.isEmpty ? nil : Double(left) / Double(trials.count) * 100, "%", 1),
            c.m("alternation_pct", L10n.tr("交替率"), trials.count >= 2 ? Double(alternations) / Double(trials.count - 1) * 100 : nil, "%", 1),
            c.m("choice_time", L10n.tr("选择点平均停留"), trials.map { $0.t1 - $0.t0 }.finiteMean, "s", 2)
        ] + c.locomotionMetrics()

        let s0 = tb.windowStartTime
        if !trials.isEmpty {
            let rows = trials.prefix(80).enumerated().map { (k, t) -> [String] in
                [String(k + 1), String(format: "%.1f", t.t0 - s0), t.to == 1 ? L10n.tr("左") : L10n.tr("右"), String(format: "%.2f", t.t1 - t.t0),
                 String(format: "%.0f", t.idPhiHead), String(format: "%.0f", t.idPhiPath), t.z.map { String(format: "%.2f", $0) } ?? "—",
                 (t.z ?? -.infinity) >= p.vteZ ? "VTE" : ""]
            }
            r.blocks.append(ReportBlock(title: L10n.tr("每次选择"), caption: L10n.tr("IdPhi = 通过选择点期间朝向变化绝对值之和"),
                                        kind: .table(TableData(columns: ["#", L10n.tr("时间"), L10n.tr("选择"), L10n.tr("停留 s"), L10n.tr("IdPhi 头"), L10n.tr("IdPhi 轨迹"), "z", ""], rows: rows,
                                                               rowColors: trials.prefix(80).map { ($0.z ?? -.infinity) >= p.vteZ ? .warning : nil }))))
            r.blocks.append(ReportBlock(title: L10n.tr("IdPhi（头朝向）"), caption: L10n.tr("橙色 = VTE"), kind: .bars(BarData(items: trials.enumerated().map { (k, t) in
                BarItem(label: "\(k + 1)", value: t.idPhiHead, color: (t.z ?? -.infinity) >= p.vteZ ? .warning : .accent) }, unit: "°", decimals: 0))))
        }
        var paths: [PlotPath] = [PlotPath(color: .neutral, segments: c.segments(), width: 0.8, opacity: 0.35)]
        for t in trials {
            let seg = c.segments(.nose, from: t.t0, to: t.t1)
            paths.append(PlotPath(color: (t.z ?? -.infinity) >= p.vteZ ? .warning : .accent, segments: seg, width: 1.6, opacity: 0.9))
        }
        r.blocks.append(ReportBlock(title: L10n.tr("选择点鼻尖轨迹"), caption: L10n.tr("橙色 = VTE 选择，蓝色 = 其他"), kind: .arena(c.arenaPlot(paths: paths))))
        let vteBouts = vte.map { Bout(start: $0.t0, end: $0.t1, i0: $0.i0, i1: $0.i1) }
        let otherBouts = trials.filter { ($0.z ?? -.infinity) < p.vteZ }.map { Bout(start: $0.t0, end: $0.t1, i0: $0.i0, i1: $0.i1) }
        let tracks = [TimelineTrack(name: "VTE", color: .warning, bouts: vteBouts), TimelineTrack(name: L10n.tr("其他选择"), color: .accent, bouts: otherBouts)]
        r.blocks.append(ReportBlock(title: L10n.tr("选择时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("maze_location", loc.map { Double($0) })]
        r.methods.append(L10n.tr("每次从起始臂经过选择点（半径 \(AnalysisContext.num(m.armWidth * max(0.5, p.choiceRadiusFactor))) cm）进入左 / 右臂记为一次选择；IdPhi 为期间头朝向变化绝对值之和，在会话内 z 标准化，zIdPhi ≥ \(AnalysisContext.num(p.vteZ)) 记为 VTE。"))
        if trials.count < 3 { r.warnings.append(L10n.tr("选择次数少于 3 次，无法做会话内 z 标准化。")) }
        return r
    }

    // MARK: Fear conditioning

    static func fear(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let freeze = c.freezingMask()
        let bouts = Bouts.find(freeze, tb)
        let win = tb.windowDuration
        let fTime = tb.total(freeze)
        let onsets = p.csOnsets.sorted()
        let cs = onsets.map { ($0, $0 + p.csDuration) }
        let epochs = cs.enumerated().map { Epoch(name: "CS\($0.offset + 1)", start: $0.element.0, end: $0.element.1) }

        func pct(_ a: Double, _ b: Double) -> Double? {
            let w = c.windowTime(from: a, to: b)
            return w > 0 ? c.total(freeze, from: a, to: b) / w * 100 : nil
        }

        r.metrics = [c.m("freeze_total_pct", L10n.tr("僵直比例（全程）"), c.percent(fTime, win), "%", 1)]
        if !cs.isEmpty {
            let perCS = cs.map { pct($0.0, $0.1) }
            let valid = perCS.compactMap { $0 }
            r.metrics.insert(c.m("freeze_cs_mean", L10n.tr("CS 期间僵直"), valid.finiteMean, "%", 1, info: L10n.tr("所有 CS 的平均")), at: 0)
            r.metrics.append(c.m("freeze_baseline_pct", L10n.tr("基线僵直"), pct(tb.windowStartTime, onsets[0]), "%", 1, info: L10n.tr("首个 CS 之前")))
            // Inter-CS intervals (after the first CS onset, outside CS).
            var iti = [Bool](repeating: false, count: c.n)
            for i in 0..<c.n where tb.t[i] >= onsets[0] { iti[i] = !cs.contains { tb.t[i] >= $0.0 && tb.t[i] < $0.1 } }
            let itiTime = tb.total(iti)
            r.metrics.append(c.m("freeze_iti_pct", L10n.tr("CS 间隔僵直"), itiTime > 0 ? tb.total(AnalysisContext.and(iti, freeze)) / itiTime * 100 : nil, "%", 1))
            for (k, v) in perCS.enumerated().prefix(20) {
                r.metrics.append(c.m("freeze_cs\(k + 1)", L10n.tr("CS\(k + 1) 僵直"), v, "%", 1))
            }
            r.primaryKey = "freeze_cs_mean"
            var items = [BarItem(label: L10n.tr("基线"), value: pct(tb.windowStartTime, onsets[0]) ?? 0, color: .neutral)]
            items += perCS.enumerated().map { BarItem(label: "CS\($0.offset + 1)", value: $0.element ?? 0, color: .freezing) }
            r.blocks.append(ReportBlock(title: L10n.tr("各 CS 僵直比例"), caption: L10n.tr("CS 时长 \(AnalysisContext.num(p.csDuration)) s"), kind: .bars(BarData(items: items, unit: "%"))))
        } else {
            r.primaryKey = "freeze_total_pct"
            r.warnings.append(L10n.tr("没有输入 CS 时间：只计算全程僵直。可在“标定与参数”中添加 CS 开始时间。"))
        }
        r.metrics += [
            c.m("freeze_time", L10n.tr("僵直总时间"), fTime, "s", 1),
            c.m("freeze_bouts", L10n.tr("僵直次数"), Double(bouts.count), "", 0),
            c.m("freeze_bout_mean", L10n.tr("平均僵直时长"), bouts.map { $0.duration }.finiteMean, "s", 1)
        ] + c.locomotionMetrics()

        // Per-bin freezing curve.
        let bins = c.timeBins(p.timeBin)
        let s0 = tb.windowStartTime
        let pts = bins.map { LinePoint(x: (($0.0 + $0.1) / 2 - s0) / 60, y: pct($0.0, $0.1) ?? 0) }
        let shifted = epochs.map { Epoch(name: $0.name, start: ($0.start - s0) / 60, end: ($0.end - s0) / 60, color: $0.color) }
        r.blocks.append(ReportBlock(title: L10n.tr("僵直时间曲线"), caption: L10n.tr("每 \(AnalysisContext.durationText(p.timeBin)) 一个点；阴影为 CS"), kind: .line(LineData(series: [LineSeries(name: L10n.tr("僵直"), color: .freezing, points: pts)], xLabel: "min", yLabel: "%", yRange: 0...100, epochs: shifted))))
        let tracks = [TimelineTrack(name: L10n.tr("僵直"), color: .freezing, bouts: bouts)]
        r.blocks.insert(ReportBlock(title: L10n.tr("僵直时间轴"), caption: L10n.tr("阴影为 CS 期间"), kind: .timeline(c.timeline(tracks, epochs: epochs))), at: 0)
        r.blocks.append(c.trajectoryBlock(L10n.tr("僵直位置"), caption: L10n.tr("点为僵直时的身体位置"), dots: c.dots(.bodyCenter, where: freeze, color: .freezing, maxDots: 800, radius: 1.8)))
        r.reviewTracks = tracks
        r.reviewEpochs = epochs
        r.frameColumns = [("freezing", AnalysisContext.flag(freeze)), ("motion_index", c.a0.motion)]
        r.methods.append(L10n.tr("僵直定义为鼻尖、两耳中点、身体中心和尾根在 0.5 s 窗口内的平均位移速度 < \(AnalysisContext.num(p.freezeSpeed)) cm/s，且持续 ≥ \(AnalysisContext.num(p.freezeMin)) s。"))
        return r
    }

    // MARK: Looming

    static func looming(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let shelter = c.zone("shelter") else {
            r.warnings.append(L10n.tr("请在标定页把 S 手柄放到巢穴中心。"))
            r.metrics = c.locomotionMetrics()
            return r
        }
        let inShelter = c.mask(.bodyCenter, in: shelter)
        let freeze = c.freezingMask()
        let onsets = p.stimOnsets.sorted().filter { t in tb.t.first.map { t >= $0 } ?? false && tb.t.last.map { t <= $0 } ?? false }
        if p.stimOnsets.isEmpty {
            r.warnings.append(L10n.tr("请在参数中输入每次 looming 刺激出现的时间（相对于视频开头，秒）。"))
        }

        struct Trial {
            var onset: Double
            var category: String
            var latency: Double?
            var toShelter: Double?
            var peak: Double?
            var freeze: Double
            var headAngle: Double?
            var distance: Double?
        }
        var trials: [Trial] = []
        for t0 in onsets {
            let i0 = tb.index(atOrAfter: t0)
            guard i0 < c.n else { continue }
            let base = c.values(a.speed, onlyWhere: (0..<c.n).map { tb.t[$0] >= t0 - p.baselineWindow && tb.t[$0] < t0 }).finiteMean ?? 0
            let thr = max(p.flightFactor * base, p.flightMinSpeed)
            let range = tb.indices(from: t0, to: t0 + p.escapeWindow)
            var latency: Double?, toShelter: Double?, peak: Double?
            var fr = 0.0
            for i in range {
                let v = a.speed[i]
                if v.isFinite {
                    peak = max(peak ?? 0, v)
                    if latency == nil && v > thr { latency = tb.t[i] - t0 }
                }
                if toShelter == nil && inShelter[i] { toShelter = tb.t[i] - t0 }
                if freeze[i] { fr += tb.dur[i] }
            }
            var angle: Double?
            var dist: Double?
            if let base = a.headBase(i0), let nose = a.pos(.nose, i0) {
                let h = nose - base, to = shelter.center - base
                if h.length > 1e-6 && to.length > 1e-6 { angle = Angle.diff(h.screenAngleDeg, to.screenAngleDeg) }
            }
            if let b = a.pos(.bodyCenter, i0), case .circle(let cc, let rr) = shelter.shape { dist = max(0, b.distance(to: cc) - rr) }
            let category: String
            if inShelter[i0] { category = L10n.tr("已在巢内") }
            else if latency != nil && toShelter != nil { category = L10n.tr("逃跑") }
            else if fr >= 1 { category = L10n.tr("僵直") }
            else { category = L10n.tr("无反应") }
            trials.append(Trial(onset: t0, category: category, latency: latency, toShelter: toShelter, peak: peak, freeze: fr, headAngle: angle, distance: dist))
        }
        let eligible = trials.filter { $0.category != L10n.tr("已在巢内") }
        let escapes = eligible.filter { $0.category == L10n.tr("逃跑") }
        r.metrics = [
            c.m("escape_pct", L10n.tr("逃跑概率"), eligible.isEmpty ? nil : Double(escapes.count) / Double(eligible.count) * 100, "%", 0, info: L10n.tr("不含刺激时已在巢内的试次")),
            c.m("trials", L10n.tr("刺激次数"), Double(trials.count), "", 0),
            c.m("reaction_latency", L10n.tr("反应潜伏期"), escapes.compactMap { $0.latency }.finiteMean, "s", 2),
            c.m("time_to_shelter", L10n.tr("回巢时间"), escapes.compactMap { $0.toShelter }.finiteMean, "s", 2),
            c.m("freeze_trial_pct", L10n.tr("僵直试次比例"), eligible.isEmpty ? nil : Double(eligible.filter { $0.category == L10n.tr("僵直") }.count) / Double(eligible.count) * 100, "%", 0),
            c.m("peak_speed", L10n.tr("峰值速度"), eligible.compactMap { $0.peak }.finiteMean, c.u + "/s", 1),
            c.m("onset_head_angle", L10n.tr("刺激时头–巢夹角"), eligible.compactMap { $0.headAngle }.finiteMean, "°", 0),
            c.m("onset_distance", L10n.tr("刺激时距巢"), eligible.compactMap { $0.distance }.finiteMean, c.u, 1),
            c.m("shelter_pct", L10n.tr("巢内时间"), c.percent(tb.total(inShelter), tb.windowDuration), "%", 1)
        ] + c.locomotionMetrics()

        if !trials.isEmpty {
            let rows = trials.enumerated().map { (k, t) -> [String] in
                [String(k + 1), String(format: "%.1f", t.onset), t.category,
                 t.latency.map { String(format: "%.2f", $0) } ?? "—", t.toShelter.map { String(format: "%.2f", $0) } ?? "—",
                 t.peak.map { String(format: "%.0f", $0) } ?? "—", String(format: "%.1f", t.freeze), t.headAngle.map { String(format: "%.0f°", $0) } ?? "—"]
            }
            r.blocks.append(ReportBlock(title: L10n.tr("每次刺激"), caption: L10n.tr("时间为视频时间（s）"), kind: .table(TableData(
                columns: ["#", L10n.tr("刺激"), L10n.tr("反应"), L10n.tr("潜伏期"), L10n.tr("回巢"), L10n.tr("峰速"), L10n.tr("僵直 s"), L10n.tr("头–巢")], rows: rows,
                rowColors: trials.map { $0.category == L10n.tr("逃跑") ? .escape : ($0.category == L10n.tr("僵直") ? .freezing : nil) }))))
            // Speed traces aligned to onset.
            let palette: [ColorKey] = [.series1, .series2, .series3, .series4, .accent, .escape]
            var series: [LineSeries] = []
            for (k, t) in trials.prefix(12).enumerated() {
                let rr = tb.indices(from: t.onset - p.baselineWindow, to: t.onset + p.escapeWindow)
                let pts = rr.compactMap { i -> LinePoint? in a.speed[i].isFinite ? LinePoint(x: tb.t[i] - t.onset, y: a.speed[i]) : nil }
                let st = max(1, pts.count / 300)
                series.append(LineSeries(name: "#\(k + 1)", color: palette[k % palette.count], points: stride(from: 0, to: pts.count, by: st).map { pts[$0] }))
            }
            r.blocks.append(ReportBlock(title: L10n.tr("刺激前后速度"), caption: L10n.tr("0 = 刺激出现"), kind: .line(LineData(series: series, xLabel: "s", yLabel: c.u + "/s", referenceY: p.flightMinSpeed, referenceX: 0))))
            let cats = [L10n.tr("逃跑"), L10n.tr("僵直"), L10n.tr("无反应"), L10n.tr("已在巢内")]
            let catColors: [ColorKey] = [.escape, .freezing, .neutral, .shelter]
            r.blocks.append(ReportBlock(title: L10n.tr("反应类型"), caption: nil, kind: .bars(BarData(items: cats.enumerated().map { (k, name) in
                BarItem(label: name, value: Double(trials.filter { $0.category == name }.count), color: catColors[k]) }, unit: L10n.tr("次"), decimals: 0))))
            var paths: [PlotPath] = [PlotPath(color: .neutral, segments: c.segments(), width: 0.7, opacity: 0.3)]
            var arrows: [PlotArrow] = []
            for (k, t) in trials.enumerated() {
                paths.append(PlotPath(color: palette[k % palette.count], segments: c.segments(from: t.onset, to: t.onset + p.escapeWindow), width: 1.6, opacity: 0.95))
                let i0 = tb.index(atOrAfter: t.onset)
                if i0 < c.n, let b = a.headBase(i0), a.hd[i0].isFinite {
                    let rad = a.hd[i0] * Double.pi / 180
                    arrows.append(PlotArrow(from: b, to: b + V2(cos(rad), -sin(rad)) * 5, color: palette[k % palette.count]))
                }
            }
            r.blocks.append(ReportBlock(title: L10n.tr("刺激后轨迹"), caption: L10n.tr("每次刺激后 \(AnalysisContext.num(p.escapeWindow)) s 的轨迹；箭头为刺激时的头朝向"), kind: .arena(c.arenaPlot(paths: paths, arrows: arrows))))
        }
        let epochs = onsets.enumerated().map { Epoch(name: "L\($0.offset + 1)", start: $0.element, end: $0.element + 0.5, color: .warning) }
        let tracks = [TimelineTrack(name: L10n.tr("巢内"), color: .shelter, bouts: Bouts.find(inShelter, tb)), TimelineTrack(name: L10n.tr("僵直"), color: .freezing, bouts: Bouts.find(freeze, tb))]
        r.blocks.append(ReportBlock(title: L10n.tr("时间轴"), caption: L10n.tr("竖条为刺激时间"), kind: .timeline(c.timeline(tracks, epochs: epochs))))
        r.reviewTracks = tracks
        r.reviewEpochs = epochs
        r.frameColumns = [("in_shelter", AnalysisContext.flag(inShelter)), ("freezing", AnalysisContext.flag(freeze))]
        r.methods.append(L10n.tr("反应定义为刺激后速度首次超过 max(\(AnalysisContext.num(p.flightFactor)) × 刺激前 \(AnalysisContext.num(p.baselineWindow)) s 平均速度, \(AnalysisContext.num(p.flightMinSpeed)) cm/s)；有反应且 \(AnalysisContext.num(p.escapeWindow)) s 内回到巢穴记为逃跑（参考 Yilmaz & Meister, 2013）。"))
        return r
    }
}
