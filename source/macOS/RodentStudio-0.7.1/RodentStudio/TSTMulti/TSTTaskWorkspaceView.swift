// TSTTaskWorkspaceView.swift — TSTScorer 6 is an assay-specific ANALYZER, not a parallel workspace.
// The normal RodentStudio Task → Group → Animal → Date / Session hierarchy is authoritative.
// A shared recording may generate multiple regular VideoRecords, one for each scored chamber.
//
// The recording sheet is a guided macOS dialog: header with the steps, the picture on the left and the
// step's settings on the right, and a fixed footer with Back / Cancel (Esc) / the next action (Return).
import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers
import Observation
import Foundation

struct TSTAnimalMapping: Codable, Identifiable, Equatable {
    var chamber: Int
    var id: Int { chamber }
    var animalID: String = ""
    var group: String = ""
    var sex: String = ""
    // Optional keys allow old 0.7.0 TST archives to be decoded without discarding the archive.
    var sessionDate: String?
    var sessionNumber: Int?
    var excluded: Bool = false
    var exclusionReason: String = ""
    /// The user chose not to save this chamber (empty, failed, selected by mistake): no session is
    /// created for it. Optional so archives written before this field existed still decode.
    var skipped: Bool?

    var isSkipped: Bool { skipped ?? false }
}

/// Compact persisted per-chamber trace for later review in the regular Session page.
/// Only the displayed motion signal, time points and QC masks are duplicated here;
/// original pixel/shape measurements are retained in the recording-level framewise CSV.
struct TSTArchivedTrace: Codable {
    var time: [Double]
    var motion: [Double]
    var immobile: [Bool]
    var noMouse: [Bool]

    init(_ original: ChamberTrace) {
        time = original.time
        motion = original.motion.map { $0.isFinite ? $0 : 0 }
        immobile = original.immobile
        noMouse = original.noMouse
    }

    var chartTrace: ChamberTrace {
        ChamberTrace(time: time, motion: motion, pixelPercent: [], shapePercent: [], immobile: immobile,
                     noMouse: noMouse, area: [], cx: [], cy: [])
    }
}

struct TSTStoredRecording: Codable, Identifiable {
    var id: UUID
    var taskID: UUID
    var videoName: String
    var savedAt: Date
    var detector: String
    var keyFrameTime: Double
    var settings: AnalysisSettings
    var fps: Double
    var summaries: [ChamberSummary]
    var mappings: [TSTAnimalMapping]
    var videoFileName: String?
    var videoDuration: Double?
    var videoFPS: Double?
    var videoWidth: Int?
    var videoHeight: Int?
    var traces: [TSTArchivedTrace]?
    // Everything needed to open the recording again for new settings or a new analysis (0.7.1 round 6+).
    // Optional so older archives still decode; for those the chambers are read from settings.json.
    var layout: ChamberLayout?
    var scanTimes: [Double]?
    var scanDetections: [[DetBox?]]?
    var keyFrameManual: Bool?
    var keyFrameSettings: KeyFrameSettings?
    /// measures.json (raw per-frame measures) was written: scoring can be changed without decoding the video.
    var hasMeasures: Bool?

    var animalCount: Int { mappings.filter { !$0.animalID.isEmpty && !$0.excluded && !$0.isSkipped }.count }
}

/// Raw per-frame measures of every chamber, stored column-wise (measures.json). With them a saved
/// recording can be re-scored (threshold, minimum bout, measure, windows) at once, without the video.
struct TSTArchivedMeasures: Codable {
    struct Chamber: Codable {
        var time: [Double] = []
        var pixelChange: [Double] = []
        var shapeChange: [Double] = []
        var area: [Double] = []
        var cx: [Double] = []
        var cy: [Double] = []
        var boxChange: [Double] = []
        var boxPresent: [Bool] = []
        var boxBody: [Double] = []
    }
    var chambers: [Chamber]

    init(_ measures: [[FrameMeasure]]) {
        chambers = measures.map { ms in
            var c = Chamber()
            for m in ms {
                c.time.append(m.time); c.pixelChange.append(m.pixelChange); c.shapeChange.append(m.shapeChange)
                c.area.append(m.area); c.cx.append(m.cx); c.cy.append(m.cy)
                c.boxChange.append(m.boxChange); c.boxPresent.append(m.boxPresent); c.boxBody.append(m.boxBody)
            }
            return c
        }
    }

    var measures: [[FrameMeasure]]? {
        var out: [[FrameMeasure]] = []
        for c in chambers {
            let n = c.time.count
            guard [c.pixelChange.count, c.shapeChange.count, c.area.count, c.cx.count, c.cy.count,
                   c.boxChange.count, c.boxPresent.count, c.boxBody.count].allSatisfy({ $0 == n }) else { return nil }
            out.append((0..<n).map { k in
                var m = FrameMeasure(time: c.time[k], pixelChange: c.pixelChange[k], shapeChange: c.shapeChange[k],
                                     area: c.area[k], cx: c.cx[k], cy: c.cy[k])
                m.boxChange = c.boxChange[k]
                m.boxPresent = c.boxPresent[k]
                m.boxBody = c.boxBody[k]
                return m
            })
        }
        return out
    }

    /// NaN marks "unknown" in the measures; plain JSON has no NaN, so it is written as a string.
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }
}

/// What is needed to open a saved recording in the recording sheet again.
struct TSTReanalysisSource {
    var record: TSTStoredRecording
    var url: URL
    var layout: ChamberLayout?
    var measures: [[FrameMeasure]]?

    init?(_ record: TSTStoredRecording) {
        guard let url = TSTTaskArchive.sourceURL(record) else { return nil }
        self.record = record
        self.url = url
        layout = record.layout ?? TSTTaskArchive.legacyLayout(record)
        measures = record.hasMeasures == true ? TSTTaskArchive.loadMeasures(record) : nil
    }

    /// When each mouse was suspended (absolute video time), as used by the saved analysis.
    var onsets: [Double]? {
        record.settings.chamberOnsetSec.map { $0.map { record.settings.startSec + $0 } }
    }
}

extension ChamberLayout {
    /// The same chambers in a picture of another size (another processing width).
    func scaled(toWidth w: Int, height h: Int) -> ChamberLayout {
        guard w > 0, h > 0, imageWidth > 0, imageHeight > 0, w != imageWidth || h != imageHeight else { return self }
        let sx = Double(w) / Double(imageWidth), sy = Double(h) / Double(imageHeight)
        var l = self
        l.walls = walls.map { min(Double(w - 1), max(0, $0 * sx)) }
        l.y0 = max(0, Int((Double(y0) * sy).rounded()))
        l.y1 = min(h, max(l.y0 + 10, Int((Double(y1) * sy).rounded())))
        l.imageWidth = w
        l.imageHeight = h
        l.spacing = spacing * sx
        l.wallProfile = []
        return l
    }
}

/// Dedicated immutable run archive. All files live in application support, not in the .app bundle.
/// The canonical run ID and per-chamber mapping appear in every animal-level export.
enum TSTTaskArchive {
    static func taskFolder(_ task: UUID) throws -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("RodentDesktopNative/TSTMulti", isDirectory: true)
            .appendingPathComponent(task.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func list(_ task: UUID) -> [TSTStoredRecording] {
        guard let folder = try? taskFolder(task),
              let dirs = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("record.json")) else { return nil }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(TSTStoredRecording.self, from: data)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    static func load(_ task: UUID, record id: UUID) -> TSTStoredRecording? {
        guard let folder = try? taskFolder(task) else { return nil }
        let url = folder.appendingPathComponent(id.uuidString).appendingPathComponent("record.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(TSTStoredRecording.self, from: data)
    }

    static func sourceURL(_ record: TSTStoredRecording) -> URL? {
        guard let name = record.videoFileName,
              let folder = try? taskFolder(record.taskID) else { return nil }
        let url = folder.appendingPathComponent(record.id.uuidString).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func loadMeasures(_ record: TSTStoredRecording) -> [[FrameMeasure]]? {
        guard let folder = try? taskFolder(record.taskID),
              let data = try? Data(contentsOf: folder.appendingPathComponent(record.id.uuidString).appendingPathComponent("measures.json")),
              let archived = try? TSTArchivedMeasures.decoder.decode(TSTArchivedMeasures.self, from: data) else { return nil }
        return archived.measures
    }

    /// Chambers of an archive written before the layout was stored, read back from its settings.json.
    static func legacyLayout(_ record: TSTStoredRecording) -> ChamberLayout? {
        struct Saved: Decodable { var walls: [Double]; var y0: Int; var y1: Int; var imageWidth: Int; var imageHeight: Int }
        guard let folder = try? taskFolder(record.taskID),
              let data = try? Data(contentsOf: folder.appendingPathComponent(record.id.uuidString).appendingPathComponent("settings.json")),
              let s = try? JSONDecoder().decode(Saved.self, from: data), s.walls.count >= 2 else { return nil }
        let n = s.walls.count - 1
        let analysed = Set(record.summaries.filter(\.analysed).map(\.chamber))
        return ChamberLayout(walls: s.walls, y0: s.y0, y1: s.y1, empty: Array(repeating: false, count: n),
                             enabled: (1...n).map { analysed.contains($0) }, imageWidth: s.imageWidth, imageHeight: s.imageHeight,
                             spacing: (s.walls[n] - s.walls[0]) / Double(n), wallProfile: [], notes: [])
    }

    static func remove(_ record: TSTStoredRecording) {
        guard let folder = try? taskFolder(record.taskID) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(record.id.uuidString))
    }

    /// Validates, then writes the archive. The text outputs are built on the main actor (cheap); copying the
    /// original video (often several GB) and writing the files happen off the main thread so the window
    /// stays responsive.
    @MainActor
    static func save(task: UUID, model: TSTAppModel, mappings: [TSTAnimalMapping]) async throws -> TSTStoredRecording {
        guard let result = model.result else { throw ArchiveError.missingResults }
        let skipped = Set(mappings.filter(\.isSkipped).map(\.chamber))
        let selected = result.summaries.filter(\.analysed).map(\.chamber).filter { !skipped.contains($0) }
        guard !selected.isEmpty else { throw ArchiveError.nothingToSave }
        for chamber in selected {
            guard let m = mappings.first(where: { $0.chamber == chamber }),
                  !m.animalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ArchiveError.unmapped(chamber)
            }
            if m.excluded && m.exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ArchiveError.exclusionReason(chamber)
            }
        }
        guard let info = model.info else { throw ArchiveError.missingSource }
        let selectedMappings = mappings.filter { selected.contains($0.chamber) }
        for m in selectedMappings where !SessionDate.isValid(m.sessionDate) || (m.sessionNumber ?? 0) < 1 {
            throw ArchiveError.sessionInfo(m.chamber)
        }
        // One mouse cannot occupy two simultaneously recorded chambers.
        let keys = selectedMappings.map { $0.animalID.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Set(keys).count == keys.count else { throw ArchiveError.duplicateIDs }
        let ext = info.url.pathExtension.lowercased()
        let sourceName = "original." + (ext.isEmpty ? "mov" : ext)
        let record = TSTStoredRecording(id: UUID(), taskID: task, videoName: model.videoName,
                                        savedAt: Date(), detector: model.detectorName,
                                        keyFrameTime: model.keyTime, settings: result.settings,
                                        fps: result.fps, summaries: result.summaries, mappings: mappings,
                                        videoFileName: sourceName, videoDuration: info.duration, videoFPS: info.fps,
                                        videoWidth: info.orientedWidth, videoHeight: info.orientedHeight,
                                        traces: result.traces.map(TSTArchivedTrace.init),
                                        layout: result.layout,
                                        scanTimes: model.scanTimes.isEmpty ? nil : model.scanTimes,
                                        scanDetections: model.scanTimes.isEmpty ? nil : model.scanDetections,
                                        keyFrameManual: model.keyFrameIsManual,
                                        keyFrameSettings: model.stored.keyFrame,
                                        hasMeasures: !model.measures.isEmpty)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        var files: [(String, Data)] = [
            ("original_summary.csv", Data(CSVExport.summary(result, videoName: model.videoName).utf8)),
            ("framewise.csv", Data(CSVExport.framewise(result).utf8)),
            ("settings.json", Data(CSVExport.settingsJSON(result).utf8)),
        ]
        if let key = model.keyResult {
            files.append(("keyframe.csv",
                          Data(CSVExport.keyFrame(key, keyTime: model.keyTime, analysisStart: result.settings.startSec,
                                                  analysisDuration: result.settings.durationSec, detector: model.detectorName).utf8)))
        }
        files.append(("animal_summary.csv", Data(taskCSV([record]).utf8)))
        files.append(("record.json", try enc.encode(record)))

        let parent = try taskFolder(task)
        let source = info.url
        let recordID = record.id
        let output = files
        let measures = model.measures
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let folder = parent.appendingPathComponent(recordID.uuidString, isDirectory: true)
            let staging = parent.appendingPathComponent(".pending-" + recordID.uuidString, isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false)
            do {
                if !measures.isEmpty {
                    let data = try TSTArchivedMeasures.encoder.encode(TSTArchivedMeasures(measures))
                    try data.write(to: staging.appendingPathComponent("measures.json"), options: .atomic)
                }
                // TSTScorer may analyse a temporary Photos copy. Persist the video once, outside the .app,
                // so every linked animal session remains reviewable after a restart.
                try fm.copyItem(at: source, to: staging.appendingPathComponent(sourceName))
                for (name, data) in output {
                    try data.write(to: staging.appendingPathComponent(name), options: .atomic)
                }
                try fm.moveItem(at: staging, to: folder)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
        }.value
        return record
    }

    static func taskCSV(_ records: [TSTStoredRecording]) -> String {
        func escaped(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func number(_ value: Double?) -> String { guard let value, value.isFinite else { return "" }; return String(format: "%.6f", value) }
        let cols = ["task_id","run_id","saved_at","video","chamber","animal_id","group","sex","excluded","exclusion_reason","analysed","immobile_total_s","immobile_pct","last_window_immobile_s","latency_s","bouts","mean_bout_s","longest_bout_s","no_mouse_pct","detector","threshold_pct","sample_fps","key_frame_s","suspended_at_video_s","immobile_early_s","immobile_primary_s","immobile_primary_pct","immobile_test_s","immobile_test_pct","test_coverage","mobility_intensity_pct_body"]
        var lines = [cols.joined(separator: ",")]
        for r in records.sorted(by: { $0.savedAt < $1.savedAt }) {
            for s in r.summaries where s.analysed {
                let m = r.mappings.first { $0.chamber == s.chamber }
                if m?.isSkipped == true { continue }   // not saved as a session: no animal row
                lines.append([
                    r.taskID.uuidString, r.id.uuidString, ISO8601DateFormatter().string(from: r.savedAt),
                    escaped(r.videoName), String(s.chamber), escaped(m?.animalID ?? ""), escaped(m?.group ?? ""),
                    escaped(m?.sex ?? ""), m?.excluded == true ? "true" : "false",
                    escaped(m?.exclusionReason ?? ""), s.analysed ? "true" : "false",
                    number(s.immobileTotalSec), number(s.immobilePercent), number(s.immobileLastWindowSec),
                    number(s.latencySec), String(s.bouts), number(s.meanBoutSec), number(s.longestBoutSec),
                    number(s.noMousePercent), escaped(r.detector), number(r.settings.immobilityThreshold),
                    number(r.fps), number(r.keyFrameTime),
                    number(s.onsetSec.map { $0 + r.settings.startSec }), number(s.earlyImmobileSec), number(s.primaryImmobileSec),
                    number(s.primaryImmobilePercent), number(s.testImmobileSec), number(s.testImmobilePercent),
                    number(s.testCoverage), number(s.mobilityIntensity)
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    enum ArchiveError: LocalizedError {
        case missingResults, missingSource, unmapped(Int), sessionInfo(Int), exclusionReason(Int), duplicateIDs, nothingToSave
        var errorDescription: String? {
            switch self {
            case .missingResults:
                return L("Run the analysis before saving.", "请先完成分析再保存。")
            case .missingSource:
                return L("The source video is no longer available.", "原始视频已无法访问。")
            case .sessionInfo(let c):
                return String(format: L("Enter the date and session number for chamber %d.", "请填写第 %d 格的日期和实验次数。"), c)
            case .unmapped(let c):
                return String(format: L("Enter an animal ID for chamber %d.", "请填写第 %d 格的小鼠编号。"), c)
            case .exclusionReason(let c):
                return String(format: L("Enter an exclusion reason for chamber %d.", "请填写第 %d 格的排除原因。"), c)
            case .duplicateIDs:
                return L("Animal IDs must be unique within one multi-chamber recording.", "同一段多格录像中的小鼠编号不能重复。")
            case .nothingToSave:
                return L("No chamber is marked to be saved.", "没有勾选任何要保存的格子。")
            }
        }
    }
}

enum TSTMetricTitle {
    static func title(_ m: MotionMetric) -> String {
        switch m {
        case .box: return L("Pixel change in the motion box", "运动框内像素变化")
        case .shape: return L("Posture change of the outline", "轮廓姿态变化")
        case .pixel: return L("Pixel change on the outline", "轮廓内像素变化")
        }
    }
}

// MARK: - Recording sheet

/// Steps shown in the sheet's header. Scanning belongs to "Key frame"; analysing to "Results".
enum TSTWizardStep: Int, CaseIterable, Identifiable {
    case video = 1, chambers, keyFrame, results

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .video: return L("Video", "视频")
        case .chambers: return L("Chambers", "格子")
        case .keyFrame: return L("Key frame", "关键帧")
        case .results: return L("Results & animals", "结果与小鼠")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .chambers: return "rectangle.split.3x1"
        case .keyFrame: return "viewfinder"
        case .results: return "checklist"
        }
    }
}

/// The TST algorithm is presented from the SAME "Add" action used by other tasks. It is not a competing
/// task workspace, animal history or export system: saving creates ordinary sessions in this task.
struct TSTRecordingAnalysisSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let experiment: NativeExperiment
    /// Video chosen in the main window (open panel or drag and drop); nil shows the choose-video step.
    var initialURL: URL? = nil
    /// Group of the sidebar selection the recording was added from; pre-fills new animals.
    var presetGroup: String? = nil
    /// A saved recording opened again (from one of its sessions) for new settings or a new analysis.
    /// Saving then updates its sessions instead of adding new ones.
    var replacing: TSTStoredRecording? = nil
    var onSaved: ([UUID]) -> Void

    private enum PendingDiscard: Identifiable {
        case close, otherVideo
        var id: Self { self }
    }

    @State private var model = TSTAppModel()
    @State private var started = false
    @State private var rows: [TSTAnimalMapping] = []
    /// Chambers whose session number was set by hand (no longer renumbered automatically).
    @State private var editedSessions: Set<Int> = []
    @State private var recordingDate = Date()
    @State private var dateNote = ""
    @State private var dateReady = false
    @State private var groupForAll = ""
    @State private var saving = false
    @State private var saveError: String?
    @State private var pendingDiscard: PendingDiscard?
    @State private var showSettings = false
    @State private var showStartPopover = false
    @State private var manualStart: Double = 0

    private var project: NativeProject? { store.selectedProject }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = model.errorMessage {
                banner(message)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 1000, idealWidth: 1200, minHeight: 660, idealHeight: 780)
        .environment(model)
        .sheet(isPresented: $showSettings) {
            TSTSettingsView().environment(model)
        }
        .confirmationDialog(pendingDiscard == .otherVideo
                                ? L("Discard this analysis and choose another video?", "放弃这次分析并选择另一段视频？")
                                : L("Discard this analysis?", "放弃这次分析？"),
                            isPresented: Binding(get: { pendingDiscard != nil }, set: { if !$0 { pendingDiscard = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDiscard) { intent in
            Button(L("Discard", "放弃"), role: .destructive) { performDiscard(intent) }
            Button(L("Keep working", "继续编辑"), role: .cancel) { pendingDiscard = nil }
        } message: { _ in
            Text(replacing != nil
                 ? L("The saved sessions of this recording stay as they are.", "这段录像已保存的实验保持不变。")
                 : L("Nothing from this recording has been saved to the task yet.", "这段录像的结果还没有保存到任务中。"))
        }
        .alert(L("Could not save", "无法保存"),
               isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button(L("OK", "好")) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: start)
        .onDisappear { model.resetForNewRecording() }   // stops any scan / analysis still running
        .onChange(of: model.phase) { _, phase in
            if phase == .loading && model.info == nil {
                // A different video: forget what was typed for the previous one.
                rows = []
                editedSessions = []
                dateReady = false
            }
            if phase == .results { prepareRows() }
        }
        // A re-opened recording runs with ITS settings; they do not become the defaults for new recordings.
        .onChange(of: model.stored) { _, value in if replacing == nil { TSTSettingsStore.save(value) } }
        .onChange(of: model.stored.keyFrame) { model.recomputeKeyFrame() }
        .onChange(of: rows.map { $0.isSkipped ? "" : $0.animalID }) { renumber() }
        .interactiveDismissDisabled(model.hasUnsavedWork || saving)
    }

    // MARK: Header

    private var currentStep: TSTWizardStep {
        switch model.phase {
        case .home, .loading: return .video
        case .chambers: return .chambers
        case .scanning, .keyframe: return .keyFrame
        case .analyzing, .results: return .results
        }
    }

    private func stepAvailable(_ s: TSTWizardStep) -> Bool {
        guard !model.isBusy, !saving else { return false }
        switch s {
        case .video: return model.info != nil && replacing == nil
        case .chambers: return model.layout != nil
        case .keyFrame: return model.keyFrameAvailable
        case .results: return model.resultMatchesSetup
        }
    }

    private func stepDone(_ s: TSTWizardStep) -> Bool {
        switch s {
        case .video: return model.info != nil
        case .chambers: return model.keyFrameAvailable
        case .keyFrame: return model.result != nil
        case .results: return false
        }
    }

    private func goTo(_ s: TSTWizardStep) {
        guard s != currentStep, stepAvailable(s) else { return }
        switch s {
        case .video: requestOtherVideo()
        case .chambers: model.phase = .chambers
        case .keyFrame: model.phase = .keyframe
        case .results: model.phase = .results
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(replacing != nil ? L("Analyse TST recording again", "重新分析 TST 录像")
                                      : L("Add TST recording", "添加 TST 录像")).font(.title3.bold())
                Text(model.videoName.isEmpty ? experiment.displayTitle : experiment.displayTitle + " · " + model.videoName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ForEach(TSTWizardStep.allCases) { s in
                    let isCurrent = s == currentStep
                    let done = stepDone(s) && !isCurrent
                    let available = stepAvailable(s)
                    Button {
                        goTo(s)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: done ? "checkmark.circle.fill" : s.symbol)
                                .foregroundStyle(done ? Color.green : (isCurrent ? Color.accentColor : Color.secondary))
                            Text(s.title).lineLimit(1)
                                .foregroundStyle(isCurrent || available ? Color.primary : Color.secondary)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 9)
                        .background(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(isCurrent || available)
                    .help(s == .video && available ? L("Choose another video", "选择另一段视频") : s.title)
                    if s != .results {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L("Dismiss", "关闭提示"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .home: TSTHomeView(onChoose: { chooseVideo() })
        case .loading: TSTBusyView(text: model.statusText)
        case .chambers: TSTChambersView(onShowSettings: { showSettings = true })
        case .scanning: TSTScanView()
        case .keyframe: TSTKeyFrameView(onShowSettings: { showSettings = true })
        case .analyzing: TSTAnalyzingView()
        case .results: resultsPage
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            footerLeading
            Spacer(minLength: 12)
            footerStatus
            Button(L("Cancel", "取消"), role: .cancel) { requestClose() }
                .keyboardShortcut(.cancelAction)
                .disabled(saving)
            footerActions
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var footerLeading: some View {
        switch model.phase {
        case .chambers:
            if replacing == nil {
                Button(L("Choose another video…", "选择另一段视频…")) { requestOtherVideo() }
            }
        case .keyframe:
            Button {
                model.phase = .chambers
            } label: {
                Label(L("Chambers", "格子"), systemImage: "chevron.left")
            }
        case .results:
            Button {
                model.phase = .keyframe
            } label: {
                Label(L("Key frame", "关键帧"), systemImage: "chevron.left")
            }
            .disabled(saving)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        switch model.phase {
        case .chambers:
            if model.selectedCount == 0 {
                Text(L("Select at least one chamber.", "请至少选择一个格子。")).font(.callout).foregroundStyle(.orange)
            } else {
                Text(String(format: L("%d chambers selected", "已选 %d 个格子"), model.selectedCount))
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .keyframe:
            if model.selectedCount == 0 {
                Text(L("Select at least one chamber.", "请至少选择一个格子。")).font(.callout).foregroundStyle(.orange)
            } else if model.analysisWindow.duration < 5 {
                Text(L("The analysis window is shorter than 5 s.", "分析时间窗短于 5 秒。")).font(.callout).foregroundStyle(.orange)
            } else {
                Text(String(format: L("%d chambers · %.0f s from %@", "%1$d 个格子 · 从 %3$@ 起 %2$.0f 秒"),
                            model.selectedCount, model.analysisWindow.duration, TSTFormat.seconds(model.keyTime)))
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .scanning:
            Text(TSTFormat.remaining(model.scanRemaining))
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
        case .analyzing:
            Text(TSTFormat.remaining(model.analysisRemaining)
                 + (model.analysisRemaining.map { String(format: L(" · done at %@", " · 预计 %@ 完成"), TSTFormat.finishTime($0)) } ?? ""))
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
        case .results:
            if saving {
                ProgressView().controlSize(.small)
                Text(L("Saving…", "正在保存…")).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(readinessText)
                    .font(.callout)
                    .foregroundStyle(readyToSave ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        switch model.phase {
        case .home:
            EmptyView()
        case .loading:
            // Only while a new video is being opened; re-detecting chambers is quick and keeps the video.
            if model.layout == nil {
                Button(L("Stop", "停止")) { model.resetForNewRecording() }
            }
        case .chambers:
            if model.keyFrameAvailable {
                Button(L("Scan again", "重新扫描")) { model.startScan() }
                    .disabled(model.selectedCount == 0)
                Button(L("Continue →", "继续 →")) { model.phase = .keyframe }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedCount == 0)
            } else {
                Button(L("Set start by hand…", "手动设定起点…")) {
                    manualStart = model.keyTime
                    showStartPopover = true
                }
                .disabled(model.selectedCount == 0)
                .popover(isPresented: $showStartPopover, arrowEdge: .top) { manualStartPopover }
                Button(L("Find key frame →", "寻找关键帧 →")) { model.startScan() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedCount == 0)
            }
        case .scanning:
            Button(L("Stop scanning", "停止扫描")) { model.cancelScan() }
            Button(L("Use key frame now →", "采用此关键帧 →")) { model.useKeyFrameNow() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.keyResult?.keyTime == nil)
        case .keyframe:
            if model.resultMatchesSetup {
                Button(L("Analyse again", "重新分析")) { model.startAnalysis() }
                Button(L("Results →", "查看结果 →")) { model.phase = .results }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(L("Analyse →", "开始分析 →")) { model.startAnalysis() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedCount == 0 || model.analysisWindow.duration < 5)
            }
        case .analyzing:
            Button(L("Stop analysis", "停止分析")) { model.cancelAnalysis() }
        case .results:
            Button(saveTitle) { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!readyToSave || saving)
        }
    }

    private var manualStartPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Skip the scan", "跳过扫描")).font(.headline)
            Text(L("For a video that is already trimmed to start after every mouse is hung. You can still fine-tune the start on the next step.",
                   "适用于已剪辑为所有小鼠挂好之后才开始的视频。下一步仍可微调起点。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TSTNumberRow(title: L("Start at", "起点"), unit: L("s", "秒"), value: $manualStart,
                         range: 0...max(0, (model.info?.duration ?? 1) - 1))
            HStack {
                Spacer()
                Button(L("Use this start", "使用此起点")) {
                    showStartPopover = false
                    model.skipScan(start: manualStart)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Video choice / closing

    private func start() {
        guard !started else { return }
        started = true
        if let old = replacing {
            if let source = TSTReanalysisSource(old) {
                model.reopen(source)
            } else {
                model.errorMessage = L("The saved copy of this recording's video is missing. Choose the original video file to analyse it again; saving then updates the sessions of this recording.",
                                       "这段录像保存的视频副本已不存在。请选择原始视频文件重新分析；保存时会更新这段录像的实验。")
            }
        } else if let url = initialURL {
            model.open(url: url, name: url.lastPathComponent)
        }
    }

    private func chooseVideo() {
        guard let url = TSTVideoPicker.choose() else { return }
        model.open(url: url, name: url.lastPathComponent)
    }

    private func requestOtherVideo() {
        if model.hasUnsavedWork { pendingDiscard = .otherVideo } else { chooseVideo() }
    }

    private func requestClose() {
        guard !saving else { return }
        if model.hasUnsavedWork { pendingDiscard = .close } else { dismiss() }
    }

    private func performDiscard(_ intent: PendingDiscard) {
        pendingDiscard = nil
        switch intent {
        case .close:
            model.resetForNewRecording()
            dismiss()
        case .otherVideo:
            chooseVideo()
        }
    }

    // MARK: Results page

    private var resultsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let r = model.result {
                    resultFacts(r)
                    FigureCard {
                        FigureCardHeader(L("Which animal was in each chamber?", "每个格子里是哪只小鼠？"), symbol: "person.2",
                                         subtitle: L("Each ticked chamber is saved as one session of one animal in this task. Group and sex belong to the animal: an animal that already has sessions here keeps its own. Untick a chamber to leave it out.",
                                                     "每个勾选的格子保存为此任务中一只小鼠的一次实验。分组和性别属于小鼠：已有实验的小鼠沿用原来的分组和性别。取消勾选可不保存该格。"))
                        recordingFields
                        assignmentGrid(r)
                    }
                    TSTResultDetails(animalLabel: { animalLabel($0) })
                }
            }
            .padding(18)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Scoring may have been changed on the key-frame step after this result was computed.
        .onAppear { model.rescore() }
    }

    private func resultFacts(_ r: TSTMultiAnalysisResult) -> some View {
        let start = r.settings.startSec, end = r.settings.startSec + r.settings.durationSec
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("Results of this recording", "这段录像的结果")).font(.title3.bold())
            Text([
                String(format: L("Analysed %@ – %@ of the video", "分析了视频的 %@ – %@"), TSTFormat.seconds(start), TSTFormat.seconds(end)),
                model.keyFrameIsManual ? L("start set by hand", "起点为手动设定") : L("start = detected key frame", "起点 = 自动识别的关键帧"),
                L("detector: ", "检测器：") + model.detectorName,
                L("measure: ", "指标：") + TSTMetricTitle.title(r.settings.metric),
            ].joined(separator: " · "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recordingFields: some View {
        HStack(spacing: 14) {
            DatePicker(L("Recording date *", "实验日期 *"),
                       selection: Binding(get: { recordingDate }, set: { recordingDate = $0; dateNote = "" }),
                       displayedComponents: .date)
                .datePickerStyle(.field)
                .fixedSize()
            if !dateNote.isEmpty {
                Label(dateNote, systemImage: "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(L("Applies to every chamber of this recording.", "适用于这段录像的所有格子。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            TextField(L("Group for new animals", "新小鼠的分组"), text: $groupForAll)
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            Button(L("Apply to all", "全部应用")) { applyGroupToAll() }
                .disabled(trimmed(groupForAll).isEmpty)
        }
    }

    private func assignmentGrid(_ r: TSTMultiAnalysisResult) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text(L("Save", "保存"))
                    .help(L("Untick to skip a chamber: no session is created for it.", "取消勾选则跳过该格：不为它创建实验记录。"))
                Text(L("Chamber", "格子"))
                Text(L("★ Immobile", "★ 不动")).gridColumnAlignment(.trailing)
                    .help(L("Immobility in the primary window (minutes 2–6 after this mouse was hung)", "主要时间窗内的不动时间（该鼠挂上后第 2–6 分钟）"))
                Text("%").gridColumnAlignment(.trailing)
                Text(L("No mouse", "无小鼠")).gridColumnAlignment(.trailing)
                Text(L("Animal ID *", "小鼠编号 *"))
                Text(L("Group", "分组"))
                Text(L("Sex", "性别"))
                Text(L("Session # *", "实验次数 *"))
                Text(L("Exclude", "排除"))
                    .help(L("Keep the session but leave it out of animal means and group statistics (a reason is required).",
                            "保留该次实验，但不纳入小鼠均值和组统计（需填写原因）。"))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
            ForEach($rows) { $row in
                assignmentRow($row, r.summaries.first { $0.chamber == row.chamber })
            }
        }
    }

    @ViewBuilder
    private func assignmentRow(_ row: Binding<TSTAnimalMapping>, _ s: ChamberSummary?) -> some View {
        let m = row.wrappedValue
        let existing = existingAttributes(m)
        let messages = rowMessages(m)
        GridRow {
            Toggle("", isOn: Binding(get: { !row.wrappedValue.isSkipped },
                                     set: { row.wrappedValue.skipped = $0 ? nil : true }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(L("Untick to skip this chamber: no session is created for it.", "取消勾选则跳过此格：不为它创建实验记录。"))
            Text(String(format: L("Chamber %d", "第 %d 格"), m.chamber))
                .fontWeight(.medium)
                .foregroundStyle(m.isSkipped ? Color.secondary : Color.primary)
            Text(s.map { String(format: "%.1f s", $0.primaryImmobileSec ?? $0.immobileLastWindowSec) } ?? "–").monospacedDigit()
            Text(s.flatMap { $0.primaryImmobilePercent }.map { String(format: "%.0f", $0) } ?? "–").monospacedDigit()
            noMouseCell(s)
            if m.isSkipped {
                Text(L("Not saved — no session is created for this chamber.", "不保存——不为此格创建实验记录。"))
                    .foregroundStyle(.secondary)
                    .gridCellColumns(5)
            } else {
                TextField(L("e.g. M01", "如 M01"), text: row.animalID)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                groupCell(row, existing: existing)
                sexCell(row, existing: existing)
                Stepper(value: Binding(get: { row.wrappedValue.sessionNumber ?? 1 },
                                       set: {
                                           row.wrappedValue.sessionNumber = max(1, $0)
                                           editedSessions.insert(row.wrappedValue.chamber)
                                       }),
                        in: 1...9999) {
                    Text("#\(m.sessionNumber ?? 1)").monospacedDigit().frame(minWidth: 36, alignment: .leading)
                }
                Toggle("", isOn: row.excluded)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(L("Keep the session but leave it out of animal means and group statistics (a reason is required).",
                            "保留该次实验，但不纳入小鼠均值和组统计（需填写原因）。"))
            }
        }
        if !m.isSkipped && (m.excluded || !messages.isEmpty) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    if m.excluded {
                        TextField(L("Reason for excluding (exported) *", "排除原因（会导出）*"), text: row.exclusionReason)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 460)
                    }
                    ForEach(messages, id: \.self) { text in
                        Label(text, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .gridCellColumns(9)
            }
        }
    }

    @ViewBuilder
    private func noMouseCell(_ s: ChamberSummary?) -> some View {
        if let s {
            HStack(spacing: 3) {
                if s.noMousePercent > 10 {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Text(String(format: "%.0f %%", s.noMousePercent)).monospacedDigit()
            }
            .help(s.noMousePercent > 10
                  ? L("More than 10 % of frames had no segmented mouse (climbing, out of view). Review this animal and exclude it if needed.",
                      "超过 10% 的帧未分割出小鼠（爬尾、出画）。请复核这只小鼠，必要时排除。")
                  : L("Frames without a segmented mouse", "未分割出小鼠的帧"))
        } else {
            Text("–")
        }
    }

    @ViewBuilder
    private func groupCell(_ row: Binding<TSTAnimalMapping>, existing: (group: String, sex: String)?) -> some View {
        if let existing {
            Label(existing.group.isEmpty ? L("No group", "无分组") : existing.group, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
                .help(L("This animal already has sessions in this task; its group is kept.", "该小鼠在此任务中已有实验，沿用其分组。"))
        } else {
            HStack(spacing: 2) {
                TextField(L("e.g. WT", "如 WT"), text: row.group)
                    .textFieldStyle(.roundedBorder)
                if !knownGroups.isEmpty {
                    Menu {
                        ForEach(knownGroups, id: \.self) { g in
                            Button(g) { row.wrappedValue.group = g }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("Groups already used in this task", "此任务中已有的分组"))
                }
            }
            .frame(width: 150)
        }
    }

    @ViewBuilder
    private func sexCell(_ row: Binding<TSTAnimalMapping>, existing: (group: String, sex: String)?) -> some View {
        if let existing {
            Text(sexTitle(existing.sex))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .help(L("This animal already has sessions in this task; its sex is kept.", "该小鼠在此任务中已有实验，沿用其性别。"))
        } else {
            Picker("", selection: row.sex) {
                Text("—").tag("")
                Text(L("Male", "雄")).tag("M")
                Text(L("Female", "雌")).tag("F")
            }
            .labelsHidden()
            .frame(width: 80)
        }
    }

    private func sexTitle(_ s: String) -> String {
        switch s {
        case "M": return L("Male", "雄")
        case "F": return L("Female", "雌")
        case "": return "—"
        default: return s
        }
    }

    // MARK: Rows: preparation, numbering, validation

    // MARK: Re-analysis of a saved recording

    /// Sessions currently linked to the recording being analysed again (fresh from the store).
    private var replacedSessions: [VideoRecord] {
        guard let old = replacing else { return [] }
        return (project?.videos ?? []).filter { $0.tstChamber?.recordingID == old.id }
    }

    private var replacedIDs: Set<UUID> { Set(replacedSessions.map(\.id)) }

    /// The row of a chamber as it is saved now: its session's animal, group, sex, number and exclusion.
    /// A chamber that was analysed but not saved stays unticked. nil = a chamber analysed for the first time.
    private func savedRow(_ chamber: Int) -> TSTAnimalMapping? {
        guard let old = replacing else { return nil }
        var m = old.mappings.first { $0.chamber == chamber } ?? TSTAnimalMapping(chamber: chamber)
        if let v = replacedSessions.first(where: { $0.tstChamber?.chamber == chamber }) {
            m.animalID = v.animalID
            m.group = v.groupKey
            m.sex = v.sex ?? ""
            m.sessionDate = v.sessionDate
            m.sessionNumber = v.sessionNumber ?? 1
            m.excluded = v.isExcluded
            m.exclusionReason = v.exclusionReason ?? ""
            m.skipped = nil
            return m
        }
        guard old.mappings.contains(where: { $0.chamber == chamber }) else { return nil }
        m.skipped = true
        return m
    }

    /// Saved sessions that will be removed: their chamber is not saved any more.
    private var sessionsToRemove: [VideoRecord] {
        let kept = Set(savableRows.map(\.chamber))
        return replacedSessions.filter { !kept.contains($0.tstChamber?.chamber ?? -1) }
    }

    private var knownGroups: [String] {
        Array((project?.groups(ofTask: experiment.id) ?? []).filter { !$0.isEmpty }.prefix(12))
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func animalLabel(_ chamber: Int) -> String {
        guard let m = rows.first(where: { $0.chamber == chamber }), !m.isSkipped else { return "" }
        return trimmed(m.animalID)
    }

    private func existingAttributes(_ m: TSTAnimalMapping) -> (group: String, sex: String)? {
        let key = trimmed(m.animalID)
        guard !key.isEmpty else { return nil }
        if replacing != nil { return project?.animalAttributes(task: experiment.id, animal: key, ignoring: replacedIDs) }
        return project?.animalAttributes(task: experiment.id, animal: key)
    }

    /// One row per analysed chamber. What was typed is kept when the user goes back and re-analyses.
    private func prepareRows() {
        guard let result = model.result else { return }
        if !dateReady { initDate() }
        let chambers = result.summaries.filter(\.analysed).map(\.chamber)
        guard rows.map(\.chamber) != chambers else { return }
        var previous: [Int: TSTAnimalMapping] = [:]
        for r in rows { previous[r.chamber] = r }
        rows = chambers.map { c in
            if let old = previous[c] { return old }
            if let saved = savedRow(c) {
                editedSessions.insert(c)   // keep the saved session number
                return saved
            }
            var m = TSTAnimalMapping(chamber: c)
            m.group = presetGroup ?? ""
            m.sessionNumber = 1
            return m
        }
        renumber()
    }

    private func initDate() {
        dateReady = true
        if replacing != nil, let text = replacedSessions.compactMap(\.sessionDate).first, let d = SessionDate.date(text) {
            recordingDate = d
            dateNote = ""
            return
        }
        let stem = (model.videoName as NSString).deletingPathExtension
        if let text = SessionDate.fromFileName(stem), let d = SessionDate.date(text) {
            recordingDate = d
            dateNote = ""
        } else if let url = model.info?.url,
                  !url.path.hasPrefix(FileManager.default.temporaryDirectory.path),
                  let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate {
            recordingDate = created
            dateNote = L("Date taken from the file's creation date; check it.", "日期取自文件创建日期，请核对。")
        } else {
            recordingDate = Date()
            dateNote = L("No date in the file name — set the recording date.", "文件名中没有日期，请设置实验日期。")
        }
    }

    /// Default session numbers: the next free number of each animal in this task.
    private func renumber() {
        var taken: [String: [Int]] = [:]
        for i in rows.indices where !rows[i].isSkipped {
            let key = trimmed(rows[i].animalID)
            guard !key.isEmpty else { continue }
            if !editedSessions.contains(rows[i].chamber) {
                let next = (replacing != nil
                            ? project?.nextSessionNumber(task: experiment.id, animal: key, alsoTaken: taken[key] ?? [], ignoring: replacedIDs)
                            : project?.nextSessionNumber(task: experiment.id, animal: key, alsoTaken: taken[key] ?? [])) ?? 1
                if rows[i].sessionNumber != next { rows[i].sessionNumber = next }
            }
            taken[key, default: []].append(rows[i].sessionNumber ?? 1)
        }
    }

    private func applyGroupToAll() {
        let g = trimmed(groupForAll)
        for i in rows.indices where existingAttributes(rows[i]) == nil { rows[i].group = g }
    }

    /// Conflicts shown in red under a row (missing values are summarised in the footer instead).
    private func rowMessages(_ m: TSTAnimalMapping) -> [String] {
        guard !m.isSkipped else { return [] }
        let animal = trimmed(m.animalID)
        guard !animal.isEmpty else { return [] }
        var out: [String] = []
        if let other = rows.first(where: { $0.chamber != m.chamber && !$0.isSkipped && trimmed($0.animalID) == animal }) {
            out.append(String(format: L("Chamber %d has the same animal ID — one mouse cannot hang in two chambers.",
                                        "第 %d 格的小鼠编号相同——同一只小鼠不能同时在两个格子里。"), other.chamber))
        }
        if let n = m.sessionNumber,
           let conflict = project?.sessionConflict(task: experiment.id, animal: animal, number: n, ignoring: replacedIDs) {
            out.append(String(format: L("%@ already has session #%d in this task (%@).", "%@ 在此任务中已有第 %d 次实验（%@）。"),
                              animal, n, conflict.sessionTitle))
        }
        return out
    }

    private var savableRows: [TSTAnimalMapping] { rows.filter { !$0.isSkipped } }
    private var missingIDs: [Int] { savableRows.filter { trimmed($0.animalID).isEmpty }.map(\.chamber) }
    private var missingReasons: [Int] {
        savableRows.filter { $0.excluded && trimmed($0.exclusionReason).isEmpty }.map(\.chamber)
    }
    private var hasConflicts: Bool { savableRows.contains { !rowMessages($0).isEmpty } }

    private var readyToSave: Bool {
        model.resultMatchesSetup && !savableRows.isEmpty && missingIDs.isEmpty && missingReasons.isEmpty && !hasConflicts
    }

    private var readinessText: String {
        if savableRows.isEmpty { return L("Tick at least one chamber to save.", "请至少勾选一个要保存的格子。") }
        if !missingIDs.isEmpty {
            return String(format: L("Enter the animal ID for chamber %@.", "请填写第 %@ 格的小鼠编号。"), TSTFormat.list(missingIDs))
        }
        if !missingReasons.isEmpty {
            return String(format: L("Enter the exclusion reason for chamber %@.", "请填写第 %@ 格的排除原因。"), TSTFormat.list(missingReasons))
        }
        if hasConflicts { return L("Fix the rows marked in red.", "请先修正标红的行。") }
        if replacing != nil {
            let removed = sessionsToRemove.count
            let updated = savableRows.count
            let text = String(format: L("%d sessions will be updated with these results.", "将用这些结果更新 %d 次实验。"), updated)
            if removed == 0 { return text }
            return text + " " + String(format: L("%d saved sessions will be removed (chamber not saved any more).",
                                                 "%d 次已保存的实验将被删除（该格不再保存）。"), removed)
        }
        return String(format: L("%d sessions will be added to “%@”.", "将向“%2$@”添加 %1$d 次实验。"),
                      savableRows.count, experiment.displayTitle)
    }

    private var saveTitle: String {
        let n = savableRows.count
        if replacing != nil { return L("Update sessions", "更新实验") }
        return n == 1 ? L("Save 1 session", "保存 1 次实验") : String(format: L("Save %d sessions", "保存 %d 次实验"), n)
    }

    private func save() {
        guard readyToSave, !saving else { return }
        let date = SessionDate.string(recordingDate)
        var mappings = rows
        for i in mappings.indices {
            mappings[i].animalID = trimmed(mappings[i].animalID)
            mappings[i].group = trimmed(mappings[i].group)
            mappings[i].exclusionReason = trimmed(mappings[i].exclusionReason)
            mappings[i].sessionDate = date
            if mappings[i].isSkipped || !mappings[i].excluded {
                mappings[i].excluded = false
                mappings[i].exclusionReason = ""
            }
        }
        saving = true
        Task { @MainActor in
            do {
                let archive = try await TSTTaskArchive.save(task: experiment.id, model: model, mappings: mappings)
                do {
                    // Register as normal session records only after the archive is durable; roll the archive
                    // back if the workspace rejects the registration.
                    let ids: [UUID]
                    if let old = replacing {
                        ids = try store.replaceTSTRecording(old: old, with: archive)
                        TSTTaskArchive.remove(old)   // its sessions now point at the new archive
                    } else {
                        ids = try store.registerTSTRecording(archive)
                    }
                    saving = false
                    onSaved(ids)
                    dismiss()
                } catch {
                    TSTTaskArchive.remove(archive)
                    throw error
                }
            } catch {
                saving = false
                saveError = error.localizedDescription
            }
        }
    }
}

// MARK: - TST steps inside the regular session flow

/// The TST-specific setup, scores and QC are displayed WITHIN the existing guided session flow.
/// Dates, sessions, animal grouping, exclusion and exports remain the standard RodentStudio path.
struct TSTSessionStepView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let video: VideoRecord
    let step: WorkflowStep
    var onAddRecording: () -> Void
    /// Opens the saved recording again (chambers, start, threshold …) and updates its sessions on saving.
    var onReanalyse: () -> Void = {}

    @State private var record: TSTStoredRecording?
    @State private var loadedID: UUID?
    @State private var notes = ""
    @State private var askExclusion = false
    @State private var exclusionDraft = ""

    /// Fresh copy from the store (the review and exclusion change while this page is open).
    private var current: VideoRecord { store.video(video.id) ?? video }
    private var reference: TSTChamberReference? { video.tstChamber }

    private var summary: ChamberSummary? {
        guard let reference else { return nil }
        return record?.summaries.first { $0.chamber == reference.chamber }
    }

    private var trace: ChamberTrace? {
        guard let reference, let traces = record?.traces,
              reference.chamber >= 1, reference.chamber <= traces.count else { return nil }
        return traces[reference.chamber - 1].chartTrace
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let r = record, let s = summary, let reference {
                    header(r, reference)
                    switch step {
                    case .calibrate:
                        setupCard(r, reference)
                    case .run:
                        scoresCard(s, r)
                        chartCards(s, r)
                    default:
                        reviewCard(s, r)
                        scoresCard(s, r)
                    }
                } else if loadedID == video.id {
                    ContentUnavailableView(L("TST analysis not found", "未找到 TST 分析结果"),
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(L("The saved analysis of this recording could not be read. It may have been moved or deleted from the app's data folder.",
                                                               "无法读取这段录像保存的分析结果，可能已被移动，或已从 App 的数据文件夹中删除。")))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(18)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear(perform: load)
        .onChange(of: video.id) { old, _ in
            commitNotes(old)
            load()
        }
        .onDisappear { commitNotes(video.id) }
        // Notes are saved shortly after typing stops (and when leaving the page).
        .task(id: notes) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            commitNotes(video.id)
        }
        .alert(L("Exclude this session from group summaries?", "将该次实验排除出组间汇总？"), isPresented: $askExclusion) {
            TextField(L("Reason (exported)", "原因（会导出）"), text: $exclusionDraft)
            Button(L("Exclude", "排除")) {
                store.setExcluded(video.id, excluded: true, reason: exclusionDraft)
            }
            .disabled(exclusionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(L("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(L("Its own results are kept; it is left out of the animal means, group statistics and comparisons.",
                   "它自己的结果仍保留；只是不进入小鼠均值、组统计和组间比较。"))
        }
    }

    private func load() {
        defer { loadedID = video.id }
        notes = current.currentReview?.notes ?? ""
        guard let reference, let task = video.experimentID else { record = nil; return }
        record = TSTTaskArchive.load(task, record: reference.recordingID)
    }

    private func commitNotes(_ id: UUID) {
        guard loadedID == id, let v = store.video(id), v.runState == .complete else { return }
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (v.currentReview?.notes ?? "") != text else { return }
        store.updateReview(id, unit: "chamber") { $0.notes = text }
    }

    private func setVerdict(_ v: ReviewVerdict) {
        commitNotes(video.id)
        store.updateReview(video.id, unit: "chamber") { s in
            s.verdict = v
            s.reviewedAt = v == .unreviewed ? nil : Date()
        }
    }

    private func verdictTitle(_ v: ReviewVerdict) -> String {
        switch v {
        case .unreviewed: return L("Not checked", "未复核")
        case .passed: return L("Scoring looks right", "评分无误")
        case .issues: return L("Problems found", "存在问题")
        }
    }

    private func siblingSessions(_ ref: TSTChamberReference) -> [VideoRecord] {
        (store.selectedProject?.videos ?? [])
            .filter { $0.tstChamber?.recordingID == ref.recordingID }
            .sorted { ($0.tstChamber?.chamber ?? 0) < ($1.tstChamber?.chamber ?? 0) }
    }

    // MARK: Cards

    private func header(_ r: TSTStoredRecording, _ ref: TSTChamberReference) -> some View {
        let v = current
        return VStack(alignment: .leading, spacing: 4) {
            Text(String(format: L("%@ · chamber %d of %d", "%@ · 第 %d 格（共 %d 格）"), v.displayName, ref.chamber, r.summaries.count))
                .font(.title3.bold())
            Text([v.sessionTitle, v.groupKey.isEmpty ? L("no group", "无分组") : v.groupKey, r.videoName].joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
            if v.isExcluded {
                let reason = v.exclusionReason ?? ""
                Label(L("Excluded from group summaries", "已排除出组间汇总") + (reason.isEmpty ? "" : L(": ", "：") + reason),
                      systemImage: "minus.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func setupCard(_ r: TSTStoredRecording, _ ref: TSTChamberReference) -> some View {
        FigureCard {
            FigureCardHeader(L("Set once for the whole recording", "整段录像统一设定"), symbol: "rectangle.split.3x1",
                             subtitle: L("Chambers, key frame and the analysed band were set when the multi-chamber recording was analysed, and are shared by every animal in it. To change any of them, or the threshold, open the recording again — its sessions are updated when you save.",
                                         "格子、关键帧和分析带已在分析多格录像时统一设定，录像中的所有小鼠共用。如需修改它们或阈值，请重新打开这段录像——保存时会更新它的各次实验。"))
            VStack(alignment: .leading, spacing: 6) {
                FigureInfoRow(key: L("Recording", "录像"), value: r.videoName)
                FigureInfoRow(key: L("Chamber", "格子"),
                              value: String(format: L("%d of %d (left → right)", "第 %d 格，共 %d 格（从左到右）"), ref.chamber, r.summaries.count))
                FigureInfoRow(key: L("Key frame (start)", "关键帧（起点）"), value: TSTFormat.seconds(r.keyFrameTime))
                FigureInfoRow(key: L("Analysed part of the video", "视频中的分析区间"),
                              value: TSTFormat.seconds(r.settings.startSec) + " – " + TSTFormat.seconds(r.settings.startSec + r.settings.durationSec))
                FigureInfoRow(key: L("Measure", "运动指标"), value: TSTMetricTitle.title(r.settings.metric))
                FigureInfoRow(key: L("Immobility threshold", "不动阈值"), value: String(format: "%.2f %%", r.settings.immobilityThreshold))
                FigureInfoRow(key: L("Minimum bout", "最短不动片段"), value: String(format: L("%.1f s", "%.1f 秒"), r.settings.minBoutSec))
                FigureInfoRow(key: L("Sampling", "采样"), value: String(format: "%.1f fps", r.fps))
                FigureInfoRow(key: L("Detector", "检测器"), value: r.detector)
                FigureInfoRow(key: L("Mouse outline", "小鼠轮廓"),
                              value: r.settings.useRefinedOutline ? L("Refined", "精细轮廓") : L("Original", "原始轮廓"))
            }
            let siblings = siblingSessions(ref)
            if siblings.count > 1 {
                Divider()
                Text(L("Animals in this recording", "这段录像中的小鼠")).font(.subheadline.weight(.semibold))
                ForEach(siblings, id: \.id) { v in
                    FigureInfoRow(key: String(format: L("Chamber %d", "第 %d 格"), v.tstChamber?.chamber ?? 0),
                                  value: v.displayName + (v.id == video.id ? L(" (this session)", "（本次）") : ""))
                }
            }
            HStack(spacing: 10) {
                Button(L("Adjust settings and analyse again…", "调整参数并重新分析…"), systemImage: "slider.horizontal.3") { onReanalyse() }
                    .buttonStyle(.borderedProminent)
                    .help(L("Opens this recording with its chambers, start and settings. Saving updates every session of the recording.",
                            "用原来的格子、起点和参数打开这段录像。保存时更新这段录像的所有实验。"))
                if let url = TSTTaskArchive.sourceURL(r) {
                    Button(L("Open original recording", "打开原始录像"), systemImage: "play.rectangle") { NSWorkspace.shared.open(url) }
                }
                Spacer(minLength: 0)
                Button(L("Analyse another recording…", "分析另一段录像…"), systemImage: "plus") { onAddRecording() }
            }
        }
    }

    private func scoresCard(_ s: ChamberSummary, _ r: TSTStoredRecording) -> some View {
        FigureCard {
            FigureCardHeader(L("Scores of this mouse", "这只小鼠的评分"), symbol: "figure.stand",
                             subtitle: L("Computed once for the shared recording. The same values appear on the task, group and animal pages and in the exports.",
                                         "由共享录像统一计算。任务、分组、小鼠页面及导出文件使用相同数值。"))
            TSTSessionMetricsGrid(summary: s, settings: r.settings)
            if s.noMousePercent > 10 {
                Label(L("More than 10 % of frames had no segmented mouse (climbing, out of view). Check this chamber in the original recording.",
                        "超过 10% 的帧未分割出小鼠（爬尾、出画）。请在原始录像中检查这个格子。"),
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("Automatic TST scoring has not been validated against blinded manual scoring.", "TST 自动评分尚未经过盲法人工评分验证。"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func chartCards(_ s: ChamberSummary, _ r: TSTStoredRecording) -> some View {
        if let trace {
            FigureCard {
                FigureCardHeader(L("Motion and immobility", "运动曲线与不动片段"), symbol: "waveform.path.ecg",
                                 subtitle: L("Shaded = scored immobility; red dashed line = threshold.", "阴影为判定的不动片段；红色虚线为阈值。"))
                TSTMotionChart(trace: trace, threshold: r.settings.immobilityThreshold,
                               offset: s.onsetSec ?? 0, marks: s.onsetSec == nil ? [] : TSTWindowMarks.marks(r.settings))
                    .frame(height: 240)
            }
        }
        if !s.perMinuteImmobileSec.isEmpty {
            FigureCard {
                FigureCardHeader(L("Immobility per minute", "每分钟不动时间"), symbol: "chart.bar")
                Chart(Array(s.perMinuteImmobileSec.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Minute", "\(item.offset + 1)"), y: .value("Immobile (s)", item.element))
                        .foregroundStyle(Color.orange)
                }
                .chartYScale(domain: 0...60)
                .chartXAxisLabel(L("Minute", "分钟"))
                .chartYAxisLabel(L("Immobile (s)", "不动（秒）"))
                .frame(height: 180)
            }
        }
        HStack(alignment: .center, spacing: 10) {
            Text(r.hasMeasures == true
                 ? L("Threshold, minimum bout and windows can be changed at once; chambers or the start need a new analysis. All sessions of this recording are updated when you save.",
                     "阈值、最短不动片段和时间窗可立即修改；改格子或起点需要重新分析。保存时更新这段录像的所有实验。")
                 : L("Changing any setting re-analyses the recording with its saved chambers and start. All sessions of this recording are updated when you save.",
                     "修改任何参数都会用保存的格子和起点重新分析这段录像。保存时更新这段录像的所有实验。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L("Adjust settings and analyse again…", "调整参数并重新分析…"), systemImage: "slider.horizontal.3") { onReanalyse() }
        }
    }

    private func reviewCard(_ s: ChamberSummary, _ r: TSTStoredRecording) -> some View {
        let v = current
        return FigureCard {
            FigureCardHeader(L("Check this animal", "复核这只小鼠"), symbol: "checkmark.seal",
                             subtitle: L("Watch this chamber in the original recording, then record your decision. It is saved immediately and exported with the session.",
                                         "在原始录像中查看这个格子，然后记录结论。结论会立即保存，并随该次实验导出。"))
            HStack(spacing: 10) {
                if let url = TSTTaskArchive.sourceURL(r) {
                    Button(L("Open original recording", "打开原始录像"), systemImage: "play.rectangle") { NSWorkspace.shared.open(url) }
                }
                Text(String(format: L("Chamber %d · the analysis starts at %@ in the video", "第 %d 格 · 分析从视频的 %@ 开始"),
                            s.chamber, TSTFormat.seconds(r.settings.startSec)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(L("Adjust settings and analyse again…", "调整参数并重新分析…"), systemImage: "slider.horizontal.3") { onReanalyse() }
                    .help(L("Scoring wrong? Open the recording with its chambers, start and settings, fix them and update every session of it.",
                            "评分不对？用原来的格子、起点和参数打开这段录像，修改后更新它的所有实验。"))
            }
            Picker(L("Result", "结论"), selection: Binding(get: { current.reviewVerdict }, set: { setVerdict($0) })) {
                ForEach(ReviewVerdict.allCases, id: \.self) { verdict in
                    Label(verdictTitle(verdict), systemImage: verdict.symbol).tag(verdict)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            TextField(L("Notes (saved with the session and exported)", "备注（随该次实验保存并导出）"), text: $notes)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitNotes(video.id) }
            if let date = v.currentReview?.reviewedAt {
                Text(String(format: L("Recorded %@", "记录于 %@"), date.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 10) {
                if v.isExcluded {
                    let reason = v.exclusionReason ?? ""
                    Label(L("Excluded from group summaries", "已排除出组间汇总") + (reason.isEmpty ? "" : L(": ", "：") + reason),
                          systemImage: "minus.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(L("Include again", "重新纳入")) { store.setExcluded(video.id, excluded: false, reason: "") }
                } else {
                    Text(L("Something wrong with this animal (climbing, fell, wrong chamber)?", "这只小鼠有问题（爬尾、掉落、格子对错）？"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Exclude from group summaries…", "排除出组间汇总…")) {
                        exclusionDraft = s.noMousePercent > 10 ? L("Many frames without a segmented mouse", "大量帧未分割出小鼠") : ""
                        askExclusion = true
                    }
                }
            }
        }
    }
}

/// Headline measures of one chamber as tiles (standard windows from this mouse's suspension).
private struct TSTSessionMetricsGrid: View {
    let summary: ChamberSummary
    let settings: AnalysisSettings

    var body: some View {
        let test = summary.testLengthSec ?? settings.standardTestSec
        let primaryStart = summary.primaryStartSec ?? max(0, test - settings.lastWindowSec)
        let primary = TSTSessionMetrics.minutes(primaryStart, test)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading)], alignment: .leading, spacing: 10) {
            tile(String(format: L("★ Immobility, min %@", "★ 不动（第 %@ 分）"), primary),
                 seconds(summary.primaryImmobileSec ?? summary.immobileLastWindowSec), primary: true)
            tile(String(format: L("Immobile %%, min %@", "不动占比（第 %@ 分）"), primary),
                 summary.primaryImmobilePercent.map { String(format: "%.1f %%", $0) } ?? "—")
            tile(String(format: L("Immobility, min %@", "不动（第 %@ 分）"), TSTSessionMetrics.minutes(0, primaryStart)),
                 summary.earlyImmobileSec.map { seconds($0) } ?? "—")
            tile(String(format: L("Immobility, min %@", "不动（第 %@ 分）"), TSTSessionMetrics.minutes(0, test)),
                 summary.testImmobileSec.map { seconds($0) } ?? "—")
            tile(L("Latency to first bout", "首次不动潜伏期"), summary.latencySec.map { seconds($0) } ?? "—")
            tile(L("Bouts · longest", "不动次数 · 最长"), "\(summary.bouts) · " + seconds(summary.longestBoutSec))
            tile(L("Mobility intensity", "运动强度"), summary.mobilityIntensity.map { String(format: L("%.1f %% body", "%.1f%% 鼠体"), $0) } ?? "—")
            tile(L("Immobility, whole recording", "不动（全程）"), seconds(summary.immobileTotalSec))
            tile(L("No mouse", "无小鼠"), String(format: "%.1f %%", summary.noMousePercent), warn: summary.noMousePercent > 10)
        }
    }

    private func seconds(_ v: Double) -> String { String(format: L("%.1f s", "%.1f 秒"), v) }

    private func tile(_ title: String, _ value: String, primary: Bool = false, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(primary ? .title2.weight(.semibold) : .title3.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(warn ? Color.orange : Color.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FigureSurface.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
