// TrackingCheckViews.swift — the tracking check inside "Frame review & export": play or step through the
// saved tracking drawn on the video, flag wrongly tracked frames and record a verdict. Every frame does
// not have to be inspected: a range (default frames 0–99) can be checked instead. The check is saved with
// the session (it survives switching session, task, section or language) and belongs to the current run.
//
// RodentFlow sessions get their own frame review here (centroid on the video, 10 Hz samples).

import SwiftUI
import AVFoundation
import AppKit

/// Playback speed of the frame review. "Every frame" never skips a frame; the others follow the video
/// clock and skip frames that cannot be decoded in time.
enum PlaybackSpeed: String, CaseIterable, Identifiable {
    case everyFrame, quarter, half, normal, double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyFrame: return L("Every frame", "逐帧播放")
        case .quarter: return "0.25×"
        case .half: return "0.5×"
        case .normal: return "1×"
        case .double: return "2×"
        }
    }

    /// Multiple of real time; nil = advance one frame at a time.
    var rate: Double? {
        switch self {
        case .everyFrame: return nil
        case .quarter: return 0.25
        case .half: return 0.5
        case .normal: return 1
        case .double: return 2
        }
    }
}

/// Plans playback: the next index to show and how long to wait before showing it.
enum PlaybackPlanner {
    /// `times` are the timestamps of the frames (seconds, increasing); `startWall` / `startTime` anchor the
    /// video clock when playback started.
    static func next(after current: Int, last: Int, times: (Int) -> Double, speed: PlaybackSpeed,
                     startWall: Date, startTime: Double) -> (index: Int, wait: Double) {
        let following = min(last, current + 1)
        guard let rate = speed.rate, rate > 0 else {
            // One frame at a time, not faster than the recording itself.
            let gap = max(0, times(following) - times(current))
            return (following, min(gap, 0.5))
        }
        let elapsed = Date().timeIntervalSince(startWall)
        let target = startTime + elapsed * rate
        var index = following
        // Skip frames whose time has already passed (decoding slower than the playback clock).
        while index < last && times(index + 1) <= target { index += 1 }
        let due = (times(index) - startTime) / rate - elapsed
        return (index, max(0, min(due, 1)))
    }
}

// MARK: - Check card

struct TrackingCheckCard: View {
    @EnvironmentObject private var store: WorkspaceStore

    let video: VideoRecord
    /// "frame" (RodentPose / RodentLimb) or "sample" (RodentFlow, 10 Hz).
    let unit: String
    let total: Int
    @Binding var rangeStart: Int
    @Binding var rangeCount: Int
    let viewed: Set<Int>
    let flagged: Set<Int>
    @Binding var notes: String
    let persist: () -> Void
    let jump: (Int) -> Void

    static let maxRange = 1000

    private var unitTitle: String { unit == "sample" ? L("sample", "采样点") : L("frame", "帧") }
    private var rangeEnd: Int { min(max(0, total - 1), rangeStart + max(1, rangeCount) - 1) }
    private var rangeSize: Int { max(0, rangeEnd - rangeStart + 1) }
    private var viewedInRange: Int { viewed.filter { $0 >= rangeStart && $0 <= rangeEnd }.count }
    private var review: VideoReviewState? { store.video(video.id)?.currentReview }

    var body: some View {
        FigureCard {
            FigureCardHeader(L("Tracking check", "追踪复核"), symbol: "checkmark.seal",
                             subtitle: L("You do not have to inspect every frame: choose a range (for example frames 0–99), play or step through it, flag frames where the tracking is wrong, then record the result. Tracking is never re-run here.",
                                         "无需逐帧检查全部视频：选择一个范围（例如第 0–99 帧），播放或逐帧查看，标记追踪错误的帧，然后记录结论。这里不会重新运行追踪。"))
            rangeControls
            HStack(spacing: 12) {
                ProgressView(value: Double(viewedInRange), total: Double(max(1, rangeSize)))
                    .frame(maxWidth: 220)
                Text(String(format: L("Viewed %d of %d in the range", "范围内已查看 %d / %d"), viewedInRange, rangeSize))
                    .font(.caption).monospacedDigit()
                if !flagged.isEmpty {
                    Text(String(format: L("%d flagged:", "已标记 %d 个："), flagged.count)).font(.caption).foregroundStyle(.orange)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(flagged.sorted(), id: \.self) { i in
                                Button("\(i)") { jump(i) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                            }
                        }
                    }
                }
            }
            Picker(L("Result", "结论"), selection: Binding(get: { review?.verdict ?? .unreviewed }, set: { setVerdict($0) })) {
                ForEach(ReviewVerdict.allCases, id: \.self) { v in
                    Label(v.title, systemImage: v.symbol).tag(v)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField(L("Notes (saved with the session and exported)", "备注（随该次实验保存并导出）"), text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .onSubmit { persist() }
            if let r = review, let date = r.reviewedAt {
                Text(String(format: L("Recorded %@ · range %d–%d · viewed %d · flagged %d", "记录于 %@ · 范围 %d–%d · 已查看 %d · 已标记 %d"),
                            date.formatted(date: .abbreviated, time: .shortened), r.windowStart, r.windowEnd, r.viewed.count, r.flagged.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let next = nextToCheck {
                Button(String(format: L("Next session to check: %@ →", "下一次待复核的实验：%@ →"), sessionLabel(next))) {
                    persist()
                    store.focusedExperimentID = next.experimentID
                    store.focusedVideoID = next.id
                }
            }
        }
    }

    private var rangeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(L("Check range from", "复核范围：从"))
                TextField("0", value: $rangeStart, format: .number)
                    .frame(width: 90)
                    .onSubmit { clamp() }
                Picker(L("Length", "数量"), selection: $rangeCount) {
                    ForEach([50, 100, 200, 500, 1000], id: \.self) { n in
                        Text(String(format: L("%d %@s", "%d 个%@"), n, unitTitle)).tag(n)
                    }
                }
                .frame(width: 200)
                if total > 0 {
                    Text(String(format: L("%@s %d–%d of %d (zero-based)", "第 %2$d–%3$d 个%1$@（共 %4$d，从 0 开始）"), unitTitle.capitalized, rangeStart, rangeEnd, total))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(L("Presets", "快捷")).font(.caption).foregroundStyle(.secondary)
                Button(L("Start (0–99)", "开头（0–99）")) { rangeStart = 0; rangeCount = 100; jump(0) }
                Button(L("Middle", "中间")) { rangeStart = max(0, total / 2 - rangeCount / 2); jump(rangeStart) }
                Button(L("End", "结尾")) { rangeStart = max(0, total - rangeCount); jump(rangeStart) }
                Button(L("Random", "随机")) {
                    rangeStart = total > rangeCount ? Int.random(in: 0...(total - rangeCount)) : 0
                    jump(rangeStart)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func clamp() {
        rangeCount = min(Self.maxRange, max(1, rangeCount))
        rangeStart = max(0, rangeStart)
        if total > 0 { rangeStart = min(rangeStart, total - 1) }
        persist()
    }

    private func setVerdict(_ v: ReviewVerdict) {
        persist()
        store.updateReview(video.id, unit: unit) { s in
            s.verdict = v
            s.reviewedAt = v == .unreviewed ? nil : Date()
        }
    }

    private func sessionLabel(_ v: VideoRecord) -> String {
        v.displayName + " · " + v.sessionTitle
    }

    /// The next analysed session of the task (sidebar order) whose tracking is not checked yet.
    private var nextToCheck: VideoRecord? {
        guard let project = store.selectedProject, let task = video.experimentID else { return nil }
        let ordered = project.orderedSessions(ofTask: task).filter { $0.runState == .complete }
        guard let i = ordered.firstIndex(where: { $0.id == video.id }) else {
            return ordered.first { $0.reviewVerdict == .unreviewed && $0.id != video.id }
        }
        let rest = Array(ordered[(i + 1)...]) + Array(ordered[..<i])
        return rest.first { $0.reviewVerdict == .unreviewed }
    }
}

// MARK: - RodentFlow frame review

struct FlowFrameReviewView: View {
    @EnvironmentObject private var store: WorkspaceStore

    let assay: StudyAssay
    let video: VideoRecord

    @AppStorage("rd.playbackSpeed") private var speedRaw = PlaybackSpeed.normal.rawValue

    @State private var points: [FlowTrackingPoint] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var dataKey = ""

    @State private var current = 0
    @State private var image: NSImage?
    @State private var imageMatches = true
    @State private var decodeWarning = ""
    @State private var generation = 0
    @State private var access: ScopedVideoAccess?
    @State private var playing = false
    @State private var playTask: Task<Void, Never>?

    @State private var rangeStart = 0
    @State private var rangeCount = 100
    @State private var viewed: Set<Int> = []
    @State private var flagged: Set<Int> = []
    @State private var notes = ""
    @State private var stateVideoID: UUID?
    @State private var message = ""

    private var speed: PlaybackSpeed { PlaybackSpeed(rawValue: speedRaw) ?? .normal }
    private var total: Int { points.count }
    private var rangeEnd: Int { min(max(0, total - 1), rangeStart + max(1, rangeCount) - 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("RodentFlow tracks the body centroid at 10 Hz. Each sample is drawn on its own video frame; the tracking is never re-run here.",
                       "RodentFlow 以 10 Hz 追踪身体质心。每个采样点画在对应的视频帧上；这里不会重新运行追踪。"))
                    .font(.callout).foregroundStyle(.secondary)
                if loading {
                    ProgressView(L("Reading the saved tracking…", "正在读取已保存的追踪结果…"))
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if total == 0 {
                    Text(L("No tracked samples.", "没有追踪数据。")).foregroundStyle(.secondary)
                } else {
                    viewer
                    TrackingCheckCard(video: video, unit: "sample", total: total,
                                      rangeStart: $rangeStart, rangeCount: $rangeCount,
                                      viewed: viewed, flagged: flagged, notes: $notes,
                                      persist: persist, jump: { show($0) })
                    exportCard
                }
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .frame(maxWidth: 1050, alignment: .leading)
        }
        .onAppear { syncState(); openVideo(); reload() }
        .onDisappear { stopPlaying(); persist() }
        .onChange(of: video.id) { _, _ in stopPlaying(); persist(); syncState(); openVideo(); reload() }
        .onChange(of: video.runFolder) { _, _ in stopPlaying(); syncState(); reload() }
        .onChange(of: rangeStart) { _, _ in persist() }
        .onChange(of: rangeCount) { _, _ in persist() }
    }

    // MARK: Viewer

    private var viewer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.black
                if let image {
                    if let p = point(current) {
                        FlowCentroidOverlay(image: image, point: p, trail: trail(current), showsPoint: imageMatches)
                    } else {
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if !decodeWarning.isEmpty {
                Label(decodeWarning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            if total > 1 {
                Slider(value: Binding(get: { Double(current) }, set: { show(Int($0.rounded())) }),
                       in: 0...Double(total - 1), step: 1)
            }
            HStack(spacing: 10) {
                Button { show(current - 1) } label: { Label(L("Previous", "上一个"), systemImage: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: [.option])
                    .disabled(current <= 0)
                Button { togglePlay() } label: {
                    Label(playing ? L("Pause", "暂停") : L("Play", "播放"), systemImage: playing ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut("p", modifiers: [.option])
                .help(L("Plays to the end of the check range (or of the recording when outside it). ⌥P", "播放到复核范围末尾（不在范围内时播放到视频结尾）。⌥P"))
                Button { show(current + 1) } label: { Label(L("Next", "下一个"), systemImage: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: [.option])
                    .disabled(current >= total - 1)
                Picker(L("Speed", "速度"), selection: $speedRaw) {
                    ForEach(PlaybackSpeed.allCases) { s in Text(s.title).tag(s.rawValue) }
                }
                .frame(width: 170)
                Divider().frame(height: 18)
                Toggle(isOn: Binding(get: { flagged.contains(current) }, set: { setFlag($0) })) {
                    Label(L("Wrong tracking here", "此处追踪错误"), systemImage: "flag.fill")
                }
                .toggleStyle(.button)
                .tint(.orange)
                .keyboardShortcut("f", modifiers: [.option])
                Spacer()
                Text(positionText).font(.callout).monospacedDigit()
            }
            Text(L("Keys: ⌥P play / pause · ⌥← ⌥→ step · ⌥F flag. The orange line is the preceding 2 s.",
                   "按键：⌥P 播放 / 暂停 · ⌥← ⌥→ 逐个查看 · ⌥F 标记。橙色线为之前 2 秒的轨迹。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var positionText: String {
        var text = String(format: L("Sample %d", "采样点 %d"), current)
        if let p = point(current) {
            text += String(format: " · t = %.2f s", p.videoTimeSeconds)
            if p.interpolated { text += " · " + L("no mouse detected", "未检出小鼠") }
            if !p.zone.isEmpty { text += " · " + RFText.key(p.zone) }
        }
        return text
    }

    private var exportCard: some View {
        FigureCard {
            FigureCardHeader(L("Export", "导出"), symbol: "square.and.arrow.up",
                             subtitle: L("Centroid samples of the whole run (CSV) and this tracking check (JSON), in English. The results and figures of the task are exported from the Results tab.",
                                         "整段结果的质心采样点（CSV）和本次追踪复核（JSON），英文。任务结果与图表在“结果”页导出。"))
            Button(L("Export samples and check…", "导出采样点与复核记录…")) { export() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Data

    private func point(_ i: Int) -> FlowTrackingPoint? { i >= 0 && i < points.count ? points[i] : nil }

    private func trail(_ i: Int) -> [FlowTrackingPoint] {
        guard i >= 0, i < points.count else { return [] }
        return Array(points[max(0, i - 20)...i])
    }

    private func reload() {
        guard let folder = store.runFolderURL(video), video.runState == .complete else { return }
        let key = "\(video.id)|\(folder.path)"
        guard key != dataKey else { return }
        dataKey = key
        loading = true
        loadError = nil
        Task { @MainActor in
            do {
                let saved = try await FlowRunCache.load(folder)
                guard dataKey == key else { return }
                points = saved.points
                loading = false
                if rangeStart >= points.count { rangeStart = max(0, points.count - rangeCount) }
                show(min(max(0, rangeStart), max(0, points.count - 1)))
            } catch {
                guard dataKey == key else { return }
                loading = false
                loadError = error.localizedDescription
            }
        }
    }

    private func openVideo() {
        image = nil
        guard let url = store.resolveURL(video) else {
            access = nil
            decodeWarning = L("The source video cannot be opened.", "无法打开原始视频。")
            return
        }
        if access?.url != url { access = ScopedVideoAccess(url: url) }
    }

    private func show(_ requested: Int) {
        Task { @MainActor in await display(requested) }
    }

    /// Decodes the video frame at the sample's timestamp and checks that it is the tracked one before the
    /// overlay is drawn.
    private func display(_ requested: Int) async {
        guard total > 0 else { return }
        let i = min(max(requested, 0), total - 1)
        current = i
        guard let p = point(i), let generator = access?.generator else { return }
        if i >= rangeStart && i <= rangeEnd { viewed.insert(i) }
        generation += 1
        let ticket = generation
        let pts = p.videoTimeSeconds
        let tolerance = max(0.012, 0.53 / max(video.framesPerSecond, 1))
        var decoded: NSImage?
        var actual = Double.nan
        do {
            let result = try await generator.image(at: CMTime(seconds: pts, preferredTimescale: 60_000))
            decoded = NSImage(cgImage: result.image, size: NSSize(width: result.image.width, height: result.image.height))
            actual = result.actualTime.seconds
        } catch {
            decoded = nil
        }
        guard generation == ticket else { return }
        image = decoded
        if decoded == nil {
            imageMatches = false
            decodeWarning = L("Cannot decode this video frame.", "无法解码这一视频帧。")
        } else if actual.isFinite && abs(actual - pts) > tolerance {
            imageMatches = false
            decodeWarning = L("The decoded frame does not match the tracked timestamp; the overlay is hidden to avoid a wrong check.",
                              "解码画面与追踪时间戳不一致；为避免错误复核，已隐藏叠加。")
        } else {
            imageMatches = true
            decodeWarning = ""
        }
    }

    private func togglePlay() {
        if playing { stopPlaying(); return }
        guard total > 1 else { return }
        if current >= total - 1 { current = 0 }
        let last = (current >= rangeStart && current < rangeEnd) ? rangeEnd : total - 1
        let samples = points
        let chosen = speed
        playing = true
        playTask = Task { @MainActor in
            let startWall = Date()
            let startTime = samples[current].videoTimeSeconds
            while !Task.isCancelled && playing && current < last {
                let plan = PlaybackPlanner.next(after: current, last: last, times: { samples[$0].videoTimeSeconds },
                                                speed: chosen, startWall: startWall, startTime: startTime)
                if plan.wait > 0 { try? await Task.sleep(nanoseconds: UInt64(plan.wait * 1_000_000_000)) }
                guard !Task.isCancelled && playing else { break }
                await display(plan.index)
            }
            playing = false
            persist()
        }
    }

    private func stopPlaying() {
        playing = false
        playTask?.cancel()
        playTask = nil
    }

    // MARK: Check state

    private func syncState() {
        stateVideoID = video.id
        let r = store.video(video.id)?.currentReview
        rangeStart = r?.windowStart ?? 0
        rangeCount = min(TrackingCheckCard.maxRange, max(1, r?.windowCount ?? 100))
        viewed = Set(r?.viewed ?? [])
        flagged = Set(r?.flagged ?? [])
        notes = r?.notes ?? ""
        current = rangeStart
    }

    /// Writes the check of the session it belongs to (never another session's).
    private func persist() {
        guard let id = stateVideoID else { return }
        let start = rangeStart, count = rangeCount
        let seen = viewed.sorted(), marks = flagged.sorted(), text = notes
        store.updateReview(id, unit: "sample") { s in
            s.windowStart = start
            s.windowCount = count
            s.viewed = seen
            s.flagged = marks
            s.notes = text
        }
    }

    private func setFlag(_ on: Bool) {
        if on { flagged.insert(current) } else { flagged.remove(current) }
        persist()
    }

    // MARK: Export

    private func export() {
        persist()
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L("Export Here", "导出到此处")
        panel.message = L("A new folder is created inside the chosen folder.", "将在所选文件夹中新建一个文件夹。")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let access = parent.startAccessingSecurityScopedResource()
        defer { if access { parent.stopAccessingSecurityScopedResource() } }
        do {
            let session = video.sessionNumber.map { "_s\($0)" } ?? ""
            let folder = try ExportFolder.make(in: parent, name: video.displayName + session + "_" + assay.rawValue, suffix: "frame_review")
            var lines = ["sample_index,frame_index,video_time_s,clip_time_s,image_x_norm,image_y_norm,arena_x_norm,arena_y_norm,x_cm,y_cm,confidence,detected,zone,motion_index,blob_area_fraction,flagged_in_check"]
            lines.reserveCapacity(points.count + 1)
            for (i, p) in points.enumerated() {
                var row: [String] = []
                row.append(String(i))
                row.append(String(p.frameIndex))
                row.append(FastFormat.fixed(p.videoTimeSeconds, 4))
                row.append(FastFormat.fixed(p.clipTimeSeconds, 4))
                row.append(FastFormat.fixed(p.imageXNormalized, 6))
                row.append(FastFormat.fixed(p.imageYNormalized, 6))
                row.append(FastFormat.fixed(p.arenaXNormalized, 6))
                row.append(FastFormat.fixed(p.arenaYNormalized, 6))
                row.append(FastFormat.fixed(p.xCentimeters, 3))
                row.append(FastFormat.fixed(p.yCentimeters, 3))
                row.append(FastFormat.fixed(p.confidence, 4))
                row.append(p.interpolated ? "0" : "1")
                row.append(FigureExport.csv(p.zone))
                row.append(p.motionIndex.map { FastFormat.fixed($0, 6) } ?? "")
                row.append(p.blobAreaFraction.map { FastFormat.fixed($0, 6) } ?? "")
                row.append(flagged.contains(i) ? "1" : "0")
                lines.append(row.joined(separator: ","))
            }
            try FigureExport.writeText(lines.joined(separator: "\n") + "\n", to: folder.appendingPathComponent("rodentflow_centroid_samples.csv"))
            let check = TrackingCheckExport(video: store.video(video.id) ?? video, assay: assay, project: store.selectedProject)
            try check.write(to: folder.appendingPathComponent("tracking_check.json"))
            message = String(format: L("Exported to %@", "已导出到 %@"), folder.path)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            message = L("Export failed: ", "导出失败：") + error.localizedDescription
        }
    }
}

/// The tracking check of a session as written into exports (English).
struct TrackingCheckExport: Encodable {
    let metadata: [String: String]
    let unit: String
    let range_start: Int
    let range_end: Int
    let viewed: [Int]
    let flagged: [Int]
    let verdict: String
    let notes: String
    let reviewed_at: String

    init(video: VideoRecord, assay: StudyAssay, project: NativeProject?) {
        let r = video.currentReview
        metadata = SessionResultsEngine.metadata(video: video, assay: assay, project: project)
        unit = r?.unit ?? (assay.module == .flow ? "sample" : "frame")
        range_start = r?.windowStart ?? 0
        range_end = r?.windowEnd ?? 99
        viewed = r?.viewed ?? []
        flagged = r?.flagged ?? []
        verdict = (r?.verdict ?? .unreviewed).exportValue
        notes = r?.notes ?? ""
        reviewed_at = r?.reviewedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
