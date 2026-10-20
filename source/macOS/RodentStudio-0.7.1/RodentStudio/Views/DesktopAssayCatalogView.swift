import SwiftUI

/// Read-only coverage matrix: accurately marks incomplete migrations rather than
/// offering misleading enabled analysis buttons.
struct DesktopAssayCatalogView: View {
    @State private var selectedFamily = "RodentPose"

    private var tasks: [StudyAssay] {
        StudyAssay.allCases.filter { $0.isDesktopEligible && $0.moduleName == selectedFamily }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: L("Task catalog · %d video tasks", "任务目录 · %d 个视频任务"), DesktopAssayCatalog.all.count))
                .font(.largeTitle.bold())
            Text(L("Each application keeps its own model or tracking method and its own calibration. Original iOS source archives are included in OriginalAppSources; unavailable stages are marked.",
                   "每个应用保留自己的模型或追踪方法以及自己的标定方式。原版 iOS 源码在 OriginalAppSources 中；未完成的环节都有标注。"))
                .foregroundStyle(.secondary)
            Picker(L("Application", "应用"), selection: $selectedFamily) {
                ForEach(DesktopAssayCatalog.families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .pickerStyle(.segmented)
            List(tasks) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: item.symbol).frame(width: 20)
                        Text(item.displayName).font(.headline)
                        if item.displayName != item.name {
                            Text(item.name).foregroundStyle(.secondary)
                        }
                    }
                    Text(item.methodCaption).foregroundStyle(.secondary)
                    Text(DesktopAssayCatalog.availabilityText(item)).font(.caption).foregroundStyle(.orange)
                    Text(item.rawValue).font(.caption2).monospaced().foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            Text(L("RodentFlow lists only the 10 video-input assays from its original catalog. Its classic centroid tracker is not yet integrated into this macOS target; no manual-only tasks are offered.",
                   "RodentFlow 只列出其原版目录中的 10 个视频任务。经典质心追踪器尚未集成到 macOS 版本；不提供纯手动录入的任务。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
