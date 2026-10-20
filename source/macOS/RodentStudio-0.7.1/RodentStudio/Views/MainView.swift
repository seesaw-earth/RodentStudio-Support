import SwiftUI

/// Former top-level sections. They are now areas of the one sidebar (tasks, smart lists, tools); the
/// value is kept so the ⌘1 / ⌘2 / ⌘3 menu commands and the saved position keep working.
enum AppSection: String, CaseIterable, Identifiable {
    case analyse, data, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .analyse: return L("Analyse", "分析")
        case .data: return L("Data", "数据")
        case .advanced: return L("Advanced", "高级")
        }
    }

    var symbol: String {
        switch self {
        case .analyse: return "play.rectangle"
        case .data: return "tablecells"
        case .advanced: return "gearshape.2"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        // One window, one sidebar: tasks, smart lists (the former Data tab) and tools (the former Advanced
        // tab) are all reached from the sidebar of the Analyse view. ⌘1 / ⌘2 / ⌘3 still jump to them.
        AnalysisWorkflowView()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DesktopTextSizeButtons()
                }
                ToolbarItem(placement: .primaryAction) {
                    LanguageMenu()
                }
            }
            .navigationTitle(store.selectedProject?.name ?? AppInfo.name)
            .alert(AppInfo.name, isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button(L("OK", "好")) { store.notice = nil }
            } message: {
                Text(store.notice ?? "")
            }
    }
}
