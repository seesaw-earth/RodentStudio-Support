# Rodent Desktop 0.4.1 — Xcode build fix

## 用户报告

Xcode (macOS 26.2 SDK) 无法编译 `RodentDesktop/Core/ScientificExportService.swift:307`：

`the compiler is unable to type-check this expression in reasonable time`

这是 Swift 编译器复杂表达式推断超时，不是 Core ML 模型错误。

## 修复

仅修改 `RodentDesktop/Core/ScientificExportService.swift`：

- 将原 `makeAnnotatedPNG` 内部的颜色选择、关键点坐标计算、标定绘制拆成三个独立的、显式类型的 Swift 函数。
- 保留 RodentPose 六关键点颜色与 RodentLimb 七关键点颜色、原始座标转换、置信度阈值以及 8 像素标点/14 像素标定圆圈定义。
- 未修改 Core ML、模型文件、行为分析器、Review 时间戳和项目 Target 配置。

## 重新构建

1. 解压完整修复版 zip；如果之前已有模型，通过原来的 `python3 install_models.py` 重新安装模型。
2. 用 Xcode 打开 `RodentDesktopNative.xcodeproj`。
3. 选择 Product > Clean Build Folder (Shift+Cmd+K)，然后 Cmd+B。
4. 如果还有报错，分享 Issue Navigator 里新的 **error**，而不是所有 warnings。

也可以直接将单独提供的 `ScientificExportService.swift` 覆盖原目录同名文件，保留以前的模型无需复制。

## 验证范围

Swift 源码语法解析通过；未在 Apple macOS Xcode 环境完成真机编译，因此不能保证不会暴露其他构建错误。视频处理结果和科研计算没有在这次补丁中改动。
