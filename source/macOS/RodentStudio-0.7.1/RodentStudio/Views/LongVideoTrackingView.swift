import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Long-video path uses bounded memory and resumable disk segments.
/// Raw pose only; scientific scoring is intentionally separate.
struct LongVideoTrackingView: View {
    @EnvironmentObject private var runSession: NativeRunSession
    var forcedModel: PoseModelKind? = nil
    var suggestedURL: URL? = nil
    @State private var model: PoseModelKind = .mousePose
    @State private var videoURL: URL?
    @State private var destination: URL?
    @State private var running = false
    @State private var status = L("Select input video and an empty output folder.", "请选择输入视频和一个空的输出文件夹。")
    @State private var completed = 0
    @State private var total = 1
    @State private var currentFrames = 0
    @State private var cancellation: NativeTrackingCancellation?
    @State private var livePreview: NativeLivePreview?
    @State private var elapsedStart:TimeInterval = 0
    @State private var estimatedRemaining:Double?
    @State private var sourceTime = 0.0
    @State private var startFraction: Double?
    private let segmentSeconds = 120.0

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Divider()
            Text(L("Long-video safe tracking · checkpointed (experimental)", "长视频安全追踪 · 断点续跑（实验性）")).font(.headline)
            Text(L("Sequential AVFoundation decoding, one Core ML frame at a time. Writes raw pose CSV in 2-minute segments; supports cancel and resume. Does not load the full trajectory into memory.", "AVFoundation 顺序解码，Core ML 逐帧识别。原始姿态 CSV 按 2 分钟分段写入；支持取消和续跑；不会把整条轨迹载入内存。"))
                .foregroundStyle(.secondary).font(.callout)
            Picker(L("Independent model", "独立选择模型"), selection: $model) {
                ForEach(forcedModel.map { [$0] } ?? PoseModelKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }.disabled(running || forcedModel != nil)
            HStack {
                Button(L("Choose input video…", "选择输入视频…")) { chooseVideo() }.disabled(running || suggestedURL != nil)
                Text(videoURL?.lastPathComponent ?? L("Not selected", "未选择")).lineLimit(1).font(.caption)
            }
            HStack {
                Button(L("Choose output folder…", "选择输出文件夹…")) { chooseFolder() }.disabled(running)
                Text(destination?.lastPathComponent ?? L("Not selected", "未选择")).lineLimit(1).font(.caption)
            }
            HStack {
                Button(L("Start / Resume", "开始 / 继续")) { start() }
                    .disabled(running || videoURL == nil || destination == nil || !NativeModelCatalog.available(forcedModel ?? model))
                if running { Button(L("Cancel after current frame", "处理完当前帧后取消")) { cancellation?.cancel() } }
                ProgressView(value: Double(completed), total: Double(max(total, 1))).frame(width: 170)
                Text(L("\(completed) / \(total) segments · \(currentFrames) frames in current segment", "\(completed) / \(total) 个分段 · 当前分段 \(currentFrames) 帧"))
                    .font(.caption).monospacedDigit()
            }
            if running {
                HStack(spacing:14) {
                    Text(L("Video time", "视频时间") + " " + CalibrationFrameScrubber.clock(sourceTime))
                    Text(estimatedRemaining.map {L("Est. remaining", "预计剩余") + " " + CalibrationFrameScrubber.clock($0)}
                         ?? L("Estimating remaining time…", "正在估算剩余时间…"))
                }.font(.callout).monospacedDigit()
                if let livePreview {
                    NativeLiveTrackingPreviewView(snapshot:livePreview)
                        .frame(maxWidth:580,maxHeight:350)
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(L("Outputs: per-segment CSV with inference_failed flag and manifest (format v2). For a previous v1 result folder choose a new output folder. Existing completed v1 CSVs remain unchanged. Behaviour metrics are NOT validated.", "输出：每个分段的 CSV（含 inference_failed 标记）和清单（格式 v2）。旧的 v1 结果文件夹请选择新的输出文件夹；已有的 v1 CSV 不会被修改。行为指标未经验证。"))
                .font(.caption).foregroundStyle(.orange)
        }.onAppear(perform: loadGuidedContext)
    }
    // Set only when launching this view inside an assay-bound workflow.
    private func loadGuidedContext() {
        if let forcedModel { model = forcedModel }
        if let suggestedURL { videoURL = suggestedURL }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { videoURL = panel.url; status = L("Video selected.", "已选择视频。") }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Use Folder", "使用此文件夹")
        if panel.runModal() == .OK { destination = panel.url; status = L("Destination selected.", "已选择输出位置。") }
    }
    private func start() {
        guard let videoURL, let destination else { return }
        running = true
        completed = 0
        livePreview = nil
        estimatedRemaining = nil
        startFraction = nil
        elapsedStart = ProcessInfo.processInfo.systemUptime
        total = 1
        currentFrames = 0
        status = L("Processing… completed segments are saved on disk.", "正在处理……已完成的分段会保存在磁盘上。")
        let selected = forcedModel ?? model
        let chunkDuration = segmentSeconds
        let token = NativeTrackingCancellation()
        cancellation = token
        DispatchQueue.global(qos: .userInitiated).async {
            let inAccess = videoURL.startAccessingSecurityScopedResource()
            let outAccess = destination.startAccessingSecurityScopedResource()
            defer {
                if inAccess { videoURL.stopAccessingSecurityScopedResource() }
                if outAccess { destination.stopAccessingSecurityScopedResource() }
            }
            do {
                let manifest = try LongVideoTrackingEngine.run(videoURL: videoURL, destination: destination,
                    kind: selected, segmentSeconds: chunkDuration, cancellation: token) { p in
                    DispatchQueue.main.async {
                        completed = p.completedSegments
                        total = p.totalSegments
                        currentFrames = p.processedInSegment
                        if let preview = p.livePreview {livePreview = preview}
                        if let time = p.sourceTime, let duration = p.sourceDuration, duration > 0 {
                            sourceTime = time
                            let fraction = max(0.001,min(1,time / duration))
                            if startFraction == nil {startFraction = fraction}
                            let recentFraction = fraction - (startFraction ?? 0)
                            let elapsed=ProcessInfo.processInfo.systemUptime - elapsedStart
                            if elapsed>8 && recentFraction > 0.015 {
                                estimatedRemaining = elapsed * (1-fraction)/recentFraction
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    running = false
                    cancellation = nil
                    runSession.acceptLong(manifest, directory: destination, source: videoURL)
                    let failures = manifest.completed.reduce(0) { $0 + $1.failedFrames }
                    status = L("Completed \(manifest.completed.count) segments (\(failures) inference failures flagged) in \(destination.lastPathComponent).", "已在 \(destination.lastPathComponent) 完成 \(manifest.completed.count) 个分段（\(failures) 帧识别失败已标记）。")
                }
            } catch {
                DispatchQueue.main.async {
                    running = false
                    cancellation = nil
                    status = L("Stopped: \(error.localizedDescription). Finished CSV segments remain available for resume.", "已停止：\(error.localizedDescription)。已完成的 CSV 分段保留，可续跑。")
                }
            }
        }
    }
}
