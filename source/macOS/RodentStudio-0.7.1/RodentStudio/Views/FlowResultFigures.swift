// FlowResultFigures.swift — the RodentFlow 1.3 result screen on macOS: metric grid (catalog names, units
// and decimals, primary first), arena plot (path / heat map with zones, restricted to the analysis
// window), freezing timeline, time-bin series, labels and methods. Ported from RodentFlow
// AssayVisuals.swift, UIComponents.swift and ResultDetailView.swift; drawing, colors and scales are
// unchanged. Object / target markers are shown where Calibrate placed them (they are moved there, not
// on the plot, so that the calibration stays the single source of truth).

import SwiftUI
import Charts
import AppKit

enum RFArenaPlotMode: String, CaseIterable, Identifiable {
    case trajectory = "Path"
    case heatmap = "Heatmap"
    var id: String { rawValue }
    var title: String { RFText.tr(rawValue) }
}

struct RFArenaMarker: Identifiable, Hashable {
    var id: String
    var label: String
    var point: FlowArenaPoint
}

// MARK: - Arena plot (trajectory / heat map + zones)

struct RFArenaPlotView: View {
    let samples: [FlowAnalysisSample]
    let config: FlowZoneConfig
    let overlays: [FlowZoneOverlay]
    var mode: RFArenaPlotMode = .trajectory
    var markers: [RFArenaMarker] = []

    private struct Frame {
        var origin: CGPoint
        var scale: CGFloat
    }

    private var arenaWidth: Double { max(1, config.arenaWidthCM) }
    private var arenaHeight: Double { max(1, config.arenaShape == .circle ? config.arenaWidthCM : config.arenaHeightCM) }

    var body: some View {
        GeometryReader { geo in
            let frame = makeFrame(geo.size)
            ZStack {
                Canvas { context, _ in
                    drawArena(&context, frame)
                    drawOverlays(&context, frame)
                    if mode == .trajectory {
                        drawTrajectory(&context, frame)
                    } else {
                        drawHeatmap(&context, frame)
                    }
                    drawOverlayLabels(&context, frame)
                }
                ForEach(markers) { marker in
                    RFMarkerHandle(label: marker.label)
                        .position(viewPoint(marker.point.x, marker.point.y, frame))
                }
            }
        }
        .aspectRatio(CGFloat(arenaWidth / arenaHeight), contentMode: .fit)
        .frame(maxHeight: 340)
    }

    private func makeFrame(_ size: CGSize) -> Frame {
        let pad: CGFloat = 12
        let s = min((size.width - 2 * pad) / CGFloat(arenaWidth), (size.height - 2 * pad) / CGFloat(arenaHeight))
        let scale = max(0.01, s)
        let origin = CGPoint(x: (size.width - CGFloat(arenaWidth) * scale) / 2, y: (size.height - CGFloat(arenaHeight) * scale) / 2)
        return Frame(origin: origin, scale: scale)
    }

    private func viewPoint(_ x: Double, _ y: Double, _ f: Frame) -> CGPoint {
        CGPoint(x: f.origin.x + CGFloat(x) * f.scale, y: f.origin.y + CGFloat(y) * f.scale)
    }

    private func viewRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ f: Frame) -> CGRect {
        CGRect(x: f.origin.x + CGFloat(x) * f.scale, y: f.origin.y + CGFloat(y) * f.scale,
               width: CGFloat(w) * f.scale, height: CGFloat(h) * f.scale)
    }

    private func drawArena(_ context: inout GraphicsContext, _ f: Frame) {
        let rect = viewRect(0, 0, arenaWidth, arenaHeight, f)
        let path: Path
        switch config.arenaShape {
        case .circle:
            path = Path(ellipseIn: rect)
        case .rectangle:
            path = Path(rect)
        default:
            path = Path(roundedRect: rect, cornerRadius: 4)
        }
        if config.arenaShape == .rectangle || config.arenaShape == .circle {
            context.fill(path, with: .color(FigureSurface.inset))
            context.stroke(path, with: .color(.secondary.opacity(0.6)), lineWidth: 1.2)
        } else {
            context.stroke(path, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private func roleColor(_ role: FlowZoneOverlay.Role) -> Color {
        switch role {
        case .center: return .blue
        case .target: return .green
        case .novel: return .orange
        case .familiar: return .gray
        case .paired: return .purple
        case .neutral: return .gray
        case .dark: return .black
        case .open: return .yellow
        case .closed: return .gray
        case .hole: return .gray
        case .divider: return .secondary
        case .wall: return .teal
        }
    }

    private func drawOverlays(_ context: inout GraphicsContext, _ f: Frame) {
        for o in overlays {
            let color = roleColor(o.role)
            switch o.shape {
            case .rect(let x, let y, let w, let h):
                let path = Path(viewRect(x, y, w, h, f))
                let fillOpacity = o.role == .dark ? 0.22 : (o.role == .open ? 0.22 : 0.13)
                context.fill(path, with: .color(color.opacity(fillOpacity)))
                context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1)
            case .circle(let cx, let cy, let r):
                let path = Path(ellipseIn: viewRect(cx - r, cy - r, 2 * r, 2 * r, f))
                if o.role == .wall {
                    context.stroke(path, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                } else if o.role == .hole {
                    context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1)
                } else {
                    context.fill(path, with: .color(color.opacity(0.22)))
                    context.stroke(path, with: .color(color), lineWidth: 1.4)
                }
            case .line(let x1, let y1, let x2, let y2):
                var path = Path()
                path.move(to: viewPoint(x1, y1, f))
                path.addLine(to: viewPoint(x2, y2, f))
                context.stroke(path, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
        }
    }

    private func drawOverlayLabels(_ context: inout GraphicsContext, _ f: Frame) {
        for o in overlays where !o.label.isEmpty {
            let anchor: CGPoint
            switch o.shape {
            case .rect(let x, let y, let w, let h): anchor = viewPoint(x + w / 2, y + h / 2, f)
            case .circle(let cx, let cy, let r): anchor = viewPoint(cx, cy - r - 2.5, f)
            case .line(let x1, let y1, _, _): anchor = viewPoint(x1, y1, f)
            }
            context.draw(Text(RFText.tr(o.label)).font(.system(size: 9.5, weight: .semibold)).foregroundColor(.primary.opacity(0.75)), at: anchor)
        }
    }

    private func drawTrajectory(_ context: inout GraphicsContext, _ f: Frame) {
        guard samples.count > 1 else { return }
        let stride = max(1, samples.count / 4000)
        var path = Path()
        var penDown = false
        var i = 0
        while i < samples.count {
            let s = samples[i]
            if s.detected {
                let p = viewPoint(s.x, s.y, f)
                if penDown { path.addLine(to: p) } else { path.move(to: p); penDown = true }
            } else {
                penDown = false
            }
            i += stride
        }
        context.stroke(path, with: .color(.orange.opacity(0.78)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        if let first = samples.first(where: { $0.detected }) {
            let p = viewPoint(first.x, first.y, f)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.green))
        }
        if let last = samples.last(where: { $0.detected }) {
            let p = viewPoint(last.x, last.y, f)
            context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.red))
        }
    }

    private func drawHeatmap(_ context: inout GraphicsContext, _ f: Frame) {
        let columns = 32
        let rows = max(4, Int((Double(columns) * arenaHeight / arenaWidth).rounded()))
        var counts = [Double](repeating: 0, count: columns * rows)
        for s in samples where s.detected {
            let c = min(columns - 1, max(0, Int(s.x / arenaWidth * Double(columns))))
            let r = min(rows - 1, max(0, Int(s.y / arenaHeight * Double(rows))))
            counts[r * columns + c] += 1
        }
        guard let maxCount = counts.max(), maxCount > 0 else { return }
        let cw = arenaWidth / Double(columns)
        let ch = arenaHeight / Double(rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let v = counts[r * columns + c]
                guard v > 0 else { continue }
                // Square-root scaling keeps short visits visible next to long dwell spots.
                let t = (v / maxCount).squareRoot()
                let rect = viewRect(Double(c) * cw, Double(r) * ch, cw + 0.05, ch + 0.05, f)
                context.fill(Path(rect), with: .color(RFHeatPalette.color(t).opacity(0.25 + 0.75 * t)))
            }
        }
    }
}

private struct RFMarkerHandle: View {
    let label: String

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.7)).frame(width: 26, height: 26)
            Circle().stroke(.yellow, lineWidth: 2.5).frame(width: 22, height: 22)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }
}

enum RFHeatPalette {
    /// Viridis-like ramp.
    private static let stops: [(Double, Double, Double)] = [
        (0.267, 0.005, 0.329), (0.231, 0.322, 0.546), (0.128, 0.567, 0.551), (0.369, 0.789, 0.383), (0.993, 0.906, 0.144)
    ]

    static func color(_ t: Double) -> Color {
        let x = min(1, max(0, t)) * Double(stops.count - 1)
        let i = min(stops.count - 2, Int(x))
        let f = x - Double(i)
        let a = stops[i], b = stops[i + 1]
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }
}

// MARK: - Series (time bins, CS)

struct RFSeriesChartView: View {
    let series: FlowResultSeries

    private struct Point: Identifiable {
        let id: Int
        let x: Double
        let y: Double
        let label: String
    }

    private var points: [Point] {
        zip(series.x, series.y).enumerated().map { index, pair in
            Point(id: index, x: pair.0, y: pair.1, label: Self.label(pair.0))
        }
    }

    private var useBars: Bool { series.key.hasSuffix("by_bin") || series.key.hasSuffix("by_cs") }

    static func label(_ x: Double) -> String {
        abs(x - x.rounded()) < 1e-9 ? String(format: "%.0f", x) : String(format: "%.1f", x)
    }

    var body: some View {
        let name = RFText.tr(series.name)
        let xLabel = RFText.tr(series.xLabel)
        VStack(alignment: .leading, spacing: 6) {
            Text(series.unit.isEmpty ? name : "\(name) (\(series.unit))")
                .font(.system(size: 14, weight: .semibold))
            if useBars {
                Chart(points) { p in
                    BarMark(x: .value(xLabel, p.label), y: .value(name, p.y))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXAxisLabel(xLabel)
                .frame(height: 150)
            } else {
                Chart(points) { p in
                    LineMark(x: .value(xLabel, p.x), y: .value(name, p.y))
                        .foregroundStyle(Color.accentColor)
                    PointMark(x: .value(xLabel, p.x), y: .value(name, p.y))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(24)
                }
                .chartXAxisLabel(xLabel)
                .frame(height: 150)
            }
        }
    }
}

// MARK: - Freezing timeline

struct RFFreezingTimelineView: View {
    let trace: FlowFreezingTrace
    let config: FlowZoneConfig

    private struct Bin: Identifiable {
        let id: Int
        let minute: Double
        let motion: Double
    }

    private struct Window: Identifiable {
        let id: Int
        let start: Double
        let end: Double
    }

    private var bins: [Bin] {
        guard let first = trace.times.first, let last = trace.times.last, last > first else { return [] }
        let count = min(700, max(1, trace.times.count))
        let width = (last - first) / Double(count)
        var sums = [Double](repeating: 0, count: count)
        var ns = [Double](repeating: 0, count: count)
        for (t, m) in zip(trace.times, trace.bodyMotionPct) {
            guard let m else { continue }
            let i = min(count - 1, max(0, Int((t - first) / max(width, 1e-9))))
            sums[i] += m
            ns[i] += 1
        }
        return (0..<count).compactMap { i in
            ns[i] > 0 ? Bin(id: i, minute: (first + (Double(i) + 0.5) * width) / 60, motion: sums[i] / ns[i]) : nil
        }
    }

    private var csWindows: [Window] {
        config.csOnsetsSeconds.sorted().enumerated().map { i, onset in
            Window(id: i, start: onset / 60, end: (onset + config.csDurationSeconds) / 60)
        }
    }

    private var yMax: Double {
        let values = trace.bodyMotionPct.compactMap { $0 }
        let p95 = FlowStats.quantile(values, 0.95)
        return max(config.freezeThresholdPct * 3, p95.isFinite ? p95 * 1.1 : 10, 1)
    }

    var body: some View {
        let top = yMax
        VStack(alignment: .leading, spacing: 6) {
            Text(RFText.tr("Motion (body-area %) and freezing"))
                .font(.system(size: 14, weight: .semibold))
            Chart {
                ForEach(csWindows) { w in
                    RectangleMark(xStart: .value("Time", w.start), xEnd: .value("Time", w.end),
                                  yStart: .value("Motion", 0.0), yEnd: .value("Motion", top))
                        .foregroundStyle(.orange.opacity(0.16))
                }
                ForEach(bins) { b in
                    LineMark(x: .value("Time", b.minute), y: .value("Motion", min(b.motion, top)))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
                RuleMark(y: .value("Threshold", config.freezeThresholdPct))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .chartYScale(domain: 0...top)
            .chartXAxisLabel(RFText.tr("Time (min, from protocol start)"))
            .frame(height: 170)

            RFFreezingRaster(trace: trace, config: config)
                .frame(height: 18)
            HStack(spacing: 12) {
                legendSwatch(.blue, "Freezing bouts")
                legendSwatch(.orange.opacity(0.5), "CS")
                legendSwatch(.red, "Threshold")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 8)
            Text(RFText.tr(text))
        }
    }
}

/// Thin strip showing freezing bouts along the session.
struct RFFreezingRaster: View {
    let trace: FlowFreezingTrace
    let config: FlowZoneConfig

    var body: some View {
        Canvas { context, size in
            guard let first = trace.times.first, let last = trace.times.last, last > first else { return }
            let span = last - first
            func x(_ t: Double) -> CGFloat { CGFloat((t - first) / span) * size.width }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(.secondary.opacity(0.12)))
            for onset in config.csOnsetsSeconds {
                let rect = CGRect(x: x(onset), y: 0, width: max(1, x(onset + config.csDurationSeconds) - x(onset)), height: size.height)
                context.fill(Path(rect), with: .color(.orange.opacity(0.35)))
            }
            var i = 0
            while i < trace.frozen.count {
                guard trace.frozen[i] else { i += 1; continue }
                var j = i
                while j < trace.frozen.count && trace.frozen[j] { j += 1 }
                let end = j < trace.times.count ? trace.times[j] : last
                let rect = CGRect(x: x(trace.times[i]), y: 3, width: max(1, x(end) - x(trace.times[i])), height: size.height - 6)
                context.fill(Path(rect), with: .color(.blue))
                i = j
            }
        }
    }
}

// MARK: - Metrics (UIComponents.MetricTile / MetricGrid / FlagList)

struct RFMetricTile: View {
    let title: String
    let value: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(11)
        .background(highlight ? Color.accentColor.opacity(0.13) : FigureSurface.inset,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RFMetricGrid: View {
    let assay: FlowAssay
    let phase: String
    let metrics: [String: Double]

    var body: some View {
        let primary = RFMetricCatalog.primaryKey(assay, phase: phase, metrics: metrics)
        let defs = RFMetricCatalog.ordered(assay, phase: phase, metrics: metrics)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 8)], spacing: 8) {
            ForEach(defs) { def in
                RFMetricTile(title: def.name,
                             value: metrics[def.key].map { def.format($0) } ?? "—",
                             highlight: def.key == primary)
                    .help(def.definition)
            }
        }
    }
}

struct RFFlagList: View {
    let flags: [String]

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(flags, id: \.self) { flag in
                    Label {
                        Text(RFText.tr(flag)).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// RodentFlow SectionCard look (title + icon above content) on the shared card.
struct RFSectionCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        FigureCard {
            FigureCardHeader(title, symbol: icon)
            content
        }
    }
}

// MARK: - Whole result (ResultDetailView order)

struct FlowResultView: View {
    let assay: FlowAssay
    let phase: String
    let computation: FlowAssayComputation
    let config: FlowZoneConfig
    /// All samples of the run (the arena plot shows the analysis window only).
    let samples: [FlowAnalysisSample]
    @State private var plotMode: RFArenaPlotMode = .trajectory

    private var markers: [RFArenaMarker] { Self.markerList(assay, config) }

    static func markerList(_ assay: FlowAssay, _ c: FlowZoneConfig) -> [RFArenaMarker] {
        switch assay {
        case .novelObject:
            var m: [RFArenaMarker] = []
            if let a = c.objectA { m.append(RFArenaMarker(id: "A", label: "A", point: a)) }
            if let b = c.objectB { m.append(RFArenaMarker(id: "B", label: "B", point: b)) }
            return m
        case .morrisWaterMaze:
            return c.target.map { [RFArenaMarker(id: "T", label: "P", point: $0)] } ?? []
        case .barnesMaze:
            return c.target.map { [RFArenaMarker(id: "T", label: "T", point: $0)] } ?? []
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RFFlagList(flags: computation.qcFlags)
            RFSectionCard(title: RFText.tr("Results"), icon: "number") {
                if computation.metrics.isEmpty {
                    Text(RFText.tr("No metrics could be computed."))
                        .font(.system(size: 14.5))
                        .foregroundStyle(.secondary)
                } else {
                    RFMetricGrid(assay: assay, phase: phase, metrics: computation.metrics)
                }
            }
            RFSectionCard(title: assay == .fearConditioning ? RFText.tr("Freezing") : RFText.tr("Arena"),
                          icon: assay == .fearConditioning ? "waveform.path.ecg" : "map") {
                if assay != .fearConditioning {
                    Picker(RFText.tr("Plot"), selection: $plotMode) {
                        ForEach(RFArenaPlotMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Self.visual(assay: assay, config: config, samples: samples, mode: plotMode)
                if !markers.isEmpty {
                    Text(L("Markers show the object / target positions placed in Calibrate. To move them, change them in Calibrate — results update without re-tracking.",
                           "标记为“校准”中放置的物体 / 目标位置。如需移动，请在“校准”中修改——结果会更新，无需重新追踪。"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(computation.series) { s in
                RFSectionCard(title: RFText.tr(s.name), icon: "chart.bar") {
                    RFSeriesChartView(series: s)
                }
            }
            if !computation.labels.isEmpty {
                RFSectionCard(title: RFText.tr("Sequence & labels"), icon: "text.alignleft") {
                    ForEach(computation.labels.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(RFText.key(key, capitalized: true))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text(RFText.tr(computation.labels[key] ?? ""))
                                .font(.system(size: 15, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            methodsCard
        }
    }

    /// Arena plot (analysis window) or, for fear conditioning, the freezing timeline.
    @ViewBuilder
    static func visual(assay: FlowAssay, config: FlowZoneConfig, samples: [FlowAnalysisSample], mode: RFArenaPlotMode) -> some View {
        if assay == .fearConditioning {
            RFFreezingTimelineView(trace: FlowAssayEngine.freezingTrace(samples, config), config: config)
        } else {
            RFArenaPlotView(samples: FlowResultInputs.windowed(samples, assay: assay, config: config),
                            config: config,
                            overlays: FlowAssayEngine.overlays(assay: assay, config: config),
                            mode: mode,
                            markers: markerList(assay, config))
        }
    }

    private var methodsCard: some View {
        RFSectionCard(title: RFText.tr("Methods"), icon: "doc.text.magnifyingglass") {
            DisclosureGroup(RFText.tr("How these numbers are computed")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(RFText.tr(RFMetricCatalog.methodsNote(assay)))
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(RFMetricCatalog.definitions(assay, metrics: computation.metrics).filter { computation.metrics[$0.key] != nil }) { def in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(def.axisTitle)
                                .font(.system(size: 13.5, weight: .semibold))
                            Text(def.definition)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !computation.parameters.isEmpty {
                        Divider()
                        Text(RFText.tr("Parameters")).font(.system(size: 13.5, weight: .semibold))
                        ForEach(computation.parameters.keys.sorted(), id: \.self) { key in
                            FigureInfoRow(key: RFText.key(key), value: RFText.tr(computation.parameters[key] ?? ""))
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 15))
        }
    }
}

// MARK: - Export

enum FlowResultExport {
    @MainActor
    static func write(assay: FlowAssay, phase: String, computation c: FlowAssayComputation, config: FlowZoneConfig,
                      run: FlowSavedRun, samples: [FlowAnalysisSample], metadata: [String: String],
                      to folder: URL, includeFigures: Bool) throws -> [URL] {
        var urls: [URL] = []
        let primary = RFMetricCatalog.primaryKey(assay, phase: phase, metrics: c.metrics)

        // Metrics (catalog order, primary first) with English names and units.
        var lines = ["metric_key,metric,value,unit,primary"]
        for def in RFMetricCatalog.ordered(assay, phase: phase, metrics: c.metrics) {
            let value = c.metrics[def.key].map { FastFormat.fixed($0, max(def.decimals, 3)) } ?? ""
            let isPrimary: String = def.key == primary ? "1" : "0"
            let row: [String] = [FigureExport.csv(def.key), FigureExport.csv(def.englishName), value, FigureExport.csv(def.unit), isPrimary]
            lines.append(row.joined(separator: ","))
        }
        let metricsURL = folder.appendingPathComponent("rodentflow_metrics.csv")
        try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: metricsURL)
        urls.append(metricsURL)

        // Series behind the bar / line charts.
        for s in c.series {
            var csv = "x,y\n"
            for (x, y) in zip(s.x, s.y) { csv += FigureExport.number(x) + "," + FigureExport.number(y) + "\n" }
            let url = folder.appendingPathComponent("rodentflow_series_" + FigureExport.slug(s.key) + ".csv")
            try FigureExport.writeText("# \(s.name) (\(s.unit)); x = \(s.xLabel)\n" + csv, to: url)
            urls.append(url)
        }

        // Full computation and the configuration it used.
        struct ResultFile: Encodable {
            let assay: String
            let phase: String
            let primaryMetricKey: String
            let computation: FlowAssayComputation
            let config: FlowZoneConfig
            let markersCM: [String: FlowArenaPoint]?
            let metadata: [String: String]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonURL = folder.appendingPathComponent("rodentflow_assay_result.json")
        try encoder.encode(ResultFile(assay: assay.rawValue, phase: phase, primaryMetricKey: primary, computation: c,
                                      config: config, markersCM: run.markersCM, metadata: metadata))
            .write(to: jsonURL, options: .atomic)
        urls.append(jsonURL)

        // Centroid samples inside the analysis window (what the numbers are computed from).
        let window = FlowResultInputs.window(assay: assay, config: config)
        let first = run.points.first?.videoTimeSeconds ?? 0
        let start = first + window.start
        let end = window.duration.map { start + $0 } ?? Double.infinity
        var centroid = "frame_index,video_time_s,image_x_normalized,image_y_normalized,x_cm,y_cm,zone,confidence,interpolated,motion_index,blob_area_fraction\n"
        for p in run.points where p.videoTimeSeconds >= start && p.videoTimeSeconds < end {
            let fields: [String] = [
                String(p.frameIndex),
                String(p.videoTimeSeconds),
                String(p.imageXNormalized),
                String(p.imageYNormalized),
                String(p.xCentimeters),
                String(p.yCentimeters),
                FigureExport.csv(p.zone),
                String(p.confidence),
                p.interpolated ? "1" : "0",
                p.motionIndex.map { String($0) } ?? "",
                p.blobAreaFraction.map { String($0) } ?? ""
            ]
            centroid += fields.joined(separator: ",") + "\n"
        }
        let centroidURL = folder.appendingPathComponent("rodentflow_centroid_analysis_window.csv")
        try FigureExport.writeText(centroid, to: centroidURL)
        urls.append(centroidURL)

        if !run.events.isEmpty {
            var events = "event_index,time_s,from_zone,to_zone\n"
            for e in run.events {
                let row: [String] = [String(e.eventIndex), String(e.timeSeconds), FigureExport.csv(e.fromZone), FigureExport.csv(e.toZone)]
                events += row.joined(separator: ",") + "\n"
            }
            let url = folder.appendingPathComponent("rodentflow_zone_events.csv")
            try FigureExport.writeText(events, to: url)
            urls.append(url)
        }

        var methods: [String] = []
        for key in metadata.keys.sorted() { methods.append("\(key): \(metadata[key] ?? "")") }
        methods.append("")
        methods.append(RFMetricCatalog.methodsNote(assay))
        methods.append("")
        for def in RFMetricCatalog.definitions(assay, metrics: c.metrics) where c.metrics[def.key] != nil {
            methods.append("\(def.exportHeader): \(def.englishDefinition)")
        }
        if !c.parameters.isEmpty {
            methods.append("")
            methods.append("Parameters:")
            for key in c.parameters.keys.sorted() { methods.append("  \(key) = \(c.parameters[key] ?? "")") }
        }
        if !c.qcFlags.isEmpty {
            methods.append("")
            methods.append("QC flags:")
            methods += c.qcFlags.map { "- " + $0 }
        }
        methods.append("")
        methods.append("RodentFlow 1.3 classic centroid tracker (10 Hz) and AssayEngine formulas, desktop port. No neural network was used. Compare with RodentFlow iOS before reporting.")
        let methodsURL = folder.appendingPathComponent("rodentflow_methods.txt")
        try FigureExport.writeText(methods.joined(separator: "\n") + "\n", to: methodsURL)
        urls.append(methodsURL)

        if includeFigures {
            let resultsCard = RFSectionCard(title: RFText.tr("Results"), icon: "number") {
                RFMetricGrid(assay: assay, phase: phase, metrics: c.metrics)
            }
            let resultsURL = folder.appendingPathComponent("rodentflow_figure_01_results.png")
            try FigureExport.writePNG(resultsCard, to: resultsURL)
            urls.append(resultsURL)
            if assay == .fearConditioning {
                let card = RFSectionCard(title: RFText.tr("Freezing"), icon: "waveform.path.ecg") {
                    FlowResultView.visual(assay: assay, config: config, samples: samples, mode: .trajectory)
                }
                let url = folder.appendingPathComponent("rodentflow_figure_02_freezing.png")
                try FigureExport.writePNG(card, to: url)
                urls.append(url)
            } else {
                for (i, mode) in RFArenaPlotMode.allCases.enumerated() {
                    let card = RFSectionCard(title: RFText.tr("Arena") + " · " + mode.title, icon: "map") {
                        FlowResultView.visual(assay: assay, config: config, samples: samples, mode: mode)
                    }
                    let url = folder.appendingPathComponent(String(format: "rodentflow_figure_%02d_arena_", i + 2) + mode.rawValue.lowercased() + ".png")
                    try FigureExport.writePNG(card, to: url)
                    urls.append(url)
                }
            }
            for (i, s) in c.series.enumerated() {
                let card = RFSectionCard(title: RFText.tr(s.name), icon: "chart.bar") { RFSeriesChartView(series: s) }
                let url = folder.appendingPathComponent(String(format: "rodentflow_figure_%02d_", i + 4) + FigureExport.slug(s.key) + ".png")
                try FigureExport.writePNG(card, to: url)
                urls.append(url)
            }
        }
        return urls
    }
}
