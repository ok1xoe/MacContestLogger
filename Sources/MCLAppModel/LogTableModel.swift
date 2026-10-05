import Foundation
import MCLCore
import Observation

/// The interaction state of the log window („Přehled spojení", Kotlin `LogTable`, `LT:157-433`): the selection, the
/// search and warnings filter, the cell edits, the context menu, the bulk actions and the delete confirmation.
///
/// The table keeps a native, permanent selection (click, ⌘-click, Shift-click as in the Finder — Kotlin's
/// selection semantics) instead of Kotlin's „Režim výběru" toggle; a cell is edited by a double click or Enter.
/// The selection bar shows with two or more selected rows. Deleting **one** QSO (the context menu, the trash) does
/// not ask (Kotlin); deleting the selection asks „Smazat N QSO?" (Kotlin, outside `tr`).
///
/// The rows an action works on are taken when it runs: the selection is a set of ids, resolved against the
/// displayed rows in their order (Kotlin `rows.filter { it.id in selected }`, `LT:377`); an edit starts from the
/// model row of its id (the stored row stays authoritative, `LogbookMutations.update`).
@Observable @MainActor
public final class LogTableModel {

    /// One entry of the row's context menu (`LT:500-508`).
    public enum MenuItem: Equatable, Sendable {
        /// Kotlin „Označit jako X-QSO (nepočítat)" / „Zrušit X-QSO (počítat)".
        case toggleXqso(isXqso: Bool)
        /// Kotlin „Přehrát nahrávku QSO" (`playQsoRecording`, always enabled as in Kotlin).
        case playRecording
        /// Kotlin „Smazat QSO" (outside `tr`), no confirmation.
        case deleteOne
        /// A bulk action over the selection (the selection bar's actions in the menu).
        case bulk(BulkAction)
        /// „Smazat" of the selection bar: asks „Smazat N QSO?".
        case deleteSelection

        public var title: ContestMessage {
            switch self {
            case .toggleXqso(let isXqso):
                return ContestMessage(isXqso ? "Zrušit X-QSO (počítat)" : "Označit jako X-QSO (nepočítat)")
            case .playRecording:
                return ContestMessage("Přehrát nahrávku QSO")
            case .deleteOne:
                return .verbatim("Smazat QSO")
            case .bulk(let action):
                return action.button
            case .deleteSelection:
                return .verbatim("Smazat")
            }
        }

        /// Every item is enabled (Kotlin).
        public var isEnabled: Bool {
            true
        }
    }

    /// Ids of the selected rows (mirrors the table's native selection).
    public private(set) var selected: Set<Int64> = []
    /// The bulk action whose text dialog is open (Kotlin `bulk`).
    public private(set) var bulkPrompt: BulkAction?
    /// Raised with every opened bulk dialog (a new sheet each time).
    public private(set) var bulkPromptId: Int = 0
    /// The „Smazat N QSO?" confirmation is open (Kotlin `confirmDelete`).
    public private(set) var confirmingDelete: Bool = false

    @ObservationIgnored private let logbook: LogbookModel
    @ObservationIgnored private let windows: WindowsModel
    @ObservationIgnored private let status: StatusModel
    /// „Přehrát nahrávku QSO" (`state.playQsoRecording(qso)`).
    @ObservationIgnored private let playRecording: @MainActor (Qso) -> Void
    /// The table's actions in flight by number (tests wait for them); each removes itself when done.
    @ObservationIgnored private var work: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var workCounter: Int = 0

    public init(logbook: LogbookModel, windows: WindowsModel, status: StatusModel,
                playRecording: @escaping @MainActor (Qso) -> Void = { _ in }) {
        self.logbook = logbook
        self.windows = windows
        self.status = status
        self.playRecording = playRecording
    }

    public convenience init(app: AppModel) {
        self.init(logbook: app.logbook, windows: app.windows, status: app.status,
                  playRecording: { [weak recording = app.recording] qso in recording?.playQsoRecording(qso) })
    }

    // MARK: - selection

    /// The table's selection changed (a click, ⌘-click, Shift-click, ⌘A, a removed row).
    public func select(_ ids: Set<Int64>) {
        if ids != selected {
            selected = ids
        }
    }

    /// The selection bar shows with at least two selected rows.
    public var showsSelectionBar: Bool {
        selected.count >= 2
    }

    /// Kotlin `rows.filter { it.id != null && it.id in selected }`: the selected rows that are displayed, in the
    /// displayed order — each as its model row (edits start from it, not from the view copy).
    public var chosen: [Qso] {
        var result: [Qso] = []
        for qso in logbook.displayed {
            guard let id: Int64 = qso.id, selected.contains(id) else { continue }
            let modelRow: Qso? = row(id)
            result.append(modelRow ?? qso)
        }
        return result
    }

    /// Kotlin `tr("Vybráno %s z %s", count, shown)`.
    public var selectionText: ContestMessage {
        ContestMessage("Vybráno %s z %s", .int(selected.count), .int(logbook.displayed.count))
    }

    /// „Vybrat vše": the displayed rows (the active search and filter apply).
    public func selectAll() {
        select(Set(logbook.displayed.compactMap(\.id)))
    }

    /// „Zrušit výběr", „Hotovo", Esc.
    public func clearSelection() {
        select([])
    }

    // MARK: - search and warnings

    /// A new search text. A changed text clears the selection (Kotlin `LaunchedEffect(query)`: a hidden QSO must
    /// not be deleted with the selection).
    public func setQuery(_ text: String) {
        guard text != logbook.query else { return }
        logbook.setQuery(text)
        clearSelection()
    }

    /// Kotlin `LaunchedEffect(state.logSearchRequest)`: Ctrl+F of the entry window fills the search (and clears the
    /// request). Returns whether there was one.
    @discardableResult
    public func takeSearchRequest() -> Bool {
        guard let request = windows.logSearchRequest else { return false }
        setQuery(request)
        windows.logSearchRequest = nil
        return true
    }

    /// Kotlin `onToggleWarnings`.
    public func toggleWarnings() {
        logbook.setOnlyWarnings(!logbook.onlyWarnings)
    }

    /// The text right of the search field: the hint while the search is blank and the warnings filter is off,
    /// otherwise „<shown> z <total>" (Kotlin literal, translated as elsewhere).
    public var searchCaption: ContestMessage {
        if KotlinStrings.isBlank(logbook.query) && !logbook.onlyWarnings {
            return ContestMessage("např. ok1 · 57 · ex:JN79 · nrrx:12 · band:20m")
        }
        return ContestMessage("%s z %s", .int(logbook.displayed.count), .int(logbook.rows.count))
    }

    /// The warnings toggle (`LT:771-779`): shown while there are warnings or the filter is on.
    public var warningsButton: ContestMessage? {
        if logbook.onlyWarnings {
            return ContestMessage("⚠ všechna QSO")
        }
        guard logbook.warnings.count > 0 else { return nil }
        return ContestMessage("⚠ %s varování", .int(logbook.warnings.count))
    }

    /// The tooltip of a row's ⚠ cell (Kotlin `warnings.joinToString("\n")`), `nil` without warnings.
    public func warningText(_ id: Int64?) -> String? {
        guard let id, let messages = logbook.warnings[id], !messages.isEmpty else { return nil }
        return messages.joined(separator: "\n")
    }

    // MARK: - cell actions

    /// The model row of an id (the edits start from it, not from a view copy).
    public func row(_ id: Int64) -> Qso? {
        logbook.rows.first { $0.id == id }
    }

    /// Enter in a cell editor (Kotlin `onCommitText` → `applyEdit` + `update`): the edit of the model row is saved
    /// even when the text did not change (Kotlin saves too).
    public func commitEdit(id: Int64, column: LogTableColumns.Column, text: String) {
        guard let old = row(id) else { return }
        let new: Qso = LogTableEdit.apply(column: column, text: text, to: old)
        track(logbook.startUpdate(LogbookMutations.Edit(old: old, new: new)))
    }

    /// The mode cell's menu (Kotlin `onPickMode`).
    public func pickMode(id: Int64, _ mode: Mode) {
        guard let old = row(id) else { return }
        let new: Qso = LogTableEdit.pickMode(mode, to: old)
        track(logbook.startUpdate(LogbookMutations.Edit(old: old, new: new)))
    }

    /// A click on the X cell or the context menu (Kotlin `onToggleXqso`).
    public func toggleXqso(id: Int64) {
        guard let old = row(id) else { return }
        track(logbook.startToggleXqso(old))
    }

    /// „Smazat QSO" of the context menu or the trash: one QSO, no confirmation, no status (Kotlin `state.delete`).
    public func deleteOne(id: Int64) {
        guard let old = row(id) else { return }
        track(logbook.startDelete([old]))
    }

    /// The context menu of a row: the selection's actions when the row is part of a selection of two or more,
    /// otherwise Kotlin's items for the row („Režim výběru" is gone).
    public func menuItems(forRow id: Int64?) -> [MenuItem] {
        guard let id, let qso = row(id) else { return [] }
        if showsSelectionBar && selected.contains(id) {
            return BulkAction.allCases.map { MenuItem.bulk($0) } + [.deleteSelection]
        }
        return [.toggleXqso(isXqso: qso.xqso), .playRecording, .deleteOne]
    }

    /// Runs a context menu item chosen on the row `id`.
    public func perform(_ item: MenuItem, row id: Int64) {
        switch item {
        case .toggleXqso:
            toggleXqso(id: id)
        case .playRecording:
            if let qso = row(id) {
                playRecording(qso)
            }
        case .deleteOne:
            deleteOne(id: id)
        case .bulk(let action):
            runBulk(action)
        case .deleteSelection:
            askDeleteSelection()
        }
    }

    // MARK: - bulk actions

    /// A bulk button (Kotlin `onBulk`): X-QSO and the interpolation run at once, the others ask for a text.
    public func runBulk(_ action: BulkAction) {
        guard action.needsText else {
            apply(action.run(text: nil, on: chosen))
            return
        }
        bulkPromptId += 1
        bulkPrompt = action
    }

    /// The title of the open bulk dialog (Kotlin `action.title + " (${chosen.size} QSO)"`), read when shown.
    public var bulkTitle: ContestMessage? {
        bulkPrompt.map { $0.dialogTitle(count: chosen.count) }
    }

    /// OK of the bulk dialog: the dialog closes, the action runs over the rows chosen now.
    public func submitBulk(_ text: String) {
        guard let action = bulkPrompt else { return }
        bulkPrompt = nil
        apply(action.run(text: text, on: chosen))
    }

    public func cancelBulk() {
        bulkPrompt = nil
    }

    private func apply(_ outcome: BulkAction.Outcome) {
        if outcome.edits.isEmpty {
            // An invalid input or an empty selection: only the text (if any), nothing is saved.
            if let message = outcome.status {
                status.show(message)
            }
            return
        }
        track(logbook.startBulk(outcome))
    }

    // MARK: - deleting the selection

    /// „Smazat" of the selection bar or the menu: asks first (Kotlin `confirmDelete = true`).
    public func askDeleteSelection() {
        guard !selected.isEmpty else { return }
        confirmingDelete = true
    }

    /// Kotlin `"Smazat ${toDelete.size} QSO?"` (outside `tr`), read when shown.
    public var deleteTitle: ContestMessage {
        .verbatim("Smazat " + String(chosen.count) + " QSO?")
    }

    /// The confirmation's text (`LT:421`).
    public var deleteText: ContestMessage {
        ContestMessage("Vybraná spojení se odstraní z deníku. Akci nelze vzít zpět.")
    }

    /// The confirm button: the chosen rows are deleted in one job, then `tr("Smazáno %s QSO", n)`, and the selection
    /// ends (Kotlin `exitSelection()`).
    public func confirmDeleteSelection() {
        guard confirmingDelete else { return }
        confirmingDelete = false
        let rows: [Qso] = chosen
        clearSelection()
        let job: Task<Bool, Never> = logbook.startDelete(rows)
        track(Task { [status] in
            // Kotlin never reaches the status line when `delete(list)` throws; the error stays shown.
            if await job.value {
                status.show(ContestMessage("Smazáno %s QSO", .int(rows.count)))
            }
        })
    }

    public func cancelDelete() {
        confirmingDelete = false
    }

    // MARK: - work

    private func track<T: Sendable>(_ job: Task<T, Never>) {
        workCounter += 1
        let number: Int = workCounter
        work[number] = Task { @MainActor [weak self] in
            _ = await job.value
            self?.work[number] = nil
        }
    }

    /// Waits for the table's actions in flight and the log's work they started (tests).
    func settle() async {
        while let task = work.values.first {
            await task.value
        }
        await logbook.settle()
    }
}

/// A click in the log table by row identity (Kotlin acts on the row's QSO, never on an index): the QSO and column
/// under the mouse-down, and the check at the action that the pointer is still over that QSO's cell in the rows the
/// table shows **now** — a view applied in between (a sort, an insert at the top, a flush after an edit) can never
/// redirect the click to another QSO.
public struct LogTableClick: Equatable, Sendable {
    public let id: Int64
    public let column: LogTableColumns.Column

    public init(id: Int64, column: LogTableColumns.Column) {
        self.id = id
        self.column = column
    }

    /// The mouse-down on `row` of `rows` (`nil` outside a QSO row or a log column).
    public static func pressed(row: Int, column: LogTableColumns.Column?, in rows: [Qso]) -> LogTableClick? {
        guard let column, row >= 0, row < rows.count, let id = rows[row].id else { return nil }
        return LogTableClick(id: id, column: column)
    }

    /// The QSO to act on when the action comes with the pointer over `row`/`column` of the current `rows`: the
    /// pressed QSO only when it is still there, in the same column; otherwise nothing.
    public func target(row: Int, column: LogTableColumns.Column?, in rows: [Qso]) -> Int64? {
        guard column == self.column, row >= 0, row < rows.count, rows[row].id == id else { return nil }
        return id
    }
}
