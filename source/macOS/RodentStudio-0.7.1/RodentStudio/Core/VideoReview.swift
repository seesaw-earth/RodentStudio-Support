import Foundation

/// Outcome of the reviewer's tracking check of one video.
enum ReviewVerdict: String, Codable, CaseIterable {
    case unreviewed, passed, issues

    var title: String {
        switch self {
        case .unreviewed: return L("Not checked", "未复核")
        case .passed: return L("Tracking OK", "追踪无误")
        case .issues: return L("Tracking problems", "追踪有问题")
        }
    }

    var symbol: String {
        switch self {
        case .unreviewed: return "circle.dashed"
        case .passed: return "checkmark.seal.fill"
        case .issues: return "exclamationmark.triangle.fill"
        }
    }

    /// English value written to exports.
    var exportValue: String {
        switch self {
        case .unreviewed: return "not_reviewed"
        case .passed: return "tracking_ok"
        case .issues: return "tracking_problems"
        }
    }
}

/// The reviewer's check of one video, saved in the workspace so it survives switching video, task,
/// section or language. It belongs to one tracking run: a new run starts a new check.
///
/// A check may cover only a window of frames (e.g. frames 0–99): every frame does not have to be
/// inspected. The window, the frames looked at and the frames flagged are recorded as they are.
struct VideoReviewState: Codable, Equatable {
    /// Run folder (relative to the app's Runs folder) this check belongs to.
    var runFolder: String
    /// "frame" for RodentPose / RodentLimb (every video frame is tracked), "sample" for RodentFlow (10 Hz).
    var unit: String = "frame"
    /// First index of the checked window (zero-based) and its length.
    var windowStart: Int = 0
    var windowCount: Int = 100
    /// Indices (absolute, zero-based) that were displayed during the check.
    var viewed: [Int] = []
    /// Indices (absolute, zero-based) flagged as wrongly tracked.
    var flagged: [Int] = []
    var verdict: ReviewVerdict = .unreviewed
    var notes: String = ""
    var reviewedAt: Date?
    /// Decisions on tracking-QC events from the full frame review (event id → "accepted" / "flagged").
    var eventDecisions: [String: String] = [:]

    init(runFolder: String, unit: String) {
        self.runFolder = runFolder
        self.unit = unit
    }

    /// Tolerant decoding: a missing or unreadable field never makes the whole workspace unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runFolder = (try? c.decode(String.self, forKey: .runFolder)) ?? ""
        unit = (try? c.decode(String.self, forKey: .unit)) ?? "frame"
        windowStart = (try? c.decode(Int.self, forKey: .windowStart)) ?? 0
        windowCount = (try? c.decode(Int.self, forKey: .windowCount)) ?? 100
        viewed = (try? c.decode([Int].self, forKey: .viewed)) ?? []
        flagged = (try? c.decode([Int].self, forKey: .flagged)) ?? []
        verdict = (try? c.decode(ReviewVerdict.self, forKey: .verdict)) ?? .unreviewed
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        reviewedAt = try? c.decode(Date.self, forKey: .reviewedAt)
        eventDecisions = (try? c.decode([String: String].self, forKey: .eventDecisions)) ?? [:]
    }

    var windowEnd: Int { windowStart + max(1, windowCount) - 1 }
}

extension VideoRecord {
    /// The check of the current run, if any. A check of an earlier run is not reused.
    var currentReview: VideoReviewState? {
        guard let review, let folder = runFolder, review.runFolder == folder else { return nil }
        return review
    }

    var reviewVerdict: ReviewVerdict { currentReview?.verdict ?? .unreviewed }

    /// The phase used for analysis. An empty or missing phase means the task's default phase, the value
    /// the Video & animal step shows (same rule everywhere: analysis, figures and exports).
    func effectivePhase(for assay: StudyAssay?) -> String {
        let stored = (phase ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        return assay?.defaultPhase ?? ""
    }
}
