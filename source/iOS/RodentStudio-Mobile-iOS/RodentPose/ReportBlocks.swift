// ReportBlocks.swift — renderers for analysis blocks: arena plot, timeline, bar / line charts,
// polar histogram and tables. Every figure can be copied or shared as an image, and its data
// copied as an English CSV (the same language policy as the exports).

import Charts
import SwiftUI
import UIKit

struct ReportBlockView: View {
    let block: ReportBlock
    /// Called with a confirmation message after a copy action (shown as a toast).
    var onCopied: ((String) -> Void)? = nil
    /// False when the view is rendered into an image (no menu button).
    var showsMenu = true

    @State private var share: SharePayload?
    @State private var showCaption = false

    private var symbol: String {
        switch block.kind {
        case .arena: return "map"
        case .timeline: return "timeline.selection"
        case .bars: return "chart.bar"
        case .line: return "chart.xyaxis.line"
        case .polar: return "safari"
        case .table: return "tablecells"
        }
    }

    var body: some View {
        Card {
            // On screen the figure note is one tap away (••• › Figure note); a copied or shared
            // image carries it under the title so the figure stands on its own.
            CardHeader(title: block.title, symbol: symbol, subtitle: showsMenu ? nil : block.caption) {
                if showsMenu { menu }
            }
            content
        }
        .contextMenu { if showsMenu { menuItems } }
        .sheet(item: $share) { p in ShareSheet(items: p.items) }
        .alert(block.title, isPresented: $showCaption) {
            Button(L10n.tr("好"), role: .cancel) {}
        } message: {
            Text(block.caption ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .arena(let d): ArenaPlotView(data: d)
        case .timeline(let d): TimelineChart(data: d)
        case .bars(let d): BarsChart(data: d)
        case .line(let d): LineChartView(data: d)
        case .polar(let d): PolarPlotView(data: d)
        case .table(let d): TableBlockView(data: d)
        }
    }

    private var menu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.tr("图表操作"))
    }

    @ViewBuilder
    private var menuItems: some View {
        if !(block.caption ?? "").isEmpty {
            Button {
                showCaption = true
            } label: {
                Label(L10n.tr("图表说明"), systemImage: "info.circle")
            }
            Divider()
        }
        Button {
            if let image = renderImage() {
                UIPasteboard.general.image = image
                onCopied?(L10n.tr("已复制图像"))
            }
        } label: {
            Label(L10n.tr("复制图像"), systemImage: "photo.on.rectangle")
        }
        Button {
            if let image = renderImage() { share = SharePayload(items: [image]) }
        } label: {
            Label(L10n.tr("分享图像…"), systemImage: "square.and.arrow.up")
        }
        // Only check that data exists here; the CSV text is built when the item is chosen
        // (building it for every figure on every redraw made the result screen sluggish).
        if BlockCSV.hasData(block) {
            Button {
                if let csv = BlockCSV.make(block) {
                    UIPasteboard.general.string = csv
                    onCopied?(L10n.tr("已复制数据"))
                }
            } label: {
                Label(L10n.tr("复制数据（CSV，英文）"), systemImage: "tablecells")
            }
        }
    }

    /// Renders the figure card at a fixed, publication-friendly width in the light appearance.
    @MainActor
    private func renderImage() -> UIImage? {
        let content = ReportBlockView(block: block, showsMenu: false)
            .frame(width: 420)
            .padding(12)
            .background(Color(uiColor: .systemGroupedBackground))
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - Shared chart pieces

/// Small legend item: a swatch and a label in text ink.
struct LegendItem: View {
    let color: Color
    let title: String
    var shape: Glyph = .bar

    enum Glyph { case bar, dot, line, dashed }

    var body: some View {
        HStack(spacing: 5) {
            switch shape {
            case .bar: RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            case .dot: Circle().fill(color).frame(width: 9, height: 9)
            case .line: Capsule().fill(color).frame(width: 14, height: 3)
            case .dashed:
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(color).frame(width: 3, height: 2) }
                }
                .frame(width: 14)
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Scale for the occupancy heat map (square-root scaled, as drawn).
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("少")).font(.caption).foregroundStyle(.secondary)
            LinearGradient(colors: (0...8).map { Palette.heat(Double($0) / 8) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: 8)
                .clipShape(Capsule())
            Text(L10n.tr("多")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.tr("停留时间（平方根标度）")).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.tr("热图颜色：越亮表示停留时间越长"))
    }
}

// MARK: - Arena plot

struct ArenaPlotView: View {
    let data: ArenaPlotData

    private var hasStartEnd: Bool {
        data.paths.contains { !$0.segments.isEmpty && $0.opacity > 0.6 }
    }

    var body: some View {
        let e = data.extent
        VStack(alignment: .leading, spacing: 8) {
            Canvas { ctx, size in
                draw(&ctx, size)
            }
            .aspectRatio(CGFloat(max(e.x, 1) / max(e.y, 1)), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 380)
            .accessibilityLabel(data.heat != nil ? L10n.tr("场地停留热图") : L10n.tr("场地轨迹图"))
            if data.heat != nil || hasStartEnd {
                WrapLayout(spacing: 12) {
                    if data.heat != nil { HeatLegend() }
                    if hasStartEnd && data.heat == nil {
                        LegendItem(color: Palette.okabeGreen, title: L10n.tr("起点"), shape: .dot)
                        LegendItem(color: Palette.danger, title: L10n.tr("终点"), shape: .dot)
                    }
                }
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let e = data.extent
        let pad: CGFloat = 8
        let bottom: CGFloat = 16 // room for the scale bar label
        let s = min((size.width - 2 * pad) / CGFloat(max(e.x, 1)), (size.height - 2 * pad - bottom) / CGFloat(max(e.y, 1)))
        let ox = (size.width - CGFloat(e.x) * s) / 2, oy = (size.height - bottom - CGFloat(e.y) * s) / 2
        func vp(_ p: V2) -> CGPoint { CGPoint(x: ox + CGFloat(p.x) * s, y: oy + CGFloat(p.y) * s) }
        func poly(_ pts: [V2]) -> Path {
            var path = Path()
            path.addLines(pts.map(vp))
            path.closeSubpath()
            return path
        }

        // Arena.
        if let arena = data.arena, arena.role == .arena {
            let path = poly(arena.outline(segments: 96))
            ctx.fill(path, with: .color(Palette.inset))
            ctx.stroke(path, with: .color(Color.secondary.opacity(0.5)), lineWidth: 1)
        }

        // Heat map.
        if let heat = data.heat {
            let maxV = heat.values.filter { $0.isFinite }.max() ?? 0
            if maxV > 0 {
                let cw = CGFloat(heat.cell) * s
                for r in 0..<heat.rows {
                    for c in 0..<heat.columns {
                        let v = heat.values[r * heat.columns + c]
                        guard v.isFinite else { continue }
                        let rect = CGRect(x: ox + CGFloat(c) * cw, y: oy + CGFloat(r) * cw, width: cw + 0.5, height: cw + 0.5)
                        if v <= 0 {
                            ctx.fill(Path(rect), with: .color(Palette.heat(0).opacity(0.85)))
                        } else {
                            ctx.fill(Path(rect), with: .color(Palette.heat((v / maxV).squareRoot())))
                        }
                    }
                }
            }
        }

        // Zones.
        for z in data.zones where z.role != .arena {
            let path = poly(z.outline(segments: 64))
            let color = Palette.zone(z.role)
            if !z.outlineOnly && z.role != .hole && data.heat == nil {
                ctx.fill(path, with: .color(color.opacity(z.role == .dark ? 0.22 : 0.14)))
            }
            ctx.stroke(path, with: .color(data.heat == nil ? color.opacity(0.85) : Color.white.opacity(0.85)),
                       style: StrokeStyle(lineWidth: z.outlineOnly ? 0.8 : 1.2, dash: z.outlineOnly ? [3, 3] : []))
        }

        // Paths.
        for p in data.paths {
            for seg in p.segments where seg.count > 1 {
                var path = Path()
                path.addLines(seg.map(vp))
                ctx.stroke(path, with: .color(Palette.color(p.color).opacity(p.opacity)), style: StrokeStyle(lineWidth: p.width, lineCap: .round, lineJoin: .round))
            }
        }
        if let first = data.paths.first(where: { !$0.segments.isEmpty && $0.opacity > 0.6 }) {
            func marker(_ c: CGPoint, _ color: Color) {
                let r: CGFloat = 4.5
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
            if let a = first.segments.first?.first { marker(vp(a), Palette.okabeGreen) }
            if let b = first.segments.last?.last { marker(vp(b), Palette.danger) }
        }

        // Dots and arrows.
        for d in data.dots {
            let c = vp(d.p)
            let r = CGFloat(d.radius)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Palette.color(d.color).opacity(0.85)))
        }
        for a in data.arrows {
            let p0 = vp(a.from), p1 = vp(a.to)
            var path = Path()
            path.move(to: p0)
            path.addLine(to: p1)
            let ang = atan2(p1.y - p0.y, p1.x - p0.x)
            let h: CGFloat = 4
            path.move(to: p1)
            path.addLine(to: CGPoint(x: p1.x - h * cos(ang - 0.5), y: p1.y - h * sin(ang - 0.5)))
            path.move(to: p1)
            path.addLine(to: CGPoint(x: p1.x - h * cos(ang + 0.5), y: p1.y - h * sin(ang + 0.5)))
            ctx.stroke(path, with: .color(Palette.color(a.color).opacity(0.75)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }

        // Zone labels on top, with a halo so they stay legible on the heat map and paths.
        for z in data.zones where z.role != .arena && z.showsLabel && !z.title.isEmpty {
            let label = Text(z.title).font(.system(size: 11, weight: .semibold))
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(uiColor: .systemBackground).opacity(0.9), radius: 2))
                layer.draw(label.foregroundColor(.primary), at: vp(z.center))
            }
        }

        // Scale bar.
        let unit = data.unit
        let barLen: Double = unit == "cm" ? (e.x > 60 ? 20 : 10) : (e.x / 5).rounded()
        if barLen > 0 {
            let y = size.height - 6
            let x0 = ox
            var bar = Path()
            bar.move(to: CGPoint(x: x0, y: y))
            bar.addLine(to: CGPoint(x: x0 + CGFloat(barLen) * s, y: y))
            ctx.stroke(bar, with: .color(.secondary), lineWidth: 2)
            ctx.draw(Text("\(Int(barLen)) \(unit)").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary),
                     at: CGPoint(x: x0 + CGFloat(barLen) * s + 5, y: y), anchor: .leading)
        }
    }
}

// MARK: - Timeline

/// Ethogram: one row per behavior. A grid keeps the label column as wide as the longest label.
struct TimelineChart: View {
    let data: TimelineData
    private let rowHeight: CGFloat = 20

    private var span: Double { max(data.end - data.start, 1e-6) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(data.tracks) { t in
                GridRow {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.color(t.color)).frame(width: 8, height: 8)
                        Text(t.name).font(.caption).lineLimit(1)
                    }
                    .frame(maxWidth: 130, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    Canvas { ctx, size in draw(t, &ctx, size) }
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel(t.name)
                        .accessibilityValue(summary(t))
                }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                HStack {
                    Text(Fmt.clock(0))
                    Spacer()
                    Text(Fmt.clock(span / 2))
                    Spacer()
                    Text(Fmt.clock(span))
                }
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            if !data.epochs.isEmpty {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    WrapLayout(spacing: 10) {
                        ForEach(Array(uniqueEpochs.enumerated()), id: \.offset) { _, e in
                            LegendItem(color: Palette.color(e.color).opacity(0.35), title: e.name)
                        }
                    }
                }
            }
        }
    }

    private var uniqueEpochs: [Epoch] {
        var seen = Set<String>()
        return data.epochs.filter { seen.insert($0.name).inserted }
    }

    private func summary(_ t: TimelineTrack) -> String {
        let total = t.bouts.reduce(0) { $0 + max(0, $1.end - $1.start) }
        return String(format: L10n.tr("%d 次，共 %.1f 秒"), t.bouts.count, total)
    }

    private func draw(_ t: TimelineTrack, _ ctx: inout GraphicsContext, _ size: CGSize) {
        func x(_ time: Double) -> CGFloat { CGFloat((time - data.start) / span) * size.width }
        let bg = CGRect(origin: .zero, size: size)
        ctx.fill(Path(roundedRect: bg, cornerRadius: 4), with: .color(Palette.inset))
        for e in data.epochs {
            let r = CGRect(x: x(e.start), y: 0, width: max(1.5, x(e.end) - x(e.start)), height: size.height)
            ctx.fill(Path(r), with: .color(Palette.color(e.color).opacity(0.18)))
        }
        let color = Palette.color(t.color)
        for b in t.bouts {
            let x0 = max(0, x(b.start)), x1 = min(size.width, x(b.end))
            guard x1 > x0 - 0.5 else { continue }
            let r = CGRect(x: x0, y: 2, width: max(1.2, x1 - x0), height: size.height - 4)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color))
        }
    }
}

// MARK: - Bars

struct BarsChart: View {
    let data: BarData

    private var grouped: Bool { data.items.contains { $0.group != nil } }

    private var legend: (domain: [String], range: [Color]) {
        var seen: [String] = []
        var colors: [Color] = []
        for i in data.items where !seen.contains(i.label) {
            seen.append(i.label)
            colors.append(Palette.color(i.color))
        }
        return (seen, colors)
    }

    var body: some View {
        if data.items.isEmpty {
            Text(L10n.tr("没有数据")).font(.footnote).foregroundStyle(.secondary)
        } else if grouped {
            groupedChart
        } else if data.horizontal {
            horizontalChart
        } else {
            verticalChart
        }
    }

    private func label(_ v: Double) -> String { String(format: "%.\(data.decimals)f", v) }

    private var verticalChart: some View {
        Chart {
            ForEach(data.items) { item in
                BarMark(x: .value(L10n.tr("类别"), item.label), y: .value(data.unit, item.value), width: .ratio(0.6))
                    .foregroundStyle(Palette.color(item.color))
                    .cornerRadius(4)
                    .annotation(position: .top, spacing: 3) {
                        if data.items.count <= 8 {
                            Text(label(item.value)).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(item.label)
                    .accessibilityValue("\(label(item.value)) \(data.unit)")
            }
            if let ref = data.referenceLine {
                RuleMark(y: .value(L10n.tr("参考"), ref))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYAxisLabel(data.unit)
        .frame(height: 200)
    }

    private var horizontalChart: some View {
        Chart {
            ForEach(data.items) { item in
                BarMark(x: .value(data.unit, item.value), y: .value(L10n.tr("类别"), item.label))
                    .foregroundStyle(Palette.color(item.color))
                    .cornerRadius(4)
                    .annotation(position: .trailing, spacing: 4) {
                        Text(label(item.value)).font(.caption2.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(item.label)
                    .accessibilityValue("\(label(item.value)) \(data.unit)")
            }
        }
        .chartXAxisLabel(data.unit)
        .frame(height: CGFloat(max(3, data.items.count)) * 30 + 30)
    }

    private var groupedChart: some View {
        let l = legend
        return Chart {
            ForEach(data.items) { item in
                BarMark(x: .value(L10n.tr("分段"), item.group ?? ""), y: .value(data.unit, item.value))
                    .foregroundStyle(by: .value(L10n.tr("类型"), item.label))
                    .position(by: .value(L10n.tr("类型"), item.label))
                    .cornerRadius(3)
            }
        }
        .chartForegroundStyleScale(domain: l.domain, range: l.range)
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxisLabel(data.unit)
        .frame(height: 220)
    }
}

// MARK: - Lines

struct LineChartView: View {
    let data: LineData
    @State private var selectedX: Double?

    private struct Row: Identifiable {
        let id: Int
        let series: String
        let x: Double
        let y: Double
    }

    /// Many repeated traces (e.g. one per looming trial) are drawn as thin neutral lines with
    /// their mean emphasized, instead of cycling through hues.
    private let isTrialStack: Bool
    // Derived once per figure instead of on every redraw (scrubbing redraws continuously).
    private let rows: [Row]
    private let meanSeries: [LinePoint]

    init(data: LineData) {
        self.data = data
        isTrialStack = data.series.count > 4
        var out: [Row] = []
        var k = 0
        for s in data.series {
            for p in s.points where p.x.isFinite && p.y.isFinite {
                out.append(Row(id: k, series: s.name, x: p.x, y: p.y))
                k += 1
            }
        }
        rows = out
        meanSeries = data.series.count > 4 ? Self.mean(of: data.series) : []
    }

    private static func mean(of series: [LineSeries]) -> [LinePoint] {
        let pts = series.flatMap { $0.points }.filter { $0.x.isFinite && $0.y.isFinite }
        guard let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max(), hi > lo else { return [] }
        let bins = 80
        let w = (hi - lo) / Double(bins)
        var sum = [Double](repeating: 0, count: bins), n = [Int](repeating: 0, count: bins)
        for p in pts {
            let b = min(bins - 1, max(0, Int((p.x - lo) / w)))
            sum[b] += p.y
            n[b] += 1
        }
        return (0..<bins).compactMap { b in n[b] > 0 ? LinePoint(x: lo + (Double(b) + 0.5) * w, y: sum[b] / Double(n[b])) : nil }
    }

    private var domain: [String] { data.series.map { $0.name } }
    private var colors: [Color] { data.series.map { Palette.color($0.color) } }

    /// Values of each series nearest to the selected x.
    private func readout(at x: Double) -> [(String, Double, Color)] {
        let source: [(String, [LinePoint], Color)] = isTrialStack
            ? [(L10n.tr("平均"), meanSeries, Color.accentColor)]
            : data.series.map { ($0.name, $0.points, Palette.color($0.color)) }
        return source.compactMap { name, points, color in
            guard let p = points.filter({ $0.y.isFinite }).min(by: { abs($0.x - x) < abs($1.x - x) }) else { return nil }
            return (name, p.y, color)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if isTrialStack {
                HStack(spacing: 14) {
                    LegendItem(color: Color.secondary.opacity(0.5), title: String(format: L10n.tr("单次（%d）"), data.series.count), shape: .line)
                    LegendItem(color: .accentColor, title: L10n.tr("平均"), shape: .line)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.epochs) { e in
                RectangleMark(xStart: .value(data.xLabel, e.start), xEnd: .value(data.xLabel, e.end))
                    .foregroundStyle(Palette.color(e.color).opacity(0.14))
            }
            if isTrialStack {
                ForEach(rows) { r in
                    LineMark(x: .value(data.xLabel, r.x), y: .value(data.yLabel, r.y), series: .value(L10n.tr("系列"), r.series))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(meanSeries.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value(data.xLabel, p.x), y: .value(data.yLabel, p.y), series: .value(L10n.tr("系列"), "__mean"))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                ForEach(rows) { r in
                    LineMark(x: .value(data.xLabel, r.x), y: .value(data.yLabel, r.y), series: .value(L10n.tr("系列"), r.series))
                        .foregroundStyle(by: .value(L10n.tr("系列"), r.series))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let y = data.referenceY {
                RuleMark(y: .value(L10n.tr("参考"), y))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let x = data.referenceX {
                RuleMark(x: .value(L10n.tr("参考"), x))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let sx = selectedX {
                RuleMark(x: .value(data.xLabel, sx))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        selectionCard(sx)
                    }
            }
        }
        .modifier(SeriesScale(domain: domain, range: colors, enabled: !isTrialStack))
        .chartLegend(!isTrialStack && data.series.count > 1 ? .visible : .hidden)
        .chartXAxisLabel(data.xLabel)
        .chartYAxisLabel(data.yLabel)
        .chartXSelection(value: $selectedX)
        .modifier(YRangeModifier(range: data.yRange))
        .frame(height: 220)
    }

    private func selectionCard(_ x: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(data.xLabel) \(Fmt.number(x, 2))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(readout(at: x).prefix(4).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Capsule().fill(item.2).frame(width: 10, height: 3)
                    Text(item.0).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(Fmt.number(item.1, 2)).font(.caption2.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct SeriesScale: ViewModifier {
    let domain: [String]
    let range: [Color]
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.chartForegroundStyleScale(domain: domain, range: range)
        } else {
            content
        }
    }
}

private struct YRangeModifier: ViewModifier {
    let range: ClosedRange<Double>?

    func body(content: Content) -> some View {
        if let range {
            content.chartYScale(domain: range)
        } else {
            content
        }
    }
}

// MARK: - Polar

struct PolarPlotView: View {
    let data: PolarData

    var body: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in draw(&ctx, size) }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.tr("方向分布极坐标图"))
                .accessibilityValue(accessibilitySummary)
            WrapLayout(spacing: 14) {
                if let m = data.meanAngle {
                    LegendItem(color: .primary, title: String(format: L10n.tr("平均方向 %.0f°"), m), shape: .line)
                }
                if let r = data.resultantLength {
                    Text(String(format: L10n.tr("向量长度 %.2f"), r))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if data.referenceAngle != nil {
                    LegendItem(color: Palette.amber, title: L10n.tr("参考方向"), shape: .dashed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let m = data.meanAngle { parts.append(String(format: L10n.tr("平均方向 %.0f°"), m)) }
        if let r = data.resultantLength { parts.append(String(format: L10n.tr("向量长度 %.2f"), r)) }
        return parts.joined(separator: ", ")
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 - 24
        let n = max(1, data.values.count)
        let maxV = max(data.values.max() ?? 0, 1e-9)
        func pt(_ deg: Double, _ r: CGFloat) -> CGPoint {
            let a = deg * .pi / 180
            return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y - r * CGFloat(sin(a)))
        }
        // Rings and spokes.
        for f in [0.25, 0.5, 0.75, 1.0] {
            let r = R * CGFloat(f)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color.secondary.opacity(f == 1 ? 0.45 : 0.18)), lineWidth: f == 1 ? 1 : 0.7)
        }
        for deg in stride(from: 0.0, to: 360.0, by: 45.0) {
            var p = Path()
            p.move(to: c)
            p.addLine(to: pt(deg, R))
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.18)), lineWidth: 0.7)
        }
        // Wedges.
        let color = Palette.color(data.color)
        let width = 360.0 / Double(n)
        for (i, v) in data.values.enumerated() where v > 0 {
            let r = R * CGFloat((v / maxV).squareRoot())
            let a0 = Double(i) * width, a1 = a0 + width
            var p = Path()
            p.move(to: c)
            for k in 0...4 { p.addLine(to: pt(a0 + (a1 - a0) * Double(k) / 4, r)) }
            p.closeSubpath()
            ctx.fill(p, with: .color(color.opacity(0.75)))
            ctx.stroke(p, with: .color(color), lineWidth: 0.5)
        }
        // Mean vector (length = resultant length × outer radius).
        if let m = data.meanAngle, let rl = data.resultantLength {
            var p = Path()
            let tip = pt(m, R * CGFloat(min(1, rl)))
            p.move(to: c)
            p.addLine(to: tip)
            ctx.stroke(p, with: .color(.primary), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)), with: .color(.primary))
        }
        if let ref = data.referenceAngle {
            var p = Path()
            p.move(to: c)
            p.addLine(to: pt(ref, R))
            ctx.stroke(p, with: .color(Palette.amber), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        // Labels.
        for (deg, text) in [(0.0, "0°"), (90.0, "90°"), (180.0, "180°"), (270.0, "270°")] {
            ctx.draw(Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary), at: pt(deg, R + 13))
        }
        ctx.draw(Text(String(format: L10n.tr("外圈 %.1f %@"), maxV, data.unit)).font(.system(size: 11)).foregroundColor(.secondary),
                 at: CGPoint(x: size.width - 2, y: size.height - 6), anchor: .trailing)
    }
}

// MARK: - Table

struct TableBlockView: View {
    let data: TableData

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    ForEach(data.columns.indices, id: \.self) { j in
                        Text(data.columns[j]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(data.rows.indices, id: \.self) { i in
                    GridRow {
                        ForEach(data.rows[i].indices, id: \.self) { j in
                            HStack(spacing: 4) {
                                if j == 0, i < data.rowColors.count, let c = data.rowColors[i] {
                                    Circle().fill(Palette.color(c)).frame(width: 6, height: 6)
                                }
                                Text(data.rows[i][j]).font(.caption).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
