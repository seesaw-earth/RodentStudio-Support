import Foundation

// How RodentStudio organizes data (see DATA_PROCESSING_CN.md):
//
//   Project → Task (one behavioural task, e.g. Open Field) → Group (optional, e.g. WT / KO)
//           → Animal (animal ID) → Session (one video: recording date + session number)
//
// A video is one session of one animal. Group and sex belong to the animal (the same in every session of
// that animal within a task). The animal ID, recording date and session number are required.

/// Recording dates are stored as calendar days ("yyyy-MM-dd"), so they never shift with time zones.
enum SessionDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ text: String?) -> Date? {
        guard let text, text.count == 10 else { return nil }
        return formatter.date(from: text)
    }

    static func isValid(_ text: String?) -> Bool { date(text) != nil }

    /// A date written in a file name: 2026-10-17, 2026_10_17, 2026.10.17 or 20261017 (years 1990–2099).
    static func fromFileName(_ name: String) -> String? {
        let patterns = [#"(19|20)\d{2}[-_.](0[1-9]|1[0-2])[-_.](0[1-9]|[12]\d|3[01])"#,
                         #"(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..<name.endIndex, in: name)),
                  let range = Range(match.range, in: name) else { continue }
            let digits = name[range].filter { $0.isNumber }
            guard digits.count == 8 else { continue }
            let s = String(digits)
            let year = String(s.prefix(4))
            let month = String(s.dropFirst(4).prefix(2))
            let day = String(s.suffix(2))
            let text = year + "-" + month + "-" + day
            if isValid(text) { return text }
        }
        return nil
    }
}

extension VideoRecord {
    /// Animal identity within a task. Videos without an animal ID are separate animals.
    var animalKey: String {
        let id = animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "video-" + String(self.id.uuidString.prefix(8)) : id
    }

    /// Group label ("" = no group).
    var groupKey: String { (group ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    var isExcluded: Bool { excluded ?? false }

    /// Animal ID, recording date and session number are filled in.
    var hasSessionInfo: Bool {
        !animalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && SessionDate.isValid(sessionDate) && (sessionNumber ?? 0) >= 1
    }

    /// Names of the required fields that are still empty (interface language).
    var missingSessionFields: [String] {
        var out: [String] = []
        if animalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(L("animal ID", "小鼠编号")) }
        if !SessionDate.isValid(sessionDate) { out.append(L("date", "日期")) }
        if (sessionNumber ?? 0) < 1 { out.append(L("session number", "实验次数")) }
        return out
    }

    /// "2026-10-17 · #2" (sidebar and tables).
    var sessionTitle: String {
        let date = SessionDate.isValid(sessionDate) ? (sessionDate ?? "") : L("No date", "无日期")
        let number = (sessionNumber ?? 0) >= 1 ? "#\(sessionNumber ?? 0)" : L("#?", "第?次")
        return date + " · " + number
    }

    /// Sort order of sessions within an animal: session number, then date, then import time.
    static func sessionOrder(_ a: VideoRecord, _ b: VideoRecord) -> Bool {
        let na = a.sessionNumber ?? Int.max, nb = b.sessionNumber ?? Int.max
        if na != nb { return na < nb }
        let da = a.sessionDate ?? "~", db = b.sessionDate ?? "~"
        if da != db { return da < db }
        return a.importedAt < b.importedAt
    }
}

/// One video to import, with the information every session must have.
struct VideoImportItem {
    var url: URL
    var animalID: String
    var group: String
    var sex: String
    var sessionDate: String
    var sessionNumber: Int
    var phase: String
}

extension NativeProject {
    func sessions(ofTask experimentID: UUID) -> [VideoRecord] {
        videos.filter { $0.experimentID == experimentID }
    }

    /// Sessions of one animal in a task.
    func sessions(ofTask experimentID: UUID, animal key: String) -> [VideoRecord] {
        videos.filter { $0.experimentID == experimentID && $0.animalKey == key }
    }

    /// Group and sex an animal already has in a task (from its other sessions).
    func animalAttributes(task experimentID: UUID, animal key: String, excluding videoID: UUID? = nil) -> (group: String, sex: String)? {
        guard let other = videos.first(where: { $0.experimentID == experimentID && $0.animalKey == key && $0.id != videoID }) else { return nil }
        return (other.groupKey, other.sex ?? "")
    }

    /// Next free session number of an animal in a task.
    func nextSessionNumber(task experimentID: UUID, animal key: String, alsoTaken: [Int] = []) -> Int {
        let used = Set(sessions(ofTask: experimentID, animal: key).compactMap(\.sessionNumber) + alsoTaken)
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    /// Another session of the same animal with the same session number in the task.
    func sessionConflict(task experimentID: UUID, animal key: String, number: Int, excluding videoID: UUID?) -> VideoRecord? {
        videos.first { $0.experimentID == experimentID && $0.animalKey == key && $0.sessionNumber == number && $0.id != videoID }
    }

    // Variants that ignore a SET of sessions — used when a saved multi-chamber recording is analysed
    // again: its own sessions are about to be replaced and must not count as conflicts.

    func animalAttributes(task experimentID: UUID, animal key: String, ignoring ids: Set<UUID>) -> (group: String, sex: String)? {
        guard let other = videos.first(where: { $0.experimentID == experimentID && $0.animalKey == key && !ids.contains($0.id) })
        else { return nil }
        return (other.groupKey, other.sex ?? "")
    }

    func nextSessionNumber(task experimentID: UUID, animal key: String, alsoTaken: [Int], ignoring ids: Set<UUID>) -> Int {
        let mine = sessions(ofTask: experimentID, animal: key).filter { !ids.contains($0.id) }
        let used = Set(mine.compactMap(\.sessionNumber) + alsoTaken)
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    func sessionConflict(task experimentID: UUID, animal key: String, number: Int, ignoring ids: Set<UUID>) -> VideoRecord? {
        videos.first { $0.experimentID == experimentID && $0.animalKey == key && $0.sessionNumber == number && !ids.contains($0.id) }
    }
}

/// Display order, color and inclusion of a group in a task's group comparison (RodentFlow GroupStyle).
struct GroupStyle: Codable, Hashable {
    var order: Int
    var colorIndex: Int
    var included: Bool
}

// MARK: - Tree order (sidebar, "next session", exports): Task → Group → Animal → Session

extension NativeProject {
    /// Group labels of a task in display order: the saved order of the group comparison if any, otherwise a
    /// likely control first, then alphabetical. "" (no group) comes last.
    func groups(ofTask experimentID: UUID) -> [String] {
        let labels = Set(sessions(ofTask: experimentID).map(\.groupKey))
        let styles = experiments.first { $0.id == experimentID }?.groupStyles ?? [:]
        let named = labels.filter { !$0.isEmpty }.sorted { a, b in
            let oa = styles[a]?.order, ob = styles[b]?.order
            if let oa, let ob, oa != ob { return oa < ob }
            if (oa != nil) != (ob != nil) { return oa != nil }
            let ca = GroupAnalysisEngine.isLikelyControl(a), cb = GroupAnalysisEngine.isLikelyControl(b)
            if ca != cb { return ca }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return labels.contains("") ? named + [""] : named
    }

    /// Animal keys of a task (optionally of one group), in natural order (M2 before M10).
    func animals(ofTask experimentID: UUID, group: String? = nil) -> [String] {
        var keys = Set<String>()
        for v in sessions(ofTask: experimentID) where group == nil || v.groupKey == group {
            keys.insert(v.animalKey)
        }
        return keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Sessions of a task in tree order: group, animal, then session number / date.
    func orderedSessions(ofTask experimentID: UUID) -> [VideoRecord] {
        var out: [VideoRecord] = []
        let all = sessions(ofTask: experimentID)
        for g in groups(ofTask: experimentID) {
            for a in animals(ofTask: experimentID, group: g) {
                out.append(contentsOf: all.filter { $0.groupKey == g && $0.animalKey == a }.sorted(by: VideoRecord.sessionOrder))
            }
        }
        return out
    }
}
