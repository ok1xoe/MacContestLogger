import Testing
@testable import MCLCore

/// `KeyCaptureRules` against `KT:46-109` (`ui/configurer/KeysTab.kt` of v1.1.1).
@Suite struct KeyCaptureRulesTests {

    private static func combo(_ text: String) throws -> KeyCombo {
        try #require(KeyCombo.parse(text))
    }

    @Test func defaultRowsCoverEveryActionInJavaOrder() {
        let rows: [KeyCaptureRules.Row] = KeyCaptureRules.rows(overrides: [:])
        #expect(rows.map(\.action) == ShortcutAction.allCases)
        #expect(rows[0].keys == "SEMICOLON")
        #expect(rows[1].keys == "QUOTE")
        #expect(rows[2].keys == "Alt+ENTER")
        #expect(rows.allSatisfy { !$0.isCustom })
    }

    @Test func noneShowsDashAndBold() {
        var overrides: [String: String] = [:]
        KeyCaptureRules.setNone(.wipe, in: &overrides)
        #expect(overrides == ["wipe": ""])
        let row = KeyCaptureRules.rows(overrides: overrides).first { $0.action == .wipe }
        #expect(row?.keys == "—")
        #expect(row?.isCustom == true)
        #expect(row?.conflictText == nil)
    }

    @Test func conflictRowsAndText() {
        let rows: [KeyCaptureRules.Row] = KeyCaptureRules.rows(overrides: ["tu_log": ";"])
        let send = rows.first { $0.action == .sendCallExchange }
        let tu = rows.first { $0.action == .tuAndLog }
        #expect(send?.isCustom == false)
        #expect(send?.conflicts == [.tuAndLog])
        #expect(send?.conflictText == "koliduje: TU a zapsat (F3)")
        #expect(tu?.isCustom == true)
        #expect(tu?.keys == "SEMICOLON")
        #expect(tu?.conflictText == "koliduje: Jeho volačka + výměna (F5+F2)")
    }

    @Test func capture() throws {
        #expect(KeyCaptureRules.capture(try Self.combo("Ctrl+Alt+S")) == .accepted("Ctrl+Alt+S"))
        #expect(KeyCaptureRules.capture(try Self.combo("F7")) == .accepted("F7"))
        #expect(KeyCaptureRules.capture(try Self.combo(";")) == .accepted("SEMICOLON"))
        #expect(KeyCaptureRules.capture(try Self.combo("Shift+A")) == .rejected(hintKey: SettingsTexts.keyNotAllowed, args: ["Shift+A"]))
        #expect(KeyCaptureRules.capture(try Self.combo("A")) == .rejected(hintKey: SettingsTexts.keyNotAllowed, args: ["A"]))
        let shift = KeyCombo(ctrl: false, alt: false, shift: true, meta: false, keyCode: AwtKeyCodes.vkShift)
        #expect(KeyCaptureRules.capture(shift) == .ignored)
        let ctrl = KeyCombo(ctrl: true, alt: false, shift: false, meta: false, keyCode: AwtKeyCodes.vkControl)
        #expect(KeyCaptureRules.capture(ctrl) == .ignored)
        #expect(KeyCaptureRules.capture(try Self.combo("ESCAPE")) == .cancelled)
        #expect(KeyCaptureRules.capture(try Self.combo("Ctrl+ESCAPE")) == .cancelled)
    }

    @Test func assignDefaultAndResetAll() {
        var overrides: [String: String] = ["wipe": ""]
        KeyCaptureRules.assign("Ctrl+Alt+S", to: .tuAndLog, in: &overrides)
        #expect(overrides == ["wipe": "", "tu_log": "Ctrl+Alt+S"])
        #expect(KeyCaptureRules.isCustom(.tuAndLog, overrides: overrides))
        KeyCaptureRules.resetToDefault(.tuAndLog, in: &overrides)
        #expect(overrides == ["wipe": ""])
        #expect(!KeyCaptureRules.isCustom(.tuAndLog, overrides: overrides))
        KeyCaptureRules.resetToDefault(.tuAndLog, in: &overrides)
        #expect(overrides == ["wipe": ""])
        KeyCaptureRules.resetAll(&overrides)
        #expect(overrides.isEmpty)
    }

}
