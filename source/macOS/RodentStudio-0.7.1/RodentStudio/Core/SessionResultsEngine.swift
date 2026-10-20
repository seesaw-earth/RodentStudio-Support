// SessionResultsEngine.swift — the results of one session (one video), computed by the task's original
// analyzer from the saved tracking with the calibration, analysis window, phase and parameters saved for
// that video. The Results tab and the task / group summaries both use this one path, so a number shown
// for a session is the same everywhere.

import Foundation
import CoreGraphics

/// Results of a RodentFlow session.
struct FlowSessionOutput {
    let assay: FlowAssay
    let phase: String
    let computation: FlowAssayComputation
    let config: FlowZoneConfig
    let samples: [FlowAnalysisSample]
    let run: FlowSavedRun
    /// Remarks about how the results were obtained (both languages; exports use English).
    let notes: [LText]
}

/// Results of a session in the form of the task's original app.
enum SessionOutput {
    case pose(AnalysisReport, ParadigmCategory)
    case limb(AnalysisResult, Assay, CGSize)
    case flow(FlowSessionOutput)
}

enum SessionResultsError: LocalizedError {
    case notAnalysed, needsCalibration, notLoaded, tooLongForLimb, wrongSetup, videoMissing, unsupported

    var errorDescription: String? {
        switch self {
        case .notAnalysed: return L("This session has not been analysed yet.", "该实验尚未分析。")
        case .needsCalibration: return L("Calibrate this video first; the results use its calibration and parameters.", "请先标定该视频；结果使用该视频的标定与参数。")
        case .notLoaded: return L("The saved tracking is still loading.", "已保存的追踪结果仍在读取。")
        case .tooLongForLimb: return L("This run is longer than 150,000 frames; RodentLimb results need the whole run in memory.", "该结果超过 150,000 帧；RodentLimb 结果需要把整段数据读入内存。")
        case .wrongSetup: return L("The saved calibration belongs to another task; calibrate this video again.", "已保存的标定属于其他任务，请重新标定该视频。")
        case .videoMissing: return L("The source video cannot be opened.", "无法打开原始视频。")
        case .unsupported: return L("This task has no results on the desktop.", "该任务在桌面版没有结果。")
        }
    }
}

/// A saved RodentPose / RodentLimb run read from the app's Runs folder.
enum LoadedTrackingRun {
    case short(NativeTrackingResult)
    case long(LongVideoManifest, folder: URL, videoURL: URL?)
}

enum SessionResultsEngine {
    // MARK: Loading

    /// Reads a saved Core ML run: in memory up to `SegmentedRunLoader.inMemoryFrameLimit` frames, otherwise
    /// as its manifest (segments are read when needed). Same rule as the Review step.
    static func loadRun(folder: URL, videoURL: URL?) throws -> LoadedTrackingRun {
        let manifestURL = folder.appendingPathComponent(LongVideoTrackingEngine.manifestName)
        let manifest = try JSONDecoder().decode(LongVideoManifest.self, from: Data(contentsOf: manifestURL))
        let frames = manifest.completed.reduce(0) { $0 + $1.records }
        if frames <= SegmentedRunLoader.inMemoryFrameLimit {
            return .short(try SegmentedRunLoader.load(manifest: manifest, folder: folder, videoURL: videoURL))
        }
        return .long(manifest, folder: folder, videoURL: videoURL)
    }

    // MARK: Module analyzers (no main-actor state; run off the main thread)

    static func pose(_ run: LoadedTrackingRun, setup: PoseTaskSetup, phase: String) throws -> AnalysisReport {
        switch run {
        case .short(let short):
            return try PoseScienceBridge.report(short, setup: setup, phase: phase)
        case .long(let manifest, let folder, let videoURL):
            let total = manifest.completed.reduce(0) { $0 + $1.records }
            var range: ClosedRange<Double>?
            if total > PoseScienceBridge.maxFrames && setup.params.windowLength > 0 {
                // Only the analysis window (with 30 s on each side for smoothing and zone state) is read.
                let a = max(0, setup.params.windowStart - 30)
                range = a...(setup.params.windowStart + setup.params.windowLength + 30)
            }
            let access = videoURL?.startAccessingSecurityScopedResource() ?? false
            defer { if access { videoURL?.stopAccessingSecurityScopedResource() } }
            let tracked = try PoseScienceLongLoader.make(manifest: manifest, folder: folder, videoURL: videoURL, timeRange: range)
            return try PoseScienceBridge.report(tracked, setup: setup, phase: phase)
        }
    }

    static func limb(_ run: LoadedTrackingRun, limbAssay: Assay, setup: LimbTaskSetup?) throws -> (AnalysisResult, CGSize) {
        guard case .short(let short) = run else { throw SessionResultsError.tooLongForLimb }
        guard let track = short.limbPoseTrack() else { throw SessionResultsError.unsupported }
        if let setup, setup.assay != limbAssay { throw SessionResultsError.wrongSetup }
        if limbAssay == .cylinder && !(setup?.isCalibrated ?? false) { throw SessionResultsError.needsCalibration }
        let calibration = setup?.scaledCalibration(width: short.videoWidth, height: short.videoHeight)
            ?? Calibration(circle: nil, floorY: nil, scale: nil, copiedFrom: nil)
        let params = setup?.params ?? AssayParams.defaults(for: limbAssay)
        let result = NativeLimbAdapter.run(track: track, assay: limbAssay, params: params, calibration: calibration)
        return (result, CGSize(width: short.videoWidth, height: short.videoHeight))
    }

    // MARK: One session

    /// Results of a session. `loaded` is the run already in memory (Review step), if any; otherwise the run
    /// is read from disk.
    @MainActor
    static func compute(video: VideoRecord, assay: StudyAssay, store: WorkspaceStore,
                        loaded: LoadedTrackingRun?) async throws -> SessionOutput {
        guard video.runState == .complete, let folder = store.runFolderURL(video) else { throw SessionResultsError.notAnalysed }
        let phase = video.effectivePhase(for: assay)
        switch assay.module {
        case .pose?:
            guard let setup = video.calibration?.pose, video.hasSetup(for: assay) else { throw SessionResultsError.needsCalibration }
            let category = setup.paradigm.category
            let source = store.resolveURL(video)
            let given = loaded
            let report = try await Task.detached(priority: .userInitiated) { () throws -> AnalysisReport in
                let run = try given ?? SessionResultsEngine.loadRun(folder: folder, videoURL: source)
                return try SessionResultsEngine.pose(run, setup: setup, phase: phase)
            }.value
            return .pose(report, category)
        case .limb?:
            guard let limbAssay = assay.limbAssay else { throw SessionResultsError.unsupported }
            let setup = video.hasSetup(for: assay) ? video.calibration?.limb : nil
            let source = store.resolveURL(video)
            let given = loaded
            let out = try await Task.detached(priority: .userInitiated) { () throws -> (AnalysisResult, CGSize) in
                let run = try given ?? SessionResultsEngine.loadRun(folder: folder, videoURL: source)
                return try SessionResultsEngine.limb(run, limbAssay: limbAssay, setup: setup)
            }.value
            return .limb(out.0, limbAssay, out.1)
        case .flow?:
            return .flow(try await flow(video: video, assay: assay, store: store, folder: folder, phase: phase))
        case nil:
            throw SessionResultsError.unsupported
        }
    }

    /// RodentFlow: the saved centroid track, the zones and parameters saved in Calibrate and the object /
    /// target positions mapped from the markers (the tracking is never re-run).
    @MainActor
    private static func flow(video: VideoRecord, assay: StudyAssay, store: WorkspaceStore, folder: URL, phase: String) async throws -> FlowSessionOutput {
        guard let current = video.calibration?.flow, video.hasSetup(for: assay) else { throw SessionResultsError.needsCalibration }
        var saved = try await FlowRunCache.load(folder)
        var notes: [LText] = []
        var markers = saved.markersCM ?? [:]
        if current.usesMarkers {
            let mappedFrom = saved.markersCalibration ?? saved.trackingSetup?.calibration
            let valid = saved.markersCM != nil && (mappedFrom.map { FlowTaskSetup.sameMarkers($0, current.calibration) } ?? false)
            if !valid {
                // Same mapping as the tracker: the geometry of the tracking run with the markers placed now.
                var markerSetup = saved.trackingSetup ?? current
                markerSetup.calibration.markerA = current.calibration.markerA
                markerSetup.calibration.markerB = current.calibration.markerB
                markerSetup.calibration.markerTarget = current.calibration.markerTarget
                guard let url = store.resolveURL(video) else { throw SessionResultsError.videoMissing }
                let mapping = markerSetup
                let computed = try await Task.detached(priority: .userInitiated) { () async throws -> [String: FlowArenaPoint] in
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try await FlowDesktopRun.markers(videoURL: url, setup: mapping)
                }.value
                markers = computed
                saved.markersCM = computed
                saved.markersCalibration = mapping.calibration
                try? FlowDesktopRun.save(saved, to: folder)
                FlowRunCache.invalidate(folder)
                notes.append(LText("Object / target positions were mapped from the markers placed in Calibrate (the tracking was not re-run).",
                                   "物体 / 目标位置已按“校准”中放置的标记换算（未重新追踪）。"))
            }
        }
        var base = current
        if let tracked = saved.trackingSetup {
            if !tracked.sameTrackingGeometry(as: current) {
                notes.append(LText("The arena calibration was changed after tracking. Positions keep the calibration of the tracking run; analyse again to apply the new calibration.",
                                   "场地标定在追踪之后被修改。位置仍使用追踪时的标定；如需应用新标定，请重新分析。"))
            }
            // Trajectory coordinates are in the arena of the tracking run.
            base.shape = tracked.shape
            base.dimensions = tracked.dimensions
        } else {
            notes.append(LText("This run was made by an earlier version that did not record its calibration. If the arena calibration was changed after tracking, analyse again.",
                               "该结果由早期版本生成，未记录追踪时的标定。如果追踪后修改过场地标定，请重新分析。"))
        }
        let config = FlowResultInputs.config(setup: base, markers: markers)
        let samples = FlowResultInputs.samples(saved)
        let flowAssay = current.assay
        let computation = await Task.detached(priority: .userInitiated) {
            FlowAssayEngine.compute(assay: flowAssay, phase: phase, samples: samples, config: config)
        }.value
        return FlowSessionOutput(assay: flowAssay, phase: phase, computation: computation, config: config,
                                 samples: samples, run: saved, notes: notes)
    }

    // MARK: Analysis window and metadata

    /// Analysis window of a session as saved in Calibrate (seconds; length 0 = to the end).
    static func analysisWindow(_ video: VideoRecord, assay: StudyAssay) -> (start: Double, length: Double) {
        switch assay.module {
        case .pose?:
            let p = video.calibration?.pose?.params
            return (p?.windowStart ?? 0, p?.windowLength ?? 0)
        case .limb?:
            if assay.limbAssay == .tailSuspension {
                let p = video.calibration?.limb?.params.tst ?? AssayParams.defaults(for: .tailSuspension).tst
                return (p.windowStart, max(0, p.windowEnd - p.windowStart))
            }
            return (0, 0)
        case .flow?:
            guard let s = video.calibration?.flow else { return (0, 0) }
            let w = FlowResultInputs.window(assay: s.assay, config: s.zone)
            return (w.start, w.duration ?? 0)
        case nil:
            return (0, 0)
        }
    }

    static func englishWindow(_ w: (start: Double, length: Double)) -> String {
        if w.length > 0 { return String(format: "%.3f-%.3f s", w.start, w.start + w.length) }
        if w.start > 0 { return String(format: "%.3f s to end", w.start) }
        return "whole recording"
    }

    /// English session metadata written into every export (built step by step to keep type checking simple).
    static func metadata(video: VideoRecord, assay: StudyAssay, project: NativeProject?) -> [String: String] {
        let experiment = project?.experiments.first { $0.id == video.experimentID }
        let review = video.currentReview
        var m: [String: String] = [:]
        m["app"] = AppInfo.label
        m["project"] = project?.name ?? ""
        m["experiment"] = experiment?.name ?? ""
        m["task"] = assay.name
        m["task_id"] = assay.rawValue
        m["subject"] = video.animalID
        m["group"] = video.group ?? ""
        m["sex"] = video.sex ?? ""
        m["session_date"] = video.sessionDate ?? ""
        m["session_number"] = video.sessionNumber.map { String($0) } ?? ""
        m["phase"] = video.effectivePhase(for: assay)
        m["day"] = video.day.map { String($0) } ?? ""
        m["trial"] = video.trial.map { String($0) } ?? ""
        m["notes"] = video.notes ?? ""
        m["excluded"] = video.isExcluded ? "yes" : "no"
        m["exclusion_reason"] = video.exclusionReason ?? ""
        m["video"] = video.fileName
        m["video_duration_s"] = String(format: "%.3f", video.durationSeconds)
        m["video_fps"] = String(format: "%.3f", video.framesPerSecond)
        m["run_folder"] = video.runFolder ?? ""
        m["run_model"] = video.runModel ?? ""
        m["analysis_window"] = englishWindow(analysisWindow(video, assay: assay))
        m["tracking_check"] = (review?.verdict ?? .unreviewed).exportValue
        if let review {
            m["tracking_check_window"] = "\(review.unit) \(review.windowStart)-\(review.windowEnd)"
            m["tracking_check_viewed"] = String(review.viewed.count)
            m["tracking_check_flagged"] = review.flagged.map { String($0) }.joined(separator: " ")
            m["tracking_check_notes"] = review.notes
        }
        if let date = video.runFinishedAt { m["run_finished"] = ISO8601DateFormatter().string(from: date) }
        if let copied = video.calibration?.copiedFrom { m["calibration_copied_from"] = copied }
        return m
    }
}
