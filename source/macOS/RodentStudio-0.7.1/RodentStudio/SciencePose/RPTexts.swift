import Foundation

/// RodentPose analysis texts are written in Chinese in the original source (RodentPose iOS 1.0) and
/// translated with RodentPose's own catalog: EnglishTranslations.json and L10nPatterns.json are copied
/// unchanged from the iOS project into Resources.
///
/// - `tr` follows the interface language (Chinese source text, or its English translation).
/// - `english`, `metricLabel` and `reportText` never depend on the interface language; exports use them.
enum RPTexts {
    private struct Template: Decodable {
        let regex: String
        let translation: String
        let source: String?
    }

    private struct Entry {
        let regex: NSRegularExpression
        let translation: String
    }

    private static let englishDictionary: [String: String] = {
        guard let url = Bundle.main.url(forResource: "EnglishTranslations", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let translations = try? JSONDecoder().decode([String: String].self, from: bytes)
        else { return [:] }
        return translations
    }()

    private static let dynamicEntries: [Entry] = {
        guard let url = Bundle.main.url(forResource: "L10nPatterns", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([Template].self, from: bytes)
        else { return [] }
        return templates.compactMap { template in
            guard let regex = try? NSRegularExpression(pattern: template.regex) else { return nil }
            return Entry(regex: regex, translation: template.translation)
        }
    }()

    /// English → Chinese (the source text) for texts generated in English (RodentStudio task summaries
    /// store metric names in both languages).
    private static let chineseDictionary: [String: String] = {
        var out: [String: String] = [:]
        for (zh, en) in englishDictionary where out[en] == nil { out[en] = zh }
        return out
    }()

    /// Chinese source text of a RodentPose text; Chinese text is returned as is, an unknown English text too.
    static func chinese(_ text: String) -> String {
        if hasHan(text) { return text }
        return chineseDictionary[text] ?? text
    }

    /// False when the catalog files are missing from the app bundle (then Chinese text is shown as is).
    static var catalogLoaded: Bool { !englishDictionary.isEmpty }

    /// Visible text in the interface language.
    static func tr(_ text: String) -> String {
        Lang.isChinese ? text : english(text)
    }

    /// Export / persistence path: never consults the interface language.
    static func english(_ text: String) -> String {
        if let value = englishDictionary[text] { return value }
        guard hasHan(text) else { return text }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for item in dynamicEntries {
            guard let match = item.regex.firstMatch(in: text, range: fullRange),
                  match.range == fullRange else { continue }
            var translation = item.translation
            for i in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
                guard let range = Range(match.range(at: i), in: text) else { continue }
                // Nested descriptions, e.g. "陌生鼠" inside a sentence, are translated too.
                let value = english(String(text[range]))
                translation = translation.replacingOccurrences(of: "{\(i - 1)}", with: value)
            }
            return translation
        }
        return text
    }

    static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let v = Int(scalar.value)
            return (0x3400...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v)
        }
    }

    /// Key-based fallback keeps machine-generated metric names in exported files English even if a
    /// translation is missing.
    static func metricLabel(_ label: String, key: String) -> String {
        let candidate = english(label)
        if !hasHan(candidate) { return candidate }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Untranslated Chinese scientific prose is never written into an English report.
    static func reportText(_ text: String) -> String {
        let candidate = english(text)
        if !hasHan(candidate) { return candidate }
        return "[An English translation for this automatically generated description is unavailable.]"
    }
}

extension Array where Element == Double {
    var finiteMedian: Double? {
        let values = self.filter(\.isFinite).sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }
    var finiteMean: Double? {
        let values = self.filter(\.isFinite)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
    func percentile(_ p: Double) -> Double? {
        let sorted = self.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let pos = Swift.min(1, Swift.max(0, p)) * Double(sorted.count - 1)
        let lo = Int(floor(pos)), hi = Int(ceil(pos))
        let alpha: Double = pos - Double(lo)
        let left: Double = sorted[lo] * (1 - alpha)
        let right: Double = sorted[hi] * alpha
        return left + right
    }
}
struct ByteWriter {
    var data = Data()
    init(capacity: Int) { data.reserveCapacity(capacity) }
    mutating func write(_ value: String) { data.append(contentsOf: value.utf8) }
    mutating func comma() { write(",") }
    mutating func newline() { write("\n") }
    mutating func row(_ columns: [String]) { write(columns.joined(separator: ",")); newline() }
}
enum FastFormat {
    static func fixed(_ value: Double, _ precision: Int) -> String {
        value.isFinite ? String(format: "%.*f", precision, value) : ""
    }
}
