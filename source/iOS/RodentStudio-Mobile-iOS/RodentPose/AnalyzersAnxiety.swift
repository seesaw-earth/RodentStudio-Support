// AnalyzersAnxiety.swift — elevated plus maze (with head dips and stretched-attend posture)
// and light–dark box (with risk-assessment pokes).

import Foundation

enum AnxietyAnalyzers {

    // MARK: Elevated plus maze

    static func epm(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let m = MazeGeometry.from(c.session.calibration, mapping: c.fs.mapping), m.ends.count == 4 else {
            r.warnings.append(L10n.tr("需要十字迷宫标定（C、N、E、S、W 五个点）。"))
            return r
        }
        let open = ZoneBuilder.openArmIndices(p)
        let centerPoly = ZoneBuilder.plusCenter(m)
        let armNames = ["N", "E", "S", "W"]

        /// 0…3 = arm, 4 = center, nil = off the maze.
        func location(_ q: V2?) -> Int? {
            guard let q else { return nil }
            if polygonContains(centerPoly, q) { return 4 }
            return m.armIndex(q, tolerance: 1.2)
        }

        // Arm state with entry / exit hysteresis.
        let full = p.entryRule == "full"
        var state = [Int](repeating: 4, count: c.n)
        var cur = 4
        var lastBody: Int? = nil
        var bodyLoc = [Int?](repeating: nil, count: c.n)
        for i in 0..<c.n {
            let bl = location(a.pos(.bodyCenter, i))
            if let bl { lastBody = bl }
            bodyLoc[i] = bl ?? lastBody
            let b = bodyLoc[i]
            if full {
                let tl = location(a.pos(.tailBase, i))
                if cur < 4 {
                    if let b, b != cur {
                        if b < 4, tl == b { cur = b } else { cur = 4 }
                    }
                } else if let b, b < 4, tl == b {
                    cur = b
                }
            } else if let b {
                cur = b
            }
            state[i] = cur
        }
        let inOpen = state.map { open.contains($0) }
        let inClosed = state.map { $0 < 4 && !open.contains($0) }
        let inCenter = state.map { $0 == 4 }
        let tOpen = tb.total(inOpen), tClosed = tb.total(inClosed), tCenter = tb.total(inCenter)

        var openEntries = 0, closedEntries = 0
        var prev: Int?
        for i in 0..<c.n where tb.inWindow[i] {
            let s = state[i]
            if let pv = prev, pv != s, s < 4 {
                if open.contains(s) { openEntries += 1 } else { closedEntries += 1 }
            }
            prev = s
        }

        // Head dips: nose beyond the open-arm edge while the body is on the maze (center or open arm).
        let reach = m.armWidth / 2 + p.headDipReach
        var dipRaw = [Bool](repeating: false, count: c.n)
        for i in 0..<c.n {
            guard let nose = a.pos(.nose, i) else { continue }
            if polygonContains(centerPoly, nose) { continue }
            if m.armIndex(nose, tolerance: 1.06) != nil { continue }
            guard m.distanceToArms(nose, arms: Array(open)) <= reach else { continue }
            let s = state[i]
            guard s == 4 || open.contains(s) else { continue }
            dipRaw[i] = true
        }
        let dips = Bouts.find(dipRaw, tb, minDuration: p.headDipMin, mergeGap: 0.15)
        let protectedDips = dips.filter { !open.contains(state[$0.i0]) }
        let dipMask = Bouts.mask(dips, count: c.n)

        // Stretched-attend posture: elongated body, slow body center.
        let l0 = c.values(a.bodyLength).finiteMedian ?? .nan
        let elong = a.bodyLength.map { l0 > 0 ? $0 / l0 : .nan }
        var sapRaw = [Bool](repeating: false, count: c.n)
        for i in 0..<c.n where elong[i].isFinite && a.speed[i].isFinite {
            sapRaw[i] = elong[i] >= p.sapElongation && a.speed[i] < p.sapSpeed
        }
        let saps = Bouts.find(sapRaw, tb, minDuration: p.sapMin, mergeGap: 0.15)
        let sapMask = Bouts.mask(saps, count: c.n)

        let armsTotal = tOpen + tClosed
        let entriesTotal = openEntries + closedEntries
        r.metrics = [
            c.m("open_time_pct", L10n.tr("开放臂时间"), c.percent(tOpen, armsTotal), "%", 1, info: L10n.tr("开放臂 ÷（开放臂 + 闭合臂）")),
            c.m("open_entries_pct", L10n.tr("开放臂进入"), c.percent(Double(openEntries), Double(entriesTotal)), "%", 1),
            c.m("open_time", L10n.tr("开放臂时间"), tOpen, "s", 1),
            c.m("closed_time", L10n.tr("闭合臂时间"), tClosed, "s", 1),
            c.m("center_time", L10n.tr("中央区时间"), tCenter, "s", 1),
            c.m("open_entries", L10n.tr("开放臂进入次数"), Double(openEntries), "", 0),
            c.m("closed_entries", L10n.tr("闭合臂进入次数"), Double(closedEntries), "", 0),
            c.m("open_latency", L10n.tr("首次进入开放臂"), tb.firstTime(inOpen), "s", 1),
            c.m("head_dips", L10n.tr("探头次数"), Double(dips.count), "", 0),
            c.m("head_dips_protected", L10n.tr("受保护探头"), Double(protectedDips.count), "", 0, info: L10n.tr("探头时身体在中央区或闭合臂")),
            c.m("head_dips_unprotected", L10n.tr("非保护探头"), Double(dips.count - protectedDips.count), "", 0),
            c.m("head_dip_time", L10n.tr("探头时间"), dips.reduce(0) { $0 + $1.duration }, "s", 1),
            c.m("sap_count", L10n.tr("伸展评估姿势"), Double(saps.count), L10n.tr("次"), 0),
            c.m("sap_time", L10n.tr("SAP 时间"), saps.reduce(0) { $0 + $1.duration }, "s", 1)
        ] + c.locomotionMetrics()

        let dipDots = c.dots(.nose, where: dipMask, color: .headDip, radius: 1.6)
        let sapDots = c.dots(.bodyCenter, where: sapMask, color: .sap, radius: 1.4)
        r.blocks.append(c.trajectoryBlock(caption: L10n.tr("红点 = 探头时鼻尖位置；紫点 = 伸展评估姿势"), dots: dipDots + sapDots))
        r.blocks.append(ReportBlock(title: L10n.tr("各区时间"), caption: nil, kind: .bars(BarData(items: [
            BarItem(label: L10n.tr("开放臂"), value: tOpen, color: .open), BarItem(label: L10n.tr("中央"), value: tCenter, color: .neutral),
            BarItem(label: L10n.tr("闭合臂"), value: tClosed, color: .closed)], unit: "s"))))
        var armItems: [BarItem] = []
        for k in 0..<4 {
            let t = tb.total(state.map { $0 == k })
            armItems.append(BarItem(label: (open.contains(k) ? L10n.tr("开 ") : L10n.tr("闭 ")) + armNames[k], value: t, color: open.contains(k) ? .open : .closed))
        }
        r.blocks.append(ReportBlock(title: L10n.tr("各臂时间"), caption: L10n.tr("N / E / S / W 为标定时的四个臂末端"), kind: .bars(BarData(items: armItems, unit: "s"))))
        let tracks = [
            TimelineTrack(name: L10n.tr("开放臂"), color: .open, bouts: Bouts.find(inOpen, tb)),
            TimelineTrack(name: L10n.tr("闭合臂"), color: .closed, bouts: Bouts.find(inClosed, tb)),
            TimelineTrack(name: L10n.tr("探头"), color: .headDip, bouts: dips),
            TimelineTrack(name: "SAP", color: .sap, bouts: saps)
        ]
        r.blocks.append(ReportBlock(title: L10n.tr("时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [
            ("in_open_arm", AnalysisContext.flag(inOpen)), ("in_closed_arm", AnalysisContext.flag(inClosed)),
            ("in_center", AnalysisContext.flag(inCenter)), ("head_dip", AnalysisContext.flag(dipMask)),
            ("stretched_attend", AnalysisContext.flag(sapMask)), ("elongation", elong)
        ]
        r.methods.append(full
            ? L10n.tr("进入臂的判定为身体中心和尾根都在同一臂内（近似四爪进入），身体中心离开该臂即为退出。")
            : L10n.tr("臂的归属按身体中心判断。"))
        r.methods.append(L10n.tr("探头：鼻尖越出开放臂边缘（距臂轴 ≤ \(AnalysisContext.num(reach)) cm）而身体仍在中央区或开放臂，持续 ≥ \(AnalysisContext.num(p.headDipMin)) s；伸展评估姿势：鼻尖–尾根长度 ≥ 中位数 × \(AnalysisContext.num(p.sapElongation)) 且身体中心速度 < \(AnalysisContext.num(p.sapSpeed)) cm/s，持续 ≥ \(AnalysisContext.num(p.sapMin)) s。"))
        if dips.isEmpty && (c.quality().keypointRates.first ?? 1) < 0.7 {
            r.warnings.append(L10n.tr("鼻尖有效帧较少，探头可能漏检（探头时鼻尖常伸出画面或被遮挡）。"))
        }
        return r
    }

    // MARK: Light–dark box

    static func lightDark(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        let a = c.a0
        guard let light = c.zone("light"), let dark = c.zone("dark") else {
            r.warnings.append(L10n.tr("需要矩形场地标定。"))
            return r
        }
        let inLight = c.mask(.bodyCenter, in: light)
        let inDark = AnalysisContext.not(inLight)
        var pokeRaw = [Bool](repeating: false, count: c.n)
        for i in 0..<c.n {
            guard let nose = a.pos(.nose, i), light.contains(nose), let body = a.pos(.bodyCenter, i), dark.contains(body) else { continue }
            if let tail = a.pos(.tailBase, i), !dark.contains(tail) { continue }
            pokeRaw[i] = true
        }
        let pokes = Bouts.find(pokeRaw, tb, minDuration: p.pokeMin, mergeGap: 0.15)
        let pokeMask = Bouts.mask(pokes, count: c.n)
        let tLight = tb.total(inLight)
        let lightEntries = Bouts.entries(inLight, tb)
        let darkEntries = Bouts.entries(inDark, tb)

        r.metrics = [
            c.m("light_pct", L10n.tr("明箱时间"), c.percent(tLight, tb.windowDuration), "%", 1),
            c.m("light_time", L10n.tr("明箱时间"), tLight, "s", 1),
            c.m("transitions", L10n.tr("穿梭次数"), Double(lightEntries + darkEntries), "", 0),
            c.m("light_entries", L10n.tr("进入明箱"), Double(lightEntries), "", 0),
            c.m("light_latency", L10n.tr("首次进入明箱"), tb.firstTime(inLight), "s", 1),
            c.m("dark_latency", L10n.tr("首次进入暗箱"), tb.firstTime(inDark), "s", 1),
            c.m("pokes", L10n.tr("探头次数"), Double(pokes.count), "", 0, info: L10n.tr("鼻尖在明箱、身体和尾根在暗箱")),
            c.m("poke_time", L10n.tr("探头时间"), pokes.reduce(0) { $0 + $1.duration }, "s", 1),
            c.m("light_distance_pct", L10n.tr("明箱路程占比"), c.percent(c.distance(onlyWhere: inLight), c.distance()), "%", 1)
        ] + c.locomotionMetrics()

        r.blocks.append(c.trajectoryBlock(caption: L10n.tr("红点 = 探头时鼻尖位置"), dots: c.dots(.nose, where: pokeMask, color: .headDip, radius: 1.8)))
        r.blocks.append(ReportBlock(title: L10n.tr("明暗箱时间"), caption: nil, kind: .bars(BarData(items: [
            BarItem(label: L10n.tr("明箱"), value: tLight, color: .light), BarItem(label: L10n.tr("暗箱"), value: tb.total(inDark), color: .dark)], unit: "s"))))
        let tracks = [TimelineTrack(name: L10n.tr("明箱"), color: .light, bouts: Bouts.find(inLight, tb)),
                      TimelineTrack(name: L10n.tr("探头"), color: .headDip, bouts: pokes)]
        r.blocks.append(ReportBlock(title: L10n.tr("时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("in_light", AnalysisContext.flag(inLight)), ("risk_poke", AnalysisContext.flag(pokeMask))]
        r.methods.append(L10n.tr("所在箱按身体中心判断；探头为鼻尖进入明箱而身体中心和尾根仍在暗箱，持续 ≥ \(AnalysisContext.num(p.pokeMin)) s。"))
        return r
    }
}
