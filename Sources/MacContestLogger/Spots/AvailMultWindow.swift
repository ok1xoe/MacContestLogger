import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `AvailableMultipliersWindow` (`availMult` 720×520, `AvailableMultipliersWindow.kt:99-228`, N1MM Available):
/// the Mults / Mults & Qs, „Pásma a režimy", focus-radio and columns buttons with the stepper top-right, the title,
/// the band summary (its bands chosen, hidden or clicked to filter) and the spot list with the user's columns (every
/// header sorts, the dividers drag the widths); a click tunes to the spot, a middle click deletes it, a right click
/// opens the row menu. Without a contest only „Žádný aktivní závod." shows.
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
        let columns: [AvailableColumn] = model.columns
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
                if model.showSummary {
                    Divider()
                    AvailMatrixView(model: model, language: language, matrix: snapshot.matrix)
                }
                Divider()
                if columns.contains(.time) || columns.contains(.heard) {
                    // The age and the speaker change without a new spot: once a second.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        AvailTable(app: app, model: model, snapshot: snapshot, columns: columns, date: context.date)
                    }
                } else {
                    AvailTable(app: app, model: model, snapshot: snapshot, columns: columns, date: Date())
                }
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
        .sheet(isPresented: Binding(get: { model.showColumns }, set: { model.showColumns = $0 })) {
            AvailColumnsSheet(model: model, language: language)
        }
    }
}

/// The Mults / Mults & Qs button (the colour and the label show the current choice), „Pásma a režimy", the
/// focus-radio filter and the columns sheet.
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
            plainButton(language.tr("Pásma a režimy")) {
                model.showFilter = true
            }
            Button {
                model.focusRadioOnly.toggle()
            } label: {
                Text(verbatim: language.tr("Fokus rig"))
                    .windowFont(13, weight: model.focusRadioOnly ? .bold : .regular)
                    .foregroundStyle(model.focusRadioOnly ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 4).fill(model.focusRadioOnly
                        ? Color(nsColor: SpotColors.buttonAll) : Color(nsColor: .quaternaryLabelColor)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(language.tr("Jen spoty na pásmu rádia s fokusem"))
            .accessibilityLabel(Text(verbatim: language.tr("Jen spoty na pásmu rádia s fokusem")))
            .accessibilityValue(Text(verbatim: language.tr(model.focusRadioOnly ? "zapnuto" : "vypnuto")))
            plainButton(language.tr("Sloupce a souhrn")) {
                model.showColumns = true
            }
        }
    }

    private func plainButton(_ title: String, _ action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            Text(verbatim: title)
                .windowFont(13)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .quaternaryLabelColor)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The columns of a row as shares of the width (Kotlin `weight`).
private struct Columns {
    let widths: [CGFloat]
    /// Points per hundredth of a share (a divider drag converts its points with it).
    let pointsPerUnit: CGFloat

    init(total: CGFloat, weights: [CGFloat]) {
        let sum: CGFloat = max(1, weights.reduce(0, +))
        widths = weights.map { total * $0 / sum }
        pointsPerUnit = total / sum
    }
}

/// The band summary (Mults / Qs / Total per band of the chosen bands; N1MM's summary panel): the best band is
/// highlighted, a click on a band shows only its spots (again = the bands as before).
private struct AvailMatrixView: View {
    let model: AvailMultModel
    let language: LanguageModel
    let matrix: [Band?: AvailableMults.Counts]

    var body: some View {
        let bands: [Band] = model.summaryBands
        let best: Band? = AvailableMults.bestBand(matrix, bands: bands)
        GeometryReader { proxy in
            let columns = Columns(total: proxy.size.width, weights: [1.2] + Array(repeating: 1, count: bands.count))
            VStack(alignment: .leading, spacing: 0) {
                header(columns, bands: bands, best: best)
                matrixRow(columns, bands, "Mults") { $0.mults }
                matrixRow(columns, bands, "Qs") { $0.qs }
                matrixRow(columns, bands, "Total") { $0.total }
            }
        }
        .frame(height: 4 * 18)
    }

    private func header(_ columns: Columns, bands: [Band], best: Band?) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: "")
                .frame(width: columns.widths[0], alignment: .leading)
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                let filtered: Bool = model.bands == [band]
                Button {
                    model.clickSummary(band)
                } label: {
                    Text(verbatim: AvailMultModel.bandLabel(band))
                        .windowFont(12, weight: .bold, design: .monospaced)
                        .foregroundStyle(band == best ? AnyShapeStyle(.mclPrimary) : AnyShapeStyle(Color.primary))
                        .underline(filtered)
                        .frame(width: columns.widths[index + 1], alignment: .leading)
                        .background(band == best ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(language.tr("Klik zobrazí jen toto pásmo"))
                .accessibilityLabel(Text(verbatim: summaryLabel(band, best: best, filtered: filtered)))
            }
        }
        .frame(height: 18)
    }

    private func summaryLabel(_ band: Band, best: Band?, filtered: Bool) -> String {
        var text: String = band.adif
        if band == best {
            text += ", " + language.tr("nejlepší pásmo")
        }
        if filtered {
            text += ", " + language.tr("jen toto pásmo")
        }
        return text
    }

    private func matrixRow(_ columns: Columns, _ bands: [Band], _ label: String,
                           _ value: @escaping (AvailableMults.Counts) -> Int) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: label)
                .windowFont(12, design: .monospaced)
                .frame(width: columns.widths[0], alignment: .leading)
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                let n: Int = matrix[band].map(value) ?? 0
                Text(verbatim: String(n))
                    .windowFont(12, design: .monospaced)
                    .foregroundStyle(n > 0 ? AnyShapeStyle(.mclPrimary) : AnyShapeStyle(Color.secondary))
                    .frame(width: columns.widths[index + 1], alignment: .leading)
            }
        }
        .frame(height: 18)
    }
}

/// Holds the window's middle-click monitor while the table is shown; only a click in the table's own window counts.
@MainActor
private final class MiddleClickMonitor: ObservableObject {
    private var token: Any?
    private var handler: (@MainActor () -> Bool)?
    weak var window: NSWindow?

    func install(_ handler: @escaping @MainActor () -> Bool) {
        self.handler = handler
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            let button: Int = event.buttonNumber
            let number: Int = event.windowNumber
            let consumed: Bool = MainActor.assumeIsolated {
                self?.handle(button: button, windowNumber: number) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func handle(button: Int, windowNumber: Int) -> Bool {
        guard button == 2, let window, window.windowNumber == windowNumber, let handler else { return false }
        return handler()
    }

    func remove() {
        if let token {
            NSEvent.removeMonitor(token)
        }
        token = nil
        handler = nil
    }
}

/// The table: the user's columns with sortable headers and draggable dividers, and the rows (`AM:176-209`).
private struct AvailTable: View {
    let app: AppModel
    let model: AvailMultModel
    let snapshot: AvailMultModel.Snapshot
    let columns: [AvailableColumn]
    let date: Date

    @StateObject private var middleClick = MiddleClickMonitor()
    @State private var dragStart: Int?

    var body: some View {
        let spectrum: SignalHeard.Spectrum? = columns.contains(.heard) ? model.spectrum() : nil
        GeometryReader { proxy in
            let layout = Columns(total: proxy.size.width, weights: columns.map { CGFloat(model.width($0)) })
            VStack(alignment: .leading, spacing: 0) {
                header(layout)
                Divider()
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(snapshot.rows, id: \.call) { row in
                                AvailRowView(app: app, model: model, row: row, columns: columns, layout: layout,
                                             age: model.ageText(row, in: snapshot, at: date),
                                             heard: model.isHeard(row, spectrum: spectrum))
                                    .id(row.call)
                            }
                        }
                    }
                    .onChange(of: model.grabbedCall) { _, call in
                        if let call {
                            reader.scrollTo(call)
                        }
                    }
                }
            }
        }
        .background(WindowAccessor { window in
            middleClick.window = window
        })
        .onAppear {
            middleClick.install { [weak model] in
                model?.removeHovered() ?? false
            }
        }
        .onDisappear { middleClick.remove() }
    }

    private func header(_ layout: Columns) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                ZStack(alignment: .trailing) {
                    sortable(column, layout.widths[index])
                    if index < columns.count - 1 {
                        divider(column, layout)
                    }
                }
                .frame(width: layout.widths[index], alignment: .leading)
            }
        }
        .padding(.vertical, 2)
    }

    private func sortable(_ column: AvailableColumn, _ width: CGFloat) -> some View {
        let active: Bool = model.sortColumn == column
        let arrow: String = active ? (model.ascending ? " ▲" : " ▼") : ""
        return Button {
            model.sort(by: column)
        } label: {
            Text(verbatim: column.title + arrow)
                .windowFont(11, weight: .bold)
                .lineLimit(1)
                .foregroundStyle(active ? AnyShapeStyle(.mclPrimary) : AnyShapeStyle(Color.primary))
                .frame(width: width, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: column.title))
    }

    /// The divider right of a header: a drag changes the column's width (saved when the drag ends).
    private func divider(_ column: AvailableColumn, _ layout: Columns) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start: Int = dragStart ?? model.width(column)
                    dragStart = start
                    let units = Int((value.translation.width / max(0.01, layout.pointsPerUnit)).rounded())
                    model.dragWidth(column, to: start + units)
                }
                .onEnded { _ in
                    dragStart = nil
                    model.endWidthDrag()
                })
            .accessibilityHidden(true)
    }
}

/// A row of the table: a click tunes to the spot, a middle click deletes it, the context menu has the spot
/// operations of the Bandmap, the rotator and the other radio's QSY.
private struct AvailRowView: View {
    let app: AppModel
    let model: AvailMultModel
    let row: SpotRow
    let columns: [AvailableColumn]
    let layout: Columns
    let age: String
    let heard: Bool

    var body: some View {
        let color: Color = Color(nsColor: SpotColors.color(SpotColorClassifier.classify(dupe: row.dupe,
                                                                                        newMultCount: row.newMultCount)))
        let marks: AvailMultModel.Marks = model.marks(row)
        Button {
            model.click(row)
        } label: {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    cell(text(column, marks), index, column == .spotter ? Color.secondary : color,
                         bold: column == .call)
                }
            }
            .padding(.vertical, 1)
            .background(model.grabbedCall == row.call ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                model.hoveredCall = row.call
            } else if model.hoveredCall == row.call {
                model.hoveredCall = nil
            }
        }
        .accessibilityLabel(Text(verbatim: spoken(marks)))
        .contextMenu { menu }
    }

    private func text(_ column: AvailableColumn, _ marks: AvailMultModel.Marks) -> String {
        switch column {
        case .call: AvailMultModel.callText(row.call, special: special, marks: marks)
        case .freq: AvailMultModel.freqText(row.freqHz, qsxHz: marks.qsxHz)
        case .dir: row.azimuth.map { String($0) + "°" } ?? ""
        case .mode: row.mode
        case .mult: row.isMult ? "✓" : ""
        case .snr: row.snr.map { String($0) } ?? ""
        case .time: age
        case .spotter: (model.isPreferred(row) ? "★ " : "") + row.spotter
        case .pts: String(row.points)
        case .heard: heard ? "♪" : ""
        }
    }

    /// N1MM Special Calls: the heart after the call.
    private var special: Bool {
        app.bandmap.isSpecialCall(row.call)
    }

    /// The row as one sentence: the colours (dupe, new multiplier), the ✓ column, the heart, the marks and the
    /// speaker are said in words.
    private func spoken(_ marks: AvailMultModel.Marks) -> String {
        let translator: Translator = app.language.translator
        let key: SpotColorClassifier.SpotColorKey = SpotColorClassifier.classify(dupe: row.dupe,
                                                                                 newMultCount: row.newMultCount)
        let base: String = AccessibilityText.bandmapSpot(call: row.call, freqHz: Int(row.freqHz), color: key,
                                                         translator: translator)
        let mult: String = AccessibilityText.multMark(row.isMult, translator: translator)
        let preferred: String = model.isPreferred(row) ? ", " + app.language.tr("preferovaný spotter") : ""
        let marked: String = (mult.isEmpty ? base : base + ", " + mult) + preferred
        let withSpecial: String = special ? marked + ", " + translator.translate("zvláštní volačka") : marked
        return withSpecial + AvailMultModel.spokenMarks(marks, heard: heard, translator: translator)
    }

    private func cell(_ text: String, _ index: Int, _ color: Color, bold: Bool = false) -> some View {
        Text(verbatim: text)
            .windowFont(11, weight: bold ? .bold : .regular, design: .monospaced)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: layout.widths[index], alignment: .leading)
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
        Button(language.tr("Natočit rotátor na %s", .string(row.call))) { model.turnRotor(row) }
        if model.hasOtherRadio {
            Button(language.tr("QSY druhého rádia / VFO")) { model.qsyOtherRadio(row) }
        }
        Divider()
        Button(language.tr("Smazat všechny spoty")) { model.clearSpots() }
    }
}

/// N1MM's Available window options: which columns show and in which order, and the summary panel (shown or not, its
/// bands). The widths are dragged in the header.
struct AvailColumnsSheet: View {
    let model: AvailMultModel
    let language: LanguageModel

    @StateObject private var form = DialogFormState()

    var body: some View {
        let visible: [AvailableColumn] = model.columns
        let chosen: Set<Band> = model.chosenSummaryBands
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Sloupce a souhrn"))
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.tr("Sloupce")).windowFont(13, weight: .semibold)
            ForEach(AvailableColumn.chooserOrder(visible), id: \.self) { column in
                columnRow(column, visible: visible)
            }
            Text(verbatim: language.tr("Šířku sloupce změníš tažením oddělovače v záhlaví."))
                .windowFont(11)
                .foregroundStyle(.secondary)
            Divider()
            Toggle(isOn: Binding(get: { model.showSummary }, set: { model.setShowSummary($0) })) {
                Text(verbatim: language.tr("Zobrazit souhrnný panel")).windowFont(12)
            }
            .toggleStyle(.checkbox)
            Text(verbatim: language.tr("Pásma souhrnu (nic nezaškrtnuto = pásma závodu)")).windowFont(12)
            FlowLayout(spacing: 8) {
                ForEach(Band.allCases, id: \.self) { band in
                    Toggle(isOn: Binding(get: { chosen.contains(band) },
                                         set: { model.setSummaryBand(band, on: $0) })) {
                        Text(verbatim: AvailMultModel.bandLabel(band)).windowFont(12)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            Divider()
            DialogButtonRow {
                Button(language.tr("Výchozí sloupce")) {
                    model.resetColumns()
                }
                Button(language.tr("Zavřít")) {
                    model.showColumns = false
                }
            }
        }
        .padding(16)
        .frame(width: 520)
        .environment(\.windowFontSize, form.fontSize)
    }

    private func columnRow(_ column: AvailableColumn, visible: [AvailableColumn]) -> some View {
        let shown: Bool = visible.contains(column)
        let index: Int? = visible.firstIndex(of: column)
        return HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { shown }, set: { model.setColumn(column, visible: $0) })) {
                Text(verbatim: column.title).windowFont(12).frame(width: 80, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            .disabled(column == .call)
            IconButton(symbol: "arrow.up", label: language.tr("Sloupec doleva")) {
                model.moveColumn(column, by: -1)
            }
            .disabled(index == nil || index == 0)
            IconButton(symbol: "arrow.down", label: language.tr("Sloupec doprava")) {
                model.moveColumn(column, by: 1)
            }
            .disabled(index == nil || index == visible.count - 1)
        }
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
