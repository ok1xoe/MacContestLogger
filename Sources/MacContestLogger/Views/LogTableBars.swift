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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
