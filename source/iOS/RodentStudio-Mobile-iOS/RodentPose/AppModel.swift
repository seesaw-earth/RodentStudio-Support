// AppModel.swift — app-wide state (model, store, presented session) and the per-session workflow
// model (info → calibration → inference → result) with instant re-analysis.

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Workflow steps

enum FlowStep: Int, CaseIterable, Identifiable {
    case info, calibrate, run, result

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .info: return L10n.tr("信息")
        case .calibrate: return L10n.tr("标定")
        case .run: return L10n.tr("识别")
        case .result: return L10n.tr("结果")
        }
    }

    var symbol: String {
        switch self {
        case .info: return "doc.text"
        case .calibrate: return "viewfinder"
        case .run: return "sparkles"
        case .result: return "chart.bar.xaxis"
        }
    }
}

// MARK: - One session

@MainActor
final class SessionFlowModel: ObservableObject, Identifiable {
    let id: UUID

    @Published var session: Session {
        didSet { sessionChanged(from: oldValue) }
    }
    @Published var step: FlowStep = .info
    @Published var frame: CGImage?
    @Published private(set) var track: PoseTrack?
    @Published private(set) var report: AnalysisReport? {
        didSet { reportVersion &+= 1 }
    }
    @Published private(set) var features: FeatureSet?
    /// Cleaned, smoothed body-center paths for video overlays (one per animal). Display only.
    @Published private(set) var trails: [DisplayTrail] = []
    /// Thinned polylines of the first animal's trail, for the calibration frame.
    @Published private(set) var trailOverview: [[NPoint]] = []
    /// Changes whenever `report` is replaced (cheap identity for views that cache derived data).
    private(set) var reportVersion = 0
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isRunning = false
    @Published private(set) var progress = InferenceProgress()
    @Published private(set) var live: LiveFrame?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var loadingFrame = false
    @Published private(set) var didLoad = false

    let store: SessionStore
    let engine: PoseEngine
    var onRunningChanged: ((SessionFlowModel) -> Void)?

    private var token: CancelToken?
    private var featuresKey: FeatureKey?
    private var analysisGeneration = 0

    /// Everything the cleaned keypoint series depend on.
    private struct FeatureKey: Equatable {
        let calibration: ArenaCalibration
        let preprocessing: [Double]
        let frames: Int
        let processedUntil: Double

        init(_ s: Session, _ t: PoseTrack) {
            calibration = s.calibration
            let p = s.params
            preprocessing = [p.kpConf, p.smoothing, p.maxGap, p.maxJumpSpeed, p.windowStart, p.windowLength, s.video.width, s.video.height]
            frames = t.count
            processedUntil = t.processedUntil
        }
    }
    /// Everything the display trails depend on.
    private struct TrailKey: Equatable {
        let settings: TrailSmoother.Settings
        let frames: Int
        let processedUntil: Double
    }
    private var trailKey: TrailKey?

    private var analysisTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    // Mapping and zones are read many times per frame by overlays; rebuild only when their
    // inputs change.
    private var mappingCache: (calibration: ArenaCalibration, frameSize: V2, value: ArenaMapping)?
    private var zonesCache: (calibration: ArenaCalibration, params: AnalysisParams, paradigm: Paradigm, phase: String, frameSize: V2, value: [Zone])?

    init(session: Session, store: SessionStore, engine: PoseEngine) {
        self.id = session.id
        self.session = session
        self.store = store
        self.engine = engine
    }

    // MARK: Derived

    var videoURL: URL? { store.videoURL(session) }
    var hasPose: Bool { (track?.count ?? 0) > 0 }
    var frameSize: V2 { session.video.frameSize }

    var mapping: ArenaMapping {
        let cal = session.calibration, size = frameSize
        if let c = mappingCache, c.frameSize == size, c.calibration == cal { return c.value }
        let m = ArenaMapper.mapping(cal, frameSize: size)
        mappingCache = (cal, size, m)
        return m
    }

    var zones: [Zone] {
        let s = session, size = frameSize
        if let c = zonesCache, c.frameSize == size, c.paradigm == s.paradigm, c.phase == s.phase,
           c.calibration == s.calibration, c.params == s.params {
            return c.value
        }
        let z = ZoneBuilder.zones(s, mapping: mapping)
        zonesCache = (s.calibration, s.params, s.paradigm, s.phase, size, z)
        return z
    }

    /// Display-trail settings derived from the analysis parameters and the calibration scale.
    private var trailSettings: TrailSmoother.Settings {
        var t = TrailSmoother.Settings()
        let p = session.params
        t.minConf = Float(p.kpConf)
        t.maxGap = max(p.maxGap, 0.2)
        let m = mapping
        if m.isMetric, p.maxJumpSpeed > 0, m.pxPerUnit.isFinite, m.pxPerUnit > 0 {
            // Rounded so that tiny handle nudges do not trigger a rebuild.
            t.maxSpeedPx = (p.maxJumpSpeed * m.pxPerUnit / 10).rounded() * 10
        }
        return t
    }

    /// The stored pose data was made with different model settings than the current ones.
    var inferenceSettingsChanged: Bool {
        guard hasPose, let used = session.usedInference else { return false }
        let now = session.inference
        return used.stride != now.stride || used.grayscale != now.grayscale || used.animalCount != now.animalCount
            || abs(used.startTime - now.startTime) > 0.01 || abs(used.endTime - now.endTime) > 0.01
    }

    var canResume: Bool {
        guard let t = track, t.count > 0, !t.complete, !inferenceSettingsChanged else { return false }
        return true
    }

    func isAvailable(_ s: FlowStep) -> Bool {
        switch s {
        case .info, .calibrate, .run: return true
        case .result: return hasPose
        }
    }

    func isDone(_ s: FlowStep) -> Bool {
        switch s {
        case .info: return !session.subjectID.isEmpty
        case .calibrate: return session.calibration.kind == .none || hasPose
        case .run: return track?.complete == true
        case .result: return false
        }
    }

    // MARK: Loading

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        if session.pose != nil, track == nil, let t = await store.loadPose(session.id) {
            track = t
            scheduleAnalysis(delay: 0)
        }
        if frame == nil { await loadFrame() }
    }

    func loadFrame(at time: Double? = nil) async {
        if let url = videoURL {
            loadingFrame = true
            let t = time ?? session.calibrationTime
            let img = await VideoTools.frame(url: url, at: t)
            loadingFrame = false
            if let img {
                frame = img
                if let time { session.calibrationTime = time }
                return
            }
        }
        if frame == nil, let ui = UIImage(contentsOfFile: store.thumbnailURL(session.id).path) {
            frame = ui.cgImage
        }
    }

    // MARK: Editing

    private func sessionChanged(from old: Session) {
        // The subject ID only matters for pairing the two phases of the social interaction test;
        // typing it must not re-run the whole analysis for every other paradigm.
        let subjectMatters = session.paradigm == .socialInteraction && old.subjectID != session.subjectID
        let needsAnalysis = old.params != session.params || old.calibration != session.calibration
            || old.phase != session.phase || old.paradigm != session.paradigm || subjectMatters
        if needsAnalysis && hasPose { scheduleAnalysis(delay: 0.25) }
        schedulePersist()
    }

    private func schedulePersist() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, !Task.isCancelled else { return }
            self.store.save(self.session)
        }
    }

    func persistNow() {
        saveTask?.cancel()
        store.save(session)
    }

    func changeParadigm(_ p: Paradigm) {
        guard p != session.paradigm else { return }
        var s = session
        s.paradigm = p
        s.params = AnalysisParams.defaults(for: p)
        s.phase = p.phases.first?.key ?? ""
        s.inference.animalCount = p.animalCount
        let kind = p.arenaKinds.contains(s.calibration.kind) ? s.calibration.kind : p.defaultArena
        let fresh = ArenaCalibration.makeDefault(paradigm: p, kind: kind, frameSize: frameSize)
        if kind == s.calibration.kind {
            // Keep the arena handles the user already placed; only add the new markers.
            s.calibration.markers = fresh.markers
        } else {
            s.calibration = fresh
        }
        s.metrics = [:]
        s.metricOrder = []
        session = s
    }

    func changeArena(_ kind: ArenaKind) {
        guard kind != session.calibration.kind else { return }
        session.calibration = ArenaCalibration.makeDefault(paradigm: session.paradigm, kind: kind, frameSize: frameSize)
    }

    func resetCalibration() {
        var updated = session
        updated.calibration = ArenaCalibration.makeDefault(paradigm: session.paradigm, kind: session.calibration.kind, frameSize: frameSize)
        if session.paradigm == .threeChamber {
            // The movable dividers belong to the calibration controls too.
            updated.params.centerChamberFraction = 1.0 / 3.0
            updated.params.centerChamberOffset = 0
        }
        session = updated
    }

    func resetParams() {
        session.params = AnalysisParams.defaults(for: session.paradigm)
    }

    // MARK: Analysis

    func scheduleAnalysis(delay: Double = 0.25) {
        guard let track, track.count > 0 else {
            report = nil
            return
        }
        analysisTask?.cancel()
        analysisGeneration += 1
        let generation = analysisGeneration
        let s = session
        let companion = store.companionMetrics(for: s)
        // Thresholds and zones do not change the cleaned keypoints: reuse them when possible.
        let key = FeatureKey(s, track)
        let cached = key == featuresKey ? features : nil
        let tKey = TrailKey(settings: trailSettings, frames: track.count, processedUntil: track.processedUntil)
        let cachedTrails: [DisplayTrail]? = tKey == trailKey && !trails.isEmpty ? trails : nil
        isAnalyzing = true
        analysisTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            let result = await Task.detached(priority: .userInitiated) { () -> (AnalysisReport, FeatureSet, [DisplayTrail], [[NPoint]]) in
                let fs = cached ?? Kinematics.build(track: track, session: s)
                let report = Analyzer.run(session: s, features: fs, companion: companion)
                let trails = cachedTrails ?? TrailSmoother.buildAll(track: track, settings: tKey.settings)
                let overview = cachedTrails == nil ? (trails.first?.polylines(maxPoints: 1500) ?? []) : []
                return (report, fs, trails, overview)
            }.value
            guard let self, generation == self.analysisGeneration else { return }
            self.report = result.0
            self.features = result.1
            self.featuresKey = key
            if cachedTrails == nil {
                self.trails = result.2
                self.trailOverview = result.3
                self.trailKey = tKey
            }
            self.isAnalyzing = false
            var updated = self.session
            Analyzer.cache(result.0, into: &updated)
            if updated != self.session {
                self.session = updated
            }
        }
    }

    // MARK: Inference

    func startInference(fresh: Bool = false) {
        guard !isRunning else { return }
        guard engine.isReady, let yolo = engine.yolo else {
            errorMessage = L10n.tr("模型还没有就绪。")
            return
        }
        guard let url = videoURL else {
            errorMessage = L10n.tr("这个会话的视频副本已删除，无法重新识别。")
            return
        }
        let resume: PoseTrack? = (!fresh && canResume) ? track : nil
        if resume == nil {
            // Drop the old data and any analysis still in flight for it.
            analysisTask?.cancel()
            analysisGeneration += 1
            isAnalyzing = false
            track = nil
            report = nil
            features = nil
            featuresKey = nil
            trails = []
            trailOverview = []
            trailKey = nil
        }
        errorMessage = nil
        notice = nil
        progress = InferenceProgress()
        live = nil
        isRunning = true
        session.status = .processing
        session.usedInference = session.inference
        UIApplication.shared.isIdleTimerDisabled = true
        onRunningChanged?(self)

        let token = CancelToken()
        self.token = token
        let settings = session.inference
        let direct = engine.direct
        let ref = WeakRef(self)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await VideoPoseProcessor.run(
                        url: url, yolo: yolo, direct: direct, settings: settings, resume: resume, token: token,
                        progress: { p in Task { @MainActor in ref.value?.progress = p } },
                        preview: { f in Task { @MainActor in ref.value?.live = f } })
                }.value
                await ref.value?.inferenceFinished(result)
            } catch {
                await ref.value?.inferenceFailed(error)
            }
        }
    }

    func stopInference() {
        token?.cancel()
    }

    private func inferenceFinished(_ result: PoseTrack) async {
        track = result
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        var s = session
        s.pose = result.summary()
        s.status = result.complete ? .done : .paused
        session = s
        do {
            try await store.savePose(result, for: session.id)
        } catch {
            errorMessage = L10n.tr("姿态数据保存失败：\(error.localizedDescription)")
        }
        persistNow()
        onRunningChanged?(self)
        scheduleAnalysis(delay: 0)
        if result.complete {
            notice = nil
            step = .result
        } else {
            notice = L10n.tr("已暂停：已识别的部分已保存，可以随时继续。")
        }
    }

    private func inferenceFailed(_ error: Error) async {
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        session.status = hasPose ? .paused : .failed
        errorMessage = L10n.tr("识别失败：\(error.localizedDescription)")
        persistNow()
        onRunningChanged?(self)
    }

    /// iOS does not allow GPU work in the background: pause and keep what was processed.
    func pauseForBackground() {
        if isRunning { token?.cancel() }
    }

    // MARK: Exports

    func exportFiles(_ kinds: Set<ExportKind>) async throws -> [URL] {
        guard let track, let report else { return [] }
        let s = session
        let fs = features
        return try await Task.detached(priority: .userInitiated) { () -> [URL] in
            var urls: [URL] = []
            let base = Exporter.baseName(s)
            if kinds.contains(.metrics) {
                urls.append(try SessionStore.writeExport(base + "_metrics.csv", text: Exporter.metricsCSV(session: s, report: report)))
            }
            if kinds.contains(.frames) {
                let features = fs ?? Kinematics.build(track: track, session: s)
                urls.append(try SessionStore.writeExport(base + "_frames.csv", csv: Exporter.frameCSV(session: s, track: track, features: features, report: report)))
            }
            if kinds.contains(.raw) {
                urls.append(try SessionStore.writeExport(base + "_keypoints.csv", csv: track.rawCSV()))
            }
            if kinds.contains(.json) {
                urls.append(try SessionStore.writeExport(base + "_report.json", data: Exporter.reportJSON(session: s, report: report)))
            }
            return urls
        }.value
    }
}

/// Weak reference that can be captured by @Sendable closures.
final class WeakRef<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

enum ExportKind: String, CaseIterable, Identifiable {
    case metrics, frames, raw, json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metrics: return L10n.tr("指标汇总 CSV")
        case .frames: return L10n.tr("逐帧分析 CSV")
        case .raw: return L10n.tr("原始关键点 CSV")
        case .json: return L10n.tr("完整报告 JSON")
        }
    }

    var detail: String {
        switch self {
        case .metrics: return L10n.tr("本次分析的全部指标，一行一个")
        case .frames: return L10n.tr("平滑后坐标（cm）、速度、头朝向、区域与行为标记")
        case .raw: return L10n.tr("模型输出的像素坐标与置信度（与 1.0 版格式相同）")
        case .json: return L10n.tr("指标、参数、标定、质量与方法说明")
        }
    }

    var symbol: String {
        switch self {
        case .metrics: return "list.bullet.rectangle"
        case .frames: return "tablecells"
        case .raw: return "point.3.connected.trianglepath.dotted"
        case .json: return "curlybraces"
        }
    }
}

// MARK: - App

@MainActor
final class AppModel: ObservableObject {
    let engine = PoseEngine()
    let store = SessionStore()

    @Published var activeFlow: SessionFlowModel?
    @Published private(set) var runningFlowID: UUID?
    @Published var newSessionRequest: NewSessionRequest?
    @Published var selectedTab: AppTab = .home
    @Published var showSettings = false

    private var flows: [UUID: SessionFlowModel] = [:]
    /// Flow to present once the "new session" sheet has been dismissed.
    var pendingFlow: SessionFlowModel?

    var runningFlow: SessionFlowModel? { runningFlowID.flatMap { flows[$0] } }

    func flow(for s: Session) -> SessionFlowModel {
        if let f = flows[s.id] { return f }
        let f = SessionFlowModel(session: store.session(s.id) ?? s, store: store, engine: engine)
        f.onRunningChanged = { [weak self] flow in
            guard let self else { return }
            if flow.isRunning { self.runningFlowID = flow.id } else if self.runningFlowID == flow.id { self.runningFlowID = nil }
        }
        flows[s.id] = f
        return f
    }

    func open(_ s: Session) {
        let f = flow(for: s)
        if f.isRunning {
            f.step = .run
        } else if s.pose != nil {
            f.step = .result
        } else {
            f.step = .info
        }
        activeFlow = f
    }

    func closeFlow() {
        if let f = activeFlow {
            f.persistNow()
            if !f.isRunning { flows[f.id] = nil }
        }
        activeFlow = nil
    }

    func startNewSession(_ paradigm: Paradigm? = nil) {
        newSessionRequest = NewSessionRequest(paradigm: paradigm)
    }

    func presentPendingFlow() {
        if let f = pendingFlow {
            pendingFlow = nil
            activeFlow = f
        }
    }

    func delete(_ s: Session) {
        if let f = flows[s.id] {
            f.stopInference()
            flows[s.id] = nil
        }
        store.delete(s)
    }

    /// The most recent session of the same paradigm with the same video resolution, for reusing its setup.
    func previousSetup(for paradigm: Paradigm, meta: VideoMeta) -> Session? {
        store.sessions.first { $0.paradigm == paradigm && abs($0.video.width - meta.width) < 1 && abs($0.video.height - meta.height) < 1 }
    }

    /// Creates a session from an imported video and returns its workflow model.
    func createSession(paradigm: Paradigm, videoURL: URL, originalName: String) async throws -> SessionFlowModel {
        var s = Session(paradigm: paradigm)
        s.videoName = originalName
        let meta = try await VideoTools.readMeta(url: videoURL)
        s.video = meta
        s.calibrationTime = min(1.0, meta.duration / 2)
        var reused = false
        if let prev = previousSetup(for: paradigm, meta: meta) {
            s.calibration = prev.calibration
            s.params = prev.params
            s.inference = prev.inference
            s.inference.endTime = 0
            s.group = prev.group
            s.phase = prev.phase
            s.day = prev.day
            reused = true
        } else {
            s.calibration = ArenaCalibration.makeDefault(paradigm: paradigm, kind: paradigm.defaultArena, frameSize: meta.frameSize)
        }
        s.videoFile = try await store.adoptVideo(from: videoURL, into: s.id)
        store.save(s)
        let f = flow(for: s)
        f.step = .info
        if reused {
            f.notice = L10n.tr("已沿用上一个同类视频的标定、参数和组别。若摄像头位置变了，请在“标定”中检查手柄。")
        }
        if let url = store.videoURL(s), let img = await VideoTools.frame(url: url, at: s.calibrationTime) {
            f.frame = img
            store.saveThumbnail(img, for: s.id)
        }
        return f
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background {
            runningFlow?.pauseForBackground()
            activeFlow?.persistNow()
        }
    }
}

struct NewSessionRequest: Identifiable {
    let id = UUID()
    var paradigm: Paradigm?
}

enum AppTab: Hashable {
    case home, catalog, library
}
