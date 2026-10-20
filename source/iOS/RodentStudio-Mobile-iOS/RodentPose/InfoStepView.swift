// InfoStepView.swift — step 1: video, paradigm, animal information and model settings.

import SwiftUI

struct InfoStepView: View {
    @ObservedObject var flow: SessionFlowModel
    @EnvironmentObject private var store: SessionStore
    @State private var showParadigmPicker = false

    private var s: Session { flow.session }

    /// Group names used before, for one-tap filling.
    private var recentGroups: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in store.sessions where !x.group.isEmpty && !seen.contains(x.group) {
            seen.insert(x.group)
            out.append(x.group)
            if out.count >= 6 { break }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let notice = flow.notice {
                    Banner(text: notice, style: .info)
                }
                videoCard
                paradigmCard
                animalCard
                modelCard
            }
            .screenContent()
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showParadigmPicker) {
            ParadigmPickerSheet(selection: s.paradigm) { p in flow.changeParadigm(p) }
        }
    }

    // MARK: Video

    private var videoCard: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if let frame = flow.frame {
                        Image(decorative: frame, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Palette.inset
                        Image(systemName: "film").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 108, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.videoName.isEmpty ? L10n.tr("视频") : s.videoName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text("\(Fmt.clock(s.video.duration)) · \(Int(s.video.width))×\(Int(s.video.height)) · \(Fmt.number(s.video.fps, 1)) fps")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if s.video.fileSize > 0 {
                        Text(Fmt.bytes(s.video.fileSize)).font(.caption).foregroundStyle(.tertiary)
                    }
                    if flow.videoURL == nil {
                        Label(L10n.tr("视频副本已删除"), systemImage: "film")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.warning)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Paradigm

    private var paradigmCard: some View {
        Card {
            HStack(spacing: 12) {
                ParadigmBadge(paradigm: s.paradigm, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.paradigm.title).font(.headline)
                    Text(s.paradigm.englishName).font(.caption).foregroundStyle(.secondary)
                }
                InfoButton(title: s.paradigm.title) { ParadigmKnowledge(paradigm: s.paradigm) }
                Spacer(minLength: 8)
                Button(L10n.tr("更换")) { showParadigmPicker = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .disabled(flow.isRunning)
                    .accessibilityLabel(L10n.tr("更换范式"))
            }
            Divider()
            PhasePicker(paradigm: s.paradigm, phase: $flow.session.phase)
        }
    }

    // MARK: Animal

    private var animalCard: some View {
        Card {
            CardHeader(title: L10n.tr("动物信息"), symbol: "tag") {
                InfoButton(title: L10n.tr("动物信息")) {
                    InfoParagraph(L10n.tr("编号"), L10n.tr("编号会用于文件名和汇总表，建议在识别前填写。"))
                    InfoParagraph(L10n.tr("组别"), L10n.tr("用过的组别会出现在输入框下方，轻点即可填入。"))
                    InfoParagraph(L10n.tr("阶段 / 条件"), L10n.tr("可选，也可以不选。轻点 + 添加自己的标签（如 Day 1、Baseline 或任何实验条件），之后同一范式会一直显示；长按自己的标签可移除。再次轻点已选中的标签即取消选择。"))
                    InfoParagraph(L10n.tr("备注"), L10n.tr("只保存在本机，会随汇总表一起导出。"))
                }
            }
            // A grid sizes the label column to the longest label, so the layout holds in both
            // languages and at large Dynamic Type sizes.
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel(L10n.tr("编号"))
                    fieldBox {
                        TextField(L10n.tr("如 M01"), text: $flow.session.subjectID)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                    }
                }
                GridRow {
                    fieldLabel(L10n.tr("组别"))
                    fieldBox {
                        TextField(L10n.tr("如 WT / KO / 对照"), text: $flow.session.group)
                            .autocorrectionDisabled()
                    }
                }
                if !recentGroups.isEmpty {
                    GridRow {
                        Color.clear.frame(width: 1, height: 1)
                        recentGroupChips
                    }
                }
            }
            Divider()
            SegmentRow(title: L10n.tr("性别"), selection: $flow.session.sex, options: [("", L10n.tr("未填")), ("M", L10n.tr("雄")), ("F", L10n.tr("雌"))])
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    OptionalIntField(title: L10n.tr("天"), value: $flow.session.day)
                    OptionalIntField(title: L10n.tr("试次"), value: $flow.session.trial)
                }
                VStack(spacing: 10) {
                    OptionalIntField(title: L10n.tr("天"), value: $flow.session.day)
                    OptionalIntField(title: L10n.tr("试次"), value: $flow.session.trial)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr("备注")).font(.subheadline)
                TextField(L10n.tr("实验条件、异常情况…"), text: $flow.session.notes, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(L10n.tr("备注"))
            }
        }
    }

    private var recentGroupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(recentGroups, id: \.self) { g in
                    Button {
                        flow.session.group = g
                    } label: {
                        Tag(text: g, color: .accentColor, filled: s.group == g)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: L10n.tr("使用组别 %@"), g))
                    .accessibilityAddTraits(s.group == g ? .isSelected : [])
                }
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize()
            .gridColumnAlignment(.leading)
    }

    private func fieldBox<Field: View>(@ViewBuilder _ field: () -> Field) -> some View {
        field()
            .font(.subheadline)
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Model settings

    private var estimatedFrames: Int {
        let v = s.video
        let start = max(0, s.inference.startTime)
        let end = s.inference.endTime > 0 ? min(s.inference.endTime, v.duration) : v.duration
        return max(0, Int((end - start) * v.fps / Double(max(1, s.inference.stride))))
    }

    private var modelCard: some View {
        Card {
            CardHeader(title: L10n.tr("识别设置"), symbol: "cpu") {
                InfoButton(title: L10n.tr("识别设置")) {
                    InfoParagraph(L10n.tr("修改后需要重新识别"))
                    InfoParagraph(L10n.tr("抽帧"), L10n.tr("长视频可隔帧识别；僵直、速度等指标按实际时间计算，不受影响。头部快速动作（VTE、探头）建议逐帧。"))
                    InfoParagraph(L10n.tr("先转灰度再识别"), L10n.tr("训练数据为灰度 / 红外视频，建议保持开启"))
                    InfoParagraph(L10n.tr("双鼠模式"), L10n.tr("每帧保留两只鼠，按位置连续性分配身份"))
                    InfoParagraph(L10n.tr("识别范围"), L10n.tr("分析时间段（例如只看前 5 分钟）可以在“标定”页随时调整，不需要重新识别。"))
                }
            }
            SegmentRow(title: L10n.tr("抽帧"), selection: $flow.session.inference.stride, options: [(1, L10n.tr("每帧")), (2, L10n.tr("每 2 帧")), (3, L10n.tr("每 3 帧")), (5, L10n.tr("每 5 帧"))])
            Toggle(isOn: $flow.session.inference.grayscale) {
                Text(L10n.tr("先转灰度再识别")).font(.subheadline)
            }
            if s.paradigm == .dyadicSocial || s.inference.animalCount > 1 {
                Toggle(isOn: Binding(get: { flow.session.inference.animalCount > 1 },
                                     set: { flow.session.inference.animalCount = $0 ? 2 : 1 })) {
                    Text(L10n.tr("双鼠模式")).font(.subheadline)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.tr("识别范围")).font(.subheadline)
                    Spacer()
                    Text(String(format: L10n.tr("约 %d 帧"), estimatedFrames))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                NumberField(title: L10n.tr("从（秒）"), value: $flow.session.inference.startTime, unit: "s", range: 0...max(0, s.video.duration))
                NumberField(title: L10n.tr("到（秒，0 = 结尾）"), value: $flow.session.inference.endTime, unit: "s", range: 0...max(0, s.video.duration))
            }
            if flow.inferenceSettingsChanged {
                Banner(text: L10n.tr("识别设置与已有姿态数据不同，进入“识别”页可用新设置重新识别。"), style: .warning)
            }
        }
        .disabled(flow.isRunning)
    }
}

// MARK: - Paradigm picker

struct ParadigmPickerSheet: View {
    let selection: Paradigm
    let onPick: (Paradigm) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ParadigmCategory.allCases) { cat in
                    Section(cat.title) {
                        ForEach(Paradigm.inCategory(cat)) { p in
                            Button {
                                onPick(p)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ParadigmBadge(paradigm: p, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        Text(p.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if p == selection {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityAddTraits(p == selection ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr("更换范式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Phase / condition

/// Phase or experimental condition: the paradigm's presets (where the analysis uses them), the
/// researcher's own labels, and "+" to add one. Nothing has to be selected; tapping the selected
/// label clears it. Long-press one of your own labels to remove it from the list.
struct PhasePicker: View {
    let paradigm: Paradigm
    @Binding var phase: String

    @State private var custom: [String] = []
    @State private var adding = false
    @State private var draft = ""

    private var options: [PhaseOption] {
        var list = paradigm.phases
        for label in custom where !list.contains(where: { $0.key == label }) {
            list.append(PhaseOption(key: label, title: label))
        }
        // A value from an older session that is in neither list still shows as selected.
        if !phase.isEmpty && !list.contains(where: { $0.key == phase }) {
            list.append(PhaseOption(key: phase, title: paradigm.phaseTitle(phase)))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("阶段 / 条件")).font(.subheadline)
            WrapLayout(spacing: 8) {
                ForEach(options) { option in
                    chip(option)
                }
                addButton
            }
        }
        .onAppear { custom = PhaseLibrary.labels(for: paradigm) }
        .onChange(of: paradigm) { _, p in custom = PhaseLibrary.labels(for: p) }
        .alert(L10n.tr("添加阶段 / 条件"), isPresented: $adding) {
            TextField(L10n.tr("名称，如 Day 1"), text: $draft)
            Button(L10n.tr("添加")) { commit() }
            Button(L10n.tr("取消"), role: .cancel) { draft = "" }
        } message: {
            Text(L10n.tr("会保存在这个范式的常用列表中。"))
        }
    }

    @ViewBuilder
    private func chip(_ option: PhaseOption) -> some View {
        let selected = phase == option.key
        let removable = custom.contains(option.key)
        let button = Button {
            phase = selected ? "" : option.key
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Palette.inset, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? L10n.tr("再次轻点取消选择") : "")
        if removable {
            button.contextMenu {
                Button(role: .destructive) {
                    remove(option.key)
                } label: {
                    Label(L10n.tr("从常用中移除"), systemImage: "minus.circle")
                }
            }
        } else {
            button
        }
    }

    private var addButton: some View {
        Button {
            draft = ""
            adding = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Palette.inset, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("添加阶段 / 条件"))
    }

    private func commit() {
        guard let label = PhaseLibrary.clean(draft) else { return }
        draft = ""
        if !paradigm.isPresetPhase(label) {
            PhaseLibrary.add(label, for: paradigm)
            custom = PhaseLibrary.labels(for: paradigm)
        }
        phase = label
    }

    private func remove(_ label: String) {
        PhaseLibrary.remove(label, for: paradigm)
        custom = PhaseLibrary.labels(for: paradigm)
    }
}
