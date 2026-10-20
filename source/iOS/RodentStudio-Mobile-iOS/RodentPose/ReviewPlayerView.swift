// ReviewPlayerView.swift — play the video with the skeleton, zones and detected behaviors overlaid,
// step frame by frame, and jump through a behavior timeline.
//
// Performance notes: the skeleton / trail layer is redrawn on every display frame from the
// player's own clock (TimelineView), so it stays in sync with the picture without re-evaluating
// the whole screen. Zones are drawn in a separate layer that only redraws when they change, and
// the timeline bars are an equatable view that only redraws when the report changes. The coarse
// time observer (12 Hz) drives the text read-outs and the timeline cursor.

import AVFoundation
import SwiftUI
import UIKit

@MainActor
final class ReviewPlayerModel: ObservableObject {
    let player: AVPlayer
    let duration: Double
    /// Position for read-outs and the timeline cursor (≈ 12 updates per second while playing).
    @Published private(set) var time: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1
    private var observer: Any?

    init(url: URL, duration: Double) {
        player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.duration = duration
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 12), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                let s = t.seconds.isFinite ? t.seconds : 0
                if abs(s - self.time) > 1e-4 { self.time = s }
                let playing = self.player.rate != 0
                if playing != self.isPlaying { self.isPlaying = playing }
            }
        }
    }

    /// Exact position for drawing: read from the player while it plays.
    var displayTime: Double {
        guard isPlaying else { return time }
        let t = player.currentTime().seconds
        return t.isFinite ? t : time
    }

    func stop() {
        player.pause()
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
    }

    func pause() {
        player.pause()
        if isPlaying { isPlaying = false }
    }

    func toggle() {
        if player.rate != 0 {
            pause()
        } else {
            if time >= duration - 0.05 { seek(0) }
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    /// `precise: false` allows the decoder to land up to 0.1 s away (fast while scrubbing).
    func seek(_ t: Double, precise: Bool = true) {
        let c = min(max(0, t), max(0, duration))
        time = c
        let tol = precise ? CMTime.zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: tol, toleranceAfter: tol)
    }

    func step(frames: Int, fps: Double) {
        pause()
        seek(time + Double(frames) / max(fps, 1))
    }

    func setRate(_ r: Float) {
        rate = r
        if player.rate != 0 { player.rate = r }
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {}
}

/// Behavior bouts of a report, sorted once so that look-ups while the video plays are binary searches.
struct ReviewEvents {
    struct Track {
        let name: String
        let color: ColorKey
        let starts: [Double]
        let ends: [Double]
    }

    private(set) var tracks: [Track] = []
    private(set) var allStarts: [Double] = []

    init() {}

    init(_ source: [TimelineTrack]) {
        tracks = source.map { tr in
            let b = tr.bouts.sorted { $0.start < $1.start }
            return Track(name: tr.name, color: tr.color, starts: b.map(\.start), ends: b.map(\.end))
        }
        allStarts = tracks.flatMap(\.starts).sorted()
    }

    func starts(filter: String?) -> [Double] {
        guard let filter else { return allStarts }
        return tracks.filter { $0.name == filter }.flatMap(\.starts).sorted()
    }

    /// Behaviors whose bout covers time `t`.
    func active(at t: Double) -> [Track] {
        tracks.filter { tr in
            let k = Self.upperBound(tr.starts, t) - 1
            return k >= 0 && t < tr.ends[k]
        }
    }

    /// First index whose value is > x.
    static func upperBound(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// First index whose value is ≥ x.
    static func lowerBound(_ a: [Double], _ x: Double) -> Int {
        var lo = 0, hi = a.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if a[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

struct ReviewPlayerView: View {
    @ObservedObject var flow: SessionFlowModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player: ReviewPlayerModel
    @State private var showZones = true
    @State private var showTrail = true
    /// Behavior used for previous / next event navigation (nil = all behaviors).
    @State private var eventFilter: String?
    @State private var events = ReviewEvents()

    init(flow: SessionFlowModel) {
        _flow = ObservedObject(wrappedValue: flow)
        let url = flow.videoURL ?? URL(fileURLWithPath: "/dev/null")
        _player = StateObject(wrappedValue: ReviewPlayerModel(url: url, duration: flow.session.video.duration))
    }

    private var fps: Double { max(1, flow.session.video.fps) }

    /// Processed frame nearest to `time` (nil if none within a frame interval).
    private func index(at time: Double) -> Int? {
        guard let t = flow.track, let i = t.nearestIndex(to: time) else { return nil }
        let tol = Double(max(1, t.frameStride)) / fps * 0.75 + 0.02
        return abs(t.time[i] - time) <= tol ? i : nil
    }

    private var index: Int? { index(at: player.time) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                videoArea
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        readout
                        timeline
                        controls
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color.black)
            .preferredColorScheme(.dark)
            .navigationTitle(L10n.tr("回看 · \(flow.session.displaySubject)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("完成")) {
                        player.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(L10n.tr("显示区域"), isOn: $showZones)
                        Toggle(L10n.tr("显示 2 s 轨迹"), isOn: $showTrail)
                        Picker(L10n.tr("速度"), selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                            Text("0.25×").tag(Float(0.25))
                            Text("0.5×").tag(Float(0.5))
                            Text("1×").tag(Float(1))
                            Text("2×").tag(Float(2))
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(L10n.tr("显示选项"))
                }
            }
        }
        .onAppear { events = ReviewEvents(flow.report?.reviewTracks ?? []) }
        .onChange(of: flow.reportVersion) { _, _ in
            events = ReviewEvents(flow.report?.reviewTracks ?? [])
        }
        .onDisappear { player.stop() }
    }

    // MARK: Video

    private var videoArea: some View {
        GeometryReader { geo in
            let fs = flow.frameSize
            let rect = aspectFitRect(CGSize(width: fs.x, height: fs.y), in: geo.size)
            ZStack {
                PlayerLayerView(player: player.player)
                if showZones, let r = flow.report {
                    // Static layer: redrawn only when the report (zones) or the layout change.
                    ReviewZonesLayer(version: flow.reportVersion, zones: r.zones, mapping: flow.mapping, rect: rect)
                        .equatable()
                        .allowsHitTesting(false)
                }
                // Skeleton and trail follow the player's clock on every display frame.
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !player.isPlaying)) { _ in
                    Canvas { ctx, _ in
                        drawPose(&ctx, rect, time: player.displayTime)
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { player.toggle() }
            .accessibilityElement()
            .accessibilityLabel(L10n.tr("视频"))
            .accessibilityHint(L10n.tr("轻点播放或暂停"))
            .accessibilityAddTraits(.startsMediaSession)
        }
        .aspectRatio(CGFloat(flow.frameSize.x / max(flow.frameSize.y, 1)), contentMode: .fit)
        .frame(maxHeight: 460)
        .background(Color.black)
    }

    private func drawPose(_ ctx: inout GraphicsContext, _ rect: CGRect, time: Double) {
        guard let t = flow.track, let i = index(at: time) else { return }
        if showTrail {
            let trails = flow.trails
            let span = t.count > 1 ? (t.time[t.count - 1] - t.time[0]) / Double(t.count - 1) : 1 / fps
            let window = max(1, Int((2.0 / max(1e-3, span)).rounded()))
            for a in 0..<min(t.animalCount, trails.count) {
                let color: Color = t.animalCount > 1 ? (a == 0 ? Palette.okabeBlue : Palette.okabeVermillion) : .orange
                PoseDrawing.drawTrail(&ctx, trail: trails[a], upTo: i, samples: window, rect: rect, color: color)
            }
        }
        let poses = (0..<t.animalCount).map { t.pose(i, $0) }
        PoseDrawing.draw(&ctx, poses: poses, frameSize: t.frameSize, rect: rect, minConf: Float(flow.session.params.kpConf), scale: rect.width > 500 ? 1.2 : 1)
    }

    // MARK: Readout

    private var readout: some View {
        let i = index
        let active = events.active(at: player.time)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.clockPrecise(player.time))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("/ \(Fmt.clock(player.duration))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if let i, let t = flow.track {
                    Text(L10n.tr("帧 \(t.frameIndex[i])")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            WrapLayout(spacing: 8) {
                if let i, let t = flow.track {
                    let c = t.conf(i, 0)
                    if c > 0 {
                        chip(String(format: L10n.tr("置信度 %.2f"), c), symbol: "checkmark.circle.fill", tint: Palette.success)
                    } else {
                        chip(L10n.tr("未检出"), symbol: "xmark.circle.fill", tint: Palette.danger)
                    }
                    if let f = flow.features, i < f.tb.count {
                        let a = f.animals[0]
                        if a.speed[i].isFinite { chip(String(format: "%.1f %@/s", a.speed[i], f.unit), symbol: "speedometer", tint: .secondary) }
                        if a.hd[i].isFinite { chip(String(format: "HD %.0f°", a.hd[i]), symbol: "location.north.line", tint: .secondary) }
                    }
                } else {
                    chip(L10n.tr("此处没有识别帧"), symbol: "minus.circle", tint: .secondary)
                }
            }
            if !active.isEmpty {
                WrapLayout(spacing: 6) {
                    ForEach(active, id: \.name) { tr in
                        HStack(spacing: 6) {
                            Circle().fill(Palette.color(tr.color)).frame(width: 8, height: 8)
                            Text(tr.name).font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .overlay { Capsule().strokeBorder(Palette.color(tr.color).opacity(0.8), lineWidth: 1) }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.tr("当前行为：") + active.map(\.name).joined(separator: ", "))
            }
        }
    }

    /// Neutral chip: icon carries the status color, text stays in primary ink.
    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.12), in: Capsule())
    }

    // MARK: Event navigation

    private func jump(forward: Bool, in starts: [Double]) {
        let t = player.time
        var target: Double?
        if forward {
            let k = ReviewEvents.upperBound(starts, t + 0.05)
            if k < starts.count { target = starts[k] }
        } else {
            let k = ReviewEvents.lowerBound(starts, t - 0.05) - 1
            if k >= 0 { target = starts[k] }
        }
        if let target {
            player.pause()
            player.seek(target)
        }
    }

    private var eventNavigator: some View {
        let starts = events.starts(filter: eventFilter)
        let t = player.time
        let current = ReviewEvents.upperBound(starts, t + 0.05)
        let hasPrevious = ReviewEvents.lowerBound(starts, t - 0.05) > 0
        let hasNext = current < starts.count
        return HStack(spacing: 10) {
            Button {
                jump(forward: false, in: starts)
            } label: {
                Label(L10n.tr("上一个"), systemImage: "chevron.backward")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .disabled(!hasPrevious)
            .accessibilityLabel(L10n.tr("上一个事件"))
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(starts.isEmpty ? "—" : "\(current) / \(starts.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(eventFilter ?? L10n.tr("全部事件"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button {
                jump(forward: true, in: starts)
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.tr("下一个"))
                    Image(systemName: "chevron.forward")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            .disabled(!hasNext)
            .accessibilityLabel(L10n.tr("下一个事件"))
        }
        .foregroundStyle(.white)
    }

    // MARK: Timeline scrubber

    private var timeline: some View {
        let tracks = flow.report?.reviewTracks ?? []
        let duration = max(player.duration, 0.1)
        let processed: ClosedRange<Double>? = {
            guard let t = flow.track, let a = t.time.first, let b = t.time.last, b >= a else { return nil }
            return a...b
        }()
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ReviewTimelineBars(version: flow.reportVersion, tracks: tracks, epochs: flow.report?.reviewEpochs ?? [],
                                       duration: duration, processed: processed)
                        .equatable()
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: CGFloat(player.time / duration) * w - 1)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        player.pause()
                        player.seek(Double(min(max(0, v.location.x / max(w, 1)), 1)) * duration, precise: false)
                    }
                    .onEnded { v in
                        player.seek(Double(min(max(0, v.location.x / max(w, 1)), 1)) * duration)
                    })
                .accessibilityElement()
                .accessibilityLabel(L10n.tr("行为时间轴"))
                .accessibilityValue(Fmt.clock(player.time))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(player.time + 5)
                    case .decrement: player.seek(player.time - 5)
                    @unknown default: break
                    }
                }
            }
            .frame(height: tracks.isEmpty ? 28 : CGFloat(tracks.count) * 16 + CGFloat(max(0, tracks.count - 1)) * 3)
            if !tracks.isEmpty {
                // Legend doubles as the filter for event navigation.
                WrapLayout(spacing: 6) {
                    filterChip(title: L10n.tr("全部"), color: nil, selected: eventFilter == nil) { eventFilter = nil }
                    ForEach(tracks) { tr in
                        filterChip(title: tr.name, color: Palette.color(tr.color), selected: eventFilter == tr.name) {
                            eventFilter = eventFilter == tr.name ? nil : tr.name
                        }
                    }
                }
                .padding(.top, 4)
                eventNavigator
                    .padding(.top, 2)
            }
        }
    }

    private func filterChip(title: String, color: Color?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let color {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                }
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .foregroundStyle(selected ? Color.black : Color.white)
            .background(selected ? Color.white : Color.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(L10n.tr("用于上一个 / 下一个事件"))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 0) {
            controlButton("gobackward.5", L10n.tr("后退 5 秒")) { player.seek(player.time - 5) }
            controlButton("backward.frame", L10n.tr("上一帧")) { player.step(frames: -max(1, flow.track?.frameStride ?? 1), fps: fps) }
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(player.isPlaying ? L10n.tr("暂停") : L10n.tr("播放"))
            controlButton("forward.frame", L10n.tr("下一帧")) { player.step(frames: max(1, flow.track?.frameStride ?? 1), fps: fps) }
            controlButton("goforward.5", L10n.tr("前进 5 秒")) { player.seek(player.time + 5) }
        }
        .foregroundStyle(.white)
    }

    private func controlButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .accessibilityLabel(label)
    }
}

/// Zone outlines over the video. Equatable on the report version and the layout, so it is not
/// redrawn while the video plays.
private struct ReviewZonesLayer: View, Equatable {
    let version: Int
    let zones: [Zone]
    let mapping: ArenaMapping
    let rect: CGRect

    static func == (a: Self, b: Self) -> Bool { a.version == b.version && a.rect == b.rect }

    var body: some View {
        Canvas { ctx, _ in
            PoseDrawing.drawZones(&ctx, zones: zones, mapping: mapping, rect: rect)
        }
    }
}

/// Behavior rows and CS epochs under the review player. Equatable on the report version, so the
/// bars are not redrawn on every tick of the playing video (only the cursor above them moves).
private struct ReviewTimelineBars: View, Equatable {
    let version: Int
    let tracks: [TimelineTrack]
    let epochs: [Epoch]
    let duration: Double
    let processed: ClosedRange<Double>?

    static func == (a: Self, b: Self) -> Bool {
        a.version == b.version && a.duration == b.duration && a.processed == b.processed && a.tracks.count == b.tracks.count
    }

    var body: some View {
        Canvas { ctx, size in
            for e in epochs {
                let r = CGRect(x: CGFloat(e.start / duration) * size.width, y: 0,
                               width: max(2, CGFloat((e.end - e.start) / duration) * size.width), height: size.height)
                ctx.fill(Path(r), with: .color(Palette.color(e.color).opacity(0.25)))
            }
            let rowH = tracks.isEmpty ? size.height : (size.height - CGFloat(tracks.count - 1) * 3) / CGFloat(tracks.count)
            if tracks.isEmpty {
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), with: .color(Color.white.opacity(0.08)))
            }
            for (k, tr) in tracks.enumerated() {
                let y = CGFloat(k) * (rowH + 3)
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: rowH), cornerRadius: 3), with: .color(Color.white.opacity(0.08)))
                // One path per row: a single fill instead of one per bout.
                var bars = Path()
                for b in tr.bouts {
                    let x0 = CGFloat(b.start / duration) * size.width
                    let x1 = CGFloat(b.end / duration) * size.width
                    bars.addRect(CGRect(x: x0, y: y, width: max(1.5, x1 - x0), height: rowH))
                }
                ctx.fill(bars, with: .color(Palette.color(tr.color)))
            }
            // Processed range.
            if let processed {
                let x0 = CGFloat(processed.lowerBound / duration) * size.width
                let x1 = CGFloat(processed.upperBound / duration) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x0, y: size.height + 3))
                p.addLine(to: CGPoint(x: x1, y: size.height + 3))
                ctx.stroke(p, with: .color(.accentColor.opacity(0.7)), lineWidth: 2)
            }
        }
    }
}
