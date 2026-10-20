import Foundation
import CoreML

// The first migration build deliberately ships without any model weights.
// Add models to the Xcode target later as .mlpackage; Xcode compiles them to .mlmodelc.
enum PoseModelKind: String, CaseIterable, Identifiable {
    case mousePose = "MousePose6_960_int8"
    case cylinderV2 = "CylinderMousePoseV2"
    var id: String { rawValue }
}

enum NativeModelCatalog {
    static func available(_ kind: PoseModelKind) -> Bool {
        Bundle.main.url(forResource: kind.rawValue, withExtension: "mlmodelc") != nil
    }

    static func load(_ kind: PoseModelKind) throws -> MLModel {
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "mlmodelc") else {
            throw NSError(domain: "RodentDesktopNative", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Model \(kind.rawValue) is not installed."])
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: config)
    }
}
