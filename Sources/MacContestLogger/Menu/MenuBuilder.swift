import AppKit
import MCLAppModel
import MCLCore
import Observation

/// The menu bar from `menu.json` (Kotlin `MenuBar { topLevelMenu(…) }`, `KApp:543-608`): an `NSMenu`
/// per top-level node, inserted right after the application menu and before SwiftUI's standard menus (Edit, View,
/// Help).
///
/// - Follows `MenuModel.entries()`: a reload of `menu.json` (`revision`), a language switch, the contest
///   state. When the structure is unchanged (`MenuShape`) titles, tooltips and states are updated in place, so an
///   open menu stays open; otherwise the menus are rebuilt.
/// - Items are enabled through `NSMenuItemValidation`: `MenuModel.isEnabled(_:ancestors:)` = state ∧ `runtimeEnabled`
///   ∧ implemented, and every menu above enabled (Kotlin `Menu(enabled = false)` disables its whole submenu).:
///   unimplemented items carry the „Zatím nedostupné" tooltip. Submenu items take their state when built, on an
///   update and before their menu opens.
/// - One Window menu: SwiftUI's own Window menu is removed and `NSApp.windowsMenu` points at the menu of the
///   `menu.json` node `window` (AppKit adds the open windows there), or at nothing when `menu.json` has none.
/// - „Dodatečné zadání" (`contest.postcontest`) carries a ✓ while POSTCONTEST is on (set when validated).
/// - No key equivalents on `menu.json` items. The only one added is the standard Settings ⌘, in the application
///   menu; it opens the Settings window.
/// - SwiftUI owns the main menu and may rebuild it; every change of the main menu, the application menu or the
///   windows menu is followed by a check that puts these items back.
@MainActor
final class MenuBuilder: NSObject, NSMenuItemValidation, NSMenuDelegate {

    private let app: AppModel
    private var installed: [NSMenuItem] = []
    private var shape: MenuShape?
    /// The built items by node path, for updates in place.
    private var itemsByPath: [String: NSMenuItem] = [:]
    private var settingsItem: NSMenuItem?
    private var settingsSeparator: NSMenuItem?
    private var observers: [NSObjectProtocol] = []
    private var observations: [NSKeyValueObservation] = []
    private var checkScheduled = false
    /// Window → Custom: the windows of the window plugins, filled each time the menu opens.
    private var customItem: NSMenuItem?
    private var customSeparator: NSMenuItem?

    init(app: AppModel) {
        self.app = app
    }

    func start() {
        update()
        let center = NotificationCenter.default
        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let menu: ObjectIdentifier? = (note.object as? NSMenu).map { ObjectIdentifier($0) }
                MainActor.assumeIsolated {
                    self?.menuChanged(menu)
                }
            })
        }
        observations.append(NSApp.observe(\.mainMenu, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.scheduleCheck()
                }
            }
        })
        // SwiftUI fills its menus lazily and without item notifications; a cheap, coalesced check after event
        // processing catches that too.
        observers.append(center.addObserver(forName: NSApplication.didUpdateNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleCheck()
            }
        })
        observations.append(NSApp.observe(\.windowsMenu, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.scheduleCheck()
                }
            }
        })
    }

    // MARK: - building

    /// Reads the model's entries (tracking what they read, so a change comes back here) and rebuilds the menus or
    /// updates them in place.
    private func update() {
        let entries: [MenuEntry] = withObservationTracking {
            app.menu.entries()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.update()
                }
            }
        }
        let newShape = MenuShape(entries)
        if newShape == shape {
            for entry in entries {
                refresh(entry, path: "")
            }
            settingsItem?.title = app.language.tr("Nastavení…")
            customItem?.title = app.language.tr("Vlastní")
            customItem?.submenu?.title = app.language.tr("Vlastní")
            return
        }
        shape = newShape
        removeInstalled()
        itemsByPath = [:]
        installed = entries.map { makeItem($0, path: "") }
        settingsItem = makeSettingsItem()
        settingsSeparator = NSMenuItem.separator()
        install()
    }

    private func makeItem(_ entry: MenuEntry, path: String) -> NSMenuItem {
        let itemPath: String = path + "/" + entry.id
        let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        item.representedObject = NodeBox(entry)
        item.toolTip = entry.toolTip
        itemsByPath[itemPath] = item
        if entry.isItem {
            item.action = #selector(choose(_:))
            item.target = self
            return item
        }
        let submenu = NSMenu(title: entry.title)
        submenu.delegate = self
        for child in entry.children {
            submenu.addItem(makeItem(child, path: itemPath))
        }
        if path.isEmpty && entry.id == "window" {
            addCustomMenu(to: submenu)
        }
        item.submenu = submenu
        item.isEnabled = entry.enabled
        return item
    }

    /// Same structure: new titles, tooltips, nodes and states.
    private func refresh(_ entry: MenuEntry, path: String) {
        let itemPath: String = path + "/" + entry.id
        guard let item = itemsByPath[itemPath] else { return }
        if item.title != entry.title {
            item.title = entry.title
            item.submenu?.title = entry.title
        }
        if item.toolTip != entry.toolTip {
            item.toolTip = entry.toolTip
        }
        item.representedObject = NodeBox(entry)
        if item.submenu != nil, item.isEnabled != entry.enabled {
            item.isEnabled = entry.enabled
        }
        for child in entry.children {
            refresh(child, path: itemPath)
        }
    }

    /// Window → Custom (after a separator): one item per window of every window plugin, rebuilt when the menu opens
    /// (the plugins directory is read again in the background, so a new plugin shows the next time).
    private func addCustomMenu(to menu: NSMenu) {
        let separator = NSMenuItem.separator()
        let item = NSMenuItem(title: app.language.tr("Vlastní"), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: app.language.tr("Vlastní"))
        submenu.delegate = self
        item.submenu = submenu
        menu.addItem(separator)
        menu.addItem(item)
        customSeparator = separator
        customItem = item
        fillCustomMenu(submenu)
    }

    private func fillCustomMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = app.pluginWindows.menuWindows
        guard !windows.isEmpty else {
            let empty = NSMenuItem(title: app.language.tr("Žádné pluginy s okny"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for window in windows {
            let item = NSMenuItem(title: window.title, action: #selector(openPluginWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = window.key as NSString
            menu.addItem(item)
        }
    }

    @objc private func openPluginWindow(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? NSString else { return }
        app.pluginWindows.open(key as String)
    }

    /// The standard „Nastavení…" ⌘, of the application menu: opens the Settings window (the menu action
    /// `settings.open` without a tab; Kotlin has no such item, the menu.json entry stays as it is).
    private func makeSettingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: app.language.tr("Nastavení…"), action: #selector(openSettings(_:)),
                              keyEquivalent: ",")
        item.target = self
        return item
    }

    // MARK: - installing into SwiftUI's main menu

    private func removeInstalled() {
        for item in installed + [settingsItem, settingsSeparator].compactMap({ $0 }) {
            item.menu?.removeItem(item)
        }
    }

    /// The submenu of the `menu.json` node `window` (it becomes the app's Window menu).
    private var windowSubmenu: NSMenu? {
        installed.first { ($0.representedObject as? NodeBox)?.node.id == "window" }?.submenu
    }

    /// Puts the items at their places when they are missing (SwiftUI rebuilt the main menu) or out of order, and
    /// keeps a single Window menu.
    private func install() {
        guard let main = NSApp.mainMenu, main.numberOfItems > 0 else { return }
        let inPlace: Bool = installed.enumerated().allSatisfy { offset, item in
            item.menu === main && main.index(of: item) == offset + 1
        }
        if !inPlace {
            for item in installed where item.menu != nil {
                item.menu?.removeItem(item)
            }
            for (offset, item) in installed.enumerated() {
                main.insertItem(item, at: min(offset + 1, main.numberOfItems))
            }
        }
        installSettings(in: main)
        keepOneWindowMenu(in: main)
    }

    /// About, separator, Settings ⌘,, separator, Services — the macOS order.
    private func installSettings(in main: NSMenu) {
        guard let settingsItem, let separator = settingsSeparator,
              let appMenu = main.item(at: 0)?.submenu else { return }
        guard settingsItem.menu !== appMenu || separator.menu !== appMenu else { return }
        settingsItem.menu?.removeItem(settingsItem)
        separator.menu?.removeItem(separator)
        let index: Int = appMenu.numberOfItems >= 2 ? 2 : appMenu.numberOfItems
        appMenu.insertItem(settingsItem, at: index)
        appMenu.insertItem(separator, at: index + 1)
    }

    /// Hides SwiftUI's Window menu and makes menu.json's `window` menu the windows menu (one Window
    /// menu; AppKit adds its window items there). The standard Minimize ⌘M and Close ⌘W (there is no File menu) are
    /// at the top of menu.json's menu, titled from the system's localization. SwiftUI's menu is the windows menu
    /// when that is not ours, or is recognised by its title or its standard window items. Without a `window` node in
    /// menu.json SwiftUI's menu stays the only Window menu.
    private func keepOneWindowMenu(in main: NSMenu) {
        guard let target = windowSubmenu else {
            return
        }
        let ours: Set<ObjectIdentifier> = Set(installed.compactMap { $0.submenu }.map { ObjectIdentifier($0) })
        let system: NSMenu? = NSApp.windowsMenu.flatMap { ours.contains(ObjectIdentifier($0)) ? nil : $0 }
        for (index, item) in main.items.enumerated() where index > 0 && !item.isHidden {
            guard let submenu = item.submenu, !ours.contains(ObjectIdentifier(submenu)) else { continue }
            if submenu === system || Self.isStandardWindowMenu(submenu) {
                // Hidden, not removed: SwiftUI puts a removed menu straight back (measured), a hidden one stays.
                item.isHidden = true
            }
        }
        placeSystemItems(in: target)
        if NSApp.windowsMenu !== target {
            NSApp.windowsMenu = target
        }
    }

    /// Minimize ⌘M, Close ⌘W and a separator, kept across rebuilds of menu.json's menus.
    private lazy var systemWindowItems: [NSMenuItem] = [
        NSMenuItem(title: Self.systemTitle("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)),
                   keyEquivalent: "m"),
        NSMenuItem(title: Self.systemTitle("Close"), action: #selector(NSWindow.performClose(_:)),
                   keyEquivalent: "w"),
        NSMenuItem.separator(),
    ]

    private static let swiftUIBundle: Bundle? = Bundle(path: "/System/Library/Frameworks/SwiftUI.framework")

    /// SwiftUI's title of its Window menu in the current localization; its menu is still empty right after launch
    /// (filled when it first shows), so the actions alone do not recognise it yet.
    private static let swiftUIWindowTitle: String? = {
        guard let bundle = swiftUIBundle else { return nil }
        let title: String = bundle.localizedString(forKey: "Window", value: "", table: "MainMenu")
        return title.isEmpty ? nil : title
    }()

    /// A standard menu title in the system's localization (SwiftUI's `MainMenu` table), English otherwise.
    private static func systemTitle(_ key: String) -> String {
        swiftUIBundle?.localizedString(forKey: key, value: key, table: "MainMenu") ?? key
    }

    private static let windowActions: Set<Selector> = [
        #selector(NSWindow.performMiniaturize(_:)), #selector(NSWindow.performClose(_:)),
        #selector(NSWindow.performZoom(_:)), #selector(NSApplication.arrangeInFront(_:)),
        #selector(NSApplication.miniaturizeAll(_:)),
    ]

    private func placeSystemItems(in menu: NSMenu) {
        // Only when missing: AppKit inserts its own window items around them, which is fine.
        guard !systemWindowItems.allSatisfy({ $0.menu === menu }) else { return }
        for item in systemWindowItems {
            item.menu?.removeItem(item)
        }
        for (offset, item) in systemWindowItems.enumerated() {
            menu.insertItem(item, at: offset)
        }
    }

    private static func isStandardWindowMenu(_ menu: NSMenu) -> Bool {
        if menu.numberOfItems == 0, let title = swiftUIWindowTitle, menu.title == title {
            return true
        }
        return menu.items.contains { item in
            item.action.map { windowActions.contains($0) } ?? false
        }
    }

    /// A change of the main menu or of one of its menus (SwiftUI fills its Window menu after inserting it).
    private func menuChanged(_ menu: ObjectIdentifier?) {
        guard let menu, let main = NSApp.mainMenu else { return }
        if menu == ObjectIdentifier(main) {
            scheduleCheck()
            return
        }
        let ours: Set<ObjectIdentifier> = Set(installed.compactMap { $0.submenu }.map { ObjectIdentifier($0) })
        let others: [ObjectIdentifier] = main.items.compactMap { $0.submenu }.map { ObjectIdentifier($0) }
        if others.contains(menu) && !ours.contains(menu) {
            scheduleCheck()
        }
    }

    /// Coalesces the checks of one run-loop turn (the own changes notify too).
    private func scheduleCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.checkScheduled = false
                self.install()
            }
        }
    }

    // MARK: - actions and validation

    @objc private func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? NodeBox else { return }
        if let request = MenuActions.perform(box.node.id, app: app) {
            ExportPanels.run(request, app: app)
        }
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        app.settings.open()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === settingsItem {
            return true
        }
        if menuItem.action == #selector(openPluginWindow(_:)) {
            return true
        }
        guard let box = menuItem.representedObject as? NodeBox else { return false }
        // The POSTCONTEST toggle shows its state.
        let checked: NSControl.StateValue = MenuActions.isChecked(box.node.id, app: app) ? .on : .off
        if menuItem.state != checked {
            menuItem.state = checked
        }
        return app.menu.isEnabled(box.node, ancestors: box.ancestors)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === customItem?.submenu {
            fillCustomMenu(menu)
            return
        }
        if menu === customItem?.menu {
            // The Window menu opens: read the plugins directory again for the Custom submenu.
            app.pluginWindows.refreshCatalog()
            customItem?.isEnabled = true
        }
        for item in menu.items where item.submenu != nil {
            if let box = item.representedObject as? NodeBox {
                item.isEnabled = app.menu.isEnabled(box.node, ancestors: box.ancestors)
            }
        }
    }
}

/// The menu node of an `NSMenuItem` (`representedObject`) with the menus above it.
private final class NodeBox: NSObject {
    let node: MenuNode
    let ancestors: [MenuNode]

    init(_ entry: MenuEntry) {
        self.node = entry.node
        self.ancestors = entry.ancestors
    }
}
