import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Read existing tracking results; do not re-run inference to generate a figure.
/// Tracking QC events and experimental behavioral events are explicitly different sources.
struct ReviewExportView: View {
    @EnvironmentObject private var run: NativeRunSession
    @EnvironmentObject private var workspace: WorkspaceStore
    /// Inside the guided workflow the result is loaded automatically, so the manual "open" row is hidden.
    var embedded = false
    @State private var threshold: Double = 0.35
    @State private var chosenIndex = 0
    @State private var figureStart = 0
    @State private var figureEnd = 0
    @State private var lastRunID = ""
    @State private var eventFilter = "All"
    @State private var preview: NSImage?
    @State private var generation = 0
    @State private var displayedIndex: Int? = nil
    @State private var alignmentWarning = ""
    @State private var longAlignedFrame: NativeTrackedFrame?
    @State private var longAlignedTrail: [NativeTrackedFrame] = []
    @State private var longDisplaySize = CGSize.zero
    @State private var showSkeletonTrail = true
    @State private var trailDuration = 2.0
    @State private var opts = ScientificExportOptions()
    @State private var status = ""
    @State private var limbAnalysis: AnalysisResult?
    @State private var scoring = false
    @State private var reviewDecisions: [String: String] = [:]
    @State private var annotatorNotes = ""
    /// Video whose review decisions are shown (guided workflow only).
    @State private var reviewVideoID: UUID?
    @State private var includeBehaviorFigure = true
    @State private var indexedLongEvents: [TrackingReviewEvent]?
    @State private var indexingLong = false
    @State private var poseScienceReport: AnalysisReport?
    @State private var poseReportRange: ClosedRange<Int>?
    @State private var calculatingPose = false
    @State private var exportPoseFigures = true
    @State private var annotatedEstimate: AnnotatedVideoExporter.Estimate?
    @State private var estimatingMP4 = false
    @State private var exportingMP4 = false
    @State private var annotatedProgress = 0.0
    @State private var confirmAnnotatedMP4 = false
    // Playback and the tracking check (guided workflow).
    @AppStorage("rd.playbackSpeed") private var speedRaw = PlaybackSpeed.normal.rawValue
    @State private var playing = false
    @State private var playTask: Task<Void, Never>?
    @State private var videoAccess: ScopedVideoAccess?
    @State private var checkStart = 0
    @State private var checkCount = 100
    @State private var checkViewed: Set<Int> = []
    @State private var checkFlagged: Set<Int> = []

    private var short: NativeTrackingResult? { run.shortResult }
    private var long: LongVideoManifest? { run.longManifest }
    private var total: Int {
        if let short { return short.frames.count }
        return long?.completed.reduce(0) { $0 + $1.records } ?? 0
    }
    private var events: [TrackingReviewEvent] {
        if let short {
            let qc = TrackingReviewEventBuilder.short(short, threshold: threshold)
            let behaviors = limbAnalysis.map {TrackingReviewEventBuilder.behavior($0,frames:short.frames)} ?? []
            return (qc + behaviors).sorted {$0.start < $1.start}
        }
        return indexedLongEvents ?? long.map(TrackingReviewEventBuilder.longSegments) ?? []
    }
    private var visibleEvents: [TrackingReviewEvent] {
        events.filter { eventFilter == "All" || (eventFilter == "Tracking QC" ? $0.source.contains("QC") : $0.source.contains("analyzer")) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:15) {
                Text(L("Review tracking & export figures", "复核追踪并导出图表")).font(.title2.bold())
                Text(L("Review event intervals, inspect frames, choose the frame range for plots, and export only what you need. Original data remain unchanged.",
                       "复核事件区间、逐帧检查、选择作图的帧范围，只导出需要的内容。原始数据保持不变。"))
                    .foregroundStyle(.secondary)
                if !embedded {
                    HStack {
                        Button(L("Open completed long-video results…", "打开已完成的长视频结果…")) { importLongResults() }
                        Text(L("Read an existing manifest and segments without re-running Core ML.", "读取已有的清单和分段，不重新运行 Core ML。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                guardContent
                if total > 0 {
                    HStack {
                        Label(L("\(total) processed frames", "已处理 \(total) 帧"),systemImage:"film.stack")
                        Text(short?.model.rawValue ?? long?.modelName ?? "").foregroundStyle(.secondary)
                        Spacer()
                        Text(L("\(events.count) displayed event intervals", "显示 \(events.count) 个事件区间")).font(.caption)
                    }
                    .font(.subheadline)
                    Divider()
                    trackingReview
                    if embedded {
                        // The guided workflow shows the original app's results in the Results tab, computed
                        // with the analysis window saved in Calibrate. The frame range here is for QC
                        // figures and raw exports only.
                        EmptyView()
                    } else if let short, short.model == .mousePose {
                        Divider()
                        poseScienceSection(short)
                    } else if let long,long.modelName == PoseModelKind.mousePose.rawValue,
                              let folder=run.longDirectory {
                        Divider()
                        poseScienceLongSection(long,folder:folder)
                    }
                    if embedded, let video = resultVideo {
                        TrackingCheckCard(video: video, unit: "frame", total: total,
                                          rangeStart: $checkStart, rangeCount: $checkCount,
                                          viewed: checkViewed, flagged: checkFlagged, notes: $annotatorNotes,
                                          persist: persistReview, jump: { jumpToFrame($0) })
                    }
                    Divider()
                    exportControls
                }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }.frame(maxWidth:1050,alignment:.leading)
        }
        .onAppear { syncRun() }
        .onDisappear { stopPlaying(); persistReview() }
        .onChange(of: runKey) { _,_ in stopPlaying(); syncRun() }
        .onChange(of: checkStart) { _,_ in persistReview() }
        .onChange(of: checkCount) { _,_ in persistReview() }
        .onChange(of: reviewDecisions) { _,_ in persistReview() }
        .onChange(of: threshold) { _,_ in indexedLongEvents=nil }
        .onChange(of: figureStart) { _,_ in poseScienceReport=nil;poseReportRange=nil;annotatedEstimate=nil }
        .onChange(of: figureEnd) { _,_ in poseScienceReport=nil;poseReportRange=nil;annotatedEstimate=nil }
        .confirmationDialog(L("Export annotated video?", "导出标注视频？"),isPresented:$confirmAnnotatedMP4,titleVisibility:.visible) {
            Button(L("Start MP4 export", "开始导出 MP4")) { writeAnnotatedMP4() }
            Button(L("Cancel", "取消"),role:.cancel) {}
        } message: {
            Text(annotatedEstimate.map { String(format:"%.1f min · %d frames · benchmark %d frames · device speed may vary",$0.seconds/60,$0.totalFrames,$0.sampleFrames) } ?? "")
        }
    }

    @ViewBuilder private var guardContent: some View {
        if total == 0 {
            ContentUnavailableView(L("No tracking results yet", "还没有追踪结果"), systemImage:"waveform.path.ecg.rectangle",
                description: Text(L("Analyse a video first, then return here. Figure generation does not start model inference.",
                                    "请先分析视频再回到这里。生成图表不会重新运行模型。")))
        } else if let long {
            Text(L("Long video: event rows currently summarize failed frames per segment, not exact behavioral bouts. Frame-range plots scan completed CSV segments individually without loading the entire run.",
                   "长视频：事件行目前汇总每个分段的失败帧，不是精确的行为片段。帧范围作图逐个扫描已完成的 CSV 分段，不把整个结果载入内存。"))
                .font(.caption).foregroundStyle(.orange)
            Text(L("\(long.completed.count) completed segments. Only completed segments enter the figure.", "已完成 \(long.completed.count) 个分段。只有已完成的分段进入图表。"))
                .font(.caption).foregroundStyle(.secondary)
        } else if embedded {
            Text(L("QC flags are not behavior scoring. The original app's results are in the Results tab; the frame range below only selects QC figures, raw exports and the annotated video.",
                   "质控标记不是行为评分。原版 App 的结果在“结果”页；下方帧范围只用于质控图、原始数据导出和标注视频。"))
                .font(.caption).foregroundStyle(.orange)
        } else {
            Text(L("QC flags are not behavior scoring. RodentPose scientific reports can be calculated from a selected frame window. Behavior event parity validation is still pending.",
                   "质控标记不是行为评分。RodentPose 可按指定帧范围计算原版科研报告；行为事件的一致性验证仍未完成。"))
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var trackingReview: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(L("Tracking events", "追踪事件")).font(.headline)
                Spacer()
                Picker(L("Event source", "事件来源"),selection:$eventFilter) {
                    Text(L("All", "全部")).tag("All")
                    Text(L("Tracking QC", "追踪质控")).tag("Tracking QC")
                    Text(L("Behavior events", "行为事件")).tag("Behavior events")
                }.pickerStyle(.menu).frame(width:240)
            }
            HStack {
                Text(L("QC confidence threshold", "质控置信度阈值"))
                Slider(value:$threshold,in:0.05...0.95,step:0.05).frame(maxWidth:220)
                Text(String(format:"%.2f",threshold)).monospacedDigit()
                Text(L("(changes review flags, not model outputs)", "（只改变复核标记，不改变模型输出）")).font(.caption).foregroundStyle(.secondary)
            }
            if let long, let folder=run.longDirectory {
                HStack {
                    if !embedded { Button(L("Locate source video…", "定位原始视频…")) { locateLongVideo() } }
                    Button(indexingLong ? L("Indexing…", "正在索引…") : L("Index exact QC events from completed CSV segments", "从已完成的 CSV 分段索引精确质控事件")) {indexLong(long, folder:folder)}
                        .disabled(indexingLong)
                    Text(indexedLongEvents == nil ? L("Currently showing segment summaries", "当前显示分段汇总") : L("Frame-level events indexed", "已索引逐帧事件"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let long, preview == nil {
                playbackRow(position: longPositionText(long))
            }
            if let long, let preview {
                HStack {
                    Toggle(L("Show trailing path", "显示运动拖尾"),isOn:$showSkeletonTrail)
                    Picker(L("Trail length", "拖尾时长"),selection:$trailDuration) {
                        Text("1 s").tag(1.0)
                        Text("2 s · iOS").tag(2.0)
                        Text("5 s").tag(5.0)
                    }.pickerStyle(.menu).frame(width:120)
                }
                playbackRow(position: longPositionText(long))
                if let frame = longAlignedFrame,let model = PoseModelKind(rawValue:long.modelName) {
                    NativeTrackingCanvas(model:model,image:preview,
                        videoWidth:Int(longDisplaySize.width),videoHeight:Int(longDisplaySize.height),
                        frame:frame,previous:longAlignedTrail,threshold:threshold,
                        showTrail:showSkeletonTrail,trailSeconds:trailDuration)
                        .frame(height:350).clipShape(RoundedRectangle(cornerRadius:8))
                    Text(L("Only neighboring CSV segments are read for this frame; model inference is not repeated.",
                           "仅读取当前帧附近的 CSV 分段；不会重新进行模型推理。"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Image(nsImage:preview).resizable().scaledToFit().frame(maxHeight:330)
                    if !alignmentWarning.isEmpty {
                        Label(alignmentWarning,systemImage:"exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                eventTimeline
            }
            if let report = short {
                HStack {
                    Toggle(L("Show trailing path", "显示运动拖尾"),isOn:$showSkeletonTrail)
                    if showSkeletonTrail {
                        Text(L("Trail", "拖尾"))
                        Picker(L("Trail length", "拖尾时长"),selection:$trailDuration) {
                            Text("1 s").tag(1.0)
                            Text("2 s · iOS").tag(2.0)
                            Text("5 s").tag(5.0)
                            Text("10 s").tag(10.0)
                        }.pickerStyle(.menu).frame(width:120)
                    }
                    Spacer()
                    Text(report.model == .mousePose ? L("RodentPose colors", "RodentPose 原版配色") : L("RodentLimb colors", "RodentLimb 原版配色"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if report.frames.count > 1 {
                    Slider(value:Binding(get:{Double(chosenIndex)},set:{v in
                        chosenIndex = min(report.frames.count-1,max(0,Int(v)))
                        loadFrame(report:report,index:chosenIndex)
                    }),in:0...Double(report.frames.count-1),step:1)
                }
                playbackRow(position: L("Frame", "帧") + " \(chosenIndex) · t = \(String(format:"%.3f",report.frames[min(chosenIndex,report.frames.count-1)].time)) s")
                if let preview {
                    if let i = displayedIndex, report.frames.indices.contains(i) {
                        let current = report.frames[i]
                        let lower = max(0, current.time - trailDuration)
                        // Only the selected time window is used in the render, never the whole file.
                        let trailStart = Self.indexAtOrAfter(report.frames, time:lower)
                        let selected = Array(report.frames[trailStart...i])
                        NativeTrackingCanvas(model:report.model,image:preview,
                            videoWidth:report.videoWidth,videoHeight:report.videoHeight,
                            frame:current,previous:selected,threshold:threshold,
                            showTrail:showSkeletonTrail,trailSeconds:trailDuration)
                            .frame(height:360)
                            .clipShape(RoundedRectangle(cornerRadius:8))
                        if i != chosenIndex {
                            Text(L("Video returned frame \(i), not requested frame \(chosenIndex); the points follow the actual displayed frame.",
                                   "视频实际返回第 \(i) 帧（请求第 \(chosenIndex) 帧）；标点以实际显示画面为准。"))
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Image(nsImage:preview).resizable().scaledToFit().frame(height:360)
                    }
                    if !alignmentWarning.isEmpty {
                        Label(alignmentWarning,systemImage:"exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                eventTimeline
                if report.model == .cylinderV2 && !embedded {
                    Button(scoring ? L("Computing…", "正在计算…") : L("Show original RodentLimb behavior events (experimental)", "显示原版 RodentLimb 行为事件（实验性）")) { scoreLimb(report) }
                        .disabled(scoring)
                    Text(L("Uses the original Swift analyzer with this video's RodentLimb calibration and parameters. Requires human QC and parity validation before scientific reporting.",
                           "使用原版 Swift 分析器和该视频的 RodentLimb 标定与参数。用于科学报告前需要人工质控和一致性验证。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if visibleEvents.isEmpty {
                Text(L("No events for this filter. A clean tracking run can legitimately have zero QC events.", "此筛选下没有事件。追踪质量好的视频可以没有任何质控事件。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(visibleEvents) { event in
                        HStack(spacing:9) {
                            Button { jump(to:event) } label: {
                                VStack(alignment:.leading,spacing:3) {
                                    Text(Self.kindTitle(event.kind)).font(.subheadline.weight(.medium))
                                    Text(L("Frame", "帧") + " \(event.firstFrame)–\(event.lastFrame) · \(String(format:"%.2f",event.start))–\(String(format:"%.2f",event.end)) s · \(Self.sourceTitle(event.source))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(event.detail).font(.caption2).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.buttonStyle(.plain)
                            Button(L("Use range", "用作范围")) {
                                figureStart=max(0,event.firstFrame)
                                figureEnd=min(total-1,event.lastFrame)
                            }.buttonStyle(.borderless)
                            Picker(L("Review", "复核"),selection:Binding(get:{reviewDecisions[event.id] ?? "unreviewed"},set:{reviewDecisions[event.id]=$0})) {
                                Text(L("Unreviewed", "未复核")).tag("unreviewed")
                                Text(L("Accepted", "接受")).tag("accepted")
                                Text(L("Flagged", "标记问题")).tag("flagged")
                            }.labelsHidden().frame(width:130)
                        }
                    }
                }.frame(minHeight:110,maxHeight:300)
            }
            if !embedded {
                TextField(L("Reviewer notes (saved with export)", "复核备注（随导出保存）"),text:$annotatorNotes)
                    .onSubmit { persistReview() }
            }
        }
    }

    private var exportControls: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(L("Export from completed tracking", "从已完成的追踪导出")).font(.headline)
            Text(L("Figure frames (inclusive, zero-based). Only this range is plotted; whole-run raw CSV remains available independently.",
                   "作图帧范围（含首尾，从 0 开始）。只绘制该范围；完整原始 CSV 另行保留。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(L("Start frame", "起始帧"))
                TextField(L("Start", "起始"),value:$figureStart,format:.number).frame(width:100)
                Text(L("End frame", "结束帧"))
                TextField(L("End", "结束"),value:$figureEnd,format:.number).frame(width:100)
                Button(L("Use current frame", "使用当前帧")) {figureStart=chosenIndex;figureEnd=chosenIndex}
                    .disabled(short==nil)
                Button(L("All frames", "全部帧")) {figureStart=0;figureEnd=max(0,total-1)}
            }
            Text(L("Selected: \(max(0,figureEnd-figureStart+1)) frames", "已选择 \(max(0,figureEnd-figureStart+1)) 帧")).font(.caption).monospacedDigit()
            Divider()
            HStack(alignment:.top,spacing:24) {
                VStack(alignment:.leading) {
                    Toggle(L("Raw keypoints CSV", "原始关键点 CSV"),isOn:$opts.rawPoseCSV).disabled(short==nil)
                    Toggle(L("QC-screened CSV", "质控筛选后的 CSV"),isOn:$opts.screenedPoseCSV).disabled(short==nil)
                    Toggle(short == nil ? L("Segment QC CSV", "分段质控 CSV") : L("Frame QC CSV", "逐帧质控 CSV"),isOn:$opts.frameQCcsv)
                    Toggle(L("Metadata / provenance JSON", "元数据 / 溯源 JSON"),isOn:$opts.provenanceJSON)
                    Toggle(L("Copy original segment CSVs", "复制原始分段 CSV"),isOn:$opts.copyLongSegments).disabled(long==nil)
                }
                VStack(alignment:.leading) {
                    Toggle(L("Trajectory figure PNG (selected frames)", "轨迹图 PNG（所选帧）"),isOn:Binding(get:{short == nil ? opts.longTrajectoryPNG : opts.trajectoryPNG},set:{v in if short == nil {opts.longTrajectoryPNG=v}else{opts.trajectoryPNG=v}}))
                    Toggle(L("Confidence figure PNG (selected frames)", "置信度图 PNG（所选帧）"),isOn:$opts.confidencePNG).disabled(short==nil)
                    Toggle(L("Annotated screenshot PNG (current frame)", "标注截图 PNG（当前帧）"),isOn:$opts.annotatedPNG).disabled(short==nil)
                    Toggle(L("Segment QC timeline PNG", "分段质控时间线 PNG"),isOn:$opts.longQCtimelinePNG).disabled(long==nil)
                    Toggle(L("RodentLimb event timeline PNG", "RodentLimb 事件时间线 PNG"),isOn:$includeBehaviorFigure).disabled(limbAnalysis == nil)
                    Text(L("Annotated MP4 is a separate, opt-in operation below.", "标注 MP4 是下面的独立、可选操作。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L("Figures are calculated from saved tracking; annotated MP4 encoding is optional, estimated before confirmation, and does not rerun models.",
                   "图表由已保存的追踪数据生成；标注 MP4 独立可选，先测速估时并确认，不重复运行模型。"))
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:6) {
                HStack {
                    Button(estimatingMP4 ? L("Benchmarking…", "测速中…") : L("Estimate annotated MP4 time…", "先估算标注 MP4 耗时…")) { estimateAnnotatedMP4() }
                        .disabled(estimatingMP4 || exportingMP4 || total==0 || figureStart>figureEnd)
                    if let estimate=annotatedEstimate {
                        Text(String(format:"Approx. %.1f–%.1f min (%d frames; %d sample frames)",
                                    estimate.seconds/60*0.7,estimate.seconds/60*1.8,estimate.totalFrames,estimate.sampleFrames))
                            .monospacedDigit().font(.caption)
                        Button(L("Export MP4…", "确认导出 MP4…")) {confirmAnnotatedMP4=true}
                            .disabled(exportingMP4)
                    }
                }
                if exportingMP4 {ProgressView(value:annotatedProgress)}
            }
            Button(L("Export selected files and figures…", "导出所选文件和图表…")) { export() }
                .keyboardShortcut("e", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(total == 0 || figureStart < 0 || figureEnd < figureStart || figureEnd >= total)
        }
    }

    /// Event names are stored in English (exports); the list shows them in the interface language.
    static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "Inference failed": return L("Inference failed", "识别失败")
        case "No detection": return L("No detection", "未检测到小鼠")
        case "Low confidence": return L("Low confidence", "置信度低")
        default: return kind
        }
    }

    static func sourceTitle(_ source: String) -> String {
        switch source {
        case "Tracking QC": return L("Tracking QC", "追踪质控")
        case "Segment QC (not exact events)": return L("Segment QC (not exact events)", "分段质控（非精确事件）")
        case "RodentLimb analyzer (not validated)": return L("RodentLimb analyzer (not validated)", "RodentLimb 分析器（未验证）")
        default: return source
        }
    }

    /// Identity of the loaded result: workspace video + run folder (or the opened folder in Advanced).
    private var runKey: String {
        let owner = run.videoID?.uuidString ?? "advanced"
        let folder = run.loadedFolder?.path ?? run.longDirectory?.path ?? run.shortVideoURL?.path ?? ""
        let size = short.map { "short-\($0.frames.count)" } ?? long.map { "long-\($0.completed.count)" } ?? "none"
        return owner + "|" + folder + "|" + size
    }

    private func syncRun() {
        let key = runKey
        guard lastRunID != key else { return }
        persistReview()
        lastRunID=key
        reviewVideoID = embedded ? run.videoID : nil
        chosenIndex=0;figureStart=0;figureEnd=max(0,total-1)
        limbAnalysis=nil;poseScienceReport=nil;poseReportRange=nil;annotatedEstimate=nil;preview=nil;displayedIndex=nil;alignmentWarning="";indexedLongEvents=nil
        longAlignedFrame=nil;longAlignedTrail=[];longDisplaySize = .zero
        // Decisions and notes are saved with the video (guided workflow), so they survive switching.
        let saved = reviewVideoID.flatMap { workspace.video($0)?.currentReview }
        reviewDecisions = saved?.eventDecisions ?? [:]
        annotatorNotes = saved?.notes ?? ""
        checkStart = saved?.windowStart ?? 0
        checkCount = min(TrackingCheckCard.maxRange, max(1, saved?.windowCount ?? 100))
        checkViewed = Set(saved?.viewed ?? [])
        checkFlagged = Set(saved?.flagged ?? [])
        if let short, !short.frames.isEmpty {
            // The check range opens where it was left (frame 0 for a new check).
            chosenIndex = embedded ? min(short.frames.count - 1, max(0, checkStart)) : 0
            loadFrame(report:short,index:chosenIndex)
        } else if embedded, long != nil, let t = longTime(forFrame: checkStart) {
            loadLongFrame(at: t)
        }
        // RodentLimb events are shown automatically, with this video's calibration and parameters.
        if embedded, let short, short.model == .cylinderV2 { scoreLimb(short, quiet: true) }
    }

    /// Writes event decisions and notes to the video they belong to.
    private func persistReview() {
        guard embedded, let id = reviewVideoID else { return }
        let decisions = reviewDecisions.filter { $0.value != "unreviewed" }
        let notes = annotatorNotes
        let unit = "frame"
        let start = checkStart, count = checkCount
        let seen = checkViewed.sorted(), marks = checkFlagged.sorted()
        workspace.updateReview(id, unit: unit) { s in
            s.eventDecisions = decisions
            s.notes = notes
            s.windowStart = start
            s.windowCount = count
            s.viewed = seen
            s.flagged = marks
        }
    }
    private func stepFrame(_ change:Int,_ report:NativeTrackingResult) {
        chosenIndex=min(report.frames.count-1,max(0,chosenIndex+change))
        loadFrame(report:report,index:chosenIndex)
    }
    private func jump(to event: TrackingReviewEvent) {
        if let short { chosenIndex=min(short.frames.count-1,max(0,event.firstFrame));loadFrame(report:short,index:chosenIndex) }
        else {
            status=L("Long-video event", "长视频事件") + ": \(event.detail) · t=\(String(format:"%.2f",event.start)) s."
            loadLongFrame(at:event.start)
        }
    }
    // Binary search on stored *presentation timestamps*, not index / nominal FPS.
    private static func nearestIndex(_ frames:[NativeTrackedFrame], to time:Double) -> Int {
        guard frames.count > 1 else {return 0}
        var lo=0,hi=frames.count
        while lo<hi {
            let m=(lo+hi)/2
            if frames[m].time < time {lo=m+1}else{hi=m}
        }
        if lo == 0{return 0}
        if lo == frames.count{return frames.count-1}
        return abs(frames[lo].time-time) < abs(frames[lo-1].time-time) ? lo : lo-1
    }
    private static func indexAtOrAfter(_ frames:[NativeTrackedFrame],time:Double) -> Int {
        guard !frames.isEmpty else{return 0}
        var lo=0,hi=frames.count
        while lo<hi {
            let m=(lo+hi)/2
            if frames[m].time < time {lo=m+1}else{hi=m}
        }
        return min(frames.count-1,lo)
    }
    private func loadFrame(report: NativeTrackingResult,index:Int) {
        Task { @MainActor in await showFrame(report: report, index: index) }
    }

    /// Decodes the video frame of tracked frame `index` (persistent decoder, so playback is smooth) and
    /// draws the points only when the decoded frame is the tracked one.
    private func showFrame(report: NativeTrackingResult, index: Int) async {
        guard let url = run.shortVideoURL, report.frames.indices.contains(index) else { return }
        if videoAccess?.url != url { videoAccess = ScopedVideoAccess(url: url) }
        guard let generator = videoAccess?.generator else { return }
        generation += 1
        let ticket = generation
        let second = report.timeOffset + report.frames[index].time
        var image: NSImage?
        var real = Double.nan
        do {
            let decoded = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 60_000))
            image = NSImage(cgImage: decoded.image, size: NSSize(width: CGFloat(decoded.image.width), height: CGFloat(decoded.image.height)))
            real = decoded.actualTime.seconds
        } catch {
            image = nil
        }
        guard generation == ticket else { return }
        let relative = real - report.timeOffset
        let actualIndex = real.isFinite ? Self.nearestIndex(report.frames, to: relative) : index
        let actualPTS = report.timeOffset + report.frames[actualIndex].time
        let timeGap = abs(real - actualPTS)
        let tolerance = max(0.012, 0.53 / max(report.fps, 1))
        let frameMatches = real.isFinite && timeGap <= tolerance
        var dimensionsMatch = false
        if let image {
            let ratio = image.size.width / max(image.size.height, 1)
            let expected = CGFloat(report.videoWidth) / CGFloat(max(report.videoHeight, 1))
            dimensionsMatch = abs(ratio - expected) < 0.015
        }
        preview = image
        displayedIndex = (frameMatches && dimensionsMatch) ? actualIndex : nil
        if image == nil {
            alignmentWarning = L("Cannot decode this video frame.", "无法解码这一视频帧。")
        } else if !frameMatches {
            alignmentWarning = L("Image timestamp does not match recorded tracking timestamps. Pose points are hidden to prevent incorrect QC.",
                                 "视频实际画面的时间戳与姿态记录不匹配。为防止错误复核，已隐藏标点。")
        } else if !dimensionsMatch {
            alignmentWarning = L("Image orientation differs from tracking coordinate system; pose points are hidden.",
                                 "画面方向与姿态坐标不一致，已隐藏标点。")
        } else {
            alignmentWarning = ""
        }
        if embedded, let shown = displayedIndex, shown >= checkStart, shown <= checkEnd { checkViewed.insert(shown) }
    }

    // MARK: Playback and tracking check

    private var speed: PlaybackSpeed { PlaybackSpeed(rawValue: speedRaw) ?? .normal }
    private var checkEnd: Int { min(max(0, total - 1), checkStart + max(1, checkCount) - 1) }
    /// The frame shown now (short runs: the displayed frame; long runs: the timestamp-matched sample).
    private var shownFrame: Int? { short != nil ? (displayedIndex ?? chosenIndex) : longAlignedFrame?.index }

    @ViewBuilder
    private func playbackRow(position: String) -> some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Label(L("Previous frame", "上一帧"), systemImage: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
                .disabled(playing)
            Button { togglePlay() } label: {
                Label(playing ? L("Pause", "暂停") : L("Play", "播放"), systemImage: playing ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut("p", modifiers: [.option])
            .help(embedded
                  ? L("Plays to the end of the check range (or of the recording when outside it). ⌥P", "播放到复核范围末尾（不在范围内时播放到视频结尾）。⌥P")
                  : L("Plays to the end of the recording. ⌥P", "播放到视频结尾。⌥P"))
            Button { step(1) } label: { Label(L("Next frame", "下一帧"), systemImage: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: [.option])
                .disabled(playing)
            Picker(L("Speed", "速度"), selection: $speedRaw) {
                ForEach(PlaybackSpeed.allCases) { s in Text(s.title).tag(s.rawValue) }
            }
            .frame(width: 170)
            if embedded {
                Divider().frame(height: 18)
                Toggle(isOn: Binding(get: { shownFrame.map { checkFlagged.contains($0) } ?? false }, set: { setFlag($0) })) {
                    Label(L("Wrong tracking here", "此处追踪错误"), systemImage: "flag.fill")
                }
                .toggleStyle(.button)
                .tint(.orange)
                .keyboardShortcut("f", modifiers: [.option])
                .disabled(shownFrame == nil)
            }
            Spacer()
            Text(position).monospacedDigit()
        }
    }

    private func longPositionText(_ manifest: LongVideoManifest) -> String {
        guard let f = longAlignedFrame else { return L("Click the timeline or press Play", "点击时间线或按“播放”") }
        return L("Frame", "帧") + " \(f.index) · t = " + String(format: "%.3f", f.time) + " s"
    }

    private func step(_ change: Int) {
        if let short {
            stepFrame(change, short)
        } else if long != nil {
            let fps = max(resultVideo?.framesPerSecond ?? 30, 1)
            let t = (longAlignedFrame?.time ?? longTime(forFrame: checkStart) ?? 0) + Double(change) / fps
            loadLongFrame(at: max(0, t))
        }
    }

    private func jumpToFrame(_ index: Int) {
        if let short {
            chosenIndex = min(short.frames.count - 1, max(0, index))
            loadFrame(report: short, index: chosenIndex)
        } else if let t = longTime(forFrame: index) {
            loadLongFrame(at: t)
        }
    }

    private func setFlag(_ on: Bool) {
        guard let i = shownFrame else { return }
        if on { checkFlagged.insert(i) } else { checkFlagged.remove(i) }
        persistReview()
    }

    /// Approximate timestamp of a frame of a long run (segments record their first / last timestamp and
    /// frame count); the overlay is drawn only for the timestamp-matched sample.
    private func longTime(forFrame index: Int) -> Double? {
        guard let long else { return nil }
        var offset = 0
        for segment in long.completed.sorted(by: { $0.index < $1.index }) {
            if index < offset + segment.records {
                let span = segment.records > 1 ? (segment.lastPTS - segment.firstPTS) / Double(segment.records - 1) : 0
                return segment.firstPTS + Double(index - offset) * span
            }
            offset += segment.records
        }
        return nil
    }

    private func togglePlay() {
        if playing { stopPlaying(); return }
        if let short { playShort(short) } else if let long { playLong(long) }
    }

    private func stopPlaying() {
        playing = false
        playTask?.cancel()
        playTask = nil
    }

    private func playShort(_ report: NativeTrackingResult) {
        guard report.frames.count > 1 else { return }
        if chosenIndex >= report.frames.count - 1 { chosenIndex = 0 }
        let inRange = embedded && chosenIndex >= checkStart && chosenIndex < checkEnd
        let last = inRange ? checkEnd : report.frames.count - 1
        let chosen = speed
        playing = true
        playTask = Task { @MainActor in
            let startWall = Date()
            let startTime = report.frames[chosenIndex].time
            while !Task.isCancelled && playing && chosenIndex < last {
                let plan = PlaybackPlanner.next(after: chosenIndex, last: last, times: { report.frames[$0].time },
                                                speed: chosen, startWall: startWall, startTime: startTime)
                if plan.wait > 0 { try? await Task.sleep(nanoseconds: UInt64(plan.wait * 1_000_000_000)) }
                guard !Task.isCancelled && playing else { break }
                chosenIndex = plan.index
                await showFrame(report: report, index: plan.index)
            }
            playing = false
            persistReview()
        }
    }

    private func playLong(_ manifest: LongVideoManifest) {
        guard run.longVideoURL != nil else {
            status = L("Locate the original video to play the review.", "请先定位原始视频再播放。")
            return
        }
        let fps = max(resultVideo?.framesPerSecond ?? 30, 1)
        let current = longAlignedFrame?.index
        let inRange = embedded && current.map { $0 >= checkStart && $0 < checkEnd } ?? false
        let lastFrame = inRange ? checkEnd : Int.max
        let chosen = speed
        let startTime = longAlignedFrame?.time ?? (embedded ? longTime(forFrame: checkStart) : nil) ?? 0
        playing = true
        playTask = Task { @MainActor in
            let startWall = Date()
            var t = startTime
            while !Task.isCancelled && playing {
                let shownTime = longAlignedFrame?.time ?? t
                var next = max(t, shownTime) + 1 / fps
                if let rate = chosen.rate {
                    next = max(next, startTime + Date().timeIntervalSince(startWall) * rate)
                    let due = (next - startTime) / rate - Date().timeIntervalSince(startWall)
                    if due > 0 { try? await Task.sleep(nanoseconds: UInt64(min(due, 1) * 1_000_000_000)) }
                }
                guard !Task.isCancelled && playing, next <= manifest.videoDuration else { break }
                t = next
                await showLongFrame(at: t)
                if let index = longAlignedFrame?.index {
                    if embedded && index >= checkStart && index <= checkEnd { checkViewed.insert(index) }
                    if index >= lastFrame { break }
                }
            }
            playing = false
            persistReview()
        }
    }

    private func showLongFrame(at time: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loadLongFrame(at: time) { continuation.resume() }
        }
    }

    /// Aligned tracking-QC / behavior event lanes, with the selected displayed-frame cursor.
    /// No event is invented here; behavior lanes require the original assay analyzer.
    private var eventTimeline: some View {
        VStack(alignment:.leading,spacing:5) {
            HStack {
                Text(L("Events aligned to tracking", "事件与运动轨迹对齐")).font(.subheadline.bold())
                Spacer()
                Button(L("Previous event", "上一事件")) { seekAdjacentEvent(forward:false) }
                    .disabled(!hasAdjacentEvent(forward:false))
                Button(L("Next event", "下一事件")) { seekAdjacentEvent(forward:true) }
                    .disabled(!hasAdjacentEvent(forward:true))
            }
            GeometryReader { geo in
                Canvas { ctx, size in
                    let width = max(size.width,1)
                    let totalCount = CGFloat(max(total-1,1))
                    let qc = visibleEvents.filter{$0.source.contains("QC")}
                    let behavior = visibleEvents.filter{$0.source.contains("analyzer")}
                    for (events,trackY,color) in [(qc,CGFloat(4),Color.orange),(behavior,CGFloat(24),Color.blue)] {
                        ctx.fill(Path(roundedRect:CGRect(x:0,y:trackY,width:width,height:13),cornerRadius:3),with:.color(.gray.opacity(0.13)))
                        for event in events.prefix(5000) {
                            let a = CGFloat(max(0,event.firstFrame)) / totalCount * width
                            let b = CGFloat(min(total-1,event.lastFrame)) / totalCount * width
                            ctx.fill(Path(roundedRect:CGRect(x:a,y:trackY,width:max(2,b-a),height:13),cornerRadius:2),with:.color(color.opacity(0.75)))
                        }
                    }
                    let x = CGFloat(longAlignedFrame?.index ?? displayedIndex ?? chosenIndex) / totalCount * width
                    var cursor=Path();cursor.move(to:CGPoint(x:x,y:0));cursor.addLine(to:CGPoint(x:x,y:42))
                    ctx.stroke(cursor,with:.color(.primary),lineWidth:1.5)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onEnded { v in
                    let fraction=min(1,max(0,v.location.x/max(geo.size.width,1)))
                    if let short,short.frames.count>1 {
                        let idx=Int((fraction*CGFloat(short.frames.count-1)).rounded())
                        chosenIndex=min(short.frames.count-1,max(0,idx))
                        loadFrame(report:short,index:chosenIndex)
                    } else if let long {
                        loadLongFrame(at:Double(fraction)*long.videoDuration)
                    }
                })
            }.frame(height:42)
            HStack(spacing:14) {
                Label(L("Tracking QC", "追踪质控"),systemImage:"circle.fill").foregroundStyle(.orange)
                Label(L("Behavior events (only when scored)", "行为事件（评分后显示）"),systemImage:"circle.fill").foregroundStyle(.blue)
                if let short,let i=displayedIndex {
                    let active=events.filter{$0.firstFrame <= i && $0.lastFrame >= i}
                    if !active.isEmpty {Text(active.prefix(2).map(\.kind).joined(separator:" · ")).lineLimit(1)}
                }
            }.font(.caption)
        }
    }
    private func hasAdjacentEvent(forward:Bool)->Bool {
        let index=longAlignedFrame?.index ?? chosenIndex
        return forward ? visibleEvents.contains{$0.firstFrame>index} : visibleEvents.contains{$0.firstFrame<index}
    }
    private func seekAdjacentEvent(forward:Bool) {
        let index=longAlignedFrame?.index ?? chosenIndex
        let sorted=visibleEvents.sorted{$0.firstFrame<$1.firstFrame}
        let item=forward ? sorted.first{$0.firstFrame>index} : sorted.last{$0.firstFrame<index}
        if let item {jump(to:item)}
    }
    /// The workspace video the shown result belongs to.
    private var resultVideo: VideoRecord? { workspace.video(run.videoID ?? workspace.focusedVideoID) }
    private var resultAssay: StudyAssay? {
        workspace.selectedProject?.experiments.first { $0.id == resultVideo?.experimentID }?.assay
    }
    private var resultCategory: ParadigmCategory { resultVideo?.calibration?.pose?.paradigm.category ?? .general }

    private func poseScienceLongSection(_ manifest:LongVideoManifest, folder:URL) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Label(L("RodentPose · Original Results (long video)", "RodentPose · 原版结果（长视频）"),systemImage:"chart.bar.xaxis")
                .font(.headline)
            Text(L("Advanced: selected frames are loaded from saved CSV segments (no new inference) and replace the analysis window saved in Calibrate. One report is limited to 216,000 frames.",
                   "高级：仅从已保存 CSV 分段读取所选帧（不重新推理），并替代“校准”中保存的分析时间段。单份报告最多 216,000 帧。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(calculatingPose ? L("Calculating…","计算中…") : L("Calculate original assay report", "计算原版实验报告")) {
                    calculateLongPose(manifest,folder:folder)
                }.disabled(calculatingPose || figureStart>figureEnd)
                Toggle(L("Export report figures PNG","导出报告图片 PNG"),isOn:$exportPoseFigures)
                    .disabled(poseScienceReport==nil)
            }
            if let result=poseScienceReport,poseReportRange == figureStart...figureEnd {
                Text(L("Frames", "帧") + " \(figureStart)–\(figureEnd)").font(.caption).foregroundStyle(.secondary)
                PoseReportView(report:result,category:resultCategory)
            }
        }
    }
    private func calculateLongPose(_ manifest:LongVideoManifest,folder:URL) {
        let setup=resultVideo?.calibration?.pose
        let phase=resultVideo?.effectivePhase(for: resultAssay) ?? ""
        let video=run.longVideoURL ?? resultVideo.flatMap{workspace.resolveURL($0)}
        let range=figureStart...figureEnd
        calculatingPose=true
        DispatchQueue.global(qos:.userInitiated).async {
            let access=video?.startAccessingSecurityScopedResource() ?? false
            let folderAccess=folder.startAccessingSecurityScopedResource()
            defer {
                if access {video?.stopAccessingSecurityScopedResource()}
                if folderAccess {folder.stopAccessingSecurityScopedResource()}
            }
            let result=Result {() throws -> AnalysisReport in
                let tracked=try PoseScienceLongLoader.make(manifest:manifest,folder:folder,videoURL:video,selected:range)
                return try PoseScienceBridge.report(tracked,setup:setup,phase:phase,frames:range)
            }
            DispatchQueue.main.async {
                calculatingPose=false
                switch result {
                case .success(let value):
                    poseScienceReport=value;poseReportRange=range
                    status=L("Results reconstructed from completed segments; iOS parity testing remains necessary.",
                             "报告已从完成的分段重建；仍须与 iOS 原版进行一致性验证。")
                case .failure(let error):status=error.localizedDescription
                }
            }
        }
    }

    private func poseScienceSection(_ report:NativeTrackingResult) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Label(L("RodentPose · Original iOS Results (custom frame window)", "RodentPose · 原版 iOS 结果（自定义帧范围）"),systemImage:"chart.bar.xaxis").font(.headline)
            Text(L("Advanced: the selected frames replace the analysis window saved in Calibrate. The guided workflow (Analysis → Review → Results) uses the Calibrate window.",
                   "高级：所选帧范围将替代“校准”中保存的分析时间段。引导流程（分析 → 复核 → 结果）使用“校准”中的时间段。"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(calculatingPose ? L("Calculating…","计算中…") : L("Calculate assay report for selected frames","根据所选帧计算实验报告")) {
                    calculatePoseResults(report)
                }.buttonStyle(.borderedProminent)
                    .disabled(calculatingPose || figureStart<0 || figureEnd>=total || figureStart>figureEnd)
                Toggle(L("Include each report figure PNG on export","导出所有实验结果图 PNG"),isOn:$exportPoseFigures)
                    .disabled(poseScienceReport==nil)
            }
            if let result=poseScienceReport,poseReportRange == figureStart...figureEnd {
                Text(L("Frames", "帧") + " \(figureStart)–\(figureEnd)").font(.caption).foregroundStyle(.secondary)
                PoseReportView(report:result,category:resultCategory)
            }
        }
    }

    private func calculatePoseResults(_ tracked:NativeTrackingResult) {
        let setup=resultVideo?.calibration?.pose
        let phase=resultVideo?.effectivePhase(for: resultAssay) ?? ""
        let range=figureStart...figureEnd
        calculatingPose=true
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result {try PoseScienceBridge.report(tracked,setup:setup,phase:phase,frames:range)}
            DispatchQueue.main.async {
                calculatingPose=false
                switch result {
                case .success(let report):
                    poseScienceReport=report
                    poseReportRange=range
                    status=L("Assay report computed from the original RodentPose formulas. iOS parity validation is pending.",
                             "已按原版 RodentPose 公式计算实验报告，尚待 iOS 一致性验证。")
                case .failure(let error):status=error.localizedDescription
                }
            }
        }
    }

    private func annotatedSource() -> AnnotatedVideoExporter.Source? {
        guard let model=short?.model ?? long.flatMap({PoseModelKind(rawValue:$0.modelName)}) else{return nil}
        let videoURL=(short != nil ? run.shortVideoURL : run.longVideoURL) ?? resultVideo.flatMap {workspace.resolveURL($0)}
        guard let videoURL, FileManager.default.fileExists(atPath:videoURL.path) else{return nil}
        return AnnotatedVideoExporter.Source(url:videoURL,model:model,short:short,long:long,
                    directory:run.longDirectory,firstFrame:figureStart,lastFrame:figureEnd)
    }

    private func estimateAnnotatedMP4() {
        guard let source=annotatedSource() else {
            status=L("First locate the original video in Review.","请先在 Review 中定位原始视频。")
            return
        }
        estimatingMP4=true;annotatedEstimate=nil
        DispatchQueue.global(qos:.utility).async {
            let access=source.url.startAccessingSecurityScopedResource()
            let folderAccess=source.directory?.startAccessingSecurityScopedResource() ?? false
            defer {if access{source.url.stopAccessingSecurityScopedResource()};if folderAccess{source.directory?.stopAccessingSecurityScopedResource()}}
            let measurement=Result {try AnnotatedVideoExporter.estimate(source)}
            DispatchQueue.main.async {
                estimatingMP4=false
                switch measurement {
                case .success(let value):annotatedEstimate=value
                case .failure(let error):status="MP4 estimate: "+error.localizedDescription
                }
            }
        }
    }

    private func writeAnnotatedMP4() {
        guard let source=annotatedSource(),annotatedEstimate != nil else{return}
        let panel=NSSavePanel();panel.allowedContentTypes=[.mpeg4Movie]
        panel.nameFieldStringValue="rodent_annotated_\(figureStart)_\(figureEnd).mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exportingMP4=true;annotatedProgress=0
        DispatchQueue.global(qos:.utility).async {
            let access=source.url.startAccessingSecurityScopedResource()
            let outputAccess=destination.startAccessingSecurityScopedResource()
            let folderAccess=source.directory?.startAccessingSecurityScopedResource() ?? false
            defer {
                if access{source.url.stopAccessingSecurityScopedResource()}
                if outputAccess{destination.stopAccessingSecurityScopedResource()}
                if folderAccess{source.directory?.stopAccessingSecurityScopedResource()}
            }
            let result=Result {
                try AnnotatedVideoExporter.export(source,to:destination) {value in
                    DispatchQueue.main.async{annotatedProgress=value}
                }
            }
            DispatchQueue.main.async {
                exportingMP4=false
                switch result {
                case .success(let n):status="Annotated MP4: \(n) encoded frames → \(destination.path)"
                case .failure(let error):status="MP4 export failed: "+error.localizedDescription
                }
            }
        }
    }

    private func scoreLimb(_ report:NativeTrackingResult, quiet: Bool = false) {
        guard let track=report.limbPoseTrack() else{return}
        let video=resultVideo
        let selected=workspace.selectedProject?.experiments.first(where:{$0.id==(video?.experimentID ?? workspace.focusedExperimentID)})?.assay
        guard let assay=selected?.limbAssay else {
            status=L("Please select a matching RodentLimb Cylinder/TST/Gait experiment before scoring events.",
                     "请先选择对应的 RodentLimb 圆筒 / 悬尾 / 步态任务，再计算事件。")
            return
        }
        // The calibration and parameters saved in the Calibrate step (RodentLimb Calibration + AssayParams).
        let setup=video?.calibration?.limb
        if let setup, setup.assay != assay {
            status=L("The saved calibration belongs to another assay; calibrate this video again.", "已保存的标定属于其他范式，请重新标定该视频。")
            return
        }
        if assay == .cylinder && !(setup?.isCalibrated ?? false) {
            if !quiet { status=L("One step left: calibration. Calibrate the cylinder for this video first.", "还差一步：标定。请先为该视频标定圆筒。") }
            return
        }
        let cal=setup?.scaledCalibration(width:report.videoWidth,height:report.videoHeight)
            ?? Calibration(circle:nil,floorY:nil,scale:nil,copiedFrom:nil)
        let params=setup?.params ?? AssayParams.defaults(for:assay)
        scoring=true
        let key = lastRunID
        DispatchQueue.global(qos:.userInitiated).async {
            let scored=NativeLimbAdapter.run(track:track,assay:assay,params:params,calibration:cal)
            DispatchQueue.main.async {
                scoring=false
                // A result of a previous video is dropped.
                guard key == lastRunID else { return }
                limbAnalysis=scored
                if !quiet {
                    status=L("Original \(assay.name.en) events loaded for inspection (not validated against manual scoring).",
                             "已载入原版\(assay.name.zh)事件供检查（未与人工评分对照验证）。")
                }
            }
        }
    }
    private func locateLongVideo() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.movie];panel.canChooseDirectories=false
        guard panel.runModal() == .OK, let url=panel.url else{return}
        run.longVideoURL=url
        status=L("Source video linked for review preview; tracking segments have not been modified.", "已关联原始视频用于预览；追踪分段未被修改。")
    }
    private func loadLongFrame(at timestamp:Double, completion: (() -> Void)? = nil) {
        guard let url=run.longVideoURL,FileManager.default.fileExists(atPath:url.path),
              let manifest=run.longManifest,let folder=run.longDirectory else {
            status += L(" Locate the original video to see a preview frame.", " 请定位原始视频以查看预览画面。")
            completion?()
            return
        }
        generation += 1
        let ticket=generation
        longAlignedFrame=nil
        longAlignedTrail=[]
        alignmentWarning=""
        let trail=trailDuration
        DispatchQueue.global(qos:.utility).async {
            let access=url.startAccessingSecurityScopedResource()
            let csvAccess=folder.startAccessingSecurityScopedResource()
            defer {
                if access{url.stopAccessingSecurityScopedResource()}
                if csvAccess{folder.stopAccessingSecurityScopedResource()}
            }
            let asset=AVURLAsset(url:url)
            let generator=AVAssetImageGenerator(asset:asset)
            generator.appliesPreferredTrackTransform=true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var actual = CMTime.invalid
            let cg=try? generator.copyCGImage(at:CMTime(seconds:max(0,timestamp),preferredTimescale:60_000),actualTime:&actual)
            let image=cg.map{NSImage(cgImage:$0,size:NSSize(width:CGFloat($0.width),height:CGFloat($0.height)))}
            let returnedTime=CMTimeGetSeconds(actual)
            let time=returnedTime.isFinite ? returnedTime : timestamp
            let result=try? LongReviewPoseLookup.load(manifest:manifest,folder:folder,
                                         time:time,lookback:trail)
            let track=asset.tracks(withMediaType:.video).first
            let dimensions=track.map{CGRect(origin:.zero,size:$0.naturalSize).applying($0.preferredTransform)}
            let displaySize=CGSize(width:abs(dimensions?.width ?? image?.size.width ?? 0),
                                   height:abs(dimensions?.height ?? image?.size.height ?? 0))
            DispatchQueue.main.async {
                defer { completion?() }
                guard generation==ticket else{return}
                preview=image
                longDisplaySize=displaySize
                let tolerance=max(0.012,0.53/max(Double(track?.nominalFrameRate ?? 30),1))
                if let value=result, let first=value.frames.last, abs(first.time-time) <= tolerance {
                    longAlignedFrame=first
                    longAlignedTrail=value.frames
                    alignmentWarning=""
                } else {
                    longAlignedFrame=nil
                    alignmentWarning=L("No timestamp-matched tracking sample for this video frame. Overlay suppressed; raw CSV unchanged.",
                                       "未找到与此画面时间戳匹配的追踪数据。已隐藏标点，原始 CSV 不变。")
                }
            }
        }
    }

    private func importLongResults() {
        let panel=NSOpenPanel()
        panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.prompt=L("Open Results", "打开结果")
        guard panel.runModal() == .OK,let folder=panel.url else {return}
        let accessed=folder.startAccessingSecurityScopedResource()
        defer {if accessed {folder.stopAccessingSecurityScopedResource()}}
        do {
            let manifestURL=folder.appendingPathComponent(LongVideoTrackingEngine.manifestName)
            let manifest=try JSONDecoder().decode(LongVideoManifest.self,from:Data(contentsOf:manifestURL))
            guard manifest.formatVersion == LongVideoTrackingEngine.formatVersion else {
                status=L("Unsupported manifest format; keep the original data unchanged.", "不支持的清单格式；原始数据保持不变。")
                return
            }
            run.acceptLong(manifest,directory:folder,source:folder.appendingPathComponent(manifest.sourceFile))
            status=L("Opened \(manifest.completed.count) completed segments.", "已打开 \(manifest.completed.count) 个已完成分段。")
            syncRun()
        } catch {status=L("Could not open long-video results: ", "无法打开长视频结果：") + error.localizedDescription}
    }

    private func indexLong(_ manifest:LongVideoManifest,folder:URL) {
        indexingLong=true
        let currentThreshold=threshold
        DispatchQueue.global(qos:.utility).async {
            let access=folder.startAccessingSecurityScopedResource()
            defer {if access {folder.stopAccessingSecurityScopedResource()}}
            do {
                let items=try TrackingReviewEventBuilder.detailedLong(manifest,folder:folder,threshold:currentThreshold)
                DispatchQueue.main.async {
                    indexedLongEvents=items;indexingLong=false
                    status=L("Indexed \(items.count) frame-level QC intervals from completed segments (up to 25,000).", "已从完成的分段索引 \(items.count) 个逐帧质控区间（最多 25,000 个）。")
                }
            } catch {
                DispatchQueue.main.async {indexingLong=false;status=L("Cannot index long-video events: ", "无法索引长视频事件：") + error.localizedDescription}
            }
        }
    }

    private func export() {
        guard total > 0,figureStart >= 0,figureEnd < total,figureStart <= figureEnd else {status=L("Invalid frame range", "帧范围无效");return}
        let panel=NSOpenPanel()
        panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true
        panel.prompt=L("Export Here", "导出到此处")
        guard panel.runModal() == .OK,let destination=panel.url else{return}
        let access=destination.startAccessingSecurityScopedResource()
        let sourceAccess=run.longDirectory?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access {destination.stopAccessingSecurityScopedResource()}
            if sourceAccess {run.longDirectory?.stopAccessingSecurityScopedResource()}
        }
        let project=workspace.selectedProject
        let video=resultVideo
        let exp=project?.experiments.first(where:{$0.id==(video?.experimentID ?? workspace.focusedExperimentID)})
        var context=ScientificExportContext()
        context.projectName=project?.name;context.experimentName=exp?.name
        context.assayID=exp?.assay.rawValue;context.animalID=video?.animalID
        context.group=video?.group;context.calibration=video?.calibration
        context.phase=video?.effectivePhase(for: exp?.assay);context.day=video?.day;context.trial=video?.trial
        context.sex=video?.sex;context.notes=video?.notes
        context.sessionDate=video?.sessionDate;context.sessionNumber=video?.sessionNumber
        context.excluded=video?.isExcluded;context.exclusionReason=video?.exclusionReason
        context.confidenceThreshold=threshold
        let verdict = video?.currentReview?.verdict ?? .unreviewed
        if verdict != .unreviewed {
            context.qcDecision = verdict.exportValue
        } else {
            context.qcDecision=reviewDecisions.values.contains("flagged") ? "reviewed_with_flags" : "unreviewed_or_partially_reviewed"
        }
        context.reviewerNotes=annotatorNotes
        do {
            let range=figureStart...figureEnd
            let package:URL
            if let short {
                package=try ScientificExportService.exportShort(short,context:context,source:run.shortVideoURL,
                      selectedFrame:chosenIndex,options:opts,into:destination,figureFrames:range)
            } else if let long,let dir=run.longDirectory {
                package=try ScientificExportService.exportLong(long,context:context,originalFolder:dir,
                      options:opts,into:destination,figureFrames:range)
            } else {status=L("Results are not available", "没有可用结果");return}
            struct Decision:Encodable {let id:String;let decision:String}
            struct ReviewMetadata:Encodable {let frameStart:Int;let frameEnd:Int;let notes:String;let decisions:[Decision];let eventSources:[String]}
            let log=ReviewMetadata(frameStart:figureStart,frameEnd:figureEnd,notes:annotatorNotes,
                      decisions:reviewDecisions.keys.sorted().map{Decision(id:$0,decision:reviewDecisions[$0] ?? "unreviewed")},
                      eventSources:Array(Set(events.map(\.source))).sorted())
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(log).write(to:package.appendingPathComponent("review_annotations.json"),options:.atomic)
            if let limbAnalysis {
                try encoder.encode(limbAnalysis).write(to:package.appendingPathComponent("rodentlimb_exploratory_analysis.json"),options:.atomic)
                if includeBehaviorFigure,let short {
                    try ScientificExportService.exportLimbEventFigure(limbAnalysis,tracked:short,
                          selectedFrames:range,to:package.appendingPathComponent("rodentlimb_events_selected_frames.png"))
                }
            }
            if let science=poseScienceReport, poseReportRange == range, !embedded {
                let meta: [String: String] = ["video": video?.fileName ?? "", "subject": video?.animalID ?? "",
                                              "custom_frame_window": "\(figureStart)-\(figureEnd)"]
                _ = try PoseReportExport.write(science,category:resultCategory,metadata:meta,to:package,
                                               includeFigures:exportPoseFigures)
            }
            status=L("Exported to ", "已导出到 ") + package.path
            NSWorkspace.shared.activateFileViewerSelecting([package])
        }catch{status=L("Export failed: ", "导出失败：") + error.localizedDescription}
    }
}


/// Frame-window lookup for long recordings. Reads at most the segments overlapping
/// [actual image PTS - lookback, actual image PTS]; never loads the complete video.
private enum LongReviewPoseLookup {
    struct Result { let frames: [NativeTrackedFrame] }
    static func load(manifest:LongVideoManifest,folder:URL,time:Double,lookback:Double) throws -> Result {
        guard let model=PoseModelKind(rawValue:manifest.modelName) else {return Result(frames:[])}
        let pointCount=model == .mousePose ? 6 : 7
        let failedColumn=4+3*pointCount
        let start=max(0,time-lookback)
        var frames:[NativeTrackedFrame]=[]
        var offset=0
        let sorted=manifest.completed.sorted{$0.index<$1.index}
        for segment in sorted {
            defer { offset += segment.records }
            guard segment.firstPTS.isFinite,segment.lastPTS.isFinite,
                  segment.lastPTS >= start-0.05, segment.firstPTS <= time+0.05 else {continue}
            let text=try String(contentsOf:folder.appendingPathComponent(segment.file),encoding:.utf8)
            for line in text.split(whereSeparator: \.isNewline).dropFirst() {
                let c=line.split(separator:",",omittingEmptySubsequences:false)
                guard c.count>failedColumn,let t=Double(c[1]),t >= start-0.04,t <= time+0.04,
                      let idx=Int(c[0]) else {continue}
                var points:[NativeTrackPoint]=[]
                points.reserveCapacity(pointCount)
                for k in 0..<pointCount {
                    let b=4+k*3
                    if let x=Double(c[b]),let y=Double(c[b+1]) {
                        points.append(NativeTrackPoint(x:x,y:y,confidence:Double(c[b+2]) ?? 0))
                    }else{points.append(.missing)}
                }
                frames.append(NativeTrackedFrame(index:offset+idx,time:t,score:Double(c[3]) ?? 0,
                                  points:points,inferenceFailed:c[failedColumn]=="1"))
            }
        }
        frames.sort{$0.time<$1.time}
        // The file reading is capped by the fixed 2-minute segment duration; final
        // return retains only the selected overlay trail and its nearest sample.
        guard let closest=frames.min(by:{abs($0.time-time)<abs($1.time-time)}) else{return Result(frames:[])}
        return Result(frames:frames.filter{$0.time <= closest.time + 0.0001 && $0.time >= closest.time-lookback})
    }
}
