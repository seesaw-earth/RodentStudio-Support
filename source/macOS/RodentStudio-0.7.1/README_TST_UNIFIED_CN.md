# RodentStudio 0.7.1 — TST 完整融入统一任务流程

## 设计原则

所有实验均使用同一份 RodentStudio 工作区与树形层级：

`Project → Task → Group（可选）→ Animal → 录制日期 · 实验次数`。

唯一与其他实验不同的是 **TST 的录像处理算法**：一段多格原始录像经过 TSTScorer 6 的格子检测、key-frame、轮廓运动评分后，产生多个 chamber-level `ChamberSummary`。随后每个有效格子转化为同一任务下、具有唯一 `VideoRecord.id` 的标准动物 Session。**不会把多只小鼠强行算成一只动物，也不会把多个帧当作独立动物。**

## 用户操作

（界面已按 macOS 使用习惯重做，详见 `TST_UX_REVISION_CN.md`。）

1. `Analyse → New Task` 选择 `Tail Suspension Test — Multi-Chamber`，像旷场 / 高架迷宫一样创建 Task。
2. 点工具栏 `添加 TST 录像…`（⌘O）或把视频拖到侧边栏，直接选择视频；分析窗口按 **视频 › 格子 › 关键帧 › 结果与小鼠** 四步进行，左边看画面、右边调设置，底部固定“返回 / 取消（Esc）/ 下一步（回车）”。
3. 在“结果与小鼠”表中逐格填写小鼠编号、分组、性别、实验次数（实验日期整段录像只填一次）。已有小鼠沿用原分组；实验次数自动取下一个可用编号；不需要的格子可取消勾选，不生成记录。
4. 点 `保存 N 次实验`。多个格子共享一份存入 Application Support 的原始录像与一次计算结果；各格写入**同一个 WorkspaceStore**，并立即出现在树形导航。
5. 点击每只小鼠的日期 / 实验次数进入标准 Session：实验信息、整段录像的共享设置、该鼠指标与曲线、复核（结论选中即保存）；各鼠可独立排除。
6. Task 的 `Compare groups`、`Export`，Group 的汇总、Animal 的多次实验曲线和常规任务完全相同，读取统一的 `TaskDataModel`/`SessionMetricSummary`。

## 重要实现

- `WorkspaceStore.VideoRecord.tstChamber` 是可选的 `recordingID/chamber` 引用；旧项目、旧 Session 无须迁移。
- `WorkspaceStore.registerTSTRecording()` 在写入前检查已有动物实验次数冲突及同录像重复动物；同一次录像不可把两个格子登记成同一只鼠。
- `TSTTaskArchive` 仅储存分析 provenance（原录像、逐帧 QC、设置及原始 TSTScorer 指标），**不是另一份项目/动物数据库**。
- `TSTSessionMetrics.load()` 把逐格结果转换为通用指标，复用统计、分组和导出代码。
- 旧版 0.7.0 的 TST archive 保留原样，未擅自删除或强制导入缺失日期/实验次数的旧数据；如先前已有实验请另行核对数据迁移。
- 原版 RodentPose、RodentLimb、RodentFlow 计算代码以及 TST `Scorer.swift`、`MotionAnalyzer.swift` 和现有 Core ML 模型内容保持不变。

## 验证限制

本包完成了全工程 Swift **语法解析**、Xcode 项目文件检查、结构接线静态验证、与算法文件的哈希比对。但构建环境不包含 macOS SDK/Xcode，**无法代替 Mac 上的 Xcode 全工程 typecheck/build、GUI 实测、真实视频验证或科研算法对照**。

在 MacBook 执行：

```bash
cd ~/Downloads/RodentStudio-0.7.1
python3 DeveloperTools/verify_tst_unified.py
open RodentStudio.xcodeproj
```

Xcode 中选 `RodentStudio → My Mac`，先 `Product → Clean Build Folder`，再 `⌘B` 和 `⌘R`。建议重点测试：一段三格录像创建三个小鼠 Session、重复录像冲突、不同组别统计、日期和 Session 编号修改、重新启动后源视频仍可打开、任务/小鼠统一 CSV 导出。

**App Store 发布前必须把示例 Bundle ID `com.ziqingshi.RodentStudio` 改成 App Store Connect 对应的真实 ID。** 版本为 0.7.1，Build 6；如目标 App Store 记录已使用过 Build 6，请改成更高、未使用的 Build Number。

**科学限制：** TST 的阈值与分割/姿态判定未经过盲法人工评分验证，当前不应宣称已验证的自动行为评分。软件功能测试和算法科学有效性是不同的工作。
