// HomeView.swift — start screen: model status, running analysis, new analysis, unfinished work,
// featured paradigms and recent results.

import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var engine: PoseEngine

    private let featured: [Paradigm] = [.threeChamber, .headDirection, .novelObject, .elevatedPlusMaze, .fearConditioning, .rotation]

    /// Sessions that still need a step (not the one currently running), newest first.
    private var unfinished: [Session] {
        store.sessions
            .filter { $0.status != .done && $0.id != app.runningFlow?.session.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var completed: [Session] {
        store.sessions.filter { $0.status == .done }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        modelStatus
                        if let flow = app.runningFlow {
                            RunningCard(flow: flow) { app.activeFlow = flow }
                        }
                        startCard
                    }
                    if !unfinished.isEmpty { continueSection }
                    featuredSection
                    recentSection
                }
                .screenContent()
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Palette.canvas)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppMark(size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("RodentStudio")
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.tr("端侧姿态识别 · 行为范式分析"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                app.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(Palette.card, in: Circle())
            }
            .accessibilityLabel(L10n.tr("设置"))
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch engine.state {
        case .ready:
            EmptyView()
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(L10n.tr("正在加载姿态模型…")).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Banner(text: message, style: .error)
                Button(L10n.tr("重新加载模型")) { engine.load() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// The one call to action. The dark tile with the colored skeleton is the app's signature:
    /// it shows what the app does (keypoints on top-view video) without decoration.
    private var startCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("开始新的分析"))
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    WorkflowSteps(steps: [L10n.tr("选择范式"), L10n.tr("导入视频"), L10n.tr("标定"), L10n.tr("识别"), L10n.tr("结果")])
                }
                Spacer(minLength: 0)
                SignatureTile()
                    .frame(width: 76, height: 76)
            }
            Button {
                app.startNewSession()
            } label: {
                Label(L10n.tr("新建分析"), systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L10n.tr("继续未完成的分析"))
            SessionList(sessions: Array(unfinished.prefix(3))) { app.open($0) }
            if unfinished.count > 3 {
                Button {
                    app.selectedTab = .library
                } label: {
                    Text(String(format: L10n.tr("另有 %d 个未完成，在“数据”中查看"), unfinished.count - 3))
                        .font(.footnote)
                }
                .padding(.leading, 4)
            }
        }
    }

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: L10n.tr("常用范式"),
                         actionTitle: String(format: L10n.tr("全部 %d 个"), Paradigm.allCases.count)) {
                app.selectedTab = .catalog
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
                ForEach(featured) { p in
                    Button {
                        app.startNewSession(p)
                    } label: {
                        ParadigmTile(paradigm: p)
                    }
                    .buttonStyle(PressableCardStyle())
                    .accessibilityHint(L10n.tr("用这个范式新建分析"))
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if completed.isEmpty {
                if store.sessions.isEmpty {
                    SectionTitle(title: L10n.tr("最近结果"))
                    VStack(spacing: 8) {
                        Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                        Text(L10n.tr("还没有分析记录")).font(.subheadline.weight(.semibold))
                        Text(L10n.tr("结果保存在本机，也可以在“文件”App › RodentStudio › Sessions 中找到。"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else {
                SectionTitle(title: L10n.tr("最近结果"), actionTitle: L10n.tr("全部数据")) {
                    app.selectedTab = .library
                }
                SessionList(sessions: Array(completed.prefix(5))) { app.open($0) }
            }
        }
    }
}

// MARK: - Pieces

/// "1 Choose an assay  2 Import video  …" — numbered because it is a real sequence; wraps instead
/// of shrinking in long languages.
struct WorkflowSteps: View {
    let steps: [String]

    var body: some View {
        WrapLayout(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 5) {
                    Text("\(i + 1)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Palette.inset, in: Circle())
                    Text(s)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(steps.joined(separator: ", "))
    }
}

/// Dark "video frame" with the colored keypoint skeleton — the brand motif.
struct SignatureTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(white: 0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(8)
            }
            .overlay {
                MouseGlyph()
                    .rotationEffect(.degrees(-28))
                    .padding(10)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Card-like button feedback that does not rely on the system highlight.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ParadigmTile: View {
    let paradigm: Paradigm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParadigmBadge(paradigm: paradigm, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(paradigm.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(paradigm.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Grouped rows on a card, used on Home.
struct SessionList: View {
    let sessions: [Session]
    let open: (Session) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                Button {
                    open(s)
                } label: {
                    SessionRow(session: s, showsChevron: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(PressableCardStyle())
                if i < sessions.count - 1 {
                    Divider().padding(.leading, 95)
                }
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SessionRow: View {
    let session: Session
    var showsChevron = false

    private var metaLine: String {
        [session.paradigm.title, session.sessionLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            SessionThumbnail(session: session)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.displaySubject)
                        .font(.headline)
                        .lineLimit(1)
                    if !session.group.isEmpty {
                        Tag(text: session.group, color: Palette.category(session.paradigm.category))
                    }
                }
                Text(metaLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if session.status != .done {
                    StatusBadge(status: session.status)
                }
            }
            Spacer(minLength: 8)
            if !session.primaryDisplay.isEmpty && session.status == .done {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(session.primaryDisplay)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text(L10n.display(english: session.primaryTitle))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// First video frame of a session (saved at import), with the paradigm badge in the corner.
struct SessionThumbnail: View {
    let session: Session
    var width: CGFloat = 64
    var height: CGFloat = 46
    @EnvironmentObject private var store: SessionStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.12)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            ParadigmBadge(paradigm: session.paradigm, size: 20)
                .overlay {
                    RoundedRectangle(cornerRadius: 20 * 0.27, style: .continuous)
                        .strokeBorder(Palette.card, lineWidth: 1.5)
                }
                .offset(x: 5, y: 5)
        }
        .padding(.trailing, 5)
        .padding(.bottom, 5)
        .accessibilityHidden(true)
        .task(id: session.id) { [id = session.id, url = store.thumbnailURL(session.id)] in
            image = await ThumbnailCache.image(for: id, url: url)
        }
    }
}

/// Small in-memory cache so list scrolling does not reread JPEGs.
@MainActor
enum ThumbnailCache {
    private static var images: [UUID: UIImage] = [:]

    static func image(for id: UUID, url: URL) async -> UIImage? {
        if let cached = images[id] { return cached }
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        guard let data, let image = UIImage(data: data) else { return nil }
        if images.count > 200 { images.removeAll() }
        images[id] = image
        return image
    }

    static func remove(_ id: UUID) { images[id] = nil }
}

struct RunningCard: View {
    @ObservedObject var flow: SessionFlowModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(fraction: flow.progress.fraction, lineWidth: 6)
                    Text("\(Int(flow.progress.fraction * 100))%")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("正在识别 · \(flow.session.displaySubject)"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L10n.tr("\(flow.session.paradigm.title) · 剩余 \(Fmt.remaining(flow.progress.remaining))"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }
}
