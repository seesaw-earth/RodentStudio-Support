> **视频追踪更新：** 此工程已加入整段视频 Core ML 试验版。请优先阅读 [VIDEO_TRACKING_README_CN.md](VIDEO_TRACKING_README_CN.md)。旧版 README 中关于“尚无视频推理循环”的说明已被这一阶段替代，但科研分析和验证仍未完成。

> **模型接入更新：** 请先看 [MODEL_INTEGRATION_README_CN.md](MODEL_INTEGRATION_README_CN.md)，本新版工程已预登记两个模型资源，并添加单帧 Core ML 实测界面。原 README 的“模型尚无推理帧循环”仍成立：只有单帧 Smoke Test，没有完整视频推理与解码。

# Rodent Desktop Native — Xcode 原生迁移起始工程

## 这是什么

这是从 **Rodent Desktop 0.2.0** 逐步迁移到 macOS 原生 SwiftUI 应用的 **第一阶段可编辑工程**。**不是**已经能替代 0.2.0、也**不是**当前可直接向 Mac App Store 提交的完整科研软件。

本工程是实际 `.xcodeproj`，不需要在 Mac 上先运行 XcodeGen。不包含权重、Conda、PyInstaller 或任何 Python 运行依赖。

## MacBook 打开方法

1. 解压本 ZIP（保持目录结构），打开 `RodentDesktopNative.xcodeproj`，或者 Terminal 运行：

   ```bash
   cd ~/Downloads/RodentDesktopNativeStarter
   open RodentDesktopNative.xcodeproj
   ```

2. 在 Xcode 顶部选择 `RodentDesktop` Scheme，运行设备选择 **My Mac**。
3. 在 `TARGETS → RodentDesktop → Signing & Capabilities` 里选择你已有的 Apple Developer **Team**；将示例 Bundle Identifier `com.ziqingshi.RodentStudio` 更改为你注册的唯一 ID。
4. 按 **⌘B** Build、**⌘R** Run。如出现 Xcode 编译错误，将完整报错发回以针对你本机 SDK 修复。当前生成环境不是 macOS，没有实际执行 `xcodebuild`。
5. 先在 `Projects` 创建项目，在 `Experiments` 选择实验，在 `Videos` 导入 MP4/MOV，`Legacy Project Inspector` 可**只读**查看旧版 `.rodentproj/project.json`。
6. `Analyse` 中可以在不放模型的情况下导入 **原版 RodentLimb iOS 的二进制 plist PoseTrack**，以原始 Swift 算法计算三种 RodentLimb 指标；**不处理视频、不提供科研有效性担保**。

## 哪些功能真正做完

| 模块 | 状态 |
|---|---|
| Xcode macOS App target + SwiftUI 导航 | 已生成，需要你的 Mac 上构建验证 |
| 项目创建与本机 Application Support 保存 | 已实现原生初版（独立新格式） |
| Experiment 实验类型注册 | 已实现初版，可选择五个 RodentPose + 三个 RodentLimb |
| AVFoundation 视频导入、元数据与授权 bookmark | 已实现初版，需沙盒下验证 |
| 原版 RodentLimb Cylinder/TST/Gait Swift 算法 | 原文件直接编入主 Target，已在当前环境 Swift 类型检查通过 |
| iOS 轨迹二进制 plist → 原版 Swift 分析器 → 指标 JSON | 已编写测试入口，需 Mac 实测 |
| 旧版 `.rodentproj` | 仅只读结构浏览，不导入/写回原项目 |
| 视频 Core ML 推理 | **待开发，模型暂不包含** |
| 原版 RodentPose Python 16 类范式算法 | **待逐项迁移、验证**（初版界面只列出五个优先实验） |
| 校准 UI、逐帧 Review 与编辑、动物级统计、论文图表 | **尚未完整实现** |
| App Store 完整审核、隐私/许可/签名检查 | **待完成** |

所有当前未实现的科研计算路径在界面中显示为待开发，**不会生成假数据**。

## 工程目录

- `RodentDesktopNative.xcodeproj/` — 可直接由 Xcode 打开的工程文件
- `RodentDesktop/App/` — 原生 SwiftUI app 入口
- `RodentDesktop/Views/` — 导航、实验、视频、分析与旧工程只读查看
- `RodentDesktop/Core/` — 本地项目模型、AVFoundation 元数据读取、Core ML 模型加载接口
- `RodentDesktop/Analysis/` — **原版 Swift 科研算法**及新 Swift 调用适配器
- `RodentDesktop/RodentDesktop.entitlements` — App Sandbox、用户选择文件读写、书签权限
- `LegacyReference/rodent-desktop-0.2.0-source.zip` — 原来 Python 软件源码，只作为**迁移依据**，不参与 Xcode 编译
- `MIGRATION_PLAN.md` — 完整迁移路线和科研一致性关卡

## 稍后添加 Core ML 模型

1. 将 `MousePose6_960_int8.mlpackage`、`CylinderMousePoseV2.mlpackage` 拖进 Xcode 项目，并勾选主 Target 的 Target Membership。
2. 在 `RodentDesktop/Core/NativeModelCatalog.swift` 中已有 bundle 模型发现和加载入口，但**尚无推理帧循环、图像预处理或模型解码器**。
3. 不要直接启用 `Analyse` 视频分析。必须先对照 0.2.0/iOS 的输入处理、输出解码、关键点一致性及科学指标。

## 一致性与许可证

原版 Swift 文件保留原始算法定义和注释，没有改写判定公式。`License` 和旧版源码一并保留。项目源码是 AGPL-3.0，Mac App Store 分发前需要核对所有第三方权重、训练数据、代码版权与分发条件；本工程不声明已解决这些法律问题。

已在当前非 macOS 环境执行：

- `.xcodeproj/project.pbxproj` 格式检查 `plutil -lint`: PASS
- PBX 对象之间引用关系检查: PASS
- 原版 RodentLimb Swift 七个文件与新 `NativeLimbAdapter.swift`：`swiftc -typecheck` PASS

**未执行**：macOS SDK 编译、macOS GUI 启动、Sandbox 实测、App Store Archive、视频/指标一致性验证。
