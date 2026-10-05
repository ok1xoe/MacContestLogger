import AppKit
import MCLAppModel
import MCLCore
import SwiftUI

/// The log window „Přehled spojení" (Kotlin `KApp:290-310` + `LogTable`): the font stepper, the search bar with the
/// warnings toggle, the selection bar (two or more selected rows), the table, and the bulk and delete dialogs.
struct LogWindowView: View {
    let host: AppHost

    @StateObject private var session = WindowSession(id: "log", persistSize: true,
                                                     defaultSize: CGSize(width: 900, height: 420))
    @StateObject private var tableHolder = LogTableHolder()

    private var binder: WindowGeometryBinder { session.binder }

    var body: some View {
        Group {
            if let app = host.model {
                content(app, table: tableHolder.model(app))
                    .navigationTitle(app.language.tr("Přehled spojení"))
                    .onAppear { binder.setStore(app.geometry) }
                    .background(WindowAccessor { window in
                        binder.isTerminating = { host.isTerminating }
                        binder.onClose = { app.windows.setOpen("log", false) }
                        binder.attach(window)
                    })
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 300, minHeight: 150)
    }

    private func content(_ app: AppModel, table: LogTableModel) -> some View {
        let logbook: LogbookModel = app.logbook
        let language: LanguageModel = app.language
        return VStack(spacing: 0) {
            WindowTopBar(size: $session.fontSize, language: language)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            LogSearchBar(app: app, table: table)
            Divider()
            if table.showsSelectionBar {
                LogSelectionBar(app: app, table: table)
                Divider()
            }
            LogTableView(rows: logbook.displayed, displayRevision: logbook.displayRevision,
                         change: logbook.lastViewChange, columns: logbook.visibleColumns,
                         sortColumn: logbook.effectiveSort, ascending: logbook.ascending, marks: logbook.marks,
                         marksRevision: logbook.marksRevision, warningsRevision: logbook.warningsRevision,
                         selected: table.selected, fontSize: session.fontSize,
                         titles: logbook.visibleColumns.map { language.tr($0.title) },
                         title: language.tr("Přehled spojení"), table: table, language: language,
                         onSort: { logbook.sort(by: $0) })
        }
        .environment(\.windowFontSize, session.fontSize)
        .onAppear {
            table.takeSearchRequest()
        }
        .onChange(of: app.windows.logSearchRequest) {
            // Kotlin `LaunchedEffect(state.logSearchRequest)`: Ctrl+F of the entry window.
            table.takeSearchRequest()
        }
        // The sheets close only through the model (their buttons and keys).
        .sheet(item: Binding(get: { table.bulkPrompt.map { BulkPromptItem(id: table.bulkPromptId, action: $0) } },
                             set: { _ in })) { item in
            BulkPromptSheet(app: app, table: table, item: item)
                .id(item.id)
        }
        .sheet(isPresented: Binding(get: { table.confirmingDelete }, set: { _ in })) {
            DeleteSelectionSheet(app: app, table: table)
        }
    }
}

/// Holds the log window's table model for the window's lifetime (Kotlin keeps this state in the composable).
@MainActor
final class LogTableHolder: ObservableObject {
    private var model: LogTableModel?

    func model(_ app: AppModel) -> LogTableModel {
        if let model {
            return model
        }
        let created = LogTableModel(app: app)
        model = created
        return created
    }
}

/// The log table as an `NSTableView` (podklad 4.2): virtualised rows, a click on a header sorts, a new
/// QSO is inserted with `insertRows(at:)`, an edit reloads only its row, a delete removes only its rows, a change of
/// the marks or warnings reloads only those cells of the visible rows. Native selection, double-click / Enter
/// editing and the context menu are in `LogTableEditing.swift` and `LogTableMenu.swift`.
struct LogTableView: NSViewRepresentable {
    let rows: [Qso]
    let displayRevision: Int
    let change: LogbookModel.ViewChange
    let columns: [LogTableColumns.Column]
    let sortColumn: LogTableColumns.Column
    let ascending: Bool
    let marks: [Int64: QsoMarks.Mark]
    let marksRevision: Int
    let warningsRevision: Int
    let selected: Set<Int64>
    let fontSize: Int
    let titles: [String]
    /// The table's accessibility label (the window title).
    let title: String
    let table: LogTableModel
    let language: LanguageModel
    let onSort: @MainActor (LogTableColumns.Column) -> Void

    func makeCoordinator() -> LogTableCoordinator {
        LogTableCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = LogNSTableView()
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.intercellSpacing = NSSize(width: 6, height: 2)
        table.style = .plain
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        context.coordinator.attach(table)
        scroll.contentView.postsFrameChangedNotifications = true
        context.coordinator.observeResize(of: scroll.contentView)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: LogTableCoordinator) {
        coordinator.teardown()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onSort = onSort
        context.coordinator.table?.setAccessibilityLabel(title)
        context.coordinator.update(self)
    }
}

/// Data source and delegate of the log table.
@MainActor
final class LogTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    /// The identifier of the trash column (Kotlin `ACTION_COL_WIDTH` box with the delete icon).
    static let trashIdentifier = NSUserInterfaceItemIdentifier("trash")
    /// Kotlin `ACTION_COL_WIDTH = 36.dp`.
    static let trashWidth: CGFloat = 36

    weak var table: NSTableView?
    var onSort: (@MainActor (LogTableColumns.Column) -> Void)?
    /// The window's table model (selection, edits, menu actions).
    var tableModel: LogTableModel?
    var language: LanguageModel?

    private(set) var rows: [Qso] = []
    private var marks: [Int64: QsoMarks.Mark] = [:]
    private(set) var columns: [LogTableColumns.Column] = []
    private var titles: [String] = []
    private var sortColumn: LogTableColumns.Column = .time
    private var ascending: Bool = true
    private var fontSize: Int = 0
    private var displayRevision: Int = -1
    private var marksRevision: Int = -1
    private var warningsRevision: Int = -1
    private var resizeObserver: NSObjectProtocol?
    private(set) var font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
    /// The table changes itself (reload, insert, remove, restoring the selection): its selection notifications are
    /// not the user's.
    private var applying: Bool = false

    /// The cell being edited (`LogTableEditing.swift`).
    var editing: CellEdit?
    /// An update that arrived while a cell was edited: applied when the edit ends (Kotlin keeps the editor of
    /// `EditCell(id, col)` across recompositions).
    var pending: LogTableView?
    /// The QSO and column under the last mouse-down; clicks act on it, never on a row index.
    private var pressed: LogTableClick?
    private var resignObserver: NSObjectProtocol?

    func attach(_ table: LogNSTableView) {
        self.table = table
        table.target = self
        table.action = #selector(clicked(_:))
        table.doubleAction = #selector(doubleClicked(_:))
        table.onEnter = { [weak self] in self?.enterPressed() }
        table.onEscape = { [weak self] in self?.tableModel?.clearSelection() }
        table.onMouseDown = { [weak self] event in self?.mouseDown(event) }
        // A cell editor left open in a window that is no longer key would hold back every update of the table:
        // the edit ends like a focus loss (a changed text is saved).
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: nil, queue: .main) { [weak self] note in
            let window: ObjectIdentifier? = (note.object as? NSWindow).map { ObjectIdentifier($0) }
            MainActor.assumeIsolated {
                guard let self, self.editing != nil, let window,
                      let own = self.table?.window, ObjectIdentifier(own) == window else { return }
                self.finishEdit(commit: true, onlyIfChanged: true)
            }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        table.menu = menu
    }

    func observeResize(of clipView: NSClipView) {
        resizeObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                                                object: clipView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitColumns() }
        }
    }

    /// The log window closed: stop observing its clip view.
    func teardown() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resizeObserver = nil
        resignObserver = nil
    }

    func update(_ view: LogTableView) {
        tableModel = view.table
        language = view.language
        guard let table else { return }
        if editing != nil {
            pending = view
            return
        }
        let interval: Perf.Interval = Perf.begin("table-update")
        var detail: String = ""
        defer { Perf.end(interval, detail) }
        applying = true
        defer { applying = false }
        var reloadAll = false
        if view.fontSize != fontSize {
            fontSize = view.fontSize
            let size = CGFloat(WindowFont.size(14, windowSize: fontSize))
            font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            boldFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            table.rowHeight = ceil(size * 1.45)
            reloadAll = true
        }
        let sortChanged: Bool = view.sortColumn != sortColumn || view.ascending != ascending
        sortColumn = view.sortColumn
        ascending = view.ascending
        if view.columns != columns || view.titles != titles || reloadAll {
            columns = view.columns
            titles = view.titles
            rebuildColumns(table)
            reloadAll = true
        } else if sortChanged {
            // Only the arrow moves; the rows follow when the sorted view arrives (a new display revision).
            updateHeaderTitles(table)
        }
        let countBefore: Int = rows.count
        if view.displayRevision != displayRevision {
            let consecutive: Bool = view.displayRevision == displayRevision + 1 && !reloadAll
            displayRevision = view.displayRevision
            let applied: String? = consecutive ? applyChange(view.change, rows: view.rows, table: table) : nil
            if let applied {
                detail = applied
            } else {
                rows = view.rows
                reloadAll = true
            }
        }
        if view.marksRevision != marksRevision {
            marksRevision = view.marksRevision
            marks = view.marks
            if !reloadAll {
                reloadVisibleCells(table, of: [.points, .mult])
            }
        }
        if view.warningsRevision != warningsRevision {
            warningsRevision = view.warningsRevision
            if !reloadAll {
                reloadVisibleCells(table, of: [.warning])
            }
        }
        if reloadAll {
            table.reloadData()
            detail = "reload " + String(rows.count)
        }
        syncSelection(view.selected, table: table)
        if rows.count != countBefore || sortChanged {
            scrollToNewest(table)
        }
    }

    /// Applies an append, an edit or a delete in place; `nil` when the change does not fit the rows shown (the
    /// caller reloads).
    private func applyChange(_ change: LogbookModel.ViewChange, rows newRows: [Qso], table: NSTableView) -> String? {
        let count: Int = rows.count
        switch change {
        case .appended(let index) where index == count && newRows.count == count + 1:
            rows = newRows
            table.insertRows(at: IndexSet(integer: index), withAnimation: [])
            return "insert " + String(rows.count)
        case .updated(let indexes) where newRows.count == count && indexes.allSatisfy({ $0 < count }):
            rows = newRows
            reloadRows(IndexSet(indexes), table: table)
            return "update " + String(indexes.count)
        case .removed(let indexes) where newRows.count == count - indexes.count && indexes.allSatisfy({ $0 < count }):
            rows = newRows
            table.removeRows(at: IndexSet(indexes), withAnimation: [])
            return "remove " + String(indexes.count)
        default:
            return nil
        }
    }

    /// An edited row: all its cells and its X-QSO alpha.
    private func reloadRows(_ indexes: IndexSet, table: NSTableView) {
        guard !indexes.isEmpty else { return }
        table.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        for row in indexes {
            table.rowView(atRow: row, makeIfNecessary: false)?.alphaValue = rows[row].xqso ? 0.5 : 1
        }
    }

    /// The model's selection on the table, by id; ids no longer shown (deleted, filtered out) leave the selection.
    private func syncSelection(_ desired: Set<Int64>, table: NSTableView) {
        var wanted = IndexSet()
        for (index, qso) in rows.enumerated() {
            if let id = qso.id, desired.contains(id) {
                wanted.insert(index)
            }
        }
        if table.selectedRowIndexes != wanted {
            table.selectRowIndexes(wanted, byExtendingSelection: false)
        }
        let shown: Set<Int64> = Set(wanted.compactMap { rows[$0].id })
        if shown != desired {
            // Not during the view update that called this.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    // Unless the selection changed again meanwhile.
                    guard let model = self?.tableModel, model.selected == desired else { return }
                    model.select(shown)
                }
            }
        }
    }

    /// Kotlin `LT:264-273`: a new QSO appears at the end (time ascending) or the start (time descending); other
    /// sorts stay put.
    private func scrollToNewest(_ table: NSTableView) {
        guard !rows.isEmpty, sortColumn == .time else { return }
        table.scrollRowToVisible(ascending ? rows.count - 1 : 0)
    }

    private func rebuildColumns(_ table: NSTableView) {
        for column in table.tableColumns {
            table.removeTableColumn(column)
        }
        for column in columns {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(column.rawValue)))
            tableColumn.headerCell.font = NSFont.systemFont(ofSize: CGFloat(WindowFont.size(12, windowSize: fontSize)))
            tableColumn.minWidth = 16
            tableColumn.resizingMask = .userResizingMask
            table.addTableColumn(tableColumn)
        }
        let trash = NSTableColumn(identifier: Self.trashIdentifier)
        trash.title = ""
        trash.minWidth = Self.trashWidth
        trash.maxWidth = Self.trashWidth
        trash.width = Self.trashWidth
        trash.resizingMask = []
        table.addTableColumn(trash)
        updateHeaderTitles(table)
        fitColumns()
    }

    /// Kotlin header: the translated title, `▲`/`▼` on the sort column.
    private func updateHeaderTitles(_ table: NSTableView) {
        for (index, tableColumn) in table.tableColumns.enumerated() where index < columns.count {
            let column: LogTableColumns.Column = columns[index]
            let arrow: String = column == sortColumn ? (ascending ? " ▲" : " ▼") : ""
            let title: String = index < titles.count ? titles[index] : column.title
            tableColumn.title = title + arrow
            if let language {
                let sorted: Bool? = column == sortColumn ? ascending : nil
                tableColumn.headerCell.setAccessibilityLabel(
                    AccessibilityText.logHeader(title: title, sorted: sorted, translator: language.translator))
            }
        }
        table.headerView?.needsDisplay = true
    }

    /// Kotlin `Modifier.weight`: the columns share the visible width (less the trash column) by their weights (again
    /// whenever the window is resized).
    func fitColumns() {
        guard let table else { return }
        let totalWeight: Double = columns.reduce(0) { $0 + $1.weight }
        let scale: CGFloat = CGFloat(fontSize) / CGFloat(WindowFont.defaultSize)
        let visibleWidth: CGFloat = table.enclosingScrollView?.contentSize.width ?? 0
        let available: CGFloat = visibleWidth > 0 ? visibleWidth : CGFloat(totalWeight) * 60 * scale
        let spacing: CGFloat = table.intercellSpacing.width * CGFloat(columns.count + 2)
        let unit: CGFloat = max(0, available - spacing - Self.trashWidth) / CGFloat(max(totalWeight, 0.01))
        for tableColumn in table.tableColumns {
            guard let column = Self.column(of: tableColumn) else { continue }
            tableColumn.width = max(tableColumn.minWidth, CGFloat(column.weight) * unit)
        }
    }

    static func column(of tableColumn: NSTableColumn?) -> LogTableColumns.Column? {
        guard let tableColumn, let raw = Int(tableColumn.identifier.rawValue) else { return nil }
        return LogTableColumns.Column(rawValue: raw)
    }

    /// The table column index of a log column, `nil` when hidden.
    func index(of column: LogTableColumns.Column) -> Int? {
        columns.firstIndex(of: column)
    }

    private func reloadVisibleCells(_ table: NSTableView, of reloaded: Set<LogTableColumns.Column>) {
        let visible: NSRange = table.rows(in: table.visibleRect)
        guard visible.length > 0 else { return }
        var columnIndexes = IndexSet()
        for (index, column) in columns.enumerated() where reloaded.contains(column) {
            columnIndexes.insert(index)
        }
        guard !columnIndexes.isEmpty else { return }
        table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                         columnIndexes: columnIndexes)
    }

    // MARK: - data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < rows.count else { return nil }
        if tableColumn.identifier == Self.trashIdentifier {
            return trashButton(tableView)
        }
        guard let column = Self.column(of: tableColumn) else { return nil }
        let label: NSTextField
        if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTextField {
            label = reused
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = tableColumn.identifier
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
        }
        configure(label, qso: rows[row], column: column)
        return label
    }

    /// Kotlin's trash icon of a row (`LT:580-589`): deletes the QSO without asking.
    private func trashButton(_ tableView: NSTableView) -> NSButton {
        if let reused = tableView.makeView(withIdentifier: Self.trashIdentifier, owner: self) as? NSButton {
            return reused
        }
        let image: NSImage? = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(trashClicked(_:)))
        button.identifier = Self.trashIdentifier
        button.isBordered = false
        button.contentTintColor = DomainColors.dupe
        let description: String = language?.tr("Smazat QSO") ?? "Smazat QSO"
        button.setAccessibilityLabel(description)
        button.toolTip = description
        return button
    }

    /// Kotlin `.alpha(if (qso.isXqso) 0.5f else 1f)` on the whole row (`LogTable.kt:526`), zebra included.
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        rowView.alphaValue = row < rows.count && rows[row].xqso ? 0.5 : 1
    }

    /// Kotlin `LogRow` colours: the points of a dupe in red, the multiplier bold in amber, the X cell red when set
    /// (a grey `·` otherwise), the ⚠ of a QSO with warnings in red with the reasons as its tooltip.
    func configure(_ label: NSTextField, qso: Qso, column: LogTableColumns.Column) {
        let mark: QsoMarks.Mark? = qso.id.flatMap { marks[$0] }
        var text: String = LogTableColumns.cellText(qso, column: column, marks: mark)
        var color: NSColor = .labelColor
        var cellFont: NSFont = font
        var toolTip: String?
        var spoken: String?
        switch column {
        case .points:
            if mark?.dupe == true {
                color = DomainColors.dupe
                if let language {
                    spoken = AccessibilityText.logPoints(text, dupe: true, translator: language.translator)
                }
            }
        case .mult:
            cellFont = boldFont
            color = DomainColors.multiplier
        case .xqso:
            if text.isEmpty {
                text = "·"
                color = .tertiaryLabelColor
            } else {
                color = DomainColors.dupe
            }
            if let language {
                spoken = AccessibilityText.logXQso(text == "·" ? "" : text, translator: language.translator)
            }
        case .warning:
            toolTip = tableModel?.warningText(qso.id)
            text = toolTip == nil ? "" : "⚠"
            color = DomainColors.dupe
            if let language {
                spoken = AccessibilityText.logWarning(toolTip, translator: language.translator)
            }
        default:
            break
        }
        label.isEditable = false
        label.cell?.isScrollable = false
        label.cell?.wraps = false
        label.lineBreakMode = .byTruncatingTail
        label.stringValue = text
        label.font = cellFont
        label.textColor = color
        label.toolTip = toolTip
        // The marks (⚠, X, a red dupe) are glyphs or colours only; the spoken text says what they mean.
        label.setAccessibilityLabel(spoken)
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let column = Self.column(of: tableColumn) else { return }
        onSort?(column)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !applying, let table else { return }
        var ids: Set<Int64> = []
        for row in table.selectedRowIndexes where row < rows.count {
            if let id = rows[row].id {
                ids.insert(id)
            }
        }
        tableModel?.select(ids)
    }

    // MARK: - clicks

    /// The row and log column under a window point.
    private func cell(at locationInWindow: NSPoint) -> (row: Int, column: LogTableColumns.Column?)? {
        guard let table else { return nil }
        let point: NSPoint = table.convert(locationInWindow, from: nil)
        let row: Int = table.row(at: point)
        let index: Int = table.column(at: point)
        let column: LogTableColumns.Column? = index >= 0 && index < table.tableColumns.count
            ? Self.column(of: table.tableColumns[index]) : nil
        return (row, column)
    }

    /// Records the QSO under the mouse-down. Kotlin: a click on another editable cell opens that one and drops the
    /// open edit unsaved (`edit = EditCell(other)`, `LT:345`).
    private func mouseDown(_ event: NSEvent) {
        guard let hit = cell(at: event.locationInWindow) else {
            pressed = nil
            return
        }
        pressed = LogTableClick.pressed(row: hit.row, column: hit.column, in: rows)
        if let editing, let pressed, let column = hit.column, Self.isEditable(column),
           pressed.id != editing.id || column != editing.column {
            finishEdit(commit: false)
        }
    }

    /// Kotlin's editable cells: the text columns, the time and the mode.
    static func isEditable(_ column: LogTableColumns.Column) -> Bool {
        column == .mode || LogTableEdit.textColumns.contains(column)
    }

    /// The QSO a click action is for: the one pressed, if the pointer is still over its cell in the rows shown now
    /// (`LogTableClick`); with its current row index.
    private func clickTarget() -> (id: Int64, row: Int, column: LogTableColumns.Column)? {
        guard let pressed, let event = NSApp.currentEvent, let hit = cell(at: event.locationInWindow),
              let id = pressed.target(row: hit.row, column: hit.column, in: rows) else { return nil }
        return (id, hit.row, pressed.column)
    }

    /// A single click on the X cell toggles the X-QSO (Kotlin `clickable { onToggleXqso() }`); the click also selects
    /// the row natively. Modifier clicks only change the selection; a drag that ends elsewhere does nothing.
    @objc func clicked(_ sender: Any?) {
        guard NSApp.currentEvent?.clickCount == 1 else { return }
        let flags: NSEvent.ModifierFlags = NSApp.currentEvent?.modifierFlags ?? []
        guard flags.intersection([.command, .shift, .control, .option]).isEmpty,
              let target = clickTarget(), target.column == .xqso else { return }
        tableModel?.toggleXqso(id: target.id)
    }

    /// A double click edits the cell (Kotlin: a click): text cells and the time in a field, the mode from its
    /// menu.
    @objc func doubleClicked(_ sender: Any?) {
        guard let target = clickTarget() else { return }
        beginEdit(row: target.row, column: target.column)
    }

    /// Enter on the table edits the call of the one selected row.
    private func enterPressed() {
        guard let table, table.selectedRowIndexes.count == 1, let row = table.selectedRowIndexes.first else { return }
        beginEdit(row: row, column: .call)
    }

    @objc func trashClicked(_ sender: NSButton) {
        guard let table else { return }
        let row: Int = table.row(for: sender)
        guard row >= 0, row < rows.count, let id = rows[row].id else { return }
        tableModel?.deleteOne(id: id)
    }
}
