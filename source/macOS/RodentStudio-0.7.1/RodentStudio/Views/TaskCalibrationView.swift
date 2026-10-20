// TaskCalibrationView.swift — the Calibrate step. Shows the calibration editor of the task's own app
// (RodentPose, RodentFlow or RodentLimb) on a frame of the selected video, and the two ways RodentLimb
// saves a calibration: for this video, or for every video of the task (fixed camera only).

import SwiftUI

struct TaskCalibrationView: View {
    @EnvironmentObject private var run: NativeRunSession

    let assay: StudyAssay
    let video: VideoRecord
    let videoURL: URL?
    let taskVideoCount: Int
    /// Working copy owned by the workflow, so leaving the step can save it.
    @Binding var draft: DesktopCalibration?
    let isSaved: Bool
    let onCreatedDefault: (DesktopCalibration) -> Void
    let onSave: () -> Void
    let onApplyToAll: () -> Void

    @StateObject private var frames = CalibrationFrameLoader()
    @State private var confirmAll = false

    private var limbTrack: PoseTrack? {
        guard assay.limbAssay != nil, run.videoID == video.id, let r = run.shortResult, r.model == .cylinderV2 else { return nil }
        return r.limbPoseTrack()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if videoURL == nil {
                ContentUnavailableView(L("The video cannot be opened", "无法打开视频"), systemImage: "film.stack",
                                       description: Text(L("It may have been moved or renamed. Remove it from the project and add it again.",
                                                           "文件可能已被移动或重命名。请将其从项目中移除后重新添加。")))
            } else if draft == nil {
                ProgressView(L("Loading a frame of the video…", "正在读取视频画面…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: video.id) { loadInitialFrame() }
        .onChange(of: frames.loadedCount) { _, _ in createDefaultIfNeeded() }
        .onChange(of: frames.failed) { _, failed in if failed { createDefaultIfNeeded() } }
        .confirmationDialog(L("Use this calibration for every video of this assay? Do this only if the camera did not move.",
                              "将此标定用于该范式的所有视频？仅在相机位置未移动时这样做。"),
                            isPresented: $confirmAll, titleVisibility: .visible) {
            Button(L("Use for all", "全部使用")) { onApplyToAll() }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Calibrate", "校准")).font(.title3.bold())
                if isSaved {
                    Label(L("Saved for this video. Changes are saved automatically.", "已保存到本视频，修改会自动保存。"),
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label(L("Not saved yet — check the handles, then Save or Continue.", "尚未保存——检查手柄后点“保存”或“继续”。"),
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let from = draft?.copiedFrom, draft?.limb == nil {
                    Label(String(format: L("Calibration reused from %@ — check it.", "标定沿用自 %@，请检查。"), from), systemImage: "doc.on.doc")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if !isSaved {
                Button(L("Save for this video", "仅保存到本视频")) { onSave() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(draft == nil)
            }
            Button(L("Use for all videos of this task…", "用于该任务的所有视频…")) { confirmAll = true }
                .disabled(draft == nil || taskVideoCount < 2)
                .help(L("Copies this calibration to every video of the task. Only if the camera did not move.",
                        "把此标定复制到该任务的所有视频。仅在相机未移动时使用。"))
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let pose = draft?.pose {
            PoseCalibrationEditor(setup: Binding(get: { draft?.pose ?? pose }, set: { draft?.pose = $0 }),
                                  phase: video.effectivePhase(for: assay),
                                  image: frames.image, loadingFrame: frames.loading,
                                  duration: video.durationSeconds, onSeek: seek)
        } else if let flow = draft?.flow {
            FlowCalibrationEditor(setup: Binding(get: { draft?.flow ?? flow }, set: { draft?.flow = $0 }),
                                  image: frames.image,
                                  frameSize: frameSize,
                                  loadingFrame: frames.loading,
                                  duration: video.durationSeconds, onSeek: seek)
        } else if let limb = draft?.limb {
            LimbCalibrationEditor(setup: Binding(get: { draft?.limb ?? limb }, set: { draft?.limb = $0 }),
                                  image: frames.image, shownTime: frames.shownTime, loadingFrame: frames.loading,
                                  duration: video.durationSeconds, track: limbTrack, onSeek: seek)
        } else {
            ContentUnavailableView(L("This task has no calibration", "该任务无需标定"), systemImage: "viewfinder")
        }
    }

    /// RodentFlow calibration is stored in normalized coordinates; the frame only sets the aspect.
    private var frameSize: CGSize {
        uprightFrameSize(record: video, image: frames.image)
    }

    // MARK: Frames and defaults

    private func loadInitialFrame() {
        guard let videoURL else { return }
        let stored = draft?.pose?.frameTime ?? draft?.flow?.frameTime ?? draft?.limb?.frameTime
        let start = stored ?? min(1, max(0, video.durationSeconds / 2))
        frames.load(url: videoURL, at: start)
    }

    private func seek(_ t: Double) {
        guard let videoURL else { return }
        frames.load(url: videoURL, at: t)
    }

    private func createDefaultIfNeeded() {
        guard draft == nil else { return }
        let size = uprightFrameSize(record: video, image: frames.image)
        let fresh = DesktopCalibration.task(for: assay, frameWidth: Double(size.width), frameHeight: Double(size.height))
        onCreatedDefault(fresh)
    }
}
