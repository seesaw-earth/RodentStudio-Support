// TaskRunViews.swift — the Analyse and Review steps of the guided workflow.
//
// One rule for every module: Analyse only tracks (the method comes from the task: RodentPose /
// RodentLimb Core ML model, or RodentFlow's classic centroid tracker); every analysis goes through the
// same queue (one video at a time, pausable, resumable). Review shows the results of the task's
// original app computed with the analysis window and parameters saved in Calibrate, and the frame review
// (play / step through the saved tracking on the video, tracking check, raw exports).

import SwiftUI

struct TaskRunPanel: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var run: NativeRunSession

    let assay: StudyAssay
    let video: VideoRecord
    let taskVideos: [VideoRecord]
    let onCalibrate: () -> Void
    let onReview: () -> Void

    @State private var confirmRerun = false

    private var isFlow: Bool { assay.module == .flow }
    private var model: PoseModelKind? { assay.modelRoute }
    private var modelReady: Bool { isFlow || (model.map { NativeModelCatalog.available($0) } ?? false) }
    /// RodentFlow tracking needs the arena calibration; Core ML tracking does not use the calibration.
    private var calibrationRequired: Bool { isFlow }
    /// Every session needs its animal, date and session number before it is analysed.
    private func canStart(_ v: VideoRecord) -> Bool { v.hasSessionInfo && (!calibrationRequired || v.hasSetup(for: assay)) }
    private var remaining: [VideoRecord] {
        taskVideos.filter { $0.runState != .complete && $0.runState != .running && !run.isQueued($0.id) && canStart($0) }
    }
    private var waitingForCalibration: Int {
        taskVideos.filter { $0.runState != .complete && $0.hasSessionInfo && calibrationRequired && !$0.hasSetup(for: assay) }.count
    }
    private var waitingForInfo: Int {
        taskVideos.filter { $0.runState != .complete && !$0.hasSessionInfo }.count
    }
    private var analysedCount: Int { taskVideos.filter { $0.runState == .complete }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Analyse", "分析")).font(.title3.bold())
            if !assay.canRunOnDesktop {
                unavailable
            } else if !modelReady {
                modelMissing
            } else {
                thisVideoCard
                taskCard
                if !video.hasSessionInfo {
                    Label(String(format: L("Fill in the session information first (missing: %@).", "请先填写实验信息（缺少：%@）。"),
                                 video.missingSessionFields.joined(separator: L(", ", "、"))),
                          systemImage: "exclamationmark.circle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if !video.hasSetup(for: assay) {
                    HStack(alignment: .top) {
                        Label(calibrationRequired
                              ? L("Calibrate the arena first: RodentFlow's tracker maps the mouse into the calibrated arena.",
                                  "请先标定场地：RodentFlow 追踪器需要把小鼠位置映射到标定后的场地中。")
                              : L("Not calibrated yet. Tracking does not use the calibration, so you can also calibrate afterwards — results update without re-running.",
                                  "尚未标定。追踪不依赖标定，也可以之后再标定——结果会更新，无需重新识别。"),
                              systemImage: "viewfinder")
                            .font(.callout)
                            .foregroundStyle(calibrationRequired ? Color.orange : Color.secondary)
                        Spacer()
                        Button(L("Calibrate", "去标定")) { onCalibrate() }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(methodNote, systemImage: isFlow ? "dot.scope" : "cpu")
                    Label(L("Results are saved in the app's own folder, so a paused or interrupted analysis resumes where it stopped. Source videos are only read.",
                            "结果保存在 App 自己的文件夹中，暂停或中断后可从停下处继续。原始视频只读不改。"), systemImage: "externaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(L("Analyse this video again? The previous results stay on disk; review uses the new run.",
                              "重新分析该视频？之前的结果仍保留在磁盘上，复核将使用新结果。"),
                            isPresented: $confirmRerun, titleVisibility: .visible) {
            Button(L("Analyse again", "重新分析")) { start([video], fresh: true) }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }

    private var methodNote: String {
        if isFlow {
            return L("RodentFlow 1.3 classic centroid tracking at 10 Hz (adaptive background and foreground component); no neural network is used.",
                     "RodentFlow 1.3 经典质心追踪，10 Hz（背景差分 + 前景连通区域），不使用神经网络。")
        }
        return L("The analysis method and model are chosen automatically for this task. Model details and manual tools are in Advanced.",
                 "分析方法和模型由任务自动决定。模型详情和手动工具在“高级”中。")
    }

    // MARK: Cards

    private var thisVideoCard: some View {
        let stage = video.stage(for: assay)
        return SetupCard(video.displayName, symbol: "film", subtitle: stage.title) {
            if let job = run.job, job.videoID == video.id {
                runningView(job)
            } else if let position = run.queuePosition(video.id) {
                Label(String(format: L("Waiting in the queue (position %d). It starts automatically.", "在队列中等待（第 %d 位），将自动开始。"), position),
                      systemImage: "hourglass")
                    .font(.callout)
                Button(L("Remove from queue", "移出队列")) { run.removeFromQueue(video.id) }
            } else {
                idleView
                if let job = run.job {
                    Text(String(format: L("Now analysing %@ (%d of %d). New videos are added to the queue.",
                                          "正在分析 %@（%d / %d）。新加入的视频会排在队列中。"), job.name, job.index + 1, job.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func runningView(_ job: RunJobProgress) -> some View {
        ProgressView(value: job.fraction) {
            Text(job.count > 1 ? String(format: L("Video %d of %d", "第 %d / %d 个视频"), job.index + 1, job.count)
                               : L("Analysing this video…", "正在分析该视频…"))
        }
        HStack(spacing: 14) {
            Text(String(format: "%.1f%%", job.fraction * 100)).monospacedDigit()
            Text(L("Video time", "视频时间") + " " + CalibrationFrameScrubber.clock(run.currentSourceTime))
            if let seconds = run.remainingEstimate, seconds.isFinite {
                Label(L("Est. remaining", "预计剩余") + " " + CalibrationFrameScrubber.clock(seconds), systemImage: "clock")
                    .monospacedDigit()
            } else {
                Text(L("Estimating remaining time…", "正在估算剩余时间…"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        if let live = run.livePreview {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Live tracking preview · about once per second", "实时追踪预览 · 约每秒更新"))
                    .font(.caption).foregroundStyle(.secondary)
                NativeLiveTrackingPreviewView(snapshot: live)
                    .frame(maxWidth: 600, maxHeight: 360)
            }
        }
        Button(L("Pause", "暂停")) { run.cancelJob() }
            .help(L("Finished parts are kept; resume later. Videos waiting in the queue stay as they were.",
                    "已完成的部分会保留，之后可继续。队列中等待的视频保持原状。"))
    }

    @ViewBuilder
    private var idleView: some View {
        switch video.runState {
        case .complete?:
            Label(analysedSummary, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
            HStack {
                Button(L("Review results →", "复核结果 →")) { onReview() }
                    .buttonStyle(.borderedProminent)
                Button(L("Analyse again…", "重新分析…")) { confirmRerun = true }
                    .disabled(!canStart(video))
            }
        case .partial?:
            Text(L("Paused. Finished parts are kept.", "已暂停，已完成的部分已保留。")).font(.callout)
            Button(L("Resume", "继续分析")) { start([video], fresh: false) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canStart(video))
        case .failed?:
            Text(String(format: L("The analysis stopped: %@", "分析已停止：%@"), video.runMessage ?? "—"))
                .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            Button(L("Try again", "重试")) { start([video], fresh: true) }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart(video))
        case .running?:
            // Left over from a run that is no longer active in this session.
            Text(L("This analysis is not active. Resume it to continue from the saved parts.", "该分析未在运行。点“继续分析”从已保存的部分继续。"))
                .font(.callout)
            Button(L("Resume", "继续分析")) { start([video], fresh: false) }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart(video))
        case nil:
            Text(isFlow
                 ? String(format: L("%@ of video. The centroid is tracked at 10 Hz.", "视频时长 %@，以 10 Hz 追踪质心。"), CalibrationFrameScrubber.clock(video.durationSeconds))
                 : String(format: L("%@ of video. Keypoints are tracked on every frame.", "视频时长 %@，逐帧识别关键点。"), CalibrationFrameScrubber.clock(video.durationSeconds)))
                .font(.callout).foregroundStyle(.secondary)
            Button(run.isRunning ? L("Add to queue", "加入队列") : L("Analyse this video", "分析该视频")) { start([video], fresh: false) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!canStart(video))
                .help(L("Start tracking ⌘R", "开始追踪 ⌘R"))
        }
    }

    private var analysedSummary: String {
        let frames = video.runFrames ?? 0
        let failed = video.runFailedFrames ?? 0
        if isFlow {
            return String(format: L("Analysed · %d samples (10 Hz) · %d without a detected mouse", "已分析 · %d 个采样点（10 Hz）· %d 个未检出小鼠"), frames, failed)
        }
        return String(format: L("Analysed · %d frames · %d frames with inference failures", "已分析 · %d 帧 · %d 帧识别失败"), frames, failed)
    }

    private var taskCard: some View {
        SetupCard(L("All animals of this task", "该任务的全部动物"), symbol: "square.stack.3d.up",
                  subtitle: String(format: L("%d of %d analysed", "已分析 %d / %d"), analysedCount, taskVideos.count)) {
            if let job = run.job, job.count > 1 {
                ProgressView(value: (Double(job.index) + job.fraction) / Double(max(1, job.count))) {
                    Text(String(format: L("Video %d of %d: %@", "第 %d / %d 个视频：%@"), job.index + 1, job.count, job.name))
                }
            }
            HStack {
                Button(String(format: L("Analyse remaining videos (%d)", "分析其余视频（%d 个）"), remaining.count)) {
                    start(remaining, fresh: false)
                }
                .disabled(remaining.isEmpty)
                if run.isRunning {
                    Button(L("Pause all", "全部暂停")) { run.cancelJob() }
                }
            }
            if waitingForCalibration > 0 {
                Text(String(format: L("%d videos are not calibrated yet and are not queued.", "%d 个视频尚未标定，未加入队列。"), waitingForCalibration))
                    .font(.caption).foregroundStyle(.orange)
            }
            if waitingForInfo > 0 {
                Text(String(format: L("%d videos lack animal, date or session number and are not queued.", "%d 个视频缺少小鼠编号、日期或实验次数，未加入队列。"), waitingForInfo))
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(L("Videos are analysed one after another. You can keep calibrating or reviewing other animals meanwhile.",
                   "视频按顺序逐个分析。期间可以继续标定或复核其他动物。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContentUnavailableView(L("This task cannot be analysed on the desktop", "该任务暂不能在桌面版分析"),
                                   systemImage: "circle.dotted.circle",
                                   description: Text(L("Its setup and calibration are saved as in the original app.", "其设置与标定已按原版 App 的方式保存。")))
            Button(L("Back to calibration", "返回标定")) { onCalibrate() }
        }
    }

    private var modelMissing: some View {
        ContentUnavailableView(L("The analysis model is not installed in this build", "此版本未安装分析模型"),
                               systemImage: "shippingbox",
                               description: Text(L("Add the model to the Xcode target (see MODEL_INTEGRATION_README_CN.md). Advanced → Models shows what is installed.",
                                                   "请把模型加入 Xcode target（见 MODEL_INTEGRATION_README_CN.md）。“高级 → 模型”可查看安装情况。")))
    }

    // MARK: Start

    private func start(_ videos: [VideoRecord], fresh: Bool) {
        guard !videos.isEmpty else { return }
        var requests: [RunRequest] = []
        var missing: [String] = []
        var uncalibrated: [String] = []
        var noInfo: [String] = []
        for v in videos {
            guard v.hasSessionInfo else {
                noInfo.append(v.displayName)
                continue
            }
            guard let url = store.resolveURL(v) else {
                missing.append(v.displayName)
                continue
            }
            if isFlow {
                guard let setup = v.calibration?.flow, v.hasSetup(for: assay) else {
                    uncalibrated.append(v.displayName)
                    continue
                }
                let target = store.destinationForFlowRun(v, fresh: fresh)
                requests.append(RunRequest(videoID: v.id, videoURL: url, kind: .flow(setup), destination: target.0,
                                           folder: target.1, displayName: v.displayName, durationSeconds: v.durationSeconds))
            } else if let model {
                let target = store.destinationForRun(v, model: model, fresh: fresh)
                requests.append(RunRequest(videoID: v.id, videoURL: url, kind: .pose(model), destination: target.0,
                                           folder: target.1, displayName: v.displayName, durationSeconds: v.durationSeconds))
            }
        }
        var notes: [String] = []
        if !missing.isEmpty {
            notes.append(L("These videos cannot be opened and were skipped: ", "以下视频无法打开，已跳过：") + missing.joined(separator: ", "))
        }
        if !uncalibrated.isEmpty {
            notes.append(L("Calibrate these videos first: ", "请先标定以下视频：") + uncalibrated.joined(separator: ", "))
        }
        if !noInfo.isEmpty {
            notes.append(L("Fill in animal, date and session number first: ", "请先填写小鼠编号、日期和实验次数：") + noInfo.joined(separator: ", "))
        }
        if !notes.isEmpty { store.notice = notes.joined(separator: " ") }
        run.enqueue(requests, store: store)
    }
}

// MARK: - Review step

enum ReviewTab: String, CaseIterable, Identifiable {
    case results, full
    var id: String { rawValue }

    var title: String {
        switch self {
        case .results: return L("Results", "结果")
        case .full: return L("Frame review & export", "逐帧复核与导出")
        }
    }

    var symbol: String {
        switch self {
        case .results: return "chart.bar.xaxis"
        case .full: return "film.stack"
        }
    }
}

struct ReviewStepView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var run: NativeRunSession

    let assay: StudyAssay
    let video: VideoRecord
    let onCalibrate: () -> Void
    let onAnalyse: () -> Void

    @AppStorage("rd.reviewTab") private var tabRaw = ReviewTab.results.rawValue

    private var isFlow: Bool { assay.module == .flow }
    private var tab: ReviewTab { ReviewTab(rawValue: tabRaw) ?? .results }

    private var needsCylinderCalibration: Bool {
        assay == .cylinder && !(video.hasSetup(for: assay) && (video.calibration?.limb?.isCalibrated ?? false))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if video.runState != .complete {
                notAnalysed
            } else {
                header
                if needsCylinderCalibration {
                    // RodentLimb "One step left: calibration".
                    HStack {
                        Label(L("One step left: calibration", "还差一步：标定"), systemImage: "scope").font(.headline)
                        Spacer()
                        Button(L("Calibrate", "开始标定")) { onCalibrate() }.buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: load)
        .onChange(of: video.id) { _, _ in load() }
        .onChange(of: video.runState) { _, _ in load() }
        .onChange(of: video.runFolder) { _, _ in load() }
        // Another view (or a finished batch) may load a different video into the shared session.
        .onChange(of: run.videoID) { _, _ in load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker(L("Review", "复核"), selection: Binding(get: { tab.rawValue }, set: { tabRaw = $0 })) {
                ForEach(ReviewTab.allCases) { t in
                    Label(t.title, systemImage: t.symbol).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            Spacer()
            let verdict = video.reviewVerdict
            Label(verdict.title, systemImage: verdict.symbol)
                .font(.callout)
                .foregroundStyle(verdict == .passed ? Color.green : (verdict == .issues ? Color.orange : Color.secondary))
                .help(L("Result of the tracking check of this session (Frame review & export).", "该次实验追踪复核的结论（逐帧复核与导出）。"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if isFlow {
            switch tab {
            case .results: TaskResultsView(assay: assay, video: video, onCalibrate: onCalibrate, onOpenCheck: { tabRaw = ReviewTab.full.rawValue })
            case .full: FlowFrameReviewView(assay: assay, video: video)
            }
        } else if run.holdsResult(of: video, store: store) {
            switch tab {
            case .results: TaskResultsView(assay: assay, video: video, onCalibrate: onCalibrate, onOpenCheck: { tabRaw = ReviewTab.full.rawValue })
            case .full: ReviewExportView(embedded: true)
            }
        } else if let failure = run.loadFailure, failure.videoID == video.id {
            VStack(alignment: .leading, spacing: 10) {
                Label(failure.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button(L("Try again", "重试")) { run.loadSaved(video, store: store) }
            }
        } else {
            ProgressView(L("Loading saved results…", "正在读取已保存的结果…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notAnalysed: some View {
        if let job = run.job, job.videoID == video.id {
            ContentUnavailableView(L("Analysing…", "正在分析…"), systemImage: "hourglass",
                                   description: Text(String(format: L("%.0f%% done. Review opens here when the analysis is finished.", "已完成 %.0f%%。分析完成后在此复核。"), job.fraction * 100)))
        } else if run.isQueued(video.id) {
            ContentUnavailableView(L("Waiting in the queue", "在队列中等待"), systemImage: "hourglass",
                                   description: Text(L("Review opens here when the analysis is finished.", "分析完成后在此复核。")))
        } else {
            ContentUnavailableView(L("Not analysed yet", "尚未分析"), systemImage: "waveform.path.ecg",
                                   description: Text(L("Analyse this video first; review and export then open here.", "请先分析该视频，之后在此复核与导出。")))
        }
        Button(L("Go to Analyse", "前往分析")) { onAnalyse() }
            .frame(maxWidth: .infinity)
    }

    private func load() {
        guard !isFlow, video.runState == .complete else { return }
        if run.holdsResult(of: video, store: store) || run.loadingVideoID == video.id { return }
        run.loadSaved(video, store: store)
    }
}
