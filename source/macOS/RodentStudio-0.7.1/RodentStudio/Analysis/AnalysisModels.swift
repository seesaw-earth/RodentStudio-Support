// AnalysisModels.swift — assays, parameters, calibration and result types.

import Foundation

// MARK: - Assays

enum Assay: String, Codable, CaseIterable, Identifiable {
    case tailSuspension, cylinder, gait
    var id: String { rawValue }

    var name: LText {
        switch self {
        case .tailSuspension: return LText("Tail suspension", "悬尾实验")
        case .cylinder: return LText("Cylinder test", "圆筒实验")
        case .gait: return LText("Gait analysis", "步态分析")
        }
    }

    var code: String {
        switch self {
        case .tailSuspension: return "TST"
        case .cylinder: return "CYL"
        case .gait: return "GAIT"
        }
    }

    var symbol: String {
        switch self {
        case .tailSuspension: return "arrow.down.to.line"
        case .cylinder: return "cylinder"
        case .gait: return "pawprint.fill"
        }
    }

    var summary: LText {
        switch self {
        case .tailSuspension:
            return LText("Immobility, latency, per-minute profile, hindlimb clasping and tail climbing",
                         "不动时间、潜伏期、逐分钟曲线、后肢抱握与爬尾检测")
        case .cylinder:
            return LText("Forelimb wall contacts during rearing: left, right, both and use asymmetry",
                         "竖立时前爪触壁：左、右、双爪及使用不对称性")
        case .gait:
            return LText("Stance/swing, stride, duty factor, base of support, interlimb phase, regularity",
                         "支撑相/摆动相、步幅、占空比、支撑面宽度、肢间相位、规律性")
        }
    }

    var cameraTip: LText {
        switch self {
        case .tailSuspension:
            return LText("Film the hanging mouse from the front or back (ventral/dorsal view) so both hind paws are visible; one mouse per video. Start recording at suspension; a standard test lasts 6 min.",
                         "从正面或背面拍摄悬挂的小鼠（腹侧/背侧视角），保证两只后爪可见；每段视频一只小鼠。从悬挂开始录制，标准时长 6 分钟。")
        case .cylinder:
            return LText("Bottom view through a transparent floor works best (paws touching the wall appear at the rim). Side view also works with a floor line. 5–10 min per mouse.",
                         "最佳为透明底面的仰视拍摄（触壁的爪出现在圆周边缘）；侧视也可用，需标定地面线。每只小鼠 5–10 分钟。")
        case .gait:
            return LText("Bottom (ventral) view of a straight walkway, camera fixed, high frame rate (≥ 60 fps recommended). Place a ruler in view once to calibrate cm.",
                         "直线步道的仰视（腹侧）拍摄，相机固定，帧率越高越好（建议 ≥ 60 fps）。画面中放一次标尺用于厘米标定。")
        }
    }
}

// MARK: - Parameters

struct CommonParams: Codable, Equatable {
    /// Keypoints below this confidence are treated as missing.
    var keypointThreshold: Double = 0.30
    /// Gaps up to this length (s) are linearly interpolated.
    var maxGap: Double = 0.25
    /// Centered moving-average window for positions (s).
    var smoothing: Double = 0.10
}

struct TSTParams: Codable, Equatable {
    var windowStart: Double = 120
    var windowEnd: Double = 360
    /// Motion below this (body lengths / s) counts as immobile.
    var motionThreshold: Double = 0.25
    var minBout: Double = 1.0
    var motionSmoothing: Double = 0.25
    /// Hind paw lateral distance from the body axis (body lengths).
    var claspPartial: Double = 0.25
    var claspFull: Double = 0.10
    var claspWindow: Double = 10
    /// Nose–tail-base distance below this fraction of body length = tail climbing.
    var climbRatio: Double = 0.5
}

enum CylinderViewMode: String, Codable, CaseIterable, Identifiable {
    case bottom, side
    var id: String { rawValue }
    var label: String { self == .bottom ? L("Bottom view", "仰视") : L("Side view", "侧视") }
}

enum CylinderScoring: String, Codable, CaseIterable, Identifiable {
    case firstPerRear, allContacts
    var id: String { rawValue }
    var label: String { self == .firstPerRear ? L("First contact per rear", "每次竖立首次触壁") : L("Every contact", "所有触壁") }
}

enum LesionSide: String, Codable, CaseIterable, Identifiable {
    case none, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L("Not set", "不设置")
        case .left: return L("Left hemisphere", "左半球")
        case .right: return L("Right hemisphere", "右半球")
        }
    }
}

struct CylinderParams: Codable, Equatable {
    var view: CylinderViewMode = .bottom
    /// Bottom view: a paw within this fraction of the radius from the rim is at the wall.
    var wallMargin: Double = 0.15
    /// Side view: paw height above the floor line (body lengths) to count as raised.
    var elevation: Double = 0.30
    /// A placed paw moves slower than this (body lengths / s).
    var stillSpeed: Double = 0.8
    var minContact: Double = 0.10
    /// Left and right placements within this interval are scored "both".
    var simultaneity: Double = 0.20
    /// Contacts separated by less than this belong to the same rear.
    var rearGap: Double = 0.5
    var scoring: CylinderScoring = .firstPerRear
    var lesion: LesionSide = .none
    var swapLR: Bool = false
    /// Score only the first N seconds / first N contacts (0 = no limit).
    var timeLimit: Double = 0
    var contactLimit: Int = 0
}

struct GaitParams: Codable, Equatable {
    /// Stance if paw speed < max(stanceFloor·BL/s, stanceRatio·body speed). 0.8 was the least
    /// biased value on simulated trot/walk at 30–100 fps with 1–2 px keypoint noise.
    var stanceRatio: Double = 0.8
    var stanceFloor: Double = 0.8
    var minPhase: Double = 0.03
    /// Strides are used only while the body moves at least this fast (BL / s).
    var minBodySpeed: Double = 1.0
    var maxStride: Double = 1.0
    var swapLR: Bool = false
    /// Strides are kept only while walking straight: mean |angular velocity| ≤ this (deg/s).
    /// Sheppard et al. 2022 analyzed straight strides at −20…+20 °/s.
    var maxTurnRate: Double = 30
    /// Drop the first and last stride of every continuous walking run (acceleration /
    /// deceleration), as in Sheppard et al. 2022.
    var trimRunEnds: Bool = true
    /// Speed at which speed-matched values are reported (body lengths / s).
    var referenceSpeed: Double = 2.0

    init() {}

    // Tolerant decoding: sessions saved by older versions lack the newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GaitParams()
        stanceRatio = try c.decodeIfPresent(Double.self, forKey: .stanceRatio) ?? d.stanceRatio
        stanceFloor = try c.decodeIfPresent(Double.self, forKey: .stanceFloor) ?? d.stanceFloor
        minPhase = try c.decodeIfPresent(Double.self, forKey: .minPhase) ?? d.minPhase
        minBodySpeed = try c.decodeIfPresent(Double.self, forKey: .minBodySpeed) ?? d.minBodySpeed
        maxStride = try c.decodeIfPresent(Double.self, forKey: .maxStride) ?? d.maxStride
        swapLR = try c.decodeIfPresent(Bool.self, forKey: .swapLR) ?? d.swapLR
        maxTurnRate = try c.decodeIfPresent(Double.self, forKey: .maxTurnRate) ?? d.maxTurnRate
        trimRunEnds = try c.decodeIfPresent(Bool.self, forKey: .trimRunEnds) ?? d.trimRunEnds
        referenceSpeed = try c.decodeIfPresent(Double.self, forKey: .referenceSpeed) ?? d.referenceSpeed
    }
}

struct AssayParams: Codable, Equatable {
    var common = CommonParams()
    var tst = TSTParams()
    var cylinder = CylinderParams()
    var gait = GaitParams()

    /// Gait needs much lighter position smoothing than the other assays: swing phases last only
    /// ~0.1 s, and a 0.1 s window would blur them into stance.
    static func defaults(for assay: Assay) -> AssayParams {
        var p = AssayParams()
        if assay == .gait { p.common.smoothing = 0.03 }
        return p
    }
}

// MARK: - Calibration (display-frame pixels)

struct CircleCal: Codable, Equatable {
    var cx: Double
    var cy: Double
    var r: Double
}

struct ScaleCal: Codable, Equatable {
    var x1: Double, y1: Double, x2: Double, y2: Double
    var cm: Double
    var pixels: Double { hypot(x2 - x1, y2 - y1) }
    var pxPerCm: Double? { cm > 0 && pixels > 1 ? pixels / cm : nil }
}

struct Calibration: Codable, Equatable {
    var circle: CircleCal?
    var floorY: Double?
    var scale: ScaleCal?
    /// When calibration was copied from another session (fixed camera), its subject ID.
    var copiedFrom: String?
}

// MARK: - Results

enum NoteLevel: String, Codable { case info, warning, error }

struct Note: Codable, Hashable, Identifiable {
    var level: NoteLevel
    var text: LText
    var id: String { level.rawValue + text.en }
    init(_ level: NoteLevel, _ en: String, _ zh: String) {
        self.level = level
        self.text = LText(en, zh)
    }
}

struct Metric: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var value: Double?
    var unit: String
    var decimals: Int
    var highlight: Bool = false
    /// Section this measure is listed under in the Measures tab.
    var group: LText? = nil
    var id: String { key }

    var formatted: String {
        guard let v = value, v.isFinite else { return "—" }
        return String(format: "%.\(decimals)f", v)
    }

    var exportValue: String {
        guard let v = value, v.isFinite else { return "" }
        return String(format: "%.\(max(decimals, 3))f", v)
    }
}

struct Interval: Codable, Hashable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

struct SeriesPoint: Codable, Hashable {
    var t: Double
    var v: Double
}

// TST
struct TSTDetail: Codable {
    var motion: [SeriesPoint]
    var threshold: Double
    var bouts: [Interval]
    var climbing: [Interval]
    var perMinute: [Double]
    var window: Interval
}

// Cylinder
enum PawLabel: String, Codable, CaseIterable, Identifiable {
    case left, right, both, ignore
    var id: String { rawValue }
    var short: String {
        switch self {
        case .left: return L("L", "左")
        case .right: return L("R", "右")
        case .both: return L("Both", "双")
        case .ignore: return L("Ignore", "忽略")
        }
    }
    var name: String {
        switch self {
        case .left: return L("Left", "左爪")
        case .right: return L("Right", "右爪")
        case .both: return L("Both", "双爪")
        case .ignore: return L("Ignored", "已忽略")
        }
    }
}

struct CylinderEvent: Codable, Hashable, Identifiable {
    /// Onset frame index — stable across re-analysis with the same video.
    var id: Int
    var onset: Double
    var offset: Double
    var auto: PawLabel
    var label: PawLabel
    var edited: Bool
    var rear: Int
    var counted: Bool
}

struct CylinderDetail: Codable {
    var events: [CylinderEvent]
    var rears: [Interval]
    var leftContacts: [Interval]
    var rightContacts: [Interval]
}

// Gait
struct GaitStride: Codable, Hashable {
    var paw: Kp
    var start: Double
    var end: Double
    var stance: Double
    var swing: Double
    var duty: Double
    var length: Double      // output units (cm or BL)
    var speed: Double       // output units per s
}

struct Footprint: Codable, Hashable {
    var paw: Kp
    var t: Double
    var x: Double           // display pixels
    var y: Double
}

struct PawSummary: Codable, Hashable {
    var paw: Kp
    var strides: Int
    var strideLength: Double?
    var strideDuration: Double?
    var stance: Double?
    var swing: Double?
    var duty: Double?
}

struct GaitDetail: Codable {
    var unit: String           // "cm" or "BL"
    var stances: [String: [Interval]]   // keyed by Kp.code
    var strides: [GaitStride]
    var footprints: [Footprint]
    var paws: [PawSummary]
    var speed: [SeriesPoint]
    var phases: [PhaseSummary]
    /// Share of hind strides per gait pattern (walk, trot, gallop, bound).
    var patterns: [PatternShare]? = nil
}

struct PatternShare: Codable, Hashable, Identifiable {
    var key: String
    var label: LText
    var count: Int
    var id: String { key }
}

extension Array where Element == Metric {
    /// Assigns Measures-tab sections by key.
    func grouped(_ sections: [(LText, [String])]) -> [Metric] {
        map { m in
            var m = m
            m.group = sections.first { $0.1.contains(m.key) }?.0
            return m
        }
    }
}

struct PhaseSummary: Codable, Hashable {
    var key: String
    var label: LText
    var values: [Double]
    var mean: Double?
    var r: Double?
}

struct AnalysisResult: Codable {
    /// Bumped whenever an analyzer changes, so stored results are recomputed on open.
    static let currentVersion = 2
    var version: Int? = AnalysisResult.currentVersion
    var metrics: [Metric]
    var notes: [Note]
    var tst: TSTDetail?
    var cylinder: CylinderDetail?
    var gait: GaitDetail?
    var analyzedAt: Date
    var poseCoverage: Double

    func metric(_ key: String) -> Metric? { metrics.first { $0.key == key } }
}
