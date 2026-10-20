import Foundation
import CoreML
import Vision
import CoreGraphics
/// Finds mice in one processed (grayscale, oriented, downscaled) frame.
protocol TSTMouseDetecting: AnyObject, Sendable {
    var name: String { get }
    /// Boxes in processed-frame pixel coordinates.
    func detect(_ frame: GrayImage, layout: ChamberLayout?) throws -> [DetBox]
}

enum TSTDetectorMode: String, Codable, CaseIterable, Identifiable {
    case auto, yolo, classical
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return L("Automatic (YOLO when a model is available)", "自动（有模型时用 YOLO）")
        case .yolo: return L("YOLO model", "YOLO 模型")
        case .classical: return L("Classical (dark blob per chamber)", "经典方法（每格找暗色区域）")
        }
    }
}

// MARK: - YOLO via Core ML + Vision

/// Works with Ultralytics Core ML exports:
///  • `nms=True` pipelines → `VNRecognizedObjectObservation`s
///  • raw exports → one MLMultiArray [1, 4 + classes, anchors] (cx, cy, w, h in input pixels), decoded here.
/// The frame is letterboxed into the model's input size by us (centred, grey 114 padding, like Ultralytics),
/// so boxes map back exactly regardless of Vision's own scaling rules.
final class TSTYOLOMouseDetector: TSTMouseDetecting, @unchecked Sendable {
    let name: String
    private let vnModel: VNCoreMLModel
    private let inputW: Int
    private let inputH: Int
    private let mouseClassIndex: Int?     // nil = accept every class (single-class custom model)
    private let mouseLabel: String?
    var iouThreshold: Double = 0.5
    var rawConfidenceFloor: Double = 0.1

    init(compiledModelURL url: URL, name: String) throws {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all
        let ml = try MLModel(contentsOf: url, configuration: cfg)
        vnModel = try VNCoreMLModel(for: ml)
        vnModel.inputImageFeatureName = ml.modelDescription.inputDescriptionsByName
            .first(where: { $0.value.type == .image })?.key ?? vnModel.inputImageFeatureName
        // Ultralytics NMS pipelines take the thresholds as extra (double) inputs; Vision gets them from here.
        let inputs = ml.modelDescription.inputDescriptionsByName
        if inputs["iouThreshold"] != nil || inputs["confidenceThreshold"] != nil {
            vnModel.featureProvider = try? MLDictionaryFeatureProvider(dictionary: [
                "iouThreshold": MLFeatureValue(double: 0.45),
                "confidenceThreshold": MLFeatureValue(double: 0.1),   // low: the app applies its own minimum
            ])
        }
        let img = inputs.values.first { $0.type == .image }?.imageConstraint
        inputW = img?.pixelsWide ?? 640
        inputH = img?.pixelsHigh ?? 640
        // class names: Ultralytics stores them in the metadata as a dict string {0: 'mouse', ...}
        let names = TSTYOLOMouseDetector.classNames(ml)
        if let i = names.firstIndex(where: { $0.lowercased() == "mouse" }), names.count > 1 {
            mouseClassIndex = i; mouseLabel = names[i]
        } else {
            mouseClassIndex = nil; mouseLabel = nil
        }
        self.name = name + " (\(inputW)×\(inputH)" + (names.isEmpty ? "" : ", \(names.count) class\(names.count == 1 ? "" : "es")") + ")"
    }

    static func classNames(_ ml: MLModel) -> [String] {
        let md = ml.modelDescription.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
        if let s = md["names"] {
            // "{0: 'mouse', 1: 'hand'}"
            let parts = s.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).split(separator: ",")
            return parts.compactMap { p in
                guard let colon = p.firstIndex(of: ":") else { return nil }
                return p[p.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            }
        }
        if let labels = ml.modelDescription.classLabels as? [String] { return labels }
        return []
    }

    func detect(_ frame: GrayImage, layout: ChamberLayout?) throws -> [DetBox] {
        let r = min(Double(inputW) / Double(frame.width), Double(inputH) / Double(frame.height))
        let dw = Double(frame.width) * r, dh = Double(frame.height) * r
        let padX = (Double(inputW) - dw) / 2, padY = (Double(inputH) - dh) / 2
        guard let src = TSTImageRendering.cgImage(frame),
              let ctx = CGContext(data: nil, width: inputW, height: inputH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        ctx.setFillColor(CGColor(gray: 114.0 / 255.0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: inputW, height: inputH))
        ctx.interpolationQuality = .medium
        // CGContext origin is bottom-left; the padding is symmetric, so the same offsets apply.
        ctx.draw(src, in: CGRect(x: padX, y: padY, width: dw, height: dh))
        guard let boxed = ctx.makeImage() else { return [] }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill   // already exactly the input size
        try VNImageRequestHandler(cgImage: boxed, options: [:]).perform([request])
        let results = request.results ?? []

        // input-pixel box (top-left origin) → frame pixels
        func toFrame(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ conf: Double) -> DetBox {
            DetBox(x0: max(0, (x0 - padX) / r), y0: max(0, (y0 - padY) / r),
                   x1: min(Double(frame.width), (x1 - padX) / r), y1: min(Double(frame.height), (y1 - padY) / r),
                   confidence: conf)
        }

        var boxes: [DetBox] = []
        let objects = results.compactMap { $0 as? VNRecognizedObjectObservation }
        if !objects.isEmpty {
            for o in objects {
                let conf: Double
                if let label = mouseLabel {
                    conf = Double(o.labels.first { $0.identifier == label }?.confidence ?? 0)
                } else {
                    conf = Double(o.confidence)
                }
                let bb = o.boundingBox   // normalised, origin bottom-left
                boxes.append(toFrame(bb.minX * Double(inputW), (1 - bb.maxY) * Double(inputH),
                                     bb.maxX * Double(inputW), (1 - bb.minY) * Double(inputH), conf))
            }
        } else if let fv = results.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
                  let arr = fv.featureValue.multiArrayValue {
            boxes = decodeRaw(arr).map { toFrame($0.x0, $0.y0, $0.x1, $0.y1, $0.confidence) }
            boxes = BoxOps.nms(boxes, iouThreshold: iouThreshold)
        }
        return boxes.filter { $0.width > 1 && $0.height > 1 }
    }

    /// Ultralytics raw head: [1, 4 + nc, N] (or [1, N, 4 + nc]); boxes in input pixels.
    private func decodeRaw(_ a: MLMultiArray) -> [DetBox] {
        let shape = a.shape.map { $0.intValue }
        guard shape.count == 3 else { return [] }
        let channelsFirst = shape[1] < shape[2]
        let c = channelsFirst ? shape[1] : shape[2], n = channelsFirst ? shape[2] : shape[1]
        guard c >= 5 else { return [] }
        let strides = a.strides.map { $0.intValue }
        func v(_ ch: Int, _ i: Int) -> Double {
            let idx = channelsFirst ? ch * strides[1] + i * strides[2] : i * strides[1] + ch * strides[2]
            return a[idx].doubleValue
        }
        var out: [DetBox] = []
        for i in 0..<n {
            var score = 0.0
            if let k = mouseClassIndex { score = v(4 + k, i) } else { for k in 4..<c { score = max(score, v(k, i)) } }
            guard score >= rawConfidenceFloor else { continue }
            let cx = v(0, i), cy = v(1, i), w = v(2, i), h = v(3, i)
            out.append(DetBox(x0: cx - w / 2, y0: cy - h / 2, x1: cx + w / 2, y1: cy + h / 2, confidence: score))
        }
        return out
    }
}

// MARK: - Classical fallback

final class TSTClassicalDetector: TSTMouseDetecting, @unchecked Sendable {
    let name = "Classical (dark blob per chamber)"
    let mouseDark: Bool
    init(mouseDark: Bool) { self.mouseDark = mouseDark }
    func detect(_ frame: GrayImage, layout: ChamberLayout?) throws -> [DetBox] {
        guard let layout else { return [] }
        return ClassicalMouseDetector.detect(frame: frame, layout: layout, mouseDark: mouseDark)
    }
}

// MARK: - Model storage

enum TSTModelStore {
    static var importedURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MouseDetector.mlmodelc", isDirectory: true)
    }

    static var bundledURL: URL? { Bundle.main.url(forResource: "MouseDetector", withExtension: "mlmodelc") }

    static var hasImported: Bool { FileManager.default.fileExists(atPath: importedURL.path) }

    /// Imported model first (the lab's fine-tuned one), then the bundled starter model.
    static func loadYOLO() -> TSTYOLOMouseDetector? {
        if hasImported, let d = try? TSTYOLOMouseDetector(compiledModelURL: importedURL, name: "Imported model") { return d }
        if let b = bundledURL, let d = try? TSTYOLOMouseDetector(compiledModelURL: b, name: "Bundled starter model") { return d }
        return nil
    }

    /// Accepts .mlmodel, .mlpackage or an already compiled .mlmodelc.
    static func importModel(from url: URL) async throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try fm.copyItem(at: url, to: staging)
        let compiled: URL = staging.pathExtension == "mlmodelc" ? staging : try await MLModel.compileModel(at: staging)
        // make sure it loads before replacing the current model
        _ = try TSTYOLOMouseDetector(compiledModelURL: compiled, name: "check")
        if fm.fileExists(atPath: importedURL.path) { try fm.removeItem(at: importedURL) }
        try fm.moveItem(at: compiled, to: importedURL)
    }

    static func removeImported() { try? FileManager.default.removeItem(at: importedURL) }
}
