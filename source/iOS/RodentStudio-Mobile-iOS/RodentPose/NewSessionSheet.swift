// NewSessionSheet.swift — choose a paradigm, then a video from Photos or Files.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct NewSessionSheet: View {
    let initialParadigm: Paradigm?

    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var engine: PoseEngine
    @Environment(\.dismiss) private var dismiss
    @State private var paradigm: Paradigm?
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var importing = false
    @State private var errorText: String?
    @State private var choosing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stepLabel(1, L10n.tr("选择范式"))
                    if let p = paradigm, !choosing {
                        selectedCard(p)
                    } else {
                        paradigmList
                    }
                    stepLabel(2, L10n.tr("导入视频"))
                        .opacity(paradigm == nil ? 0.4 : 1)
                    videoButtons
                        .disabled(paradigm == nil || importing)
                        .opacity(paradigm == nil ? 0.4 : 1)
                    if let errorText {
                        Banner(text: errorText, style: .error)
                    }
                    Text(L10n.tr("视频会保存在本次分析的文件夹中，便于之后回看；不需要时可在“数据”里删除视频副本，只保留结果。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .screenContent()
                .padding(.vertical, 12)
            }
            .background(Palette.canvas)
            .navigationTitle(L10n.tr("新建分析"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("取消")) { dismiss() }.disabled(importing)
                }
            }
            .overlay {
                if importing {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(L10n.tr("正在导入视频…")).font(.subheadline.weight(.medium))
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .onAppear {
                if paradigm == nil { paradigm = initialParadigm }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                importFromPhotos(item)
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { importFromFiles(url) }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .interactiveDismissDisabled(importing)
        }
    }

    // MARK: Pieces

    private func stepLabel(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(title).font(.headline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func selectedCard(_ p: Paradigm) -> some View {
        Card {
            HStack(spacing: 12) {
                ParadigmBadge(paradigm: p, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.headline)
                    Text(p.englishName).font(.footnote).foregroundStyle(.secondary)
                }
                // Setup tips, measures and literature: on demand.
                InfoButton(title: p.title) { ParadigmKnowledge(paradigm: p) }
                Spacer(minLength: 8)
                Button(L10n.tr("更换")) { withAnimation(Motion.snappy) { choosing = true } }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityLabel(L10n.tr("更换范式"))
            }
            Text(p.tagline).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var paradigmList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(ParadigmCategory.allCases) { cat in
                VStack(alignment: .leading, spacing: 6) {
                    Text(cat.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.category(cat))
                        .padding(.leading, 4)
                    VStack(spacing: 0) {
                        let items = Paradigm.inCategory(cat)
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, p in
                            Button {
                                withAnimation(Motion.snappy) {
                                    paradigm = p
                                    choosing = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ParadigmBadge(paradigm: p, size: 34)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(p.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if paradigm == p {
                                        Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(paradigm == p ? .isSelected : [])
                            if i < items.count - 1 { Divider().padding(.leading, 58) }
                        }
                    }
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var videoButtons: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photoItem, matching: .videos) {
                Label(L10n.tr("从相册选择视频"), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button {
                showFiles = true
            } label: {
                Label(L10n.tr("从“文件”选择视频"), systemImage: "folder")
            }
            .buttonStyle(SecondaryButtonStyle())
            if !engine.isReady {
                Text(L10n.tr("模型仍在加载，可以先导入视频并完成标定。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Import

    private func importFromPhotos(_ item: PhotosPickerItem) {
        guard let p = paradigm else { return }
        importing = true
        errorText = nil
        Task {
            do {
                guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                    throw NSError(domain: "RodentPose", code: 10, userInfo: [NSLocalizedDescriptionKey: L10n.tr("无法读取这个视频")])
                }
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm"
                let flow = try await app.createSession(paradigm: p, videoURL: movie.url, originalName: L10n.tr("相册视频 ") + df.string(from: Date()))
                finish(flow)
            } catch {
                errorText = L10n.tr("导入失败：\(error.localizedDescription)")
                importing = false
            }
            photoItem = nil
        }
    }

    private func importFromFiles(_ url: URL) {
        guard let p = paradigm else { return }
        importing = true
        errorText = nil
        Task {
            do {
                let tmp = try await Task.detached(priority: .userInitiated) { () -> URL in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let dst = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
                    try FileManager.default.copyItem(at: url, to: dst)
                    return dst
                }.value
                let flow = try await app.createSession(paradigm: p, videoURL: tmp, originalName: url.lastPathComponent)
                finish(flow)
            } catch {
                errorText = L10n.tr("导入失败：\(error.localizedDescription)")
                importing = false
            }
        }
    }

    private func finish(_ flow: SessionFlowModel) {
        app.pendingFlow = flow
        importing = false
        dismiss()
    }
}
