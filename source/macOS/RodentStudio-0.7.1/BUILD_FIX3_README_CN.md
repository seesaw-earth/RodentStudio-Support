# RodentStudio 0.7.0 — Build Fix 3

针对 2026-10-20 Xcode Debug build 日志（工程目录为 `RodentStudio-0.7.0 3`）做**最小范围编译修复**。本文件不是 macOS 构建通过证明。

## 修改内容

1. `RodentStudio/TSTMulti/Views/ResultsView.swift`：原代码误将 `ChamberSummary.bouts` 写成 `s.tstBouts`，现改用正确字段 `bouts`；明确使用 `chamber` 作为 `ForEach` 的身份字段。
2. `RodentStudio/TSTMulti/Views/ScanView.swift`：替换 UIKit 专属的 `Color(.secondarySystemBackground)` 为 macOS AppKit `Color(nsColor: NSColor.controlBackgroundColor)`；显式将 chamber 范围转为数组，避免误匹配 SwiftUI Binding 版本的 `ForEach`。
3. `RodentStudio/Resources/Assets.xcassets/AppIcon.appiconset/`：去掉未分配的 `appicon_1024.png`，它和仍在使用的 `icon_512@2x.png` SHA256 完全相同，清除 Xcode unassigned child 警告。
4. **保留** Build Fix 1 `TSTMultiSettingsView.swift` 唯一文件名修改及 Build Fix 2 `TSTTaskArchive.save` 的 `@MainActor`。

只修改 TST UI 代码与一份冗余 App Icon 文件；Core ML 权重、TST 检测/评分算法、旧版 RodentPose/RodentLimb/RodentFlow 分析逻辑均未修改。

## 安装和启动

在 MacBook 下载新的 ZIP，并在 Terminal 运行：

```bash
cd ~/Downloads
mkdir -p RodentStudio-buildfix3
unzip -q RodentStudio-0.7.0-TST-buildfix3-source.zip -d RodentStudio-buildfix3
open RodentStudio-buildfix3/RodentStudio-0.7.0/RodentStudio.xcodeproj
```

在 Xcode 选择 `RodentStudio` scheme、`My Mac`，执行 `Product → Clean Build Folder`，再 `Command+B`、`Command+R`。

不想重新解压时，也可以下载单独的 `fix_rodentstudio_070_build3.py`，对先前的 buildfix2 工程运行：

```bash
python3 ~/Downloads/fix_rodentstudio_070_build3.py "$HOME/Downloads/RodentStudio-0.7.0 3"
```

此脚本只处理前两项 Swift 源码问题，不处理 App Icon 冗余文件；可重复运行，不覆盖已有备份。***不要对 0.6.2 原始工程执行。***

## 验证范围

当前可执行：完整 Swift **语法解析**、Xcode 项目配置 `plutil -lint`、模型内容对照、修复脚本幂等性检查。

当前环境是 Linux，没有 macOS SwiftUI / AppKit SDK 与 Xcode，因此**无法在这里运行完整 Xcode typecheck/build、签名、Core ML 实时推理、GUI 或科研准确性校验**。确认是否成功必须看你自己的 Xcode `BUILD SUCCEEDED` 和真实视频结果。

App Store 上传前需更改当前示例 Bundle ID `com.ziqingshi.RodentStudio` 为 RodentStudio App Store Connect 对应真实 Bundle ID；这次没有擅自修改。
