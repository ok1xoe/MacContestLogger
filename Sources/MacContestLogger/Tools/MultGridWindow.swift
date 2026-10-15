import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `MultiplierGridWindow` (`mult-<kind>` 980×620, `MultiplierGridWindow.kt:77-330`, N1MM multiplier grid): the
/// rows (prefix or key and six bands) flowed into columns by the visible height, the cells coloured worked / spotted /
/// spotted double multiplier, a tooltip with the spot on a spotted cell (a click tunes to it) and, for DXCC, the filter
/// of continents. One window per kind; its id in `openWindows` is `mult:<kind>`, its geometry id `mult-<kind>`.
struct MultGridWindowView: View {
    let host: AppHost
    let kind: String

    static func id(_ kind: String) -> String {
        "mult:" + kind
    }

    var body: some View {
        ToolWindowShell(host: host, id: Self.id(kind), geometryId: "mult-" + kind,
                        title: { $0.multGrid(kind: kind).title },
                        size: CGSize(width: 980, height: 620), minSize: CGSize(width: 420, height: 260),
                        appeared: { $0.multGrid(kind: kind).open() },
                        disappeared: { $0.multGrid(kind: kind).close() },
                        leading: { app in
            Headline(model: app.multGrid(kind: kind))
        },
                        content: { app, windowSize in
            MultGridContent(model: app.multGrid(kind: kind), language: app.language, windowSize: windowSize)
        })
    }
}

private struct Headline: View {
    let model: MultGridModel

    var body: some View {
        if model.contestActive && model.grid.available {
            Text(verbatim: model.headline)
                .windowFont(13, weight: .bold)
                .foregroundStyle(.mclPrimary)
                .lineLimit(1)
                .accessibilityIdentifier("mult.headline")
        }
    }
}

private struct MultGridContent: View {
    let model: MultGridModel
    let language: LanguageModel
    let windowSize: Int

    @State private var editingExpected = false

    var body: some View {
        if !model.contestActive {
            Text(verbatim: model.noContestText)
                .windowFont(13)
                .accessibilityIdentifier("mult.noContest")
            Spacer(minLength: 0)
        } else if !model.grid.available {
            Text(verbatim: model.unavailableText)
                .windowFont(13)
                .accessibilityIdentifier("mult.unavailable")
            Spacer(minLength: 0)
        } else {
            available
                .sheet(isPresented: $editingExpected) {
                    ExpectedMultsSheet(model: model, language: language) { editingExpected = false }
                }
                .sheet(item: Binding(get: { model.details }, set: { model.details = $0 })) { details in
                    MultDetailsSheet(details: details, language: language) { model.details = nil }
                }
        }
    }

    private var available: some View {
        let metrics = MultGridLayout.Metrics(fontSp: max(windowSize - 1, 1))
        return VStack(alignment: .leading, spacing: 0) {
            legend
            Divider()
            GeometryReader { proxy in
                let columns: [[MultGridRow]] = MultGridLayout.columns(
                    rows: model.visibleRows, height: Float(proxy.size.height), metrics: metrics)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, rows in
                            GridColumnView(model: model, rows: rows, metrics: metrics)
                        }
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(MultGridLayout.workedColor, "Worked")
            legendItem(MultGridLayout.spottedColor, "Spotted")
            legendItem(MultGridLayout.spottedDblColor, "Spotted (Dbl Mult)")
            if model.hasContinents {
                continentChecks
            }
            Spacer(minLength: 0)
            optionsMenu
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("mult.legend")
    }

    /// N1MM's right-click list and display items: the bands displayed, „show all possible", the expected list.
    private var optionsMenu: some View {
        Menu {
            Menu(language.tr("Zobrazená pásma")) {
                ForEach(MultGridExtras.bandChoices, id: \.self) { band in
                    Toggle(isOn: Binding(get: { model.bands.contains(band) },
                                         set: { model.setBand(band, shown: $0) })) {
                        Text(verbatim: band.adif)
                    }
                }
            }
            if model.contestModes.count > 1 {
                Menu(language.tr("Zobrazené módy")) {
                    ForEach(model.contestModes, id: \.self) { mode in
                        Toggle(isOn: Binding(get: { model.shownModes.contains(mode) },
                                             set: { model.setMode(mode, shown: $0) })) {
                            Text(verbatim: mode)
                        }
                    }
                }
            }
            Toggle(isOn: Binding(get: { model.showAll }, set: { model.setShowAll($0) })) {
                Text(verbatim: language.tr("Zobrazit všechny možné násobiče"))
            }
            Button(language.tr("Očekávané násobiče…")) {
                editingExpected = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(Text(verbatim: language.tr("Volby okna násobičů")))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(language.tr("Volby okna násobičů"))
        .accessibilityIdentifier("mult.options")
    }

    private var continentChecks: some View {
        HStack(spacing: 4) {
            check("All", selected: model.selected.count == MultGridLayout.continents.count) {
                model.toggleAll()
            }
            ForEach(MultGridLayout.continents, id: \.self) { continent in
                check(continent, selected: model.selected.contains(continent)) {
                    model.toggle(continent: continent)
                }
            }
        }
        .padding(.leading, 12)
    }

    private func check(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { selected }, set: { _ in action() })) {
            Text(verbatim: label).windowFont(11)
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("mult.continent.\(label)")
    }

    private func legendItem(_ color: UInt32, _ label: String) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(Color(argb: color)).frame(width: 12, height: 12)
            Text(verbatim: label).windowFont(11)
        }
    }
}

/// One column of the flow (Kotlin `GridColumn`): the band header and the rows.
private struct GridColumnView: View {
    let model: MultGridModel
    let rows: [MultGridRow]
    let metrics: MultGridLayout.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer().frame(width: CGFloat(metrics.prefixW))
                ForEach(Array(model.bandHeaders.enumerated()), id: \.offset) { _, header in
                    Text(verbatim: header)
                        .font(.system(size: CGFloat(metrics.bandFontSp), weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: CGFloat(metrics.cell), alignment: .leading)
                }
            }
            .frame(height: CGFloat(metrics.headerH))
            ForEach(rows, id: \.key) { row in
                GridRowView(model: model, row: row, metrics: metrics)
            }
        }
    }
}

private struct GridRowView: View {
    let model: MultGridModel
    let row: MultGridRow
    let metrics: MultGridLayout.Metrics
    @Environment(\.mclSpotTooltips) private var spotTooltips

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: MultGridLayout.label(row))
                .font(.system(size: CGFloat(metrics.fontSp), weight: model.isExpected(row) ? .bold : .regular,
                              design: .monospaced))
                .lineLimit(1)
                .padding(.trailing, CGFloat(metrics.prefixGap))
                .frame(width: CGFloat(metrics.prefixW), alignment: .trailing)
                .help(model.prefixInfo(row) ?? "")
            ForEach(Array(model.bands.enumerated()), id: \.offset) { _, band in
                cell(band)
            }
        }
        .frame(height: CGFloat(metrics.rowH))
        .contextMenu {
            MultRowMenu(model: model, row: row)
        }
    }

    @ViewBuilder private func cell(_ band: Band) -> some View {
        let state: MultCell = MultGridLayout.cell(row, band: band)
        let size = CGFloat(metrics.square)
        Group {
            if let argb = MultGridLayout.color(state) {
                if let tip = model.tooltip(key: row.key, band: band) {
                    Rectangle().fill(Color(argb: argb))
                        .frame(width: size, height: size)
                        .help(spotTooltips ? tip : "")
                        .onTapGesture { model.tune(key: row.key, band: band) }
                        .accessibilityElement()
                        .accessibilityLabel(Text(verbatim: "\(MultGridLayout.label(row)) \(band.adif)"))
                        .accessibilityValue(Text(verbatim: tip))
                        .accessibilityAddTraits(.isButton)
                } else {
                    Rectangle().fill(Color(argb: argb)).frame(width: size, height: size)
                }
            } else {
                Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1).frame(width: size, height: size)
            }
        }
        .frame(width: CGFloat(metrics.cell), height: CGFloat(metrics.rowH), alignment: .leading)
    }
}

/// N1MM's right-click menu of a multiplier.
private struct MultRowMenu: View {
    let model: MultGridModel
    let row: MultGridRow

    var body: some View {
        let language: LanguageModel = model.languageModel
        Button(language.tr("Pracované stanice a spoty")) {
            model.showCallsWorked(row)
        }
        if model.isZoneKind {
            Button(language.tr("Země v zóně")) {
                model.showCountries(row)
            }
        }
        if model.canTurnAntenna(row) {
            Button(language.tr("Natočit anténu")) {
                model.turnAntenna(row)
            }
        }
        if model.canSetRover {
            Button(language.tr("Nastavit rover QTH")) {
                model.setRover(row)
            }
        }
    }
}

/// The list of „calls worked and spots" or „countries in zone".
struct MultDetailsSheet: View {
    let details: MultGridDetails
    let language: LanguageModel
    let close: () -> Void

    @StateObject private var form = DialogFormState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: details.title)
                    .windowFont(15, weight: .semibold)
            }
            ScrollView {
                Text(verbatim: details.lines.joined(separator: "\n"))
                    .windowFont(13, design: .monospaced)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel(Text(verbatim: details.title))
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 300)
        .environment(\.windowFontSize, form.fontSize)
    }
}

/// N1MM „Edit Expected Multiplier List": one multiplier per line, import and export of plain text files, the export
/// of the multipliers and bands worked in this contest.
private struct ExpectedMultsSheet: View {
    let model: MultGridModel
    let language: LanguageModel
    let close: () -> Void

    @StateObject private var form = DialogFormState()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Očekávané násobiče"))
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.tr("Jeden násobič na řádek, velkými písmeny, jak je okno ukazuje."))
                .windowFont(12)
                .foregroundStyle(.secondary)
            TextEditor(text: $form.text)
                .windowFont(13, design: .monospaced)
                .frame(minHeight: 200)
                .accessibilityLabel(Text(verbatim: language.tr("Očekávané násobiče")))
            HStack(spacing: 8) {
                Button(language.tr("Importovat…")) {
                    if let text = ExpectedMultsFiles.open() {
                        form.text = text
                    }
                }
                Button(language.tr("Exportovat…")) {
                    ExpectedMultsFiles.save(form.text, name: "expected-\(model.kind).txt")
                }
                Button(language.tr("Exportovat pracované násobiče…")) {
                    ExpectedMultsFiles.save(model.workedExport, name: "worked-\(model.kind).txt")
                }
                Spacer(minLength: 0)
            }
            .windowFont(12)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
                Button(language.tr("Uložit")) {
                    model.setExpectedText(form.text)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 380)
        .environment(\.windowFontSize, form.fontSize)
        .onAppear {
            if !loaded {
                form.text = model.expectedText
                loaded = true
            }
        }
    }
}

/// Plain text files of the expected list.
@MainActor
enum ExpectedMultsFiles {

    static func open() -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func save(_ text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
