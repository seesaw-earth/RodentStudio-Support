// Paradigms.swift — catalog of behavioral paradigms that benefit from keypoint (pose) data.
// One place defines, for every paradigm: names, category, what is measured and why pose helps,
// setup hints, arena types, phases, markers to place, defaults and literature.

import Foundation

// MARK: - Arena kinds

enum ArenaKind: String, Codable, CaseIterable, Identifiable {
    case none, rectangle, circle, plusMaze, yMaze, tMaze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L10n.tr("不标定（像素）")
        case .rectangle: return L10n.tr("矩形场地")
        case .circle: return L10n.tr("圆形场地")
        case .plusMaze: return L10n.tr("十字迷宫")
        case .yMaze: return L10n.tr("Y 迷宫")
        case .tMaze: return L10n.tr("T 迷宫")
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
        case .social: return L10n.tr("社交行为")
        case .navigation: return L10n.tr("空间导航 · 神经记录")
        case .anxiety: return L10n.tr("焦虑与风险评估")
        case .memory: return L10n.tr("学习、记忆与恐惧")
        case .motor: return L10n.tr("运动功能")
        case .general: return L10n.tr("通用")
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

struct MeasureInfo: Hashable {
    let name: String
    let definition: String
}

struct PaperRef: Hashable {
    let citation: String
    let doi: String?

    var url: URL? { doi.flatMap { URL(string: "https://doi.org/\($0)") } }
}

struct PhaseOption: Hashable, Identifiable {
    let key: String     // stored / exported (English for presets, verbatim for the user's own labels)
    let title: String   // shown
    var id: String { key }
}

/// The researcher's own phase / condition labels per paradigm (e.g. "Day 1", "Baseline", or any
/// experimental condition), offered next to the presets. Stored on this device only.
enum PhaseLibrary {
    static let maxCount = 24
    static let maxLength = 40

    private static func key(_ p: Paradigm) -> String { "customPhases." + p.rawValue }

    static func labels(for p: Paradigm) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(p)) ?? []
    }

    /// Cleans a typed label; nil when nothing usable is left.
    static func clean(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxLength))
    }

    static func add(_ label: String, for p: Paradigm) {
        var list = labels(for: p)
        guard !list.contains(label), !p.isPresetPhase(label) else { return }
        list.append(label)
        UserDefaults.standard.set(Array(list.suffix(maxCount)), forKey: key(p))
    }

    static func remove(_ label: String, for p: Paradigm) {
        let list = labels(for: p).filter { $0 != label }
        UserDefaults.standard.set(list, forKey: key(p))
    }
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
        case .threeChamber: return L10n.tr("三箱社交")
        case .socialInteraction: return L10n.tr("社交回避测试")
        case .dyadicSocial: return L10n.tr("双鼠社交互动")
        case .headDirection: return L10n.tr("头朝向")
        case .spatialExploration: return L10n.tr("空间探索 · 位置细胞")
        case .openField: return L10n.tr("旷场")
        case .elevatedPlusMaze: return L10n.tr("高架十字迷宫")
        case .lightDark: return L10n.tr("明暗箱")
        case .novelObject: return L10n.tr("新物体识别")
        case .barnesMaze: return L10n.tr("Barnes 迷宫")
        case .yMaze: return L10n.tr("Y 迷宫自发交替")
        case .tMaze: return L10n.tr("T 迷宫 · VTE")
        case .fearConditioning: return L10n.tr("恐惧条件化")
        case .looming: return L10n.tr("Looming 逃跑")
        case .rotation: return L10n.tr("旋转行为")
        case .poseOnly: return L10n.tr("仅导出姿态")
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

    var tagline: String {
        switch self {
        case .threeChamber: return L10n.tr("社交偏好与社交新颖性 · 鼻尖嗅探判定")
        case .socialInteraction: return L10n.tr("慢性社会挫败后的社交回避 · SI ratio")
        case .dyadicSocial: return L10n.tr("两只自由活动小鼠 · 鼻对鼻、肛殖区嗅探、跟随")
        case .headDirection: return L10n.tr("HD 细胞记录配套 · 头朝向占据与角速度")
        case .spatialExploration: return L10n.tr("占据图、覆盖度与速度 · 神经记录同步")
        case .openField: return L10n.tr("运动与焦虑样行为 · 中央区、转圈、静止")
        case .elevatedPlusMaze: return L10n.tr("开放臂探索 + 探头 + 伸展评估姿势")
        case .lightDark: return L10n.tr("明箱时间、穿梭 + 探头风险评估")
        case .novelObject: return L10n.tr("鼻尖距离 + 朝向判定探索 · 辨别指数")
        case .barnesMaze: return L10n.tr("以鼻尖探洞计错误数 · 潜伏期与路径")
        case .yMaze: return L10n.tr("工作记忆 · 交替率与探头未进入")
        case .tMaze: return L10n.tr("选择点头部扫视（替代性试错）")
        case .fearConditioning: return L10n.tr("关键点僵直检测 · 按 CS 分段")
        case .looming: return L10n.tr("头顶扩张黑影 → 逃回巢穴或僵直")
        case .rotation: return L10n.tr("单侧损伤模型 · 同侧 / 对侧整圈数")
        case .poseOnly: return L10n.tr("逐帧 6 个关键点 + 运动学 · 自定义分析")
        }
    }

    var summary: String {
        switch self {
        case .threeChamber:
            return L10n.tr("实验鼠在三个相连的箱室中自由探索，两侧各放一个铁丝杯。社交偏好阶段一侧杯内是陌生鼠，另一侧为空杯或物体；社交新颖性阶段一侧是熟悉鼠，另一侧换成新的陌生鼠。经典读数是各箱室的停留时间和对两个杯子的嗅探时间。")
        case .socialInteraction:
            return L10n.tr("慢性社会挫败应激（CSDS）模型的标准读数。实验鼠在旷场中探索两次，每次 150 s：第一次网罩内为空（无目标），第二次放入陌生的攻击鼠（有目标）。比较两次在网罩周围互动区的停留时间，SI ratio < 1 通常归为易感。")
        case .dyadicSocial:
            return L10n.tr("两只小鼠在同一场地自由互动，例如青少年社交、居住者-入侵者测试中的非攻击部分、雌雄互动。读数是各类嗅探与跟随行为的时间和次数。")
        case .headDirection:
            return L10n.tr("记录头朝向细胞（ADN、后下托、压后皮层等）时，需要每一帧动物头部在环境中的朝向，以及每个方向上的停留时间（占据），用来归一化调谐曲线；角速度（AHV）用于分析 AHV 细胞和调谐的速度依赖性。")
        case .spatialExploration:
            return L10n.tr("位置细胞、网格细胞记录通常让动物在开放场地中觅食数十分钟。分析放电野之前要先看占据是否均匀、覆盖度是否足够，并按速度阈值（如 > 2 cm/s）去掉静止时段。")
        case .openField:
            return L10n.tr("最常用的自发活动与焦虑样行为测试：动物在方形或圆形场地中自由探索 5–30 min，读数包括总路程、中央区时间和进入次数。")
        case .elevatedPlusMaze:
            return L10n.tr("两条开放臂与两条闭合臂交叉的高架迷宫，通常测 5 min。开放臂时间和进入次数比例越低，焦虑样行为越强。")
        case .lightDark:
            return L10n.tr("明亮的大箱与黑暗的小箱通过小门相连，测 5–10 min。明箱时间和穿梭次数反映焦虑样行为。")
        case .novelObject:
            return L10n.tr("训练期探索两个相同物体，间隔一段时间后把其中一个换成新物体。啮齿类天生偏好新物体，辨别指数 DI 反映识别记忆。移动物体位置即为物体位置记忆（OLM）。")
        case .barnesMaze:
            return L10n.tr("圆形平台边缘有一圈洞，只有目标洞下有逃逸箱。动物借助墙上的空间线索学习目标位置。读数为找到目标洞的潜伏期、错误数和路径长度；探索测试中看目标象限时间。")
        case .yMaze:
            return L10n.tr("三条臂互成 120°，动物自由探索约 8 min。连续三次进入三条不同的臂记为一次交替，交替率 = 交替次数 ÷（总进入次数 − 2）。")
        case .tMaze:
            return L10n.tr("动物在选择点停下，头部在两侧之间来回摆动，称为替代性试错（VTE），反映决策时的权衡。经典量化方法是通过选择点时朝向的累计绝对变化 IdPhi，并在每次会话内做 z 标准化。")
        case .fearConditioning:
            return L10n.tr("声音（CS）与足底电击配对后，在相同情境或新情境中重放 CS，测量僵直（除呼吸外完全不动）所占的百分比。")
        case .looming:
            return L10n.tr("动物头顶的屏幕呈现快速扩大的黑色圆盘（模拟俯冲的捕食者），小鼠通常在一秒内逃回庇护所或原地僵直。读数是反应潜伏期、是否逃回巢穴、逃跑速度和僵直。")
        case .rotation:
            return L10n.tr("单侧损伤或其他单侧操作后，动物常表现出偏向一侧的旋转。按身体轴向统计同侧与对侧整圈数，净旋转数用于量化左右不对称的程度，或比较不同实验条件。")
        case .poseOnly:
            return L10n.tr("不做范式分析，只输出逐帧关键点和派生运动学（速度、头朝向、身体轴向等），用于自己的分析流程（如 Keypoint-MoSeq、B-SOiD、SimBA）。")
        }
    }

    var whyPose: String {
        switch self {
        case .threeChamber:
            return L10n.tr("质心追踪只能判断动物在哪个箱室。真正的社交接触是鼻尖贴近杯子并朝向它。RodentStudio 用鼻尖到杯子的距离加头朝向判定嗅探，并排除爬到杯子上的帧，更接近人工计分。")
        case .socialInteraction:
            return L10n.tr("除了身体中心在互动区的时间，RodentStudio 还给出鼻尖在网罩附近的嗅探时间，帮助区分主动探索和路过；同一只鼠的两个阶段会自动配对，计算 SI ratio。")
        case .dyadicSocial:
            return L10n.tr("社交接触由身体部位之间的距离定义：鼻尖–鼻尖、鼻尖–尾根（肛殖区）、鼻尖–身体。这需要每只鼠的多个关键点，用质心无法区分。")
        case .headDirection:
            return L10n.tr("传统方法要在头上装两个 LED。RodentStudio 用两耳中点 → 鼻尖的向量估计头朝向（鼻尖缺失时用颈部 → 鼻尖），不需要标记物，并输出带时间戳的逐帧 HD 和 AHV，可直接与电生理或钙成像数据对齐。")
        case .spatialExploration:
            return L10n.tr("身体中心比质心更稳定（不受尾巴影响），同时还能得到头朝向，便于做位置 × 方向的联合分析。逐帧导出位置、速度和 HD。")
        case .openField:
            return L10n.tr("用身体中心代替质心（不受尾巴影响），另外还能得到按身体轴向计的转圈数、静止时间和身体伸展程度。")
        case .elevatedPlusMaze:
            return L10n.tr("风险评估行为——探头（头伸出开放臂边缘向下看）和伸展评估姿势（身体拉长、后肢不动地向前探）——能提供开放臂时间之外的信息，但只能靠鼻尖位置和身体长度来判断。")
        case .lightDark:
            return L10n.tr("身体留在暗箱、只把头伸进明箱的“探头”是典型的风险评估行为，需要把鼻尖和身体分开判断。")
        case .novelObject:
            return L10n.tr("公认的“探索”定义是鼻尖距物体 ≤ 2 cm 且头朝向物体，爬到物体上或背对物体坐着都不算。质心半径法会把路过和坐在旁边也算进去。")
        case .barnesMaze:
            return L10n.tr("Barnes 迷宫的“错误”定义是把鼻子探进非目标洞，这是鼻尖行为，质心追踪无法计数。")
        case .yMaze:
            return L10n.tr("标准规定四爪都进入臂才算一次进入。RodentStudio 默认要求身体中心和尾根都在臂内（近似四爪进入），并单独统计“只探头、未进入”。")
        case .tMaze:
            return L10n.tr("VTE 本质是头部扫视。RodentStudio 直接用头朝向计算 IdPhi，同时给出基于运动轨迹方向的 IdPhi 作为对照，并统计左右选择与交替。")
        case .fearConditioning:
            return L10n.tr("运动像素法会把呼吸、光照闪烁和相机噪声也算进去。RodentStudio 用鼻尖、两耳中点、身体中心和尾根在 0.5 s 窗口内的位移速度判断僵直，头部的小动作（嗅探、扫视）不会被误判为僵直。")
        case .looming:
            return L10n.tr("刺激出现时的头朝向和到巢穴的方向决定了逃跑路径，是这个范式的重要协变量。RodentStudio 给出每次刺激时头部与巢穴方向的夹角。")
        case .rotation:
            return L10n.tr("旋转计数需要身体轴向（尾根 → 颈部）。RodentStudio 对轴向角度累计计数完整的 360° 转圈，原地小转也能计入，不需要旋转计。")
        case .poseOnly:
            return L10n.tr("保留原始逐帧关键点（像素坐标、置信度），同时附带标定后的厘米坐标和派生特征。")
        }
    }

    var setupTips: [String] {
        var tips = [L10n.tr("摄像头尽量正上方俯拍，画面包含整个场地，光照均匀")]
        switch self {
        case .threeChamber:
            tips += [L10n.tr("标定四个角点并输入三箱内部尺寸"), L10n.tr("把 L / R 手柄拖到两个铁丝杯的中心"), L10n.tr("在参数里选择陌生鼠（或新陌生鼠）所在的一侧")]
        case .socialInteraction:
            tips += [L10n.tr("标定旷场四角，选择网罩靠在哪面墙"), L10n.tr("无目标、有目标两个阶段分别建立分析，编号相同即可自动配对")]
        case .dyadicSocial:
            tips += [L10n.tr("两只鼠体色相同时，身体紧贴重叠后身份可能交换；建议毛色或标记区分"), L10n.tr("识别时会自动开启双鼠模式")]
        case .headDirection:
            tips += [L10n.tr("可选：把 Q 手柄拖到墙上的提示卡，作为参考方向"), L10n.tr("记录系统与视频的同步偏移需自行对齐（导出 CSV 含逐帧时间戳）")]
        case .spatialExploration:
            tips += [L10n.tr("长时间记录可在设置中选择每 2–3 帧识别一次，以节省时间")]
        case .openField:
            tips += [L10n.tr("中央区默认为场地边长的 50%，可在参数中调整")]
        case .elevatedPlusMaze:
            tips += [L10n.tr("依次拖动 C（中心）和 N / E / S / W 四个臂末端"), L10n.tr("选择开放臂方向（南北或东西）"), L10n.tr("四周留出空间，让探头时鼻尖仍在画面内")]
        case .lightDark:
            tips += [L10n.tr("标定整个箱体，再设置明箱所在侧和所占比例")]
        case .novelObject:
            tips += [L10n.tr("把 A / B 手柄拖到两个物体中心，设置物体半径"), L10n.tr("测试阶段选择哪个是新物体")]
        case .barnesMaze:
            tips += [L10n.tr("拖动 C（中心）和 R（边缘）标定平台"), L10n.tr("把 T 手柄拖到目标洞中心；其余洞按数量均匀排列")]
        case .yMaze:
            tips += [L10n.tr("J 为三臂交汇中心，A / B / C 为三个臂末端"), L10n.tr("输入臂长和臂宽（cm）")]
        case .tMaze:
            tips += [L10n.tr("J 为选择点，S 为起始臂末端，L / R 为左右臂末端")]
        case .fearConditioning:
            tips += [L10n.tr("在参数里输入 CS 开始时间（相对于视频开头）和时长"), L10n.tr("红外或灰度视频效果最好")]
        case .looming:
            tips += [L10n.tr("把 S 手柄拖到巢穴（庇护所）中心"), L10n.tr("输入每次刺激出现的时间（相对于视频开头）")]
        case .rotation:
            tips += [L10n.tr("选择损伤侧别；从透明底部仰拍时请打开“从下方拍摄”"), L10n.tr("每 5 min 分段统计"), L10n.tr("实验条件可在“信息”页用 + 添加为自定义标签")]
        case .poseOnly:
            tips += [L10n.tr("不标定时坐标为像素；标定后额外输出厘米坐标")]
        }
        return tips
    }

    var measures: [MeasureInfo] {
        switch self {
        case .threeChamber:
            return [
                MeasureInfo(name: L10n.tr("箱室停留时间"), definition: L10n.tr("身体中心所在箱室（左 / 中 / 右）的累计时间与进入次数。")),
                MeasureInfo(name: L10n.tr("嗅探时间"), definition: L10n.tr("鼻尖在杯子外缘 2 cm 以内、头朝向杯子（±45°），且身体中心不在杯子上。")),
                MeasureInfo(name: L10n.tr("社交指数"), definition: L10n.tr("(社交 − 物体) ÷ (社交 + 物体)，按嗅探时间计算；新颖性阶段为 (新 − 熟悉) ÷ (新 + 熟悉)。")),
                MeasureInfo(name: L10n.tr("潜伏期与次数"), definition: L10n.tr("首次嗅探每个杯子的时间、嗅探回合数。"))
            ]
        case .socialInteraction:
            return [
                MeasureInfo(name: L10n.tr("互动区时间"), definition: L10n.tr("身体中心在网罩周围互动区（默认 26 × 14 cm）内的时间。")),
                MeasureInfo(name: L10n.tr("角落区时间"), definition: L10n.tr("身体中心在网罩对侧两个角落区（默认 9 × 9 cm）内的时间。")),
                MeasureInfo(name: "SI ratio", definition: L10n.tr("有目标阶段互动区时间 ÷ 无目标阶段互动区时间（同一编号自动配对）。")),
                MeasureInfo(name: L10n.tr("嗅探网罩"), definition: L10n.tr("鼻尖在网罩外缘 2 cm 以内并朝向网罩的时间。"))
            ]
        case .dyadicSocial:
            return [
                MeasureInfo(name: L10n.tr("鼻–鼻接触"), definition: L10n.tr("两只鼠鼻尖距离 < 2.5 cm。")),
                MeasureInfo(name: L10n.tr("肛殖区嗅探"), definition: L10n.tr("一只鼠的鼻尖到另一只鼠尾根 < 2.5 cm（A→B、B→A 分开统计）。")),
                MeasureInfo(name: L10n.tr("身体嗅探"), definition: L10n.tr("鼻尖到对方身体中心 < 3 cm，且不属于上面两类。")),
                MeasureInfo(name: L10n.tr("跟随"), definition: L10n.tr("间距 < 15 cm，两鼠速度都 > 5 cm/s，跟随者朝向对方（±45°）且持续 ≥ 0.5 s。")),
                MeasureInfo(name: L10n.tr("间距"), definition: L10n.tr("身体中心距离的平均值，以及 < 10 cm 的近距离时间。"))
            ]
        case .headDirection:
            return [
                MeasureInfo(name: L10n.tr("头朝向 HD"), definition: L10n.tr("两耳中点 → 鼻尖向量的方向；0° = 画面右方（或提示卡方向），逆时针为正。")),
                MeasureInfo(name: L10n.tr("HD 占据"), definition: L10n.tr("每 6° 一格的停留时间，用于归一化调谐曲线。")),
                MeasureInfo(name: L10n.tr("方向覆盖度"), definition: L10n.tr("停留时间 ≥ 1 s 的方向格所占比例。")),
                MeasureInfo(name: L10n.tr("占据平均向量长度"), definition: L10n.tr("HD 占据分布的平均向量长度，越接近 0 越均匀；偏大时调谐曲线容易受采样偏差影响。")),
                MeasureInfo(name: L10n.tr("角速度 AHV"), definition: L10n.tr("头朝向对时间的导数（°/s），以及顺 / 逆时针转头时间。"))
            ]
        case .spatialExploration:
            return [
                MeasureInfo(name: L10n.tr("占据图"), definition: L10n.tr("身体中心在每个 2.5 cm 方格中的停留时间。")),
                MeasureInfo(name: L10n.tr("覆盖度"), definition: L10n.tr("停留 ≥ 0.2 s 的方格占场地方格的比例，以及随时间的增长曲线。")),
                MeasureInfo(name: L10n.tr("运动时间"), definition: L10n.tr("速度 > 2 cm/s 的时间比例（放电野分析常用的速度筛选）。")),
                MeasureInfo(name: L10n.tr("路程与速度"), definition: L10n.tr("总路程、平均运动速度、速度分布。"))
            ]
        case .openField:
            return [
                MeasureInfo(name: L10n.tr("总路程与速度"), definition: L10n.tr("身体中心的移动距离（m）和平均速度。")),
                MeasureInfo(name: L10n.tr("中央区"), definition: L10n.tr("中央区时间 %、进入次数、首次进入潜伏期。")),
                MeasureInfo(name: L10n.tr("静止"), definition: L10n.tr("关键点运动 < 1 cm/s 持续 ≥ 1 s 的时间。")),
                MeasureInfo(name: L10n.tr("转圈"), definition: L10n.tr("按身体轴向累计的完整顺时针 / 逆时针转圈数。"))
            ]
        case .elevatedPlusMaze:
            return [
                MeasureInfo(name: L10n.tr("开放臂时间 %"), definition: L10n.tr("开放臂时间 ÷（开放臂 + 闭合臂时间）。")),
                MeasureInfo(name: L10n.tr("开放臂进入 %"), definition: L10n.tr("开放臂进入 ÷ 总进入；默认身体中心和尾根都进入臂才算。")),
                MeasureInfo(name: L10n.tr("探头"), definition: L10n.tr("鼻尖伸出开放臂边缘且身体仍在迷宫上（≥ 0.2 s）；身体在中央区或闭合臂时为受保护探头。")),
                MeasureInfo(name: L10n.tr("伸展评估姿势 SAP"), definition: L10n.tr("身体长度 ≥ 中位数的 1.2 倍且身体中心速度 < 5 cm/s，持续 ≥ 0.5 s。"))
            ]
        case .lightDark:
            return [
                MeasureInfo(name: L10n.tr("明箱时间 %"), definition: L10n.tr("身体中心在明箱内的时间比例。")),
                MeasureInfo(name: L10n.tr("穿梭次数"), definition: L10n.tr("身体中心在明暗箱之间的穿越次数。")),
                MeasureInfo(name: L10n.tr("潜伏期"), definition: L10n.tr("首次进入明箱、首次进入暗箱的时间。")),
                MeasureInfo(name: L10n.tr("探头"), definition: L10n.tr("鼻尖进入明箱而身体中心和尾根仍在暗箱，持续 ≥ 0.2 s。"))
            ]
        case .novelObject:
            return [
                MeasureInfo(name: L10n.tr("探索时间"), definition: L10n.tr("鼻尖在物体外缘 2 cm 以内、头朝向物体（±45°），且身体中心不在物体上。")),
                MeasureInfo(name: L10n.tr("辨别指数 DI"), definition: L10n.tr("(新 − 旧) ÷ (新 + 旧)；训练阶段为 (B − A) ÷ (B + A)，用来检查位置偏好。")),
                MeasureInfo(name: L10n.tr("识别指数 RI"), definition: L10n.tr("新 ÷ (新 + 旧) × 100%。")),
                MeasureInfo(name: L10n.tr("20 s 标准"), definition: L10n.tr("累计探索达到 20 s 的时间，以及达到时的 DI。"))
            ]
        case .barnesMaze:
            return [
                MeasureInfo(name: L10n.tr("首次潜伏期"), definition: L10n.tr("鼻尖首次探入目标洞的时间。")),
                MeasureInfo(name: L10n.tr("错误数"), definition: L10n.tr("鼻尖探入非目标洞的次数：首次找到目标前的为首次错误，全程的为总错误。")),
                MeasureInfo(name: L10n.tr("路径长度"), definition: L10n.tr("首次找到目标洞之前身体中心的移动距离。")),
                MeasureInfo(name: L10n.tr("目标象限"), definition: L10n.tr("以目标洞为中心 ±45° 扇区内的时间比例（探索测试）。"))
            ]
        case .yMaze:
            return [
                MeasureInfo(name: L10n.tr("交替率"), definition: L10n.tr("连续三次进入三条不同臂的次数 ÷（总进入次数 − 2）。")),
                MeasureInfo(name: L10n.tr("进入次数"), definition: L10n.tr("默认身体中心和尾根都在臂内才算一次进入。")),
                MeasureInfo(name: L10n.tr("探头未进入"), definition: L10n.tr("鼻尖进入某臂但身体没有进入就退回。"))
            ]
        case .tMaze:
            return [
                MeasureInfo(name: "IdPhi", definition: L10n.tr("每次从起始臂经过选择点进入左 / 右臂期间，头朝向变化绝对值的累计（°）。")),
                MeasureInfo(name: L10n.tr("zIdPhi 与 VTE"), definition: L10n.tr("会话内 z 标准化；zIdPhi ≥ 0.5 记为 VTE（阈值可调）。")),
                MeasureInfo(name: L10n.tr("选择"), definition: L10n.tr("左 / 右选择、连续选择的交替率、选择点停留时间。"))
            ]
        case .fearConditioning:
            return [
                MeasureInfo(name: L10n.tr("僵直"), definition: L10n.tr("核心关键点 0.5 s 窗口位移速度 < 1.0 cm/s，持续 ≥ 1 s。")),
                MeasureInfo(name: L10n.tr("按 CS 分段"), definition: L10n.tr("基线（首个 CS 前）、每个 CS 期间、CS 间隔的僵直百分比。")),
                MeasureInfo(name: L10n.tr("时间曲线"), definition: L10n.tr("每分钟僵直百分比。"))
            ]
        case .looming:
            return [
                MeasureInfo(name: L10n.tr("反应潜伏期"), definition: L10n.tr("刺激后速度首次超过 max(4 × 基线速度, 15 cm/s) 的时间。")),
                MeasureInfo(name: L10n.tr("逃跑"), definition: L10n.tr("有反应且在 10 s 内回到巢穴区。")),
                MeasureInfo(name: L10n.tr("僵直"), definition: L10n.tr("刺激后 10 s 内的僵直时长（同恐惧条件化的定义）。")),
                MeasureInfo(name: L10n.tr("朝向与距离"), definition: L10n.tr("刺激时头朝向与巢穴方向的夹角、到巢穴的距离。"))
            ]
        case .rotation:
            return [
                MeasureInfo(name: L10n.tr("整圈数"), definition: L10n.tr("身体轴向（尾根 → 颈部）累计转过 360° 记一圈，顺 / 逆时针分开；反向回转超过 90° 时重新计数。")),
                MeasureInfo(name: L10n.tr("同侧 / 对侧"), definition: L10n.tr("根据损伤侧别换算；俯拍时画面逆时针 = 动物向左转。")),
                MeasureInfo(name: L10n.tr("净旋转"), definition: L10n.tr("同侧 − 对侧，及每分钟净旋转数和分段曲线。"))
            ]
        case .poseOnly:
            return [
                MeasureInfo(name: L10n.tr("逐帧关键点"), definition: L10n.tr("6 个关键点的像素坐标与置信度（与旧版 CSV 格式一致）。")),
                MeasureInfo(name: L10n.tr("运动学"), definition: L10n.tr("平滑后的坐标、速度、头朝向、身体轴向、头–身夹角、身体长度。")),
                MeasureInfo(name: L10n.tr("质量"), definition: L10n.tr("检出率、各关键点平均置信度。"))
            ]
        }
    }

    var references: [PaperRef] {
        switch self {
        case .threeChamber:
            return [
                PaperRef(citation: "Moy SS et al. (2004) Sociability and preference for social novelty in five inbred strains: an approach to assess autistic-like behavior in mice. Genes Brain Behav 3:287–302.", doi: "10.1111/j.1601-1848.2004.00076.x"),
                PaperRef(citation: "Yang M, Silverman JL, Crawley JN (2011) Automated three-chambered social approach task for mice. Curr Protoc Neurosci 8.26.", doi: "10.1002/0471142301.ns0826s56")
            ]
        case .socialInteraction:
            return [
                PaperRef(citation: "Golden SA, Covington HE, Berton O, Russo SJ (2011) A standardized protocol for repeated social defeat stress in mice. Nat Protoc 6:1183–1191.", doi: "10.1038/nprot.2011.361"),
                PaperRef(citation: "Krishnan V et al. (2007) Molecular adaptations underlying susceptibility and resistance to social defeat in brain reward regions. Cell 131:391–404.", doi: "10.1016/j.cell.2007.09.018")
            ]
        case .dyadicSocial:
            return [
                PaperRef(citation: "Segalin C et al. (2021) The Mouse Action Recognition System (MARS) software pipeline for automated analysis of social behaviors in mice. eLife 10:e63720.", doi: "10.7554/eLife.63720"),
                PaperRef(citation: "Hong W et al. (2015) Automated measurement of mouse social behaviors using depth sensing, video tracking, and machine learning. PNAS 112:E5351–E5360.", doi: "10.1073/pnas.1515982112")
            ]
        case .headDirection:
            return [
                PaperRef(citation: "Taube JS, Muller RU, Ranck JB (1990) Head-direction cells recorded from the postsubiculum in freely moving rats. I. J Neurosci 10:420–435.", doi: "10.1523/JNEUROSCI.10-02-00420.1990"),
                PaperRef(citation: "Peyrache A, Lacroix MM, Petersen PC, Buzsáki G (2015) Internally organized mechanisms of the head direction sense. Nat Neurosci 18:569–575.", doi: "10.1038/nn.3968"),
                PaperRef(citation: "Mathis A et al. (2018) DeepLabCut: markerless pose estimation of user-defined body parts with deep learning. Nat Neurosci 21:1281–1289.", doi: "10.1038/s41593-018-0209-y")
            ]
        case .spatialExploration:
            return [
                PaperRef(citation: "O'Keefe J, Dostrovsky J (1971) The hippocampus as a spatial map. Brain Res 34:171–175.", doi: "10.1016/0006-8993(71)90358-1"),
                PaperRef(citation: "Hafting T, Fyhn M, Molden S, Moser MB, Moser EI (2005) Microstructure of a spatial map in the entorhinal cortex. Nature 436:801–806.", doi: "10.1038/nature03721")
            ]
        case .openField:
            return [
                PaperRef(citation: "Prut L, Belzung C (2003) The open field as a paradigm to measure the effects of drugs on anxiety-like behaviors: a review. Eur J Pharmacol 463:3–33.", doi: "10.1016/S0014-2999(03)01272-X"),
                PaperRef(citation: "Seibenhener ML, Wooten MC (2015) Use of the open field maze to measure locomotor and anxiety-like behavior in mice. J Vis Exp 96:e52434.", doi: "10.3791/52434")
            ]
        case .elevatedPlusMaze:
            return [
                PaperRef(citation: "Pellow S, Chopin P, File SE, Briley M (1985) Validation of open:closed arm entries in an elevated plus-maze as a measure of anxiety in the rat. J Neurosci Methods 14:149–167.", doi: "10.1016/0165-0270(85)90031-7"),
                PaperRef(citation: "Walf AA, Frye CA (2007) The use of the elevated plus maze as an assay of anxiety-related behavior in rodents. Nat Protoc 2:322–328.", doi: "10.1038/nprot.2007.44"),
                PaperRef(citation: "Holly KS, Orndorff CO, Murray TA (2016) MATSAP: an automated analysis of stretch-attend posture in rodent behavioral experiments. Sci Rep 6:31286.", doi: "10.1038/srep31286")
            ]
        case .lightDark:
            return [
                PaperRef(citation: "Bourin M, Hascoët M (2003) The mouse light/dark box test. Eur J Pharmacol 463:55–65.", doi: "10.1016/S0014-2999(03)01274-3"),
                PaperRef(citation: "Takao K, Miyakawa T (2006) Light/dark transition test for mice. J Vis Exp (1):e104.", doi: "10.3791/104")
            ]
        case .novelObject:
            return [
                PaperRef(citation: "Ennaceur A, Delacour J (1988) A new one-trial test for neurobiological studies of memory in rats. 1: Behavioral data. Behav Brain Res 31:47–59.", doi: "10.1016/0166-4328(88)90157-X"),
                PaperRef(citation: "Leger M et al. (2013) Object recognition test in mice. Nat Protoc 8:2531–2537.", doi: "10.1038/nprot.2013.155"),
                PaperRef(citation: "Gabriel CJ et al. (2022) BehaviorDEPOT is a simple, flexible tool for automated behavioral detection based on markerless pose tracking. eLife 11:e74314.", doi: "10.7554/eLife.74314")
            ]
        case .barnesMaze:
            return [
                PaperRef(citation: "Barnes CA (1979) Memory deficits associated with senescence: a neurophysiological and behavioral study in the rat. J Comp Physiol Psychol 93:74–104.", doi: "10.1037/h0077579"),
                PaperRef(citation: "Pitts MW (2018) Barnes maze procedure for spatial learning and memory in mice. Bio-protocol 8:e2744.", doi: "10.21769/BioProtoc.2744")
            ]
        case .yMaze:
            return [
                PaperRef(citation: "Hughes RN (2004) The value of spontaneous alternation behavior (SAB) as a test of retention in pharmacological investigations of memory. Neurosci Biobehav Rev 28:497–505.", doi: "10.1016/j.neubiorev.2004.06.006"),
                PaperRef(citation: "Kraeuter AK, Guest PC, Sarnyai Z (2019) The Y-maze for assessment of spatial working and reference memory in mice. Methods Mol Biol 1916:105–111.", doi: "10.1007/978-1-4939-8994-2_10")
            ]
        case .tMaze:
            return [
                PaperRef(citation: "Redish AD (2016) Vicarious trial and error. Nat Rev Neurosci 17:147–159.", doi: "10.1038/nrn.2015.30"),
                PaperRef(citation: "Deacon RMJ, Rawlins JNP (2006) T-maze alternation in the rodent. Nat Protoc 1:7–12.", doi: "10.1038/nprot.2006.2"),
                PaperRef(citation: "Gabriel CJ et al. (2022) BehaviorDEPOT (VTE module). eLife 11:e74314.", doi: "10.7554/eLife.74314")
            ]
        case .fearConditioning:
            return [
                PaperRef(citation: "Phillips RG, LeDoux JE (1992) Differential contribution of amygdala and hippocampus to cued and contextual fear conditioning. Behav Neurosci 106:274–285.", doi: "10.1037/0735-7044.106.2.274"),
                PaperRef(citation: "Anagnostaras SG et al. (2010) Automated assessment of Pavlovian conditioned freezing and shock reactivity in mice using the Video Freeze system. Front Behav Neurosci 4:158.", doi: "10.3389/fnbeh.2010.00158"),
                PaperRef(citation: "Gabriel CJ et al. (2022) BehaviorDEPOT (freezing from keypoints). eLife 11:e74314.", doi: "10.7554/eLife.74314")
            ]
        case .looming:
            return [
                PaperRef(citation: "Yilmaz M, Meister M (2013) Rapid innate defensive responses of mice to looming visual stimuli. Curr Biol 23:2011–2015.", doi: "10.1016/j.cub.2013.08.015"),
                PaperRef(citation: "Vale R, Evans DA, Branco T (2017) Rapid spatial learning controls instinctive defensive behavior in mice. Curr Biol 27:1342–1349.", doi: "10.1016/j.cub.2017.03.031")
            ]
        case .rotation:
            return [
                PaperRef(citation: "Pycock CJ (1980) Turning behaviour in animals. Neuroscience 5:461–514.", doi: nil)
            ]
        case .poseOnly:
            return [
                PaperRef(citation: "Mathis A et al. (2018) DeepLabCut. Nat Neurosci 21:1281–1289.", doi: "10.1038/s41593-018-0209-y"),
                PaperRef(citation: "Pereira TD et al. (2022) SLEAP: a deep learning system for multi-animal pose tracking. Nat Methods 19:486–495.", doi: "10.1038/s41592-022-01426-1"),
                PaperRef(citation: "Weinreb C et al. (2024) Keypoint-MoSeq: parsing behavior by linking point tracking to pose dynamics. Nat Methods 21:1329–1339.", doi: "10.1038/s41592-024-02318-2")
            ]
        }
    }

    /// Keypoints the paradigm relies on (shown in the catalog).
    var keypointsUsed: [KP] {
        switch self {
        case .threeChamber, .novelObject, .lightDark: return [.nose, .leftEar, .rightEar, .bodyCenter, .tailBase]
        case .socialInteraction, .openField, .spatialExploration: return [.nose, .bodyCenter, .tailBase]
        case .dyadicSocial, .poseOnly, .fearConditioning: return KP.allCases
        case .headDirection: return [.nose, .leftEar, .rightEar, .neck, .bodyCenter]
        case .elevatedPlusMaze: return [.nose, .bodyCenter, .tailBase]
        case .barnesMaze: return [.nose, .leftEar, .rightEar, .bodyCenter, .tailBase]
        case .yMaze: return [.nose, .bodyCenter, .tailBase]
        case .tMaze, .looming: return [.nose, .leftEar, .rightEar, .neck, .bodyCenter]
        case .rotation: return [.neck, .bodyCenter, .tailBase]
        }
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
            return [PhaseOption(key: "Sociability", title: L10n.tr("社交偏好")), PhaseOption(key: "Social novelty", title: L10n.tr("社交新颖性")), PhaseOption(key: "Habituation", title: L10n.tr("适应"))]
        case .socialInteraction:
            return [PhaseOption(key: "No target", title: L10n.tr("无目标")), PhaseOption(key: "Target", title: L10n.tr("有目标"))]
        case .novelObject:
            return [PhaseOption(key: "Test", title: L10n.tr("测试")), PhaseOption(key: "Training", title: L10n.tr("训练"))]
        case .barnesMaze:
            return [PhaseOption(key: "Acquisition", title: L10n.tr("学习期")), PhaseOption(key: "Probe", title: L10n.tr("探索测试"))]
        case .fearConditioning:
            return [PhaseOption(key: "Cue test", title: L10n.tr("线索测试")), PhaseOption(key: "Context test", title: L10n.tr("情境测试")), PhaseOption(key: "Training", title: L10n.tr("训练"))]
        default:
            // No presets: the researcher adds their own labels (or leaves it empty).
            return []
        }
    }

    func phaseTitle(_ key: String) -> String {
        phases.first { $0.key == key }?.title ?? key
    }

    func isPresetPhase(_ key: String) -> Bool {
        phases.contains { $0.key == key }
    }

    /// Draggable markers placed on the calibration frame.
    var markers: [MarkerSpec] {
        switch self {
        case .threeChamber: return [MarkerSpec(key: "cupL", label: "L", title: L10n.tr("左杯")), MarkerSpec(key: "cupR", label: "R", title: L10n.tr("右杯"))]
        case .novelObject: return [MarkerSpec(key: "objA", label: "A", title: L10n.tr("物体 A")), MarkerSpec(key: "objB", label: "B", title: L10n.tr("物体 B"))]
        case .barnesMaze: return [MarkerSpec(key: "target", label: "T", title: L10n.tr("目标洞"))]
        case .looming: return [MarkerSpec(key: "shelter", label: "S", title: L10n.tr("巢穴"))]
        case .headDirection: return [MarkerSpec(key: "cue", label: "Q", title: L10n.tr("提示卡"))]
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
