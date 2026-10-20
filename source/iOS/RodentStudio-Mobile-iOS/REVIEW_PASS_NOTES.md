# RodentPose — 过审清理、拖尾平滑、流畅度与界面精简（2026-10-14）

本轮基于上传的 `RodentPose 3` 工程修改。识别模型、文件格式、导出列名、语言策略不变；**所有分析指标的计算方式不变**（见“验证”）。

---

## 中文

### 1. 移除可能影响审核的药物名称

| 位置 | 原内容 | 现在 |
|---|---|---|
| 旋转范式的“阶段”选项 | 两个药物名称 + “自发 / 其他” | 无预设；用户点 **＋** 添加自己的标签，也可以不选 |
| 旋转范式简介 | 一种神经毒素名称和两种药物名称 | 改为“单侧损伤或其他单侧操作后……净旋转数用于量化左右不对称或比较实验条件” |
| 高架十字迷宫“为什么需要姿态” | 提到某类药物“更敏感” | “能提供开放臂时间之外的信息” |
| 备注输入框占位 | 含用药相关示例 | “实验条件、异常情况…” |
| 阶段输入框占位 | 含用药相关示例 | 删除（改为标签选择） |
| 明暗箱参考文献 | 一篇标题含药物类别名的 1980 年文献 | 换为 Takao & Miyakawa 2006（JoVE，doi:10.3791/104） |
| 旋转范式参考文献 | 两篇标题含神经毒素名称的文献 | 换为 Pycock 1980 *Turning behaviour in animals*（未附 DOI，提交前可自行补充） |
| 中文 README | 范式名后带神经毒素名称 | “旋转行为（单侧损伤模型）” |

`Localizable.xcstrings` 中对应的旧条目已删除，`EnglishTranslations.json` 已重新生成。全工程（代码、字符串表、翻译表、文档、docx 发布指南）已检索，不再含上述药物名称。

**阶段 / 条件**（所有范式统一）：范式预设（例如三箱的“社交偏好 / 社交新颖性”，分析会用到）+ 用户自定义标签 + **＋** 按钮。自定义标签按范式保存在本机，长按可移除；再点一次已选中的标签即取消选择。不选时各范式按第一个预设的默认逻辑分析，与之前一致。旧会话里保存的阶段值原样保留，作为用户数据显示。

### 2. 拖尾不再乱飞

**原因**：回看里的 2 秒拖尾直接连接模型原始的身体中心点（阈值 0.3，无去跳变、无平滑）；某一两帧检到反光、杯子或另一只鼠时，就会拉出一条横穿画面的线。标定页的“叠加已识别轨迹”把所有点连成一条线，缺口处也直接连上。

**做法**（新文件 `TrailSmoothing.swift`，只用于显示）：
1. 置信度门限：与分析一致（“关键点置信度阈值”）；
2. 去尖峰：每个点与前后 ±0.25 s 邻居的二维滑动中位数比较，用 MAD 作稳健尺度（下限约 ⅓ 体长），偏离过大的点丢弃——能处理连续几帧的误检；
3. 断线而不是硬连：缺口超过“最长插值缺口”，或相邻两点所需速度超过动物可能的速度（已标定时用“跳变速度上限”150 cm/s 换算成像素；未标定时约 15 个体长/秒），就开始新的一段；
4. 段内短缺口线性插值；
5. 段内高斯加权局部线性平滑（σ ≈ 0.08 s），段首段尾不会被“拉回”；
6. 少于 3 个点的段不画。

回看拖尾改为按时间渐隐、带深色描边；标定页轨迹按段绘制。结果页“轨迹与区域”等图在明显跳点处断开（只影响画线，不影响数值）。

**分析指标不受影响**：指标仍用原来的预处理（置信度 → 跳变过滤 → 插值 → 滑动平均）。没有改动它，是因为“数据”页的汇总表使用每个会话缓存的指标，悄悄改算法会让新旧会话混在同一张表里。若希望指标也使用更稳健的去尖峰，可以作为一个可选参数（默认关闭）再加。

### 3. 运行流畅度

- **识别提速（主要一项）**：UltralyticsYOLO 8.9.16 的姿态推理每帧都会额外生成一张标注图（新建 CIContext、全分辨率渲染、UIKit 绘图），App 从不使用。新增 `DirectPoseModel` 用同一个 Vision 请求、同一模型、同样的缩放方式直接推理，解码逻辑放在 `PoseDecoding.swift`，与原包算法逐位一致（已用随机数据对比 320 组输出、9600 个检测，0 差异）。每次运行的前 3 个有动物的帧会两条路径各算一次并逐点比对，任何差异立即退回原路径，所以**姿态结果与之前相同**。识别页的“ms/帧”会直接反映提速。
- 识别时预先分配逐帧数组，避免长视频反复扩容。
- **回看**：骨架和拖尾跟随播放器时钟逐帧刷新（TimelineView），与画面同步、不再重算整个页面；区域层和行为时间轴只在结果变化时重绘；时间读数改为 12 Hz；事件跳转、当前行为用预排序 + 二分查找；拖动时间轴时先快速定位、松手后精确定位。
- **标定拖动**：每次刷新只计算一次单应矩阵与区域（原来每个绘制点都会重新解一次）；会话级的映射和区域也做了缓存。
- **结果页**：不再在每次渲染时为每张图生成 CSV（只在点“复制数据”时生成）；折线图的数据行只计算一次；骨架绘制合并路径，减少绘制调用。
- **其他**：英文界面下带数字的文字翻译结果做缓存（原来每次渲染最多跑约 90 个正则）；系统语言只读一次；输入编号时不再触发整次重新分析（只有社交回避测试需要按编号配对）；标定页轨迹概览在后台预先计算。

### 4. 分析界面精简

- 分析流程各页（信息、标定、识别、结果）只保留操作和数据。说明文字统一收进卡片标题右侧的小 **ⓘ**：浅色、无底色、与其他按钮隔开，点开只是一张可下拉关闭的说明页，误触不会改变任何设置。
- **信息**：范式名旁 ⓘ = 该范式的完整知识（简介、为什么需要姿态、指标、拍摄与标定、文献）；动物信息、识别设置的说明都在各自的 ⓘ 里；识别范围只显示“约 N 帧”。
- **标定**：画面下只留手柄图例 + ⓘ（如何对准、放大镜、轨迹含义）；范式参数、分析时间段的 ⓘ 里是参数含义和指标定义。
- **识别**：三条使用提示移入 ⓘ。
- **结果**：只保留主要指标（大数字 + 量程条）、全部指标、图表、一行识别质量和操作按钮。标题旁的 ⓘ“结果说明”里有：指标说明、指标定义、图表说明、完整识别质量、方法说明（可复制）、汇总导出提示、“关于此范式”。每张图的 ••• 菜单也有“图表说明”；复制或分享的图片仍带图注。
- 新建分析时的拍摄建议也收进 ⓘ。完整知识库仍在底部“范式库”标签页。

### 5. 验证（本环境无 Xcode / 真机）

- 分析引擎、拖尾平滑、解码在 Linux 上用 Swift 6.0.3（Swift 5 语言模式）编译。
- **回归**：16 个范式 × 所有场地类型，用同一合成轨迹分别跑原版和新版引擎：所有指标、警告数、图表数、区域数逐项完全相同（371 行）。唯一差异是未标定模式下的轨迹图在跳点处断开。
- 拖尾平滑合成测试 15 项全部通过（单帧尖峰、4 帧反光、0.7 s 缺口断开、0.2 s 缺口插值、低置信度、身份交换式跳变断开、静止抖动、真实快速逃跑不被切断）；30 分钟 30 fps 视频约 80 ms。
- 解码与原包算法逐位一致（见上）。
- 整个 App 用 SwiftUI / UIKit / AVFoundation / Vision / Core ML / Charts / UltralyticsYOLO / PhotosUI 的接口桩做完整类型检查：0 错误 0 警告（原版同样为 0，用于校准接口桩）。
- 工程自带的 `check_localizations.py`、`check_english_exports.py`（含 Swift 运行时测试）、`check_environment_injection.py` 均通过；另检查了所有 `L10n.tr` 字面量都有翻译。
- 顺带修复：字符串表中 30 个由 Xcode 自动提取、缺翻译的符号类条目（如 “—”、“1×”）补上了原样翻译，语言选择器里的“中文 / English”改为不翻译的固定文字，`check_localizations.py` 由 30 个问题变为 0。
- 构建号 `CURRENT_PROJECT_VERSION` 由 2 改为 3，便于重新上传。

### 6. 请在真机上确认

1. 识别：开始识别后“ms/帧”应明显下降；结果与旧版一致（可对同一视频比较检出率与几个指标）。
2. 回看：拖尾平滑、无横穿画面的线；播放时骨架与画面同步；拖动时间轴流畅。
3. 标定：拖手柄跟手；叠加轨迹按段显示。
4. 信息页：＋ 添加标签、长按移除、再次点击取消选择；旋转范式没有预设。
5. 各 ⓘ 能打开、能下拉关闭；结果说明里的“关于此范式”能进入。
6. 中英文各走一遍。

---

## English (summary)

- **Drug names removed** (App Review): the rotation assay's two drug-named phase presets, the neurotoxin and drug names in its description, a drug-class phrase in the EPM text, dose/treatment placeholders, and references whose titles name compounds (replaced by Takao & Miyakawa 2006 and Pycock 1980). Phase / condition is now presets (where the analysis uses them) + the researcher's own labels added with **+**, and may be left empty.
- **Trail no longer flies**: the Review trail and the calibration overlay now use a display-only path (`TrailSmoothing.swift`): confidence gate → moving-median/MAD spike rejection → segment breaks at long gaps or impossible speeds → short-gap interpolation → Gaussian local-linear smoothing. Metrics are unchanged (verified: identical outputs for all 16 assays).
- **Speed**: inference skips the per-frame annotated image that UltralyticsYOLO 8.9 renders for pose (same Vision request, bit-exact decoding, cross-checked against the package on the first frames of every run with automatic fallback); Review overlay driven by the player clock with static layers cached; calibration drag computes the homography once per update; results no longer build CSV text on every redraw; cached translations of interpolated strings; no re-analysis while typing the subject ID.
- **Cleaner analysis screens**: explanations moved behind small ⓘ buttons (sheets); the result screen shows numbers and figures only, with definitions, figure notes, the full quality report and the Methods text in "About these results".
- Verified with Swift 6.0.3 on Linux (engine regression, trail tests, bit-exact decoder test, full-app type-check against API stubs, the project's three check scripts). Not built with Xcode or run on a device. Build number bumped to 3.
