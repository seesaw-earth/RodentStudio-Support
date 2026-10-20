// LimbResultFigures.swift — the RodentLimb 1.1.2 result cards on macOS (Summary and Measures tabs):
// headline measures, notes, the TST motion and per-minute charts, cylinder forelimb use and contact
// timeline, gait footfall, pattern, per-paw table, interlimb phase dials and footprints. Ported from
// RodentLimb UI/ResultSections.swift and UI/DesignSystem.swift; drawing, colors and scales are unchanged.
// Exports follow RodentLimb Data/Exporter.swift (English).

import SwiftUI
import Charts
import AppKit

// MARK: - Palette (RodentLimb DesignSystem)

enum RLPalette {
    static let gray = Color(nsColor: .systemGray)

    /// Laterality colors for text and marks.
    static let left = Color.adaptive(0x1767B8, 0x6CB4FF)
    static let right = Color.adaptive(0xC42B3B, 0xFF7C88)
    static let both = Color.adaptive(0x0B7480, 0x3CC3CD)

    static let success = Color.adaptive(0x0A7A44, 0x3DD27F)
    static let warning = Color.adaptive(0xA65700, 0xFFB547)
    static let danger = Color.adaptive(0xD12E2E, 0xFF6E6E)

    /// Assay identity colors (same family as RodentPose categories).
    static func assay(_ a: Assay) -> Color {
        switch a {
        case .tailSuspension: return Color.adaptive(0x7C4DDB, 0xB593FF)
        case .cylinder: return Color.adaptive(0x0B7480, 0x3CC3CD)
        case .gait: return Color.adaptive(0xAB4F08, 0xF2A04E)
        }
    }

    static func label(_ l: PawLabel) -> Color {
        switch l {
        case .left: return left
        case .right: return right
        case .both: return both
        case .ignore: return gray
        }
    }
}

enum RLKeypointColors {
    /// Left fore blue, right fore red, left hind green, right hind violet, pink tail.
    static func hex(_ k: Kp) -> UInt32 {
        switch k {
        case .lf: return 0x1E7FD8
        case .rf: return 0xE5404F
        case .lh: return 0x12A05A
        case .rh: return 0x8A4FE0
        case .tail: return 0xE58FA6
        case .nose: return 0xF2A500
        case .mouth: return 0x5FC3E8
        }
    }
    static func color(_ k: Kp) -> Color { Color(hex: hex(k)) }
}

enum RLFmt {
    static func clockPrecise(_ s: Double) -> String {
        guard s.isFinite else { return "—" }
        let m = Int(max(0, s) / 60)
        return String(format: "%d:%05.2f", m, max(0, s) - Double(m) * 60)
    }
    static func num(_ v: Double?, _ d: Int = 1) -> String {
        guard let v, v.isFinite else { return "—" }
        return String(format: "%.\(d)f", v)
    }
}

// MARK: - Notes and metrics (RodentLimb DesignSystem)

struct RLBanner: View {
    let text: String
    var level: NoteLevel = .info

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: Self.icon(level)).foregroundStyle(Self.color(level))
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.color(level).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Self.color(level).opacity(0.25), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    static func icon(_ l: NoteLevel) -> String {
        switch l {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    static func color(_ l: NoteLevel) -> Color {
        switch l {
        case .info: return .accentColor
        case .warning: return RLPalette.warning
        case .error: return RLPalette.danger
        }
    }
}

/// Several notes collapse into one expandable card, most severe first.
struct RLNoteList: View {
    let notes: [Note]
    @State private var expanded = false

    private var sorted: [Note] {
        notes.sorted { rank($0.level) > rank($1.level) }
    }
    private func rank(_ l: NoteLevel) -> Int { l == .error ? 2 : l == .warning ? 1 : 0 }

    var body: some View {
        if notes.count == 1 {
            RLBanner(text: notes[0].text.text, level: notes[0].level)
        } else if notes.count > 1 {
            let top = sorted[0].level
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: RLBanner.icon(top)).foregroundStyle(RLBanner.color(top))
                        Text(String(format: L("%d notes", "%d 条提示"), notes.count)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(expanded ? sorted : Array(sorted.prefix(1))) { n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: RLBanner.icon(n.level)).font(.caption).foregroundStyle(RLBanner.color(n.level))
                        Text(n.text.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !expanded {
                    Text(String(format: L("%d more", "还有 %d 条"), notes.count - 1)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RLBanner.color(top).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(RLBanner.color(top).opacity(0.25), lineWidth: 1) }
        }
    }
}

/// Up to four headline numbers, large and calm: the first thing a result screen shows.
struct RLHeroMetrics: View {
    let metrics: [Metric]
    var tint: Color = .accentColor

    var body: some View {
        let shown = Array(metrics.prefix(4))
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
            ForEach(shown) { m in
                RLHeroMetric(metric: m)
            }
        }
        .padding(18)
        .background(FigureSurface.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            Capsule().fill(tint).frame(width: 28, height: 4).padding(.leading, 18).padding(.top, 8)
                .accessibilityHidden(true)
        }
    }
}

private struct RLHeroMetric: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.label.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metric.formatted)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// All measures as a quiet grouped list (label · value unit), one card per section.
struct RLMeasureList: View {
    let metrics: [Metric]

    private struct MeasureSection: Identifiable {
        let id: String
        let title: String
        let items: [Metric]
    }

    private var sections: [MeasureSection] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var items: [String: [Metric]] = [:]
        for m in metrics {
            let key = m.group?.en ?? "_other"
            if items[key] == nil {
                order.append(key)
                titles[key] = m.group?.text ?? L("Other", "其他")
                items[key] = []
            }
            items[key]?.append(m)
        }
        return order.map { MeasureSection(id: $0, title: titles[$0] ?? "", items: items[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { i, m in
                            RLMeasureRow(metric: m)
                            if i < section.items.count - 1 { Divider().padding(.leading, 14) }
                        }
                    }
                    .background(FigureSurface.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }
}

private struct RLMeasureRow: View {
    let metric: Metric

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(metric.label.text).font(.subheadline)
            Spacer(minLength: 12)
            Text(metric.formatted).font(.subheadline.weight(.semibold)).monospacedDigit()
            if !metric.unit.isEmpty && metric.value != nil {
                Text(metric.unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tail suspension

struct RLTSTMotionCard: View {
    let detail: TSTDetail
    var seek: ((Double) -> Void)? = nil

    private var ymax: Double { max(detail.threshold * 4, min(3, detail.motion.map(\.v).max() ?? 1)) }

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Motion over time", "运动随时间变化"), symbol: "waveform.path",
                             subtitle: seek == nil
                                ? L("Shaded = immobile · dashed line = threshold.", "阴影 = 不动，虚线 = 阈值。")
                                : L("Shaded = immobile · dashed line = threshold. Click the chart to check that moment.",
                                    "阴影 = 不动，虚线 = 阈值。点击图表可复核该时刻。"))
            chart
        }
    }

    private var chart: some View {
        let top = ymax
        return Chart {
            RectangleMark(xStart: .value("t", detail.window.start), xEnd: .value("t", detail.window.end),
                          yStart: .value("v", 0), yEnd: .value("v", top))
                .foregroundStyle(Color.accentColor.opacity(0.05))
            ForEach(Array(detail.bouts.enumerated()), id: \.offset) { item in
                RectangleMark(xStart: .value("t", item.element.start), xEnd: .value("t", item.element.end),
                              yStart: .value("v", 0), yEnd: .value("v", top))
                    .foregroundStyle(RLPalette.assay(.tailSuspension).opacity(0.22))
            }
            ForEach(Array(detail.motion.enumerated()), id: \.offset) { item in
                LineMark(x: .value("t", item.element.t), y: .value("v", min(item.element.v, top)))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            RuleMark(y: .value("thr", detail.threshold))
                .foregroundStyle(RLPalette.right)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...top)
        .chartXAxisLabel(L("Time (s)", "时间（秒）"))
        .chartYAxisLabel(L("BL/s", "体长/秒"))
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { loc in
                        guard let seek, let plot = proxy.plotFrame else { return }
                        let x = loc.x - geo[plot].origin.x
                        if let t: Double = proxy.value(atX: x) { seek(max(0, t)) }
                    }
            }
        }
        .frame(height: 190)
        .accessibilityLabel(L("Motion chart", "运动曲线图"))
    }
}

struct RLTSTPerMinuteCard: View {
    let detail: TSTDetail

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Immobility per minute", "每分钟不动时间"), symbol: "chart.bar",
                             subtitle: L("Gray minutes are outside the analysis window.", "灰色为分析窗口之外的分钟。"))
            Chart {
                ForEach(Array(detail.perMinute.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("min", "\(item.offset + 1)"), y: .value("s", item.element))
                        .foregroundStyle(inWindow(item.offset) ? RLPalette.assay(.tailSuspension) : RLPalette.gray.opacity(0.4))
                        .cornerRadius(5)
                }
            }
            .chartYScale(domain: 0...60)
            .chartXAxisLabel(L("Minute", "分钟"))
            .chartYAxisLabel(L("s", "秒"))
            .frame(height: 160)
        }
    }

    private func inWindow(_ minute: Int) -> Bool {
        let a = Double(minute) * 60, b = a + 60
        return b > detail.window.start + 1 && a < detail.window.end - 1
    }
}

// MARK: - Cylinder

struct RLCylinderUseCard: View {
    let detail: CylinderDetail

    private struct Row: Identifiable {
        let label: PawLabel
        let count: Int
        var id: String { label.rawValue }
    }

    private var rows: [Row] {
        let counted = detail.events.filter { $0.counted }
        return [PawLabel.left, .right, .both].map { l in Row(label: l, count: counted.filter { $0.label == l }.count) }
    }

    var body: some View {
        let items = rows
        let total = max(1, items.map(\.count).reduce(0, +))
        FigureCard {
            FigureCardHeader(L("Forelimb use", "前爪使用"), symbol: "hand.raised")
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(items) { row in
                        if row.count > 0 {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(RLPalette.label(row.label))
                                .frame(width: max(4, geo.size.width * CGFloat(row.count) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 26)
            .accessibilityHidden(true)
            HStack(spacing: 18) {
                ForEach(items) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(RLPalette.label(row.label)).frame(width: 8, height: 8)
                            Text(row.label.name).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("\(row.count)").font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct RLCylinderTimelineCard: View {
    let detail: CylinderDetail

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Contacts over time", "触壁时间分布"), symbol: "timeline.selection")
            Chart {
                ForEach(detail.events) { e in
                    PointMark(x: .value("t", e.onset), y: .value("paw", e.label.name))
                        .foregroundStyle(e.counted ? RLPalette.label(e.label) : RLPalette.gray.opacity(0.4))
                        .symbolSize(e.edited ? 90 : 50)
                }
            }
            .chartXAxisLabel(L("Time (s)", "时间（秒）"))
            .frame(height: 130)
        }
    }
}

/// Read-only list of the detected contacts (RodentLimb CylinderEventList without relabelling).
struct RLCylinderEventList: View {
    let detail: CylinderDetail
    var seek: ((Double) -> Void)? = nil

    @State private var filter: PawLabel?
    @State private var showAll = false

    private var list: [CylinderEvent] { detail.events.filter { filter == nil || $0.label == filter } }

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Contacts", "触壁列表"), symbol: "checklist",
                             subtitle: L("Automatic calls of the original analyzer. Relabelling contacts is not available on the desktop yet.",
                                         "原版分析器的自动判断。桌面版暂不支持修改触壁标签。"))
            Picker(L("Filter", "筛选"), selection: $filter) {
                Text(L("All", "全部")).tag(PawLabel?.none)
                ForEach(PawLabel.allCases) { Text($0.short).tag(PawLabel?.some($0)) }
            }
            .pickerStyle(.segmented)
            if list.isEmpty {
                Text(L("No contacts yet. Check the calibration and parameters.", "尚未检测到触壁，请检查标定和参数。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                ForEach(showAll ? list : Array(list.prefix(10))) { e in
                    RLCylinderEventRow(event: e, seek: seek)
                }
            }
            if list.count > 10 {
                Button(showAll ? L("Show fewer", "收起") : String(format: L("Show all %d", "显示全部 %d 条"), list.count)) {
                    withAnimation(.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }
}

private struct RLCylinderEventRow: View {
    let event: CylinderEvent
    let seek: ((Double) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: seek == nil ? "circle.fill" : "play.circle.fill")
                .font(seek == nil ? Font.caption : Font.title2)
                .foregroundStyle(RLPalette.label(event.label))
            VStack(alignment: .leading, spacing: 1) {
                Text(RLFmt.clockPrecise(event.onset)).font(.subheadline.monospacedDigit().weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.label.short)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(event.label == .ignore ? Color.secondary : Color.white)
                .frame(minWidth: 54, minHeight: 26)
                .background(event.label == .ignore ? FigureSurface.inset : RLPalette.label(event.label), in: Capsule())
            if let seek {
                Button(L("Check", "复核")) { seek(max(0, event.onset - 0.5)) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(event.counted || event.label == .ignore ? 1 : 0.55)
    }

    private var subtitle: String {
        var parts = [String(format: L("Rear %d", "第 %d 次竖立"), event.rear)]
        if event.edited { parts.append(L("edited", "已修改")) }
        if !event.counted && event.label != .ignore { parts.append(L("over limit", "超出上限")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Gait

struct RLFootfallBar: Identifiable {
    let id: Int
    let paw: Kp
    let start: Double
    let end: Double
}

struct RLFootfallCard: View {
    let detail: GaitDetail

    @State private var windowStart: Double = 0
    private let windowLength = 2.0
    private var lastTime: Double { detail.speed.last?.t ?? 0 }

    private var bars: [RLFootfallBar] { Self.bars(detail, start: windowStart, length: windowLength) }

    static func bars(_ detail: GaitDetail, start a: Double, length: Double) -> [RLFootfallBar] {
        let b = a + length
        var out: [RLFootfallBar] = []
        for paw in Kp.paws {
            for iv in detail.stances[paw.code] ?? [] where iv.end > a && iv.start < b {
                out.append(RLFootfallBar(id: out.count, paw: paw, start: max(iv.start, a), end: min(iv.end, b)))
            }
        }
        return out
    }

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Footfall pattern", "足落模式"), symbol: "chart.bar.doc.horizontal",
                             subtitle: L("Bars = paw on the ground (stance); gaps = swing.", "色条 = 爪着地（支撑相）；空隙 = 摆动相。"))
            RLFootfallChart(bars: bars, start: windowStart, length: windowLength, now: nil)
            if lastTime > windowLength {
                Slider(value: $windowStart, in: 0...max(0, lastTime - windowLength))
                    .accessibilityLabel(L("Time window", "时间窗"))
            }
        }
    }
}

struct RLFootfallChart: View {
    let bars: [RLFootfallBar]
    let start: Double
    let length: Double
    let now: Double?

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(xStart: .value("t", bar.start), xEnd: .value("t", bar.end),
                        y: .value("paw", bar.paw.code), height: .ratio(0.62))
                    .foregroundStyle(RLKeypointColors.color(bar.paw))
                    .cornerRadius(4)
            }
            if let now {
                RuleMark(x: .value("now", now)).foregroundStyle(Color.primary.opacity(0.45))
            }
        }
        .chartXScale(domain: start...(start + length))
        .chartYScale(domain: ["LF", "RF", "LH", "RH"])
        .chartXAxisLabel(L("Time (s)", "时间（秒）"))
        .frame(height: 150)
    }
}

struct RLGaitPatternCard: View {
    let patterns: [PatternShare]

    private func color(_ key: String) -> Color {
        switch key {
        case "walk": return RLKeypointColors.color(.lf)
        case "trot": return RLKeypointColors.color(.lh)
        case "gallop": return RLKeypointColors.color(.nose)
        default: return RLKeypointColors.color(.rf)
        }
    }

    var body: some View {
        let total = max(1, patterns.map(\.count).reduce(0, +))
        FigureCard {
            FigureCardHeader(L("Gait pattern", "步态模式"), symbol: "figure.walk.motion",
                             subtitle: L("Each hind stride, classified from interlimb phase (after Bellardita & Kiehn 2015).",
                                         "按每个后肢步幅的肢间相位分类（参考 Bellardita & Kiehn 2015）。"))
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(patterns) { p in
                        if p.count > 0 {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color(p.key))
                                .frame(width: max(4, geo.size.width * CGFloat(p.count) / CGFloat(total) - 3))
                        }
                    }
                }
            }
            .frame(height: 22)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                ForEach(patterns) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(color(p.key)).frame(width: 8, height: 8)
                            Text(p.label.text).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(String(format: "%.0f%%", Double(p.count) / Double(total) * 100))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct RLPawTableCard: View {
    let detail: GaitDetail

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Per paw", "各爪参数"), symbol: "tablecells")
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                header
                Divider()
                ForEach(detail.paws, id: \.paw) { RLPawRow(p: $0) }
            }
        }
    }

    private var header: some View {
        GridRow {
            Text("").gridColumnAlignment(.leading)
            Text("n")
            Text(L("Stride", "步幅") + " " + detail.unit)
            Text(L("Stance", "支撑") + " s")
            Text(L("Swing", "摆动") + " s")
            Text(L("Duty", "占空比"))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

struct RLPawRow: View {
    let p: PawSummary

    var body: some View {
        GridRow {
            HStack(spacing: 6) {
                Circle().fill(RLKeypointColors.color(p.paw)).frame(width: 9, height: 9)
                Text(p.paw.code).font(.subheadline.weight(.semibold))
            }
            Text("\(p.strides)")
            Text(RLFmt.num(p.strideLength, 2))
            Text(RLFmt.num(p.stance, 3))
            Text(RLFmt.num(p.swing, 3))
            Text(dutyText)
        }
        .font(.subheadline.monospacedDigit())
    }

    private var dutyText: String {
        guard let d = p.duty else { return "—" }
        return String(format: "%.0f%%", d * 100)
    }
}

struct RLPhaseCard: View {
    let detail: GaitDetail

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Interlimb coordination", "肢间协调"), symbol: "circle.dotted",
                             subtitle: L("0.5 = alternating, 0 / 1 = together. Distance from the center = consistency (R).",
                                         "0.5 = 交替，0/1 = 同步。离圆心越远，一致性（R）越高。"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(detail.phases, id: \.key) { RLPhaseDial(phase: $0) }
            }
        }
    }
}

struct RLFootprintCard: View {
    let detail: GaitDetail
    let videoSize: CGSize

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Footprints", "足印分布"), symbol: "pawprint",
                             subtitle: L("Where each paw was planted, in the video frame.", "每次着地的爪位置（视频画面坐标）。"))
            RLFootprintChart(prints: detail.footprints, videoSize: videoSize)
            RLPawLegend()
        }
    }
}

struct RLFootprintChart: View {
    let prints: [Footprint]
    let videoSize: CGSize

    private var w: Double { Double(max(1, videoSize.width)) }
    private var h: Double { Double(max(1, videoSize.height)) }

    var body: some View {
        Chart {
            ForEach(Array(prints.enumerated()), id: \.offset) { item in
                PointMark(x: .value("x", item.element.x), y: .value("y", -item.element.y))
                    .foregroundStyle(RLKeypointColors.color(item.element.paw))
                    .symbolSize(28)
            }
        }
        .chartXScale(domain: 0.0...w)
        .chartYScale(domain: (-h)...0.0)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .aspectRatio(CGFloat(w / h), contentMode: .fit)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct RLPawLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Kp.paws) { p in
                HStack(spacing: 4) {
                    Circle().fill(RLKeypointColors.color(p)).frame(width: 8, height: 8)
                    Text(p.code).font(.caption)
                }
            }
        }
    }
}

struct RLPhaseDial: View {
    let phase: PhaseSummary

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in draw(ctx, size) }
                .frame(width: 92, height: 92)
            Text(phase.label.text).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            Text(phase.mean.map { String(format: "%.2f · R %.2f", $0, phase.r ?? 0) } ?? "—")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = min(size.width, size.height) / 2 - 6
        func point(_ cycle: Double, _ radius: CGFloat) -> CGPoint {
            let a = CGFloat(2 * Double.pi * cycle - Double.pi / 2)
            return CGPoint(x: c.x + radius * CGFloat(Foundation.cos(Double(a))),
                           y: c.y + radius * CGFloat(Foundation.sin(Double(a))))
        }
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                   with: .color(Color.secondary.opacity(0.35)), lineWidth: 1)
        for frac in [0.0, 0.25, 0.5, 0.75] {
            var p = Path()
            p.move(to: point(frac, 0.85 * r))
            p.addLine(to: point(frac, r))
            ctx.stroke(p, with: .color(Color.secondary.opacity(0.6)), lineWidth: 1)
        }
        for v in phase.values.suffix(200) {
            let pt = point(v, r)
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                     with: .color(Color.accentColor.opacity(0.35)))
        }
        guard let m = phase.mean, let R = phase.r else { return }
        let pt = point(m, CGFloat(R) * r)
        var line = Path(); line.move(to: c); line.addLine(to: pt)
        ctx.stroke(line, with: .color(Color.accentColor), lineWidth: 2.5)
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Color.accentColor))
    }
}

// MARK: - Whole result (SessionDetailView Summary + Measures)

struct LimbResultView: View {
    let result: AnalysisResult
    let assay: Assay
    let videoSize: CGSize
    var seek: ((Double) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Summary tab
            RLHeroMetrics(metrics: result.metrics.filter { $0.highlight }, tint: RLPalette.assay(assay))
            RLNoteList(notes: result.notes)
            if let d = result.tst {
                RLTSTMotionCard(detail: d, seek: seek)
            }
            if let d = result.cylinder {
                RLCylinderUseCard(detail: d)
            }
            if let d = result.gait {
                RLFootfallCard(detail: d)
                if let p = d.patterns { RLGaitPatternCard(patterns: p) }
            }
            // Measures tab
            Text(L("All measures", "全部指标")).font(.headline).padding(.top, 4)
            RLMeasureList(metrics: result.metrics)
            if let d = result.tst { RLTSTPerMinuteCard(detail: d) }
            if let d = result.cylinder {
                RLCylinderTimelineCard(detail: d)
                RLCylinderEventList(detail: d, seek: seek)
            }
            if let d = result.gait {
                RLPawTableCard(detail: d)
                RLPhaseCard(detail: d)
                RLFootprintCard(detail: d, videoSize: videoSize)
            }
        }
    }
}

// MARK: - Export (RodentLimb Exporter.sessionFiles, plus figures)

enum LimbResultExport {
    static func f(_ v: Double?, _ d: Int = 4) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(d)f", v)
    }

    static func row(_ fields: [String]) -> String { fields.map(FigureExport.csv).joined(separator: ",") + "\n" }

    @MainActor
    static func write(_ result: AnalysisResult, assay: Assay, setup: LimbTaskSetup?, metadata: [(String, String)],
                      videoSize: CGSize, to folder: URL, includeFigures: Bool) throws -> [URL] {
        var urls: [URL] = []
        let base = "rodentlimb_" + assay.code.lowercased()

        var summary = row(["field", "value", "unit"])
        for (k, v) in metadata { summary += row([k, v, ""]) }
        for m in result.metrics { summary += row([m.key, m.exportValue, m.unit]) }
        for n in result.notes { summary += row(["note_" + n.level.rawValue, n.text.en, ""]) }
        let summaryURL = folder.appendingPathComponent(base + "_summary.csv")
        try FigureExport.writeText(summary, to: summaryURL)
        urls.append(summaryURL)

        switch assay {
        case .tailSuspension:
            if let d = result.tst {
                var b = row(["bout", "start_s", "end_s", "duration_s", "overlaps_window"])
                for (i, x) in d.bouts.enumerated() {
                    b += row(["\(i + 1)", f(x.start, 3), f(x.end, 3), f(x.duration, 3), (x.end > d.window.start && x.start < d.window.end) ? "1" : "0"])
                }
                let u1 = folder.appendingPathComponent(base + "_immobility_bouts.csv")
                try FigureExport.writeText(b, to: u1)
                urls.append(u1)
                var m = row(["minute", "immobility_s"])
                for (i, v) in d.perMinute.enumerated() { m += row(["\(i + 1)", f(v, 2)]) }
                let u2 = folder.appendingPathComponent(base + "_per_minute.csv")
                try FigureExport.writeText(m, to: u2)
                urls.append(u2)
            }
        case .cylinder:
            if let d = result.cylinder {
                var e = row(["event", "onset_s", "offset_s", "rear", "auto_label", "final_label", "edited", "counted"])
                for (i, x) in d.events.enumerated() {
                    e += row(["\(i + 1)", f(x.onset, 3), f(x.offset, 3), "\(x.rear)", x.auto.rawValue, x.label.rawValue,
                              x.edited ? "1" : "0", x.counted ? "1" : "0"])
                }
                let u = folder.appendingPathComponent(base + "_contacts.csv")
                try FigureExport.writeText(e, to: u)
                urls.append(u)
            }
        case .gait:
            if let d = result.gait {
                var st = row(["paw", "start_s", "end_s", "stride_s", "stance_s", "swing_s", "duty", "stride_length_\(d.unit)", "speed_\(d.unit)_per_s"])
                for x in d.strides {
                    st += row([x.paw.code, f(x.start, 4), f(x.end, 4), f(x.end - x.start, 4), f(x.stance, 4), f(x.swing, 4),
                               f(x.duty, 4), f(x.length, 4), f(x.speed, 3)])
                }
                let u1 = folder.appendingPathComponent(base + "_strides.csv")
                try FigureExport.writeText(st, to: u1)
                urls.append(u1)
                var fp = row(["paw", "strike_s", "x_px", "y_px"])
                for x in d.footprints { fp += row([x.paw.code, f(x.t, 4), f(x.x, 2), f(x.y, 2)]) }
                let u2 = folder.appendingPathComponent(base + "_footprints.csv")
                try FigureExport.writeText(fp, to: u2)
                urls.append(u2)
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = folder.appendingPathComponent(base + "_result.json")
        try encoder.encode(result).write(to: json, options: .atomic)
        urls.append(json)

        let methodsURL = folder.appendingPathComponent(base + "_methods.txt")
        try FigureExport.writeText(methods(assay: assay, setup: setup), to: methodsURL)
        urls.append(methodsURL)

        if includeFigures {
            var figures: [(String, AnyView)] = []
            let highlights = result.metrics.filter { $0.highlight }
            if !highlights.isEmpty {
                figures.append(("summary", AnyView(RLHeroMetrics(metrics: highlights, tint: RLPalette.assay(assay)))))
            }
            figures.append(("measures", AnyView(RLMeasureList(metrics: result.metrics))))
            if let d = result.tst {
                figures.append(("motion", AnyView(RLTSTMotionCard(detail: d))))
                figures.append(("immobility_per_minute", AnyView(RLTSTPerMinuteCard(detail: d))))
            }
            if let d = result.cylinder {
                figures.append(("forelimb_use", AnyView(RLCylinderUseCard(detail: d))))
                figures.append(("contacts_over_time", AnyView(RLCylinderTimelineCard(detail: d))))
            }
            if let d = result.gait {
                let bars = RLFootfallCard.bars(d, start: 0, length: 2)
                figures.append(("footfall_first_2s", AnyView(FigureCard {
                    FigureCardHeader(L("Footfall pattern", "足落模式"), symbol: "chart.bar.doc.horizontal",
                                     subtitle: L("First 2 s. Bars = paw on the ground (stance); gaps = swing.", "前 2 秒。色条 = 爪着地（支撑相）；空隙 = 摆动相。"))
                    RLFootfallChart(bars: bars, start: 0, length: 2, now: nil)
                })))
                if let p = d.patterns { figures.append(("gait_pattern", AnyView(RLGaitPatternCard(patterns: p)))) }
                figures.append(("per_paw", AnyView(RLPawTableCard(detail: d))))
                figures.append(("interlimb_phase", AnyView(RLPhaseCard(detail: d))))
                figures.append(("footprints", AnyView(RLFootprintCard(detail: d, videoSize: videoSize))))
            }
            for (i, item) in figures.enumerated() {
                let url = folder.appendingPathComponent(base + String(format: "_figure_%02d_", i + 1) + item.0 + ".png")
                try FigureExport.writePNG(item.1, to: url)
                urls.append(url)
            }
        }
        return urls
    }

    /// RodentLimb Exporter.methods, with this video's parameters.
    static func methods(assay: Assay, setup: LimbTaskSetup?) -> String {
        let params = setup?.params ?? AssayParams.defaults(for: assay)
        let c = params.common
        var t = "RodentLimb — automated analysis methods (\(assay.name.en)); computed by \(AppInfo.name) with the original RodentLimb 1.1.2 analyzers (desktop port; parity with RodentLimb iOS not yet validated)\n\n"
        t += String(format: "Pose estimation: %@ (7 keypoints: left/right fore and hind paws, tail base, nose, mouth), run with Core ML on every video frame. Keypoints with confidence < %.2f were treated as missing; gaps ≤ %.2f s were linearly interpolated, followed by a 3-point median filter and a %.2f s centered moving average. Distances are normalized to body length (BL, median nose–tail-base distance) unless a cm scale was calibrated.\n\n",
                    "CylinderMousePoseV2", c.keypointThreshold, c.maxGap, c.smoothing)
        switch assay {
        case .tailSuspension:
            let p = params.tst
            t += String(format: "Tail suspension test (Steru et al., 1985; Can et al., 2012). Motion was the mean speed of the four paws and the nose (BL/s, %.2f s smoothing). Frames with motion < %.2f BL/s for at least %.1f s were scored as immobile. Immobility was summed over %.0f–%.0f s of the recording; latency is the start of the first immobility bout. Tail climbing was flagged when the nose–tail-base distance fell below %.2f BL. Hindlimb clasping during the first %.0f s was estimated from the lateral distance of each hind paw to the tail-base–nose axis (partial < %.2f BL, full < %.2f BL; score adapted from Guyenet et al., 2010).\n",
                         p.motionSmoothing, p.motionThreshold, p.minBout, p.windowStart, p.windowEnd, p.climbRatio, p.claspWindow, p.claspPartial, p.claspFull)
        case .cylinder:
            let p = params.cylinder
            let wall = p.view == .bottom
                ? String(format: "within %.0f%% of the radius from the calibrated cylinder rim (bottom view)", p.wallMargin * 100)
                : String(format: "raised ≥ %.2f BL above the calibrated floor line (side view)", p.elevation)
            t += String(format: "Cylinder test (Schallert et al., 2000). A forepaw wall contact was scored when the paw was %@ and moved slower than %.2f BL/s for ≥ %.2f s. Contacts separated by < %.2f s formed one rear. %@; left and right placements within %.2f s were scored as both. ",
                         wall, p.stillSpeed, p.minContact, p.rearGap,
                         p.scoring == .firstPerRear ? "The first placement of each rear was scored" : "Every placement was scored",
                         p.simultaneity)
            if p.lesion != .none {
                t += "Contralateral forelimb use = contra / (ipsi + contra) × 100; asymmetry index = (ipsi − contra) / (ipsi + contra + both) × 100, relative to the \(p.lesion.rawValue) lesioned hemisphere. "
            }
            t += "Automatically detected contacts were not edited (relabelling is not available on the desktop).\n"
        case .gait:
            let p = params.gait
            t += String(format: "Gait analysis (bottom view). A paw was in stance when its frame-to-frame speed (smaller of backward and forward steps) was below max(%.2f BL/s, %.2f × body speed); phases shorter than %.0f ms were merged. Strides (foot strike to foot strike of the same paw, ≤ %.2f s) were analyzed only while the body moved ≥ %.2f BL/s ", p.stanceFloor, p.stanceRatio, p.minPhase * 1000, p.maxStride, p.minBodySpeed)
            t += String(format: "in a straight line (mean |angular velocity| ≤ %.0f °/s)%@ (Sheppard et al., 2022). Speed-matched values were obtained from each animal's linear regression of the hind-stride measure on stride speed, evaluated at %.1f BL/s. Gait pattern per hind stride followed Bellardita & Kiehn (2015): hind phase within 0.5 ± 0.15 = walk, or trot if the diagonal (LH→RF) phase was within 0 ± 0.15; hind phase within 0 ± 0.15 = bound; otherwise gallop. Nose and tail-base lateral displacement amplitude was the within-stride range of the perpendicular offset from the line joining the body centre at stride start and end. ", p.maxTurnRate, p.trimRunEnds ? ", excluding the first and last stride of each continuous run" : "", p.referenceSpeed)
            t += "Duty factor = stance / stride duration; stride length = distance between consecutive footprints; base of support = lateral distance between left and right footprints perpendicular to the heading; interlimb phase = (strike_target − strike_reference) / stride_reference, summarized by circular mean and resultant length R; regularity index = 4 × normal step sequence patterns / paw placements × 100 (Cheng et al., 1997). Gait parameters depend on speed (Batka et al., 2014), so per-stride speed is reported.\n"
            if let px = setup?.calibration.scale?.pxPerCm { t += String(format: "Spatial scale: %.2f px/cm.\n", px) }
        }
        return t
    }
}
