// FlowSetupModel.swift — RodentFlow iOS 1.3 arena calibration and zone settings, ported from
// OriginalAppSources (TrackingModels.swift: ArenaShape, NormalizedPoint, ArenaCalibration;
// ArenaMapping.swift: PlanarHomography; ResultModels.swift: ArenaPoint, ZoneConfig;
// AssayCatalog.swift: videoArenaShapes, phases, days / trials; AppState.swift: arena dimensions).
// Types carry a `Flow` prefix because RodentPose uses the same names for different structures.
// Default handle positions, defaults and tolerant decoding are copied from the originals.

import Foundation

// MARK: - Arena shape

enum FlowArenaShape: String, Codable, CaseIterable, Identifiable {
    case rectangle
    case circle
    case tMaze = "t_maze"
    case yMaze = "y_maze"
    case plusMaze = "plus_maze"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: return L("Open Field · Rectangle", "旷场 · 矩形")
        case .circle: return L("Open Field · Circle", "旷场 · 圆形")
        case .tMaze: return L("T-Maze", "T 迷宫")
        case .yMaze: return L("Y-Maze", "Y 迷宫")
        case .plusMaze: return L("Elevated Plus Maze", "高架十字迷宫")
        }
    }

    var shortName: String {
        switch self {
        case .rectangle: return L("Rectangle", "矩形")
        case .circle: return L("Circle", "圆形")
        case .tMaze: return L("T-Maze", "T 迷宫")
        case .yMaze: return L("Y-Maze", "Y 迷宫")
        case .plusMaze: return L("Plus maze", "十字迷宫")
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle.dashed"
        case .circle: return "circle.dashed"
        case .tMaze: return "arrow.triangle.branch"
        case .yMaze: return "arrow.triangle.branch"
        case .plusMaze: return "plus"
        }
    }

    var isMaze: Bool { self == .tMaze || self == .yMaze || self == .plusMaze }
}

// MARK: - Normalized point (upright frame, 0…1)

struct FlowPoint: Codable, Hashable {
    var x: Double
    var y: Double

    static let topLeft = FlowPoint(x: 0.06, y: 0.06)
    static let topRight = FlowPoint(x: 0.94, y: 0.06)
    static let bottomRight = FlowPoint(x: 0.94, y: 0.94)
    static let bottomLeft = FlowPoint(x: 0.06, y: 0.94)
    static let center = FlowPoint(x: 0.50, y: 0.50)
    static let circleEdge = FlowPoint(x: 0.88, y: 0.50)

    static let tJunction = FlowPoint(x: 0.50, y: 0.34)
    static let tStart = FlowPoint(x: 0.50, y: 0.90)
    static let tLeft = FlowPoint(x: 0.12, y: 0.34)
    static let tRight = FlowPoint(x: 0.88, y: 0.34)

    static let yJunction = FlowPoint(x: 0.50, y: 0.55)
    static let yA = FlowPoint(x: 0.50, y: 0.10)
    static let yB = FlowPoint(x: 0.16, y: 0.84)
    static let yC = FlowPoint(x: 0.84, y: 0.84)

    static let plusCenter = FlowPoint(x: 0.50, y: 0.50)
    static let plusN = FlowPoint(x: 0.50, y: 0.06)
    static let plusE = FlowPoint(x: 0.80, y: 0.50)
    static let plusS = FlowPoint(x: 0.50, y: 0.94)
    static let plusW = FlowPoint(x: 0.20, y: 0.50)

    static let markerA = FlowPoint(x: 0.35, y: 0.35)
    static let markerB = FlowPoint(x: 0.65, y: 0.65)
    static let markerTarget = FlowPoint(x: 0.68, y: 0.32)

    func clamped() -> FlowPoint { FlowPoint(x: min(max(0, x), 1), y: min(max(0, y), 1)) }
}

// MARK: - Arena calibration

struct FlowArenaCalibration: Codable, Hashable {
    var topLeft: FlowPoint = .topLeft
    var topRight: FlowPoint = .topRight
    var bottomRight: FlowPoint = .bottomRight
    var bottomLeft: FlowPoint = .bottomLeft

    var circleCenter: FlowPoint = .center
    var circleEdge: FlowPoint = .circleEdge

    var tJunction: FlowPoint = .tJunction
    var tStart: FlowPoint = .tStart
    var tLeft: FlowPoint = .tLeft
    var tRight: FlowPoint = .tRight

    var yJunction: FlowPoint = .yJunction
    var yA: FlowPoint = .yA
    var yB: FlowPoint = .yB
    var yC: FlowPoint = .yC

    /// Elevated plus maze: center junction and the four arm ends (image-relative N/E/S/W).
    var plusCenter: FlowPoint = .plusCenter
    var plusN: FlowPoint = .plusN
    var plusE: FlowPoint = .plusE
    var plusS: FlowPoint = .plusS
    var plusW: FlowPoint = .plusW

    /// Assay zone markers placed on the calibration frame (object A/B, platform / target hole).
    var markerA: FlowPoint = .markerA
    var markerB: FlowPoint = .markerB
    var markerTarget: FlowPoint = .markerTarget

    var corners: [FlowPoint] { [topLeft, topRight, bottomRight, bottomLeft] }
    var tPoints: [FlowPoint] { [tJunction, tStart, tLeft, tRight] }
    var yPoints: [FlowPoint] { [yJunction, yA, yB, yC] }
    var plusPoints: [FlowPoint] { [plusCenter, plusN, plusE, plusS, plusW] }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topLeft = c.v(.topLeft, FlowPoint.topLeft)
        topRight = c.v(.topRight, FlowPoint.topRight)
        bottomRight = c.v(.bottomRight, FlowPoint.bottomRight)
        bottomLeft = c.v(.bottomLeft, FlowPoint.bottomLeft)
        circleCenter = c.v(.circleCenter, FlowPoint.center)
        circleEdge = c.v(.circleEdge, FlowPoint.circleEdge)
        tJunction = c.v(.tJunction, FlowPoint.tJunction)
        tStart = c.v(.tStart, FlowPoint.tStart)
        tLeft = c.v(.tLeft, FlowPoint.tLeft)
        tRight = c.v(.tRight, FlowPoint.tRight)
        yJunction = c.v(.yJunction, FlowPoint.yJunction)
        yA = c.v(.yA, FlowPoint.yA)
        yB = c.v(.yB, FlowPoint.yB)
        yC = c.v(.yC, FlowPoint.yC)
        plusCenter = c.v(.plusCenter, FlowPoint.plusCenter)
        plusN = c.v(.plusN, FlowPoint.plusN)
        plusE = c.v(.plusE, FlowPoint.plusE)
        plusS = c.v(.plusS, FlowPoint.plusS)
        plusW = c.v(.plusW, FlowPoint.plusW)
        markerA = c.v(.markerA, FlowPoint.markerA)
        markerB = c.v(.markerB, FlowPoint.markerB)
        markerTarget = c.v(.markerTarget, FlowPoint.markerTarget)
    }

    mutating func setPlusMazePoint(_ index: Int, to point: FlowPoint) {
        switch index {
        case 0: plusCenter = point
        case 1: plusN = point
        case 2: plusE = point
        case 3: plusS = point
        case 4: plusW = point
        default: break
        }
    }

    mutating func setCorner(_ index: Int, to point: FlowPoint) {
        switch index {
        case 0: topLeft = point
        case 1: topRight = point
        case 2: bottomRight = point
        case 3: bottomLeft = point
        default: break
        }
    }

    mutating func setTMazePoint(_ index: Int, to point: FlowPoint) {
        switch index {
        case 0: tJunction = point
        case 1: tStart = point
        case 2: tLeft = point
        case 3: tRight = point
        default: break
        }
    }

    mutating func setYMazePoint(_ index: Int, to point: FlowPoint) {
        switch index {
        case 0: yJunction = point
        case 1: yA = point
        case 2: yB = point
        case 3: yC = point
        default: break
        }
    }
}

// MARK: - Planar homography (arena-normalized → image-normalized), from ArenaMapping.swift

struct PlanarHomography {
    private let h: [Double]

    init?(source: [(Double, Double)], destination: [(Double, Double)]) {
        guard source.count == 4, destination.count == 4 else { return nil }
        var a = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = source[i]
            let (u, v) = destination[i]
            let r = 2 * i
            a[r][0] = x; a[r][1] = y; a[r][2] = 1
            a[r][6] = -u * x; a[r][7] = -u * y; a[r][8] = u
            a[r + 1][3] = x; a[r + 1][4] = y; a[r + 1][5] = 1
            a[r + 1][6] = -v * x; a[r + 1][7] = -v * y; a[r + 1][8] = v
        }
        for col in 0..<8 {
            var pivot = col
            for row in col..<8 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            if pivot != col { a.swapAt(pivot, col) }
            let divisor = a[col][col]
            for j in col..<9 { a[col][j] /= divisor }
            for row in 0..<8 where row != col {
                let factor = a[row][col]
                guard factor != 0 else { continue }
                for j in col..<9 { a[row][j] -= factor * a[col][j] }
            }
        }
        h = (0..<8).map { a[$0][8] }
    }

    func map(_ x: Double, _ y: Double) -> (Double, Double) {
        let d = h[6] * x + h[7] * y + 1
        guard abs(d) > 1e-12 else { return (x, y) }
        return ((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d)
    }

    /// Maps arena-normalized (0…1) coordinates to normalized image coordinates for a calibrated
    /// rectangle with corners TL, TR, BR, BL.
    static func arenaToImage(_ calibration: FlowArenaCalibration) -> PlanarHomography? {
        PlanarHomography(
            source: [(0, 0), (1, 0), (1, 1), (0, 1)],
            destination: calibration.corners.map { ($0.x, $0.y) }
        )
    }
}

// MARK: - Zone settings (ResultModels.swift ZoneConfig)

struct FlowArenaPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

/// Post-hoc analysis parameters for video-derived results. In RodentFlow, editing these re-computes the
/// metrics from the saved tracking samples without re-running the tracker.
struct FlowZoneConfig: Codable, Hashable {
    var arenaShape: FlowArenaShape = .rectangle
    var arenaWidthCM: Double = 40
    var arenaHeightCM: Double = 40
    /// Analysis window relative to the first tracked sample. Duration 0 = until the end.
    var analysisStartSeconds: Double = 0
    var analysisDurationSeconds: Double = 0
    var entryMinSeconds: Double = 0.3

    // Open field
    var centerFraction: Double = 0.5
    var movingSpeedCMs: Double = 2.0
    var immobilityMinSeconds: Double = 2.0
    var timeBinSeconds: Double = 300

    // Elevated plus maze
    var plusArmLengthCM: Double = 30
    var plusArmWidthCM: Double = 5
    var plusOpenAxis: String = "NS"
    var plusCenterMarginCM: Double = 0

    // Light–dark box
    var lightFraction: Double = 0.667
    var lightOnLeft: Bool = true
    var undetectedIsDark: Bool = true

    // Conditioned place preference
    var cppChambers: Int = 2
    var cppDivider: Double = 0.5
    var cppNeutralFraction: Double = 0.2
    var cppPairedOnLeft: Bool = true

    // Novel object recognition
    var objectA: FlowArenaPoint?
    var objectB: FlowArenaPoint?
    /// Body-centroid radius around the object centre. The centroid sits ~4–5 cm behind the nose,
    /// so sniffing a 2–3 cm object puts it ~6–9 cm from the object centre.
    var objectZoneRadiusCM: Double = 8
    var novelObject: String = "B"
    var minTotalExplorationSeconds: Double = 10

    // Morris water maze / Barnes maze
    var target: FlowArenaPoint?
    var targetRadiusCM: Double = 6
    var maxTrialSeconds: Double = 60
    var platformStaySeconds: Double = 1.0
    var wallZoneCM: Double = 10
    var holeCount: Int = 20

    // Fear conditioning
    var freezeThresholdPct: Double = 5
    var freezeMinSeconds: Double = 1.0
    var protocolOffsetSeconds: Double = 0
    var baselineSeconds: Double = 120
    var csOnsetsSeconds: [Double] = []
    var csDurationSeconds: Double = 30
    var fearBinSeconds: Double = 60

    // T / Y maze
    var mazeEntryMinSeconds: Double = 0.25

    init() {}

    /// Sensible starting values for each assay (ZoneConfig.defaults(for:shape:widthCM:heightCM:)).
    static func defaults(for assay: FlowAssay, shape: FlowArenaShape, widthCM: Double, heightCM: Double) -> FlowZoneConfig {
        var c = FlowZoneConfig()
        c.arenaShape = shape
        c.arenaWidthCM = widthCM
        c.arenaHeightCM = heightCM
        switch assay {
        case .novelObject:
            c.analysisDurationSeconds = 300
            c.objectA = FlowArenaPoint(x: widthCM * 0.3, y: heightCM * 0.3)
            c.objectB = FlowArenaPoint(x: widthCM * 0.7, y: heightCM * 0.7)
        case .morrisWaterMaze:
            c.maxTrialSeconds = 60
            c.targetRadiusCM = 6
            c.wallZoneCM = 10
            c.target = FlowArenaPoint(x: widthCM * 0.75, y: heightCM * 0.25)
        case .barnesMaze:
            c.maxTrialSeconds = 180
            // A dark mouse's head disappears into the hole during a poke, so the visible-body
            // centroid stays ~5–7 cm from the hole centre. Visits go to the nearest hole, so the
            // zone may exceed half the hole spacing.
            c.targetRadiusCM = 8
            c.entryMinSeconds = 0.2
            c.target = FlowArenaPoint(x: widthCM * 0.5, y: heightCM * 0.06)
        case .elevatedPlusMaze:
            c.entryMinSeconds = 0.25
        case .lightDark:
            c.entryMinSeconds = 0.5
        case .placePreference:
            c.entryMinSeconds = 0.5
        default:
            break
        }
        return c
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FlowZoneConfig()
        arenaShape = c.v(.arenaShape, d.arenaShape)
        arenaWidthCM = c.v(.arenaWidthCM, d.arenaWidthCM)
        arenaHeightCM = c.v(.arenaHeightCM, d.arenaHeightCM)
        analysisStartSeconds = c.v(.analysisStartSeconds, d.analysisStartSeconds)
        analysisDurationSeconds = c.v(.analysisDurationSeconds, d.analysisDurationSeconds)
        entryMinSeconds = c.v(.entryMinSeconds, d.entryMinSeconds)
        centerFraction = c.v(.centerFraction, d.centerFraction)
        movingSpeedCMs = c.v(.movingSpeedCMs, d.movingSpeedCMs)
        immobilityMinSeconds = c.v(.immobilityMinSeconds, d.immobilityMinSeconds)
        timeBinSeconds = c.v(.timeBinSeconds, d.timeBinSeconds)
        plusArmLengthCM = c.v(.plusArmLengthCM, d.plusArmLengthCM)
        plusArmWidthCM = c.v(.plusArmWidthCM, d.plusArmWidthCM)
        plusOpenAxis = c.v(.plusOpenAxis, d.plusOpenAxis)
        plusCenterMarginCM = c.v(.plusCenterMarginCM, d.plusCenterMarginCM)
        lightFraction = c.v(.lightFraction, d.lightFraction)
        lightOnLeft = c.v(.lightOnLeft, d.lightOnLeft)
        undetectedIsDark = c.v(.undetectedIsDark, d.undetectedIsDark)
        cppChambers = c.v(.cppChambers, d.cppChambers)
        cppDivider = c.v(.cppDivider, d.cppDivider)
        cppNeutralFraction = c.v(.cppNeutralFraction, d.cppNeutralFraction)
        cppPairedOnLeft = c.v(.cppPairedOnLeft, d.cppPairedOnLeft)
        objectA = (try? c.decodeIfPresent(FlowArenaPoint.self, forKey: .objectA)) ?? nil
        objectB = (try? c.decodeIfPresent(FlowArenaPoint.self, forKey: .objectB)) ?? nil
        objectZoneRadiusCM = c.v(.objectZoneRadiusCM, d.objectZoneRadiusCM)
        novelObject = c.v(.novelObject, d.novelObject)
        minTotalExplorationSeconds = c.v(.minTotalExplorationSeconds, d.minTotalExplorationSeconds)
        target = (try? c.decodeIfPresent(FlowArenaPoint.self, forKey: .target)) ?? nil
        targetRadiusCM = c.v(.targetRadiusCM, d.targetRadiusCM)
        maxTrialSeconds = c.v(.maxTrialSeconds, d.maxTrialSeconds)
        platformStaySeconds = c.v(.platformStaySeconds, d.platformStaySeconds)
        wallZoneCM = c.v(.wallZoneCM, d.wallZoneCM)
        holeCount = c.v(.holeCount, d.holeCount)
        freezeThresholdPct = c.v(.freezeThresholdPct, d.freezeThresholdPct)
        freezeMinSeconds = c.v(.freezeMinSeconds, d.freezeMinSeconds)
        protocolOffsetSeconds = c.v(.protocolOffsetSeconds, d.protocolOffsetSeconds)
        baselineSeconds = c.v(.baselineSeconds, d.baselineSeconds)
        csOnsetsSeconds = c.v(.csOnsetsSeconds, d.csOnsetsSeconds)
        csDurationSeconds = c.v(.csDurationSeconds, d.csDurationSeconds)
        fearBinSeconds = c.v(.fearBinSeconds, d.fearBinSeconds)
        mazeEntryMinSeconds = c.v(.mazeEntryMinSeconds, d.mazeEntryMinSeconds)
    }
}

// MARK: - Assay facts used by setup (AssayCatalog.swift, video assays only)

enum FlowAssay: String, Codable, CaseIterable, Identifiable {
    case openField = "open_field"
    case elevatedPlusMaze = "elevated_plus_maze"
    case lightDark = "light_dark_box"
    case yMaze = "y_maze"
    case tMaze = "t_maze"
    case novelObject = "novel_object_recognition"
    case morrisWaterMaze = "morris_water_maze"
    case barnesMaze = "barnes_maze"
    case fearConditioning = "fear_conditioning"
    case placePreference = "conditioned_place_preference"

    var id: String { rawValue }

    /// Arena shapes that the original on-device tracker supports for this assay.
    var videoArenaShapes: [FlowArenaShape] {
        switch self {
        case .openField, .novelObject: return [.rectangle, .circle]
        case .elevatedPlusMaze: return [.plusMaze]
        case .lightDark, .placePreference, .fearConditioning: return [.rectangle]
        case .morrisWaterMaze, .barnesMaze: return [.circle]
        case .yMaze: return [.yMaze]
        case .tMaze: return [.tMaze]
        }
    }

    /// Fixed phase labels (stored in English). Empty = optional free text.
    var phases: [String] {
        switch self {
        case .novelObject: return ["Training", "Test"]
        case .morrisWaterMaze: return ["Acquisition", "Probe"]
        case .barnesMaze: return ["Acquisition", "Probe"]
        case .fearConditioning: return ["Training", "Context test", "Cue test"]
        case .placePreference: return ["Pre-test", "Conditioning", "Test"]
        default: return []
        }
    }

    var defaultPhase: String { phases.last ?? "" }

    var usesDays: Bool {
        switch self {
        case .morrisWaterMaze, .barnesMaze, .placePreference: return true
        default: return false
        }
    }

    var usesTrials: Bool {
        switch self {
        case .morrisWaterMaze, .barnesMaze, .tMaze: return true
        default: return false
        }
    }

    static func phaseTitle(_ phase: String) -> String {
        switch phase {
        case "Training": return L("Training", "训练")
        case "Test": return L("Test", "测试")
        case "Acquisition": return L("Acquisition", "习得")
        case "Probe": return L("Probe", "探索测试")
        case "Context test": return L("Context test", "情境测试")
        case "Cue test": return L("Cue test", "线索测试")
        case "Pre-test": return L("Pre-test", "前测")
        case "Conditioning": return L("Conditioning", "条件化")
        default: return phase
        }
    }
}

// MARK: - Arena dimensions entered in Setup (AppState.swift)

struct FlowArenaDimensions: Codable, Hashable {
    var arenaWidthCM: Double = 40
    var arenaHeightCM: Double = 40
    var mazeArmWidthCM: Double = 10
    var tStartArmLengthCM: Double = 40
    var tChoiceArmLengthCM: Double = 30
    var yArmLengthCM: Double = 35
    var plusArmLengthCM: Double = 30
    var plusArmWidthCM: Double = 5

    func effectiveWidthCM(_ shape: FlowArenaShape) -> Double {
        switch shape {
        case .rectangle: return arenaWidthCM
        case .circle: return arenaWidthCM
        case .tMaze: return 2 * tChoiceArmLengthCM + mazeArmWidthCM
        case .yMaze: return sqrt(3.0) * yArmLengthCM + mazeArmWidthCM
        case .plusMaze: return 2 * (plusArmLengthCM + plusArmWidthCM)
        }
    }

    func effectiveHeightCM(_ shape: FlowArenaShape) -> Double {
        switch shape {
        case .rectangle: return arenaHeightCM
        case .circle: return arenaWidthCM
        case .tMaze: return tStartArmLengthCM + mazeArmWidthCM
        case .yMaze: return 1.5 * yArmLengthCM + mazeArmWidthCM
        case .plusMaze: return 2 * (plusArmLengthCM + plusArmWidthCM)
        }
    }
}
