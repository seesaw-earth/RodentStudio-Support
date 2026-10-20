// PoseParadigms.swift — ported from RodentPose iOS 1.0 Paradigms.swift (OriginalAppSources): names, categories,
// setup tips, arena kinds, phases, calibration markers and default arena sizes of the 16 RodentPose paradigms.
// Descriptions, measure definitions and literature lists are not needed for calibration and are left out.
// Strings are bilingual L(en, zh); the English is the app's own EnglishTranslations.json.
// One place defines, for every paradigm: names, category, what is measured and why pose helps,
// setup hints, arena types, phases, markers to place, defaults and literature.

import Foundation

// MARK: - Arena kinds

enum ArenaKind: String, Codable, CaseIterable, Identifiable {
    case none, rectangle, circle, plusMaze, yMaze, tMaze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L("No calibration (pixels)", "不标定（像素）")
        case .rectangle: return L("Rectangular arena", "矩形场地")
        case .circle: return L("Circular arena", "圆形场地")
        case .plusMaze: return L("Plus maze", "十字迷宫")
        case .yMaze: return L("Y-maze", "Y 迷宫")
        case .tMaze: return L("T-maze", "T 迷宫")
        }
    }

    var symbol: String {
        switch self {
        case .none: return "viewfinder"
        case .rectangle: return "square.dashed"
        case .circle: return "circle.dashed"
        case .plusMaze: return "plus"
        case .yMaze: return "arrow.triangle.branch"
        case .tMaze: return "arrow.triangle.turn.up.right.diamond"
        }
    }

    /// Labels of the calibration handles for maze arenas.
    var mazeLabels: [String] {
        switch self {
        case .plusMaze: return ["C", "N", "E", "S", "W"]
        case .yMaze: return ["J", "A", "B", "C"]
        case .tMaze: return ["J", "S", "L", "R"]
        default: return []
        }
    }
}

// MARK: - Category

enum ParadigmCategory: String, CaseIterable, Codable, Identifiable {
    case social, navigation, anxiety, memory, motor, general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .social: return L("Social behavior", "社交行为")
        case .navigation: return L("Spatial navigation · Neural recording", "空间导航 · 神经记录")
        case .anxiety: return L("Anxiety and risk assessment", "焦虑与风险评估")
        case .memory: return L("Learning, memory and fear", "学习、记忆与恐惧")
        case .motor: return L("Motor function", "运动功能")
        case .general: return L("General", "通用")
        }
    }

    var english: String {
        switch self {
        case .social: return "Social behavior"
        case .navigation: return "Navigation & neural recording"
        case .anxiety: return "Anxiety & risk assessment"
        case .memory: return "Learning, memory & fear"
        case .motor: return "Motor function"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .social: return "person.2.fill"
        case .navigation: return "location.north.circle.fill"
        case .anxiety: return "exclamationmark.shield.fill"
        case .memory: return "brain.head.profile"
        case .motor: return "arrow.clockwise.circle.fill"
        case .general: return "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: - Supporting types

struct PhaseOption: Hashable, Identifiable {
    let key: String     // stored / exported (English)
    let title: String   // shown
    var id: String { key }
}

struct MarkerSpec: Hashable, Identifiable {
    let key: String
    let label: String
    let title: String
    var id: String { key }
}

// MARK: - Paradigm

enum Paradigm: String, CaseIterable, Codable, Identifiable {
    case threeChamber = "three_chamber"
    case socialInteraction = "social_interaction"
    case dyadicSocial = "dyadic_social"
    case headDirection = "head_direction"
    case spatialExploration = "spatial_exploration"
    case openField = "open_field"
    case elevatedPlusMaze = "elevated_plus_maze"
    case lightDark = "light_dark_box"
    case novelObject = "novel_object_recognition"
    case barnesMaze = "barnes_maze"
    case yMaze = "y_maze"
    case tMaze = "t_maze_vte"
    case fearConditioning = "fear_conditioning"
    case looming = "looming_escape"
    case rotation = "rotation"
    case poseOnly = "pose_only"

    var id: String { rawValue }

    /// Robust decoding: unknown ids from a newer build fall back to `.poseOnly`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Paradigm(rawValue: raw) ?? .poseOnly
    }

    static func inCategory(_ c: ParadigmCategory) -> [Paradigm] { allCases.filter { $0.category == c } }

    var category: ParadigmCategory {
        switch self {
        case .threeChamber, .socialInteraction, .dyadicSocial: return .social
        case .headDirection, .spatialExploration: return .navigation
        case .openField, .elevatedPlusMaze, .lightDark: return .anxiety
        case .novelObject, .barnesMaze, .yMaze, .tMaze, .fearConditioning, .looming: return .memory
        case .rotation: return .motor
        case .poseOnly: return .general
        }
    }

    var title: String {
        switch self {
        case .threeChamber: return L("Three-Chamber Sociability", "三箱社交")
        case .socialInteraction: return L("Social Interaction Test", "社交回避测试")
        case .dyadicSocial: return L("Dyadic Social Interaction", "双鼠社交互动")
        case .headDirection: return L("Head Direction", "头朝向")
        case .spatialExploration: return L("Spatial Exploration · Place Cells", "空间探索 · 位置细胞")
        case .openField: return L("Open Field", "旷场")
        case .elevatedPlusMaze: return L("Elevated Plus Maze", "高架十字迷宫")
        case .lightDark: return L("Light–Dark Box", "明暗箱")
        case .novelObject: return L("Novel Object Recognition", "新物体识别")
        case .barnesMaze: return L("Barnes Maze", "Barnes 迷宫")
        case .yMaze: return L("Y-Maze Spontaneous Alternation", "Y 迷宫自发交替")
        case .tMaze: return L("T-Maze · VTE", "T 迷宫 · VTE")
        case .fearConditioning: return L("Fear Conditioning", "恐惧条件化")
        case .looming: return L("Looming-Evoked Escape", "Looming 逃跑")
        case .rotation: return L("Rotational Behavior", "旋转行为")
        case .poseOnly: return L("Pose Data Only", "仅导出姿态")
        }
    }

    var englishName: String {
        switch self {
        case .threeChamber: return "Three-Chamber Sociability"
        case .socialInteraction: return "Social Interaction Test (CSDS)"
        case .dyadicSocial: return "Dyadic Social Interaction"
        case .headDirection: return "Head Direction"
        case .spatialExploration: return "Spatial Exploration (Place / Grid Cells)"
        case .openField: return "Open Field"
        case .elevatedPlusMaze: return "Elevated Plus Maze"
        case .lightDark: return "Light–Dark Box"
        case .novelObject: return "Novel Object Recognition"
        case .barnesMaze: return "Barnes Maze"
        case .yMaze: return "Y-Maze Spontaneous Alternation"
        case .tMaze: return "T-Maze Choice & VTE"
        case .fearConditioning: return "Fear Conditioning (Freezing)"
        case .looming: return "Looming Threat Escape"
        case .rotation: return "Rotation (unilateral lesion)"
        case .poseOnly: return "Pose Only"
        }
    }

    /// Short English label, also used in exported file names.
    var shortName: String {
        switch self {
        case .threeChamber: return "3CH"
        case .socialInteraction: return "SI"
        case .dyadicSocial: return "Dyad"
        case .headDirection: return "HD"
        case .spatialExploration: return "Place"
        case .openField: return "OF"
        case .elevatedPlusMaze: return "EPM"
        case .lightDark: return "LDB"
        case .novelObject: return "NOR"
        case .barnesMaze: return "Barnes"
        case .yMaze: return "YMaze"
        case .tMaze: return "VTE"
        case .fearConditioning: return "Fear"
        case .looming: return "Loom"
        case .rotation: return "Rotation"
        case .poseOnly: return "Pose"
        }
    }

    var symbol: String {
        switch self {
        case .threeChamber: return "rectangle.split.3x1"
        case .socialInteraction: return "person.fill.viewfinder"
        case .dyadicSocial: return "person.2"
        case .headDirection: return "location.north.circle"
        case .spatialExploration: return "map"
        case .openField: return "square.dashed"
        case .elevatedPlusMaze: return "plus"
        case .lightDark: return "circle.lefthalf.filled"
        case .novelObject: return "cube"
        case .barnesMaze: return "circle.dotted"
        case .yMaze: return "arrow.triangle.branch"
        case .tMaze: return "arrow.triangle.turn.up.right.diamond"
        case .fearConditioning: return "bolt.heart"
        case .looming: return "bird"
        case .rotation: return "arrow.clockwise.circle"
        case .poseOnly: return "point.3.connected.trianglepath.dotted"
        }
    }

    var setupTips: [String] {
        var tips = [L("Film from directly overhead, with the entire arena visible and uniform lighting.", "摄像头尽量正上方俯拍，画面包含整个场地，光照均匀")]
        switch self {
        case .threeChamber:
            tips += [L("Calibrate four corners and enter the three-chamber arena dimensions.", "标定四个角点并输入三箱内部尺寸"), L("Drag L / R handles to the centers of the two wire cups.", "把 L / R 手柄拖到两个铁丝杯的中心"), L("Select the side containing the stranger (or novel stranger) in parameters.", "在参数里选择陌生鼠（或新陌生鼠）所在的一侧")]
        case .socialInteraction:
            tips += [L("Calibrate the open-field corners and specify the enclosure wall.", "标定旷场四角，选择网罩靠在哪面墙"), L("Analyze target-absent and target-present phases separately under the same subject ID to pair results automatically.", "无目标、有目标两个阶段分别建立分析，编号相同即可自动配对")]
        case .dyadicSocial:
            tips += [L("When mice look alike, identities may swap after overlap; distinguish them by coat or safe marking when possible.", "两只鼠体色相同时，身体紧贴重叠后身份可能交换；建议毛色或标记区分"), L("Two-mouse detection is enabled automatically.", "识别时会自动开启双鼠模式")]
        case .headDirection:
            tips += [L("Optional: drag Q to a wall-mounted cue card to set the direction reference.", "可选：把 Q 手柄拖到墙上的提示卡，作为参考方向"), L("Align any recording-to-video timestamp offset yourself; CSV exports include frame timestamps.", "记录系统与视频的同步偏移需自行对齐（导出 CSV 含逐帧时间戳）")]
        case .spatialExploration:
            tips += [L("For long recordings, process every 2nd or 3rd frame to save time.", "长时间记录可在设置中选择每 2–3 帧识别一次，以节省时间")]
        case .openField:
            tips += [L("The default center region spans 50% of the arena side length; adjust in parameters.", "中央区默认为场地边长的 50%，可在参数中调整")]
        case .elevatedPlusMaze:
            tips += [L("Place C at the center and N / E / S / W at the four arm tips.", "依次拖动 C（中心）和 N / E / S / W 四个臂末端"), L("Select the open-arm axis (north–south or east–west).", "选择开放臂方向（南北或东西）"), L("Leave enough margin so the nose remains visible during head dips.", "四周留出空间，让探头时鼻尖仍在画面内")]
        case .lightDark:
            tips += [L("Calibrate the full chamber, then set the light compartment side and fraction.", "标定整个箱体，再设置明箱所在侧和所占比例")]
        case .novelObject:
            tips += [L("Drag A / B handles to object centers and set the object radius.", "把 A / B 手柄拖到两个物体中心，设置物体半径"), L("Specify which object is novel in the test phase.", "测试阶段选择哪个是新物体")]
        case .barnesMaze:
            tips += [L("Calibrate the platform with C (center) and R (edge).", "拖动 C（中心）和 R（边缘）标定平台"), L("Place T at the target hole; other holes are placed evenly according to the hole count.", "把 T 手柄拖到目标洞中心；其余洞按数量均匀排列")]
        case .yMaze:
            tips += [L("J marks the junction; A / B / C mark the three arm tips.", "J 为三臂交汇中心，A / B / C 为三个臂末端"), L("Enter arm length and width (cm).", "输入臂长和臂宽（cm）")]
        case .tMaze:
            tips += [L("J marks the choice point, S the start arm, and L / R the left and right arms.", "J 为选择点，S 为起始臂末端，L / R 为左右臂末端")]
        case .fearConditioning:
            tips += [L("Enter CS onset times (relative to video start) and durations.", "在参数里输入 CS 开始时间（相对于视频开头）和时长"), L("Infrared or grayscale recordings work best.", "红外或灰度视频效果最好")]
        case .looming:
            tips += [L("Drag S to the center of the shelter.", "把 S 手柄拖到巢穴（庇护所）中心"), L("Enter each stimulus onset time relative to video start.", "输入每次刺激出现的时间（相对于视频开头）")]
        case .rotation:
            tips += [L("Set the lesion side; enable “Filmed from below” if recorded through a transparent floor.", "选择损伤侧别；从透明底部仰拍时请打开“从下方拍摄”"), L("Report results in 5-minute bins.", "每 5 min 分段统计")]
        case .poseOnly:
            tips += [L("Without calibration, coordinates are pixels; calibration also provides centimeter coordinates.", "不标定时坐标为像素；标定后额外输出厘米坐标")]
        }
        return tips
    }

    var arenaKinds: [ArenaKind] {
        switch self {
        case .threeChamber, .socialInteraction, .lightDark, .fearConditioning: return [.rectangle]
        case .dyadicSocial, .headDirection, .spatialExploration, .openField, .novelObject, .looming: return [.rectangle, .circle]
        case .elevatedPlusMaze: return [.plusMaze]
        case .barnesMaze: return [.circle]
        case .yMaze: return [.yMaze]
        case .tMaze: return [.tMaze]
        case .rotation: return [.circle, .rectangle, .none]
        case .poseOnly: return [.none, .rectangle, .circle]
        }
    }

    var defaultArena: ArenaKind { arenaKinds[0] }

    var phases: [PhaseOption] {
        switch self {
        case .threeChamber:
            return [PhaseOption(key: "Sociability", title: L("Sociability", "社交偏好")), PhaseOption(key: "Social novelty", title: L("Social novelty", "社交新颖性")), PhaseOption(key: "Habituation", title: L("Habituation", "适应"))]
        case .socialInteraction:
            return [PhaseOption(key: "No target", title: L("Target absent", "无目标")), PhaseOption(key: "Target", title: L("Target present", "有目标"))]
        case .novelObject:
            return [PhaseOption(key: "Test", title: L("Test", "测试")), PhaseOption(key: "Training", title: L("Training", "训练"))]
        case .barnesMaze:
            return [PhaseOption(key: "Acquisition", title: L("Learning", "学习期")), PhaseOption(key: "Probe", title: L("Probe trial", "探索测试"))]
        case .fearConditioning:
            return [PhaseOption(key: "Cue test", title: L("Cued test", "线索测试")), PhaseOption(key: "Context test", title: L("Context test", "情境测试")), PhaseOption(key: "Training", title: L("Training", "训练"))]
        case .rotation:
            return [PhaseOption(key: "Apomorphine", title: L("Apomorphine", "阿扑吗啡")), PhaseOption(key: "Amphetamine", title: L("Amphetamine", "安非他明")), PhaseOption(key: "Spontaneous", title: L("Spontaneous", "自发")), PhaseOption(key: "Other", title: L("Other", "其他"))]
        default:
            return []
        }
    }

    func phaseTitle(_ key: String) -> String {
        phases.first { $0.key == key }?.title ?? key
    }

    /// Draggable markers placed on the calibration frame.
    var markers: [MarkerSpec] {
        switch self {
        case .threeChamber: return [MarkerSpec(key: "cupL", label: "L", title: L("Left cup", "左杯")), MarkerSpec(key: "cupR", label: "R", title: L("Right cup", "右杯"))]
        case .novelObject: return [MarkerSpec(key: "objA", label: "A", title: L("Object A", "物体 A")), MarkerSpec(key: "objB", label: "B", title: L("Object B", "物体 B"))]
        case .barnesMaze: return [MarkerSpec(key: "target", label: "T", title: L("Target hole", "目标洞"))]
        case .looming: return [MarkerSpec(key: "shelter", label: "S", title: L("Shelter", "巢穴"))]
        case .headDirection: return [MarkerSpec(key: "cue", label: "Q", title: L("Cue card", "提示卡"))]
        default: return []
        }
    }

    /// Number of animals tracked per frame.
    var animalCount: Int { self == .dyadicSocial ? 2 : 1 }

    /// Metric shown in lists and highlighted on the result screen.
    var primaryMetricKey: String {
        switch self {
        case .threeChamber: return "sniff_index"
        case .socialInteraction: return "iz_time"
        case .dyadicSocial: return "social_total"
        case .headDirection: return "hd_coverage"
        case .spatialExploration: return "coverage"
        case .openField: return "center_pct"
        case .elevatedPlusMaze: return "open_time_pct"
        case .lightDark: return "light_pct"
        case .novelObject: return "di"
        case .barnesMaze: return "primary_latency"
        case .yMaze: return "alternation_pct"
        case .tMaze: return "vte_pct"
        case .fearConditioning: return "freeze_cs_mean"
        case .looming: return "escape_pct"
        case .rotation: return "net_per_min"
        case .poseOnly: return "detection_rate"
        }
    }

    /// Default arena size (cm) for a new session.
    var defaultArenaSize: (width: Double, height: Double) {
        switch self {
        case .threeChamber: return (60, 40)
        case .socialInteraction: return (42, 42)
        case .dyadicSocial: return (40, 40)
        case .headDirection, .spatialExploration: return (50, 50)
        case .openField, .novelObject: return (40, 40)
        case .lightDark: return (45, 30)
        case .fearConditioning: return (30, 24)
        case .looming: return (48, 48)
        case .barnesMaze: return (92, 92)
        case .rotation: return (30, 30)
        case .elevatedPlusMaze: return (30, 5)   // arm length × arm width
        case .yMaze: return (35, 5)
        case .tMaze: return (30, 8)
        case .poseOnly: return (40, 40)
        }
    }
}
