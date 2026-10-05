import AppKit
import MCLAppModel
import MCLCore

/// The log table's `NSTableView`: Enter edits the selected row's call, Esc clears the selection (Kotlin: Esc ends
/// the selection mode). Both only while the table itself is the first responder — a cell editor gets its own keys,
/// and with them any input method's composition.
final class LogNSTableView: NSTableView {

    var onEnter: (@MainActor () -> Void)?
    var onEscape: (@MainActor () -> Void)?
    /// Before the table handles a mouse-down (its tracking loop runs inside `super`): the coordinator records the
    /// QSO under the pointer.
    var onMouseDown: (@MainActor (NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
        super.mouseDown(with: event)
    }

    private static let escapeKey: UInt16 = 0x35

    override func keyDown(with event: NSEvent) {
        let flags: NSEvent.ModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain: Bool = flags.intersection([.command, .control, .option, .shift]).isEmpty
        let code: UInt16 = event.keyCode
        if plain && AwtKeyCodes.isMacEnterKey(code) {
            // A held Return must not reopen the editor its first press just closed.
            if !event.isARepeat {
                onEnter?()
            }
        } else if plain && code == Self.escapeKey {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The context menu of a row (Kotlin `ContextMenuArea`; `LT:500-508`): built when it opens for the clicked row
/// (`clickedRow`). One row: the X-QSO toggle, „Přehrát nahrávku QSO" (`RecordingModel.playQsoRecording`, always
/// enabled as in Kotlin), „Smazat QSO" (no confirmation). A row of a selection of two or more: the selection's bulk
/// actions and „Smazat" (asks first).
extension LogTableCoordinator: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let table, let model = tableModel, let language else { return }
        let row: Int = table.clickedRow
        guard row >= 0, row < rows.count, let id = rows[row].id else { return }
        for item in model.menuItems(forRow: id) {
            let menuItem = NSMenuItem(title: language.text(item.title), action: #selector(menuChosen(_:)),
                                      keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = MenuPick(item: item, id: id)
            menuItem.isEnabled = item.isEnabled
            menu.addItem(menuItem)
        }
    }

    @objc func menuChosen(_ sender: NSMenuItem) {
        guard let pick = sender.representedObject as? MenuPick else { return }
        tableModel?.perform(pick.item, row: pick.id)
    }
}

/// A context menu item with the row it was opened on.
private final class MenuPick: NSObject {
    let item: LogTableModel.MenuItem
    let id: Int64

    init(item: LogTableModel.MenuItem, id: Int64) {
        self.item = item
        self.id = id
    }
}
