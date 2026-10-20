// TST-specific analyzer output adapted into RodentStudio's ordinary SessionMetricSummary.
// Standard TaskDataModel / group statistics / task exports are unchanged.
//
// Measures follow the usual TST reporting (Steru 1985; Can et al. 2012, JoVE): every mouse is timed from
// its OWN suspension; the primary measure is immobility in the last 4 min of a 6-min test (minutes 2–6),
// with minutes 0–2, the whole 0–6 min test, latency and bout structure as secondary measures. The
// per-minute immobility is also supplied as a series, so the group page can show the time course
// (mean ± SEM per group, n = animals) and test group × minute with the existing mixed ANOVA.
import Foundation

enum TSTSessionMetrics {
    static let seriesKey = "tst_immobility_per_minute"
    static let seriesName = "Immobility per minute"
    static let seriesXLabel = "Minute after suspension"

    /// "2–6 min" style label of a window given in seconds.
    static func minutes(_ a: Double, _ b: Double, dash: String = "–") -> String {
        func m(_ s: Double) -> String {
            let v = s / 60
            return abs(v - v.rounded()) < 0.01 ? String(Int(v.rounded())) : String(format: "%.1f", v)
        }
        return m(a) + dash + m(b)
    }

    static func load(video: VideoRecord, key: String) -> SessionMetricSummary? {
        guard let ref = video.tstChamber, let task = video.experimentID,
              let record = TSTTaskArchive.load(task, record: ref.recordingID),
              let chamber = record.summaries.first(where: { $0.chamber == ref.chamber && $0.analysed })
        else { return nil }
        func metric(_ key: String, _ en: String, _ zh: String, _ unitEN: String, _ unitZH: String,
                    _ value: Double?, _ decimals: Int = 2) -> SessionMetricEntry {
            SessionMetricEntry(key: key, nameEN: en, nameZH: zh, unitEN: unitEN, unitZH: unitZH,
                               decimals: decimals, value: value?.isFinite == true ? value : nil,
                               chance: nil, section: nil)
        }
        // Archives written before the standard windows existed: their "last window" is the primary value.
        let testLength = chamber.testLengthSec ?? record.settings.standardTestSec
        let primaryStart = chamber.primaryStartSec ?? max(0, testLength - record.settings.lastWindowSec)
        let primaryLabel = minutes(primaryStart, testLength)
        let earlyLabel = minutes(0, primaryStart)
        let testLabel = minutes(0, testLength)
        // English names go into the exports: plain ASCII hyphen.
        let primaryEN = minutes(primaryStart, testLength, dash: "-")
        let earlyEN = minutes(0, primaryStart, dash: "-")
        let testEN = minutes(0, testLength, dash: "-")

        var metrics: [SessionMetricEntry] = [
            metric("tst_imm_primary_s", "Immobility, min " + primaryEN, "不动时间（第 " + primaryLabel + " 分钟）", "s", "秒",
                   chamber.primaryImmobileSec ?? chamber.immobileLastWindowSec),
            metric("tst_imm_primary_pct", "Immobility %, min " + primaryEN, "不动百分比（第 " + primaryLabel + " 分钟）", "%", "%",
                   chamber.primaryImmobilePercent),
            metric("tst_imm_early_s", "Immobility, min " + earlyEN, "不动时间（第 " + earlyLabel + " 分钟）", "s", "秒",
                   chamber.earlyImmobileSec),
            metric("tst_imm_test_s", "Immobility, min " + testEN, "不动时间（第 " + testLabel + " 分钟）", "s", "秒",
                   chamber.testImmobileSec),
            metric("tst_imm_test_pct", "Immobility %, min " + testEN, "不动百分比（第 " + testLabel + " 分钟）", "%", "%",
                   chamber.testImmobilePercent),
            metric("tst_latency_s", "Latency to first immobility", "首次不动潜伏期", "s", "秒", chamber.latencySec),
            metric("tst_bouts", "Immobility bouts, min " + testEN, "不动次数（第 " + testLabel + " 分钟）", "count", "次",
                   Double(chamber.bouts), 0),
            metric("tst_mean_bout_s", "Mean immobility bout", "平均不动持续时间", "s", "秒", chamber.meanBoutSec),
            metric("tst_longest_bout_s", "Longest immobility bout", "最长不动持续时间", "s", "秒", chamber.longestBoutSec),
            metric("tst_intensity", "Mobility intensity (motion while mobile)", "运动强度（活动时的运动量）", "% body", "% 鼠体",
                   chamber.mobilityIntensity),
            metric("tst_immobile_s", "Immobility, whole recording", "不动时间（全程）", "s", "秒", chamber.immobileTotalSec),
            metric("tst_immobile_pct", "Immobility %, whole recording", "不动百分比（全程）", "%", "%", chamber.immobilePercent),
            metric("tst_no_mouse_pct", "No-mouse / segmentation failure", "漏检／分割失败", "%", "%", chamber.noMousePercent),
            metric("tst_test_coverage_pct", "Recorded share of the min " + testEN + " test", "第 " + testLabel + " 分钟测试的录制比例",
                   "%", "%", chamber.testCoverage.map { 100 * $0 }, 0),
        ]
        for (i, seconds) in chamber.perMinuteImmobileSec.enumerated() {
            metrics.append(metric("tst_minute_\(i + 1)_s", "Minute \(i + 1) immobility", "第 \(i + 1) 分钟不动", "s", "秒", seconds))
        }

        let onset = chamber.onsetSec ?? 0
        // Time course for the group page: whole minutes of the standard test that were fully recorded.
        let recordedSinceSuspension = record.settings.durationSec - onset
        let testMinutes = Int((testLength / 60).rounded(.down))
        var x: [Double] = [], y: [Double] = []
        for m in 0..<min(testMinutes, chamber.perMinuteImmobileSec.count) where Double(m + 1) * 60 <= recordedSinceSuspension + 0.5 {
            x.append(Double(m + 1))
            y.append(chamber.perMinuteImmobileSec[m])
        }
        // Stored in English like every other series (exports are English); the interface translates the
        // labels with RFText (Resources/RodentFlowChinese.json).
        let series = x.isEmpty ? [] : [FlowResultSeries(key: seriesKey, name: seriesName, unit: "s",
                                                         xLabel: seriesXLabel, x: x, y: y)]

        var out = SessionMetricSummary(cacheKey: key,
                                       analyzer: "TSTScorer6 / multi-chamber · measure: " + record.settings.metric.rawValue
                                           + (record.settings.useRefinedOutline ? " · refined outline" : " · original outline")
                                           + (chamber.onsetSec != nil ? " · timed from each mouse's suspension" : ""),
                                       computedAt: record.savedAt, videoID: video.id,
                                       runFolder: video.runFolder ?? "", phase: video.effectivePhase(for: .tstMultiChamber),
                                       primaryKey: "tst_imm_primary_s", metrics: metrics)
        out.series = series
        out.windowStart = record.settings.startSec + onset
        out.windowLength = testLength
        out.trackedFraction = max(0, min(1, 1 - chamber.noMousePercent / 100))
        if let coverage = chamber.testCoverage, coverage < 0.98 {
            out.qcFlags.append(String(format: "Only %.0f%% of the %@ min test was recorded after this mouse's suspension", 100 * coverage, testEN))
        }
        if chamber.noMousePercent > 10 { out.qcFlags.append("No-mouse / segmentation-failure frames exceed 10%; manually review") }
        out.qcFlags.append("TST multi-chamber scoring has not been validated against blinded manual scoring")
        return out
    }
}

// MARK: - TST data export (CSV + JSON)
//
// What is saved and why (see TST_UX_REVISION_CN.md, round 7):
//  · Identity: task, session, animal, group, sex, date, session #, inclusion + reason, review — so every row
//    can be traced back and excluded sessions stay visible (they are flagged, not dropped).
//  · Timing: suspension time, key frame and analysed span in VIDEO seconds, test length, primary window and
//    the recorded share of the test — so a reader can check every value against the original video.
//  · Measures (all from each mouse's own suspension): ★ immobility in the primary window (s, %), minutes
//    0–2, the whole 0–6 min test (s, %), latency, bouts / mean / longest bout, mobility intensity, the
//    whole recording, and immobility per minute.
//  · QC: no-mouse %, test coverage, flags. · Method: measure, threshold, minimum bout, smoothing, sampling,
//    detector, outline — values are only comparable between sessions scored the same way.
//  · Bouts: start / end of every immobility bout, for ethograms or re-analysis with other bout criteria.
//  · Frames: the motion signal itself, frame by frame (smoothed signal that was scored, the raw signal of
//    the chosen measure and its pixel components when the archive has them, immobile / no-mouse flags,
//    window) and a 1-s binned version — so immobility can be re-scored with any threshold or criterion,
//    motion can be plotted, and the automatic scoring can be compared with hand scoring frame by frame.
//  · Animal level: the mean of an animal's INCLUDED sessions (n = animals), ready for statistics.
// Values come from the saved analysis of each recording (what the task pages show), never from the
// settings currently open in a recording sheet.

enum TSTExport {
    static let files: [(String, String, String)] = [
        ("tst_sessions.csv", "one row per session: animal, inclusion, timing, every TST measure, minutes 1–6, QC and method",
         "每次实验一行：小鼠、是否纳入、时间信息、全部 TST 指标、第 1-6 分钟、质控和方法"),
        ("tst_animals.csv", "one row per animal: mean of its included sessions (n = animals) — use this for statistics",
         "每只小鼠一行：其纳入实验的均值（n = 小鼠数），统计用这一份"),
        ("tst_minutes_long.csv", "one row per session × minute after suspension (repeated measures / mixed models)",
         "每次实验 × 挂上后每分钟一行（重复测量／混合模型）"),
        ("tst_bouts.csv", "every immobility bout: start, end, duration (from suspension and in the video)",
         "每个不动片段：开始、结束、时长（从挂上时起，以及在视频中的时间）"),
        ("tst_frames_long.csv", "frame-based motion: one row per session × analysed frame (motion, raw components, immobile, no mouse, window)",
         "逐帧运动：每次实验 × 每个分析帧一行（运动量、原始分量、是否不动、是否无小鼠、时间窗）"),
        ("tst_motion_1s.csv", "motion binned per second after suspension: mean motion, immobile and no-mouse fraction",
         "挂上后逐秒汇总的运动：平均运动量、不动比例、无小鼠比例"),
        ("tst_export.json", "everything above except the frames, in one structured file, with the settings of each recording and the definitions",
         "除逐帧数据外的全部内容的结构化文件，含每段录像的参数和指标定义"),
        ("tst_frames.json", "the frame-based motion of every session as arrays (for scripts)",
         "每次实验的逐帧运动数组（供脚本读取）"),
        ("tst_data_dictionary.csv", "what each column means and its unit", "每一列的含义和单位"),
    ]

    // MARK: Model

    struct Definition: Codable { var column: String; var unit: String; var description: String }

    struct Bout: Codable {
        var index: Int
        var startFromSuspensionS: Double
        var endFromSuspensionS: Double
        var durationS: Double
        var startVideoS: Double
        var inTest: Bool
    }

    struct Measures: Codable {
        var immobilePrimaryS: Double?
        var immobilePrimaryPct: Double?
        var immobileEarlyS: Double?
        var immobileTestS: Double?
        var immobileTestPct: Double?
        var latencyS: Double?
        var boutsTest: Int
        var meanBoutS: Double
        var longestBoutS: Double
        var mobilityIntensityPctBody: Double?
        /// Mean / median of the scored (smoothed) motion over the test frames with the mouse visible.
        var meanMotionTestPctBody: Double?
        var medianMotionTestPctBody: Double?
        var immobileWholeRecordingS: Double
        var immobileWholeRecordingPct: Double
        /// nil = that minute was not fully recorded.
        var perMinuteImmobileS: [Double?]
    }

    struct Session: Codable {
        var sessionID: String
        var animalID: String
        var group: String
        var sex: String
        var sessionDate: String
        var sessionNumber: Int?
        var included: Bool
        var exclusionReason: String
        var reviewVerdict: String
        var reviewNotes: String
        var recordingID: String
        var video: String
        var chamber: Int
        var chambersInRecording: Int
        var suspendedAtVideoS: Double
        var keyFrameVideoS: Double
        var analysisStartVideoS: Double
        var analysisEndVideoS: Double
        var recordedAfterSuspensionS: Double
        var testLengthS: Double
        var primaryWindowStartS: Double
        var primaryWindowEndS: Double
        var testCoveragePct: Double?
        var noMousePct: Double
        var qcFlags: [String]
        var measures: Measures
        var bouts: [Bout]
    }

    struct Recording: Codable {
        var recordingID: String
        var video: String
        var analysedAt: Date
        var detector: String
        var measure: String
        var immobilityThresholdPct: Double
        var minimumBoutS: Double
        var smoothingS: Double
        var sampleFPS: Double
        var refinedOutline: Bool
        var timedFromEachSuspension: Bool
        var keyFrameVideoS: Double
        var analysisStartVideoS: Double
        var analysisEndVideoS: Double
    }

    struct Animal: Codable {
        var animalID: String
        var group: String
        var sex: String
        var includedSessions: Int
        var sessionNumbers: [Int]
        var means: [String: Double]
    }

    struct Document: Codable {
        var format = "RodentStudio TST export"
        var formatVersion = 1
        var exportedAt: Date
        var taskID: String
        var task: String
        var taskNote: String
        var groupFilter: String?
        var notes: [String]
        var definitions: [Definition]
        var recordings: [Recording]
        var sessions: [Session]
        var animals: [Animal]
    }

    // MARK: Definitions (dictionary + JSON)

    static let definitions: [Definition] = [
        .init(column: "session_id", unit: "", description: "RodentStudio session ID (one chamber of one recording)"),
        .init(column: "included", unit: "true/false", description: "false = excluded from animal means and group statistics (reason in exclusion_reason)"),
        .init(column: "review_verdict", unit: "", description: "manual check of the scoring: unreviewed / passed / issues"),
        .init(column: "suspended_at_video_s", unit: "s", description: "when this mouse was suspended, in video time; every measure is timed from here"),
        .init(column: "key_frame_video_s", unit: "s", description: "first moment every selected chamber had a mouse (or the start set by hand)"),
        .init(column: "analysis_start_video_s / analysis_end_video_s", unit: "s", description: "part of the video that was analysed"),
        .init(column: "recorded_after_suspension_s", unit: "s", description: "video available after this mouse's suspension"),
        .init(column: "test_length_s", unit: "s", description: "standard test length (default 360 s = 6 min)"),
        .init(column: "primary_window_start_s / primary_window_end_s", unit: "s from suspension", description: "primary window (default 120-360 s = minutes 2-6)"),
        .init(column: "test_coverage_pct", unit: "%", description: "share of the standard test that was recorded; < 98 % means the test is incomplete"),
        .init(column: "immobile_primary_s", unit: "s", description: "PRIMARY MEASURE: immobility in the primary window"),
        .init(column: "immobile_primary_pct", unit: "%", description: "immobility as % of the primary window frames with the mouse visible"),
        .init(column: "immobile_early_s", unit: "s", description: "immobility before the primary window (default minutes 0-2)"),
        .init(column: "immobile_test_s / immobile_test_pct", unit: "s / %", description: "immobility in the whole standard test (default minutes 0-6)"),
        .init(column: "latency_s", unit: "s", description: "time from suspension to the first immobility bout (empty = none)"),
        .init(column: "bouts_test / mean_bout_s / longest_bout_s", unit: "count / s / s", description: "immobility bouts within the standard test"),
        .init(column: "mobility_intensity_pct_body", unit: "% body", description: "mean motion while mobile within the test (struggling vigour)"),
        .init(column: "immobile_min<k>_s", unit: "s", description: "immobility in minute k after suspension (0-60 s; empty = minute not fully recorded)"),
        .init(column: "immobile_whole_recording_s / _pct", unit: "s / %", description: "immobility from suspension to the end of the analysed video (not comparable between videos of different length)"),
        .init(column: "no_mouse_pct", unit: "%", description: "QC: frames without the mouse (climbing, out of view, taken down); review above 10 %"),
        .init(column: "measure", unit: "", description: "motion measure: box = pixel change in the motion box after swing alignment; shape; pixel"),
        .init(column: "immobility_threshold_pct", unit: "% body", description: "motion below this is immobile"),
        .init(column: "min_bout_s", unit: "s", description: "shorter immobile runs are not counted"),
        .init(column: "smoothing_s / sample_fps", unit: "s / fps", description: "median smoothing of the motion signal; frames analysed per second"),
        .init(column: "start_from_suspension_s / end_from_suspension_s (bouts)", unit: "s", description: "bout limits from this mouse's suspension; in_test = starts within the standard test"),
        .init(column: "recorded_s (minutes)", unit: "s", description: "seconds of that minute that were recorded; complete = 60 s"),
        .init(column: "mean_motion_test_pct_body / median_motion_test_pct_body", unit: "% body", description: "mean / median of the scored motion over the test frames with the mouse visible"),
        .init(column: "frame (frames)", unit: "", description: "index of the analysed frame (frames are sampled at sample_fps from analysis_start_video_s)"),
        .init(column: "time_from_suspension_s / video_time_s (frames)", unit: "s", description: "frame time from this mouse's suspension (negative = before) and in the video"),
        .init(column: "window (frames, 1 s)", unit: "", description: "before_suspension / early (min 0-2) / primary (min 2-6) / after_test"),
        .init(column: "motion_pct_body (frames)", unit: "% body", description: "SCORED motion signal: chosen measure, gaps interpolated, median-smoothed; empty when no mouse"),
        .init(column: "motion_raw_pct_body (frames)", unit: "% body", description: "chosen measure before interpolation and smoothing (needs an analysis saved by 0.7.1 round 6+)"),
        .init(column: "box_change_px / box_body_px / box_mouse_present (frames)", unit: "px", description: "box measure: changed pixels in the motion box after swing alignment, reference body size, mouse seen in the box"),
        .init(column: "pixel_change_px / shape_change_px / area_px / cx / cy (frames)", unit: "px", description: "outline measures: changed pixels, aligned silhouette change, mouse area and centroid (processed-image pixels)"),
        .init(column: "below_threshold / immobile / no_mouse (frames)", unit: "0/1", description: "motion below the threshold; scored immobile (after the minimum bout); mouse not found"),
        .init(column: "mean_motion_pct_body / immobile_fraction / no_mouse_fraction (1 s)", unit: "% body / 0-1", description: "per second after suspension, over the frames of that second"),
    ]

    // MARK: Build

    @MainActor
    static func document(experiment: NativeExperiment, sessions: [VideoRecord], group: String?) -> Document {
        var archives: [UUID: TSTStoredRecording] = [:]
        var out: [Session] = []
        for v in sessions {
            guard let ref = v.tstChamber, v.runState == .complete else { continue }
            if archives[ref.recordingID] == nil, let r = TSTTaskArchive.load(experiment.id, record: ref.recordingID) {
                archives[ref.recordingID] = r
            }
            guard let r = archives[ref.recordingID],
                  let s = r.summaries.first(where: { $0.chamber == ref.chamber && $0.analysed }) else { continue }
            out.append(session(v, ref: ref, record: r, summary: s))
        }
        let recordings = archives.values.sorted { $0.savedAt < $1.savedAt }.map { r in
            Recording(recordingID: r.id.uuidString, video: r.videoName, analysedAt: r.savedAt, detector: r.detector,
                      measure: r.settings.metric.rawValue, immobilityThresholdPct: r.settings.immobilityThreshold,
                      minimumBoutS: r.settings.minBoutSec, smoothingS: r.settings.smoothSec, sampleFPS: r.fps,
                      refinedOutline: r.settings.useRefinedOutline,
                      timedFromEachSuspension: r.settings.chamberOnsetSec != nil,
                      keyFrameVideoS: r.keyFrameTime, analysisStartVideoS: r.settings.startSec,
                      analysisEndVideoS: r.settings.startSec + r.settings.durationSec)
        }
        var notes = [
            "Every measure is timed from each mouse's own suspension.",
            "Excluded sessions are listed with included = false and are left out of the animal means.",
            "Automatic TST scoring has not been validated against blinded manual scoring.",
            "JSON: a value that is not available is left out; an unrecorded minute is null.",
        ]
        let methods = Set(recordings.map { "\($0.measure)|\($0.immobilityThresholdPct)|\($0.minimumBoutS)|\($0.smoothingS)" })
        if methods.count > 1 {
            notes.append("WARNING: recordings were scored with different measures / thresholds / minimum bouts; values are not directly comparable.")
        }
        // English task name (displayTitle would be the localized assay title).
        return Document(exportedAt: Date(), taskID: experiment.id.uuidString, task: experiment.name,
                        taskNote: experiment.notes ?? "", groupFilter: group, notes: notes, definitions: definitions,
                        recordings: recordings, sessions: out, animals: animals(out))
    }

    private static func session(_ v: VideoRecord, ref: TSTChamberReference, record r: TSTStoredRecording,
                                summary s: ChamberSummary) -> Session {
        let settings = r.settings
        let onset = s.onsetSec ?? 0
        let test = s.testLengthSec ?? settings.standardTestSec
        let primaryStart = s.primaryStartSec ?? max(0, test - settings.lastWindowSec)
        let recorded = max(0, settings.durationSec - onset)
        // Minutes of the standard test; a minute that was not fully recorded is left empty.
        let testMinutes = Int((test / 60).rounded(.down))
        let perMinute: [Double?] = (0..<testMinutes).map { m in
            guard m < s.perMinuteImmobileSec.count, Double(m + 1) * 60 <= recorded + 0.5 else { return nil }
            return s.perMinuteImmobileSec[m]
        }
        var bouts: [Bout] = []
        let traceIndex = ref.chamber - 1
        if let traces = r.traces, traceIndex >= 0, traceIndex < traces.count {
            let tr = traces[traceIndex]
            let dt = 1 / max(r.fps, 0.001)
            var k = 0
            while k < tr.immobile.count {
                guard tr.immobile[k], k < tr.time.count else { k += 1; continue }
                var e = k
                while e + 1 < tr.immobile.count, tr.immobile[e + 1] { e += 1 }
                let start = tr.time[k] - onset
                let end = (e < tr.time.count ? tr.time[e] : tr.time[k]) + dt - onset
                bouts.append(Bout(index: bouts.count + 1, startFromSuspensionS: start, endFromSuspensionS: end,
                                  durationS: end - start, startVideoS: settings.startSec + tr.time[k], inTest: start < test))
                k = e + 1
            }
        }
        var testMotion: [Double] = []
        if let traces = r.traces, traceIndex >= 0, traceIndex < traces.count {
            let tr = traces[traceIndex]
            for k in tr.time.indices where k < tr.motion.count && k < tr.noMouse.count && !tr.noMouse[k] {
                let rel = tr.time[k] - onset
                if rel >= 0, rel < test, tr.motion[k].isFinite { testMotion.append(tr.motion[k]) }
            }
        }
        let meanMotion: Double? = testMotion.isEmpty ? nil : testMotion.reduce(0, +) / Double(testMotion.count)
        let medianMotion: Double? = testMotion.isEmpty ? nil : testMotion.sorted()[testMotion.count / 2]
        var flags: [String] = []
        if let c = s.testCoverage, c < 0.98 { flags.append(String(format: "test incomplete: %.0f%% recorded", 100 * c)) }
        if s.noMousePercent > 10 { flags.append("no-mouse frames > 10%") }
        if s.onsetSec == nil { flags.append("timed from the key frame (older analysis)") }
        let review = v.currentReview
        return Session(sessionID: v.id.uuidString, animalID: v.animalID, group: v.groupKey, sex: v.sex ?? "",
                       sessionDate: v.sessionDate ?? "", sessionNumber: v.sessionNumber, included: !v.isExcluded,
                       exclusionReason: v.isExcluded ? (v.exclusionReason ?? "") : "",
                       reviewVerdict: (review?.verdict ?? .unreviewed).rawValue, reviewNotes: review?.notes ?? "",
                       recordingID: r.id.uuidString, video: r.videoName, chamber: ref.chamber,
                       chambersInRecording: r.summaries.count,
                       suspendedAtVideoS: settings.startSec + onset, keyFrameVideoS: r.keyFrameTime,
                       analysisStartVideoS: settings.startSec, analysisEndVideoS: settings.startSec + settings.durationSec,
                       recordedAfterSuspensionS: recorded, testLengthS: test,
                       primaryWindowStartS: primaryStart, primaryWindowEndS: test,
                       testCoveragePct: s.testCoverage.map { 100 * $0 }, noMousePct: s.noMousePercent, qcFlags: flags,
                       measures: Measures(immobilePrimaryS: s.primaryImmobileSec ?? s.immobileLastWindowSec,
                                          immobilePrimaryPct: s.primaryImmobilePercent,
                                          immobileEarlyS: s.earlyImmobileSec,
                                          immobileTestS: s.testImmobileSec, immobileTestPct: s.testImmobilePercent,
                                          latencyS: s.latencySec, boutsTest: s.bouts, meanBoutS: s.meanBoutSec,
                                          longestBoutS: s.longestBoutSec, mobilityIntensityPctBody: s.mobilityIntensity,
                                          meanMotionTestPctBody: meanMotion, medianMotionTestPctBody: medianMotion,
                                          immobileWholeRecordingS: s.immobileTotalSec,
                                          immobileWholeRecordingPct: s.immobilePercent,
                                          perMinuteImmobileS: perMinute),
                       bouts: bouts)
    }

    /// Numbers averaged per animal (included sessions only), in column order.
    private static func animalValues(_ x: Session) -> [(String, Double?)] {
        let m = x.measures
        var out: [(String, Double?)] = [
            ("immobile_primary_s", m.immobilePrimaryS), ("immobile_primary_pct", m.immobilePrimaryPct),
            ("immobile_early_s", m.immobileEarlyS), ("immobile_test_s", m.immobileTestS),
            ("immobile_test_pct", m.immobileTestPct), ("latency_s", m.latencyS),
            ("bouts_test", Double(m.boutsTest)), ("mean_bout_s", m.meanBoutS), ("longest_bout_s", m.longestBoutS),
            ("mobility_intensity_pct_body", m.mobilityIntensityPctBody),
            ("mean_motion_test_pct_body", m.meanMotionTestPctBody), ("median_motion_test_pct_body", m.medianMotionTestPctBody),
            ("no_mouse_pct", x.noMousePct),
        ]
        for (i, v) in m.perMinuteImmobileS.enumerated() { out.append(("immobile_min\(i + 1)_s", v)) }
        return out
    }

    private static func animals(_ sessions: [Session]) -> [Animal] {
        var order: [String] = []
        var byAnimal: [String: [Session]] = [:]
        for s in sessions where s.included {
            let key = s.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            if byAnimal[key] == nil { order.append(key) }
            byAnimal[key, default: []].append(s)
        }
        return order.map { key in
            let list = byAnimal[key] ?? []
            var sums: [String: (Double, Int)] = [:]
            for s in list {
                for (k, v) in animalValues(s) {
                    guard let v, v.isFinite else { continue }
                    let old = sums[k] ?? (0, 0)
                    sums[k] = (old.0 + v, old.1 + 1)
                }
            }
            var means: [String: Double] = [:]
            for (k, v) in sums where v.1 > 0 { means[k] = v.0 / Double(v.1) }
            return Animal(animalID: list.first?.animalID ?? key, group: list.first?.group ?? "", sex: list.first?.sex ?? "",
                          includedSessions: list.count, sessionNumbers: list.compactMap(\.sessionNumber).sorted(), means: means)
        }
    }

    // MARK: Write

    private static func row(_ fields: [String]) -> String { fields.map { FigureExport.csv($0) }.joined(separator: ",") }
    private static func num(_ v: Double?, _ d: Int = 3) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(d)f", v)
    }

    @MainActor
    @discardableResult
    static func write(experiment: NativeExperiment, sessions: [VideoRecord], group: String?, to folder: URL) throws -> Document {
        let doc = document(experiment: experiment, sessions: sessions, group: group)
        let byRecording = Dictionary(uniqueKeysWithValues: doc.recordings.map { ($0.recordingID, $0) })
        let minuteCount = doc.sessions.map(\.measures.perMinuteImmobileS.count).max() ?? 0

        // Sessions
        var cols = ["task", "session_id", "animal_id", "group", "sex", "session_date", "session_number", "included",
                    "exclusion_reason", "review_verdict", "review_notes", "recording_id", "video", "chamber",
                    "chambers_in_recording", "suspended_at_video_s", "key_frame_video_s", "analysis_start_video_s",
                    "analysis_end_video_s", "recorded_after_suspension_s", "test_length_s", "primary_window_start_s",
                    "primary_window_end_s", "test_coverage_pct", "immobile_primary_s", "immobile_primary_pct",
                    "immobile_early_s", "immobile_test_s", "immobile_test_pct", "latency_s", "bouts_test", "mean_bout_s",
                    "longest_bout_s", "mobility_intensity_pct_body", "mean_motion_test_pct_body", "median_motion_test_pct_body"]
        cols += (0..<minuteCount).map { "immobile_min\($0 + 1)_s" }
        cols += ["immobile_whole_recording_s", "immobile_whole_recording_pct", "no_mouse_pct", "qc_flags", "measure",
                 "immobility_threshold_pct", "min_bout_s", "smoothing_s", "sample_fps", "detector", "refined_outline", "analysed_at"]
        var lines = [row(cols)]
        let iso = ISO8601DateFormatter()
        for s in doc.sessions {
            let m = s.measures
            let r = byRecording[s.recordingID]
            var f = [doc.task, s.sessionID, s.animalID, s.group, s.sex, s.sessionDate, s.sessionNumber.map { String($0) } ?? "",
                     s.included ? "true" : "false", s.exclusionReason, s.reviewVerdict, s.reviewNotes, s.recordingID, s.video,
                     String(s.chamber), String(s.chambersInRecording), num(s.suspendedAtVideoS), num(s.keyFrameVideoS),
                     num(s.analysisStartVideoS), num(s.analysisEndVideoS), num(s.recordedAfterSuspensionS), num(s.testLengthS),
                     num(s.primaryWindowStartS), num(s.primaryWindowEndS), num(s.testCoveragePct, 1),
                     num(m.immobilePrimaryS), num(m.immobilePrimaryPct), num(m.immobileEarlyS), num(m.immobileTestS),
                     num(m.immobileTestPct), num(m.latencyS), String(m.boutsTest), num(m.meanBoutS), num(m.longestBoutS),
                     num(m.mobilityIntensityPctBody), num(m.meanMotionTestPctBody), num(m.medianMotionTestPctBody)]
            f += (0..<minuteCount).map { $0 < m.perMinuteImmobileS.count ? num(m.perMinuteImmobileS[$0]) : "" }
            f += [num(m.immobileWholeRecordingS), num(m.immobileWholeRecordingPct), num(s.noMousePct), s.qcFlags.joined(separator: "; "),
                  r?.measure ?? "", num(r?.immobilityThresholdPct), num(r?.minimumBoutS), num(r?.smoothingS), num(r?.sampleFPS, 2),
                  r?.detector ?? "", r.map { $0.refinedOutline ? "true" : "false" } ?? "",
                  r.map { iso.string(from: $0.analysedAt) } ?? ""]
            lines.append(row(f))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("tst_sessions.csv"))

        // Animals
        let valueKeys = ["immobile_primary_s", "immobile_primary_pct", "immobile_early_s", "immobile_test_s", "immobile_test_pct",
                         "latency_s", "bouts_test", "mean_bout_s", "longest_bout_s", "mobility_intensity_pct_body",
                         "mean_motion_test_pct_body", "median_motion_test_pct_body", "no_mouse_pct"]
            + (0..<minuteCount).map { "immobile_min\($0 + 1)_s" }
        lines = [row(["task", "animal_id", "group", "sex", "included_sessions", "session_numbers"] + valueKeys)]
        for a in doc.animals {
            lines.append(row([doc.task, a.animalID, a.group, a.sex, String(a.includedSessions),
                              a.sessionNumbers.map { String($0) }.joined(separator: ";")] + valueKeys.map { num(a.means[$0]) }))
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("tst_animals.csv"))

        // Minutes (long)
        lines = [row(["task", "session_id", "animal_id", "group", "sex", "session_number", "included", "minute", "window",
                      "immobile_s", "recorded_s", "complete"])]
        for s in doc.sessions {
            let primaryFirstMinute = Int((s.primaryWindowStartS / 60).rounded(.down)) + 1
            for (i, v) in s.measures.perMinuteImmobileS.enumerated() {
                let recorded = max(0, min(60, s.recordedAfterSuspensionS - Double(i) * 60))
                lines.append(row([doc.task, s.sessionID, s.animalID, s.group, s.sex, s.sessionNumber.map { String($0) } ?? "",
                                  s.included ? "true" : "false", String(i + 1), i + 1 >= primaryFirstMinute ? "primary" : "early",
                                  num(v), num(recorded, 1), recorded >= 59.5 ? "true" : "false"]))
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("tst_minutes_long.csv"))

        // Bouts
        lines = [row(["task", "session_id", "animal_id", "group", "included", "bout", "start_from_suspension_s",
                      "end_from_suspension_s", "duration_s", "start_video_s", "in_test"])]
        for s in doc.sessions {
            for b in s.bouts {
                lines.append(row([doc.task, s.sessionID, s.animalID, s.group, s.included ? "true" : "false", String(b.index),
                                  num(b.startFromSuspensionS), num(b.endFromSuspensionS), num(b.durationS), num(b.startVideoS),
                                  b.inTest ? "true" : "false"]))
            }
        }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("tst_bouts.csv"))

        // Dictionary
        lines = [row(["column", "unit", "description"])] + definitions.map { row([$0.column, $0.unit, $0.description]) }
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("tst_data_dictionary.csv"))

        // JSON: snake_case keys like the CSV columns; an unrecorded minute is null.
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let data = try enc.encode(doc)
        try data.write(to: folder.appendingPathComponent("tst_export.json"), options: .atomic)
        try writeFrames(doc, taskID: experiment.id, to: folder)
        return doc
    }

    // MARK: Frame-based motion

    /// Per-frame arrays of one session (also the content of tst_frames.json).
    struct FrameSeries: Codable {
        var sessionID: String
        var animalID: String
        var group: String
        var included: Bool
        var measure: String
        var immobilityThresholdPct: Double
        var sampleFPS: Double
        var suspendedAtVideoS: Double
        var analysisStartVideoS: Double
        var timeFromSuspensionS: [Double]
        var motionPctBody: [Double?]
        var motionRawPctBody: [Double?]?
        var immobile: [Int]
        var noMouse: [Int]
    }

    private static func rounded(_ v: Double, _ d: Double = 1000) -> Double { (v * d).rounded() / d }

    private static func window(_ rel: Double, primaryStart: Double, test: Double) -> String {
        if rel < 0 { return "before_suspension" }
        if rel < primaryStart { return "early" }
        if rel < test { return "primary" }
        return "after_test"
    }

    /// Writes tst_frames_long.csv, tst_motion_1s.csv and tst_frames.json. Streams the CSV (it can have
    /// several hundred thousand rows).
    @MainActor
    private static func writeFrames(_ doc: Document, taskID: UUID, to folder: URL) throws {
        let framesURL = folder.appendingPathComponent("tst_frames_long.csv")
        let binsURL = folder.appendingPathComponent("tst_motion_1s.csv")
        FileManager.default.createFile(atPath: framesURL.path, contents: nil)
        FileManager.default.createFile(atPath: binsURL.path, contents: nil)
        let frames = try FileHandle(forWritingTo: framesURL)
        let bins = try FileHandle(forWritingTo: binsURL)
        defer { try? frames.close(); try? bins.close() }
        var buffer = row(["task", "session_id", "animal_id", "group", "sex", "included", "frame", "time_from_suspension_s",
                          "video_time_s", "window", "motion_pct_body", "motion_raw_pct_body", "threshold_pct", "below_threshold",
                          "immobile", "no_mouse", "box_change_px", "box_body_px", "box_mouse_present", "pixel_change_px",
                          "shape_change_px", "area_px", "cx", "cy"]) + "\n"
        var binBuffer = row(["task", "session_id", "animal_id", "group", "sex", "included", "second_from_suspension", "window",
                             "frames", "mean_motion_pct_body", "immobile_fraction", "no_mouse_fraction"]) + "\n"
        func flush(_ force: Bool = false) throws {
            if force || buffer.utf8.count > 1_000_000 { try frames.write(contentsOf: Data(buffer.utf8)); buffer = "" }
            if force || binBuffer.utf8.count > 1_000_000 { try bins.write(contentsOf: Data(binBuffer.utf8)); binBuffer = "" }
        }

        var archives: [String: TSTStoredRecording] = [:]
        var measuresCache: [String: [[FrameMeasure]]] = [:]
        var series: [FrameSeries] = []
        for s in doc.sessions {
            if archives[s.recordingID] == nil, let id = UUID(uuidString: s.recordingID),
               let r = TSTTaskArchive.load(taskID, record: id) {
                archives[s.recordingID] = r
                if r.hasMeasures == true, let m = TSTTaskArchive.loadMeasures(r) { measuresCache[s.recordingID] = m }
            }
            guard let r = archives[s.recordingID], let traces = r.traces,
                  s.chamber >= 1, s.chamber <= traces.count else { continue }
            let tr = traces[s.chamber - 1]
            let raw: [FrameMeasure]? = measuresCache[s.recordingID].flatMap { all in
                s.chamber <= all.count && all[s.chamber - 1].count == tr.time.count ? all[s.chamber - 1] : nil
            }
            // Raw (unsmoothed) value of the chosen measure, exactly as the scorer forms it.
            var rawPct: [Double]? = nil
            if let raw {
                let areas = raw.map(\.area).filter { $0 > 0 }.sorted()
                let ref = areas.isEmpty ? 0 : areas[areas.count / 2]
                switch r.settings.metric {
                case .box: rawPct = raw.map { $0.boxBody > 0 ? 100 * $0.boxChange / $0.boxBody : .nan }
                case .pixel: rawPct = raw.map { ref > 0 ? 100 * $0.pixelChange / ref : .nan }
                case .shape: rawPct = raw.map { ref > 0 ? 100 * $0.shapeChange / ref : .nan }
                }
            }
            let onset = s.suspendedAtVideoS - s.analysisStartVideoS
            let threshold = r.settings.immobilityThreshold
            let ident = [doc.task, s.sessionID, s.animalID, s.group, s.sex, s.included ? "true" : "false"]
            var fs = FrameSeries(sessionID: s.sessionID, animalID: s.animalID, group: s.group, included: s.included,
                                 measure: r.settings.metric.rawValue, immobilityThresholdPct: threshold, sampleFPS: r.fps,
                                 suspendedAtVideoS: s.suspendedAtVideoS, analysisStartVideoS: s.analysisStartVideoS,
                                 timeFromSuspensionS: [], motionPctBody: [], motionRawPctBody: rawPct == nil ? nil : [],
                                 immobile: [], noMouse: [])
            // 1-s bins after suspension
            var binSecond = Int.min
            var binN = 0, binImm = 0, binNone = 0, binMotion = 0.0, binMotionN = 0
            func closeBin() {
                guard binSecond >= 0, binN > 0 else { return }
                let w = window(Double(binSecond), primaryStart: s.primaryWindowStartS, test: s.testLengthS)
                binBuffer += row(ident + [String(binSecond), w, String(binN),
                                          num(binMotionN > 0 ? binMotion / Double(binMotionN) : nil),
                                          num(Double(binImm) / Double(binN)), num(Double(binNone) / Double(binN))]) + "\n"
            }
            for k in tr.time.indices {
                let rel = tr.time[k] - onset
                let none = k < tr.noMouse.count ? tr.noMouse[k] : true
                let imm = k < tr.immobile.count ? tr.immobile[k] : false
                let motion: Double? = !none && k < tr.motion.count && tr.motion[k].isFinite ? tr.motion[k] : nil
                let rawValue: Double? = rawPct.flatMap { k < $0.count && $0[k].isFinite ? $0[k] : nil }
                let m = raw.map { $0[k] }
                var f = ident + [String(k), num(rel), num(s.analysisStartVideoS + tr.time[k]),
                                 window(rel, primaryStart: s.primaryWindowStartS, test: s.testLengthS),
                                 num(motion), num(rawValue), num(threshold),
                                 motion.map { $0 < threshold ? "1" : "0" } ?? "", imm ? "1" : "0", none ? "1" : "0"]
                if let m {
                    f += [num(m.boxChange, 1), num(m.boxBody, 1), m.boxPresent ? "1" : "0", num(m.pixelChange, 1),
                          num(m.shapeChange, 1), num(m.area, 1), num(m.cx, 1), num(m.cy, 1)]
                } else {
                    f += ["", "", "", "", "", "", "", ""]
                }
                buffer += row(f) + "\n"
                fs.timeFromSuspensionS.append(rounded(rel))
                fs.motionPctBody.append(motion.map { rounded($0) })
                if rawPct != nil { fs.motionRawPctBody?.append(rawValue.map { rounded($0) }) }
                fs.immobile.append(imm ? 1 : 0)
                fs.noMouse.append(none ? 1 : 0)
                if rel >= 0 {
                    let sec = Int(rel.rounded(.down))
                    if sec != binSecond {
                        closeBin()
                        binSecond = sec; binN = 0; binImm = 0; binNone = 0; binMotion = 0; binMotionN = 0
                    }
                    binN += 1
                    if imm { binImm += 1 }
                    if none { binNone += 1 }
                    if let motion { binMotion += motion; binMotionN += 1 }
                }
                try flush()
            }
            closeBin()
            series.append(fs)
        }
        try flush(true)

        struct FramesDocument: Codable {
            var format = "RodentStudio TST frame-based motion"
            var formatVersion = 1
            var task: String
            var notes: [String]
            var sessions: [FrameSeries]
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.keyEncodingStrategy = .convertToSnakeCase
        let json = FramesDocument(task: doc.task, notes: [
            "time_from_suspension_s: frame time from this mouse's suspension (negative = before).",
            "motion_pct_body: the scored, smoothed motion (% of body); null = no mouse.",
            "motion_raw_pct_body: the chosen measure before smoothing (absent for analyses saved before 0.7.1 round 6).",
            "immobile / no_mouse: 1 = yes. Arrays of a session have the same length.",
        ], sessions: series)
        try enc.encode(json).write(to: folder.appendingPathComponent("tst_frames.json"), options: .atomic)
    }
}
