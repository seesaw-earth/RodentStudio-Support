import SwiftUI
import Observation
/// Everything the user tunes once per rig is remembered between launches.
struct TSTPersistedSettings: Codable, Equatable {
    var analysis = AnalysisSettings()
    var keyFrame = KeyFrameSettings()
    var detectorMode: TSTDetectorMode = .auto
    var scanFPS: Double = 4
    /// 2 = box pixel-difference metric and whole-video window are the defaults. nil = saved earlier.
    var revision: Int? = 2
}

/// On/off switch that the background analysis loop can read safely while the UI changes it.
final class TSTAtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    var isOn: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
}

enum TSTSettingsStore {
    private static let key = "TSTRodentStudio.TSTMulti.Settings.v1"
    static func load() -> TSTPersistedSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              var s = try? JSONDecoder().decode(TSTPersistedSettings.self, from: d) else { return TSTPersistedSettings() }
        // Settings saved before the refined outline existed: switch it on (it can be turned off again).
        if s.analysis.refinedOutline == nil { s.analysis.refinedOutline = true }
        // Settings saved before revision 2: move to the new defaults once (box pixel difference, whole
        // video after the key frame). Both can be changed back in the app.
        if (s.revision ?? 0) < 2 {
            s.analysis.metric = .box
            s.analysis.limitDuration = nil
            s.revision = 2
        }
        return s
    }
    static func save(_ s: TSTPersistedSettings) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }
}

/// Workflow:
///  1. chambers   – count and walls found automatically (YOLO boxes or dark blobs + wall edges)
///  2. selection  – user taps the chambers that will hold a mouse
///  3. scan       – detector runs through the video; key frame = first moment every selected chamber
///                  has a mouse continuously for `stableSec`
///  4. key frame  – user reviews / nudges the key frame, analysis band is fitted to the mice
///  5. analysis   – posture (contour) algorithm from the key frame for `durationSec`
@MainActor
@Observable
final class TSTAppModel {
    enum Phase: Equatable { case home, loading, chambers, scanning, keyframe, analyzing, results }

    var phase: Phase = .home
    var statusText = ""
    var errorMessage: String?

    // video
    var videoName = ""
    var info: TSTVideoInfo?

    // settings
    var stored: TSTPersistedSettings = TSTSettingsStore.load()
    var settings: AnalysisSettings {
        get { stored.analysis }
        set { stored.analysis = newValue }
    }

    // detector
    @ObservationIgnored private var yolo: TSTYOLOMouseDetector?
    var detectorName = ""
    var yoloAvailable = false

    // chambers
    var samples: [GrayImage] = []
    var sampleTimes: [Double] = []
    var sampleDetections: [[DetBox]] = []
    var preview: CGImage?
    var layout: ChamberLayout?
    var autoDetected = false

    // key-frame scan
    var scanProgress: Double = 0
    var scanText = ""
    var scanPreview: CGImage?
    var scanTimes: [Double] = []
    var scanDetections: [[DetBox?]] = []
    var keyResult: KeyFrameResult?
    var keyTime: Double = 0
    var keyFrameImage: CGImage?
    var keyFrameBoxes: [DetBox] = []
    var keyFrameIsManual = false
    /// Suspension times (absolute) kept from a saved analysis whose scan was not archived (older archives),
    /// so a re-analysis still times every mouse from its own suspension. Cleared by a new scan or start.
    var restoredOnsets: [Double]?

    // analysis
    var progress: Double = 0
    var progressText = ""
    var livePreview: CGImage?
    /// Time estimates of the running analysis / scan (wall-clock seconds; nil until there is enough data).
    var analysisElapsed: Double = 0
    var analysisRemaining: Double?
    /// Video seconds processed per wall-clock second.
    var analysisSpeed: Double?
    var scanRemaining: Double?
    /// The live picture during the analysis. Rendering it costs little (a few times per second); turning it
    /// off mainly saves the drawing work on slower Macs.
    private(set) var livePreviewEnabled = true
    @ObservationIgnored private let previewSwitch = TSTAtomicFlag(true)

    func setLivePreview(_ on: Bool) {
        livePreviewEnabled = on
        previewSwitch.set(on)
        if !on { livePreview = nil }
    }
    var result: TSTMultiAnalysisResult?
    var measures: [[FrameMeasure]] = []

    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init() { reloadDetector() }

    // MARK: - State used by the guided sheet

    /// Decoding / detection / analysis is running; navigation is locked until it finishes or is stopped.
    var isBusy: Bool { phase == .loading || phase == .scanning || phase == .analyzing }

    /// Work that would be lost by closing the sheet or choosing another video.
    var hasUnsavedWork: Bool {
        result != nil || keyResult != nil || phase == .scanning || phase == .analyzing
    }

    /// The key-frame step can be opened (a scan was done, or a start time was set by hand).
    var keyFrameAvailable: Bool { keyResult != nil && layout != nil }

    /// The current result was computed with exactly the chambers, band and time window shown now.
    /// When the user changes any of them the result is kept but is no longer offered as current.
    var resultMatchesSetup: Bool {
        guard let r = result, let layout else { return false }
        let w = analysisWindow
        return r.layout == layout
            && Self.sameAnalysisInputs(r.settings, settings)
            && abs(r.settings.startSec - w.start) < 0.001
            && abs(r.settings.durationSec - w.duration) < 0.001
    }

    /// Settings that are applied while the video is processed (changing them needs a new analysis). The
    /// others — measure, threshold, smoothing, minimum bout, last window — only re-score.
    static func sameAnalysisInputs(_ a: AnalysisSettings, _ b: AnalysisSettings) -> Bool {
        a.useRefinedOutline == b.useRefinedOutline && a.alignRotation == b.alignRotation
            && a.diffThreshold == b.diffThreshold && a.mouseDark == b.mouseDark && a.otsuOffset == b.otsuOffset
            && a.targetFPS == b.targetFPS && a.processingWidth == b.processingWidth
            && a.edgeTolerancePx == b.edgeTolerancePx && abs(a.compareLagSec - b.compareLagSec) < 1e-9
    }

    /// Chamber geometry changed (count, walls, re-detection). The scan's detections were assigned to the old
    /// chambers; re-assign them to the new ones (by box centre) instead of throwing away a scan that may
    /// have taken minutes, then recompute the key frame. The analysed band and a hand-set start are kept.
    private func remapScan() {
        guard let layout else { return }
        if scanTimes.isEmpty {
            // Start set by hand without a scan: only the chamber count has to match.
            if let k = keyResult, k.selected.count != layout.count {
                restoredOnsets = nil
                keyResult = KeyFrameResult(times: [], presence: Array(repeating: [], count: layout.count),
                                           selected: layout.enabled, keyTime: nil,
                                           hungAt: Array(repeating: nil, count: layout.count), allPresentEnd: nil)
            }
            return
        }
        restoredOnsets = nil
        let minConfidence = stored.keyFrame.minConfidence
        scanDetections = scanDetections.map { BoxOps.assign($0.compactMap { $0 }, to: layout, minConfidence: minConfidence) }
        keyResult = KeyFrameFinder.find(times: scanTimes, detections: scanDetections, selected: layout.enabled,
                                        settings: stored.keyFrame)
        if !keyFrameIsManual, let t = keyResult?.keyTime, abs(t - keyTime) > 0.001 { setKeyTime(t) }
    }

    /// Cancel any running scan/analysis before switching to a new recording.
    func resetForNewRecording() {
        work?.cancel()
        previewTask?.cancel()
        work = nil
        previewTask = nil
        result = nil
        measures = []
        layout = nil
        info = nil
        samples = []
        keyResult = nil
        scanTimes = []
        scanDetections = []
        keyFrameIsManual = false
        restoredOnsets = nil
        errorMessage = nil
        videoName = ""
        phase = .home
    }

    // MARK: - Detector

    func reloadDetector() {
        yolo = TSTModelStore.loadYOLO()
        yoloAvailable = yolo != nil
        detectorName = activeDetector.name
    }

    var activeDetector: TSTMouseDetecting {
        switch stored.detectorMode {
        case .classical: return TSTClassicalDetector(mouseDark: settings.mouseDark)
        case .yolo, .auto: return yolo ?? TSTClassicalDetector(mouseDark: settings.mouseDark)
        }
    }

    var usingYOLO: Bool { stored.detectorMode != .classical && yolo != nil }

    func importModel(_ url: URL) {
        Task {
            do {
                try await TSTModelStore.importModel(from: url)
                reloadDetector()
                errorMessage = L("Model imported: ", "模型已导入：") + detectorName
            } catch {
                errorMessage = L("Could not import the model: ", "无法导入模型：") + error.localizedDescription
            }
        }
    }

    func removeImportedModel() {
        TSTModelStore.removeImported()
        reloadDetector()
    }

    // MARK: - 1. Open video and find chambers

    func open(url: URL, name: String) {
        work?.cancel()
        previewTask?.cancel()
        videoName = name
        errorMessage = nil
        info = nil
        result = nil; measures = []; layout = nil; preview = nil; samples = []
        keyResult = nil; scanTimes = []; scanDetections = []; keyFrameImage = nil; keyFrameBoxes = []
        keyFrameIsManual = false; keyTime = 0; restoredOnsets = nil
        phase = .loading
        statusText = L("Reading video…", "正在读取视频…")
        work = Task {
            do {
                info = try await TSTVideoFrameReader.loadInfo(url: url)
                try await detectChambers()
                phase = .chambers
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
                phase = .home
            }
        }
    }

    /// Opens a SAVED recording again with everything it was analysed with: settings, chambers, analysed band,
    /// key-frame scan and start. With the archived per-frame measures the saved result comes back at once
    /// (scoring can be changed without decoding the video); otherwise the key-frame step is shown, ready to
    /// analyse again.
    func reopen(_ source: TSTReanalysisSource) {
        work?.cancel()
        previewTask?.cancel()
        let record = source.record
        videoName = record.videoName
        errorMessage = nil
        info = nil
        result = nil; measures = []; layout = nil; preview = nil; samples = []
        keyResult = nil; scanTimes = []; scanDetections = []; keyFrameImage = nil; keyFrameBoxes = []
        keyFrameIsManual = false; keyTime = 0; restoredOnsets = nil
        var s = record.settings
        s.chamberOnsetSec = nil
        settings = s
        if let k = record.keyFrameSettings, k != stored.keyFrame { stored.keyFrame = k }
        phase = .loading
        statusText = L("Opening the saved recording…", "正在打开保存的录像…")
        work = Task {
            do {
                info = try await TSTVideoFrameReader.loadInfo(url: source.url)
                try await detectChambers()
                restore(source)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
                phase = .home
            }
        }
    }

    private func restore(_ source: TSTReanalysisSource) {
        let record = source.record
        errorMessage = nil   // the fresh detection may have complained; the saved chambers are used instead
        if let saved = source.layout, let first = samples.first {
            var l = saved.scaled(toWidth: first.width, height: first.height)
            // Wall strengths only snap walls when the count is changed; older archives did not keep them.
            if l.wallProfile.isEmpty, l != saved || record.layout == nil,
               let detected = layout, detected.imageWidth == l.imageWidth {
                l.wallProfile = detected.wallProfile
            }
            if l.empty.count != l.count { l.empty = Array(repeating: false, count: l.count) }
            layout = l
        }
        guard let layout else { phase = .chambers; return }
        let times = record.scanTimes ?? []
        if !times.isEmpty, let dets = record.scanDetections, dets.count == times.count {
            scanTimes = times
            let minConfidence = stored.keyFrame.minConfidence
            scanDetections = dets.allSatisfy({ $0.count == layout.count })
                ? dets
                : dets.map { BoxOps.assign($0.compactMap { $0 }, to: layout, minConfidence: minConfidence) }
            keyResult = KeyFrameFinder.find(times: scanTimes, detections: scanDetections, selected: layout.enabled,
                                            settings: stored.keyFrame)
            keyFrameIsManual = record.keyFrameManual ?? false
        } else {
            keyResult = KeyFrameResult(times: [], presence: Array(repeating: [], count: layout.count),
                                       selected: layout.enabled, keyTime: nil,
                                       hungAt: Array(repeating: nil, count: layout.count), allPresentEnd: nil)
            keyFrameIsManual = true
            if let onsets = source.onsets, onsets.count == layout.count { restoredOnsets = onsets }
        }
        setKeyTime(record.keyFrameTime)
        if let m = source.measures, let saved = source.layout, m.count == saved.count {
            measures = m
            result = Scorer.score(measures: m, layout: saved, settings: record.settings, fps: record.fps)
        }
        phase = result != nil && resultMatchesSetup ? .results : .keyframe
    }

    /// Samples frames across the WHOLE video (mice are hung during the recording) and finds the chambers.
    func detectChambers() async throws {
        guard let info else { return }
        statusText = L("Sampling frames…", "正在抽取画面…")
        let n = max(8, settings.detectionSamples)
        let times = (0..<n).map { info.duration * (Double($0) + 0.5) / Double(n) }
        let reader = TSTVideoFrameReader(info: info, processingWidth: settings.processingWidth)
        let frames = try await Task.detached(priority: .userInitiated) { try await reader.sampleFrames(at: times) }.value
        let mouseDark = settings.mouseDark
        let yolo = usingYOLO ? self.yolo : nil
        statusText = yolo != nil ? L("Detecting mice (YOLO)…", "正在识别小鼠（YOLO）…") : L("Finding chambers…", "正在寻找格子…")
        let classical = TSTClassicalDetector(mouseDark: mouseDark)
        let (found, perSample) = try await Task.detached(priority: .userInitiated) { () -> (ChamberLayout?, [[DetBox]]) in
            var dets: [[DetBox]] = []
            if let yolo {
                for f in frames {
                    try Task.checkCancellation()
                    dets.append((try? yolo.detect(f, layout: nil)) ?? [])
                }
            }
            let filtered = dets.map { $0.filter { $0.confidence >= 0.35 } }
            let layout = ChamberDetector.detect(frames: frames, mouseDark: mouseDark,
                                                detections: yolo != nil ? filtered : nil)
            // per-sample boxes for pre-selecting chambers (classical detector needs the layout first)
            if yolo == nil, let layout {
                dets = frames.map { (try? classical.detect($0, layout: layout)) ?? [] }
            }
            return (layout, dets)
        }.value
        samples = frames
        sampleTimes = Array(times.prefix(frames.count))
        preview = TSTImageRendering.cgImage(frames[frames.count / 2])
        if var l = found {
            // pre-select chambers in which a mouse was seen in ≥ 2 samples
            sampleDetections = perSample
            var seen = [Int](repeating: 0, count: l.count)
            for boxes in perSample {
                for (i, b) in BoxOps.assign(boxes, to: l, minConfidence: stored.keyFrame.minConfidence).enumerated() where b != nil {
                    seen[i] += 1
                }
            }
            l.enabled = seen.map { $0 >= 2 }
            if !l.enabled.contains(true) { l.enabled = l.empty.map { !$0 } }
            layout = l
            autoDetected = true
        } else {
            layout = ChamberLayout.equalSplit(width: frames[0].width, height: frames[0].height, count: 6)
            sampleDetections = []
            autoDetected = false
            errorMessage = L("Chambers could not be found automatically. The picture was split evenly into 6 — set the number of chambers and drag the white handles onto the walls.",
                             "未能自动找到格子，已先平均分成 6 格。请设置格子数，并把白色手柄拖到隔板上。")
        }
    }

    func redetect() {
        work?.cancel()
        errorMessage = nil
        statusText = L("Finding chambers…", "正在寻找格子…")
        phase = .loading
        work = Task {
            do {
                try await detectChambers()
                remapScan()
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
            phase = .chambers
        }
    }

    // MARK: - Layout editing

    func setChamberCount(_ n: Int) {
        guard let l = layout, n >= 1, n <= 16 else { return }
        layout = ChamberDetector.refit(l, count: n)
        remapScan()
    }

    func equalSplit() {
        guard let first = samples.first else { return }
        let n = layout?.count ?? 6
        var l = ChamberLayout.equalSplit(width: first.width, height: first.height, count: n)
        l.wallProfile = layout?.wallProfile ?? []
        // Keep which chambers were selected when the count is unchanged.
        if let old = layout, old.enabled.count == l.enabled.count { l.enabled = old.enabled }
        layout = l
        remapScan()
    }

    func moveWall(_ j: Int, to x: Double) {
        guard var l = layout, j >= 0, j < l.walls.count else { return }
        let lo = j > 0 ? l.walls[j - 1] + 4 : 0
        let hi = j < l.walls.count - 1 ? l.walls[j + 1] - 4 : Double(l.imageWidth - 1)
        l.walls[j] = min(max(x, lo), hi)
        layout = l
        remapScan()
    }

    func moveBand(top: Bool, to y: Double) {
        guard var l = layout else { return }
        if top { l.y0 = Int(min(max(0, y), Double(l.y1 - 10))) }
        else { l.y1 = Int(max(min(Double(l.imageHeight), y), Double(l.y0 + 10))) }
        layout = l
    }

    func toggleChamber(_ i: Int) {
        guard var l = layout, i < l.enabled.count else { return }
        l.enabled[i].toggle()
        layout = l
        if keyResult != nil { recomputeKeyFrame() }
    }

    func setAllChambers(_ on: Bool) {
        guard var l = layout else { return }
        l.enabled = Array(repeating: on, count: l.count)
        layout = l
        if keyResult != nil { recomputeKeyFrame() }
    }

    var selectedCount: Int { layout?.enabled.filter { $0 }.count ?? 0 }

    // MARK: - 3. Key-frame scan

    func startScan() {
        guard let info, let layout, selectedCount > 0 else { return }
        work?.cancel()
        let detector = activeDetector
        detectorName = detector.name
        let step = max(1, Int((info.fps / stored.scanFPS).rounded()))
        let processingWidth = settings.processingWidth
        let keySettings = stored.keyFrame
        let selected = layout.enabled
        errorMessage = nil
        keyFrameIsManual = false
        restoredOnsets = nil
        phase = .scanning
        scanProgress = 0; scanText = L("Starting…", "正在开始…"); scanPreview = nil; scanRemaining = nil
        scanTimes = []; scanDetections = []; keyResult = nil
        work = Task.detached(priority: .userInitiated) {
            do {
                let reader = TSTVideoFrameReader(info: info, processingWidth: processingWidth)
                var times: [Double] = [], dets: [[DetBox?]] = []
                var lastUI = Date.distantPast
                let scanStarted = Date()
                try await reader.readSequential(start: 0, end: info.duration, step: step) { frame, t in
                    let boxes = try detector.detect(frame, layout: layout)
                    times.append(t)
                    dets.append(BoxOps.assign(boxes, to: layout, minConfidence: keySettings.minConfidence))
                    if Date().timeIntervalSince(lastUI) > 0.35 {
                        lastUI = Date()
                        let img = TSTImageRendering.detections(frame: frame, layout: layout, boxes: boxes, selected: selected)
                        let k = KeyFrameFinder.find(times: times, detections: dets, selected: selected, settings: keySettings)
                        let p = min(1, t / max(0.1, info.duration))
                        let scanElapsed = Date().timeIntervalSince(scanStarted)
                        let scanEta: Double? = p > 0.02 ? scanElapsed / p - scanElapsed : nil
                        let found = k.keyTime.map { String(format: L(" · key frame at %.1f s", " · 关键帧在 %.1f 秒"), $0) } ?? ""
                        let text = String(format: "%.0f / %.0f s", t, info.duration) + found
                        let (tt, dd) = (times, dets)
                        Task { @MainActor in
                            // A late update must not bring back a scan that was stopped or already finished.
                            guard self.phase == .scanning else { return }
                            self.scanProgress = p; self.scanText = text; self.scanPreview = img
                            self.scanRemaining = scanEta
                            self.scanTimes = tt; self.scanDetections = dd; self.keyResult = k
                        }
                    }
                }
                let finalTimes = times, finalDets = dets
                let k = KeyFrameFinder.find(times: finalTimes, detections: finalDets, selected: selected, settings: keySettings)
                await MainActor.run {
                    self.scanTimes = finalTimes; self.scanDetections = finalDets; self.keyResult = k
                    self.finishScan()
                }
            } catch is CancellationError {
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.phase = .chambers
                }
            }
        }
    }

    /// Stop scanning early once a key frame has been found (the end-of-test detection is then unknown).
    func useKeyFrameNow() {
        guard keyResult?.keyTime != nil else { return }
        work?.cancel()
        finishScan()
    }

    func cancelScan() {
        work?.cancel()
        keyResult = nil
        scanTimes = []
        scanDetections = []
        phase = .chambers
    }

    /// Skip the scan: analyse from a manually chosen time.
    func skipScan(start: Double = 0) {
        guard let layout else { return }
        work?.cancel()
        keyResult = KeyFrameResult(times: [], presence: Array(repeating: [], count: layout.count),
                                   selected: layout.enabled, keyTime: nil,
                                   hungAt: Array(repeating: nil, count: layout.count), allPresentEnd: nil)
        keyFrameIsManual = true
        restoredOnsets = nil
        setKeyTime(start)
        fitBandFromDetections()
        phase = .keyframe
    }

    private func finishScan() {
        keyFrameIsManual = keyResult?.keyTime == nil
        if keyResult?.keyTime == nil {
            errorMessage = String(format: L("No moment was found where every selected chamber had a mouse for %d s. Check which chambers are selected, lower the confidence in Detection settings, or set the start time by hand below.",
                                            "没有找到所有选中格子同时有小鼠并持续 %d 秒的时刻。请检查选中的格子、在“检测设置”中降低置信度，或在下方手动设定起点。"),
                                  Int(stored.keyFrame.stableSec))
        }
        setKeyTime(keyResult?.keyTime ?? 0)
        fitBandFromDetections()
        phase = .keyframe
    }

    func recomputeKeyFrame() {
        guard let layout, !scanTimes.isEmpty else { return }
        keyResult = KeyFrameFinder.find(times: scanTimes, detections: scanDetections, selected: layout.enabled,
                                        settings: stored.keyFrame)
        if !keyFrameIsManual, let t = keyResult?.keyTime { setKeyTime(t) }
        fitBandFromDetections()
    }

    func setKeyTime(_ t: Double, manual: Bool = false) {
        guard let info else { return }
        keyTime = min(max(0, t), max(0, info.duration - 1))
        if manual { keyFrameIsManual = true }
        loadKeyFramePreview()
    }

    func resetKeyTimeToDetected() {
        keyFrameIsManual = false
        if let t = keyResult?.keyTime { setKeyTime(t) }
    }

    private func loadKeyFramePreview() {
        guard let info, let layout else { return }
        previewTask?.cancel()
        let t = keyTime, width = settings.processingWidth
        let detector = activeDetector
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(120))   // debounce slider drags
            guard !Task.isCancelled else { return }
            let reader = TSTVideoFrameReader(info: info, processingWidth: width)
            guard let f = try? await reader.frame(at: t), !Task.isCancelled else { return }
            let boxes = await Task.detached { (try? detector.detect(f, layout: layout)) ?? [] }.value
            guard !Task.isCancelled else { return }
            self.keyFrameBoxes = boxes
            self.keyFrameImage = TSTImageRendering.detections(frame: f, layout: layout, boxes: boxes, selected: layout.enabled)
        }
    }

    /// Vertical analysis band = union of the mice in the selected chambers during the first 30 s after the key frame.
    func fitBandFromDetections() {
        guard var l = layout else { return }
        var boxes: [DetBox] = []
        for (k, t) in scanTimes.enumerated() where t >= keyTime && t <= keyTime + 30 {
            for (i, b) in scanDetections[k].enumerated() where i < l.enabled.count && l.enabled[i] {
                if let b { boxes.append(b) }
            }
        }
        if boxes.isEmpty {   // no scan: use the chamber-detection samples
            for s in sampleDetections {
                for (i, b) in BoxOps.assign(s, to: l, minConfidence: stored.keyFrame.minConfidence).enumerated()
                where i < l.enabled.count && l.enabled[i] { if let b { boxes.append(b) } }
            }
        }
        if !boxes.isEmpty {
            // robust union: ignore the most extreme 2 % (e.g. a hand box assigned to a chamber)
            let y0s = boxes.map { $0.y0 }.sorted(), y1s = boxes.map { $0.y1 }.sorted()
            let lo = y0s[Int(Double(y0s.count - 1) * 0.02)], hi = y1s[Int(Double(y1s.count - 1) * 0.98)]
            l = l.fittingBand(to: [DetBox(x0: 0, y0: lo, x1: 1, y1: hi, confidence: 1)])
        }
        layout = l
    }

    /// Effective analysis window: from the key frame to the END OF THE VIDEO. Only when the user turns on
    /// "Stop after" is it limited to `durationSec`. It is never cut short automatically; frames after a
    /// mouse was taken down are reported as "no mouse" for that chamber, not dropped for all chambers.
    var analysisWindow: (start: Double, duration: Double, cutReason: String?) {
        guard let info else { return (0, 0, nil) }
        // Starts when the FIRST mouse was suspended, so every mouse's own test is complete.
        var start = keyTime
        if let onsets = perMouseOnsets, let layout {
            for (i, onset) in onsets.enumerated() where i < layout.enabled.count && layout.enabled[i] {
                start = min(start, onset)
            }
        }
        var end = info.duration
        var reason: String? = nil
        if settings.stopsAtDuration {
            if start + settings.durationSec <= info.duration {
                end = start + settings.durationSec
            } else {
                reason = L("the video ends before the set duration", "视频在设定时长之前结束")
            }
        }
        return (start, max(0, end - start), reason)
    }

    /// When each mouse was suspended (absolute video time), from the key-frame scan: its first stable
    /// detection plus the settle delay, never later than the key frame. nil when the start was set by hand
    /// or there is no scan — then every mouse is timed from the key frame.
    var perMouseOnsets: [Double]? {
        if let restored = restoredOnsets, let layout, restored.count == layout.count, keyResult != nil {
            return restored.map { min(keyTime, $0) }
        }
        guard let layout, let k = keyResult, k.keyTime != nil, !keyFrameIsManual, !k.times.isEmpty else { return nil }
        return (0..<layout.count).map { i in
            guard i < k.hungAt.count, let hung = k.hungAt[i] else { return keyTime }
            return min(keyTime, hung + stored.keyFrame.settleSec)
        }
    }

    /// First time after the key frame at which some selected mouse stays undetected (taken down?), if the
    /// scan saw it inside the analysed window. Informational only.
    var mouseMissingFrom: Double? {
        let w = analysisWindow
        guard let e = keyResult?.allPresentEnd, e > w.start, e < w.start + w.duration else { return nil }
        return e
    }

    /// Motion box per chamber (image coordinates): where the detector saw the mouse from the key frame to
    /// the end of the analysed window (robust 2–98 % extent, so a hand or one wrong box does not inflate
    /// it), plus 10 % for limbs and swing; kept inside the chamber and the analysed band. With only the
    /// key-frame box it is widened for swing. nil = no detector box: the whole chamber is used.
    func motionBoxes() -> [DetBox?] {
        guard let layout else { return [] }
        let w = analysisWindow
        let end = w.start + w.duration
        let minConfidence = stored.keyFrame.minConfidence
        var groups = [[DetBox]](repeating: [], count: layout.count)
        for (k, t) in scanTimes.enumerated() where t >= keyTime && t <= end && k < scanDetections.count {
            for i in 0..<min(layout.count, scanDetections[k].count) {
                guard let b = scanDetections[k][i], b.confidence >= minConfidence, b.width >= 4, b.height >= 6,
                      b.width < 0.84 * layout.spacing, layout.chamberIndex(x: b.cx) == i else { continue }
                groups[i].append(b)
            }
        }
        let refs = segmentationReferences(for: layout, start: keyTime)
        func quantile(_ values: [Double], _ f: Double) -> Double {
            let s = values.sorted()
            return s[Int(Double(s.count - 1) * f)]
        }
        return (0..<layout.count).map { i -> DetBox? in
            guard i < layout.enabled.count, layout.enabled[i] else { return nil }
            var x0: Double, y0: Double, x1: Double, y1: Double
            if groups[i].count >= 3 {
                x0 = quantile(groups[i].map(\.x0), 0.02); y0 = quantile(groups[i].map(\.y0), 0.02)
                x1 = quantile(groups[i].map(\.x1), 0.98); y1 = quantile(groups[i].map(\.y1), 0.98)
            } else if i < refs.count, let r = refs[i] {
                x0 = r.cx - 0.8 * r.width; x1 = r.cx + 0.8 * r.width
                y0 = r.y0 - 0.15 * r.height; y1 = r.y1 + 0.15 * r.height
            } else {
                return nil
            }
            let mx = 0.10 * (x1 - x0), my = 0.10 * (y1 - y0)
            x0 = max(x0 - mx, layout.walls[i]); x1 = min(x1 + mx, layout.walls[i + 1])
            y0 = max(y0 - my, Double(layout.y0)); y1 = min(y1 + my, Double(layout.y1))
            guard x1 - x0 >= 4, y1 - y0 >= 4 else { return nil }
            return DetBox(x0: x0, y0: y0, x1: x1, y1: y1, confidence: 1)
        }
    }

    /// Reference positions estimated from already-computed YOLO/key-frame detections.
    /// They guide the contour search but DO NOT become the pixel masks. No per-frame
    /// Core ML inference is added to the time-critical 360-s analysis loop.
    private func segmentationReferences(for layout: ChamberLayout, start: Double) -> [DetBox?] {
        var groups = [[DetBox]](repeating: [], count: layout.count)
        func accept(_ box: DetBox?, chamber i: Int) {
            guard i < layout.count, let b = box, b.confidence >= stored.keyFrame.minConfidence,
                  b.width >= 4, b.height >= 6,
                  b.width < 0.84 * layout.spacing,
                  layout.chamberIndex(x: b.cx) == i else { return }
            groups[i].append(b)
        }
        // Near the start is preferable because mice may move or be taken down later.
        for (k, t) in scanTimes.enumerated() where t >= start - 1 && t <= start + 25 && k < scanDetections.count {
            for i in 0..<min(layout.count, scanDetections[k].count) { accept(scanDetections[k][i], chamber: i) }
        }
        let keyBoxes = BoxOps.assign(keyFrameBoxes, to: layout, minConfidence: stored.keyFrame.minConfidence)
        for i in 0..<layout.count where groups[i].count < 3 { accept(keyBoxes[i], chamber: i) }
        // If a manual key frame bypassed scanning, reuse the video sample detections.
        if groups.contains(where: { $0.isEmpty }) {
            for (k, boxes) in sampleDetections.enumerated() {
                guard k < sampleTimes.count, sampleTimes[k] >= start - 2 else { continue }
                let assigned = BoxOps.assign(boxes, to: layout, minConfidence: stored.keyFrame.minConfidence)
                for i in 0..<layout.count where groups[i].isEmpty { accept(assigned[i], chamber: i) }
            }
        }
        func med(_ vals: [Double]) -> Double { let a = vals.sorted(); return a[a.count / 2] }
        return groups.map { boxes in
            guard !boxes.isEmpty else { return nil }
            let x0 = med(boxes.map(\.x0)), x1 = med(boxes.map(\.x1))
            let y0 = med(boxes.map(\.y0)), y1 = med(boxes.map(\.y1))
            guard x1 > x0, y1 > y0 else { return nil }
            return DetBox(x0: x0, y0: y0, x1: x1, y1: y1, confidence: 1)
        }
    }

    // MARK: - 5. Analysis

    func startAnalysis() {
        guard let info, let layout, layout.enabled.contains(true) else { return }
        work?.cancel()
        let window = analysisWindow
        guard window.duration >= 5 else {
            errorMessage = L("The analysis window is shorter than 5 s. Move the start (key frame) earlier, or check that the video is long enough.",
                             "分析时间窗短于 5 秒。请把起点（关键帧）往前调，或确认视频长度足够。")
            return
        }
        errorMessage = nil
        let referenceBoxes = segmentationReferences(for: layout, start: keyTime)
        let onsets = perMouseOnsets?.map { max(0, $0 - window.start) }
        // Threshold / body-size samples from the key frame on (all mice hanging).
        let sampleStart = min(max(window.start, keyTime), window.start + window.duration - 1)
        let boxes = motionBoxes()
        // Threshold / body-size samples only where every mouse is still hanging.
        let sampleEnd = max(sampleStart + 1, min(window.start + window.duration,
                                                 mouseMissingFrom.flatMap { $0 > sampleStart + 10 ? $0 : nil } ?? .infinity))
        var eff = settings
        eff.startSec = window.start
        eff.durationSec = window.duration
        eff.lastWindowSec = min(settings.lastWindowSec, settings.standardTestSec)
        eff.chamberOnsetSec = onsets
        phase = .analyzing
        progress = 0
        progressText = L("Calibrating mouse-specific masks…", "正在为每只小鼠校准分割阈值…")
        livePreview = nil
        analysisElapsed = 0
        analysisRemaining = nil
        analysisSpeed = nil
        let previewSwitch = self.previewSwitch
        work = Task.detached(priority: .userInitiated) {
            do {
                let reader = TSTVideoFrameReader(info: info, processingWidth: eff.processingWidth)
                // segmentation thresholds from frames INSIDE the window (before the key frame chambers are empty)
                let n = 20
                let ts = (0..<n).map { sampleStart + (sampleEnd - sampleStart) * (Double($0) + 0.5) / Double(n) }
                let thrSamples = try await reader.sampleFrames(at: ts)
                let step = max(1, Int((info.fps / eff.targetFPS).rounded()))
                let fps = info.fps / Double(step)
                let analyzer = MotionAnalyzer(layout: layout, settings: eff, sampleFrames: thrSamples,
                                              referenceBoxes: referenceBoxes, motionBoxes: boxes)
                analyzer.setFrameRate(fps)
                let total = max(1, Int(eff.durationSec * fps))
                var count = 0
                var lastUI = Date.distantPast
                let t0 = Date()
                try await reader.readSequential(start: eff.startSec, end: eff.startSec + eff.durationSec, step: step) { frame, t in
                    let masks = analyzer.process(frame, time: t)
                    count += 1
                    if Date().timeIntervalSince(lastUI) > 0.3 {
                        lastUI = Date()
                        let p = min(1, Double(count) / Double(total))
                        let elapsed = Date().timeIntervalSince(t0)
                        let eta: Double? = p > 0.02 ? elapsed / p - elapsed : nil
                        let speed: Double? = elapsed > 1 ? t / elapsed : nil
                        let img = previewSwitch.isOn
                            ? TSTImageRendering.overlay(frame: frame, rois: analyzer.rois, masks: masks,
                                                        boxes: analyzer.motionRectsInImage)
                            : nil
                        let text = String(format: L("%.0f / %.0f s of video analysed", "已分析视频 %.0f / %.0f 秒"), t, eff.durationSec)
                        Task { @MainActor in
                            guard self.phase == .analyzing else { return }
                            self.progress = p; self.progressText = text
                            if let img { self.livePreview = img }
                            self.analysisElapsed = elapsed
                            self.analysisRemaining = eta
                            self.analysisSpeed = speed
                        }
                    }
                }
                if count == 0 { throw TSTVideoError.noFrames }
                let result = analyzer.finish(fps: fps)
                let measures = analyzer.measures
                await MainActor.run {
                    self.result = result
                    self.measures = measures
                    self.progress = 1
                    self.phase = .results
                }
            } catch is CancellationError {
                await MainActor.run { self.phase = .keyframe }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.phase = .keyframe
                }
            }
        }
    }

    func cancelAnalysis() {
        work?.cancel()
        phase = .keyframe
    }

    /// Re-classify after the threshold / bout length / metric changed (no video decoding needed).
    func rescore() {
        guard let r = result else { return }
        // Keep everything that was applied while processing the video (window, outline, alignment …);
        // only the scoring choices come from the current settings.
        var s = r.settings
        s.metric = settings.metric
        s.immobilityThreshold = settings.immobilityThreshold
        s.minBoutSec = settings.minBoutSec
        s.smoothSec = settings.smoothSec
        s.testLengthSec = settings.testLengthSec
        s.lastWindowSec = min(settings.lastWindowSec, s.standardTestSec)
        result = Scorer.score(measures: measures, layout: r.layout, settings: s, fps: r.fps)
    }

    // MARK: - Calibration against manual scoring

    struct CalibrationPoint: Identifiable { let id = UUID(); let threshold: Double; let mae: Double; let r: Double }

    func calibrationSweep(manual: [Double?]) -> [CalibrationPoint] {
        guard let base = result else { return [] }
        var pts: [CalibrationPoint] = []
        for th in stride(from: 0.25, through: 15.0, by: 0.25) {
            // Same analysis inputs as the result (window, per-mouse onsets …); only the threshold varies.
            var s = base.settings
            s.metric = settings.metric
            s.minBoutSec = settings.minBoutSec
            s.smoothSec = settings.smoothSec
            s.immobilityThreshold = th
            let r = Scorer.score(measures: measures, layout: base.layout, settings: s, fps: base.fps)
            var a: [Double] = [], m: [Double] = []
            for (i, v) in manual.enumerated() where i < r.summaries.count {
                // Hand scores are compared with the primary window (minutes 2–6 of each mouse's test).
                if let v, r.summaries[i].analysed {
                    a.append(r.summaries[i].primaryImmobileSec ?? r.summaries[i].immobileLastWindowSec)
                    m.append(v)
                }
            }
            guard !a.isEmpty else { return [] }
            let mae = zip(a, m).map { abs($0 - $1) }.reduce(0, +) / Double(a.count)
            pts.append(CalibrationPoint(threshold: th, mae: mae, r: pearson(a, m)))
        }
        return pts
    }

    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        guard n > 1 else { return .nan }
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var sab = 0.0, saa = 0.0, sbb = 0.0
        for (x, y) in zip(a, b) { sab += (x - ma) * (y - mb); saa += (x - ma) * (x - ma); sbb += (y - mb) * (y - mb) }
        return saa > 0 && sbb > 0 ? sab / (saa * sbb).squareRoot() : .nan
    }

    // MARK: - Export

    func exportFiles() -> [URL] {
        guard let r = result else { return [] }
        let base = (videoName as NSString).deletingPathExtension
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [(String, String)] = [
            ("\(base)_summary.csv", CSVExport.summary(r, videoName: videoName)),
            ("\(base)_framewise.csv", CSVExport.framewise(r)),
            ("\(base)_settings.json", CSVExport.settingsJSON(r)),
        ]
        if let k = keyResult {
            files.append(("\(base)_keyframe.csv",
                          CSVExport.keyFrame(k, keyTime: keyTime, analysisStart: r.settings.startSec,
                                             analysisDuration: r.settings.durationSec, detector: detectorName)))
        }
        return files.compactMap { name, text in
            let url = dir.appendingPathComponent(name)
            do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
        }
    }
}
