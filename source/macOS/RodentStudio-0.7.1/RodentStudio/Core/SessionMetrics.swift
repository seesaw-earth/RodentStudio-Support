// SessionMetrics.swift — the summary numbers of one session, as the task / group summaries use them.
//
// A summary is taken from the session's own results (SessionResultsEngine: the original analyzer with the
// session's calibration, analysis window, phase and parameters), so it holds exactly the numbers the
// Results tab shows. It is saved next to the tracking run in the app's Runs folder
// (rodentstudio_session_metrics.json) together with a key of everything it depends on; a summary whose
// key no longer matches (re-run, new calibration, other phase, newer analyzer) is never used.

import Foundation
import CryptoKit

struct SessionMetricEntry: Codable, Hashable {
    var key: String
    var nameEN: String
    var nameZH: String
    var unitEN: String
    var unitZH: String
    var decimals: Int
    var value: Double?
    /// Reference value for an optional one-sample test (only where the original app defines one).
    var chance: Double?
    /// Section of the original result screen (RodentLimb), English.
    var section: String?
}

struct SessionMetricSummary: Codable {
    static let currentFormat = 1
    var format = SessionMetricSummary.currentFormat
    var cacheKey: String
    var analyzer: String
    var computedAt: Date
    var videoID: UUID
    var runFolder: String
    var phase: String
    var primaryKey: String
    var metrics: [SessionMetricEntry]
    var series: [FlowResultSeries] = []
    /// Quality warnings of the analysis (English).
    var qcFlags: [String] = []
    var windowStart: Double = 0
    var windowLength: Double = 0
    /// Detection rate (RodentPose), pose coverage (RodentLimb) or tracked samples (RodentFlow), 0–1.
    var trackedFraction: Double?

    var values: [String: Double] {
        var out: [String: Double] = [:]
        for m in metrics {
            if let v = m.value, v.isFinite, out[m.key] == nil { out[m.key] = v }
        }
        return out
    }

    func value(_ key: String) -> Double? { values[key] }
    func entry(_ key: String) -> SessionMetricEntry? { metrics.first { $0.key == key } }
}

enum SessionMetrics {
    static let cacheFileName = "rodentstudio_session_metrics.json"

    /// Changes whenever the way summaries are taken from results changes, so saved summaries are recomputed.
    static var analyzerVersion: String {
        "RodentStudio session metrics 1; RodentPose 1.0 port; RodentLimb 1.1.2 port (result v\(AnalysisResult.currentVersion)); RodentFlow 1.3 port"
    }

    // MARK: Key

    /// Everything the numbers of a session depend on: task, run, the module's saved setup, phase and analyzer.
    static func cacheKey(video: VideoRecord, assay: StudyAssay) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var setupText = "none"
        if let c = video.calibration, video.hasSetup(for: assay) {
            let data: Data?
            switch assay.module {
            case .pose?: data = try? encoder.encode(c.pose)
            case .limb?: data = try? encoder.encode(c.limb)
            case .flow?: data = try? encoder.encode(c.flow)
            case nil: data = nil
            }
            setupText = data.map { String(decoding: $0, as: UTF8.self) } ?? "none"
        }
        var parts: [String] = []
        parts.append(analyzerVersion)
        parts.append(assay.rawValue)
        parts.append(video.id.uuidString)
        if let ref = video.tstChamber {
            parts.append("TST:" + ref.recordingID.uuidString + ":" + String(ref.chamber))
        }
        parts.append(video.runFolder ?? "")
        parts.append(video.runModel ?? "")
        parts.append(String(video.runFrames ?? -1))
        parts.append(video.runFinishedAt.map { String(format: "%.3f", $0.timeIntervalSince1970) } ?? "")
        parts.append(video.effectivePhase(for: assay))
        parts.append(setupText)
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Cache file (in the run folder of the app container; source videos are never touched)

    static func readCache(folder: URL, key: String) -> SessionMetricSummary? {
        let url = folder.appendingPathComponent(cacheFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let s = try? decoder.decode(SessionMetricSummary.self, from: data),
              s.format == SessionMetricSummary.currentFormat, s.cacheKey == key else { return nil }
        return s
    }

    static func writeCache(_ summary: SessionMetricSummary, folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(summary) else { return }
        try? data.write(to: folder.appendingPathComponent(cacheFileName), options: .atomic)
    }

    // MARK: From results

    static func summary(_ output: SessionOutput, video: VideoRecord, assay: StudyAssay, key: String) -> SessionMetricSummary {
        let window = SessionResultsEngine.analysisWindow(video, assay: assay)
        var s = SessionMetricSummary(cacheKey: key, analyzer: analyzerVersion, computedAt: Date(), videoID: video.id,
                                     runFolder: video.runFolder ?? "", phase: video.effectivePhase(for: assay),
                                     primaryKey: "", metrics: [])
        s.windowStart = window.start
        s.windowLength = window.length
        switch output {
        case .pose(let report, _):
            s.metrics = poseEntries(report)
            s.primaryKey = report.primary?.key ?? ""
            s.qcFlags = report.warnings.map { RPTexts.reportText($0) }
            s.trackedFraction = report.quality.detectionRate
        case .limb(let result, _, _):
            s.metrics = limbEntries(result)
            s.primaryKey = result.metrics.first(where: { $0.highlight })?.key ?? result.metrics.first?.key ?? ""
            s.qcFlags = result.notes.filter { $0.level != .info }.map { $0.text.en }
            s.trackedFraction = result.poseCoverage
        case .flow(let f):
            s.metrics = flowEntries(f)
            s.primaryKey = RFMetricCatalog.primaryKey(f.assay, phase: f.phase, metrics: f.computation.metrics)
            s.series = f.computation.series
            s.qcFlags = f.computation.qcFlags + f.notes.filter { $0.en.contains("changed after tracking") || $0.en.contains("earlier version") }.map(\.en)
            s.trackedFraction = f.computation.metrics["tracked_pct"].map { $0 / 100 }
        }
        return s
    }

    private static func poseEntries(_ report: AnalysisReport) -> [SessionMetricEntry] {
        var out: [SessionMetricEntry] = []
        var seen = Set<String>()
        for m in report.metrics where !seen.contains(m.key) {
            seen.insert(m.key)
            let value: Double? = (m.value?.isFinite ?? false) ? m.value : nil
            let entry = SessionMetricEntry(key: m.key,
                                           nameEN: RPTexts.metricLabel(m.title, key: m.key),
                                           nameZH: RPTexts.chinese(m.title),
                                           unitEN: RPTexts.english(m.unit),
                                           unitZH: RPTexts.chinese(m.unit),
                                           decimals: m.decimals,
                                           value: value,
                                           chance: poseChance(m.key),
                                           section: nil)
            out.append(entry)
        }
        return out
    }

    /// Reference values where RodentPose's own definition has a natural "no preference" value:
    /// preference / discrimination indices (a − b) / (a + b) → 0, RI (%) → 50, target quadrant (%) → 25
    /// (as RodentFlow defines them). Used only when the user asks for a one-sample test.
    static func poseChance(_ key: String) -> Double? {
        switch key {
        case "di", "di_20s", "sniff_index", "chamber_index", "turn_bias": return 0
        case "ri": return 50
        case "target_quadrant_pct": return 25
        default: return nil
        }
    }

    private static func limbEntries(_ result: AnalysisResult) -> [SessionMetricEntry] {
        var out: [SessionMetricEntry] = []
        var seen = Set<String>()
        for m in result.metrics where !seen.contains(m.key) {
            seen.insert(m.key)
            let value: Double? = (m.value?.isFinite ?? false) ? m.value : nil
            out.append(SessionMetricEntry(key: m.key, nameEN: m.label.en, nameZH: m.label.zh, unitEN: m.unit, unitZH: m.unit,
                                          decimals: m.decimals, value: value, chance: nil, section: m.group?.en))
        }
        return out
    }

    private static func flowEntries(_ f: FlowSessionOutput) -> [SessionMetricEntry] {
        var out: [SessionMetricEntry] = []
        for def in RFMetricCatalog.definitions(f.assay, metrics: f.computation.metrics) {
            guard let v = f.computation.metrics[def.key], v.isFinite else { continue }
            out.append(SessionMetricEntry(key: def.key, nameEN: def.englishName, nameZH: RFText.chineseText(def.englishName),
                                          unitEN: def.unit, unitZH: def.unit, decimals: def.decimals, value: v,
                                          chance: def.chance, section: nil))
        }
        return out
    }
}

// MARK: - Task-level definitions

extension TaskMetricDef {
    init(_ e: SessionMetricEntry) {
        self.init(key: e.key, nameEN: e.nameEN, nameZH: e.nameZH, unit: e.unitEN, unitZH: e.unitZH,
                  decimals: e.decimals, chance: e.chance)
    }
}

enum TaskMetricDefinitions {
    /// Measures of a task, in the order of the original result screens. Names are taken from the sessions of
    /// `preferredPhase` first (some RodentPose names depend on the phase, e.g. NOR training vs test).
    static func defs(_ summaries: [SessionMetricSummary], preferredPhase: String?) -> [TaskMetricDef] {
        var order: [String] = []
        var byKey: [String: TaskMetricDef] = [:]
        let preferred = summaries.filter { preferredPhase == nil || $0.phase == preferredPhase }
        let rest = summaries.filter { !(preferredPhase == nil || $0.phase == preferredPhase) }
        for s in preferred + rest {
            for e in s.metrics where byKey[e.key] == nil {
                byKey[e.key] = TaskMetricDef(e)
                order.append(e.key)
            }
        }
        return order.compactMap { byKey[$0] }
    }

    /// Primary measure for a phase: the one the original app highlights in most sessions of that phase.
    static func primaryKey(_ summaries: [SessionMetricSummary], phase: String) -> String {
        let pool = phase.isEmpty ? summaries : summaries.filter { $0.phase == phase }
        var counts: [String: Int] = [:]
        for s in pool where !s.primaryKey.isEmpty { counts[s.primaryKey, default: 0] += 1 }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? ""
    }

    /// Within-animal pairs: RodentFlow's own pairs, and the same comparisons on RodentPose's measures.
    static func pairs(_ assay: StudyAssay) -> [MetricPair] {
        if assay.flowAssay != nil { return TaskPairs.pairs(assay) }
        switch assay.paradigm {
        case .novelObject?:
            return [MetricPair(key: "novel_vs_familiar", nameEN: "Novel vs familiar exploration", nameZH: "新物体 vs 熟悉物体探索",
                               metricA: "exp_novel", metricB: "exp_familiar",
                               labelAEN: "Novel", labelAZH: "新物体", labelBEN: "Familiar", labelBZH: "熟悉物体")]
        case .threeChamber?:
            return [MetricPair(key: "stimulus_vs_other", nameEN: "Sniffing: stimulus vs other side", nameZH: "嗅探：刺激侧 vs 另一侧",
                               metricA: "sniff_stim", metricB: "sniff_other",
                               labelAEN: "Stimulus", labelAZH: "刺激侧", labelBEN: "Other", labelBZH: "另一侧")]
        case .elevatedPlusMaze?:
            return [MetricPair(key: "open_vs_closed", nameEN: "Open vs closed arm time", nameZH: "开放臂 vs 闭合臂时间",
                               metricA: "open_time", metricB: "closed_time",
                               labelAEN: "Open", labelAZH: "开放臂", labelBEN: "Closed", labelBZH: "闭合臂")]
        case .fearConditioning?:
            return [MetricPair(key: "baseline_vs_cs", nameEN: "Baseline vs CS freezing", nameZH: "基线 vs CS 僵直",
                               metricA: "freeze_baseline_pct", metricB: "freeze_cs_mean",
                               labelAEN: "Baseline", labelAZH: "基线", labelBEN: "CS", labelBZH: "CS")]
        default:
            return []
        }
    }
}
