# 每个任务的标定与原版 App 的对应关系（0.4.0）

原则：**每个任务用它自己那款 App 的标定方式**，三款 App 之间不共用、不互相换算。代码是从 `OriginalAppSources` 里的 iOS 源码移植的；改动只限于桌面交互（鼠标、键盘），标定点的定义、默认位置、区域公式和参数默认值都没有改。

| 模块 | 原版文件（iOS） | 桌面文件 | 说明 |
|---|---|---|---|
| RodentPose 1.0 | `Geometry.swift`、`Zones.swift`、`Paradigms.swift`、`SessionModels.swift`（ArenaCalibration / AnalysisParams）、`CalibrationStepView.swift`、`ParamsEditor.swift` | `Calibration/PoseGeometry.swift`、`PoseZones.swift`、`PoseParadigms.swift`、`PoseSetupModel.swift`，`Views/PoseCalibrationEditor.swift` | 逐行移植；`Angle` 改名 `RPAngle`（避免与 SwiftUI 冲突）；文字改为 `L(英, 中)`，中文取自原版 App 自己的翻译 |
| RodentFlow 1.3 | `TrackingModels.swift`（ArenaShape / ArenaCalibration）、`ArenaMapping.swift`（PlanarHomography）、`ResultModels.swift`（ZoneConfig）、`AssayCatalog.swift`、`AppState.swift`（场地尺寸）、`ArenaCalibrationView.swift`、`ZoneParameterEditor.swift`、`SetupView.swift` | `Calibration/FlowSetupModel.swift`，`Views/FlowCalibrationEditor.swift` | 类型加 `Flow` 前缀（与 RodentPose 同名但结构不同）；中文取自原版 `Localizable.xcstrings` |
| RodentLimb 1.1.2 | `CalibrationView.swift`、`ParamsSheet.swift`、`Session.swift`（isCalibrated） | `Views/LimbCalibrationEditor.swift`，模型沿用已在工程中的 `Analysis/AnalysisModels.swift`（Calibration / AssayParams） | 标定仍以像素保存，并记录标定画面尺寸；评分时按结果的画面尺寸换算 |

## RodentPose（16 个范式）

- 场地类型：与 `Paradigm.arenaKinds` 完全一致。三箱、社交互动、明暗箱、恐惧条件化只有矩形；双鼠社交、头朝向、空间探索、旷场、新物体、Looming 可选矩形或圆形；EPM 只有十字迷宫；Barnes 只有圆形；Y / T 迷宫各自一种；旋转为圆形 / 矩形 / 不标定；仅姿态为不标定 / 矩形 / 圆形。
- 手柄：矩形 1–4（左上、右上、右下、左下）；圆形 C / R（拖 C 时 R 一起移动）；十字迷宫 C、N、E、S、W（开放臂为青色）；Y 迷宫 J、A、B、C；T 迷宫 J、S、L、R。
- 范式标记：三箱左 / 右杯（青色 L / R）+ 紫色中箱分隔线 L / R（改的是 `centerChamberFraction` / `centerChamberOffset`）；新物体 A / B；Barnes 目标洞 T；Looming 巢穴 S；头朝向提示卡 Q。
- 默认位置：`ArenaCalibration.makeDefault(paradigm:kind:frameSize:)`，按画面尺寸和范式默认场地尺寸生成，与 iOS 相同。
- 区域预览：`ZoneBuilder.zones(...)`，与 iOS 画在视频上的区域相同（单应性映射）。
- 尺寸：矩形 宽（1→2）/ 高（2→3）；圆形 直径；迷宫 臂长（不含中央区）/ 臂宽。
- 参数：`ParamsEditor` 的每个范式分支和 `CommonParamsEditor`（分析起点 / 时长、关键点置信度、平滑、插值缺口、时间分段）原样移植。
- 阶段：每个范式的固定阶段；没有固定阶段时可填自由文本（同 iOS）。天、试次对所有范式可填。

## RodentFlow（10 个视频任务）

- 场地形状：`videoArenaShapes` —— 旷场 / 新物体：矩形或圆形；EPM：十字迷宫；明暗箱 / CPP / 恐惧条件化：矩形；水迷宫 / Barnes：圆形；Y、T 迷宫各一种。
- 默认点位：四角 (0.06,0.06)…(0.94,0.94)；圆心 (0.5,0.5)、边缘 (0.88,0.5)；T 迷宫 J(0.5,0.34) S(0.5,0.9) L(0.12,0.34) R(0.88,0.34)；Y 迷宫 J(0.5,0.55) A(0.5,0.1) B(0.16,0.84) C(0.84,0.84)；十字迷宫 C(0.5,0.5) N(0.5,0.06) E(0.8,0.5) S(0.5,0.94) W(0.2,0.5)；标记 A(0.35,0.35) B(0.65,0.65) 目标 (0.68,0.32)。
- 标记：新物体 A / B；水迷宫 P（仅圆形，画象限线）；Barnes T（仅圆形，按洞数画一圈洞）。
- 区域预览：旷场中央方形、明暗箱分隔线（`lightOnLeft ? lightFraction : 1 − lightFraction`）、CPP 一条分隔线或三箱时两条线，均经 `PlanarHomography.arenaToImage` 映射；圆形旷场画中央圆。
- 尺寸与有效场地大小：T 迷宫 宽 = 2·选择臂 + 臂宽、高 = 起始臂 + 臂宽；Y 迷宫 宽 = √3·臂长 + 臂宽、高 = 1.5·臂长 + 臂宽；十字迷宫 2·(臂长 + 臂宽)。
- 分析设置：`ZoneConfig.defaults(for:)` 的每个范式默认值和 `ZoneParameterEditor` 的每个控件（含进入判定、分析窗口、CS 时间表）。
- 阶段 / 天 / 试次：只在原版要求的范式出现（如水迷宫、Barnes 有天和试次；T 迷宫有试次；CPP 有天）。
- **追踪器尚未移植**：设置和标定已保存，但桌面版不能运行 RodentFlow 的经典质心追踪，也不会用姿态模型替代。

## RodentLimb（3 个任务）

- 圆筒：拍摄视角 仰视 → 圆形边缘（圆内拖动 = 移动，拖圆边 ≈30 px 内 = 改半径，最小半径 20 px，虚线内圈 = r·(1 − 触壁区域)）；侧视 → 地面线。默认圆 (w/2, h/2, 0.42·min(w,h))，地面线 0.85·h。**必须标定后才计算事件**（原版 “还差一步：标定”）。
- 步态、悬尾：cm 标尺（两端 + 已知距离，默认 (0.3w,0.85h)–(0.7w,0.85h)、10 cm），可选；“移除标尺（使用体长单位）”。原版对悬尾也显示标尺，这里保持一致（0.3.2 版本把悬尾设为“不标定”，已更正）。
- 有追踪结果时：画面上叠加关键点，并提供“根据追踪自动拟合”（圆）/“根据后爪位置估计”（地面线），算法与原版相同。
- 参数：`ParamsSheet` 的悬尾 / 圆筒 / 步态分节和“姿态预处理（高级）”。
- 保存：“仅保存到本视频” 或 “用于该任务的所有视频…”（确认框提示：仅在相机未移动时使用），被复制的视频显示“标定沿用自 …，请检查”。

## 桌面版有意做的交互改动（不改变科学定义）

1. 拖动时保留鼠标与手柄的初始偏移，手柄不会跳到鼠标下（RodentFlow iOS 是直接跳到手指位置）。
2. 拖动期间只重绘画布，松开后写入一次（与 RodentPose iOS 的做法相同，三模块统一）。
3. 点选手柄后可用方向键微调（每次 0.2% 画面，按住 ⇧ 为 1%）。
4. 3× 放大镜显示在指针对侧的上角。
5. 修改约 0.6 秒后自动保存到当前视频；未改动的默认位置只有在点“继续”或“仅保存到本视频”后才保存（避免没看过就算“已标定”）。

## 尚未验证

- 本环境没有 macOS SDK，**未做 Xcode 编译**，也没有用真实视频和原版 App 做逐像素对照。请在 Mac 上 ⌘B，并用同一段视频在 iOS 与桌面各标定一次，比较 `qc_provenance.json` 中的手柄坐标。
- RodentPose 的行为指标、RodentFlow 的追踪与指标仍未移植；标定和参数已经按原版保存，等分析器移植后直接使用。
