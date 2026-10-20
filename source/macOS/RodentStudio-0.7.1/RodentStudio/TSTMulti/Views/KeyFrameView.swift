import SwiftUI
import Charts

/// Review the key frame (start of the analysis), nudge it, check the analysed band, set the window.
/// The time controls sit directly under the picture, like a video player; "Analyse" is in the footer.
struct TSTKeyFrameView: View {
    @Environment(TSTAppModel.self) private var model
    var onShowSettings: () -> Void

    private var duration: Double { model.info?.duration ?? 1 }

    var body: some View {
        TSTSplitLayout {
            if let img = model.keyFrameImage ?? model.preview, let layout = model.layout {
                TSTChamberEditor(image: img, layout: layout, showBand: true,
                                 motionBoxes: model.settings.metric == .box ? model.motionBoxes() : [])
                    .aspectRatio(CGFloat(layout.imageWidth) / CGFloat(max(1, layout.imageHeight)), contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            scrubber
            if let k = model.keyResult, !k.times.isEmpty {
                TSTPresenceTimeline(result: k, keyTime: model.keyTime,
                                    analysisEnd: model.keyTime + model.analysisWindow.duration,
                                    duration: duration,
                                    onSeek: { model.setKeyTime($0, manual: true) })
                    .frame(height: CGFloat(k.selected.count) * 16 + 44)
            }
            Label(model.settings.metric == .box
                  ? L("Orange = mice detected at this moment; dashed cyan = motion box per chamber (where the mouse was detected after the key frame, + 10 %). Pixel changes are counted only inside the cyan box. Yellow handles = analysed band.",
                      "橙色框为此刻检测到的小鼠；青色虚线框为各格的运动框（关键帧之后检测到小鼠的范围，外扩 10%）。只统计青色框内的像素变化。黄色手柄为分析带。")
                  : L("Orange boxes = detected mice. Drag the yellow handles so the band covers every mouse with a little room above it.",
                      "橙色框为检测到的小鼠。拖动黄色手柄，使分析带覆盖每只小鼠并在上方留一点空间。"),
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } inspector: {
            startSection
            windowSection
            outlineSection
            TSTInspectorSection(title: L("Scoring", "评分"),
                                footer: L("Can also be changed after the analysis, without processing the video again.",
                                          "分析后仍可修改，无需重新处理视频。")) {
                TSTScoringControls()
            }
            Button(L("Detection settings…", "检测设置…"), systemImage: "gearshape") { onShowSettings() }
                .controlSize(.small)
        }
    }

    // MARK: Time under the picture

    private var scrubber: some View {
        HStack(spacing: 6) {
            nudge(-1, symbol: "backward.end.fill", help: L("1 s earlier", "提前 1 秒"))
            nudge(-0.25, symbol: "chevron.left", help: L("0.25 s earlier", "提前 0.25 秒"))
            Slider(value: Binding(get: { model.keyTime }, set: { model.setKeyTime($0, manual: true) }),
                   in: 0...max(1, duration - 1))
                .help(L("Start of the analysis (key frame)", "分析起点（关键帧）"))
            nudge(0.25, symbol: "chevron.right", help: L("0.25 s later", "推后 0.25 秒"))
            nudge(1, symbol: "forward.end.fill", help: L("1 s later", "推后 1 秒"))
            Text(TSTFormat.seconds(model.keyTime))
                .monospacedDigit()
                .foregroundStyle(model.keyFrameIsManual ? Color.orange : Color.primary)
                .frame(minWidth: 120, alignment: .trailing)
        }
    }

    private func nudge(_ d: Double, symbol: String, help: String) -> some View {
        Button {
            model.setKeyTime(model.keyTime + d, manual: true)
        } label: {
            Image(systemName: symbol).frame(width: 14)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    // MARK: Inspector

    private var startSection: some View {
        TSTInspectorSection(title: L("Start (key frame)", "起点（关键帧）")) {
            LabeledContent(L("Analysis starts at", "分析起点"), value: TSTFormat.seconds(model.keyTime))
                .monospacedDigit()
            if let detected = model.keyResult?.keyTime {
                if model.keyFrameIsManual {
                    Label(L("Set by hand", "手动设定"), systemImage: "hand.point.up.left")
                        .font(.caption).foregroundStyle(.orange)
                    Button(String(format: L("Use the detected key frame (%@)", "恢复自动关键帧（%@）"), TSTFormat.seconds(detected))) {
                        model.resetKeyTimeToDetected()
                    }
                    .controlSize(.small)
                } else {
                    Label(L("Detected: every selected mouse hangs from here on.", "自动识别：从此刻起所有选中的小鼠都已悬挂。"),
                          systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            } else {
                Label(L("No automatic key frame. Move the slider under the picture to the moment the last mouse is hung.",
                        "没有自动关键帧。请拖动画面下方的滑块，定位到最后一只小鼠挂好的时刻。"),
                      systemImage: "hand.draw")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let missing = missingMice
            if !missing.isEmpty {
                Label(String(format: L("No mouse detected in chamber %@ at this moment.", "此时第 %@ 格未检测到小鼠。"),
                             TSTFormat.list(missing)),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var outlineSection: some View {
        TSTInspectorSection(title: L("Mouse outline (posture measures)", "小鼠轮廓（轮廓类指标）"),
                            footer: L("Refined: limbs, paws and the fur edge are grown back after the tail is removed, so the outline follows the mouse and kicking counts as movement. Turn off only to reproduce analyses made with the original outline; the immobility threshold should be calibrated for the outline you use. Takes effect on the next analysis.",
                                      "精细轮廓：去掉尾巴后，把四肢、爪子和毛边补回来，轮廓更贴合，蹬腿也会计为运动。只有在需要复现旧轮廓的分析结果时才关闭；不动阈值应针对所用轮廓单独校准。下次分析时生效。")) {
            Toggle(L("Refined outline (recommended)", "精细轮廓（推荐）"),
                   isOn: Binding(get: { model.settings.useRefinedOutline },
                                 set: { model.settings.refinedOutline = $0 }))
        }
    }

    /// How the mice are timed: each from its own suspension (scan), or all from the key frame.
    @ViewBuilder
    private var timingNote: some View {
        if let onsets = model.perMouseOnsets, let layout = model.layout {
            DisclosureGroup(L("Each mouse is timed from its own suspension", "每只鼠从自己挂上的时刻计时")) {
                ForEach(Array(onsets.enumerated()), id: \.offset) { item in
                    if item.offset < layout.enabled.count && layout.enabled[item.offset] {
                        LabeledContent(String(format: L("Chamber %d", "第 %d 格"), item.offset + 1),
                                       value: TSTFormat.seconds(item.element))
                            .monospacedDigit()
                    }
                }
            }
            .font(.caption)
        } else {
            Label(L("All mice are timed from the key frame (start set by hand, or no scan).", "所有小鼠都从关键帧计时（手动设定起点或没有扫描）。"),
                  systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingMice: [Int] {
        guard let l = model.layout else { return [] }
        let a = BoxOps.assign(model.keyFrameBoxes, to: l, minConfidence: model.stored.keyFrame.minConfidence)
        return (0..<l.count).filter { $0 < l.enabled.count && l.enabled[$0] && $0 < a.count && a[$0] == nil }.map { $0 + 1 }
    }

    private var windowSection: some View {
        @Bindable var model = model
        let w = model.analysisWindow
        let testSec: Double = model.settings.standardTestSec
        let primaryStart: Double = testSec - min(model.settings.lastWindowSec, testSec)
        let primaryLabel: String = TSTSessionMetrics.minutes(primaryStart, testSec)
        let earlyLabel: String = TSTSessionMetrics.minutes(0, primaryStart)
        let testLabel: String = TSTSessionMetrics.minutes(0, testSec)
        return TSTInspectorSection(title: L("Analysis window", "分析时间窗"),
                                   footer: L("By default everything from the key frame to the end of the video is analysed. Turn on “Stop after” only for a fixed protocol length (standard TST: 6 min). Immobility in the last part is reported separately.",
                                             "默认分析从关键帧到视频结束的全部内容。只有需要固定时长（标准 TST 为 6 分钟）时才打开“到此为止”。末段的不动时间会单独报告。")) {
            Toggle(L("Stop after a set duration", "到此为止（限定时长）"),
                   isOn: Binding(get: { model.settings.stopsAtDuration }, set: { model.settings.limitDuration = $0 ? true : nil }))
            if model.settings.stopsAtDuration {
                TSTNumberRow(title: L("Duration", "时长"), unit: L("s", "秒"), value: $model.settings.durationSec, range: 10...3600)
            }
            TSTNumberRow(title: L("Standard test", "标准测试时长"), unit: L("s", "秒"),
                         value: Binding(get: { model.settings.standardTestSec }, set: { model.settings.testLengthSec = $0 }),
                         range: 60...3600, step: 60)
            TSTNumberRow(title: L("★ Primary = last", "★ 主要指标 = 最后"), unit: L("s", "秒"), value: $model.settings.lastWindowSec, range: 0...3600, step: 60)
            Text(String(format: L("Primary measure: immobility in minutes %@ after each mouse was hung; minutes %@ and %@ are reported too.",
                                  "主要指标：每只鼠挂上后第 %@ 分钟的不动时间；同时报告第 %@ 分钟和第 %@ 分钟。"),
                        primaryLabel, earlyLabel, testLabel))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            timingNote
            LabeledContent(L("Analysed part of the video", "视频中的分析区间"),
                           value: TSTFormat.seconds(w.start) + " – " + TSTFormat.seconds(w.start + w.duration))
                .font(.callout)
                .monospacedDigit()
            if let reason = w.cutReason {
                Label(String(format: L("%.0f s analysed: %@.", "分析 %.0f 秒：%@。"), w.duration, reason),
                      systemImage: "scissors")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let missing = model.mouseMissingFrom {
                Label(String(format: L("From %@ a mouse is no longer detected (taken down?). The analysis still runs to the end; frames without the mouse count as “no mouse”, not as immobility.",
                                       "从 %@ 起有小鼠不再被检测到（已取下？）。分析仍会进行到结尾；没有小鼠的帧计为“无小鼠”，不计为不动。"),
                             TSTFormat.seconds(missing)),
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.result != nil && !model.resultMatchesSetup {
                Label(L("Start, band, chambers or window changed since the last analysis — analyse again to update the results.",
                        "自上次分析后，起点、分析带、格子或时间窗已改变——请重新分析以更新结果。"),
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Measure, threshold and minimum bout. Used before the analysis and on the results page.
struct TSTScoringControls: View {
    @Environment(TSTAppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            Picker(L("Measure", "运动指标"), selection: $model.settings.metric) {
                Text(L("Pixel change in the box (recommended)", "运动框内像素变化（推荐）")).tag(MotionMetric.box)
                Text(L("Posture change of the outline", "轮廓姿态变化")).tag(MotionMetric.shape)
                Text(L("Pixel change on the outline", "轮廓内像素变化")).tag(MotionMetric.pixel)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L("Immobility threshold", "不动阈值"))
                    Spacer()
                    Text(String(format: "%.2f %%", model.settings.immobilityThreshold)).monospacedDigit()
                }
                Slider(value: $model.settings.immobilityThreshold, in: 0.25...15, step: 0.25)
            }
            TSTNumberRow(title: L("Minimum bout", "最短不动片段"), unit: L("s", "秒"),
                         value: $model.settings.minBoutSec, range: 0...10, step: 0.5)
        }
    }
}

/// Per-chamber detection presence (bars), key frame and analysis end. Click to move the key frame.
struct TSTPresenceTimeline: View {
    let result: KeyFrameResult
    let keyTime: Double?
    let analysisEnd: Double?
    let duration: Double
    var onSeek: ((Double) -> Void)? = nil

    private struct Seg: Identifiable { let id = UUID(); let chamber: String; let a: Double; let b: Double; let selected: Bool }

    var body: some View {
        let names = result.selected.indices.map { "#\($0 + 1)" }
        let dt = result.times.count > 1 ? result.times[1] - result.times[0] : 0.25
        var segs: [Seg] = []
        for c in result.presence.indices where c < names.count {
            let p = result.presence[c]
            var i = 0
            while i < p.count {
                if p[i] {
                    var j = i
                    while j < p.count && p[j] { j += 1 }
                    if i < result.times.count && j - 1 < result.times.count {
                        segs.append(Seg(chamber: names[c], a: result.times[i], b: result.times[j - 1] + dt,
                                        selected: c < result.selected.count && result.selected[c]))
                    }
                    i = j
                } else { i += 1 }
            }
        }
        return Chart {
            if let keyTime, let analysisEnd {
                RectangleMark(xStart: .value("a", keyTime), xEnd: .value("b", analysisEnd))
                    .foregroundStyle(Color.accentColor.opacity(0.12))
            }
            ForEach(segs) { s in
                RectangleMark(xStart: .value("Start", s.a), xEnd: .value("End", s.b),
                              y: .value("Chamber", s.chamber), height: .ratio(0.65))
                    .foregroundStyle(s.selected ? Color.orange : Color.gray.opacity(0.5))
            }
            if let keyTime {
                RuleMark(x: .value("Key frame", keyTime))
                    .foregroundStyle(Color.red)
                    .annotation(position: .top, alignment: .leading) {
                        Text(L("start", "起点")).font(.caption2).foregroundStyle(.red)
                    }
            }
        }
        .chartYScale(domain: names)
        .chartXScale(domain: 0...max(1, duration))
        .chartXAxisLabel(onSeek == nil
                         ? L("Time in video (s) · bars = mouse detected", "视频时间（秒）· 条带 = 检测到小鼠")
                         : L("Time in video (s) · bars = mouse detected · click to move the start", "视频时间（秒）· 条带 = 检测到小鼠 · 点击可移动起点"))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let onSeek, let plot = proxy.plotFrame else { return }
                        let x = loc.x - geo[plot].origin.x
                        if let t: Double = proxy.value(atX: x) { onSeek(max(0, t)) }
                    }
            }
        }
    }
}
