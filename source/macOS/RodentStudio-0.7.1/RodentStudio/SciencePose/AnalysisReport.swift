// RodentPose iOS 1.0 scientific algorithm port; only PoseTrack name and localization/zone invocation adapted.
// AnalysisReport.swift — what an analyzer returns: headline metrics plus typed visual blocks.
// The interface renders blocks generically, so a new paradigm only needs a new analyzer.

import Foundation

/// Semantic colors; the interface maps them to the palette (light / dark aware).
enum ColorKey: String {
    case accent, neutral, warning
    case social, object, novel, familiar
    case center, periphery, open, closed, light, dark
    case freezing, sniff, headDip, sap, poke
    case target, error, shelter, escape
    case cw, ccw, animalA, animalB
    case nose, body, tail
    case series1, series2, series3, series4
}

struct MetricValue: Identifiable {
    let key: String
    let title: String
    let value: Double?
    let unit: String
    let decimals: Int
    var highlight = false
    var info: String?

    var id: String { key }

    var formatted: String {
        guard let v = value, v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    var formattedWithUnit: String {
        guard value != nil, value?.isFinite == true else { return "—" }
        return unit.isEmpty ? formatted : "\(formatted) \(unit)"
    }

    /// Column header for CSV exports, e.g. "Open arm time (%)".
    var exportHeader: String { unit.isEmpty ? title : "\(title) (\(unit))" }
}

// MARK: - Blocks

struct TimelineTrack: Identifiable {
    let id = UUID()
    var name: String
    var color: ColorKey
    var bouts: [Bout]
}

struct Epoch: Identifiable {
    let id = UUID()
    var name: String
    var start: Double
    var end: Double
    var color: ColorKey = .warning
}

struct TimelineData {
    var start: Double
    var end: Double
    var tracks: [TimelineTrack]
    var epochs: [Epoch] = []
}

struct BarItem: Identifiable {
    let id = UUID()
    var label: String
    var value: Double
    var color: ColorKey
    var group: String? = nil
}

struct BarData {
    var items: [BarItem]
    var unit: String
    var decimals = 1
    var referenceLine: Double? = nil
    var horizontal = false
}

struct LinePoint: Hashable {
    var x: Double
    var y: Double
}

struct LineSeries: Identifiable {
    let id = UUID()
    var name: String
    var color: ColorKey
    var points: [LinePoint]
    var dashed = false
}

struct LineData {
    var series: [LineSeries]
    var xLabel: String
    var yLabel: String
    var yRange: ClosedRange<Double>? = nil
    var referenceY: Double? = nil
    var referenceX: Double? = nil
    var epochs: [Epoch] = []
}

struct PolarData {
    /// Value per angular bin, bin 0 starts at 0° (counter-clockwise).
    var values: [Double]
    var unit: String
    var meanAngle: Double?
    var resultantLength: Double?
    /// Optional reference direction (e.g. cue card), degrees.
    var referenceAngle: Double?
    var color: ColorKey = .accent
}

struct TableData {
    var columns: [String]
    var rows: [[String]]
    /// Optional highlight per row.
    var rowColors: [ColorKey?] = []
}

struct PlotPath {
    var color: ColorKey
    /// Polylines; a new segment starts after missing samples.
    var segments: [[V2]]
    var width: Double = 1.2
    var opacity: Double = 0.8
}

struct PlotDot {
    var p: V2
    var color: ColorKey
    var radius: Double = 1.6
}

struct PlotArrow {
    var from: V2
    var to: V2
    var color: ColorKey
}

struct HeatGrid {
    var columns: Int
    var rows: Int
    var cell: Double
    /// Row-major values (seconds); NaN = outside arena.
    var values: [Double]
}

struct ArenaPlotData {
    var extent: V2
    var arena: Zone?
    var zones: [Zone]
    var paths: [PlotPath] = []
    var dots: [PlotDot] = []
    var arrows: [PlotArrow] = []
    var heat: HeatGrid? = nil
    var unit: String
}

enum ReportBlockKind {
    case arena(ArenaPlotData)
    case timeline(TimelineData)
    case bars(BarData)
    case line(LineData)
    case polar(PolarData)
    case table(TableData)
}

struct ReportBlock: Identifiable {
    let id = UUID()
    var title: String
    var caption: String?
    var kind: ReportBlockKind
}

// MARK: - Report

struct AnalysisReport {
    var metrics: [MetricValue] = []
    var blocks: [ReportBlock] = []
    var warnings: [String] = []
    /// Extra per-frame columns for the frame-by-frame CSV (flags, zone membership, …).
    var frameColumns: [(String, [Double])] = []
    var primaryKey: String = ""
    var zones: [Zone] = []
    /// Timeline tracks shown under the review player.
    var reviewTracks: [TimelineTrack] = []
    var reviewEpochs: [Epoch] = []
    /// One sentence per method decision, for a Methods paragraph.
    var methods: [String] = []
    /// Quality summary.
    var quality: QualityInfo = QualityInfo()

    func metric(_ key: String) -> MetricValue? { metrics.first { $0.key == key } }
    var primary: MetricValue? { metric(primaryKey) ?? metrics.first }
}

struct QualityInfo {
    var frames = 0
    var framesInWindow = 0
    var windowSeconds: Double = 0
    var detectionRate: Double = 0
    /// Fraction of frames with each keypoint above the confidence threshold.
    var keypointRates: [Double] = []
    var headDirectionRate: Double = 0
    var sampleRate: Double = 0
    var pxPerUnit: Double = 0
    var unit = "cm"
}
