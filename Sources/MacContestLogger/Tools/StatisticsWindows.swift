import AppKit
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

    @StateObject private var typing = TypingToEntryForwarder()

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
        .background(WindowAccessor { window in
            typing.attach(window) { [weak app] text in app?.typeIntoEntry(text) }
        })
        .onDisappear {
            typing.detach()
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
            dimensionPicker(model, model.rowChoices, selection: model.rowDimension, identifier: "statistics.rows") {
                model.setRows($0)
            }
            Text(verbatim: "Sloupce:").windowFont(13)
            dimensionPicker(model, model.columnChoices, selection: model.columnDimension,
                            identifier: "statistics.columns") { model.setColumns($0) }
            Toggle(isOn: Binding(get: { model.includeDupes }, set: { model.setIncludeDupes($0) })) {
                Text(verbatim: language.tr("Včetně dupů a X-QSO"))
            }
            .toggleStyle(.checkbox)
            .windowFont(12)
            .accessibilityIdentifier("statistics.includeDupes")
        }
        HStack(spacing: 8) {
            Picker(selection: Binding(get: { model.showGraph }, set: { model.setShowGraph($0) })) {
                Text(verbatim: language.tr("Tabulka")).tag(false)
                Text(verbatim: language.tr("Graf")).tag(true)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(Text(verbatim: language.tr("Zobrazení statistik")))
            Spacer(minLength: 0)
            Button(language.tr("Kopírovat vše")) {
                if let text = model.tableText {
                    app.clipboard(text)
                }
            }
            Button(language.tr("Uložit…")) {
                StatisticsOutput.save(model.tableText)
            }
            Button(language.tr("Tisk…")) {
                StatisticsOutput.print(model.tableText, title: language.tr("Statistiky"))
            }
        }
        .windowFont(12)
        .disabled(model.snapshot == nil)
        if let snapshot = model.snapshot {
            HourChartView(chart: snapshot.chart,
                          summary: AccessibilityText.hourChartValue(snapshot.chart,
                                                                    translator: language.translator))
                .frame(height: 110)
            Divider()
            if model.showGraph {
                PivotGraphView(table: snapshot.table)
            } else {
                PivotTableView(table: snapshot.table, windowSize: windowSize)
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private func dimensionPicker(_ model: StatisticsModel, _ choices: [StatsDimension], selection: StatsDimension,
                                 identifier: String,
                                 select: @escaping (StatsDimension) -> Void) -> some View {
        Picker(selection: Binding(get: { selection }, set: { select($0) })) {
            ForEach(choices, id: \.self) { dimension in
                Text(verbatim: model.label(dimension)).tag(dimension)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .windowFont(13)
        .frame(width: 170)
        .accessibilityIdentifier(identifier)
    }
}

/// N1MM Statistics' Copy All / Print / Print to file of the table.
@MainActor
enum StatisticsOutput {

    /// „Uložit…": the table as a tab-separated text file.
    static func save(_ text: String?) {
        guard let text else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "statistics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// „Tisk…": the table in a monospaced font through the print panel.
    static func print(_ text: String?, title: String) {
        guard let text else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        view.string = text.replacingOccurrences(of: "\t", with: "  ")
        view.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        view.setAccessibilityLabel(title)
        let operation = NSPrintOperation(view: view)
        operation.jobTitle = title
        operation.run()
    }
}

/// The pivot as a graph: one stacked bar per row, a colour per column, with the legend.
private struct PivotGraphView: View {
    let table: StatisticsTable

    private static let palette: [Color] = [.blue, .orange, .green, .red, .purple, .brown, .pink, .teal, .indigo,
                                           .yellow, .mint, .cyan, .gray]

    var body: some View {
        let totals: [Int] = table.rows.indices.map { row in
            table.columns.indices.reduce(0) { $0 + table.count(row: row, column: $1) }
        }
        let scale: Int = max(totals.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ForEach(Array(table.columns.enumerated()), id: \.offset) { index, column in
                    HStack(spacing: 3) {
                        Rectangle()
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(verbatim: column)
                            .windowFont(11)
                    }
                }
            }
            Canvas { context, size in
                guard !table.rows.isEmpty else { return }
                let width: CGFloat = size.width / CGFloat(table.rows.count)
                for row in table.rows.indices {
                    var top: CGFloat = size.height
                    for column in table.columns.indices {
                        let value: Int = table.count(row: row, column: column)
                        guard value > 0 else { continue }
                        let height: CGFloat = size.height * CGFloat(value) / CGFloat(scale)
                        top -= height
                        let rect = CGRect(x: CGFloat(row) * width + 1, y: top, width: max(width - 2, 1),
                                          height: height)
                        context.fill(Path(rect), with: .color(Self.palette[column % Self.palette.count]))
                    }
                }
            }
            .frame(minHeight: 120)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: table.rowHeader))
            .accessibilityValue(Text(verbatim: zip(table.rows, totals).map { $0.0.label + " " + String($0.1) }
                .joined(separator: ", ")))
            HStack(spacing: 0) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Text(verbatim: row.label)
                        .windowFont(9, design: .monospaced)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("statistics.pivotGraph")
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
                let color: Color = AccentToken.color(.primary, in: context.environment)
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
/// N1MM: one sheet per VFO / radio — `dupesheet` follows VFO A, `dupesheet2` the VFO B entry window.
struct DupesheetWindowView: View {
    static let id = "dupesheet"
    static let id2 = "dupesheet2"

    let host: AppHost
    /// 0 = VFO A, 1 = VFO B.
    var vfo: Int = 0

    var body: some View {
        let second: Bool = vfo == 1
        ToolWindowShell(host: host, id: second ? Self.id2 : Self.id,
                        title: { $0.language.tr(second ? "Dupesheet VFO B" : "Dupesheet VFO A") },
                        size: CGSize(width: 900, height: 420), minSize: CGSize(width: 420, height: 240),
                        appeared: { (second ? $0.dupesheet2 : $0.dupesheet).open() },
                        disappeared: { (second ? $0.dupesheet2 : $0.dupesheet).close() },
                        content: { app, windowSize in
            DupesheetContent(app: app, sheet: second ? app.dupesheet2 : app.dupesheet, windowSize: windowSize)
        })
    }
}

private struct DupesheetContent: View {
    let app: AppModel
    let sheet: DupesheetModel
    let windowSize: Int

    var body: some View {
        if let view = sheet.view {
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

/// N1MM: typing while a window that takes no text is in front (Statistics) goes to the Entry window. Plain letters,
/// digits and `/` pressed in the window (not in one of its text fields) are handed over; everything else stays.
@MainActor
final class TypingToEntryForwarder: ObservableObject {

    private var token: Any?
    private weak var window: NSWindow?
    private var forward: (@MainActor (String) -> Void)?

    func attach(_ window: NSWindow, forward: @escaping @MainActor (String) -> Void) {
        self.forward = forward
        guard self.window !== window || token == nil else { return }
        detach()
        self.window = window
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let number: Int = event.windowNumber
            let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters: String = event.characters ?? ""
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(windowNumber: number, flags: flags, characters: characters) ?? false
            }
            return consumed ? nil : event
        }
    }

    func detach() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        window = nil
    }

    private func handle(windowNumber: Int, flags: NSEvent.ModifierFlags, characters: String) -> Bool {
        guard let window, window.windowNumber == windowNumber, window.isKeyWindow,
              flags.intersection([.command, .control, .option]).isEmpty,
              !(window.firstResponder is NSText) else { return false }
        guard !characters.isEmpty,
              characters.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "/") }) else { return false }
        forward?(characters)
        return true
    }
}
