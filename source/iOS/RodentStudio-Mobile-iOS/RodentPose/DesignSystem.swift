// DesignSystem.swift — palette, typography helpers and shared building blocks of the interface.

import SwiftUI
import UIKit

// MARK: - Palette
//
// Two families of color with different jobs:
// • Interface colors (accent, category, status) are used for text, icons and controls. Each has
//   a light and a dark value chosen for ≥ 4.5 : 1 contrast on the card and canvas surfaces
//   (WCAG AA for body text), so they can be used for captions and tags.
// • Mark colors (Okabe–Ito and the zone tints) are only used for chart marks, zones and video
//   overlays, where 3 : 1 against the surface is the requirement and labels carry the meaning.

enum Palette {
    // Okabe–Ito (Wong 2011, Nature Methods) — color-vision-deficiency-safe series colors.
    static let okabeBlue = Color(red: 0.000, green: 0.447, blue: 0.698)
    static let okabeVermillion = Color(red: 0.835, green: 0.369, blue: 0.000)
    static let okabeGreen = Color(red: 0.000, green: 0.620, blue: 0.451)
    static let okabePurple = Color(red: 0.800, green: 0.475, blue: 0.655)

    // Zone and mark tints (fills / strokes on plots and video, never small text).
    static let coral = Color(red: 0.949, green: 0.420, blue: 0.380)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.106)
    static let indigo = Color(red: 0.365, green: 0.396, blue: 0.945)
    static let teal = Color(red: 0.137, green: 0.639, blue: 0.690)
    static let violet = Color(red: 0.616, green: 0.388, blue: 0.898)
    static let slate = Color(red: 0.443, green: 0.494, blue: 0.573)

    // Interface colors: (light, dark). Values checked for AA contrast on both surfaces.
    static let social = adaptive(0xBE3A32, 0xFF7B6E)
    static let navigation = adaptive(0x4F46E5, 0x8C88FF)
    static let anxiety = adaptive(0x0B7480, 0x3CC3CD)
    static let memory = adaptive(0x7C4DDB, 0xB593FF)
    static let motor = adaptive(0xAB4F08, 0xF2A04E)
    static let general = adaptive(0x5B6474, 0xA3ABB8)

    // Status colors — always paired with an icon and a word, never color alone.
    static let success = adaptive(0x0A7A44, 0x3DD27F)
    static let warning = adaptive(0xA65700, 0xFFB547)
    static let danger = adaptive(0xD12E2E, 0xFF6E6E)
    /// Solid fill for destructive / stop buttons with white text (≥ 4.5 : 1 in both appearances).
    static let dangerFill = Color(uiColor: UIColor(hex: 0xC4302B))
    static let successFill = Color(uiColor: UIColor(hex: 0x0A7A44))

    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let hairline = Color(uiColor: .separator)

    /// Keypoint colors (same order as the model output). Chosen for visibility on grayscale /
    /// infrared video; they are the app's signature and also appear in the app icon glyph.
    static let keypoints: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]

    static func keypoint(_ k: Int) -> Color { keypoints[((k % 6) + 6) % 6] }

    /// sRGB color with light / dark (and optional increased-contrast) variants.
    static func adaptive(_ light: UInt32, _ dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let high = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: high ? (highContrastDark ?? dark) : dark)
            }
            return UIColor(hex: high ? (highContrastLight ?? light) : light)
        })
    }

    /// Category color for text, icons and tags (adapts to dark mode).
    static func category(_ c: ParadigmCategory) -> Color {
        switch c {
        case .social: return social
        case .navigation: return navigation
        case .anxiety: return anxiety
        case .memory: return memory
        case .motor: return motor
        case .general: return general
        }
    }

    /// Deep category color for solid fills that carry white symbols or text (≥ 4.5 : 1 with white
    /// in both appearances).
    static func categoryFill(_ c: ParadigmCategory) -> Color {
        switch c {
        case .social: return Color(uiColor: UIColor(hex: 0xBE3A32))
        case .navigation: return Color(uiColor: UIColor(hex: 0x4F46E5))
        case .anxiety: return Color(uiColor: UIColor(hex: 0x0B7480))
        case .memory: return Color(uiColor: UIColor(hex: 0x7C4DDB))
        case .motor: return Color(uiColor: UIColor(hex: 0xAB4F08))
        case .general: return Color(uiColor: UIColor(hex: 0x5B6474))
        }
    }

    static func color(_ key: ColorKey) -> Color {
        switch key {
        case .accent: return .accentColor
        case .neutral: return Color(uiColor: .systemGray)
        case .warning: return amber
        case .social: return coral
        case .object: return Color(uiColor: .systemGray)
        case .novel: return amber
        case .familiar: return okabeBlue
        case .center: return indigo
        case .periphery: return teal
        case .open: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .closed: return Color(uiColor: .systemGray)
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
        // Fixed series order (validated for CVD separation): blue, green, vermillion, purple.
        case .series1: return okabeBlue
        case .series2: return okabeGreen
        case .series3: return okabeVermillion
        case .series4: return okabePurple
        }
    }

    static func zone(_ role: ZoneRole) -> Color {
        switch role {
        case .arena: return Color(uiColor: .systemGray)
        case .center: return indigo
        case .periphery, .corner: return teal
        case .chamber, .cup, .enclosure, .mazeCenter, .hole: return Color(uiColor: .systemGray)
        case .social, .interaction: return coral
        case .object: return Color(uiColor: .systemGray)
        case .novel: return amber
        case .familiar: return okabeBlue
        case .open: return color(.open)
        case .closed: return Color(uiColor: .systemGray)
        case .arm: return indigo
        case .choice: return amber
        case .light: return color(.light)
        case .dark: return color(.dark)
        case .shelter: return teal
        case .target, .quadrant: return okabeGreen
        case .cue: return amber
        }
    }

    /// Sequential occupancy scale (dark blue → teal → yellow), perceptually ordered and readable
    /// in grayscale. Pair with `HeatLegend` wherever it is used.
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Motion

/// Animations that respect Reduce Motion (they become instant changes).
enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }
    static var snappy: Animation? { reduced ? nil : .snappy }
    static var gentle: Animation? { reduced ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86) }
}

// MARK: - Formatting

enum Fmt {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func clockPrecise(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let m = Int(seconds / 60)
        return String(format: "%d:%05.2f", m, seconds - Double(m) * 60)
    }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    static func remaining(_ s: Double?) -> String {
        guard let s, s.isFinite else { return L10n.tr("估算中…") }
        if s < 60 { return L10n.tr("约 \(max(1, Int(s))) 秒") }
        if s < 3600 { return L10n.tr("约 \(Int((s / 60).rounded())) 分钟") }
        return String(format: L10n.tr("约 %.1f 小时"), s / 3600)
    }

    static func number(_ v: Double, _ decimals: Int = 1) -> String {
        guard v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }
}

// MARK: - Cards

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Card title. The symbol is secondary ink so the accent color stays reserved for things that
/// can be tapped.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Screen-level section title with an optional trailing action ("See all").
struct SectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
        }
    }
}

/// Rounded-square icon used for paradigms and status. Flat fill, white symbol.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct ParadigmBadge: View {
    let paradigm: Paradigm
    var size: CGFloat = 40

    var body: some View {
        IconBadge(symbol: paradigm.symbol, color: Palette.categoryFill(paradigm.category), size: size)
    }
}

struct Tag: View {
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

extension SessionStatus {
    var color: Color {
        switch self {
        case .done: return Palette.success
        case .processing: return .accentColor
        case .paused: return Palette.warning
        case .failed: return Palette.danger
        case .draft: return .secondary
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .labelStyle(.titleAndIcon)
    }
}

struct InfoRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// Inline message. The icon carries the status color; the text stays in primary ink so it is
/// readable in every appearance.
struct Banner: View {
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

    static func icon(_ style: Style) -> String {
        switch style {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    static func color(_ style: Style) -> Color {
        switch style {
        case .info: return .accentColor
        case .warning: return Palette.warning
        case .success: return Palette.success
        case .error: return Palette.danger
        }
    }
}

/// Several warnings collapse into one card instead of a stack of banners.
struct NoticeList: View {
    let notices: [String]
    var style: Banner.Style = .warning
    @State private var expanded = false

    var body: some View {
        if notices.count == 1 {
            Banner(text: notices[0], style: style)
        } else if notices.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(Motion.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: Banner.icon(style)).foregroundStyle(Banner.color(style))
                        Text(String(format: L10n.tr("%d 条提示"), notices.count))
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
                .accessibilityHint(expanded ? L10n.tr("收起") : L10n.tr("展开"))
                ForEach(Array((expanded ? notices : Array(notices.prefix(1))).enumerated()), id: \.offset) { _, n in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Banner.color(style)).frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(n).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !expanded {
                    Text(String(format: L10n.tr("还有 %d 条"), notices.count - 1))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Banner.color(style).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Banner.color(style).opacity(0.25), lineWidth: 1)
            }
        }
    }
}

// MARK: - Explanations on demand

/// Small "ⓘ" that opens explanations in a sheet. Analysis screens keep only controls and results;
/// background knowledge and how-to text live behind this button, so researchers read it when they
/// want to. Secondary ink, no fill, and a sheet that only shows text — tapping it by accident
/// changes nothing.
struct InfoButton<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.regular))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("说明"))
        .accessibilityHint(title)
        .sheet(isPresented: $isPresented) {
            InfoSheet(title: title, content: content)
        }
    }
}

/// Sheet with readable, scrollable explanations.
struct InfoSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One explanation: optional heading and body text.
struct InfoParagraph: View {
    let heading: String?
    let text: String

    init(_ heading: String?, _ text: String) {
        self.heading = heading
        self.text = text
    }

    init(_ text: String) {
        self.heading = nil
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let heading {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(heading == nil ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Group title inside an info sheet.
struct InfoSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Metrics

struct MetricTile: View {
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
                    .contentTransition(.numericText())
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if metric.highlight {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(metric.info ?? "")
    }
}

struct MetricGrid: View {
    let metrics: [MetricValue]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
            ForEach(metrics) { m in
                MetricTile(metric: m)
            }
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, color: color)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isEnabled ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(isEnabled ? color.opacity(configuration.isPressed ? 0.82 : 1) : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.98 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }

    private struct SecondaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.18 : 0.11) : Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var color: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
        }
    }
}

// MARK: - Brand glyph

/// Top-down mouse skeleton with the six colored keypoints — the app's visual signature.
struct MouseGlyph: View {
    var lineColor: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: (size.width - s) / 2 + x * s, y: (size.height - s) / 2 + y * s)
            }
            let pts = [p(0.5, 0.14), p(0.36, 0.30), p(0.64, 0.30), p(0.5, 0.40), p(0.5, 0.60), p(0.5, 0.82)]
            var body = Path()
            body.addEllipse(in: CGRect(x: p(0.31, 0.30).x, y: p(0.31, 0.30).y, width: s * 0.38, height: s * 0.56))
            ctx.fill(body, with: .color(lineColor.opacity(0.12)))
            var tail = Path()
            tail.move(to: pts[5])
            tail.addCurve(to: p(0.70, 0.97), control1: p(0.50, 0.92), control2: p(0.62, 0.98))
            ctx.stroke(tail, with: .color(lineColor.opacity(0.35)), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
            for (a, b) in kBones {
                var path = Path()
                path.move(to: pts[a])
                path.addLine(to: pts[b])
                ctx.stroke(path, with: .color(lineColor.opacity(0.9)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
            }
            for (i, c) in pts.enumerated() {
                let r = s * (i == 0 ? 0.055 : 0.05)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Palette.keypoint(i)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct AppMark: View {
    var size: CGFloat = 52

    var body: some View {
        Image("BrandMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Inputs

/// Numeric text field bound to a Double. Accepts "," as decimal separator. Values outside
/// `range` are clamped, and the field says so instead of changing the number silently.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit = ""
    var help: String?
    var range: ClosedRange<Double>? = nil

    @State private var text = ""
    @State private var outOfRange = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                TextField("—", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 90)
                    .focused($focused)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        if outOfRange {
                            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.warning, lineWidth: 1)
                        }
                    }
                    .accessibilityLabel(title)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .leading)
                }
            }
            if outOfRange, let range {
                Label(String(format: L10n.tr("有效范围 %@–%@，已按边界值计算"), Self.format(range.lowerBound), Self.format(range.upperBound)),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
        .onAppear { text = Self.format(value) }
        .onChange(of: text) { _, newValue in
            guard let v = Self.parse(newValue) else { return }
            let clamped = range.map { min(max(v, $0.lowerBound), $0.upperBound) } ?? v
            outOfRange = clamped != v
            if clamped != value { value = clamped }
        }
        .onChange(of: value) { _, newValue in
            if !focused { text = Self.format(newValue) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                text = Self.format(value)
                outOfRange = false
            }
        }
    }

    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        abs(v - v.rounded()) < 1e-9 ? String(format: "%.0f", v) : String(format: "%g", v)
    }
}

/// Optional integer (day / trial).
struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 70)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .font(.subheadline)
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: text) { _, t in
            let v = Int(t.trimmingCharacters(in: .whitespaces))
            if v != value { value = v }
        }
    }
}

/// Labeled segmented picker row.
struct SegmentRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].1).tag(options[i].0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}

// MARK: - Layout helpers

func aspectFitRect(_ content: CGSize, in container: CGSize) -> CGRect {
    guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let s = min(container.width / content.width, container.height / content.height)
    let w = content.width * s, h = content.height * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

extension V2 {
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

extension View {
    /// Standard screen padding and width limit for readable layouts on iPad.
    func screenContent() -> some View {
        self
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
    }

    /// A bar pinned to the top or bottom edge. On iOS 26 it uses the system scroll-edge effect
    /// (Liquid Glass); earlier systems get the standard bar material and a hairline.
    @ViewBuilder
    func chromeBar<Bar: View>(_ edge: VerticalEdge, @ViewBuilder bar: () -> Bar) -> some View {
        let content = bar()
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.safeAreaBar(edge: edge, spacing: 0) { content }
        } else {
            self.safeAreaInset(edge: edge, spacing: 0) { LegacyBarBackground(edge: edge) { content } }
        }
        #else
        self.safeAreaInset(edge: edge, spacing: 0) { LegacyBarBackground(edge: edge) { content } }
        #endif
    }

    /// Transient confirmation ("Copied") shown above the bottom edge; also announced to VoiceOver.
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

private struct LegacyBarBackground<Content: View>: View {
    let edge: VerticalEdge
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: edge == .top ? .bottom : .top) { Divider() }
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var shown: String?
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let shown {
                    Label(shown, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                        .padding(.bottom, 12)
                        .transition(Motion.reduced ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.success, trigger: generation)
            .onChange(of: message) { _, new in
                guard let new else { return }
                generation += 1
                let mine = generation
                withAnimation(Motion.gentle) { shown = new }
                AccessibilityNotification.Announcement(new).post()
                message = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    if mine == generation { withAnimation(Motion.gentle) { shown = nil } }
                }
            }
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
