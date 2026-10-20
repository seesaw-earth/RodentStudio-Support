// RunStepView.swift — step 3: run the pose model over the video with a live preview.

import SwiftUI

struct RunStepView: View {
    @ObservedObject var flow: SessionFlowModel
    @EnvironmentObject private var engine: PoseEngine
    @State private var confirmRedo = false

    private var s: Session { flow.session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let e = flow.errorMessage { Banner(text: e, style: .error) }
                if let n = flow.notice, !flow.isRunning { Banner(text: n, style: .info) }
                if case .failed(let message) = engine.state { Banner(text: message, style: .error) }
                if flow.videoURL == nil { Banner(text: L10n.tr("视频副本已删除，无法识别。"), style: .warning) }
                previewCard
                if flow.isRunning || flow.canResume {
                    progressCard
                } else if let t = flow.track, t.complete, !flow.inferenceSettingsChanged {
                    doneCard(t)
                } else {
                    readyCard
                }
            }
            .screenContent()
            .padding(.vertical, 14)
        }
        .confirmationDialog(L10n.tr("重新识别整段视频？"), isPresented: $confirmRedo, titleVisibility: .visible) {
            Button(L10n.tr("重新识别"), role: .destructive) { flow.startInference(fresh: true) }
        } message: {
            Text(L10n.tr("现有姿态数据会被替换；标定和参数保留。"))
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        Card(padding: 12) {
            ZStack(alignment: .topLeading) {
                if let live = flow.live {
                    FrameWithPose(image: live.image, frameSize: live.frameSize, poses: live.poses)
                } else {
                    FrameWithPose(image: flow.frame, frameSize: flow.frameSize, zones: flow.zones, mapping: flow.mapping)
                }
                if flow.isRunning {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                        Text(L10n.tr("实时预览 · \(Fmt.clock(flow.live?.time ?? flow.progress.videoTime))"))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if flow.isRunning || flow.canResume {
                ProgressView(value: flow.progress.fraction)
                    .tint(.accentColor)
            }
        }
    }

    // MARK: States

    private var estimatedFrames: Int {
        let v = s.video
        let end = s.inference.endTime > 0 ? min(s.inference.endTime, v.duration) : v.duration
        return max(0, Int((end - max(0, s.inference.startTime)) * v.fps / Double(max(1, s.inference.stride))))
    }

    private var readyCard: some View {
        Card {
            HStack(spacing: 14) {
                IconBadge(symbol: "sparkles", color: .accentColor, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.isReady ? L10n.tr("准备就绪") : L10n.tr("正在加载模型…")).font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.tr("约 \(estimatedFrames) 帧 · \(s.inference.stride == 1 ? L10n.tr("逐帧") : L10n.tr("每 \(s.inference.stride) 帧")) · \(s.inference.grayscale ? L10n.tr("灰度") : L10n.tr("彩色"))\(s.inference.animalCount > 1 ? L10n.tr(" · 双鼠") : "")"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                InfoButton(title: L10n.tr("识别")) {
                    InfoParagraph(L10n.tr("识别期间保持 App 在前台；屏幕不会自动锁定。"))
                    InfoParagraph(L10n.tr("切到后台会自动暂停，已识别的部分会保存，回来后可继续。"))
                    InfoParagraph(L10n.tr("识别完成后，区域和阈值都可以随时调整，结果即时更新。"))
                }
            }
            if flow.inferenceSettingsChanged {
                Banner(text: L10n.tr("识别设置已修改；重新识别会替换现有姿态数据（标定和参数保留）。"), style: .warning)
            }
        }
    }

    private var progressCard: some View {
        Card {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    ProgressRing(fraction: flow.progress.fraction, lineWidth: 9)
                    VStack(spacing: 0) {
                        Text("\(Int((flow.progress.fraction * 100).rounded(.down)))")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    Text(flow.isRunning ? L10n.tr("正在识别") : L10n.tr("已暂停"))
                        .font(.headline)
                    InfoRow(key: L10n.tr("已识别"), value: L10n.tr("\((flow.track?.count ?? 0) + (flow.isRunning ? flow.progress.processedFrames : 0)) 帧"))
                    if flow.isRunning {
                        InfoRow(key: L10n.tr("速度"), value: flow.progress.msPerFrame > 0 ? String(format: L10n.tr("%.0f ms/帧"), flow.progress.msPerFrame) : "—")
                        InfoRow(key: L10n.tr("剩余"), value: Fmt.remaining(flow.progress.remaining))
                    } else if let t = flow.track {
                        InfoRow(key: L10n.tr("已到"), value: "\(Fmt.clock(t.processedUntil)) / \(Fmt.clock(s.video.duration))")
                    }
                }
            }
            if !flow.isRunning {
                Button {
                    confirmRedo = true
                } label: {
                    Label(L10n.tr("从头重新识别"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!engine.isReady || flow.videoURL == nil)
            }
        }
    }

    private func doneCard(_ t: PoseTrack) -> some View {
        let summary = t.summary()
        return Card {
            HStack(spacing: 14) {
                IconBadge(symbol: "checkmark", color: Palette.successFill, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("识别完成")).font(.headline)
                    Text(L10n.tr("\(summary.frames) 帧 · 平均 \(Fmt.number(summary.msPerFrame, 0)) ms/帧"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 6) {
                InfoRow(key: L10n.tr("检出率"), value: String(format: "%.1f%%", summary.detectionRate * 100))
                InfoRow(key: L10n.tr("平均检测置信度"), value: String(format: "%.2f", summary.meanConfidence))
                InfoRow(key: L10n.tr("识别范围"), value: "\(Fmt.clock(t.time.first ?? 0)) – \(Fmt.clock(t.time.last ?? 0))")
            }
            if summary.detectionRate < 0.8 {
                Banner(text: L10n.tr("检出率偏低。可在回看中检查漏检帧（遮挡、反光、动物出画）。"), style: .warning)
            }
            Button {
                confirmRedo = true
            } label: {
                Label(L10n.tr("重新识别"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!engine.isReady || flow.videoURL == nil)
        }
    }
}
