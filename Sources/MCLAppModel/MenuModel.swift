import Foundation
import MCLCore
import Observation

/// The menu tree from `menu.json` (Kotlin `App.kt` `KApp:543-608`): loaded with its source, labels through `tr`, the
/// runtime enabling of `runtimeEnabled` (`KApp:575`) and the actions implemented so far (the others
/// are shown disabled with „Zatím nedostupné").
@Observable @MainActor
public final class MenuModel {

    /// Prefix of the nodes that are Settings tabs, not menu items (`TAB_ID_PREFIX`).
    public static let tabPrefix = "tab."

    /// Actions implemented so far (the log window, `settings.downloadScp` and `contest.postcontest`,
    /// import, merge, exports, printing, data tools, definition editor and profiles, the Settings window, the
    /// contest recording and radio tool windows, the spot windows, the network windows and the info and tool windows).
    public static let implementedActions: Set<String> = [
        "contest.new", "contest.open", "contest.rescore", "contest.none", "database.new", "database.open",
        "window.log", "settings.exportCabrillo", "settings.export", "settings.downloadScp", "contest.postcontest",
        "settings.import", "settings.merge", "settings.exportEdi", "settings.exportOther", "settings.print",
        "database.refillDxcc", "database.updateClubLogDxcc", "contest.updateCallHistory", "contest.updateDefinitions", "contest.editor",
        "settings.profiles", "settings.open", "contest.record", "window.catlog", "window.rotator",
        "window.cwkeyboard", "window.cwreader", "window.digitalinterface", "window.waterfall", "beacons.load",
        "window.dxcluster", "window.bandmap", "window.availmult", "window.blacklist", "window.netstatus",
        "window.chat", "window.partner", "window.wsjtxdecodes", "window.hamqthlog", "window.rate", "window.skeds",
        "window.score", "window.movemults", "window.dupesheet", "window.statistics", "window.qtc",
        "window.propagation", "window.bandnotes", "window.simulator", "window.dxccmap", "mult.dxcc", "mult.grid",
        "mult.map", "mult.itu", "mult.cq", "mult.districts", "mult.other", "mult.sections",
        "edit.wipe", "edit.wipeUndo", "edit.incrementNr", "edit.note", "edit.find", "edit.deleteLast",
        "settings.keys", "help.docs", "help.shortcuts", "help.commands", "help.report", "help.dataFolder",
    ]

    /// The Edit items that run an entry-window shortcut, and the Help item that is its key: the menu shows the key
    /// the user has (remapped or default) next to the label; the item itself carries no key equivalent, the entry
    /// window's key router stays the only one that reacts to the keys.
    public static let shortcutActions: [String: ShortcutAction] = [
        "edit.wipe": .wipe, "edit.wipeUndo": .wipeUndo, "edit.incrementNr": .incrementNr, "edit.note": .note,
        "edit.find": .find, "edit.deleteLast": .deleteLast, "help.docs": .help,
    ]

    /// Prefix of the ids of separator nodes (`sep.file.1`): drawn as a separator line, never an item.
    public static let separatorPrefix = "sep."

    /// A menu action requested by a call-field command (Kotlin `pendingMenuAction`: EXPORT, CABRILLO, CLOSE…); the
    /// main window runs it through `MenuActions.performPending` like the menu item.
    public var pendingMenuAction: String?
    /// Kotlin `pendingSettingsTab` (MSGS, WKEY, NETCONFIG, the action FUNCTION_KEYS_SETUP): the Settings tab
    /// selected after the pending menu action ran (`applyPendingSettingsTab`).
    public var pendingSettingsTab: String?

    /// Top-level nodes.
    public private(set) var tree: [MenuNode] = []
    public private(set) var source: MenuConfigStore.Source = .builtIn
    /// Kotlin `menuRevision`: 0 at start-up, raised by „Načíst menu znovu"; the menu bar is rebuilt on a change.
    public private(set) var revision: Int = 0
    /// The start-up dialog about a broken `menu.json` (Kotlin `menuLoadError`, only for revision 0).
    public var loadError: String?

    @ObservationIgnored private let language: LanguageModel
    @ObservationIgnored private let status: StatusModel
    @ObservationIgnored private let contest: ContestModel
    @ObservationIgnored private let dataDir: URL
    /// The user's key remapping (`config.keyBindings`); read while the entries are built, so a change of the
    /// bindings rebuilds the shown keys.
    @ObservationIgnored public var keyBindingsSource: (@MainActor () -> [String: String]?)?

    init(language: LanguageModel, status: StatusModel, contest: ContestModel, dataDir: URL) {
        self.language = language
        self.status = status
        self.contest = contest
        self.dataDir = dataDir
    }

    /// Loads `<dataDir>/menu.json` (or the built-in menu) off the main thread. A broken user file is reported in the
    /// status line and, at start-up, by a dialog.
    public func load() async {
        let dir: URL = dataDir
        let result: MenuConfigStore.LoadResult? = try? await BlockingQueue.run {
            MenuConfigStore.loadFrom(dataDir: dir)
        }
        guard let loaded = result else {
            // The blocking queue never fails here (`loadFrom` does not throw); keep the menu from code.
            tree = DefaultMenu.tree().menu
            source = .builtIn
            return
        }
        tree = loaded.menu.menu
        source = loaded.source
        if loaded.source == .userInvalid {
            let reason: ContestMessage = loaded.error.map { .verbatim($0) } ?? ContestMessage("vadný menu.json")
            status.showJoined([.verbatim("Menu: "), reason, ContestMessage(" Platí vestavěné menu.")], separator: "")
            if revision == 0 {
                loadError = loaded.error ?? "Vadný menu.json."
            }
        }
    }

    /// „Načíst menu znovu": a new revision, then the file is read again.
    public func reload() async {
        revision += 1
        await load()
    }

    /// `tr(node.label ?: DefaultMenu.labelFor(id) ?: id)`.
    public func label(_ node: MenuNode) -> String {
        language.tr(node.label ?? DefaultMenu.labelFor(node.id) ?? node.id)
    }

    /// Kotlin `runtimeEnabled(id, state)`.
    public func runtimeEnabled(_ id: String) -> Bool {
        switch id {
        case "contest.new", "contest.none":
            return contest.engineAvailable
        case "settings.exportCabrillo", "settings.exportEdi", "contest.rescore", "contest.updateCallHistory":
            return contest.isActive
        default:
            return true
        }
    }

    /// The key an item shows next to its label (`Ctrl+W`), or `nil` (no key, or not a shortcut item).
    public func shortcutHint(_ id: String) -> String? {
        guard let action = Self.shortcutActions[id] else { return nil }
        return KeyBindings(keyBindingsSource?()).comboFor(action)?.format()
    }

    public func isSeparator(_ node: MenuNode) -> Bool {
        node.id.hasPrefix(Self.separatorPrefix) && node.children.isEmpty
    }

    public func isImplemented(_ id: String) -> Bool {
        Self.implementedActions.contains(id)
    }

    /// Children shown as menu entries (`tab.*` nodes are Settings tabs).
    public func menuChildren(_ node: MenuNode) -> [MenuNode] {
        node.children.filter { !$0.id.hasPrefix(Self.tabPrefix) }
    }

    /// A node rendered as an item: no children, or only `tab.*` children (the Settings host).
    public func isItem(_ node: MenuNode) -> Bool {
        menuChildren(node).isEmpty
    }

    /// Kotlin `node.state == ENABLE && runtimeEnabled(id)`; an item must also be implemented.
    public func isEnabled(_ node: MenuNode) -> Bool {
        guard node.state == .enable, runtimeEnabled(node.id) else { return false }
        return !isItem(node) || isImplemented(node.id)
    }

    /// Kotlin `Menu(enabled = false)` disables the whole submenu: a node is effectively enabled only when every
    /// menu above it is (`state == ENABLE && runtimeEnabled`) and the node itself is.
    public func isEnabled(_ node: MenuNode, ancestors: [MenuNode]) -> Bool {
        ancestors.allSatisfy { $0.state == .enable && runtimeEnabled($0.id) } && isEnabled(node)
    }

    /// The tooltip of an item that is shown but not implemented yet.
    public func unavailableHint(_ node: MenuNode) -> String? {
        isItem(node) && !isImplemented(node.id) ? language.tr("Zatím nedostupné") : nil
    }
}

/// One rendered node of the menu bar (Kotlin `topLevelMenu` / `renderMenuNode`): the title in the current language,
/// whether it is enabled when built, the „Zatím nedostupné" hint and the visible children.
public struct MenuEntry: Equatable, Sendable {
    public let node: MenuNode
    /// The menus above the node, outermost first (their state disables the node too).
    public let ancestors: [MenuNode]
    public let title: String
    public let enabled: Bool
    /// The tooltip of an item that is not implemented yet.
    public let toolTip: String?
    /// A leaf the user can choose (also the Settings host whose children are only `tab.*` nodes).
    public let isItem: Bool
    public let children: [MenuEntry]
    /// The user's key of an Edit or Help item, shown right-aligned (not a key equivalent).
    public var shortcut: String? = nil
    /// A separator line (`sep.*` nodes); the other fields mean nothing.
    public var isSeparator: Bool = false

    public var id: String {
        node.id
    }
}

extension MenuModel {

    /// The menu bar as Kotlin renders it: hidden nodes are left out, a top-level node is always a menu, a nested node
    /// with menu children is a submenu and every other node is an item. Reads the tree and the language, so an
    /// observer rebuilds the `NSMenu` after a reload or a language switch.
    public func entries() -> [MenuEntry] {
        tree.compactMap { node in
            guard node.state != .hidden else { return nil }
            return MenuEntry(node: node, ancestors: [], title: label(node),
                             enabled: node.state == .enable && runtimeEnabled(node.id), toolTip: nil, isItem: false,
                             children: childEntries(node, ancestors: [node]))
        }
    }

    private func childEntries(_ node: MenuNode, ancestors: [MenuNode]) -> [MenuEntry] {
        menuChildren(node).compactMap { child in
            guard child.state != .hidden else { return nil }
            if isSeparator(child) {
                return MenuEntry(node: child, ancestors: ancestors, title: "", enabled: false, toolTip: nil,
                                 isItem: false, children: [], isSeparator: true)
            }
            let item: Bool = isItem(child)
            return MenuEntry(node: child, ancestors: ancestors, title: label(child),
                             enabled: isEnabled(child, ancestors: ancestors), toolTip: unavailableHint(child),
                             isItem: item, children: item ? [] : childEntries(child, ancestors: ancestors + [child]),
                             shortcut: item ? shortcutHint(child.id) : nil)
        }
    }
}

/// The structure of a menu bar (node ids, items and submenus), without titles and states: when it is unchanged, the
/// `NSMenu` is updated in place instead of rebuilt, so an open menu is not torn down by a language switch or a
/// contest state change.
public struct MenuShape: Equatable, Sendable {
    private let ids: [String]

    public init(_ entries: [MenuEntry]) {
        var ids: [String] = []
        Self.collect(entries, depth: 0, into: &ids)
        self.ids = ids
    }

    private static func collect(_ entries: [MenuEntry], depth: Int, into ids: inout [String]) {
        for entry in entries {
            ids.append(String(depth) + (entry.isSeparator ? ":sep:" : entry.isItem ? ":item:" : ":menu:") + entry.id)
            collect(entry.children, depth: depth + 1, into: &ids)
        }
        ids.append(String(depth) + ":end")
    }
}
