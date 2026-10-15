import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// Kotlin `SearchBar` (`LogTable.kt:727-781`): the search field, its clear button, the hint or „<shown> z <total>",
/// and the „jen varování" toggle while there are warnings (or the filter is on).
struct LogSearchBar: View {
    let app: AppModel
    let table: LogTableModel

    var body: some View {
        let logbook: LogbookModel = app.logbook
        let language: LanguageModel = app.language
        let query = Binding<String>(get: { logbook.query }, set: { table.setQuery($0) })
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(text: query) {
                Text(verbatim: language.tr("Hledat"))
            }
            .textFieldStyle(.roundedBorder)
            .windowFont(14)
            .accessibilityLabel(Text(verbatim: language.tr("Hledat")))
            if !logbook.query.isEmpty {
                IconButton(symbol: "xmark.circle.fill", label: language.tr("Zrušit hledání")) {
                    table.setQuery("")
                }
                .buttonStyle(.borderless)
            }
            Text(verbatim: language.text(table.searchCaption))
                .windowFont(12)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            if let warnings = table.warningsButton {
                Button {
                    table.toggleWarnings()
                } label: {
                    Text(verbatim: language.text(warnings))
                        .windowFont(13)
                        .foregroundStyle(Color(domain: DomainColors.dupe))
                }
                .buttonStyle(.borderless)
            }
            LogViewMenu(app: app, table: table)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

/// The log window's view options (N1MM's Log window menu and View → Notes): only the QSOs with a note, the mode
/// column, and the deleted QSOs (N1MM DELETEDQS).
struct LogViewMenu: View {
    let app: AppModel
    let table: LogTableModel

    var body: some View {
        let language: LanguageModel = app.language
        let logbook: LogbookModel = app.logbook
        Menu {
            Toggle(isOn: Binding(get: { logbook.onlyNotes }, set: { _ in table.toggleNotes() })) {
                Text(verbatim: language.tr("Jen QSO s poznámkou"))
            }
            Toggle(isOn: Binding(get: { table.showsModeColumn }, set: { table.setShowsModeColumn($0) })) {
                Text(verbatim: language.tr("Zobrazit sloupec Mód"))
            }
            Divider()
            Button(language.tr("Smazaná QSO…")) {
                table.openDeleted()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(Text(verbatim: language.tr("Zobrazení deníku")))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(language.tr("Zobrazení deníku"))
    }
}

/// N1MM's DELETEDQS log: the deleted QSOs of the contest, the most recently deleted first; „Obnovit" puts the chosen
/// ones back into the log.
struct DeletedQsosSheet: View {
    let app: AppModel
    let table: LogTableModel

    @StateObject private var form = DialogFormState()
    @StateObject private var keys = DialogKeyMonitor(enterSubmits: false, escapeOnPress: true)

    var body: some View {
        let language: LanguageModel = app.language
        let table: LogTableModel = self.table
        let rows: [LogbookRepository.DeletedQso] = table.deleted ?? []
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.tr("Smazaná QSO"))
                    .windowFont(15, weight: .semibold)
            }
            if rows.isEmpty {
                Text(verbatim: language.tr("Žádná smazaná QSO"))
                    .windowFont(13)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(rows, selection: Binding(get: { table.deletedSelection },
                                               set: { table.deletedSelection = $0 })) {
                    TableColumn(language.tr("Smazáno")) { row in
                        Text(verbatim: LogTableColumns.timeText(row.deletedAt))
                    }
                    TableColumn(language.tr("Čas UTC")) { row in
                        Text(verbatim: LogTableColumns.timeText(row.qso.timestampUtc))
                    }
                    TableColumn(language.tr("Volačka")) { row in
                        Text(verbatim: row.qso.call)
                    }
                    TableColumn(language.tr("Pásmo")) { row in
                        Text(verbatim: row.qso.band?.adif ?? "")
                    }
                    TableColumn(language.tr("Mód")) { row in
                        Text(verbatim: row.qso.mode?.rawValue ?? "")
                    }
                    TableColumn("Exchange") { row in
                        Text(verbatim: row.qso.exchangeRcvd)
                    }
                }
                .windowFont(13, design: .monospaced)
                .accessibilityLabel(Text(verbatim: language.tr("Smazaná QSO")))
            }
            DialogButtonRow {
                Button(language.tr("Zavřít")) {
                    table.closeDeleted()
                }
                Button(language.tr("Exportovat ADIF…")) {
                    StatisticsOutput.save(table.deletedAdif, name: "deleted-qsos.adi")
                }
                .disabled(rows.isEmpty)
                .help(language.tr("Vybraná smazaná QSO (bez výběru všechna) do souboru ADIF"))
                Button(language.tr("Obnovit")) {
                    table.restoreDeleted()
                }
                .disabled(table.deletedSelection.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 360)
        .environment(\.windowFontSize, form.fontSize)
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            keys.onEscape = { table.closeDeleted() }
        }
        .onDisappear {
            keys.detach()
        }
    }
}

/// Kotlin `SelectionBar` (`LT:439-472`), shown with two or more selected rows: „Vybráno N z M", „Vybrat vše",
/// „Zrušit výběr", the bulk actions, „Smazat" (asks first) and „Hotovo" (ends the selection). „Smazat" and „Hotovo"
/// are Kotlin literals outside `tr`.
struct LogSelectionBar: View {
    let app: AppModel
    let table: LogTableModel

    var body: some View {
        let language: LanguageModel = app.language
        let enabled: Bool = !table.selected.isEmpty
        HStack(spacing: 4) {
            Text(verbatim: language.text(table.selectionText))
                .windowFont(12)
                .lineLimit(1)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            Button(language.tr("Vybrat vše")) {
                table.selectAll()
            }
            Button(language.tr("Zrušit výběr")) {
                table.clearSelection()
            }
            .disabled(!enabled)
            ForEach(Array(BulkAction.allCases.enumerated()), id: \.offset) { _, action in
                Button(language.text(action.button)) {
                    table.runBulk(action)
                }
                .disabled(!enabled)
            }
            Button {
                table.askDeleteSelection()
            } label: {
                Text(verbatim: "Smazat")
                    .foregroundStyle(enabled ? Color(domain: DomainColors.dupe) : Color.secondary)
            }
            .disabled(!enabled)
            Button {
                table.clearSelection()
            } label: {
                Text(verbatim: "Hotovo")
            }
        }
        .buttonStyle(.borderless)
        .windowFont(12)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.mclStrip)
    }
}

/// An open bulk dialog as a sheet item.
struct BulkPromptItem: Identifiable {
    let id: Int
    let action: BulkAction
}

/// The bulk actions' text dialog (Kotlin `TextInputDialog(action.title + " (n QSO)", action.hint, "")`, `LT:388`):
/// the text is uppercased as typed (the Kotlin default), Enter confirms on its release, Esc cancels on its press,
/// as the entry window's prompt.
struct BulkPromptSheet: View {
    let app: AppModel
    let table: LogTableModel
    let item: BulkPromptItem

    @StateObject private var form = DialogFormState()
    @StateObject private var keys = DialogKeyMonitor(escapeOnPress: true)
    @StateObject private var focusHolder = FocusHolder()

    var body: some View {
        let language: LanguageModel = app.language
        let table: LogTableModel = self.table
        VStack(alignment: .leading, spacing: 8) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: table.bulkTitle.map { language.text($0) } ?? "")
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.text(item.action.hint))
                .windowFont(12)
                .foregroundStyle(.secondary)
            WindowFontReader { size in
                EntryTextField(key: .call, text: form.text, transform: .uppercase,
                               fontSize: WindowFont.size(14, windowSize: size),
                               accessibilityLabel: language.text(item.action.title),
                               focus: focusHolder.controller) { form.text = $0 }
                    .frame(width: 420 * Double(size) / Double(WindowFont.defaultSize),
                           height: WindowFont.size(26, windowSize: size))
            }
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    table.cancelBulk()
                }
                Button {
                    table.submitBulk(form.text)
                } label: {
                    Text(verbatim: "OK")
                }
            }
        }
        .padding(16)
        .environment(\.windowFontSize, form.fontSize)
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            let form: DialogFormState = self.form
            keys.onEnter = { table.submitBulk(form.text) }
            keys.onEscape = { table.cancelBulk() }
            focusHolder.controller.focus(.call)
        }
        .onDisappear {
            keys.detach()
        }
    }
}

/// Kotlin's confirmation of deleting the selection (`LT:416-432`): „Smazat N QSO?" (outside `tr`), the text, „Zrušit"
/// and „Smazat" in red. As Kotlin's `AlertDialog`, Enter does not confirm and Esc cancels on its press.
struct DeleteSelectionSheet: View {
    let app: AppModel
    let table: LogTableModel

    @StateObject private var keys = DialogKeyMonitor(enterSubmits: false, escapeOnPress: true)
    @StateObject private var form = DialogFormState()

    var body: some View {
        let language: LanguageModel = app.language
        let table: LogTableModel = self.table
        VStack(alignment: .leading, spacing: 10) {
            WindowTopBar(size: $form.fontSize, language: language) {
                Text(verbatim: language.text(table.deleteTitle))
                    .windowFont(15, weight: .semibold)
            }
            Text(verbatim: language.text(table.deleteText))
                .windowFont(13)
                .fixedSize(horizontal: false, vertical: true)
            DialogButtonRow {
                Button(language.tr("Zrušit")) {
                    table.cancelDelete()
                }
                Button {
                    table.confirmDeleteSelection()
                } label: {
                    Text(verbatim: "Smazat")
                        .foregroundStyle(Color(domain: DomainColors.dupe))
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .environment(\.windowFontSize, form.fontSize)
        .background(WindowAccessor { window in
            keys.attach(window)
        })
        .onAppear {
            keys.onEscape = { table.cancelDelete() }
        }
        .onDisappear {
            keys.detach()
        }
    }
}

/// N1MM's lower pane of the log window: the QSOs already logged with the call typed in the entry window, with all
/// their fields (the sent serial, the exchange, the note…).
struct LogPreviousQsosPane: View {
    let app: AppModel
    let table: LogTableModel

    var body: some View {
        let language: LanguageModel = app.language
        let call: String = table.typedCall
        let rows: [Qso] = table.previousQsos
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: rows.isEmpty ? language.tr("%s: zatím žádné QSO", .string(call))
                : language.tr("Předchozí QSO s %s: %s", .string(call), .int(rows.count)))
                .windowFont(12, weight: .semibold)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("log.previous.title")
            if !rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, qso in
                            Text(verbatim: LogTableModel.previousLine(qso))
                                .windowFont(12, design: .monospaced)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
                .accessibilityLabel(Text(verbatim: language.tr("Předchozí QSO s %s: %s", .string(call),
                                                               .int(rows.count))))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
