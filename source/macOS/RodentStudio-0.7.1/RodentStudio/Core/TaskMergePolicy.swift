// TaskMergePolicy.swift — consolidate tasks with the same name, assay and note.
// Keep stable surviving UUIDs, source videos, saved run folders and independent notes.
import Foundation

struct TaskMergeOutcome {
    var redirects: [UUID: UUID] = [:]
    var blocked: [UUID] = []
}

enum TaskMergePolicy {
    static func sameName(_ a: String, _ b: String) -> Bool {
        func normalized(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        return normalized(a) == normalized(b)
    }

    /// Match the full note after trimming accidental leading/trailing whitespace.
    /// Internal text and case are significant: e.g. "Group A" and "Group a" may refer
    /// to different treatment cohorts. Missing notes and whitespace-only notes are equal.
    static func sameNotes(_ a: String?, _ b: String?) -> Bool {
        let left = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return left == right
    }

    /// Merge only when task names, experiment assays, and complete notes all match.
    /// Assays must match: identically named tasks with different models are not equivalent.
    @discardableResult
    static func consolidate(document: inout WorkspaceDocument) -> TaskMergeOutcome {
        var result = TaskMergeOutcome()
        for p in document.projects.indices {
            var keep: [NativeExperiment] = []
            var oldToNew: [UUID: UUID] = [:]
            let project = document.projects[p]
            for exp in project.experiments {
                // Multi-chamber recordings are archived by task UUID in a separate store.
                // Never redirect this task ID without migrating every saved recording.
                if exp.assay == .tstMultiChamber { keep.append(exp); continue }
                guard let index = keep.firstIndex(where: {
                    $0.assay == exp.assay && sameName($0.name, exp.name)
                        && sameNotes($0.notes, exp.notes)
                }) else {
                    keep.append(exp)
                    continue
                }
                let survivor = keep[index]
                guard canMerge(project: project, survivor: survivor.id, moving: exp.id,
                               redirects: oldToNew) else {
                    result.blocked.append(exp.id)
                    keep.append(exp)
                    continue
                }
                oldToNew[exp.id] = survivor.id
                result.redirects[exp.id] = survivor.id
                // Preserve any group style not already configured on the surviving task.
                var styles = keep[index].groupStyles ?? [:]
                for (group, style) in exp.groupStyles ?? [:] where styles[group] == nil {
                    styles[group] = style
                }
                if !styles.isEmpty { keep[index].groupStyles = styles }
            }
            guard !oldToNew.isEmpty else { continue }
            document.projects[p].experiments = keep
            for i in document.projects[p].videos.indices {
                if let old = document.projects[p].videos[i].experimentID,
                   let destination = oldToNew[old] {
                    document.projects[p].videos[i].experimentID = destination
                }
            }
        }
        return result
    }

    /// Prevent a silent scientific data error: one animal must not acquire the same numbered
    /// session twice or conflicting nonempty group/sex attributes as a result of consolidation.
    private static func canMerge(project: NativeProject, survivor: UUID, moving: UUID,
                                 redirects: [UUID: UUID]) -> Bool {
        let into = project.videos.filter { v in
            guard let id = v.experimentID else { return false }
            return id == survivor || redirects[id] == survivor
        }
        let from = project.videos.filter { $0.experimentID == moving }
        for a in from {
            for b in into where a.animalKey == b.animalKey {
                if let n = a.sessionNumber, let m = b.sessionNumber, n == m { return false }
                if !a.groupKey.isEmpty && !b.groupKey.isEmpty && a.groupKey != b.groupKey { return false }
                let sexA = a.sex ?? "", sexB = b.sex ?? ""
                if !sexA.isEmpty && !sexB.isEmpty && sexA != sexB { return false }
            }
        }
        return true
    }
}
