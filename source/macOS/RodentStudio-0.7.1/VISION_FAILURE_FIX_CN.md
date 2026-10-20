# 处理到第 16366 帧时 Vision/Core ML 报错：修复说明

适用项目：RodentDesktopNativeWorkflowUX 的原生 Xcode 工程。保留原来的 RodentPose (6 点，MousePose6) 和 RodentLimb (7 点，Cylinder V2) 选择规则、原始模型和 Swift 分析算法。

## 发现的旧版失败路径

`NativeVideoTrackingEngine.swift` 在普通 Whole-video 模式中执行 `VNImageRequestHandler.perform([request])`；单次失败就抛出 `NativeTrackingError.invalidVideo("Core ML frame N...")`，从而使整次运行 `Stopped`。这条错误本身不包含底层 NSError 的域/代码，不能据此断言特定帧损坏或一定是内存溢出。旧版普通模式始终把所有帧轨迹存在数组里，长视频还伴有额外内存风险。

## 本次补丁

- 同一帧最多尝试 2 次 Vision 推理；第一次失败后创建新的 `VNCoreMLRequest`，不更换 Core ML 模型或推理精度。
- 将单帧推理与解码放入 `autoreleasepool`，减少跨帧未及时释放的临时对象。
- 如果重试仍失败，保留该帧时间戳，输出缺失关键点，并在 CSV 末尾新增 `inference_failed=1`。`score=0` **不能**被当作正常无检测帧参与科研 QC；须据此列区分。
- 当连续失败 5 帧时停止；长视频模式在一个片段内累计失败 30 帧也会停止，避免静默掩盖系统性问题。
- 在 Xcode 控制台打印 NSError 域、错误码和 underlying error（如有）。
- Long-video 模式每 120 秒保存 CSV + manifest；格式版本从 1 增加到 2，记录每段失败帧数。**旧版 v1 输出文件夹无法在 v2 直接续跑，请新建输出文件夹**；原有文件不会被删除。

## Mac 使用步骤

1. 解压 `RodentDesktopNativeVisionRecovery.zip` 到 `~/Downloads`。
2. 打开项目根目录中的 `RodentDesktopNative.xcodeproj`；若模型未随工程复制，运行根目录 `python3 install_models.py` 安装你现有的 `.mlpackage`。
3. Xcode 选择 `My Mac`，使用 `Command+B`、`Command+R` 编译运行。
4. 视频大于 5 分钟时优先使用 `Long-video safe tracking`，选择**新的空输出文件夹**，点击 Start / Resume。
5. 如果再次停止，复制 Xcode Console 中 `Rodent Core ML attempt` 和 `Rodent long-video segment` 后面的 NSError 域、code、underlying error，并同时记录视频编码、分辨率、帧率，以及活动监视器内存使用情况。

## 必须单独验证

- 在失败发生的 16366 帧附近重复运行，比较是否总在同一时间戳失败；如果总在同一时间戳，也应检查编码、时间戳和帧画面。
- 用至少一个 1 小时视频测试总内存、连续时长、错误数和 resume 一致性。
- `inference_failed=1` 必须在后续 RodentPose/RodentLimb 行为分析 QC 中单独标记/排除，不能被插值伪造成有效检测。
- 当前仅完成静态语法检查（Linux Swift parser）和 Xcode 项目格式检查，尚未在你的 macOS/Xcode 上实测运行，不保证排除所有 Vision/Core ML 错误。
