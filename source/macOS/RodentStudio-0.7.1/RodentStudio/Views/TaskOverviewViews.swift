// TaskOverviewViews.swift — what the sidebar shows for a task, a group and an animal.
//
//   Task:   every session in one table, the group comparison (preliminary statistics, RodentFlow's
//           methods), and the task-level export.
//   Group:  its animals, descriptive statistics per phase, and the group-level export.
//   Animal: its sessions and the values of one measure across sessions; animal ID, group and sex.
//
// All numbers come from TaskDataModel (each session computed once by its own Results path).

import SwiftUI
import AppKit
import Charts

// MARK: - Shared pieces

/// Starts the background computation of a task's session results whenever its sessions change
/// (placed in the background of the task, group and animal pages).
private struct TaskDataPreparer: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel
    let experiment: NativeExperiment

    private var key: String {
        guard let project = store.selectedProject else { return "" }
        var parts: [String] = [experiment.id.uuidString]
        for v in project.sessions(ofTask: experiment.id) where v.runState == .complete {
            parts.append(taskData.key(v, assay: experiment.assay))
        }
        return parts.joined(separator: "|")
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: key) { taskData.prepare(task: experiment.id, store: store) }
            .accessibilityHidden(true)
    }
}

private struct StatChip: View {
    let title: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Progress of the background computation of session results.
private struct ComputeStatus: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel
    let experiment: NativeExperiment

    var body: some View {
        if let p = taskData.progress {
            HStack(spacing: 10) {
                ProgressView(value: Double(p.done), total: Double(max(1, p.total))).frame(maxWidth: 200)
                Text(String(format: L("Computing session results %d / %d (same analysis as each Results page; saved with the run)…",
                                      "正在计算各次实验的结果 %d / %d（与各次实验“结果”页相同的分析；随结果保存）…"), p.done, p.total))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Stop", "停止")) { taskData.cancel() }.controlSize(.small)
            }
        } else if failedCount > 0 {
            HStack(spacing: 10) {
                Label(String(format: L("%d session(s) could not be computed; open them to see why.", "%d 次实验无法计算结果；打开查看原因。"), failedCount),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                Button(L("Try again", "重试")) { taskData.retryFailed(task: experiment.id, store: store) }.controlSize(.small)
            }
        }
    }

    private var failedCount: Int {
        guard let project = store.selectedProject else { return 0 }
        return project.sessions(ofTask: experiment.id).filter {
            if case .failed = taskData.state($0, assay: experiment.assay) { return true }
            return false
        }.count
    }
}

/// Short value of the primary measure of a session ("—" without results).
@MainActor
private func primaryText(_ v: VideoRecord, assay: StudyAssay, data: TaskDataModel) -> String {
    guard let s = data.summary(v, assay: assay), let e = s.entry(s.primaryKey), let value = e.value else { return "—" }
    let def = TaskMetricDef(e)
    return def.format(value)
}

@MainActor
private func primaryHelp(_ v: VideoRecord, assay: StudyAssay, data: TaskDataModel) -> String {
    guard let s = data.summary(v, assay: assay), let e = s.entry(s.primaryKey) else { return data.state(v, assay: assay).title }
    return TaskMetricDef(e).name
}

private func sexTitle(_ sex: String) -> String {
    switch sex {
    case "M": return L("Male", "雄")
    case "F": return L("Female", "雌")
    default: return sex.isEmpty ? "—" : sex
    }
}

/// Table of sessions used by the task, group and animal pages (≤ 10 columns).
private struct SessionTable: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel
    let experiment: NativeExperiment
    let sessions: [VideoRecord]
    var showAnimal = true
    var showGroup = true
    let onOpen: (SidebarItem) -> Void

    @State private var selection: Set<UUID> = []
    @State private var excludeTarget: Set<UUID> = []
    @State private var excludeReason = ""

    private var assay: StudyAssay { experiment.assay }

    var body: some View {
        Table(sessions, selection: $selection) {
            TableColumn(L("Animal", "小鼠")) { (v: VideoRecord) in Text(v.displayName) }
            TableColumn(L("Group", "分组")) { (v: VideoRecord) in Text(v.groupKey.isEmpty ? "—" : v.groupKey) }
            TableColumn(L("Date", "日期")) { (v: VideoRecord) in
                Text(SessionDate.isValid(v.sessionDate) ? (v.sessionDate ?? "") : L("missing", "缺少"))
                    .foregroundStyle(SessionDate.isValid(v.sessionDate) ? Color.primary : Color.orange)
            }
            TableColumn(L("Session", "实验次数")) { (v: VideoRecord) in
                Text(v.sessionNumber.map { "#\($0)" } ?? L("missing", "缺少"))
                    .monospacedDigit()
                    .foregroundStyle(v.sessionNumber == nil ? Color.orange : Color.primary)
            }
            TableColumn(L("Phase", "阶段")) { (v: VideoRecord) in
                let p = v.effectivePhase(for: assay)
                Text(p.isEmpty ? "—" : assay.phaseTitle(p))
            }
            TableColumn(L("Analysis", "分析")) { (v: VideoRecord) in
                let stage = v.stage(for: assay)
                Label(stage.title, systemImage: stage.symbol).foregroundStyle(stage.color)
            }
            TableColumn(L("Primary measure", "主要指标")) { (v: VideoRecord) in
                Text(primaryText(v, assay: assay, data: taskData))
                    .monospacedDigit()
                    .help(primaryHelp(v, assay: assay, data: taskData))
            }
            TableColumn(L("Tracking check", "追踪复核")) { (v: VideoRecord) in
                let verdict = v.reviewVerdict
                Label(verdict.title, systemImage: verdict.symbol)
                    .foregroundStyle(verdict == .passed ? Color.green : (verdict == .issues ? Color.orange : Color.secondary))
            }
            TableColumn(L("Included", "纳入")) { (v: VideoRecord) in
                if v.isExcluded {
                    Label(L("Excluded", "已排除"), systemImage: "minus.circle")
                        .foregroundStyle(.orange)
                        .help(v.exclusionReason ?? "")
                } else {
                    Label(L("Included", "纳入"), systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button(L("Open", "打开")) { if let id = ids.first { onOpen(.session(id)) } }
                .disabled(ids.count != 1)
            Divider()
            Button(L("Exclude from group summaries…", "排除出组间汇总…")) { excludeReason = ""; excludeTarget = ids }
                .disabled(ids.isEmpty)
            Button(L("Include in group summaries", "重新纳入组间汇总")) {
                for id in ids { store.setExcluded(id, excluded: false, reason: "") }
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            if let id = ids.first { onOpen(.session(id)) }
        }
        .alert(L("Exclude the selected sessions from group summaries?", "将所选实验排除出组间汇总？"),
               isPresented: Binding(get: { !excludeTarget.isEmpty }, set: { if !$0 { excludeTarget = [] } })) {
            TextField(L("Reason (exported)", "原因（会导出）"), text: $excludeReason)
            Button(L("Exclude", "排除")) {
                for id in excludeTarget { store.setExcluded(id, excluded: true, reason: excludeReason) }
                excludeTarget = []
            }
            Button(L("Cancel", "取消"), role: .cancel) { excludeTarget = [] }
        } message: {
            Text(L("Their own results are kept; they are left out of animal means, group statistics, comparisons and summary exports.",
                   "它们自己的结果仍保留；只是不进入小鼠均值、组统计、组间比较和汇总导出。"))
        }
    }
}

// MARK: - Task

enum TaskPageTab: String, CaseIterable, Identifiable {
    case sessions, compare, export
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sessions: return L("Sessions", "全部实验")
        case .compare: return L("Compare groups", "组间比较")
        case .export: return L("Export", "导出")
        }
    }
    var symbol: String {
        switch self {
        case .sessions: return "tablecells"
        case .compare: return "chart.bar.xaxis"
        case .export: return "square.and.arrow.up"
        }
    }
}

struct TaskOverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel
    @AppStorage("rd.taskTab") private var tabRaw = TaskPageTab.sessions.rawValue

    let experiment: NativeExperiment
    let onOpen: (SidebarItem) -> Void
    let onAddVideos: () -> Void
    let onEditNote: () -> Void

    private var tab: TaskPageTab { TaskPageTab(rawValue: tabRaw) ?? .sessions }
    private var sessions: [VideoRecord] { store.selectedProject?.orderedSessions(ofTask: experiment.id) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ComputeStatus(experiment: experiment)
            Picker(L("View", "视图"), selection: Binding(get: { tab.rawValue }, set: { tabRaw = $0 })) {
                ForEach(TaskPageTab.allCases) { t in Label(t.title, systemImage: t.symbol).tag(t.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 460)
            switch tab {
            case .sessions:
                if sessions.isEmpty {
                    ContentUnavailableView(L("No sessions yet", "还没有实验"), systemImage: "film.stack",
                                           description: Text(experiment.assay == .tstMultiChamber
                                               ? L("Add a TST recording with +, score the chambers, then assign each chamber to an animal, date and session number.",
                                                   "点 + 添加 TST 录像，完成多格分析后将各格关联到小鼠、日期和实验次数。")
                                               : L("Add videos with +: each video is one session of one animal (animal ID, date and session number are required).",
                                                   "点 + 添加视频：每段视频是一只小鼠的一次实验（必须填写小鼠编号、日期和实验次数）。")))
                } else {
                    SessionTable(experiment: experiment, sessions: sessions, onOpen: onOpen)
                    Text(L("Double-click a session to open it. Right-click to exclude sessions from group summaries (with a reason).",
                           "双击打开某次实验。右键可将实验排除出组间汇总（需填写原因）。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .compare:
                GroupComparisonView(experiment: experiment)
            case .export:
                ScrollView { DataExportPanel(experiment: experiment, group: nil).frame(maxWidth: 820, alignment: .leading) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TaskDataPreparer(experiment: experiment))
    }

    private var header: some View {
        let all = sessions
        let animals = Set(all.map(\.animalKey)).count
        let analysed = all.filter { $0.runState == .complete }.count
        let ready = all.filter { taskData.summary($0, assay: experiment.assay) != nil }.count
        let excluded = all.filter(\.isExcluded).count
        let missing = all.filter { !$0.hasSessionInfo }.count
        let groups = (store.selectedProject?.groups(ofTask: experiment.id) ?? []).filter { !$0.isEmpty }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: experiment.assay.symbol).foregroundStyle(Color.accentColor)
                Text(experiment.displayTitle).font(.title2.bold())
                Text(experiment.assay.moduleName + " · " + experiment.assay.methodCaption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    onEditNote()
                } label: {
                    Label(L("Edit note…", "编辑备注…"), systemImage: "note.text")
                }
                Button {
                    onAddVideos()
                } label: {
                    Label(experiment.assay == .tstMultiChamber
                          ? L("Add TST recording…", "添加 TST 录像…")
                          : L("Add videos…", "添加视频…"), systemImage: "plus")
                }
            }
            if experiment.hasNotes {
                Text(experiment.notes ?? "")
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                StatChip(title: L("Groups", "分组"), value: "\(groups)")
                StatChip(title: L("Animals", "小鼠"), value: "\(animals)")
                StatChip(title: L("Sessions", "实验"), value: "\(all.count)")
                StatChip(title: L("Analysed", "已分析"), value: "\(analysed)")
                StatChip(title: L("Results ready", "结果就绪"), value: "\(ready)")
                StatChip(title: L("Excluded", "已排除"), value: "\(excluded)", tint: excluded > 0 ? .orange : .primary)
                if missing > 0 {
                    StatChip(title: L("Missing info", "缺少信息"), value: "\(missing)", tint: .orange)
                }
            }
        }
    }
}

// MARK: - Group comparison

struct GroupComparisonView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel

    let experiment: NativeExperiment

    @State private var request = GroupAnalysisRequest()
    @State private var requestTask: UUID?
    @State private var showAnimals = false
    @State private var message = ""

    private var project: NativeProject? { store.selectedProject }
    private var records: [GroupRecord] {
        guard let project else { return [] }
        return taskData.records(task: experiment.id, project: project)
    }
    private var context: GroupAnalysisContext? {
        guard let project else { return nil }
        return taskData.context(task: experiment, project: project, phase: request.phaseFilter)
    }
    private var styles: [String: GroupStyle] { store.experiment(experiment.id)?.groupStyles ?? [:] }

    /// Groups present in the results, in the saved order (likely control first by default).
    private var allGroups: [String] {
        let present = GroupAnalysisEngine.orderedGroups(records)
        return present.enumerated().sorted { a, b in
            let oa = styles[a.element]?.order ?? (1000 + a.offset)
            let ob = styles[b.element]?.order ?? (1000 + b.offset)
            return oa < ob
        }.map(\.element)
    }

    private var includedGroups: [String] { allGroups.filter { styles[$0]?.included ?? true } }

    private var effectiveRequest: GroupAnalysisRequest {
        var r = request
        r.groups = includedGroups
        return r
    }

    private var colors: [String: Color] {
        var out: [String: Color] = [:]
        for (i, g) in allGroups.enumerated() { out[g] = GroupPalette.color(styles[g]?.colorIndex ?? i) }
        return out
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView(L("No results yet", "还没有结果"), systemImage: "chart.bar.xaxis",
                                       description: Text(L("Group comparisons use the results of analysed and calibrated sessions. They appear here as soon as the first session results are computed.",
                                                           "组间比较使用已分析并已标定的实验结果。一旦算出第一批实验结果就会显示在这里。")))
            } else if let context {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        controls(context)
                        let result = GroupAnalysisEngine.run(effectiveRequest, records: records, context: context)
                        resultView(result, context: context)
                        Text(L("Preliminary statistics for exploring the data: n = animals (sessions of an animal are averaged first), no correction across measures or across repeated looks at the data. Confirm with a pre-specified analysis before reporting.",
                               "用于初步查看数据的统计：n = 小鼠数（同一小鼠的多次实验先取平均），没有对多个指标或多次查看数据做校正。报告前请用预先设定的分析确认。"))
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        if !message.isEmpty {
                            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: 980, alignment: .leading)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear { resetIfNeeded() }
        .onChange(of: experiment.id) { _, _ in resetIfNeeded() }
        .onChange(of: records.count) { _, _ in resetIfNeeded() }
    }

    private func resetIfNeeded() {
        guard let context, !records.isEmpty else { return }
        let metrics = GroupAnalysisEngine.metricOptions(context, records: records)
        let valid = requestTask == experiment.id && metrics.contains { $0.key == request.metricKey }
        if !valid {
            request = GroupAnalysisEngine.defaultRequest(context, records: records)
            requestTask = experiment.id
        }
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ context: GroupAnalysisContext) -> some View {
        let designs = GroupAnalysisEngine.availableDesigns(context, records: records)
        let phases = GroupAnalysisEngine.phases(records, assayPhases: context.assayPhases)
        let sessionNumbers = GroupAnalysisEngine.sessions(records)
        FigureCard {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L("Design", "设计")).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Picker(L("Design", "设计"), selection: $request.design) {
                            ForEach(designs) { d in Text(d.displayName).tag(d) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                        Text(request.design.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
                measureRow(context)
                if request.design == .phaseChange {
                    GridRow {
                        Text(L("Phases", "阶段")).foregroundStyle(.secondary)
                        HStack {
                            phasePicker(phases, selection: $request.phaseB, context: context)
                            Text("−")
                            phasePicker(phases, selection: $request.phaseA, context: context)
                        }
                    }
                } else if !phases.isEmpty && (!context.assayPhases.isEmpty || phases.count >= 2) {
                    GridRow {
                        Text(L("Phase", "阶段")).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Picker(L("Phase", "阶段"), selection: $request.phaseFilter) {
                                ForEach(phases, id: \.self) { p in Text(context.phaseTitle(p, english: false)).tag(Optional(p)) }
                                Text(L("All phases pooled", "全部阶段合并")).tag(String?.none)
                            }
                            .labelsHidden()
                            .frame(maxWidth: 260)
                            if request.phaseFilter == nil && phases.count >= 2 {
                                Text(L("Different phases are pooled: usually not meaningful (e.g. training and test).", "不同阶段被合并：通常没有意义（如训练和测试）。"))
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                if request.design != .bySession && sessionNumbers.count >= 2 {
                    GridRow {
                        Text(L("Session", "实验次数")).foregroundStyle(.secondary)
                        Picker(L("Session", "实验次数"), selection: $request.sessionFilter) {
                            Text(L("All sessions (averaged per animal)", "全部实验（按小鼠取平均）")).tag(Int?.none)
                            ForEach(sessionNumbers, id: \.self) { n in Text(String(format: L("Session %d only", "仅第 %d 次"), n)).tag(Optional(n)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
                GridRow {
                    Text(L("Statistics", "统计")).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Picker(L("Statistics", "统计"), selection: $request.mode) {
                            ForEach(StatMode.allCases) { m in Text(m.displayName).tag(m) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)
                        if includedGroups.count >= 3 || (includedGroups.count >= 2 && [.bySession, .byDay, .withinSession].contains(request.design)) {
                            Picker(L("Comparisons", "比较方式"), selection: $request.comparison) {
                                ForEach(ComparisonMode.allCases) { c in Text(c.displayName).tag(c) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 200)
                        }
                    }
                }
                GridRow {
                    Text(L("Options", "选项")).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Toggle(L("Include excluded sessions", "包含已排除的实验"), isOn: $request.includeExcluded)
                        if chanceAvailable(context) && [.betweenGroups].contains(request.design) {
                            Toggle(L("Test each group against the reference value", "各组与参考值比较"), isOn: $request.testAgainstChance)
                        }
                        if [.bySession, .byDay, .withinSession].contains(request.design) {
                            Toggle(L("Show individual animals", "显示每只小鼠"), isOn: $showAnimals)
                        }
                    }
                }
            }
            groupEditor
        }
    }

    @ViewBuilder
    private func measureRow(_ context: GroupAnalysisContext) -> some View {
        switch request.design {
        case .withinSession:
            let options = GroupAnalysisEngine.seriesOptions(records)
            GridRow {
                Text(L("Series", "序列")).foregroundStyle(.secondary)
                Picker(L("Series", "序列"), selection: $request.seriesKey) {
                    ForEach(options) { o in Text(o.name).tag(o.key) }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        case .pairedMeasures:
            GridRow {
                Text(L("Pair", "配对")).foregroundStyle(.secondary)
                Picker(L("Pair", "配对"), selection: $request.pairKey) {
                    ForEach(context.pairs) { p in Text(p.title(english: false)).tag(p.key) }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        default:
            let metrics = GroupAnalysisEngine.metricOptions(context, records: records)
            GridRow {
                Text(L("Measure", "指标")).foregroundStyle(.secondary)
                Picker(L("Measure", "指标"), selection: $request.metricKey) {
                    ForEach(metrics) { m in Text(m.axisTitle).tag(m.key) }
                }
                .labelsHidden()
                .frame(maxWidth: 360)
            }
        }
    }

    private func phasePicker(_ phases: [String], selection: Binding<String>, context: GroupAnalysisContext) -> some View {
        Picker("", selection: selection) {
            ForEach(phases, id: \.self) { p in Text(context.phaseTitle(p, english: false)).tag(p) }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
    }

    private func chanceAvailable(_ context: GroupAnalysisContext) -> Bool {
        context.defs.first { $0.key == request.metricKey }?.chance != nil
    }

    // MARK: Groups (order, inclusion, color)

    private var groupEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Groups (the first included group is the control for “vs. first group”)", "分组（第一个纳入的组作为“与第一组比较”的对照）"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(allGroups.enumerated()), id: \.element) { item in
                groupRow(item.element, index: item.offset)
            }
        }
    }

    private func groupRow(_ g: String, index: Int) -> some View {
        let included = styles[g]?.included ?? true
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { included }, set: { setIncluded(g, $0) })).labelsHidden()
            Menu {
                ForEach(0..<GroupPalette.count, id: \.self) { c in
                    Button {
                        setColor(g, c)
                    } label: {
                        Label(String(format: L("Color %d", "颜色 %d"), c + 1), systemImage: "circle.fill")
                    }
                }
            } label: {
                Circle().fill(colors[g] ?? .gray).frame(width: 12, height: 12)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help(L("Color of this group", "该组的颜色"))
            Text(groupDisplayName(g)).foregroundStyle(included ? Color.primary : Color.secondary)
            let n = Set(records.filter { $0.displayGroup == g && (request.includeExcluded || !$0.excluded) }.map(\.subjectKey)).count
            Text(String(format: L("%d animals with results", "%d 只小鼠有结果"), n)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { move(g, by: -1) } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.borderless).disabled(index == 0)
            Button { move(g, by: 1) } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.borderless).disabled(index == allGroups.count - 1)
        }
        .frame(maxWidth: 520)
    }

    private func currentStyles() -> [String: GroupStyle] {
        var out = styles
        for (i, g) in allGroups.enumerated() {
            var s = out[g] ?? GroupStyle(order: i, colorIndex: i, included: true)
            s.order = i
            out[g] = s
        }
        return out
    }

    private func setIncluded(_ g: String, _ on: Bool) {
        var s = currentStyles()
        s[g]?.included = on
        store.updateGroupStyles(experiment.id, s)
    }

    private func setColor(_ g: String, _ c: Int) {
        var s = currentStyles()
        s[g]?.colorIndex = c
        store.updateGroupStyles(experiment.id, s)
    }

    private func move(_ g: String, by delta: Int) {
        var order = allGroups
        guard let i = order.firstIndex(of: g) else { return }
        let j = i + delta
        guard j >= 0 && j < order.count else { return }
        order.swapAt(i, j)
        var s = currentStyles()
        for (k, name) in order.enumerated() { s[name]?.order = k }
        store.updateGroupStyles(experiment.id, s)
    }

    // MARK: Result

    @ViewBuilder
    private func resultView(_ result: GroupAnalysisResult, context: GroupAnalysisContext) -> some View {
        if result.isEmpty {
            RPBanner(text: L("No animal has a value for this choice (measure, phase, session, groups).", "按当前选择（指标、阶段、实验次数、分组）没有小鼠有数值。"), style: .warning)
            ForEach(result.notes, id: \.self) { n in RPBanner(text: n, style: .info) }
        } else {
            GroupFigureView(result: result, colors: colors, title: result.metricName,
                            subtitle: subtitle(result), showAnimals: showAnimals)
            descriptivesCard(result)
            testsCard(result)
            ForEach(result.notes, id: \.self) { n in RPBanner(text: n, style: .info) }
            HStack {
                Button(L("Export this comparison…", "导出该比较…")) { export(context: context) }
                    .buttonStyle(.borderedProminent)
                Text(L("Figure (PNG), summary (TXT), full result (JSON) and animal values (CSV), in English.", "图（PNG）、摘要（TXT）、完整结果（JSON）和每只小鼠的数值（CSV），英文。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ r: GroupAnalysisResult) -> String {
        var parts: [String] = [r.request.design.displayName]
        if let p = r.request.phaseFilter, r.request.design != .phaseChange {
            parts.append(p.isEmpty ? L("No phase", "无阶段") : experiment.assay.phaseTitle(p))
        }
        if let s = r.request.sessionFilter, r.request.design != .bySession { parts.append(String(format: L("session %d", "第 %d 次"), s)) }
        parts.append(String(format: L("n = %d animals", "n = %d 只小鼠"), r.animalCount))
        return parts.joined(separator: " · ")
    }

    private func descriptivesCard(_ r: GroupAnalysisResult) -> some View {
        FigureCard {
            FigureCardHeader(r.request.design == .pairedMeasures ? L("Differences per group", "各组差值")
                                                                 : L("Descriptive statistics", "描述统计"), symbol: "list.number")
            Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(L("Group", "分组")).gridColumnAlignment(.leading)
                    Text("n")
                    Text(L("Mean", "均值"))
                    Text("SEM")
                    Text("SD")
                    Text(L("Median", "中位数"))
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(r.groups, id: \.self) { g in
                    let d = r.descriptives[g] ?? .empty
                    GridRow {
                        HStack(spacing: 5) {
                            Circle().fill(colors[g] ?? .gray).frame(width: 8, height: 8)
                            Text(groupDisplayName(g))
                        }
                        .gridColumnAlignment(.leading)
                        Text("\(d.n)")
                        Text(StatsFormat.number(d.mean))
                        Text(d.n >= 2 ? StatsFormat.number(d.sem) : "—")
                        Text(d.n >= 2 ? StatsFormat.number(d.sd) : "—")
                        Text(StatsFormat.number(d.median))
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    private func testsCard(_ r: GroupAnalysisResult) -> some View {
        FigureCard {
            FigureCardHeader(L("Tests", "检验"), symbol: "function", subtitle: r.report.methodSummary)
            if let o = r.report.omnibus {
                Text("\(o.name): \(o.reportLine)").monospacedDigit().textSelection(.enabled)
            }
            if let m = r.report.mixed {
                if let g = m.group { Text(L("Group: ", "组：") + g.reportLine).monospacedDigit() }
                Text((r.levelLabel.isEmpty ? L("Within animal", "组内") : r.levelLabel) + ": " + m.level.reportLine).monospacedDigit()
                if let i = m.interaction { Text(L("Interaction: ", "交互作用：") + i.reportLine).monospacedDigit() }
                Text(String(format: L("Greenhouse–Geisser ε = %@ · animals used %d (left out %d)", "Greenhouse–Geisser ε = %@ · 使用 %d 只小鼠（排除 %d 只）"),
                            StatsFormat.number(m.epsilonGG), m.subjectsUsed, m.subjectsDropped))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !r.report.pairwise.isEmpty {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text(L("Comparison", "比较")).gridColumnAlignment(.leading)
                        Text(L("Difference", "差值"))
                        Text(L("Statistic", "统计量"))
                        Text("p")
                        Text(L("p adjusted", "校正 p"))
                        Text("")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(r.report.pairwise) { c in
                        GridRow {
                            Text("\(groupDisplayName(c.groupA)) vs \(groupDisplayName(c.groupB))" + (c.level.map { " · \($0)" } ?? ""))
                                .gridColumnAlignment(.leading)
                            Text(StatsFormat.number(c.difference))
                            Text("\(c.statisticName) = \(StatsFormat.number(c.statistic))")
                            Text(StatsFormat.p(c.p))
                            Text(StatsFormat.p(c.pAdjusted))
                            Text(StatsFormat.stars(c.pAdjusted)).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                        .font(.callout)
                    }
                }
            }
            if !r.report.perGroup.isEmpty {
                ForEach(r.report.perGroup.keys.sorted(), id: \.self) { g in
                    if let t = r.report.perGroup[g] {
                        Text("\(groupDisplayName(g)) (\(r.report.perGroupLabel)): \(t.name), \(t.reportLine)").monospacedDigit()
                    }
                }
            }
            if r.report.omnibus == nil && r.report.mixed == nil && r.report.pairwise.isEmpty && r.report.perGroup.isEmpty {
                Text(L("No test for this choice.", "此选择下没有检验。")).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Export

    private func export(context: GroupAnalysisContext) {
        guard let project else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here", "导出到此处")
        panel.message = L("A new folder with this comparison is created inside the chosen folder.", "将在所选文件夹中新建一个文件夹，存放该比较。")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let access = parent.startAccessingSecurityScopedResource()
        defer { if access { parent.stopAccessingSecurityScopedResource() } }
        do {
            // Exports are always English (names of measures, phases, groups, tests and notes).
            let englishContext = taskData.context(task: experiment, project: project, phase: effectiveRequest.phaseFilter)
            let result = GroupAnalysisEngine.run(effectiveRequest, records: records, context: englishContext, english: true)
            let folder = try GroupComparisonExport.write(result, taskName: experiment.assay.name, context: englishContext,
                                                         colors: colors, records: records, to: parent)
            message = String(format: L("Exported to %@", "已导出到 %@"), folder.path)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            message = L("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }
}

/// Files of one group comparison (English).
enum GroupComparisonExport {
    @MainActor
    static func write(_ r: GroupAnalysisResult, taskName: String, context: GroupAnalysisContext, colors: [String: Color],
                      records: [GroupRecord], to parent: URL) throws -> URL {
        let slug = FigureExport.slug(r.metricName)
        let folder = try ExportFolder.make(in: parent, name: taskName + "_" + slug, suffix: "comparison")
        let summary = GroupAnalysisEngine.summaryText(r, taskName: taskName, context: context)
        try FigureExport.writeText(summary + "\n", to: folder.appendingPathComponent("comparison_summary.txt"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(r).write(to: folder.appendingPathComponent("comparison_result.json"), options: .atomic)

        var lines: [String] = []
        switch r.request.design {
        case .betweenGroups, .phaseChange:
            lines.append("group,animal_id,value,sessions_averaged")
            for p in r.points {
                lines.append([FigureExport.csv(p.group), FigureExport.csv(p.subject), String(format: "%.6g", p.value), String(p.records)].joined(separator: ","))
            }
        case .byDay, .bySession, .withinSession:
            lines.append("group,animal_id,level,value")
            for s in r.subjectSeries {
                for (j, v) in s.values.enumerated() {
                    guard let v, j < r.levels.count else { continue }
                    lines.append([FigureExport.csv(s.group), FigureExport.csv(s.subject), String(format: "%.6g", r.levels[j]), String(format: "%.6g", v)].joined(separator: ","))
                }
            }
        case .pairedMeasures:
            lines.append("group,animal_id,\(FigureExport.csv(r.pairLabelA)),\(FigureExport.csv(r.pairLabelB)),difference")
            for p in r.paired {
                lines.append([FigureExport.csv(p.group), FigureExport.csv(p.subject), String(format: "%.6g", p.a), String(format: "%.6g", p.b), String(format: "%.6g", p.a - p.b)].joined(separator: ","))
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("comparison_animal_values.csv"))

        var sub: [String] = [r.request.design.rawValue.replacingOccurrences(of: "_", with: " ")]
        if let p = r.request.phaseFilter, r.request.design != .phaseChange { sub.append("phase: \(p)") }
        if let s = r.request.sessionFilter, r.request.design != .bySession { sub.append("session \(s)") }
        sub.append("n = \(r.animalCount) animals")
        let figure = GroupFigureView(result: r, colors: colors, title: r.metricName, subtitle: sub.joined(separator: " · "))
        try FigureExport.writePNG(figure, to: folder.appendingPathComponent("comparison_figure.png"), width: 520)
        return folder
    }
}

// MARK: - Export panel (task level or group level)

struct DataExportPanel: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel

    let experiment: NativeExperiment
    /// nil = task level; a group label ("" = ungrouped) = group level.
    let group: String?

    @State private var message = ""
    @State private var frameProgress: Double?

    private var sessions: [VideoRecord] {
        let all = store.selectedProject?.orderedSessions(ofTask: experiment.id) ?? []
        guard let group else { return all }
        return all.filter { $0.groupKey == group }
    }

    var body: some View {
        let all = sessions
        let analysed = all.filter { $0.runState == .complete }
        let ready = all.filter { taskData.summary($0, assay: experiment.assay) != nil }
        let pending = analysed.count - ready.count
        FigureCard {
            FigureCardHeader(group == nil ? L("Task-level export", "任务级导出") : L("Group-level export", "组级导出"),
                             symbol: "square.and.arrow.up",
                             subtitle: group == nil
                                ? L("Every session of this task, every animal and every group, in English, with the original IDs.", "该任务的全部实验、全部小鼠和全部分组，英文，保留原始编号。")
                                : L("The sessions and animals of this group, in English, with the original IDs.", "该组的实验和小鼠，英文，保留原始编号。"))
            VStack(alignment: .leading, spacing: 4) {
                fileLine("sessions.csv", L("one row per session: animal, group, sex, date, session number, phase, exclusion, status, tracking check, QC", "每次实验一行：小鼠、分组、性别、日期、实验次数、阶段、排除、状态、追踪复核、质控"))
                fileLine("metrics_long.csv / metrics_wide.csv", L("every measure of every session with results", "每次有结果的实验的全部指标"))
                fileLine("animals.csv", L("per animal and phase: mean of its included sessions (n = animals)", "每只小鼠每个阶段：其纳入实验的均值（n = 小鼠数）"))
                fileLine("group_summary.csv", L("per phase, group and measure: n, mean, SD, SEM, median, quartiles, range", "每个阶段、分组和指标：n、均值、SD、SEM、中位数、四分位数、范围"))
                fileLine("README_methods.txt", L("how the numbers were obtained, counts, exclusions", "数值如何得到、计数、排除情况"))
                if experiment.assay == .tstMultiChamber {
                    Divider().padding(.vertical, 2)
                    ForEach(TSTExport.files.indices, id: \.self) { i in
                        let file = TSTExport.files[i]
                        fileLine(file.0, L(file.1, file.2))
                    }
                }
            }
            if pending > 0 || taskData.progress != nil {
                Label(String(format: L("Results of %d analysed session(s) are still being computed; wait for them or they are listed without values.",
                                       "还有 %d 次已分析实验的结果正在计算；请等待，否则它们将无数值。"), max(pending, 0)),
                      systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(String(format: L("%d sessions · %d analysed · %d with results · %d excluded", "%d 次实验 · 已分析 %d · 有结果 %d · 已排除 %d"),
                        all.count, analysed.count, ready.count, all.filter(\.isExcluded).count))
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(group == nil ? L("Export task data…", "导出任务数据…") : L("Export group data…", "导出组数据…")) { export() }
                    .buttonStyle(.borderedProminent)
                    .disabled(all.isEmpty)
                if experiment.assay == .tstMultiChamber {
                    Button(L("Export TST data only (JSON + CSV)…", "仅导出 TST 数据（JSON + CSV）…")) { export(tstOnly: true) }
                        .disabled(analysed.isEmpty)
                        .help(L("Only the tst_* files above, in a new folder.", "只导出上面的 tst_* 文件，放在新文件夹中。"))
                }
            }
            if experiment.assay != .tstMultiChamber {
                Divider().padding(.vertical, 4)
                Text(L("Frame-by-frame tracking (DeepLabCut-style)", "逐帧追踪数据（DeepLabCut 格式）")).font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(FrameDataExport.fileNotes.indices, id: \.self) { i in
                        let file = FrameDataExport.fileNotes[i]
                        fileLine(file.0, L(file.1, file.2))
                    }
                }
                HStack(spacing: 10) {
                    Button(L("Export frame data…", "导出逐帧数据…")) { exportFrames() }
                        .disabled(analysed.isEmpty || frameProgress != nil)
                    if let p = frameProgress {
                        ProgressView(value: p).frame(width: 160)
                        Text(String(format: "%.0f %%", 100 * p)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Text(L("Large: about 1 MB per minute of video per session.", "文件较大：每次实验每分钟视频约 1 MB。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if group == nil {
                Text(L("Group comparisons with tests are exported from “Compare groups”, where the measure, phase, session and test are chosen.",
                       "带检验的组间比较在“组间比较”中导出（在那里选择指标、阶段、实验次数和检验）。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func fileLine(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.callout.monospaced())
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Frame-by-frame tracking of every analysed session; written in the background (files can be large).
    private func exportFrames() {
        let jobs = FrameDataExport.jobs(experiment: experiment, sessions: sessions, store: store)
        guard !jobs.isEmpty else {
            message = L("No analysed session with tracking to export.", "没有可导出追踪数据的已分析实验。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here", "导出到此处")
        panel.message = L("A new folder is created inside the chosen folder.", "将在所选文件夹中新建一个文件夹。")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let label = group.map { $0.isEmpty ? GroupRecord.ungroupedLabel : $0 }
        let name = experiment.name + (label.map { "_" + $0 } ?? "")
        let taskName = experiment.name, taskID = experiment.id.uuidString
        frameProgress = 0
        message = ""
        Task { @MainActor in
            let access = parent.startAccessingSecurityScopedResource()
            defer { if access { parent.stopAccessingSecurityScopedResource() } }
            do {
                let folder = try ExportFolder.make(in: parent, name: name, suffix: "frames")
                let result = try await Task.detached(priority: .userInitiated) { () throws -> [FrameExportSummary] in
                    try FrameDataExport.write(jobs: jobs, task: taskName, taskID: taskID, to: folder) { p in
                        Task { @MainActor in frameProgress = p }
                    }
                }.value
                let failed = result.filter { $0.error != nil }.count
                frameProgress = nil
                message = String(format: L("Exported the frames of %d sessions to %@", "已导出 %d 次实验的逐帧数据到 %@"),
                                 result.count - failed, folder.path)
                    + (failed > 0 ? String(format: L(" (%d could not be read; see frames_index.csv)", "（%d 次无法读取，见 frames_index.csv）"), failed) : "")
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                frameProgress = nil
                message = L("Export failed: ", "导出失败：") + error.localizedDescription
            }
        }
    }

    private func export(tstOnly: Bool = false) {
        guard let project = store.selectedProject else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here", "导出到此处")
        panel.message = L("A new folder is created inside the chosen folder.", "将在所选文件夹中新建一个文件夹。")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let access = parent.startAccessingSecurityScopedResource()
        defer { if access { parent.stopAccessingSecurityScopedResource() } }
        do {
            let folder: URL
            if tstOnly {
                let label = group.map { $0.isEmpty ? GroupRecord.ungroupedLabel : $0 }
                folder = try ExportFolder.make(in: parent, name: experiment.name + (label.map { "_" + $0 } ?? ""), suffix: "tst_export")
                let doc = try TSTExport.write(experiment: experiment, sessions: sessions, group: label, to: folder)
                message = String(format: L("Exported %d sessions to %@", "已导出 %d 次实验到 %@"), doc.sessions.count, folder.path)
            } else {
                folder = try TaskDataExport.write(experiment: experiment, project: project, group: group, data: taskData, to: parent)
                message = String(format: L("Exported to %@", "已导出到 %@"), folder.path)
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            message = L("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }
}

// MARK: - Group

struct GroupOverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel
    @AppStorage("rd.taskTab") private var taskTabRaw = TaskPageTab.sessions.rawValue

    let experiment: NativeExperiment
    let group: String
    let onOpen: (SidebarItem) -> Void
    let onAddVideos: () -> Void

    @State private var newName = ""
    @State private var phase: String?

    private var project: NativeProject? { store.selectedProject }
    private var sessions: [VideoRecord] { project?.orderedSessions(ofTask: experiment.id).filter { $0.groupKey == group } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ComputeStatus(experiment: experiment)
                animalsCard
                summaryCard
                if !sessions.isEmpty {
                    FigureCard {
                        FigureCardHeader(L("Sessions of this group", "该组的全部实验"), symbol: "tablecells")
                        SessionTable(experiment: experiment, sessions: sessions, showGroup: false, onOpen: onOpen)
                            .frame(minHeight: 220)
                    }
                }
                DataExportPanel(experiment: experiment, group: group)
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(18)
        }
        .background(TaskDataPreparer(experiment: experiment))
        .onAppear { newName = group }
        .onChange(of: group) { _, g in newName = g }
    }

    private var header: some View {
        let animals = project?.animals(ofTask: experiment.id, group: group) ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(group.isEmpty ? L("Ungrouped", "未分组") : group).font(.title2.bold())
                Text(experiment.assay.displayName).foregroundStyle(.secondary)
                Spacer()
                Button {
                    taskTabRaw = TaskPageTab.compare.rawValue
                    onOpen(.task(experiment.id))
                } label: {
                    Label(L("Compare groups", "组间比较"), systemImage: "chart.bar.xaxis")
                }
                Button {
                    onAddVideos()
                } label: {
                    Label(L("Add videos…", "添加视频…"), systemImage: "plus")
                }
            }
            HStack(spacing: 8) {
                StatChip(title: L("Animals", "小鼠"), value: "\(animals.count)")
                StatChip(title: L("Sessions", "实验"), value: "\(sessions.count)")
                StatChip(title: L("Results ready", "结果就绪"), value: "\(sessions.filter { taskData.summary($0, assay: experiment.assay) != nil }.count)")
                StatChip(title: L("Excluded", "已排除"), value: "\(sessions.filter(\.isExcluded).count)")
            }
            HStack(spacing: 8) {
                TextField(L("Group name", "组名"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Button(L("Rename group", "重命名分组")) {
                    let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.renameGroup(task: experiment.id, from: group, to: target)
                    onOpen(.group(experiment.id, target))
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines) == group)
                Text(L("Applies to every animal of this group in this task.", "应用于此任务中该组的所有小鼠。")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var animalsCard: some View {
        let animals = project?.animals(ofTask: experiment.id, group: group) ?? []
        return FigureCard {
            FigureCardHeader(L("Animals", "小鼠"), symbol: "pawprint")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text(L("Animal", "小鼠"))
                    Text(L("Sex", "性别"))
                    Text(L("Sessions", "实验次数"))
                    Text(L("Analysed", "已分析"))
                    Text(L("Checked", "已复核"))
                    Text(L("Excluded", "已排除"))
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(animals, id: \.self) { key in
                    let mine = sessions.filter { $0.animalKey == key }
                    GridRow {
                        Button(mine.first?.displayName ?? key) { onOpen(.animal(experiment.id, key)) }
                            .buttonStyle(.link)
                        Text(sexTitle(mine.first?.sex ?? ""))
                        Text(mine.compactMap(\.sessionNumber).sorted().map { "#\($0)" }.joined(separator: " "))
                        Text("\(mine.filter { $0.runState == .complete }.count)/\(mine.count)")
                        Text("\(mine.filter { $0.reviewVerdict != .unreviewed }.count)")
                        Text("\(mine.filter(\.isExcluded).count)")
                    }
                    .monospacedDigit()
                }
            }
        }
    }

    /// Animal means of the included sessions, per phase (descriptive only).
    private var summaryCard: some View {
        let summaries: [UUID: SessionMetricSummary] = {
            var out: [UUID: SessionMetricSummary] = [:]
            for v in sessions { if let s = taskData.summary(v, assay: experiment.assay) { out[v.id] = s } }
            return out
        }()
        let rows = TaskDataExport.animalRows(sessions: sessions, summaries: summaries)
        let phases = Array(Set(rows.map(\.phase))).sorted { a, b in
            let order = experiment.assay.phaseOptions.map(\.key)
            return (order.firstIndex(of: a) ?? 99, a) < (order.firstIndex(of: b) ?? 99, b)
        }
        let chosen = phase.flatMap { p in phases.contains(p) ? p : nil } ?? phases.first
        let defs = TaskMetricDefinitions.defs(Array(summaries.values), preferredPhase: chosen)
        let members = rows.filter { $0.phase == chosen }
        return FigureCard {
            FigureCardHeader(L("Summary of this group", "该组汇总"), symbol: "sum",
                             subtitle: L("Mean of each animal's included sessions, then n = animals. Descriptive only; tests are in Compare groups.",
                                         "先计算每只小鼠纳入实验的均值，n = 小鼠数。仅描述统计；检验见“组间比较”。"))
            if phases.count > 1 {
                Picker(L("Phase", "阶段"), selection: Binding(get: { chosen ?? "" }, set: { phase = $0 })) {
                    ForEach(phases, id: \.self) { p in Text(p.isEmpty ? L("No phase", "无阶段") : experiment.assay.phaseTitle(p)).tag(p) }
                }
                .frame(maxWidth: 280)
            }
            if members.isEmpty {
                Text(L("No results yet.", "还没有结果。")).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 5) {
                    GridRow {
                        Text(L("Measure", "指标")).gridColumnAlignment(.leading)
                        Text("n")
                        Text(L("Mean ± SEM", "均值 ± SEM"))
                        Text(L("Median", "中位数"))
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(defs) { d in
                        let values = members.compactMap { $0.values[d.key] }
                        if !values.isEmpty {
                            let s = Stats.describe(values)
                            GridRow {
                                Text(d.axisTitle).gridColumnAlignment(.leading)
                                Text("\(s.n)")
                                Text(s.n >= 2 ? "\(StatsFormat.number(s.mean)) ± \(StatsFormat.number(s.sem))" : StatsFormat.number(s.mean))
                                Text(StatsFormat.number(s.median))
                            }
                            .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Animal

struct AnimalOverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var taskData: TaskDataModel

    let experiment: NativeExperiment
    let animalKey: String
    let onOpen: (SidebarItem) -> Void
    let onAddVideos: () -> Void

    @State private var newID = ""
    @State private var group = ""
    @State private var sex = ""
    @State private var metricKey = ""

    private var project: NativeProject? { store.selectedProject }
    private var sessions: [VideoRecord] {
        (project?.sessions(ofTask: experiment.id, animal: animalKey) ?? []).sorted(by: VideoRecord.sessionOrder)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                identityCard
                FigureCard {
                    FigureCardHeader(L("Sessions", "各次实验"), symbol: "calendar")
                    SessionTable(experiment: experiment, sessions: sessions, showAnimal: false, onOpen: onOpen)
                        .frame(minHeight: 180)
                }
                valuesCard
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(18)
        }
        .background(TaskDataPreparer(experiment: experiment))
        .onAppear(perform: syncFields)
        .onChange(of: animalKey) { _, _ in syncFields() }
    }

    private func syncFields() {
        let first = sessions.first
        newID = first?.animalID ?? animalKey
        group = first?.groupKey ?? ""
        sex = first?.sex ?? ""
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "pawprint").foregroundStyle(.secondary)
            Text(sessions.first?.displayName ?? animalKey).font(.title2.bold())
            Text(experiment.assay.displayName).foregroundStyle(.secondary)
            Spacer()
            Button {
                onAddVideos()
            } label: {
                Label(L("Add a session…", "添加一次实验…"), systemImage: "plus")
            }
        }
    }

    private var identityCard: some View {
        FigureCard {
            FigureCardHeader(L("Animal", "小鼠"), symbol: "person.text.rectangle",
                             subtitle: L("Animal ID, group and sex apply to every session of this animal in this task.", "小鼠编号、分组和性别应用于该小鼠在此任务中的所有实验。"))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(L("Animal ID", "小鼠编号")).foregroundStyle(.secondary)
                    HStack {
                        TextField(L("Animal ID", "小鼠编号"), text: $newID).textFieldStyle(.roundedBorder).frame(width: 180)
                        Button(L("Rename", "重命名")) { rename() }
                            .disabled(newID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || newID.trimmingCharacters(in: .whitespacesAndNewlines) == animalKey)
                    }
                }
                GridRow {
                    Text(L("Group", "分组")).foregroundStyle(.secondary)
                    HStack {
                        TextField(L("Group (optional)", "分组（可选）"), text: $group).textFieldStyle(.roundedBorder).frame(width: 180)
                        if experiment.assay.usesSex {
                            Picker(L("Sex", "性别"), selection: $sex) {
                                Text("—").tag("")
                                Text(L("Male", "雄")).tag("M")
                                Text(L("Female", "雌")).tag("F")
                            }
                            .frame(width: 160)
                        }
                        Button(L("Apply", "应用")) {
                            store.setAnimalAttributes(task: experiment.id, animal: animalKey, group: group, sex: sex)
                        }
                        .disabled(group.trimmingCharacters(in: .whitespacesAndNewlines) == (sessions.first?.groupKey ?? "") && sex == (sessions.first?.sex ?? ""))
                    }
                }
            }
        }
    }

    private func rename() {
        let target = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = store.renameAnimal(task: experiment.id, from: animalKey, to: target) {
            store.notice = problem
        } else {
            onOpen(.animal(experiment.id, target))
        }
    }

    private struct SessionValue {
        let number: Int
        let value: Double
        let excluded: Bool
        let label: String
    }

    /// One measure across the sessions of the animal.
    private var valuesCard: some View {
        var ready: [VideoRecord] = []
        var summaries: [SessionMetricSummary] = []
        for v in sessions {
            if let s = taskData.summary(v, assay: experiment.assay) {
                ready.append(v)
                summaries.append(s)
            }
        }
        let defs = TaskMetricDefinitions.defs(summaries, preferredPhase: nil)
        let key = defs.contains(where: { $0.key == metricKey }) ? metricKey : (summaries.first?.primaryKey ?? defs.first?.key ?? "")
        let def = defs.first(where: { $0.key == key })
        var points: [SessionValue] = []
        for (v, s) in zip(ready, summaries) {
            if let n = v.sessionNumber, let value = s.value(key) {
                points.append(SessionValue(number: n, value: value, excluded: v.isExcluded, label: v.sessionTitle))
            }
        }
        return FigureCard {
            FigureCardHeader(L("Across sessions", "跨实验次数"), symbol: "chart.xyaxis.line",
                             subtitle: L("Values of one measure in each session of this animal (excluded sessions in gray).", "该小鼠每次实验中某一指标的数值（已排除的实验为灰色）。"))
            if defs.isEmpty {
                Text(L("No results yet.", "还没有结果。")).foregroundStyle(.secondary)
            } else {
                Picker(L("Measure", "指标"), selection: Binding(get: { key }, set: { metricKey = $0 })) {
                    ForEach(defs) { d in Text(d.axisTitle).tag(d.key) }
                }
                .frame(maxWidth: 380)
                if points.count >= 1 {
                    Chart {
                        ForEach(Array(points.enumerated()), id: \.offset) { item in
                            LineMark(x: .value(L("Session", "实验次数"), item.element.number), y: .value(def?.axisTitle ?? key, item.element.value))
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                            PointMark(x: .value(L("Session", "实验次数"), item.element.number), y: .value(def?.axisTitle ?? key, item.element.value))
                                .foregroundStyle(item.element.excluded ? Color.gray : Color.accentColor)
                                .symbolSize(50)
                        }
                    }
                    .chartXAxisLabel(L("Session number", "实验次数"))
                    .chartYAxisLabel(def?.axisTitle ?? key)
                    .frame(height: 220)
                    ForEach(Array(points.enumerated()), id: \.offset) { item in
                        HStack {
                            Text(item.element.label).monospacedDigit()
                            Spacer()
                            Text(def.map { $0.format(item.element.value) } ?? StatsFormat.number(item.element.value))
                                .monospacedDigit()
                                .foregroundStyle(item.element.excluded ? Color.secondary : Color.primary)
                        }
                        .frame(maxWidth: 420)
                    }
                }
            }
        }
    }
}
