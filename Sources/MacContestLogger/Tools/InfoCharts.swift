import MCLAppModel
import MCLCore
import SwiftUI

/// The colours of the Info window (Kotlin `GOAL_MET`, `GOAL_CLOSE`, `GOAL_MISSED`, `GOAL_LINE`, `OK_BG`, `WARN_BG`,
/// `OVER_BG`, `OPERATOR_COLOR`).
enum InfoColors {
    static let goalMet = Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x32 / 255)
    static let goalClose = Color(red: 0xF9 / 255, green: 0xA8 / 255, blue: 0x25 / 255)
    static let goalMissed = Color(red: 0xC6 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let goalLine = Color(red: 0xC6 / 255, green: 0x28 / 255, blue: 0x28 / 255)
    static let okBackground = Color(red: 0xB9 / 255, green: 0xF6 / 255, blue: 0xCA / 255)
    static let warnBackground = Color(red: 0xFF / 255, green: 0xE0 / 255, blue: 0x82 / 255)
    static let overBackground = Color(red: 0xFF / 255, green: 0xAB / 255, blue: 0x91 / 255)
    static let operatorCall = Color(red: 0x15 / 255, green: 0x65 / 255, blue: 0xC0 / 255)

    /// The colour of a bar or a point against the goal (`barColor`).
    static func color(_ status: GoalStatus) -> Color {
        switch status {
        case .none: return Color(domain: DomainColors.primary)
        case .met: return goalMet
        case .close: return goalClose
        case .missed: return goalMissed
        }
    }

    /// The background of a timer (`nil` = none).
    static func background(_ state: TimerState) -> Color? {
        switch state {
        case .none: return nil
        case .ok: return okBackground
        case .warn: return warnBackground
        case .over: return overBackground
        }
    }
}

/// The left graph (Kotlin `NearTermRates` + `GoalOverlay`): four bars with the value over and the label under, the
/// goal as a horizontal line through the bars.
struct NearTermChart: View {
    static let barWidth: CGFloat = 32
    static let barHeight: CGFloat = 88
    static let spacing: CGFloat = 7

    let rates: NearTermRates
    /// The spoken value (the bars with their goal status); the drawn bars say nothing to VoiceOver.
    var summary: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolCaption(text: rates.title, base: 12)
            VStack(spacing: 0) {
                row { bar in
                    Text(verbatim: String(bar.value))
                        .windowFont(13, weight: .bold, design: .monospaced)
                        .foregroundStyle(InfoColors.color(bar.status))
                }
                bars
                row { bar in
                    Text(verbatim: bar.label)
                        .windowFont(11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rates.title))
        .accessibilityValue(Text(verbatim: summary))
        .accessibilityIdentifier("info.nearTerm")
    }

    private func row<Cell: View>(@ViewBuilder _ cell: @escaping (RateBar) -> Cell) -> some View {
        HStack(spacing: Self.spacing) {
            ForEach(Array(rates.bars.enumerated()), id: \.offset) { _, bar in
                cell(bar)
                    .frame(width: Self.barWidth)
            }
        }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            ForEach(Array(rates.bars.enumerated()), id: \.offset) { _, bar in
                let height: CGFloat = Self.barHeight * CGFloat(bar.value) / CGFloat(max(rates.peak, 1))
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(InfoColors.color(bar.status))
                    .frame(width: Self.barWidth, height: height)
                    .frame(height: Self.barHeight, alignment: .bottom)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let goal = rates.goalLine {
                let offset: CGFloat = Self.barHeight * CGFloat(goal) / CGFloat(max(rates.peak, 1))
                Rectangle()
                    .fill(InfoColors.goalLine)
                    .frame(height: 1)
                    .offset(y: -offset)
            }
        }
    }
}

/// The middle graph (Kotlin `TrendChart`): the rate per interval as a line with the Y axis grid, the dashed goal line,
/// the value over every point and the time under it. The last point is the interval in progress: an outline, the
/// last segment faded.
struct TrendChart: View {
    static let height: CGFloat = 88
    static let valueStrip: CGFloat = 12

    let trend: TrendView
    let windowSize: Int
    /// The spoken value (the points and the last one with its goal status).
    var summary: String = ""

    private var slotWidth: CGFloat {
        CGFloat((Double(windowSize) - 1) * 0.62 * 5 + 12)
    }

    private var axisWidth: CGFloat {
        CGFloat((Double(windowSize) - 2) * 0.62 * 3 + 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ToolCaption(text: trend.title, base: 12)
            Canvas { context, size in
                draw(&context, size: size)
            }
            .frame(width: axisWidth + slotWidth * CGFloat(trend.points.count), height: Self.height + Self.valueStrip)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                Spacer().frame(width: axisWidth)
                ForEach(Array(trend.points.enumerated()), id: \.offset) { _, point in
                    Text(verbatim: point.clock)
                        .windowFont(11)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: slotWidth)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: trend.title))
        .accessibilityValue(Text(verbatim: summary))
        .accessibilityIdentifier("info.trend")
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let points: [TrendPoint] = trend.points
        guard !points.isEmpty else { return }
        let axis: CGFloat = axisWidth
        let top: CGFloat = Self.valueStrip
        let plotHeight: CGFloat = size.height - top
        let slot: CGFloat = (size.width - axis) / CGFloat(points.count)
        let scale: CGFloat = CGFloat(max(trend.scale, 1))
        func xAt(_ index: Int) -> CGFloat { axis + slot * (CGFloat(index) + 0.5) }
        func yAt(_ value: Int) -> CGFloat { top + plotHeight * (1 - CGFloat(value) / scale) }

        let grid: Color = Color.secondary.opacity(0.18)
        let axisFont: Font = .system(size: WindowFont.size(10, windowSize: windowSize), design: .monospaced)
        for label in trend.gridLabels {
            let y: CGFloat = yAt(label)
            var line = Path()
            line.move(to: CGPoint(x: axis, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(grid), lineWidth: 1)
            let text = Text(verbatim: String(label)).font(axisFont).foregroundColor(.secondary)
            context.draw(context.resolve(text), at: CGPoint(x: axis - 3, y: y), anchor: .trailing)
        }
        if let goal = trend.goalLine {
            var line = Path()
            line.move(to: CGPoint(x: axis, y: yAt(goal)))
            line.addLine(to: CGPoint(x: size.width, y: yAt(goal)))
            context.stroke(line, with: .color(InfoColors.goalLine),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        let lineColor: Color = Color(domain: DomainColors.primary)
        for index in 0..<(points.count - 1) {
            let unfinished: Bool = index == points.count - 2
            var segment = Path()
            segment.move(to: CGPoint(x: xAt(index), y: yAt(points[index].value)))
            segment.addLine(to: CGPoint(x: xAt(index + 1), y: yAt(points[index + 1].value)))
            context.stroke(segment, with: .color(lineColor.opacity(unfinished ? 0.45 : 1)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        let valueFont: Font = .system(size: WindowFont.size(11, windowSize: windowSize), weight: .bold,
                                      design: .monospaced)
        for (index, point) in points.enumerated() {
            let center = CGPoint(x: xAt(index), y: yAt(point.value))
            let color: Color = InfoColors.color(point.status)
            let dot = Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            if index == points.count - 1 {
                context.stroke(dot, with: .color(color), lineWidth: 1.5)
            } else {
                context.fill(dot, with: .color(color))
            }
            let text = Text(verbatim: String(point.value)).font(valueFont).foregroundColor(color)
            context.draw(context.resolve(text), at: CGPoint(x: center.x, y: max(center.y - 5, 0)), anchor: .bottom)
        }
    }
}

/// One timer (Kotlin `Timer`): the caption over a big monospaced value, on the colour of its state.
struct InfoTimerView: View {
    let cell: TimerCell
    /// The colour of the state as a word (green / amber / red say nothing to VoiceOver), `nil` = no colour.
    var stateText: String?

    private var timerValue: String {
        let value: String = cell.value ?? "—"
        guard let stateText else { return value }
        return value + ", " + stateText
    }

    var body: some View {
        let background: Color? = InfoColors.background(cell.state)
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: cell.label)
                .windowFont(11)
                .foregroundStyle(background == nil ? Color.secondary : Color.black)
                .lineLimit(1)
            Text(verbatim: cell.value ?? "—")
                .windowFont(18, weight: .bold, design: .monospaced)
                .foregroundStyle(background == nil ? Color(domain: DomainColors.primary) : Color.black)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 3).fill(background ?? Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: cell.label))
        .accessibilityValue(Text(verbatim: timerValue))
    }
}
