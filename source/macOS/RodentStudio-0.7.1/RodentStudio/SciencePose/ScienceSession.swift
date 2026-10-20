import Foundation

struct RPInferenceSettings: Codable, Equatable {
    var stride: Int = 1
    var grayscale = true
    var animalCount = 1
    var startTime: Double = 0
    /// 0 = until the end of the video.
    var endTime: Double = 0

    init() {}

    enum CodingKeys: String, CodingKey { case stride, grayscale, animalCount, startTime, endTime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stride = max(1, c.v(.stride, 1))
        grayscale = c.v(.grayscale, true)
        animalCount = min(2, max(1, c.v(.animalCount, 1)))
        startTime = c.v(.startTime, 0)
        endTime = c.v(.endTime, 0)
    }
}


// MARK: - Video and pose summaries

struct VideoMeta: Codable, Equatable {
    var duration: Double = 0
    var fps: Double = 30
    /// Upright (display-oriented) frame size in pixels.
    var width: Double = 1920
    var height: Double = 1080
    var creationDate: Date?
    var fileSize: Int64 = 0

    var frameSize: V2 { V2(width, height) }
    var estimatedFrames: Int { Int((duration * max(fps, 1)).rounded()) }

    init() {}

    enum CodingKeys: String, CodingKey { case duration, fps, width, height, creationDate, fileSize }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = c.v(.duration, 0)
        fps = c.v(.fps, 30)
        width = c.v(.width, 1920)
        height = c.v(.height, 1080)
        creationDate = c.v(.creationDate, nil as Date?)
        fileSize = c.v(.fileSize, 0)
    }
}

struct PoseSummary: Codable, Equatable {
    var frames = 0
    var detectedFrames = 0
    var meanConfidence: Double = 0
    var msPerFrame: Double = 0
    var processedUntil: Double = 0
    var complete = false
    var animalCount = 1

    var detectionRate: Double { frames > 0 ? Double(detectedFrames) / Double(frames) : 0 }

    init() {}

    enum CodingKeys: String, CodingKey { case frames, detectedFrames, meanConfidence, msPerFrame, processedUntil, complete, animalCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frames = c.v(.frames, 0)
        detectedFrames = c.v(.detectedFrames, 0)
        meanConfidence = c.v(.meanConfidence, 0)
        msPerFrame = c.v(.msPerFrame, 0)
        processedUntil = c.v(.processedUntil, 0)
        complete = c.v(.complete, false)
        animalCount = c.v(.animalCount, 1)
    }
}

enum SessionStatus: String, Codable {
    case draft, processing, paused, done, failed

    var title: String {
        switch self {
        case .draft: return RPTexts.tr("待识别")
        case .processing: return RPTexts.tr("识别中")
        case .paused: return RPTexts.tr("已暂停")
        case .done: return RPTexts.tr("已完成")
        case .failed: return RPTexts.tr("失败")
        }
    }

    var symbol: String {
        switch self {
        case .draft: return "circle.dashed"
        case .processing: return "hourglass"
        case .paused: return "pause.circle"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Session

struct Session: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var updatedAt = Date()
    var paradigm: Paradigm = .openField
    var subjectID = ""
    var group = ""
    var sex = ""          // "", "M", "F"
    var phase = ""        // stored English key (see Paradigm.phases)
    var day: Int?
    var trial: Int?
    var notes = ""
    var videoName = ""
    /// File name of the video inside the session folder; nil when the copy was deleted.
    var videoFile: String?
    var video = VideoMeta()
    var calibration = ArenaCalibration()
    var calibrationTime: Double = 0
    var params = AnalysisParams()
    var inference = RPInferenceSettings()
    /// Inference settings of the stored pose data (nil before the first run).
    var usedInference: RPInferenceSettings?
    var status: SessionStatus = .draft
    var pose: PoseSummary?
    /// Cached headline metrics for lists and summary exports.
    var metrics: [String: Double] = [:]
    var metricOrder: [String] = []
    var metricLabels: [String: String] = [:]
    /// Headline metric as shown in lists, e.g. "0.42" / "35.2 %".
    var primaryTitle = ""
    var primaryDisplay = ""

    init() {}

    init(paradigm: Paradigm) {
        self.paradigm = paradigm
        self.params = AnalysisParams.defaults(for: paradigm)
        self.phase = paradigm.phases.first?.key ?? ""
        self.inference.animalCount = paradigm.animalCount
        self.calibration.kind = paradigm.defaultArena
    }

    var displaySubject: String { subjectID.isEmpty ? RPTexts.tr("未命名") : subjectID }
    var phaseTitle: String { paradigm.phaseTitle(phase) }

    /// "D2 · T3"-style label for day and trial.
    var sessionLabel: String {
        var parts: [String] = []
        if !phase.isEmpty { parts.append(phaseTitle) }
        if let day { parts.append("D\(day)") }
        if let trial { parts.append("T\(trial)") }
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, paradigm, subjectID, group, sex, phase, day, trial, notes
        case videoName, videoFile, video, calibration, calibrationTime, params, inference, usedInference, status, pose
        case metrics, metricOrder, metricLabels, primaryTitle, primaryDisplay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.v(.id, UUID())
        createdAt = c.v(.createdAt, Date())
        updatedAt = c.v(.updatedAt, createdAt)
        paradigm = c.v(.paradigm, .poseOnly)
        subjectID = c.v(.subjectID, "")
        group = c.v(.group, "")
        sex = c.v(.sex, "")
        phase = c.v(.phase, "")
        day = c.v(.day, nil as Int?)
        trial = c.v(.trial, nil as Int?)
        notes = c.v(.notes, "")
        videoName = c.v(.videoName, "")
        videoFile = c.v(.videoFile, nil as String?)
        video = c.v(.video, VideoMeta())
        calibration = c.v(.calibration, ArenaCalibration())
        calibrationTime = c.v(.calibrationTime, 0)
        params = c.v(.params, AnalysisParams.defaults(for: paradigm))
        inference = c.v(.inference, RPInferenceSettings())
        usedInference = c.v(.usedInference, nil as RPInferenceSettings?)
        status = c.v(.status, .draft)
        pose = c.v(.pose, nil as PoseSummary?)
        metrics = c.v(.metrics, [:])
        metricOrder = c.v(.metricOrder, [])
        metricLabels = c.v(.metricLabels, [:])
        primaryTitle = c.v(.primaryTitle, "")
        primaryDisplay = c.v(.primaryDisplay, "")
    }
}

