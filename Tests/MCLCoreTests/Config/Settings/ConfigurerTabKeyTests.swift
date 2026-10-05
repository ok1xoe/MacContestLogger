import Testing
@testable import MCLCore

/// `src/test/kotlin/…/ui/configurer/ConfigurerTabKeyTest.kt` — the same four methods.
@Suite struct ConfigurerTabKeyTests {

    @Test func allKeysResolveBackToTab() {
        for tab in ConfigurerTab.allCases {
            #expect(ConfigurerTab.byKey(tab.key) == tab)
        }
    }

    @Test func unknownKeyIsNull() {
        #expect(ConfigurerTab.byKey("nope") == nil)
    }

    @Test func keysAreKebab() {
        #expect(ConfigurerTab.functionKeys.key == "function-keys")
        #expect(ConfigurerTab.wsjt.key == "wsjt")
        #expect(ConfigurerTab.scoreReporting.key == "score-reporting")
    }

    /// The name is kept from Kotlin so that the two test sets pair up; the Kotlin test asserts 20 tabs too.
    @Test func nineteenTabs() {
        #expect(ConfigurerTab.allCases.count == 20)
    }
}
