import Foundation
import AVFoundation

/// Persisted 10 Hz classic-centroid tracking, using the original RodentFlow 1.3 analyzer.
/// Each checkpoint is committed atomically. The video and iOS algorithm are not modified.
struct FlowSavedRun: Codable {
    var sourceName: String
    var sourceSize: UInt64
    var sourceModified: Double
    var points: [FlowTrackingPoint]
    var events: [FlowMazeEvent]
    var completed: Bool
    var analysisHz: Double
    var arenaShape: FlowArenaShape
    var startedAt: Date
    var finishedAt: Date?
    /// Object A / B and target positions in arena cm, mapped by the tracker from the markers placed in
    /// Calibrate (RodentFlow FullAnalysisResult.markersCM). Missing in runs saved by 0.5.0.
    var markersCM: [String: FlowArenaPoint]?
    /// The setup the tracker used (0.5.1+). Missing in runs saved by 0.5.0.
    var trackingSetup: FlowTaskSetup?
    /// Calibration (with its object / target markers) that `markersCM` was mapped from.
    var markersCalibration: FlowArenaCalibration?
}

struct FlowRestartState: Codable {
    var nextTargetTime: Double
    var nextCheckpointIndex: Int
    var trackerState: FlowNativeMouseTracker.SessionState
    var sourceSize: UInt64
    var sourceModified: Double
    /// Setup of the paused run (0.5.1+); a resume with another arena geometry is refused.
    var setup: FlowTaskSetup?
}

enum FlowDesktopRun {
    static let filename = "flow_centroid_result.json"

    enum RunError: LocalizedError {
        case setupChanged
        var errorDescription: String? {
            switch self {
            case .setupChanged:
                return L("The arena calibration was changed after this run was paused, so it cannot be resumed. Use “Try again” to analyse the video from the start.",
                         "该分析暂停后场地标定被修改，无法继续。请点“重试”从头分析该视频。")
            }
        }
    }

    static func load(from folder: URL) throws -> FlowSavedRun {
        try JSONDecoder().decode(FlowSavedRun.self, from: Data(contentsOf: folder.appendingPathComponent(filename)))
    }

    static func save(_ record: FlowSavedRun, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: folder.appendingPathComponent(filename), options: .atomic)
    }

    static func run(videoURL: URL, folder: URL, setup: FlowTaskSetup,
                    progress: @escaping @Sendable (FlowAnalysisProgressSnapshot) -> Void) async throws -> FlowSavedRun {
        let started = Date()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let attrs = try FileManager.default.attributesOfItem(atPath: videoURL.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var chunks: [FlowTrackingPoint] = []
        let stateURL = folder.appendingPathComponent("flow_restart_state.json")
        var resume: FlowFullVideoAnalyzer.ResumeSnapshot? = nil
        if let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(FlowRestartState.self, from: data),
           state.sourceSize == size && state.sourceModified == modified {
            if let paused = state.setup, !paused.sameTrackingGeometry(as: setup) { throw RunError.setupChanged }
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let sorted = entries.filter { $0.lastPathComponent.hasPrefix("flow_chunk_") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in sorted {
                let pts = try JSONDecoder().decode([FlowTrackingPoint].self, from: Data(contentsOf: url))
                chunks.append(contentsOf: pts)
            }
            resume = FlowFullVideoAnalyzer.ResumeSnapshot(existingPoints: chunks, nextTargetTimeSeconds: state.nextTargetTime,
                                                          trackerState: state.trackerState, nextCheckpointIndex: state.nextCheckpointIndex)
        }
        let archive = folder
        let result = try await FlowFullVideoAnalyzer.analyze(videoURL: videoURL,
            arenaShape: setup.shape,
            arenaWidthCM: setup.dimensions.effectiveWidthCM(setup.shape),
            arenaHeightCM: setup.dimensions.effectiveHeightCM(setup.shape),
            calibration: setup.calibration,
            mazeArmWidthCM: setup.dimensions.mazeArmWidthCM,
            tStartArmLengthCM: setup.dimensions.tStartArmLengthCM,
            tChoiceArmLengthCM: setup.dimensions.tChoiceArmLengthCM,
            yArmLengthCM: setup.dimensions.yArmLengthCM,
            plusArmLengthCM: setup.dimensions.plusArmLengthCM,
            plusArmWidthCM: setup.dimensions.plusArmWidthCM,
            resume: resume,
            checkpointEverySamples: 300,
            checkpoint: { info in
                let encoder = JSONEncoder()
                let name = String(format: "flow_chunk_%06d.json", info.checkpointIndex)
                try encoder.encode(info.points).write(to: archive.appendingPathComponent(name), options: .atomic)
                let stamp = FlowRestartState(nextTargetTime: info.nextTargetTimeSeconds,
                                             nextCheckpointIndex: info.checkpointIndex + 1, trackerState: info.trackerState,
                                             sourceSize: size, sourceModified: modified, setup: setup)
                try encoder.encode(stamp).write(to: stateURL, options: .atomic)
            }, progress: progress)
        let record = FlowSavedRun(sourceName: videoURL.lastPathComponent, sourceSize: size, sourceModified: modified,
                                  points: result.points, events: result.mazeEvents, completed: true,
                                  analysisHz: result.processingFPS, arenaShape: setup.shape,
                                  startedAt: started, finishedAt: Date(),
                                  markersCM: result.markersCM, trackingSetup: setup,
                                  markersCalibration: setup.calibration)
        try save(record, to: folder)
        return record
    }

    /// Object / target positions in arena cm for the markers of `setup`, mapped exactly as the tracker maps
    /// them (FullVideoAnalyzer builds the same tracker and reads `arenaPoint(rawNormalized:)`). Used for
    /// runs saved without markers and after markers were moved in Calibrate. Reads the background frames
    /// and a fraction of a second of video; the saved tracking is not changed.
    static func markers(videoURL: URL, setup: FlowTaskSetup) async throws -> [String: FlowArenaPoint] {
        let output = try await FlowFullVideoAnalyzer.analyzeRange(videoURL: videoURL,
            startSeconds: 0,
            durationSeconds: 0.3,
            arenaShape: setup.shape,
            arenaWidthCM: setup.dimensions.effectiveWidthCM(setup.shape),
            arenaHeightCM: setup.dimensions.effectiveHeightCM(setup.shape),
            calibration: setup.calibration,
            mazeArmWidthCM: setup.dimensions.mazeArmWidthCM,
            tStartArmLengthCM: setup.dimensions.tStartArmLengthCM,
            tChoiceArmLengthCM: setup.dimensions.tChoiceArmLengthCM,
            yArmLengthCM: setup.dimensions.yArmLengthCM,
            plusArmLengthCM: setup.dimensions.plusArmLengthCM,
            plusArmWidthCM: setup.dimensions.plusArmWidthCM)
        return output.markersCM
    }
}

extension FlowTaskSetup {
    /// Whether two setups give the tracker the same arena geometry (shape, size and calibration points).
    /// Object / target markers are not part of it: they only place zones.
    func sameTrackingGeometry(as other: FlowTaskSetup) -> Bool {
        var a = calibration
        var b = other.calibration
        a.markerA = .markerA; a.markerB = .markerB; a.markerTarget = .markerTarget
        b.markerA = .markerA; b.markerB = .markerB; b.markerTarget = .markerTarget
        return shape == other.shape && dimensions == other.dimensions && a == b
    }

    func sameMarkers(as other: FlowTaskSetup) -> Bool {
        FlowTaskSetup.sameMarkers(calibration, other.calibration)
    }

    static func sameMarkers(_ a: FlowArenaCalibration, _ b: FlowArenaCalibration) -> Bool {
        a.markerA == b.markerA && a.markerB == b.markerB && a.markerTarget == b.markerTarget
    }

    /// Assays whose zones come from markers placed in Calibrate.
    var usesMarkers: Bool {
        switch assay {
        case .novelObject, .morrisWaterMaze, .barnesMaze: return true
        default: return false
        }
    }
}

/// Inputs of RodentFlow's AssayEngine built exactly as RodentFlow 1.3 builds them
/// (AppState.makeExperimentResult and ResultDetailView.TrackingVisuals).
enum FlowResultInputs {
    static func samples(_ run: FlowSavedRun) -> [FlowAnalysisSample] {
        run.points.map { p in
            FlowAnalysisSample(t: p.videoTimeSeconds, x: p.xCentimeters, y: p.yCentimeters,
                               detected: !p.interpolated, zone: p.zone,
                               motion: p.motionIndex, blobArea: p.blobAreaFraction)
        }
    }

    /// The analysis parameters saved in Calibrate, the arena size of the setup and, for NOR / MWM /
    /// Barnes, the calibrated object / target positions.
    static func config(setup: FlowTaskSetup, markers: [String: FlowArenaPoint]) -> FlowZoneConfig {
        var synced = setup
        synced.syncArenaSize()
        var config = synced.zone
        switch setup.assay {
        case .novelObject:
            if let a = markers["A"] { config.objectA = a }
            if let b = markers["B"] { config.objectB = b }
        case .morrisWaterMaze, .barnesMaze:
            if let t = markers["T"] { config.target = t }
        default:
            break
        }
        return config
    }

    /// Analysis window in seconds relative to the first sample, as the engine applies it
    /// (MWM / Barnes default to the trial maximum).
    static func window(assay: FlowAssay, config c: FlowZoneConfig) -> (start: Double, duration: Double?) {
        var duration = c.analysisDurationSeconds
        if duration <= 0, assay == .morrisWaterMaze || assay == .barnesMaze { duration = c.maxTrialSeconds }
        return (max(0, c.analysisStartSeconds), duration > 0 ? duration : nil)
    }

    /// Trajectory restricted to the analysis window, so the plot matches the numbers.
    static func windowed(_ s: [FlowAnalysisSample], assay: FlowAssay, config c: FlowZoneConfig) -> [FlowAnalysisSample] {
        guard let first = s.first?.t else { return s }
        let w = window(assay: assay, config: c)
        let start = first + w.start
        let end = w.duration.map { start + $0 } ?? Double.infinity
        return s.filter { $0.t >= start && $0.t < end }
    }
}
