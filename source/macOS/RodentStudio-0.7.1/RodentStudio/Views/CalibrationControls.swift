// CalibrationControls.swift — shared pieces of the per-task calibration editors: an off-main-thread
// frame loader, the handle and loupe drawings (from RodentPose CalibrationStepView / RodentLimb
// LoupeView), zone colours (RodentPose Palette.zone) and compact form rows for a desktop inspector.

import SwiftUI
import AppKit
import AVFoundation

// MARK: - Frame loading

/// Loads one video frame at a time on a background queue. Only the latest request is shown, so
/// scrubbing never blocks the interface (heavy work and file I/O stay off the main actor).
@MainActor
final class CalibrationFrameLoader: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    /// Video time of the frame actually shown (the generator may return a nearby frame).
    @Published private(set) var shownTime: Double = 0
    /// Increments on every successfully loaded frame (CGImage itself is not Equatable for onChange).
    @Published private(set) var loadedCount = 0

    private var generation = 0
    private var generator: AVAssetImageGenerator?
    private var generatorURL: URL?
    private let queue = DispatchQueue(label: "rodentdesktop.calibration-frames", qos: .userInitiated)

    func load(url: URL, at seconds: Double) {
        generation += 1
        let ticket = generation
        loading = true
        failed = false
        if generatorURL != url || generator == nil {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            g.appliesPreferredTrackTransform = true
            g.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            g.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            g.maximumSize = CGSize(width: 1920, height: 1920)
            generator = g
            generatorURL = url
        }
        guard let gen = generator else { return }
        gen.cancelAllCGImageGeneration()
        let time = max(0, seconds)
        queue.async {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var actual = CMTime.zero
            let cg = try? gen.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: &actual)
            let shown = actual.seconds.isFinite ? actual.seconds : time
            Task { @MainActor [weak self] in
                guard let self, self.generation == ticket else { return }
                self.loading = false
                if let cg {
                    self.image = cg
                    self.shownTime = shown
                    self.loadedCount += 1
                } else {
                    self.failed = true
                }
            }
        }
    }
}

// MARK: - Geometry helpers

func calibrationFitRect(_ content: CGSize, in container: CGSize) -> CGRect {
    let cw = max(content.width, 1), ch = max(content.height, 1)
    let s = min(container.width / cw, container.height / ch)
    let w = cw * s, h = ch * s
    return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
}

/// Upright frame size for a new setup. Records imported by 0.3.x stored the encoded size, which
/// can be rotated relative to the displayed frame; the loaded frame decides the orientation.
func uprightFrameSize(record: VideoRecord, image: CGImage?) -> CGSize {
    var w = Double(record.videoWidth), h = Double(record.videoHeight)
    if let image {
        if w <= 0 || h <= 0 { return CGSize(width: image.width, height: image.height) }
        let recordLandscape = w >= h
        let imageLandscape = image.width >= image.height
        if recordLandscape != imageLandscape { swap(&w, &h) }
    }
    return CGSize(width: max(w, 1), height: max(h, 1))
}

// MARK: - Handles and loupe

/// Ring with an exact centre dot; the label sits outside the ring so the target stays visible.
struct CalibrationHandleView: View {
    let label: String
    let color: Color
    var active = false
    var selected = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.38)).frame(width: 26, height: 26)
            Circle().strokeBorder(color, lineWidth: selected ? 3 : 2.2).frame(width: 21, height: 21)
            Circle().fill(color).frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 4)
                .frame(minWidth: 17, minHeight: 15)
                .background(color, in: Capsule())
                .offset(x: 15, y: -15)
        }
        .scaleEffect(active ? 1.15 : 1)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}

/// Magnified view of the frame around the point being placed (3×), with a crosshair.
struct CalibrationLoupe: View {
    let image: CGImage?
    /// Where the video frame is drawn, in canvas coordinates.
    let imageRect: CGRect
    /// Target point, in canvas coordinates.
    let point: CGPoint
    let color: Color
    var diameter: CGFloat = 120
    var zoom: CGFloat = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(x: diameter / 2 - (point.x - imageRect.minX) * zoom,
                            y: diameter / 2 - (point.y - imageRect.minY) * zoom)
            }
            Canvas { ctx, size in
                let m = CGPoint(x: size.width / 2, y: size.height / 2)
                var cross = Path()
                for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                    cross.move(to: CGPoint(x: m.x + 6 * dx, y: m.y + 6 * dy))
                    cross.addLine(to: CGPoint(x: m.x + 22 * dx, y: m.y + 22 * dy))
                }
                ctx.stroke(cross, with: .color(.black.opacity(0.7)), lineWidth: 3)
                ctx.stroke(cross, with: .color(color), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: m.x - 1.5, y: m.y - 1.5, width: 3, height: 3)), with: .color(color))
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .accessibilityHidden(true)
    }

    /// Loupe goes to the top corner on the other side from the pointer, so it never covers the target.
    static func center(for p: CGPoint, in size: CGSize, diameter: CGFloat = 120) -> CGPoint {
        let r = diameter / 2 + 8
        let x = p.x < size.width / 2 ? size.width - r : r
        return CGPoint(x: x, y: min(r, size.height / 2))
    }
}

struct HandleLegendItem: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().strokeBorder(color, lineWidth: 2.5)
                .background { Circle().fill(Color.black.opacity(0.55)) }
                .frame(width: 13, height: 13)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Text that explains keyboard nudging of the selected handle.
struct HandleKeyboardHint: View {
    var body: some View {
        Label(L("Click a handle, then use the arrow keys to nudge it (⇧ for larger steps).",
                "点选手柄后可用方向键微调（按住 ⇧ 移动更多）。"), systemImage: "keyboard")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Zone colours (RodentPose Palette.zone)

enum ZonePalette {
    static let okabeBlue = Color(red: 0.000, green: 0.447, blue: 0.698)
    static let okabeGreen = Color(red: 0.000, green: 0.620, blue: 0.451)
    static let coral = Color(red: 0.949, green: 0.420, blue: 0.380)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.106)
    static let indigo = Color(red: 0.365, green: 0.396, blue: 0.945)
    static let teal = Color(red: 0.137, green: 0.639, blue: 0.690)
    static let gray = Color(nsColor: .systemGray)

    static func color(_ role: ZoneRole) -> Color {
        switch role {
        case .arena: return gray
        case .center: return indigo
        case .periphery, .corner: return teal
        case .chamber, .cup, .enclosure, .mazeCenter, .hole: return gray
        case .social, .interaction: return coral
        case .object: return gray
        case .novel: return amber
        case .familiar: return okabeBlue
        case .open: return Color(red: 0.95, green: 0.70, blue: 0.10)
        case .closed: return gray
        case .arm: return indigo
        case .choice: return amber
        case .light: return Color(red: 0.98, green: 0.78, blue: 0.18)
        case .dark: return Color(red: 0.30, green: 0.32, blue: 0.42)
        case .shelter: return teal
        case .target, .quadrant: return okabeGreen
        case .cue: return amber
        }
    }
}

// MARK: - Inspector building blocks

/// A titled group in the settings column.
struct SetupCard<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    let content: Content

    init(_ title: String, symbol: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.18)))
    }
}

/// Numeric entry with a unit. Values are clamped to `range` when committed.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""
    var help: String? = nil
    var range: ClosedRange<Double>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                TextField(title, value: clamped, format: .number.precision(.fractionLength(0...3)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                if !unit.isEmpty {
                    Text(unit).font(.callout).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading)
                }
            }
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var clamped: Binding<Double> {
        Binding(get: { value }, set: { v in
            guard v.isFinite else { return }
            if let range { value = min(max(v, range.lowerBound), range.upperBound) } else { value = v }
        })
    }
}

/// Optional whole number (day, trial).
struct OptionalIntField: View {
    let title: String
    @Binding var value: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.callout)
            TextField(title, value: $value, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
        }
    }
}

/// A small set of choices. Segmented when it fits, a menu otherwise.
struct SegmentRow<T: Hashable>: View {
    let title: String
    @Binding var selection: T
    let options: [(T, String)]

    private var fitsSegmented: Bool {
        options.count <= 3 && options.allSatisfy { $0.1.count <= 16 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            if fitsSegmented {
                Picker(title, selection: $selection) {
                    ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            } else {
                Picker(title, selection: $selection) {
                    ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 0.01)
        }
    }
}

/// Slider with a formatted value, as in RodentLimb ParamsSheet / RodentFlow ZoneParameterEditor.
struct ParamSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var unit: String = ""
    var decimals: Int = 2
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.callout)
                Spacer(minLength: 8)
                Text(String(format: "%.\(decimals)f", value) + (unit.isEmpty ? "" : " " + unit))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InfoRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

/// Comma-separated list of times (seconds) with a generator for regular schedules
/// (RodentPose OnsetsEditor).
struct OnsetsEditor: View {
    let title: String
    @Binding var onsets: [Double]
    var hint: String = ""

    @State private var text = ""
    @State private var showGenerator = false
    @State private var first: Double = 120
    @State private var count: Double = 3
    @State private var interval: Double = 90
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text(L("\(onsets.count) events", "\(onsets.count) 次")).font(.caption).foregroundStyle(.secondary)
            }
            TextField(L("e.g., 120, 210, 300", "如 120, 210, 300"), text: $text, axis: .vertical)
                .font(.callout.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            if !hint.isEmpty {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(L("Generate evenly spaced events", "按固定间隔生成"), isExpanded: $showGenerator) {
                VStack(spacing: 8) {
                    NumberField(title: L("First", "第一次"), value: $first, unit: "s", range: 0...100_000)
                    NumberField(title: L("Number", "次数"), value: $count, unit: L("events", "次"), range: 1...200)
                    NumberField(title: L("Interval (onset to onset)", "间隔（开始到开始）"), value: $interval, unit: "s", range: 0.1...100_000)
                    Button {
                        let n = max(1, Int(count.rounded()))
                        onsets = (0..<n).map { first + Double($0) * interval }
                        text = Self.format(onsets)
                    } label: {
                        Label(L("Generate", "生成"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
        .onAppear { text = Self.format(onsets) }
        .onChange(of: text) { _, t in
            let parsed = Self.parse(t)
            if parsed != onsets { onsets = parsed }
        }
        .onChange(of: onsets) { _, o in
            if !focused { text = Self.format(o) }
        }
    }

    static func parse(_ s: String) -> [Double] {
        s.replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
    }

    static func format(_ v: [Double]) -> String {
        v.map { abs($0 - $0.rounded()) < 1e-9 ? String(format: "%.0f", $0) : String(format: "%g", $0) }.joined(separator: ", ")
    }
}

/// Frame scrubber shared by the calibration editors. The frame is loaded when the slider is released.
struct CalibrationFrameScrubber: View {
    @Binding var time: Double
    let duration: Double
    let onCommit: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(L("Video time", "画面时间")).font(.caption).foregroundStyle(.secondary)
            Slider(value: $time, in: 0...max(0.1, duration)) { editing in
                if !editing { onCommit(time) }
            }
            .accessibilityLabel(L("Video time", "画面时间"))
            Text(Self.clock(time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
        }
    }

    static func clock(_ t: Double) -> String {
        guard t.isFinite else { return "–" }
        let total = max(0, t)
        let m = Int(total) / 60
        let s = total - Double(m * 60)
        return String(format: "%d:%05.2f", m, s)
    }
}
