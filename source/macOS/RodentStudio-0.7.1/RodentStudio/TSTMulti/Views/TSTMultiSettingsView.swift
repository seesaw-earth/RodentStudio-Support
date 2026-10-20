import SwiftUI
import UniformTypeIdentifiers

/// Detector, key-frame and advanced analysis settings (remembered between launches).
struct TSTSettingsView: View {
    @Environment(TSTAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var confirmReset = false

    private static let modelTypes: [UTType] = [
        UTType("com.apple.coreml.model"),
        UTType(filenameExtension: "mlmodel"),
        UTType(filenameExtension: "mlpackage", conformingTo: .package),
        UTType(filenameExtension: "mlmodelc", conformingTo: .package),
        .folder,
    ].compactMap { $0 }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker(L("Detector", "检测器"), selection: $model.stored.detectorMode) {
                        ForEach(TSTDetectorMode.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledContent(L("In use", "当前使用")) {
                        Text(model.activeDetector.name).font(.footnote).textSelection(.enabled)
                    }
                    HStack {
                        Button(L("Import YOLO model (.mlpackage / .mlmodel)…", "导入 YOLO 模型（.mlpackage / .mlmodel）…"),
                               systemImage: "square.and.arrow.down") {
                            showImporter = true
                        }
                        if TSTModelStore.hasImported {
                            Button(L("Remove imported model", "移除已导入的模型"), role: .destructive) { model.removeImportedModel() }
                        }
                    }
                } header: {
                    Text(L("Mouse detector", "小鼠检测器"))
                } footer: {
                    Text(L("The bundled starter model was trained on synthetic images from one rig. For your own rig, fine-tune it with the scripts in the project's yolo/ folder and import the exported Core ML model here.",
                           "内置入门模型由单一装置的合成图像训练。针对自己的装置，请用工程 yolo/ 文件夹中的脚本微调，并在此导入导出的 Core ML 模型。"))
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(L("Minimum confidence", "最低置信度"))
                            Spacer()
                            Text(String(format: "%.2f", model.stored.keyFrame.minConfidence)).monospacedDigit()
                        }
                        Slider(value: $model.stored.keyFrame.minConfidence, in: 0.1...0.9, step: 0.05)
                    }
                    TSTNumberRow(title: L("Mice present for", "小鼠持续出现"), unit: L("s", "秒"),
                                 value: $model.stored.keyFrame.stableSec, range: 0.5...30, step: 0.5)
                    TSTNumberRow(title: L("Bridge gaps up to", "可忽略的漏检"), unit: L("s", "秒"),
                                 value: $model.stored.keyFrame.maxGapSec, range: 0...5, step: 0.25)
                    TSTNumberRow(title: L("Start after key frame", "关键帧后延迟"), unit: L("s", "秒"),
                                 value: $model.stored.keyFrame.settleSec, range: 0...60, step: 1)
                    TSTNumberRow(title: L("Scan rate", "扫描速率"), unit: "fps",
                                 value: $model.stored.scanFPS, range: 1...15, step: 1)
                } header: {
                    Text(L("Key frame", "关键帧"))
                } footer: {
                    Text(L("Key frame = first moment every selected chamber has a mouse (confidence ≥ minimum) continuously for the set time; short detection drop-outs are bridged. “Start after key frame” adds a settling delay, e.g. so the experimenter's hands have left the view.",
                           "关键帧 = 所有选中格子同时有小鼠（置信度 ≥ 最低值）并持续设定时长的第一个时刻；短暂漏检会被忽略。“关键帧后延迟”可额外等待一段时间，例如等实验者的手离开画面。"))
                }

                TSTAdvancedSettingsSection(confirmReset: $confirmReset)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(L("Done", "完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 560, idealHeight: 680)
        .onChange(of: model.stored.detectorMode) { model.reloadDetector() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.modelTypes) { result in
            if case .success(let url) = result { model.importModel(url) }
        }
        .confirmationDialog(L("Reset all TST settings to their defaults?", "将所有 TST 设置恢复为默认值？"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Reset", "恢复默认"), role: .destructive) { model.stored = TSTPersistedSettings() }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }
}

/// Numeric row with a text field and a stepper.
struct TSTNumberRow: View {
    let title: String
    let unit: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                      format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            Text(unit).foregroundStyle(.secondary)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
    }
}

struct TSTAdvancedSettingsSection: View {
    @Environment(TSTAppModel.self) private var model
    @Binding var confirmReset: Bool

    var body: some View {
        @Bindable var model = model
        Section {
            DisclosureGroup(L("Advanced analysis", "高级分析设置")) {
                Picker(L("Mouse colour", "小鼠颜色"), selection: $model.settings.mouseDark) {
                    Text(L("Dark mice / light background", "深色小鼠 / 浅色背景")).tag(true)
                    Text(L("Light mice / dark background", "浅色小鼠 / 深色背景")).tag(false)
                }
                Picker(L("Processing width", "处理宽度"), selection: $model.settings.processingWidth) {
                    ForEach([480, 640, 800, 960], id: \.self) { Text("\($0) px").tag($0) }
                }
                TSTNumberRow(title: L("Analysis rate", "分析帧率"), unit: "fps", value: $model.settings.targetFPS, range: 5...60, step: 5)
                TSTNumberRow(title: L("Smoothing", "平滑"), unit: L("s", "秒"), value: $model.settings.smoothSec, range: 0...3, step: 0.1)
                TSTNumberRow(title: L("Compare over", "比较间隔"), unit: L("s", "秒"), value: $model.settings.compareLagSec, range: 0.05...1, step: 0.05)
                Stepper(String(format: L("Edge tolerance: %d px", "边缘容差：%d px"), model.settings.edgeTolerancePx),
                        value: $model.settings.edgeTolerancePx, in: 0...3)
                Toggle(L("Compensate swing (align frames before comparing)", "补偿摆动（比较前先对齐画面）"), isOn: $model.settings.alignRotation)
                Stepper(String(format: L("Segmentation offset: %d", "分割偏移：%d"), model.settings.otsuOffset),
                        value: $model.settings.otsuOffset, in: -40...40, step: 2)
                Stepper(String(format: L("Pixel-change threshold: %d", "像素变化阈值：%d"), model.settings.diffThreshold),
                        value: $model.settings.diffThreshold, in: 3...60)
                Button(L("Reset all settings…", "恢复全部默认设置…"), role: .destructive) { confirmReset = true }
            }
        } footer: {
            Text(L("Mouse colour and processing width take effect on the next video (or after “Detect again”).",
                   "小鼠颜色和处理宽度在下一段视频（或“重新检测”后）生效。"))
        }
    }
}
