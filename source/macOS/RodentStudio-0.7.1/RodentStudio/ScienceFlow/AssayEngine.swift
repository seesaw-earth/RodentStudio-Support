import Foundation

// MARK: - Inputs

/// One 10 Hz tracking sample in arena coordinates (cm). Built from `TrackingPoint` or from a
/// saved `full_tracking.json`, so results can be re-computed later without the video.
struct FlowAnalysisSample: Hashable {
    var t: Double
    var x: Double
    var y: Double
    var detected: Bool
    var zone: String
    var motion: Double?
    var blobArea: Double?
}

/// Shapes in arena centimeters used to draw zones over the trajectory.
struct FlowZoneOverlay: Hashable, Identifiable {
    enum Shape: Hashable {
        case rect(x: Double, y: Double, w: Double, h: Double)
        case circle(cx: Double, cy: Double, r: Double)
        case line(x1: Double, y1: Double, x2: Double, y2: Double)
    }

    enum Role: String, Hashable {
        case center, target, novel, familiar, paired, neutral, dark, open, closed, hole, divider, wall
    }

    var id: String
    var shape: Shape
    var role: Role
    var label: String
}

/// Per-sample freezing decision, exposed for the freezing timeline plot.
struct FlowFreezingTrace {
    var times: [Double]          // protocol time (s)
    var bodyMotionPct: [Double?] // motion as % of body area
    var frozen: [Bool]
    var referenceArea: Double
}

// MARK: - Engine

enum FlowAssayEngine {
    static func compute(assay: FlowAssay, phase: String, samples: [FlowAnalysisSample], config: FlowZoneConfig) -> FlowAssayComputation {
        let sorted = samples.sorted { $0.t < $1.t }
        guard sorted.count >= 3 else {
            var empty = FlowAssayComputation()
            empty.qcFlags.append(flowLoc("Not enough tracking samples to compute results."))
            return empty
        }
        var out: FlowAssayComputation
        switch assay {
        case .openField: out = openField(sorted, config)
        case .elevatedPlusMaze: out = plusMaze(sorted, config)
        case .lightDark: out = lightDark(sorted, config)
        case .placePreference: out = placePreference(sorted, config)
        case .novelObject: out = novelObject(sorted, config)
        case .morrisWaterMaze: out = waterMaze(sorted, config, phase: phase)
        case .barnesMaze: out = barnesMaze(sorted, config)
        case .fearConditioning: out = fearConditioning(sorted, config)
        case .yMaze: out = yMaze(sorted, config)
        case .tMaze: out = tMaze(sorted, config)
        default: out = openField(sorted, config)
        }

        // Shared quality control.
        let detectedFraction = Double(sorted.filter(\.detected).count) / Double(sorted.count)
        out.set("tracked_pct", detectedFraction * 100)
        let tolerant: Set<FlowAssay> = [.lightDark, .fearConditioning, .barnesMaze]
        if detectedFraction < 0.9 && !tolerant.contains(assay) {
            out.qcFlags.append(String(format: flowLoc("Mouse detected in only %.0f%% of samples — check the tracking preview."), detectedFraction * 100))
        }
        out.parameters["tracking"] = flowLoc("classic centroid, 10 Hz")
        out.param("analysis_start_s", config.analysisStartSeconds, decimals: 1)
        if config.analysisDurationSeconds > 0 { out.param("analysis_duration_s", config.analysisDurationSeconds, decimals: 1) }
        return out
    }

    // MARK: Windowing helpers

    struct Window {
        var samples: [FlowAnalysisSample]
        var dt: [Double]
        var start: Double
        var end: Double
        var duration: Double { end - start }
        var detectedTime: Double { zip(samples, dt).reduce(0) { $0 + ($1.0.detected ? $1.1 : 0) } }
    }

    /// Typical sampling interval (median of positive steps).
    static func nominalStep(_ s: [FlowAnalysisSample]) -> Double {
        var steps: [Double] = []
        steps.reserveCapacity(min(s.count, 2000))
        var i = 1
        let stride = max(1, s.count / 2000)
        while i < s.count {
            let d = s[i].t - s[i - 1].t
            if d > 0 { steps.append(d) }
            i += stride
        }
        let m = FlowStats.quantile(steps, 0.5)
        return m.isFinite && m > 0 ? m : 0.1
    }

    /// Samples inside [start, end) with the time each one represents (until the next sample,
    /// capped at 5 sampling intervals so gaps in the video do not inflate zone times).
    static func window(_ s: [FlowAnalysisSample], startOffset: Double, duration: Double?) -> Window {
        let base = s.first?.t ?? 0
        let start = base + max(0, startOffset)
        let step = nominalStep(s)
        let lastT = (s.last?.t ?? base) + step
        var end = lastT
        if let duration, duration > 0 { end = min(lastT, start + duration) }
        var samples: [FlowAnalysisSample] = []
        var dts: [Double] = []
        for i in s.indices where s[i].t >= start && s[i].t < end {
            let next = i + 1 < s.count ? s[i + 1].t : s[i].t + step
            let dt = max(0, min(next, end) - s[i].t)
            samples.append(s[i])
            dts.append(min(dt, 5 * step))
        }
        return Window(samples: samples, dt: dts, start: start, end: max(start, end))
    }

    /// Path length between consecutive detected samples (same rule as v1.0 summaries).
    static func distance(_ w: [FlowAnalysisSample], where include: ((FlowAnalysisSample) -> Bool)? = nil) -> Double {
        guard w.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<w.count {
            let a = w[i - 1], b = w[i]
            guard a.detected, b.detected else { continue }
            if let include, !include(b) { continue }
            total += hypot(b.x - a.x, b.y - a.y)
        }
        return total
    }

    /// Central-difference speed (cm/s) where the sample and both neighbors are detected.
    static func speeds(_ w: [FlowAnalysisSample]) -> [Double?] {
        guard w.count >= 3 else { return Array(repeating: nil, count: w.count) }
        var out = [Double?](repeating: nil, count: w.count)
        for i in 1..<(w.count - 1) {
            let a = w[i - 1], b = w[i], c = w[i + 1]
            guard a.detected, b.detected, c.detected else { continue }
            let dt = c.t - a.t
            guard dt > 0 else { continue }
            out[i] = hypot(c.x - a.x, c.y - a.y) / dt
        }
        return out
    }

    struct ZoneEntry: Hashable {
        var time: Double
        var zone: String
        var initial: Bool
    }

    /// Debounced zone transitions: a new zone is committed after it has been occupied for at
    /// least `minDwell` seconds. `nil` states (mouse not seen) keep the current zone.
    static func zoneEntries(_ states: [String?], times: [Double], minDwell: Double) -> [ZoneEntry] {
        var committed: String?
        var candidate: String?
        var candidateStart = 0.0
        var out: [ZoneEntry] = []
        for i in states.indices {
            guard let z = states[i] else { continue }
            if z == committed {
                candidate = nil
                continue
            }
            if z != candidate {
                candidate = z
                candidateStart = times[i]
            }
            if times[i] - candidateStart >= minDwell - 1e-9 {
                out.append(ZoneEntry(time: candidateStart, zone: z, initial: committed == nil))
                committed = z
                candidate = nil
            }
        }
        return out
    }

    static func timeIn(_ w: Window, states: [String?], zone: String) -> Double {
        var total = 0.0
        for i in states.indices where states[i] == zone { total += w.dt[i] }
        return total
    }

    static func pct(_ part: Double, _ whole: Double) -> Double? {
        whole > 0 ? part / whole * 100 : nil
    }

    // MARK: Open field

    static func centerContains(_ p: FlowAnalysisSample, _ c: FlowZoneConfig) -> Bool {
        let f = min(0.98, max(0.05, c.centerFraction))
        if c.arenaShape == .circle {
            let r = c.arenaWidthCM / 2
            return hypot(p.x - r, p.y - r) <= f * r
        }
        let w = c.arenaWidthCM, h = c.arenaHeightCM
        return abs(p.x - w / 2) <= f * w / 2 && abs(p.y - h / 2) <= f * h / 2
    }

    static func openField(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        guard !w.samples.isEmpty else { return out }
        let dist = distance(w.samples)
        out.set("distance_m", dist / 100)
        out.set("mean_speed_cms", w.duration > 0 ? dist / w.duration : nil)

        // Mobility from central-difference speed.
        let v = speeds(w.samples)
        var known = 0.0, mobile = 0.0, immobile = 0.0, run = 0.0
        for i in v.indices {
            guard let speed = v[i] else {
                if run >= c.immobilityMinSeconds { immobile += run }
                run = 0
                continue
            }
            known += w.dt[i]
            if speed >= c.movingSpeedCMs {
                mobile += w.dt[i]
                if run >= c.immobilityMinSeconds { immobile += run }
                run = 0
            } else {
                run += w.dt[i]
            }
        }
        if run >= c.immobilityMinSeconds { immobile += run }
        out.set("mobile_time_pct", pct(mobile, known))
        out.set("immobile_time_s", immobile)

        // Center zone.
        let states: [String?] = w.samples.map { $0.detected ? (centerContains($0, c) ? "center" : "periphery") : nil }
        let centerTime = timeIn(w, states: states, zone: "center")
        let detectedTime = w.detectedTime
        out.set("center_time_s", centerTime)
        out.set("center_time_pct", pct(centerTime, detectedTime))
        let entries = zoneEntries(states, times: w.samples.map(\.t), minDwell: c.entryMinSeconds)
        out.set("center_entries", Double(entries.filter { !$0.initial && $0.zone == "center" }.count))
        if let first = entries.first(where: { $0.zone == "center" }) {
            out.set("center_latency_s", first.initial ? 0 : first.time - w.start)
        } else {
            out.set("center_latency_s", w.duration)
        }
        let centerDistance = distance(w.samples) { centerContains($0, c) }
        out.set("center_distance_pct", pct(centerDistance, dist))

        // Time bins.
        let bin = max(10, c.timeBinSeconds)
        let binCount = max(1, Int(ceil(w.duration / bin - 1e-9)))
        if binCount >= 2 {
            var binDistance = [Double](repeating: 0, count: binCount)
            var binCenter = [Double](repeating: 0, count: binCount)
            var binDetected = [Double](repeating: 0, count: binCount)
            for i in w.samples.indices {
                let b = min(binCount - 1, Int((w.samples[i].t - w.start) / bin))
                if w.samples[i].detected {
                    binDetected[b] += w.dt[i]
                    if states[i] == "center" { binCenter[b] += w.dt[i] }
                }
                if i > 0, w.samples[i].detected, w.samples[i - 1].detected {
                    binDistance[b] += hypot(w.samples[i].x - w.samples[i - 1].x, w.samples[i].y - w.samples[i - 1].y)
                }
            }
            let xs = (0..<binCount).map { Double($0 + 1) * bin / 60 }
            out.addSeries("distance_by_bin", "Distance per bin", unit: "m", xLabel: "Time (min)", x: xs, y: binDistance.map { $0 / 100 })
            out.addSeries("center_pct_by_bin", "Center time per bin", unit: "%", xLabel: "Time (min)", x: xs,
                          y: zip(binCenter, binDetected).map { $1 > 0 ? $0 / $1 * 100 : .nan })
        }

        out.param("center_fraction", c.centerFraction)
        out.param("moving_threshold_cm_s", c.movingSpeedCMs)
        out.param("immobility_min_s", c.immobilityMinSeconds)
        out.param("entry_min_s", c.entryMinSeconds)
        out.param("time_bin_s", bin, decimals: 0)
        out.parameters["center_zone"] = c.arenaShape == .circle
            ? String(format: flowLoc("concentric circle, radius = %.0f%% of arena radius"), c.centerFraction * 100)
            : String(format: flowLoc("concentric rectangle, sides = %.0f%% of arena sides (%.0f%% of area)"), c.centerFraction * 100, c.centerFraction * c.centerFraction * 100)
        return out
    }

    // MARK: Elevated plus maze

    static func plusZone(_ p: FlowAnalysisSample, _ c: FlowZoneConfig) -> String {
        let w = max(1, c.plusArmWidthCM)
        let mid = c.plusArmLengthCM + w
        let px = p.x - mid, py = p.y - mid
        let half = w / 2 + max(0, c.plusCenterMarginCM)
        if abs(px) <= half && abs(py) <= half { return "center" }
        if abs(py) >= abs(px) { return py < 0 ? "N" : "S" }
        return px > 0 ? "E" : "W"
    }

    static func openArms(_ c: FlowZoneConfig) -> Set<String> { c.plusOpenAxis == "EW" ? ["E", "W"] : ["N", "S"] }

    static func plusMaze(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        guard !w.samples.isEmpty else { return out }
        let open = openArms(c)
        let zones: [String?] = w.samples.map { $0.detected ? plusZone($0, c) : nil }
        var openTime = 0.0, closedTime = 0.0, centerTime = 0.0
        for i in zones.indices {
            guard let z = zones[i] else { continue }
            if z == "center" { centerTime += w.dt[i] } else if open.contains(z) { openTime += w.dt[i] } else { closedTime += w.dt[i] }
        }
        let entries = zoneEntries(zones, times: w.samples.map(\.t), minDwell: c.entryMinSeconds)
        let armEntries = entries.filter { $0.zone != "center" }
        let openEntries = armEntries.filter { open.contains($0.zone) }.count
        let closedEntries = armEntries.count - openEntries
        out.set("open_time_s", openTime)
        out.set("closed_time_s", closedTime)
        out.set("center_time_s", centerTime)
        out.set("open_time_pct", pct(openTime, openTime + closedTime))
        out.set("open_entries", Double(openEntries))
        out.set("closed_entries", Double(closedEntries))
        out.set("total_entries", Double(armEntries.count))
        out.set("open_entries_pct", pct(Double(openEntries), Double(armEntries.count)))
        if let first = armEntries.first(where: { open.contains($0.zone) }) {
            out.set("open_latency_s", max(0, first.time - w.start))
        } else {
            out.set("open_latency_s", w.duration)
        }
        out.set("distance_m", distance(w.samples) / 100)
        out.labels["arm_sequence"] = armEntries.map { open.contains($0.zone) ? "O\($0.zone)" : "C\($0.zone)" }.joined(separator: " ")
        out.parameters["open_arms"] = c.plusOpenAxis == "EW" ? flowLoc("E/W (image left/right)") : flowLoc("N/S (image top/bottom)")
        out.param("arm_length_cm", c.plusArmLengthCM, decimals: 1)
        out.param("arm_width_cm", c.plusArmWidthCM, decimals: 1)
        out.param("entry_min_s", c.entryMinSeconds)
        return out
    }

    // MARK: Light–dark box

    static func isLight(_ p: FlowAnalysisSample, _ c: FlowZoneConfig) -> Bool {
        let f = min(1, max(0.05, c.lightFraction))
        return c.lightOnLeft ? p.x <= f * c.arenaWidthCM : p.x >= (1 - f) * c.arenaWidthCM
    }

    static func lightDark(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        guard !w.samples.isEmpty else { return out }
        let states: [String?] = w.samples.map { p in
            if p.detected { return isLight(p, c) ? "light" : "dark" }
            return c.undetectedIsDark ? "dark" : nil
        }
        let light = timeIn(w, states: states, zone: "light")
        let dark = timeIn(w, states: states, zone: "dark")
        out.set("light_time_s", light)
        out.set("dark_time_s", dark)
        out.set("light_time_pct", pct(light, light + dark))
        let entries = zoneEntries(states, times: w.samples.map(\.t), minDwell: c.entryMinSeconds)
        out.set("transitions", Double(entries.filter { !$0.initial }.count))
        if let first = entries.first(where: { $0.zone == "dark" }) {
            out.set("latency_dark_s", first.initial ? 0 : first.time - w.start)
        } else {
            out.set("latency_dark_s", w.duration)
        }
        out.set("light_distance_m", distance(w.samples) { isLight($0, c) } / 100)
        out.param("light_fraction", c.lightFraction)
        out.parameters["light_side"] = c.lightOnLeft ? "left" : "right"
        out.parameters["unseen_samples"] = c.undetectedIsDark ? "counted as dark" : "excluded"
        out.param("entry_min_s", c.entryMinSeconds)
        return out
    }

    // MARK: Conditioned place preference

    static func cppChamber(_ p: FlowAnalysisSample, _ c: FlowZoneConfig) -> String {
        let x = p.x / max(1e-9, c.arenaWidthCM)
        if c.cppChambers >= 3 {
            let n = min(0.8, max(0.02, c.cppNeutralFraction))
            if x < (1 - n) / 2 { return "left" }
            if x > (1 + n) / 2 { return "right" }
            return "neutral"
        }
        return x < c.cppDivider ? "left" : "right"
    }

    static func placePreference(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        guard !w.samples.isEmpty else { return out }
        let pairedSide = c.cppPairedOnLeft ? "left" : "right"
        let unpairedSide = c.cppPairedOnLeft ? "right" : "left"
        let states: [String?] = w.samples.map { $0.detected ? cppChamber($0, c) : nil }
        let paired = timeIn(w, states: states, zone: pairedSide)
        let unpaired = timeIn(w, states: states, zone: unpairedSide)
        let neutral = timeIn(w, states: states, zone: "neutral")
        out.set("paired_time_s", paired)
        out.set("unpaired_time_s", unpaired)
        if c.cppChambers >= 3 { out.set("neutral_time_s", neutral) }
        out.set("preference_score_s", paired - unpaired)
        out.set("preference_pct", pct(paired, paired + unpaired))
        let entries = zoneEntries(states, times: w.samples.map(\.t), minDwell: c.entryMinSeconds)
        out.set("paired_entries", Double(entries.filter { !$0.initial && $0.zone == pairedSide }.count))
        out.set("distance_m", distance(w.samples) / 100)
        out.parameters["paired_side"] = pairedSide
        out.parameters["chambers"] = "\(c.cppChambers)"
        out.param("entry_min_s", c.entryMinSeconds)
        return out
    }

    // MARK: Novel object recognition

    static func objectState(_ p: FlowAnalysisSample, _ c: FlowZoneConfig) -> String {
        guard let a = c.objectA, let b = c.objectB else { return "none" }
        let r = max(0.5, c.objectZoneRadiusCM)
        let da = hypot(p.x - a.x, p.y - a.y)
        let db = hypot(p.x - b.x, p.y - b.y)
        if da <= r && da <= db { return "A" }
        if db <= r { return "B" }
        return "none"
    }

    static func novelObject(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        guard !w.samples.isEmpty else { return out }
        out.set("distance_m", distance(w.samples) / 100)
        guard c.objectA != nil, c.objectB != nil else {
            out.qcFlags.append(flowLoc("Object positions are not set."))
            return out
        }
        let states: [String?] = w.samples.map { $0.detected ? objectState($0, c) : nil }
        let timeA = timeIn(w, states: states, zone: "A")
        let timeB = timeIn(w, states: states, zone: "B")
        let novelIsA = c.novelObject == "A"
        let novel = novelIsA ? timeA : timeB
        let familiar = novelIsA ? timeB : timeA
        let total = novel + familiar
        out.set("novel_time_s", novel)
        out.set("familiar_time_s", familiar)
        out.set("total_exploration_s", total)
        if total > 0 {
            out.set("discrimination_index", (novel - familiar) / total)
            out.set("recognition_index_pct", novel / total * 100)
        }
        let entries = zoneEntries(states, times: w.samples.map(\.t), minDwell: c.entryMinSeconds)
        let novelKey = novelIsA ? "A" : "B"
        let familiarKey = novelIsA ? "B" : "A"
        out.set("novel_bouts", Double(entries.filter { $0.zone == novelKey }.count))
        out.set("familiar_bouts", Double(entries.filter { $0.zone == familiarKey }.count))
        if let first = entries.first(where: { $0.zone == "A" || $0.zone == "B" }) {
            out.set("first_approach_latency_s", max(0, first.time - w.start))
        }
        if total < c.minTotalExplorationSeconds {
            out.qcFlags.append(String(format: flowLoc("Low exploration: %.1f s total (criterion %.0f s)."), total, c.minTotalExplorationSeconds))
        }
        out.parameters["novel_object"] = novelKey
        out.param("interaction_radius_cm", c.objectZoneRadiusCM, decimals: 1)
        out.param("min_total_exploration_s", c.minTotalExplorationSeconds, decimals: 1)
        out.param("entry_min_s", c.entryMinSeconds)
        out.parameters["exploration_rule"] = flowLoc("body centroid within interaction radius of object center")
        return out
    }

    // MARK: Circular arenas: water maze / Barnes

    /// Signed angle difference wrapped to (−π, π].
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > Double.pi { d -= 2 * Double.pi }
        while d <= -Double.pi { d += 2 * Double.pi }
        return d
    }

    static func quadrant(_ p: FlowAnalysisSample, center: (Double, Double), targetAngle: Double) -> String {
        let a = atan2(p.y - center.1, p.x - center.0)
        let d = abs(angleDelta(a, targetAngle))
        if d <= Double.pi / 4 { return "target" }
        if d >= 3 * Double.pi / 4 { return "opposite" }
        return "adjacent"
    }

    static func waterMaze(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig, phase: String) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let maxTrial = max(1, c.maxTrialSeconds)
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds > 0 ? c.analysisDurationSeconds : maxTrial)
        guard !w.samples.isEmpty else { return out }
        let r = c.arenaWidthCM / 2
        let center = (r, r)
        guard let target = c.target else {
            out.qcFlags.append(flowLoc("Platform position is not set."))
            out.set("path_length_m", distance(w.samples) / 100)
            return out
        }
        let isProbe = phase == "Probe"
        let rp = max(0.5, c.targetRadiusCM)
        let inPlatform: (FlowAnalysisSample) -> Bool = { hypot($0.x - target.x, $0.y - target.y) <= rp }

        // Escape: first moment from which the (possibly held) position stays on the platform.
        var escapeIndex: Int?
        if !isProbe {
            var i = 0
            while i < w.samples.count {
                if w.samples[i].detected && inPlatform(w.samples[i]) {
                    var j = i
                    var stayed = true
                    while j < w.samples.count && w.samples[j].t - w.samples[i].t < c.platformStaySeconds {
                        if !inPlatform(w.samples[j]) { stayed = false; break }
                        j += 1
                    }
                    let reachedEnd = j >= w.samples.count
                    if stayed && (!reachedEnd || w.end - w.samples[i].t >= c.platformStaySeconds * 0.5) {
                        escapeIndex = i
                        break
                    }
                }
                i += 1
            }
        }

        let swimSamples: [FlowAnalysisSample]
        let swimDT: [Double]
        if let e = escapeIndex {
            swimSamples = Array(w.samples[..<max(1, e)])
            swimDT = Array(w.dt[..<max(1, e)])
            let latency = w.samples[e].t - w.start
            out.set("escape_latency_s", latency)
            out.set("found_platform_pct", 100)
        } else {
            swimSamples = w.samples
            swimDT = w.dt
            if !isProbe {
                out.set("escape_latency_s", min(maxTrial, w.duration))
                out.set("found_platform_pct", 0)
                out.qcFlags.append(String(format: flowLoc("Platform not reached within %.0f s (latency set to the trial maximum)."), min(maxTrial, w.duration)))
            }
        }
        let swimWindow = Window(samples: swimSamples, dt: swimDT, start: w.start,
                                end: escapeIndex.map { w.samples[$0].t } ?? w.end)
        let path = distance(swimSamples)
        out.set("path_length_m", path / 100)
        if swimWindow.duration > 0 { out.set("swim_speed_cms", path / swimWindow.duration) }

        // Spatial measures over the swim period (probe: whole window).
        let targetAngle = atan2(target.y - center.1, target.x - center.0)
        var detectedTime = 0.0, targetQ = 0.0, oppositeQ = 0.0, wallTime = 0.0, distSum = 0.0, distCount = 0.0
        for i in swimSamples.indices where swimSamples[i].detected {
            let p = swimSamples[i]
            let dt = swimDT[i]
            detectedTime += dt
            switch quadrant(p, center: center, targetAngle: targetAngle) {
            case "target": targetQ += dt
            case "opposite": oppositeQ += dt
            default: break
            }
            if hypot(p.x - center.0, p.y - center.1) >= r - c.wallZoneCM { wallTime += dt }
            distSum += hypot(p.x - target.x, p.y - target.y)
            distCount += 1
        }
        out.set("target_quadrant_pct", pct(targetQ, detectedTime))
        out.set("opposite_quadrant_pct", pct(oppositeQ, detectedTime))
        out.set("thigmotaxis_pct", pct(wallTime, detectedTime))
        if distCount > 0 { out.set("mean_platform_distance_cm", distSum / distCount) }

        // Platform-zone crossings (any entry, no dwell requirement).
        var crossings = 0
        var firstCrossing: Double?
        var inside: Bool?
        for p in w.samples where p.detected {
            let now = inPlatform(p)
            if now && inside != true {
                crossings += 1
                if firstCrossing == nil { firstCrossing = p.t - w.start }
            }
            inside = now
        }
        out.set("platform_crossings", Double(crossings))
        out.set("first_crossing_latency_s", firstCrossing ?? w.duration)

        out.parameters["trial_type"] = isProbe ? "probe" : "acquisition"
        out.param("platform_radius_cm", rp, decimals: 1)
        out.param("max_trial_s", maxTrial, decimals: 0)
        out.param("platform_stay_s", c.platformStaySeconds, decimals: 1)
        out.param("wall_zone_cm", c.wallZoneCM, decimals: 1)
        return out
    }

    struct HoleLayout {
        var center: (Double, Double)
        var ringRadius: Double
        var targetAngle: Double
        var count: Int
        func position(_ k: Int) -> (Double, Double) {
            let a = targetAngle + 2 * Double.pi * Double(k) / Double(count)
            return (center.0 + ringRadius * cos(a), center.1 + ringRadius * sin(a))
        }
        /// Signed hole offset from the target: 0 = target, ±1 = adjacent, …
        func offset(_ k: Int) -> Int { k <= count / 2 ? k : k - count }
    }

    static func holeLayout(_ c: FlowZoneConfig) -> HoleLayout? {
        guard let t = c.target else { return nil }
        let r = c.arenaWidthCM / 2
        let ring = hypot(t.x - r, t.y - r)
        guard ring > 0.1 * r else { return nil }
        return HoleLayout(center: (r, r), ringRadius: ring, targetAngle: atan2(t.y - r, t.x - r), count: max(4, c.holeCount))
    }

    static func barnesMaze(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let maxTrial = max(1, c.maxTrialSeconds)
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds > 0 ? c.analysisDurationSeconds : maxTrial)
        guard !w.samples.isEmpty else { return out }
        guard let layout = holeLayout(c) else {
            out.qcFlags.append(flowLoc("Target hole is not set (or too close to the center)."))
            out.set("mean_speed_cms", w.duration > 0 ? distance(w.samples) / w.duration : nil)
            return out
        }
        let zoneR = max(0.5, c.targetRadiusCM)
        let holes = (0..<layout.count).map { layout.position($0) }
        let states: [String?] = w.samples.map { p in
            guard p.detected else { return nil }
            var best: Int?
            var bestD = Double.infinity
            for (k, h) in holes.enumerated() {
                let d = hypot(p.x - h.0, p.y - h.1)
                if d <= zoneR && d < bestD { best = k; bestD = d }
            }
            return best.map { "h\($0)" } ?? "platform"
        }

        // Escape: mouse disappears for ≥ 3 s after being seen near the target hole.
        var endTime = w.end
        var escapeLatency: Double?
        if let lastSeen = w.samples.lastIndex(where: { $0.detected }) {
            let p = w.samples[lastSeen]
            let unseenAfter = w.end - p.t
            if unseenAfter >= 3, hypot(p.x - holes[0].0, p.y - holes[0].1) <= 2 * zoneR {
                escapeLatency = p.t - w.start
                endTime = p.t + 0.001
            }
        }
        var trimmed: [FlowAnalysisSample] = []
        var trimmedDT: [Double] = []
        var trimmedStates: [String?] = []
        for i in w.samples.indices where w.samples[i].t < endTime {
            trimmed.append(w.samples[i])
            trimmedDT.append(w.dt[i])
            trimmedStates.append(states[i])
        }

        let entries = zoneEntries(trimmedStates, times: trimmed.map(\.t), minDwell: c.entryMinSeconds)
        let visits = entries.compactMap { e -> (Int, Double)? in
            guard e.zone.hasPrefix("h"), let k = Int(e.zone.dropFirst()) else { return nil }
            return (k, e.time)
        }
        let firstTarget = visits.first { $0.0 == 0 }
        let primaryLatency = firstTarget.map { $0.1 - w.start }
        let preTarget = visits.prefix { $0.0 != 0 }
        out.set("primary_latency_s", primaryLatency ?? min(maxTrial, endTime - w.start))
        out.set("primary_errors", Double(firstTarget == nil ? visits.count : preTarget.count))
        out.set("total_errors", Double(visits.filter { $0.0 != 0 }.count))
        if firstTarget == nil {
            out.qcFlags.append(flowLoc("Target hole not visited within the trial."))
        }
        let pathEnd = firstTarget?.1 ?? endTime
        out.set("path_length_m", distance(trimmed.filter { $0.t <= pathEnd }) / 100)
        let trimmedDuration = max(0, endTime - w.start)
        if trimmedDuration > 0 { out.set("mean_speed_cms", distance(trimmed) / trimmedDuration) }
        if let escapeLatency { out.set("escape_latency_s", escapeLatency) }

        var detectedTime = 0.0, targetQ = 0.0, oppositeQ = 0.0, distSum = 0.0, n = 0.0
        for i in trimmed.indices where trimmed[i].detected {
            let p = trimmed[i]
            detectedTime += trimmedDT[i]
            switch quadrant(p, center: layout.center, targetAngle: layout.targetAngle) {
            case "target": targetQ += trimmedDT[i]
            case "opposite": oppositeQ += trimmedDT[i]
            default: break
            }
            distSum += hypot(p.x - holes[0].0, p.y - holes[0].1)
            n += 1
        }
        out.set("target_quadrant_pct", pct(targetQ, detectedTime))
        out.set("opposite_quadrant_pct", pct(oppositeQ, detectedTime))
        if n > 0 { out.set("mean_target_distance_cm", distSum / n) }

        // Search strategy (rule-based, display only).
        // Direct: target first, or at most two checks of holes adjacent to it.
        // Serial: at least three consecutive adjacent holes visited in one direction (target included).
        // Random: anything else.
        let offsets = preTarget.map { layout.offset($0.0) }
        var strategy = "Random"
        if firstTarget != nil && (offsets.isEmpty || (offsets.count <= 2 && offsets.allSatisfy { abs($0) <= 1 })) {
            strategy = "Direct"
        } else {
            let sequence = offsets + (firstTarget != nil ? [0] : [])
            var longest = 0, current = 0, lastStep = 0
            if sequence.count >= 2 {
                for i in 1..<sequence.count {
                    let step = sequence[i] - sequence[i - 1]
                    if abs(step) == 1 {
                        current = step == lastStep ? current + 1 : 1
                        lastStep = step
                    } else {
                        current = 0
                        lastStep = 0
                    }
                    longest = max(longest, current)
                }
            }
            if longest >= 2 { strategy = "Serial" }
        }
        if firstTarget != nil || !offsets.isEmpty { out.labels["search_strategy"] = strategy }
        out.labels["hole_visits"] = visits.map { $0.0 == 0 ? "T" : String(layout.offset($0.0)) }.joined(separator: " ")
        out.param("hole_count", Double(layout.count), decimals: 0)
        out.param("hole_zone_radius_cm", zoneR, decimals: 1)
        out.param("max_trial_s", maxTrial, decimals: 0)
        out.param("entry_min_s", c.entryMinSeconds)
        out.parameters["error_rule"] = flowLoc("body-centroid visit to a non-target hole zone (proxy for nose pokes)")
        return out
    }

    // MARK: Fear conditioning

    static func freezingTrace(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowFreezingTrace {
        let areas = s.compactMap { $0.detected ? $0.blobArea : nil }.filter { $0 > 0 }
        var reference = FlowStats.quantile(areas, 0.5)
        if !reference.isFinite || reference <= 0 { reference = 0.012 }
        let base = (s.first?.t ?? 0) + c.protocolOffsetSeconds
        let times = s.map { $0.t - base }
        let motion: [Double?] = s.map { p in p.motion.map { $0 / reference * 100 } }
        let step = nominalStep(s)
        var frozen = [Bool](repeating: false, count: s.count)
        var i = 0
        while i < s.count {
            guard let m = motion[i], m < c.freezeThresholdPct else { i += 1; continue }
            _ = m
            var j = i
            while j < s.count, let mj = motion[j], mj < c.freezeThresholdPct { j += 1 }
            let runEnd = j < s.count ? s[j].t : s[s.count - 1].t + step
            if runEnd - s[i].t >= c.freezeMinSeconds - 1e-9 {
                for k in i..<j { frozen[k] = true }
            }
            i = j
        }
        return FlowFreezingTrace(times: times, bodyMotionPct: motion, frozen: frozen, referenceArea: reference)
    }

    static func fearConditioning(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        guard s.contains(where: { $0.motion != nil }) else {
            out.qcFlags.append(flowLoc("This tracking run has no motion index. Re-analyze the video with RodentFlow 1.1 or later."))
            return out
        }
        let trace = freezingTrace(s, c)
        let step = nominalStep(s)
        var dt = [Double](repeating: step, count: s.count)
        for i in 0..<(s.count - 1) { dt[i] = min(5 * step, max(0, s[i + 1].t - s[i].t)) }
        let sessionEnd = c.analysisDurationSeconds > 0 ? c.analysisDurationSeconds : (trace.times.last ?? 0) + step

        func freezingPct(_ from: Double, _ to: Double) -> Double? {
            var total = 0.0, frozen = 0.0
            for i in trace.times.indices where trace.times[i] >= from && trace.times[i] < to {
                total += dt[i]
                if trace.frozen[i] { frozen += dt[i] }
            }
            return total > 0 ? frozen / total * 100 : nil
        }

        out.set("freezing_pct", freezingPct(0, sessionEnd))
        let onsets = c.csOnsetsSeconds.filter { $0 >= 0 }.sorted()
        if c.baselineSeconds > 0 {
            out.set("baseline_freezing_pct", freezingPct(0, min(c.baselineSeconds, onsets.first ?? c.baselineSeconds)))
        }
        if !onsets.isEmpty {
            let perCS = onsets.map { freezingPct($0, $0 + c.csDurationSeconds) }
            let valid = perCS.compactMap { $0 }
            if !valid.isEmpty { out.set("cs_freezing_pct", FlowStats.mean(valid)) }
            out.addSeries("freezing_by_cs", "Freezing per CS", unit: "%", xLabel: "CS",
                          x: onsets.indices.map { Double($0 + 1) }, y: perCS.map { $0 ?? .nan })
            // ITI: after the first CS onset, outside CS windows.
            var total = 0.0, frozen = 0.0
            for i in trace.times.indices {
                let t = trace.times[i]
                guard t >= onsets[0], t < sessionEnd else { continue }
                if onsets.contains(where: { t >= $0 && t < $0 + c.csDurationSeconds }) { continue }
                total += dt[i]
                if trace.frozen[i] { frozen += dt[i] }
            }
            out.set("iti_freezing_pct", pct(frozen, total))
        }

        // Bouts within the session window.
        var bouts: [Double] = []
        var i = 0
        while i < trace.frozen.count {
            guard trace.frozen[i], trace.times[i] >= 0, trace.times[i] < sessionEnd else { i += 1; continue }
            var j = i
            var length = 0.0
            while j < trace.frozen.count && trace.frozen[j] && trace.times[j] < sessionEnd {
                length += dt[j]
                j += 1
            }
            bouts.append(length)
            i = j
        }
        out.set("freezing_bouts", Double(bouts.count))
        if !bouts.isEmpty { out.set("mean_bout_s", FlowStats.mean(bouts)) }

        let bin = max(10, c.fearBinSeconds)
        let binCount = Int(ceil(sessionEnd / bin - 1e-9))
        if binCount >= 2 {
            let xs = (0..<binCount).map { Double($0 + 1) * bin / 60 }
            let ys = (0..<binCount).map { freezingPct(Double($0) * bin, Double($0 + 1) * bin) ?? .nan }
            out.addSeries("freezing_by_bin", "Freezing per bin", unit: "%", xLabel: "Time (min)", x: xs, y: ys)
        }

        out.param("freeze_threshold_pct_body", c.freezeThresholdPct, decimals: 1)
        out.param("freeze_min_bout_s", c.freezeMinSeconds, decimals: 2)
        out.param("reference_body_area_fraction", trace.referenceArea, decimals: 4)
        out.param("protocol_offset_s", c.protocolOffsetSeconds, decimals: 1)
        out.param("baseline_s", c.baselineSeconds, decimals: 0)
        if !onsets.isEmpty {
            out.parameters["cs_onsets_s"] = onsets.map { String(format: "%.0f", $0) }.joined(separator: ",")
            out.param("cs_duration_s", c.csDurationSeconds, decimals: 0)
        }
        out.parameters["motion_pixel_delta"] = flowLoc("20 gray levels (full range) between consecutive 10 Hz frames")
        return out
    }

    // MARK: T / Y maze

    static func mazeEntries(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig, arms: Set<String>, allowed: Set<String>) -> (Window, [ZoneEntry]) {
        let w = window(s, startOffset: c.analysisStartSeconds, duration: c.analysisDurationSeconds)
        let states: [String?] = w.samples.map { ($0.detected && allowed.contains($0.zone)) ? $0.zone : nil }
        let entries = zoneEntries(states, times: w.samples.map(\.t), minDwell: c.mazeEntryMinSeconds).filter { arms.contains($0.zone) }
        return (w, entries)
    }

    static func yMaze(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let (w, entries) = mazeEntries(s, c, arms: ["A", "B", "C"], allowed: ["center", "A", "B", "C"])
        let seq = entries.map(\.zone)
        out.set("arm_entries", Double(seq.count))
        if seq.count >= 3 {
            var ok = 0
            for i in 2..<seq.count where Set([seq[i - 2], seq[i - 1], seq[i]]).count == 3 { ok += 1 }
            out.set("alternations", Double(ok))
            out.set("alternation_pct", Double(ok) / Double(seq.count - 2) * 100)
        } else {
            out.qcFlags.append(flowLoc("Fewer than 3 arm entries — alternation cannot be computed."))
        }
        out.set("distance_m", distance(w.samples) / 100)
        out.labels["arm_sequence"] = seq.joined(separator: "")
        out.param("entry_min_s", c.mazeEntryMinSeconds)
        return out
    }

    static func tMaze(_ s: [FlowAnalysisSample], _ c: FlowZoneConfig) -> FlowAssayComputation {
        var out = FlowAssayComputation()
        let (w, entries) = mazeEntries(s, c, arms: ["left", "right"], allowed: ["start", "center", "left", "right"])
        let left = entries.filter { $0.zone == "left" }.count
        let right = entries.filter { $0.zone == "right" }.count
        out.set("left_entries", Double(left))
        out.set("right_entries", Double(right))
        out.set("arm_entries", Double(left + right))
        if let first = entries.first {
            out.set("right_choice_pct", first.zone == "right" ? 100 : 0)
            out.set("choice_latency_s", max(0, first.time - w.start))
            out.labels["first_choice"] = first.zone
        } else {
            out.qcFlags.append(flowLoc("No choice-arm entry detected."))
        }
        out.set("distance_m", distance(w.samples) / 100)
        out.labels["arm_sequence"] = entries.map { $0.zone == "left" ? "L" : "R" }.joined(separator: "")
        out.param("entry_min_s", c.mazeEntryMinSeconds)
        return out
    }

    // MARK: Zone overlays for drawing

    static func overlays(assay: FlowAssay, config c: FlowZoneConfig) -> [FlowZoneOverlay] {
        let w = c.arenaWidthCM, h = c.arenaHeightCM
        var out: [FlowZoneOverlay] = []
        switch assay {
        case .openField:
            let f = c.centerFraction
            if c.arenaShape == .circle {
                out.append(FlowZoneOverlay(id: "center", shape: .circle(cx: w / 2, cy: w / 2, r: f * w / 2), role: .center, label: flowLoc("Center")))
            } else {
                out.append(FlowZoneOverlay(id: "center", shape: .rect(x: w * (1 - f) / 2, y: h * (1 - f) / 2, w: w * f, h: h * f), role: .center, label: flowLoc("Center")))
            }
        case .elevatedPlusMaze:
            let aw = max(1, c.plusArmWidthCM)
            let mid = c.plusArmLengthCM + aw
            let reach = c.plusArmLengthCM + aw / 2
            let open = openArms(c)
            func arm(_ name: String, _ rect: FlowZoneOverlay.Shape) -> FlowZoneOverlay {
                FlowZoneOverlay(id: "arm\(name)", shape: rect, role: open.contains(name) ? .open : .closed,
                            label: (open.contains(name) ? flowLoc("Open") : flowLoc("Closed")) + " " + name)
            }
            out.append(arm("N", .rect(x: mid - aw / 2, y: mid - reach, w: aw, h: reach - aw / 2)))
            out.append(arm("S", .rect(x: mid - aw / 2, y: mid + aw / 2, w: aw, h: reach - aw / 2)))
            out.append(arm("W", .rect(x: mid - reach, y: mid - aw / 2, w: reach - aw / 2, h: aw)))
            out.append(arm("E", .rect(x: mid + aw / 2, y: mid - aw / 2, w: reach - aw / 2, h: aw)))
            let half = aw / 2 + max(0, c.plusCenterMarginCM)
            out.append(FlowZoneOverlay(id: "center", shape: .rect(x: mid - half, y: mid - half, w: 2 * half, h: 2 * half), role: .center, label: flowLoc("Center")))
        case .lightDark:
            let f = min(1, max(0.05, c.lightFraction))
            let darkX = c.lightOnLeft ? f * w : 0
            let darkW = (1 - f) * w
            if darkW > 0.01 {
                out.append(FlowZoneOverlay(id: "dark", shape: .rect(x: darkX, y: 0, w: darkW, h: h), role: .dark, label: flowLoc("Dark")))
            }
            let lineX = c.lightOnLeft ? f * w : (1 - f) * w
            out.append(FlowZoneOverlay(id: "divider", shape: .line(x1: lineX, y1: 0, x2: lineX, y2: h), role: .divider, label: ""))
        case .placePreference:
            let pairedLeft = c.cppPairedOnLeft
            if c.cppChambers >= 3 {
                let n = min(0.8, max(0.02, c.cppNeutralFraction))
                let a = (1 - n) / 2 * w, b = (1 + n) / 2 * w
                out.append(FlowZoneOverlay(id: "left", shape: .rect(x: 0, y: 0, w: a, h: h), role: pairedLeft ? .paired : .neutral, label: pairedLeft ? flowLoc("Paired") : flowLoc("Unpaired")))
                out.append(FlowZoneOverlay(id: "right", shape: .rect(x: b, y: 0, w: w - b, h: h), role: pairedLeft ? .neutral : .paired, label: pairedLeft ? flowLoc("Unpaired") : flowLoc("Paired")))
                out.append(FlowZoneOverlay(id: "d1", shape: .line(x1: a, y1: 0, x2: a, y2: h), role: .divider, label: ""))
                out.append(FlowZoneOverlay(id: "d2", shape: .line(x1: b, y1: 0, x2: b, y2: h), role: .divider, label: ""))
            } else {
                let d = c.cppDivider * w
                out.append(FlowZoneOverlay(id: "paired", shape: pairedLeft ? .rect(x: 0, y: 0, w: d, h: h) : .rect(x: d, y: 0, w: w - d, h: h), role: .paired, label: flowLoc("Paired")))
                out.append(FlowZoneOverlay(id: "d1", shape: .line(x1: d, y1: 0, x2: d, y2: h), role: .divider, label: ""))
            }
        case .novelObject:
            let r = c.objectZoneRadiusCM
            if let a = c.objectA {
                out.append(FlowZoneOverlay(id: "A", shape: .circle(cx: a.x, cy: a.y, r: r), role: c.novelObject == "A" ? .novel : .familiar, label: c.novelObject == "A" ? flowLoc("A · novel") : "A"))
            }
            if let b = c.objectB {
                out.append(FlowZoneOverlay(id: "B", shape: .circle(cx: b.x, cy: b.y, r: r), role: c.novelObject == "B" ? .novel : .familiar, label: c.novelObject == "B" ? flowLoc("B · novel") : "B"))
            }
        case .morrisWaterMaze:
            let r = w / 2
            if c.wallZoneCM > 0 && c.wallZoneCM < r {
                out.append(FlowZoneOverlay(id: "wall", shape: .circle(cx: r, cy: r, r: r - c.wallZoneCM), role: .wall, label: ""))
            }
            if let t = c.target {
                let a = atan2(t.y - r, t.x - r)
                for (k, off) in [Double.pi / 4, -Double.pi / 4].enumerated() {
                    out.append(FlowZoneOverlay(id: "q\(k)", shape: .line(x1: r - r * cos(a + off), y1: r - r * sin(a + off), x2: r + r * cos(a + off), y2: r + r * sin(a + off)), role: .divider, label: ""))
                }
                out.append(FlowZoneOverlay(id: "platform", shape: .circle(cx: t.x, cy: t.y, r: c.targetRadiusCM), role: .target, label: flowLoc("Platform")))
            }
        case .barnesMaze:
            if let layout = holeLayout(c) {
                for k in 0..<layout.count {
                    let p = layout.position(k)
                    out.append(FlowZoneOverlay(id: "h\(k)", shape: .circle(cx: p.0, cy: p.1, r: c.targetRadiusCM), role: k == 0 ? .target : .hole, label: k == 0 ? flowLoc("Target") : ""))
                }
            }
        default:
            break
        }
        return out
    }
}
