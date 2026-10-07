import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The entry panel of an entry window (Kotlin `EntryPanel(state, vfo)`, `EP:1029-1370`): with two entry windows the
/// header, the frequency strip, the band × mode grid, the fields (with „Čas UTC" in post-contest entry), the dupe and
/// multiplier feedback, the worked-before strip, the SCP suggestions, the reverse call history lookup, N+1, the info
/// strip with the LEDs, Run/S&P and the CW speed, the F-key bar and the action bar. The keys of the fields are routed
/// by `EntryKeyMonitor`, the mouse wheel by `TuningWheelMonitor` (the panel's frame comes from `TuningWheelArea`);
/// the parts are separate views so each stays small for the type checker.
struct EntryPanelView: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController
    let wheel: TuningWheelMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EntryWindowHeader(app: app, vfo: panel.vfo)
            FrequencyStripView(app: app, panel: panel, focus: focus)
            StationCallWarning(app: app)
            HStack(alignment: .top, spacing: 8) {
                BandGridView(app: app, entry: panel.entry)
                EntryColumn(app: app, panel: panel, focus: focus)
            }
        }
        .padding(8)
        .background(TuningWheelArea(monitor: wheel))
        .disabled(!app.acceptsEntryInput)
    }
}

/// Kotlin's warning about a contest without the station's call.
private struct StationCallWarning: View {
    let app: AppModel

    var body: some View {
        if EntryFeedback.missingStationCall(app.contest) {
            let language: LanguageModel = app.language
            Text(verbatim: language.tr("⚠ Nastav Nastavení → Station data → My Call a znovu vyber závod — ")
                + language.tr("body se počítají relativně k tvé stanici (jinak 0)."))
                .windowFont(11)
                .foregroundStyle(Color(domain: DomainColors.dupe))
        }
    }
}

/// The column right of the band grid, in Kotlin order (`EP:1083-1368`).
private struct EntryColumn: View {
    let app: AppModel
    let panel: EntryPanel
    let focus: EntryFocusController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EntryFieldsRow(app: app, entry: panel.entry, focus: focus)
            if panel.suggestions.showsScpRow {
                ScpSuggestionsView(app: app, panel: panel)
            }
            if panel.suggestions.showsNPlusOneRow {
                NPlusOneView(app: app, panel: panel)
            }
            InfoStripView(app: app, panel: panel)
            FunctionKeyBar(app: app, panel: panel)
            EntryActionBar(app: app, panel: panel, focus: focus)
        }
    }
}

// MARK: - fields

/// The row of fields (`EP:1090-1160`): „Čas UTC" in post-contest entry, the call, Snt, then SentNr and the contest's
/// received fields, or only Rcv in free logging.
private struct EntryFieldsRow: View {
    let app: AppModel
    let entry: EntryModel
    let focus: EntryFocusController

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if app.operating.postContest {
                WeightedField(label: app.language.tr("Čas UTC"), weight: 1.1, content: timeField)
            }
            WeightedField(label: app.language.tr("Volačka"), weight: 2.2, content: callField)
            WeightedField(label: "Snt", weight: 0.8, content: field(.rstSent, text: entry.form.rstSent,
                                                                   label: "Snt") { entry.editRstSent($0) })
            if app.contest.isActive {
                WeightedField(label: "SentNr", weight: 0.8,
                              content: Readout(text: String(format: "%03ld", app.logbook.nextSerial)))
                ContestFieldsView(entry: entry, focus: focus)
            } else {
                // Free logging: reports only — no serial number and no exchange field.
                WeightedField(label: "Rcv", weight: 0.8, content: field(.rstRcvd, text: entry.form.rstRcvd,
                                                                       label: "Rcv") { entry.editRstRcvd($0) })
            }
        }
    }

    /// "Čas UTC" has only Kotlin's shared `keys` (no `fieldKeys`), so Tab is Compose's focus traversal: the next
    /// focusable in composition order, the call field right after it in the row (`EP:1092-1100`). Shift+Tab would go
    /// to the last band-grid cell in Compose (a `clickable` is focusable there); SwiftUI's grid buttons are no key
    /// views, so AppKit's key-view loop decides it.
    private var timeField: some View {
        let entry: EntryModel = self.entry
        let focus: EntryFocusController = self.focus
        return EntryFieldBox(key: .time, text: entry.paperTime, transform: .paperTime, big: false,
                             label: app.language.tr("Čas UTC"), isError: false, focus: focus,
                             onChange: { entry.paperTime = $0 },
                             onTab: { backward in
                                 guard !backward else { return false }
                                 focus.focus(.call)
                                 return true
                             })
    }

    private var callField: some View {
        let entry: EntryModel = self.entry
        return EntryFieldBox(key: .call, text: entry.form.call, transform: .uppercase, big: true,
                             label: app.language.tr("Volačka"), isError: entry.isDupe, focus: focus) {
            entry.callChanged($0)
        }
    }

    private func field(_ key: EntryFieldKey, text: String, transform: EntryTextTransform = .none, label: String,
                       onChange: @escaping @MainActor (String) -> Void) -> EntryFieldBox {
        EntryFieldBox(key: key, text: text, transform: transform, big: false, label: label, isError: false,
                      focus: focus, onChange: onChange)
    }
}

/// The received fields of the active contest (Kotlin `cfields.forEachIndexed`).
private struct ContestFieldsView: View {
    let entry: EntryModel
    let focus: EntryFocusController

    var body: some View {
        ForEach(Array(entry.fields.enumerated()), id: \.offset) { _, contestField in
            let id: String? = contestField.id
            WeightedField(label: id ?? "null", weight: 1,
                          content: EntryFieldBox(key: .contest(id), text: entry.form.contestExchange[id] ?? "",
                                                 transform: .uppercase, big: false, label: id ?? "",
                                                 isError: false, focus: focus) {
                              entry.editContestField(id, $0)
                          })
        }
    }
}

/// One entry field at the window's font size.
private struct EntryFieldBox: View {
    let key: EntryFieldKey
    let text: String
    let transform: EntryTextTransform
    let big: Bool
    let label: String
    let isError: Bool
    let focus: EntryFocusController
    let onChange: @MainActor (String) -> Void
    var onTab: (@MainActor (_ backward: Bool) -> Bool)?

    var body: some View {
        WindowFontReader { size in
            EntryTextField(key: key, text: text, transform: transform,
                           fontSize: WindowFont.size(big ? 20 : 14, windowSize: size), bold: big, isError: isError,
                           accessibilityLabel: label, focus: focus, onChange: onChange, onTab: onTab)
                .frame(height: WindowFont.size(big ? 34 : 26, windowSize: size))
        }
    }
}

/// Reads the window's font size for views that need the number itself (AppKit fields, frame heights).
struct WindowFontReader<Content: View>: View {
    @Environment(\.windowFontSize) private var size
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        content(size)
    }
}

/// A labelled field whose width follows its Kotlin weight and the window font.
struct WeightedField<Content: View>: View {
    let label: String
    let weight: Double
    let content: Content
    @Environment(\.windowFontSize) private var size

    /// Width of weight 1 at the default font (the Kotlin row of fields fills about 630 pt of the 820 pt window).
    static var unit: Double { 90 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .windowFont(11)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            content
        }
        .frame(width: weight * Self.unit * Double(size) / Double(WindowFont.defaultSize))
    }
}

/// Kotlin `Readout`: a read-only value in the row of fields (SentNr).
private struct Readout: View {
    let text: String
    @Environment(\.windowFontSize) private var size

    var body: some View {
        Text(verbatim: text)
            .windowFont(14, design: .monospaced)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: WindowFont.size(26, windowSize: size))
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .quaternaryLabelColor)))
    }
}

/// Kotlin `Chip`.
struct ChipView: View {
    let text: String
    let background: NSColor
    let foreground: NSColor

    var body: some View {
        Text(verbatim: text)
            .windowFont(11, design: .monospaced)
            .foregroundStyle(Color(nsColor: foreground))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: background)))
    }
}

/// The band × mode grid (Kotlin `BandColumns`): a click tunes to the segment start and sets the column's mode.
private struct BandGridView: View {
    let app: AppModel
    let entry: EntryModel

    var body: some View {
        let grid: EntryGrid = EntryGrid.of(app.contest)
        HStack(alignment: .top, spacing: 3) {
            ForEach(grid.columns, id: \.self) { column in
                VStack(spacing: 3) {
                    Text(verbatim: EntryGrid.title(column))
                        .windowFont(11, design: .monospaced)
                    ForEach(grid.rows, id: \.band) { row in
                        let cell = grid.cell(row, column, currentBand: entry.band, currentMode: entry.form.mode)
                        BandCellView(label: row.label, cell: cell) {
                            if let kHz = cell.kHz {
                                entry.qsy(toKHz: kHz, mode: EntryGrid.mode(column))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct BandCellView: View {
    let label: String
    let cell: EntryGrid.Cell
    let action: () -> Void
    @Environment(\.windowFontSize) private var size

    var body: some View {
        Button(action: action) {
            Text(verbatim: label)
                .windowFont(12, design: .monospaced)
                .frame(width: WindowFont.size(38, windowSize: size), height: WindowFont.size(20, windowSize: size))
                .foregroundStyle(foreground)
                .background(RoundedRectangle(cornerRadius: 3).fill(background))
        }
        .buttonStyle(.plain)
        .disabled(!cell.enabled)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(cell.active ? .isSelected : [])
    }

    private var background: Color {
        if cell.active {
            return Color.accentColor
        }
        let base = Color(nsColor: .quaternaryLabelColor)
        return cell.enabled ? base : base.opacity(0.4)
    }

    private var foreground: Color {
        if cell.active {
            return .white
        }
        return cell.enabled ? Color.secondary : Color.secondary.opacity(0.4)
    }
}
