// LibraryView.swift — all sessions: search, filter by paradigm, open, delete, export a summary table.

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var store: SessionStore
    @State private var search = ""
    @State private var filter: Paradigm?
    @State private var share: SharePayload?
    @State private var pendingDelete: Session?
    @State private var storage: Int64?
    @State private var exportError: String?

    private var filtered: [Session] {
        store.sessions.filter { s in
            (filter == nil || s.paradigm == filter) &&
            (search.isEmpty || [s.subjectID, s.group, s.phaseTitle, s.paradigm.title, s.paradigm.shortName, s.notes, s.videoName]
                .joined(separator: " ").localizedCaseInsensitiveContains(search))
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let sessions: [Session]
        var id: Date { day }
    }

    /// Sessions grouped by calendar day (newest first).
    private var days: [DayGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { DayGroup(day: $0, sessions: (groups[$0] ?? []).sorted { $0.createdAt > $1.createdAt }) }
    }

    private var paradigmsWithData: [Paradigm] {
        Paradigm.allCases.filter { p in store.sessions.contains { $0.paradigm == p } }
    }

    var body: some View {
        NavigationStack {
            List {
                if paradigmsWithData.count > 1 {
                    Section {
                        filterChips
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                ForEach(days) { group in
                    Section(group.day.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.sessions) { s in
                            Button {
                                app.open(s)
                            } label: {
                                SessionRow(session: s)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    app.open(s)
                                } label: {
                                    Label(L10n.tr("打开"), systemImage: "arrow.up.forward.app")
                                }
                                if s.videoFile != nil {
                                    Button {
                                        store.deleteVideo(of: s)
                                        refreshStorage()
                                    } label: {
                                        Label(L10n.tr("删除视频副本"), systemImage: "film")
                                    }
                                }
                                Divider()
                                Button(role: .destructive) {
                                    pendingDelete = s
                                } label: {
                                    Label(L10n.tr("删除此分析"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = s
                                } label: {
                                    Label(L10n.tr("删除"), systemImage: "trash")
                                }
                                if s.videoFile != nil {
                                    Button {
                                        store.deleteVideo(of: s)
                                        refreshStorage()
                                    } label: {
                                        Label(L10n.tr("删视频"), systemImage: "film")
                                    }
                                    .tint(Palette.categoryFill(.motor))
                                }
                            }
                        }
                    }
                }
                if !store.sessions.isEmpty {
                    Section {
                        HStack {
                            Text(L10n.tr("\(store.sessions.count) 次分析"))
                            Spacer()
                            if let storage { Text(L10n.tr("占用 \(Fmt.bytes(storage))")) }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } footer: {
                        Text(L10n.tr("左滑或长按可删除整次分析，或只删除视频副本（保留姿态数据与结果，但无法再回看视频）。"))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.tr("数据"))
            .searchable(text: $search, prompt: L10n.tr("编号、组别、阶段"))
            .overlay {
                if store.isLoaded && store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.tr("还没有分析"), systemImage: "tray")
                    } description: {
                        Text(L10n.tr("新建一次分析后，结果会出现在这里。"))
                    } actions: {
                        Button(L10n.tr("新建分析")) { app.startNewSession() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if !store.sessions.isEmpty && filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportSummary()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(filtered.filter { $0.status == .done }.isEmpty)
                    .accessibilityLabel(filter == nil ? L10n.tr("导出汇总表（全部）") : L10n.tr("导出汇总表（\(filter!.title)）"))
                }
            }
            .confirmationDialog(L10n.tr("删除这次分析？"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { s in
                Button(L10n.tr("删除"), role: .destructive) {
                    app.delete(s)
                    refreshStorage()
                }
            } message: { s in
                Text(L10n.tr("\(s.displaySubject) · \(s.paradigm.title) 的视频、姿态数据和结果都会被删除。"))
            }
            .sheet(item: $share) { payload in
                ShareSheet(items: payload.items)
            }
            .alert(L10n.tr("导出失败"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button(L10n.tr("好")) {}
            } message: {
                Text(exportError ?? "")
            }
            .task { refreshStorage() }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: L10n.tr("全部"), symbol: "square.stack.3d.up", selected: filter == nil, color: .secondary) { filter = nil }
                ForEach(paradigmsWithData) { p in
                    chip(title: p.title, symbol: p.symbol, selected: filter == p, color: Palette.category(p.category)) {
                        filter = filter == p ? nil : p
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    /// Selected chips invert (primary ink fill) so the state never depends on hue alone.
    private func chip(title: String, symbol: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(selected ? Color(uiColor: .systemBackground) : color)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
            .background(selected ? Color.primary : Palette.card, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func refreshStorage() {
        Task { storage = await store.storageBytes() }
    }

    private func exportSummary() {
        let rows = filtered.filter { $0.status == .done }.sorted { ($0.paradigm.rawValue, $0.group, $0.subjectID) < ($1.paradigm.rawValue, $1.group, $1.subjectID) }
        let name = "RodentStudio_summary_" + (filter?.shortName ?? "all") + ".csv"
        do {
            let url = try SessionStore.writeExport(name, text: Exporter.summaryCSV(rows))
            share = SharePayload(items: [url])
        } catch {
            exportError = error.localizedDescription
        }
    }
}
