import SwiftUI
import AppKit
import AVFoundation
import CoreML
import Vision
import UniformTypeIdentifiers

/// A one-frame integration check only. It does NOT generate verified scientific tracks.
/// iOS preprocessing / source-video orientation / multi-frame parity remain unverified.
struct ModelInferenceCheckView: View {
    @State private var selection: PoseModelKind = .mousePose
    @State private var outputMessage = L("Choose a bundled model and one test video.", "请选择一个已打包的模型和一段测试视频。")
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(L("Core ML model / video smoke test", "Core ML 模型 / 视频冒烟测试")).font(.headline)
            Text(L("Check that an actual video frame reaches the Core ML model and returns a tensor. This does not perform pose decoding or research scoring.", "检查真实视频帧能否送入 Core ML 模型并返回张量。不做姿态解码，也不做研究评分。"))
                .font(.callout).foregroundStyle(.secondary)
            Picker(L("Model", "模型"), selection: $selection) {
                ForEach(PoseModelKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Text(NativeModelCatalog.available(selection) ? L("Model bundled", "模型已打包") : L("Model missing from App Bundle", "App 包中缺少模型"))
                    .foregroundStyle(NativeModelCatalog.available(selection) ? Color.green : Color.orange)
                Button(isRunning ? L("Running…", "正在运行…") : L("Test one video frame…", "测试一帧视频…")) { testOneFrame() }
                    .disabled(isRunning || !NativeModelCatalog.available(selection))
            }
            Text(outputMessage)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func testOneFrame() {
        let panel = NSOpenPanel()
        panel.message = L("Select a short mouse video for a one-frame Core ML test", "选择一段小鼠短视频做单帧 Core ML 测试")
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let chosen = selection
        isRunning = true
        outputMessage = L("Loading model and first video frame…", "正在加载模型和第一帧…")
        // Work off the main thread so large models do not freeze the interface.
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let ml = try NativeModelCatalog.load(chosen)
                let description = ml.modelDescription
                let inputs = description.inputDescriptionsByName.map { key, feature in
                    "\(key): \(feature.type.rawValue)"
                }.sorted().joined(separator: ", ")
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
                let request = VNCoreMLRequest(model: try VNCoreMLModel(for: ml))
                request.imageCropAndScaleOption = .scaleFit
                try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
                let outputs = (request.results ?? []).compactMap { $0 as? VNCoreMLFeatureValueObservation }
                let info = outputs.map { obs -> String in
                    if let tensor = obs.featureValue.multiArrayValue {
                        return "\(obs.featureName): \(tensor.shape.map { $0.intValue })"
                    }
                    return "\(obs.featureName): not a multi-array"
                }
                guard !outputs.isEmpty else {
                    throw NSError(domain: "RodentDesktop", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Core ML feature-value output. Inspect Xcode model Predictions."])
                }
                let report = "SUCCESS · \(chosen.rawValue)\nInput: \(inputs)\nFrame: \(cg.width)×\(cg.height)\nOutputs:\n\(info.joined(separator: "\n"))"
                DispatchQueue.main.async { outputMessage = report; isRunning = false }
            } catch {
                DispatchQueue.main.async {
                    outputMessage = "FAILED · \(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }
}
