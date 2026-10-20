import SwiftUI
import AppKit

/// Key-frame scan in progress: live detections on the left, per-chamber status on the right.
/// Stopping or accepting the key frame happens in the sheet's footer.
struct TSTScanView: View {
    @Environment(TSTAppModel.self) private var model

    var body: some View {
        TSTSplitLayout {
            TSTFrameImage(image: model.scanPreview)
            if let k = model.keyResult, !k.times.isEmpty {
                TSTPresenceTimeline(result: k, keyTime: k.keyTime, analysisEnd: nil, duration: model.info?.duration ?? 1)
                    .frame(height: CGFloat(k.selected.count) * 16 + 44)
            }
        } inspector: {
            TSTInspectorSection(title: L("Looking for the key frame", "正在寻找关键帧"),
                                footer: String(format: L("The key frame is the first moment at which every selected chamber has had a mouse for %d s; the analysis starts there and runs to the end of the video. Letting the scan finish gives each chamber's motion box the full range of the mouse's movement and shows when mice are taken down.",
                                                         "关键帧是所有选中格子都已有小鼠并持续 %d 秒的第一个时刻，分析从这里开始并一直进行到视频结束。让扫描完整跑完，各格的运动框才能覆盖小鼠的全部活动范围，并能看出小鼠何时被取下。"),
                                              Int(model.stored.keyFrame.stableSec))) {
                ProgressView(value: model.scanProgress)
                Text(TSTFormat.remaining(model.scanRemaining))
                    .font(.headline)
                    .monospacedDigit()
                Text(model.scanText)
                    .font(.callout)
                    .monospacedDigit()
                if let t = model.keyResult?.keyTime {
                    Label(String(format: L("Key frame found at %@", "已找到关键帧：%@"), TSTFormat.seconds(t)),
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
            if let layout = model.layout {
                TSTInspectorSection(title: L("Chambers", "格子")) {
                    TSTChamberStatusGrid(layout: layout, result: model.keyResult)
                }
            }
        }
    }
}

/// One chip per chamber: not used / waiting / mouse detected (with time).
struct TSTChamberStatusGrid: View {
    let layout: ChamberLayout
    let result: KeyFrameResult?

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(Array(0..<layout.count), id: \.self) { i in
                let sel = i < layout.enabled.count && layout.enabled[i]
                let hung = result.flatMap { i < $0.hungAt.count ? $0.hungAt[i] : nil }
                HStack(spacing: 6) {
                    Image(systemName: !sel ? "minus.circle" : (hung != nil ? "checkmark.circle.fill" : "hourglass"))
                        .foregroundStyle(!sel ? Color.secondary : (hung != nil ? Color.green : Color.orange))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(String(format: L("Chamber %d", "第 %d 格"), i + 1)).font(.caption.bold())
                        Text(!sel ? L("skipped", "跳过")
                                  : (hung.map { String(format: L("mouse from %.0f s", "%.0f 秒起有鼠"), $0) } ?? L("waiting…", "等待中…")))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: NSColor.controlBackgroundColor)))
            }
        }
    }
}
