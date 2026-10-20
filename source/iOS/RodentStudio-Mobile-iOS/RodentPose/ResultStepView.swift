// ResultStepView.swift — step 4: dashboard of the analysis (headline metric, all metrics, plots,
// quality, methods) and exports.

import SwiftUI
import UIKit

struct ResultStepView: View {
    @ObservedObject var flow: SessionFlowModel
    @Binding var showReview: Bool
    @Binding var showExport: Bool
    @State private var toast: String?

    private var s: Session { flow.session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let r = flow.report {
                    NoticeList(notices: r.warnings)
                    if let primary = r.primary {
                        KeyResultCard(metric: primary, category: s.paradigm.category)
                    }
                    let others = r.metrics.filter { $0.key != r.primary?.key }
                    if !others.isEmpty {
                        Text(L10n.tr("全部指标"))
                            .font(.headline)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                        MetricGrid(metrics: others)
                    }
                    ForEach(r.blocks) { b in ReportBlockView(block: b) { toast = $0 } }
                    QualitySummary(quality: r.quality)
                    actionsCard(r)
                } else if flow.hasPose {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.tr("正在分析…")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ContentUnavailableView(L10n.tr("还没有姿态数据"), systemImage: "sparkles", description: Text(L10n.tr("先在“识别”页运行模型。")))
                }
            }
            .screenContent()
            .padding(.vertical, 14)
        }
        .toast($toast)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ParadigmBadge(paradigm: s.paradigm, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(s.displaySubject).font(.title3.weight(.bold))
                        if !s.group.isEmpty { Tag(text: s.group, color: Palette.category(s.paradigm.category)) }
                    }
                    Text([s.paradigm.title, s.sessionLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if flow.isAnalyzing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel(L10n.tr("正在分析…"))
                }
                if let r = flow.report {
                    // Definitions, figure notes, quality details and the Methods text — on demand.
                    InfoButton(title: L10n.tr("结果说明")) { ResultGuide(session: s, report: r) }
                }
            }
            if !s.notes.isEmpty {
                Label {
                    Text(s.notes).lineLimit(2)
                } icon: {
                    Image(systemName: "note.text").foregroundStyle(.secondary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.tr("备注") + ": " + s.notes)
            }
        }
    }

    // MARK: Actions

    private func actionsCard(_ r: AnalysisReport) -> some View {
        Card {
            CardHeader(L10n.tr("下一步"), symbol: "arrow.forward.circle")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                Button {
                    showExport = true
                } label: {
                    Label(L10n.tr("导出"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    UIPasteboard.general.string = Exporter.textSummary(session: s, report: r)
                    toast = L10n.tr("已复制摘要")
                } label: {
                    Label(L10n.tr("复制摘要"), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    withAnimation(Motion.snappy) { flow.step = .calibrate }
                } label: {
                    Label(L10n.tr("调整区域 / 阈值"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    showReview = true
                } label: {
                    Label(L10n.tr("回看"), systemImage: "play.rectangle")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(flow.videoURL == nil)
            }
        }
    }
}

// MARK: - Result explanations

/// Everything that explains a result, kept off the result screen: metric notes and definitions,
/// figure notes, the full quality report, the Methods paragraph and the paradigm background.
struct ResultGuide: View {
    let session: Session
    let report: AnalysisReport
    @State private var copied = false

    var body: some View {
        let explained = report.metrics.filter { ($0.info ?? "").isEmpty == false }
        let captioned = report.blocks.filter { ($0.caption ?? "").isEmpty == false }
        let methods = report.methods.joined(separator: "")

        if !explained.isEmpty {
            InfoSectionTitle(L10n.tr("指标说明"))
            ForEach(explained) { m in InfoParagraph(m.title, m.info ?? "") }
        }
        InfoSectionTitle(L10n.tr("指标定义"))
        ForEach(session.paradigm.measures, id: \.self) { m in InfoParagraph(m.name, m.definition) }
        if !captioned.isEmpty {
            InfoSectionTitle(L10n.tr("图表说明"))
            ForEach(captioned) { b in InfoParagraph(b.title, b.caption ?? "") }
        }
        QualityCard(quality: report.quality)
        if !methods.isEmpty {
            InfoSectionTitle(L10n.tr("方法说明（可用于论文 Methods）"))
            Text(methods)
                .font(.footnote)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                UIPasteboard.general.string = methods
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    copied = false
                }
            } label: {
                Label(copied ? L10n.tr("已复制方法说明") : L10n.tr("复制方法说明"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        }
        InfoSectionTitle(L10n.tr("汇总与导出"))
        InfoParagraph(L10n.tr("汇总多只动物：在“数据”页导出汇总表（CSV），可直接导入 RodentFlow 的“组间分析”或 R / Python。"))
        NavigationLink {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ParadigmHero(paradigm: session.paradigm)
                    ParadigmKnowledge(paradigm: session.paradigm)
                }
                .screenContent()
                .padding(.vertical, 12)
            }
            .background(Palette.canvas)
            .navigationTitle(session.paradigm.title)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label(L10n.tr("关于此范式"), systemImage: "books.vertical")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }
}

// MARK: - Key result

/// The headline measure: large number in primary ink, unit, definition, and — for bounded
/// measures — a scale showing where the value sits (with the conventional reference point).
struct KeyResultCard: View {
    let metric: MetricValue
    let category: ParadigmCategory
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 44

    var body: some View {
        Card {
            Text(metric.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.formatted)
                    .font(.system(size: valueSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                if !metric.unit.isEmpty && metric.value != nil {
                    Text(metric.unit).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .animation(Motion.snappy, value: metric.value)
            if let scale = MetricScale(metric), let v = metric.value {
                ScaleBar(scale: scale, value: v, color: Palette.categoryFill(category))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(metric.info ?? "")
    }
}

struct ScaleBar: View {
    let scale: MetricScale
    let value: Double
    let color: Color

    private func fraction(_ x: Double) -> CGFloat {
        let span = scale.range.upperBound - scale.range.lowerBound
        return CGFloat(min(max((x - scale.range.lowerBound) / span, 0), 1))
    }

    private func label(_ x: Double) -> String {
        scale.range.upperBound == 100 ? String(format: "%.0f%%", x) : (x > 0 ? String(format: "+%.0f", x) : String(format: "%.0f", x))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                let origin = fraction(scale.reference ?? scale.range.lowerBound)
                let x = fraction(value)
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.inset).frame(height: 8)
                    Rectangle()
                        .fill(color)
                        .frame(width: max(2, abs(x - origin) * w), height: 8)
                        .offset(x: min(x, origin) * w)
                        .clipShape(Capsule())
                    if scale.reference != nil {
                        Rectangle().fill(Color.primary.opacity(0.55)).frame(width: 1.5, height: 16)
                            .offset(x: origin * w - 0.75)
                    }
                    Circle()
                        .fill(color)
                        .overlay { Circle().strokeBorder(Palette.card, lineWidth: 2) }
                        .frame(width: 14, height: 14)
                        .offset(x: x * w - 7)
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            HStack {
                Text(label(scale.range.lowerBound))
                Spacer()
                if let ref = scale.referenceLabel { Text(ref) }
                Spacer()
                Text(label(scale.range.upperBound))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Quality

/// One line on the result screen; the full report is in the result guide.
struct QualitySummary: View {
    let quality: QualityInfo

    var body: some View {
        let level = QualityCard.level(quality)
        HStack(spacing: 10) {
            Image(systemName: Banner.icon(level?.1 ?? .info))
                .foregroundStyle(Banner.color(level?.1 ?? .info))
                .accessibilityHidden(true)
            Text(L10n.tr("识别质量")).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(String(format: L10n.tr("检出率 %.1f%%"), quality.detectionRate * 100))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(level?.0 ?? "")
    }
}

struct QualityCard: View {
    let quality: QualityInfo

    static func level(_ quality: QualityInfo) -> (String, Banner.Style)? {
        guard quality.framesInWindow > 0 else { return nil }
        if quality.detectionRate >= 0.95 { return (L10n.tr("检出率良好"), .success) }
        if quality.detectionRate >= 0.8 { return (L10n.tr("检出率尚可，建议抽查回看"), .warning) }
        return (L10n.tr("检出率偏低，请先回看检查"), .error)
    }

    private var level: (String, Banner.Style)? { Self.level(quality) }

    var body: some View {
        Card {
            CardHeader(title: L10n.tr("识别质量"), symbol: "checkmark.seal") {
                if let level {
                    Label(level.0, systemImage: Banner.icon(level.1))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Banner.color(level.1))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            VStack(spacing: 6) {
                InfoRow(key: L10n.tr("检出率（分析时间段）"), value: String(format: "%.1f%%", quality.detectionRate * 100))
                InfoRow(key: L10n.tr("分析帧数"), value: "\(quality.framesInWindow) / \(quality.frames)")
                InfoRow(key: L10n.tr("分析时长"), value: Fmt.clock(quality.windowSeconds))
                InfoRow(key: L10n.tr("采样率"), value: String(format: "%.1f Hz", quality.sampleRate))
                InfoRow(key: L10n.tr("头朝向有效"), value: String(format: "%.1f%%", quality.headDirectionRate * 100))
                if quality.unit == "cm" {
                    InfoRow(key: L10n.tr("比例"), value: String(format: "%.1f px/cm", quality.pxPerUnit))
                }
            }
            if !quality.keypointRates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("各关键点有效比例")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        ForEach(KP.allCases) { k in
                            let v = k.rawValue < quality.keypointRates.count ? quality.keypointRates[k.rawValue] : 0
                            GridRow {
                                HStack(spacing: 6) {
                                    Circle().fill(Palette.keypoint(k.rawValue)).frame(width: 7, height: 7)
                                    Text(k.title).font(.caption).lineLimit(1).fixedSize()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(k.title)
                                .accessibilityValue(String(format: "%.0f%%", v * 100))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Palette.inset)
                                        Capsule().fill(Color.accentColor.opacity(0.75))
                                            .frame(width: g.size.width * CGFloat(min(1, max(0, v))))
                                    }
                                }
                                .frame(height: 7)
                                .accessibilityHidden(true)
                                Text(String(format: "%.0f%%", v * 100))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Export sheet

struct ExportSheet: View {
    @ObservedObject var flow: SessionFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var kinds: Set<ExportKind> = [.metrics, .frames]
    @State private var working = false
    @State private var share: SharePayload?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ExportKind.allCases) { k in
                        Button {
                            if kinds.contains(k) { kinds.remove(k) } else { kinds.insert(k) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: k.symbol).foregroundStyle(.secondary).frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(k.title).foregroundStyle(.primary)
                                    Text(k.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: kinds.contains(k) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(kinds.contains(k) ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(kinds.contains(k) ? .isSelected : [])
                    }
                } footer: {
                    Text(L10n.tr("CSV 为 UTF-8（带 BOM），Excel 可直接打开中文。列名为英文，便于 Python / R 读取。"))
                }
                if let errorText {
                    Section { Label(errorText, systemImage: "xmark.octagon.fill").foregroundStyle(Palette.danger) }
                }
            }
            .navigationTitle(L10n.tr("导出"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("关闭")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button(L10n.tr("导出")) { export() }.disabled(kinds.isEmpty)
                    }
                }
            }
            .sheet(item: $share) { p in ShareSheet(items: p.items) }
        }
        .presentationDetents([.medium, .large])
    }

    private func export() {
        working = true
        errorText = nil
        Task {
            do {
                let urls = try await flow.exportFiles(kinds)
                working = false
                if !urls.isEmpty { share = SharePayload(items: urls) }
            } catch {
                working = false
                errorText = error.localizedDescription
            }
        }
    }
}
