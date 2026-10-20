# 原版 App 的图在桌面版中的对应

位置：分析 → 复核与导出 → **结果**。图由已保存的追踪数据和“校准”中的设置计算，不重新运行模型或追踪。导出：结果页底部“导出结果与图表…”，每只动物新建一个文件夹（`<动物编号>_<任务ID>_results_<时间>`）。PNG 按 iOS 的方式渲染：卡片宽 420 pt、3 倍、浅色外观。

## RodentPose 1.0（`Views/PoseResultFigures.swift`）

| 原版（iOS 文件） | 桌面版 | 导出文件 |
|---|---|---|
| ResultStepView.KeyResultCard + ScaleBar（ReportFormatting.MetricScale） | `RPKeyResultCard` / `RPScaleBar` / `RPMetricScale` | `rodentpose_figure_00_key_result.png` |
| MetricGrid / MetricTile | `RPMetricGrid` / `RPMetricTile` | `rodentpose_metrics.csv`（metric_key, metric, value, unit，同 iOS Exporter.metricsCSV） |
| ReportBlocks.ArenaPlotView（区域、热图、轨迹、起终点、点、箭头、区域标签、比例尺、热图图例） | `RPArenaPlotView` | `rodentpose_figure_NN_<标题>.png` |
| TimelineChart（行为时间轴 + 时段） | `RPTimelineChart` | 同上 + `.csv` |
| BarsChart（竖 / 横 / 分组，数值标注，参考线） | `RPBarsChart` | 同上 + `.csv` |
| LineChartView（时段、多系列、>4 条按试次叠加+均值、参考线、读数） | `RPLineChartView` | 同上 + `.csv` |
| PolarPlotView（平方根扇区、平均向量、参考方向） | `RPPolarPlotView` | 同上 + `.csv` |
| TableBlockView | `RPTableBlockView` | 同上 + `.csv` |
| QualityCard（检出率、关键点有效比例） | `RPQualityCard` | `rodentpose_figure_quality.png` |
| 方法说明 | 方法卡（可复制） | `rodentpose_methods_quality.txt`，`rodentpose_report.json`（同 iOS reportJSON 结构 + 桌面元数据） |

配色 `RPPalette` 与 iOS `Palette` 相同（Okabe–Ito、区域色、热图色阶）。每张图的菜单：复制图像、保存图像、复制数据（CSV，英文；同 iOS BlockCSV）。

## RodentLimb 1.1.2（`Views/LimbResultFigures.swift`）

| 原版（UI/ResultSections.swift、DesignSystem.swift） | 桌面版 | 导出文件 |
|---|---|---|
| HeroMetrics / NoteList / MeasureList | `RLHeroMetrics` / `RLNoteList` / `RLMeasureList` | `rodentlimb_<code>_figure_01_summary.png`、`_02_measures.png` |
| TSTMotionCard / TSTPerMinuteCard | `RLTSTMotionCard` / `RLTSTPerMinuteCard` | `_motion.png`、`_immobility_per_minute.png`，`rodentlimb_tst_immobility_bouts.csv`、`_per_minute.csv` |
| CylinderUseCard / CylinderTimelineCard / CylinderEventList | `RLCylinderUseCard` / `RLCylinderTimelineCard` / `RLCylinderEventList`（只读） | `_forelimb_use.png`、`_contacts_over_time.png`，`rodentlimb_cyl_contacts.csv` |
| FootfallCard / GaitPatternCard / PawTableCard / PhaseCard / FootprintCard | `RLFootfallCard` / `RLGaitPatternCard` / `RLPawTableCard` / `RLPhaseCard` / `RLFootprintCard` | `_footfall_first_2s.png` 等，`rodentlimb_gait_strides.csv`、`_footprints.csv` |
| Exporter.sessionFiles / methods | `LimbResultExport` | `rodentlimb_<code>_summary.csv`、`_result.json`、`_methods.txt` |

## RodentFlow 1.3（`Views/FlowResultFigures.swift`，指标定义 `ScienceFlow/FlowMetricCatalog.swift`）

| 原版（AssayVisuals.swift、UIComponents.swift、ResultDetailView.swift、AssayCatalog.swift） | 桌面版 | 导出文件 |
|---|---|---|
| MetricGrid（AssayCatalog 名称 / 单位 / 小数位，主指标在前） | `RFMetricGrid` + `RFMetricCatalog` | `rodentflow_figure_01_results.png`，`rodentflow_metrics.csv` |
| ArenaPlotView 轨迹 / 热图 + 区域 + 标记（只画分析窗口） | `RFArenaPlotView`（标记在“校准”中移动） | `rodentflow_figure_02_arena_path.png`、`_03_arena_heatmap.png` |
| FreezingTimelineView + FreezingRaster | `RFFreezingTimelineView` / `RFFreezingRaster` | `rodentflow_figure_02_freezing.png` |
| SeriesChartView（by_bin / by_cs 为柱状，其余折线） | `RFSeriesChartView` | `rodentflow_figure_NN_<key>.png`，`rodentflow_series_<key>.csv` |
| Sequence & labels、Methods（methodsNote、定义、参数）、FlagList | 结果页对应卡片 | `rodentflow_methods.txt`，`rodentflow_assay_result.json` |
| — | 分析窗口内的质心样本、区域切换 | `rodentflow_centroid_analysis_window.csv`、`rodentflow_zone_events.csv` |

界面中文使用 RodentFlow 自己的翻译（`Resources/RodentFlowChinese.json`，由原版 Localizable.xcstrings 提取）；导出始终英文。

## 与原版的差别（如实）

- 桌面版没有 iOS 的分享面板；改为复制图像 / 保存 PNG / 复制 CSV。
- RodentFlow 结果图上的物体 / 目标标记不能拖动（原版可在结果页拖动）；桌面版只在“校准”中移动，避免两个来源。
- RodentLimb 圆筒触壁列表只读（不能改标签）；“点击图表跳到该时刻”未接入。
- 颜色在 macOS 上用对应的系统色（卡片 / 内嵌背景），PNG 导出固定为浅色外观；与 iOS 截图可能有细微差别。
