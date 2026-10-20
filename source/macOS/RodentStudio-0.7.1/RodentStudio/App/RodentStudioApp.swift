import SwiftUI

@main
struct RodentStudioApp: App {
    @StateObject private var workspace = WorkspaceStore()
    @StateObject private var runSession = NativeRunSession()
    /// Session summaries for the task / group pages (computed once per session, saved with its run).
    @StateObject private var taskData = TaskDataModel()
    @AppStorage(AppLanguage.storageKey) private var lang = AppLanguage.system.rawValue
    @AppStorage("rd.fontScale") private var fontScale = DesktopFontScale.standard.rawValue
    @AppStorage("rd.section") private var sectionRaw = AppSection.analyse.rawValue

    var body: some Scene {
        WindowGroup("RodentStudio") {
            // Rebuilding on a language change makes every L("en", "zh") string switch at once.
            // Workflow position is kept in AppStorage / the workspace, so context survives the switch.
            MainView()
                .id(lang)
                .environment(\.locale, AppLanguage.locale(for: lang))
                .dynamicTypeSize((DesktopFontScale(rawValue:fontScale) ?? .standard).size)
                .environmentObject(workspace)
                .environmentObject(runSession)
                .environmentObject(taskData)
                .frame(minWidth: 1100, minHeight: 680)
        }
        .defaultSize(width: 1420, height: 880)
        .commands {
            CommandGroup(before: .sidebar) {
                Button(L("Tasks", "任务")) { sectionRaw = AppSection.analyse.rawValue }
                    .keyboardShortcut("1", modifiers: .command)
                Button(L("All sessions", "全部实验")) { sectionRaw = AppSection.data.rawValue }
                    .keyboardShortcut("2", modifiers: .command)
                Button(L("Tools", "工具")) { sectionRaw = AppSection.advanced.rawValue }
                    .keyboardShortcut("3", modifiers: .command)
                Divider()
                Button(L("Increase text size", "放大字体")) { fontScale = min(3, fontScale + 1) }.keyboardShortcut("+", modifiers: .command)
                Button(L("Decrease text size", "缩小字体")) { fontScale = max(0, fontScale - 1) }.keyboardShortcut("-", modifiers: .command)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .id(lang)
                .environment(\.locale, AppLanguage.locale(for: lang))
        }
    }
}
