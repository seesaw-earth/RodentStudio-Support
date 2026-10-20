// CylinderAnalyzer.swift — cylinder (forelimb asymmetry) test.
//
// Schallert et al. 2000: during rearing the animal places one or both forepaws on the wall;
// the first paw placed in each rear is scored left, right or both (simultaneous). Asymmetry
// is reported relative to the lesioned hemisphere:
//   • contralateral use (%) = contra / (ipsi + contra) × 100           (Magno et al. 2019)
//   • contralateral incl. both (%) = (contra + ½ both) / total × 100
//   • asymmetry index (%) = (ipsi − contra) / (ipsi + contra + both) × 100
//
// Automated contact: a forepaw is "placed on the wall" when it is still (speed < stillSpeed)
// AND at the wall — bottom view: within `wallMargin` of the calibrated rim; side view: raised
// above the calibrated floor line by `elevation` body lengths. Every event can be relabeled by
// the user; edits are keyed by onset frame and survive re-analysis.

import Foundation

enum CylinderAnalyzer {
    static func run(_ s: PoseSeries, _ p: CylinderParams, calibration: Calibration,
                    overrides: [Int: PawLabel]) -> AnalysisResult {
        var notes: [Note] = []
        let bl = s.bodyLength
        let n = s.n
        let leftKp: Kp = p.swapLR ? .rf : .lf
        let rightKp: Kp = p.swapLR ? .lf : .rf

        let circle = calibration.circle
        let floor = calibration.floorY
        let calibrated = p.view == .bottom ? circle != nil : floor != nil
        if !calibrated {
            notes.append(Note(.error,
                              p.view == .bottom ? "Mark the cylinder rim in Calibration to detect wall contacts." : "Mark the floor line in Calibration to detect wall contacts.",
                              p.view == .bottom ? "请在“标定”中标出圆筒边缘以检测触壁。" : "请在“标定”中标出地面线以检测触壁。"))
        }

        func contactMask(_ k: Kp) -> [Bool] {
            let sp = s.speed(k)
            var m = [Bool](repeating: false, count: n)
            guard calibrated else { return m }
            for i in 0..<n {
                guard let pt = s.p(k, i), sp[i].isFinite, sp[i] / bl < p.stillSpeed else { continue }
                switch p.view {
                case .bottom:
                    if let c = circle, pt.dist(P(x: c.cx, y: c.cy)) >= c.r * (1 - p.wallMargin) { m[i] = true }
                case .side:
                    if let f = floor, (f - pt.y) / bl >= p.elevation { m[i] = true }
                }
            }
            // Bridge 1–2 frame dropouts so one placement is not split in two.
            let bridge = max(2, s.samples(0.06))
            var i = 0
            while i < n {
                if !m[i] {
                    var j = i
                    while j < n && !m[j] { j += 1 }
                    if i > 0 && j < n && j - i <= bridge { for k in i..<j { m[k] = true } }
                    i = j
                } else { i += 1 }
            }
            return m
        }

        func contacts(_ mask: [Bool]) -> [(Range<Int>, Interval)] {
            Signal.runs(mask).map { ($0, s.interval($0)) }.filter { $0.1.duration >= p.minContact - 1e-9 }
        }
        let left = contacts(contactMask(leftKp))
        let right = contacts(contactMask(rightKp))

        // Rears = union of contacts with gaps < rearGap.
        var all = (left.map { $0.1 } + right.map { $0.1 }).sorted { $0.start < $1.start }
        var rears: [Interval] = []
        for c in all {
            if var last = rears.last, c.start - last.end < p.rearGap {
                last.end = max(last.end, c.end)
                rears[rears.count - 1] = last
            } else {
                rears.append(c)
            }
        }
        all.removeAll()

        func rearIndex(_ t: Double) -> Int {
            rears.firstIndex { t >= $0.start - 1e-9 && t <= $0.end + 1e-9 } ?? 0
        }

        // Candidate events.
        struct Onset { var frame: Int; var t: Double; var end: Double; var left: Bool }
        let onsets = (left.map { Onset(frame: $0.0.lowerBound, t: $0.1.start, end: $0.1.end, left: true) } +
                      right.map { Onset(frame: $0.0.lowerBound, t: $0.1.start, end: $0.1.end, left: false) })
            .sorted { $0.t < $1.t }
        var events: [CylinderEvent] = []
        switch p.scoring {
        case .firstPerRear:
            for (ri, rear) in rears.enumerated() {
                let inRear = onsets.filter { $0.t >= rear.start - 1e-9 && $0.t <= rear.end + 1e-9 }
                guard let first = inRear.first else { continue }
                let other = inRear.first { $0.left != first.left && $0.t - first.t <= p.simultaneity }
                let label: PawLabel = other != nil ? .both : (first.left ? .left : .right)
                events.append(CylinderEvent(id: first.frame, onset: first.t, offset: rear.end, auto: label,
                                            label: label, edited: false, rear: ri + 1, counted: true))
            }
        case .allContacts:
            var used = Set<Int>()
            for (i, o) in onsets.enumerated() where !used.contains(i) {
                var label: PawLabel = o.left ? .left : .right
                var end = o.end
                for j in (i + 1)..<onsets.count {
                    let q = onsets[j]
                    if q.t - o.t > p.simultaneity { break }
                    if q.left != o.left && !used.contains(j) {
                        label = .both; used.insert(j); end = max(end, q.end); break
                    }
                }
                used.insert(i)
                events.append(CylinderEvent(id: o.frame, onset: o.t, offset: end, auto: label, label: label,
                                            edited: false, rear: rearIndex(o.t) + 1, counted: true))
            }
        }

        // Apply user edits and limits.
        var counted = 0
        for i in events.indices {
            if let o = overrides[events[i].id] {
                events[i].label = o
                events[i].edited = o != events[i].auto
            }
            var ok = events[i].label != .ignore
            if p.timeLimit > 0 && events[i].onset >= p.timeLimit { ok = false }
            if p.contactLimit > 0 && counted >= p.contactLimit { ok = false }
            events[i].counted = ok
            if ok { counted += 1 }
        }
        let scored = events.filter { $0.counted }
        let nl = Double(scored.filter { $0.label == .left }.count)
        let nr = Double(scored.filter { $0.label == .right }.count)
        let nb = Double(scored.filter { $0.label == .both }.count)
        let total = nl + nr + nb
        func pct(_ a: Double, _ b: Double) -> Double? { b > 0 ? a / b * 100 : nil }

        var metrics: [Metric] = [
            Metric(key: "contacts_total", label: LText("Wall contacts scored", "计分触壁次数"), value: total, unit: "", decimals: 0, highlight: true),
            Metric(key: "contacts_left", label: LText("Left paw", "左爪"), value: nl, unit: "", decimals: 0),
            Metric(key: "contacts_right", label: LText("Right paw", "右爪"), value: nr, unit: "", decimals: 0),
            Metric(key: "contacts_both", label: LText("Both paws", "双爪"), value: nb, unit: "", decimals: 0),
            Metric(key: "left_pct", label: LText("Left (% of all)", "左爪（占全部）"), value: pct(nl, total), unit: "%", decimals: 1),
            Metric(key: "right_pct", label: LText("Right (% of all)", "右爪（占全部）"), value: pct(nr, total), unit: "%", decimals: 1),
            Metric(key: "both_pct", label: LText("Both (% of all)", "双爪（占全部）"), value: pct(nb, total), unit: "%", decimals: 1),
        ]
        if p.lesion == .none {
            metrics[0].highlight = false
            metrics.insert(Metric(key: "left_use_pct", label: LText("Left use, L/(L+R)", "左爪使用率 L/(L+R)"),
                                  value: pct(nl, nl + nr), unit: "%", decimals: 1, highlight: true), at: 1)
            metrics.insert(Metric(key: "lr_bias_pct", label: LText("Left − right bias", "左右偏好指数"),
                                  value: total > 0 ? (nl - nr) / total * 100 : nil, unit: "%", decimals: 1, highlight: true), at: 2)
            notes.append(Note(.info, "Set the lesion hemisphere in Parameters to get ipsilateral / contralateral scores.",
                              "在“参数”中设置损伤半球，即可得到同侧/对侧指标。"))
        } else {
            let ipsi = p.lesion == .left ? nl : nr
            let contra = p.lesion == .left ? nr : nl
            metrics.insert(contentsOf: [
                Metric(key: "contra_use_pct", label: LText("Contralateral use", "对侧前肢使用率"),
                       value: pct(contra, ipsi + contra), unit: "%", decimals: 1, highlight: true),
                Metric(key: "contra_use_both_pct", label: LText("Contralateral incl. ½ both", "对侧（含½双爪）"),
                       value: total > 0 ? (contra + nb / 2) / total * 100 : nil, unit: "%", decimals: 1),
                Metric(key: "asymmetry_pct", label: LText("Asymmetry index", "不对称指数"),
                       value: total > 0 ? (ipsi - contra) / total * 100 : nil, unit: "%", decimals: 1, highlight: true),
                Metric(key: "ipsi_n", label: LText("Ipsilateral", "同侧"), value: ipsi, unit: "", decimals: 0),
                Metric(key: "contra_n", label: LText("Contralateral", "对侧"), value: contra, unit: "", decimals: 0),
            ], at: 1)
        }

        let lDur = left.map { $0.1.duration }, rDur = right.map { $0.1.duration }
        let twentieth = scored.count >= 20 ? scored[19].onset : nil
        let coverage = min(s.visibility[leftKp.rawValue], s.visibility[rightKp.rawValue])
        metrics += [
            Metric(key: "rears_n", label: LText("Rears with wall contact", "触壁竖立次数"), value: Double(rears.count), unit: "", decimals: 0),
            Metric(key: "left_contact_s", label: LText("Left paw on wall", "左爪触壁总时长"), value: lDur.reduce(0, +), unit: "s", decimals: 1),
            Metric(key: "right_contact_s", label: LText("Right paw on wall", "右爪触壁总时长"), value: rDur.reduce(0, +), unit: "s", decimals: 1),
            Metric(key: "left_contact_mean_s", label: LText("Mean left placement", "左爪平均每次触壁"), value: Signal.mean(lDur), unit: "s", decimals: 2),
            Metric(key: "right_contact_mean_s", label: LText("Mean right placement", "右爪平均每次触壁"), value: Signal.mean(rDur), unit: "s", decimals: 2),
            Metric(key: "time_to_20_s", label: LText("Time to 20 contacts", "达到 20 次触壁用时"), value: twentieth, unit: "s", decimals: 1),
            Metric(key: "edited_n", label: LText("Manually edited events", "人工修改事件"), value: Double(events.filter { $0.edited }.count), unit: "", decimals: 0),
            Metric(key: "pose_coverage_pct", label: LText("Forepaw visibility", "前爪可见率"), value: coverage * 100, unit: "%", decimals: 0),
        ]

        if calibrated && total < 20 {
            notes.append(Note(.info,
                              String(format: "%.0f contacts were scored. Many protocols aim for at least 20 per animal.", total),
                              String(format: "共计分 %.0f 次触壁。许多方案要求每只动物至少 20 次。", total)))
        }
        if coverage < 0.5 {
            notes.append(Note(.warning,
                              String(format: "Forepaws were visible in only %.0f%% of frames; contacts may be missed. Review events on the video.", coverage * 100),
                              String(format: "前爪仅在 %.0f%% 的帧中可见，可能漏检触壁，请在视频上复核事件。", coverage * 100)))
        }
        if s.bodyLengthEstimated {
            notes.append(Note(.warning,
                              "Body length was estimated from the frame size; speed and height thresholds may not fit.",
                              "体长按画面尺寸估算，速度和高度阈值可能不准确。"))
        }

        metrics = metrics.grouped([
            (LText("Lesion-relative", "相对损伤侧"), ["contra_use_pct", "contra_use_both_pct", "asymmetry_pct", "ipsi_n", "contra_n"]),
            (LText("Paw use", "前爪使用"), ["contacts_total", "left_use_pct", "lr_bias_pct", "contacts_left", "contacts_right", "contacts_both", "left_pct", "right_pct", "both_pct"]),
            (LText("Rears & contacts", "竖立与触壁"), ["rears_n", "left_contact_s", "right_contact_s", "left_contact_mean_s", "right_contact_mean_s", "time_to_20_s"]),
            (LText("Quality", "数据质量"), ["edited_n", "pose_coverage_pct"]),
        ])
        let detail = CylinderDetail(events: events, rears: rears,
                                    leftContacts: left.map { $0.1 }, rightContacts: right.map { $0.1 })
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: detail, gait: nil,
                              analyzedAt: Date(), poseCoverage: coverage)
    }
}
