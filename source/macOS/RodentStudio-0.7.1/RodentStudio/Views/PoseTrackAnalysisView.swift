import SwiftUI
import AppKit

/// Model-free scientific-engine smoke path. Loads the original RodentLimb iOS binary plist
/// PoseTrack and computes metrics using the original Swift analyzers, not Python.
struct PoseTrackAnalysisView: View {
    @State private var track: PoseTrack?
    @State private var trackFilename = ""
    @State private var assay: Assay = .tailSuspension
    @State private var result: AnalysisResult?
    @State private var warning: String?
    @State private var rimX = 0.0
    @State private var rimY = 0.0
    @State private var rimRadius = 0.0
    @State private var floorY = 0.0
    @State private var cylinderView: CylinderViewMode = .bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(L("Original RodentLimb Swift analysis (without ML model)", "原版 RodentLimb Swift 分析（不使用模型）")).font(.headline)
            Text(L("Load an existing iOS RodentLimb PoseTrack binary plist. This uses the original analyzers and does not process raw video.", "载入已有的 iOS RodentLimb PoseTrack 二进制 plist。使用原版分析器，不处理原始视频。"))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(L("Open PoseTrack…", "打开 PoseTrack…")) { pickTrack() }
                Text(trackFilename.isEmpty ? L("No track", "无轨迹") : trackFilename).foregroundStyle(.secondary)
            }
            Picker(L("Assay", "范式"), selection: $assay) {
                ForEach(Assay.allCases) { item in Text(item.name.text).tag(item) }
            }
            if assay == .cylinder {
                Picker(L("Camera", "拍摄视角"), selection: $cylinderView) {
                    Text(L("Bottom", "仰视")).tag(CylinderViewMode.bottom)
                    Text(L("Side", "侧视")).tag(CylinderViewMode.side)
                }
                if cylinderView == .bottom {
                    HStack {
                        TextField(L("Rim center X (pixels)", "边缘圆心 X（像素）"), value: $rimX, format: .number)
                        TextField(L("Rim center Y (pixels)", "边缘圆心 Y（像素）"), value: $rimY, format: .number)
                        TextField(L("Rim radius (pixels)", "边缘半径（像素）"), value: $rimRadius, format: .number)
                    }
                } else {
                    TextField(L("Floor Y (pixels)", "地面 Y（像素）"), value: $floorY, format: .number)
                }
            }
            Button(L("Run original Swift analyzer", "运行原版 Swift 分析器")) { run() }
                .disabled(track == nil)
            if let warning { Text(warning).foregroundStyle(.orange).font(.callout) }
            if let result {
                Text(L("Computed metrics — NOT independently validated", "计算出的指标——未经独立验证")).font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(result.metrics) { metric in
                            HStack {
                                Text(metric.label.text)
                                Spacer()
                                Text(metric.formatted + (metric.unit.isEmpty ? "" : " " + metric.unit))
                                    .monospacedDigit()
                            }
                        }
                    }
                }.frame(maxHeight: 250)
                Button(L("Export result JSON…", "导出结果 JSON…")) { export(result) }
                Text(L("This test does not establish macOS / iOS video preprocessing parity or validity against manual scoring.", "此测试不能证明 macOS / iOS 视频预处理一致，也不能证明与人工评分一致。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pickTrack() {
        let panel = NSOpenPanel()
        panel.message = L("Select a RodentLimb PoseTrack binary plist (.mpt2 / .plist)", "选择 RodentLimb PoseTrack 二进制 plist（.mpt2 / .plist）")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            track = try PropertyListDecoder().decode(PoseTrack.self, from: bytes)
            trackFilename = url.lastPathComponent
            result = nil
            warning = nil
        } catch {
            warning = L("Cannot decode track: ", "无法解码轨迹：") + error.localizedDescription
        }
    }

    private func run() {
        guard let track else { return }
        // Defensive validation because the legacy algorithms index seven keypoint arrays by frame.
        let n = track.frameCount
        guard n > 1, track.x.count == 7, track.y.count == 7, track.c.count == 7,
              track.boxConfidence.count == n,
              track.x.allSatisfy({ $0.count == n }),
              track.y.allSatisfy({ $0.count == n }),
              track.c.allSatisfy({ $0.count == n }),
              track.times.allSatisfy({ $0.isFinite }) else {
            warning = L("Invalid 7-keypoint PoseTrack shape; analysis was not run.", "PoseTrack 不是有效的 7 关键点格式，未运行分析。")
            return
        }
        var params = AssayParams.defaults(for: assay)
        params.cylinder.view = cylinderView
        let circle: CircleCal? = cylinderView == .bottom && rimRadius > 0
            ? CircleCal(cx: rimX, cy: rimY, r: rimRadius) : nil
        let floor: Double? = cylinderView == .side ? floorY : nil
        let cal = Calibration(circle: circle, floorY: floor, scale: nil, copiedFrom: nil)
        result = NativeLimbAdapter.run(track: track, assay: assay,
                                       params: params, calibration: cal)
        warning = result?.notes.contains(where: { $0.level == .error }) == true
            ? L("Analyzer reported a calibration or input error; inspect the notes before using results.", "分析器报告了标定或输入错误；使用结果前请查看说明。") : nil
    }

    private func export(_ report: AnalysisResult) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "rodentlimb_native_result.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            warning = L("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }
}
