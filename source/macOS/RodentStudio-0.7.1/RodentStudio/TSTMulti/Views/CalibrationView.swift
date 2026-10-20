import SwiftUI
import Charts

/// Enter hand-scored immobility for some chambers; sweep the threshold to best match them.
struct TSTCalibrationView: View {
    @Environment(TSTAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let chambers: Int
    @State private var texts: [String] = []
    @State private var points: [TSTAppModel.CalibrationPoint] = []

    private var best: TSTAppModel.CalibrationPoint? { points.min { $0.mae < $1.mae } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(0..<chambers, id: \.self) { i in
                        HStack {
                            Text(String(format: L("Chamber %d", "第 %d 格"), i + 1))
                            Spacer()
                            TextField(L("not scored", "未评分"), text: binding(i))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 110)
                            Text(L("s", "秒")).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Hand-scored immobility (same time window)", "人工评分的不动时间（相同时间窗）"))
                } footer: {
                    Text(L("Score the video by hand (e.g. with BORIS) and enter the total immobile seconds for the chambers you scored; leave the others empty. Use 2–3 videos with a range of immobility for a robust threshold.",
                           "先人工评分（如使用 BORIS），填写已评分格子的总不动秒数，其余留空。使用 2–3 段不动程度不同的视频，阈值会更稳健。"))
                }

                Section {
                    Button(L("Find the best threshold", "寻找最佳阈值"), systemImage: "scope") {
                        points = model.calibrationSweep(manual: texts.map { Double($0.replacingOccurrences(of: ",", with: ".")) })
                    }
                    .disabled(texts.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    if let b = best {
                        LabeledContent(L("Best threshold", "最佳阈值"), value: String(format: "%.2f %%", b.threshold))
                        LabeledContent(L("Mean absolute error", "平均绝对误差"), value: String(format: L("%.1f s", "%.1f 秒"), b.mae))
                        LabeledContent(L("Pearson r", "Pearson r"), value: b.r.isFinite ? String(format: "%.3f", b.r) : "–")
                        Chart(points) { p in
                            LineMark(x: .value("Threshold (%)", p.threshold), y: .value("MAE (s)", p.mae))
                            if p.id == b.id {
                                PointMark(x: .value("Threshold (%)", p.threshold), y: .value("MAE (s)", p.mae))
                                    .foregroundStyle(.red)
                            }
                        }
                        .chartXAxisLabel(L("Threshold (%)", "阈值（%）"))
                        .chartYAxisLabel(L("Mean abs. error (s)", "平均绝对误差（秒）"))
                        .frame(height: 160)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button(L("Cancel", "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(best.map { String(format: L("Apply %.2f %%", "应用 %.2f %%"), $0.threshold) } ?? L("Apply", "应用")) {
                    if let b = best { model.settings.immobilityThreshold = b.threshold }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(best == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520, idealHeight: 620)
        .onAppear { if texts.count != chambers { texts = Array(repeating: "", count: chambers) } }
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(get: { i < texts.count ? texts[i] : "" },
                set: { if i < texts.count { texts[i] = $0 } })
    }
}
