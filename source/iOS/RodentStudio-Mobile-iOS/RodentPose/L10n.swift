// RodentPose localization. UI language is selectable inside the app, while exported
// scientific labels and generated reports ALWAYS use English.
// EnglishTranslations.json is generated from Localizable.xcstrings; regenerate after
// changing catalog entries (see tools/update_english_translations.py).

import Foundation

enum L10n {
    static let preferenceKey = "uiLanguage" // "system", "zh-Hans", "en"

    private struct Template: Decodable {
        let regex: String
        let translation: String
        let source: String
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

    /// The system language cannot change while the app runs (iOS relaunches it), so it is read once.
    private static let systemIsChinese: Bool =
        (Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "en")
            .lowercased().hasPrefix("zh")

    private static var isChinese: Bool {
        switch UserDefaults.standard.string(forKey: preferenceKey) {
        case "zh-Hans": return true
        case "en": return false
        default: return systemIsChinese
        }
    }

    /// Results of the regex fallback below. Interpolated interface strings ("约 120 帧…") miss the
    /// static dictionary and would otherwise run up to ~90 regular expressions on every redraw.
    private static let memoLock = NSLock()
    private static var memo: [String: String] = [:]

    // For visible UI text only. Rebuilding the root view on preference change
    // ensures pre-localized strings update without relaunching the app.
    static func tr(_ text: String) -> String {
        isChinese ? text : english(text)
    }

    /// Reverse catalog (English → Chinese source) for labels that were stored in English,
    /// e.g. the cached headline metric name shown in session lists. When several sources share
    /// one translation, the shortest (then lexicographically first) is used.
    private static let chineseByEnglish: [String: String] = {
        var out: [String: String] = [:]
        for (zh, en) in englishDictionary {
            if let current = out[en], (current.count, current) <= (zh.count, zh) { continue }
            out[en] = zh
        }
        return out
    }()

    /// Interface text for a label that is persisted in English (never used for exports).
    static func display(english text: String) -> String {
        guard isChinese, !text.isEmpty else { return text }
        return chineseByEnglish[text] ?? text
    }

    // Export and persistence path: NEVER consult the user's interface language.
    static func english(_ text: String) -> String {
        if let v = englishDictionary[text] { return v }
        memoLock.lock()
        let hit = memo[text]
        memoLock.unlock()
        if let hit { return hit }
        let result = translateDynamic(text)
        memoLock.lock()
        if memo.count > 4000 { memo.removeAll(keepingCapacity: true) }
        memo[text] = result
        memoLock.unlock()
        return result
    }

    private static func translateDynamic(_ text: String) -> String {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for item in dynamicEntries {
            guard let match = item.regex.firstMatch(in: text, range: fullRange),
                  match.range == fullRange else { continue }
            var translation = item.translation
            for i in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
                guard let range = Range(match.range(at: i), in: text) else { continue }
                // Translate nested descriptions, e.g. "陌生鼠" within a sentence.
                let value = english(String(text[range]))
                translation = translation.replacingOccurrences(of: "{\(i - 1)}", with: value)
            }
            return translation
        }
        return text
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) || (0xF900...0xFAFF).contains(Int($0.value)) }
    }

    // Key-based fallback guarantees machine-generated metric names in exported
    // files are English even if an older version had a missing translation.
    static func metricLabel(_ label: String, key: String) -> String {
        let candidate = english(label)
        if !hasHan(candidate) { return candidate }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // Cached headline values in historical session.json may include localized
    // unit suffixes. Their numbers must not be reformatted or translated.
    static func englishDisplay(_ text: String) -> String {
        var value = text
        for unit in ["圈/min", "圈", "次"] {
            value = value.replacingOccurrences(of: unit, with: english(unit))
        }
        return hasHan(value) ? "—" : value
    }

    // Do not silently put untranslated Chinese scientific prose into English reports.
    static func reportText(_ text: String) -> String {
        let candidate = english(text)
        if !hasHan(candidate) { return candidate }
        return "[An English translation for this automatically generated description is unavailable.]"
    }
}
