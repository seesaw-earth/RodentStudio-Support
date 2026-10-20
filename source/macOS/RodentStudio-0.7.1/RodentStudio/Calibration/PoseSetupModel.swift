// PoseSetupModel.swift — ported unchanged from RodentPose iOS 1.0 SessionModels.swift (OriginalAppSources):
// ArenaCalibration (handles in normalized upright-frame coordinates, real dimensions in cm, markers) with
// ArenaCalibration.makeDefault, and AnalysisParams (paradigm thresholds and zone settings) with their
// tolerant decoding. Session-level types (video, pose summary, status) are not needed here.

import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value if present and valid, otherwise returns the default.
    func v<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Calibration

struct ArenaCalibration: Codable, Equatable {
    var kind: ArenaKind = .rectangle
    /// Rectangle corners in order TL, TR, BR, BL (normalized image coordinates).
    var corners: [NPoint] = [NPoint(0.1, 0.1), NPoint(0.9, 0.1), NPoint(0.9, 0.9), NPoint(0.1, 0.9)]
    var widthCM: Double = 40
    var heightCM: Double = 40
    var circleCenter = NPoint(0.5, 0.5)
    var circleEdge = NPoint(0.85, 0.5)
    var diameterCM: Double = 40
    /// Maze handles: plus C,N,E,S,W · Y J,A,B,C · T J,S,L,R.
    var mazePoints: [NPoint] = []
    var armWidthCM: Double = 5
    var armLengthCM: Double = 30
    /// Paradigm markers (objects, cups, shelter, target hole, cue card).
    var markers: [String: NPoint] = [:]

    init() {}

    enum CodingKeys: String, CodingKey {
        case kind, corners, widthCM, heightCM, circleCenter, circleEdge, diameterCM, mazePoints, armWidthCM, armLengthCM, markers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ArenaCalibration()
        kind = c.v(.kind, d.kind)
        corners = c.v(.corners, d.corners)
        if corners.count != 4 { corners = d.corners }
        widthCM = c.v(.widthCM, d.widthCM)
        heightCM = c.v(.heightCM, d.heightCM)
        circleCenter = c.v(.circleCenter, d.circleCenter)
        circleEdge = c.v(.circleEdge, d.circleEdge)
        diameterCM = c.v(.diameterCM, d.diameterCM)
        mazePoints = c.v(.mazePoints, d.mazePoints)
        armWidthCM = c.v(.armWidthCM, d.armWidthCM)
        armLengthCM = c.v(.armLengthCM, d.armLengthCM)
        markers = c.v(.markers, d.markers)
    }

    /// Default handles for a paradigm, laid out for a frame of the given pixel size.
    static func makeDefault(paradigm: Paradigm, kind: ArenaKind, frameSize: V2) -> ArenaCalibration {
        var cal = ArenaCalibration()
        cal.kind = kind
        let w = max(frameSize.x, 1), h = max(frameSize.y, 1)
        let size = paradigm.defaultArenaSize
        let minDim = min(w, h)

        switch kind {
        case .none:
            break
        case .rectangle:
            cal.widthCM = size.width
            cal.heightCM = size.height
            let aspect = size.width / max(size.height, 1)
            var rectH = 0.8 * h
            var rectW = aspect * rectH
            if rectW > 0.85 * w {
                let s = 0.85 * w / rectW
                rectW *= s
                rectH *= s
            }
            let nw = rectW / w / 2, nh = rectH / h / 2
            cal.corners = [NPoint(0.5 - nw, 0.5 - nh), NPoint(0.5 + nw, 0.5 - nh), NPoint(0.5 + nw, 0.5 + nh), NPoint(0.5 - nw, 0.5 + nh)]
        case .circle:
            cal.diameterCM = size.width
            let r = 0.42 * minDim
            cal.circleCenter = NPoint(0.5, 0.5)
            cal.circleEdge = NPoint(0.5 + r / w, 0.5)
        case .plusMaze:
            cal.armLengthCM = size.width
            cal.armWidthCM = size.height
            let l = 0.44 * minDim
            cal.mazePoints = [NPoint(0.5, 0.5), NPoint(0.5, 0.5 - l / h), NPoint(0.5 + l / w, 0.5), NPoint(0.5, 0.5 + l / h), NPoint(0.5 - l / w, 0.5)]
        case .yMaze:
            cal.armLengthCM = size.width
            cal.armWidthCM = size.height
            let l = 0.42 * minDim
            let jy = 0.56
            cal.mazePoints = [NPoint(0.5, jy), NPoint(0.5, jy - l / h),
                              NPoint(0.5 - 0.866 * l / w, jy + 0.5 * l / h), NPoint(0.5 + 0.866 * l / w, jy + 0.5 * l / h)]
        case .tMaze:
            cal.armLengthCM = size.width
            cal.armWidthCM = size.height
            let l = 0.45 * minDim
            let jy = 0.28
            cal.mazePoints = [NPoint(0.5, jy), NPoint(0.5, jy + 1.3 * l / h), NPoint(0.5 - l / w, jy), NPoint(0.5 + l / w, jy)]
        }

        // Markers: positions defined in arena units, converted to the image with the default mapping.
        let mapping = ArenaMapper.mapping(cal, frameSize: frameSize)
        let e = mapping.extent
        func put(_ key: String, _ ax: Double, _ ay: Double) {
            cal.markers[key] = mapping.toNormalized(V2(ax * e.x, ay * e.y)).clamped()
        }
        switch paradigm {
        case .threeChamber:
            put("cupL", 1.0 / 6.0, 0.5)
            put("cupR", 5.0 / 6.0, 0.5)
        case .novelObject:
            put("objA", 0.3, 0.3)
            put("objB", 0.7, 0.3)
        case .looming:
            put("shelter", 0.16, 0.16)
        case .headDirection:
            put("cue", 0.5, 0.02)
        case .barnesMaze:
            // Target hole on the ring ~5 cm from the edge, at 45° (upper right).
            let r = e.x / 2
            let ring = max(r - 5, r * 0.8)
            let a = 45.0 * Double.pi / 180
            cal.markers["target"] = mapping.toNormalized(V2(r + ring * cos(a), r - ring * sin(a))).clamped()
        default:
            break
        }
        return cal
    }
}

struct AnalysisParams: Codable, Equatable {
    // Preprocessing
    var kpConf: Double = 0.5
    var smoothing: Double = 0.15
    var maxGap: Double = 0.5
    var maxJumpSpeed: Double = 150
    // Analysis window (seconds of video time); length 0 = to the end
    var windowStart: Double = 0
    var windowLength: Double = 0
    var timeBin: Double = 60
    // Locomotion / immobility
    var moveSpeed: Double = 2
    var freezeSpeed: Double = 1.0
    var freezeMin: Double = 1.0
    // Open field
    var centerFraction: Double = 0.5
    // Objects (NOR) and cups (three-chamber)
    var objectRadius: Double = 2.5
    var exploreMargin: Double = 2
    var headTolerance: Double = 45
    var novelObject = "B"
    var cupRadius: Double = 5
    var stimSide = "L"
    var centerChamberFraction: Double = 1.0 / 3.0
    /// Offset of the middle chamber center from 0.5 of the arena width (0 = centered).
    var centerChamberOffset: Double = 0
    // Social interaction test (CSDS)
    var enclosureWall = "top"
    var enclosureWidth: Double = 10
    var enclosureDepth: Double = 6.5
    var izWidth: Double = 26
    var izDepth: Double = 14
    var cornerSize: Double = 9
    // Dyadic social
    var noseNoseDist: Double = 2.5
    var anogenitalDist: Double = 2.5
    var bodySniffDist: Double = 3
    var proximityDist: Double = 10
    var followDist: Double = 15
    var followSpeed: Double = 5
    var followAngle: Double = 45
    var followMin: Double = 0.5
    // Plus / Y / T maze
    var openAxis = "NS"
    var entryRule = "full"     // body · full · nose
    var headDipReach: Double = 6
    var headDipMin: Double = 0.2
    var sapElongation: Double = 1.2
    var sapSpeed: Double = 5
    var sapMin: Double = 0.5
    var choiceRadiusFactor: Double = 1.0
    var vteZ: Double = 0.5
    // Light–dark
    var lightOnLeft = true
    var lightFraction: Double = 2.0 / 3.0
    var pokeMin: Double = 0.2
    // Barnes
    var holeCount: Int = 20
    var holeRadius: Double = 2.5
    var pokeMargin: Double = 1.0
    var holePokeMin: Double = 0.15
    // Fear conditioning
    var csOnsets: [Double] = []
    var csDuration: Double = 30
    // Looming
    var stimOnsets: [Double] = []
    var shelterRadius: Double = 10
    var flightFactor: Double = 4
    var flightMinSpeed: Double = 15
    var escapeWindow: Double = 10
    var baselineWindow: Double = 5
    // Rotation
    var lesionSide = "none"    // none · left · right
    var cameraBelow = false
    var rotationBin: Double = 300
    // Head direction / spatial
    var hdBinDeg: Double = 6
    var hdReference = "image"  // image · cue
    var hdMinBinTime: Double = 1
    var spatialBin: Double = 2.5
    var coverageMinTime: Double = 0.2

    init() {}

    static func defaults(for paradigm: Paradigm) -> AnalysisParams {
        var p = AnalysisParams()
        switch paradigm {
        case .socialInteraction: p.windowLength = 150
        case .elevatedPlusMaze: p.windowLength = 300
        case .rotation: p.timeBin = 300
        case .headDirection: p.hdReference = "image"
        default: break
        }
        return p
    }

    enum CodingKeys: String, CodingKey {
        case kpConf, smoothing, maxGap, maxJumpSpeed, windowStart, windowLength, timeBin, moveSpeed, freezeSpeed, freezeMin
        case centerFraction, objectRadius, exploreMargin, headTolerance, novelObject, cupRadius, stimSide, centerChamberFraction, centerChamberOffset
        case enclosureWall, enclosureWidth, enclosureDepth, izWidth, izDepth, cornerSize
        case noseNoseDist, anogenitalDist, bodySniffDist, proximityDist, followDist, followSpeed, followAngle, followMin
        case openAxis, entryRule, headDipReach, headDipMin, sapElongation, sapSpeed, sapMin, choiceRadiusFactor, vteZ
        case lightOnLeft, lightFraction, pokeMin, holeCount, holeRadius, pokeMargin, holePokeMin
        case csOnsets, csDuration, stimOnsets, shelterRadius, flightFactor, flightMinSpeed, escapeWindow, baselineWindow
        case lesionSide, cameraBelow, rotationBin, hdBinDeg, hdReference, hdMinBinTime, spatialBin, coverageMinTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AnalysisParams()
        kpConf = c.v(.kpConf, d.kpConf)
        smoothing = c.v(.smoothing, d.smoothing)
        maxGap = c.v(.maxGap, d.maxGap)
        maxJumpSpeed = c.v(.maxJumpSpeed, d.maxJumpSpeed)
        windowStart = c.v(.windowStart, d.windowStart)
        windowLength = c.v(.windowLength, d.windowLength)
        timeBin = c.v(.timeBin, d.timeBin)
        moveSpeed = c.v(.moveSpeed, d.moveSpeed)
        freezeSpeed = c.v(.freezeSpeed, d.freezeSpeed)
        freezeMin = c.v(.freezeMin, d.freezeMin)
        centerFraction = c.v(.centerFraction, d.centerFraction)
        objectRadius = c.v(.objectRadius, d.objectRadius)
        exploreMargin = c.v(.exploreMargin, d.exploreMargin)
        headTolerance = c.v(.headTolerance, d.headTolerance)
        novelObject = c.v(.novelObject, d.novelObject)
        cupRadius = c.v(.cupRadius, d.cupRadius)
        stimSide = c.v(.stimSide, d.stimSide)
        centerChamberFraction = c.v(.centerChamberFraction, d.centerChamberFraction)
        centerChamberOffset = c.v(.centerChamberOffset, d.centerChamberOffset)
        enclosureWall = c.v(.enclosureWall, d.enclosureWall)
        enclosureWidth = c.v(.enclosureWidth, d.enclosureWidth)
        enclosureDepth = c.v(.enclosureDepth, d.enclosureDepth)
        izWidth = c.v(.izWidth, d.izWidth)
        izDepth = c.v(.izDepth, d.izDepth)
        cornerSize = c.v(.cornerSize, d.cornerSize)
        noseNoseDist = c.v(.noseNoseDist, d.noseNoseDist)
        anogenitalDist = c.v(.anogenitalDist, d.anogenitalDist)
        bodySniffDist = c.v(.bodySniffDist, d.bodySniffDist)
        proximityDist = c.v(.proximityDist, d.proximityDist)
        followDist = c.v(.followDist, d.followDist)
        followSpeed = c.v(.followSpeed, d.followSpeed)
        followAngle = c.v(.followAngle, d.followAngle)
        followMin = c.v(.followMin, d.followMin)
        openAxis = c.v(.openAxis, d.openAxis)
        entryRule = c.v(.entryRule, d.entryRule)
        headDipReach = c.v(.headDipReach, d.headDipReach)
        headDipMin = c.v(.headDipMin, d.headDipMin)
        sapElongation = c.v(.sapElongation, d.sapElongation)
        sapSpeed = c.v(.sapSpeed, d.sapSpeed)
        sapMin = c.v(.sapMin, d.sapMin)
        choiceRadiusFactor = c.v(.choiceRadiusFactor, d.choiceRadiusFactor)
        vteZ = c.v(.vteZ, d.vteZ)
        lightOnLeft = c.v(.lightOnLeft, d.lightOnLeft)
        lightFraction = c.v(.lightFraction, d.lightFraction)
        pokeMin = c.v(.pokeMin, d.pokeMin)
        holeCount = c.v(.holeCount, d.holeCount)
        holeRadius = c.v(.holeRadius, d.holeRadius)
        pokeMargin = c.v(.pokeMargin, d.pokeMargin)
        holePokeMin = c.v(.holePokeMin, d.holePokeMin)
        csOnsets = c.v(.csOnsets, d.csOnsets)
        csDuration = c.v(.csDuration, d.csDuration)
        stimOnsets = c.v(.stimOnsets, d.stimOnsets)
        shelterRadius = c.v(.shelterRadius, d.shelterRadius)
        flightFactor = c.v(.flightFactor, d.flightFactor)
        flightMinSpeed = c.v(.flightMinSpeed, d.flightMinSpeed)
        escapeWindow = c.v(.escapeWindow, d.escapeWindow)
        baselineWindow = c.v(.baselineWindow, d.baselineWindow)
        lesionSide = c.v(.lesionSide, d.lesionSide)
        cameraBelow = c.v(.cameraBelow, d.cameraBelow)
        rotationBin = c.v(.rotationBin, d.rotationBin)
        hdBinDeg = c.v(.hdBinDeg, d.hdBinDeg)
        hdReference = c.v(.hdReference, d.hdReference)
        hdMinBinTime = c.v(.hdMinBinTime, d.hdMinBinTime)
        spatialBin = c.v(.spatialBin, d.spatialBin)
        coverageMinTime = c.v(.coverageMinTime, d.coverageMinTime)
    }
}
