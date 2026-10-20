// AdvancedView.swift — the "Advanced" tab. Everything that is not part of running an experiment lives
// here: model status and smoke test, manual tracking with an explicit model choice, the long-video tool,
// review of manually tracked results, the RodentLimb PoseTrack analyzer, the task catalog and the
// read-only legacy project inspector. The guided workflow never asks the user to pick a model.

import SwiftUI

enum AdvancedTool: String, CaseIterable, Identifiable {
    case models, manualTracking, longTracking, review, limbAnalyzer, catalog, legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: return L("Models", "模型")
        case .manualTracking: return L("Manual tracking", "手动追踪")
        case .longTracking: return L("Long-video tracking", "长视频追踪")
        case .review: return L("Review manual results", "复核手动结果")
        case .limbAnalyzer: return L("RodentLimb track analyzer", "RodentLimb 轨迹分析")
        case .catalog: return L("Task catalog", "任务目录")
        case .legacy: return L("Legacy project inspector", "旧项目查看器")
        }
    }

    var symbol: String {
        switch self {
        case .models: return "cpu"
        case .manualTracking: return "figure.walk.motion"
        case .longTracking: return "film.stack"
        case .review: return "eye"
        case .limbAnalyzer: return "pawprint"
        case .catalog: return "list.bullet.rectangle"
        case .legacy: return "doc.text.magnifyingglass"
        }
    }
}

struct AdvancedView: View {
    @AppStorage("rd.advancedTool") private var toolRaw = AdvancedTool.models.rawValue

    private var tool: AdvancedTool { AdvancedTool(rawValue: toolRaw) ?? .models }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { Optional(tool) }, set: { toolRaw = ($0 ?? .models).rawValue })) {
                Section(L("Advanced", "高级")) {
                    ForEach(AdvancedTool.allCases) { t in
                        Label(t.title, systemImage: t.symbol).tag(t)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            AdvancedToolPage(tool: tool)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The page of one tool. Shown from the "Tools" section of the main sidebar.
struct AdvancedToolPage: View {
    let tool: AdvancedTool

    var body: some View {
        detail
    }

    @ViewBuilder
    private var detail: some View {
        switch tool {
        case .models:
            scrolling { ModelStatusView() }
        case .manualTracking:
            scrolling {
                note(L("For checks and troubleshooting. The model is chosen by hand here; results are not linked to a task or animal. For experiments, use the tasks in the sidebar.",
                       "用于检查和排错。这里手动选择模型，结果不关联任务或动物。做实验请使用侧栏中的任务。"))
                NativeVideoTrackingView()
            }
        case .longTracking:
            scrolling {
                note(L("Segmented tracking into a folder you choose. The guided workflow does this automatically in the app's own folder.",
                       "分段追踪到您选择的文件夹。引导流程会自动在 App 自己的文件夹中完成这一步。"))
                LongVideoTrackingView()
            }
        case .review:
            ReviewExportView()
                .padding(22)
        case .limbAnalyzer:
            scrolling { PoseTrackAnalysisView() }
        case .catalog:
            DesktopAssayCatalogView()
                .padding(22)
        case .legacy:
            LegacyProjectInspector()
                .padding(22)
        }
    }

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tool.title).font(.largeTitle.bold())
                content()
            }
            .padding(22)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// Which model each module uses, whether it is bundled, and a one-frame smoke test.
struct ModelStatusView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("The analysis model is decided by the task, never by the user: RodentPose tasks use the 6-keypoint mouse model, RodentLimb tasks use the 7-keypoint cylinder model, and RodentFlow uses its own classic-centroid tracker (not yet ported).",
                   "分析模型由任务决定，而不是由用户选择：RodentPose 任务使用 6 关键点小鼠模型，RodentLimb 任务使用 7 关键点圆筒模型，RodentFlow 使用自己的经典质心追踪器（尚未移植）。"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(PoseModelKind.allCases) { kind in
                HStack(spacing: 10) {
                    Image(systemName: NativeModelCatalog.available(kind) ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(NativeModelCatalog.available(kind) ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.rawValue).font(.headline).monospaced()
                        Text(kind == .mousePose ? L("Used by: RodentPose tasks", "用于：RodentPose 任务") : L("Used by: RodentLimb tasks", "用于：RodentLimb 任务"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(NativeModelCatalog.available(kind) ? L("Bundled", "已打包") : L("Not installed", "未安装"))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack(spacing: 10) {
                Image(systemName: "circle.dotted.circle").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("RodentFlow classic centroid", "RodentFlow 经典质心")).font(.headline)
                    Text(L("Original iOS code retained; macOS port pending. No pose model is substituted.", "保留原版 iOS 代码；macOS 移植待完成。不会用姿态模型代替。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            ModelInferenceCheckView()
        }
    }
}
