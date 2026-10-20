# RodentPose 1.0 — interface and usability refresh / 界面与易用性优化

This is an edited copy of the uploaded RodentPose 1.0 project (TouchFix · Language · EnglishData · CrashFix). The analysis engine, the model, file formats, exports and the language policy are unchanged; this pass changes how the app looks and how it is used.

本版本基于上传的 RodentPose 1.0 工程修改。分析算法、模型、文件格式、导出内容与语言策略均未改变；本次只改动外观与操作体验。

---

## English

### What guided the changes

- **Apple HIG and iOS 26 (Liquid Glass).** Let system bars and the scroll-edge effect do the work instead of custom material bars; keep the accent color for things that can be tapped; 44 × 44 pt touch targets; text no smaller than 11 pt; contrast ≥ 4.5 : 1 for body text; never color alone; respect Reduce Motion; add VoiceOver labels and actions to custom controls.
- **Charts.** Every chart gets a scale or legend; inspect values by touching (scrubbing); consistent series order; a data twin (copy as CSV); repeated traces drawn as muted lines with an emphasized mean rather than a rainbow.
- **Usable scientific software** (List et al., *Ten simple rules…*). Sensible defaults, input validation that says what happened, reproducible exports, standard formats.
- **Behavior-coding tools** (e.g. BORIS). Review is about jumping between scored events, not scrubbing blind.
- **Precision touch.** A finger hides what it is placing; measuring apps solve this with an offset or a magnifier.

### Changes by screen

**Everywhere**
- New palette. Accent blue matched to the app icon (light `#1B66E0`, dark `#3D8BFF`, plus increased-contrast variants in the asset catalog). Category and status colors now have light and dark values that pass WCAG AA as text on cards and the background (the old amber, coral and teal were 2.2–3.0 : 1). Solid fills that carry white symbols use deep values that pass in both appearances.
- Chart series order fixed to blue → green → vermillion → purple (Okabe–Ito; validated for color-vision deficiency).
- Flat paradigm badges (no gradients); card-header icons in secondary ink, so blue means "interactive".
- Banners: icon carries the status color, text stays in primary ink. Several warnings collapse into one expandable card.
- Toast confirmations ("Summary copied", "Image copied") with a success haptic and a VoiceOver announcement, replacing the label that stayed "Copied" forever.
- Buttons show a disabled state; numeric fields warn when a value was clamped to its valid range.
- Animations become instant with Reduce Motion.
- On iOS 26 the step bar and the bottom action bar use `safeAreaBar`, so they get the system scroll-edge effect; iOS 17–18 keep the standard bar material. The iOS 26 code is behind `#if compiler(>=6.2)`, so the project still builds with Xcode 16.

**Home**
- The gradient banner is replaced by a quiet card: the five workflow steps (wrapping instead of shrinking in English), the New analysis button, and a small dark "video frame" with the colored keypoint skeleton — the app's signature.
- New **Continue where you left off** list (drafts, paused or failed sessions) with video thumbnails.
- **Recent results** shows completed sessions only. The headline measure name is shown in the interface language (it is stored in English).

**Session workspace**
- Info: the animal form is a grid that sizes its label column to the longest label (the fixed 44 pt column truncated English labels); a hint explains why the subject ID matters.
- Calibration: handles are a ring with an exact center dot and an outside label (the old label covered the point being aligned); a **magnifier** appears in the opposite top corner while dragging; a light haptic on grab; VoiceOver users can nudge handles with Move left / right / up / down; a color legend explains yellow / purple / cyan handles; zone labels have a halo so they stay legible on video.
- Results: section links (Summary · Figures · Quality · Methods); the headline measure is a plain card with a large number and, for bounded measures, a scale (−1…+1 indices with 0 = no preference; 0–100 % with 50 % = chance for alternation); "All measures"; the session notes are shown under the title; quality gets a verdict (good / acceptable / low).
- Figures: a ••• menu and long-press menu on every figure — **Copy image**, **Share image…**, **Copy data (CSV, English)**; heat maps have a color scale; trajectory maps explain start/end markers; line charts can be scrubbed to read values; looming traces are muted with a bold mean; timelines size their label column to the content and read as "Bouts: n; total s" in VoiceOver.

**Review**
- **Previous / Next event** buttons with "n / N"; the behavior legend is also the filter for which events to step through.
- Read-outs are neutral chips with status icons; VoiceOver labels for every transport button; the timeline is adjustable by swipe up/down (±5 s).

**Data**
- Thumbnails in rows; long-press menu (Open, Delete video copy, Delete this session) matching the swipe actions; selected filter chips invert instead of relying on hue; export summary is a single button.

### Bilingual and data policy

All 68 new interface strings are in `Localizable.xcstrings` with 简体中文 and English; `EnglishTranslations.json` was regenerated. New strings use static keys with `String(format:)`, so no new regex patterns were needed. Copied figure data goes through `L10n.english`, so it is English like every export.

### Verification done here

- Whole app type-checked against SwiftUI / UIKit / Charts API stubs (Swift 5.10, Linux). Not compiled with Xcode, not run on a device.
- Engine regression tests (synthetic ground truth for all 16 paradigms, export round-trips) plus new tests for the headline scale and figure CSVs (English-only across 88 figures): all pass.
- `tools/check_localizations.py`, `tools/check_english_exports.py` (including its Swift runtime test) and `tools/check_environment_injection.py`: pass.

### Please test on a device

1. Light, dark and **Increase Contrast**; Larger Text up to AX sizes (Info form, results, step bar).
2. Calibration: drag each handle type and check the magnifier position, haptic, and that dragging still never scrolls the page; nudge with VoiceOver actions.
3. Results: section links, figure menu (copy image → paste into Notes; share; copy data → paste into Numbers), chart scrubbing.
4. Review: Previous / Next with and without a behavior filter.
5. iOS 26 vs iOS 17/18: bars at top and bottom of the session workspace and Assay detail.
6. Switch 中文 / English and repeat a quick pass.

---

## 中文

### 依据

- **Apple 人机界面指南与 iOS 26（Liquid Glass）**：系统栏与滚动边缘效果代替自绘材质栏；强调色只用于可点按元素；触控区域 ≥ 44 pt；文字 ≥ 11 pt；正文对比度 ≥ 4.5 : 1；不单靠颜色传达信息；尊重“减弱动态效果”；为自定义控件补充 VoiceOver 标签与操作。
- **图表**：每张图都有标尺或图例；可触摸查看数值；系列颜色顺序固定；提供数据副本（CSV）；重复曲线用浅色细线 + 加粗均值，而不是彩虹配色。
- **易用科研软件的十条原则**：合理默认值、输入校验并说明结果、可复现的导出、标准格式。
- **行为编码工具（如 BORIS）**：回看的核心是在已判定事件之间跳转。
- **精确触控**：手指会挡住要对准的位置，测量类 App 通常用偏移或放大镜解决。

### 各页面改动

**全局**：新配色（强调蓝与图标一致，含深色与“增强对比度”变体；分类与状态色在浅色 / 深色下作为文字均达 WCAG AA）；图表系列顺序为蓝 → 绿 → 朱红 → 紫（Okabe–Ito，已做色觉缺陷校验）；范式图标去掉渐变；卡片标题图标改为次要色；提示条文字保持主色、图标带状态色，多条警告合并为一张可展开卡片；复制等操作改为短暂提示 + 触感反馈 + VoiceOver 播报；按钮有禁用态；数值超出范围时会提示已按边界计算；开启“减弱动态效果”时动画改为瞬时；iOS 26 上步骤栏与底部操作栏使用 `safeAreaBar`（Xcode 16 仍可编译）。

**首页**：渐变横幅改为简洁卡片（五个步骤、“新建分析”按钮、深色画面中的彩色骨架作为标志）；新增“继续未完成的分析”（含视频缩略图）；“最近结果”只列已完成分析，主要指标名称按界面语言显示。

**分析流程**：信息页表单改为自适应标签宽度的网格（原 44 pt 固定宽度会截断英文）；标定手柄改为“圆环 + 中心点 + 外侧标签”，拖动时在对侧上角显示**放大镜**，抓取时轻触感反馈，VoiceOver 可上下左右微调，并有手柄颜色图例；结果页增加分区跳转（概要 · 图表 · 质量 · 方法），主要指标改为大号数字 + 量程条（指数 −1…+1，0 = 无偏好；交替率 50% = 随机水平），显示备注，识别质量给出结论。

**图表**：每张图有 ••• 菜单与长按菜单——复制图像、分享图像、复制数据（CSV，英文）；热图有颜色标尺；轨迹图说明起点 / 终点；折线图可触摸读数；逼近刺激的多条速度曲线改为浅色 + 加粗均值；时间轴标签列自适应。

**回看**：新增“上一个 / 下一个事件”与“n / N”计数，图例同时作为事件筛选；读数改为中性标签 + 状态图标；所有播放按钮有 VoiceOver 标签，时间轴可上下轻扫 ±5 秒。

**数据**：列表显示缩略图；长按菜单（打开、删除视频副本、删除此分析）与左滑操作一致；筛选标签选中时反色显示；导出汇总表改为单个按钮。

### 双语与数据

新增 68 条界面文字均已写入 `Localizable.xcstrings`（简体中文 + English），并重新生成 `EnglishTranslations.json`。复制的图表数据经 `L10n.english` 处理，与所有导出一样为英文。

### 已完成的验证

整套源码已在 Linux 上用 SwiftUI / UIKit / Charts 接口桩做类型检查（未经 Xcode 编译、未上真机）；16 个范式的合成数据回归测试与新增的量程 / 图表 CSV 测试全部通过；工程自带的三个检查脚本均通过。

### 请在真机上测试

浅色 / 深色 / 增强对比度与大字号；标定拖动、放大镜与触感、拖动时页面不滚动；结果页跳转、图表菜单与触摸读数；回看事件跳转；iOS 26 与 iOS 17/18 的上下栏；中英文切换后各走一遍。

---

## Sources / 参考

- Apple, Adopting Liquid Glass — https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Apple, `safeAreaBar(edge:alignment:spacing:content:)` — https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)
- Apple HIG: Accessibility — https://developer.apple.com/design/human-interface-guidelines/accessibility ; Color — https://developer.apple.com/design/human-interface-guidelines/color ; Charting data — https://developer.apple.com/design/human-interface-guidelines/charting-data ; Charts — https://developer.apple.com/design/human-interface-guidelines/charts ; Feedback — https://developer.apple.com/design/human-interface-guidelines/feedback ; Onboarding — https://developer.apple.com/design/human-interface-guidelines/onboarding
- List M, Ebert P, Albrecht F. Ten simple rules for developing usable software in computational biology. PLoS Comput Biol 2017 — https://limswiki.org/index.php/Journal:Ten_simple_rules_for_developing_usable_software_in_computational_biology
- Friard O, Gamba M. BORIS: a free, versatile open-source event-logging software for video/audio coding and live observations. Methods Ecol Evol 2016 — https://iris.unito.it/handle/2318/1589424
- Wong B. Color blindness. Nature Methods 8, 441 (2011) — https://doi.org/10.1038/nmeth.1618
- Touch offset for measuring on iPhone (forum discussion) — https://forums.sketchup.com/t/iphone-app-add-offset-to-touch-point-to-make-measure-tool-usable/313248
- Swift Charts selection (`chartXSelection`) — https://antongubarenko.substack.com/p/swiftui-charts-interactivity-part
