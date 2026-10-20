# Rodent Desktop Native — Mouse Workflow Edition (0.3.1)

本版本基于 `RodentDesktopNativeUnifiedLongVideo`，没有替换模型、训练权重或科研评分公式。

## 源码依据（直接阅读了原始 iOS Swift）

- `OriginalAppSources/RodentPose_iOS_1.0.zip`：`SessionFlowView.swift`、`CalibrationStepView.swift`（含 `CalibrationCanvas` 与 3× `CalibrationLoupe`）、`ReviewPlayerView.swift`。
- `OriginalAppSources/RodentLimb_iOS_1.1.2.zip`：`UI/CalibrationView.swift`（`LoupeView`）、`UI/SessionDetailView.swift`（Summary / Review / Measures）、`UI/ReviewPlayer.swift`。
- `OriginalAppSources/RodentFlow_iOS_1.3.zip`：`SetupView.swift`、`ArenaCalibrationView.swift`、`ZoneParameterEditor.swift`、`AssayCatalog.swift`、`FlowNavigation.swift`。

## 新的主流程

启动后默认进入 `Start Here`：

1. **Video**：选项目、导入或选已有视频。
2. **Experiment**：选择现有实验，或按三个原始模块创建视频实验；填写 Animal ID 和 Group。
3. **Calibrate**：使用鼠标拖动视频上的标定点/关键区标记；拖动时显示 3× 局部放大镜。拖到合适位置后保存，进度条可切换标定帧。可调整基本分区/时间窗参数。
4. **Quick check**：解释所选实验的正确计算路径与尚未实现的预览；不会自动在这里运行错误模型。
5. **Run**：RodentPose 使用 MousePose6 (6 keypoints)；RodentLimb 使用 CylinderMousePoseV2 (7 keypoints)；RodentFlow 不使用 YOLO，经典质心追踪原版代码仍待原生移植。长视频使用分段磁盘保存路径。
6. **Review & export**：目前只是迁移状态说明；已经存在的姿态预览及 CSV 导出位于 Run 的视频跟踪组件内。尚未移植真实事件复核、重新评分的 UI。

菜单侧边栏还保留 Projects / Experiments / Videos / Analyse 等高级入口，但新用户不必从这些页面猜顺序。

## 鼠标标定（本版实际可操作的部分）

- RodentPose / RodentFlow：矩形 1–4；圆形 C/R；EPM C/N/E/S/W；Y 迷宫 J/A/B/C；T 迷宫 J/S/L/R。NOR A/B 物体位置、Three-Chamber 中箱 L/R 与 cups、RodentFlow 水迷宫平台 P、Barnes 目标 T。
- RodentLimb：Cylinder 圆缘（bottom view）或地面线（side view）；Gait 已知距离标尺双端点；TST 无强制几何标定。
- 可改动：尺寸或参考距离、图像标定帧、Open Field 中心区比例、Light/Dark 分界、CPP 分界、EPM 开放臂方向、NOR 新物体及区域半径、分析时间窗。调整和记录会保存在当前视频的 setup 中。
- 放大镜：指针拖动控制点时显示 3× 圆形局部图像并标注手柄，不影响图像/关键点数据。

**科学状态：这些是可运行的编辑和存储界面。** 原 iOS 的完整区域几何/透视投影、参数组合、后处理和指标重计算尚未迁移；虚线分区只作界面预览，不代表已经参与数据计算。不要把设置可编辑等同于原始 iOS 分析已完成。

## RodentFlow：只保留视频输入的 10 个 Assay

1. Open Field / Center
2. Elevated Plus Maze
3. Light–Dark Box
4. Y-Maze
5. T-Maze
6. Novel Object Recognition
7. Morris Water Maze
8. Barnes Maze
9. Fear Conditioning
10. Conditioned Place Preference

原版另 6 个“非视频输入”的流程不再显示在 Mac 的实验选择或 Assay Catalog：Marble Burying、Sucrose Preference、Beam Walking、Manual Gait Analysis、Two-Armed Bandit、Custom Table。

原版 iOS ZIP **原样保留在 OriginalAppSources** 以便追溯；旧 Desktop workspace 内如果已存在这些实验 ID，仍可解码读取，但在当前 App 的选择/执行页面被隐藏，既不重新解释为其他实验，也不擅自删除历史数据。

## 如何运行

```bash
cd ~/Downloads
unzip RodentDesktopNativeWorkflowUX.zip
cd RodentDesktopNativeWorkflowUX
python3 install_models.py       # 如果之前已有模型，这一步使用 Downloads 中原始文件复制
open RodentDesktopNative.xcodeproj
```

Xcode 里 `My Mac` → `⌘B` → `⌘R`。若需要签名，请设置自己的 Apple Developer Team/Bundle ID。

本环境只进行了 `.pbxproj` 结构检查、Swift 语法解析和目录/目录 ID 检查；**尚未在真实 Xcode/macOS 上完整构建或用长视频测试**。正式科学发布需要源 iOS 与 Mac 的参数/关键点/逐动物指标一致性和人工评分验证。
