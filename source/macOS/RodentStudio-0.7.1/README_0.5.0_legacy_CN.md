> **0.5.1 起部分步骤已改变**：结果在“复核与导出 → 结果”中按“校准”保存的分析时间段自动计算（不再按复核帧范围计算）；RodentFlow 在“分析”中追踪、在“结果”中查看。最新说明见 `README_START_HERE_CN.md`。

# Rodent Desktop Native 0.5.0 — 科研结果、质心追踪和可选 MP4

这次升级基于 0.4.1 BuildFix 的 Xcode macOS SwiftUI 工程。**本压缩包不包含 Core ML 权重**，也没有经过 macOS/Xcode 完整编译；所有新功能应在本机编译并使用短视频验证后，再用于正式科研。

## 1. 安装

```bash
cd ~/Downloads
unzip -q RodentDesktopNative-0.5.0-FinalUpgrade.zip
cd RodentDesktopNative-0.5.0
python3 install_models.py
open RodentDesktopNative.xcodeproj
```

Xcode 选择 My Mac，先按 ⌘B 编译，再按 ⌘R 运行。运行前使用你自己的 Bundle ID / Developer Team。以前的项目、模型和输入视频不应删除。**不要覆盖已验证的旧版工程。**

## 2. RodentPose — 原版 Results

先选择 RodentPose 的实验，导入视频、按原版校准、运行 MousePose6 六关键点模型。分析完到 Review，在 `Start frame / End frame` 填写指定区间，选择 **Calculate assay report for selected frames**。将看到原始 iOS `Analyzer.run` 计算的主指标、完整指标和对应 `ReportBlock` 图：场地区域及轨迹/热图、柱状图、折线图、事件时间轴、极坐标图、表格，以及警告/方法说明。

点 Export 时，若已计算所选范围的报告，还会导出 `rodentpose_metrics.csv`、`rodentpose_methods_quality.txt`；选择 `Include each report figure PNG` 可导出 `rodentpose_figure_01.png` 等。**改变帧范围后要重新点击计算，避免导出旧区间图表。** 只从已保存的六关键点生成，不重跑模型。双动物互动范式当前仍明确不评分，因为现有追踪结果是一只动物。

长视频只在用户需要报告时读取范围覆盖的 CSV 分段；单份报告最多 100,000 帧，超长视频请分段生成多份报告。原始分段仍保留。

## 3. RodentFlow — 原版无模型经典质心

选择 **RodentFlow** 中的任一个视频输入实验（10 项），导入视频，然后按原版场地编辑器标定，进入 Analyse。点击 `Track video with classic centroid`。它使用原版 RodentFlow 1.3：稀疏背景帧构建时间中位数背景、背景差分、动态阈值、连通区域、时间一致性、对比度加权质心和区域映射，按 10 Hz 采样。**不调用 MousePose6 或 CylinderV2**。

每约 300 个采样点（约 30 秒）生成一个原始质心 JSON 检查点，中断后可从符合指纹的检查点继续；完整结果保存 `flow_centroid_result.json`。随后在 Review/Analyse 的 RodentFlow 面板中看到可选时间窗的轨迹、区域切换事件，及使用原版 `AssayEngine.compute`（10 种视频范式）的实验指标与时间序列；可导出 `rodentflow_centroid_selected.csv`、`rodentflow_centroid_trajectory.png`、`rodentflow_assay_metrics.csv`、`rodentflow_assay_results.json`、`rodentflow_assay_figures.png`。

一些 RodentFlow 视频任务（如 NOR、Barnes、Fear）原版本身使用基于质心的近似操作定义，不等同于鼻尖嗅探或人工 Freeze 标注。请查看原版参数和 QC，不能将代理指标冒充人工标签。跨 checkpoint 的第一帧运动状态需要单独验证。虽然采用分段落盘，当前 RodentFlow 分析器仍会在内存中保存 10 Hz 质心点，因此极端长视频必须压力测试。

## 4. Annotated MP4：先估算、再确认

RodentPose 或 RodentLimb 已完成分析后，进入 Review → Export，填写 `Start frame / End frame`。点击 **Estimate annotated MP4 time…**：软件先把所选视频的约 30 帧执行真实读取、关键点叠加和 H.264 编码到临时文件，从测速估算整个范围需要的时间；这一步会短暂运行，也可能第一次较慢。预计分钟数和测试帧数显示出来（软件同时给出不确定范围）。

仅在用户主动点击 **Export MP4…**，再次确认后才选择文件路径并开始导出。MP4 是视频画面、原版配色关键点和骨架的可选标注输出；它按帧流式读取已保存轨迹，不重跑模型，不默认导出，不覆盖原始视频。长视频只读取与当前时间对应的 CSV 分段，不一次性载入全部轨迹。**目前不复制原视频声音轨**。本机视频编码性能及坐标旋转仍需实际验证，估算仅供决策，不保证准确。

## 5. 保留与限制

- RodentPose 六关键点和 RodentLimb 七关键点的模型、解码、配色、Review 对齐及分析路线彼此独立。
- RodentLimb Cylinder、TST、Gait 原版 Swift 分析器仍在；Review events、拖尾、QC、字体调整、放大镜、鼠标标定、长视频 Core ML 分段与断点续跑均保留。
- 所有科学计算均需使用同一视频/同一参数与原版 iOS App 导出的数据逐项比对；类型检查通过不代表临床/科研准确性验证完成。
- `.app` 能在 Xcode Debug 模式运行 ≠ 符合 Mac App Store 所有签名、许可、隐私及 Sandbox 审核要求。

## 6. 建议测试顺序（优先）

1. Xcode ⌘B 检查 Swift 类型和 Core ML 模型打包；如有红色错误，把**第一条 error** 及前后上下文发回来。
2. 用 15–30 秒 Open Field 小鼠视频分别跑 RodentPose 和 RodentFlow，比较质心、轨迹和原版 iOS 指标。
3. RodentPose 选定中间 300 帧：Results 页面指标、热图、图表、事件和导出 PNG 是否对应此范围。
4. Review 的画面、时间戳与标点是否一致；Annotated MP4 测速、确认、保存和回放时颜色/时间是否正确。
5. 用较长视频（30–60 分钟）验证续跑、缓存、内存占用、MP4 导出和长区间 Results。
6. 科学验证：针对 10 项 RodentFlow 视频实验和 RodentPose 的每个任务，对照原版 iOS 同条件输出。正式发表前按需加入人工评分对照。
