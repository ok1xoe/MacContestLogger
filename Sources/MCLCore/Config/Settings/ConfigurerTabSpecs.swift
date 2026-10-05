/// Tab specs of the Settings window from `menu.json` — `buildTabSpecs`/`findTabHost` (`app/App.kt:580-610`), the
/// initial selection of `AppState.openConfigurer` (`ui/AppState.kt:2705-2710`) and the deep link of
/// `applyPendingSettingsTab` (`ui/AppState.kt:1817-1821`).
public enum ConfigurerTabSpecs {

    static let tabIdPrefix = "tab."

    /// `buildTabSpecs(cfg)`: without a tab host all 20 tabs are enabled with their `title` (Kotlin `tab.title`, so
    /// only the four `tr` titles are translated). With a host its children are walked depth-first: a hidden node is
    /// skipped (with its children), a node whose id names a tab gives a spec (its own children are ignored —
    /// `online_logs` → HamQTH/QRZ), any other node with children is a group that is walked, and a childless node
    /// with an unknown id is dropped. Label = `tr(node.label ?: DefaultMenu.labelFor(id) ?: tab.title)`.
    public static func build(menu: MenuConfig) -> [ConfigurerTabSpec] {
        guard let host = findTabHost(menu.menu) else {
            return ConfigurerTab.allCases.map { tab in
                ConfigurerTabSpec(
                    tab: tab, labelKey: tab.titleKey, isLabelTranslated: tab.isTitleTranslated, state: .enable)
            }
        }
        var out: [ConfigurerTabSpec] = []
        collect(host.children, into: &out)
        return out
    }

    /// `findTabHost`: the first node (depth-first, pre-order) that has children and all of them are `tab.*`.
    static func findTabHost(_ nodes: [MenuNode]) -> MenuNode? {
        for node in nodes {
            if !node.children.isEmpty && node.children.allSatisfy({ isTabId($0.id) }) {
                return node
            }
            if let found = findTabHost(node.children) {
                return found
            }
        }
        return nil
    }

    private static func collect(_ nodes: [MenuNode], into out: inout [ConfigurerTabSpec]) {
        for node in nodes {
            if node.state == .hidden { continue }
            if let tab = ConfigurerTab.byKey(removeTabPrefix(node.id)) {
                let label: String = node.label ?? DefaultMenu.labelFor(node.id) ?? tab.titleKey
                out.append(ConfigurerTabSpec(tab: tab, labelKey: label, isLabelTranslated: true, state: node.state))
            } else if !node.children.isEmpty {
                collect(node.children, into: &out)
            }
        }
    }

    /// Kotlin `startsWith("tab.")` (by UTF-16 units, so a combining mark after the dot does not hide the prefix).
    static func isTabId(_ id: String) -> Bool {
        id.utf16.starts(with: tabIdPrefix.utf16)
    }

    /// Kotlin `removePrefix("tab.")`.
    static func removeTabPrefix(_ id: String) -> String {
        guard isTabId(id) else { return id }
        return String(id.unicodeScalars.dropFirst(tabIdPrefix.unicodeScalars.count))
    }

    /// Selection when the window opens (`openConfigurer`): the first enabled tab, else the first tab, else Hardware.
    public static func firstEnabled(_ specs: [ConfigurerTabSpec]) -> ConfigurerTab {
        if let enabled = specs.first(where: { $0.state == .enable }) {
            return enabled.tab
        }
        return specs.first?.tab ?? .hardware
    }

    /// Deep link (`applyPendingSettingsTab`): the first visible tab with the key — a disabled one too (Kotlin).
    public static func deepLink(_ specs: [ConfigurerTabSpec], key: String) -> ConfigurerTab? {
        specs.first { $0.tab.key == key }?.tab
    }
}
