// Port of RodentFlow iOS 1.3 AssayCatalog: metric definitions, primary metric and methods note of the
// video assays. Names, units, decimals and definitions are copied unchanged (English); the interface
// shows RodentFlow's own Simplified Chinese translations (Resources/RodentFlowChinese.json, extracted
// from RodentFlow's Localizable.xcstrings). Exports always use the English text.

import Foundation

enum RFText {
    private static let chinese: [String: String] = {
        guard let url = Bundle.main.url(forResource: "RodentFlowChinese", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: bytes)
        else { return [:] }
        return table
    }()

    /// RodentFlow `loc`: the translation in the interface language, the English text otherwise.
    static func tr(_ english: String) -> String {
        guard Lang.isChinese, !english.isEmpty else { return english }
        return chinese[english] ?? english
    }

    /// RodentFlow's Chinese translation regardless of the interface language (English if there is none).
    static func chineseText(_ english: String) -> String {
        guard !english.isEmpty else { return english }
        return chinese[english] ?? english
    }

    /// RodentFlow `locKey`: a stored identifier shown as words ("light_side" → "light side").
    static func key(_ key: String, capitalized: Bool = false) -> String {
        let translated = tr(key)
        if translated != key { return translated }
        let plain = key.replacingOccurrences(of: "_", with: " ")
        return capitalized ? plain.capitalized : plain
    }
}

struct RFMetricDefinition: Hashable, Identifiable {
    let key: String
    /// English name and definition (exports); `name` / `definition` are for the interface.
    let englishName: String
    let unit: String
    let englishDefinition: String
    /// Reference value for an optional one-sample test (e.g. DI vs 0, quadrant vs 25%).
    let chance: Double?
    let decimals: Int

    var id: String { key }
    var name: String { RFText.tr(englishName) }
    var definition: String { RFText.tr(englishDefinition) }

    init(_ key: String, _ name: String, _ unit: String, _ definition: String, chance: Double? = nil, decimals: Int = 1) {
        self.key = key
        self.englishName = name
        self.unit = unit
        self.englishDefinition = definition
        self.chance = chance
        self.decimals = decimals
    }

    var axisTitle: String { unit.isEmpty ? name : "\(name) (\(unit))" }
    var exportHeader: String { unit.isEmpty ? englishName : "\(englishName) (\(unit))" }

    func format(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        let number = String(format: "%.\(decimals)f", value)
        switch unit {
        case "": return number
        case "%": return number + "%"
        default: return number + " " + unit
        }
    }
}

enum RFMetricCatalog {
    /// RodentFlow `AssayKind.primaryMetricKey(phase:)`.
    static func primaryKey(_ assay: FlowAssay, phase: String) -> String {
        switch assay {
        case .openField: return "distance_m"
        case .elevatedPlusMaze: return "open_time_pct"
        case .lightDark: return "light_time_pct"
        case .yMaze: return "alternation_pct"
        case .tMaze: return "right_choice_pct"
        case .novelObject: return "discrimination_index"
        case .morrisWaterMaze: return phase == "Probe" ? "target_quadrant_pct" : "escape_latency_s"
        case .barnesMaze: return phase == "Probe" ? "target_quadrant_pct" : "primary_latency_s"
        case .fearConditioning: return phase == "Cue test" ? "cs_freezing_pct" : "freezing_pct"
        case .placePreference: return "preference_score_s"
        }
    }

    /// RodentFlow `ExperimentResult.primaryMetricKey`: the catalog key when it was computed.
    static func primaryKey(_ assay: FlowAssay, phase: String, metrics: [String: Double]) -> String {
        let key = primaryKey(assay, phase: phase)
        if !key.isEmpty, metrics[key] != nil { return key }
        return key.isEmpty ? (metrics.keys.sorted().first ?? "") : key
    }

    /// RodentFlow `AssayCatalog.metricDefinitions(for:)`: catalog order, then any other key.
    static func definitions(_ assay: FlowAssay, metrics: [String: Double]) -> [RFMetricDefinition] {
        var defs = self.metrics(assay)
        let known = Set(defs.map(\.key))
        for key in metrics.keys.sorted() where !known.contains(key) {
            defs.append(RFMetricDefinition(key, key, "", "Imported value.", decimals: 3))
        }
        return defs
    }

    /// Definitions of the metrics present, primary first (RodentFlow MetricGrid order).
    static func ordered(_ assay: FlowAssay, phase: String, metrics: [String: Double]) -> [RFMetricDefinition] {
        let primary = primaryKey(assay, phase: phase, metrics: metrics)
        let all = definitions(assay, metrics: metrics).filter { metrics[$0.key] != nil }
        return all.filter { $0.key == primary } + all.filter { $0.key != primary }
    }

    /// RodentFlow `AssayKind.methodsNote` (English).
    static func methodsNote(_ assay: FlowAssay) -> String {
        switch assay {
        case .openField:
            return "Body-centroid tracking at 10 Hz. The center zone is a concentric square (or circle) whose side (or radius) is a set fraction of the arena. Zone times use detected samples only."
        case .elevatedPlusMaze:
            return "Centroid tracking on a calibrated plus-maze. An arm entry requires the centroid to leave the central square and stay in the arm for the entry criterion. Open-arm % = open / (open + closed)."
        case .lightDark:
            return "The light compartment is defined by a divider line in arena coordinates. If the dark box is covered, samples where the mouse is not visible are counted as dark."
        case .yMaze:
            return "Arm entries require 0.25 s of stable centroid occupancy. Alternation % = consecutive triplets of three different arms / (entries − 2) × 100."
        case .tMaze:
            return "Arm entries require stable centroid occupancy. First choice is the first choice-arm entry."
        case .novelObject:
            return "Exploration is approximated as the body centroid within the object interaction zone (radius set by the user). Nose-directed scoring by hand can be entered manually instead. DI = (novel − familiar) / (novel + familiar)."
        case .morrisWaterMaze:
            return "Escape = centroid within the platform zone for at least the stay criterion. Quadrants are 90° sectors centered on the platform direction. Mean distance to platform = Gallagher proximity."
        case .barnesMaze:
            return "Holes are placed evenly around the ring defined by the target hole. A hole visit = centroid within the hole zone for the entry criterion. Errors are visits to non-target holes before the first target visit (body-centroid proxy for nose pokes)."
        case .fearConditioning:
            return "Motion index = fraction of arena pixels changing between consecutive 10 Hz frames, normalized to the median mouse body area. Freezing = motion below threshold for at least the minimum bout duration. Validate the threshold against hand-scored clips."
        case .placePreference:
            return "Chamber times from centroid tracking. Preference score = paired − unpaired time; CPP score = test − pre-test (computed in group analysis)."
        }
    }

    static func metrics(_ assay: FlowAssay) -> [RFMetricDefinition] {
        switch assay {
        case .openField:
            return [
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps between consecutive detected samples.", decimals: 2),
                RFMetricDefinition("mean_speed_cms", "Mean speed", "cm/s", "Total distance / analyzed duration.", decimals: 2),
                RFMetricDefinition("mobile_time_pct", "Mobile time", "%", "Time with speed ≥ moving threshold / time with known speed."),
                RFMetricDefinition("immobile_time_s", "Immobility", "s", "Sum of bouts with speed below threshold lasting at least the minimum duration."),
                RFMetricDefinition("center_time_s", "Center time", "s", "Time with the centroid inside the center zone."),
                RFMetricDefinition("center_time_pct", "Center time", "%", "Center time / detected time × 100."),
                RFMetricDefinition("center_entries", "Center entries", "", "Periphery → center transitions meeting the entry criterion.", decimals: 0),
                RFMetricDefinition("center_latency_s", "Latency to center", "s", "Time to the first center entry (analysis duration if never)."),
                RFMetricDefinition("center_distance_pct", "Center distance", "%", "Distance traveled inside the center zone / total distance × 100."),
                RFMetricDefinition("tracked_pct", "Tracked samples", "%", "Samples with a detected mouse / all samples.")
            ]
        case .elevatedPlusMaze:
            return [
                RFMetricDefinition("open_time_pct", "Open-arm time", "%", "Open / (open + closed) arm time × 100."),
                RFMetricDefinition("open_entries_pct", "Open-arm entries", "%", "Open / (open + closed) arm entries × 100."),
                RFMetricDefinition("open_time_s", "Open-arm time", "s", "Time in both open arms."),
                RFMetricDefinition("closed_time_s", "Closed-arm time", "s", "Time in both closed arms."),
                RFMetricDefinition("center_time_s", "Center time", "s", "Time in the central square."),
                RFMetricDefinition("open_entries", "Open-arm entries", "", "Entries into open arms.", decimals: 0),
                RFMetricDefinition("closed_entries", "Closed-arm entries", "", "Entries into closed arms.", decimals: 0),
                RFMetricDefinition("total_entries", "Total arm entries", "", "Open + closed entries (locomotor index).", decimals: 0),
                RFMetricDefinition("open_latency_s", "Latency to open arm", "s", "Time to the first open-arm entry."),
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps.", decimals: 2),
                RFMetricDefinition("tracked_pct", "Tracked samples", "%", "Samples with a detected mouse / all samples.")
            ]
        case .lightDark:
            return [
                RFMetricDefinition("light_time_pct", "Light-box time", "%", "Light time / total time × 100."),
                RFMetricDefinition("light_time_s", "Light-box time", "s", "Time with the centroid in the light compartment."),
                RFMetricDefinition("dark_time_s", "Dark-box time", "s", "Time in the dark compartment (including unseen samples if enabled)."),
                RFMetricDefinition("transitions", "Transitions", "", "Compartment changes meeting the entry criterion.", decimals: 0),
                RFMetricDefinition("latency_dark_s", "Latency to dark", "s", "Time to the first entry into the dark compartment."),
                RFMetricDefinition("light_distance_m", "Distance in light", "m", "Distance traveled inside the light compartment.", decimals: 2),
                RFMetricDefinition("tracked_pct", "Visible samples", "%", "Samples with a detected mouse / all samples.")
            ]
        case .yMaze:
            return [
                RFMetricDefinition("alternation_pct", "Spontaneous alternation", "%", "Triplets of three different arms / (entries − 2) × 100."),
                RFMetricDefinition("arm_entries", "Arm entries", "", "Total arm entries.", decimals: 0),
                RFMetricDefinition("alternations", "Alternations", "", "Number of successful triplets.", decimals: 0),
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps.", decimals: 2),
                RFMetricDefinition("tracked_pct", "Tracked samples", "%", "Samples with a detected mouse / all samples.")
            ]
        case .tMaze:
            return [
                RFMetricDefinition("right_choice_pct", "Right first choice", "%", "100 if the first choice-arm entry is right, 0 if left; averages to % right across runs.", decimals: 0),
                RFMetricDefinition("left_entries", "Left-arm entries", "", "Entries into the left arm.", decimals: 0),
                RFMetricDefinition("right_entries", "Right-arm entries", "", "Entries into the right arm.", decimals: 0),
                RFMetricDefinition("arm_entries", "Choice-arm entries", "", "Left + right entries.", decimals: 0),
                RFMetricDefinition("choice_latency_s", "Choice latency", "s", "Time to the first choice-arm entry."),
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps.", decimals: 2)
            ]
        case .novelObject:
            return [
                RFMetricDefinition("discrimination_index", "Discrimination index", "", "(novel − familiar) / (novel + familiar).", chance: 0, decimals: 3),
                RFMetricDefinition("recognition_index_pct", "Recognition index", "%", "novel / (novel + familiar) × 100.", chance: 50),
                RFMetricDefinition("novel_time_s", "Novel object exploration", "s", "Time in the novel-object zone (object B in training)."),
                RFMetricDefinition("familiar_time_s", "Familiar object exploration", "s", "Time in the familiar-object zone (object A in training)."),
                RFMetricDefinition("total_exploration_s", "Total exploration", "s", "novel + familiar exploration time."),
                RFMetricDefinition("novel_bouts", "Novel object bouts", "", "Approaches to the novel object.", decimals: 0),
                RFMetricDefinition("familiar_bouts", "Familiar object bouts", "", "Approaches to the familiar object.", decimals: 0),
                RFMetricDefinition("first_approach_latency_s", "Latency to first approach", "s", "Time to the first approach to either object."),
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps.", decimals: 2)
            ]
        case .morrisWaterMaze:
            return [
                RFMetricDefinition("escape_latency_s", "Escape latency", "s", "Time to reach and stay on the platform (capped at the trial maximum)."),
                RFMetricDefinition("path_length_m", "Path length", "m", "Swim path until escape (or trial end).", decimals: 2),
                RFMetricDefinition("swim_speed_cms", "Swim speed", "cm/s", "Path length / swim time.", decimals: 1),
                RFMetricDefinition("found_platform_pct", "Platform found", "%", "100 if the platform was reached, else 0.", decimals: 0),
                RFMetricDefinition("target_quadrant_pct", "Target quadrant time", "%", "Time in the 90° sector centered on the platform.", chance: 25),
                RFMetricDefinition("opposite_quadrant_pct", "Opposite quadrant time", "%", "Time in the quadrant opposite the platform.", chance: 25),
                RFMetricDefinition("platform_crossings", "Platform crossings", "", "Entries into the platform zone.", decimals: 0),
                RFMetricDefinition("first_crossing_latency_s", "Latency to platform zone", "s", "Time to the first platform-zone entry."),
                RFMetricDefinition("mean_platform_distance_cm", "Mean distance to platform", "cm", "Average distance to the platform center (Gallagher proximity)."),
                RFMetricDefinition("thigmotaxis_pct", "Wall-zone time", "%", "Time within the wall zone / swim time × 100.")
            ]
        case .barnesMaze:
            return [
                RFMetricDefinition("primary_latency_s", "Primary latency", "s", "Time to the first target-hole visit."),
                RFMetricDefinition("primary_errors", "Primary errors", "", "Non-target hole visits before the first target visit.", decimals: 0),
                RFMetricDefinition("total_errors", "Total errors", "", "All non-target hole visits within the trial.", decimals: 0),
                RFMetricDefinition("path_length_m", "Path length to target", "m", "Distance traveled until the first target visit.", decimals: 2),
                RFMetricDefinition("mean_speed_cms", "Mean speed", "cm/s", "Distance / time over the analyzed trial.", decimals: 1),
                RFMetricDefinition("escape_latency_s", "Escape latency", "s", "Time until the mouse disappears into the escape box (if detectable)."),
                RFMetricDefinition("target_quadrant_pct", "Target quadrant time", "%", "Time in the 90° sector centered on the target hole.", chance: 25),
                RFMetricDefinition("opposite_quadrant_pct", "Opposite quadrant time", "%", "Time in the opposite quadrant.", chance: 25),
                RFMetricDefinition("mean_target_distance_cm", "Mean distance to target", "cm", "Average distance to the target hole.")
            ]
        case .fearConditioning:
            return [
                RFMetricDefinition("freezing_pct", "Freezing (session)", "%", "Freezing time / analyzed time × 100."),
                RFMetricDefinition("baseline_freezing_pct", "Baseline freezing", "%", "Freezing during the pre-CS baseline."),
                RFMetricDefinition("cs_freezing_pct", "CS freezing", "%", "Freezing averaged over all CS presentations."),
                RFMetricDefinition("iti_freezing_pct", "Post-CS / ITI freezing", "%", "Freezing outside CS periods after the first CS."),
                RFMetricDefinition("freezing_bouts", "Freezing bouts", "", "Number of freezing bouts.", decimals: 0),
                RFMetricDefinition("mean_bout_s", "Mean bout duration", "s", "Average freezing bout duration.")
            ]
        case .placePreference:
            return [
                RFMetricDefinition("preference_score_s", "Preference score", "s", "Paired − unpaired chamber time."),
                RFMetricDefinition("preference_pct", "Paired-side preference", "%", "Paired / (paired + unpaired) × 100.", chance: 50),
                RFMetricDefinition("paired_time_s", "Paired chamber time", "s", "Time in the drug/reward-paired chamber."),
                RFMetricDefinition("unpaired_time_s", "Unpaired chamber time", "s", "Time in the unpaired chamber."),
                RFMetricDefinition("neutral_time_s", "Neutral chamber time", "s", "Time in the middle chamber (3-chamber apparatus)."),
                RFMetricDefinition("paired_entries", "Paired chamber entries", "", "Entries into the paired chamber.", decimals: 0),
                RFMetricDefinition("distance_m", "Total distance", "m", "Sum of centroid steps.", decimals: 2)
            ]
        }
    }
}
