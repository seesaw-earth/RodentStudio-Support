// ReportFormatting.swift — interface-independent helpers for presenting a report: the natural
// scale of a headline measure and the plain-text data behind a figure. Foundation only, so the
// logic is unit-testable outside the app.

import Foundation

/// Bounded measures that have a natural scale.
struct MetricScale {
    let range: ClosedRange<Double>
    let reference: Double?
    let referenceLabel: String?

    init?(_ m: MetricValue) {
        guard let v = m.value, v.isFinite else { return nil }
        let isIndex = m.key.hasSuffix("_index") || m.key == "di" || m.key == "turn_bias"
        if isIndex, (-1.0...1.0).contains(v) {
            range = -1...1
            reference = 0
            referenceLabel = L10n.tr("0 = 无偏好")
        } else if m.unit == "%", (0.0...100.0).contains(v) {
            range = 0...100
            if m.key == "alternation_pct" {
                reference = 50
                referenceLabel = L10n.tr("50% = 随机水平")
            } else {
                reference = nil
                referenceLabel = nil
            }
        } else {
            return nil
        }
    }
}

// MARK: - CSV for a block

/// Plain-text data behind a figure. Labels go through `L10n.english` so the copied table is in
/// English whatever the interface language.
enum BlockCSV {
    /// Cheap check used by menus: `make` returns a table for exactly these blocks.
    static func hasData(_ block: ReportBlock) -> Bool {
        switch block.kind {
        case .arena: return false
        case .bars(let d): return !d.items.isEmpty
        case .line(let d): return d.series.contains { !$0.points.isEmpty }
        case .timeline(let d): return d.tracks.contains { !$0.bouts.isEmpty }
        case .polar(let d): return !d.values.isEmpty
        case .table(let d): return !d.rows.isEmpty
        }
    }

    static func make(_ block: ReportBlock) -> String? {
        func esc(_ s: String) -> String {
            let e = L10n.english(s)
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
