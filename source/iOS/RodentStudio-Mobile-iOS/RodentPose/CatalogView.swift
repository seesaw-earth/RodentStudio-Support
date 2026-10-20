// CatalogView.swift — library of paradigms: what each measures, why pose helps, setup and literature.

import SwiftUI

struct CatalogView: View {
    @State private var search = ""

    private func items(_ c: ParadigmCategory) -> [Paradigm] {
        Paradigm.inCategory(c).filter { p in
            search.isEmpty || [p.title, p.englishName, p.tagline, p.summary, p.measures.map { $0.name }.joined(separator: " ")]
                .joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("哪些研究需要姿态数据？"))
                                .font(.headline)
                            Text(L10n.tr("质心追踪只知道动物“在哪里”。鼻尖、两耳、颈部、身体中心和尾根六个关键点还能回答“朝向哪里、在做什么”：嗅探与探索、头朝向、风险评估姿势、转圈和僵直。下面的范式参考文献中的常用定义实现，所有阈值都可以调整。"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            KeypointLegend()
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                }
                ForEach(ParadigmCategory.allCases) { cat in
                    let list = items(cat)
                    if !list.isEmpty {
                        Section {
                            ForEach(list) { p in
                                NavigationLink(value: p) {
                                    HStack(spacing: 12) {
                                        ParadigmBadge(paradigm: p, size: 38)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.title).font(.subheadline.weight(.semibold))
                                            Text(p.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } header: {
                            Label(cat.title, systemImage: cat.symbol)
                                .foregroundStyle(Palette.category(cat))
                                .font(.footnote.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.tr("范式库"))
            .searchable(text: $search, prompt: L10n.tr("搜索范式或指标"))
            .navigationDestination(for: Paradigm.self) { p in
                ParadigmDetailView(paradigm: p)
            }
        }
    }
}

// MARK: - Detail

struct ParadigmDetailView: View {
    let paradigm: Paradigm
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ParadigmHero(paradigm: paradigm)
                ParadigmKnowledge(paradigm: paradigm)
            }
            .screenContent()
            .padding(.vertical, 12)
        }
        .background(Palette.canvas)
        .navigationTitle(paradigm.title)
        .navigationBarTitleDisplayMode(.inline)
        .chromeBar(.bottom) {
            Button {
                app.startNewSession(paradigm)
            } label: {
                Label(L10n.tr("用这个范式开始分析"), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle(color: Palette.categoryFill(paradigm.category)))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 720)
        }
    }
}

struct ParadigmHero: View {
    let paradigm: Paradigm

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ParadigmBadge(paradigm: paradigm, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(paradigm.title).font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(paradigm.englishName).font(.subheadline).foregroundStyle(.secondary)
                Tag(text: paradigm.category.title, color: Palette.category(paradigm.category))
            }
        }
        .padding(.top, 4)
    }
}

/// Background knowledge of one paradigm: what it is, why pose helps, measures, setup and
/// literature. Shown in the paradigm library and, on demand, from the ⓘ in the workspace.
struct ParadigmKnowledge: View {
    let paradigm: Paradigm

    private var tint: Color { Palette.category(paradigm.category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                CardHeader(L10n.tr("范式简介"), symbol: "text.book.closed")
                Text(paradigm.summary).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            Card {
                CardHeader(L10n.tr("为什么需要姿态"), symbol: "point.3.connected.trianglepath.dotted")
                Text(paradigm.whyPose).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .center, spacing: 16) {
                    KeypointDiagram(highlight: Set(paradigm.keypointsUsed.map { $0.rawValue }))
                        .frame(width: 92, height: 112)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("用到的关键点")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        FlowChips(items: paradigm.keypointsUsed.map { ($0.title, Palette.keypoint($0.rawValue)) })
                    }
                }
            }
            Card {
                CardHeader(L10n.tr("输出指标"), symbol: "chart.bar.xaxis")
                ForEach(paradigm.measures, id: \.self) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.name).font(.subheadline.weight(.semibold))
                        Text(m.definition).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
            Card {
                CardHeader(L10n.tr("拍摄与标定"), symbol: "camera.viewfinder")
                ForEach(paradigm.setupTips, id: \.self) { tip in
                    Label {
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                }
                WrapLayout(spacing: 6) {
                    Text(L10n.tr("场地")).font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 3)
                    ForEach(paradigm.arenaKinds) { k in
                        Tag(text: k.title, color: tint)
                    }
                }
            }
            Card {
                CardHeader(L10n.tr("参考文献"), symbol: "books.vertical")
                ForEach(paradigm.references, id: \.self) { ref in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ref.citation).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        if let url = ref.url {
                            Link(destination: url) {
                                Label("doi: \(ref.doi ?? "")", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.medium))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Keypoint helpers

/// Skeleton with the used keypoints highlighted.
struct KeypointDiagram: View {
    var highlight: Set<Int> = Set(0..<6)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let pts = [CGPoint(x: 0.5 * w, y: 0.08 * h), CGPoint(x: 0.28 * w, y: 0.24 * h), CGPoint(x: 0.72 * w, y: 0.24 * h),
                       CGPoint(x: 0.5 * w, y: 0.34 * h), CGPoint(x: 0.5 * w, y: 0.58 * h), CGPoint(x: 0.5 * w, y: 0.84 * h)]
            var outline = Path()
            outline.addEllipse(in: CGRect(x: 0.26 * w, y: 0.22 * h, width: 0.48 * w, height: 0.66 * h))
            ctx.fill(outline, with: .color(Color.secondary.opacity(0.10)))
            var tail = Path()
            tail.move(to: pts[5])
            tail.addQuadCurve(to: CGPoint(x: 0.78 * w, y: 0.99 * h), control: CGPoint(x: 0.52 * w, y: 0.99 * h))
            ctx.stroke(tail, with: .color(Color.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for (a, b) in kBones {
                var p = Path()
                p.move(to: pts[a])
                p.addLine(to: pts[b])
                ctx.stroke(p, with: .color(Color.secondary.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            for (i, c) in pts.enumerated() {
                let on = highlight.contains(i)
                let r: CGFloat = on ? 6 : 4
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(on ? Palette.keypoint(i) : Color.secondary.opacity(0.3)))
                if on { ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5) }
            }
        }
        .accessibilityHidden(true)
    }
}

struct KeypointLegend: View {
    var body: some View {
        FlowChips(items: KP.allCases.map { ($0.title, Palette.keypoint($0.rawValue)) })
    }
}

/// Wrapping row of colored chips.
struct FlowChips: View {
    let items: [(String, Color)]

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    Circle().fill(items[i].1).frame(width: 8, height: 8)
                    Text(items[i].0).font(.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.inset, in: Capsule())
            }
        }
    }
}

/// Simple flow layout that wraps children onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
