# Rodent Desktop Native — 完整视频 Core ML 试验版（Stage 2）

## 本次新增

在 **Analyse → Whole-video Core ML tracking (experimental)** 中：

1. 选择 MousePose6 或 CylinderMousePoseV2。
2. 点击 **Choose video…** 选择 MP4/MOV。
3. 点击 **Track entire video**。使用 AVAssetReader 顺序读取完整视频，Core ML/Vision 的 `.scaleFit` 每帧推理，记录原视频时间戳；提供进度与取消。
4. 完成后可拖动帧号观看对应帧的关键点叠加，并导出 `raw_keypoints.csv`。
5. Cylinder 另可导出与原始 RodentLimb Swift 分析器兼容的 **二进制 PoseTrack**。该文件可在同页面的 “Original RodentLimb Swift analysis” 入口手动导入、设置标定后测试计算。

新版本**没有**自动输出 Cylinder 触壁结果、TST、Gait 或 RodentPose 的正式科研指标。它只是整段视频姿态提取与可视化的试验路径，不能替代原版科学计算的一致性验证。

## Mac 上安装和启动

下载并解压该 ZIP 之后：

```bash
cd ~/Downloads
mkdir -p RodentNativeVideo
unzip -q RodentDesktopNativeVideoTracking.zip -d RodentNativeVideo
cd RodentNativeVideo/RodentDesktopNativeStarter
python3 install_models.py
open RodentDesktopNative.xcodeproj
```

如果 `RodentDesktopNativeStarter` 已经存在，先改名或解压到一个**新文件夹**，不要覆盖之前的项目。`install_models.py` 从之前的下载目录复制两个模型文件，支持重复运行。选择 **My Mac → ⌘B → ⌘R**；根据你的 Team 设置签名。

**模型文件没有包含在 ZIP 中**，需运行 `install_models.py` 或沿用原先 Xcode 工程下的两个 `.mlpackage`。模型安装后可以在 Xcode 构建时编译。

## 新代码

- `RodentDesktop/Core/NativeVideoTrackingEngine.swift`：视频解码、Core ML 推理、两个专用 decoder、原始 CSV/PoseTrack 数据结构。
- `RodentDesktop/Views/NativeVideoTrackingView.swift`：模型/视频选择、进度、取消、视频静态帧骨架预览、导出。
- `MainView.swift`：在 Analyse 页面嵌入追踪入口。

## 科研注意

- MousePose6 期望输出 `[1,300,24]`，取前 30 个得分超过 0.25 的检测中最高者；6 点顺序是 `nose,left_ear,right_ear,neck,body_center,tail_base`。
- Cylinder V2 期望 `[1,26,8400]`，取全体候选的最高置信度（>0.25），7 点顺序是左前/后、右前/后、尾根、鼻、嘴；原始头不运行 NMS。
- 两者使用不同 decoder，使用 Vision `.scaleFit`；视频读取 `AVAssetReader`，模型输入图像方向 `.up`，之后依视频 `preferredTransform` 转成显示坐标。
- 当前 MousePose 路线**尚未复刻**旧版 iOS 可选的灰度 Core Image 预处理、所有多动物身份逻辑；使用单一最佳检测，不能声称等价于既有 0.2.0 分析。
- 当前静态预览仅显示置信度 ≥0.35 的点，坐标来自推理帧的朝向变换。
- 时间戳以视频**首个可解码帧**为零点，PoseTrack 同时保存首帧原始时间偏移。
- 源视频不修改；如果取消，中间轨迹在内存中丢弃。无自动覆盖导出文件。
- 尚未在 Mac 上用 `xcodebuild` 编译或执行：请以 Xcode 编译结果为准，并进行多帧/旋转视频/iOS 数值一致性测试、人工 QC、行为学指标验证。

## 目前还有哪些未完成

- 与 Project → Videos 里选中的实验/动物建立结果记录及恢复任务。
- 时间轴上的逐帧 Review 和手工纠正。
- RodentPose Open Field / NOR / EPM / Three-Chamber 的 Swift 科学分析。
- Cylinder / Gait / TST 原生标定 UI + 自动调用 Swift 分析器。
- 批量任务持久化、导出 provenance/原始媒体哈希、App Store Archive 与沙盒的完整验收。

这仍然是**原生迁移试验版**，不是已达到 Mac App Store 生产级的发布版本。
