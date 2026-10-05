import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `StatisticsWindow` (`statistics` 820×560, `StatisticsWindow.kt:37-181`): the pivot table of the log (rows ×
/// columns of two dimensions) with the totals and the bar chart of QSOs per hour, or the reports (best rate, breaks,
/// runs). The snapshot is computed off the main thread by the model when the log changes.
struct StatisticsWindowView: View {
    static let id = "statistics"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Statistiky") },
                        size: CGSize(width: 820, height: 560), minSize: CGSize(width: 520, height: 300),
                        appeared: { $0.statistics.open() }, disappeared: { $0.statistics.close() },
                        content: { app, windowSize in
            StatisticsContent(app: app, windowSize: windowSize)
        })
    }
}

private struct StatisticsContent: View {
    let app: AppModel
    let windowSize: Int

    var body: some View {
        let model: StatisticsModel = app.statistics
        let language: LanguageModel = app.language
        VStack(alignment: .leading, spacing: 6) {
            ToolChips(choices: [
                ToolChips.Choice(label: "Pivot", selected: !model.showReports, identifier: "statistics.pivot",
                                 action: { model.setShowReports(false) }),
                ToolChips.Choice(label: language.tr("Rate, přestávky, běhy"), selected: model.showReports,
                                 identifier: "statistics.reports", action: { model.setShowReports(true) }),
            ])
            if model.showReports {
                reports(model)
            } else {
                pivot(model, language: language)
            }
        }
    }

    private func reports(_ model: StatisticsModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((model.snapshot?.reports ?? []).enumerated()), id: \.offset) { index, section in
                    if index > 0 {
                        Divider()
                    }
                    Text(verbatim: section.title)
                        .windowFont(13, weight: .bold)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .windowFont(12, design: .monospaced)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("statistics.reportsView")
    }

    @ViewBuilder private func pivot(_ model: StatisticsModel, language: LanguageModel) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: language.tr("Řádky:")).windowFont(13)
            dimensionPicker(model.rowChoices, selection: model.rowDimension, identifier: "statistics.rows") {
                model.setRows($0)
            }
            Text(verbatim: "Sloupce:").windowFont(13)
            dimensionPicker(model.columnChoices, selection: model.columnDimension,
                            identifier: "statistics.columns") { model.setColumns($0) }
        }
        if let snapshot = model.snapshot {
            HourChartView(chart: snapshot.chart,
                          summary: AccessibilityText.hourChartValue(snapshot.chart,
                                                                    translator: language.translator))
                .frame(height: 110)
            Divider()
            PivotTableView(table: snapshot.table, windowSize: windowSize)
        } else {
            Spacer(minLength: 0)
        }
    }

    private func dimensionPicker(_ choices: [LogStatistics.Dimension], selection: LogStatistics.Dimension,
                                 identifier: String,
                                 select: @escaping (LogStatistics.Dimension) -> Void) -> some View {
        Picker(selection: Binding(get: { selection }, set: { select($0) })) {
            ForEach(choices, id: \.self) { dimension in
                Text(verbatim: dimension.label).tag(dimension)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .windowFont(13)
        .frame(width: 160)
        .accessibilityIdentifier(identifier)
    }
}

/// The pivot (Kotlin `Cell` rows): the header, one row per row label, the totals row; monospaced, the counts right-aligned.
private struct PivotTableView: View {
    let table: StatisticsTable
    let windowSize: Int

    var body: some View {
        let cellWidth: CGFloat = CGFloat(windowSize * 5)
        let headWidth: CGFloat = CGFloat(windowSize * 9)
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                row(table.rowHeader, table.columns, table.totalLabel, bold: true, shaded: true,
                    head: headWidth, cell: cellWidth)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, entry in
                    row(entry.label, entry.cells, entry.total, bold: false, shaded: false, head: headWidth,
                        cell: cellWidth)
                }
                row(table.totalLabel, table.columnTotals, table.grandTotal, bold: true, shaded: true,
                    head: headWidth, cell: cellWidth)
            }
        }
        .accessibilityIdentifier("statistics.pivotTable")
    }

    private func row(_ head: String, _ cells: [String], _ total: String, bold: Bool, shaded: Bool, head headWidth: CGFloat,
                     cell cellWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            cellText(head, width: headWidth, bold: bold, leading: true)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, text in
                cellText(text, width: cellWidth, bold: bold, leading: false)
            }
            cellText(total, width: cellWidth, bold: true, leading: false)
        }
        .background(shaded ? Color.secondary.opacity(0.15) : Color.clear)
    }

    private func cellText(_ text: String, width: CGFloat, bold: Bool, leading: Bool) -> some View {
        Text(verbatim: text)
            .windowFont(12, weight: bold ? .bold : .regular, design: .monospaced)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(width: width, alignment: leading ? .leading : .trailing)
    }
}

/// The bar chart of QSOs per hour (Kotlin `HourChart`): one bar per hour on a common scale, a base line.
private struct HourChartView: View {
    let chart: HourlyChart
    /// The spoken value of the bars (the range and the total).
    var summary: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: chart.title)
                .windowFont(12, weight: .medium)
            Canvas { context, size in
                guard !chart.values.isEmpty else { return }
                let width: CGFloat = size.width / CGFloat(chart.values.count)
                let color: Color = Color(domain: DomainColors.primary)
                for (index, value) in chart.values.enumerated() {
                    let height: CGFloat = size.height * CGFloat(value) / CGFloat(chart.scale)
                    let rect = CGRect(x: CGFloat(index) * width + 1, y: size.height - height,
                                      width: max(width - 2, 1), height: height)
                    context.fill(Path(rect), with: .color(color))
                }
                var base = Path()
                base.move(to: CGPoint(x: 0, y: size.height))
                base.addLine(to: CGPoint(x: size.width, y: size.height))
                context.stroke(base, with: .color(.secondary), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: chart.title))
        .accessibilityValue(Text(verbatim: summary))
        .accessibilityIdentifier("statistics.hourChart")
    }
}

/// Kotlin `ScoreWindow` (`score` 620×420, `ScoreWindow.kt:30-138`): the breakdown of QSOs, dupes, points and
/// multipliers by band × mode (or just bands), the totals, the score formula and the QSOs that could not be counted.
struct ScoreWindowView: View {
    static let id = "score"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Skóre") },
                        size: CGSize(width: 620, height: 420), minSize: CGSize(width: 420, height: 240),
                        appeared: { $0.scoreWindow.open() }, disappeared: { $0.scoreWindow.close() },
                        content: { app, windowSize in
            ScoreContent(app: app, windowSize: windowSize)
        })
    }
}

private struct ScoreContent: View {
    let app: AppModel
    let windowSize: Int

    var body: some View {
        let model: ScoreWindowModel = app.scoreWindow
        let language: LanguageModel = app.language
        if let table = model.table {
            VStack(alignment: .leading, spacing: 6) {
                ToolChips(choices: [
                    ToolChips.Choice(label: language.tr("Pásmo × mód"), selected: model.byMode,
                                     identifier: "score.byMode", action: { model.byMode = true }),
                    ToolChips.Choice(label: language.tr("Jen pásma"), selected: !model.byMode,
                                     identifier: "score.bandsOnly", action: { model.byMode = false }),
                ])
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        scoreRow(table.headers, lead: table.lead, header: true)
                        Divider()
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, cells in
                            scoreRow(cells, lead: table.lead, header: false)
                        }
                        Divider()
                        scoreRow(table.total, lead: table.lead, header: true)
                        if let title = table.modesTitle {
                            Text(verbatim: title)
                                .windowFont(13, weight: .medium)
                                .padding(.top, 10)
                            ForEach(Array(table.modeRows.enumerated()), id: \.offset) { _, cells in
                                scoreRow(cells, lead: table.lead, header: false)
                            }
                        }
                    }
                }
                Divider()
                Text(verbatim: table.footer)
                    .windowFont(12, weight: .bold, design: .monospaced)
                    .accessibilityIdentifier("score.footer")
                if let skipped = table.skippedNote {
                    Text(verbatim: skipped)
                        .windowFont(11)
                        .foregroundStyle(Color(domain: DomainColors.dupe))
                }
            }
        } else {
            Text(verbatim: model.statusText)
                .windowFont(13)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("score.status")
            Spacer(minLength: 0)
        }
    }

    private func scoreRow(_ cells: [String], lead: Int, header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, text in
                Text(verbatim: text)
                    .windowFont(12, weight: header ? .bold : .regular, design: .monospaced)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(width: WindowFont.size(index < lead ? 70 : 72, windowSize: windowSize),
                           alignment: index < lead ? .leading : .trailing)
            }
        }
        .padding(.vertical, 2)
        .background(header ? Color.secondary.opacity(0.15) : Color.clear)
    }
}

/// Kotlin `DupesheetWindow` (`dupesheet` 900×420, `DupesheetWindow.kt:30-109`): the worked calls of the shown band (and
/// mode by the contest's dupe rules) in columns by the digit; calls that contain the typed text are highlighted.
struct DupesheetWindowView: View {
    static let id = "dupesheet"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Dupesheet") },
                        size: CGSize(width: 900, height: 420), minSize: CGSize(width: 420, height: 240),
                        appeared: { $0.dupesheet.open() }, disappeared: { $0.dupesheet.close() },
                        content: { app, windowSize in
            DupesheetContent(app: app, windowSize: windowSize)
        })
    }
}

private struct DupesheetContent: View {
    let app: AppModel
    let windowSize: Int

    var body: some View {
        if let view = app.dupesheet.view {
            Text(verbatim: view.title)
                .windowFont(13, weight: .medium)
                .accessibilityIdentifier("dupesheet.title")
            Divider()
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(view.columns.enumerated()), id: \.offset) { _, column in
                        columnView(column, app.language)
                    }
                }
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private func columnView(_ column: DupesheetColumn, _ language: LanguageModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: column.header)
                .windowFont(12, weight: .bold)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.15))
            ForEach(Array(column.calls.enumerated()), id: \.offset) { _, call in
                let chip = DomainColors.errorContainer
                Text(verbatim: call.text)
                    .accessibilityLabel(Text(verbatim: AccessibilityText.dupesheetCall(
                        call.text, hit: call.hit, translator: language.translator)))
                    .windowFont(12, weight: call.hit ? .bold : .regular, design: .monospaced)
                    .foregroundStyle(call.hit ? Color(domain: chip.text) : Color.primary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(call.hit ? Color(domain: chip.background) : Color.clear)
            }
        }
        .frame(width: CGFloat(windowSize * 7))
    }
}
