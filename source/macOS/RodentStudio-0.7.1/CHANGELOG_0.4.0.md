# 0.4.0（macOS 原生原型）

## 流程
- 新的“分析”流程按原版 App 的顺序：任务 → 视频与动物 → 校准 → 分析 → 复核与导出，可随时返回任一步；“下一只动物”。
- 侧栏为“任务 → 动物”两级，每只动物显示状态（需要标定 / 可以分析 / 正在分析 / 已暂停 / 失败 / 已分析）。
- 先选任务；项目和任务实验自动建立。视频可拖入，默认以文件名作为动物编号（同 RodentLimb）。
- 阶段 / 性别 / 天 / 试次 / 备注按各原版 App 对该任务的要求显示。
- 顶部三个区域：分析、数据（全部动物表格）、高级。模型选择从主流程移除，只在“高级”中出现。

## 标定（与原版一致）
- RodentPose：移植 Geometry / Zones / Paradigms / ArenaCalibration / AnalysisParams / CalibrationStepView / ParamsEditor。
- RodentFlow：移植 ArenaShape / ArenaCalibration / PlanarHomography / ZoneConfig / ArenaCalibrationView / ZoneParameterEditor 及场地尺寸公式。
- RodentLimb：移植 CalibrationView（圆筒边缘 / 地面线 / cm 标尺、自动拟合）与 ParamsSheet；悬尾改为与原版一致的可选标尺。
- “仅保存到本视频” / “用于该任务的所有视频…”（相机未移动时）；被复制的标定会提示检查。
- 标定保存在视频记录中，并汇总到导出的 `qc_provenance.json`；0.3.x 的工作区仍可读取（旧的通用标定不会被当作新任务标定使用）。

## 分析与复核
- 模型由任务决定；流程内的追踪一律分段写入 App 容器，可暂停、续跑、批量处理其余视频。
- 复核时自动载入保存的结果（≤150,000 帧读入内存，支持逐帧与 RodentLimb 事件；更长的按分段复核）。
- RodentLimb 事件使用该视频保存的 RodentLimb 标定和参数（按结果画面尺寸换算）；圆筒未标定时提示“还差一步：标定”。
- 导出上下文增加阶段、天、试次、性别、备注。

## 体验
- 中英文切换（工具栏地球按钮 / 设置），立即生效，导出保持英文。
- 键盘：⌘1/2/3、⌘[ / ⌘]、⌘O、⌘R、⌘S、⌘E、方向键微调手柄。
- 工作区写盘与画面解码移到后台；拖动只重绘画布，松开后写一次。
- 导入视频时记录显示方向的画面尺寸（考虑旋转）。

## 移除
- `GuidedWorkflowView.swift`、`DesktopMouseCalibrationView.swift`（被各模块自己的标定编辑器取代）。

## 未验证
- 未在 macOS 上编译运行；未用真实视频与原版 App 逐项对照。RodentFlow 追踪与 RodentPose 行为指标仍未移植。
