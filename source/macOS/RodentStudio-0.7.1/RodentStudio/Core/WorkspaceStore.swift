import Foundation
import AVFoundation

// Native workspace is intentionally separate from desktop 0.2.0's .rodentproj files.
// Legacy files can be inspected read-only from the UI; never overwritten by this app.
enum StudyAssay: String, Codable, CaseIterable, Identifiable {
    case threeChamber = "rodentpose.three_chamber"
    case poseSocialInteraction = "rodentpose.social_interaction"
    case poseDyadicSocial = "rodentpose.dyadic_social"
    case poseHeadDirection = "rodentpose.head_direction"
    case poseSpatialExploration = "rodentpose.spatial_exploration"
    case openField = "rodentpose.open_field"
    case elevatedPlusMaze = "rodentpose.epm"
    case poseLightDarkBox = "rodentpose.light_dark_box"
    case novelObject = "rodentpose.nor"
    case poseBarnesMaze = "rodentpose.barnes_maze"
    case poseYMaze = "rodentpose.y_maze"
    case poseTMazeVte = "rodentpose.t_maze_vte"
    case poseFearConditioning = "rodentpose.fear_conditioning"
    case poseLoomingEscape = "rodentpose.looming_escape"
    case poseRotation = "rodentpose.rotation"
    case poseOnly = "rodentpose.pose_only"
    case cylinder = "rodentlimb.cylinder"
    case tailSuspension = "rodentlimb.tail_suspension"
    case tstMultiChamber = "tstscorer.multi_chamber"
    case gait = "rodentlimb.gait"
    case flowOpenField = "rodentflow.open_field"
    case flowElevatedPlusMaze = "rodentflow.elevated_plus_maze"
    case flowLightDarkBox = "rodentflow.light_dark_box"
    case flowMarbleBurying = "rodentflow.marble_burying"
    case flowSucrosePreference = "rodentflow.sucrose_preference"
    case flowYMaze = "rodentflow.y_maze"
    case flowTMaze = "rodentflow.t_maze"
    case flowNovelObjectRecognition = "rodentflow.novel_object_recognition"
    case flowMorrisWaterMaze = "rodentflow.morris_water_maze"
    case flowBarnesMaze = "rodentflow.barnes_maze"
    case flowFearConditioning = "rodentflow.fear_conditioning"
    case flowBeamWalking = "rodentflow.beam_walking"
    case flowGaitAnalysis = "rodentflow.gait_analysis"
    case flowConditionedPlacePreference = "rodentflow.conditioned_place_preference"
    case flowTwoArmedBandit = "rodentflow.two_armed_bandit"
    case flowCustom = "rodentflow.custom"

    var id: String { rawValue }
    /// English catalog name (stable; used in exports).
    var name: String { DesktopAssayCatalog.lookup(rawValue)?.name ?? rawValue }
    var moduleName: String { DesktopAssayCatalog.lookup(rawValue)?.module ?? "Unknown" }
    var statusLabel: String { DesktopAssayCatalog.lookup(rawValue)?.availability ?? "Unknown" }
    var isLimb: Bool { rawValue.hasPrefix("rodentlimb.") }
    var isDesktopEligible: Bool {
        // Retain old enum cases solely so saved 0.2.0 workspaces can still decode.
        // They are no longer shown as choices or executable desktop assays.
        DesktopAssayCatalog.lookup(rawValue) != nil
    }
    /// Chosen by the app, never by the user in the main workflow (see Advanced for manual model tools).
    var modelRoute: PoseModelKind? {
        if moduleName == "RodentPose" { return .mousePose }
        if isLimb { return .cylinderV2 }
        return nil // RodentFlow uses its original classic-centroid tracker, NOT Core ML.
    }
}

struct NativeExperiment: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var assay: StudyAssay
    var experimentalUnit: String = "animal"
    /// Order, color and inclusion of groups in the group comparison of this task.
    var groupStyles: [String: GroupStyle]?
    /// Tasks with identical names, assays, and notes are grouped into one task.
    /// Optional for compatibility with workspaces saved by RodentStudio 0.6.0 and earlier.
    var notes: String?

    var hasNotes: Bool { !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Localize built-in assay titles, but preserve custom task names verbatim.
    var displayTitle: String { name == assay.name ? assay.displayName : name }
}

/// State of the saved tracking run of a video (stored in the app's own container).
enum VideoRunState: String, Codable {
    case running, complete, partial, failed
}

/// A TST multi-chamber recording is analysed once; each chamber is one independent animal session.
/// Both the archive and the workspace use stable identifiers. Optional for all pre-0.7.1 sessions.
struct TSTChamberReference: Codable, Equatable {
    var recordingID: UUID
    var chamber: Int
}

struct VideoRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var fileName: String
    var bookmark: Data
    var durationSeconds: Double
    /// Upright (displayed) frame size for videos imported by 0.4+; encoded size for older imports.
    var videoWidth: Int = 0
    var videoHeight: Int = 0
    var framesPerSecond: Double = 0
    var importedAt: Date = Date()
    var experimentID: UUID?
    var animalID: String = ""
    var status: String = "Not analysed — model pending"
    // Optional fields ensure workspaces saved by older builds remain decodable.
    var group: String?
    var sex: String?
    var phase: String?
    var day: Int?
    var trial: Int?
    var notes: String?
    var calibration: DesktopCalibration?
    /// Folder of the segmented run, relative to the app's Runs folder.
    var runFolder: String?
    var runState: VideoRunState?
    var runModel: String?
    var runFrames: Int?
    var runFailedFrames: Int?
    var runFinishedAt: Date?
    var runMessage: String?
    /// The reviewer's tracking check of the current run (see VideoReview.swift).
    var review: VideoReviewState?
    /// Recording date of this session, "yyyy-MM-dd" (required for new videos; see SessionModel.swift).
    var sessionDate: String?
    /// 实验次数: the n-th session of this animal in this task (1, 2, 3 …; required for new videos).
    var sessionNumber: Int?
    /// Left out of group comparisons and group summaries (its own results are kept), with the reason.
    var excluded: Bool?
    var exclusionReason: String?
    var tstChamber: TSTChamberReference?

    var displayName: String {
        let id = animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? fileName : id
    }
}

struct NativeProject: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var experiments: [NativeExperiment] = []
    var videos: [VideoRecord] = []
}

struct WorkspaceDocument: Codable {
    var schemaVersion: Int = 1
    var projects: [NativeProject] = []
    var selectedProjectID: UUID?
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var document: WorkspaceDocument
    @Published var notice: String?
    @Published var focusedVideoID: UUID?
    @Published var focusedExperimentID: UUID?

    private let storageURL: URL
    let runsRoot: URL
    private let writer = DispatchQueue(label: "rodentdesktop.workspace-writer", qos: .utility)

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RodentDesktopNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        storageURL = base.appendingPathComponent("workspace.json")
        runsRoot = base.appendingPathComponent("Runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: runsRoot, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: storageURL),
           let loaded = try? JSONDecoder().decode(WorkspaceDocument.self, from: data) {
            document = loaded
        } else {
            document = WorkspaceDocument()
        }
        // A run that was in progress when the app quit keeps its finished segments and can be resumed.
        for p in document.projects.indices {
            for v in document.projects[p].videos.indices where document.projects[p].videos[v].runState == .running {
                document.projects[p].videos[v].runState = .partial
            }
        }
        // One-time, safe consolidation of old duplicate tasks. Never change the user's saved
        // workspace before creating a backup; individual video/run identifiers remain intact.
        var candidate = document
        let merged = TaskMergePolicy.consolidate(document: &candidate)
        if !merged.redirects.isEmpty {
            let backup = base.appendingPathComponent("workspace-before-task-merge-" + UUID().uuidString + ".json")
            do {
                try FileManager.default.copyItem(at: storageURL, to: backup)
                document = candidate
                save()
            } catch {
                notice = L("Could not back up workspace; duplicate tasks were not merged: ",
                           "无法备份工作区，因此没有合并同名任务：") + error.localizedDescription
            }
        }
        if !merged.blocked.isEmpty && notice == nil {
            notice = L("Some tasks with matching name and notes could not merge because their animal/session data conflict. Give them different notes or resolve the duplicate session numbers first.",
                       "部分名称和备注相同的任务存在小鼠／实验次数冲突，未自动合并。请修改为不同备注，或先解决重复的实验次数。")
        }
        if document.selectedProjectID == nil { document.selectedProjectID = document.projects.first?.id }
        if let p = selectedProject {
            focusedExperimentID = p.experiments.last?.id
        }
    }

    var selectedProject: NativeProject? {
        document.projects.first(where: { $0.id == document.selectedProjectID })
    }

    private var selectedIndex: Int? {
        document.projects.firstIndex(where: { $0.id == document.selectedProjectID })
    }

    // MARK: Projects and tasks

    func createProject(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let project = NativeProject(name: name)
        document.projects.append(project)
        document.selectedProjectID = project.id
        focusedExperimentID = nil
        focusedVideoID = nil
        save()
    }

    func renameProject(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = document.projects.firstIndex(where: { $0.id == id }) else { return }
        document.projects[i].name = name
        save()
    }

    func selectProject(_ id: UUID) {
        document.selectedProjectID = id
        focusedExperimentID = selectedProject?.experiments.last?.id
        focusedVideoID = nil
        save()
    }

    /// The workflow never asks for a project first: one is created when needed.
    @discardableResult
    func ensureProject() -> Int {
        if let i = selectedIndex { return i }
        let project = NativeProject(name: L("My study", "我的研究"))
        document.projects.append(project)
        document.selectedProjectID = project.id
        save()
        return document.projects.count - 1
    }

    func createExperiment(name: String, assay: StudyAssay) {
        guard assay.isDesktopEligible else { return }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        let index = ensureProject()
        if let existing = document.projects[index].experiments.first(where: {
            !$0.hasNotes && $0.assay == assay && TaskMergePolicy.sameName($0.name, label)
        }) {
            focusedExperimentID = existing.id
            return
        }
        let new = NativeExperiment(name: label, assay: assay)
        document.projects[index].experiments.append(new)
        focusedExperimentID = new.id
        save()
    }

    /// Selecting an assay uses its shared task with no note.
    @discardableResult
    func selectTask(_ assay: StudyAssay) -> UUID? {
        guard assay.isDesktopEligible else { return nil }
        let index = ensureProject()
        if let existing = document.projects[index].experiments.first(where: {
            !$0.hasNotes && $0.assay == assay && TaskMergePolicy.sameName($0.name, assay.name)
        }) {
            focusedExperimentID = existing.id
            return existing.id
        }
        let new = NativeExperiment(name: assay.name, assay: assay)
        document.projects[index].experiments.append(new)
        focusedExperimentID = new.id
        save()
        return new.id
    }

    /// Reuses a matching annotated task, or creates a distinct task for a different note.
    /// Never create a redundant empty duplicate with the same name, assay and note.
    @discardableResult
    func createSeparateTask(from id: UUID, note rawNote: String) -> UUID? {
        guard let p = selectedIndex,
              let original = document.projects[p].experiments.first(where: { $0.id == id }) else { return nil }
        let note = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return nil }
        if let existing = document.projects[p].experiments.first(where: {
            $0.assay == original.assay && TaskMergePolicy.sameName($0.name, original.name)
                && TaskMergePolicy.sameNotes($0.notes, note)
        }) {
            focusedExperimentID = existing.id
            focusedVideoID = nil
            return existing.id
        }
        var new = NativeExperiment(name: original.name, assay: original.assay)
        new.notes = note
        document.projects[p].experiments.append(new)
        focusedExperimentID = new.id
        focusedVideoID = nil
        save()
        return new.id
    }

    /// Returns the surviving ID when editing a note makes two tasks identical.
    @discardableResult
    func setTaskNotes(_ id: UUID, notes rawNotes: String) -> UUID? {
        guard let p = selectedIndex,
              let e = document.projects[p].experiments.firstIndex(where: { $0.id == id }) else { return nil }
        let note = rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = document
        candidate.projects[p].experiments[e].notes = note.isEmpty ? nil : note
        let outcome = TaskMergePolicy.consolidate(document: &candidate)
        if !outcome.redirects.isEmpty {
            // Back up the exact in-memory state before a manual note edit joins two tasks.
            // The normal workspace writer is asynchronous, so copying workspace.json here
            // would risk backing up an older version of the work in progress.
            let backup = storageURL.deletingLastPathComponent()
                .appendingPathComponent("workspace-before-task-merge-" + UUID().uuidString + ".json")
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(document).write(to: backup, options: .atomic)
            } catch {
                notice = L("Could not back up workspace; tasks were not merged: ",
                           "无法备份工作区，因此没有合并任务：") + error.localizedDescription
                return nil
            }
        }
        document = candidate
        if !outcome.blocked.isEmpty {
            notice = L("Some same-name, same-note tasks cannot merge because their animal/session data conflict.",
                       "部分同名且备注相同的任务存在小鼠／实验次数冲突，未自动合并。")
        }
        if let previous = focusedExperimentID { focusedExperimentID = outcome.redirects[previous] ?? previous }
        let surviving = outcome.redirects[id] ?? id
        save()
        return surviving
    }

    /// Removes a task and its imported sessions from the workspace, without touching source
    /// videos or saved run folders. The view must confirm with the user and stop active jobs first.
    @discardableResult
    func deleteTask(_ id: UUID) -> Int {
        guard let p = selectedIndex,
              document.projects[p].experiments.contains(where: { $0.id == id }) else { return 0 }
        let removedIDs = Set(document.projects[p].videos.filter { $0.experimentID == id }.map(\.id))
        document.projects[p].videos.removeAll { $0.experimentID == id }
        document.projects[p].experiments.removeAll { $0.id == id }
        if let vid = focusedVideoID, removedIDs.contains(vid) { focusedVideoID = nil }
        if focusedExperimentID == id { focusedExperimentID = document.projects[p].experiments.first?.id }
        save()
        return removedIDs.count
    }

    // MARK: Multi-chamber TST → normal animal sessions

    /// Commit every scored chamber as a regular session under Task → Group → Animal → Date / Session #.
    /// Called only after the original shared video and analysis archive are saved durably.
    /// Performs all validation before mutating the workspace; no fake per-chamber video decoding.
    @discardableResult
    func registerTSTRecording(_ record: TSTStoredRecording) throws -> [UUID] {
        guard let p = selectedIndex,
              document.projects[p].experiments.contains(where: { $0.id == record.taskID && $0.assay == .tstMultiChamber }),
              let sourceURL = TSTTaskArchive.sourceURL(record) else { throw TSTIntegrationError.missingSource }
        let project = document.projects[p]
        // Chambers the user chose not to save (empty, failed, selected by mistake) create no session.
        let scored = record.summaries.filter { s in
            s.analysed && !(record.mappings.first(where: { $0.chamber == s.chamber })?.isSkipped ?? false)
        }
        guard !scored.isEmpty else { throw TSTIntegrationError.nothingToSave }
        var seen = Set<String>()
        var seenAnimals = Set<String>()
        for s in scored {
            guard let m = record.mappings.first(where: { $0.chamber == s.chamber }),
                  !m.animalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  SessionDate.isValid(m.sessionDate), (m.sessionNumber ?? 0) > 0
            else { throw TSTIntegrationError.missingInformation(s.chamber) }
            let key = m.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = m.sessionNumber ?? 0
            let duplicate = key + ":" + String(number)
            guard seenAnimals.insert(key).inserted, seen.insert(duplicate).inserted,
                  project.sessionConflict(task: record.taskID, animal: key, number: number, excluding: nil) == nil
            else { throw TSTIntegrationError.sessionConflict(key, number) }
            if m.excluded && m.exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TSTIntegrationError.missingExclusion(s.chamber)
            }
        }
        let bookmark = try sourceURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let w = record.videoWidth ?? 0, h = record.videoHeight ?? 0
        let existingIDs = Set(project.videos.compactMap { $0.tstChamber?.recordingID == record.id ? $0.id : nil })
        guard existingIDs.isEmpty else { throw TSTIntegrationError.alreadyRegistered }
        var added: [VideoRecord] = []
        for s in scored {
            guard let m = record.mappings.first(where: { $0.chamber == s.chamber }) else { continue }
            let animal = m.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            var v = VideoRecord(fileName: record.videoName, bookmark: bookmark,
                                durationSeconds: 0, importedAt: record.savedAt, experimentID: record.taskID,
                                animalID: animal, status: "Analysed")
            Self.fillTSTSession(&v, record: record, chamber: s.chamber, mapping: m,
                                prior: project.animalAttributes(task: record.taskID, animal: animal), keepNotes: nil)
            added.append(v)
        }
        document.projects[p].videos.append(contentsOf: added)
        if let first = added.first { focusedVideoID = first.id }
        focusedExperimentID = record.taskID
        save()
        return added.map(\.id)
    }

    /// Writes one chamber of a TST recording into a session record (new or existing).
    private static func fillTSTSession(_ v: inout VideoRecord, record: TSTStoredRecording, chamber: Int,
                                       mapping m: TSTAnimalMapping, prior: (group: String, sex: String)?, keepNotes: String?) {
        v.fileName = record.videoName
        v.durationSeconds = record.videoDuration ?? (record.settings.startSec + record.settings.durationSec)
        v.videoWidth = record.videoWidth ?? 0
        v.videoHeight = record.videoHeight ?? 0
        v.framesPerSecond = record.videoFPS ?? record.fps
        v.experimentID = record.taskID
        v.animalID = m.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
        v.status = "Analysed"
        v.group = prior?.group ?? (m.group.isEmpty ? nil : m.group)
        v.sex = prior?.sex ?? (m.sex.isEmpty ? nil : m.sex)
        v.sessionDate = m.sessionDate
        v.sessionNumber = m.sessionNumber
        v.tstChamber = TSTChamberReference(recordingID: record.id, chamber: chamber)
        v.runState = .complete
        v.runModel = "TSTScorer6-multi-chamber"
        v.runFinishedAt = record.savedAt
        // Stable run identity for the existing review/QC machinery; source data lives in TST archive.
        v.runFolder = "tst-multi/" + record.id.uuidString + "/chamber-" + String(chamber)
        v.runFrames = Int((record.settings.durationSec * record.fps).rounded())
        // The numbers changed, so the check starts again; the reviewer's notes are carried over.
        var review = VideoReviewState(runFolder: v.runFolder ?? "", unit: "chamber")
        if let keepNotes, !keepNotes.isEmpty { review.notes = keepNotes }
        v.review = review
        v.excluded = m.excluded ? true : nil
        v.exclusionReason = m.excluded ? m.exclusionReason : nil
    }

    /// A saved multi-chamber recording was analysed again. Its sessions are updated IN PLACE (same session
    /// IDs), chambers that are newly saved become new sessions and chambers that are no longer saved lose
    /// their session. Everything is validated before the workspace changes. The caller deletes the old
    /// archive afterwards.
    @discardableResult
    func replaceTSTRecording(old: TSTStoredRecording, with record: TSTStoredRecording) throws -> [UUID] {
        guard let p = selectedIndex,
              document.projects[p].experiments.contains(where: { $0.id == record.taskID && $0.assay == .tstMultiChamber }),
              let sourceURL = TSTTaskArchive.sourceURL(record) else { throw TSTIntegrationError.missingSource }
        let project = document.projects[p]
        let previous = project.videos.filter { $0.tstChamber?.recordingID == old.id }
        let previousIDs = Set(previous.map(\.id))
        var previousByChamber: [Int: VideoRecord] = [:]
        for v in previous { if let c = v.tstChamber?.chamber { previousByChamber[c] = v } }
        let scored = record.summaries.filter { s in
            s.analysed && !(record.mappings.first(where: { $0.chamber == s.chamber })?.isSkipped ?? false)
        }
        guard !scored.isEmpty else { throw TSTIntegrationError.nothingToSave }
        var seenAnimals = Set<String>()
        for s in scored {
            guard let m = record.mappings.first(where: { $0.chamber == s.chamber }),
                  !m.animalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  SessionDate.isValid(m.sessionDate), (m.sessionNumber ?? 0) > 0
            else { throw TSTIntegrationError.missingInformation(s.chamber) }
            let key = m.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = m.sessionNumber ?? 0
            guard seenAnimals.insert(key).inserted,
                  project.sessionConflict(task: record.taskID, animal: key, number: number, ignoring: previousIDs) == nil
            else { throw TSTIntegrationError.sessionConflict(key, number) }
            if m.excluded && m.exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw TSTIntegrationError.missingExclusion(s.chamber)
            }
        }
        guard !project.videos.contains(where: { $0.tstChamber?.recordingID == record.id }) else {
            throw TSTIntegrationError.alreadyRegistered
        }
        let bookmark = try sourceURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let kept = Set(scored.map(\.chamber))
        var videos = project.videos
        videos.removeAll { previousIDs.contains($0.id) && !kept.contains($0.tstChamber?.chamber ?? -1) }
        var ids: [UUID] = []
        for s in scored {
            guard let m = record.mappings.first(where: { $0.chamber == s.chamber }) else { continue }
            let animal = m.animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            let prior = project.animalAttributes(task: record.taskID, animal: animal, ignoring: previousIDs)
            if let old = previousByChamber[s.chamber], let i = videos.firstIndex(where: { $0.id == old.id }) {
                var v = videos[i]
                v.bookmark = bookmark
                Self.fillTSTSession(&v, record: record, chamber: s.chamber, mapping: m, prior: prior,
                                    keepNotes: old.currentReview?.notes)
                videos[i] = v
                ids.append(v.id)
            } else {
                var v = VideoRecord(fileName: record.videoName, bookmark: bookmark,
                                    durationSeconds: 0, importedAt: record.savedAt, experimentID: record.taskID,
                                animalID: animal, status: "Analysed")
                Self.fillTSTSession(&v, record: record, chamber: s.chamber, mapping: m, prior: prior, keepNotes: nil)
                videos.append(v)
                ids.append(v.id)
            }
        }
        document.projects[p].videos = videos
        if let vid = focusedVideoID, !videos.contains(where: { $0.id == vid }) { focusedVideoID = ids.first }
        focusedExperimentID = record.taskID
        save()
        return ids
    }

    enum TSTIntegrationError: LocalizedError {
        case missingSource, missingInformation(Int), sessionConflict(String, Int), missingExclusion(Int), alreadyRegistered, nothingToSave
        var errorDescription: String? {
            switch self {
            case .missingSource:
                return L("The saved copy of the TST video is missing; the sessions cannot be linked.", "TST 录像的保存副本不存在，无法建立实验记录。")
            case .missingInformation(let c):
                return String(format: L("Chamber %d needs an animal ID, a date and a session number.", "第 %d 格需要填写小鼠编号、日期和实验次数。"), c)
            case .sessionConflict(let a, let n):
                return String(format: L("%@ already has session #%d in this task.", "%@ 在此任务中已有第 %d 次实验。"), a, n)
            case .missingExclusion(let c):
                return String(format: L("Chamber %d needs a reason for the exclusion.", "第 %d 格需要填写排除原因。"), c)
            case .alreadyRegistered:
                return L("This TST recording is already linked to sessions of this task.", "该 TST 录像已经关联到此任务的实验记录。")
            case .nothingToSave:
                return L("No chamber is marked to be saved.", "没有勾选任何要保存的格子。")
            }
        }
    }

    // MARK: Videos

    /// Imports videos with the information every session needs (animal, date, session number, group).
    /// Returns the IDs of the new sessions.
    @discardableResult
    func addVideos(_ items: [VideoImportItem], experimentID: UUID) async -> [UUID] {
        let index = ensureProject()
        let projectID = document.projects[index].id
        var added: [UUID] = []
        var failures: [String] = []
        for item in items {
            let url = item.url
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard let track = tracks.first else {
                    failures.append(url.lastPathComponent)
                    continue
                }
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let rate = try await track.load(.nominalFrameRate)
                let upright = CGRect(origin: .zero, size: size).applying(transform)
                let seconds = CMTimeGetSeconds(duration)
                var video = VideoRecord(fileName: url.lastPathComponent,
                                        bookmark: bookmark,
                                        durationSeconds: seconds.isFinite ? max(0, seconds) : 0,
                                        videoWidth: Int(abs(upright.width).rounded()),
                                        videoHeight: Int(abs(upright.height).rounded()),
                                        framesPerSecond: Double(rate),
                                        experimentID: experimentID,
                                        animalID: item.animalID.trimmingCharacters(in: .whitespacesAndNewlines),
                                        status: "Imported")
                let group = item.group.trimmingCharacters(in: .whitespacesAndNewlines)
                video.group = group.isEmpty ? nil : group
                video.sex = item.sex.isEmpty ? nil : item.sex
                video.phase = item.phase.isEmpty ? nil : item.phase
                video.sessionDate = item.sessionDate
                video.sessionNumber = item.sessionNumber
                guard let pi = document.projects.firstIndex(where: { $0.id == projectID }) else { break }
                document.projects[pi].videos.append(video)
                added.append(video.id)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let first = added.first {
            focusedExperimentID = experimentID
            focusedVideoID = first
        }
        if !added.isEmpty { save() }
        if !failures.isEmpty {
            notice = L("Could not import: ", "无法导入：") + failures.joined(separator: "; ")
        }
        return added
    }

    /// Group and sex belong to the animal: they are set on every session of the animal in the task.
    func setAnimalAttributes(task experimentID: UUID, animal key: String, group: String, sex: String) {
        guard let p = selectedIndex else { return }
        let g = group.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        for v in document.projects[p].videos.indices
        where document.projects[p].videos[v].experimentID == experimentID && document.projects[p].videos[v].animalKey == key {
            document.projects[p].videos[v].group = g.isEmpty ? nil : g
            document.projects[p].videos[v].sex = sex.isEmpty ? nil : sex
            changed = true
        }
        if changed { save() }
    }

    /// Renames an animal of a task (every session of it). Renaming to an animal that already exists merges
    /// the sessions into it (they take its group and sex), unless a session number would then be used twice.
    /// Returns the reason when nothing was changed.
    @discardableResult
    func renameAnimal(task experimentID: UUID, from key: String, to rawID: String) -> String? {
        guard let p = selectedIndex else { return nil }
        let newID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newID.isEmpty else { return L("The animal ID cannot be empty.", "小鼠编号不能为空。") }
        if newID == key { return nil }
        let project = document.projects[p]
        let moving = project.sessions(ofTask: experimentID, animal: key)
        let target = project.sessions(ofTask: experimentID, animal: newID)
        let used = Set(target.compactMap(\.sessionNumber))
        let clashes = moving.compactMap(\.sessionNumber).filter { used.contains($0) }
        if !clashes.isEmpty {
            return String(format: L("%@ already has session number(s) %@ in this task. Change the session numbers first.",
                                    "%@ 在此任务中已有第 %@ 次实验。请先修改实验次数。"),
                          newID, clashes.sorted().map { String($0) }.joined(separator: ", "))
        }
        let attributes = target.first.map { ($0.groupKey, $0.sex ?? "") }
        for v in document.projects[p].videos.indices
        where document.projects[p].videos[v].experimentID == experimentID && document.projects[p].videos[v].animalKey == key {
            document.projects[p].videos[v].animalID = newID
            if let attributes {
                document.projects[p].videos[v].group = attributes.0.isEmpty ? nil : attributes.0
                document.projects[p].videos[v].sex = attributes.1.isEmpty ? nil : attributes.1
            }
        }
        save()
        return nil
    }

    /// Renames a group of a task (all its animals); its style in the group comparison is kept.
    func renameGroup(task experimentID: UUID, from old: String, to raw: String) {
        guard let p = selectedIndex else { return }
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != old else { return }
        for v in document.projects[p].videos.indices
        where document.projects[p].videos[v].experimentID == experimentID && document.projects[p].videos[v].groupKey == old {
            document.projects[p].videos[v].group = new.isEmpty ? nil : new
        }
        if let e = document.projects[p].experiments.firstIndex(where: { $0.id == experimentID }),
           var styles = document.projects[p].experiments[e].groupStyles, let style = styles[old] {
            styles[old] = nil
            if styles[new] == nil { styles[new] = style }
            document.projects[p].experiments[e].groupStyles = styles
        }
        save()
    }

    /// Leaves a session out of (or back into) group comparisons and summaries.
    func setExcluded(_ videoID: UUID, excluded: Bool, reason: String) {
        updateVideo(videoID) { v in
            v.excluded = excluded ? true : nil
            let r = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            v.exclusionReason = excluded && !r.isEmpty ? r : nil
        }
    }

    func updateGroupStyles(_ experimentID: UUID, _ styles: [String: GroupStyle]) {
        guard let p = selectedIndex, let e = document.projects[p].experiments.firstIndex(where: { $0.id == experimentID }) else { return }
        if document.projects[p].experiments[e].groupStyles == styles { return }
        document.projects[p].experiments[e].groupStyles = styles
        save()
    }

    func experiment(_ id: UUID?) -> NativeExperiment? {
        guard let id else { return nil }
        return selectedProject?.experiments.first { $0.id == id }
    }

    func video(_ id: UUID?) -> VideoRecord? {
        guard let id else { return nil }
        return selectedProject?.videos.first { $0.id == id }
    }

    func updateVideo(_ id: UUID, _ change: (inout VideoRecord) -> Void) {
        guard let p = selectedIndex, let v = document.projects[p].videos.firstIndex(where: { $0.id == id }) else { return }
        change(&document.projects[p].videos[v])
        save()
    }

    /// Removes a video from the project. The video file itself is never touched.
    func removeVideo(_ id: UUID) {
        guard let p = selectedIndex else { return }
        document.projects[p].videos.removeAll { $0.id == id }
        if focusedVideoID == id { focusedVideoID = nil }
        save()
    }

    func resolveURL(_ video: VideoRecord) -> URL? {
        if let reference = video.tstChamber, let task = video.experimentID,
           let record = TSTTaskArchive.load(task, record: reference.recordingID) {
            return TSTTaskArchive.sourceURL(record)
        }
        var isStale = false
        return try? URL(resolvingBookmarkData: video.bookmark, options: .withSecurityScope,
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    // MARK: Setup

    func saveSetup(videoID: UUID, experimentID: UUID, setup: DesktopCalibration) {
        var s = setup
        s.syncSummary()
        // Focus is left to the caller: a pending save of the previous animal must not move the selection.
        updateVideo(videoID) { v in
            v.experimentID = experimentID
            v.calibration = s
        }
    }

    /// RodentLimb "Save and use for all videos of this assay": only valid when the camera did not move.
    @discardableResult
    func applySetupToTask(_ setup: DesktopCalibration, from videoID: UUID, experimentID: UUID) -> Int {
        guard let p = selectedIndex else { return 0 }
        let source = document.projects[p].videos.first { $0.id == videoID }?.displayName ?? ""
        var copy = setup
        copy.syncSummary()
        copy.copiedFrom = source
        if copy.limb != nil { copy.limb?.calibration.copiedFrom = source }
        var n = 0
        for v in document.projects[p].videos.indices
        where document.projects[p].videos[v].experimentID == experimentID && document.projects[p].videos[v].id != videoID {
            document.projects[p].videos[v].calibration = copy
            n += 1
        }
        save()
        return n
    }

    /// Backwards-compatible setter used by 0.3.x views.
    func saveVideoSetup(videoID: UUID, experimentID: UUID, animalID: String,
                        group: String, calibration: DesktopCalibration) {
        updateVideo(videoID) { v in
            v.experimentID = experimentID
            v.animalID = animalID.trimmingCharacters(in: .whitespacesAndNewlines)
            v.group = group.trimmingCharacters(in: .whitespacesAndNewlines)
            v.calibration = calibration
        }
        focusedVideoID = videoID
        focusedExperimentID = experimentID
    }

    // MARK: Runs (segmented, saved in the app container)

    func runFolderURL(_ video: VideoRecord) -> URL? {
        guard let folder = video.runFolder, !folder.isEmpty else { return nil }
        return runsRoot.appendingPathComponent(folder, isDirectory: true)
    }

    /// A partial run of the same model is resumed; otherwise a new empty folder is used.
    func destinationForRun(_ video: VideoRecord, model: PoseModelKind, fresh: Bool) -> (URL, String) {
        // Only a paused run is resumed; a failed run starts again in a new folder (the old one is kept).
        if !fresh, video.runState == .partial, video.runModel == model.rawValue,
           let folder = video.runFolder, let url = runFolderURL(video) {
            return (url, folder)
        }
        let stamp = Self.stampFormatter.string(from: Date())
        let relative = "\(video.id.uuidString)/\(model.rawValue)-\(stamp)"
        return (runsRoot.appendingPathComponent(relative, isDirectory: true), relative)
    }

    func markRunStarted(_ videoID: UUID, folder: String, model: PoseModelKind) {
        updateVideo(videoID) { v in
            v.runFolder = folder
            v.runState = .running
            v.runModel = model.rawValue
            v.runMessage = nil
            v.status = "Tracking"
        }
    }

    /// Model identifier recorded for RodentFlow runs (classic centroid tracker, no neural network).
    static let flowRunModel = "RodentFlow_classic_centroid_1.3"

    /// A paused RodentFlow run resumes in its own folder (the tracker checkpoints there); otherwise a new folder.
    func destinationForFlowRun(_ video: VideoRecord, fresh: Bool) -> (URL, String) {
        if !fresh, video.runState == .partial, video.runModel == Self.flowRunModel,
           let folder = video.runFolder, let url = runFolderURL(video) {
            return (url, folder)
        }
        let stamp = Self.stampFormatter.string(from: Date())
        let relative = "\(video.id.uuidString)/flow-centroid-\(stamp)"
        return (runsRoot.appendingPathComponent(relative, isDirectory: true), relative)
    }

    func startFlowRun(_ videoID: UUID, folder: String) {
        updateVideo(videoID) { v in
            v.runFolder = folder
            v.runState = .running
            v.runModel = Self.flowRunModel
            v.runMessage = nil
            v.status = "Classic centroid tracking"
        }
    }

    func markRunFinished(_ videoID: UUID, frames: Int, failedFrames: Int) {
        updateVideo(videoID) { v in
            v.runState = .complete
            v.runFrames = frames
            v.runFailedFrames = failedFrames
            v.runFinishedAt = Date()
            v.runMessage = nil
            v.status = "Tracked"
        }
    }

    func markRunStopped(_ videoID: UUID, message: String, cancelled: Bool) {
        updateVideo(videoID) { v in
            v.runState = cancelled ? .partial : .failed
            v.runMessage = message
            v.status = cancelled ? "Tracking paused" : "Tracking failed"
        }
    }

    // MARK: Review

    /// Changes the reviewer's check of the video's current run (created on first use).
    func updateReview(_ videoID: UUID, unit: String, _ change: (inout VideoReviewState) -> Void) {
        guard let v = video(videoID), let folder = v.runFolder, v.runState == .complete else { return }
        var state = v.currentReview ?? VideoReviewState(runFolder: folder, unit: unit)
        change(&state)
        if state == v.review { return }
        updateVideo(videoID) { $0.review = state }
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    // MARK: Persistence

    /// Encoding happens here; the atomic file write runs on a background queue so typing and
    /// dragging never wait for the disk.
    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let bytes = try encoder.encode(document)
            let url = storageURL
            writer.async { [weak self] in
                do {
                    try bytes.write(to: url, options: .atomic)
                } catch {
                    let message = error.localizedDescription
                    Task { @MainActor in
                        self?.notice = L("Workspace could not be saved: ", "工作区无法保存：") + message
                    }
                }
            }
        } catch {
            notice = L("Workspace could not be saved: ", "工作区无法保存：") + error.localizedDescription
        }
    }
}
