import Foundation

public enum MotionMetric: String, Codable, CaseIterable, Sendable {
    /// Centroid- and axis-aligned silhouette change: ignores passive pendulum swing.
    case shape
    /// Frame differencing on the segmented mouse pixels; counts swinging as movement.
    case pixel
    /// Frame differencing inside a fixed box per chamber (where the detector saw the mouse after the key
    /// frame), after aligning the previous frame to the current one (shift + rotation of the dark mass)
    /// so that passive swinging is not counted. Does not depend on the segmented outline (default).
    case box
}

public struct AnalysisSettings: Codable, Equatable, Sendable {
    // Time window
    public var startSec: Double = 0
    public var durationSec: Double = 360          // standard TST: 6 min
    public var lastWindowSec: Double = 240        // report the last 4 min separately

    // Sampling
    public var processingWidth: Int = 640         // frames are downscaled to this width
    public var targetFPS: Double = 15             // analyse at most this many frames per second
    public var detectionSamples: Int = 40         // frames sampled for chamber detection / thresholds

    // Segmentation
    public var mouseDark: Bool = true             // dark mice on a light background
    public var otsuOffset: Int = 0                // + makes dark-mouse segmentation stricter
    public var wallMarginFraction: Double = 0.04  // trimmed from each side of a chamber
    public var tailKernelFraction: Double = 0.08  // opening kernel (× chamber pitch) that strips the tail/tape
    public var minMouseAreaFraction: Double = 0.008 // of chamber ROI area (curled-up mice are small)

    // Motion & classification
    public var metric: MotionMetric = .box
    public var alignRotation: Bool = true
    public var compareLagSec: Double = 0.2        // shape metric compares with the silhouette this long ago
    public var edgeTolerancePx: Int = 1           // ignore silhouette edge jitter up to this many px
    public var diffThreshold: Int = 15            // grey-level change for the pixel-change metric
    public var smoothSec: Double = 0.5            // rolling median
    public var immobilityThreshold: Double = 2.0  // % of mouse area per frame; below = immobile (calibrate!)
    public var minBoutSec: Double = 1.0           // immobility must last at least this long

    // Outline refinement (see MouseSegmenter.refineOutline). The tail-removing opening also strips the
    // limbs, paws and fur edge; the refinement grows them back from the selected body. nil = settings
    // saved before the option existed, i.e. analysed with the original outline.
    public var refinedOutline: Bool? = true
    public var useRefinedOutline: Bool { refinedOutline ?? false }

    // Analysis window. By default the whole video after the key frame is analysed; `durationSec` only
    // limits it when the user turns this on. nil = off.
    public var limitDuration: Bool? = nil
    public var stopsAtDuration: Bool { limitDuration ?? false }

    // Standard test windows, measured from EACH mouse's own suspension. Standard TST: a 6-min test whose
    // last 4 min (minutes 2–6) are the primary measure (`lastWindowSec`); minutes 0–2 are reported too.
    public var testLengthSec: Double? = nil
    public var standardTestSec: Double { max(60, testLengthSec ?? 360) }
    /// Per chamber: when that mouse was suspended, in seconds after `startSec` (set by the analysis from the
    /// key-frame scan). nil = every mouse is timed from `startSec`.
    public var chamberOnsetSec: [Double]? = nil

    public init() {}
}
