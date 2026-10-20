import SwiftUI

// MARK: - Layout shared by the steps of the TST sheet
//
// The picture is the thing being judged, so it gets all the room the sheet has (left); the settings
// for the step sit in a fixed-width column on the right, like an inspector. Moving on, going back and
// cancelling always happen in the sheet's footer, never inside a scrolling form.

struct TSTSplitLayout<Picture: View, Inspector: View>: View {
    @ViewBuilder var picture: Picture
    @ViewBuilder var inspector: Inspector

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) { picture }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.primary.opacity(0.035))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { inspector }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 340)
        }
    }
}

struct TSTInspectorSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A video frame scaled to fit, or a spinner while it is not available yet.
struct TSTFrameImage: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Centered spinner with a status line (reading the video, finding chambers).
struct TSTBusyView: View {
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum TSTFormat {
    /// "42.5 s", or "83.5 s (1:23.5)" from one minute on, so a time can be found in a video player.
    static func seconds(_ s: Double) -> String {
        guard s.isFinite else { return "–" }
        let plain = String(format: L("%.1f s", "%.1f 秒"), s)
        guard s >= 60 else { return plain }
        let m = Int(s) / 60
        let rest = s - Double(m * 60)
        return plain + String(format: " (%d:%04.1f)", m, rest)
    }

    /// Wall-clock duration for estimates: "45 s", "3 min 20 s", "1 h 05 min".
    static func duration(_ s: Double) -> String {
        let total = max(0, Int(s.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        if h > 0 { return String(format: L("%d h %02d min", "%d 小时 %02d 分"), h, m) }
        if m > 0 { return String(format: L("%d min %02d s", "%d 分 %02d 秒"), m, sec) }
        return String(format: L("%d s", "%d 秒"), sec)
    }

    /// "About 3 min 20 s left" / "Estimating time left…".
    static func remaining(_ s: Double?) -> String {
        guard let s, s.isFinite else { return L("Estimating time left…", "正在估算剩余时间…") }
        return String(format: L("About %@ left", "约剩 %@"), duration(s))
    }

    /// Clock time at which a task that needs `s` more seconds should finish.
    static func finishTime(_ s: Double) -> String {
        Date().addingTimeInterval(s).formatted(date: .omitted, time: .shortened)
    }

    /// "1, 3 and 5" style list of chamber numbers.
    static func list(_ numbers: [Int]) -> String {
        numbers.map(String.init).joined(separator: L(", ", "、"))
    }
}

// MARK: - Step: chambers

/// Chambers are found automatically; the user checks the count and walls and picks the chambers that hold a mouse.
struct TSTChambersView: View {
    @Environment(TSTAppModel.self) private var model
    var onShowSettings: () -> Void

    var body: some View {
        TSTSplitLayout {
            if let preview = model.preview, let layout = model.layout {
                TSTChamberEditor(image: preview, layout: layout, showBand: false)
                    .aspectRatio(CGFloat(layout.imageWidth) / CGFloat(max(1, layout.imageHeight)), contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Label(L("Click a chamber to include or skip it. Drag the white handles onto the walls between chambers.",
                        "点击格子可选中或跳过；拖动白色手柄，对齐格子之间的隔板。"),
                      systemImage: "cursorarrow.click")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } inspector: {
            if let layout = model.layout {
                TSTInspectorSection(title: L("Chambers", "格子")) {
                    Stepper(value: Binding(get: { layout.count }, set: { model.setChamberCount($0) }), in: 1...16) {
                        LabeledContent(L("Number of chambers", "格子数"), value: "\(layout.count)")
                    }
                    HStack(spacing: 8) {
                        Button(L("Detect again", "重新检测"), systemImage: "wand.and.stars") { model.redetect() }
                        Button(L("Split evenly", "平均分割"), systemImage: "rectangle.split.3x1") { model.equalSplit() }
                    }
                    .controlSize(.small)
                    if !layout.notes.isEmpty {
                        DisclosureGroup(L("Detection details", "检测详情")) {
                            Text(layout.notes.joined(separator: "\n"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.caption)
                    }
                }

                TSTInspectorSection(title: L("Which chambers hold a mouse?", "哪些格子里有小鼠？"),
                                    footer: model.autoDetected
                                        ? L("Pre-selected where a mouse was seen in the video. Only selected chambers are analysed.",
                                            "已预先勾选在视频中检测到小鼠的格子。只分析勾选的格子。")
                                        : L("Only selected chambers are analysed.", "只分析勾选的格子。")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6, alignment: .leading)],
                              alignment: .leading, spacing: 6) {
                        ForEach(0..<layout.count, id: \.self) { i in
                            Toggle(isOn: Binding(get: { i < layout.enabled.count && layout.enabled[i] },
                                                 set: { _ in model.toggleChamber(i) })) {
                                Text(String(format: L("Chamber %d", "第 %d 格"), i + 1))
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    HStack(spacing: 8) {
                        Button(L("Select all", "全选")) { model.setAllChambers(true) }
                        Button(L("Select none", "全不选")) { model.setAllChambers(false) }
                        Spacer()
                        Text(String(format: L("%d of %d", "%d / %d"), model.selectedCount, layout.count))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.small)
                }
            }

            TSTInspectorSection(title: L("Mouse detector", "小鼠检测器")) {
                Text(model.detectorName).font(.callout).textSelection(.enabled)
                if !model.yoloAvailable {
                    Text(L("No YOLO model is available, so the classical detector is used. A model trained on your rig copes better with hands, sleeves and shadows.",
                           "没有可用的 YOLO 模型，正在使用经典检测器。用自己装置训练的模型更能排除手、袖子和阴影的干扰。"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(L("Detection settings…", "检测设置…"), systemImage: "gearshape") { onShowSettings() }
                    .controlSize(.small)
            }

            TSTVideoInfoSection()
        }
    }
}

struct TSTVideoInfoSection: View {
    @Environment(TSTAppModel.self) private var model

    var body: some View {
        if let info = model.info {
            TSTInspectorSection(title: L("Video", "视频")) {
                Group {
                    LabeledContent(L("Duration", "时长"), value: TSTFormat.seconds(info.duration))
                    LabeledContent(L("Frame rate", "帧率"), value: String(format: "%.2f fps", info.fps))
                    LabeledContent(L("Resolution", "分辨率"), value: "\(info.orientedWidth) × \(info.orientedHeight)")
                    if let l = model.layout {
                        LabeledContent(L("Analysed at", "分析分辨率"), value: "\(l.imageWidth) × \(l.imageHeight)")
                    }
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }
}
