<p align="center">
  <img src="assets/github-banner.png" alt="RodentStudio：适用于 Mac、iPhone 和 iPad 的小鼠行为视频分析" width="100%">
</p>

<p align="center">
  <a href="https://testflight.apple.com/join/8e6r8Dc4"><img src="https://img.shields.io/badge/TestFlight-%E5%85%AC%E5%BC%80%E5%86%85%E6%B5%8B-0D96F6?logo=apple&amp;logoColor=white" alt="TestFlight 公开内测"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-12304A" alt="macOS 14 或更新">
  <img src="https://img.shields.io/badge/iOS%20%2F%20iPadOS-17%2B-12304A" alt="iOS / iPadOS 17 或更新">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&amp;logoColor=white" alt="Swift 与 SwiftUI">
  <a href="source/macOS/RodentStudio-0.7.1/LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-1C5DC9" alt="许可证：AGPL-3.0"></a>
</p>

<p align="center">
  <a href="https://seesaw-earth.github.io/RodentStudio-Support/zh/"><b>官网</b></a> ·
  <a href="https://seesaw-earth.github.io/RodentStudio-Support/zh/guide.html"><b>使用指南</b></a> ·
  <a href="https://testflight.apple.com/join/8e6r8Dc4"><b>加入内测</b></a> ·
  <a href="https://seesaw-earth.github.io/RodentStudio-Support/zh/support.html"><b>获取支持</b></a> ·
  <a href="README.md"><b>English</b></a>
</p>

---

**RodentStudio** 在你自己的设备上分析你自己拍摄的实验啮齿类视频。导入视频、校准场地、运行追踪、复核结果、导出结构化数据——不用写代码，不需要 Python、账号或联网，视频也不会上传。Core ML 模型已内置在 App 中。

## 🧪 TestFlight 公开内测

Mac 版现已开放公开测试。

1. 在 Mac 的 App Store 免费下载 Apple 的 **TestFlight**。
2. 在 Mac 上打开邀请链接：**<https://testflight.apple.com/join/8e6r8Dc4>**，点“接受”再点“安装”。
3. 用自己的视频试一试，在 TestFlight 里点“发送 Beta 版反馈”，或[提交 Issue](https://github.com/seesaw-earth/RodentStudio-Support/issues/new/choose)。

> 测试版可能不稳定，请备份原始视频与导出数据。

## 四步完成分析

| 步骤 | 你要做的 |
| --- | --- |
| **1 · 导入视频** | 拖入 MP4 / MOV，从文件名自动识别小鼠编号和日期。 |
| **2 · 校准场地** | 把手柄拖到场地上，输入实际尺寸（cm）。 |
| **3 · 自动追踪** | 本机 Core ML 姿态模型或经典质心追踪，多段视频排队依次分析。 |
| **4 · 复核并导出** | 抽查 100 帧、标记错误帧，导出表格、图表和方法说明。 |

## 20 种行为学范式

| 模块 | 方法 | 范式 |
| --- | --- | --- |
| **RodentPose** | Core ML 姿态，6 个关键点 · Mac、iPhone、iPad | 旷场 · 高架十字迷宫 · 明暗箱 · 新物体识别 · 三箱社交 · 社交回避 · 双鼠社交互动 · Y 迷宫自发交替 · T 迷宫 VTE · Barnes 迷宫 · 恐惧条件化 · Looming 逃跑 · 旋转行为 · 头朝向 · 空间探索 / 位置细胞 · *仅导出姿态* |
| **RodentLimb** | Core ML 四肢姿态，7 个关键点 · Mac | 圆筒实验 · 悬尾实验（单鼠） · 步态分析 |
| **RodentFlow** | 经典质心追踪，10 Hz · Mac | Morris 水迷宫 · 条件性位置偏好 · 以及旷场、高架十字迷宫、明暗箱、Y 迷宫、T 迷宫、新物体识别、Barnes 迷宫、恐惧条件化的位置版本 |
| **多格悬尾实验** | 格子检测 + 逐格运动评分 · Mac | 一段录像中并排悬挂的多只小鼠同时评分 |

各范式的标定方法和指标见[实验范式速查](https://seesaw-earth.github.io/RodentStudio-Support/zh/guide.html#assays)。

## 让结果经得起检验

- **逐帧复核**：抽查 100 帧不到一分钟，标记追踪错误并记录结论。
- **追踪一次，评分多次**：修改区域、阈值或分析时间段，不用重新运行模型。
- **n = 小鼠数**：同一只小鼠的多次实验先取平均再做组间统计，不按帧数凑 n。
- **组间比较**：内置 Welch t 检验、方差分析、混合方差分析和非参数检验（Mac），用于初步查看数据。
- **导出即用**：英文列名 CSV 加 `README_methods.txt`，可直接用于 R、Python、Prism 或 Excel；逐帧数据支持 DeepLabCut 格式。

## 🔒 隐私

- 无需账号、不上传：视频、追踪数据和结果都留在你的 Mac、iPhone 或 iPad 上。
- 没有广告，也没有开发者运营的数据统计。
- 原始视频只读取、不修改。

详见[隐私政策](https://seesaw-earth.github.io/RodentStudio-Support/zh/privacy.html)。

## 系统要求

| | RodentStudio（Mac 版） | RodentStudio Mobile（iPhone / iPad） |
| --- | --- | --- |
| **系统** | macOS 14 Sonoma 或更新（推荐 Apple 芯片） | iOS / iPadOS 17 或更新 |
| **适合** | 完整课题：多只动物、多个分组、多次实验、统计和批量导出 | 单段视频快速分析、实验台旁检查、教学演示 |
| **状态** | TestFlight 公开内测中 | 准备发布中 |

## 仓库内容

```text
├── index.html、guide.html 等   支持网站（由 GitHub Pages 发布）
├── zh/                          中文页面
├── assets/                      图标、样式、横幅图
├── source/                      Mac 与 iPhone / iPad 的 Swift / SwiftUI 源码
│   ├── macOS/RodentStudio-0.7.1/
│   └── iOS/RodentStudio-Mobile-iOS/
├── MAINTAINING.md               网站如何部署与维护
├── PUBLISHING_CHECKLIST_CN.md   App Store 发布检查清单
└── APP_STORE_CONNECT_URLS.md    App Store Connect 中使用的网址
```

### 从源码编译

在 Xcode 中打开对应平台的 `.xcodeproj`，选择你自己的开发团队进行签名后编译。Core ML 模型使用 **Git LFS** 存储，克隆后请运行 `git lfs pull`。详见 [source/README.md](source/README.md) 与[从源码编译](https://seesaw-earth.github.io/RodentStudio-Support/zh/guide.html#build)。

## 获取支持

问题与错误请通过 [Issues](https://github.com/seesaw-earth/RodentStudio-Support/issues/new/choose) 提交，并附上 App 版本、macOS / iOS 版本、Mac 芯片、模块和复现步骤。**Issues 是公开的，请勿上传保密的科研视频或个人信息。**

## 许可证

[`source/`](source/) 中的 App 源码以 **GNU AGPL-3.0** 发布，详见各项目的 `LICENSE`；第三方组件与模型说明见项目文件夹（例如 [THIRD_PARTY_NOTICES.md](source/iOS/RodentStudio-Mobile-iOS/THIRD_PARTY_NOTICES.md)）。© 2026 Ziqing Shi。

> **科研提示：** RodentStudio 是科研辅助工具，不是诊断工具。其指标是算法估计，请先在自己的装置上与人工评分对比验证，再得出科研结论。
