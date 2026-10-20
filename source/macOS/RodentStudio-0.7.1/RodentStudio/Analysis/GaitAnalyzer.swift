// GaitAnalyzer.swift — paw-level gait analysis from bottom-view video (v2).
//
// Stance / swing (Machado et al. 2015; Hamers et al. 2001; Sheppard et al. 2022): a paw is in
// stance while its world-frame step speed is below max(stanceFloor·BL/s, stanceRatio·body
// speed); phases shorter than `minPhase` are merged.
//
// Stride selection (Sheppard et al. 2022): foot strike → next foot strike of the same paw, kept
// only when the body moves ≥ minBodySpeed, the path is straight (mean |angular velocity| ≤
// maxTurnRate) and — optionally — the stride is not the first or last of a continuous run.
//
// Measures
//   stride length / step length / base of support (step width) from footprints
//   duty factor = stance / stride; stride-to-stride CV (Machado 2015: variability in ataxia)
//   interlimb phase = (strike_target − strike_ref) / stride_ref; circular mean and R
//   gait pattern per hind stride (after Bellardita & Kiehn 2015): alternating hind limbs with
//     diagonal coupling = trot, otherwise walk; synchronous hind limbs = bound; else gallop
//   lateral displacement of nose and tail base within each stride, relative to the line joining
//     the body centre at the stride start and end (Sheppard 2022): amplitude (BL) and phase
//   regularity index (Cheng et al. 1997)
//   speed-matched values: per-animal linear fit of each hind measure against stride speed,
//     evaluated at `referenceSpeed` (Batka et al. 2014: gait must be compared at equal speed)

import Foundation

enum GaitAnalyzer {
    static func run(_ s: PoseSeries, _ p: GaitParams, calibration: Calibration) -> AnalysisResult {
        var notes: [Note] = []
        let bl = s.bodyLength
        let n = s.n
        let pxPerCm = calibration.scale?.pxPerCm
        let unit = pxPerCm != nil ? "cm" : "BL"
        let toUnit: (Double) -> Double = { px in pxPerCm.map { px / $0 } ?? px / bl }
        if pxPerCm == nil {
            notes.append(Note(.info, "No cm scale set: lengths are in body lengths (BL). Add a scale in Calibration for cm.",
                              "未设置厘米标尺：长度单位为体长（BL）。在“标定”中添加标尺即可得到厘米。"))
        }
        func map(_ k: Kp) -> Kp { p.swapLR ? k.mirrored : k }

        // MARK: Body centre, speed, heading, angular velocity
        var cx = [Double](repeating: .nan, count: n), cy = cx
        for i in 0..<n {
            if let a = s.p(.nose, i), let b = s.p(.tail, i) {
                cx[i] = (a.x + b.x) / 2; cy[i] = (a.y + b.y) / 2
            } else {
                let pts = Kp.paws.compactMap { s.p($0, i) }
                if pts.count >= 3 {
                    cx[i] = pts.map(\.x).reduce(0, +) / Double(pts.count)
                    cy[i] = pts.map(\.y).reduce(0, +) / Double(pts.count)
                }
            }
        }
        let sw = s.samples(0.15)
        cx = Signal.smooth(cx, window: sw); cy = Signal.smooth(cy, window: sw)
        let vx = Signal.derivative(cx, t: s.t), vy = Signal.derivative(cy, t: s.t)
        let bodySpeed = zip(vx, vy).map { hypot($0, $1) }

        var angle = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            if bodySpeed[i].isFinite, bodySpeed[i] > 0.2 * bl {
                angle[i] = atan2(vy[i], vx[i])
            } else if let a = s.p(.nose, i), let b = s.p(.tail, i) {
                angle[i] = atan2(a.y - b.y, a.x - b.x)
            }
        }
        // Unwrap, smooth, differentiate → |deg/s|.
        var last: Int?
        for i in 0..<n where angle[i].isFinite {
            if let j = last {
                var d = angle[i] - angle[j]
                while d > .pi { angle[i] -= 2 * .pi; d -= 2 * .pi }
                while d < -.pi { angle[i] += 2 * .pi; d += 2 * .pi }
            }
            last = i
        }
        let turnRate = Signal.derivative(Signal.smooth(angle, window: s.samples(0.2)), t: s.t).map { abs($0) * 180 / .pi }
        func heading(_ i: Int) -> P? {
            guard i >= 0, i < n, angle[i].isFinite else { return nil }
            return P(x: cos(angle[i]), y: sin(angle[i]))
        }
        func meanOver(_ v: [Double], _ a: Double, _ b: Double) -> Double? {
            Signal.mean(Array(v[s.indices(from: a, to: b)]))
        }

        // MARK: Stance detection
        struct Stance { var range: Range<Int>; var interval: Interval; var print: P }
        var stances: [Kp: [Stance]] = [:]
        let minPhase = s.samples(p.minPhase)
        for paw in Kp.paws {
            let src = map(paw)
            let sp = s.stepSpeed(src)
            var state = [Int](repeating: -1, count: n)   // 1 stance, 0 swing, -1 unknown
            for i in 0..<n where sp[i].isFinite {
                let thr = max(p.stanceFloor * bl, p.stanceRatio * (bodySpeed[i].isFinite ? bodySpeed[i] : 0))
                state[i] = sp[i] < thr ? 1 : 0
            }
            var changed = true, passes = 0
            while changed && passes < 4 {
                changed = false; passes += 1
                var i = 0
                while i < n {
                    var j = i
                    while j < n && state[j] == state[i] { j += 1 }
                    if state[i] >= 0, i > 0, j < n, j - i < minPhase, state[i - 1] == state[j], state[j] >= 0 {
                        for k in i..<j { state[k] = state[j] }
                        changed = true
                    }
                    i = j
                }
            }
            var list: [Stance] = []
            var i = 0
            while i < n {
                var j = i
                while j < n && state[j] == state[i] { j += 1 }
                if state[i] == 1, i > 0, j < n, state[i - 1] == 0, state[j] == 0 {
                    let pts = (i..<j).compactMap { s.p(src, $0) }
                    if !pts.isEmpty {
                        let m = P(x: pts.map(\.x).reduce(0, +) / Double(pts.count),
                                  y: pts.map(\.y).reduce(0, +) / Double(pts.count))
                        list.append(Stance(range: i..<j, interval: s.interval(i..<j), print: m))
                    }
                }
                i = j
            }
            stances[paw] = list
        }

        // MARK: Strides (straight, steady, optionally trimmed)
        struct Candidate { var stride: GaitStride; var ok: Bool; var speedBL: Double }
        var strides: [GaitStride] = []
        var speedsBL: [Double] = []         // parallel to `strides`
        var rejectedTurn = 0
        for paw in Kp.paws {
            let list = stances[paw] ?? []
            guard list.count >= 2 else { continue }
            var cands: [Candidate] = []
            for k in 0..<(list.count - 1) {
                let a = list[k], b = list[k + 1]
                let dur = b.interval.start - a.interval.start
                let v = meanOver(bodySpeed, a.interval.start, b.interval.start) ?? 0
                let w = meanOver(turnRate, a.interval.start, b.interval.start) ?? 0
                let stance = a.interval.duration
                let swing = dur - stance
                var ok = dur > 0 && dur <= p.maxStride && v >= p.minBodySpeed * bl && swing > 0
                if ok && w > p.maxTurnRate { ok = false; rejectedTurn += 1 }
                cands.append(Candidate(stride: GaitStride(paw: paw, start: a.interval.start, end: b.interval.start,
                                                          stance: stance, swing: max(0, swing), duty: dur > 0 ? stance / dur : 0,
                                                          length: toUnit(a.print.dist(b.print)), speed: toUnit(v)),
                                       ok: ok, speedBL: v / bl))
            }
            var i = 0
            while i < cands.count {
                guard cands[i].ok else { i += 1; continue }
                var j = i
                while j + 1 < cands.count, cands[j + 1].ok, abs(cands[j + 1].stride.start - cands[j].stride.end) < 1e-9 { j += 1 }
                var run = Array(cands[i...j])
                if p.trimRunEnds { run = run.count >= 3 ? Array(run.dropFirst().dropLast()) : [] }
                strides += run.map(\.stride)
                speedsBL += run.map(\.speedBL)
                i = j + 1
            }
        }
        let hindIdx = strides.indices.filter { strides[$0].paw == .lh || strides[$0].paw == .rh }

        // MARK: Per-paw summaries & girdle means
        var paws: [PawSummary] = []
        for paw in Kp.paws {
            let st = strides.filter { $0.paw == paw }
            paws.append(PawSummary(paw: paw, strides: st.count,
                                   strideLength: Signal.mean(st.map(\.length)),
                                   strideDuration: Signal.mean(st.map { $0.end - $0.start }),
                                   stance: Signal.mean(st.map(\.stance)),
                                   swing: Signal.mean(st.map(\.swing)),
                                   duty: Signal.mean(st.map(\.duty))))
        }
        func girdle(_ a: Kp, _ b: Kp, _ f: (GaitStride) -> Double) -> Double? {
            Signal.mean(strides.filter { $0.paw == a || $0.paw == b }.map(f))
        }
        func cv(_ v: [Double]) -> Double? {
            guard v.count > 2, let m = Signal.mean(v), m > 0, let sd = Signal.sd(v) else { return nil }
            return sd / m * 100
        }
        let hindStrides = hindIdx.map { strides[$0] }

        // MARK: Speed-matched values (linear fit against stride speed)
        let hindSpeeds = hindIdx.map { speedsBL[$0] }
        var refNote = false
        func atReference(_ f: (GaitStride) -> Double) -> Double? {
            let xs = hindSpeeds, ys = hindStrides.map(f)
            guard xs.count >= 8, let mx = Signal.mean(xs), let my = Signal.mean(ys), let sx = Signal.sd(xs), sx >= 0.1,
                  let lo = xs.min(), let hi = xs.max() else { return nil }
            guard p.referenceSpeed >= lo * 0.75, p.referenceSpeed <= hi * 1.25 else { refNote = true; return nil }
            var sxy = 0.0, sxx = 0.0
            for (x, y) in zip(xs, ys) { sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx) }
            guard sxx > 0 else { return nil }
            let slope = sxy / sxx
            return my + slope * (p.referenceSpeed - mx)
        }

        // MARK: Base of support (step width) and step length
        func pairStep(_ l: Kp, _ r: Kp) -> (width: Double?, length: Double?) {
            var widths: [Double] = [], lengths: [Double] = []
            let rs = stances[r] ?? []
            for a in stances[l] ?? [] {
                guard let v = meanOver(bodySpeed, a.interval.start, a.interval.end), v >= p.minBodySpeed * bl else { continue }
                let mid = (a.range.lowerBound + a.range.upperBound) / 2
                guard let h = heading(mid) else { continue }
                var best: Stance?, bestScore = -Double.infinity
                for b in rs {
                    let overlap = min(a.interval.end, b.interval.end) - max(a.interval.start, b.interval.start)
                    let score = overlap > 0 ? overlap : -abs(b.interval.start - a.interval.start)
                    if score > bestScore && (overlap > 0 || abs(b.interval.start - a.interval.start) < p.maxStride / 2) {
                        bestScore = score; best = b
                    }
                }
                if let b = best { widths.append(toUnit(abs(h.cross(b.print - a.print)))) }
                if let next = rs.first(where: { $0.interval.start > a.interval.start && $0.interval.start - a.interval.start < p.maxStride }) {
                    lengths.append(toUnit(abs(h.dot(next.print - a.print))))
                }
            }
            return (Signal.mean(widths), Signal.mean(lengths))
        }
        let fore = pairStep(.lf, .rf)
        let hind = pairStep(.lh, .rh)

        // MARK: Interlimb phases
        let lhStrides = strides.filter { $0.paw == .lh }
        let lfStrides = strides.filter { $0.paw == .lf }
        func strikes(_ k: Kp) -> [Double] { (stances[k] ?? []).map { $0.interval.start } }
        func phase(in st: GaitStride, of target: Kp) -> Double? {
            guard let t = strikes(target).first(where: { $0 >= st.start && $0 < st.end }) else { return nil }
            return (t - st.start) / (st.end - st.start)
        }
        let phaseDefs: [(String, LText, [GaitStride], Kp)] = [
            ("phase_LH_RH", LText("Hind homologous (LH→RH)", "后肢同源（LH→RH）"), lhStrides, .rh),
            ("phase_LF_RF", LText("Fore homologous (LF→RF)", "前肢同源（LF→RF）"), lfStrides, .rf),
            ("phase_LH_LF", LText("Homolateral (LH→LF)", "同侧（LH→LF）"), lhStrides, .lf),
            ("phase_LH_RF", LText("Diagonal (LH→RF)", "对角（LH→RF）"), lhStrides, .rf),
        ]
        let phaseList: [PhaseSummary] = phaseDefs.map { def in
            let (key, label, refs, target) = def
            let v = refs.compactMap { phase(in: $0, of: target) }
            let c = Signal.circular(v)
            return PhaseSummary(key: key, label: label, values: v, mean: c?.mean, r: c?.r)
        }

        // MARK: Gait pattern per hind stride (after Bellardita & Kiehn 2015)
        var walk = 0, trot = 0, gallop = 0, bound = 0
        for st in lhStrides {
            guard let h = phase(in: st, of: .rh) else { continue }
            if abs(h - 0.5) <= 0.15 {
                if let d = phase(in: st, of: .rf), min(d, 1 - d) <= 0.15 { trot += 1 } else { walk += 1 }
            } else if min(h, 1 - h) <= 0.15 {
                bound += 1
            } else {
                gallop += 1
            }
        }
        let classified = walk + trot + gallop + bound
        let patterns: [PatternShare] = [
            PatternShare(key: "walk", label: LText("Walk", "慢走"), count: walk),
            PatternShare(key: "trot", label: LText("Trot", "小跑"), count: trot),
            PatternShare(key: "gallop", label: LText("Gallop", "跑步"), count: gallop),
            PatternShare(key: "bound", label: LText("Bound", "跳跃"), count: bound),
        ]
        func share(_ x: Int) -> Double? { classified > 0 ? Double(x) / Double(classified) * 100 : nil }

        // MARK: Whole-body lateral displacement (Sheppard et al. 2022)
        func lateral(_ k: Kp) -> (amp: Double?, phase: Double?) {
            var amps: [Double] = [], phs: [Double] = []
            for st in lhStrides {
                let r = s.indices(from: st.start, to: st.end)
                guard r.count >= 4 else { continue }
                let p0 = P(x: cx[r.lowerBound], y: cy[r.lowerBound]), p1 = P(x: cx[r.upperBound - 1], y: cy[r.upperBound - 1])
                guard p0.x.isFinite, p1.x.isFinite, let u = (p1 - p0).unit else { continue }
                var offs: [(Double, Double)] = []
                for i in r {
                    if let q = s.p(k, i) { offs.append((u.cross(q - p0), Double(i - r.lowerBound) / Double(r.count))) }
                }
                guard Double(offs.count) >= Double(r.count) * 0.7,
                      let mx = offs.max(by: { $0.0 < $1.0 }), let mn = offs.min(by: { $0.0 < $1.0 }) else { continue }
                amps.append((mx.0 - mn.0) / bl)
                phs.append(mx.1)
            }
            return (Signal.mean(amps), Signal.circular(phs)?.mean)
        }
        let noseLat = lateral(.nose)
        let tailLat = lateral(.tail)

        // MARK: Print positioning
        func printPosition(_ hindPaw: Kp, _ forePaw: Kp) -> Double? {
            var vals: [Double] = []
            let fs = stances[forePaw] ?? []
            for h in stances[hindPaw] ?? [] {
                guard let v = meanOver(bodySpeed, h.interval.start, h.interval.end), v >= p.minBodySpeed * bl,
                      let f = fs.last(where: { $0.interval.start <= h.interval.start && h.interval.start - $0.interval.start <= p.maxStride })
                else { continue }
                vals.append(toUnit(h.print.dist(f.print)))
            }
            return Signal.mean(vals)
        }

        // MARK: Regularity index
        var strikeList: [(Double, Kp)] = []
        for paw in Kp.paws {
            for st in stances[paw] ?? [] {
                let i = st.range.lowerBound
                if bodySpeed[i].isFinite && bodySpeed[i] >= p.minBodySpeed * bl { strikeList.append((st.interval.start, paw)) }
            }
        }
        strikeList.sort { $0.0 < $1.0 }
        let normal: Set<[Kp]> = [[.rf, .lf, .rh, .lh], [.lf, .rf, .lh, .rh], [.rf, .rh, .lf, .lh],
                                 [.lf, .rh, .rf, .lh], [.rf, .lf, .lh, .rh], [.lf, .rf, .rh, .lh]]
        var nssp = 0, k = 0
        while k + 4 <= strikeList.count {
            let seq = strikeList[k..<(k + 4)].map { $0.1 }
            let gapOK = strikeList[k + 3].0 - strikeList[k].0 <= p.maxStride * 1.5
            if gapOK && normal.contains(seq) { nssp += 1; k += 4 } else { k += 1 }
        }
        let regularity: Double? = strikeList.count >= 8 ? Double(nssp * 4) / Double(strikeList.count) * 100 : nil

        // MARK: Symmetry, coverage
        let lhLen = paws.first { $0.paw == .lh }?.strideLength
        let rhLen = paws.first { $0.paw == .rh }?.strideLength
        var symmetry: Double?
        if let a = lhLen, let b = rhLen, a + b > 0 { symmetry = (a - b) / ((a + b) / 2) * 100 }
        let moving = bodySpeed.filter { $0.isFinite && $0 >= p.minBodySpeed * bl }.count
        let coverage = Kp.paws.map { s.visibility[map($0).rawValue] }.min() ?? 0
        let speedUnit = unit + "/s"
        let validSpeeds = strides.map(\.speed)

        let ph = Dictionary(uniqueKeysWithValues: phaseList.map { ($0.key, $0) })
        let blPerUnit: Double = pxPerCm.map { $0 / bl } ?? 1      // output unit → BL
        let refLabel = String(format: "@ %.1f BL/s", p.referenceSpeed)
        let strideFreq: Double? = girdle(.lh, .rh) { $0.end - $0.start }.map { 1 / $0 }
        let refFreq: Double? = atReference { $0.end - $0.start }.map { 1 / $0 }
        let refLen: Double? = atReference { $0.length * blPerUnit }
        let refDuty: Double? = atReference { $0.duty }.map { $0 * 100 }
        let refSwing: Double? = atReference { $0.swing }
        let dutyFore: Double? = girdle(.lf, .rf) { $0.duty }.map { $0 * 100 }
        let dutyHind: Double? = girdle(.lh, .rh) { $0.duty }.map { $0 * 100 }
        let movingPct: Double? = n > 0 ? Double(moving) / Double(n) * 100 : nil

        var metrics: [Metric] = []
        func add(_ key: String, _ en: String, _ zh: String, _ value: Double?, _ unit: String, _ dec: Int, _ hi: Bool = false) {
            metrics.append(Metric(key: key, label: LText(en, zh), value: value, unit: unit, decimals: dec, highlight: hi))
        }
        func addPhase(_ key: String) {
            guard let x = ph[key] else { return }
            metrics.append(Metric(key: key, label: x.label, value: x.mean, unit: "cycle", decimals: 2))
        }
        add("speed", "Walking speed", "行走速度", Signal.mean(validSpeeds), speedUnit, 1, true)
        add("speed_cv_pct", "Speed variability (CV)", "速度变异系数", cv(validSpeeds), "%", 0)
        add("strides_n", "Strides analyzed", "分析步幅数", Double(strides.count), "", 0)
        add("moving_pct", "Time walking", "行走时间占比", movingPct, "%", 0)
        add("stride_len_fore", "Stride length, fore", "前肢步幅", girdle(.lf, .rf) { $0.length }, unit, 2)
        add("stride_len_hind", "Stride length, hind", "后肢步幅", girdle(.lh, .rh) { $0.length }, unit, 2, true)
        add("stride_len_hind_bl", "Stride length, hind (body lengths)", "后肢步幅（体长）", Signal.mean(hindStrides.map { $0.length * blPerUnit }), "BL", 2)
        add("step_len_hind", "Step length, hind", "后肢步长", hind.length, unit, 2)
        add("bos_fore", "Base of support, fore", "前肢支撑面宽度", fore.width, unit, 2)
        add("bos_hind", "Base of support, hind", "后肢支撑面宽度", hind.width, unit, 2, true)
        add("print_pos_left", "Print position, left", "左侧足印位置", printPosition(.lh, .lf), unit, 2)
        add("print_pos_right", "Print position, right", "右侧足印位置", printPosition(.rh, .rf), unit, 2)
        add("stride_freq_hz", "Stride frequency", "步频", strideFreq, "Hz", 2)
        add("stance_fore_s", "Stance, fore", "前肢支撑相", girdle(.lf, .rf) { $0.stance }, "s", 3)
        add("stance_hind_s", "Stance, hind", "后肢支撑相", girdle(.lh, .rh) { $0.stance }, "s", 3)
        add("swing_fore_s", "Swing, fore", "前肢摆动相", girdle(.lf, .rf) { $0.swing }, "s", 3)
        add("swing_hind_s", "Swing, hind", "后肢摆动相", girdle(.lh, .rh) { $0.swing }, "s", 3)
        add("duty_fore", "Duty factor, fore", "前肢占空比", dutyFore, "%", 1)
        add("duty_hind", "Duty factor, hind", "后肢占空比", dutyHind, "%", 1, true)
        add("ref_stride_len_bl", "Hind stride length \(refLabel)", "后肢步幅 \(refLabel)", refLen, "BL", 2)
        add("ref_stride_freq_hz", "Stride frequency \(refLabel)", "步频 \(refLabel)", refFreq, "Hz", 2)
        add("ref_duty_hind", "Hind duty factor \(refLabel)", "后肢占空比 \(refLabel)", refDuty, "%", 1)
        add("ref_swing_hind_s", "Hind swing \(refLabel)", "后肢摆动相 \(refLabel)", refSwing, "s", 3)
        add("cv_stride_len_hind_pct", "Stride length variability (CV)", "步幅变异系数", cv(hindStrides.map(\.length)), "%", 1)
        add("cv_stride_time_hind_pct", "Stride time variability (CV)", "步时变异系数", cv(hindStrides.map { $0.end - $0.start }), "%", 1)
        add("hind_len_symmetry_pct", "Hind stride L−R asymmetry", "后肢步幅左右不对称", symmetry, "%", 1)
        addPhase("phase_LH_RH"); addPhase("phase_LF_RF"); addPhase("phase_LH_LF"); addPhase("phase_LH_RF")
        add("coupling_hind_R", "Hind coupling strength (R)", "后肢耦合强度 R", ph["phase_LH_RH"]?.r, "", 2)
        add("regularity_pct", "Regularity index", "规律性指数", regularity, "%", 1)
        add("pattern_walk_pct", "Walk strides", "慢走步幅占比", share(walk), "%", 0)
        add("pattern_trot_pct", "Trot strides", "小跑步幅占比", share(trot), "%", 0)
        add("pattern_gallop_pct", "Gallop strides", "跑步步幅占比", share(gallop), "%", 0)
        add("pattern_bound_pct", "Bound strides", "跳跃步幅占比", share(bound), "%", 0)
        add("nose_lateral_amp_bl", "Nose lateral sway", "鼻尖侧向摆动", noseLat.amp, "BL", 3)
        add("tail_lateral_amp_bl", "Tail-base lateral sway", "尾根侧向摆动", tailLat.amp, "BL", 3)
        add("nose_lateral_phase", "Nose sway phase", "鼻尖摆动相位", noseLat.phase, "cycle", 2)
        add("tail_lateral_phase", "Tail-base sway phase", "尾根摆动相位", tailLat.phase, "cycle", 2)
        add("turn_rejected_n", "Strides excluded for turning", "因转向排除的步幅", Double(rejectedTurn), "", 0)
        add("pose_coverage_pct", "Paw visibility (worst paw)", "爪可见率（最低）", coverage * 100, "%", 0)
        metrics = metrics.grouped([
            (LText("Speed", "速度"), ["speed", "speed_cv_pct", "strides_n", "moving_pct"]),
            (LText("Spatial", "空间参数"), ["stride_len_fore", "stride_len_hind", "stride_len_hind_bl", "step_len_hind", "bos_fore", "bos_hind", "print_pos_left", "print_pos_right"]),
            (LText("Temporal", "时间参数"), ["stride_freq_hz", "stance_fore_s", "stance_hind_s", "swing_fore_s", "swing_hind_s", "duty_fore", "duty_hind"]),
            (LText("Speed-matched", "速度匹配值"), ["ref_stride_len_bl", "ref_stride_freq_hz", "ref_duty_hind", "ref_swing_hind_s"]),
            (LText("Variability & symmetry", "变异与对称"), ["cv_stride_len_hind_pct", "cv_stride_time_hind_pct", "hind_len_symmetry_pct"]),
            (LText("Coordination", "协调"), ["phase_LH_RH", "phase_LF_RF", "phase_LH_LF", "phase_LH_RF", "coupling_hind_R", "regularity_pct",
                                          "pattern_walk_pct", "pattern_trot_pct", "pattern_gallop_pct", "pattern_bound_pct"]),
            (LText("Whole-body posture", "全身姿态"), ["nose_lateral_amp_bl", "tail_lateral_amp_bl", "nose_lateral_phase", "tail_lateral_phase"]),
            (LText("Quality", "数据质量"), ["turn_rejected_n", "pose_coverage_pct"]),
        ])

        // MARK: Notes
        let perPawMin = paws.map(\.strides).min() ?? 0
        if perPawMin < 5 {
            notes.append(Note(.warning,
                              String(format: "Only %d strides for the weakest paw passed the filters (steady, straight walking). Use longer runs, or relax the turning and speed filters in Parameters.", perPawMin),
                              String(format: "最少的一只爪只有 %d 个步幅通过筛选（稳定直线行走）。请使用更长的行走片段，或在“参数”中放宽转向和速度筛选。", perPawMin)))
        }
        if coverage < 0.6 {
            notes.append(Note(.warning,
                              String(format: "At least one paw was visible in only %.0f%% of frames. A bottom view of the walkway gives the best paw tracking.", coverage * 100),
                              String(format: "至少一只爪仅在 %.0f%% 的帧中可见。步道仰视拍摄的爪追踪效果最好。", coverage * 100)))
        }
        if s.fps < 50 {
            notes.append(Note(.info,
                              String(format: "Video is %.0f fps, so stance and swing are resolved to %.0f ms. ≥ 60 fps is recommended for gait.", s.fps, 1000 / s.fps),
                              String(format: "视频为 %.0f fps，支撑/摆动时长分辨率为 %.0f 毫秒；步态分析建议 ≥ 60 fps。", s.fps, 1000 / s.fps)))
        }
        if refNote {
            notes.append(Note(.info,
                              String(format: "Speed-matched values need strides around %.1f BL/s; this animal walked at other speeds, so they are left blank rather than extrapolated.", p.referenceSpeed),
                              String(format: "速度匹配值需要约 %.1f 体长/秒附近的步幅；该动物的行走速度不在此范围，为避免外推，相应指标留空。", p.referenceSpeed)))
        }
        notes.append(Note(.info,
                          "Gait changes with speed. Compare groups with the speed-matched values, or use per-stride speed as a covariate (strides export).",
                          "步态随速度变化。组间比较请使用速度匹配值，或将每步速度作为协变量（见步幅导出表）。"))

        var stanceMap: [String: [Interval]] = [:]
        var prints: [Footprint] = []
        for paw in Kp.paws {
            stanceMap[paw.code] = (stances[paw] ?? []).map(\.interval)
            prints += (stances[paw] ?? []).map { Footprint(paw: paw, t: $0.interval.start, x: $0.print.x, y: $0.print.y) }
        }
        let speedSeries = Signal.downsample(t: s.t, v: bodySpeed.map { $0.isFinite ? toUnit($0) : .nan }, maxPoints: 1200)
        let detail = GaitDetail(unit: unit, stances: stanceMap, strides: strides, footprints: prints,
                                paws: paws, speed: speedSeries, phases: phaseList, patterns: patterns)
        return AnalysisResult(metrics: metrics, notes: notes, tst: nil, cylinder: nil, gait: detail,
                              analyzedAt: Date(), poseCoverage: coverage)
    }
}
