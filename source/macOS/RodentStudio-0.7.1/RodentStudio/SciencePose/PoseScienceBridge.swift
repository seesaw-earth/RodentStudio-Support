import Foundation

/// Converts existing RodentPose tracking results to the original iOS scientific report types.
/// This never runs inference; it only uses the six-keypoint MousePose6 output and per-assay setup.
enum PoseScienceBridge {
    /// Largest number of frames analysed in one report (2 h at 30 fps). A desktop engineering limit;
    /// RodentPose iOS has none.
    static let maxFrames = 216_000

    enum Failure: LocalizedError {
        case wrongModel, missingSetup, unsupportedMultiAnimal, emptyRange, tooManyFrames
        var errorDescription: String? {
            switch self {
            case .wrongModel: return L("RodentPose requires MousePose6, not the RodentLimb model.", "RodentPose 需要 MousePose6 模型，而不是 RodentLimb 模型。")
            case .missingSetup: return L("Calibrate this video first: the RodentPose report needs the arena, zones and analysis parameters.",
                                         "请先标定该视频：RodentPose 报告需要场地、区域和分析参数。")
            case .unsupportedMultiAnimal: return L("This recording has only one saved animal; dyadic two-animal scoring is unavailable.",
                                                   "该视频只保存了一只动物；无法进行双鼠评分。")
            case .emptyRange: return L("The analysis window has no recorded poses.", "分析时间段内没有姿态记录。")
            case .tooManyFrames: return L("The analysis window has more than 216,000 frames. Set a shorter analysis window in Calibrate.",
                                          "分析时间段超过 216,000 帧。请在“校准”中设置更短的分析时间段。")
            }
        }
    }

    /// RodentPose report exactly as the app computes it: the whole track is analysed and the analysis
    /// window saved in Calibrate (CommonParams windowStart / windowLength) selects the frames measured.
    static func report(_ tracked: NativeTrackingResult, setup: PoseTaskSetup?, phase: String) throws -> AnalysisReport {
        guard tracked.model == .mousePose else { throw Failure.wrongModel }
        guard let setup else { throw Failure.missingSetup }
        if setup.paradigm == .dyadicSocial { throw Failure.unsupportedMultiAnimal }
        guard !tracked.frames.isEmpty else { throw Failure.emptyRange }
        guard tracked.frames.count <= maxFrames else { throw Failure.tooManyFrames }
        let session = makeSession(tracked, setup: setup, phase: phase, lastTime: tracked.frames.last?.time ?? 0)
        var report = Analyzer.run(session: session, track: makeTrack(tracked.frames, tracked))
        let w = setup.params
        let window = w.windowLength > 0
            ? String(format: "%.2f–%.2f s", w.windowStart, w.windowStart + w.windowLength)
            : String(format: "from %.2f s to the end", w.windowStart)
        report.methods.append(" \(AppInfo.name): original RodentPose 1.0 analyzers on the saved MousePose6 tracking; analysis window \(window) as set in Calibrate. Parity with RodentPose iOS has not been validated.")
        return report
    }

    /// Advanced tool: report over an explicit frame window that replaces the window saved in Calibrate.
    static func report(_ tracked: NativeTrackingResult, setup: PoseTaskSetup?,
                       phase: String, frames range: ClosedRange<Int>) throws -> AnalysisReport {
        guard tracked.model == .mousePose else { throw Failure.wrongModel }
        guard let setup else { throw Failure.missingSetup }
        if setup.paradigm == .dyadicSocial { throw Failure.unsupportedMultiAnimal }
        let source = tracked.frames.filter { range.contains($0.index) }
        guard !source.isEmpty else { throw Failure.emptyRange }
        guard source.count <= maxFrames else { throw Failure.tooManyFrames }
        var session = makeSession(tracked, setup: setup, phase: phase, lastTime: tracked.frames.last?.time ?? 0)
        let firstTime = source.first?.time ?? 0
        let lastTime = source.last?.time ?? firstTime
        session.params.windowStart = firstTime
        session.params.windowLength = max(0.001, lastTime - firstTime + 1 / max(1, tracked.fps))
        var report = Analyzer.run(session: session, track: makeTrack(source, tracked))
        report.methods.append(" \(AppInfo.name) (Advanced): custom frame window \(range.lowerBound)–\(range.upperBound) replaced the analysis window saved in Calibrate. Parity with RodentPose iOS has not been validated.")
        return report
    }

    private static func makeTrack(_ source: [NativeTrackedFrame], _ tracked: NativeTrackingResult) -> RPPoseTrack {
        var track = RPPoseTrack(animalCount: 1, fps: tracked.fps,
                                frameWidth: Double(tracked.videoWidth),
                                frameHeight: Double(tracked.videoHeight), frameStride: 1)
        track.frameIndex.reserveCapacity(source.count)
        track.time.reserveCapacity(source.count)
        track.detConf.reserveCapacity(source.count)
        track.kp.reserveCapacity(source.count * 18)
        for f in source {
            var p = AnimalPose.missing
            if !f.inferenceFailed && f.score > 0 && f.points.count == 6 {
                p.conf = Float(f.score)
                for k in 0..<6 {
                    let point = f.points[k]
                    if point.x.isFinite && point.y.isFinite && point.x >= 0 && point.y >= 0 {
                        p.x[k] = Float(point.x)
                        p.y[k] = Float(point.y)
                        p.kconf[k] = Float(point.confidence)
                    }
                }
            }
            track.append(frame: f.index, time: f.time, animals: [p])
        }
        track.complete = true
        track.processedUntil = source.last?.time ?? 0
        return track
    }

    private static func makeSession(_ tracked: NativeTrackingResult, setup: PoseTaskSetup, phase: String, lastTime: Double) -> Session {
        var session = Session(paradigm: setup.paradigm)
        session.phase = phase
        session.calibration = setup.calibration
        session.params = setup.params
        session.video.fps = tracked.fps
        session.video.width = Double(tracked.videoWidth)
        session.video.height = Double(tracked.videoHeight)
        session.video.duration = lastTime
        session.inference.stride = 1
        session.inference.animalCount = 1
        return session
    }
}
