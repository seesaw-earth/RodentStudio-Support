// ParamsEditor.swift — paradigm-specific thresholds and settings, plus the common analysis settings.

import SwiftUI

struct ParamsEditor: View {
    let paradigm: Paradigm
    let phase: String
    @Binding var params: AnalysisParams
    var hasCue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch paradigm {
            case .openField: openFieldRows
            case .spatialExploration: spatialExplorationRows
            case .headDirection: headDirectionRows
            case .threeChamber: threeChamberRows
            case .socialInteraction: socialInteractionRows
            case .dyadicSocial: dyadicSocialRows
            case .elevatedPlusMaze: elevatedPlusMazeRows
            case .lightDark: lightDarkRows
            case .novelObject: novelObjectRows
            case .barnesMaze: barnesMazeRows
            case .yMaze: yMazeRows
            case .tMaze: tMazeRows
            case .fearConditioning: fearConditioningRows
            case .looming: loomingRows
            case .rotation: rotationRows
            case .poseOnly: poseOnlyRows
            }
        }
    }

    @ViewBuilder
    private var openFieldRows: some View {
        PercentSlider(title: L10n.tr("中央区大小（边长比例）"), value: $params.centerFraction, range: 0.2...0.8)
        freezeRows(title: L10n.tr("静止判定"))
    }

    @ViewBuilder
    private var spatialExplorationRows: some View {
        NumberField(title: L10n.tr("占据图方格"), value: $params.spatialBin, unit: "cm", range: 0.5...20)
        NumberField(title: L10n.tr("覆盖判定最短停留"), value: $params.coverageMinTime, unit: "s", range: 0...10)
        NumberField(title: L10n.tr("运动速度阈值"), value: $params.moveSpeed, unit: "cm/s", range: 0...50)
    }

    @ViewBuilder
    private var headDirectionRows: some View {
        SegmentRow(title: L10n.tr("0° 参考方向"), selection: $params.hdReference, options: [("image", L10n.tr("场地右方")), ("cue", L10n.tr("提示卡 Q"))])
        if params.hdReference == "cue" && !hasCue {
            Label(L10n.tr("没有找到提示卡手柄 Q，将使用场地右方。"), systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Palette.warning)
        }
        SegmentRow(title: L10n.tr("方向分格"), selection: $params.hdBinDeg, options: [(3.0, "3°"), (6.0, "6°"), (10.0, "10°"), (15.0, "15°")])
        NumberField(title: L10n.tr("覆盖判定最短停留"), value: $params.hdMinBinTime, unit: "s", range: 0...30)
    }

    @ViewBuilder
    private var threeChamberRows: some View {
        SegmentRow(title: phase == "Social novelty" ? L10n.tr("新陌生鼠所在杯") : (phase == "Habituation" ? L10n.tr("参照杯（指数分子）") : L10n.tr("陌生鼠所在杯")),
                   selection: $params.stimSide, options: [("L", L10n.tr("左杯 L")), ("R", L10n.tr("右杯 R"))])
        NumberField(title: L10n.tr("杯子半径"), value: $params.cupRadius, unit: "cm", range: 1...20)
        NumberField(title: L10n.tr("嗅探距离（杯外缘）"), value: $params.exploreMargin, unit: "cm", range: 0...10)
        NumberField(title: L10n.tr("头朝向容差"), value: $params.headTolerance, unit: "°", range: 5...180)
        PercentSlider(title: L10n.tr("中箱宽度（占总长）"), value: $params.centerChamberFraction, range: 0.1...0.8)
    }

    @ViewBuilder
    private var socialInteractionRows: some View {
        SegmentRow(title: L10n.tr("网罩靠哪面墙（画面方向）"), selection: $params.enclosureWall, options: [("top", L10n.tr("上")), ("bottom", L10n.tr("下")), ("left", L10n.tr("左")), ("right", L10n.tr("右"))])
        NumberField(title: L10n.tr("互动区宽（沿墙）"), value: $params.izWidth, unit: "cm", range: 1...100)
        NumberField(title: L10n.tr("互动区深（离墙）"), value: $params.izDepth, unit: "cm", range: 1...100)
        NumberField(title: L10n.tr("网罩宽"), value: $params.enclosureWidth, unit: "cm", range: 1...50)
        NumberField(title: L10n.tr("网罩深"), value: $params.enclosureDepth, unit: "cm", range: 1...50)
        NumberField(title: L10n.tr("角落区边长"), value: $params.cornerSize, unit: "cm", range: 1...50)
    }

    @ViewBuilder
    private var dyadicSocialRows: some View {
        NumberField(title: L10n.tr("鼻–鼻距离"), value: $params.noseNoseDist, unit: "cm", range: 0.5...10)
        NumberField(title: L10n.tr("鼻–尾根（肛殖区）距离"), value: $params.anogenitalDist, unit: "cm", range: 0.5...10)
        NumberField(title: L10n.tr("鼻–身体距离"), value: $params.bodySniffDist, unit: "cm", range: 0.5...10)
        NumberField(title: L10n.tr("近距离（身体中心）"), value: $params.proximityDist, unit: "cm", range: 1...50)
        DisclosureGroup(L10n.tr("跟随判定")) {
            VStack(spacing: 10) {
                NumberField(title: L10n.tr("最大间距"), value: $params.followDist, unit: "cm", range: 1...60)
                NumberField(title: L10n.tr("最低速度"), value: $params.followSpeed, unit: "cm/s", range: 0...50)
                NumberField(title: L10n.tr("朝向容差"), value: $params.followAngle, unit: "°", range: 5...90)
                NumberField(title: L10n.tr("最短持续"), value: $params.followMin, unit: "s", range: 0...10)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var elevatedPlusMazeRows: some View {
        SegmentRow(title: L10n.tr("开放臂方向"), selection: $params.openAxis, options: [("NS", L10n.tr("N–S（上下）")), ("EW", L10n.tr("E–W（左右）"))])
        entryRule
        DisclosureGroup(L10n.tr("探头与伸展评估姿势")) {
            VStack(spacing: 10) {
                NumberField(title: L10n.tr("探头范围（臂边缘外）"), value: $params.headDipReach, unit: "cm", range: 1...20)
                NumberField(title: L10n.tr("探头最短持续"), value: $params.headDipMin, unit: "s", range: 0...3)
                NumberField(title: L10n.tr("SAP 身体伸长倍数"), value: $params.sapElongation, unit: "×", range: 1.05...2)
                NumberField(title: L10n.tr("SAP 最高速度"), value: $params.sapSpeed, unit: "cm/s", range: 0...30)
                NumberField(title: L10n.tr("SAP 最短持续"), value: $params.sapMin, unit: "s", range: 0...5)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var lightDarkRows: some View {
        SegmentRow(title: L10n.tr("明箱在画面"), selection: $params.lightOnLeft, options: [(true, L10n.tr("左侧")), (false, L10n.tr("右侧"))])
        PercentSlider(title: L10n.tr("明箱占总长"), value: $params.lightFraction, range: 0.2...0.8)
        NumberField(title: L10n.tr("探头最短持续"), value: $params.pokeMin, unit: "s", range: 0...3)
    }

    @ViewBuilder
    private var novelObjectRows: some View {
        if phase != "Training" {
            SegmentRow(title: L10n.tr("新物体"), selection: $params.novelObject, options: [("A", "A"), ("B", "B")])
        }
        NumberField(title: L10n.tr("物体半径"), value: $params.objectRadius, unit: "cm", range: 0.5...20)
        NumberField(title: L10n.tr("探索距离（物体外缘）"), value: $params.exploreMargin, unit: "cm", range: 0...10)
        NumberField(title: L10n.tr("头朝向容差"), value: $params.headTolerance, unit: "°", range: 5...180)
    }

    @ViewBuilder
    private var barnesMazeRows: some View {
        NumberField(title: L10n.tr("洞的数量"), value: Binding(get: { Double(params.holeCount) }, set: { params.holeCount = max(4, Int($0.rounded())) }), unit: L10n.tr("个"), range: 4...60)
        NumberField(title: L10n.tr("洞半径"), value: $params.holeRadius, unit: "cm", range: 0.5...10)
        NumberField(title: L10n.tr("探洞判定余量"), value: $params.pokeMargin, unit: "cm", range: 0...5)
        NumberField(title: L10n.tr("探洞最短持续"), value: $params.holePokeMin, unit: "s", range: 0...2)
    }

    @ViewBuilder
    private var yMazeRows: some View {
        entryRule
    }

    @ViewBuilder
    private var tMazeRows: some View {
        NumberField(title: L10n.tr("选择点半径（× 臂宽）"), value: $params.choiceRadiusFactor, unit: "×", range: 0.5...3)
        NumberField(title: L10n.tr("VTE 阈值 zIdPhi"), value: $params.vteZ, unit: "", range: -2...5)
    }

    @ViewBuilder
    private var fearConditioningRows: some View {
        OnsetsEditor(title: L10n.tr("CS 开始时间"), onsets: $params.csOnsets)
        NumberField(title: L10n.tr("CS 时长"), value: $params.csDuration, unit: "s", range: 1...600)
        freezeRows(title: L10n.tr("僵直判定"))
        SegmentRow(title: L10n.tr("曲线分段"), selection: $params.timeBin, options: [(20.0, "20 s"), (30.0, "30 s"), (60.0, "1 min"), (120.0, "2 min")])
    }

    @ViewBuilder
    private var loomingRows: some View {
        OnsetsEditor(title: L10n.tr("刺激出现时间"), onsets: $params.stimOnsets)
        NumberField(title: L10n.tr("巢穴半径"), value: $params.shelterRadius, unit: "cm", range: 1...40)
        DisclosureGroup(L10n.tr("反应判定")) {
            VStack(spacing: 10) {
                NumberField(title: L10n.tr("速度倍数（× 基线）"), value: $params.flightFactor, unit: "×", range: 1...20)
                NumberField(title: L10n.tr("最低逃跑速度"), value: $params.flightMinSpeed, unit: "cm/s", range: 1...100)
                NumberField(title: L10n.tr("反应窗口"), value: $params.escapeWindow, unit: "s", range: 1...60)
                NumberField(title: L10n.tr("基线窗口"), value: $params.baselineWindow, unit: "s", range: 1...60)
            }
            .padding(.top, 8)
        }
        .font(.subheadline)
        freezeRows(title: L10n.tr("僵直判定"))
    }

    @ViewBuilder
    private var rotationRows: some View {
        SegmentRow(title: L10n.tr("损伤侧"), selection: $params.lesionSide, options: [("none", L10n.tr("未设置")), ("left", L10n.tr("左侧")), ("right", L10n.tr("右侧"))])
        Toggle(L10n.tr("从下方拍摄（画面左右镜像）"), isOn: $params.cameraBelow).font(.subheadline)
        SegmentRow(title: L10n.tr("分段"), selection: $params.rotationBin, options: [(60.0, "1 min"), (300.0, "5 min"), (600.0, "10 min")])
    }

    @ViewBuilder
    private var poseOnlyRows: some View {
        Text(L10n.tr("仅导出姿态，没有范式参数。")).font(.subheadline).foregroundStyle(.secondary)
    }

    private var entryRule: some View {
        SegmentRow(title: L10n.tr("进入臂的判定"), selection: $params.entryRule, options: [("full", L10n.tr("身体+尾根")), ("body", L10n.tr("身体中心")), ("nose", L10n.tr("鼻尖"))])
    }

    @ViewBuilder
    private func freezeRows(title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
        NumberField(title: L10n.tr("运动阈值"), value: $params.freezeSpeed, unit: "cm/s", range: 0.1...10)
        NumberField(title: L10n.tr("最短持续"), value: $params.freezeMin, unit: "s", range: 0...10)
    }
}

// MARK: - Common settings

struct CommonParamsEditor: View {
    @Binding var params: AnalysisParams
    let duration: Double
    let paradigm: Paradigm

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NumberField(title: L10n.tr("分析起点"), value: $params.windowStart, unit: "s", range: 0...max(0, duration))
            NumberField(title: L10n.tr("分析时长（0 = 到结尾）"), value: $params.windowLength, unit: "s", range: 0...max(0, duration))
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("关键点置信度阈值")).font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f", params.kpConf)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $params.kpConf, in: 0.1...0.9, step: 0.05)
            }
            NumberField(title: L10n.tr("平滑窗口"), value: $params.smoothing, unit: "s", range: 0...1)
            NumberField(title: L10n.tr("最长插值缺口"), value: $params.maxGap, unit: "s", range: 0...5)
            if paradigm != .fearConditioning && paradigm != .rotation {
                SegmentRow(title: L10n.tr("时间分段"), selection: $params.timeBin, options: [(30.0, "30 s"), (60.0, "1 min"), (120.0, "2 min"), (300.0, "5 min")])
            }
        }
    }

}

// MARK: - Helpers

struct PercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 0.01)
        }
    }
}

/// Comma-separated list of times (seconds) with a generator for regular schedules.
struct OnsetsEditor: View {
    let title: String
    @Binding var onsets: [Double]

    @State private var text = ""
    @State private var showGenerator = false
    @State private var first: Double = 120
    @State private var count: Double = 3
    @State private var interval: Double = 90
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(L10n.tr("\(onsets.count) 次")).font(.caption).foregroundStyle(.secondary)
            }
            TextField(L10n.tr("秒，如 120, 210, 300"), text: $text, axis: .vertical)
                .keyboardType(.numbersAndPunctuation)
                .font(.subheadline.monospacedDigit())
                .focused($focused)
                .padding(10)
                .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            DisclosureGroup(L10n.tr("按固定间隔生成"), isExpanded: $showGenerator) {
                VStack(spacing: 10) {
                    NumberField(title: L10n.tr("第一次"), value: $first, unit: "s", range: 0...100_000)
                    NumberField(title: L10n.tr("次数"), value: $count, unit: L10n.tr("次"), range: 1...200)
                    NumberField(title: L10n.tr("间隔（开始到开始）"), value: $interval, unit: "s", range: 0.1...100_000)
                    Button {
                        let n = max(1, Int(count.rounded()))
                        onsets = (0..<n).map { first + Double($0) * interval }
                        text = Self.format(onsets)
                    } label: {
                        Label(L10n.tr("生成"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
        }
        .onAppear { text = Self.format(onsets) }
        .onChange(of: text) { _, t in
            let parsed = Self.parse(t)
            if parsed != onsets { onsets = parsed }
        }
        .onChange(of: onsets) { _, o in
            if !focused { text = Self.format(o) }
        }
    }

    static func parse(_ s: String) -> [Double] {
        s.replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " || $0 == "\n" })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()
    }

    static func format(_ v: [Double]) -> String {
        v.map { abs($0 - $0.rounded()) < 1e-9 ? String(format: "%.0f", $0) : String(format: "%g", $0) }.joined(separator: ", ")
    }
}

// MARK: - Explanations (shown from the ⓘ buttons)

/// What the paradigm parameters mean: the measure definitions plus notes for specific controls.
struct ParamsGuide: View {
    let paradigm: Paradigm

    var body: some View {
        InfoParagraph(L10n.tr("修改阈值或区域后，结果会立即重新计算，不需要重新识别。"))
        if !notes.isEmpty {
            InfoSectionTitle(L10n.tr("参数说明"))
            ForEach(Array(notes.enumerated()), id: \.offset) { _, n in InfoParagraph(n.0, n.1) }
        }
        InfoSectionTitle(L10n.tr("指标定义"))
        ForEach(paradigm.measures, id: \.self) { m in InfoParagraph(m.name, m.definition) }
    }

    private var notes: [(String, String)] {
        let freeze = (L10n.tr("运动阈值"), L10n.tr("核心关键点 0.5 s 窗口位移速度低于此值视为不动"))
        switch paradigm {
        case .threeChamber:
            return [(L10n.tr("中箱宽度（占总长）"), L10n.tr("也可直接拖动视频上的两条中箱边界（紫色 L/R 控制点），分别调整位置和宽度。"))]
        case .openField:
            return [freeze]
        case .fearConditioning:
            return [(L10n.tr("CS 开始时间"), L10n.tr("相对于视频开头的秒数，逗号分隔，如 180, 260, 340")), freeze]
        case .looming:
            return [(L10n.tr("刺激出现时间"), L10n.tr("相对于视频开头的秒数，逗号分隔")), freeze]
        case .rotation:
            return [(L10n.tr("从下方拍摄（画面左右镜像）"), L10n.tr("从透明底部仰拍时画面左右镜像，打开后同侧 / 对侧按动物自身方向换算。"))]
        default:
            return []
        }
    }
}

/// What the analysis window and preprocessing settings do.
struct CommonParamsGuide: View {
    let paradigm: Paradigm

    var body: some View {
        InfoParagraph(L10n.tr("这些设置只影响统计，不需要重新识别。"))
        InfoParagraph(L10n.tr("分析时长（0 = 到结尾）"), windowHelp)
        InfoParagraph(L10n.tr("关键点置信度阈值"), L10n.tr("低于此置信度的关键点视为缺失。调高更严格（缺失更多），调低会保留更多不确定的点。"))
        InfoParagraph(L10n.tr("平滑窗口"), L10n.tr("滑动平均；0 = 不平滑"))
        InfoParagraph(L10n.tr("最长插值缺口"), L10n.tr("不超过这个时长的缺失按线性插值补齐；更长的缺口保持缺失。"))
    }

    private var windowHelp: String {
        switch paradigm {
        case .socialInteraction: return L10n.tr("Golden 2011 标准为 150 s")
        case .elevatedPlusMaze: return L10n.tr("常用 5 min（300 s）")
        case .yMaze: return L10n.tr("常用 8 min（480 s）")
        default: return L10n.tr("只统计这段时间；不影响已识别的数据")
        }
    }
}
