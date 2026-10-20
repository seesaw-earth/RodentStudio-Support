// TaskDataExport.swift — task-level and group-level data exports (English, original identifiers).
//
// Data processing (see DATA_PROCESSING_CN.md):
//   1. Session level: each session's measures come from its own Results (original analyzer, the session's
//      calibration, analysis window, phase and parameters). All sessions are listed, excluded ones too.
//   2. Animal level: within one phase, the included sessions of an animal are averaged (n = animals).
//      Excluded sessions are left out. Phases are never pooled.
//   3. Group level: descriptive statistics of the animal values, per phase, group and measure.
//   Group comparisons with tests are exported from the "Compare groups" page (they depend on the choices
//   made there: measure, phase, session, design, test family).

import Foundation

/// New export folder "<name>_<stamp>" inside a chosen folder (never overwrites an existing folder).
enum ExportFolder {
    static func make(in parent: URL, name: String, suffix: String = "results") throws -> URL {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        let safe = name.components(separatedBy: bad).filter { !$0.isEmpty }.joined(separator: "_")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = (safe.isEmpty ? "export" : safe) + "_" + suffix + "_" + f.string(from: Date())
        var url = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent(base + "_\(n)", isDirectory: true)
            n += 1
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

/// Animal values of one phase: included sessions averaged within the animal.
struct AnimalPhaseRow {
    var animalID: String
    var animalKey: String
    var group: String
    var sex: String
    var phase: String
    var sessionCount: Int
    var sessionNumbers: [Int]
    var dates: [String]
    var values: [String: Double]
    var counts: [String: Int]
}

@MainActor
enum TaskDataExport {
    static func statusValue(_ state: SessionDataState) -> String {
        switch state {
        case .ready: return "results_ready"
        case .computing, .waiting: return "results_pending"
        case .notAnalysed: return "not_analysed"
        case .needsCalibration: return "needs_calibration"
        case .failed: return "results_failed"
        }
    }

    /// Animal × phase means of the included sessions (excluded sessions are left out).
    static func animalRows(sessions: [VideoRecord], summaries: [UUID: SessionMetricSummary]) -> [AnimalPhaseRow] {
        var order: [String] = []
        var rows: [String: AnimalPhaseRow] = [:]
        var sums: [String: [String: Double]] = [:]
        for v in sessions where !v.isExcluded {
            guard let s = summaries[v.id] else { continue }
            let id = v.groupKey + "|" + v.animalKey + "|" + s.phase
            if rows[id] == nil {
                rows[id] = AnimalPhaseRow(animalID: v.animalID, animalKey: v.animalKey, group: v.groupKey, sex: v.sex ?? "",
                                          phase: s.phase, sessionCount: 0, sessionNumbers: [], dates: [], values: [:], counts: [:])
                order.append(id)
            }
            rows[id]?.sessionCount += 1
            if let n = v.sessionNumber { rows[id]?.sessionNumbers.append(n) }
            if let d = v.sessionDate { rows[id]?.dates.append(d) }
            for (k, value) in s.values {
                sums[id, default: [:]][k, default: 0] += value
                rows[id]?.counts[k, default: 0] += 1
            }
        }
        var out: [AnimalPhaseRow] = []
        for id in order {
            guard var row = rows[id] else { continue }
            for (k, total) in sums[id] ?? [:] {
                let n = row.counts[k] ?? 0
                if n > 0 { row.values[k] = total / Double(n) }
            }
            out.append(row)
        }
        return out
    }

    // MARK: Write

    /// Writes the task-level (group == nil) or group-level export. Returns the new folder.
    static func write(experiment: NativeExperiment, project: NativeProject, group: String?, data: TaskDataModel,
                      to parent: URL) throws -> URL {
        let assay = experiment.assay
        let allSessions = project.orderedSessions(ofTask: experiment.id)
        let sessions = group.map { g in allSessions.filter { $0.groupKey == g } } ?? allSessions
        var summaries: [UUID: SessionMetricSummary] = [:]
        for v in sessions {
            if let s = data.summary(v, assay: assay) { summaries[v.id] = s }
        }
        let defs = TaskMetricDefinitions.defs(Array(summaries.values), preferredPhase: nil)
        let groupName = group.map { $0.isEmpty ? GroupRecord.ungroupedLabel : $0 }
        let folderName = experiment.name + (groupName.map { "_" + $0 } ?? "")
        let folder = try ExportFolder.make(in: parent, name: folderName, suffix: group == nil ? "task_export" : "group_export")

        try writeSessions(sessions, summaries: summaries, assay: assay, data: data, project: project,
                          to: folder.appendingPathComponent("sessions.csv"))
        try writeMetricsLong(sessions, summaries: summaries, assay: assay, to: folder.appendingPathComponent("metrics_long.csv"))
        try writeMetricsWide(sessions, summaries: summaries, assay: assay, defs: defs, to: folder.appendingPathComponent("metrics_wide.csv"))
        if summaries.values.contains(where: { !$0.series.isEmpty }) {
            try writeSeriesLong(sessions, summaries: summaries, to: folder.appendingPathComponent("timecourse_long.csv"))
        }
        let animals = animalRows(sessions: sessions, summaries: summaries)
        try writeAnimals(animals, assay: assay, defs: defs, to: folder.appendingPathComponent("animals.csv"))
        try writeGroupSummary(animals, assay: assay, defs: defs, groupOrder: project.groups(ofTask: experiment.id),
                              to: folder.appendingPathComponent("group_summary.csv"))
        if assay == .tstMultiChamber {
            // TST-specific files: timing from each suspension, every window, bouts, method — see TSTExport.
            try TSTExport.write(experiment: experiment, sessions: sessions, group: groupName, to: folder)
        }
        let methods = methodsText(experiment: experiment, project: project, group: groupName, sessions: sessions,
                                  summaries: summaries, animals: animals)
        try FigureExport.writeText(methods, to: folder.appendingPathComponent("README_methods.txt"))
        return folder
    }

    private static func csvRow(_ fields: [String]) -> String {
        fields.map { FigureExport.csv($0) }.joined(separator: ",")
    }

    private static func number(_ v: Double?, _ decimals: Int) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(max(decimals, 3))f", v)
    }

    private static func writeSessions(_ sessions: [VideoRecord], summaries: [UUID: SessionMetricSummary], assay: StudyAssay,
                                      data: TaskDataModel, project: NativeProject, to url: URL) throws {
        var lines: [String] = []
        lines.append(csvRow(["task_id", "task", "animal_id", "group", "sex", "session_date", "session_number", "phase", "day", "trial",
                             "excluded", "exclusion_reason", "results_status", "tracking_check", "tracking_check_flagged",
                             "qc_flags", "analysis_window", "primary_metric", "primary_value", "video_file", "run_folder", "notes"]))
        for v in sessions {
            let s = summaries[v.id]
            let primary = s.flatMap { $0.entry($0.primaryKey) }
            var row: [String] = []
            row.append(assay.rawValue)
            row.append(assay.name)
            row.append(v.animalID)
            row.append(v.groupKey)
            row.append(v.sex ?? "")
            row.append(v.sessionDate ?? "")
            row.append(v.sessionNumber.map { String($0) } ?? "")
            row.append(v.effectivePhase(for: assay))
            row.append(v.day.map { String($0) } ?? "")
            row.append(v.trial.map { String($0) } ?? "")
            row.append(v.isExcluded ? "yes" : "no")
            row.append(v.exclusionReason ?? "")
            row.append(statusValue(data.state(v, assay: assay)))
            row.append(v.reviewVerdict.exportValue)
            row.append(String(v.currentReview?.flagged.count ?? 0))
            row.append(s?.qcFlags.joined(separator: " | ") ?? "")
            row.append(SessionResultsEngine.englishWindow(SessionResultsEngine.analysisWindow(v, assay: assay)))
            row.append(primary.map { $0.unitEN.isEmpty ? $0.nameEN : "\($0.nameEN) (\($0.unitEN))" } ?? "")
            row.append(number(primary?.value, primary?.decimals ?? 3))
            row.append(v.fileName)
            row.append(v.runFolder ?? "")
            row.append(v.notes ?? "")
            lines.append(csvRow(row))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func writeMetricsLong(_ sessions: [VideoRecord], summaries: [UUID: SessionMetricSummary], assay: StudyAssay, to url: URL) throws {
        var lines: [String] = []
        lines.append(csvRow(["animal_id", "group", "sex", "session_date", "session_number", "phase", "day", "trial", "excluded",
                             "metric_key", "metric", "unit", "value", "primary"]))
        for v in sessions {
            guard let s = summaries[v.id] else { continue }
            for m in s.metrics {
                var row: [String] = []
                row.append(v.animalID)
                row.append(v.groupKey)
                row.append(v.sex ?? "")
                row.append(v.sessionDate ?? "")
                row.append(v.sessionNumber.map { String($0) } ?? "")
                row.append(s.phase)
                row.append(v.day.map { String($0) } ?? "")
                row.append(v.trial.map { String($0) } ?? "")
                row.append(v.isExcluded ? "yes" : "no")
                row.append(m.key)
                row.append(m.nameEN)
                row.append(m.unitEN)
                row.append(number(m.value, m.decimals))
                row.append(m.key == s.primaryKey ? "1" : "0")
                lines.append(csvRow(row))
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    /// Time courses (e.g. TST immobility per minute after suspension) in long format: one row per session
    /// and time bin, ready for a repeated-measures / mixed-model analysis (animal as the repeated unit).
    private static func writeSeriesLong(_ sessions: [VideoRecord], summaries: [UUID: SessionMetricSummary], to url: URL) throws {
        var lines: [String] = []
        lines.append(csvRow(["animal_id", "group", "sex", "session_date", "session_number", "phase", "excluded",
                             "series_key", "series", "x_label", "x", "value", "unit"]))
        for v in sessions {
            guard let s = summaries[v.id] else { continue }
            for series in s.series {
                // Summaries computed by an earlier build may hold translated TST labels: always write English.
                let tst = series.key == TSTSessionMetrics.seriesKey
                let name = tst ? TSTSessionMetrics.seriesName : series.name
                let xLabel = tst ? TSTSessionMetrics.seriesXLabel : series.xLabel
                let unit = tst ? "s" : series.unit
                for (x, y) in zip(series.x, series.y) where x.isFinite && y.isFinite {
                    lines.append(csvRow([v.animalID, v.groupKey, v.sex ?? "", v.sessionDate ?? "",
                                         v.sessionNumber.map { String($0) } ?? "", s.phase, v.isExcluded ? "yes" : "no",
                                         series.key, name, xLabel,
                                         String(format: "%g", x), String(format: "%.4f", y), unit]))
                }
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func header(_ d: TaskMetricDef) -> String {
        (d.unit.isEmpty ? d.nameEN : "\(d.nameEN) (\(d.unit))") + " [\(d.key)]"
    }

    private static func writeMetricsWide(_ sessions: [VideoRecord], summaries: [UUID: SessionMetricSummary], assay: StudyAssay,
                                         defs: [TaskMetricDef], to url: URL) throws {
        var lines: [String] = []
        var head = ["animal_id", "group", "sex", "session_date", "session_number", "phase", "day", "trial", "excluded"]
        head.append(contentsOf: defs.map { header($0) })
        lines.append(csvRow(head))
        for v in sessions {
            guard let s = summaries[v.id] else { continue }
            let values = s.values
            var row: [String] = [v.animalID, v.groupKey, v.sex ?? "", v.sessionDate ?? "", v.sessionNumber.map { String($0) } ?? "",
                                 s.phase, v.day.map { String($0) } ?? "", v.trial.map { String($0) } ?? "", v.isExcluded ? "yes" : "no"]
            for d in defs { row.append(number(values[d.key], d.decimals)) }
            lines.append(csvRow(row))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func writeAnimals(_ animals: [AnimalPhaseRow], assay: StudyAssay, defs: [TaskMetricDef], to url: URL) throws {
        var lines: [String] = []
        var head = ["animal_id", "group", "sex", "phase", "n_sessions_included", "session_numbers", "session_dates"]
        head.append(contentsOf: defs.map { header($0) })
        lines.append(csvRow(head))
        for a in animals {
            let numbers = a.sessionNumbers.sorted().map { String($0) }.joined(separator: " ")
            let dates = a.dates.sorted().joined(separator: " ")
            var row: [String] = [a.animalID.isEmpty ? a.animalKey : a.animalID, a.group, a.sex, a.phase,
                                 String(a.sessionCount), numbers, dates]
            for d in defs { row.append(number(a.values[d.key], d.decimals)) }
            lines.append(csvRow(row))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func writeGroupSummary(_ animals: [AnimalPhaseRow], assay: StudyAssay, defs: [TaskMetricDef],
                                          groupOrder: [String], to url: URL) throws {
        var lines: [String] = []
        lines.append(csvRow(["phase", "group", "metric_key", "metric", "unit", "n_animals", "mean", "sd", "sem", "median", "q1", "q3", "min", "max"]))
        var phases: [String] = []
        for p in assay.phaseOptions.map(\.key) where animals.contains(where: { $0.phase == p }) { phases.append(p) }
        for a in animals where !phases.contains(a.phase) { phases.append(a.phase) }
        for phase in phases {
            for g in groupOrder {
                let members = animals.filter { $0.phase == phase && $0.group == g }
                guard !members.isEmpty else { continue }
                for d in defs {
                    let values = members.compactMap { $0.values[d.key] }
                    guard !values.isEmpty else { continue }
                    let s = Stats.describe(values)
                    var row: [String] = [phase, g.isEmpty ? GroupRecord.ungroupedLabel : g, d.key, d.nameEN, d.unit, String(s.n)]
                    row.append(number(s.mean, d.decimals))
                    row.append(s.n >= 2 ? number(s.sd, d.decimals) : "")
                    row.append(s.n >= 2 ? number(s.sem, d.decimals) : "")
                    row.append(number(s.median, d.decimals))
                    row.append(number(s.q1, d.decimals))
                    row.append(number(s.q3, d.decimals))
                    row.append(number(s.min, d.decimals))
                    row.append(number(s.max, d.decimals))
                    lines.append(csvRow(row))
                }
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func methodsText(experiment: NativeExperiment, project: NativeProject, group: String?, sessions: [VideoRecord],
                                    summaries: [UUID: SessionMetricSummary], animals: [AnimalPhaseRow]) -> String {
        let assay = experiment.assay
        let ready = sessions.filter { summaries[$0.id] != nil }
        let excluded = ready.filter(\.isExcluded)
        let missingInfo = sessions.filter { !$0.hasSessionInfo }
        let flagged = ready.filter { $0.reviewVerdict == .issues }
        let unchecked = ready.filter { $0.reviewVerdict == .unreviewed }
        let animalCount = Set(sessions.map(\.animalKey)).count
        let stamp = ISO8601DateFormatter().string(from: Date())
        var t: [String] = []
        t.append("\(AppInfo.label) — \(group == nil ? "task-level" : "group-level") data export")
        t.append("Generated: \(stamp)")
        t.append("Project: \(project.name)")
        t.append("Task: \(assay.name) (\(assay.rawValue)); experiment name: \(experiment.name)")
        if let group { t.append("Group: \(group)") }
        t.append("")
        t.append("Contents")
        t.append("  sessions.csv       one row per session (video): animal, group, sex, recording date, session number, phase, exclusion, results status, tracking check, QC flags, analysis window, primary measure.")
        t.append("  metrics_long.csv   one row per session and measure (all sessions with results, excluded sessions marked).")
        t.append("  metrics_wide.csv   one row per session, one column per measure.")
        t.append("  animals.csv        one row per animal and phase: mean of the animal's included sessions of that phase.")
        t.append("  group_summary.csv  per phase, group and measure: descriptive statistics of the animal values (n = animals).")
        t.append("")
        t.append("Data processing")
        t.append("  1. Session values are the results of the task's original analyzer (\(assay.moduleName) port) computed from the saved tracking with the calibration, analysis window, phase and parameters saved for that session — the same numbers as its Results page and its single-session export.")
        t.append("  2. Excluded sessions are listed in sessions.csv and metrics_*.csv but left out of animals.csv and group_summary.csv.")
        t.append("  3. Within one phase, the included sessions of an animal are averaged before group statistics, so n = animals, not sessions or frames. Different phases are never pooled.")
        t.append("  4. Group statistics are descriptive only. Hypothesis tests are exported from the Compare groups page, where the measure, phase, session number, design and test family are chosen; they are preliminary, uncorrected across measures, and must be confirmed with a pre-specified analysis.")
        t.append("  5. Sessions without results (not analysed, not calibrated, or failed) are listed in sessions.csv with their status and contribute no values.")
        t.append("")
        t.append("Counts")
        t.append("  Sessions: \(sessions.count) (with results: \(ready.count); excluded: \(excluded.count); missing animal/date/session number: \(missingInfo.count))")
        t.append("  Animals: \(animalCount); animal × phase rows: \(animals.count)")
        t.append("  Tracking check: \(flagged.count) session(s) with tracking problems, \(unchecked.count) not checked.")
        if !excluded.isEmpty {
            t.append("")
            t.append("Excluded sessions")
            for v in excluded {
                t.append("  \(v.animalID) \(v.sessionDate ?? "") #\(v.sessionNumber.map { String($0) } ?? "?"): \(v.exclusionReason ?? "no reason given")")
            }
        }
        let multiGroup = Dictionary(grouping: sessions, by: \.animalKey).filter { Set($0.value.map(\.groupKey)).count > 1 }
        if !multiGroup.isEmpty {
            t.append("")
            t.append("Warning: animal ID(s) with sessions in more than one group: \(multiGroup.keys.sorted().joined(separator: ", ")). Check the group labels.")
        }
        t.append("")
        t.append("Desktop port of the original analyzers; parity with the iOS apps has not been validated. Compare with manual scoring before reporting.")
        return t.joined(separator: "\n") + "\n"
    }
}

// MARK: - Frame-by-frame tracking export (DeepLabCut-style)
//
// For every analysed session of a task, the raw tracking of every frame, in English:
//  · RodentPose / RodentLimb (Core ML keypoints):
//      <session>_DLC.csv     DeepLabCut layout — 3 header rows (scorer / bodyparts / coords) and one row per
//                            frame: x, y, likelihood of each keypoint. Readable by DLC analysis tools,
//                            SimBA, B-SOiD, keypoint-MoSeq … (pandas: read_csv(header=[0,1,2], index_col=0)).
//      <session>_frames.csv  the same frames with time and QC columns: video time, time from the first
//                            tracked frame, video frame number, analysis-window flag, detection / box
//                            confidence, inference failure, then <keypoint>_x / _y / _likelihood.
//  · RodentFlow (classic centroid tracker, 10 Hz): <session>_centroid.csv (image px and normalised, arena
//    normalised and cm, confidence, interpolated, zone, motion index, blob area), the centroid as a one-
//    bodypart DLC file, and <session>_maze_events.csv when the run has maze events.
//  · frames_index.csv / frames_metadata.json: which file belongs to which animal / group / session, model,
//    keypoint names, frame size, fps, analysis window, coordinate conventions and column definitions.
// Coordinates are pixels of the upright (rotation-corrected) video frame, origin top-left, as in DLC.
// Missing keypoints are empty cells with likelihood 0. Excluded sessions are exported and flagged.

struct FrameExportJob: Sendable {
    enum Source: Sendable { case keypoints(URL), centroid(URL) }
    var source: Source
    var base: String
    var sessionID: String
    var animalID: String
    var group: String
    var sex: String
    var sessionDate: String
    var sessionNumber: String
    var phase: String
    var excluded: Bool
    var exclusionReason: String
    var trackingCheck: String
    var videoFile: String
    var videoWidth: Int
    var videoHeight: Int
    var videoFPS: Double
    var windowStart: Double
    var windowLength: Double
}

struct FrameExportSummary: Sendable {
    var job: FrameExportJob
    var files: [String] = []
    var tracker = ""
    var bodyparts: [String] = []
    var frames = 0
    var detectedFrames = 0
    var firstVideoTime: Double?
    var error: String?
}

enum FrameDataExport {
    static let fileNotes: [(String, String, String)] = [
        ("frames/<session>_DLC.csv", "DeepLabCut layout: x, y, likelihood of every keypoint in every frame",
         "DeepLabCut 格式：每帧每个关键点的 x、y、likelihood"),
        ("frames/<session>_frames.csv", "the same frames with video time, frame number, analysis-window flag and QC columns",
         "同样的帧，另含视频时间、帧号、分析时间窗标记和质控列"),
        ("frames/<session>_centroid.csv", "RodentFlow tasks: centroid per 10 Hz sample (px, cm, zone, motion index)",
         "RodentFlow 任务：每个 10 Hz 采样的质心（像素、厘米、区域、运动指数）"),
        ("frames_index.csv / frames_metadata.json", "which file belongs to which animal and session; model, keypoints, frame size, fps, column definitions",
         "每个文件对应的小鼠和实验；模型、关键点、画面尺寸、帧率、列定义"),
    ]

    /// Sessions with a finished run, as plain values that a background task can process.
    @MainActor
    static func jobs(experiment: NativeExperiment, sessions: [VideoRecord], store: WorkspaceStore) -> [FrameExportJob] {
        let assay = experiment.assay
        var used = Set<String>()
        var out: [FrameExportJob] = []
        for v in sessions where v.runState == .complete && v.tstChamber == nil {
            guard let folder = store.runFolderURL(v) else { continue }
            let source: FrameExportJob.Source
            switch assay.module {
            case .pose?, .limb?: source = .keypoints(folder)
            case .flow?: source = .centroid(folder)
            case nil: continue
            }
            var base = safe([v.animalID.isEmpty ? "animal" : v.animalID, v.sessionDate ?? "nodate",
                             "S" + (v.sessionNumber.map { String($0) } ?? "x")].joined(separator: "_"))
            if used.contains(base) { base += "_" + String(v.id.uuidString.prefix(8)) }
            used.insert(base)
            let w = SessionResultsEngine.analysisWindow(v, assay: assay)
            out.append(FrameExportJob(source: source, base: base, sessionID: v.id.uuidString, animalID: v.animalID,
                                      group: v.groupKey, sex: v.sex ?? "", sessionDate: v.sessionDate ?? "",
                                      sessionNumber: v.sessionNumber.map { String($0) } ?? "",
                                      phase: v.effectivePhase(for: assay), excluded: v.isExcluded,
                                      exclusionReason: v.exclusionReason ?? "", trackingCheck: v.reviewVerdict.exportValue,
                                      videoFile: v.fileName, videoWidth: v.videoWidth, videoHeight: v.videoHeight,
                                      videoFPS: v.framesPerSecond, windowStart: w.start, windowLength: w.length))
        }
        return out
    }

    private static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        let parts = s.components(separatedBy: bad).filter { !$0.isEmpty }
        return parts.isEmpty ? "session" : parts.joined(separator: "_")
    }

    // MARK: Writing (background)

    /// Writes everything into `folder`. Call from a background task; `progress` gets the fraction done.
    static func write(jobs: [FrameExportJob], task: String, taskID: String, to folder: URL,
                      progress: @escaping @Sendable (Double) -> Void) throws -> [FrameExportSummary] {
        let frames = folder.appendingPathComponent("frames", isDirectory: true)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        var summaries: [FrameExportSummary] = []
        for (i, job) in jobs.enumerated() {
            var s = FrameExportSummary(job: job)
            do {
                switch job.source {
                case .keypoints(let run): try writeKeypoints(job, run: run, to: frames, summary: &s)
                case .centroid(let run): try writeCentroid(job, run: run, to: frames, summary: &s)
                }
            } catch {
                s.error = error.localizedDescription
            }
            summaries.append(s)
            progress(Double(i + 1) / Double(max(1, jobs.count)))
        }
        try writeIndex(summaries, to: folder.appendingPathComponent("frames_index.csv"))
        try writeMetadata(summaries, task: task, taskID: taskID, to: folder.appendingPathComponent("frames_metadata.json"))
        return summaries
    }

    /// Buffered text output (files can have millions of lines).
    private final class Output {
        let handle: FileHandle
        var buffer = ""
        init(_ url: URL) throws {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }
        func line(_ s: String) throws {
            buffer += s
            buffer += "\n"
            if buffer.utf8.count > 1_000_000 { try flush() }
        }
        func flush() throws { try handle.write(contentsOf: Data(buffer.utf8)); buffer = "" }
        func close() throws { try flush(); try handle.close() }
    }

    private static func csv(_ fields: [String]) -> String { fields.map { FigureExport.csv($0) }.joined(separator: ",") }

    private static func inWindow(_ t: Double, _ job: FrameExportJob) -> Bool {
        t >= job.windowStart - 1e-9 && (job.windowLength <= 0 || t < job.windowStart + job.windowLength)
    }

    private static func writeKeypoints(_ job: FrameExportJob, run: URL, to dir: URL, summary s: inout FrameExportSummary) throws {
        let manifest = try JSONDecoder().decode(LongVideoManifest.self,
                                                from: Data(contentsOf: run.appendingPathComponent(LongVideoTrackingEngine.manifestName)))
        let segments = manifest.completed.sorted { $0.index < $1.index }
        guard let first = segments.first else { throw CocoaError(.fileReadCorruptFile) }
        // Keypoint names from the segment header (<name>_x, <name>_y, <name>_conf).
        let firstText = try String(contentsOf: run.appendingPathComponent(first.file), encoding: .utf8)
        guard let headerLine = firstText.split(whereSeparator: \.isNewline).first else { throw CocoaError(.fileReadCorruptFile) }
        let header = headerLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var parts: [(name: String, col: Int)] = []
        for (i, h) in header.enumerated() where h.hasSuffix("_x") && i + 2 < header.count
            && header[i + 1] == String(h.dropLast(2)) + "_y" && header[i + 2] == String(h.dropLast(2)) + "_conf" {
            parts.append((String(h.dropLast(2)), i))
        }
        guard !parts.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let failedCol = header.firstIndex(of: "inference_failed")
        let scorer = "RodentStudio_" + manifest.modelName
        s.tracker = manifest.modelName
        s.bodyparts = parts.map(\.name)

        let dlcName = job.base + "_DLC.csv", framesName = job.base + "_frames.csv"
        let dlc = try Output(dir.appendingPathComponent(dlcName))
        let wide = try Output(dir.appendingPathComponent(framesName))
        try dlc.line(csv(["scorer"] + Array(repeating: scorer, count: parts.count * 3)))
        try dlc.line(csv(["bodyparts"] + parts.flatMap { [$0.name, $0.name, $0.name] }))
        try dlc.line(csv(["coords"] + parts.flatMap { _ in ["x", "y", "likelihood"] }))
        try wide.line(csv(["frame", "video_frame", "video_time_s", "time_from_first_frame_s", "in_analysis_window",
                           "detected", "box_confidence", "inference_failed"]
                          + parts.flatMap { ["\($0.name)_x", "\($0.name)_y", "\($0.name)_likelihood"] }))
        let origin = first.firstPTS
        let fps = job.videoFPS > 0 ? job.videoFPS : 0
        var frame = 0
        for segment in segments {
            let text = segment.index == first.index ? firstText
                : try String(contentsOf: run.appendingPathComponent(segment.file), encoding: .utf8)
            for line in text.split(whereSeparator: \.isNewline).dropFirst() {
                let c = line.split(separator: ",", omittingEmptySubsequences: false)
                guard c.count >= 4, let pts = Double(c[1]) else { continue }
                let failed = failedCol.map { $0 < c.count && c[$0] == "1" } ?? false
                let detected = !failed && c[2] == "1"
                let t = pts - origin
                var dlcRow = [String(frame)]
                var wideRow = [String(frame), fps > 0 ? String(Int((pts * fps).rounded())) : "",
                               String(format: "%.6f", pts), String(format: "%.6f", t), inWindow(t, job) ? "1" : "0",
                               detected ? "1" : "0", String(c[3]), failed ? "1" : "0"]
                for p in parts {
                    let x = p.col < c.count ? Double(c[p.col]) : nil
                    let y = p.col + 1 < c.count ? Double(c[p.col + 1]) : nil
                    let conf = p.col + 2 < c.count ? (Double(c[p.col + 2]) ?? 0) : 0
                    if let x, let y, x.isFinite, y.isFinite, x >= 0, y >= 0, !failed {
                        let cells = [String(format: "%.3f", x), String(format: "%.3f", y), String(format: "%.5f", conf)]
                        dlcRow += cells; wideRow += cells
                    } else {
                        dlcRow += ["", "", "0"]; wideRow += ["", "", "0"]
                    }
                }
                try dlc.line(dlcRow.joined(separator: ","))
                try wide.line(wideRow.joined(separator: ","))
                if s.firstVideoTime == nil { s.firstVideoTime = pts }
                if detected { s.detectedFrames += 1 }
                frame += 1
            }
        }
        try dlc.close()
        try wide.close()
        s.frames = frame
        s.files = ["frames/" + dlcName, "frames/" + framesName]
    }

    private static func writeCentroid(_ job: FrameExportJob, run: URL, to dir: URL, summary s: inout FrameExportSummary) throws {
        let saved = try FlowDesktopRun.load(from: run)
        s.tracker = String(format: "RodentFlow classic centroid tracker (%.0f Hz)", saved.analysisHz)
        s.bodyparts = ["centroid"]
        let name = job.base + "_centroid.csv", dlcName = job.base + "_DLC.csv"
        let out = try Output(dir.appendingPathComponent(name))
        let dlc = try Output(dir.appendingPathComponent(dlcName))
        try out.line(csv(["sample", "video_frame", "video_time_s", "time_from_first_sample_s", "in_analysis_window",
                          "image_x_px", "image_y_px", "image_x_norm", "image_y_norm", "arena_x_norm", "arena_y_norm",
                          "x_cm", "y_cm", "confidence", "interpolated", "zone", "motion_index", "blob_area_fraction"]))
        try dlc.line(csv(["scorer", "RodentStudio_RodentFlow", "RodentStudio_RodentFlow", "RodentStudio_RodentFlow"]))
        try dlc.line(csv(["bodyparts", "centroid", "centroid", "centroid"]))
        try dlc.line(csv(["coords", "x", "y", "likelihood"]))
        let origin = saved.points.first?.videoTimeSeconds ?? 0
        let w = Double(job.videoWidth), h = Double(job.videoHeight)
        func f(_ v: Double?, _ d: Int = 4) -> String {
            guard let v, v.isFinite else { return "" }
            return String(format: "%.\(d)f", v)
        }
        for (i, p) in saved.points.enumerated() {
            let t = p.videoTimeSeconds - origin
            let px: Double? = w > 0 ? p.imageXNormalized * w : nil
            let py: Double? = h > 0 ? p.imageYNormalized * h : nil
            try out.line(csv([String(i), String(p.frameIndex), f(p.videoTimeSeconds, 6), f(t, 6), inWindow(t, job) ? "1" : "0",
                              f(px, 3), f(py, 3), f(p.imageXNormalized, 6), f(p.imageYNormalized, 6),
                              f(p.arenaXNormalized, 6), f(p.arenaYNormalized, 6), f(p.xCentimeters, 3), f(p.yCentimeters, 3),
                              f(p.confidence, 5), p.interpolated ? "1" : "0", p.zone, f(p.motionIndex, 6), f(p.blobAreaFraction, 6)]))
            try dlc.line([String(i), f(px, 3), f(py, 3), f(p.interpolated ? 0 : p.confidence, 5)].joined(separator: ","))
            if !p.interpolated { s.detectedFrames += 1 }
        }
        try out.close()
        try dlc.close()
        s.frames = saved.points.count
        s.firstVideoTime = saved.points.first?.videoTimeSeconds
        s.files = ["frames/" + name, "frames/" + dlcName]
        if !saved.events.isEmpty {
            let eventsName = job.base + "_maze_events.csv"
            let enc = JSONEncoder()
            // Generic: every event field as a column, so new event fields need no change here.
            let objects = saved.events.compactMap { e -> [String: Any]? in
                guard let d = try? enc.encode(e) else { return nil }
                return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            }
            let keys = Array(Set(objects.flatMap(\.keys))).sorted()
            var lines = [csv(keys)]
            for o in objects {
                lines.append(csv(keys.map { key in o[key].map { value in "\(value)" } ?? "" }))
            }
            try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: dir.appendingPathComponent(eventsName))
            s.files.append("frames/" + eventsName)
        }
    }

    private static func writeIndex(_ list: [FrameExportSummary], to url: URL) throws {
        var lines = [csv(["session_id", "animal_id", "group", "sex", "session_date", "session_number", "phase", "excluded",
                          "exclusion_reason", "tracking_check", "video_file", "video_width_px", "video_height_px", "video_fps",
                          "tracker", "bodyparts", "frames", "detected_frames", "first_frame_video_time_s",
                          "analysis_window_start_s", "analysis_window_length_s", "files", "error"])]
        for s in list {
            let j = s.job
            lines.append(csv([j.sessionID, j.animalID, j.group, j.sex, j.sessionDate, j.sessionNumber, j.phase,
                              j.excluded ? "yes" : "no", j.exclusionReason, j.trackingCheck, j.videoFile,
                              String(j.videoWidth), String(j.videoHeight), String(format: "%.4f", j.videoFPS), s.tracker,
                              s.bodyparts.joined(separator: ";"), String(s.frames), String(s.detectedFrames),
                              s.firstVideoTime.map { String(format: "%.6f", $0) } ?? "",
                              String(format: "%.3f", j.windowStart), j.windowLength > 0 ? String(format: "%.3f", j.windowLength) : "",
                              s.files.joined(separator: ";"), s.error ?? ""]))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func writeMetadata(_ list: [FrameExportSummary], task: String, taskID: String, to url: URL) throws {
        struct Session: Codable {
            var sessionID, animalID, group, sex, sessionDate, sessionNumber, phase: String
            var excluded: Bool
            var exclusionReason, trackingCheck, videoFile: String
            var videoWidthPx, videoHeightPx: Int
            var videoFPS: Double
            var tracker: String
            var bodyparts: [String]
            var frames, detectedFrames: Int
            var firstFrameVideoTimeS: Double?
            var analysisWindowStartS: Double
            var analysisWindowLengthS: Double?
            var files: [String]
            var error: String?
        }
        struct Doc: Codable {
            var format = "RodentStudio frame-by-frame tracking export"
            var formatVersion = 1
            var app: String
            var exportedAt: Date
            var task: String
            var taskID: String
            var conventions: [String: String]
            var columns: [String: String]
            var sessions: [Session]
        }
        let doc = Doc(app: AppInfo.label, exportedAt: Date(), task: task, taskID: taskID, conventions: [
            "coordinates": "pixels of the upright (rotation-corrected) video frame, origin at the top-left corner, x to the right, y down",
            "missing": "x and y empty, likelihood 0 (keypoint not found, no animal detected, or inference failed)",
            "dlc_files": "DeepLabCut layout; pandas: pd.read_csv(path, header=[0, 1, 2], index_col=0)",
            "frame": "0-based index of the tracked frame (every decoded frame for Core ML runs; every 10 Hz sample for RodentFlow)",
            "video_frame": "frame number in the video, from video time x fps",
            "time": "video_time_s = presentation time in the video; time_from_first_frame_s / time_from_first_sample_s = from the first tracked frame (the time base of the analysis window)",
            "analysis_window": "in_analysis_window = 1 inside the session's analysis window set in Calibrate (empty length = to the end)",
            "excluded_sessions": "exported and flagged (excluded = yes); leave them out of group analyses",
        ], columns: [
            "<bodypart>_x / <bodypart>_y": "keypoint position (px)",
            "<bodypart>_likelihood": "model confidence of the keypoint (0-1)",
            "detected": "1 = an animal was detected in the frame",
            "box_confidence": "confidence of the animal detection box",
            "inference_failed": "1 = the model could not be run on this frame (different from 'no animal')",
            "image_x_norm / image_y_norm": "RodentFlow centroid as a fraction of the frame width / height",
            "arena_x_norm / arena_y_norm, x_cm / y_cm": "RodentFlow centroid in the calibrated arena (fraction; cm)",
            "interpolated": "1 = the centroid was not detected and was interpolated",
            "zone": "RodentFlow zone of the centroid",
            "motion_index": "fraction of arena pixels that changed since the previous sample (freezing analysis)",
            "blob_area_fraction": "area of the tracked foreground blob as a fraction of the arena",
        ], sessions: list.map { s in
            let j = s.job
            return Session(sessionID: j.sessionID, animalID: j.animalID, group: j.group, sex: j.sex, sessionDate: j.sessionDate,
                           sessionNumber: j.sessionNumber, phase: j.phase, excluded: j.excluded, exclusionReason: j.exclusionReason,
                           trackingCheck: j.trackingCheck, videoFile: j.videoFile, videoWidthPx: j.videoWidth,
                           videoHeightPx: j.videoHeight, videoFPS: j.videoFPS, tracker: s.tracker, bodyparts: s.bodyparts,
                           frames: s.frames, detectedFrames: s.detectedFrames, firstFrameVideoTimeS: s.firstVideoTime,
                           analysisWindowStartS: j.windowStart, analysisWindowLengthS: j.windowLength > 0 ? j.windowLength : nil,
                           files: s.files, error: s.error)
        })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        enc.keyEncodingStrategy = .convertToSnakeCase
        try enc.encode(doc).write(to: url, options: .atomic)
    }
}
