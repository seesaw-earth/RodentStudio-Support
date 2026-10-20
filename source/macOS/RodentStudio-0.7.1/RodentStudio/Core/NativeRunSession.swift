import Foundation
import Combine
import AVFoundation

/// What tracks a video: the task's Core ML model (RodentPose / RodentLimb) or RodentFlow's classic
/// centroid tracker with the video's saved RodentFlow setup.
enum RunKind {
    case pose(PoseModelKind)
    case flow(FlowTaskSetup)
}

/// One video to track in the guided workflow. The method comes from the task, never from the user.
struct RunRequest {
    let videoID: UUID
    let videoURL: URL
    let kind: RunKind
    let destination: URL
    let folder: String
    let displayName: String
    /// Video duration (s), for the progress display of the RodentFlow tracker.
    var durationSeconds: Double = 0

    init(videoID: UUID, videoURL: URL, kind: RunKind, destination: URL, folder: String,
         displayName: String, durationSeconds: Double = 0) {
        self.videoID = videoID
        self.videoURL = videoURL
        self.kind = kind
        self.destination = destination
        self.folder = folder
        self.displayName = displayName
        self.durationSeconds = durationSeconds
    }

    /// Core ML run (kept for callers written before RodentFlow runs joined the queue).
    init(videoID: UUID, videoURL: URL, model: PoseModelKind, destination: URL, folder: String, displayName: String) {
        self.init(videoID: videoID, videoURL: videoURL, kind: .pose(model), destination: destination,
                  folder: folder, displayName: displayName)
    }

    var model: PoseModelKind? {
        if case .pose(let m) = kind { return m }
        return nil
    }
}

struct RunJobProgress: Equatable {
    var videoID: UUID
    var name: String
    /// Position of this video in the current batch (0-based) and the batch size.
    var index: Int
    var count: Int
    var fraction: Double
}

/// Run state shared by the guided workflow and the Advanced tools.
///
/// All guided analyses go through one queue, one video at a time: RodentPose / RodentLimb (segmented Core
/// ML engine) and RodentFlow (classic centroid tracker) alike. Results are written to the app container,
/// survive a restart and can be resumed. A queued video is only marked as running when it starts, so
/// "Pause all" leaves waiting videos exactly as they were.
///
/// The session also holds the one saved result loaded for review. It records the run folder it was read
/// from, so a re-run (new folder) is never shown with the previous result.
@MainActor
final class NativeRunSession: ObservableObject {
    @Published var shortResult: NativeTrackingResult?
    @Published var shortVideoURL: URL?
    @Published var longManifest: LongVideoManifest?
    @Published var longDirectory: URL?
    @Published var longVideoURL: URL?
    /// Workspace video the loaded result belongs to (nil for results opened in Advanced).
    @Published var videoID: UUID?
    /// Run folder the loaded result was read from (nil for results opened in Advanced).
    @Published private(set) var loadedFolder: URL?
    @Published private(set) var job: RunJobProgress?
    @Published private(set) var pending: [RunRequest] = [] {
        didSet { pendingIDs = pending.map(\.videoID) }
    }
    /// Video IDs waiting in the queue, in order (published separately because RunRequest is not Equatable).
    @Published private(set) var pendingIDs: [UUID] = []
    @Published private(set) var loadingVideoID: UUID?
    /// Video whose saved result could not be read, with the reason.
    @Published private(set) var loadFailure: (videoID: UUID, message: String)?
    @Published private(set) var livePreview: NativeLivePreview?
    @Published private(set) var currentSourceTime: Double = 0
    @Published private(set) var remainingEstimate: Double?

    private var currentJobStart: TimeInterval = 0
    private var progressOriginFraction: Double?
    private var batchDone = 0
    private var batchTotal = 0

    private var cancellation: NativeTrackingCancellation?
    private var flowTask: Task<Void, Never>?
    private var loadTicket = 0

    var loadingResult: Bool { loadingVideoID != nil }

    func acceptShort(_ result: NativeTrackingResult, source: URL, videoID: UUID? = nil, folder: URL? = nil) {
        shortResult = result
        shortVideoURL = source
        longManifest = nil
        longDirectory = nil
        longVideoURL = nil
        self.videoID = videoID
        loadedFolder = folder
    }

    func acceptLong(_ manifest: LongVideoManifest, directory: URL, source: URL, videoID: UUID? = nil, folder: URL? = nil) {
        shortResult = nil
        shortVideoURL = nil
        longManifest = manifest
        longDirectory = directory
        longVideoURL = source
        self.videoID = videoID
        loadedFolder = folder
    }

    func clear() {
        livePreview = nil
        remainingEstimate = nil
        shortResult = nil
        shortVideoURL = nil
        longManifest = nil
        longDirectory = nil
        longVideoURL = nil
        videoID = nil
        loadedFolder = nil
    }

    var hasResult: Bool { shortResult != nil || longManifest != nil }
    var isRunning: Bool { job != nil }

    /// The loaded result is the saved run of `video` (same video and same run folder).
    func holdsResult(of video: VideoRecord, store: WorkspaceStore) -> Bool {
        guard hasResult, videoID == video.id, let folder = store.runFolderURL(video) else { return false }
        return loadedFolder?.standardizedFileURL == folder.standardizedFileURL
    }

    func isQueued(_ id: UUID) -> Bool { pendingIDs.contains(id) }

    /// 1-based position in the waiting queue.
    func queuePosition(_ id: UUID) -> Int? { pendingIDs.firstIndex(of: id).map { $0 + 1 } }

    /// Pauses the running analysis (finished segments / checkpoints are kept) and empties the queue.
    func cancelJob() {
        pending.removeAll()
        cancellation?.cancel()
        flowTask?.cancel()
    }

    /// Takes a waiting video out of the queue; it keeps its previous state.
    func removeFromQueue(_ id: UUID) {
        let before = pending.count
        pending.removeAll { $0.videoID == id }
        batchTotal -= before - pending.count
        if let job { self.job?.count = max(job.count - (before - pending.count), job.index + 1) }
    }

    /// Adds videos to the queue (videos already running or waiting are skipped) and starts it if idle.
    func enqueue(_ requests: [RunRequest], store: WorkspaceStore) {
        var busy = Set(pendingIDs)
        if let job { busy.insert(job.videoID) }
        var fresh: [RunRequest] = []
        for r in requests where !busy.contains(r.videoID) {
            fresh.append(r)
            busy.insert(r.videoID)
        }
        guard !fresh.isEmpty else { return }
        pending.append(contentsOf: fresh)
        batchTotal += fresh.count
        if job != nil {
            job?.count = batchTotal
        } else {
            startNext(store: store)
        }
    }

    /// Backwards-compatible entry point: queues the requests.
    func start(_ requests: [RunRequest], store: WorkspaceStore, loadResultFor focusID: UUID? = nil) {
        enqueue(requests, store: store)
    }

    private func startNext(store: WorkspaceStore) {
        guard job == nil else { return }
        guard !pending.isEmpty else {
            batchDone = 0
            batchTotal = 0
            cancellation = nil
            flowTask = nil
            remainingEstimate = nil
            return
        }
        let r = pending.removeFirst()
        job = RunJobProgress(videoID: r.videoID, name: r.displayName, index: batchDone, count: max(batchTotal, batchDone + 1), fraction: 0)
        currentJobStart = ProcessInfo.processInfo.systemUptime
        progressOriginFraction = nil
        livePreview = nil
        remainingEstimate = nil
        currentSourceTime = 0
        // A result loaded for review that belongs to this video is now outdated.
        if videoID == r.videoID { clear() }
        switch r.kind {
        case .pose(let model):
            store.markRunStarted(r.videoID, folder: r.folder, model: model)
            runPose(r, model: model, store: store)
        case .flow(let queued):
            // The setup saved when the run starts is used (it may have been edited while waiting).
            let setup = store.video(r.videoID)?.calibration?.flow ?? queued
            store.startFlowRun(r.videoID, folder: r.folder)
            runFlow(r, setup: setup, store: store)
        }
    }

    private func finishJob(store: WorkspaceStore) {
        job = nil
        batchDone += 1
        livePreview = nil
        startNext(store: store)
    }

    private func updateProgress(_ id: UUID, fraction: Double, sourceTime: Double?) {
        guard job?.videoID == id else { return }
        job?.fraction = fraction
        if let sourceTime { currentSourceTime = sourceTime }
        if progressOriginFraction == nil { progressOriginFraction = fraction }
        let processed = fraction - (progressOriginFraction ?? 0)
        let elapsed = ProcessInfo.processInfo.systemUptime - currentJobStart
        // Resume-aware estimate: only this run's completed fraction determines throughput.
        if elapsed > 8 && processed > 0.015 && fraction < 0.995 {
            remainingEstimate = min(86400 * 7, elapsed * (1 - fraction) / processed)
        } else if fraction >= 0.995 {
            remainingEstimate = 0
        }
    }

    // MARK: RodentPose / RodentLimb (segmented Core ML engine)

    private func runPose(_ r: RunRequest, model: PoseModelKind, store: WorkspaceStore) {
        let token = NativeTrackingCancellation()
        cancellation = token
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let access = r.videoURL.startAccessingSecurityScopedResource()
            defer { if access { r.videoURL.stopAccessingSecurityScopedResource() } }
            do {
                let manifest = try LongVideoTrackingEngine.run(videoURL: r.videoURL, destination: r.destination,
                                                               kind: model, segmentSeconds: 120,
                                                               cancellation: token) { p in
                    let fraction: Double
                    if let time = p.sourceTime, let duration = p.sourceDuration, duration > 0 {
                        fraction = min(1, max(0, time / duration))
                    } else {
                        fraction = min(1, Double(p.completedSegments) / Double(max(1, p.totalSegments)))
                    }
                    let snapshot = p.livePreview
                    let time = p.sourceTime
                    Task { @MainActor [weak self] in
                        guard let self, self.job?.videoID == r.videoID else { return }
                        if let snapshot { self.livePreview = snapshot }
                        self.updateProgress(r.videoID, fraction: fraction, sourceTime: time)
                    }
                }
                let frames = manifest.completed.reduce(0) { $0 + $1.records }
                let failed = manifest.completed.reduce(0) { $0 + $1.failedFrames }
                Task { @MainActor [weak self] in
                    store.markRunFinished(r.videoID, frames: frames, failedFrames: failed)
                    self?.finishJob(store: store)
                }
            } catch {
                let cancelled = token.isCancelled
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    store.markRunStopped(r.videoID, message: message, cancelled: cancelled)
                    self?.finishJob(store: store)
                }
            }
        }
    }

    // MARK: RodentFlow (classic centroid tracker, 10 Hz)

    private func runFlow(_ r: RunRequest, setup: FlowTaskSetup, store: WorkspaceStore) {
        cancellation = nil
        let id = r.videoID
        let duration = r.durationSeconds
        flowTask = Task { @MainActor [weak self] in
            let access = r.videoURL.startAccessingSecurityScopedResource()
            defer { if access { r.videoURL.stopAccessingSecurityScopedResource() } }
            do {
                let result = try await FlowDesktopRun.run(videoURL: r.videoURL, folder: r.destination, setup: setup) { snapshot in
                    let fraction = snapshot.fraction
                    Task { @MainActor [weak self] in
                        self?.updateProgress(id, fraction: fraction, sourceTime: duration > 0 ? fraction * duration : nil)
                    }
                }
                let undetected = result.points.filter { $0.interpolated }.count
                store.markRunFinished(id, frames: result.points.count, failedFrames: undetected)
            } catch {
                let cancelled = error is CancellationError || Task.isCancelled
                store.markRunStopped(id, message: cancelled ? L("Paused", "已暂停") : error.localizedDescription, cancelled: cancelled)
            }
            self?.finishJob(store: store)
        }
    }

    // MARK: Loading saved results for review

    /// Loads the saved run of a video for review. Runs up to `SegmentedRunLoader.inMemoryFrameLimit`
    /// frames are read into memory (frame-by-frame review, RodentLimb results); longer runs are reviewed
    /// from their segments. RodentFlow runs are read by the review views themselves.
    func loadSaved(_ video: VideoRecord, store: WorkspaceStore) {
        guard video.runState == .complete, video.runModel != WorkspaceStore.flowRunModel,
              let folder = store.runFolderURL(video) else { return }
        if holdsResult(of: video, store: store) { return }
        if loadingVideoID == video.id { return }
        loadTicket += 1
        let ticket = loadTicket
        let source = store.resolveURL(video)
        let id = video.id
        loadingVideoID = id
        if loadFailure?.videoID == id { loadFailure = nil }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let manifestURL = folder.appendingPathComponent(LongVideoTrackingEngine.manifestName)
            var manifest: LongVideoManifest?
            var readError: String?
            do {
                manifest = try JSONDecoder().decode(LongVideoManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                readError = error.localizedDescription
            }
            var loaded: NativeTrackingResult?
            if let manifest, manifest.completed.reduce(0, { $0 + $1.records }) <= SegmentedRunLoader.inMemoryFrameLimit {
                do {
                    loaded = try SegmentedRunLoader.load(manifest: manifest, folder: folder, videoURL: source)
                } catch {
                    readError = error.localizedDescription
                }
            }
            let result = loaded
            let message = readError
            Task { @MainActor [weak self] in
                guard let self, self.loadTicket == ticket else { return }
                self.loadingVideoID = nil
                if let result, let source {
                    self.acceptShort(result, source: source, videoID: id, folder: folder)
                } else if let manifest {
                    self.acceptLong(manifest, directory: folder,
                                    source: source ?? folder.appendingPathComponent(manifest.sourceFile), videoID: id, folder: folder)
                } else {
                    self.loadFailure = (id, message ?? L("The saved results of this video could not be read.", "无法读取该视频已保存的结果。"))
                }
            }
        }
    }
}

/// Reads completed segment CSVs written by `LongVideoTrackingEngine` back into a frame list.
enum SegmentedRunLoader {
    static let inMemoryFrameLimit = 150_000

    enum LoadError: LocalizedError {
        case unknownModel(String)
        var errorDescription: String? {
            switch self {
            case .unknownModel(let m): return "Unknown model in manifest: \(m)"
            }
        }
    }

    static func load(manifest: LongVideoManifest, folder: URL, videoURL: URL?) throws -> NativeTrackingResult {
        guard let model = PoseModelKind(rawValue: manifest.modelName) else { throw LoadError.unknownModel(manifest.modelName) }
        let pointCount = model == .mousePose ? 6 : 7
        let failedColumn = 4 + pointCount * 3
        var frames: [NativeTrackedFrame] = []
        frames.reserveCapacity(manifest.completed.reduce(0) { $0 + $1.records })
        var firstPTS: Double?
        var index = 0
        for segment in manifest.completed.sorted(by: { $0.index < $1.index }) {
            let text = try String(contentsOf: folder.appendingPathComponent(segment.file), encoding: .utf8)
            var header = true
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                if header { header = false; continue }
                let cells = line.split(separator: ",", omittingEmptySubsequences: false)
                guard cells.count >= failedColumn, let pts = Double(cells[1]) else { continue }
                let score = Double(cells[3]) ?? 0
                var points: [NativeTrackPoint] = []
                points.reserveCapacity(pointCount)
                for k in 0..<pointCount {
                    let b = 4 + k * 3
                    if let x = Double(cells[b]), let y = Double(cells[b + 1]) {
                        points.append(NativeTrackPoint(x: x, y: y, confidence: Double(cells[b + 2]) ?? 0))
                    } else {
                        points.append(.missing)
                    }
                }
                let failed = cells.count > failedColumn && cells[failedColumn] == "1"
                let origin = firstPTS ?? pts
                if firstPTS == nil { firstPTS = pts }
                frames.append(NativeTrackedFrame(index: index, time: pts - origin, score: score, points: points, inferenceFailed: failed))
                index += 1
            }
        }
        var width = 0, height = 0
        var fps = 0.0
        if let videoURL {
            let access = videoURL.startAccessingSecurityScopedResource()
            defer { if access { videoURL.stopAccessingSecurityScopedResource() } }
            if let track = AVURLAsset(url: videoURL).tracks(withMediaType: .video).first {
                let r = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
                width = Int(abs(r.width).rounded())
                height = Int(abs(r.height).rounded())
                fps = Double(track.nominalFrameRate)
            }
        }
        return NativeTrackingResult(model: model, videoFile: manifest.sourceFile, videoWidth: width, videoHeight: height,
                                    fps: fps, timeOffset: firstPTS ?? 0, frames: frames, elapsedSeconds: 0)
    }
}
