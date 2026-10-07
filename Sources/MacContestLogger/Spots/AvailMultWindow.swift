import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `AvailableMultipliersWindow` (`availMult` 720×520, `AvailableMultipliersWindow.kt:99-228`, N1MM Available):
/// the Mults / Mults & Qs and „Pásma a režimy" buttons with the stepper top-right, the title, the band matrix and the
/// sortable table of spots; a click tunes to the spot, a right click opens the row menu. Without a contest only
/// „Žádný aktivní závod." shows.
struct AvailMultWindowView: View {
    static let id = "availMult"

    let host: AppHost

    @StateObject private var session = WindowSession(id: AvailMultWindowView.id, persistSize: true,
                                                     defaultSize: CGSize(width: 720, height: 520))

    var body: some View {
        Group {
            if let app = host.model {
                content(app)
                    .modifier(RadioWindowChrome(host: host, app: app, id: Self.id, title: "Dostupné multiplikátory",
                                                binder: session.binder))
                    .onAppear { app.availMult.resetSort() }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 480, minHeight: 260)
    }

    private func content(_ app: AppModel) -> some View {
        let language: LanguageModel = app.language
        let model: AvailMultModel = app.availMult
        let snapshot: AvailMultModel.Snapshot = model.snapshot()
        return VStack(alignment: .leading, spacing: 4) {
            WindowTopBar(size: $session.fontSize, language: language) {
                if model.contestActive {
                    AvailFilterButtons(model: model, language: language)
                }
            }
            if model.contestActive {
                Text(verbatim: language.text(model.title(snapshot.counts)))
                    .windowFont(13, weight: .bold)
                    .foregroundStyle(.mclPrimary)
                Divider()
                AvailMatrixView(matrix: snapshot.matrix)
                Divider()
                AvailTable(app: app, model: model, rows: snapshot.rows)
            } else {
                Text(verbatim: language.tr("Žádný aktivní závod.")).windowFont(14)
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .environment(\.windowFontSize, session.fontSize)
        .sheet(isPresented: Binding(get: { model.showFilter }, set: { model.showFilter = $0 })) {
            AvailFilterSheet(model: model, language: language)
        }
    }
}

/// The Mults / Mults & Qs button (the colour and the label show the current choice) and „Pásma a režimy".
private struct AvailFilterButtons: View {
    let model: AvailMultModel
    let language: LanguageModel

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.multsOnly.toggle()
            } label: {
                Text(verbatim: model.multsOnly ? "Mults" : "Mults & Qs")
                    .windowFont(13, weight: .bold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(
                        Color(nsColor: model.multsOnly ? SpotColors.buttonMults : SpotColors.buttonAll)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: model.multsOnly ? "Mults" : "Mults & Qs"))
            Button {
                model.showFilter = true
            } label: {
                Text(verbatim: language.tr("Pásma a režimy"))
                    .windowFont(13)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .quaternaryLabelColor)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The columns of a row as shares of the width (Kotlin `weight`).
private struct Columns {
    let widths: [CGFloat]

    init(total: CGFloat, weights: [CGFloat]) {
        let sum: CGFloat = weights.reduce(0, +)
        widths = weights.map { total * $0 / sum }
    }
}

/// The band matrix (Mults / Qs / Total per band of `AvailableMults.matrixBands`).
private struct AvailMatrixView: View {
    let matrix: [Band?: AvailableMults.Counts]

    var body: some View {
        GeometryReader { proxy in
            let columns = Columns(total: proxy.size.width, weights: [1.2] + Array(repeating: 1, count: 6))
            VStack(alignment: .leading, spacing: 0) {
                row(columns, label: "", cells: AvailableMults.matrixBands.map { band in
                    (String(band.adif.dropLast()), true, nil)
                })
                matrixRow(columns, "Mults") { $0.mults }
                matrixRow(columns, "Qs") { $0.qs }
                matrixRow(columns, "Total") { $0.total }
            }
        }
        .frame(height: 4 * 18)
    }

    private func matrixRow(_ columns: Columns, _ label: String,
                           _ value: (AvailableMults.Counts) -> Int) -> some View {
        row(columns, label: label, cells: AvailableMults.matrixBands.map { band in
            let n: Int = matrix[band].map(value) ?? 0
            return (String(n), false, n > 0)
        })
    }

    /// `cells`: the text, bold, and whether it is highlighted (`nil` = the header: the default colour).
    private func row(_ columns: Columns, label: String, cells: [(String, Bool, Bool?)]) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: label)
                .windowFont(12, design: .monospaced)
                .frame(width: columns.widths[0], alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(verbatim: cell.0)
                    .windowFont(12, weight: cell.1 ? .bold : .regular, design: .monospaced)
                    .foregroundStyle(color(cell.2))
                    .frame(width: columns.widths[index + 1], alignment: .leading)
            }
        }
        .frame(height: 18)
    }

    private func color(_ highlighted: Bool?) -> AnyShapeStyle {
        switch highlighted {
        case nil: AnyShapeStyle(Color.primary)
        case true?: AnyShapeStyle(.mclPrimary)
        case false?: AnyShapeStyle(Color.secondary)
        }
    }
}

/// The table: sortable Freq / Dir / Pts headers and the rows (`AM:176-209`).
private struct AvailTable: View {
    let app: AppModel
    let model: AvailMultModel
    let rows: [SpotRow]

    private static let weights: [CGFloat] = [1.3, 1, 0.7, 0.6, 0.5, 0.5, 1.3, 0.5]

    var body: some View {
        GeometryReader { proxy in
            let columns = Columns(total: proxy.size.width, weights: Self.weights)
            VStack(alignment: .leading, spacing: 0) {
                header(columns)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            AvailRowView(app: app, model: model, row: row, columns: columns)
                        }
                    }
                }
            }
        }
    }

    private func header(_ columns: Columns) -> some View {
        HStack(spacing: 0) {
            plain("Call", columns.widths[0])
            sortable("Freq", columns.widths[1], .freq)
            sortable("Dir", columns.widths[2], .dir)
            plain("Md", columns.widths[3])
            plain("Mlt", columns.widths[4])
            plain("SN", columns.widths[5])
            plain("Spotter", columns.widths[6])
            sortable("Pts", columns.widths[7], .pts)
        }
        .padding(.vertical, 2)
    }

    private func plain(_ title: String, _ width: CGFloat) -> some View {
        Text(verbatim: title)
            .windowFont(11, weight: .bold)
            .frame(width: width, alignment: .leading)
    }

    private func sortable(_ title: String, _ width: CGFloat, _ column: AvailableMults.SortColumn) -> some View {
        let active: Bool = model.sortColumn == column
        let arrow: String = active ? (model.ascending ? " ▲" : " ▼") : ""
        return Button {
            model.sort(by: column)
        } label: {
            Text(verbatim: title + arrow)
                .windowFont(11, weight: .bold)
                .foregroundStyle(active ? AnyShapeStyle(.mclPrimary) : AnyShapeStyle(Color.primary))
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// A row of the table: a click tunes to the spot, the context menu has the spot operations of the Bandmap.
private struct AvailRowView: View {
    let app: AppModel
    let model: AvailMultModel
    let row: SpotRow
    let columns: Columns

    var body: some View {
        let color: Color = Color(nsColor: SpotColors.color(SpotColorClassifier.classify(dupe: row.dupe,
                                                                                        newMultCount: row.newMultCount)))
        Button {
            model.click(row)
        } label: {
            HStack(spacing: 0) {
                cell(row.call, 0, color, bold: true)
                cell(EntryFormat.oneDecimal(Double(row.freqHz) / 1000.0), 1, color)
                cell(row.azimuth.map { String($0) + "°" } ?? "", 2, color)
                cell(row.mode, 3, color)
                cell(row.isMult ? "✓" : "", 4, color)
                cell(row.snr.map { String($0) } ?? "", 5, color)
                cell(row.spotter, 6, Color.secondary)
                cell(String(row.points), 7, color)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: spoken))
        .contextMenu { menu }
    }

    /// The row as one sentence: the colours (dupe, new multiplier) and the ✓ column are said in words.
    private var spoken: String {
        let translator: Translator = app.language.translator
        let key: SpotColorClassifier.SpotColorKey = SpotColorClassifier.classify(dupe: row.dupe,
                                                                                 newMultCount: row.newMultCount)
        let base: String = AccessibilityText.bandmapSpot(call: row.call, freqHz: Int(row.freqHz), color: key,
                                                         translator: translator)
        let mult: String = AccessibilityText.multMark(row.isMult, translator: translator)
        return mult.isEmpty ? base : base + ", " + mult
    }

    private func cell(_ text: String, _ column: Int, _ color: Color, bold: Bool = false) -> some View {
        Text(verbatim: text)
            .windowFont(11, weight: bold ? .bold : .regular, design: .monospaced)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: columns.widths[column], alignment: .leading)
    }

    @ViewBuilder
    private var menu: some View {
        let language: LanguageModel = app.language
        Button("Odebrat spot") { model.remove(row) }
        Button(language.tr("Blacklist volačky %s", .string(row.call))) { model.blacklistCall(row) }
        Button("Blacklist spottera " + row.spotter) { model.blacklistSpotter(row) }
        Button("QRZ.com") { model.openQrz(row) }
        Button("HamQTH") { model.openHamQth(row) }
        Divider()
        Button(language.tr("Smazat všechny spoty")) { model.clearSpots() }
    }
}

/// Kotlin `AvailFilterDialog` („Pásma a režimy", N1MM Bands/Modes): the band groups and the traffic categories; what
/// the active contest does not have is greyed out. „Zavřít" closes it.
struct AvailFilterSheet: View {
    let model: AvailMultModel
    let language: LanguageModel

    @StateObject private var form = DialogFormState()

    var body: some View {
        let supportedBands: Set<Band> = model.supportedBands
        let supportedModes: Set<String> = model.supportedModes
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Pásma a režimy"))
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.tr("Pásma")).windowFont(13, weight: .semibold)
            ForEach(Array(AvailMultModel.bandGroups.enumerated()), id: \.offset) { _, group in
                groupRow(group, supported: supportedBands)
            }
            Divider()
            Text(verbatim: language.tr("Režimy")).windowFont(13, weight: .semibold)
            HStack(spacing: 12) {
                ForEach(Array(AvailMultModel.modeChoices.enumerated()), id: \.offset) { _, choice in
                    check(choice.label, on: model.modes.contains(choice.mode), enabled: supportedModes.contains(choice.mode)) {
                        model.setMode(choice.mode, ticked: $0)
                    }
                }
            }
            Divider()
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    model.showFilter = false
                }
            }
        }
        .padding(16)
        .frame(width: 520)
        .environment(\.windowFontSize, form.fontSize)
    }

    private func groupRow(_ group: AvailMultModel.BandGroup, supported: Set<Band>) -> some View {
        let enabled: Bool = group.bands.contains { supported.contains($0) }
        return HStack(alignment: .center, spacing: 6) {
            Button {
                model.toggleGroup(group)
            } label: {
                Text(verbatim: group.title).windowFont(13).frame(width: 44, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            FlowLayout(spacing: 8) {
                ForEach(group.bands, id: \.self) { band in
                    check(AvailMultModel.bandLabel(band), on: model.bands.contains(band),
                          enabled: supported.contains(band)) { model.setBand(band, ticked: $0) }
                }
                ForEach(group.extra, id: \.self) { label in
                    check(label, on: false, enabled: false) { _ in }
                }
            }
        }
    }

    private func check(_ label: String, on: Bool, enabled: Bool, set: @escaping @MainActor (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { set($0) })) {
            Text(verbatim: label).windowFont(12)
        }
        .toggleStyle(.checkbox)
        .disabled(!enabled)
    }
}
