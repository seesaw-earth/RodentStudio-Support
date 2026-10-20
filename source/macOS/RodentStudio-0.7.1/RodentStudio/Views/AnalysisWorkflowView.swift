// AnalysisWorkflowView.swift — the Analyse section.
//
// The sidebar is the data itself: Task → Group (only when groups are used) → Animal → Session
// (recording date · session number). Selecting a task, group or animal opens its overview (summaries,
// group comparison, exports); selecting a session opens the guided steps of the original apps:
// Session info → Calibrate (the task's own calibration) → Analyse (method chosen by the task) →
// Review & export. Every video is one session of one animal, so animal, date and session number are
// required when videos are added. Steps can be revisited at any time; nothing irreversible happens
// without a prompt.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum WorkflowStep: Int, CaseIterable, Identifiable {
    case video = 1, calibrate, run, review

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .video: return L("Session info", "实验信息")
        case .calibrate: return L("Calibrate", "校准")
        case .run: return L("Analyse", "分析")
        case .review: return L("Review & export", "复核与导出")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "info.circle"
        case .calibrate: return "viewfinder"
        case .run: return "play.circle"
        case .review: return "checkmark.seal"
        }
    }
}

enum VideoStage {
    case needsSetup, ready, running, paused, failed, analysed

    var title: String {
        switch self {
        case .needsSetup: return L("Needs calibration", "需要标定")
        case .ready: return L("Ready to analyse", "可以分析")
        case .running: return L("Analysing…", "正在分析…")
        case .paused: return L("Paused — can resume", "已暂停，可继续")
        case .failed: return L("Analysis failed", "分析失败")
        case .analysed: return L("Analysed", "已分析")
        }
    }

    var symbol: String {
        switch self {
        case .needsSetup: return "viewfinder"
        case .ready: return "circle"
        case .running: return "hourglass"
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .analysed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .needsSetup: return .secondary
        case .ready: return .accentColor
        case .running: return .accentColor
        case .paused: return .orange
        case .failed: return .red
        case .analysed: return .green
        }
    }
}

extension VideoRecord {
    func stage(for assay: StudyAssay?) -> VideoStage {
        switch runState {
        case .running?: return .running
        case .complete?: return .analysed
        case .partial?: return .paused
        case .failed?: return .failed
        case nil: break
        }
        if let assay, let c = calibration, c.matches(assay) { return .ready }
        return .needsSetup
    }

    func hasSetup(for assay: StudyAssay) -> Bool { calibration?.matches(assay) ?? false }
}

/// Session information edited in the Session info step (saved shortly after typing stops).
struct VideoInfoDraft: Equatable {
    var animalID = ""
    var group = ""
    var sex = ""
    var sessionDate: Date?
    var sessionNumber: Int?
    var phase = ""
    var day: Int?
    var trial: Int?
    var notes = ""
    var excluded = false
    var exclusionReason = ""

    init() {}

    init(_ v: VideoRecord, defaultPhase: String) {
        animalID = v.animalID
        group = v.group ?? ""
        sex = v.sex ?? ""
        sessionDate = SessionDate.date(v.sessionDate)
        sessionNumber = v.sessionNumber
        let stored = (v.phase ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        phase = stored.isEmpty ? defaultPhase : stored
        day = v.day
        trial = v.trial
        notes = v.notes ?? ""
        excluded = v.isExcluded
        exclusionReason = v.exclusionReason ?? ""
    }
}

/// A node of the sidebar tree.
enum SidebarItem: Hashable {
    case task(UUID)
    case group(UUID, String)
    case animal(UUID, String)
    case session(UUID)
    case unassigned(UUID)

    var taskID: UUID? {
        switch self {
        case .task(let t), .group(let t, _), .animal(let t, _): return t
        case .session, .unassigned: return nil
        }
    }
}

/// Cross-task lists in the sidebar (they replace the former Data tab's filters).
enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case all, toAnalyse, toReview, missingInfo, excluded, unassigned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("All sessions", "全部实验")
        case .toAnalyse: return L("To analyse", "待分析")
        case .toReview: return L("To review", "待复核")
        case .missingInfo: return L("Missing info", "缺信息")
        case .excluded: return L("Excluded", "已排除")
        case .unassigned: return L("Not in a task", "未分配任务")
        }
    }

    var symbol: String {
        switch self {
        case .all: return "tablecells"
        case .toAnalyse: return "play.circle"
        case .toReview: return "checkmark.seal"
        case .missingInfo: return "exclamationmark.circle"
        case .excluded: return "minus.circle"
        case .unassigned: return "tray"
        }
    }

    /// What the list shows when nothing in it is selected.
    var explanation: String {
        switch self {
        case .all: return ""
        case .toAnalyse: return L("Sessions of every task that have not been analysed yet.", "所有任务中尚未分析的实验。")
        case .toReview: return L("Analysed sessions whose tracking or scoring has not been checked yet.", "已分析、但追踪或评分尚未复核的实验。")
        case .missingInfo: return L("Sessions without animal ID, date or session number. They are left out of summaries until completed.", "缺少小鼠编号、日期或实验次数的实验，补全前不进入汇总。")
        case .excluded: return L("Sessions left out of group summaries, with the reason.", "已排除出组间汇总的实验（附原因）。")
        case .unassigned: return L("Videos imported by earlier versions without a task.", "早期版本导入、没有任务的视频。")
        }
    }

    func matches(_ v: VideoRecord) -> Bool {
        switch self {
        case .all: return true
        case .toAnalyse: return v.experimentID != nil && v.runState != .complete
        case .toReview: return v.experimentID != nil && v.runState == .complete && v.reviewVerdict == .unreviewed
        case .missingInfo: return v.experimentID != nil && !v.hasSessionInfo
        case .excluded: return v.experimentID != nil && v.isExcluded
        case .unassigned: return v.experimentID == nil
        }
    }
}

/// What the sidebar points at. The middle list shows its animals / sessions; the page shows the selection.
enum SidebarDestination: Hashable {
    case task(UUID)
    case group(UUID, String)
    case smart(SmartList)
    case tool(AdvancedTool)

    /// The former top-level section it belongs to (kept for the ⌘1 / ⌘2 / ⌘3 menu commands).
    var section: AppSection {
        switch self {
        case .task, .group: return .analyse
        case .smart(let s): return s == .all ? .data : .analyse
        case .tool: return .advanced
        }
    }
}

/// One node of the sidebar's task outline (a task, or a group inside it).
struct SidebarTaskNode: Identifiable {
    let id: SidebarDestination
    let title: String
    let symbol: String
    let count: Int
    let note: String?
    var children: [SidebarTaskNode]?
}

/// A multi-chamber TST recording to analyse (chosen in the open panel or dropped on the sidebar).
struct TSTImportRequest: Identifiable {
    let id = UUID()
    let experimentID: UUID
    var url: URL?
    var presetGroup: String?
    /// A saved recording opened again from one of its sessions (new settings / new analysis).
    var replacing: TSTStoredRecording? = nil
}

/// Videos waiting for their session information before they are imported.
struct ImportRequest: Identifiable {
    let id = UUID()
    let experimentID: UUID
    let urls: [URL]
    var presetAnimal: String?
    var presetGroup: String?
}

struct AnalysisWorkflowView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var run: NativeRunSession
    @EnvironmentObject private var taskData: TaskDataModel
    @AppStorage("rd.workflowStep") private var stepRaw = WorkflowStep.video.rawValue

    @AppStorage("rd.section") private var sectionRaw = AppSection.analyse.rawValue
    @AppStorage("rd.advancedTool") private var toolRaw = AdvancedTool.models.rawValue

    /// Sidebar choice (task, group, smart list or tool) — decides the middle list.
    @State private var destination: SidebarDestination?
    /// The item whose page is shown (task / group overview, animal, session).
    @State private var selection: SidebarItem?
    @State private var collapsed: Set<String> = []
    @State private var contentQuery = ""
    @AppStorage("rd.listWidth") private var listWidth = 280.0
    @State private var listDragStart: Double?

    @State private var info = VideoInfoDraft()
    @State private var infoVideoID: UUID?
    @State private var infoExperimentID: UUID?
    @State private var infoSaveTask: Task<Void, Never>?

    @State private var setupDraft: DesktopCalibration?
    @State private var setupVideoID: UUID?
    /// Task the setup draft belongs to; a draft is never saved into another task.
    @State private var setupExperimentID: UUID?
    @State private var setupUntouched: DesktopCalibration?
    @State private var setupSaveTask: Task<Void, Never>?

    @State private var confirmRemove: UUID?
    @State private var confirmDeleteTask: UUID?
    @State private var taskNoteTarget: TaskNoteTarget?
    @State private var taskNoteDraft = ""
    @State private var dropTargeted = false
    @State private var importRequest: ImportRequest?
    @State private var tstImport: TSTImportRequest?
    @State private var showTaskPicker = false
    @State private var excludeTarget: UUID?
    @State private var excludeReason = ""

    private struct TaskNoteTarget: Identifiable {
        let id = UUID()
        let taskID: UUID
        let createsSeparateTask: Bool
    }

    private var step: WorkflowStep { WorkflowStep(rawValue: stepRaw) ?? .video }
    private var project: NativeProject? { store.selectedProject }
    private var tasks: [NativeExperiment] { project?.experiments.filter { $0.assay.isDesktopEligible } ?? [] }

    /// The selected session (or unassigned video).
    private var video: VideoRecord? {
        switch selection {
        case .session(let id)?, .unassigned(let id)?: return store.video(id)
        default: return nil
        }
    }

    /// The task of the selection.
    private var experiment: NativeExperiment? {
        if let t = selection?.taskID { return store.experiment(t) }
        if let v = video, let e = v.experimentID { return store.experiment(e) }
        return nil
    }

    private var assay: StudyAssay? { experiment?.assay }

    private var taskVideos: [VideoRecord] {
        guard let id = experiment?.id, let project else { return [] }
        return project.orderedSessions(ofTask: id)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { restoreSelection(); restoreDestination(); syncDrafts() }
        .onDisappear { flushDrafts(confirmSetup: false) }
        .onChange(of: store.focusedVideoID) { _, id in followFocus(id) }
        .onChange(of: store.document.selectedProjectID) { _, _ in
            selection = nil
            destination = nil
            restoreSelection()
            restoreDestination()
            syncDrafts()
        }
        .onChange(of: selection) { _, _ in
            syncDrafts()
            syncDestination()
        }
        .onChange(of: sectionRaw) { _, raw in followSectionCommand(raw) }
        .onChange(of: info) { _, _ in scheduleInfoSave() }
        // Exclusion can also change outside the Session info step (context menu, TST review). Follow it in the
        // draft unless the draft itself was edited, so a later flush does not write the old value back.
        .onChange(of: video?.isExcluded) { old, new in followExcluded(old, new) }
        .onChange(of: video?.exclusionReason) { old, new in followExclusionReason(old, new) }
        .onChange(of: setupDraft) { _, _ in scheduleSetupSave() }
        .sheet(item: $importRequest) { request in
            if let exp = store.experiment(request.experimentID) {
                ImportVideosSheet(experiment: exp, urls: request.urls, presetAnimal: request.presetAnimal,
                                  presetGroup: request.presetGroup) { ids in imported(ids) }
                    .environmentObject(store)
            }
        }
        .sheet(item: $tstImport) { request in
            if let exp = store.experiment(request.experimentID) {
                TSTRecordingAnalysisSheet(experiment: exp, initialURL: request.url, presetGroup: request.presetGroup,
                                          replacing: request.replacing) { ids in
                    tstImport = nil
                    // After a re-analysis stay on the session it was started from (when it is still saved).
                    var current: UUID?
                    if case .session(let id)? = selection, ids.contains(id) { current = id }
                    if let first = current ?? ids.first, let v = store.video(first) {
                        expandAncestors(of: v)
                        select(.session(first))
                        stepRaw = WorkflowStep.review.rawValue
                        taskData.prepare(task: exp.id, store: store)
                    }
                }.environmentObject(store)
            }
        }
        .sheet(isPresented: $showTaskPicker) { newTaskSheet }
        .sheet(item: $taskNoteTarget) { target in taskNoteSheet(target) }
        .confirmationDialog(L("Delete this task and all its imported sessions from the project? Source videos and saved tracking folders will be kept.",
                              "从项目中删除此任务及其全部实验记录？原始视频及已有的追踪结果文件仍会保留。"),
                            isPresented: Binding(get: { confirmDeleteTask != nil },
                                                 set: { if !$0 { confirmDeleteTask = nil } }),
                            titleVisibility: .visible) {
            Button(L("Delete task", "删除任务"), role: .destructive) {
                if let id = confirmDeleteTask { deleteTask(id) }
                confirmDeleteTask = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { confirmDeleteTask = nil }
        } message: {
            if let id = confirmDeleteTask {
                let n = project?.sessions(ofTask: id).count ?? 0
                Text(String(format: L("%d session records will be removed from the workspace. This cannot be undone in the app.",
                                      "将从工作区移除 %d 条实验记录。此操作无法在应用内撤销。"), n))
            }
        }
        .confirmationDialog(L("Remove this video from the project? The video file is not deleted.", "从项目中移除该视频？视频文件本身不会被删除。"),
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible) {
            Button(L("Remove", "移除"), role: .destructive) {
                if let id = confirmRemove {
                    if selection == .session(id) || selection == .unassigned(id) { selection = experiment.map { .task($0.id) } }
                    store.removeVideo(id)
                }
                confirmRemove = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { confirmRemove = nil }
        }
        .alert(L("Exclude this session from group summaries?", "将该次实验排除出组间汇总？"),
               isPresented: Binding(get: { excludeTarget != nil }, set: { if !$0 { excludeTarget = nil } })) {
            TextField(L("Reason (exported)", "原因（会导出）"), text: $excludeReason)
            Button(L("Exclude", "排除")) {
                if let id = excludeTarget { store.setExcluded(id, excluded: true, reason: excludeReason) }
                excludeTarget = nil
            }
            Button(L("Cancel", "取消"), role: .cancel) { excludeTarget = nil }
        } message: {
            Text(L("Its own results are kept; it is left out of the animal means, group statistics and comparisons.",
                   "它自己的结果仍保留；只是不进入小鼠均值、组统计和组间比较。"))
        }
    }

    // MARK: Rows of the middle list

    private struct SidebarRow: Identifiable {
        let id: String
        let item: SidebarItem?
        let depth: Int
        /// Expandable node id (nil for leaves).
        let node: String?
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
    }

    // MARK: Sidebar (two levels at most: task → group; smart lists; tools)

    private var sidebar: some View {
        List(selection: Binding(get: { destination }, set: { navigate(to: $0) })) {
            Section(L("Tasks", "任务")) {
                if tasks.isEmpty {
                    Text(L("No task yet. Use “New task” to start.", "还没有任务。点“新建任务”开始。"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                OutlineGroup(taskNodes, children: \.children) { node in
                    sidebarLabel(node)
                        .tag(node.id)
                        .contextMenu { sidebarContextMenu(node.id) }
                }
            }
            Section(L("Smart lists", "智能列表")) {
                ForEach(visibleSmartLists) { list in
                    Label(list.title, systemImage: list.symbol)
                        .badge(smartCount(list))
                        .tag(SidebarDestination.smart(list))
                }
            }
            Section(L("Tools", "工具")) {
                ForEach(AdvancedTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol)
                        .tag(SidebarDestination.tool(tool))
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showTaskPicker = true
                } label: {
                    Label(L("New task…", "新建任务…"), systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help(L("Add a behavioural task to this project ⇧⌘N", "向该项目添加一个行为学任务 ⇧⌘N"))
                Button {
                    chooseVideos()
                } label: {
                    Label(assay == .tstMultiChamber ? L("Add TST recording…", "添加 TST 录像…") : L("Add videos…", "添加视频…"),
                          systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(importContext == nil)
                .help(assay == .tstMultiChamber
                      ? L("Add multi-chamber TST recording ⌘O", "添加多格 TST 录像 ⌘O")
                      : L("Add videos of the selected task; each video is one session of one animal ⌘O",
                          "为所选任务添加视频；每段视频是一只小鼠的一次实验 ⌘O"))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importDropped(urls)
        } isTargeted: { dropTargeted = $0 }
    }

    private func sidebarLabel(_ node: SidebarTaskNode) -> some View {
        Label {
            Text(node.title).lineLimit(1)
        } icon: {
            Image(systemName: node.symbol)
        }
        .badge(node.count)
        .help(node.note ?? node.title)
    }

    @ViewBuilder
    private func sidebarContextMenu(_ destination: SidebarDestination) -> some View {
        switch destination {
        case .task(let id): contextMenu(.task(id))
        case .group(let id, let g): contextMenu(.group(id, g))
        default: EmptyView()
        }
    }

    /// Tasks, with their groups as the second (and last) level when groups are used.
    private var taskNodes: [SidebarTaskNode] {
        guard let project else { return [] }
        return tasks.map { (exp: NativeExperiment) -> SidebarTaskNode in
            let sessions = project.sessions(ofTask: exp.id)
            var node = SidebarTaskNode(id: .task(exp.id), title: exp.displayTitle, symbol: exp.assay.symbol,
                                       count: sessions.count, note: exp.hasNotes ? exp.notes : nil, children: nil)
            if usesGroups(exp.id) {
                node.children = project.groups(ofTask: exp.id).map { (g: String) -> SidebarTaskNode in
                    SidebarTaskNode(id: .group(exp.id, g), title: g.isEmpty ? L("Ungrouped", "未分组") : g,
                                    symbol: "folder", count: sessions.filter { $0.groupKey == g }.count,
                                    note: nil, children: nil)
                }
            }
            return node
        }
    }

    /// Smart lists of the current project; "Not in a task" only when there is something in it.
    private var visibleSmartLists: [SmartList] {
        SmartList.allCases.filter { $0 != .unassigned || !unassignedVideos.isEmpty }
    }

    private func smartCount(_ list: SmartList) -> Int {
        (project?.videos ?? []).filter { v in
            list.matches(v) && (v.experimentID == nil || tasks.contains { $0.id == v.experimentID })
        }.count
    }

    private var unassignedVideos: [VideoRecord] { project?.videos.filter { $0.experimentID == nil } ?? [] }

    // MARK: Main area: middle list + page

    @ViewBuilder
    private var mainArea: some View {
        switch destination {
        case .tool(let tool)?:
            AdvancedToolPage(tool: tool)
        case .smart(.all)?:
            DataOverviewView(onOpen: { openFromData($0) })
        case nil:
            detail
        default:
            // Plain SwiftUI (not HSplitView): it respects the floating sidebar and the toolbar, so nothing
            // is drawn under them. The list width is dragged at the divider and remembered.
            HStack(spacing: 0) {
                contentList
                    .frame(width: CGFloat(listWidth))
                    .frame(maxHeight: .infinity)
                listResizeHandle
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
        }
    }

    private var listResizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let start = listDragStart ?? listWidth
                                if listDragStart == nil { listDragStart = listWidth }
                                listWidth = min(460, max(200, start + Double(value.translation.width)))
                            }
                            .onEnded { _ in listDragStart = nil }
                    )
            }
    }

    /// The page. In a smart list nothing is shown until a session is picked from the middle list.
    @ViewBuilder
    private var detailPane: some View {
        if case .smart(let list)? = destination, !selectionIsListItem {
            ContentUnavailableView(list.title, systemImage: list.symbol,
                                   description: Text(list.explanation + "\n" + L("Pick a session in the list.", "在列表中选择一次实验。")))
        } else {
            detail
        }
    }

    private var selectionIsListItem: Bool {
        switch selection {
        case .animal?, .session?, .unassigned?: return true
        default: return false
        }
    }

    // MARK: Middle list (animals and their sessions, or the sessions of a smart list)

    private struct ContentSection: Identifiable {
        let id: String
        let title: String
        let rows: [SidebarRow]
    }

    private var contentTitle: String {
        switch destination {
        case .task(let id)?: return store.experiment(id)?.displayTitle ?? ""
        case .group(let id, let g)?:
            return (store.experiment(id)?.displayTitle ?? "") + " › " + (g.isEmpty ? L("Ungrouped", "未分组") : g)
        case .smart(let list)?: return list.title
        default: return ""
        }
    }

    private var contentList: some View {
        let sections = contentSections
        let sessionCount: Int = sections.reduce(0) { total, section in total + section.rows.filter(isSessionRow).count }
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(contentTitle).font(.headline).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(String(format: L("%d sessions", "%d 次实验"), sessionCount))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Search animal, group or date", "搜索小鼠、分组或日期"), text: $contentQuery)
                        .textFieldStyle(.plain)
                    if !contentQuery.isEmpty {
                        Button {
                            contentQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(L("Clear search", "清除搜索"))
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(10)
            Divider()
            if sections.isEmpty {
                ContentUnavailableView(contentQuery.isEmpty ? L("Nothing here yet", "这里还没有内容") : L("No match", "没有匹配项"),
                                       systemImage: contentQuery.isEmpty ? "tray" : "magnifyingglass",
                                       description: Text(contentQuery.isEmpty
                                                         ? L("Add videos with + (or drag them here).", "点 + 添加视频（或拖到这里）。")
                                                         : L("Try another animal ID, group or date.", "换一个小鼠编号、分组或日期试试。")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { selectionIsListItem ? selection : nil }, set: { pickFromList($0) })) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                if let item = row.item {
                                    rowView(row)
                                        .tag(item)
                                        .contextMenu { contextMenu(item) }
                                }
                            }
                        } header: {
                            if !section.title.isEmpty { Text(section.title) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            importDropped(urls)
        } isTargeted: { dropTargeted = $0 }
    }

    private var contentSections: [ContentSection] {
        guard let project, let destination else { return [] }
        let query = contentQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch destination {
        case .task(let id):
            guard let exp = store.experiment(id) else { return [] }
            if usesGroups(id) {
                return project.groups(ofTask: id).compactMap { g -> ContentSection? in
                    var rows: [SidebarRow] = []
                    appendAnimals(&rows, project: project, task: exp, group: g, depth: 0, query: query)
                    return rows.isEmpty ? nil : ContentSection(id: "g:" + g, title: g.isEmpty ? L("Ungrouped", "未分组") : g, rows: rows)
                }
            }
            var rows: [SidebarRow] = []
            appendAnimals(&rows, project: project, task: exp, group: nil, depth: 0, query: query)
            return rows.isEmpty ? [] : [ContentSection(id: "all", title: "", rows: rows)]
        case .group(let id, let g):
            guard let exp = store.experiment(id) else { return [] }
            var rows: [SidebarRow] = []
            appendAnimals(&rows, project: project, task: exp, group: g, depth: 0, query: query)
            return rows.isEmpty ? [] : [ContentSection(id: "g:" + g, title: "", rows: rows)]
        case .smart(let list):
            if list == .unassigned {
                let rows = unassignedVideos
                    .filter { query.isEmpty || $0.fileName.lowercased().contains(query) }
                    .map { v in
                        SidebarRow(id: "u:" + v.id.uuidString, item: .unassigned(v.id), depth: 0, node: nil,
                                   title: v.fileName, subtitle: "", symbol: "film", tint: .secondary)
                    }
                return rows.isEmpty ? [] : [ContentSection(id: "unassigned", title: "", rows: rows)]
            }
            return tasks.compactMap { exp -> ContentSection? in
                let rows = project.orderedSessions(ofTask: exp.id)
                    .filter { list.matches($0) && matchesQuery($0, query) }
                    .map { sessionRow($0, task: exp, depth: 0, showAnimal: true) }
                return rows.isEmpty ? nil : ContentSection(id: exp.id.uuidString, title: exp.displayTitle, rows: rows)
            }
        case .tool:
            return []
        }
    }

    private func isSessionRow(_ row: SidebarRow) -> Bool {
        switch row.item {
        case .session?, .unassigned?: return true
        default: return false
        }
    }

    private func matchesQuery(_ v: VideoRecord, _ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return v.animalKey.lowercased().contains(query) || v.groupKey.lowercased().contains(query)
            || v.sessionTitle.lowercased().contains(query) || v.fileName.lowercased().contains(query)
    }

    /// Animal rows (with their sessions unless collapsed) of a task, optionally of one group.
    private func appendAnimals(_ rows: inout [SidebarRow], project: NativeProject, task exp: NativeExperiment,
                               group: String?, depth: Int, query: String = "") {
        let all = project.sessions(ofTask: exp.id)
        for key in project.animals(ofTask: exp.id, group: group) {
            let sessions = all.filter { $0.animalKey == key && (group == nil || $0.groupKey == group) }.sorted(by: VideoRecord.sessionOrder)
            if !query.isEmpty && !sessions.contains(where: { matchesQuery($0, query) }) { continue }
            let animalNode = "a:" + exp.id.uuidString + ":" + (group ?? "*") + ":" + key
            let sex = sessions.first?.sex ?? ""
            var subtitle = String(format: L("%d sessions", "%d 次实验"), sessions.count)
            if !sex.isEmpty { subtitle += " · " + (sex == "M" ? L("male", "雄") : (sex == "F" ? L("female", "雌") : sex)) }
            if group == nil, let g = sessions.first?.groupKey, !g.isEmpty { subtitle += " · " + g }
            let title = sessions.first?.animalID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rows.append(SidebarRow(id: animalNode, item: .animal(exp.id, key), depth: depth, node: animalNode,
                                   title: title.isEmpty ? L("No animal ID", "无小鼠编号") : title,
                                   subtitle: subtitle, symbol: "pawprint", tint: .secondary))
            guard !collapsed.contains(animalNode) else { continue }
            for v in sessions {
                rows.append(sessionRow(v, task: exp, depth: depth + 1, showAnimal: false))
            }
        }
    }

    private func sessionRow(_ v: VideoRecord, task exp: NativeExperiment, depth: Int, showAnimal: Bool) -> SidebarRow {
        let stage = v.stage(for: exp.assay)
        var parts: [String] = []
        let phase = v.effectivePhase(for: exp.assay)
        if !phase.isEmpty && !exp.assay.phaseOptions.isEmpty { parts.append(exp.assay.phaseTitle(phase)) }
        parts.append(run.isQueued(v.id) ? L("Queued", "排队中") : stage.title)
        if v.isExcluded { parts.append(L("excluded", "已排除")) }
        return SidebarRow(id: "s:" + v.id.uuidString, item: .session(v.id), depth: depth, node: nil,
                          title: showAnimal ? v.displayName + " · " + v.sessionTitle : v.sessionTitle,
                          subtitle: parts.joined(separator: " · "),
                          symbol: v.hasSessionInfo ? stage.symbol : "exclamationmark.circle",
                          tint: v.hasSessionInfo ? stage.color : .orange)
    }

    // MARK: Navigation between sidebar, list and page

    /// Sidebar click.
    private func navigate(to target: SidebarDestination?) {
        guard let target, target != destination else { return }
        flushDrafts(confirmSetup: false)
        contentQuery = ""
        destination = target
        if sectionRaw != target.section.rawValue { sectionRaw = target.section.rawValue }
        switch target {
        case .task(let id):
            select(.task(id))
        case .group(let id, let g):
            select(.group(id, g))
        case .smart(let list):
            // Keep the open session when it belongs to the list; otherwise start with an empty page.
            var keep = false
            switch selection {
            case .session(let vid)?: keep = store.video(vid).map { list.matches($0) } ?? false
            case .unassigned?: keep = list == .unassigned
            default: keep = false
            }
            if !keep { selection = nil }
        case .tool(let tool):
            toolRaw = tool.rawValue
        }
    }

    /// Middle-list click. Deselecting shows the overview of the task / group again.
    private func pickFromList(_ item: SidebarItem?) {
        if let item {
            select(item)
            return
        }
        switch destination {
        case .task(let id)?: select(.task(id))
        case .group(let id, let g)?: select(.group(id, g))
        default: selection = nil
        }
    }

    /// Whether the middle list of the current destination contains this session.
    private func destinationContains(_ v: VideoRecord) -> Bool {
        switch destination {
        case .task(let t)?: return v.experimentID == t
        case .group(let t, let g)?: return v.experimentID == t && v.groupKey == g
        case .smart(let list)?: return list.matches(v)
        default: return false
        }
    }

    /// The page moved (breadcrumb, "Next session", import, Data table): move the sidebar with it when the
    /// middle list would not show the new item.
    private func syncDestination() {
        switch selection {
        case .task(let id)?:
            if destination != .task(id) { destination = .task(id) }
        case .group(let id, let g)?:
            if destination != .group(id, g) { destination = .group(id, g) }
        case .animal(let id, let key)?:
            switch destination {
            case .task(let t)? where t == id: break
            case .group(let t, let g)? where t == id && (project?.animalAttributes(task: id, animal: key)?.group ?? "") == g: break
            default: destination = .task(id)
            }
        case .session(let vid)?:
            if let v = store.video(vid), !destinationContains(v), let t = v.experimentID { destination = .task(t) }
        case .unassigned?:
            if destination != .smart(.unassigned) { destination = .smart(.unassigned) }
        case nil:
            break
        }
        if let d = destination, sectionRaw != d.section.rawValue { sectionRaw = d.section.rawValue }
    }

    /// Sidebar position after launch or a project switch (the selection is restored first).
    private func restoreDestination() {
        if destination != nil { return }
        switch AppSection(rawValue: sectionRaw) {
        case .data?:
            destination = .smart(.all)
        case .advanced?:
            destination = .tool(AdvancedTool(rawValue: toolRaw) ?? .models)
        default:
            syncDestination()
            if destination == nil, let first = tasks.first {
                destination = .task(first.id)
                if selection == nil { selection = .task(first.id) }
            }
        }
    }

    /// ⌘1 / ⌘2 / ⌘3 (View menu): tasks, all sessions, tools.
    private func followSectionCommand(_ raw: String) {
        guard let section = AppSection(rawValue: raw), destination?.section != section else { return }
        switch section {
        case .analyse:
            if let id = experiment?.id ?? store.focusedExperimentID ?? tasks.first?.id { navigate(to: .task(id)) }
        case .data:
            navigate(to: .smart(.all))
        case .advanced:
            navigate(to: .tool(AdvancedTool(rawValue: toolRaw) ?? .models))
        }
    }

    /// Double-click in the All sessions table: open that session in its task.
    private func openFromData(_ id: UUID) {
        guard let v = store.video(id) else { return }
        flushDrafts(confirmSetup: false)
        if let t = v.experimentID {
            destination = .task(t)
            expandAncestors(of: v)
            select(.session(id))
            stepRaw = (v.runState == .complete && v.hasSessionInfo ? WorkflowStep.review : WorkflowStep.video).rawValue
        } else {
            destination = .smart(.unassigned)
            select(.unassigned(id))
        }
        if let d = destination, sectionRaw != d.section.rawValue { sectionRaw = d.section.rawValue }
    }

    private func rowView(_ row: SidebarRow) -> some View {
        HStack(spacing: 6) {
            if let node = row.node {
                Button {
                    if collapsed.contains(node) { collapsed.remove(node) } else { collapsed.insert(node) }
                } label: {
                    Image(systemName: collapsed.contains(node) ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed.contains(node) ? L("Expand", "展开") : L("Collapse", "收起"))
            } else {
                Color.clear.frame(width: 12, height: 1)
            }
            Image(systemName: row.symbol).foregroundStyle(row.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(row.depth == 0 ? .headline : .body)
                    .lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing(row)
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(_ row: SidebarRow) -> some View {
        switch row.item {
        case .session(let id)?:
            if let job = run.job, job.videoID == id {
                ProgressView(value: job.fraction).frame(width: 36).controlSize(.small)
            } else if let position = run.queuePosition(id) {
                Label("\(position)", systemImage: "hourglass")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2).foregroundStyle(.secondary)
                    .help(L("Waiting in the analysis queue", "在分析队列中等待"))
            } else if let v = store.video(id), v.runState == .complete, v.reviewVerdict != .unreviewed {
                Image(systemName: v.reviewVerdict.symbol)
                    .foregroundStyle(v.reviewVerdict == .passed ? Color.green : Color.orange)
                    .help(v.reviewVerdict.title)
            }
        case .task(let id)?:
            if let exp = store.experiment(id), exp.hasNotes {
                Image(systemName: "note.text").foregroundStyle(.secondary)
                    .help(exp.notes ?? "")
            }
            if let computing = taskData.computingID, store.video(computing)?.experimentID == id {
                ProgressView().controlSize(.small).help(L("Computing session results…", "正在计算各次实验的结果…"))
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func contextMenu(_ item: SidebarItem) -> some View {
        switch item {
        case .task(let id):
            Button(L("Add videos…", "添加视频…")) { chooseVideos(for: ImportContext(experimentID: id)) }
            Divider()
            Button(L("Add / edit note…", "添加／编辑备注…")) { openTaskNoteEditor(id) }
            if let exp = store.experiment(id), exp.hasNotes {
                Button(L("Remove note", "删除备注"), role: .destructive) {
                    if let surviving = store.setTaskNotes(id, notes: ""), selection?.taskID == id { select(.task(surviving)) }
                }
            }
            Button(L("Create task with another note…", "按不同备注新建同名任务…")) {
                openTaskNoteEditor(id, createsSeparateTask: true)
            }
            Divider()
            Button(L("Delete task…", "删除任务…"), role: .destructive) { confirmDeleteTask = id }
        case .group(let id, let g):
            Button(L("Add videos to this group…", "向该组添加视频…")) { chooseVideos(for: ImportContext(experimentID: id, group: g)) }
        case .animal(let id, let key):
            Button(L("Add a session of this animal…", "为该小鼠添加一次实验…")) {
                let attrs = project?.animalAttributes(task: id, animal: key)
                chooseVideos(for: ImportContext(experimentID: id, animal: key, group: attrs?.group))
            }
        case .session(let id), .unassigned(let id):
            if let v = store.video(id), v.tstChamber != nil {
                Button(L("Adjust settings and analyse again…", "调整参数并重新分析…")) { reanalyseTST(v) }
                Divider()
            }
            if let v = store.video(id), v.experimentID != nil {
                if v.isExcluded {
                    Button(L("Include in group summaries", "重新纳入组间汇总")) { store.setExcluded(id, excluded: false, reason: "") }
                } else {
                    Button(L("Exclude from group summaries…", "排除出组间汇总…")) { excludeReason = ""; excludeTarget = id }
                }
                Divider()
            }
            Button(L("Remove from project…", "从项目中移除…"), role: .destructive) { confirmRemove = id }
        }
    }

    /// Opens the saved multi-chamber recording of a TST session again, with its chambers, start and settings.
    private func reanalyseTST(_ v: VideoRecord) {
        guard let ref = v.tstChamber, let task = v.experimentID,
              let record = TSTTaskArchive.load(task, record: ref.recordingID) else {
            store.notice = L("The saved analysis of this recording could not be read.", "无法读取这段录像保存的分析结果。")
            return
        }
        flushDrafts(confirmSetup: false)
        tstImport = TSTImportRequest(experimentID: task, url: nil, presetGroup: nil, replacing: record)
    }

    // MARK: Task notes and deletion

    private func openTaskNoteEditor(_ id: UUID, createsSeparateTask: Bool = false) {
        guard let exp = store.experiment(id) else { return }
        taskNoteDraft = createsSeparateTask ? "" : (exp.notes ?? "")
        taskNoteTarget = TaskNoteTarget(taskID: id, createsSeparateTask: createsSeparateTask)
    }

    private func taskNoteSheet(_ target: TaskNoteTarget) -> some View {
        let creates = target.createsSeparateTask
        return VStack(alignment: .leading, spacing: 14) {
            Text(creates ? L("Task with a note", "带备注的任务")
                         : L("Task note", "任务备注"))
                .font(.title3.bold())
            if let exp = store.experiment(target.taskID) {
                Text(exp.displayTitle).foregroundStyle(.secondary)
            }
            Text(creates
                 ? L("Give this task a note. If a task with the same name, assay and note exists, that task will be selected instead of creating a duplicate.",
                     "请填写备注。如果已有名称、实验类型和备注都相同的任务，将直接打开已有任务，不再重复创建。")
                 : L("Tasks with the same name, assay and note (including no note) merge automatically. Different notes keep tasks separate; conflicting animal/session data will not be merged.",
                     "名称、实验类型和备注都相同（包括都没有备注）的任务会自动合并；备注不同则保持独立。若小鼠／实验次数冲突，则不合并。"))
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $taskNoteDraft)
                .font(.body)
                .frame(minHeight: 145)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
            HStack {
                if !creates {
                    Button(L("Clear note", "删除备注"), role: .destructive) {
                        flushDrafts(confirmSetup: false)
                        if let id = store.setTaskNotes(target.taskID, notes: "") {
                            if selection?.taskID == target.taskID { select(.task(id)) }
                        }
                        taskNoteTarget = nil
                    }
                    .disabled(taskNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
                Button(L("Cancel", "取消")) { taskNoteTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button(creates ? L("Create task", "新建任务") : L("Save note", "保存备注")) {
                    flushDrafts(confirmSetup: false)
                    if creates {
                        if let id = store.createSeparateTask(from: target.taskID, note: taskNoteDraft) {
                            select(.task(id))
                        }
                    } else if let id = store.setTaskNotes(target.taskID, notes: taskNoteDraft) {
                        // Matching another task's note can merge into that existing task.
                        if selection?.taskID == target.taskID { select(.task(id)) }
                    }
                    taskNoteTarget = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(creates && taskNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func deleteTask(_ id: UUID) {
        let vids = project?.sessions(ofTask: id) ?? []
        let ids = Set(vids.map(\.id))
        // Running and queued sessions must not write back into a deleted task.
        if let job = run.job, ids.contains(job.videoID) {
            store.notice = L("Pause the active analysis before deleting its task.",
                             "删除任务前，请先暂停正在运行的分析。")
            return
        }
        for vid in ids { run.removeFromQueue(vid) }
        if let loaded = run.videoID, ids.contains(loaded) { run.clear() }
        taskData.cancel()
        flushDrafts(confirmSetup: false)
        store.deleteTask(id)
        var wasSelected = selection?.taskID == id
        if case .session(let vid)? = selection { wasSelected = wasSelected || ids.contains(vid) }
        if case .task(let t)? = destination, t == id { destination = nil }
        if case .group(let t, _)? = destination, t == id { destination = nil }
        if wasSelected {
            selection = nil
            restoreSelection()
        }
        if destination == nil { restoreDestination() }
    }

    // MARK: Selection

    private func select(_ item: SidebarItem?) {
        guard item != selection else { return }
        flushDrafts(confirmSetup: false)
        selection = item
        switch item {
        case .task(let id)?, .group(let id, _)?, .animal(let id, _)?:
            store.focusedExperimentID = id
            store.focusedVideoID = nil
        case .session(let id)?:
            if let v = store.video(id) {
                store.focusedExperimentID = v.experimentID
                if step == .review && v.runState != .complete { stepRaw = WorkflowStep.run.rawValue }
                if !v.hasSessionInfo { stepRaw = WorkflowStep.video.rawValue }
            }
            store.focusedVideoID = id
        case .unassigned(let id)?:
            store.focusedVideoID = id
        case nil:
            break
        }
    }

    /// Selection after launch, a project switch or a return from another section.
    private func restoreSelection() {
        if selection != nil { return }
        if let id = store.focusedVideoID, let v = store.video(id) {
            selection = v.experimentID == nil ? .unassigned(id) : .session(id)
            expandAncestors(of: v)
        } else if let t = store.focusedExperimentID, store.experiment(t) != nil {
            selection = .task(t)
        } else if let first = tasks.first {
            selection = .task(first.id)
        }
    }

    /// Another view moved the focus to a session (Data tab, "next session to check", import).
    private func followFocus(_ id: UUID?) {
        guard let id, let v = store.video(id) else { return }
        let item: SidebarItem = v.experimentID == nil ? .unassigned(id) : .session(id)
        guard item != selection else { return }
        flushDrafts(confirmSetup: false)
        selection = item
        expandAncestors(of: v)
        if step == .review && v.runState != .complete { stepRaw = WorkflowStep.run.rawValue }
    }

    private func expandAncestors(of v: VideoRecord) {
        guard let t = v.experimentID else { return }
        collapsed.remove("t:" + t.uuidString)
        collapsed.remove("g:" + t.uuidString + ":" + v.groupKey)
        collapsed.remove("a:" + t.uuidString + ":" + v.groupKey + ":" + v.animalKey)
        collapsed.remove("a:" + t.uuidString + ":*:" + v.animalKey)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .task(let id)?:
            if let exp = store.experiment(id) {
                TaskOverviewView(experiment: exp, onOpen: { select($0) },
                                 onAddVideos: { chooseVideos(for: ImportContext(experimentID: id)) },
                                 onEditNote: { openTaskNoteEditor(id) })
            } else {
                emptyDetail
            }
        case .group(let id, let g)?:
            if let exp = store.experiment(id) {
                GroupOverviewView(experiment: exp, group: g, onOpen: { select($0) },
                                  onAddVideos: { chooseVideos(for: ImportContext(experimentID: id, group: g)) })
            } else {
                emptyDetail
            }
        case .animal(let id, let key)?:
            if let exp = store.experiment(id) {
                AnimalOverviewView(experiment: exp, animalKey: key, onOpen: { select($0) },
                                   onAddVideos: {
                                       let attrs = project?.animalAttributes(task: id, animal: key)
                                       chooseVideos(for: ImportContext(experimentID: id, animal: key, group: attrs?.group))
                                   })
            } else {
                emptyDetail
            }
        case .session?:
            if video != nil {
                VStack(spacing: 0) {
                    breadcrumb
                    stepBar
                    Divider()
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                emptyDetail
            }
        case .unassigned?:
            unassignedDetail
        case nil:
            emptyDetail
        }
    }

    @ViewBuilder
    private var emptyDetail: some View {
        if tasks.isEmpty {
            TaskPickerView(current: nil) { picked in createTask(picked) }
        } else {
            ContentUnavailableView(L("Select a task, group, animal or session", "选择任务、分组、小鼠或某次实验"), systemImage: "sidebar.left",
                                   description: Text(L("Tasks contain groups, animals and their sessions. Add videos with +.", "任务下面是分组、小鼠及其各次实验。点 + 添加视频。")))
        }
    }

    private var unassignedDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("This video is not in a task", "该视频不属于任何任务")).font(.title3.bold())
            Text(L("Videos imported by earlier versions may have no task. Add the file again to a task (with its animal, date and session number), then remove this entry.",
                   "早期版本导入的视频可能没有任务。请把该文件重新添加到某个任务（填写小鼠、日期和实验次数），然后移除这一条。"))
                .foregroundStyle(.secondary)
            if let v = video {
                LabeledContent(L("File", "文件"), value: v.fileName)
                HStack {
                    Menu(L("Add to task…", "添加到任务…")) {
                        ForEach(tasks) { exp in
                            Button(exp.displayTitle) {
                                if let url = store.resolveURL(v) {
                                    importRequest = ImportRequest(experimentID: exp.id, urls: [url],
                                                                  presetAnimal: v.animalID.isEmpty ? nil : v.animalID, presetGroup: v.group)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 220)
                    Button(L("Remove from project…", "从项目中移除…"), role: .destructive) { confirmRemove = v.id }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 720, alignment: .leading)
    }

    // MARK: Session steps (navigation sits at the top, never at the window bottom)

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            if let exp = experiment, let v = video {
                Button(exp.displayTitle) { select(.task(exp.id)) }.buttonStyle(.link)
                if usesGroups(exp.id) {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Button(v.groupKey.isEmpty ? L("Ungrouped", "未分组") : v.groupKey) { select(.group(exp.id, v.groupKey)) }.buttonStyle(.link)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Button(v.displayName) { select(.animal(exp.id, v.animalKey)) }.buttonStyle(.link)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text(v.sessionTitle).foregroundStyle(.secondary)
                if v.isExcluded {
                    Label(L("Excluded", "已排除"), systemImage: "minus.circle").foregroundStyle(.orange).font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)              // long task / animal names shorten instead of pushing the page wider
        .truncationMode(.middle)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func usesGroups(_ taskID: UUID) -> Bool {
        project?.groups(ofTask: taskID).contains(where: { !$0.isEmpty }) ?? false
    }

    private var stepBar: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                stepItems(showTitles: true)
                stepItems(showTitles: false)
            }
            Spacer(minLength: 8)
            Button {
                back()
            } label: {
                Label(L("Back", "上一步"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(step == .video)
            .help(L("Previous step ⌘[", "上一步 ⌘["))
            Button {
                forward()
            } label: {
                Text(continueTitle)
            }
            .keyboardShortcut("]", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!canContinue)
            .help(L("Next step ⌘]", "下一步 ⌘]"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func stepItems(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(WorkflowStep.allCases) { s in
                Button {
                    go(s)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isDone(s) && s != step ? "checkmark.circle.fill" : s.symbol)
                            .foregroundStyle(isDone(s) && s != step ? Color.green : (s == step ? Color.accentColor : Color.secondary))
                        if showTitles { Text(s.title).lineLimit(1) }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 9)
                    .background(s == step ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable(s))
                .help(s.title)
                .accessibilityLabel(s.title)
                if s != .review {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .fixedSize()
    }

    private var continueTitle: String {
        switch step {
        case .review: return L("Next session →", "下一次实验 →")
        case .run: return L("Review →", "复核 →")
        default: return L("Continue →", "继续 →")
        }
    }

    private func isAvailable(_ s: WorkflowStep) -> Bool {
        guard experiment != nil, video != nil else { return false }
        switch s {
        case .video, .calibrate, .run: return true
        case .review: return video?.runState == .complete
        }
    }

    private func isDone(_ s: WorkflowStep) -> Bool {
        switch s {
        case .video: return video?.hasSessionInfo ?? false
        case .calibrate: return assay == .tstMultiChamber || (assay.map { video?.hasSetup(for: $0) ?? false } ?? false)
        case .run: return video?.runState == .complete
        case .review: return video?.reviewVerdict == .passed
        }
    }

    private var canContinue: Bool {
        switch step {
        case .video: return video != nil && infoProblems.isEmpty
        case .calibrate: return assay == .tstMultiChamber || setupDraft != nil
        case .run: return video?.runState == .complete
        case .review: return nextVideo != nil
        }
    }

    /// Next session in tree order: during review the next analysed session whose tracking is not checked
    /// yet, otherwise the next session that still needs work.
    private var nextVideo: VideoRecord? {
        guard let current = video, let i = taskVideos.firstIndex(where: { $0.id == current.id }) else { return nil }
        let rest = Array(taskVideos[(i + 1)...]) + Array(taskVideos[..<i])
        if step == .review, let unchecked = rest.first(where: { $0.runState == .complete && $0.reviewVerdict == .unreviewed }) {
            return unchecked
        }
        return rest.first { $0.runState != .complete } ?? rest.first
    }

    private func go(_ s: WorkflowStep) {
        guard isAvailable(s) else { return }
        flushDrafts(confirmSetup: false)
        stepRaw = s.rawValue
    }

    private func back() {
        guard let prev = WorkflowStep(rawValue: step.rawValue - 1) else { return }
        flushDrafts(confirmSetup: false)
        stepRaw = prev.rawValue
    }

    private func forward() {
        switch step {
        case .video:
            flushDrafts(confirmSetup: false, forceInfo: true)
            stepRaw = WorkflowStep.calibrate.rawValue
        case .calibrate:
            flushDrafts(confirmSetup: true)
            stepRaw = WorkflowStep.run.rawValue
        case .run:
            stepRaw = WorkflowStep.review.rawValue
        case .review:
            if let next = nextVideo {
                select(.session(next.id))
                if let v = store.video(next.id) { expandAncestors(of: v) }
                // An analysed session is reviewed next; one that is not analysed yet starts at its information.
                stepRaw = (next.runState == .complete ? WorkflowStep.review : WorkflowStep.video).rawValue
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .video:
            sessionInfoStep
        case .calibrate:
            if let assay, let video, assay == .tstMultiChamber {
                TSTSessionStepView(video: video, step: .calibrate, onAddRecording: { chooseVideos() },
                                   onReanalyse: { reanalyseTST(video) })
            } else if let assay, let video {
                TaskCalibrationView(assay: assay, video: video, videoURL: store.resolveURL(video),
                                    taskVideoCount: taskVideos.count,
                                    draft: $setupDraft,
                                    isSaved: video.hasSetup(for: assay),
                                    onCreatedDefault: { fresh in
                                        setupUntouched = fresh
                                        setupDraft = fresh
                                    },
                                    onSave: { flushDrafts(confirmSetup: true) },
                                    onApplyToAll: { applySetupToAll() })
                    .padding(18)
                    .id(video.id)
            }
        case .run:
            if let assay, let video, assay == .tstMultiChamber {
                TSTSessionStepView(video: video, step: .run, onAddRecording: { chooseVideos() },
                                   onReanalyse: { reanalyseTST(video) })
            } else if let assay, let video {
                ScrollView {
                    TaskRunPanel(assay: assay, video: video, taskVideos: taskVideos,
                                 onCalibrate: { go(.calibrate) }, onReview: { go(.review) })
                        .padding(18)
                        .frame(maxWidth: 900, alignment: .leading)
                }
            }
        case .review:
            if let assay, let video, assay == .tstMultiChamber {
                TSTSessionStepView(video: video, step: .review, onAddRecording: { chooseVideos() },
                                   onReanalyse: { reanalyseTST(video) })
            } else if let assay, let video {
                ReviewStepView(assay: assay, video: video, onCalibrate: { go(.calibrate) }, onAnalyse: { go(.run) })
                    .padding(18)
            }
        }
    }

    // MARK: Session info

    /// Problems that keep the session information from being complete (shown in red; Continue waits).
    private var infoProblems: [String] {
        var out: [String] = []
        let animal = info.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        if animal.isEmpty { out.append(L("Animal ID is required.", "必须填写小鼠编号。")) }
        if info.sessionDate == nil { out.append(L("Recording date is required.", "必须填写实验日期。")) }
        if (info.sessionNumber ?? 0) < 1 { out.append(L("Session number (1, 2, 3 …) is required.", "必须填写实验次数（1、2、3 …）。")) }
        if let conflict = infoConflict {
            out.append(String(format: L("%@ already has session #%d in this task (%@).", "%@ 在此任务中已有第 %d 次实验（%@）。"),
                              animal, info.sessionNumber ?? 0, conflict.fileName))
        }
        return out
    }

    private var infoConflict: VideoRecord? {
        let animal = info.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let exp = experiment, let id = infoVideoID, !animal.isEmpty, let n = info.sessionNumber else { return nil }
        return project?.sessionConflict(task: exp.id, animal: animal, number: n, excluding: id)
    }

    /// Group and sex of another existing animal the session is being moved to (they are kept).
    private var targetAnimalAttributes: (group: String, sex: String)? {
        guard let exp = experiment, let v = video else { return nil }
        let animal = info.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !animal.isEmpty, animal != v.animalKey else { return nil }
        return project?.animalAttributes(task: exp.id, animal: animal, excluding: v.id)
    }

    @ViewBuilder
    private var sessionInfoStep: some View {
        if let video, let assay {
            let otherSessions = (project?.sessions(ofTask: experiment?.id ?? UUID(), animal: video.animalKey).count ?? 1) - 1
            Form {
                Section {
                    LabeledContent(L("File", "文件"), value: video.fileName)
                    LabeledContent(L("Video", "视频"), value: videoSummary(video))
                }
                Section {
                    TextField(L("Animal ID *", "小鼠编号 *"), text: $info.animalID, prompt: Text(L("e.g. M01", "如 M01")))
                    if let target = targetAnimalAttributes {
                        Label(String(format: L("This session moves to the existing animal %@ (group %@).", "该次实验将归入已有小鼠 %@（分组 %@）。"),
                                     info.animalID.trimmingCharacters(in: .whitespacesAndNewlines),
                                     target.group.isEmpty ? L("none", "无") : target.group),
                              systemImage: "arrow.right.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField(L("Group", "分组"), text: $info.group, prompt: Text(L("e.g. WT, KO, Vehicle (optional)", "如 WT / KO / 对照（可选）")))
                        if !knownGroups.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(knownGroups, id: \.self) { g in
                                        Button(g) { info.group = g }
                                            .buttonStyle(.plain)
                                            .font(.callout)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(info.group == g ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: Capsule())
                                            .accessibilityLabel(String(format: L("Use group %@", "使用组别 %@"), g))
                                    }
                                }
                            }
                        }
                        if assay.usesSex {
                            Picker(L("Sex", "性别"), selection: $info.sex) {
                                Text("—").tag("")
                                Text(L("Male", "雄")).tag("M")
                                Text(L("Female", "雌")).tag("F")
                            }
                            .pickerStyle(.segmented)
                        }
                        if otherSessions > 0 {
                            Text(String(format: L("Group and sex belong to the animal: a change applies to its %d other session(s) in this task too.",
                                                  "分组和性别属于小鼠：修改会同时应用到它在此任务中的另外 %d 次实验。"), otherSessions))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L("Animal", "小鼠"))
                }
                Section {
                    if info.sessionDate != nil {
                        DatePicker(L("Recording date *", "实验日期 *"),
                                   selection: Binding(get: { info.sessionDate ?? Date() }, set: { info.sessionDate = $0 }),
                                   displayedComponents: .date)
                    } else {
                        HStack {
                            Text(L("Recording date *", "实验日期 *"))
                            Spacer()
                            Button(L("Set date…", "填写日期…")) { info.sessionDate = guessedDate(video) }
                        }
                    }
                    Stepper(value: Binding(get: { info.sessionNumber ?? 0 }, set: { info.sessionNumber = max(1, $0) }), in: 0...9999) {
                        HStack {
                            Text(L("Session number (实验次数) *", "实验次数 *"))
                            Spacer()
                            Text((info.sessionNumber ?? 0) >= 1 ? "#\(info.sessionNumber ?? 0)" : L("not set", "未填写"))
                                .monospacedDigit().foregroundStyle((info.sessionNumber ?? 0) >= 1 ? Color.primary : Color.orange)
                        }
                    }
                    let options = assay.phaseOptions
                    if !options.isEmpty {
                        Picker(L("Phase", "阶段"), selection: $info.phase) {
                            ForEach(options.indices, id: \.self) { i in Text(options[i].title).tag(options[i].key) }
                        }
                    } else if assay.allowsFreePhase {
                        TextField(L("Phase", "阶段"), text: $info.phase, prompt: Text(L("Optional, e.g. after dosing", "可选，如 给药后")))
                    }
                    if assay.usesDay { OptionalIntField(title: L("Day (learning curve)", "天（学习曲线）"), value: $info.day) }
                    if assay.usesTrial { OptionalIntField(title: L("Trial within the day", "当天试次"), value: $info.trial) }
                    ForEach(infoProblems, id: \.self) { p in
                        Label(p, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text(L("Session", "实验"))
                } footer: {
                    Text(L("One video = one session of one animal. Session numbers count the sessions of the animal in this task (1, 2, 3 …); phases are never pooled in the summaries.",
                           "一段视频 = 一只小鼠的一次实验。实验次数为该小鼠在此任务中的第几次（1、2、3 …）；汇总时不同阶段不会合并。"))
                }
                Section {
                    Toggle(L("Exclude from group summaries", "排除出组间汇总"), isOn: $info.excluded)
                    if info.excluded {
                        TextField(L("Reason (exported)", "原因（会导出）"), text: $info.exclusionReason, prompt: Text(L("e.g. fell off the maze, tracking failed", "如 掉落迷宫、追踪失败")))
                    }
                    if assay.usesNotes || !info.notes.isEmpty {
                        TextField(L("Notes", "备注"), text: $info.notes, prompt: Text(L("Dose, treatment, anything unusual…", "剂量、处理、异常情况…")), axis: .vertical)
                            .lineLimit(2...5)
                    }
                } header: {
                    Text(L("Inclusion and notes", "纳入与备注"))
                } footer: {
                    Text(L("An excluded session keeps its own results; it is left out of animal means, group statistics, comparisons and summary exports (listed with its reason).",
                           "被排除的实验保留自己的结果；只是不进入小鼠均值、组统计、组间比较和汇总导出（导出时会列出原因）。"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func guessedDate(_ v: VideoRecord) -> Date {
        if let text = SessionDate.fromFileName(v.fileName), let d = SessionDate.date(text) { return d }
        return v.importedAt
    }

    private var knownGroups: [String] {
        guard let exp = experiment, let project else { return [] }
        return Array(project.groups(ofTask: exp.id).filter { !$0.isEmpty }.prefix(12))
    }

    private func videoSummary(_ v: VideoRecord) -> String {
        let minutes = Int(v.durationSeconds) / 60, seconds = Int(v.durationSeconds) % 60
        return String(format: "%d:%02d · %d × %d · %.1f fps", minutes, seconds, v.videoWidth, v.videoHeight, v.framesPerSecond)
    }

    // MARK: Drafts

    private func syncDrafts() {
        let current = video
        let infoChanged = current?.id != infoVideoID || experiment?.id != infoExperimentID
        let setupChanged = current?.id != setupVideoID || experiment?.id != setupExperimentID
        // Pending edits of the previous session are written first (to their own video and task).
        if infoChanged || setupChanged { flushDrafts(confirmSetup: false) }
        if infoChanged {
            infoSaveTask?.cancel()
            infoVideoID = current?.id
            infoExperimentID = experiment?.id
            info = current.map { VideoInfoDraft($0, defaultPhase: assay?.defaultPhase ?? "") } ?? VideoInfoDraft()
        }
        if setupChanged {
            setupSaveTask?.cancel()
            setupVideoID = current?.id
            setupExperimentID = experiment?.id
            setupUntouched = nil
            if let current, let assay, let saved = current.calibration, saved.matches(assay) {
                setupDraft = saved
            } else {
                setupDraft = nil
            }
        }
    }

    /// The stored exclusion changed outside the draft: take it over unless the draft was edited itself.
    private func followExcluded(_ old: Bool?, _ new: Bool?) {
        guard let new, infoVideoID == video?.id, info.excluded == (old ?? false) else { return }
        info.excluded = new
    }

    private func followExclusionReason(_ old: String?, _ new: String?) {
        guard infoVideoID == video?.id, info.exclusionReason == (old ?? "") else { return }
        info.exclusionReason = new ?? ""
    }

    private func scheduleInfoSave() {
        guard let id = infoVideoID, store.video(id) != nil else { return }
        infoSaveTask?.cancel()
        infoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            saveInfo(force: false)
        }
    }

    /// Writes the session information. Typing saves edits; Continue also stores the defaults shown (e.g. the
    /// task's default phase). An animal / session number that would clash with another session is not
    /// saved (the red message stays until it is fixed). Group and sex are written to every session of the
    /// animal; a session moved to an existing animal takes that animal's group and sex.
    private func saveInfo(force: Bool) {
        guard let id = infoVideoID, let v = store.video(id) else { return }
        let d = info
        let expID = infoExperimentID ?? v.experimentID
        let taskAssay = expID.flatMap { e in project?.experiments.first { $0.id == e }?.assay }
        let edited = VideoInfoDraft(v, defaultPhase: taskAssay?.defaultPhase ?? "") != d
        guard edited || force else { return }
        let animal = d.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        var clash = false
        if let expID, !animal.isEmpty, let n = d.sessionNumber,
           project?.sessionConflict(task: expID, animal: animal, number: n, excluding: id) != nil {
            clash = true
        }
        let existing: (group: String, sex: String)? = (expID != nil && !animal.isEmpty && animal != v.animalKey)
            ? project?.animalAttributes(task: expID!, animal: animal, excluding: id) : nil
        store.updateVideo(id) { r in
            if !clash {
                r.animalID = animal
                r.sessionNumber = (d.sessionNumber ?? 0) >= 1 ? d.sessionNumber : nil
            }
            r.sessionDate = d.sessionDate.map { SessionDate.string($0) }
            r.phase = d.phase.trimmingCharacters(in: .whitespacesAndNewlines)
            r.day = d.day
            r.trial = d.trial
            r.notes = d.notes.isEmpty ? nil : d.notes
            r.excluded = d.excluded ? true : nil
            let reason = d.exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines)
            r.exclusionReason = d.excluded && !reason.isEmpty ? reason : nil
            if r.experimentID == nil { r.experimentID = expID }
        }
        guard let expID, let saved = store.video(id) else { return }
        if let existing, !clash {
            store.setAnimalAttributes(task: expID, animal: saved.animalKey, group: existing.group, sex: existing.sex)
        } else {
            store.setAnimalAttributes(task: expID, animal: saved.animalKey, group: d.group, sex: d.sex)
        }
    }

    /// Calibration edits are saved shortly after the pointer is released. An untouched default is only
    /// saved when the user confirms it (Continue or Save), as RodentLimb requires for the cylinder.
    private func scheduleSetupSave() {
        guard let draft = setupDraft, let id = setupVideoID else { return }
        if let untouched = setupUntouched, draft == untouched, !(store.video(id)?.hasSetup(for: assay ?? .poseOnly) ?? false) { return }
        setupSaveTask?.cancel()
        setupSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveSetup(confirm: false)
        }
    }

    private func saveSetup(confirm: Bool) {
        guard var draft = setupDraft, let id = setupVideoID, let expID = setupExperimentID,
              let exp = project?.experiments.first(where: { $0.id == expID }), draft.matches(exp.assay),
              let v = store.video(id) else { return }
        let stored = v.calibration
        if !confirm, let untouched = setupUntouched, draft == untouched, !(v.hasSetup(for: exp.assay)) { return }
        if stored == draft && v.hasSetup(for: exp.assay) { return }
        if let stored, stored != draft, draft.copiedFrom != nil, draft.copiedFrom == stored.copiedFrom,
           stored.pose != draft.pose || stored.flow != draft.flow {
            // Edited after being copied from another animal: it is now this video's own calibration.
            draft.copiedFrom = nil
        }
        draft.syncSummary()
        setupDraft = draft
        setupUntouched = nil
        store.saveSetup(videoID: id, experimentID: exp.id, setup: draft)
    }

    private func flushDrafts(confirmSetup: Bool, forceInfo: Bool = false) {
        if infoSaveTask != nil {
            infoSaveTask?.cancel()
            infoSaveTask = nil
        }
        saveInfo(force: forceInfo)
        setupSaveTask?.cancel()
        setupSaveTask = nil
        if setupDraft != nil { saveSetup(confirm: confirmSetup) }
    }

    private func applySetupToAll() {
        guard let draft = setupDraft, let id = setupVideoID, let expID = setupExperimentID,
              let exp = project?.experiments.first(where: { $0.id == expID }), draft.matches(exp.assay) else { return }
        saveSetup(confirm: true)
        let n = store.applySetupToTask(draft, from: id, experimentID: exp.id)
        store.notice = String(format: L("Calibration copied to %d other videos of this task.", "已把标定复制到该任务的另外 %d 个视频。"), n)
    }

    // MARK: Tasks and import

    private var newTaskSheet: some View {
        VStack(spacing: 0) {
            TaskPickerView(current: nil) { picked in
                showTaskPicker = false
                createTask(picked)
            }
            Divider()
            HStack {
                Text(L("One task per behavioural test. Its groups, animals and sessions are added with the videos.",
                       "每个行为学测试一个任务。分组、小鼠和各次实验随视频一起添加。"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel", "取消"), role: .cancel) { showTaskPicker = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 820, minHeight: 600)
    }

    private func createTask(_ assay: StudyAssay) {
        flushDrafts(confirmSetup: false)
        guard let id = store.selectTask(assay) else { return }
        collapsed.remove("t:" + id.uuidString)
        select(.task(id))
    }

    /// Where new videos go: the task of the selection, with the group / animal of the selection as presets.
    struct ImportContext {
        var experimentID: UUID
        var animal: String? = nil
        var group: String? = nil
    }

    private var importContext: ImportContext? {
        switch selection {
        case .task(let id)?: return ImportContext(experimentID: id)
        case .group(let id, let g)?: return ImportContext(experimentID: id, group: g)
        case .animal(let id, let key)?:
            return ImportContext(experimentID: id, animal: key, group: project?.animalAttributes(task: id, animal: key)?.group)
        case .session?:
            if let v = video, let e = v.experimentID { return ImportContext(experimentID: e) }
        default:
            break
        }
        if let t = store.focusedExperimentID, store.experiment(t) != nil { return ImportContext(experimentID: t) }
        return tasks.count == 1 ? ImportContext(experimentID: tasks[0].id) : nil
    }

    private func chooseVideos(for context: ImportContext? = nil) {
        guard let target = context ?? importContext else {
            store.notice = L("Select a task first (or create one with “New task”).", "请先选择一个任务（或用“新建任务”创建）。")
            return
        }
        if store.experiment(target.experimentID)?.assay == .tstMultiChamber {
            // One raw recording may contain many animals: choose the file first (as for every other task),
            // then the sheet detects the chambers and asks for each chamber's animal, date and session number.
            guard let url = TSTVideoPicker.choose() else { return }
            flushDrafts(confirmSetup: false)
            tstImport = TSTImportRequest(experimentID: target.experimentID, url: url, presetGroup: target.group)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = L("Choose the videos (one session of one animal per video)", "选择视频（每段视频是一只小鼠的一次实验）")
        panel.prompt = L("Continue", "继续")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        flushDrafts(confirmSetup: false)
        importRequest = ImportRequest(experimentID: target.experimentID, urls: panel.urls,
                                      presetAnimal: target.animal, presetGroup: target.group)
    }

    private func importDropped(_ urls: [URL]) -> Bool {
        guard let target = importContext else { return false }
        let movies = urls.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .movie)
        }
        guard !movies.isEmpty else { return false }
        if store.experiment(target.experimentID)?.assay == .tstMultiChamber {
            // One dropped file cannot be assumed to be one animal session: it opens the multi-chamber sheet.
            // Recordings are analysed one at a time.
            flushDrafts(confirmSetup: false)
            tstImport = TSTImportRequest(experimentID: target.experimentID, url: movies[0], presetGroup: target.group)
            if movies.count > 1 {
                store.notice = L("TST recordings are analysed one at a time; the first dropped video was opened.",
                                 "TST 录像需逐段分析；已打开拖入的第一段视频。")
            }
            return true
        }
        flushDrafts(confirmSetup: false)
        importRequest = ImportRequest(experimentID: target.experimentID, urls: movies,
                                      presetAnimal: target.animal, presetGroup: target.group)
        return true
    }

    /// After an import the first new session opens at Calibrate (its information was entered on import).
    private func imported(_ ids: [UUID]) {
        guard let first = ids.first, let v = store.video(first) else { return }
        expandAncestors(of: v)
        select(.session(first))
        stepRaw = WorkflowStep.calibrate.rawValue
    }
}

// MARK: - Task picker (RodentPose "choose paradigm", grouped by app and category)

struct TaskPickerView: View {
    let current: StudyAssay?
    let onPick: (StudyAssay) -> Void
    @State private var query = ""

    private struct TaskGroup: Identifiable {
        let id: String
        let title: String
        let caption: String
        let tasks: [StudyAssay]
    }

    private func matches(_ a: StudyAssay) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return a.displayName.lowercased().contains(q) || a.name.lowercased().contains(q)
    }

    private var groups: [TaskGroup] {
        var out: [TaskGroup] = []
        let eligible = StudyAssay.allCases.filter { $0.isDesktopEligible && matches($0) }
        for cat in ParadigmCategory.allCases {
            let items = eligible.filter { $0.module == .pose && $0.paradigm?.category == cat }
            if !items.isEmpty {
                out.append(TaskGroup(id: "pose." + cat.rawValue, title: "RodentPose · " + cat.title,
                                     caption: L("Pose tracking with 6 keypoints; zones from the calibration.", "6 关键点姿态追踪；区域来自标定。"),
                                     tasks: items))
            }
        }
        let limb = eligible.filter { $0.module == .limb || $0 == .tstMultiChamber }
        if !limb.isEmpty {
            out.append(TaskGroup(id: "limb", title: L("Limb function and tail suspension", "肢体功能与悬尾实验"),
                                 caption: L("Task-specific algorithms: 7-point limb pose or multi-chamber silhouette scoring.",
                                            "各任务使用专属算法：七关键点姿态或多格轮廓评分。"),
                                 tasks: limb))
        }
        let flow = eligible.filter { $0.module == .flow }
        if !flow.isEmpty {
            out.append(TaskGroup(id: "flow", title: "RodentFlow · " + L("Classic centroid", "经典质心"),
                                 caption: L("Setup and calibration as in RodentFlow; RodentFlow 1.3 classic centroid tracker at 10 Hz (no neural network).",
                                            "设置与标定同 RodentFlow；使用 RodentFlow 1.3 经典质心追踪（10 Hz，不使用神经网络）。"),
                                 tasks: flow))
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("What are you measuring?", "要测量哪种行为？")).font(.title2.bold())
                    Text(L("Choose the behavioural task. It decides the calibration, the analysis method and the model — you do not need to pick a model.",
                           "选择行为学任务。它决定标定方式、分析方法和模型——无需自己选择模型。"))
                        .foregroundStyle(.secondary)
                    TextField(L("Search tasks", "搜索任务"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                }
                if groups.isEmpty {
                    Text(L("No task matches the search.", "没有匹配的任务。")).foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.headline)
                        Text(group.caption).font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(group.tasks) { a in
                                taskCard(a)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    private func taskCard(_ a: StudyAssay) -> some View {
        let selected = a == current
        return Button {
            onPick(a)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: a.symbol)
                    .font(.title3)
                    .frame(width: 26)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.displayName).font(.callout.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    if !a.canRunOnDesktop {
                        Text(L("Setup only on desktop", "桌面版仅可设置")).font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.displayName)
    }
}
