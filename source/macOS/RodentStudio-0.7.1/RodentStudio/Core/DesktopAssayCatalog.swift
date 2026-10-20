import Foundation

/// Video-only desktop catalog. RodentFlow manual/table assays intentionally excluded. Stable IDs must not be reused
/// for different algorithms even when two apps have the same assay display name.
struct DesktopAssayDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let module: String
    let modality: String
    let availability: String
}

enum DesktopAssayCatalog {
    static let all: [DesktopAssayDescriptor] = [
        .init(id: "rodentpose.three_chamber", name: "Three-Chamber Social Test", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.social_interaction", name: "Social Interaction", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.dyadic_social", name: "Dyadic Social", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Single-animal tracking only; the two-animal analysis is not available on the desktop"),
        .init(id: "rodentpose.head_direction", name: "Head Direction", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.spatial_exploration", name: "Spatial Exploration", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.open_field", name: "Open Field", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.epm", name: "Elevated Plus Maze", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.light_dark_box", name: "Light–Dark Box", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.nor", name: "Novel Object Recognition", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.barnes_maze", name: "Barnes Maze", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.y_maze", name: "Y-Maze", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.t_maze_vte", name: "T-Maze with VTE", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.fear_conditioning", name: "Fear Conditioning", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.looming_escape", name: "Looming Escape", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.rotation", name: "Rotation", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentpose.pose_only", name: "Pose Tracking Only", module: "RodentPose", modality: "Pose + 6 keypoint", availability: "Core ML tracking + RodentPose 1.0 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentlimb.cylinder", name: "Cylinder Test", module: "RodentLimb", modality: "Limb + 7 keypoint", availability: "Core ML tracking + RodentLimb 1.1.2 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentlimb.tail_suspension", name: "Tail Suspension", module: "RodentLimb", modality: "Limb + 7 keypoint", availability: "Core ML tracking + RodentLimb 1.1.2 analyzers (desktop port, iOS parity pending)"),
        .init(id: "tstscorer.multi_chamber", name: "Tail Suspension Test — Multi-Chamber", module: "RodentStudio", modality: "Multi-chamber silhouette analysis", availability: "TSTScorer 6 key-frame + per-chamber pixel/contour motion scoring (manual validation pending)"),
        .init(id: "rodentlimb.gait", name: "Gait", module: "RodentLimb", modality: "Limb + 7 keypoint", availability: "Core ML tracking + RodentLimb 1.1.2 analyzers (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.open_field", name: "Open Field / Center", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.elevated_plus_maze", name: "Elevated Plus Maze", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.light_dark_box", name: "Light–Dark Box", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.y_maze", name: "Y-Maze", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.t_maze", name: "T-Maze", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.novel_object_recognition", name: "Novel Object Recognition", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.morris_water_maze", name: "Morris Water Maze", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.barnes_maze", name: "Barnes Maze", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.fear_conditioning", name: "Fear Conditioning", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
        .init(id: "rodentflow.conditioned_place_preference", name: "Conditioned Place Preference", module: "RodentFlow", modality: "Classic centroid video", availability: "RodentFlow 1.3 classic centroid tracker + AssayEngine (desktop port, iOS parity pending)"),
    ]
    static func lookup(_ id: String) -> DesktopAssayDescriptor? { all.first { $0.id == id } }

    /// What the desktop app can do for a task today, in the interface language.
    static func availabilityText(_ assay: StudyAssay) -> String {
        switch assay.module {
        case .pose?:
            if assay == .poseDyadicSocial {
                return L("Single-animal tracking only; the two-animal analysis is not available on the desktop",
                         "仅单鼠追踪；桌面版暂不支持双鼠分析")
            }
            return L("Pose tracking, RodentPose calibration and original analyzers with figures (desktop port, iOS parity pending)",
                     "姿态追踪、RodentPose 标定和原版分析与图表（桌面移植，尚待与 iOS 对照）")
        case .limb?:
            return L("Pose tracking, RodentLimb calibration and original analyzers with figures (desktop port, iOS parity pending)",
                     "姿态追踪、RodentLimb 标定和原版分析与图表（桌面移植，尚待与 iOS 对照）")
        case .flow?:
            return L("RodentFlow setup and calibration, classic centroid tracker and original AssayEngine with figures (desktop port, iOS parity pending)",
                     "RodentFlow 设置与标定、经典质心追踪和原版 AssayEngine 与图表（桌面移植，尚待与 iOS 对照）")
        case nil:
            return assay.statusLabel
        }
    }
    static var families: [String] { ["RodentPose", "RodentLimb", "RodentFlow", "RodentStudio"] }
}
