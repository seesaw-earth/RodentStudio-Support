# 将两个现有 Core ML 模型接入 Rodent Desktop Native

该工程是在 NativeStarter 上增加的模型资源注册与单帧推理 Smoke Test。**没有附带权重**；不会训练或转换任何模型，也没有引入 Python 运行时依赖。第一次安装模型使用一个仅依赖 Python 标准库的复制脚本；用户运行 App 不需要 Python。

## 1. 准备模型

默认从这两个已知位置寻找：

- `~/Downloads/rodent-desktop/models/source/MousePose6_960_int8.mlpackage`（或 `~/Downloads/rodent-desktop-0.2.0/rodent-desktop/models/source/...`）
- `~/Downloads/07_export/CylinderMousePoseV2.mlpackage.zip`（或此前复制在 `rodent-desktop/models/user_supplied/cylinder_v2/` 里的 ZIP）

**不要换成** `CylinderMousePoseV2_FP16.mlpackage.zip`，也不要把 Cylinder V1 或 `.pt` 误当成 V2 Core ML 模型。若希望更换，先明确做科学一致性验证。

## 2. 安装模型文件

打开 Terminal：

```bash
cd ~/Downloads/RodentDesktopNativeStarter
conda activate rodent-desktop
python install_models.py
```

脚本会验证每个 `.mlpackage` 至少含 Manifest 和 `.mlmodel`，将文件放在：

```
RodentDesktop/Resources/Models/MousePose6_960_int8.mlpackage
RodentDesktop/Resources/Models/CylinderMousePoseV2.mlpackage
```

如文件在不同位置：

```bash
python install_models.py --mouse '/absolute/path/MousePose6_960_int8.mlpackage' --cylinder '/absolute/path/CylinderMousePoseV2.mlpackage.zip'
```

**Xcode 项目已预先将两个模型注册到 App Target 的 Compile Sources Build Phase**，不需要再次手动拖入（避免重复资源）。

## 3. 编译检查

```bash
open RodentDesktopNative.xcodeproj
```

选择 My Mac → ⌘B / ⌘R → Analyse 页面：

- 两个模型的状态均应为 `Bundled`。
- 在 Core ML model / video smoke test 中选择模型，点击 `Test one video frame…`，选择短视频，应该看到输入信息和多维张量输出形状。
- MousePose6 的常见输出是 `(1, 300, 24)`；Cylinder V2 的原始输出是 `(1, 26, 8400)`。如果模型版本导出选项不同，应记录实际形状并检查，不要直接假定等价。

如果模型显示 `Add later`，请检查 Xcode Build Phases → Compile Sources 是否包含两个 `.mlpackage`，并且确实编译出了对应 `.mlmodelc`，并确保模型资源名称与 `NativeModelCatalog.swift` 完全一致。

## 4. 目前已完成 / 未完成

**已完成的代码**：预先注册两个 `.mlpackage` 模型资源；安装脚本；动态检测与加载模型；从用户授权视频读取一帧并使用 Vision / Core ML 取得原始模型张量。

**未完成**：对照 iOS / 0.2.0 的色彩、letterbox、旋转与输入归一化；6/7 关键点的正式解码器；按原始帧时间戳连续推理、暂停取消；把 PoseTrack 传给 Swift 分析器；轨迹画面、人工 QC、统计和可追踪导出。单帧 Smoke Test 不应生成科研结论。

由于当前环境不是 macOS，**尚未实际使用 Xcode 编译**。pbxproj 经 plutil 验证，Swift 源码仅经过语法 parse 验证。请在 Mac 上验证后再用于研究。
