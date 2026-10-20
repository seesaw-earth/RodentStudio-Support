// ImportVideosSheet.swift — adding videos to a task. Every video is one session of one animal, so the
// animal ID, the recording date and the session number (实验次数) are required before importing. Group and
// sex belong to the animal: for an animal that already has sessions in this task they are taken from it.

import SwiftUI
import AppKit

struct ImportVideosSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss

    let experiment: NativeExperiment
    let urls: [URL]
    var presetAnimal: String? = nil
    var presetGroup: String? = nil
    let onImported: ([UUID]) -> Void

    struct Row: Identifiable {
        let id = UUID()
        let url: URL
        var animalID: String
        var group: String
        var sex: String
        var date: Date
        var dateNote: String
        var session: Int
        var sessionEdited = false
        var phase: String
    }

    @State private var rows: [Row] = []
    @State private var importing = false
    @State private var groupForAll = ""

    private var assay: StudyAssay { experiment.assay }
    private var project: NativeProject? { store.selectedProject }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L("Add %d videos to %@", "向“%2$@”添加 %1$d 个视频"), urls.count, assay.displayName))
                    .font(.title3.bold())
                Text(L("Each video is one session of one animal. Animal ID, date and session number are required. Group and sex belong to the animal; for an animal that already has sessions in this task they are taken from those.",
                       "每段视频是一只小鼠的一次实验。小鼠编号、日期和实验次数必须填写。分组和性别属于小鼠；该任务中已有实验的小鼠沿用已有的分组和性别。"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text(L("Video", "视频"))
                        Text(L("Animal ID *", "小鼠编号 *"))
                        Text(L("Group", "分组"))
                        if assay.usesSex { Text(L("Sex", "性别")) }
                        Text(L("Date *", "日期 *"))
                        Text(L("Session # *", "实验次数 *"))
                        if !assay.phaseOptions.isEmpty { Text(L("Phase", "阶段")) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(rows.indices, id: \.self) { i in
                        rowView(i)
                        let issues = problems(i)
                        if !issues.isEmpty || !rows[i].dateNote.isEmpty {
                            GridRow {
                                Color.clear.frame(width: 1, height: 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(issues, id: \.self) { t in
                                        Label(t, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
                                    }
                                    if !rows[i].dateNote.isEmpty {
                                        Label(rows[i].dateNote, systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
                                    }
                                }
                                .font(.caption)
                                .gridCellColumns(6)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 160, maxHeight: 420)
            HStack(spacing: 10) {
                TextField(L("Group for new animals", "新小鼠的分组"), text: $groupForAll)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button(L("Apply", "应用")) { applyGroupToAll() }
                    .disabled(groupForAll.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(L("Use the first date for all", "全部使用第一行的日期")) { applyFirstDate() }
                    .disabled(rows.count < 2)
                Spacer()
                Button(L("Cancel", "取消"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(importing ? L("Importing…", "正在导入…") : String(format: L("Import %d", "导入 %d 个"), rows.count)) { importAll() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(importing || rows.isEmpty || hasProblems)
            }
            if hasProblems {
                Text(L("Fix the marked rows to import.", "请先修正标红的行。")).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 860)
        .onAppear(perform: prepare)
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ i: Int) -> some View {
        let existing = existingAttributes(i)
        GridRow {
            Text(rows[i].url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 200, alignment: .leading)
                .help(rows[i].url.path)
            TextField(L("e.g. M01", "如 M01"), text: Binding(get: { rows[i].animalID }, set: { setAnimal(i, $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            if let existing {
                Label(existing.group.isEmpty ? L("No group", "无分组") : existing.group, systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.secondary)
                    .help(L("This animal already has sessions in this task; its group is kept.", "该小鼠在此任务中已有实验，沿用其分组。"))
                    .frame(width: 120, alignment: .leading)
            } else {
                TextField(L("e.g. WT", "如 WT"), text: $rows[i].group)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            if assay.usesSex {
                if let existing {
                    Text(existing.sex.isEmpty ? "—" : existing.sex).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                } else {
                    Picker("", selection: $rows[i].sex) {
                        Text("—").tag("")
                        Text(L("Male", "雄")).tag("M")
                        Text(L("Female", "雌")).tag("F")
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }
            }
            DatePicker("", selection: Binding(get: { rows[i].date }, set: { rows[i].date = $0; rows[i].dateNote = "" }),
                       displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: 120)
            Stepper(value: Binding(get: { rows[i].session }, set: { rows[i].session = max(1, $0); rows[i].sessionEdited = true }), in: 1...9999) {
                Text("#\(rows[i].session)").monospacedDigit().frame(width: 44, alignment: .leading)
            }
            if !assay.phaseOptions.isEmpty {
                let options = assay.phaseOptions
                Picker("", selection: $rows[i].phase) {
                    ForEach(options.indices, id: \.self) { k in
                        Text(options[k].title).tag(options[k].key)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private func existingAttributes(_ i: Int) -> (group: String, sex: String)? {
        let key = rows[i].animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return project?.animalAttributes(task: experiment.id, animal: key)
    }

    private func setAnimal(_ i: Int, _ value: String) {
        rows[i].animalID = value
        if !rows[i].sessionEdited { renumber() }
    }

    /// Default session numbers: the next free number of each animal, counting earlier rows of the list.
    private func renumber() {
        var taken: [String: [Int]] = [:]
        for i in rows.indices {
            let key = rows[i].animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            if !rows[i].sessionEdited {
                rows[i].session = project?.nextSessionNumber(task: experiment.id, animal: key, alsoTaken: taken[key] ?? []) ?? 1
            }
            taken[key, default: []].append(rows[i].session)
        }
    }

    private func problems(_ i: Int) -> [String] {
        var out: [String] = []
        let row = rows[i]
        let animal = row.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        if animal.isEmpty { out.append(L("Animal ID is required.", "必须填写小鼠编号。")) }
        if row.session < 1 { out.append(L("Session number must be at least 1.", "实验次数至少为 1。")) }
        guard !animal.isEmpty else { return out }
        if let conflict = project?.sessionConflict(task: experiment.id, animal: animal, number: row.session, excluding: nil) {
            out.append(String(format: L("%@ already has session #%d in this task (%@).", "%@ 在此任务中已有第 %d 次实验（%@）。"),
                              animal, row.session, conflict.fileName))
        }
        let twice = rows.indices.contains { j in
            j != i && rows[j].animalID.trimmingCharacters(in: .whitespacesAndNewlines) == animal && rows[j].session == row.session
        }
        if twice { out.append(L("The same animal and session number appear twice in this list.", "列表中同一小鼠的实验次数重复。")) }
        return out
    }

    private var hasProblems: Bool { rows.indices.contains { !problems($0).isEmpty } }

    private func applyGroupToAll() {
        let g = groupForAll.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in rows.indices where existingAttributes(i) == nil { rows[i].group = g }
    }

    private func applyFirstDate() {
        guard let first = rows.first?.date else { return }
        for i in rows.indices {
            rows[i].date = first
            rows[i].dateNote = ""
        }
    }

    // MARK: Prepare / import

    private func prepare() {
        guard rows.isEmpty else { return }
        var made: [Row] = []
        for url in urls {
            let stem = url.deletingPathExtension().lastPathComponent
            var date = Date()
            var note = L("Date not found in the file name or file; set it.", "文件名和文件中没有日期，请填写。")
            if let text = SessionDate.fromFileName(stem), let d = SessionDate.date(text) {
                date = d
                note = ""
            } else if let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate {
                date = created
                note = L("Date taken from the file's creation date; check it.", "日期取自文件创建日期，请核对。")
            }
            let animal = presetAnimal ?? Self.animalGuess(stem)
            made.append(Row(url: url, animalID: animal, group: presetGroup ?? "", sex: "",
                            date: date, dateNote: note, session: 1, phase: assay.defaultPhase))
        }
        rows = made
        renumber()
    }

    /// The file name without a date in it (RodentLimb uses the file name as the starting animal ID).
    static func animalGuess(_ stem: String) -> String {
        var s = stem
        if let date = SessionDate.fromFileName(stem) {
            let variants = [date, date.replacingOccurrences(of: "-", with: ""), date.replacingOccurrences(of: "-", with: "_"),
                            date.replacingOccurrences(of: "-", with: ".")]
            for v in variants { s = s.replacingOccurrences(of: v, with: "") }
        }
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: " _-."))
        return trimmed.isEmpty ? stem : trimmed
    }

    private func importAll() {
        guard !hasProblems else { return }
        var items: [VideoImportItem] = []
        for i in rows.indices {
            let row = rows[i]
            let animal = row.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = existingAttributes(i)
            items.append(VideoImportItem(url: row.url, animalID: animal,
                                         group: existing?.group ?? row.group,
                                         sex: existing?.sex ?? row.sex,
                                         sessionDate: SessionDate.string(row.date),
                                         sessionNumber: row.session,
                                         phase: row.phase))
        }
        importing = true
        let expID = experiment.id
        Task { @MainActor in
            let ids = await store.addVideos(items, experimentID: expID)
            importing = false
            onImported(ids)
            dismiss()
        }
    }
}
