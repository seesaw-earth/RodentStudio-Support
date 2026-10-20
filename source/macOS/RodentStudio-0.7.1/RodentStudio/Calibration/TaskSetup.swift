// TaskSetup.swift — per-task setup that follows the original iOS app of each module.
//
// RodentPose tasks use RodentPose's ArenaCalibration + AnalysisParams (Paradigm-specific handles,
// markers, zones and parameters). RodentFlow tasks use RodentFlow's arena calibration, arena
// dimensions and ZoneConfig. RodentLimb tasks use RodentLimb's Calibration (cylinder rim, floor
// line or cm ruler) and AssayParams. Nothing is shared or re-interpreted across modules.

import Foundation
import CoreGraphics

enum TaskModule: String, Codable {
    case pose, flow, limb
}

struct PoseTaskSetup: Codable, Equatable {
    var paradigm: Paradigm
    var calibration: ArenaCalibration
    var params: AnalysisParams
    /// Upright frame size (pixels) the calibration was drawn on.
    var frameWidth: Double
    var frameHeight: Double
    var frameTime: Double = 0

    var frameSize: V2 { V2(max(frameWidth, 1), max(frameHeight, 1)) }
}

struct FlowTaskSetup: Codable, Equatable {
    var assay: FlowAssay
    var shape: FlowArenaShape
    var dimensions = FlowArenaDimensions()
    var calibration = FlowArenaCalibration()
    var zone: FlowZoneConfig
    var frameTime: Double = 0

    /// Keeps the analysis arena size in ZoneConfig equal to the size entered in Setup, as RodentFlow does.
    mutating func syncArenaSize() {
        zone.arenaShape = shape
        zone.arenaWidthCM = dimensions.effectiveWidthCM(shape)
        zone.arenaHeightCM = dimensions.effectiveHeightCM(shape)
        zone.plusArmLengthCM = dimensions.plusArmLengthCM
        zone.plusArmWidthCM = dimensions.plusArmWidthCM
    }
}

struct LimbTaskSetup: Codable, Equatable {
    var assay: Assay
    /// RodentLimb calibration in pixels of the upright frame (frameWidth × frameHeight).
    var calibration: Calibration
    var params: AssayParams
    var frameWidth: Double
    var frameHeight: Double
    var frameTime: Double = 0

    enum Mode { case circle, floor, ruler }

    /// Same rule as RodentLimb CalibrationView.mode.
    var mode: Mode {
        switch assay {
        case .gait, .tailSuspension: return .ruler
        case .cylinder: return params.cylinder.view == .bottom ? .circle : .floor
        }
    }

    /// Same rule as RodentLimb Session.isCalibrated.
    var isCalibrated: Bool {
        switch assay {
        case .tailSuspension, .gait: return true
        case .cylinder:
            return params.cylinder.view == .bottom ? calibration.circle != nil : calibration.floorY != nil
        }
    }

    /// Calibration rescaled to the pixel size of a tracking result.
    func scaledCalibration(width w: Int, height h: Int) -> Calibration {
        let sx = Double(max(w, 1)) / max(frameWidth, 1)
        let sy = Double(max(h, 1)) / max(frameHeight, 1)
        var c = calibration
        if let circle = c.circle {
            c.circle = CircleCal(cx: circle.cx * sx, cy: circle.cy * sy, r: circle.r * (sx + sy) / 2)
        }
        if let y = c.floorY { c.floorY = y * sy }
        if let s = c.scale {
            c.scale = ScaleCal(x1: s.x1 * sx, y1: s.y1 * sy, x2: s.x2 * sx, y2: s.y2 * sy, cm: s.cm)
        }
        return c
    }

    /// Defaults of RodentLimb CalibrationView.setup().
    static func defaultCircle(w: Double, h: Double) -> CircleCal { CircleCal(cx: w / 2, cy: h / 2, r: min(w, h) * 0.42) }
    static func defaultFloor(h: Double) -> Double { h * 0.85 }
    static func defaultRuler(w: Double, h: Double) -> ScaleCal { ScaleCal(x1: w * 0.3, y1: h * 0.85, x2: w * 0.7, y2: h * 0.85, cm: 10) }
}

// MARK: - Task identity

extension StudyAssay {
    var module: TaskModule? {
        if self == .tstMultiChamber { return nil } // Dedicated multi-animal task workflow; never route to single-animal tracking.
        if rawValue.hasPrefix("rodentpose.") { return .pose }
        if rawValue.hasPrefix("rodentlimb.") { return .limb }
        if rawValue.hasPrefix("rodentflow.") { return .flow }
        return nil
    }

    var paradigm: Paradigm? {
        switch self {
        case .threeChamber: return .threeChamber
        case .poseSocialInteraction: return .socialInteraction
        case .poseDyadicSocial: return .dyadicSocial
        case .poseHeadDirection: return .headDirection
        case .poseSpatialExploration: return .spatialExploration
        case .openField: return .openField
        case .elevatedPlusMaze: return .elevatedPlusMaze
        case .poseLightDarkBox: return .lightDark
        case .novelObject: return .novelObject
        case .poseBarnesMaze: return .barnesMaze
        case .poseYMaze: return .yMaze
        case .poseTMazeVte: return .tMaze
        case .poseFearConditioning: return .fearConditioning
        case .poseLoomingEscape: return .looming
        case .poseRotation: return .rotation
        case .poseOnly: return .poseOnly
        default: return nil
        }
    }

    var flowAssay: FlowAssay? {
        switch self {
        case .flowOpenField: return .openField
        case .flowElevatedPlusMaze: return .elevatedPlusMaze
        case .flowLightDarkBox: return .lightDark
        case .flowYMaze: return .yMaze
        case .flowTMaze: return .tMaze
        case .flowNovelObjectRecognition: return .novelObject
        case .flowMorrisWaterMaze: return .morrisWaterMaze
        case .flowBarnesMaze: return .barnesMaze
        case .flowFearConditioning: return .fearConditioning
        case .flowConditionedPlacePreference: return .placePreference
        default: return nil
        }
    }

    var limbAssay: Assay? {
        switch self {
        case .cylinder: return .cylinder
        case .tailSuspension: return .tailSuspension
        case .gait: return .gait
        default: return nil
        }
    }

    /// Interface name in the current language (exports keep `rawValue` and the English catalog name).
    var displayName: String {
        if self == .tstMultiChamber { return L("TST · Multi-Chamber", "悬尾实验 · 多格同步评分") }
        if let p = paradigm { return p.title }
        if let a = limbAssay { return a.name.text }
        if let f = flowAssay { return f.title }
        return name
    }

    var symbol: String {
        if self == .tstMultiChamber { return "figure.stand" }
        if let p = paradigm { return p.symbol }
        if let a = limbAssay { return a.symbol }
        if let f = flowAssay { return f.symbol }
        return "questionmark.square.dashed"
    }

    /// One-line description of how this task is measured, for the task picker.
    var methodCaption: String {
        if self == .tstMultiChamber { return L("Multi-chamber segmentation / silhouette motion", "多格分割／轮廓运动分析") }
        switch module {
        case .pose: return L("Pose · 6 keypoints", "姿态 · 6 个关键点")
        case .limb: return L("Limbs · 7 keypoints", "四肢 · 7 个关键点")
        case .flow: return L("Classic centroid tracking", "经典质心追踪")
        case .none: return ""
        }
    }

    /// Whether the desktop app can run tracking for this task today (RodentFlow's tracker is not ported).
    var canRunOnDesktop: Bool { self == .tstMultiChamber || modelRoute != nil || (module == .flow && isDesktopEligible) }

    // Phase / day / trial fields follow the original app of each module.
    var phaseOptions: [(key: String, title: String)] {
        if let p = paradigm { return p.phases.map { (key: $0.key, title: $0.title) } }
        if let f = flowAssay { return f.phases.map { (key: $0, title: FlowAssay.phaseTitle($0)) } }
        return []
    }

    /// RodentPose offers a free-text phase when the paradigm has no fixed phases; RodentFlow and RodentLimb do not.
    var allowsFreePhase: Bool { paradigm != nil && phaseOptions.isEmpty }
    var defaultPhase: String {
        if let p = paradigm { return p.phases.first?.key ?? "" }
        if let f = flowAssay { return f.defaultPhase }
        return ""
    }
    var usesDay: Bool { paradigm != nil || (flowAssay?.usesDays ?? false) }
    var usesTrial: Bool { paradigm != nil || (flowAssay?.usesTrials ?? false) }
    var usesSex: Bool { module == .pose || module == .flow || self == .tstMultiChamber }
    var usesNotes: Bool { module == .pose || module == .limb }

    func phaseTitle(_ key: String) -> String {
        if let p = paradigm { return p.phaseTitle(key) }
        if flowAssay != nil { return FlowAssay.phaseTitle(key) }
        return key
    }
}

extension FlowAssay {
    var title: String {
        switch self {
        case .openField: return L("Open Field", "旷场")
        case .elevatedPlusMaze: return L("Elevated Plus Maze", "高架十字迷宫")
        case .lightDark: return L("Light–Dark Box", "明暗箱")
        case .yMaze: return L("Y-Maze", "Y 迷宫")
        case .tMaze: return L("T-Maze", "T 迷宫")
        case .novelObject: return L("Novel Object Recognition", "新物体识别")
        case .morrisWaterMaze: return L("Morris Water Maze", "Morris 水迷宫")
        case .barnesMaze: return L("Barnes Maze", "Barnes 迷宫")
        case .fearConditioning: return L("Fear Conditioning", "恐惧条件化")
        case .placePreference: return L("Conditioned Place Preference", "条件性位置偏好")
        }
    }

    var symbol: String {
        switch self {
        case .openField: return "square.dashed"
        case .elevatedPlusMaze: return "plus"
        case .lightDark: return "lightbulb.min"
        case .yMaze, .tMaze: return "arrow.triangle.branch"
        case .novelObject: return "cube"
        case .morrisWaterMaze: return "drop"
        case .barnesMaze: return "circle.grid.cross"
        case .fearConditioning: return "bolt.heart"
        case .placePreference: return "rectangle.split.2x1"
        }
    }
}

// MARK: - Setup container

extension DesktopCalibration {
    /// A fresh setup for a task, using the defaults of the task's original app.
    static func task(for assay: StudyAssay, frameWidth: Double, frameHeight: Double) -> DesktopCalibration {
        let w = max(frameWidth, 1), h = max(frameHeight, 1)
        var out = DesktopCalibration(shape: .none, handles: [:])
        if let p = assay.paradigm {
            let cal = ArenaCalibration.makeDefault(paradigm: p, kind: p.defaultArena, frameSize: V2(w, h))
            out.pose = PoseTaskSetup(paradigm: p, calibration: cal, params: AnalysisParams.defaults(for: p),
                                     frameWidth: w, frameHeight: h)
        } else if let f = assay.flowAssay {
            let shape = f.videoArenaShapes.first ?? .rectangle
            let dims = FlowArenaDimensions()
            var setup = FlowTaskSetup(assay: f, shape: shape, dimensions: dims,
                                      zone: FlowZoneConfig.defaults(for: f, shape: shape,
                                                                    widthCM: dims.effectiveWidthCM(shape),
                                                                    heightCM: dims.effectiveHeightCM(shape)))
            setup.syncArenaSize()
            out.flow = setup
        } else if let a = assay.limbAssay {
            var cal = Calibration(circle: nil, floorY: nil, scale: nil, copiedFrom: nil)
            let params = AssayParams.defaults(for: a)
            if a == .cylinder {
                // The cylinder must be calibrated before analysis (RodentLimb "One step left: calibration").
                cal.circle = LimbTaskSetup.defaultCircle(w: w, h: h)
            }
            out.limb = LimbTaskSetup(assay: a, calibration: cal, params: params, frameWidth: w, frameHeight: h)
        }
        out.syncSummary()
        return out
    }

    /// Whether the saved setup belongs to this task (a video can be re-assigned to another task).
    func matches(_ assay: StudyAssay) -> Bool {
        if let p = assay.paradigm { return pose?.paradigm == p }
        if let f = assay.flowAssay { return flow?.assay == f }
        if let a = assay.limbAssay { return limb?.assay == a }
        return false
    }

    /// Fills the generic, export-facing fields (shape, normalized handles, sizes, analysis window)
    /// from the module-specific setup, so provenance files list exactly what was calibrated.
    mutating func syncSummary() {
        var h: [String: DesktopPoint] = [:]
        func put(_ k: String, _ x: Double, _ y: Double) { h[k] = DesktopPoint(x, y) }
        if let pose {
            let c = pose.calibration
            switch c.kind {
            case .none: shape = .none
            case .rectangle:
                shape = .rectangle
                for (i, p) in c.corners.enumerated() { put("\(i + 1)", p.x, p.y) }
                widthCM = c.widthCM
                heightCM = c.heightCM
            case .circle:
                shape = .circle
                put("C", c.circleCenter.x, c.circleCenter.y)
                put("R", c.circleEdge.x, c.circleEdge.y)
                widthCM = c.diameterCM
                heightCM = c.diameterCM
            case .plusMaze, .yMaze, .tMaze:
                shape = c.kind == .plusMaze ? .plusMaze : (c.kind == .yMaze ? .yMaze : .tMaze)
                for (i, p) in c.mazePoints.enumerated() where i < c.kind.mazeLabels.count { put(c.kind.mazeLabels[i], p.x, p.y) }
                widthCM = c.armLengthCM
                heightCM = c.armWidthCM
            }
            for (k, p) in c.markers { put("marker_" + k, p.x, p.y) }
            timeSeconds = pose.frameTime
            visualParameters.analysisStartSeconds = pose.params.windowStart
            visualParameters.analysisDurationSeconds = pose.params.windowLength
        } else if let flow {
            let c = flow.calibration
            switch flow.shape {
            case .rectangle:
                shape = .rectangle
                for (i, p) in c.corners.enumerated() { put("\(i + 1)", p.x, p.y) }
            case .circle:
                shape = .circle
                put("C", c.circleCenter.x, c.circleCenter.y)
                put("R", c.circleEdge.x, c.circleEdge.y)
            case .tMaze:
                shape = .tMaze
                for (l, p) in zip(["J", "S", "L", "R"], c.tPoints) { put(l, p.x, p.y) }
            case .yMaze:
                shape = .yMaze
                for (l, p) in zip(["J", "A", "B", "C"], c.yPoints) { put(l, p.x, p.y) }
            case .plusMaze:
                shape = .plusMaze
                for (l, p) in zip(["C", "N", "E", "S", "W"], c.plusPoints) { put(l, p.x, p.y) }
            }
            switch flow.assay {
            case .novelObject:
                put("marker_A", c.markerA.x, c.markerA.y)
                put("marker_B", c.markerB.x, c.markerB.y)
            case .morrisWaterMaze where flow.shape == .circle:
                put("marker_P", c.markerTarget.x, c.markerTarget.y)
            case .barnesMaze where flow.shape == .circle:
                put("marker_T", c.markerTarget.x, c.markerTarget.y)
            default:
                break
            }
            widthCM = flow.zone.arenaWidthCM
            heightCM = flow.zone.arenaHeightCM
            timeSeconds = flow.frameTime
            visualParameters.analysisStartSeconds = flow.zone.analysisStartSeconds
            visualParameters.analysisDurationSeconds = flow.zone.analysisDurationSeconds
        } else if let limb {
            let w = max(limb.frameWidth, 1), hh = max(limb.frameHeight, 1)
            switch limb.mode {
            case .circle:
                shape = .circle
                if let c = limb.calibration.circle {
                    put("C", c.cx / w, c.cy / hh)
                    put("R", (c.cx + c.r) / w, c.cy / hh)
                }
            case .floor:
                shape = .floorLine
                if let y = limb.calibration.floorY { put("F", 0.5, y / hh) }
            case .ruler:
                shape = .ruler
                if let s = limb.calibration.scale {
                    put("A", s.x1 / w, s.y1 / hh)
                    put("B", s.x2 / w, s.y2 / hh)
                    referenceCM = s.cm
                }
            }
            timeSeconds = limb.frameTime
        }
        handles = h
    }
}
