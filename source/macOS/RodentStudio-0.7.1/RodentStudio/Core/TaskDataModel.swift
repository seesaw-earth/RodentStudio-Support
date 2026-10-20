// TaskDataModel.swift — the numbers of every session of a task, for the task / group / animal pages and
// the task-level exports.
//
// Each session is computed once by SessionResultsEngine (the same path as its Results tab) and its
// summary is saved next to its tracking run. Sessions are computed one after another in the background;
// the Results tab also hands over what it has just computed. A summary is only used while its key still
// matches the session (same run, calibration, phase and analyzer).

import Foundation
import SwiftUI

/// Where a session stands for the task summaries.
enum SessionDataState: Equatable {
    case ready, computing, waiting, notAnalysed, needsCalibration, failed(String)

    var title: String {
        switch self {
        case .ready: return L("Results ready", "结果已就绪")
        case .computing: return L("Computing…", "正在计算…")
        case .waiting: return L("Waiting to compute", "等待计算")
        case .notAnalysed: return L("Not analysed", "未分析")
        case .needsCalibration: return L("Needs calibration", "需要标定")
        case .failed: return L("Results failed", "结果计算失败")
        }
    }

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .computing, .waiting: return "hourglass"
        case .notAnalysed: return "circle.dashed"
        case .needsCalibration: return "viewfinder"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class TaskDataModel: ObservableObject {
    @Published private(set) var summaries: [UUID: SessionMetricSummary] = [:]
    @Published private(set) var failures: [UUID: (key: String, message: String)] = [:]
    @Published private(set) var computingID: UUID?
    /// Sessions computed / to compute in the current pass.
    @Published private(set) var progress: (done: Int, total: Int)?

    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var keyMemo: [UUID: (calibration: DesktopCalibration?, phase: String, folder: String, finished: Date?, assay: StudyAssay, key: String)] = [:]

    // MARK: Keys

    /// Current key of a session (memoized while the inputs are unchanged).
    func key(_ video: VideoRecord, assay: StudyAssay) -> String {
        let phase = video.effectivePhase(for: assay)
        let folder = video.runFolder ?? ""
        if let m = keyMemo[video.id], m.calibration == video.calibration, m.phase == phase, m.folder == folder,
           m.finished == video.runFinishedAt, m.assay == assay {
            return m.key
        }
        let k = SessionMetrics.cacheKey(video: video, assay: assay)
        keyMemo[video.id] = (video.calibration, phase, folder, video.runFinishedAt, assay, k)
        return k
    }

    /// The summary of a session if it is up to date.
    func summary(_ video: VideoRecord, assay: StudyAssay) -> SessionMetricSummary? {
        guard video.runState == .complete, let s = summaries[video.id] else { return nil }
        return s.cacheKey == key(video, assay: assay) ? s : nil
    }

    func state(_ video: VideoRecord, assay: StudyAssay) -> SessionDataState {
        guard video.runState == .complete else { return .notAnalysed }
        if summary(video, assay: assay) != nil { return .ready }
        if computingID == video.id { return .computing }
        if Self.needsCalibration(video, assay: assay) { return .needsCalibration }
        if let f = failures[video.id], f.key == key(video, assay: assay) { return .failed(f.message) }
        return .waiting
    }

    /// Results need the session's calibration (RodentLimb TST / gait can use the default parameters; the
    /// cylinder must be calibrated, as in RodentLimb).
    static func needsCalibration(_ video: VideoRecord, assay: StudyAssay) -> Bool {
        // For TST, chamber layout and key-frame alignment are performed ONCE per recording.
        // There is no per-animal arena calibration to repeat.
        if assay == .tstMultiChamber { return false }
        if assay.module == .limb {
            guard assay.limbAssay == .cylinder else { return false }
            return !(video.hasSetup(for: assay) && (video.calibration?.limb?.isCalibrated ?? false))
        }
        return !video.hasSetup(for: assay)
    }

    /// The Results tab hands over what it computed (no second computation).
    func record(_ output: SessionOutput, video: VideoRecord, assay: StudyAssay, store: WorkspaceStore) {
        let k = key(video, assay: assay)
        if summaries[video.id]?.cacheKey == k { return }
        let s = SessionMetrics.summary(output, video: video, assay: assay, key: k)
        summaries[video.id] = s
        failures[video.id] = nil
        if let folder = store.runFolderURL(video) {
            Task.detached(priority: .utility) { SessionMetrics.writeCache(s, folder: folder) }
        }
    }

    // MARK: Background computation

    /// Queues every analysed session of the task whose summary is missing or out of date.
    func prepare(task experimentID: UUID, store: WorkspaceStore) {
        guard let project = store.selectedProject,
              let assay = project.experiments.first(where: { $0.id == experimentID })?.assay else { return }
        if assay == .tstMultiChamber {
            // Same TaskDataModel API as every other assay; only the analyzer-specific
            // source of session numbers differs. Exactly one chamber per VideoRecord.
            for v in project.sessions(ofTask: experimentID) where v.runState == .complete {
                let k = key(v, assay: assay)
                if summaries[v.id]?.cacheKey == k { continue }
                if let linked = TSTSessionMetrics.load(video: v, key: k) {
                    summaries[v.id] = linked
                    failures[v.id] = nil
                } else {
                    failures[v.id] = (k, "TST recording / chamber archive not found")
                }
            }
            return
        }
        var added = 0
        for v in project.sessions(ofTask: experimentID) where v.runState == .complete {
            if summary(v, assay: assay) != nil { continue }
            if let f = failures[v.id], f.key == key(v, assay: assay) { continue }
            if Self.needsCalibration(v, assay: assay) { continue }
            if queue.contains(v.id) || computingID == v.id { continue }
            queue.append(v.id)
            added += 1
        }
        guard added > 0 else { return }
        if let p = progress {
            progress = (p.done, p.total + added)
        } else {
            progress = (0, added)
        }
        if worker == nil { startWorker(store: store) }
    }

    /// Computes the failed sessions of a task again.
    func retryFailed(task experimentID: UUID, store: WorkspaceStore) {
        guard let project = store.selectedProject else { return }
        for v in project.sessions(ofTask: experimentID) { failures[v.id] = nil }
        prepare(task: experimentID, store: store)
    }

    func cancel() {
        queue.removeAll()
        worker?.cancel()
    }

    private func startWorker(store: WorkspaceStore) {
        worker = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, !self.queue.isEmpty {
                let id = self.queue.removeFirst()
                await self.computeOne(id, store: store)
                if let p = self.progress { self.progress = (p.done + 1, p.total) }
                await Task.yield()
            }
            self?.computingID = nil
            self?.progress = nil
            self?.worker = nil
        }
    }

    private func computeOne(_ id: UUID, store: WorkspaceStore) async {
        guard let project = store.selectedProject,
              let video = project.videos.first(where: { $0.id == id }), video.runState == .complete,
              let assay = project.experiments.first(where: { $0.id == video.experimentID })?.assay,
              let folder = store.runFolderURL(video) else { return }
        let k = key(video, assay: assay)
        if summaries[id]?.cacheKey == k { return }
        computingID = id
        defer { computingID = nil }
        let cached = await Task.detached(priority: .utility) { SessionMetrics.readCache(folder: folder, key: k) }.value
        if let cached {
            summaries[id] = cached
            return
        }
        do {
            let output = try await SessionResultsEngine.compute(video: video, assay: assay, store: store, loaded: nil)
            // The session may have changed while it was computed; the result is kept only for its own key.
            let s = SessionMetrics.summary(output, video: video, assay: assay, key: k)
            summaries[id] = s
            failures[id] = nil
            await Task.detached(priority: .utility) { SessionMetrics.writeCache(s, folder: folder) }.value
        } catch is CancellationError {
            return
        } catch {
            failures[id] = (k, error.localizedDescription)
        }
    }

    // MARK: Records for the group comparison

    /// One record per session with up-to-date results.
    func records(task experimentID: UUID, project: NativeProject) -> [GroupRecord] {
        guard let assay = project.experiments.first(where: { $0.id == experimentID })?.assay else { return [] }
        var out: [GroupRecord] = []
        for v in project.sessions(ofTask: experimentID).sorted(by: VideoRecord.sessionOrder) {
            guard let s = summary(v, assay: assay) else { continue }
            out.append(GroupRecord(id: v.id,
                                   subjectID: v.animalID.trimmingCharacters(in: .whitespacesAndNewlines),
                                   subjectKey: v.animalKey,
                                   group: v.groupKey,
                                   phase: s.phase,
                                   day: v.day,
                                   trial: v.trial,
                                   session: v.sessionNumber,
                                   date: v.sessionDate,
                                   metrics: s.values,
                                   series: s.series,
                                   excluded: v.isExcluded,
                                   exclusionReason: v.exclusionReason ?? "",
                                   qcFlags: s.qcFlags,
                                   trackingProblem: v.reviewVerdict == .issues))
        }
        return out
    }

    func summaries(task experimentID: UUID, project: NativeProject) -> [SessionMetricSummary] {
        guard let assay = project.experiments.first(where: { $0.id == experimentID })?.assay else { return [] }
        return project.sessions(ofTask: experimentID).compactMap { summary($0, assay: assay) }
    }

    /// What the group comparison needs to know about the task (measure names from the given phase first).
    func context(task experiment: NativeExperiment, project: NativeProject, phase: String?) -> GroupAnalysisContext {
        let all = summaries(task: experiment.id, project: project)
        let assay = experiment.assay
        let defs = TaskMetricDefinitions.defs(all, preferredPhase: phase)
        let phases = assay.phaseOptions.map(\.key)
        return GroupAnalysisContext(assay: assay, defs: defs, pairs: TaskMetricDefinitions.pairs(assay), assayPhases: phases,
                                    primaryKey: { p in TaskMetricDefinitions.primaryKey(all, phase: p) },
                                    usesDays: assay.flowAssay?.usesDays ?? false)
    }
}
