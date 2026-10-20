import SwiftUI

/// Contour analysis in progress. "Stop" is in the sheet's footer.
struct TSTAnalyzingView: View {
    @Environment(TSTAppModel.self) private var model

    var body: some View {
        TSTSplitLayout {
            if model.livePreviewEnabled {
                TSTFrameImage(image: model.livePreview)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(L("Live preview is off", "实时预览已关闭")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Label(model.settings.metric == .box
                  ? L("Cyan = motion box (pixel changes are counted inside it, after aligning for swing). Orange = segmented outline, used for the posture measures and as a check.",
                      "青色为运动框（对齐摆动后统计框内像素变化）。橙色为分割轮廓，用于轮廓类指标和检查。")
                  : L("Orange = segmented mouse body. Check that the outlines follow the mice; if they do not, stop and adjust the band or the mouse colour in Detection settings.",
                      "橙色为分割出的鼠体。请确认轮廓贴合小鼠；如不贴合，可停止后调整分析带，或在“检测设置”中修改小鼠颜色。"),
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } inspector: {
            TSTInspectorSection(title: L("Analysing", "正在分析"),
                                footer: L("Every chamber is measured from the key frame to the end of the window. Passive swinging is aligned away before frames are compared, so it is not counted as movement.",
                                          "从关键帧到时间窗结束逐格测量。比较前会先对齐被动摆动，因此摆动不计为运动。")) {
                ProgressView(value: model.progress)
                HStack(alignment: .firstTextBaseline) {
                    Text(TSTFormat.remaining(model.analysisRemaining))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(String(format: "%.0f %%", model.progress * 100))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let r = model.analysisRemaining {
                    Text(String(format: L("Expected to finish at %@", "预计 %@ 完成"), TSTFormat.finishTime(r)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(model.progressText)
                    .font(.callout)
                    .monospacedDigit()
                LabeledContent(L("Elapsed", "已用时间"), value: TSTFormat.duration(model.analysisElapsed))
                    .font(.callout)
                    .monospacedDigit()
                if let v = model.analysisSpeed {
                    LabeledContent(L("Speed", "速度"), value: String(format: L("%.1f× real time", "%.1f 倍实时"), v))
                        .font(.callout)
                        .monospacedDigit()
                }
                Toggle(L("Live preview", "实时预览"),
                       isOn: Binding(get: { model.livePreviewEnabled }, set: { model.setLivePreview($0) }))
                    .help(L("The preview is redrawn a few times per second and costs little; the chambers are analysed in parallel either way.",
                            "预览每秒只刷新几次，开销很小；无论是否打开，各格都在并行分析。"))
                let w = model.analysisWindow
                LabeledContent(L("Chambers", "格子"), value: "\(model.selectedCount)")
                    .font(.callout)
                LabeledContent(L("Window", "时间窗"),
                               value: TSTFormat.seconds(w.start) + " – " + TSTFormat.seconds(w.start + w.duration))
                    .font(.callout)
                    .monospacedDigit()
            }
        }
    }
}
