// Export.swift — CSV / JSON / text exports. Column names and keys are English so files can be
// read by other tools (Python, R, RodentFlow's table import) regardless of the interface language.

import Foundation

/// Fixed-point number formatting without `String(format:)` (which dominates CSV export time).
enum FastFormat {
    private static let scales: [Double] = [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000]

    static func fixed(_ v: Double, _ decimals: Int) -> String {
        guard v.isFinite else { return "" }
        let d = min(max(decimals, 0), 6)
        let scaled = (v * scales[d]).rounded()
        guard abs(scaled) < 9.0e15 else { return String(v) }
        let iv = Int64(scaled)
        let mag = iv.magnitude
        let unit = UInt64(scales[d])
        var out = iv < 0 ? "-" : ""
        out += String(mag / unit)
        if d > 0 {
            let frac = String(mag % unit)
            out += "."
            if frac.count < d { out += String(repeating: "0", count: d - frac.count) }
            out += frac
        }
        return out
    }
}

/// Appends UTF-8 bytes; much faster than growing a String for multi-megabyte CSV files.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int = 0) { bytes.reserveCapacity(max(0, capacity)) }

    @inline(__always) mutating func write(_ s: String) { bytes.append(contentsOf: s.utf8) }
    @inline(__always) mutating func comma() { bytes.append(44) }
    @inline(__always) mutating func newline() { bytes.append(10) }

    mutating func row(_ fields: [String]) {
        for (i, f) in fields.enumerated() {
            if i > 0 { comma() }
            write(Exporter.csvField(f))
        }
        newline()
    }

    var data: Data { Data(bytes) }
}

enum Exporter {

    static func csvField(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    @inline(__always)
    static func num(_ v: Double, _ decimals: Int) -> String {
        FastFormat.fixed(v, decimals)
    }

    static func safeFileName(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>: ")
        return s.components(separatedBy: bad).filter { !$0.isEmpty }.joined(separator: "_")
    }

    static func baseName(_ s: Session) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        let parts = [s.paradigm.shortName, s.subjectID, s.phase, df.string(from: s.createdAt)].filter { !$0.isEmpty }
        return safeFileName(parts.joined(separator: "_"))
    }

    // MARK: Frame-by-frame analysis CSV

    static func frameCSV(session: Session, track: PoseTrack, features fs: FeatureSet, report: AnalysisReport) -> Data {
        let u = fs.unit
        var header = ["frame", "time_s", "in_window"]
        let multi = fs.animals.count > 1
        for (a, _) in fs.animals.enumerated() {
            let pre = multi ? "m\(a + 1)_" : ""
            header.append(pre + "det_conf")
            for name in kKeypointNames { header += ["\(pre)\(name)_x_\(u)", "\(pre)\(name)_y_\(u)"] }
            header += ["\(pre)speed_\(u)_s", "\(pre)head_direction_deg", "\(pre)ahv_deg_s", "\(pre)body_angle_deg",
                       "\(pre)head_body_angle_deg", "\(pre)body_length_\(u)", "\(pre)motion_\(u)_s"]
        }
        for (name, _) in report.frameColumns { header.append(name) }

        var w = ByteWriter(capacity: (fs.tb.count + 1) * header.count * 7)
        w.row(header)
        let columns = report.frameColumns.map { $0.1 }
        for i in 0..<fs.tb.count {
            w.write(String(fs.frameIndex[i])); w.comma()
            w.write(num(fs.tb.t[i], 3)); w.comma()
            w.write(fs.tb.inWindow[i] ? "1" : "0")
            for a in 0..<fs.animals.count {
                let f = fs.animals[a]
                w.comma(); w.write(num(Double(track.conf(i, a)), 3))
                for k in 0..<kKeypointCount {
                    w.comma(); w.write(num(f.kp[k].x[i], 2))
                    w.comma(); w.write(num(f.kp[k].y[i], 2))
                }
                w.comma(); w.write(num(f.speed[i], 2))
                w.comma(); w.write(num(f.hd[i], 1))
                w.comma(); w.write(num(f.ahv[i], 1))
                w.comma(); w.write(num(f.body[i], 1))
                w.comma(); w.write(num(f.headBody[i], 1))
                w.comma(); w.write(num(f.bodyLength[i], 2))
                w.comma(); w.write(num(f.motion[i], 2))
            }
            for col in columns {
                w.comma()
                if i < col.count { w.write(num(col[i], col[i] == col[i].rounded() ? 0 : 3)) }
            }
            w.newline()
        }
        return w.data
    }

    // MARK: Metrics of one session

    static func metricsCSV(session s: Session, report: AnalysisReport) -> String {
        var lines = ["metric_key,metric,value,unit"]
        for m in report.metrics {
            lines.append([csvField(m.key), csvField(L10n.metricLabel(m.title, key: m.key)),
                          m.value.map { num($0, max(m.decimals, 3)) } ?? "", csvField(L10n.reportText(m.unit))].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Summary table across sessions

    /// One row per session; metadata columns use the names RodentFlow's table import recognizes.
    static func summaryCSV(_ sessions: [Session]) -> String {
        var keys: [String] = []
        var labels: [String: String] = [:]
        for s in sessions {
            for k in s.metricOrder where labels[k] == nil {
                keys.append(k)
                labels[k] = L10n.metricLabel(s.metricLabels[k] ?? k, key: k)
            }
        }
        // Disambiguate duplicate labels.
        var seen: [String: Int] = [:]
        var headers: [String] = []
        for k in keys {
            var h = labels[k] ?? k
            if let c = seen[h] { seen[h] = c + 1; h += " [\(k)]" } else { seen[h] = 1 }
            headers.append(h)
        }
        let df = ISO8601DateFormatter()
        var lines = [(["subject", "group", "sex", "phase", "day", "trial", "paradigm", "date", "video", "notes", "detection_rate"] + headers)
            .map(csvField).joined(separator: ",")]
        for s in sessions {
            var row = [s.subjectID, s.group, s.sex, s.phase, s.day.map(String.init) ?? "", s.trial.map(String.init) ?? "",
                       s.paradigm.shortName, df.string(from: s.createdAt), s.videoName, s.notes,
                       s.pose.map { num($0.detectionRate * 100, 1) } ?? ""].map(csvField)
            for k in keys { row.append(s.metrics[k].map { num($0, 4) } ?? "") }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: JSON report

    static func reportJSON(session s: Session, report r: AnalysisReport) throws -> Data {
        var metrics: [[String: Any]] = []
        for m in r.metrics {
            var d: [String: Any] = ["key": m.key, "title": L10n.metricLabel(m.title, key: m.key),
                                    "unit": L10n.reportText(m.unit)]
            if let v = m.value, v.isFinite { d["value"] = v }
            metrics.append(d)
        }
        let enc = JSONEncoder()
        let sessionObj = try JSONSerialization.jsonObject(with: enc.encode(englishSession(s)))
        let q = r.quality
        let obj: [String: Any] = [
            "app": "RodentStudio iOS 1.0",
            "data_language": "en",
            "model": kModelName,
            "keypoints": kKeypointNames,
            "paradigm": s.paradigm.rawValue,
            "metrics": metrics,
            "warnings": r.warnings.map(L10n.reportText),
            "methods": r.methods.map(L10n.reportText),
            "quality": ["frames": q.frames, "frames_in_window": q.framesInWindow, "window_s": q.windowSeconds,
                        "detection_rate": q.detectionRate, "keypoint_rates": q.keypointRates,
                        "sample_rate_hz": q.sampleRate, "px_per_unit": q.pxPerUnit, "unit": q.unit],
            "session": sessionObj
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Clean stored/generated scientific metadata

    /// Free-form fields entered by the researcher (subject/group/notes/video name)
    /// are preserved verbatim; translating them would corrupt participant IDs.
    static func englishSession(_ input: Session) -> Session {
        var s = input
        for (key, value) in input.metricLabels {
            s.metricLabels[key] = L10n.metricLabel(value, key: key)
        }
        let primaryKey = s.paradigm.primaryMetricKey
        s.primaryTitle = L10n.metricLabel(input.primaryTitle, key: primaryKey)
        s.primaryDisplay = L10n.englishDisplay(input.primaryDisplay)
        return s
    }

    // MARK: Plain-text summary

    static func textSummary(session s: Session, report r: AnalysisReport) -> String {
        var lines: [String] = []
        lines.append(s.paradigm.englishName)
        lines.append("Subject: " + (s.subjectID.isEmpty ? "Unnamed" : s.subjectID))
        if !s.group.isEmpty { lines.append("Group: " + s.group) }
        if !s.phase.isEmpty { lines.append("Phase: " + s.phase) }
        if let day = s.day { lines.append("Day: " + String(day)) }
        if let trial = s.trial { lines.append("Trial: " + String(trial)) }
        lines.append("")
        for m in r.metrics {
            let unit = m.unit.isEmpty ? "" : " " + L10n.reportText(m.unit)
            lines.append("\(L10n.metricLabel(m.title, key: m.key)): \(m.formatted)\(m.value == nil ? "" : unit)")
        }
        if !r.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            lines += r.warnings.map { "- " + L10n.reportText($0) }
        }
        if !r.methods.isEmpty {
            lines.append("")
            lines.append("Methods:")
            lines.append(r.methods.map(L10n.reportText).joined(separator: ""))
        }
        return lines.joined(separator: "\n")
    }
}
