// PoseZones.swift — ported from RodentPose iOS 1.0 Zones.swift (OriginalAppSources). Zones are drawn on the
// calibration frame exactly as the iOS app draws them. Changes: bilingual labels via L(en, zh) taken from the
// app's own EnglishTranslations.json, and ZoneBuilder.zones takes paradigm / phase / calibration / params
// explicitly instead of a Session.
// Zones are the single source of truth for analysis and for drawing on the video / plots.

import Foundation

// MARK: - Mapping from calibration

enum ArenaMapper {
    /// Distance from the maze center to the end of an arm, in cm.
    static func centerToEnd(_ cal: ArenaCalibration) -> Double {
        switch cal.kind {
        case .yMaze: return cal.armLengthCM + cal.armWidthCM * 0.29
        default: return cal.armLengthCM + cal.armWidthCM / 2
        }
    }

    static func mapping(_ cal: ArenaCalibration, frameSize: V2) -> ArenaMapping {
        let fs = V2(max(frameSize.x, 1), max(frameSize.y, 1))
        switch cal.kind {
        case .none:
            return .pixelsOnly(frameSize: fs)

        case .rectangle:
            let w = max(cal.widthCM, 1), h = max(cal.heightCM, 1)
            let src = cal.corners.map { $0.pixels(fs) }
            let dst = [V2(0, 0), V2(w, 0), V2(w, h), V2(0, h)]
            guard let hm = Homography.fit(src: src, dst: dst), let inv = hm.inverse else {
                return .pixelsOnly(frameSize: fs)
            }
            return ArenaMapping(kind: .homography(hm, inv), extent: V2(w, h), frameSize: fs)

        case .circle:
            let c = cal.circleCenter.pixels(fs)
            let e = cal.circleEdge.pixels(fs)
            let rPx = max(c.distance(to: e), 1)
            let d = max(cal.diameterCM, 1)
            let s = (d / 2) / rPx
            return ArenaMapping(kind: .similarity(cmPerPx: s, originPx: c, offsetCM: V2(d / 2, d / 2)), extent: V2(d, d), frameSize: fs)

        case .plusMaze, .yMaze, .tMaze:
            let need = cal.kind == .plusMaze ? 5 : 4
            guard cal.mazePoints.count == need else { return .pixelsOnly(frameSize: fs) }
            let px = cal.mazePoints.map { $0.pixels(fs) }
            let center = px[0]
            let lengths = px.dropFirst().map { $0.distance(to: center) }
            let meanPx = max(lengths.reduce(0, +) / Double(lengths.count), 1)
            let s = centerToEnd(cal) / meanPx
            let rel = px.map { ($0 - center) * s }
            let margin = cal.armWidthCM / 2 + 8
            let minX = (rel.map { $0.x }.min() ?? 0) - margin
            let minY = (rel.map { $0.y }.min() ?? 0) - margin
            let maxX = (rel.map { $0.x }.max() ?? 0) + margin
            let maxY = (rel.map { $0.y }.max() ?? 0) + margin
            return ArenaMapping(kind: .similarity(cmPerPx: s, originPx: center, offsetCM: V2(-minX, -minY)),
                                extent: V2(maxX - minX, maxY - minY), frameSize: fs)
        }
    }
}

// MARK: - Zone

enum ZoneRole: String {
    case arena, center, periphery, chamber, social, object, novel, familiar, cup
    case interaction, corner, enclosure
    case open, closed, mazeCenter, arm, choice
    case light, dark, shelter, target, hole, quadrant, cue
}

enum ZoneShape {
    case polygon([V2])
    case circle(center: V2, radius: Double)
}

struct Zone: Identifiable {
    let id: String
    var title: String
    var role: ZoneRole
    var shape: ZoneShape
    /// Drawn with a label in plots and on the video.
    var showsLabel = true
    /// Drawn as a thin outline only (e.g. sniff zones around cups).
    var outlineOnly = false

    func contains(_ p: V2) -> Bool {
        guard p.isFinite else { return false }
        switch shape {
        case .polygon(let pts): return polygonContains(pts, p)
        case .circle(let c, let r): return p.distance(to: c) <= r
        }
    }

    var center: V2 {
        switch shape {
        case .circle(let c, _): return c
        case .polygon(let pts):
            guard !pts.isEmpty else { return .zero }
            let s = pts.reduce(V2.zero, +)
            return s / Double(pts.count)
        }
    }

    /// Closed outline in arena units (circles sampled as polygons).
    func outline(segments: Int = 64) -> [V2] {
        switch shape {
        case .polygon(let pts): return pts
        case .circle(let c, let r):
            return (0..<segments).map { i in
                let a = Double(i) / Double(segments) * 2 * .pi
                return V2(c.x + r * cos(a), c.y + r * sin(a))
            }
        }
    }

    static func rect(_ id: String, _ title: String, _ role: ZoneRole, x: Double, y: Double, w: Double, h: Double) -> Zone {
        Zone(id: id, title: title, role: role, shape: .polygon([V2(x, y), V2(x + w, y), V2(x + w, y + h), V2(x, y + h)]))
    }

    static func circle(_ id: String, _ title: String, _ role: ZoneRole, _ c: V2, _ r: Double) -> Zone {
        Zone(id: id, title: title, role: role, shape: .circle(center: c, radius: r))
    }
}

// MARK: - Maze geometry (cm)

struct MazeGeometry {
    let center: V2
    let ends: [V2]          // arm end points
    let labels: [String]
    let armWidth: Double
    let centerRadius: Double

    /// Arm rectangle (from the edge of the center region to the arm end).
    func armPolygon(_ i: Int, extraWidth: Double = 0) -> [V2] {
        let dir = (ends[i] - center).normalized
        let n = dir.perp
        let start = center + dir * centerRadius
        let hw = armWidth / 2 + extraWidth
        let end = ends[i]
        return [start + n * hw, end + n * hw, end - n * hw, start - n * hw]
    }

    /// Index of the arm the point lies in (with a tolerance on the width), or nil.
    func armIndex(_ p: V2, tolerance: Double = 1.25) -> Int? {
        guard p.isFinite else { return nil }
        if p.distance(to: center) <= centerRadius { return nil }
        var best: (Int, Double)?
        for i in ends.indices {
            let (d, t) = pointSegment(p, center, ends[i])
            let len = ends[i].distance(to: center)
            guard t * len >= centerRadius * 0.85, t <= 1.08, d <= armWidth / 2 * tolerance else { continue }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        return best?.0
    }

    func inCenter(_ p: V2, tolerance: Double = 1.0) -> Bool {
        p.isFinite && p.distance(to: center) <= centerRadius * tolerance
    }

    /// Distance from p to the nearest arm axis.
    func distanceToArms(_ p: V2, arms: [Int]) -> Double {
        arms.map { pointSegment(p, center, ends[$0]).distance }.min() ?? .infinity
    }

    static func from(_ cal: ArenaCalibration, mapping: ArenaMapping) -> MazeGeometry? {
        let need = cal.kind == .plusMaze ? 5 : 4
        guard [.plusMaze, .yMaze, .tMaze].contains(cal.kind), cal.mazePoints.count == need else { return nil }
        let pts = cal.mazePoints.map { mapping.toArena($0) }
        let w = max(cal.armWidthCM, 1)
        let cr: Double
        switch cal.kind {
        case .yMaze: cr = w * 0.65
        default: cr = w / 2
        }
        return MazeGeometry(center: pts[0], ends: Array(pts.dropFirst()), labels: Array(cal.kind.mazeLabels.dropFirst()), armWidth: w, centerRadius: cr)
    }
}

// MARK: - Barnes holes

struct BarnesGeometry {
    let center: V2
    let radius: Double
    let holes: [V2]        // index 0 = target
    let holeRadius: Double
    let targetAngle: Double  // screen angle (deg) of the target from the center

    /// Signed hole offset from the target (−N/2 … N/2) for plots.
    func offset(_ i: Int) -> Int {
        let n = holes.count
        var o = i
        if o > n / 2 { o -= n }
        return o
    }

    static func from(_ cal: ArenaCalibration, params: AnalysisParams, mapping: ArenaMapping) -> BarnesGeometry? {
        guard cal.kind == .circle, let t = cal.markers["target"] else { return nil }
        let r = cal.diameterCM / 2
        let c = V2(r, r)
        let tp = mapping.toArena(t)
        let ring = max(tp.distance(to: c), 1)
        let base = atan2(tp.y - c.y, tp.x - c.x)
        let n = max(4, params.holeCount)
        let holes = (0..<n).map { k -> V2 in
            let a = base + 2 * Double.pi * Double(k) / Double(n)
            return V2(c.x + ring * cos(a), c.y + ring * sin(a))
        }
        return BarnesGeometry(center: c, radius: r, holes: holes, holeRadius: params.holeRadius, targetAngle: (tp - c).screenAngleDeg)
    }
}

// MARK: - Zone builder

enum ZoneBuilder {
    /// Outline of the arena itself.
    static func arenaZone(_ cal: ArenaCalibration, mapping: ArenaMapping) -> Zone? {
        let e = mapping.extent
        switch cal.kind {
        case .none: return nil
        case .rectangle: return Zone.rect("arena", L("Arena", "场地"), .arena, x: 0, y: 0, w: e.x, h: e.y)
        case .circle: return Zone.circle("arena", L("Arena", "场地"), .arena, V2(e.x / 2, e.y / 2), e.x / 2)
        case .plusMaze, .yMaze, .tMaze:
            guard let m = MazeGeometry.from(cal, mapping: mapping) else { return nil }
            // Not a single polygon; arms are added as separate zones.
            return Zone.circle("arena", "", .arena, m.center, 0.01)
        }
    }

    /// Boundaries in normalized arena X. Older sessions retain centered thirds.
    /// Keep a narrow but nonzero outer chamber on both sides.
    static func threeChamberBounds(_ p: AnalysisParams) -> (left: Double, right: Double) {
        let rawW = p.centerChamberFraction.isFinite ? p.centerChamberFraction : 1.0 / 3.0
        let w = clamp(rawW, 0.1, 0.8)
        let rawOffset = p.centerChamberOffset.isFinite ? p.centerChamberOffset : 0
        let mid = clamp(0.5 + rawOffset, 0.05 + w / 2, 0.95 - w / 2)
        return (mid - w / 2, mid + w / 2)
    }

    static func zones(paradigm: Paradigm, phase: String, calibration cal: ArenaCalibration,
                      params p: AnalysisParams, mapping: ArenaMapping) -> [Zone] {
        let e = mapping.extent
        var z: [Zone] = []

        func marker(_ key: String) -> V2? { cal.markers[key].map { mapping.toArena($0) } }

        switch paradigm {
        case .openField, .spatialExploration, .headDirection, .dyadicSocial, .fearConditioning, .rotation, .poseOnly:
            if paradigm == .openField {
                let f = clamp(p.centerFraction, 0.05, 0.95)
                if cal.kind == .circle {
                    z.append(Zone.circle("center", L("Center zone", "中央区"), .center, V2(e.x / 2, e.y / 2), e.x / 2 * f))
                } else if cal.kind == .rectangle {
                    z.append(Zone.rect("center", L("Center zone", "中央区"), .center, x: e.x * (1 - f) / 2, y: e.y * (1 - f) / 2, w: e.x * f, h: e.y * f))
                }
            }
            if paradigm == .headDirection, p.hdReference == "cue", let q = marker("cue") {
                z.append(Zone.circle("cue", L("Cue card", "提示卡"), .cue, q, 2))
            }

        case .threeChamber:
            let bounds = threeChamberBounds(p)
            let left = bounds.left * e.x, right = bounds.right * e.x
            z.append(Zone.rect("chL", L("Left chamber", "左箱"), .chamber, x: 0, y: 0, w: left, h: e.y))
            z.append(Zone.rect("chC", L("Center chamber", "中箱"), .chamber, x: left, y: 0, w: right - left, h: e.y))
            z.append(Zone.rect("chR", L("Right chamber", "右箱"), .chamber, x: right, y: 0, w: e.x - right, h: e.y))
            let novelty = phase == "Social novelty"
            for (key, side) in [("cupL", "L"), ("cupR", "R")] {
                guard let c = marker(key) else { continue }
                let isStim = p.stimSide == side
                let title: String
                let role: ZoneRole
                if novelty {
                    title = isStim ? L("Novel stranger", "新陌生鼠") : L("Familiar mouse", "熟悉鼠")
                    role = isStim ? .novel : .familiar
                } else {
                    title = isStim ? L("Stranger mouse", "陌生鼠") : L("Empty cup", "空杯")
                    role = isStim ? .social : .object
                }
                z.append(Zone.circle(key, title, role, c, p.cupRadius))
                var sniff = Zone.circle(key + "_sniff", "", role, c, p.cupRadius + p.exploreMargin)
                sniff.showsLabel = false
                sniff.outlineOnly = true
                z.append(sniff)
            }

        case .socialInteraction:
            let (enc, iz) = enclosureRects(p, extent: e)
            z.append(iz)
            z.append(enc)
            z.append(contentsOf: cornerZones(p, extent: e))

        case .novelObject:
            for key in ["objA", "objB"] {
                guard let c = marker(key) else { continue }
                let label = key == "objA" ? "A" : "B"
                let isNovel = phase != "Training" && p.novelObject == label
                let title = phase == "Training" ? L("Object \(label)", "物体 \(label)") : (isNovel ? L("Novel \(label)", "新 \(label)") : L("Familiar \(label)", "旧 \(label)"))
                let role: ZoneRole = phase == "Training" ? .object : (isNovel ? .novel : .familiar)
                z.append(Zone.circle(key, title, role, c, p.objectRadius))
                var ex = Zone.circle(key + "_explore", "", role, c, p.objectRadius + p.exploreMargin)
                ex.showsLabel = false
                ex.outlineOnly = true
                z.append(ex)
            }

        case .lightDark:
            let f = clamp(p.lightFraction, 0.1, 0.9)
            let lw = e.x * f
            if p.lightOnLeft {
                z.append(Zone.rect("light", L("Light compartment", "明箱"), .light, x: 0, y: 0, w: lw, h: e.y))
                z.append(Zone.rect("dark", L("Dark compartment", "暗箱"), .dark, x: lw, y: 0, w: e.x - lw, h: e.y))
            } else {
                z.append(Zone.rect("dark", L("Dark compartment", "暗箱"), .dark, x: 0, y: 0, w: e.x - lw, h: e.y))
                z.append(Zone.rect("light", L("Light compartment", "明箱"), .light, x: e.x - lw, y: 0, w: lw, h: e.y))
            }

        case .looming:
            if let c = marker("shelter") {
                z.append(Zone.circle("shelter", L("Shelter", "巢穴"), .shelter, c, p.shelterRadius))
            }

        case .barnesMaze:
            if let b = BarnesGeometry.from(cal, params: p, mapping: mapping) {
                // Target quadrant (±45° around the target).
                let a0 = atan2(b.holes[0].y - b.center.y, b.holes[0].x - b.center.x)
                var quad: [V2] = [b.center]
                for k in 0...16 {
                    let a = a0 - Double.pi / 4 + Double.pi / 2 * Double(k) / 16
                    quad.append(V2(b.center.x + b.radius * cos(a), b.center.y + b.radius * sin(a)))
                }
                var q = Zone(id: "quadrant", title: L("Target quadrant", "目标象限"), role: .quadrant, shape: .polygon(quad))
                q.showsLabel = false
                z.append(q)
                for (i, h) in b.holes.enumerated() {
                    var hz = Zone.circle(i == 0 ? "hole_target" : "hole_\(i)", i == 0 ? L("Target", "目标") : "", i == 0 ? .target : .hole, h, b.holeRadius)
                    hz.showsLabel = i == 0
                    z.append(hz)
                }
            }

        case .elevatedPlusMaze:
            if let m = MazeGeometry.from(cal, mapping: mapping) {
                let openIdx = openArmIndices(p)
                let names = ["N", "E", "S", "W"]
                for i in 0..<min(4, m.ends.count) {
                    let open = openIdx.contains(i)
                    z.append(Zone(id: "arm\(names[i])", title: open ? L("Open arm \(names[i])", "开放臂 \(names[i])") : L("Closed arm \(names[i])", "闭合臂 \(names[i])"), role: open ? .open : .closed, shape: .polygon(m.armPolygon(i))))
                }
                z.append(Zone(id: "center", title: L("Center", "中央"), role: .mazeCenter, shape: .polygon(plusCenter(m))))
            }

        case .yMaze:
            if let m = MazeGeometry.from(cal, mapping: mapping) {
                for i in m.ends.indices {
                    z.append(Zone(id: "arm\(m.labels[i])", title: L("Arm \(m.labels[i])", "臂 \(m.labels[i])"), role: .arm, shape: .polygon(m.armPolygon(i))))
                }
                z.append(Zone.circle("center", L("Center", "中央"), .mazeCenter, m.center, m.centerRadius))
            }

        case .tMaze:
            if let m = MazeGeometry.from(cal, mapping: mapping) {
                let titles = [L("Start arm", "起始臂"), L("Left arm", "左臂"), L("Right arm", "右臂")]
                for i in m.ends.indices {
                    z.append(Zone(id: "arm\(m.labels[i])", title: titles[min(i, 2)], role: .arm, shape: .polygon(m.armPolygon(i))))
                }
                z.append(Zone.circle("choice", L("Choice point", "选择点"), .choice, m.center, m.armWidth * max(0.5, p.choiceRadiusFactor)))
            }
        }
        return z
    }

    /// Arm indices (0 = N, 1 = E, 2 = S, 3 = W) that are open in the plus maze.
    static func openArmIndices(_ p: AnalysisParams) -> Set<Int> {
        p.openAxis == "EW" ? [1, 3] : [0, 2]
    }

    /// Center square of the plus maze, oriented by the N–S and E–W axes.
    static func plusCenter(_ m: MazeGeometry) -> [V2] {
        guard m.ends.count == 4 else { return [] }
        let u = (m.ends[0] - m.ends[2]).normalized   // S → N
        let v = (m.ends[1] - m.ends[3]).normalized   // W → E
        let h = m.armWidth / 2
        return [m.center + u * h + v * h, m.center + u * h - v * h, m.center - u * h - v * h, m.center - u * h + v * h]
    }

    /// Enclosure and interaction zone for the social interaction test.
    static func enclosureRects(_ p: AnalysisParams, extent e: V2) -> (Zone, Zone) {
        let ew = p.enclosureWidth, ed = p.enclosureDepth
        let iw = p.izWidth, id = p.izDepth
        switch p.enclosureWall {
        case "bottom":
            return (Zone.rect("enclosure", L("Enclosure", "网罩"), .enclosure, x: (e.x - ew) / 2, y: e.y - ed, w: ew, h: ed),
                    Zone.rect("iz", L("Interaction zone", "互动区"), .interaction, x: (e.x - iw) / 2, y: e.y - id, w: iw, h: id))
        case "left":
            return (Zone.rect("enclosure", L("Enclosure", "网罩"), .enclosure, x: 0, y: (e.y - ew) / 2, w: ed, h: ew),
                    Zone.rect("iz", L("Interaction zone", "互动区"), .interaction, x: 0, y: (e.y - iw) / 2, w: id, h: iw))
        case "right":
            return (Zone.rect("enclosure", L("Enclosure", "网罩"), .enclosure, x: e.x - ed, y: (e.y - ew) / 2, w: ed, h: ew),
                    Zone.rect("iz", L("Interaction zone", "互动区"), .interaction, x: e.x - id, y: (e.y - iw) / 2, w: id, h: iw))
        default:
            return (Zone.rect("enclosure", L("Enclosure", "网罩"), .enclosure, x: (e.x - ew) / 2, y: 0, w: ew, h: ed),
                    Zone.rect("iz", L("Interaction zone", "互动区"), .interaction, x: (e.x - iw) / 2, y: 0, w: iw, h: id))
        }
    }

    /// The two corner zones on the wall opposite the enclosure.
    static func cornerZones(_ p: AnalysisParams, extent e: V2) -> [Zone] {
        let c = p.cornerSize
        switch p.enclosureWall {
        case "bottom":
            return [Zone.rect("corner1", L("Corner", "角落"), .corner, x: 0, y: 0, w: c, h: c), Zone.rect("corner2", L("Corner", "角落"), .corner, x: e.x - c, y: 0, w: c, h: c)]
        case "left":
            return [Zone.rect("corner1", L("Corner", "角落"), .corner, x: e.x - c, y: 0, w: c, h: c), Zone.rect("corner2", L("Corner", "角落"), .corner, x: e.x - c, y: e.y - c, w: c, h: c)]
        case "right":
            return [Zone.rect("corner1", L("Corner", "角落"), .corner, x: 0, y: 0, w: c, h: c), Zone.rect("corner2", L("Corner", "角落"), .corner, x: 0, y: e.y - c, w: c, h: c)]
        default:
            return [Zone.rect("corner1", L("Corner", "角落"), .corner, x: 0, y: e.y - c, w: c, h: c), Zone.rect("corner2", L("Corner", "角落"), .corner, x: e.x - c, y: e.y - c, w: c, h: c)]
        }
    }
}
