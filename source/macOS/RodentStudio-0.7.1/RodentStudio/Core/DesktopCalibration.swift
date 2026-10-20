import Foundation

/// UI calibration observations in *normalized displayed-video coordinates*. This is NOT a
/// substitute for each iOS assay's zone-mapping / scoring algorithms. Keep original assay ID.
struct DesktopPoint: Codable, Hashable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

enum DesktopArenaShape: String, CaseIterable, Codable, Identifiable {
    case rectangle, circle, plusMaze, yMaze, tMaze, floorLine, ruler, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .rectangle: L("Rectangle / corners", "矩形 / 四角")
        case .circle: L("Circle / rim", "圆形 / 边缘")
        case .plusMaze: L("Plus maze", "十字迷宫")
        case .yMaze: L("Y maze", "Y 迷宫")
        case .tMaze: L("T maze", "T 迷宫")
        case .floorLine: L("Floor line", "地面线")
        case .ruler: L("Ruler / distance", "标尺 / 距离")
        case .none: L("No calibration", "不标定")
        }
    }
}

struct DesktopVisualParameters: Codable, Hashable {
    var centerFraction: Double = 0.50
    var lightFraction: Double = 0.50
    var lightOnLeft: Bool = true
    var cppDivider: Double = 0.50
    var plusOpenAxis: String = "NS"
    var novelObject: String = "B"
    var zoneRadiusCM: Double = 8
    var analysisStartSeconds: Double = 0
    var analysisDurationSeconds: Double = 0
}

/// Per-video setup. `pose`, `flow` and `limb` hold the setup of the task's original app
/// (see TaskSetup.swift); the generic fields below are a normalized summary used by exports.
struct DesktopCalibration: Codable, Equatable {
    var shape: DesktopArenaShape
    var handles: [String: DesktopPoint]
    var widthCM: Double = 40
    var heightCM: Double = 40
    var referenceCM: Double = 10
    var timeSeconds: Double = 0
    var overlayVisible: Bool = true
    var visualParameters: DesktopVisualParameters = DesktopVisualParameters()
    // Optional so that workspaces saved by 0.3.x still decode.
    var pose: PoseTaskSetup?
    var flow: FlowTaskSetup?
    var limb: LimbTaskSetup?
    /// Animal / video the setup was copied from ("use for all videos of this task").
    var copiedFrom: String?

    static func allowedShapes(for assay: StudyAssay) -> [DesktopArenaShape] {
        switch assay {
        case .cylinder: return [.circle, .floorLine]
        case .tailSuspension: return [.none]
        case .gait: return [.ruler]
        case .elevatedPlusMaze, .flowElevatedPlusMaze: return [.plusMaze]
        case .poseYMaze, .flowYMaze: return [.yMaze]
        case .poseTMazeVte, .flowTMaze: return [.tMaze]
        case .poseBarnesMaze, .flowBarnesMaze, .flowMorrisWaterMaze: return [.circle]
        case .openField, .flowOpenField, .novelObject, .flowNovelObjectRecognition: return [.rectangle, .circle]
        case .poseOnly, .poseRotation, .poseDyadicSocial, .poseHeadDirection: return [.none, .rectangle]
        default: return [.rectangle]
        }
    }

    static func make(for assay: StudyAssay, shape override: DesktopArenaShape? = nil) -> DesktopCalibration {
        let shape = override ?? allowedShapes(for: assay).first ?? .rectangle
        var handles: [String: DesktopPoint]
        switch shape {
        case .rectangle:
            handles = ["1": .init(0.12,0.12), "2": .init(0.88,0.12),
                       "3": .init(0.88,0.88), "4": .init(0.12,0.88)]
        case .circle:
            handles = ["C": .init(0.5,0.5), "R": .init(0.84,0.5)]
        case .plusMaze:
            handles = ["C": .init(0.5,0.5), "N": .init(0.5,0.10),
                       "E": .init(0.9,0.5), "S": .init(0.5,0.9), "W": .init(0.10,0.5)]
        case .yMaze:
            handles = ["J": .init(0.5,0.5), "A": .init(0.5,0.09),
                       "B": .init(0.12,0.84), "C": .init(0.88,0.84)]
        case .tMaze:
            handles = ["J": .init(0.5,0.4), "S": .init(0.5,0.9),
                       "L": .init(0.1,0.4), "R": .init(0.9,0.4)]
        case .floorLine:
            handles = ["F": .init(0.5,0.8)]
        case .ruler:
            handles = ["A": .init(0.3,0.83), "B": .init(0.7,0.83)]
        case .none:
            handles = [:]
        }
        if shape == .rectangle {
            if assay == .threeChamber {
                handles["L"] = .init(0.36,0.5)
                handles["R"] = .init(0.64,0.5)
                handles["cupA"] = .init(0.18,0.5)
                handles["cupB"] = .init(0.82,0.5)
            } else if assay == .novelObject || assay == .flowNovelObjectRecognition {
                let isFlow = assay == .flowNovelObjectRecognition
                handles[isFlow ? "A" : "objectA"] = .init(0.33,0.5)
                handles[isFlow ? "B" : "objectB"] = .init(0.67,0.5)
            } else if assay == .poseLoomingEscape {
                handles["shelter"] = .init(0.5,0.85)
            }
        }
        if shape == .circle {
            if assay == .flowMorrisWaterMaze { handles["P"] = .init(0.65, 0.34) }
            if assay == .flowBarnesMaze { handles["T"] = .init(0.70, 0.36) }
        }
        return DesktopCalibration(shape: shape, handles: handles)
    }
}
