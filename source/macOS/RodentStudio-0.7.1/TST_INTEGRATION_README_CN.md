# RodentStudio 0.7.0 — Multi-Chamber TST 源码集成

本版本从 RodentStudio 0.6.2 源码构建，**不覆盖旧版**；将 `TSTScorer 6.zip` 中原有的检测、格子布局、关键帧、轮廓运动分析、评分和界面作为新任务移入同一个 macOS Xcode target。

## 在 Mac 上运行（必须使用 Xcode）

1. 解压 `RodentStudio-0.7.0-TST-source.zip`，打开其中 `RodentStudio-0.7.0/RodentStudio.xcodeproj`。
2. 在 Xcode 选择 **RodentStudio** scheme 和 **My Mac**。
3. 按 `⌘B` 编译，成功后按 `⌘R` 运行。
4. 点击 **New Task**，在 **TSTScorer → TST · Multi-Chamber** 中新建任务。
5. 点开这个任务；导入 TST 录像、检查实验格子、寻找 key frame、复核、分析，然后输入每格的 Animal ID、Group，点击 **Save run to task**。
6. 在 **Saved runs** 查看归档，并导出 **一行一只动物**的 CSV。

也可以在 Terminal 的项目根目录执行：

```bash
xcodebuild -project RodentStudio.xcodeproj -scheme RodentStudio -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Xcode Signing：上传 App Store 前，必须把 `com.ziqingshi.RodentStudio` 改成你在 App Store Connect 的**实际 RodentStudio Bundle ID**，并选对 Team；源码默认不会擅自替换它。

## 新增 / 保留功能

- 新增 `tstscorer.multi_chamber`，与旧版 `rodentlimb.tail_suspension` **保持不同 assay ID**。旧的 RodentLimb TST 不受影响。
- TSTScorer 原有的经典/YOLO 检测器、鼠笼格子校正、扫描、key frame、motion segmentation、threshold 校准、逐帧图表、原始 CSV 导出。
- 内置源工程中的 `MouseDetector.mlpackage`（约 5 MB）。缺少可用模型时，原 TSTScorer 将回退经典检测器；导出标记实际使用的后端。
- 一个 TST 任务内支持多个录像；**同一录像的多个 chamber 分别绑定不同 Animal ID 和 Group**。必要时排除并填写原因，不将多个格子视为同一只动物。
- 每次保存产生独立文件夹，含 `record.json`、`animal_summary.csv`、`original_summary.csv`、`framewise.csv`、`settings.json`、可能的 `keyframe.csv`。不会覆盖旧结果。
- TST 的归档目录：`~/Library/Application Support/RodentDesktopNative/TSTMulti/<task-uuid>/<run-uuid>/`（沙盒 App 在其 container 内的对应 Application Support）。
- **Saved runs → Export animal-level CSV** 合并输出：task/run ID、video、chamber、Animal ID、Group、Sex、QC exclusion、immobility、no-mouse 占比、检测器、阈值、采样率等。
- 旧版 0.6.2 的 Pose/Limb/Flow Swift 文件和算法未重写。`TaskMergePolicy` 阻止合并带有独立归档 UUID 的 TST 任务。已有归档的 TST 任务不能直接删除，防止找不回数据。

## 验证状态（重要）

- 当前执行环境没有 macOS SDK / Xcode，所以**没有实际运行 macOS App 编译、Core ML 视频处理和 GUI**。首次运行可能出现 Swift / SDK 兼容错误；请发送 Xcode `⌘B` 的报错定位修复。
- 已完成 Swift 前端**语法解析**，`plutil -lint` **Xcode 工程结构检测**，所有新增源文件引用路径检查。
- 上游 TSTCore 纯 Swift 模块在 Linux 成功编译；key-frame、chamber-refit、motion translation、no-mouse 4 个选定单元测试通过。全量测试在本环境运行超时，不能称为全部通过。
- TST 入门 YOLO 模型训练来源包含合成数据，跨装置/光照可靠性未经确认；TST immobility 默认阈值需要用盲法人工评分校准。**不可直接标记为科研验证完成**。
- TST Task 的汇总独立于旧的单动物 VideoRecord/GroupAnalysis，因为它的科学单位是每格一鼠。已经提供动物级 CSV，**尚未接入全局推断性统计和跨任务报告**。这是为了避免把帧或单视频错误计为样本量；后续应在 Mac 真实测试后再整合。
- 本版本不保证解决 Apple Guideline 4.3；最终审核前还需要实际功能证据和审核说明。

## 核心修改文件

- `RodentStudio/Core/WorkspaceStore.swift`：新增唯一 assay ID。
- `RodentStudio/Core/DesktopAssayCatalog.swift`：注册新任务。
- `RodentStudio/Calibration/TaskSetup.swift`：新任务路由与文字。
- `RodentStudio/Views/AnalysisWorkflowView.swift`：任务选择入口、专用页面及安全限制。
- `RodentStudio/Core/TaskMergePolicy.swift`：保护独立 TST 归档。
- `RodentStudio/TSTMulti/`：来自原 TSTScorer 的纯 Swift 核心、视频/检测、原界面，以及新增 `TSTTaskWorkspaceView.swift`。
- `RodentStudio.xcodeproj/project.pbxproj`：把新 Swift 文件、Core ML 模型加入原 Xcode target；版本改为 0.7.0 (5)。

**备注**：为避免与 RodentStudio 已有 `AnalysisResult` 和 `SettingsView` 等标识符冲突，移植代码仅做必要的命名隔离，例如 `TSTMultiAnalysisResult`、`TSTResultsView`、`TSTAppModel`；未调整 TSTCore 行为学算法、默认阈值或实验规则。
