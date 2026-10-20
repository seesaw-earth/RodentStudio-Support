import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Experimental native video pose tracker, independent of the project's validated assay pipeline.
/// Outputs per-frame keypoints and optional raw RodentLimb PoseTrack; never makes clinical/scientific scores.
struct NativeVideoTrackingView: View {
    @EnvironmentObject private var runSession: NativeRunSession
    var forcedModel: PoseModelKind? = nil
    var suggestedURL: URL? = nil
    @State private var model: PoseModelKind = .mousePose
    @State private var videoURL: URL?
    @State private var running = false
    @State private var progress = 0
    @State private var total = 0
    @State private var status = L("Select a video and a bundled model.", "请选择视频和已打包的模型。")
    @State private var result: NativeTrackingResult?
    @State private var currentFrame = 0
    @State private var preview: NSImage?
    @State private var previewGeneration = 0
    @State private var matchedFrameIndex: Int?
    @State private var frameAlignmentMessage = ""
    @State private var cancellation: NativeTrackingCancellation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(L("Whole-video Core ML tracking (experimental)", "整段视频 Core ML 追踪（实验性）")).font(.headline)
            Text(L("Short-video mode retains all frames in memory. For 5+ minute videos use Long-video safe tracking below (disk segments, resume). Failed inference frames are explicitly flagged in CSV; scientific scoring is not validated.", "短视频模式把所有帧保存在内存中。5 分钟以上的视频请用下方的长视频安全追踪（磁盘分段、可续跑）。识别失败的帧会在 CSV 中明确标记；科学评分未经验证。"))
                .font(.callout).foregroundStyle(.secondary)
            Picker(L("Pose model", "姿态模型"), selection: $model) {
                ForEach(forcedModel.map { [$0] } ?? PoseModelKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }.pickerStyle(.menu).disabled(running || forcedModel != nil)
            HStack(spacing: 12) {
                Button(L("Choose video…", "选择视频…")) { chooseVideo() }.disabled(running || suggestedURL != nil)
                Text(videoURL?.lastPathComponent ?? L("No video chosen", "未选择视频"))
                    .lineLimit(1).foregroundStyle(.secondary)
            }
            HStack {
                Button(running ? L("Analysing…", "正在分析…") : L("Track entire video", "追踪整段视频")) { start() }
                    .disabled(running || videoURL == nil || !NativeModelCatalog.available(forcedModel ?? model))
                if running {
                    Button(L("Cancel", "取消")) { cancellation?.cancel() }
                    ProgressView(value: Double(progress), total: Double(max(1, total)))
                        .frame(maxWidth: 190)
                    Text("\(progress) / ~\(total)").monospacedDigit().font(.caption)
                }
            }
            Text(status).font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary).textSelection(.enabled)
            if let report = result {
                Text(L("\(report.frames.count) frames · \(String(format: "%.1f", report.detectionFraction * 100))% with detection on valid frames · \(report.inferenceFailureCount) inference failures · \(String(format: "%.1f", report.elapsedSeconds)) s processing", "\(report.frames.count) 帧 · 有效帧中 \(String(format: "%.1f", report.detectionFraction * 100))% 检测到小鼠 · \(report.inferenceFailureCount) 帧识别失败 · 处理用时 \(String(format: "%.1f", report.elapsedSeconds)) s"))
                    .font(.callout)
                HStack {
                    Button(L("Export raw CSV…", "导出原始 CSV…")) { saveCSV(report) }
                    if report.model == .cylinderV2 {
                        Button(L("Export RodentLimb PoseTrack…", "导出 RodentLimb PoseTrack…")) { saveLimbTrack(report) }
                    }
                }
                if report.frames.count > 1 {
                    Slider(value: Binding(get: { Double(currentFrame) }, set: { next in
                        currentFrame = min(report.frames.count - 1, max(0, Int(next)))
                        loadPreview(for: report)
                    }), in: 0...Double(report.frames.count - 1), step: 1)
                    Text(L("Frame", "帧") + " \(currentFrame + 1) / \(report.frames.count) · t=\(String(format: "%.3f", report.frames[currentFrame].time)) s")
                        .font(.caption).monospacedDigit()
                }
                if let preview {
                    if let matchedFrameIndex {
                        let frame = report.frames[matchedFrameIndex]
                        NativeTrackingCanvas(model:report.model,image:preview,videoWidth:report.videoWidth,
                            videoHeight:report.videoHeight,frame:frame,previous:[frame],threshold:0.35,showTrail:false)
                            .frame(height:310).clipShape(RoundedRectangle(cornerRadius:8))
                    } else {
                        Image(nsImage:preview).resizable().scaledToFit().frame(height:310)
                        Text(frameAlignmentMessage).font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(L("Rendering video preview…", "正在生成视频预览…")).font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Overlay is a read-only preview. Exported tracks are unvalidated research inputs, not final behavioural measurements.", "叠加层只是只读预览。导出的轨迹是未经验证的研究输入，不是最终行为测量值。"))
                    .font(.caption).foregroundStyle(.orange)
            }
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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        videoURL = url
        result = nil; preview = nil
        status = L("Ready · ", "就绪 · ") + url.lastPathComponent
    }

    private func start() {
        guard let url = videoURL, NativeModelCatalog.available(forcedModel ?? model) else { return }
        let selectedModel = forcedModel ?? model
        let token = NativeTrackingCancellation()
        cancellation = token
        running = true; progress = 0; total = 1; result = nil; preview = nil
        status = L("Processing video on Apple Core ML…", "正在用 Apple Core ML 处理视频…")
        DispatchQueue.global(qos: .userInitiated).async {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let output = try NativeVideoTrackingEngine.run(url: url, kind: selectedModel, cancellation: token) { processed, estimated in
                    DispatchQueue.main.async { progress = processed; total = estimated }
                }
                DispatchQueue.main.async {
                    result = output; running = false; cancellation = nil
                    runSession.acceptShort(output, source: url)
                    progress = output.frames.count; total = output.frames.count
                    currentFrame = output.frames.count / 2
                    status = L("Completed pose tracking · \(output.inferenceFailureCount) failed inference frames flagged (inference_failed column) · no behavioural scores computed", "姿态追踪完成 · \(output.inferenceFailureCount) 帧识别失败已标记（inference_failed 列）· 未计算行为评分")
                    loadPreview(for: output)
                }
            } catch {
                DispatchQueue.main.async {
                    running = false; cancellation = nil
                    status = L("Stopped · ", "已停止 · ") + error.localizedDescription
                }
            }
        }
    }

    private func loadPreview(for report: NativeTrackingResult) {
        guard let url = videoURL, report.frames.indices.contains(currentFrame) else {return}
        let targetIndex=currentFrame
        let time = report.timeOffset + report.frames[targetIndex].time
        previewGeneration += 1
        let generation=previewGeneration
        matchedFrameIndex=nil
        DispatchQueue.global(qos:.utility).async {
            let accessed=url.startAccessingSecurityScopedResource()
            defer {if accessed {url.stopAccessingSecurityScopedResource()}}
            let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url))
            generator.appliesPreferredTrackTransform=true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var returned=CMTime.invalid
            let cg=try? generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:60_000),actualTime:&returned)
            let image=cg.map{NSImage(cgImage:$0,size:NSSize(width:CGFloat($0.width),height:CGFloat($0.height)))}
            let actual=CMTimeGetSeconds(returned)
            // For short-video advanced mode, a narrow local search finds the nearest PTS.
            let lower=max(0,targetIndex-10),upper=min(report.frames.count-1,targetIndex+10)
            let nearest=(lower...upper).min{abs(report.timeOffset+report.frames[$0].time-actual)<abs(report.timeOffset+report.frames[$1].time-actual)} ?? targetIndex
            let matching=actual.isFinite && abs(report.timeOffset+report.frames[nearest].time-actual) <= max(0.012,0.53/max(report.fps,1))
            let correctAspect=image.map{abs($0.size.width/max($0.size.height,1)-CGFloat(report.videoWidth)/CGFloat(max(1,report.videoHeight))) < 0.015} ?? false
            DispatchQueue.main.async {
                guard previewGeneration==generation else{return}
                preview=image
                matchedFrameIndex=(matching && correctAspect) ? nearest : nil
                frameAlignmentMessage = matching && correctAspect ? "" :
                    L("Tracking timestamp/orientation mismatch: annotation suppressed.",
                      "时间戳或画面方向不匹配：为避免错画已隐藏标点。")
            }
        }
    }

    private func saveCSV(_ report: NativeTrackingResult) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(report.model.rawValue)_raw_keypoints.csv"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            try report.csv().write(to: target, atomically: true, encoding: .utf8)
            status = "CSV exported · \(target.lastPathComponent)"
        } catch { status = "CSV export failed · \(error.localizedDescription)" }
    }

    private func saveLimbTrack(_ report: NativeTrackingResult) {
        guard let track = report.limbPoseTrack() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CylinderV2_native_pose.mpt2"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(track).write(to: target, options: .atomic)
            status = L("RodentLimb PoseTrack exported · ", "已导出 RodentLimb PoseTrack · ") + target.lastPathComponent
        } catch { status = L("PoseTrack export failed · ", "PoseTrack 导出失败 · ") + error.localizedDescription }
    }
}
