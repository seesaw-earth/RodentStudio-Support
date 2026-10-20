// SettingsView.swift — app settings (⌘,) and the language menu in the toolbar.
// Switching language rebuilds the window immediately; exports always stay in English.

import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var lang = AppLanguage.system.rawValue
    @AppStorage("rd.fontScale") private var fontScale = DesktopFontScale.standard.rawValue

    var body: some View {
        Form {
            Picker(L("Text size", "字体大小"), selection: $fontScale) {
                ForEach(DesktopFontScale.allCases, id: \.rawValue) { scale in
                    Text(scale.label).tag(scale.rawValue)
                }
            }
            Picker(L("Language", "语言"), selection: $lang) {
                ForEach(AppLanguage.allCases) { l in Text(l.pickerLabel).tag(l.rawValue) }
            }
            .pickerStyle(.radioGroup)
            Text(L("Exports (CSV, JSON, figures and methods text) always use English column names and identifiers, whatever the interface language.",
                   "导出文件（CSV、JSON、图表和方法说明）始终使用英文列名和标识，与界面语言无关。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }
}

struct LanguageMenu: View {
    @AppStorage(AppLanguage.storageKey) private var lang = AppLanguage.system.rawValue

    var body: some View {
        Menu {
            Picker(L("Language", "语言"), selection: $lang) {
                ForEach(AppLanguage.allCases) { l in Text(l.pickerLabel).tag(l.rawValue) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L("Language", "语言"), systemImage: "globe")
        }
        .help(L("Interface language (中文 / English)", "界面语言（中文 / English）"))
    }
}


/// Native scalable text styles. Custom pixel-sized annotation markers deliberately stay
/// fixed so increasing the UI font cannot move scientific image coordinates.
enum DesktopFontScale: Int, CaseIterable {
    case compact = 0, standard = 1, large = 2, extraLarge = 3
    var size: DynamicTypeSize {
        switch self {
        case .compact: return .small
        case .standard: return .large
        case .large: return .xxxLarge
        case .extraLarge: return .accessibility1
        }
    }
    var label: String {
        switch self {
        case .compact: return L("Compact", "紧凑")
        case .standard: return L("Standard", "标准")
        case .large: return L("Large", "大")
        case .extraLarge: return L("Extra large", "特大")
        }
    }
}

struct DesktopTextSizeButtons: View {
    @AppStorage("rd.fontScale") private var size = DesktopFontScale.standard.rawValue
    var body: some View {
        HStack(spacing: 3) {
            Button { size = max(0, size - 1) } label: {
                Image(systemName:"textformat.size.smaller")
            }
            .help(L("Decrease text size", "缩小字体"))
            .disabled(size <= 0)
            Text("A").font(.caption).accessibilityLabel(L("Text size", "字体大小"))
            Button { size = min(DesktopFontScale.extraLarge.rawValue, size + 1) } label: {
                Image(systemName:"textformat.size.larger")
            }
            .help(L("Increase text size", "放大字体"))
            .disabled(size >= DesktopFontScale.extraLarge.rawValue)
        }
        .buttonStyle(.borderless)
    }
}
