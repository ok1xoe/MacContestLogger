import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// N1MM „Grid Square Map" (Window → Multipliers, `gridmap` 760×560): the 4-character squares around the own square
/// (or a picked centre) as many as fit the window, north up, coloured worked / spotted / expected, a band filter and
/// a right-click menu per square.
struct GridSquareMapWindowView: View {
    static let id = "gridmap"

    let host: AppHost

    var body: some View {
        ToolWindowShell(host: host, id: Self.id, title: { $0.language.tr("Mapa lokátorových čtverců") },
                        size: CGSize(width: 760, height: 560), minSize: CGSize(width: 360, height: 260),
                        appeared: { $0.gridMap.open() },
                        disappeared: { $0.gridMap.close() },
                        leading: { app in
            if app.gridMap.center != nil {
                Text(verbatim: app.gridMap.headline)
                    .windowFont(13, weight: .bold)
                    .foregroundStyle(.mclPrimary)
                    .lineLimit(1)
                    .accessibilityIdentifier("gridmap.headline")
            }
        },
                        content: { app, windowSize in
            GridSquareMapContent(model: app.gridMap, language: app.language, windowSize: windowSize)
        })
    }
}

private struct GridSquareMapContent: View {
    let model: GridSquareMapModel
    let language: LanguageModel
    let windowSize: Int

    @State private var editingExpected = false

    var body: some View {
        if let center = model.center {
            VStack(alignment: .leading, spacing: 4) {
                toolbar(center)
                Divider()
                matrix(center)
            }
            .sheet(isPresented: $editingExpected) {
                ExpectedSquaresSheet(model: model, language: language) { editingExpected = false }
            }
            .sheet(item: Binding(get: { model.details }, set: { model.details = $0 })) { details in
                MultDetailsSheet(details: details, language: language) { model.details = nil }
            }
        } else {
            Text(verbatim: model.noGridText)
                .windowFont(13)
                .accessibilityIdentifier("gridmap.noGrid")
            Spacer(minLength: 0)
        }
    }

    private func toolbar(_ center: String) -> some View {
        HStack(spacing: 8) {
            Picker(selection: Binding(get: { model.band }, set: { model.band = $0 })) {
                Text(verbatim: language.tr("Všechna pásma")).tag(Band?.none)
                ForEach(model.bandChoices, id: \.self) { band in
                    Text(verbatim: band.adif).tag(Band?.some(band))
                }
            } label: {
                Text(verbatim: language.tr("Pásmo"))
            }
            .fixedSize()
            .windowFont(12)
            .accessibilityIdentifier("gridmap.band")
            legendItem(.worked, "Worked")
            legendItem(.spotted, "Spotted")
            legendItem(.expected, language.tr("Očekávané"))
            Spacer(minLength: 0)
            if model.centerOverride != nil {
                Button(language.tr("Střed na vlastní čtverec")) {
                    model.resetCenter()
                }
                .windowFont(12)
                .accessibilityIdentifier("gridmap.resetCenter")
            }
            optionsMenu
        }
        .padding(.vertical, 2)
    }

    private var optionsMenu: some View {
        Menu {
            Button(language.tr("Očekávané násobiče…")) {
                editingExpected = true
            }
            Button(language.tr("Vymazat očekávané násobiče")) {
                model.clearExpected()
            }
            Button(language.tr("Exportovat pracované násobiče…")) {
                ExpectedMultsFiles.save(model.workedExport, name: "worked-gridsquares.txt")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(Text(verbatim: language.tr("Volby okna násobičů")))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(language.tr("Volby okna násobičů"))
        .accessibilityIdentifier("gridmap.options")
    }

    private func legendItem(_ cell: GridSquareMap.Cell, _ label: String) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(Color(argb: GridSquareMap.color(cell) ?? 0)).frame(width: 12, height: 12)
            Text(verbatim: label).windowFont(11)
        }
    }

    private func matrix(_ center: String) -> some View {
        let font = CGFloat(max(windowSize - 2, 8))
        let cell: CGFloat = font * 3.2
        let cells: [String: GridSquareMap.Cell] = model.cells
        return GeometryReader { proxy in
            let columns: Int = GridSquareMap.fit(length: Double(proxy.size.width), cell: Double(cell))
            let rows: Int = GridSquareMap.fit(length: Double(proxy.size.height), cell: Double(cell))
            let squares: [[String?]] = model.matrix(columns: columns, rows: rows)
            VStack(spacing: 0) {
                ForEach(Array(squares.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 0) {
                        ForEach(Array(line.enumerated()), id: \.offset) { _, square in
                            SquareCell(model: model, square: square, state: square.flatMap { cells[$0] } ?? .empty,
                                       isCenter: square == center, size: cell, font: font)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: language.tr("Mapa lokátorových čtverců")))
    }
}

/// One square of the map with its right-click menu.
private struct SquareCell: View {
    let model: GridSquareMapModel
    let square: String?
    let state: GridSquareMap.Cell
    let isCenter: Bool
    let size: CGFloat
    let font: CGFloat

    var body: some View {
        if let square {
            ZStack {
                Rectangle().fill(GridSquareMap.color(state).map { Color(argb: $0) } ?? Color.clear)
                Rectangle().stroke(Color.secondary.opacity(isCenter ? 1 : 0.35), lineWidth: isCenter ? 2 : 1)
                Text(verbatim: square)
                    .font(.system(size: font, weight: isCenter ? .bold : .regular, design: .monospaced))
                    .foregroundStyle(state == .empty ? Color.primary : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: size, height: size)
            .help(model.tooltip(square))
            .contextMenu {
                SquareMenu(model: model, square: square)
            }
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: square))
            .accessibilityValue(Text(verbatim: stateText))
            .accessibilityIdentifier("gridmap.square.\(square)")
        } else {
            Color.clear.frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private var stateText: String {
        let language: LanguageModel = model.language
        switch state {
        case .worked: return language.tr("pracováno")
        case .spotted: return language.tr("spotováno")
        case .expected: return language.tr("očekáváno")
        case .empty: return ""
        }
    }
}

/// N1MM's right-click menu of a square.
private struct SquareMenu: View {
    let model: GridSquareMapModel
    let square: String

    var body: some View {
        let language: LanguageModel = model.language
        Button(language.tr("Pracované stanice a spoty")) {
            model.showCallsWorked(square)
        }
        if model.canTurnAntenna(square) {
            Button(language.tr("Natočit anténu")) {
                model.turnAntenna(square)
            }
        }
        if model.canSetRover {
            Button(language.tr("Nastavit rover QTH")) {
                model.setRover(square)
            }
        }
        Button(language.tr("Nastavit střed mapy sem")) {
            model.setCenter(square)
        }
        Button(language.tr("Azimut ke středu čtverce")) {
            model.showHeading(square)
        }
    }
}

/// N1MM „Edit Expected Multipliers List" of the grid square map: one square per line.
private struct ExpectedSquaresSheet: View {
    let model: GridSquareMapModel
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
            Text(verbatim: language.tr("Jeden čtverec na řádek (např. JN79)."))
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
                    ExpectedMultsFiles.save(form.text, name: "expected-gridsquares.txt")
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
        .frame(minWidth: 420, minHeight: 360)
        .environment(\.windowFontSize, form.fontSize)
        .onAppear {
            if !loaded {
                form.text = model.expectedText
                loaded = true
            }
        }
    }
}
