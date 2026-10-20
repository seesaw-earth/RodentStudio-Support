// PoseTypes.swift — keypoint definition of CylinderMousePoseV2 and the stored pose track.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Output order of CylinderMousePoseV2 (matches cylinder_DLC/config.yaml exactly).
enum Kp: Int, CaseIterable, Codable, Identifiable {
    case lf = 0      // left fore paw
    case lh = 1      // left hind paw
    case rf = 2      // right fore paw
    case rh = 3      // right hind paw
    case tail = 4    // tail base
    case nose = 5
    case mouth = 6

    var id: Int { rawValue }

    /// Column name used in exports (English, matches the DLC config).
    var exportName: String {
        switch self {
        case .lf: return "L_fore_paw"
        case .lh: return "L_hind_paw"
        case .rf: return "R_fore_paw"
        case .rh: return "R_hind_paw"
        case .tail: return "tail_base"
        case .nose: return "nose"
        case .mouth: return "mouth"
        }
    }

    var label: LText {
        switch self {
        case .lf: return LText("Left forepaw", "左前爪")
        case .lh: return LText("Left hind paw", "左后爪")
        case .rf: return LText("Right forepaw", "右前爪")
        case .rh: return LText("Right hind paw", "右后爪")
        case .tail: return LText("Tail base", "尾根")
        case .nose: return LText("Nose", "鼻尖")
        case .mouth: return LText("Mouth", "嘴")
        }
    }

    /// Short code used in gait tables and exports.
    var code: String {
        switch self {
        case .lf: return "LF"
        case .lh: return "LH"
        case .rf: return "RF"
        case .rh: return "RH"
        case .tail: return "TB"
        case .nose: return "N"
        case .mouth: return "M"
        }
    }

    static let paws: [Kp] = [.lf, .rf, .lh, .rh]

    /// Left/right counterpart (used when the user swaps L/R labels).
    var mirrored: Kp {
        switch self {
        case .lf: return .rf
        case .rf: return .lf
        case .lh: return .rh
        case .rh: return .lh
        default: return self
        }
    }

    /// Skeleton used for overlays: limb girdles, ipsilateral limbs to the tail base, nose–mouth.
    static let bones: [(Kp, Kp)] = [(.lf, .rf), (.lh, .rh), (.nose, .mouth), (.lf, .lh), (.rf, .rh), (.lh, .tail), (.rh, .tail)]
}

/// Whole-video pose result, stored once per session (binary plist) and re-analyzed as often as
/// needed. Coordinates are in the *displayed* (orientation-corrected) video frame, top-left
/// origin, pixels. A missing keypoint has x = y = -1 and confidence 0.
struct PoseTrack: Codable {
    var width: Int
    var height: Int
    var fps: Double
    var duration: Double
    var modelName: String
    var modelVersion: String
    var times: [Double]
    var boxConfidence: [Float]
    var x: [[Float]]   // [keypoint][frame]
    var y: [[Float]]
    var c: [[Float]]
    /// Presentation time of the first frame in the video's own timeline. `times` start at 0;
    /// AVPlayer reports the video timeline, so player time − timeOffset = track time.
    /// Missing in tracks made by 1.0–1.1 (filled in on open).
    var timeOffset: Double?

    var frameCount: Int { times.count }

    /// Frame on screen at a given *player* time.
    func frameIndex(atPlayerTime t: Double) -> Int? {
        frameIndex(at: t - (timeOffset ?? 0))
    }

    init(width: Int, height: Int, fps: Double, duration: Double, modelName: String, modelVersion: String) {
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration
        self.modelName = modelName
        self.modelVersion = modelVersion
        times = []
        boxConfidence = []
        x = Array(repeating: [], count: Kp.allCases.count)
        y = Array(repeating: [], count: Kp.allCases.count)
        c = Array(repeating: [], count: Kp.allCases.count)
    }

    mutating func reserve(_ n: Int) {
        times.reserveCapacity(n)
        boxConfidence.reserveCapacity(n)
        for k in 0..<x.count {
            x[k].reserveCapacity(n); y[k].reserveCapacity(n); c[k].reserveCapacity(n)
        }
    }

    /// Index of the frame shown at time `t` (last frame whose timestamp ≤ t).
    func frameIndex(at t0: Double) -> Int? {
        guard !times.isEmpty else { return nil }
        let t = t0 + 0.001   // tolerate rounding so an exact frame time selects that frame
        var lo = 0, hi = times.count - 1
        if t <= times[0] { return 0 }
        if t >= times[hi] { return hi }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if times[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func point(_ k: Kp, _ i: Int, threshold: Double) -> CGPoint? {
        guard i >= 0, i < times.count else { return nil }
        let conf = Double(c[k.rawValue][i])
        let px = x[k.rawValue][i], py = y[k.rawValue][i]
        guard conf >= threshold, px >= 0, py >= 0 else { return nil }
        return CGPoint(x: Double(px), y: Double(py))
    }

    var detectedFraction: Double {
        guard !boxConfidence.isEmpty else { return 0 }
        return Double(boxConfidence.filter { $0 > 0 }.count) / Double(boxConfidence.count)
    }
}

struct InferenceSettings: Codable, Equatable {
    var boxThreshold: Double = 0.25
    var renderSkeletonVideo: Bool = false
}
