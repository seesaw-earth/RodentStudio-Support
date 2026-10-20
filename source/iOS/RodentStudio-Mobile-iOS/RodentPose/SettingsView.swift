// SettingsView.swift — model status, keypoints, data location and about.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: PoseEngine
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var storage: Int64?
    @AppStorage(L10n.preferenceKey) private var uiLanguage = "system"

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AppMark(size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RodentStudio").font(.title3.weight(.bold))
                                .accessibilityAddTraits(.isHeader)
                            Text(L10n.tr("版本 \(version)")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section(L10n.tr("姿态模型")) {
                    LabeledContent(L10n.tr("模型"), value: kModelName)
                    LabeledContent(L10n.tr("状态")) {
                        switch engine.state {
                        case .ready: Label(L10n.tr("已就绪"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.success)
                        case .loading: Label(L10n.tr("加载中"), systemImage: "hourglass").foregroundStyle(.secondary)
                        case .failed: Label(L10n.tr("加载失败"), systemImage: "xmark.octagon.fill").foregroundStyle(Palette.danger)
                        }
                    }
                    if case .failed(let message) = engine.state {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.tr("重新加载")) { engine.load() }
                    }
                    LabeledContent(L10n.tr("输入"), value: "960 × 960 · INT8 · Core ML")
                }
                Section {
                    HStack(alignment: .center, spacing: 16) {
                        KeypointDiagram().frame(width: 80, height: 100)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(KP.allCases) { k in
                                HStack(spacing: 8) {
                                    Circle().fill(Palette.keypoint(k.rawValue)).frame(width: 9, height: 9)
                                    Text(k.title).font(.subheadline)
                                    Text(k.key).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(L10n.tr("关键点"))
                } footer: {
                    Text(L10n.tr("头朝向 = 两耳中点 → 鼻尖；身体轴向 = 尾根 → 颈部；身体长度 = 鼻尖 → 尾根。"))
                }
                Section {
                    LabeledContent(L10n.tr("分析次数"), value: "\(store.sessions.count)")
                    LabeledContent(L10n.tr("占用空间"), value: storage.map { Fmt.bytes($0) } ?? L10n.tr("计算中…"))
                } header: {
                    Text(L10n.tr("数据"))
                } footer: {
                    Text(L10n.tr("所有视频、姿态数据和结果只保存在本机，可在“文件”App › 我的 iPhone › RodentStudio › Sessions 中找到。每次分析一个文件夹：session.json（设置与指标）、pose.mpt（逐帧关键点）、video.*（视频副本）。"))
                }
                Section(L10n.tr("语言")) {
                    Picker(L10n.tr("界面语言"), selection: $uiLanguage) {
                        Text(L10n.tr("跟随系统")).tag("system")
                        Text(verbatim: "中文").tag("zh-Hans")
                        Text(verbatim: "English").tag("en")
                    }
                    .pickerStyle(.segmented)
                    Text(L10n.tr("切换语言后界面会立即更新。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L10n.tr("实验数据始终以英文保存和导出，不受界面语言影响。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(L10n.tr("使用建议")) {
                    tip("camera", L10n.tr("俯拍、画面包含整个场地、光照均匀；红外 / 灰度视频效果最好。"))
                    tip("ruler", L10n.tr("标定时手柄对准场地内壁；尺寸以厘米输入。"))
                    tip("checklist", L10n.tr("同一批实验的第一只鼠认真标定，之后的视频会自动沿用。"))
                    tip("play.rectangle", L10n.tr("在“回看”中抽查骨架和行为判定，必要时调整阈值。"))
                }
            }
            .navigationTitle(L10n.tr("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("完成")) { dismiss() } }
            }
            .task { storage = await store.storageBytes() }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}
