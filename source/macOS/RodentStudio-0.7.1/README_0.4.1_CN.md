# Rodent Desktop Native 0.4.1 — 本次如何使用

1. 解压压缩包，进入 `RodentDesktopNative` 文件夹。运行 `python3 install_models.py`（如已有权重，也可以把两套完整 `.mlpackage` 放到 `RodentDesktop/Resources/Models/`）。
2. 使用 `open RodentDesktopNative.xcodeproj`，Xcode 选择 My Mac，先 ⌘B、再 ⌘R。项目是 macOS 原生 SwiftUI；正常使用**不需要 Python 运行时**。仅模型复制脚本需要 Python 3。
3. 顶部 A− / A+ 调整字体，或 macOS 菜单 Rodent Desktop → Settings → Text Size。默认仍为标准尺寸。
4. 按之前的顺序：分析 → 选择任务（自动匹配模型）→ 视频/动物 → 鼠标标定（放大镜依旧）→ 分析。处理时显示百分比、预计剩余时间和实时抽样的姿态画面。估算时间可能波动；缩略图不是每个原始视频帧。
5. 到 Review 逐帧移动。RodentPose 按原 App 使用 6 色点和白色骨架、2 s 身体中心拖尾。RodentLimb 用 7 个专属颜色和模型独立骨架。拖尾可选 1/2/5/10 s；事件轴分别显示追踪 QC 和已计算的实验事件。
6. 点“上一个事件 / 下一个事件”或事件列表跳到帧，再对照拖尾和视频。若出现“时间戳 / 方向不匹配”，请不要把这些帧用于人工评分；这是防止错误标点的保护。
7. 从 Review 选择起止帧并导出 PNG/CSV。标注截图使用对应**实际返回的源视频帧**，无法匹配时明确报错。原始 CSV 不被更改。

## 长视频

默认分段分析、断点续跑不变。超过 150,000 帧时进入事件后按需读取对应 CSV 段；不会把全视频加载到内存。点事件时需能读取原始视频；若原视频移动过，请先使用定位视频入口。

## 功能界限

目前 RodentPose 的完整 assay-specific 行为评分与原版多种结果图尚需真正移植；RodentFlow 原生质心追踪尚需移植。这次新加的拖尾是 **从已存关键点时间序列绘制的观察轨迹**，不会冒充专属实验的正式指标。苹果系统和各类视频编解码器仍可能有平台特有问题，本包未在真实 Xcode Mac 上构建验证。
