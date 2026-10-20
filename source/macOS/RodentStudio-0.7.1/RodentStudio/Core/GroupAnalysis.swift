// Port of RodentFlow iOS 1.3 GroupAnalysis.swift, generalized from RodentFlow records to the sessions of
// any RodentStudio task (RodentPose, RodentLimb, RodentFlow). The rules are RodentFlow's:
//   • the animal is the experimental unit (n = animals); several sessions of one animal are averaged
//     within the animal first;
//   • phases are never pooled by default; excluded sessions are left out unless asked;
//   • the first included group is the control for "vs. first group" comparisons;
//   • tests: Welch t / Mann–Whitney (2 groups), one-way ANOVA + Tukey–Kramer or Welch + Holm vs control /
//     Kruskal–Wallis + Dunn–Holm (≥ 3 groups), mixed ANOVA with Greenhouse–Geisser for repeated levels,
//     paired t / Wilcoxon for within-animal pairs.
// Added for RodentStudio: a session-number filter and an "across sessions" design (level = 实验次数).
// Text is produced in English when `english` is true (exports) and in the interface language otherwise.

import Foundation

// MARK: - Request / result types

enum GroupDesign: String, CaseIterable, Codable, Identifiable {
    case betweenGroups = "between_groups"
    case bySession = "by_session"
    case byDay = "by_day"
    case withinSession = "within_session"
    case pairedMeasures = "paired_measures"
    case phaseChange = "phase_change"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betweenGroups: return L("Compare groups", "组间比较")
        case .bySession: return L("Across sessions", "按实验次数")
        case .byDay: return L("Across days", "按天")
        case .withinSession: return L("Time course", "时间进程")
        case .pairedMeasures: return L("Paired measures", "配对指标")
        case .phaseChange: return L("Change between phases", "阶段间变化")
        }
    }

    var explanation: String {
        switch self {
        case .betweenGroups: return L("One value per animal (sessions averaged within animal).", "每只小鼠一个值（同一小鼠的多次实验先取平均）。")
        case .bySession: return L("One value per animal per session number (实验次数): learning across sessions.", "每只小鼠每个实验次数一个值：跨实验次数的变化。")
        case .byDay: return L("Learning curve: one value per animal per day (trials averaged within day).", "学习曲线：每只小鼠每天一个值（同一天的试次先取平均）。")
        case .withinSession: return L("Series stored in each session: time bins, CS presentations.", "每次实验内的序列：时间段、CS 呈现。")
        case .pairedMeasures: return L("Two measures from the same animal, e.g. novel vs familiar.", "同一小鼠的两个指标，如新物体 vs 熟悉物体。")
        case .phaseChange: return L("Per-animal difference between two phases, e.g. test − pre-test.", "每只小鼠两个阶段之差，如 测试 − 预测试。")
        }
    }
}

enum StatMode: String, CaseIterable, Codable, Identifiable {
    case parametric
    case nonparametric
    var id: String { rawValue }
    var displayName: String { self == .parametric ? L("Parametric", "参数检验") : L("Non-parametric", "非参数检验") }
}

enum ComparisonMode: String, CaseIterable, Codable, Identifiable {
    case allPairs = "all_pairs"
    case versusControl = "versus_control"
    var id: String { rawValue }
    var displayName: String { self == .allPairs ? L("All pairs", "两两比较") : L("Vs. first group", "与第一组比较") }
}

/// A measure of a task, with names in both languages (English goes into exports).
struct TaskMetricDef: Codable, Hashable, Identifiable {
    var key: String
    var nameEN: String
    var nameZH: String
    var unit: String
    var unitZH: String
    var decimals: Int
    /// Reference value for an optional one-sample test (e.g. DI vs 0, quadrant vs 25%).
    var chance: Double?

    var id: String { key }
    var name: String { Lang.isChinese && !nameZH.isEmpty ? nameZH : nameEN }
    var displayUnit: String { Lang.isChinese && !unitZH.isEmpty ? unitZH : unit }
    var axisTitle: String { displayUnit.isEmpty ? name : "\(name) (\(displayUnit))" }
    var exportHeader: String { unit.isEmpty ? nameEN : "\(nameEN) (\(unit))" }

    func title(english: Bool) -> String { english ? nameEN : name }
    func unitText(english: Bool) -> String { english ? unit : displayUnit }

    func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let number = String(format: "%.\(decimals)f", value)
        let u = displayUnit
        if u.isEmpty { return number }
        return u == "%" ? number + "%" : number + " " + u
    }
}

/// Two measures of the same animal compared within animal (RodentFlow AssayKind.withinPairs).
struct MetricPair: Codable, Hashable, Identifiable {
    var key: String
    var nameEN: String
    var nameZH: String
    var metricA: String
    var metricB: String
    var labelAEN: String
    var labelAZH: String
    var labelBEN: String
    var labelBZH: String
    var id: String { key }

    func title(english: Bool) -> String { english || !Lang.isChinese ? nameEN : nameZH }
    func labelA(english: Bool) -> String { english || !Lang.isChinese ? labelAEN : labelAZH }
    func labelB(english: Bool) -> String { english || !Lang.isChinese ? labelBEN : labelBZH }
}

enum TaskPairs {
    /// RodentFlow 1.3 within-animal pairs of the video assays.
    static func pairs(_ assay: StudyAssay) -> [MetricPair] {
        guard let flow = assay.flowAssay else { return [] }
        switch flow {
        case .novelObject:
            return [MetricPair(key: "novel_vs_familiar", nameEN: "Novel vs familiar exploration", nameZH: "新物体 vs 熟悉物体探索",
                               metricA: "novel_time_s", metricB: "familiar_time_s",
                               labelAEN: "Novel", labelAZH: "新物体", labelBEN: "Familiar", labelBZH: "熟悉物体")]
        case .placePreference:
            return [MetricPair(key: "paired_vs_unpaired", nameEN: "Paired vs unpaired side", nameZH: "配对侧 vs 非配对侧",
                               metricA: "paired_time_s", metricB: "unpaired_time_s",
                               labelAEN: "Paired", labelAZH: "配对侧", labelBEN: "Unpaired", labelBZH: "非配对侧")]
        case .morrisWaterMaze, .barnesMaze:
            return [MetricPair(key: "target_vs_opposite", nameEN: "Target vs opposite quadrant", nameZH: "目标象限 vs 对侧象限",
                               metricA: "target_quadrant_pct", metricB: "opposite_quadrant_pct",
                               labelAEN: "Target", labelAZH: "目标", labelBEN: "Opposite", labelBZH: "对侧")]
        case .fearConditioning:
            return [MetricPair(key: "baseline_vs_cs", nameEN: "Baseline vs CS freezing", nameZH: "基线 vs CS 僵直",
                               metricA: "baseline_freezing_pct", metricB: "cs_freezing_pct",
                               labelAEN: "Baseline", labelAZH: "基线", labelBEN: "CS", labelBZH: "CS")]
        case .elevatedPlusMaze:
            return [MetricPair(key: "open_vs_closed", nameEN: "Open vs closed arm time", nameZH: "开放臂 vs 闭合臂时间",
                               metricA: "open_time_s", metricB: "closed_time_s",
                               labelAEN: "Open", labelAZH: "开放臂", labelBEN: "Closed", labelBZH: "闭合臂")]
        default:
            return []
        }
    }

    /// RodentFlow AssayKind.analysisDefaultPhase.
    static func analysisDefaultPhase(_ assay: StudyAssay) -> String? {
        switch assay.flowAssay {
        case .novelObject?, .placePreference?: return "Test"
        case .morrisWaterMaze?, .barnesMaze?: return "Acquisition"
        case .fearConditioning?: return "Cue test"
        default: return nil
        }
    }
}

/// One session (video) as the group comparison sees it.
struct GroupRecord: Identifiable {
    var id: UUID
    /// Animal ID as entered ("" if missing).
    var subjectID: String
    /// Animal identity within the task (videos without an ID are separate animals).
    var subjectKey: String
    /// Group label ("" = no group).
    var group: String
    var phase: String
    var day: Int?
    var trial: Int?
    var session: Int?
    var date: String?
    var metrics: [String: Double]
    var series: [FlowResultSeries]
    var excluded: Bool
    var exclusionReason: String
    /// QC warnings of the analysis (English).
    var qcFlags: [String]
    /// The reviewer marked the tracking of this session as having problems.
    var trackingProblem: Bool

    static let ungroupedLabel = "Ungrouped"
    var displayGroup: String { group.isEmpty ? Self.ungroupedLabel : group }
    var displaySubject: String { subjectID.isEmpty ? subjectKey : subjectID }
}

/// Group label for the interface ("Ungrouped" is shown in the interface language).
func groupDisplayName(_ g: String) -> String {
    g == GroupRecord.ungroupedLabel ? L("Ungrouped", "未分组") : g
}

/// What the engine needs to know about the task.
struct GroupAnalysisContext {
    var assay: StudyAssay
    var defs: [TaskMetricDef]
    var pairs: [MetricPair]
    /// Phase keys in the task's own order.
    var assayPhases: [String]
    /// Primary measure for a phase ("" = all phases).
    var primaryKey: (String) -> String
    var usesDays: Bool

    func phaseTitle(_ key: String, english: Bool) -> String {
        if key.isEmpty { return english ? "no phase" : L("No phase", "无阶段") }
        return english ? key : assay.phaseTitle(key)
    }
}

struct GroupAnalysisRequest: Codable, Hashable {
    var design: GroupDesign = .betweenGroups
    var metricKey: String = ""
    var seriesKey: String = ""
    var pairKey: String = ""
    /// nil = all phases.
    var phaseFilter: String?
    /// nil = all sessions (averaged within animal); a number = only that session number (实验次数).
    var sessionFilter: Int?
    var phaseA: String = ""
    var phaseB: String = ""
    /// Included groups in display order; the first one is treated as the control.
    var groups: [String] = []
    var includeExcluded = false
    var mode: StatMode = .parametric
    var comparison: ComparisonMode = .allPairs
    var testAgainstChance = false
}

struct SubjectPoint: Codable, Hashable, Identifiable {
    var subject: String
    var group: String
    var value: Double
    var records: Int
    var id: String { group + "|" + subject }
}

struct CurvePoint: Codable, Hashable, Identifiable {
    var group: String
    var level: Double
    var mean: Double
    var sem: Double
    var n: Int
    var id: String { "\(group)|\(level)" }
}

struct SubjectSeries: Codable, Hashable, Identifiable {
    var subject: String
    var group: String
    var values: [Double?]
    var id: String { group + "|" + subject }
}

struct PairedPoint: Codable, Hashable, Identifiable {
    var subject: String
    var group: String
    var a: Double
    var b: Double
    var id: String { group + "|" + subject }
}

struct GroupTestReport: Codable, Hashable {
    var omnibus: TestResult?
    var mixed: StatTests.MixedANOVAOutput?
    var pairwise: [PairwiseComparison] = []
    var perGroup: [String: TestResult] = [:]
    var perGroupLabel = ""
    var methodSummary = ""
}

struct GroupAnalysisResult: Codable {
    var request: GroupAnalysisRequest
    var english = false
    var metricName = ""
    var unit = ""
    var levelLabel = ""
    var groups: [String] = []
    var points: [SubjectPoint] = []
    var descriptives: [String: Descriptives] = [:]
    var levels: [Double] = []
    var curves: [CurvePoint] = []
    var subjectSeries: [SubjectSeries] = []
    var paired: [PairedPoint] = []
    var pairLabelA = ""
    var pairLabelB = ""
    var chance: Double?
    var report = GroupTestReport()
    var notes: [String] = []
    var generatedAt = Date()

    var animalCount: Int {
        switch request.design {
        case .betweenGroups, .phaseChange: return points.count
        case .byDay, .bySession, .withinSession: return subjectSeries.count
        case .pairedMeasures: return paired.count
        }
    }

    var isEmpty: Bool { animalCount == 0 }

    var axisTitle: String { unit.isEmpty ? metricName : "\(metricName) (\(unit))" }
}

struct SeriesOption: Hashable, Identifiable {
    var key: String
    var name: String
    var unit: String
    var xLabel: String
    var id: String { key }
}

// MARK: - Engine

enum GroupAnalysisEngine {
    static let controlHints = ["control", "ctrl", "wt", "wild", "vehicle", "veh", "saline", "sham", "naive", "con"]

    private static func tx(_ english: Bool, _ en: String, _ zh: String) -> String {
        english || !Lang.isChinese ? en : zh
    }

    /// Groups ordered with a likely control first, then alphabetically.
    static func orderedGroups(_ records: [GroupRecord]) -> [String] {
        let names = Set(records.map(\.displayGroup))
        return names.sorted { a, b in
            let ca = isLikelyControl(a), cb = isLikelyControl(b)
            if ca != cb { return ca }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }

    static func isLikelyControl(_ name: String) -> Bool {
        let lower = name.lowercased()
        return controlHints.contains { lower == $0 || lower.hasPrefix($0 + " ") || lower.hasPrefix($0 + "-") || lower.hasPrefix($0 + "_") || lower.hasPrefix($0 + "/") }
    }

    /// Phases present, in the task's order. "" (no phase) is listed only when other phases exist too, so it
    /// can be analysed separately instead of being pooled with them.
    static func phases(_ records: [GroupRecord], assayPhases: [String]) -> [String] {
        var seen: [String] = []
        for p in assayPhases where records.contains(where: { $0.phase == p }) { seen.append(p) }
        for r in records where !r.phase.isEmpty && !seen.contains(r.phase) { seen.append(r.phase) }
        if !seen.isEmpty && records.contains(where: { $0.phase.isEmpty }) { seen.append("") }
        return seen
    }

    static func days(_ records: [GroupRecord]) -> [Int] {
        Array(Set(records.compactMap(\.day))).sorted()
    }

    static func sessions(_ records: [GroupRecord]) -> [Int] {
        Array(Set(records.compactMap(\.session))).sorted()
    }

    static func metricOptions(_ context: GroupAnalysisContext, records: [GroupRecord]) -> [TaskMetricDef] {
        let present = Set(records.flatMap { $0.metrics.keys })
        return context.defs.filter { present.contains($0.key) }
    }

    static func seriesOptions(_ records: [GroupRecord], english: Bool = false) -> [SeriesOption] {
        var out: [SeriesOption] = []
        for r in records {
            for s in r.series where !out.contains(where: { $0.key == s.key }) {
                out.append(SeriesOption(key: s.key, name: english ? s.name : RFText.tr(s.name), unit: s.unit,
                                        xLabel: english ? s.xLabel : RFText.tr(s.xLabel)))
            }
        }
        return out
    }

    static func availableDesigns(_ context: GroupAnalysisContext, records: [GroupRecord]) -> [GroupDesign] {
        var designs: [GroupDesign] = [.betweenGroups]
        if sessions(records).count >= 2 { designs.append(.bySession) }
        if days(records).count >= 2 { designs.append(.byDay) }
        if !seriesOptions(records).isEmpty { designs.append(.withinSession) }
        let pairs = context.pairs.filter { pair in records.contains { $0.metrics[pair.metricA] != nil && $0.metrics[pair.metricB] != nil } }
        if !pairs.isEmpty { designs.append(.pairedMeasures) }
        if phases(records, assayPhases: context.assayPhases).count >= 2 { designs.append(.phaseChange) }
        return designs
    }

    /// A reasonable starting request for a task and its sessions.
    static func defaultRequest(_ context: GroupAnalysisContext, records: [GroupRecord]) -> GroupAnalysisRequest {
        var req = GroupAnalysisRequest()
        let ph = phases(records, assayPhases: context.assayPhases)
        if !ph.isEmpty && (!context.assayPhases.isEmpty || ph.count >= 2) {
            // Never pool different phases by default (e.g. acquisition and probe trials).
            let preferred = TaskPairs.analysisDefaultPhase(context.assay) ?? context.assay.defaultPhase
            req.phaseFilter = ph.contains(preferred) ? preferred : ph[0]
        }
        let primaryPhase = req.phaseFilter ?? (ph.count == 1 ? ph[0] : "")
        // (An empty primary phase means: the measure highlighted most often in all sessions.)
        let metrics = metricOptions(context, records: records)
        let primary = context.primaryKey(primaryPhase)
        req.metricKey = metrics.contains(where: { $0.key == primary }) ? primary : (metrics.first?.key ?? "")
        req.groups = orderedGroups(records)
        if context.usesDays && days(records).count >= 2 { req.design = .byDay }
        if ph.count >= 2 {
            req.phaseA = ph.first(where: { $0.lowercased().contains("pre") }) ?? ph[0]
            req.phaseB = ph.first(where: { $0 == "Test" }) ?? ph[ph.count - 1]
        }
        req.seriesKey = seriesOptions(records).first?.key ?? ""
        req.pairKey = context.pairs.first?.key ?? ""
        return req
    }

    // MARK: Run

    static func run(_ req: GroupAnalysisRequest, records allRecords: [GroupRecord], context: GroupAnalysisContext,
                    english: Bool = false) -> GroupAnalysisResult {
        var result = GroupAnalysisResult(request: req)
        result.english = english
        var records = allRecords
        let excludedCount = records.filter(\.excluded).count
        if !req.includeExcluded {
            records.removeAll(where: \.excluded)
            if excludedCount > 0 {
                result.notes.append(String(format: tx(english, "%d excluded session(s) left out.", "已排除 %d 次实验（未纳入）。"), excludedCount))
            }
        }
        if req.design != .phaseChange, let phase = req.phaseFilter {
            records = records.filter { $0.phase == phase }
        }
        if req.design != .bySession, let session = req.sessionFilter {
            records = records.filter { $0.session == session }
        }
        let groupSet = Set(req.groups)
        records = records.filter { groupSet.contains($0.displayGroup) }
        result.groups = req.groups.filter { g in records.contains { $0.displayGroup == g } }

        let def = context.defs.first { $0.key == req.metricKey }
        result.metricName = def?.title(english: english) ?? req.metricKey
        result.unit = def?.unitText(english: english) ?? ""
        result.chance = def?.chance

        let flagged = records.filter { !$0.qcFlags.isEmpty || $0.trackingProblem }
        if !flagged.isEmpty {
            let names = flagged.prefix(4).map(\.displaySubject).joined(separator: ", ") + (flagged.count > 4 ? "…" : "")
            result.notes.append(String(format: tx(english,
                "%d included session(s) have QC warnings or tracking problems (%@). Open them and exclude them if your criteria require it.",
                "%d 次纳入的实验有质控警告或追踪问题（%@）。如按你的标准应排除，请打开并标记排除。"), flagged.count, names))
        }
        let unnamed = records.filter { $0.subjectID.trimmingCharacters(in: .whitespaces).isEmpty }.count
        if unnamed > 0 {
            result.notes.append(String(format: tx(english, "%d session(s) without an animal ID were treated as separate animals.",
                                                  "%d 次实验没有小鼠编号，按不同小鼠处理。"), unnamed))
        }

        switch req.design {
        case .betweenGroups:
            result.points = subjectMeans(records, metric: req.metricKey)
            noteAveraging(&result)
            analyzeIndependent(&result)
        case .phaseChange:
            result.metricName = "Δ " + result.metricName + " (\(context.phaseTitle(req.phaseB, english: english)) − \(context.phaseTitle(req.phaseA, english: english)))"
            result.points = phaseDifferences(records, metric: req.metricKey, phaseA: req.phaseA, phaseB: req.phaseB, english: english, notes: &result.notes)
            result.chance = 0
            analyzeIndependent(&result)
        case .byDay, .bySession:
            let byDay = req.design == .byDay
            result.levelLabel = byDay ? tx(english, "Day", "天") : tx(english, "Session", "实验次数")
            let rows = records.compactMap { r -> (String, String, Double, Double)? in
                guard let level = byDay ? r.day : r.session, let v = r.metrics[req.metricKey], v.isFinite else { return nil }
                return (r.displayGroup, r.subjectKey, Double(level), v)
            }
            if rows.count < records.count {
                result.notes.append(String(format: tx(english, "%d session(s) without a %@ or value were skipped.", "%d 次实验缺少%@或数值，已跳过。"),
                                           records.count - rows.count, result.levelLabel.lowercased()))
            }
            buildRepeated(&result, rows: rows)
        case .withinSession:
            let option = seriesOptions(records, english: english).first { $0.key == req.seriesKey }
            result.metricName = option?.name ?? req.seriesKey
            result.unit = option?.unit ?? ""
            result.levelLabel = option?.xLabel ?? tx(english, "Level", "水平")
            result.chance = nil
            var rows: [(String, String, Double, Double)] = []
            for r in records {
                guard let s = r.series.first(where: { $0.key == req.seriesKey }) else { continue }
                for (x, y) in zip(s.x, s.y) where x.isFinite && y.isFinite { rows.append((r.displayGroup, r.subjectKey, x, y)) }
            }
            buildRepeated(&result, rows: rows)
        case .pairedMeasures:
            analyzePaired(&result, records: records, context: context)
        }
        return result
    }

    static func subjectMeans(_ records: [GroupRecord], metric: String) -> [SubjectPoint] {
        var sums: [String: (group: String, subject: String, sum: Double, n: Int)] = [:]
        var order: [String] = []
        for r in records {
            guard let v = r.metrics[metric], v.isFinite else { continue }
            let key = r.displayGroup + "|" + r.subjectKey
            if sums[key] == nil {
                sums[key] = (r.displayGroup, r.subjectKey, 0, 0)
                order.append(key)
            }
            sums[key]!.sum += v
            sums[key]!.n += 1
        }
        return order.compactMap { key in
            guard let e = sums[key] else { return nil }
            return SubjectPoint(subject: e.subject, group: e.group, value: e.sum / Double(e.n), records: e.n)
        }
    }

    static func noteAveraging(_ result: inout GroupAnalysisResult) {
        let english = result.english
        let multi = result.points.filter { $0.records > 1 }
        if !multi.isEmpty {
            result.notes.append(String(format: tx(english,
                "%d animal(s) had several sessions; their values were averaged so n = animals. Filter by phase or session number to analyze one session.",
                "%d 只小鼠有多次实验，已在小鼠内取平均，n = 小鼠数。可按阶段或实验次数筛选，只分析某一次实验。"), multi.count))
        }
        let subjects = Dictionary(grouping: result.points, by: \.subject).filter { $0.value.count > 1 }
        if !subjects.isEmpty {
            result.notes.append(String(format: tx(english, "Animal ID(s) appearing in more than one group: %@. Check the group labels.",
                                                  "出现在多个分组中的小鼠编号：%@。请检查分组。"),
                                       subjects.keys.sorted().joined(separator: ", ")))
        }
    }

    static func phaseDifferences(_ records: [GroupRecord], metric: String, phaseA: String, phaseB: String, english: Bool, notes: inout [String]) -> [SubjectPoint] {
        let a = subjectMeans(records.filter { $0.phase == phaseA }, metric: metric)
        let b = subjectMeans(records.filter { $0.phase == phaseB }, metric: metric)
        var out: [SubjectPoint] = []
        var unmatched = 0
        for pb in b {
            if let pa = a.first(where: { $0.subject == pb.subject && $0.group == pb.group }) {
                out.append(SubjectPoint(subject: pb.subject, group: pb.group, value: pb.value - pa.value, records: pa.records + pb.records))
            } else {
                unmatched += 1
            }
        }
        unmatched += a.filter { pa in !b.contains { $0.subject == pa.subject && $0.group == pa.group } }.count
        if unmatched > 0 {
            notes.append(String(format: tx(english, "%d animal(s) had only one of the two phases and were left out.", "%d 只小鼠只有其中一个阶段，未纳入。"), unmatched))
        }
        return out
    }

    // MARK: Independent groups (one value per animal)

    static func analyzeIndependent(_ result: inout GroupAnalysisResult) {
        let req = result.request
        let english = result.english
        let groups = result.groups
        var values: [[Double]] = []
        for g in groups {
            let v = result.points.filter { $0.group == g }.map(\.value)
            values.append(v)
            result.descriptives[g] = Stats.describe(v)
        }
        let present = zip(groups, values).filter { !$0.1.isEmpty }
        let names = present.map { $0.0 }
        let data = present.map { $0.1 }
        var report = GroupTestReport()
        let k = data.count

        if k == 2 {
            if req.mode == .parametric {
                if let t = StatTests.welchT(data[0], data[1]) {
                    report.omnibus = t
                    report.pairwise = [PairwiseComparison(groupA: names[0], groupB: names[1], level: nil,
                                                          difference: Stats.mean(data[0]) - Stats.mean(data[1]),
                                                          statisticName: "t", statistic: t.statistic, p: t.p, pAdjusted: t.p, method: t.name)]
                    report.methodSummary = tx(english, "Two-tailed Welch's t-test (unequal variances).", "双侧 Welch t 检验（方差不等）。")
                    if let ci = StatTests.welchDifferenceCI(data[0], data[1]) {
                        result.notes.append(String(format: tx(english, "Mean difference (%@ − %@) = %@, 95%% CI [%@, %@].", "均值差（%@ − %@）= %@，95%% CI [%@, %@]。"),
                                                   names[0], names[1],
                                                   StatsFormat.number(Stats.mean(data[0]) - Stats.mean(data[1])),
                                                   StatsFormat.number(ci.low), StatsFormat.number(ci.high)))
                    }
                }
            } else if let u = StatTests.mannWhitney(data[0], data[1]) {
                report.omnibus = u
                report.pairwise = [PairwiseComparison(groupA: names[0], groupB: names[1], level: nil,
                                                      difference: Stats.quantile(data[0], 0.5) - Stats.quantile(data[1], 0.5),
                                                      statisticName: "U", statistic: u.statistic, p: u.p, pAdjusted: u.p, method: u.name)]
                report.methodSummary = String(format: tx(english, "Two-tailed Mann–Whitney U test (%@).", "双侧 Mann–Whitney U 检验（%@）。"), u.note ?? "exact")
            }
        } else if k >= 3 {
            let control = req.comparison == .versusControl ? 0 : nil
            if req.mode == .parametric {
                report.omnibus = StatTests.oneWayANOVA(data)?.test
                if control == nil {
                    report.pairwise = StatTests.tukeyHSD(data, names: names)
                    report.methodSummary = tx(english, "One-way ANOVA followed by Tukey–Kramer HSD for all pairwise comparisons.",
                                              "单因素方差分析，事后用 Tukey–Kramer HSD 做两两比较。")
                } else {
                    var comps: [PairwiseComparison] = []
                    for j in 1..<k {
                        if let t = StatTests.welchT(data[0], data[j]) {
                            comps.append(PairwiseComparison(groupA: names[0], groupB: names[j], level: nil,
                                                            difference: Stats.mean(data[0]) - Stats.mean(data[j]),
                                                            statisticName: "t", statistic: t.statistic, p: t.p, pAdjusted: t.p, method: "Welch's t (Holm)"))
                        }
                    }
                    let adj = Stats.holm(comps.map(\.p))
                    for i in comps.indices { comps[i].pAdjusted = adj[i] }
                    report.pairwise = comps
                    report.methodSummary = String(format: tx(english, "One-way ANOVA followed by Welch's t-tests of each group against %@ with Holm correction.",
                                                             "单因素方差分析，事后各组分别与 %@ 做 Welch t 检验（Holm 校正）。"), names[0])
                }
            } else {
                report.omnibus = StatTests.kruskalWallis(data)
                report.pairwise = StatTests.dunn(data, names: names, controlIndex: control)
                report.methodSummary = control == nil
                    ? tx(english, "Kruskal–Wallis test followed by Dunn's test with Holm correction.", "Kruskal–Wallis 检验，事后 Dunn 检验（Holm 校正）。")
                    : String(format: tx(english, "Kruskal–Wallis test followed by Dunn's test with Holm correction (each group vs %@).",
                                        "Kruskal–Wallis 检验，事后 Dunn 检验（Holm 校正，各组与 %@ 比较）。"), names[0])
            }
        } else if k == 1 {
            report.methodSummary = tx(english, "Single group: descriptive statistics only.", "只有一组：仅描述统计。")
        }
        if k >= 2 && report.omnibus == nil {
            result.notes.append(tx(english, "No test result: each group needs at least 2 animals with values that differ (identical values give no variability to test).",
                                   "没有检验结果：每组至少需要 2 只数值不完全相同的小鼠。"))
        }

        if req.testAgainstChance, let chance = result.chance {
            for (name, v) in zip(names, data) {
                let test: TestResult?
                if req.mode == .parametric {
                    test = StatTests.oneSampleT(v, mu: chance)
                } else {
                    test = StatTests.wilcoxonSignedRank(v.map { $0 - chance })
                }
                if let test { report.perGroup[name] = test }
            }
            report.perGroupLabel = String(format: tx(english, "vs %@", "与 %@ 比较"), StatsFormat.number(chance))
            report.methodSummary += req.mode == .parametric
                ? " " + String(format: tx(english, "One-sample t-tests against %@.", "单样本 t 检验（与 %@ 比较）。"), StatsFormat.number(chance))
                : " " + String(format: tx(english, "Wilcoxon signed-rank tests against %@.", "Wilcoxon 符号秩检验（与 %@ 比较）。"), StatsFormat.number(chance))
        }
        result.report = report
    }

    // MARK: Repeated (sessions, days, bins, CS)

    static func buildRepeated(_ result: inout GroupAnalysisResult, rows: [(String, String, Double, Double)]) {
        let req = result.request
        let english = result.english
        let levels = Array(Set(rows.map { $0.2 })).sorted()
        result.levels = levels
        guard !levels.isEmpty else { return }
        var levelIndex: [Double: Int] = [:]
        for (i, level) in levels.enumerated() { levelIndex[level] = i }

        // Average within animal × level (e.g. trials within a day).
        var cell: [String: [Double]] = [:]
        var subjectsByGroup: [String: [String]] = [:]
        for (g, s, x, y) in rows {
            let key = g + "|" + s + "|" + String(levelIndex[x] ?? 0)
            cell[key, default: []].append(y)
            if !(subjectsByGroup[g]?.contains(s) ?? false) { subjectsByGroup[g, default: []].append(s) }
        }
        var series: [SubjectSeries] = []
        for g in result.groups {
            for s in subjectsByGroup[g] ?? [] {
                let values: [Double?] = levels.indices.map { j in
                    cell[g + "|" + s + "|" + String(j)].map { Stats.mean($0) }
                }
                series.append(SubjectSeries(subject: s, group: g, values: values))
            }
        }
        result.subjectSeries = series

        var curves: [CurvePoint] = []
        for g in result.groups {
            let gs = series.filter { $0.group == g }
            for (j, level) in levels.enumerated() {
                let v = gs.compactMap { $0.values[j] }
                guard !v.isEmpty else { continue }
                let d = Stats.describe(v)
                curves.append(CurvePoint(group: g, level: level, mean: d.mean, sem: d.sem, n: d.n))
            }
            result.descriptives[g] = Stats.describe(gs.compactMap { s -> Double? in
                let v = s.values.compactMap { $0 }
                return v.isEmpty ? nil : Stats.mean(v)
            })
        }
        result.curves = curves

        var report = GroupTestReport()
        let groupsWithData = result.groups.filter { g in series.contains { $0.group == g } }
        let complete = series.filter { $0.values.allSatisfy { $0 != nil } }
        let dropped = series.count - complete.count
        let levelWord = result.levelLabel.lowercased()

        if levels.count >= 2 {
            if req.mode == .parametric {
                let data = groupsWithData.map { g in complete.filter { $0.group == g }.map { $0.values.map { $0 ?? 0 } } }
                if let mixed = StatTests.mixedANOVA(data, levelCount: levels.count, dropped: dropped) {
                    report.mixed = mixed
                    report.methodSummary = groupsWithData.count >= 2
                        ? String(format: tx(english, "Two-way mixed ANOVA (group × %@, animal as the repeated unit) with Greenhouse–Geisser correction for the within-animal factor.",
                                            "两因素混合方差分析（组 × %@，小鼠为重复测量单位），组内因素用 Greenhouse–Geisser 校正。"), levelWord)
                        : tx(english, "One-way repeated-measures ANOVA with Greenhouse–Geisser correction.", "单因素重复测量方差分析（Greenhouse–Geisser 校正）。")
                }
                if dropped > 0 {
                    result.notes.append(String(format: tx(english, "%d animal(s) missing at least one %@ were left out of the ANOVA (still shown in the plot).",
                                                          "%d 只小鼠缺少至少一个%@，未纳入方差分析（图中仍显示）。"), dropped, levelWord))
                }
            } else if groupsWithData.count == 1 {
                let rowsComplete = complete.map { $0.values.map { $0 ?? 0 } }
                report.omnibus = StatTests.friedman(rowsComplete)
                report.methodSummary = String(format: tx(english, "Friedman test across %@s.", "跨%@的 Friedman 检验。"), levelWord)
            } else {
                report.methodSummary = String(format: tx(english, "Non-parametric: per-%@ Mann–Whitney tests with Holm correction (no omnibus test).",
                                                         "非参数：每个%@分别做 Mann–Whitney 检验（Holm 校正，无总体检验）。"), levelWord)
            }
        }

        // Post-hoc: groups compared at each level.
        if groupsWithData.count >= 2 {
            var comps: [PairwiseComparison] = []
            for (j, level) in levels.enumerated() {
                let byGroup = groupsWithData.map { g in series.filter { $0.group == g }.compactMap { $0.values[j] } }
                for a in 0..<groupsWithData.count {
                    for b in (a + 1)..<groupsWithData.count {
                        if req.comparison == .versusControl && a != 0 { continue }
                        let x = byGroup[a], y = byGroup[b]
                        let label = levelName(level, label: result.levelLabel, english: english)
                        if req.mode == .parametric, let t = StatTests.welchT(x, y) {
                            comps.append(PairwiseComparison(groupA: groupsWithData[a], groupB: groupsWithData[b], level: label,
                                                            difference: Stats.mean(x) - Stats.mean(y), statisticName: "t",
                                                            statistic: t.statistic, p: t.p, pAdjusted: t.p, method: "Welch's t (Holm)"))
                        } else if req.mode == .nonparametric, let u = StatTests.mannWhitney(x, y) {
                            comps.append(PairwiseComparison(groupA: groupsWithData[a], groupB: groupsWithData[b], level: label,
                                                            difference: Stats.quantile(x, 0.5) - Stats.quantile(y, 0.5), statisticName: "U",
                                                            statistic: u.statistic, p: u.p, pAdjusted: u.p, method: "Mann–Whitney (Holm)"))
                        }
                    }
                }
            }
            let adj = Stats.holm(comps.map(\.p))
            for i in comps.indices { comps[i].pAdjusted = adj[i] }
            report.pairwise = comps
            if !comps.isEmpty {
                report.methodSummary += " " + (req.mode == .parametric
                    ? String(format: tx(english, "Group differences at each %@: Welch's t-tests, Holm-corrected across all comparisons.",
                                        "每个%@的组间差异：Welch t 检验，所有比较一起做 Holm 校正。"), levelWord)
                    : String(format: tx(english, "Group differences at each %@: Mann–Whitney tests, Holm-corrected across all comparisons.",
                                        "每个%@的组间差异：Mann–Whitney 检验，所有比较一起做 Holm 校正。"), levelWord))
            }
        }
        result.report = report
    }

    static func levelName(_ level: Double, label: String, english: Bool) -> String {
        let number = abs(level - level.rounded()) < 1e-9 ? String(format: "%.0f", level) : String(format: "%.1f", level)
        if label == tx(english, "Day", "天") { return String(format: tx(english, "Day %@", "第 %@ 天"), number) }
        if label == tx(english, "Session", "实验次数") { return String(format: tx(english, "Session %@", "第 %@ 次"), number) }
        return label.isEmpty ? number : "\(label) \(number)"
    }

    // MARK: Paired measures

    static func analyzePaired(_ result: inout GroupAnalysisResult, records: [GroupRecord], context: GroupAnalysisContext) {
        let req = result.request
        let english = result.english
        guard let pair = context.pairs.first(where: { $0.key == req.pairKey }) ?? context.pairs.first else { return }
        let defA = context.defs.first { $0.key == pair.metricA }
        let labelA = pair.labelA(english: english), labelB = pair.labelB(english: english)
        result.metricName = pair.title(english: english)
        result.unit = defA?.unitText(english: english) ?? ""
        result.pairLabelA = labelA
        result.pairLabelB = labelB
        result.chance = nil

        let a = subjectMeans(records, metric: pair.metricA)
        let b = subjectMeans(records, metric: pair.metricB)
        var paired: [PairedPoint] = []
        for pa in a {
            if let pb = b.first(where: { $0.subject == pa.subject && $0.group == pa.group }) {
                paired.append(PairedPoint(subject: pa.subject, group: pa.group, a: pa.value, b: pb.value))
            }
        }
        result.paired = paired

        var report = GroupTestReport()
        report.perGroupLabel = String(format: tx(english, "%@ vs %@", "%@ vs %@"), labelA, labelB)
        var differencesByGroup: [[Double]] = []
        var groupsWithData: [String] = []
        for g in result.groups {
            let pts = paired.filter { $0.group == g }
            guard !pts.isEmpty else { continue }
            groupsWithData.append(g)
            differencesByGroup.append(pts.map { $0.a - $0.b })
            result.descriptives[g] = Stats.describe(pts.map { $0.a - $0.b })
            let test = req.mode == .parametric
                ? StatTests.pairedT(pts.map(\.a), pts.map(\.b))
                : StatTests.wilcoxonSignedRank(pts.map { $0.a - $0.b })
            if let test { report.perGroup[g] = test }
        }
        report.methodSummary = req.mode == .parametric
            ? String(format: tx(english, "Within each group: paired t-test (%@ vs %@).", "各组内：配对 t 检验（%@ vs %@）。"), labelA, labelB)
            : String(format: tx(english, "Within each group: Wilcoxon signed-rank test (%@ vs %@).", "各组内：Wilcoxon 符号秩检验（%@ vs %@）。"), labelA, labelB)

        if groupsWithData.count >= 2 {
            if req.mode == .parametric {
                let data = groupsWithData.map { g in paired.filter { $0.group == g }.map { [$0.a, $0.b] } }
                report.mixed = StatTests.mixedANOVA(data, levelCount: 2)
                report.methodSummary += " " + String(format: tx(english, "Between groups: two-way mixed ANOVA (group × measure); the interaction tests whether the %@–%@ difference differs between groups.",
                                                                "组间：两因素混合方差分析（组 × 指标）；交互作用检验 %@–%@ 之差在各组间是否不同。"), labelA, labelB)
            } else {
                report.omnibus = groupsWithData.count == 2
                    ? StatTests.mannWhitney(differencesByGroup[0], differencesByGroup[1])
                    : StatTests.kruskalWallis(differencesByGroup)
                report.methodSummary += " " + (groupsWithData.count == 2
                    ? String(format: tx(english, "Between groups: the %@ − %@ differences were compared with a Mann–Whitney test.",
                                        "组间：%@ − %@ 之差用 Mann–Whitney 检验比较。"), labelA, labelB)
                    : String(format: tx(english, "Between groups: the %@ − %@ differences were compared with a Kruskal–Wallis test.",
                                        "组间：%@ − %@ 之差用 Kruskal–Wallis 检验比较。"), labelA, labelB))
            }
        }
        result.report = report
    }

    // MARK: Text summary (RodentFlow GroupAnalysisViewModel.summaryText)

    static func summaryText(_ r: GroupAnalysisResult, taskName: String, context: GroupAnalysisContext) -> String {
        let english = r.english
        var lines: [String] = []
        lines.append("\(taskName) — \(r.metricName)\(r.unit.isEmpty ? "" : " (\(r.unit))")")
        if let phase = r.request.phaseFilter, r.request.design != .phaseChange {
            lines.append(String(format: tx(english, "Phase: %@", "阶段：%@"), context.phaseTitle(phase, english: english)))
        }
        if let session = r.request.sessionFilter, r.request.design != .bySession {
            lines.append(String(format: tx(english, "Session number: %d", "实验次数：%d"), session))
        }
        for g in r.groups {
            if let d = r.descriptives[g], d.n > 0 {
                let name = english ? g : groupDisplayName(g)
                lines.append(String(format: tx(english, "%@: n = %d, mean ± SEM = %@ ± %@, median = %@", "%@：n = %d，均值 ± SEM = %@ ± %@，中位数 = %@"),
                                    name, d.n, StatsFormat.number(d.mean), StatsFormat.number(d.sem), StatsFormat.number(d.median)))
            }
        }
        lines.append(r.report.methodSummary)
        if let omnibus = r.report.omnibus { lines.append("\(omnibus.name): \(omnibus.reportLine)") }
        if let m = r.report.mixed {
            if let g = m.group { lines.append(String(format: tx(english, "Group: %@", "组：%@"), g.reportLine)) }
            lines.append("\(r.levelLabel.isEmpty ? tx(english, "Within", "组内") : r.levelLabel): \(m.level.reportLine)")
            if let i = m.interaction { lines.append(String(format: tx(english, "Interaction: %@", "交互作用：%@"), i.reportLine)) }
        }
        for c in r.report.pairwise {
            let level = c.level.map { " [\($0)]" } ?? ""
            lines.append(String(format: tx(english, "%@ vs %@%@: %@ = %@, adjusted %@ %@", "%@ vs %@%@：%@ = %@，校正后 %@ %@"),
                                c.groupA, c.groupB, level, c.statisticName, StatsFormat.number(c.statistic), StatsFormat.p(c.pAdjusted), StatsFormat.stars(c.pAdjusted)))
        }
        for g in r.report.perGroup.keys.sorted() {
            if let t = r.report.perGroup[g] { lines.append("\(g) (\(r.report.perGroupLabel)): \(t.reportLine)") }
        }
        lines.append(contentsOf: r.notes)
        lines.append(tx(english, "n = animals. Generated with \(AppInfo.name) (RodentFlow 1.3 group-analysis methods).",
                        "n = 小鼠数。由 \(AppInfo.name) 生成（RodentFlow 1.3 组间分析方法）。"))
        return lines.joined(separator: "\n")
    }
}
