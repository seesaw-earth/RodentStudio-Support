// PoseDecoding.swift — decoding of the end-to-end YOLO pose output ([1, N, 6 + 3·K]) into
// keypoints of the upright video frame. Same arithmetic as UltralyticsYOLO 8.9
// (PoseEstimator.postProcessEnd2EndPose + BasePredictor letterbox / inputPoint / normalizedPoint),
// kept free of Core ML so it can be tested anywhere.

import Foundation

enum PoseDecoding {
    struct Layout {
        var detections: Int
        var fields: Int
        var detectionStride: Int
        var fieldStride: Int
    }

    /// Detections with confidence above `threshold`, in model order, at most `limit`.
    /// `inputSize` is the size of the image given to Vision (letterboxed into `modelSize`);
    /// keypoints are returned in pixels of `frameSize`. nil if the buffer is too small.
    static func decode(_ p: UnsafeBufferPointer<Float>, layout: Layout, inputSize: CGSize,
                       modelSize: (width: Int, height: Int), frameSize: CGSize,
                       threshold: Float, limit: Int) -> [AnimalPose]? {
        let count = layout.detections, fields = layout.fields
        let ds = layout.detectionStride, fs = layout.fieldStride
        guard count > 0 else { return [] }
        guard fields >= 6 else { return nil }
        let kpStart = (fields - 6) % 3 == 0 ? 6 : 5
        guard (fields - kpStart) / 3 >= kKeypointCount else { return nil }
        guard (count - 1) * ds + (fields - 1) * fs < p.count else { return nil }
        let iw = inputSize.width, ih = inputSize.height
        guard iw > 0, ih > 0, modelSize.width > 0, modelSize.height > 0 else { return nil }
        // BasePredictor.letterboxTransform
        let mw = CGFloat(modelSize.width), mh = CGFloat(modelSize.height)
        let gain = min(mh / ih, mw / iw)
        guard gain > 0 else { return nil }
        let padX = ((mw - (iw * gain).rounded()) / 2 - 0.1).rounded()
        let padY = ((mh - (ih * gain).rounded()) / 2 - 0.1).rounded()
        let fw = Float(frameSize.width), fh = Float(frameSize.height)
        var out: [AnimalPose] = []
        for d in 0..<count {
            let base = d * ds
            let conf = p[base + 4 * fs]
            guard conf > threshold else { continue }
            var xs = [Float](repeating: 0, count: kKeypointCount)
            var ys = xs, cs = xs
            for k in 0..<kKeypointCount {
                let kx = CGFloat(p[base + (kpStart + 3 * k) * fs])
                let ky = CGFloat(p[base + (kpStart + 3 * k + 1) * fs])
                // inputPoint(fromModelPoint:) then normalizedPoint(fromInputPoint:)
                let x = min(max((kx - padX) / gain, 0), iw)
                let y = min(max((ky - padY) / gain, 0), ih)
                xs[k] = Float(x / iw) * fw
                ys[k] = Float(y / ih) * fh
                cs[k] = p[base + (kpStart + 3 * k + 2) * fs]
            }
            out.append(AnimalPose(conf: max(conf, 1e-4), x: xs, y: ys, kconf: cs))
            if out.count >= limit { break }
        }
        return out
    }
}
