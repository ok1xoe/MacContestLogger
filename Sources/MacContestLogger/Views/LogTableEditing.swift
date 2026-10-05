import AppKit
import MCLAppModel
import MCLCore

/// The cell being edited in the log table.
struct CellEdit {
    let id: Int64
    let column: LogTableColumns.Column
    let field: NSTextField
    /// The text the editor started with.
    let original: String
}

/// In-cell editing of the log table (Kotlin `EditableCell`, `ModeCell`, `LT:633-705`).
///
/// A double click (or Enter on the one selected row: the call) opens the cell's own `NSTextField` as the native
/// table editor. Text cells start with the cell text, the time with its full form `yyyy-MM-dd HH:mm:ss`
/// (`LogTableEdit.editText`). Enter saves and Esc cancels **on the press** — the native editor's commands
/// (`insertNewline:`, `cancelOperation:`); Kotlin acts on the key's release (divergence). A mouse-down on another
/// editable cell drops the edit unsaved (Kotlin). Moving the focus away otherwise (a click on a read-only cell or
/// elsewhere, Tab, the window resigning key) saves a changed text, the native behaviour; Kotlin leaves its editor
/// open (divergence).
/// While text is being composed (an input method's marked text), the field editor gets every key: its commands
/// reach this delegate only after the composition is committed or cancelled.
///
/// The mode cell opens a menu of `Mode.values()` below the cell (Kotlin `DropdownMenu`); dismissing it changes
/// nothing.
extension LogTableCoordinator: NSTextFieldDelegate {

    /// Opens the editor of a cell (no-op for read-only cells: band, warning, points, multipliers, X).
    func beginEdit(row: Int, column: LogTableColumns.Column) {
        guard editing == nil, let table, row >= 0, row < rows.count, let id = rows[row].id else { return }
        if column == .mode {
            showModeMenu(row: row, id: id)
            return
        }
        guard LogTableEdit.textColumns.contains(column), let columnIndex = index(of: column),
              let qso = tableModel?.row(id) else { return }
        table.scrollRowToVisible(row)
        guard let field = table.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTextField else {
            return
        }
        let text: String = LogTableEdit.editText(qso, column: column)
        field.stringValue = text
        field.textColor = .labelColor
        field.isEditable = true
        field.isSelectable = true
        // A long text scrolls in a narrow cell instead of clipping the caret.
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        editing = CellEdit(id: id, column: column, field: field, original: text)
        if table.window?.makeFirstResponder(field) != true {
            finishEdit(commit: false)
            return
        }
        field.currentEditor()?.selectAll(nil)
    }

    /// The field editor's commands: Enter saves, Esc cancels. Nothing is taken while text is marked (the input
    /// method owns the keys then).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let editing, control === editing.field, !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            finishEdit(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            finishEdit(commit: false)
            return true
        default:
            return false
        }
    }

    /// The editor lost the focus (a click elsewhere, Tab): a changed text is saved (native; Kotlin keeps the editor).
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let editing, (notification.object as? NSTextField) === editing.field else { return }
        finishEdit(commit: true, onlyIfChanged: true)
    }

    /// Closes the editor; `commit` saves the text through the model (Kotlin `onCommitText` → `applyEdit` +
    /// `update`, saved even when unchanged). The cell shows the model row again, and an update that waited for the
    /// edit is applied.
    func finishEdit(commit: Bool, onlyIfChanged: Bool = false) {
        guard let state = editing else { return }
        editing = nil
        let text: String = state.field.stringValue
        state.field.delegate = nil
        if let window = state.field.window, let editor = state.field.currentEditor(), window.firstResponder === editor {
            window.makeFirstResponder(table)
        }
        state.field.isEditable = false
        state.field.isSelectable = false
        if commit && !(onlyIfChanged && text == state.original) {
            tableModel?.commitEdit(id: state.id, column: state.column, text: text)
        }
        if let qso = tableModel?.row(state.id) {
            configure(state.field, qso: qso, column: state.column)
        }
        // The parked update after the current event: neither this mouse-down or key command nor the field editor's
        // own end-of-editing sees the table reload under it.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.editing == nil, let waiting = self.pending else { return }
                self.pending = nil
                self.update(waiting)
            }
        }
    }

    // MARK: - mode

    /// Kotlin `ModeCell`: the modes in `Mode.values()` order, monospaced, below the cell.
    private func showModeMenu(row: Int, id: Int64) {
        guard let table, let columnIndex = index(of: .mode) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = font
        for mode in LogTableEdit.modes {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(modePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ModePick(id: id, mode: mode)
            menu.addItem(item)
        }
        let cell: NSRect = table.frameOfCell(atColumn: columnIndex, row: row)
        menu.popUp(positioning: nil, at: NSPoint(x: cell.minX, y: cell.maxY), in: table)
    }

    @objc func modePicked(_ sender: NSMenuItem) {
        guard let pick = sender.representedObject as? ModePick else { return }
        tableModel?.pickMode(id: pick.id, pick.mode)
    }
}

/// The QSO and mode of a mode menu item.
private final class ModePick: NSObject {
    let id: Int64
    let mode: Mode

    init(id: Int64, mode: Mode) {
        self.id = id
        self.mode = mode
    }
}
