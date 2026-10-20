// RodentPose iOS 1.0 scientific algorithm port; only PoseTrack name and localization/zone invocation adapted.
// AnalyzersSocial.swift — three-chamber test, social interaction (CSDS) test, dyadic interaction.

import Foundation

extension AnalysisContext {
    /// Nose within `reach` of a circular target, head pointing at it within the tolerance, and the
    /// body center not on top of the object (climbing).
    func investigationMask(target c: V2, radius r: Double, reach: Double, animal: Int = 0) -> [Bool] {
        let f = fs.animals[animal]
        let tol = p.headTolerance
        return (0..<n).map { i in
            guard let nose = f.pos(.nose, i), nose.distance(to: c) <= r + reach else { return false }
            if let body = f.pos(.bodyCenter, i), body.distance(to: c) < r { return false }
            guard let base = f.headBase(i) else { return false }
            let head = nose - base
            let toTarget = c - base
            guard head.length > 1e-6, toTarget.length > 1e-6 else { return true }
            return RPAngle.diff(head.screenAngleDeg, toTarget.screenAngleDeg) <= tol
        }
    }

    /// Cumulative time of a mask over the window, sampled for a line chart (x in minutes).
    func cumulative(_ mask: [Bool], points: Int = 240) -> [LinePoint] {
        let s = tb.windowStartTime
        var out: [LinePoint] = [LinePoint(x: 0, y: 0)]
        var acc = 0.0
        let idx = (0..<n).filter { tb.inWindow[$0] }
        guard !idx.isEmpty else { return out }
        let step = max(1, idx.count / points)
        for (j, i) in idx.enumerated() {
            if mask[i] { acc += tb.dur[i] }
            if j % step == 0 || j == idx.count - 1 {
                out.append(LinePoint(x: (tb.t[i] + tb.dur[i] - s) / 60, y: acc))
            }
        }
        return out
    }

    func bouts(_ mask: [Bool], minDuration: Double = 0.2, mergeGap: Double = 0.3) -> [Bout] {
        Bouts.find(mask, tb, minDuration: minDuration, mergeGap: mergeGap)
    }
}

/// Distance from a point to a polygon (0 inside).
func polygonDistance(_ poly: [V2], _ p: V2) -> Double {
    if polygonContains(poly, p) { return 0 }
    var d = Double.infinity
    for i in poly.indices {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        d = min(d, pointSegment(p, a, b).distance)
    }
    return d
}

enum SocialAnalyzers {

    // MARK: Three-chamber

    static func threeChamber(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let phase = c.session.phase
        let novelty = phase == "Social novelty"
        let habituation = phase == "Habituation"
        let stimSide = p.stimSide == "R" ? "R" : "L"
        let otherSide = stimSide == "L" ? "R" : "L"

        let stimName = habituation ? (stimSide == "L" ? RPTexts.tr("左杯") : RPTexts.tr("右杯")) : (novelty ? RPTexts.tr("新陌生鼠") : RPTexts.tr("陌生鼠"))
        let otherName = habituation ? (otherSide == "L" ? RPTexts.tr("左杯") : RPTexts.tr("右杯")) : (novelty ? RPTexts.tr("熟悉鼠") : RPTexts.tr("空杯"))
        let stimColor: ColorKey = novelty ? .novel : .social
        let otherColor: ColorKey = novelty ? .familiar : .object

        guard let chL = c.zone("chL"), let chC = c.zone("chC"), let chR = c.zone("chR") else {
            r.warnings.append(RPTexts.tr("需要矩形场地标定。"))
            return r
        }
        let inL = c.mask(.bodyCenter, in: chL)
        let inC = c.mask(.bodyCenter, in: chC)
        let inR = c.mask(.bodyCenter, in: chR)
        let inStim = stimSide == "L" ? inL : inR
        let inOther = stimSide == "L" ? inR : inL

        var sniffStim = [Bool](repeating: false, count: c.n)
        var sniffOther = sniffStim
        var cupMissing = false
        if let cs = c.zone("cup" + stimSide), let co = c.zone("cup" + otherSide) {
            sniffStim = c.investigationMask(target: cs.center, radius: p.cupRadius, reach: p.exploreMargin)
            sniffOther = c.investigationMask(target: co.center, radius: p.cupRadius, reach: p.exploreMargin)
        } else {
            cupMissing = true
            r.warnings.append(RPTexts.tr("未放置杯子位置（L / R 手柄），无法计算嗅探。"))
        }

        let tb = c.tb
        let tS = tb.total(sniffStim), tO = tb.total(sniffOther)
        let cS = tb.total(inStim), cO = tb.total(inOther), cC = tb.total(inC)
        let bS = c.bouts(sniffStim), bO = c.bouts(sniffOther)

        let idxTitle = habituation ? RPTexts.tr("左右偏好指数") : (novelty ? RPTexts.tr("社交新颖性指数") : RPTexts.tr("社交指数"))
        r.metrics = [
            c.m("sniff_index", idxTitle, c.index(tS, tO), "", 2, info: RPTexts.tr("(\(stimName) − \(otherName)) ÷ 总嗅探时间")),
            c.m("sniff_stim", RPTexts.tr("嗅探\(stimName)"), tS, "s", 1),
            c.m("sniff_other", RPTexts.tr("嗅探\(otherName)"), tO, "s", 1),
            c.m("sniff_bouts_stim", RPTexts.tr("\(stimName)嗅探次数"), Double(bS.count), "", 0),
            c.m("sniff_bouts_other", RPTexts.tr("\(otherName)嗅探次数"), Double(bO.count), "", 0),
            c.m("latency_stim", RPTexts.tr("首次嗅探\(stimName)"), tb.firstTime(sniffStim), "s", 1),
            c.m("latency_other", RPTexts.tr("首次嗅探\(otherName)"), tb.firstTime(sniffOther), "s", 1),
            c.m("chamber_index", RPTexts.tr("箱室偏好指数"), c.index(cS, cO), "", 2, info: RPTexts.tr("按身体中心所在箱室的时间")),
            c.m("chamber_stim", RPTexts.tr("\(stimName)侧箱室"), cS, "s", 1),
            c.m("chamber_center", RPTexts.tr("中箱"), cC, "s", 1),
            c.m("chamber_other", RPTexts.tr("\(otherName)侧箱室"), cO, "s", 1),
            c.m("entries_stim", RPTexts.tr("进入\(stimName)侧"), Double(Bouts.entries(inStim, tb)), "", 0),
            c.m("entries_other", RPTexts.tr("进入\(otherName)侧"), Double(Bouts.entries(inOther, tb)), "", 0)
        ] + c.locomotionMetrics()

        let dotsS = c.dots(.nose, where: sniffStim, color: stimColor, radius: 1.8)
        let dotsO = c.dots(.nose, where: sniffOther, color: otherColor, radius: 1.8)
        r.blocks.append(c.trajectoryBlock(caption: RPTexts.tr("彩色点为嗅探时的鼻尖位置；虚线圈为嗅探判定范围"), dots: dotsS + dotsO))
        if !cupMissing {
            r.blocks.append(ReportBlock(title: RPTexts.tr("嗅探时间"), caption: idxTitle + String(format: " = %@", c.index(tS, tO).map { String(format: "%.2f", $0) } ?? "—"),
                                        kind: .bars(BarData(items: [BarItem(label: stimName, value: tS, color: stimColor), BarItem(label: otherName, value: tO, color: otherColor)], unit: "s"))))
            r.blocks.append(ReportBlock(title: RPTexts.tr("累计嗅探时间"), caption: RPTexts.tr("横轴为分析起点后的分钟数"),
                                        kind: .line(LineData(series: [LineSeries(name: stimName, color: stimColor, points: c.cumulative(sniffStim)),
                                                                      LineSeries(name: otherName, color: otherColor, points: c.cumulative(sniffOther))],
                                                             xLabel: "min", yLabel: "s"))))
        }
        let chamberItems = [
            BarItem(label: RPTexts.tr("左箱"), value: tb.total(inL), color: stimSide == "L" ? stimColor : otherColor),
            BarItem(label: RPTexts.tr("中箱"), value: cC, color: .neutral),
            BarItem(label: RPTexts.tr("右箱"), value: tb.total(inR), color: stimSide == "R" ? stimColor : otherColor)
        ]
        r.blocks.append(ReportBlock(title: RPTexts.tr("箱室停留时间"), caption: nil, kind: .bars(BarData(items: chamberItems, unit: "s"))))
        let tracks = [
            TimelineTrack(name: RPTexts.tr("嗅探\(stimName)"), color: stimColor, bouts: bS),
            TimelineTrack(name: RPTexts.tr("嗅探\(otherName)"), color: otherColor, bouts: bO),
            TimelineTrack(name: RPTexts.tr("\(stimName)侧"), color: stimColor, bouts: Bouts.find(inStim, tb)),
            TimelineTrack(name: RPTexts.tr("\(otherName)侧"), color: otherColor, bouts: Bouts.find(inOther, tb))
        ]
        r.blocks.append(ReportBlock(title: RPTexts.tr("行为时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = Array(tracks.prefix(2))

        if !cupMissing && tS + tO < 5 {
            r.warnings.append(RPTexts.tr("两侧嗅探总时间不足 5 s，指数可能不稳定。"))
        }
        r.frameColumns = [
            ("in_chamber_left", AnalysisContext.flag(inL)), ("in_chamber_center", AnalysisContext.flag(inC)),
            ("in_chamber_right", AnalysisContext.flag(inR)),
            ("sniff_" + (stimSide == "L" ? "left" : "right"), AnalysisContext.flag(sniffStim)),
            ("sniff_" + (otherSide == "L" ? "left" : "right"), AnalysisContext.flag(sniffOther))
        ]
        r.methods.append(RPTexts.tr("嗅探定义为鼻尖距杯子外缘 ≤ \(AnalysisContext.num(p.exploreMargin)) cm、头朝向（两耳中点 → 鼻尖）与杯子方向夹角 ≤ \(AnalysisContext.num(p.headTolerance))°，且身体中心不在杯子上；箱室归属按身体中心判断。"))
        return r
    }

    // MARK: Social interaction test (CSDS)

    static func socialInteraction(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        let p = c.p
        let tb = c.tb
        guard let iz = c.zone("iz"), let enc = c.zone("enclosure") else {
            r.warnings.append(RPTexts.tr("需要矩形场地标定。"))
            return r
        }
        let corners = c.zones.filter { $0.role == .corner }
        let inIZ = c.mask(.bodyCenter, in: iz)
        let inCorner = c.mask(.bodyCenter) { q in corners.contains { $0.contains(q) } }

        // Nose investigating the enclosure.
        guard case .polygon(let encPoly) = enc.shape else { return r }
        let encCenter = enc.center
        let a = c.a0
        let sniff: [Bool] = (0..<c.n).map { i in
            guard let nose = a.pos(.nose, i), polygonDistance(encPoly, nose) <= p.exploreMargin else { return false }
            guard let base = a.headBase(i) else { return false }
            let head = nose - base, to = encCenter - base
            guard head.length > 1e-6, to.length > 1e-6 else { return true }
            return RPAngle.diff(head.screenAngleDeg, to.screenAngleDeg) <= p.headTolerance + 30
        }

        let izTime = tb.total(inIZ)
        let cornerTime = tb.total(inCorner)
        r.metrics = [
            c.m("iz_time", RPTexts.tr("互动区时间"), izTime, "s", 1),
            c.m("iz_pct", RPTexts.tr("互动区时间比例"), c.percent(izTime, tb.windowDuration), "%", 1),
            c.m("corner_time", RPTexts.tr("角落区时间"), cornerTime, "s", 1),
            c.m("iz_entries", RPTexts.tr("进入互动区"), Double(Bouts.entries(inIZ, tb)), "", 0),
            c.m("iz_latency", RPTexts.tr("首次进入互动区"), tb.firstTime(inIZ), "s", 1),
            c.m("enclosure_sniff", RPTexts.tr("嗅探网罩"), tb.total(sniff), "s", 1)
        ]

        // Pairing with the other phase of the same animal.
        let isTarget = c.session.phase == "Target"
        if let otherIZ = c.companion["iz_time"] {
            let ratio: Double? = isTarget ? (otherIZ > 0 ? izTime / otherIZ : nil) : (izTime > 0 ? otherIZ / izTime : nil)
            r.metrics.insert(c.m("si_ratio", "SI ratio", ratio, "", 2, info: RPTexts.tr("有目标 ÷ 无目标互动区时间；< 1 常归为易感，≥ 1 为抗逆")), at: 0)
            if let otherCorner = c.companion["corner_time"] {
                let cr: Double? = isTarget ? (otherCorner > 0 ? cornerTime / otherCorner : nil) : (cornerTime > 0 ? otherCorner / cornerTime : nil)
                r.metrics.insert(c.m("corner_ratio", RPTexts.tr("角落 ratio"), cr, "", 2), at: 2)
            }
            r.primaryKey = "si_ratio"
            let noTarget = isTarget ? otherIZ : izTime
            let target = isTarget ? izTime : otherIZ
            r.blocks.append(ReportBlock(title: RPTexts.tr("两阶段互动区时间"), caption: RPTexts.tr("同一编号的无目标 / 有目标两次测试"),
                                        kind: .bars(BarData(items: [BarItem(label: RPTexts.tr("无目标"), value: noTarget, color: .neutral),
                                                                    BarItem(label: RPTexts.tr("有目标"), value: target, color: .social)], unit: "s"))))
        } else {
            r.warnings.append(RPTexts.tr("还没有同一编号的“\(isTarget ? RPTexts.tr("无目标") : RPTexts.tr("有目标"))”阶段结果；分析完另一阶段后会自动计算 SI ratio。"))
        }
        r.metrics += c.locomotionMetrics()

        r.blocks.insert(c.trajectoryBlock(caption: RPTexts.tr("互动区（网罩周围）与对侧两个角落区"), dots: c.dots(.nose, where: sniff, color: .sniff, radius: 1.6)), at: 0)
        r.blocks.append(c.heatBlock())
        let tracks = [
            TimelineTrack(name: RPTexts.tr("互动区"), color: .social, bouts: Bouts.find(inIZ, tb)),
            TimelineTrack(name: RPTexts.tr("角落区"), color: .periphery, bouts: Bouts.find(inCorner, tb)),
            TimelineTrack(name: RPTexts.tr("嗅探网罩"), color: .sniff, bouts: c.bouts(sniff))
        ]
        r.blocks.append(ReportBlock(title: RPTexts.tr("行为时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = tracks
        r.frameColumns = [("in_interaction_zone", AnalysisContext.flag(inIZ)), ("in_corner", AnalysisContext.flag(inCorner)), ("sniff_enclosure", AnalysisContext.flag(sniff))]
        r.methods.append(RPTexts.tr("互动区为网罩周围 \(AnalysisContext.num(p.izWidth)) × \(AnalysisContext.num(p.izDepth)) cm 区域，角落区为对侧 \(AnalysisContext.num(p.cornerSize)) × \(AnalysisContext.num(p.cornerSize)) cm；按身体中心判断（Golden et al., 2011）。"))
        return r
    }

    // MARK: Dyadic interaction

    static func dyadic(_ c: AnalysisContext) -> AnalysisReport {
        var r = AnalysisReport()
        guard c.fs.animals.count >= 2 else {
            r.warnings.append(RPTexts.tr("此会话只识别了一只鼠。请在“信息”中开启双鼠模式后重新识别。"))
            r.metrics = c.locomotionMetrics()
            r.blocks = [c.trajectoryBlock()]
            return r
        }
        let p = c.p
        let tb = c.tb
        let A = c.fs.animals[0], B = c.fs.animals[1]
        let n = c.n
        var nn = [Bool](repeating: false, count: n)
        var agAB = nn, agBA = nn, bodyAB = nn, bodyBA = nn, prox = nn, folAB = nn, folBA = nn
        var dist = [Double](repeating: .nan, count: n)

        func follows(_ f: AnimalFeatures, _ g: AnimalFeatures, _ i: Int) -> Bool {
            guard let pf = f.pos(.bodyCenter, i), let pg = g.pos(.bodyCenter, i) else { return false }
            let v = pg - pf
            guard v.length < p.followDist, v.length > 1e-6 else { return false }
            guard f.speed[i] > p.followSpeed, g.speed[i] > p.followSpeed else { return false }
            let heading = f.hd[i].isFinite ? f.hd[i] : f.body[i]
            guard heading.isFinite, RPAngle.diff(heading, v.screenAngleDeg) <= p.followAngle else { return false }
            // The leader moves away from the follower (follower is behind).
            if g.body[i].isFinite { return RPAngle.diff(g.body[i], v.screenAngleDeg) <= 90 }
            return true
        }

        for i in 0..<n {
            let na = A.pos(.nose, i), nb = B.pos(.nose, i)
            let ta = A.pos(.tailBase, i), tbB = B.pos(.tailBase, i)
            let ba = A.pos(.bodyCenter, i), bb = B.pos(.bodyCenter, i)
            if let na, let nb { nn[i] = na.distance(to: nb) < p.noseNoseDist }
            if let na, let tbB { agAB[i] = na.distance(to: tbB) < p.anogenitalDist }
            if let nb, let ta { agBA[i] = nb.distance(to: ta) < p.anogenitalDist }
            if let na, let bb { bodyAB[i] = na.distance(to: bb) < p.bodySniffDist && !nn[i] && !agAB[i] }
            if let nb, let ba { bodyBA[i] = nb.distance(to: ba) < p.bodySniffDist && !nn[i] && !agBA[i] }
            if let ba, let bb {
                let d = ba.distance(to: bb)
                dist[i] = d
                prox[i] = d < p.proximityDist
            }
            folAB[i] = follows(A, B, i)
            folBA[i] = follows(B, A, i)
        }
        folAB = Bouts.sustained(folAB, tb, minDuration: p.followMin, mergeGap: 0.2)
        folBA = Bouts.sustained(folBA, tb, minDuration: p.followMin, mergeGap: 0.2)
        var social = [Bool](repeating: false, count: n)
        for i in 0..<n { social[i] = nn[i] || agAB[i] || agBA[i] || bodyAB[i] || bodyBA[i] }

        let win = tb.windowDuration
        let socialT = tb.total(social)
        r.metrics = [
            c.m("social_total", RPTexts.tr("社交接触总时间"), socialT, "s", 1, info: RPTexts.tr("鼻–鼻、肛殖区嗅探、身体嗅探的并集")),
            c.m("social_pct", RPTexts.tr("社交接触比例"), c.percent(socialT, win), "%", 1),
            c.m("nose_nose", RPTexts.tr("鼻–鼻接触"), tb.total(nn), "s", 1),
            c.m("nose_nose_bouts", RPTexts.tr("鼻–鼻接触次数"), Double(c.bouts(nn, minDuration: 0.1).count), "", 0),
            c.m("ag_ab", RPTexts.tr("A 嗅 B 肛殖区"), tb.total(agAB), "s", 1),
            c.m("ag_ba", RPTexts.tr("B 嗅 A 肛殖区"), tb.total(agBA), "s", 1),
            c.m("body_ab", RPTexts.tr("A 嗅 B 身体"), tb.total(bodyAB), "s", 1),
            c.m("body_ba", RPTexts.tr("B 嗅 A 身体"), tb.total(bodyBA), "s", 1),
            c.m("follow_ab", RPTexts.tr("A 跟随 B"), tb.total(folAB), "s", 1),
            c.m("follow_ba", RPTexts.tr("B 跟随 A"), tb.total(folBA), "s", 1),
            c.m("proximity_pct", RPTexts.tr("近距离时间"), c.percent(tb.total(prox), win), "%", 1, info: RPTexts.tr("身体中心间距 < \(AnalysisContext.num(p.proximityDist)) cm")),
            c.m("mean_distance", RPTexts.tr("平均间距"), c.mean(dist), c.u, 1)
        ] + c.locomotionMetrics(animal: 0, prefix: "a_", titlePrefix: "A ") + c.locomotionMetrics(animal: 1, prefix: "b_", titlePrefix: "B ")

        // Contact locations: midpoint of the two noses.
        var contactDots: [PlotDot] = []
        let idx = (0..<n).filter { social[$0] && tb.inWindow[$0] }
        let step = max(1, idx.count / 1200)
        for j in stride(from: 0, to: idx.count, by: step) {
            let i = idx[j]
            if let a = A.pos(.nose, i), let b = B.pos(.nose, i) { contactDots.append(PlotDot(p: V2.mid(a, b), color: .sniff, radius: 1.6)) }
        }
        r.blocks.append(c.trajectoryBlock(caption: RPTexts.tr("蓝 = A，橙 = B；点为社交接触时两鼻尖的中点"), dots: contactDots))
        r.blocks.append(ReportBlock(title: RPTexts.tr("社交行为时间"), caption: nil, kind: .bars(BarData(items: [
            BarItem(label: RPTexts.tr("鼻–鼻"), value: tb.total(nn), color: .sniff),
            BarItem(label: RPTexts.tr("A→B 肛殖"), value: tb.total(agAB), color: .animalA),
            BarItem(label: RPTexts.tr("B→A 肛殖"), value: tb.total(agBA), color: .animalB),
            BarItem(label: RPTexts.tr("A→B 身体"), value: tb.total(bodyAB), color: .animalA),
            BarItem(label: RPTexts.tr("B→A 身体"), value: tb.total(bodyBA), color: .animalB),
            BarItem(label: RPTexts.tr("A 跟随"), value: tb.total(folAB), color: .animalA),
            BarItem(label: RPTexts.tr("B 跟随"), value: tb.total(folBA), color: .animalB)
        ], unit: "s", horizontal: true))))
        let tracks = [
            TimelineTrack(name: RPTexts.tr("鼻–鼻"), color: .sniff, bouts: c.bouts(nn, minDuration: 0.1)),
            TimelineTrack(name: RPTexts.tr("A→B 肛殖区"), color: .animalA, bouts: c.bouts(agAB, minDuration: 0.1)),
            TimelineTrack(name: RPTexts.tr("B→A 肛殖区"), color: .animalB, bouts: c.bouts(agBA, minDuration: 0.1)),
            TimelineTrack(name: RPTexts.tr("A 跟随 B"), color: .animalA, bouts: Bouts.find(folAB, tb)),
            TimelineTrack(name: RPTexts.tr("B 跟随 A"), color: .animalB, bouts: Bouts.find(folBA, tb))
        ]
        r.blocks.append(ReportBlock(title: RPTexts.tr("行为时间轴"), caption: nil, kind: .timeline(c.timeline(tracks))))
        r.reviewTracks = Array(tracks.prefix(3))

        // Inter-animal distance over time.
        var pts: [LinePoint] = []
        let s0 = tb.windowStartTime
        let widx = (0..<n).filter { tb.inWindow[$0] && dist[$0].isFinite }
        let st = max(1, widx.count / 600)
        for j in stride(from: 0, to: widx.count, by: st) { pts.append(LinePoint(x: (tb.t[widx[j]] - s0) / 60, y: dist[widx[j]])) }
        r.blocks.append(ReportBlock(title: RPTexts.tr("两鼠间距"), caption: RPTexts.tr("身体中心距离"), kind: .line(LineData(series: [LineSeries(name: RPTexts.tr("间距"), color: .accent, points: pts)], xLabel: "min", yLabel: c.u, referenceY: p.proximityDist))))

        r.frameColumns = [
            ("nose_nose", AnalysisContext.flag(nn)), ("anogenital_A_to_B", AnalysisContext.flag(agAB)), ("anogenital_B_to_A", AnalysisContext.flag(agBA)),
            ("body_sniff_A_to_B", AnalysisContext.flag(bodyAB)), ("body_sniff_B_to_A", AnalysisContext.flag(bodyBA)),
            ("follow_A_B", AnalysisContext.flag(folAB)), ("follow_B_A", AnalysisContext.flag(folBA)), ("inter_animal_distance", dist)
        ]
        r.warnings.append(RPTexts.tr("身份按位置连续性分配：两鼠贴近或重叠后 A / B 可能交换。总社交时间不受影响，区分个体的指标请在回看中确认。"))
        r.methods.append(RPTexts.tr("鼻–鼻接触：鼻尖距离 < \(AnalysisContext.num(p.noseNoseDist)) cm；肛殖区嗅探：鼻尖到对方尾根 < \(AnalysisContext.num(p.anogenitalDist)) cm；身体嗅探：鼻尖到对方身体中心 < \(AnalysisContext.num(p.bodySniffDist)) cm；跟随：间距 < \(AnalysisContext.num(p.followDist)) cm、两鼠速度 > \(AnalysisContext.num(p.followSpeed)) cm/s、跟随者朝向对方 ±\(AnalysisContext.num(p.followAngle))°，持续 ≥ \(AnalysisContext.num(p.followMin)) s。"))
        return r
    }
}
