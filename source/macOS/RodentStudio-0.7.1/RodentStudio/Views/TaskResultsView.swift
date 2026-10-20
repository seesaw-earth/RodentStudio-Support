// TaskResultsView.swift — "Results" tab of the Review step: the result screen of the task's original app,
// computed automatically from the saved tracking with the calibration, analysis window, phase and
// parameters saved for this video (one source of truth: Calibrate). Changing them in Calibrate updates
// the results without re-tracking. Figures and tables export in English. The computation is
// SessionResultsEngine's, the same one the task and group summaries use; what is computed here is handed
// to the task summaries.

import SwiftUI
import AppKit

struct TaskResultsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var run: NativeRunSession
    @EnvironmentObject private var taskData: TaskDataModel

    let assay: StudyAssay
    let video: VideoRecord
    let onCalibrate: () -> Void
    /// Opens the tracking check (Frame review & export tab).
    let onOpenCheck: () -> Void

    typealias Output = SessionOutput

    @State private var output: Output?
    @State private var outputKey = ""
    @State private var failure: String?
    @State private var computing = false
    @State private var message = ""
    @State private var includeFigures = true
    @State private var exporting = false

    private var phase: String { video.effectivePhase(for: assay) }

    /// Everything the results depend on (the session-metrics key: run, setup, phase, analyzer), whether the
    /// run is in memory, and the language. A change of any part recomputes them; results of another key are
    /// never shown.
    private var key: String {
        let loaded = assay.module == .flow ? "flow" : (run.holdsResult(of: video, store: store) ? "loaded" : "waiting")
        return [taskData.key(video, assay: assay), loaded, Lang.isChinese ? "zh" : "en"].joined(separator: "|")
    }

    private var current: Output? { outputKey == key ? output : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryBar
                checkBanner
                if let failure, outputKey == key {
                    RPBanner(text: failure, style: .warning)
                    if !video.hasSetup(for: assay) {
                        Button(L("Calibrate", "去标定")) { onCalibrate() }.buttonStyle(.borderedProminent)
                    }
                } else if let current {
                    resultBody(current)
                    exportBar
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L("Computing results…", "正在计算结果…")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(L("Desktop port of the original analyzers. Compare with the iOS app and with manual scoring before reporting.",
                       "原版分析算法的桌面移植。用于报告前，请与 iOS 原版及人工评分对照。"))
                    .font(.caption).foregroundStyle(.orange)
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.bottom, 20)
        }
        .task(id: key) { await compute(key) }
    }

    // MARK: Summary of what the numbers are computed from

    private var summaryBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(assay.displayName).font(.headline)
                Text(windowDescription).font(.callout).foregroundStyle(.secondary)
                if !phase.isEmpty {
                    Text(L("Phase", "阶段") + ": " + assay.phaseTitle(phase)).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(L("Change in Calibrate", "在“校准”中修改")) { onCalibrate() }
                .help(L("The analysis window, zones and parameters are set in Calibrate; results update without re-tracking.",
                        "分析时间段、区域和参数在“校准”中设置；修改后结果会更新，无需重新追踪。"))
        }
        .padding(12)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var windowDescription: String {
        switch assay.module {
        case .pose?:
            guard let p = video.calibration?.pose?.params else { return L("Analysis window: not set (calibrate first)", "分析时间段：未设置（请先标定）") }
            return Self.window(start: p.windowStart, length: p.windowLength)
        case .limb?:
            if assay.limbAssay == .tailSuspension {
                let p = video.calibration?.limb?.params.tst ?? AssayParams.defaults(for: .tailSuspension).tst
                return Self.window(start: p.windowStart, length: max(0, p.windowEnd - p.windowStart))
            }
            return L("Analysis window: whole recording", "分析时间段：整段视频")
        case .flow?:
            guard video.calibration?.flow != nil else { return L("Analysis window: not set (calibrate first)", "分析时间段：未设置（请先标定）") }
            let w = SessionResultsEngine.analysisWindow(video, assay: assay)
            return Self.window(start: w.start, length: w.length)
        case nil:
            return ""
        }
    }

    static func window(start: Double, length: Double) -> String {
        if length > 0 {
            return String(format: L("Analysis window: %@ – %@ (%@)", "分析时间段：%@ – %@（%@）"),
                          RPFmt.clock(start), RPFmt.clock(start + length), RPFmt.clock(length))
        }
        if start > 0 {
            return String(format: L("Analysis window: from %@ to the end", "分析时间段：%@ 至结束"), RPFmt.clock(start))
        }
        return L("Analysis window: whole recording", "分析时间段：整段视频")
    }

    @ViewBuilder
    private var checkBanner: some View {
        switch video.reviewVerdict {
        case .unreviewed:
            HStack {
                Label(L("Tracking not checked yet. Playing through a range of frames (e.g. 0–99) is enough.", "尚未复核追踪。播放查看一段帧（如第 0–99 帧）即可。"),
                      systemImage: "circle.dashed")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(L("Check tracking", "复核追踪")) { onOpenCheck() }
            }
        case .issues:
            HStack {
                RPBanner(text: String(format: L("The tracking check found problems (%d flagged). Interpret these results with care; the session can be excluded from group summaries in its information.",
                                                "追踪复核发现问题（标记 %d 处）。请谨慎解读这些结果；可在该次实验的信息中将其排除出组间汇总。"),
                                      video.currentReview?.flagged.count ?? 0), style: .warning)
                Button(L("Open check", "查看复核")) { onOpenCheck() }
            }
        case .passed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func resultBody(_ out: Output) -> some View {
        switch out {
        case .pose(let report, let category):
            PoseReportView(report: report, category: category) { message = $0 }
        case .limb(let result, let limbAssay, let size):
            if !video.hasSetup(for: assay) {
                RPBanner(text: L("Default RodentLimb parameters are used (this video has no saved calibration).", "使用 RodentLimb 默认参数（该视频没有保存标定）。"), style: .info)
            }
            LimbResultView(result: result, assay: limbAssay, videoSize: size)
        case .flow(let f):
            ForEach(f.notes.map(\.text), id: \.self) { note in RPBanner(text: note, style: .info) }
            FlowResultView(assay: f.assay, phase: f.phase, computation: f.computation, config: f.config, samples: f.samples)
        }
    }

    private var exportBar: some View {
        HStack(spacing: 12) {
            Button(exporting ? L("Exporting…", "正在导出…") : L("Export results and figures…", "导出结果与图表…")) { export() }
                .buttonStyle(.borderedProminent)
                .disabled(exporting)
            Toggle(L("Include figures (PNG, as in the app)", "包含图表（PNG，与 App 相同）"), isOn: $includeFigures)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Compute

    @MainActor
    private func compute(_ key: String) async {
        guard video.runState == .complete else { return }
        if outputKey == key, output != nil || failure != nil { return }
        computing = true
        defer { computing = false }
        do {
            var loaded: LoadedTrackingRun?
            if assay.module != .flow {
                // The Review step loads the run; this view recomputes when it is in memory (the key changes).
                guard run.holdsResult(of: video, store: store) else { return }
                if let short = run.shortResult {
                    loaded = .short(short)
                } else if let manifest = run.longManifest, let folder = run.longDirectory {
                    loaded = .long(manifest, folder: folder, videoURL: run.longVideoURL)
                } else {
                    return
                }
            }
            let result = try await SessionResultsEngine.compute(video: video, assay: assay, store: store, loaded: loaded)
            guard !Task.isCancelled else { return }
            output = result
            failure = nil
            outputKey = key
            taskData.record(result, video: video, assay: assay, store: store)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            output = nil
            failure = error.localizedDescription
            outputKey = key
        }
    }

    // MARK: Export

    private var metadata: [String: String] {
        SessionResultsEngine.metadata(video: video, assay: assay, project: store.selectedProject)
    }

    @MainActor
    private func export() {
        guard let out = current else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here", "导出到此处")
        panel.message = L("A new folder with the results of this animal is created inside the chosen folder.", "将在所选文件夹中新建一个文件夹，存放该动物的结果。")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let access = parent.startAccessingSecurityScopedResource()
        defer { if access { parent.stopAccessingSecurityScopedResource() } }
        exporting = true
        defer { exporting = false }
        do {
            let folder = try ExportFolder.make(in: parent, name: video.displayName + "_" + (video.sessionNumber.map { "s\($0)_" } ?? "") + assay.rawValue)
            let urls: [URL]
            switch out {
            case .pose(let report, let category):
                urls = try PoseReportExport.write(report, category: category, metadata: metadata, to: folder, includeFigures: includeFigures)
            case .limb(let result, let limbAssay, let size):
                let pairs = metadata.keys.sorted().map { ($0, metadata[$0] ?? "") }
                urls = try LimbResultExport.write(result, assay: limbAssay, setup: video.hasSetup(for: assay) ? video.calibration?.limb : nil,
                                                  metadata: pairs, videoSize: size, to: folder, includeFigures: includeFigures)
            case .flow(let f):
                urls = try FlowResultExport.write(assay: f.assay, phase: f.phase, computation: f.computation, config: f.config,
                                                  run: f.run, samples: f.samples, metadata: metadata, to: folder, includeFigures: includeFigures)
            }
            message = String(format: L("Exported %d files to %@", "已导出 %d 个文件到 %@"), urls.count, folder.path)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            message = L("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }
}
