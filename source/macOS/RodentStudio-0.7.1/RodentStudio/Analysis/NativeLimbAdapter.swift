import Foundation

// Reuses the ORIGINAL RodentLimb 1.1.2 scientific algorithms without a subprocess.
// Do not call this without a validated 7-keypoint PoseTrack.
enum NativeLimbAdapter {
    static func run(track: PoseTrack, assay: Assay, params: AssayParams,
                    calibration: Calibration, overrides: [Int: PawLabel] = [:]) -> AnalysisResult {
        let prepared = PoseSeries(track: track, params: params.common)
        switch assay {
        case .cylinder:
            return CylinderAnalyzer.run(prepared, params.cylinder,
                                        calibration: calibration, overrides: overrides)
        case .tailSuspension:
            return TSTAnalyzer.run(prepared, params.tst, duration: track.duration)
        case .gait:
            return GaitAnalyzer.run(prepared, params.gait, calibration: calibration)
        }
    }
}
