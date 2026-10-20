// SessionFlowView.swift — the full-screen workspace of one analysis: step bar, step content and
// a back / next bar that is the same on every step.

import SwiftUI

struct SessionFlowView: View {
    @ObservedObject var flow: SessionFlowModel
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var engine: PoseEngine
    @State private var showReview = false
    @State private var showExport = false
    @State private var confirmDelete = false
    @State private var confirmRerun = false
    @State private var confirmDeleteVideo = false

    var body: some View {
        NavigationStack {
            content
                .background(Palette.canvas)
                .chromeBar(.top) {
                    StepBar(current: flow.step, isAvailable: { flow.isAvailable($0) }, isDone: { flow.isDone($0) }) { s in
                        withAnimation(Motion.snappy) { flow.step = s }
                    }
                }
                .chromeBar(.bottom) { bottomBar }
                .navigationTitle(flow.session.subjectID.isEmpty ? flow.session.paradigm.title : flow.session.subjectID)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .task { await flow.loadIfNeeded() }
        .sheet(isPresented: $showExport) { ExportSheet(flow: flow) }
        .fullScreenCover(isPresented: $showReview) { ReviewPlayerView(flow: flow) }
        .confirmationDialog(L10n.tr("删除这次分析？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.tr("删除"), role: .destructive) {
                let s = flow.session
                app.closeFlow()
                app.delete(s)
            }
        } message: {
            Text(L10n.tr("视频副本、姿态数据和结果都会被删除，无法恢复。"))
        }
        .confirmationDialog(L10n.tr("删除视频副本？"), isPresented: $confirmDeleteVideo, titleVisibility: .visible) {
            Button(L10n.tr("删除视频"), role: .destructive) {
                flow.store.deleteVideo(of: flow.session)
                flow.session.videoFile = nil
            }
        } message: {
            Text(L10n.tr("姿态数据和结果会保留，可以继续调整参数、导出；但无法再回看视频或重新识别。"))
        }
        .confirmationDialog(L10n.tr("重新识别？"), isPresented: $confirmRerun, titleVisibility: .visible) {
            Button(L10n.tr("用新设置重新识别"), role: .destructive) { flow.startInference(fresh: true) }
        } message: {
            Text(L10n.tr("识别设置已修改，现有的姿态数据会被替换。"))
        }
        .sensoryFeedback(.success, trigger: flow.track?.complete == true) { _, done in done }
    }

    @ViewBuilder
    private var content: some View {
        switch flow.step {
        case .info: InfoStepView(flow: flow)
        case .calibrate: CalibrationStepView(flow: flow)
        case .run: RunStepView(flow: flow)
        case .result: ResultStepView(flow: flow, showReview: $showReview, showExport: $showExport)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                app.closeFlow()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel(L10n.tr("关闭"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showExport = true
                } label: {
                    Label(L10n.tr("导出数据"), systemImage: "square.and.arrow.up")
                }
                .disabled(flow.report == nil)
                Button {
                    showReview = true
                } label: {
                    Label(L10n.tr("回看视频"), systemImage: "play.rectangle")
                }
                .disabled(flow.videoURL == nil || !flow.hasPose)
                Button {
                    nextAnimal()
                } label: {
                    Label(L10n.tr("下一只（同范式）"), systemImage: "forward")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDeleteVideo = true
                } label: {
                    Label(L10n.tr("删除视频副本"), systemImage: "film")
                }
                .disabled(flow.videoURL == nil || flow.isRunning)
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(L10n.tr("删除此分析"), systemImage: "trash")
                }
                .disabled(flow.isRunning)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func nextAnimal() {
        let p = flow.session.paradigm
        app.closeFlow()
        let app = self.app
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            app.startNewSession(p)
        }
    }

    // MARK: Bottom bar

    private var backStep: FlowStep? {
        switch flow.step {
        case .info: return nil
        case .calibrate: return .info
        case .run: return .calibrate
        case .result: return .calibrate
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let back = backStep {
                    Button {
                        withAnimation(Motion.snappy) { flow.step = back }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward").font(.subheadline.weight(.semibold))
                            Text(back == .calibrate && flow.step == .result ? L10n.tr("调整") : back.title)
                                .lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 50)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(PressableCardStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(flow.isRunning && flow.step == .run)
                    .accessibilityLabel(L10n.tr("返回：") + (back == .calibrate && flow.step == .result ? L10n.tr("调整") : back.title))
                }
                primaryAction
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch flow.step {
        case .info:
            nextButton(L10n.tr("下一步：标定"), symbol: "viewfinder") { flow.step = .calibrate }
        case .calibrate:
            if flow.hasPose && !flow.inferenceSettingsChanged {
                nextButton(L10n.tr("查看结果"), symbol: "chart.bar.xaxis") { flow.step = .result }
            } else {
                nextButton(L10n.tr("下一步：识别"), symbol: "sparkles") { flow.step = .run }
            }
        case .run:
            if flow.isRunning {
                Button(role: .destructive) {
                    flow.stopInference()
                } label: {
                    Label(L10n.tr("暂停识别"), systemImage: "pause.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Palette.dangerFill))
            } else if flow.inferenceSettingsChanged {
                nextButton(L10n.tr("用新设置重新识别"), symbol: "arrow.clockwise") { confirmRerun = true }
                    .disabled(!engine.isReady || flow.videoURL == nil)
            } else if flow.canResume {
                nextButton(L10n.tr("继续识别"), symbol: "play.fill") { flow.startInference() }
                    .disabled(!engine.isReady || flow.videoURL == nil)
            } else if flow.track?.complete == true {
                nextButton(L10n.tr("查看结果"), symbol: "chart.bar.xaxis") { flow.step = .result }
            } else {
                nextButton(L10n.tr("开始识别"), symbol: "play.fill") { flow.startInference() }
                    .disabled(!engine.isReady || flow.videoURL == nil)
            }
        case .result:
            nextButton(L10n.tr("回看视频"), symbol: "play.rectangle") { showReview = true }
                .disabled(flow.videoURL == nil)
        }
    }

    private func nextButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Motion.snappy) { action() }
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

// MARK: - Step bar

struct StepBar: View {
    let current: FlowStep
    let isAvailable: (FlowStep) -> Bool
    let isDone: (FlowStep) -> Bool
    let onSelect: (FlowStep) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(FlowStep.allCases) { step in
                if step != .info {
                    Capsule()
                        .fill(step.rawValue <= current.rawValue ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 15)
                }
                chip(step)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func chip(_ step: FlowStep) -> some View {
        let available = isAvailable(step)
        let isCurrent = step == current
        let done = isDone(step) && !isCurrent
        return Button {
            if !isCurrent && available { onSelect(step) }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.accentColor : (done ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12)))
                        .frame(width: 30, height: 30)
                    Image(systemName: done ? "checkmark" : step.symbol)
                        .font(.system(size: 13, weight: .bold)) // symbol inside a fixed 30 pt circle
                        .foregroundStyle(isCurrent ? Color.white : (done ? Color.accentColor : (available ? Color.primary : Color.secondary)))
                }
                Text(step.title)
                    .font(.caption.weight(isCurrent ? .bold : .medium))
                    .foregroundStyle(isCurrent || available ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 52, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(available || isCurrent ? 1 : 0.5)
        .disabled(!available && !isCurrent)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityLabel(L10n.tr("第 \(step.rawValue + 1) 步：\(step.title)") + (isCurrent ? L10n.tr("，当前") : (done ? L10n.tr("，已完成") : "")))
    }
}
