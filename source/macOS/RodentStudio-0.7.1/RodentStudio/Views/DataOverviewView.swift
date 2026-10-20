// DataOverviewView.swift — the "Data" tab: projects, tasks and every session in one table, so a whole
// cohort can be checked at a glance (who is calibrated, analysed, which group / date / session number).

import SwiftUI

struct DataOverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let onOpen: (UUID) -> Void

    @State private var newProjectName = ""
    @State private var renameText = ""
    @State private var renaming = false
    @State private var selection: Set<UUID> = []
    @State private var taskFilter: UUID?

    private var project: NativeProject? { store.selectedProject }
    private var experiments: [NativeExperiment] { project?.experiments.filter { $0.assay.isDesktopEligible } ?? [] }
    private var rows: [VideoRecord] {
        let all = (project?.videos ?? []).sorted { a, b in
            if a.animalKey != b.animalKey { return a.animalKey.localizedStandardCompare(b.animalKey) == .orderedAscending }
            return VideoRecord.sessionOrder(a, b)
        }
        guard let taskFilter else { return all }
        return all.filter { $0.experimentID == taskFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let project {
                if !experiments.isEmpty { taskSummary(project) }
                if rows.isEmpty {
                    ContentUnavailableView(L("No videos yet", "还没有视频"), systemImage: "film.stack",
                                           description: Text(L("Choose a task in the sidebar, then add videos with +.", "在侧栏选择任务后，点 + 添加视频。")))
                } else {
                    table
                    Text(L("One row per session (one video of one animal). Double-click a row to open it in its task. Removing a video from the project never deletes the file.",
                           "每行是一次实验（一只小鼠的一段视频）。双击某行可在所属任务中打开。从项目中移除视频不会删除文件。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(L("No project yet", "还没有项目"), systemImage: "folder",
                                       description: Text(L("A project is created automatically when you create a task.", "新建任务时会自动创建项目。")))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: store.document.selectedProjectID) { _, _ in taskFilter = nil; selection = [] }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Data", "数据")).font(.largeTitle.bold())
                Text(L("Native workspace. Existing .rodentproj files are never modified.", "原生工作区。已有的 .rodentproj 文件不会被修改。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.document.projects.isEmpty {
                Picker(L("Project", "项目"), selection: Binding(get: { store.document.selectedProjectID },
                                                             set: { if let id = $0 { store.selectProject(id) } })) {
                    ForEach(store.document.projects) { p in Text(p.name).tag(Optional(p.id)) }
                }
                .frame(maxWidth: 280)
                Button(L("Rename…", "重命名…")) {
                    renameText = project?.name ?? ""
                    renaming = true
                }
                .disabled(project == nil)
            }
            TextField(L("New project name", "新项目名称"), text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(createProject)
            Button(L("New project", "新建项目"), action: createProject)
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(L("Rename project", "重命名项目"), isPresented: $renaming) {
            TextField(L("Project name", "项目名称"), text: $renameText)
            Button(L("Rename", "重命名")) { if let id = project?.id { store.renameProject(id, to: renameText) } }
            Button(L("Cancel", "取消"), role: .cancel) {}
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.createProject(name)
        newProjectName = ""
    }

    // MARK: Tasks

    private func taskSummary(_ project: NativeProject) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                summaryChip(title: L("All tasks", "全部任务"), symbol: "tray.full", detail: String(format: L("%d videos", "%d 个视频"), project.videos.count),
                            selected: taskFilter == nil) { taskFilter = nil }
                ForEach(experiments) { exp in
                    let vids = project.videos.filter { $0.experimentID == exp.id }
                    let animals = Set(vids.map(\.animalKey)).count
                    let analysed = vids.filter { $0.runState == .complete }.count
                    summaryChip(title: exp.displayTitle + (exp.hasNotes ? " 📝" : ""), symbol: exp.assay.symbol,
                                detail: String(format: L("%d animals · %d sessions · %d analysed", "%d 只小鼠 · %d 次实验 · 已分析 %d"), animals, vids.count, analysed),
                                selected: taskFilter == exp.id) { taskFilter = exp.id }
                }
            }
        }
    }

    private func summaryChip(title: String, symbol: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Table

    private func assay(of v: VideoRecord) -> StudyAssay? {
        experiments.first { $0.id == v.experimentID }?.assay
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn(L("Animal", "小鼠")) { (v: VideoRecord) in Text(v.displayName) }
            TableColumn(L("Group", "组别")) { (v: VideoRecord) in Text(v.group ?? "") }
            TableColumn(L("Task", "任务")) { (v: VideoRecord) in Text(assay(of: v)?.displayName ?? L("Not assigned", "未分配")) }
            TableColumn(L("Phase", "阶段")) { (v: VideoRecord) in Text(v.phase.map { p in assay(of: v)?.phaseTitle(p) ?? p } ?? "") }
            TableColumn(L("Date", "日期")) { (v: VideoRecord) in
                Text(SessionDate.isValid(v.sessionDate) ? (v.sessionDate ?? "") : L("missing", "缺少"))
                    .foregroundStyle(SessionDate.isValid(v.sessionDate) ? Color.primary : Color.orange)
            }
            TableColumn(L("Session", "实验次数")) { (v: VideoRecord) in
                Text(v.sessionNumber.map { "#\($0)" } ?? L("missing", "缺少"))
                    .monospacedDigit()
                    .foregroundStyle(v.sessionNumber == nil ? Color.orange : Color.primary)
            }
            TableColumn(L("Calibration", "标定")) { (v: VideoRecord) in
                let ok = assay(of: v).map { v.hasSetup(for: $0) } ?? false
                Label(ok ? L("Calibrated", "已标定") : L("Not calibrated", "未标定"), systemImage: ok ? "checkmark.circle" : "circle.dashed")
                    .foregroundStyle(ok ? Color.primary : Color.secondary)
            }
            TableColumn(L("Analysis", "分析")) { (v: VideoRecord) in
                let stage = v.stage(for: assay(of: v))
                Label(stage.title, systemImage: stage.symbol).foregroundStyle(stage.color)
            }
            TableColumn(L("Tracking check", "追踪复核")) { (v: VideoRecord) in
                let verdict = v.reviewVerdict
                Label(verdict.title, systemImage: verdict.symbol)
                    .foregroundStyle(verdict == .passed ? Color.green : (verdict == .issues ? Color.orange : Color.secondary))
            }
            TableColumn(L("File", "文件")) { (v: VideoRecord) in Text(v.fileName).foregroundStyle(.secondary) }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button(L("Open in its task", "在所属任务中打开")) { if let id = ids.first { onOpen(id) } }
                .disabled(ids.count != 1)
            Divider()
            Button(L("Remove from project", "从项目中移除"), role: .destructive) {
                for id in ids { store.removeVideo(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { onOpen(id) }
        }
    }
}
