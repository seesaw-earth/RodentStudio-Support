// GroupCharts.swift — figures of the group comparison (RodentFlow GroupChartView): one dot per animal with
// mean ± SEM, curves across sessions / days / bins with mean ± SEM, and paired measures joined per animal.
// Groups keep their color wherever they appear (color follows the group, never its rank); the group name
// is always written next to the marks, so color is never the only cue.

import SwiftUI
import Charts

/// Group colors (Okabe–Ito based, color-blind safe); the first is a neutral gray for the control group.
enum GroupPalette {
    static let count = 8

    static func color(_ index: Int) -> Color {
        switch ((index % count) + count) % count {
        case 0: return Color.adaptive(0x6B7280, 0xA3A9B4)
        case 1: return Color.adaptive(0x0072B2, 0x4FA3E0)
        case 2: return Color.adaptive(0xD55E00, 0xF08A4B)
        case 3: return Color.adaptive(0x009E73, 0x3CC79E)
        case 4: return Color.adaptive(0xCC79A7, 0xDE9DC2)
        case 5: return Color.adaptive(0xB07A00, 0xE6B03C)
        case 6: return Color.adaptive(0x3A93C3, 0x7CC3EA)
        default: return Color.adaptive(0x7F3C8D, 0xB27BC0)
        }
    }

    /// Colors of the groups of a result, from the saved group styles (first group gray by default).
    static func colors(_ groups: [String], styles: [String: GroupStyle]) -> [String: Color] {
        var out: [String: Color] = [:]
        for (i, g) in groups.enumerated() {
            out[g] = color(styles[g]?.colorIndex ?? i)
        }
        return out
    }
}

/// Group label in a figure: English for exports, interface language otherwise.
func groupLabel(_ g: String, english: Bool) -> String {
    english ? g : groupDisplayName(g)
}

// MARK: - One value per animal

struct IndependentGroupsChart: View {
    let result: GroupAnalysisResult
    let colors: [String: Color]
    var showChance = false

    private struct Dot: Identifiable {
        let id: String
        let x: Double
        let y: Double
        let group: String
    }

    private struct Summary: Identifiable {
        let id: String
        let x: Double
        let mean: Double
        let low: Double
        let high: Double
        let group: String
    }

    private var groups: [String] { result.groups.filter { g in result.points.contains { $0.group == g } } }

    private var dots: [Dot] {
        var out: [Dot] = []
        for (i, g) in groups.enumerated() {
            let pts = result.points.filter { $0.group == g }.sorted { $0.value < $1.value }
            for (k, p) in pts.enumerated() {
                // Deterministic spread so dots with similar values do not hide each other.
                let spread = pts.count > 1 ? (Double(k % 5) - 2) * 0.06 : 0
                out.append(Dot(id: p.id, x: Double(i) + spread, y: p.value, group: g))
            }
        }
        return out
    }

    private var summaries: [Summary] {
        var out: [Summary] = []
        for (i, g) in groups.enumerated() {
            guard let d = result.descriptives[g], d.n > 0 else { continue }
            out.append(Summary(id: g, x: Double(i), mean: d.mean, low: d.mean - d.sem, high: d.mean + d.sem, group: g))
        }
        return out
    }

    var body: some View {
        let names = groups
        Chart {
            ForEach(summaries) { s in
                RuleMark(xStart: .value("x", s.x - 0.28), xEnd: .value("x", s.x + 0.28), y: .value("Mean", s.mean))
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(colors[s.group] ?? .gray)
                RuleMark(x: .value("x", s.x), yStart: .value("Low", s.low), yEnd: .value("High", s.high))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(colors[s.group] ?? .gray)
            }
            ForEach(dots) { d in
                PointMark(x: .value("x", d.x), y: .value(result.axisTitle, d.y))
                    .symbolSize(46)
                    .foregroundStyle(colors[d.group] ?? .gray)
                    .opacity(0.85)
            }
            if showChance, let chance = result.chance {
                RuleMark(y: .value("Reference", chance))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: -0.6...(Double(max(names.count, 1)) - 0.4))
        .chartXAxis {
            AxisMarks(values: Array(0..<names.count).map { Double($0) }) { value in
                AxisValueLabel {
                    if let x = value.as(Double.self) {
                        let i = Int(x.rounded())
                        if i >= 0 && i < names.count {
                            Text(groupLabel(names[i], english: result.english)).font(.caption)
                        }
                    }
                }
            }
        }
        .chartYAxisLabel(result.axisTitle)
        .frame(minHeight: 260)
    }
}

// MARK: - Curves (sessions, days, bins, CS)

struct CurveChart: View {
    let result: GroupAnalysisResult
    let colors: [String: Color]
    var showAnimals = false

    private struct AnimalPoint: Identifiable {
        let id: String
        let series: String
        let group: String
        let x: Double
        let y: Double
    }

    private var animalPoints: [AnimalPoint] {
        var out: [AnimalPoint] = []
        for s in result.subjectSeries {
            for (j, v) in s.values.enumerated() {
                guard let v, j < result.levels.count else { continue }
                out.append(AnimalPoint(id: s.id + "|\(j)", series: s.id, group: s.group, x: result.levels[j], y: v))
            }
        }
        return out
    }

    var body: some View {
        let domain = result.groups
        let range = domain.map { colors[$0] ?? .gray }
        Chart {
            if showAnimals {
                ForEach(animalPoints) { p in
                    LineMark(x: .value(result.levelLabel, p.x), y: .value(result.axisTitle, p.y), series: .value("Animal", p.series))
                        .foregroundStyle(by: .value("Group", p.group))
                        .opacity(0.25)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            ForEach(result.curves) { c in
                LineMark(x: .value(result.levelLabel, c.level), y: .value(result.axisTitle, c.mean), series: .value("Group", c.group))
                    .foregroundStyle(by: .value("Group", c.group))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value(result.levelLabel, c.level), y: .value(result.axisTitle, c.mean))
                    .foregroundStyle(by: .value("Group", c.group))
                    .symbolSize(40)
                RuleMark(x: .value(result.levelLabel, c.level), yStart: .value("Low", c.mean - c.sem), yEnd: .value("High", c.mean + c.sem))
                    .foregroundStyle(by: .value("Group", c.group))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .chartLegend(.hidden)
        .chartXAxisLabel(result.levelLabel)
        .chartYAxisLabel(result.axisTitle)
        .frame(minHeight: 260)
    }
}

// MARK: - Paired measures

struct PairedMeasuresChart: View {
    let result: GroupAnalysisResult
    let colors: [String: Color]

    private struct Point: Identifiable {
        let id: String
        let series: String
        let group: String
        let x: Double
        let y: Double
    }

    private struct Mean: Identifiable {
        let id: String
        let group: String
        let x: Double
        let y: Double
    }

    private var groups: [String] { result.groups.filter { g in result.paired.contains { $0.group == g } } }

    private var points: [Point] {
        var out: [Point] = []
        for (i, g) in groups.enumerated() {
            for p in result.paired where p.group == g {
                let base = Double(i) * 3
                out.append(Point(id: p.id + "|a", series: p.id, group: g, x: base, y: p.a))
                out.append(Point(id: p.id + "|b", series: p.id, group: g, x: base + 1, y: p.b))
            }
        }
        return out
    }

    private var means: [Mean] {
        var out: [Mean] = []
        for (i, g) in groups.enumerated() {
            let pts = result.paired.filter { $0.group == g }
            guard !pts.isEmpty else { continue }
            let base = Double(i) * 3
            out.append(Mean(id: g + "|a", group: g, x: base, y: Stats.mean(pts.map(\.a))))
            out.append(Mean(id: g + "|b", group: g, x: base + 1, y: Stats.mean(pts.map(\.b))))
        }
        return out
    }

    var body: some View {
        let names = groups
        let ticks: [Double] = names.indices.flatMap { [Double($0) * 3, Double($0) * 3 + 1] }
        Chart {
            ForEach(points) { p in
                LineMark(x: .value("x", p.x), y: .value(result.axisTitle, p.y), series: .value("Animal", p.series))
                    .foregroundStyle(colors[p.group] ?? .gray)
                    .opacity(0.5)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("x", p.x), y: .value(result.axisTitle, p.y))
                    .foregroundStyle(colors[p.group] ?? .gray)
                    .symbolSize(30)
            }
            ForEach(means) { m in
                RuleMark(xStart: .value("x", m.x - 0.3), xEnd: .value("x", m.x + 0.3), y: .value("Mean", m.y))
                    .foregroundStyle(colors[m.group] ?? .gray)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .chartXScale(domain: -0.6...(Double(max(names.count, 1)) * 3 - 1.4))
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisValueLabel {
                    if let x = value.as(Double.self) {
                        let i = Int((x / 3).rounded(.down))
                        let isA = abs(x - Double(i) * 3) < 0.01
                        if i >= 0 && i < names.count {
                            VStack(spacing: 1) {
                                Text(isA ? result.pairLabelA : result.pairLabelB).font(.caption)
                                if isA { Text(groupLabel(names[i], english: result.english)).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .chartYAxisLabel(result.axisTitle)
        .frame(minHeight: 260)
    }
}

// MARK: - Figure (on screen and PNG export)

struct GroupLegend: View {
    let result: GroupAnalysisResult
    let colors: [String: Color]

    var body: some View {
        WrapLayout(spacing: 12) {
            ForEach(result.groups, id: \.self) { g in
                HStack(spacing: 5) {
                    Circle().fill(colors[g] ?? .gray).frame(width: 9, height: 9)
                    Text(groupLabel(g, english: result.english)).font(.caption)
                    if let d = result.descriptives[g] {
                        Text("n = \(d.n)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The chart of a comparison with its title, legend and test summary line.
struct GroupFigureView: View {
    let result: GroupAnalysisResult
    let colors: [String: Color]
    let title: String
    var subtitle: String = ""
    var showAnimals = false

    var body: some View {
        FigureCard {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            chart
            GroupLegend(result: result, colors: colors)
            if let line = testLine {
                Text(line).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch result.request.design {
        case .betweenGroups, .phaseChange:
            IndependentGroupsChart(result: result, colors: colors, showChance: result.request.testAgainstChance)
        case .bySession, .byDay, .withinSession:
            CurveChart(result: result, colors: colors, showAnimals: showAnimals)
        case .pairedMeasures:
            PairedMeasuresChart(result: result, colors: colors)
        }
    }

    private var testLine: String? {
        let r = result.report
        var parts: [String] = []
        if let o = r.omnibus { parts.append("\(o.name): \(o.reportLine)") }
        if let m = r.mixed {
            if let g = m.group { parts.append((result.english ? "Group: " : L("Group: ", "组：")) + g.reportLine) }
            if let i = m.interaction { parts.append((result.english ? "Interaction: " : L("Interaction: ", "交互作用：")) + i.reportLine) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
