// PoseResultFigures.swift — the RodentPose iOS 1.0 result screen on macOS: headline measure with its
// scale, all measures, the report figures (arena plot, ethogram, bars, lines, polar, tables), detection
// quality and the methods text. Ported from RodentPose ReportBlocks.swift, ResultStepView.swift,
// ReportFormatting.swift and DesignSystem.swift; drawing, colors and scales are unchanged. Interface
// text goes through RPTexts.tr with RodentPose's own catalog; copied data and exports are English.

import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

// MARK: - Palette (RodentPose DesignSystem.Palette)

enum RPPalette {
    // Okabe–Ito (Wong 2011, Nature Methods) — color-vision-deficiency-safe series colors.
    static let okabeBlue = Color(red: 0.000, green: 0.447, blue: 0.698)
    static let okabeVermillion = Color(red: 0.835, green: 0.369, blue: 0.000)
    static let okabeGreen = Color(red: 0.000, green: 0.620, blue: 0.451)
    static let okabePurple = Color(red: 0.800, green: 0.475, blue: 0.655)

    // Zone and mark tints.
    static let coral = Color(red: 0.949, green: 0.420, blue: 0.380)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.106)
    static let indigo = Color(red: 0.365, green: 0.396, blue: 0.945)
    static let teal = Color(red: 0.137, green: 0.639, blue: 0.690)
    static let violet = Color(red: 0.616, green: 0.388, blue: 0.898)
    static let slate = Color(red: 0.443, green: 0.494, blue: 0.573)
    static let gray = Color(nsColor: .systemGray)

    static let success = Color.adaptive(0x0A7A44, 0x3DD27F)
    static let warning = Color.adaptive(0xA65700, 0xFFB547)
    static let danger = Color.adaptive(0xD12E2E, 0xFF6E6E)

    static let keypoints: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]
    static func keypoint(_ k: Int) -> Color { keypoints[((k % 6) + 6) % 6] }

    static func category(_ c: ParadigmCategory) -> Color {
        switch c {
        case .social: return Color.adaptive(0xBE3A32, 0xFF7B6E)
        case .navigation: return Color.adaptive(0x4F46E5, 0x8C88FF)
        case .anxiety: return Color.adaptive(0x0B7480, 0x3CC3CD)
        case .memory: return Color.adaptive(0x7C4DDB, 0xB593FF)
        case .motor: return Color.adaptive(0xAB4F08, 0xF2A04E)
        case .general: return Color.adaptive(0x5B6474, 0xA3ABB8)
        }
    }

    static func categoryFill(_ c: ParadigmCategory) -> Color {
        switch c {
        case .social: return Color(hex: 0xBE3A32)
        case .navigation: return Color(hex: 0x4F46E5)
        case .anxiety: return Color(hex: 0x0B7480)
        case .memory: return Color(hex: 0x7C4DDB)
        case .motor: return Color(hex: 0xAB4F08)
        case .general: return Color(hex: 0x5B6474)
        }
    }

    static func color(_ key: ColorKey) -> Color {
        switch key {
        case .accent: return .accentColor
        case .neutral: return gray
        case .warning: return amber
        case .social: return coral
        case .object: return gray
        case .novel: return amber
        case .familiar: return okabeBlue
        case .center: return indigo
        case .periphery: return teal
        case .open: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .closed: return gray
        case .light: return Color(red: 0.98, green: 0.78, blue: 0.18)
        case .dark: return Color(red: 0.30, green: 0.32, blue: 0.42)
        case .freezing: return indigo
        case .sniff: return Color(red: 0.91, green: 0.30, blue: 0.56)
        case .headDip: return Color(red: 0.92, green: 0.26, blue: 0.24)
        case .sap: return violet
        case .poke: return Color(red: 0.91, green: 0.30, blue: 0.56)
        case .target: return okabeGreen
        case .error: return Color(red: 0.92, green: 0.26, blue: 0.24)
        case .shelter: return teal
        case .escape: return okabeGreen
        case .cw: return okabeVermillion
        case .ccw: return okabeBlue
        case .animalA: return okabeBlue
        case .animalB: return okabeVermillion
        case .nose: return .red
        case .body: return .cyan
        case .tail: return .purple
        case .series1: return okabeBlue
        case .series2: return okabeGreen
        case .series3: return okabeVermillion
        case .series4: return okabePurple
        }
    }

    static func zone(_ role: ZoneRole) -> Color {
        switch role {
        case .arena: return gray
        case .center: return indigo
        case .periphery, .corner: return teal
        case .chamber, .cup, .enclosure, .mazeCenter, .hole: return gray
        case .social, .interaction: return coral
        case .object: return gray
        case .novel: return amber
        case .familiar: return okabeBlue
        case .open: return color(.open)
        case .closed: return gray
        case .arm: return indigo
        case .choice: return amber
        case .light: return color(.light)
        case .dark: return color(.dark)
        case .shelter: return teal
        case .target, .quadrant: return okabeGreen
        case .cue: return amber
        }
    }

    /// Sequential occupancy scale (dark blue → teal → yellow); pair with RPHeatLegend.
    static let heatStops: [(Double, Double, Double)] = [(0.12, 0.10, 0.36), (0.16, 0.38, 0.62), (0.13, 0.62, 0.60), (0.48, 0.80, 0.38), (0.99, 0.88, 0.22)]

    static func heat(_ t: Double) -> Color {
        let stops = heatStops
        let x = min(max(t, 0), 1) * Double(stops.count - 1)
        let i = min(Int(x), stops.count - 2)
        let f = x - Double(i)
        let a = stops[i], b = stops[i + 1]
        return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
    }
}

enum RPFmt {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func number(_ v: Double, _ decimals: Int = 1) -> String {
        guard v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }
}

// MARK: - Small pieces (RodentPose DesignSystem)

struct RPTag: View {
    let text: String
    var color: Color = .secondary
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? color : color.opacity(0.12), in: Capsule())
    }
}

/// Inline message. The icon carries the status color; the text stays in primary ink.
struct RPBanner: View {
    enum Style { case info, warning, success, error }
    let text: String
    var style: Style = .info

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: Self.icon(style)).foregroundStyle(Self.color(style))
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.color(style).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Self.color(style).opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    static func icon(_ s: Style) -> String {
        switch s {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    static func color(_ s: Style) -> Color {
        switch s {
        case .info: return .accentColor
        case .warning: return RPPalette.warning
        case .success: return RPPalette.success
        case .error: return RPPalette.danger
        }
    }
}

/// Several notices collapse into one expandable card.
struct RPNoticeList: View {
    let notices: [String]
    var style: RPBanner.Style = .warning
    @State private var expanded = false

    var body: some View {
        if notices.count == 1 {
            RPBanner(text: notices[0], style: style)
        } else if notices.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: RPBanner.icon(style)).foregroundStyle(RPBanner.color(style))
                        Text(String(format: RPTexts.tr("%d 条提示"), notices.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(Array((expanded ? notices : Array(notices.prefix(1))).enumerated()), id: \.offset) { _, n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(RPBanner.color(style)).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(n).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !expanded {
                    Text(String(format: RPTexts.tr("还有 %d 条"), notices.count - 1))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RPBanner.color(style).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(RPBanner.color(style).opacity(0.25), lineWidth: 1)
            }
        }
    }
}

struct RPMetricTile: View {
    let metric: MetricValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.formatted)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if metric.highlight {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .help(metric.info ?? "")
        .accessibilityElement(children: .combine)
    }
}

struct RPMetricGrid: View {
    let metrics: [MetricValue]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
            ForEach(metrics) { m in
                RPMetricTile(metric: m)
            }
        }
    }
}

/// Small legend item: a swatch and a label in text ink.
struct RPLegendItem: View {
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
struct RPHeatLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(RPTexts.tr("少")).font(.caption).foregroundStyle(.secondary)
            LinearGradient(colors: (0...8).map { RPPalette.heat(Double($0) / 8) }, startPoint: .leading, endPoint: .trailing)
                .frame(width: 110, height: 8)
                .clipShape(Capsule())
            Text(RPTexts.tr("多")).font(.caption).foregroundStyle(.secondary)
            Text(RPTexts.tr("停留时间（平方根标度）")).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RPTexts.tr("热图颜色：越亮表示停留时间越长"))
    }
}

// MARK: - Block card

struct RPReportBlockView: View {
    let block: ReportBlock
    /// False when the view is rendered into an image (no menu button).
    var showsMenu = true
    var onMessage: ((String) -> Void)? = nil

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
        FigureCard {
            FigureCardHeader(title: block.title, symbol: symbol, subtitle: block.caption) {
                if showsMenu { menu }
            }
            content
        }
        .contextMenu { if showsMenu { menuItems } }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .arena(let d): RPArenaPlotView(data: d)
        case .timeline(let d): RPTimelineChart(data: d)
        case .bars(let d): RPBarsChart(data: d)
        case .line(let d): RPLineChartView(data: d)
        case .polar(let d): RPPolarPlotView(data: d)
        case .table(let d): RPTableBlockView(data: d)
        }
    }

    private var menu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(RPTexts.tr("图表操作"))
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(RPTexts.tr("复制图像")) { copyImage() }
        Button(L("Save image…", "保存图像…")) { saveImage() }
        if RPBlockCSV.make(block) != nil {
            Button(RPTexts.tr("复制数据（CSV，英文）")) { copyCSV() }
        }
    }

    @MainActor
    private func renderedPNG() -> Data? {
        FigureExport.png(RPReportBlockView(block: block, showsMenu: false))
    }

    @MainActor
    private func copyImage() {
        guard let data = renderedPNG(), let image = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        onMessage?(RPTexts.tr("已复制图像"))
    }

    @MainActor
    private func saveImage() {
        guard let data = renderedPNG() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "rodentpose_" + FigureExport.slug(RPTexts.english(block.title)) + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) } catch { onMessage?(error.localizedDescription) }
    }

    private func copyCSV() {
        guard let csv = RPBlockCSV.make(block) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        onMessage?(RPTexts.tr("已复制数据"))
    }
}

// MARK: - Arena plot

struct RPArenaPlotView: View {
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
            .accessibilityLabel(data.heat != nil ? RPTexts.tr("场地停留热图") : RPTexts.tr("场地轨迹图"))
            if data.heat != nil || hasStartEnd {
                WrapLayout(spacing: 12) {
                    if data.heat != nil { RPHeatLegend() }
                    if hasStartEnd && data.heat == nil {
                        RPLegendItem(color: RPPalette.okabeGreen, title: RPTexts.tr("起点"), shape: .dot)
                        RPLegendItem(color: RPPalette.danger, title: RPTexts.tr("终点"), shape: .dot)
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
            ctx.fill(path, with: .color(FigureSurface.inset))
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
                            ctx.fill(Path(rect), with: .color(RPPalette.heat(0).opacity(0.85)))
                        } else {
                            ctx.fill(Path(rect), with: .color(RPPalette.heat((v / maxV).squareRoot())))
                        }
                    }
                }
            }
        }

        // Zones.
        for z in data.zones where z.role != .arena {
            let path = poly(z.outline(segments: 64))
            let color = RPPalette.zone(z.role)
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
                ctx.stroke(path, with: .color(RPPalette.color(p.color).opacity(p.opacity)),
                           style: StrokeStyle(lineWidth: p.width, lineCap: .round, lineJoin: .round))
            }
        }
        if let first = data.paths.first(where: { !$0.segments.isEmpty && $0.opacity > 0.6 }) {
            func marker(_ c: CGPoint, _ color: Color) {
                let r: CGFloat = 4.5
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
            if let a = first.segments.first?.first { marker(vp(a), RPPalette.okabeGreen) }
            if let b = first.segments.last?.last { marker(vp(b), RPPalette.danger) }
        }

        // Dots and arrows.
        for d in data.dots {
            let c = vp(d.p)
            let r = CGFloat(d.radius)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(RPPalette.color(d.color).opacity(0.85)))
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
            ctx.stroke(path, with: .color(RPPalette.color(a.color).opacity(0.75)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        }

        // Zone labels on top, with a halo so they stay legible on the heat map and paths.
        for z in data.zones where z.role != .arena && z.showsLabel && !z.title.isEmpty {
            let label = Text(z.title).font(.system(size: 11, weight: .semibold))
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(nsColor: .textBackgroundColor).opacity(0.9), radius: 2))
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

// MARK: - Timeline (ethogram)

struct RPTimelineChart: View {
    let data: TimelineData
    private let rowHeight: CGFloat = 20

    private var span: Double { max(data.end - data.start, 1e-6) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(data.tracks) { t in
                GridRow {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(RPPalette.color(t.color)).frame(width: 8, height: 8)
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
                    Text(RPFmt.clock(0))
                    Spacer()
                    Text(RPFmt.clock(span / 2))
                    Spacer()
                    Text(RPFmt.clock(span))
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
                            RPLegendItem(color: RPPalette.color(e.color).opacity(0.35), title: e.name)
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
        return String(format: RPTexts.tr("%d 次，共 %.1f 秒"), t.bouts.count, total)
    }

    private func draw(_ t: TimelineTrack, _ ctx: inout GraphicsContext, _ size: CGSize) {
        func x(_ time: Double) -> CGFloat { CGFloat((time - data.start) / span) * size.width }
        let bg = CGRect(origin: .zero, size: size)
        ctx.fill(Path(roundedRect: bg, cornerRadius: 4), with: .color(FigureSurface.inset))
        for e in data.epochs {
            let r = CGRect(x: x(e.start), y: 0, width: max(1.5, x(e.end) - x(e.start)), height: size.height)
            ctx.fill(Path(r), with: .color(RPPalette.color(e.color).opacity(0.18)))
        }
        let color = RPPalette.color(t.color)
        for b in t.bouts {
            let x0 = max(0, x(b.start)), x1 = min(size.width, x(b.end))
            guard x1 > x0 - 0.5 else { continue }
            let r = CGRect(x: x0, y: 2, width: max(1.2, x1 - x0), height: size.height - 4)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color))
        }
    }
}

// MARK: - Bars

struct RPBarsChart: View {
    let data: BarData

    private var grouped: Bool { data.items.contains { $0.group != nil } }

    private var legend: (domain: [String], range: [Color]) {
        var seen: [String] = []
        var colors: [Color] = []
        for i in data.items where !seen.contains(i.label) {
            seen.append(i.label)
            colors.append(RPPalette.color(i.color))
        }
        return (seen, colors)
    }

    var body: some View {
        if data.items.isEmpty {
            Text(RPTexts.tr("没有数据")).font(.footnote).foregroundStyle(.secondary)
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
                BarMark(x: .value(RPTexts.tr("类别"), item.label), y: .value(data.unit, item.value), width: .ratio(0.6))
                    .foregroundStyle(RPPalette.color(item.color))
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
                RuleMark(y: .value(RPTexts.tr("参考"), ref))
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
                BarMark(x: .value(data.unit, item.value), y: .value(RPTexts.tr("类别"), item.label))
                    .foregroundStyle(RPPalette.color(item.color))
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
                BarMark(x: .value(RPTexts.tr("分段"), item.group ?? ""), y: .value(data.unit, item.value))
                    .foregroundStyle(by: .value(RPTexts.tr("类型"), item.label))
                    .position(by: .value(RPTexts.tr("类型"), item.label))
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

struct RPLineChartView: View {
    let data: LineData
    @State private var selectedX: Double?

    private struct Row: Identifiable {
        let id: Int
        let series: String
        let x: Double
        let y: Double
    }

    /// Many repeated traces (e.g. one per looming trial) are drawn as thin neutral lines with their
    /// mean emphasized, instead of cycling through hues.
    private var isTrialStack: Bool { data.series.count > 4 }

    private var rows: [Row] {
        var out: [Row] = []
        var k = 0
        for s in data.series {
            for p in s.points where p.x.isFinite && p.y.isFinite {
                out.append(Row(id: k, series: s.name, x: p.x, y: p.y))
                k += 1
            }
        }
        return out
    }

    private var meanSeries: [LinePoint] {
        let pts = data.series.flatMap { $0.points }.filter { $0.x.isFinite && $0.y.isFinite }
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
    private var colors: [Color] { data.series.map { RPPalette.color($0.color) } }

    /// Values of each series nearest to the selected x.
    private func readout(at x: Double) -> [(String, Double, Color)] {
        let source: [(String, [LinePoint], Color)] = isTrialStack
            ? [(RPTexts.tr("平均"), meanSeries, Color.accentColor)]
            : data.series.map { ($0.name, $0.points, RPPalette.color($0.color)) }
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
                    RPLegendItem(color: Color.secondary.opacity(0.5), title: String(format: RPTexts.tr("单次（%d）"), data.series.count), shape: .line)
                    RPLegendItem(color: .accentColor, title: RPTexts.tr("平均"), shape: .line)
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(data.epochs) { e in
                RectangleMark(xStart: .value(data.xLabel, e.start), xEnd: .value(data.xLabel, e.end))
                    .foregroundStyle(RPPalette.color(e.color).opacity(0.14))
            }
            if isTrialStack {
                ForEach(rows) { r in
                    LineMark(x: .value(data.xLabel, r.x), y: .value(data.yLabel, r.y), series: .value(RPTexts.tr("系列"), r.series))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(meanSeries.enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value(data.xLabel, p.x), y: .value(data.yLabel, p.y), series: .value(RPTexts.tr("系列"), "__mean"))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                ForEach(rows) { r in
                    LineMark(x: .value(data.xLabel, r.x), y: .value(data.yLabel, r.y), series: .value(RPTexts.tr("系列"), r.series))
                        .foregroundStyle(by: .value(RPTexts.tr("系列"), r.series))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            if let y = data.referenceY {
                RuleMark(y: .value(RPTexts.tr("参考"), y))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if let x = data.referenceX {
                RuleMark(x: .value(RPTexts.tr("参考"), x))
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
        .modifier(RPSeriesScale(domain: domain, range: colors, enabled: !isTrialStack))
        .chartLegend(!isTrialStack && data.series.count > 1 ? .visible : .hidden)
        .chartXAxisLabel(data.xLabel)
        .chartYAxisLabel(data.yLabel)
        .chartXSelection(value: $selectedX)
        .modifier(RPYRangeModifier(range: data.yRange))
        .frame(height: 220)
    }

    private func selectionCard(_ x: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(data.xLabel) \(RPFmt.number(x, 2))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(readout(at: x).prefix(4).enumerated()), id: \.offset) { _, item in
                HStack(spacing: 5) {
                    Capsule().fill(item.2).frame(width: 10, height: 3)
                    Text(item.0).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(RPFmt.number(item.1, 2)).font(.caption2.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(FigureSurface.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(FigureSurface.hairline, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

private struct RPSeriesScale: ViewModifier {
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

private struct RPYRangeModifier: ViewModifier {
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

struct RPPolarPlotView: View {
    let data: PolarData

    var body: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in draw(&ctx, size) }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(RPTexts.tr("方向分布极坐标图"))
                .accessibilityValue(accessibilitySummary)
            WrapLayout(spacing: 14) {
                if let m = data.meanAngle {
                    RPLegendItem(color: .primary, title: String(format: RPTexts.tr("平均方向 %.0f°"), m), shape: .line)
                }
                if let r = data.resultantLength {
                    Text(String(format: RPTexts.tr("向量长度 %.2f"), r))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if data.referenceAngle != nil {
                    RPLegendItem(color: RPPalette.amber, title: RPTexts.tr("参考方向"), shape: .dashed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let m = data.meanAngle { parts.append(String(format: RPTexts.tr("平均方向 %.0f°"), m)) }
        if let r = data.resultantLength { parts.append(String(format: RPTexts.tr("向量长度 %.2f"), r)) }
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
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(Color.secondary.opacity(f == 1 ? 0.45 : 0.18)), lineWidth: f == 1 ? 1 : 0.7)
        }
        for deg in stride(from: 0.0, to: 360.0, by: 45.0) {
            var p = Path()
            p.move(to: c)
            p.addLine(to: pt(deg, R))
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.18)), lineWidth: 0.7)
        }
        // Wedges.
        let color = RPPalette.color(data.color)
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
            ctx.stroke(p, with: .color(RPPalette.amber), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        // Labels.
        for (deg, text) in [(0.0, "0°"), (90.0, "90°"), (180.0, "180°"), (270.0, "270°")] {
            ctx.draw(Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary), at: pt(deg, R + 13))
        }
        ctx.draw(Text(String(format: RPTexts.tr("外圈 %.1f %@"), maxV, data.unit)).font(.system(size: 11)).foregroundColor(.secondary),
                 at: CGPoint(x: size.width - 2, y: size.height - 6), anchor: .trailing)
    }
}

// MARK: - Table

struct RPTableBlockView: View {
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
                            RPTableCell(text: data.rows[i][j], dot: dotColor(row: i, column: j))
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func dotColor(row i: Int, column j: Int) -> Color? {
        guard j == 0, i < data.rowColors.count, let c = data.rowColors[i] else { return nil }
        return RPPalette.color(c)
    }
}

private struct RPTableCell: View {
    let text: String
    let dot: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text).font(.caption).monospacedDigit()
        }
    }
}

// MARK: - Key result (ResultStepView.KeyResultCard / ScaleBar)

/// Bounded measures that have a natural scale (ReportFormatting.MetricScale).
struct RPMetricScale {
    let range: ClosedRange<Double>
    let reference: Double?
    let referenceLabel: String?

    init?(_ m: MetricValue) {
        guard let v = m.value, v.isFinite else { return nil }
        let isIndex = m.key.hasSuffix("_index") || m.key == "di" || m.key == "turn_bias"
        if isIndex, (-1.0...1.0).contains(v) {
            range = -1...1
            reference = 0
            referenceLabel = RPTexts.tr("0 = 无偏好")
        } else if m.unit == "%", (0.0...100.0).contains(v) {
            range = 0...100
            if m.key == "alternation_pct" {
                reference = 50
                referenceLabel = RPTexts.tr("50% = 随机水平")
            } else {
                reference = nil
                referenceLabel = nil
            }
        } else {
            return nil
        }
    }
}

struct RPKeyResultCard: View {
    let metric: MetricValue
    let category: ParadigmCategory

    var body: some View {
        FigureCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metric.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                RPTag(text: RPTexts.tr("主要指标"), color: RPPalette.category(category))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.formatted)
                    .font(.system(size: 44, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if let scale = RPMetricScale(metric), let v = metric.value {
                RPScaleBar(scale: scale, value: v, color: RPPalette.categoryFill(category))
            }
            if let info = metric.info {
                Text(info)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RPScaleBar: View {
    let scale: RPMetricScale
    let value: Double
    let color: Color

    private func fraction(_ x: Double) -> CGFloat {
        let span = scale.range.upperBound - scale.range.lowerBound
        return CGFloat(min(max((x - scale.range.lowerBound) / span, 0), 1))
    }

    private func label(_ x: Double) -> String {
        scale.range.upperBound == 100 ? String(format: "%.0f%%", x) : (x > 0 ? String(format: "+%.0f", x) : String(format: "%.0f", x))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let origin = fraction(scale.reference ?? scale.range.lowerBound)
                let x = fraction(value)
                ZStack(alignment: .leading) {
                    Capsule().fill(FigureSurface.inset).frame(height: 8)
                    Rectangle()
                        .fill(color)
                        .frame(width: max(2, abs(x - origin) * w), height: 8)
                        .offset(x: min(x, origin) * w)
                        .clipShape(Capsule())
                    if scale.reference != nil {
                        Rectangle().fill(Color.primary.opacity(0.55)).frame(width: 1.5, height: 16)
                            .offset(x: origin * w - 0.75)
                    }
                    Circle()
                        .fill(color)
                        .overlay { Circle().strokeBorder(FigureSurface.card, lineWidth: 2) }
                        .frame(width: 14, height: 14)
                        .offset(x: x * w - 7)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text(label(scale.range.lowerBound))
                Spacer()
                if let ref = scale.referenceLabel { Text(ref) }
                Spacer()
                Text(label(scale.range.upperBound))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Quality (ResultStepView.QualityCard)

struct RPQualityCard: View {
    let quality: QualityInfo

    private var level: (String, RPBanner.Style)? {
        guard quality.framesInWindow > 0 else { return nil }
        if quality.detectionRate >= 0.95 { return (RPTexts.tr("检出率良好"), .success) }
        if quality.detectionRate >= 0.8 { return (RPTexts.tr("检出率尚可，建议抽查回看"), .warning) }
        return (RPTexts.tr("检出率偏低，请先回看检查"), .error)
    }

    var body: some View {
        FigureCard {
            FigureCardHeader(title: RPTexts.tr("识别质量"), symbol: "checkmark.seal") {
                if let level {
                    Label(level.0, systemImage: RPBanner.icon(level.1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RPBanner.color(level.1))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            VStack(spacing: 6) {
                FigureInfoRow(key: RPTexts.tr("检出率（分析时间段）"), value: String(format: "%.1f%%", quality.detectionRate * 100))
                FigureInfoRow(key: RPTexts.tr("分析帧数"), value: "\(quality.framesInWindow) / \(quality.frames)")
                FigureInfoRow(key: RPTexts.tr("分析时长"), value: RPFmt.clock(quality.windowSeconds))
                FigureInfoRow(key: RPTexts.tr("采样率"), value: String(format: "%.1f Hz", quality.sampleRate))
                FigureInfoRow(key: RPTexts.tr("头朝向有效"), value: String(format: "%.1f%%", quality.headDirectionRate * 100))
                if quality.unit == "cm" {
                    FigureInfoRow(key: RPTexts.tr("比例"), value: String(format: "%.1f px/cm", quality.pxPerUnit))
                }
            }
            if !quality.keypointRates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RPTexts.tr("各关键点有效比例")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        ForEach(KP.allCases) { k in
                            RPKeypointRateRow(keypoint: k, rate: rate(k))
                        }
                    }
                }
            }
        }
    }

    private func rate(_ k: KP) -> Double {
        k.rawValue < quality.keypointRates.count ? quality.keypointRates[k.rawValue] : 0
    }
}

private struct RPKeypointRateRow: View {
    let keypoint: KP
    let rate: Double

    var body: some View {
        GridRow {
            HStack(spacing: 6) {
                Circle().fill(RPPalette.keypoint(keypoint.rawValue)).frame(width: 7, height: 7)
                Text(keypoint.title).font(.caption).lineLimit(1).fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(keypoint.title)
            .accessibilityValue(String(format: "%.0f%%", rate * 100))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(FigureSurface.inset)
                    Capsule().fill(Color.accentColor.opacity(0.75))
                        .frame(width: g.size.width * CGFloat(min(1, max(0, rate))))
                }
            }
            .frame(height: 7)
            .accessibilityHidden(true)
            Text(String(format: "%.0f%%", rate * 100))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Whole report (ResultStepView body order)

struct PoseReportView: View {
    let report: AnalysisReport
    let category: ParadigmCategory
    var onMessage: ((String) -> Void)? = nil
    @State private var showMethods = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RPNoticeList(notices: report.warnings)
            if let primary = report.primary {
                RPKeyResultCard(metric: primary, category: category)
            }
            let others = report.metrics.filter { $0.key != report.primary?.key }
            if !others.isEmpty {
                Text(RPTexts.tr("全部指标"))
                    .font(.headline)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)
                RPMetricGrid(metrics: others)
            }
            ForEach(report.blocks) { b in
                RPReportBlockView(block: b, onMessage: onMessage)
            }
            RPQualityCard(quality: report.quality)
            methodsCard
        }
    }

    private var methodsCard: some View {
        FigureCard {
            DisclosureGroup(isExpanded: $showMethods) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(report.methods.joined(separator: ""))
                        .font(.footnote)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.methods.joined(separator: ""), forType: .string)
                        onMessage?(RPTexts.tr("已复制方法说明"))
                    } label: {
                        Label(RPTexts.tr("复制方法说明"), systemImage: "doc.on.doc")
                    }
                }
                .padding(.top, 8)
            } label: {
                FigureCardHeader(RPTexts.tr("方法说明（可用于论文 Methods）"), symbol: "text.alignleft")
            }
        }
    }
}

// MARK: - Plain-text data of a figure (ReportFormatting.BlockCSV)

/// Labels go through `RPTexts.english`, so the copied table is in English whatever the interface language.
enum RPBlockCSV {
    static func make(_ block: ReportBlock) -> String? {
        func esc(_ s: String) -> String {
            let e = RPTexts.english(s)
            return e.contains(",") || e.contains("\"") ? "\"" + e.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : e
        }
        func num(_ v: Double) -> String { v.isFinite ? String(format: "%.4g", v) : "" }
        var lines: [String] = []
        switch block.kind {
        case .arena:
            return nil
        case .bars(let d):
            let grouped = d.items.contains { $0.group != nil }
            lines.append(grouped ? "group,category,value" : "category,value")
            for i in d.items {
                lines.append((grouped ? esc(i.group ?? "") + "," : "") + esc(i.label) + "," + num(i.value))
            }
        case .line(let d):
            lines.append("series," + esc(d.xLabel) + "," + esc(d.yLabel))
            for s in d.series {
                for p in s.points { lines.append(esc(s.name) + "," + num(p.x) + "," + num(p.y)) }
            }
        case .timeline(let d):
            lines.append("behavior,start_s,end_s,duration_s")
            for t in d.tracks {
                for b in t.bouts { lines.append(esc(t.name) + "," + num(b.start) + "," + num(b.end) + "," + num(b.end - b.start)) }
            }
        case .polar(let d):
            let width = 360.0 / Double(max(1, d.values.count))
            lines.append("bin_start_deg,bin_end_deg,value_" + esc(d.unit))
            for (i, v) in d.values.enumerated() {
                lines.append(num(Double(i) * width) + "," + num(Double(i + 1) * width) + "," + num(v))
            }
        case .table(let d):
            lines.append(d.columns.map(esc).joined(separator: ","))
            for r in d.rows { lines.append(r.map(esc).joined(separator: ",")) }
        }
        return lines.count > 1 ? lines.joined(separator: "\n") + "\n" : nil
    }
}

// MARK: - Export (RodentPose Exporter.metricsCSV / reportJSON, plus figures)

enum PoseReportExport {
    /// Writes metrics CSV, report JSON, methods text, and one PNG (and CSV, when the figure has data)
    /// per report figure. All text is English.
    @MainActor
    static func write(_ report: AnalysisReport, category: ParadigmCategory, metadata: [String: String],
                      to folder: URL, includeFigures: Bool) throws -> [URL] {
        var written: [URL] = []
        let metricsURL = folder.appendingPathComponent("rodentpose_metrics.csv")
        try FigureExport.writeText(metricsCSV(report), to: metricsURL)
        written.append(metricsURL)

        let jsonURL = folder.appendingPathComponent("rodentpose_report.json")
        try reportJSON(report, metadata: metadata).write(to: jsonURL, options: .atomic)
        written.append(jsonURL)

        let methodsURL = folder.appendingPathComponent("rodentpose_methods_quality.txt")
        try FigureExport.writeText(methodsText(report, metadata: metadata), to: methodsURL)
        written.append(methodsURL)

        if includeFigures {
            if let primary = report.primary {
                let url = folder.appendingPathComponent("rodentpose_figure_00_key_result.png")
                try FigureExport.writePNG(RPKeyResultCard(metric: primary, category: category), to: url)
                written.append(url)
            }
            for (i, block) in report.blocks.enumerated() {
                let base = String(format: "rodentpose_figure_%02d_", i + 1) + FigureExport.slug(RPTexts.english(block.title))
                let png = folder.appendingPathComponent(base + ".png")
                try FigureExport.writePNG(RPReportBlockView(block: block, showsMenu: false), to: png)
                written.append(png)
                if let csv = RPBlockCSV.make(block) {
                    let url = folder.appendingPathComponent(base + ".csv")
                    try FigureExport.writeText(csv, to: url)
                    written.append(url)
                }
            }
            let quality = folder.appendingPathComponent("rodentpose_figure_quality.png")
            try FigureExport.writePNG(RPQualityCard(quality: report.quality), to: quality)
            written.append(quality)
        }
        return written
    }

    static func metricsCSV(_ report: AnalysisReport) -> String {
        var lines = ["metric_key,metric,value,unit"]
        for m in report.metrics {
            let value: String = m.value.map { FastFormat.fixed($0, max(m.decimals, 3)) } ?? ""
            let row: [String] = [FigureExport.csv(m.key), FigureExport.csv(RPTexts.metricLabel(m.title, key: m.key)),
                                 value, FigureExport.csv(RPTexts.reportText(m.unit))]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func reportJSON(_ r: AnalysisReport, metadata: [String: String]) throws -> Data {
        var metrics: [[String: Any]] = []
        for m in r.metrics {
            var d: [String: Any] = ["key": m.key, "title": RPTexts.metricLabel(m.title, key: m.key),
                                    "unit": RPTexts.reportText(m.unit)]
            if let v = m.value, v.isFinite { d["value"] = v }
            metrics.append(d)
        }
        let q = r.quality
        let quality: [String: Any] = ["frames": q.frames, "frames_in_window": q.framesInWindow, "window_s": q.windowSeconds,
                                      "detection_rate": q.detectionRate, "keypoint_rates": q.keypointRates,
                                      "sample_rate_hz": q.sampleRate, "px_per_unit": q.pxPerUnit, "unit": q.unit]
        let obj: [String: Any] = [
            "app": AppInfo.label + " (RodentPose 1.0 analyzers, desktop port; iOS parity validation pending)",
            "data_language": "en",
            "model": kModelName,
            "keypoints": kKeypointNames,
            "primary_metric_key": r.primary?.key ?? "",
            "metrics": metrics,
            "warnings": r.warnings.map(RPTexts.reportText),
            "methods": r.methods.map(RPTexts.reportText),
            "quality": quality,
            "session": metadata
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    static func methodsText(_ r: AnalysisReport, metadata: [String: String]) -> String {
        var lines: [String] = []
        for key in metadata.keys.sorted() { lines.append("\(key): \(metadata[key] ?? "")") }
        lines.append("")
        lines.append(String(format: "Detection rate (analysis window): %.1f%%", r.quality.detectionRate * 100))
        lines.append("Analyzed frames: \(r.quality.framesInWindow) / \(r.quality.frames)")
        lines.append(String(format: "Analysis duration: %.2f s", r.quality.windowSeconds))
        if !r.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines += r.warnings.map { "- " + RPTexts.reportText($0) }
        }
        lines.append("")
        lines.append("Methods:")
        lines.append(r.methods.map(RPTexts.reportText).joined(separator: ""))
        lines.append("")
        lines.append("Desktop port of the RodentPose 1.0 analyzers. Compare with RodentPose iOS and manual scoring before reporting.")
        return lines.joined(separator: "\n") + "\n"
    }
}
