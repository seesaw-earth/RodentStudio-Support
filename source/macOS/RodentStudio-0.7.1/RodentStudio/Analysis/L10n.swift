// L10n.swift — in-app English / Chinese switching.
//
// Every visible string is written once with both languages side by side: L("English", "中文").
// Nothing can be "missing" from a catalog, and switching language inside the app takes effect
// immediately (RodentLimbApp rebuilds the view tree when the preference changes).
//
// Rule: exported files (CSV, methods text) and saved keys ALWAYS use English, independent of
// the interface language. Use `LText.en` for those, never `L(...)`.

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zh
    var id: String { rawValue }
    static let storageKey = "rl.uiLanguage"

    var pickerLabel: String {
        switch self {
        case .system: return L("Follow system", "跟随系统")
        case .en: return "English"
        case .zh: return "中文"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "system") ?? .system
    }

    /// Locale used for system-provided formatting inside the app (dates, pickers).
    static func locale(for raw: String) -> Locale {
        switch AppLanguage(rawValue: raw) ?? .system {
        case .zh: return Locale(identifier: "zh-Hans")
        case .en: return Locale(identifier: "en")
        case .system: return Locale(identifier: Locale.preferredLanguages.first ?? "en")
        }
    }
}

enum Lang {
    static var isChinese: Bool {
        switch AppLanguage.current {
        case .zh: return true
        case .en: return false
        case .system: return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("zh")
        }
    }
}

/// Interface string in the current app language.
@inline(__always) func L(_ en: String, _ zh: String) -> String {
    Lang.isChinese ? zh : en
}

/// A bilingual string that can be stored (metric labels, notes). `text` follows the interface
/// language; `en` is what goes into exports.
struct LText: Codable, Hashable {
    var en: String
    var zh: String
    init(_ en: String, _ zh: String) { self.en = en; self.zh = zh }
    var text: String { L(en, zh) }
}
