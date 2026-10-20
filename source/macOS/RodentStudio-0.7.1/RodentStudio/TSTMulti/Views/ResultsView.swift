import SwiftUI
import Charts

/// Everything below the chamber → animal table on the results page: scoring (instant re-score), all
/// measures, ethogram, motion trace and per-minute immobility. Chambers are labelled with the animal IDs
/// as they are typed in the table above.
struct TSTResultDetails: View {
    @Environment(TSTAppModel.self) private var model
    /// Chamber number → animal ID typed for it ("" when none yet).
    var animalLabel: (Int) -> String = { _ in "" }
    @State private var selectedChamber: Int?
    @State private var showCalibration = false

    var body: some View {
        if let r = model.result {
            let analysed = r.summaries.filter(\.analysed)
            VStack(alignment: .leading, spacing: 16) {
                FigureCard {
                    FigureCardHeader(L("Scoring", "评分"), symbol: "slider.horizontal.3",
                                     subtitle: L("Changes apply at once to every chamber; the video is not processed again. Calibrate the threshold once per setup against hand scoring.",
                                                 "修改立即作用于所有格子，不需要重新处理视频。每套装置应先用人工评分校准一次阈值。"))
                    TSTScoringControls()
                        .frame(maxWidth: 520, alignment: .leading)
                    Button(L("Calibrate against manual scores…", "用人工评分校准阈值…"),
                           systemImage: "slider.horizontal.below.square.and.square.filled") {
                        showCalibration = true
                    }
                }

                FigureCard {
                    FigureCardHeader(L("All measures", "全部指标"), symbol: "tablecells")
                    TSTSummaryTable(result: r, animalLabel: animalLabel)
                    Text(L("Every mouse is timed from its own suspension. ★ = primary measure (last 4 min of the 6-min test). Intensity = mean motion while the mouse is mobile (higher = more vigorous struggling). “No mouse” = frames without the mouse (taken down, out of view); review chambers above 10 %.",
                           "每只小鼠从它自己挂上的时刻开始计时。★ 为主要指标（6 分钟测试的最后 4 分钟）。强度 = 小鼠活动时的平均运动量（越高挣扎越剧烈）。“无小鼠”为看不到小鼠的帧（已取下、出画）；超过 10% 的格子请复核。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FigureCard {
                    FigureCardHeader(L("Ethogram", "行为时间图"), symbol: "chart.bar.xaxis",
                                     subtitle: L("Orange = scored immobility, from each mouse's suspension. Dashed lines = the primary window (minutes 2–6).",
                                                 "橙色 = 判定为不动，从各鼠挂上时起计。虚线 = 主要时间窗（第 2–6 分钟）。"))
                    TSTEthogramChart(result: r, animalLabel: animalLabel)
                        .frame(height: CGFloat(max(3, analysed.count)) * 26 + 44)
                }

                FigureCard {
                    FigureCardHeader(L("Motion trace", "运动曲线"), symbol: "waveform.path.ecg",
                                     subtitle: L("Red dashed line = threshold; shaded = immobile.", "红色虚线 = 阈值；阴影 = 不动。"))
                    if !analysed.isEmpty {
                        Picker(L("Chamber", "格子"), selection: Binding(get: { selectedChamber ?? analysed[0].chamber },
                                                                       set: { selectedChamber = $0 })) {
                            ForEach(analysed) { s in
                                Text(TSTChartLabel.chamber(s.chamber, animalLabel(s.chamber))).tag(s.chamber)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 320)
                        let c = selectedChamber ?? analysed[0].chamber
                        if c >= 1 && c <= r.traces.count {
                            TSTMotionChart(trace: r.traces[c - 1], threshold: model.settings.immobilityThreshold,
                                           offset: r.traces[c - 1].onsetSec,
                                           marks: TSTWindowMarks.marks(r.settings))
                                .frame(height: 220)
                        }
                    }
                }

                FigureCard {
                    FigureCardHeader(L("Immobility per minute", "每分钟不动时间"), symbol: "chart.bar")
                    TSTPerMinuteChart(result: r, animalLabel: animalLabel)
                        .frame(height: 220)
                }
            }
            .sheet(isPresented: $showCalibration) {
                TSTCalibrationView(chambers: r.summaries.count).environment(model)
            }
            // Threshold / measure / bout edits re-score instantly (no video decoding).
            .onChange(of: model.settings) { model.rescore() }
        }
    }
}

enum TSTChartLabel {
    /// "#3" or "#3 · M07".
    static func chamber(_ c: Int, _ animal: String) -> String {
        let a = animal.trimmingCharacters(in: .whitespacesAndNewlines)
        return a.isEmpty ? "#\(c)" : "#\(c) · \(a)"
    }
}

// MARK: - Summary table

struct TSTSummaryTable: View {
    let result: TSTMultiAnalysisResult
    var animalLabel: (Int) -> String = { _ in "" }

    private var windows: (early: String, primary: String, test: String) {
        let test = result.settings.standardTestSec
        let primaryStart = test - min(result.settings.lastWindowSec, test)
        return (TSTSessionMetrics.minutes(0, primaryStart), TSTSessionMetrics.minutes(primaryStart, test),
                TSTSessionMetrics.minutes(0, test))
    }

    var body: some View {
        let w = windows
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    head(L("Chamber", "格子")).gridColumnAlignment(.leading)
                    head(L("Animal", "小鼠")).gridColumnAlignment(.leading)
                    head(L("Hung at", "挂上时刻"))
                    head(String(format: L("Min %@", "第 %@ 分"), w.early))
                    head(String(format: L("★ Min %@", "★ 第 %@ 分"), w.primary))
                    head(L("★ %", "★ %"))
                    head(String(format: L("Min %@", "第 %@ 分"), w.test))
                    head(L("Latency", "潜伏期"))
                    head(L("Bouts", "次数"))
                    head(L("Intensity", "强度"))
                    head(L("Whole rec.", "全程"))
                    head(L("No mouse", "无小鼠"))
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(result.summaries, id: \.chamber) { s in
                    row(s)
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private func row(_ s: ChamberSummary) -> some View {
        let animal = animalLabel(s.chamber)
        GridRow {
            Text("\(s.chamber)").bold()
            Text(animal.isEmpty ? "—" : animal)
                .foregroundStyle(animal.isEmpty ? Color.secondary : Color.primary)
            if s.analysed {
                Text(TSTFormat.seconds(result.settings.startSec + (s.onsetSec ?? 0)))
                Text(seconds(s.earlyImmobileSec))
                Text(seconds(s.primaryImmobileSec ?? s.immobileLastWindowSec)).bold()
                Text(percent(s.primaryImmobilePercent))
                Text(seconds(s.testImmobileSec))
                Text(seconds(s.latencySec))
                Text("\(s.bouts)")
                Text(s.mobilityIntensity.map { String(format: "%.1f", $0) } ?? "–")
                Text(seconds(s.immobileTotalSec))
                Text(String(format: "%.0f %%", s.noMousePercent))
                    .foregroundStyle(s.noMousePercent > 10 ? Color.orange : Color.primary)
            } else {
                Text(L("not analysed", "未分析"))
                    .foregroundStyle(.secondary)
                    .gridCellColumns(10)
            }
        }
        .monospacedDigit()
        if s.analysed, let coverage = s.testCoverage, coverage < 0.98 {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Label(String(format: L("Only %.0f %% of the 6-min test was recorded after this mouse was hung.",
                                       "该鼠挂上后，6 分钟测试只录到了 %.0f%%。"), 100 * coverage),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .gridCellColumns(11)
                    .gridCellAnchor(.leading)
            }
        }
    }

    private func seconds(_ v: Double?) -> String { v.map { String(format: "%.1f s", $0) } ?? "–" }
    private func percent(_ v: Double?) -> String { v.map { String(format: "%.0f", $0) } ?? "–" }

    private func head(_ s: String) -> some View {
        Text(s).font(.caption.bold()).foregroundStyle(.secondary)
    }
}

/// Boundaries of the standard windows (primary start, test end), in seconds since suspension.
enum TSTWindowMarks {
    static func marks(_ settings: AnalysisSettings) -> [Double] {
        let test = settings.standardTestSec
        let primaryStart = test - min(settings.lastWindowSec, test)
        return primaryStart > 0 ? [primaryStart, test] : [test]
    }
}

// MARK: - Charts

struct TSTBout: Identifiable {
    let id = UUID()
    let chamber: String
    let start: Double
    let end: Double
}

func tstBouts(of trace: ChamberTrace, chamber: String, dt: Double, offset: Double = 0) -> [TSTBout] {
    var out: [TSTBout] = []
    var i = 0
    let n = min(trace.immobile.count, trace.time.count)
    while i < n {
        if trace.immobile[i] {
            var j = i
            while j < n && trace.immobile[j] { j += 1 }
            out.append(TSTBout(chamber: chamber, start: trace.time[i] - offset, end: trace.time[j - 1] + dt - offset))
            i = j
        } else { i += 1 }
    }
    return out
}

struct TSTEthogramChart: View {
    let result: TSTMultiAnalysisResult
    var animalLabel: (Int) -> String = { _ in "" }

    var body: some View {
        let dt = 1 / max(result.fps, 0.001)
        let analysed = result.summaries.filter(\.analysed).filter { $0.chamber >= 1 && $0.chamber <= result.traces.count }
        let names = analysed.map { TSTChartLabel.chamber($0.chamber, animalLabel($0.chamber)) }
        let data = zip(analysed, names).flatMap { s, name in
            tstBouts(of: result.traces[s.chamber - 1], chamber: name, dt: dt, offset: result.traces[s.chamber - 1].onsetSec)
        }
        let marks = TSTWindowMarks.marks(result.settings)
        return Chart {
            ForEach(data) { b in
                RectangleMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end),
                              y: .value("Chamber", b.chamber), height: .ratio(0.7))
                    .foregroundStyle(Color.orange)
            }
            ForEach(marks, id: \.self) { m in
                RuleMark(x: .value("Window", m))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: names)
        .chartXScale(domain: 0...max(1, result.settings.durationSec))
        .chartXAxisLabel(L("Time since suspension (s)", "挂上后的时间（秒）"))
    }
}

struct TSTMotionChart: View {
    let trace: ChamberTrace
    let threshold: Double
    /// Seconds subtracted from the trace times (the mouse's suspension), and window boundaries to mark.
    var offset: Double = 0
    var marks: [Double] = []

    private struct Pt: Identifiable { let id: Int; let t: Double; let v: Double }

    var body: some View {
        let n = min(trace.time.count, trace.motion.count)
        let stride = max(1, n / 1200)
        let pts = Swift.stride(from: 0, to: n, by: stride).map { Pt(id: $0, t: trace.time[$0] - offset, v: trace.motion[$0]) }
        let sorted = trace.motion.filter { $0.isFinite }.sorted()
        let p98 = sorted.isEmpty ? 1 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.98))]
        let ymax = max(threshold * 3, p98 * 1.2, 1)
        let dt = n > 1 ? trace.time[1] - trace.time[0] : 0.1
        let immobile = tstBouts(of: trace, chamber: "", dt: dt, offset: offset)
        return Chart {
            ForEach(immobile) { b in
                RectangleMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end),
                              yStart: .value("y0", 0), yEnd: .value("y1", ymax))
                    .foregroundStyle(Color.orange.opacity(0.22))
            }
            ForEach(pts) { p in
                LineMark(x: .value("Time (s)", p.t), y: .value("Motion (%)", p.v.isFinite ? min(p.v, ymax) : 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            RuleMark(y: .value("Threshold", threshold))
                .foregroundStyle(Color.red)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            ForEach(marks, id: \.self) { m in
                RuleMark(x: .value("Window", m))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYScale(domain: 0...ymax)
        .chartXAxisLabel(L("Time since suspension (s)", "挂上后的时间（秒）"))
        .chartYAxisLabel(L("Motion (% of body)", "运动（占鼠体 %）"))
    }
}

struct TSTPerMinuteChart: View {
    let result: TSTMultiAnalysisResult
    var animalLabel: (Int) -> String = { _ in "" }

    private struct Bar: Identifiable { let id = UUID(); let minute: String; let chamber: String; let sec: Double }

    var body: some View {
        let bars = result.summaries.filter { $0.analysed }.flatMap { s in
            s.perMinuteImmobileSec.enumerated().map {
                Bar(minute: "\($0.offset + 1)", chamber: TSTChartLabel.chamber(s.chamber, animalLabel(s.chamber)), sec: $0.element)
            }
        }
        return Chart(bars) { b in
            BarMark(x: .value("Minute", b.minute), y: .value("Immobile (s)", b.sec))
                .foregroundStyle(by: .value("Chamber", b.chamber))
                .position(by: .value("Chamber", b.chamber))
        }
        .chartYScale(domain: 0...60)
        .chartXAxisLabel(L("Minute after suspension", "挂上后第几分钟"))
        .chartYAxisLabel(L("Immobile (s)", "不动（秒）"))
    }
}
