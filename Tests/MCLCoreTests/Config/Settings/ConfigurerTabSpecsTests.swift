import Testing
@testable import MCLCore

/// `buildTabSpecs`/`findTabHost` (`app/App.kt:580-610`), `openConfigurer` (`ui/AppState.kt:2705-2710`) and
/// `applyPendingSettingsTab` (`ui/AppState.kt:1817-1821`), read from the source.
@Suite struct ConfigurerTabSpecsTests {

    private func leaf(_ id: String, _ state: MenuState = .enable, label: String? = nil) -> MenuNode {
        MenuNode(id: id, label: label, state: state, children: [])
    }

    private func menu(_ hostChildren: [MenuNode]) -> MenuConfig {
        var cfg = MenuConfig()
        cfg.menu = [MenuNode(id: "settings", children: [MenuNode(id: "settings.open", children: hostChildren)])]
        return cfg
    }

    @Test func builtInMenuGivesAllTwentyTabsInOrder() {
        let specs = ConfigurerTabSpecs.build(menu: MenuConfigStore.builtIn())
        #expect(specs.map(\.tab) == ConfigurerTab.allCases)
        #expect(specs.allSatisfy { $0.state == .enable && $0.isLabelTranslated })
        // The labels of menu.json; `online_logs` is a tab, its HamQTH/QRZ children are ignored.
        #expect(specs.first { $0.tab == .onlineCallbooks }?.labelKey == "Online callbooks")
        #expect(specs.first { $0.tab == .winkey }?.labelKey == "CW klíč")
        #expect(specs.first { $0.tab == .broadcast }?.labelKey == "Broadcast Data")
    }

    @Test func defaultTreeWithoutLabelsUsesDefaultMenuLabels() {
        let specs = ConfigurerTabSpecs.build(menu: DefaultMenu.tree())
        #expect(specs.count == 20)
        for spec in specs {
            #expect(spec.labelKey == DefaultMenu.labelFor("tab." + spec.tab.key))
        }
    }

    @Test func ownLabelWins() {
        let specs = ConfigurerTabSpecs.build(menu: menu([leaf("tab.map", label: "Moje mapa"), leaf("tab.keys")]))
        #expect(specs.map(\.labelKey) == ["Moje mapa", "Klávesy"])
    }

    @Test func hiddenTabIsSkippedDisabledTabStays() {
        let specs = ConfigurerTabSpecs.build(menu: menu([
            leaf("tab.hardware", .hidden), leaf("tab.keys", .disable), leaf("tab.station"),
        ]))
        #expect(specs.map(\.tab) == [.keys, .station])
        #expect(specs.map(\.state) == [.disable, .enable])
    }

    @Test func nestedGroupIsWalkedHiddenGroupIsNot() {
        let group = MenuNode(id: "tab.group", children: [leaf("tab.station"), leaf("tab.map", .hidden), leaf("tab.cluster")])
        let hiddenGroup = MenuNode(id: "tab.more", state: .hidden, children: [leaf("tab.audio")])
        let specs = ConfigurerTabSpecs.build(menu: menu([leaf("tab.hardware"), group, hiddenGroup, leaf("tab.wsjt")]))
        #expect(specs.map(\.tab) == [.hardware, .station, .cluster, .wsjt])
    }

    /// A `tab.*` id that names no tab and has no children (Kotlin: neither a tab nor a container) is dropped.
    @Test func unknownTabWithoutChildrenIsDropped() {
        let specs = ConfigurerTabSpecs.build(menu: menu([leaf("tab.x"), leaf("tab.map")]))
        #expect(specs.map(\.tab) == [.map])
    }

    /// Without a node whose children are all `tab.*` every tab is enabled with its own title; only the four
    /// Kotlin `tr` titles are translated.
    @Test func menuWithoutHostGivesAllTabsEnabled() {
        var cfg = MenuConfig()
        cfg.menu = [MenuNode(id: "settings", children: [leaf("settings.open"), leaf("tab.map")])]
        let specs = ConfigurerTabSpecs.build(menu: cfg)
        #expect(specs.map(\.tab) == ConfigurerTab.allCases)
        #expect(specs.allSatisfy { $0.state == .enable && $0.labelKey == $0.tab.titleKey })
        #expect(specs.filter(\.isLabelTranslated).map(\.tab) == [.keys, .winkey, .contest, .bandplan])
    }

    /// `findTabHost` checks a node before its children and stops at the first match (pre-order, depth-first).
    @Test func firstHostDepthFirstWins() {
        var cfg = MenuConfig()
        cfg.menu = [
            MenuNode(id: "a", children: [MenuNode(id: "b", children: [leaf("tab.map")]), leaf("x")]),
            MenuNode(id: "c", children: [leaf("tab.keys")]),
        ]
        #expect(ConfigurerTabSpecs.build(menu: cfg).map(\.tab) == [.map])
        #expect(ConfigurerTabSpecs.findTabHost(cfg.menu)?.id == "b")
    }

    @Test func firstEnabledFallsBackToFirstThenHardware() {
        let specs = ConfigurerTabSpecs.build(menu: menu([leaf("tab.keys", .disable), leaf("tab.map")]))
        #expect(ConfigurerTabSpecs.firstEnabled(specs) == .map)
        let disabled = ConfigurerTabSpecs.build(menu: menu([leaf("tab.keys", .disable), leaf("tab.map", .disable)]))
        #expect(ConfigurerTabSpecs.firstEnabled(disabled) == .keys)
        #expect(ConfigurerTabSpecs.firstEnabled([]) == .hardware)
    }

    /// The deep link selects a disabled tab too; a hidden one is not among the specs.
    @Test func deepLinkSelectsDisabledButNotHidden() {
        let specs = ConfigurerTabSpecs.build(menu: menu([
            leaf("tab.keys", .disable), leaf("tab.map"), leaf("tab.winkey", .hidden),
        ]))
        #expect(ConfigurerTabSpecs.deepLink(specs, key: "keys") == .keys)
        #expect(ConfigurerTabSpecs.deepLink(specs, key: "winkey") == nil)
        #expect(ConfigurerTabSpecs.deepLink(specs, key: "nope") == nil)
    }
}
