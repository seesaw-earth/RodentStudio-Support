# RodentDesktopNative 0.5.0 — Xcode compile fix 2

基于上一版 XcodeRefFix 工程。本次只改动两个 Swift 文件，不更改模型、行为计算和分析参数。

## 修复

- `RodentDesktop/Views/FlowDesktopPanel.swift`：将 RodentFlow CSV 行拆分成显式 `[String]`，避免 `.map(String.init)` 与过长字符串插值造成 Swift 类型推断歧义。
- `RodentDesktop/Core/AnnotatedVideoExporter.swift`：使用显式 `[String: Any]`，并将 `kCVPixelBufferWidthKey`、`kCVPixelBufferHeightKey` 从 CFString 转为 String，修复视频编码器像素缓冲区属性字典的类型不匹配。

## 快速替换（不需要重新导入模型）

如果你下载的是两个单文件，直接替换当前工程中的文件：

```bash
cd ~/Downloads/RodentDesktopNative-0.5.0
cp ~/Downloads/FlowDesktopPanel-0.5.0-fixed.swift RodentDesktop/Views/FlowDesktopPanel.swift
cp ~/Downloads/AnnotatedVideoExporter-0.5.0-fixed.swift RodentDesktop/Core/AnnotatedVideoExporter.swift
open RodentDesktopNative.xcodeproj
```

在 Xcode 使用 `Product → Clean Build Folder`，然后 `⌘B`。

## 测试边界

全部 67 个 Swift 文件已通过 `swiftc -frontend -parse` 语法解析；Xcode 项目文件未改变，和上一轮引用修复版一致；RodentFlow CSV 字段拼接用独立 Swift 代码做了实际类型检查。尚未在 macOS SDK 下运行 `xcodebuild`，不代表已经完成 macOS 构建或 MP4 编码实机测试。若出现新报错，请提供第一条 `error:`。
