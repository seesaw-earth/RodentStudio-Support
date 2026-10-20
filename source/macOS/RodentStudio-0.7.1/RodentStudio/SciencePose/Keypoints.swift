// RodentPose iOS 1.0 scientific algorithm port; only PoseTrack name and localization/zone invocation adapted.
// Keypoints.swift — the six keypoints predicted by MousePose6_960_int8 and the skeleton.

import Foundation

let kModelName = "MousePose6_960_int8"
let kKeypointNames = ["nose", "left_ear", "right_ear", "neck", "body_center", "tail_base"]
let kKeypointCount = 6
let kBones: [(Int, Int)] = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 4), (4, 5)]

enum KP: Int, CaseIterable, Identifiable {
    case nose = 0, leftEar, rightEar, neck, bodyCenter, tailBase

    var id: Int { rawValue }
    var key: String { kKeypointNames[rawValue] }

    var title: String {
        switch self {
        case .nose: return RPTexts.tr("鼻尖")
        case .leftEar: return RPTexts.tr("左耳")
        case .rightEar: return RPTexts.tr("右耳")
        case .neck: return RPTexts.tr("颈部")
        case .bodyCenter: return RPTexts.tr("身体中心")
        case .tailBase: return RPTexts.tr("尾根")
        }
    }

    /// Short label drawn next to keypoints in the legend.
    var short: String {
        switch self {
        case .nose: return "N"
        case .leftEar: return "LE"
        case .rightEar: return "RE"
        case .neck: return "Nk"
        case .bodyCenter: return "B"
        case .tailBase: return "T"
        }
    }
}
