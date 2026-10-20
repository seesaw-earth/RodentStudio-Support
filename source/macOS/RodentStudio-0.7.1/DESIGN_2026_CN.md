# 0.4.0 界面设计依据（只采用 2026 年的资料）

检索时只保留 2026 年发布或 2026 年更新过的资料（Apple 人机界面指南页面以页内“Change log”的 2026 日期为准）。

| 2026 资料 | 要点 | 在 0.4.0 中的做法 |
|---|---|---|
| Apple HIG · Sidebars（2026-06-08 更新） | 侧栏一般不超过两级；用 SF Symbols；允许隐藏侧栏；macOS 中不要把关键信息或操作放在侧栏底部 | “分析”侧栏只有两级：任务 → 动物；每行带状态符号；“添加视频…”放在侧栏工具栏顶部（⌘O）；侧栏可用系统按钮隐藏 |
| Apple HIG · Layout（2026-09-09 更新） | 按重要性排序；用渐进披露减少初始内容；macOS 不要把控件或关键信息放在窗口底部 | 步骤条和“上一步 / 继续”放在内容顶部；标定页左侧是画面、右侧是参数栏，高级预处理和次要判定放在可展开分组里 |
| Apple HIG · Sheets（2026-03-24 更新） | 复杂或较长的流程不要用 sheet；macOS 中需要反复输入并观察结果时用面板 / 窗口；Done 要和 Cancel 配对 | 标定不再是弹窗，而是主窗口里的一步，可边拖手柄边看区域；重命名、移除、批量套用都有“取消” |
| Apple HIG · Menus（2026-06-08 更新） | 需要进一步输入的操作在名称后加省略号；不可用的项目变暗；菜单图标少而有目的 | “添加视频…”“用于该任务的所有视频…”“重新分析…”等都带省略号；不满足前提的步骤变暗不可点；语言菜单只用一个地球图标 |
| WWDC26 Session 268 “Profile, fix, and verify: Improve app responsiveness with Instruments” | 不可避免的重活放到后台，界面保持响应；主线程同步写文件会造成卡顿 | 工作区 JSON 改为后台串行队列原子写入；标定画面在后台解码且只显示最新请求；保存的结果在后台读入；拖动时只重绘画布，松开后写一次 |
| WWDC26 Session 213 “Translate your app using agents in Xcode” | 先让文字可本地化，再在界面里检查截断与布局，并请母语者检查 | 所有界面文字为 `L(英, 中)`，中文取自三款原版 App 自己的翻译；切换语言立即生效；导出始终英文。仍建议请中文母语的实验人员通读一遍 |
| NN/g “Why So Many Info Tips Are Bad (and How to Make Them Better)”（2026-01-23） | 关键信息不要藏在提示气泡里，应放在界面上，紧挨相关控件 | 标定说明、颜色图例、保存状态、“尚未标定”等直接显示在画面旁边；悬停提示只用于快捷键 |
| NN/g “State of UX 2026: Design Deeper to Differentiate”（2026-01-16） | 用户要能掌控、看到系统在做什么，出错时能恢复；减少摩擦 | 模型由任务自动决定（不再让用户选），但可在“高级”中查看；运行有进度、可暂停 / 续跑；任何步骤都能返回；移除视频和批量套用都要确认且不删除原文件 |

## 结构变化

- 顶部三个区域：**分析**（实验流程）、**数据**（项目、任务、全部动物的表格）、**高级**（模型状态与测试、手动追踪 / 手动选模型、长视频工具、手动结果复核、RodentLimb 轨迹分析、任务目录、旧项目查看器）。⌘1 / ⌘2 / ⌘3 切换。
- 分析流程的顺序按原版 App：任务 → 视频与动物 → 校准 → 分析 → 复核与导出；最后一步可直接“下一只动物”。
- 键盘：⌘[ / ⌘] 上一步 / 下一步，⌘O 添加视频，⌘R 分析，⌘S 保存标定，⌘E 导出，方向键微调选中的手柄。

## 资料链接

- https://developer.apple.com/design/human-interface-guidelines/sidebars
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/sheets
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://developer.apple.com/videos/play/wwdc2026/268/
- https://nonstrict.eu/wwdcindex/wwdc2026/213/
- https://www.nngroup.com/articles/info-tips-bad/
- https://www.nngroup.com/articles/state-of-ux-2026/
