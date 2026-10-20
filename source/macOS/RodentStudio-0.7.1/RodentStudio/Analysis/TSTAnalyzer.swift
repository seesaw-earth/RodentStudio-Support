// TSTAnalyzer.swift — tail suspension test.
//
// Immobility (Steru et al. 1985; Can et al. 2012): hanging passively without limb or body
// movement. Here: mean speed of the four paws and the nose, normalized by body length and
// smoothed, below `motionThreshold` for at least `minBout` seconds. The tail base is excluded
// because it sits at the suspension point. Standard reporting window is minutes 2–6 of a 6-min
// test; the whole-video per-minute profile is also returned.
//
// Hindlimb clasping (Guyenet et al. 2010, JoVE): hind paws drawn toward the body midline during
// the first seconds of suspension. Lateral distance of each hind paw from the tail-base → nose
// axis is measured; the 0–3 score is an automated approximation of the visual score and should
// be confirmed on the video.
//
// Tail climbing: nose comes close to the tail base (mouse curls up its own tail). Many labs
// exclude animals that climb for > 20 % of the test.

import Foundation

enum TSTAnalyzer {
    static func run(_ s: PoseSeries, _ p: TSTParams, duration: Double) -> AnalysisResult {
        var notes: [Note] = []
        let bl = s.bodyLength
        let n = s.n

        // Motion signal (body lengths / s).
        let parts: [Kp] = [.lf, .rf, .lh, .rh, .nose]
        let speeds = parts.map { s.speed($0) }
        var motion = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            var sum = 0.0, c = 0
            for sp in speeds where sp[i].isFinite {
                sum += min(sp[i] / bl, 5); c += 1
            }
            if c >= 2 { motion[i] = sum / Double(c) }
        }
        motion = Signal.smooth(motion, window: s.samples(p.motionSmoothing))

        // Immobile bouts over the whole video.
        let still = motion.map { $0.isFinite && $0 < p.motionThreshold }
        let bouts = Signal.runs(still).map { s.interval($0) }.filter { $0.duration >= p.minBout - 1e-9 }
        var immobileMask = [Bool](repeating: false, count: n)
        for r in Signal.runs(still) where s.interval(r).duration >= p.minBout - 1e-9 {
            for i in r { immobileMask[i] = true }
        }

        // Analysis window.
        let videoEnd = max(duration, (s.t.last ?? 0) + s.dt)
        var w0 = max(0, p.windowStart), w1 = min(p.windowEnd, videoEnd)
        if w1 - w0 < 10 {
            notes.append(Note(.warning,
                              "The video is shorter than the analysis window; the whole video was analyzed instead.",
                              "视频短于分析窗口，已改为分析整段视频。"))
            w0 = 0; w1 = videoEnd
        } else if p.windowEnd > videoEnd + 0.5 {
            notes.append(Note(.warning,
                              String(format: "The video ends at %.0f s, before the window end (%.0f s).", videoEnd, p.windowEnd),
                              String(format: "视频在 %.0f 秒结束，早于分析窗口终点（%.0f 秒）。", videoEnd, p.windowEnd)))
        }
        let win = s.indices(from: w0, to: w1)
        let winSeconds = Double(win.count) * s.dt
        var immobileSeconds = 0.0, known = 0
        for i in win {
            if immobileMask[i] { immobileSeconds += s.dt }
            if motion[i].isFinite { known += 1 }
        }
        let coverage = win.isEmpty ? 0 : Double(known) / Double(win.count)
        let inWindow = bouts.filter { $0.end > w0 && $0.start < w1 }
        let latency = bouts.first?.start

        // Per-minute profile (whole video).
        let minutes = max(1, Int(ceil(videoEnd / 60 - 1e-6)))
        var perMinute = [Double](repeating: 0, count: minutes)
        for i in 0..<n where immobileMask[i] {
            let m = min(minutes - 1, Int(s.t[i] / 60))
            perMinute[m] += s.dt
        }

        // Tail climbing.
        var climbMask = [Bool](repeating: false, count: n)
        var climbFrames = 0, climbKnown = 0
        for i in 0..<n {
            guard let nose = s.p(.nose, i), let tail = s.p(.tail, i) else { continue }
            let c = nose.dist(tail) < p.climbRatio * bl
            climbMask[i] = c
            if win.contains(i) { climbKnown += 1; if c { climbFrames += 1 } }
        }
        let climbFraction = climbKnown > 0 ? Double(climbFrames) / Double(climbKnown) : nil
        let climbing = Signal.runs(climbMask).map { s.interval($0) }.filter { $0.duration >= 0.5 }

        // Hindlimb clasping in the first `claspWindow` seconds.
        let clasp = s.indices(from: 0, to: p.claspWindow)
        var partialL = 0, partialR = 0, fullL = 0, fullR = 0, claspKnown = 0
        var separation: [Double] = []
        for i in 0..<n {
            guard let nose = s.p(.nose, i), let tail = s.p(.tail, i), let axis = (nose - tail).unit,
                  let lh = s.p(.lh, i), let rh = s.p(.rh, i) else { continue }
            if win.contains(i) { separation.append(lh.dist(rh) / bl) }
            guard clasp.contains(i) else { continue }
            let dl = abs(axis.cross(lh - tail)) / bl
            let dr = abs(axis.cross(rh - tail)) / bl
            claspKnown += 1
            if dl < p.claspPartial { partialL += 1 }
            if dr < p.claspPartial { partialR += 1 }
            if dl < p.claspFull { fullL += 1 }
            if dr < p.claspFull { fullR += 1 }
        }
        var claspScore: Double?
        var fracL: Double?, fracR: Double?
        if claspKnown >= s.samples(min(2, p.claspWindow / 2)) {
            let k = Double(claspKnown)
            let pl = Double(partialL) / k, pr = Double(partialR) / k
            let fl = Double(fullL) / k, fr = Double(fullR) / k
            fracL = pl * 100; fracR = pr * 100
            if fl > 0.5 && fr > 0.5 { claspScore = 3 }
            else if pl > 0.5 && pr > 0.5 { claspScore = 2 }
            else if pl > 0.5 || pr > 0.5 { claspScore = 1 }
            else { claspScore = 0 }
        } else {
            notes.append(Note(.info,
                              "Hind paws were not visible enough in the first seconds to estimate clasping.",
                              "前几秒内后爪可见度不足，无法估计抱握评分。"))
        }

        // Quality notes.
        if s.bodyLengthEstimated {
            notes.append(Note(.warning,
                              "Nose and tail base were rarely detected, so body length was estimated from the frame size. Thresholds may not fit this video.",
                              "鼻尖和尾根很少被检测到，体长按画面尺寸估算，阈值可能不适合该视频。"))
        }
        if coverage < 0.9 {
            notes.append(Note(.warning,
                              String(format: "Pose was available for only %.0f%% of the window; frames without pose are not counted as immobile.", coverage * 100),
                              String(format: "窗口内仅 %.0f%% 的帧有姿态，无姿态的帧不计为不动。", coverage * 100)))
        }
        if let cf = climbFraction, cf > 0.2 {
            notes.append(Note(.warning,
                              String(format: "Tail climbing in %.0f%% of the window. Many protocols exclude animals climbing > 20%% of the test.", cf * 100),
                              String(format: "窗口内爬尾占 %.0f%%。许多方案会排除爬尾超过 20%% 的动物。", cf * 100)))
        }
        if claspScore != nil {
            notes.append(Note(.info,
                              "The clasping score is an automated estimate from paw–midline distance; confirm visually on the video.",
                              "抱握评分为根据爪到中线距离的自动估计，请在视频上目视确认。"))
        }

        let durations = inWindow.map { min($0.end, w1) - max($0.start, w0) }
        let metrics: [Metric] = [
            Metric(key: "immobility_s", label: LText("Immobility time", "不动时间"), value: immobileSeconds, unit: "s", decimals: 1, highlight: true),
            Metric(key: "immobility_pct", label: LText("Immobility", "不动比例"), value: winSeconds > 0 ? immobileSeconds / winSeconds * 100 : nil, unit: "%", decimals: 1, highlight: true),
            Metric(key: "latency_s", label: LText("Latency to first immobility", "首次不动潜伏期"), value: latency, unit: "s", decimals: 1),
            Metric(key: "bouts_n", label: LText("Immobility bouts", "不动次数"), value: Double(inWindow.count), unit: "", decimals: 0),
            Metric(key: "bout_mean_s", label: LText("Mean bout duration", "平均每次不动时长"), value: Signal.mean(durations), unit: "s", decimals: 1),
            Metric(key: "bout_max_s", label: LText("Longest bout", "最长不动时长"), value: durations.max(), unit: "s", decimals: 1),
            Metric(key: "window_s", label: LText("Analysis window", "分析窗口"), value: winSeconds, unit: "s", decimals: 0),
            Metric(key: "climb_pct", label: LText("Tail climbing", "爬尾比例"), value: climbFraction.map { $0 * 100 }, unit: "%", decimals: 1),
            Metric(key: "clasp_score", label: LText("Clasping score (est.)", "抱握评分（估计）"), value: claspScore, unit: "/3", decimals: 0),
            Metric(key: "clasp_left_pct", label: LText("Left hind paw near midline", "左后爪靠近中线"), value: fracL, unit: "%", decimals: 0),
            Metric(key: "clasp_right_pct", label: LText("Right hind paw near midline", "右后爪靠近中线"), value: fracR, unit: "%", decimals: 0),
            Metric(key: "hind_separation_bl", label: LText("Hind paw separation", "后爪间距"), value: Signal.mean(separation), unit: "BL", decimals: 2),
            Metric(key: "pose_coverage_pct", label: LText("Pose coverage", "姿态覆盖率"), value: coverage * 100, unit: "%", decimals: 0),
        ]

        let groupedMetrics = metrics.grouped([
            (LText("Immobility", "不动"), ["immobility_s", "immobility_pct", "latency_s", "bouts_n", "bout_mean_s", "bout_max_s", "window_s"]),
            (LText("Clasping & climbing", "抱握与爬尾"), ["clasp_score", "clasp_left_pct", "clasp_right_pct", "hind_separation_bl", "climb_pct"]),
            (LText("Quality", "数据质量"), ["pose_coverage_pct"]),
        ])
        let detail = TSTDetail(motion: Signal.downsample(t: s.t, v: motion, maxPoints: 1200),
                               threshold: p.motionThreshold, bouts: bouts, climbing: climbing,
                               perMinute: perMinute, window: Interval(start: w0, end: w1))
        return AnalysisResult(metrics: groupedMetrics, notes: notes, tst: detail, cylinder: nil, gait: nil,
                              analyzedAt: Date(), poseCoverage: coverage)
    }
}
