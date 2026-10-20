// FigureSupport.swift — pieces shared by the result figures ported from RodentPose, RodentLimb and
// RodentFlow: the card container of the iOS apps, adaptive colors, a wrapping layout, and PNG / CSV
// writing for exports.

import SwiftUI
import AppKit

// MARK: - Surfaces (iOS grouped-background roles mapped to macOS)

enum FigureSurface {
    /// iOS secondarySystemGroupedBackground (cards).
    static let card = Color(nsColor: .controlBackgroundColor)
    /// iOS tertiarySystemGroupedBackground (insets inside cards, empty plot areas).
    static let inset = Color.primary.opacity(0.055)
    /// iOS systemGroupedBackground (page behind cards).
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
}

extension Color {
    /// sRGB color from 0xRRGGBB.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Color with light / dark variants (the iOS apps' `Palette.adaptive`).
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Card (RodentPose / RodentLimb DesignSystem)

struct FigureCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FigureSurface.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(FigureSurface.hairline.opacity(0.6), lineWidth: 0.5))
    }
}

/// Card title. The symbol is secondary ink so the accent color stays reserved for controls.
struct FigureCardHeader<Trailing: View>: View {
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

extension FigureCardHeader where Trailing == EmptyView {
    init(_ title: String, symbol: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Key–value row (RodentPose InfoRow).
struct FigureInfoRow: View {
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

// MARK: - Wrapping layout (RodentPose CatalogView.WrapLayout)

struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Export helpers

enum FigureExport {
    /// Renders a figure card as the iOS apps do: fixed width (420 pt), light appearance, 3× scale.
    @MainActor
    static func png<V: View>(_ view: V, width: CGFloat = 420) -> Data? {
        let content = view
            .frame(width: width)
            .padding(12)
            .background(FigureSurface.canvas)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        var data: Data?
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        light.performAsCurrentDrawingAppearance {
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                data = rep.representation(using: .png, properties: [:])
            }
        }
        return data
    }

    @MainActor
    static func writePNG<V: View>(_ view: V, to url: URL, width: CGFloat = 420) throws {
        guard let data = png(view, width: width) else { throw ExportFailure.render(url.lastPathComponent) }
        try data.write(to: url, options: .atomic)
    }

    static func writeText(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// CSV field: quoted when it contains a comma, quote or line break.
    static func csv(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func number(_ v: Double?, _ decimals: Int = 6) -> String {
        guard let v, v.isFinite else { return "" }
        return String(format: "%.\(decimals)g", v)
    }

    /// File-name-safe slug of a figure title (English).
    static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        var out = ""
        for scalar in text.lowercased().unicodeScalars {
            if allowed.contains(scalar) && scalar.isASCII { out.unicodeScalars.append(scalar) }
            else if !out.hasSuffix("_") { out += "_" }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "figure" : String(trimmed.prefix(48))
    }

    enum ExportFailure: LocalizedError {
        case render(String)
        var errorDescription: String? {
            switch self {
            case .render(let name): return "The figure \(name) could not be rendered."
            }
        }
    }
}
