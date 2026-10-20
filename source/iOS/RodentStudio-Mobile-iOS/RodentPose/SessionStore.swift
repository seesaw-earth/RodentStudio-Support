// SessionStore.swift — sessions on disk: Documents/Sessions/<id>/{session.json, pose.mpt, video.*, thumb.jpg}.
// Visible in the Files app (UIFileSharingEnabled), so results can also be copied out by hand.

import Foundation
import SwiftUI
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var isLoaded = false
    @Published var lastError: String?

    let root: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    // MARK: Paths

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func sessionFile(_ id: UUID) -> URL { folder(id).appendingPathComponent("session.json") }
    func poseFile(_ id: UUID) -> URL { folder(id).appendingPathComponent("pose.mpt") }
    func thumbnailURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("thumb.jpg") }

    func videoURL(_ s: Session) -> URL? {
        guard let name = s.videoFile else { return nil }
        let url = folder(s.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func session(_ id: UUID) -> Session? { sessions.first { $0.id == id } }

    // MARK: Loading

    func reload() {
        let root = self.root
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            let decoder = JSONDecoder()
            var loaded: [Session] = []
            for d in dirs {
                let f = d.appendingPathComponent("session.json")
                guard let data = try? Data(contentsOf: f), let s = try? decoder.decode(Session.self, from: data) else { continue }
                loaded.append(s)
            }
            loaded.sort { $0.updatedAt > $1.updatedAt }
            let result = loaded
            await MainActor.run {
                self.sessions = result
                self.isLoaded = true
            }
        }
    }

    // MARK: Saving

    /// Sessions deleted in this run; late saves (debounced edits, a stopped inference) are ignored.
    private var deleted = Set<UUID>()

    func save(_ s: Session) {
        guard !deleted.contains(s.id) else { return }
        var s = Exporter.englishSession(s)
        s.updatedAt = Date()
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i] = s
        } else {
            sessions.insert(s, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        let url = sessionFile(s.id)
        let dir = folder(s.id)
        let snapshot = s
        Task.detached(priority: .utility) {
            do {
                // The folder is created on import; never re-create a folder that was deleted meanwhile.
                guard FileManager.default.fileExists(atPath: dir.path) else { return }
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                enc.dateEncodingStrategy = .deferredToDate
                try enc.encode(snapshot).write(to: url, options: .atomic)
            } catch {
                await MainActor.run { self.lastError = L10n.tr("保存失败：\(error.localizedDescription)") }
            }
        }
    }

    func savePose(_ track: PoseTrack, for id: UUID) async throws {
        guard !deleted.contains(id) else { return }
        let url = poseFile(id)
        let dir = folder(id)
        try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: dir.path) else { return }
            try track.encoded().write(to: url, options: .atomic)
        }.value
    }

    func loadPose(_ id: UUID) async -> PoseTrack? {
        let url = poseFile(id)
        return await Task.detached(priority: .userInitiated) { () -> PoseTrack? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? PoseTrack.decode(data)
        }.value
    }

    /// Moves an imported video into the session folder and returns its file name.
    func adoptVideo(from url: URL, into id: UUID) async throws -> String {
        let dir = folder(id)
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()
        let name = "video." + ext
        let dst = dir.appendingPathComponent(name)
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
            let tmp = fm.temporaryDirectory.standardizedFileURL.path
            if url.standardizedFileURL.path.hasPrefix(tmp) {
                try fm.moveItem(at: url, to: dst)
            } else {
                try fm.copyItem(at: url, to: dst)
            }
        }.value
        return name
    }

    func saveThumbnail(_ image: CGImage, for id: UUID) {
        let url = thumbnailURL(id)
        let ui = UIImage(cgImage: image)
        Task.detached(priority: .utility) {
            let maxSide: CGFloat = 480
            let scale = min(1, maxSide / max(ui.size.width, ui.size.height, 1))
            let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let small = renderer.image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
            try? small.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
        }
    }

    // MARK: Deleting

    func delete(_ s: Session) {
        deleted.insert(s.id)
        sessions.removeAll { $0.id == s.id }
        let dir = folder(s.id)
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: dir) }
    }

    func deleteVideo(of s: Session) {
        guard let url = videoURL(s) else { return }
        var s = s
        s.videoFile = nil
        save(s)
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Pairing (social interaction test)

    /// Metrics of the other phase of the same animal (e.g. "No target" for a "Target" run).
    func companionMetrics(for s: Session) -> [String: Double] {
        guard s.paradigm == .socialInteraction, !s.subjectID.isEmpty else { return [:] }
        let other = sessions
            .filter { $0.id != s.id && $0.paradigm == s.paradigm && $0.subjectID == s.subjectID && $0.phase != s.phase && !$0.metrics.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        return other?.metrics ?? [:]
    }

    // MARK: Storage

    func storageBytes() async -> Int64 {
        let root = self.root
        return await Task.detached(priority: .utility) { () -> Int64 in
            var total: Int64 = 0
            if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let url as URL in e {
                    total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return total
        }.value
    }

    // MARK: Export files

    /// Writes an export into a temporary "Exports" folder and returns its URL (for the share sheet).
    nonisolated static func writeExport(_ name: String, data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    nonisolated static func writeExport(_ name: String, text: String) throws -> URL {
        try writeExport(name, csv: Data(text.utf8))
    }

    /// CSV as UTF-8 with BOM, so that Excel opens Chinese text correctly.
    nonisolated static func writeExport(_ name: String, csv: Data) throws -> URL {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(csv)
        return try writeExport(name, data: data)
    }
}
