# RodentStudio Mobile — iOS 上架准备（从 RodentPose 重命名）

## 变更内容
- iOS 主屏幕图标和 App 内 BrandMark 使用上传的 RodentStudio macOS 工程已有图案（转换为不透明的 1024×1024 PNG）；没有重新设计图案。
- `CFBundleDisplayName` 更改为 `RodentStudio`。Xcode 内工程、target 与 Swift `RodentPoseApp` 结构名称继续保持不变，避免影响现有模型和构建文件引用。
- App 主页、设置与产品文字中的品牌改为 `RodentStudio`。某些导出的元数据/CSV 文件名将反映新品牌，科研指标、关键点、算法及模型保持不变。
- iOS Build Number 从 3 改成 4；Marketing Version 保持 1.0。
- **Bundle ID 仍为 `com.ziqingshi.RodentStudio`，必须与原 iOS App Store Connect 记录一致。**

## Xcode
1. 打开 `RodentPose.xcodeproj`，选择 **RodentPose** target（这是内部 target 名称，无需为了品牌修改）。
2. Signing & Capabilities → Team → 选择自己正确的开发团队，确认 Bundle Identifier `com.ziqingshi.RodentStudio`。
3. General → Display Name 为 `RodentStudio`，App Icons Source 为 `AppIcon`；Assets.xcassets → AppIcon 应可见小鼠图标。
4. Product → Clean Build Folder → Build → Run，检查首页、设置、导入视频、标定、追踪、回看与 CSV/JSON 导出。测试中英文和重启后存储路径显示。
5. 在 App Store Connect 的 **RodentPose 原记录**编辑 App Information 名称（若原 Mac 记录占用了 RodentStudio 名称，暂用 `RodentStudio Mobile`），描述与截图、审核说明；随后以 1.0 Build 4 或更高未使用 Build Number Archive/上传。
6. 用户已经拿到两份 4.3/4.2.6 拒审通知：请先回复或提供真实、完整的九项信息，并确认是否需要实质产品改动。品牌变化本身不会自动解决 4.3。

## 特别注意
- 不要新建第 3 个 App 记录或随便变更 Bundle ID。若想只保留一条 iOS+macOS 统一购买的 App Store 记录，须先规划统一 record，按 Apple `Add Platform` 与 Bundle ID 规则操作；既有两个 App 记录无法合并。
- macOS 上传的 `RodentStudio-0.7.1` 工程 Bundle ID 仍是 `com.example.RodentDesktopNative`，与实际提交的 Mac 版本可能不符。必须查询原 App Store Connect 记录并更正后才可 Archive。
- Mac 源码中 Marketing Version 0.7.1/Build 6，之前拒审记录显示 1.0/Build 7；准备重传时先核对并递增以符合对应的版本记录。
- 图标与标题调整不等于验证 scientific metric。医学/科研可靠性声明需独立验证。模型许可、隐私政策与外部公开演示视频也需要审核。
- 本代码包未在 macOS/Xcode/真机上编译或测试。

## Apple 官方资料
- https://developer.apple.com/documentation/xcode/configuring-your-app-icon
- https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/
- https://developer.apple.com/app-store/review/guidelines/
