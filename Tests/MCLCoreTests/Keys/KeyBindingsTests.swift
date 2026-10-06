import Testing
@testable import MCLCore

/// Port of `keys/KeyBindingsTest` (6).
@Suite struct KeyBindingsTests {

    private static func combo(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> KeyCombo {
        try #require(KeyCombo.parse(text), sourceLocation: sourceLocation)
    }

    @Test func parseAndFormatRoundTrip() throws {
        let c = try Self.combo("ctrl+alt+s")
        #expect(c == KeyCombo(ctrl: true, alt: true, shift: false, meta: false, keyCode: 83))
        #expect(c.format() == "Ctrl+Alt+S")
        #expect(try Self.combo("Ctrl+PgUp").keyCode == 33)
        #expect(try Self.combo("Cmd+Down").format() == "Cmd+DOWN")
        #expect(try Self.combo(";").keyCode == 59)
        #expect(try Self.combo("Option+F7").keyCode == 118)
        #expect(KeyCombo.parse("Ctrl+Nonsense") == nil)
        #expect(KeyCombo.parse("Ctrl+") == nil)
    }

    @Test func plainLettersAreNotAllowedAsShortcuts() throws {
        #expect(try !Self.combo("A").isAllowedShortcut, "it would override typing")
        #expect(try !Self.combo("Shift+A").isAllowedShortcut)
        #expect(try Self.combo("F9").isAllowedShortcut)
        #expect(try Self.combo(";").isAllowedShortcut)
        #expect(try Self.combo("Cmd+A").isAllowedShortcut)
    }

    @Test func allDefaultsAreValidAndUnique() {
        let b = KeyBindings(nil)
        for a in ShortcutAction.allCases {
            #expect(a.defaultCombo().isAllowedShortcut, "\(a.name)")
            #expect(b.resolve(a.defaultCombo()) == a, "\(a.name) the default key collides")
        }
    }

    @Test func remapMovesTheShortcut() throws {
        // The spot jumps default to Cmd+↓/↑ (Ctrl+arrows belong to Mission Control); a user can still remap them.
        let defaults = KeyBindings(nil)
        #expect(defaults.resolve(try Self.combo("Cmd+Down")) == .nextSpotUp)
        #expect(defaults.resolve(try Self.combo("Cmd+Up")) == .nextSpotDown)
        #expect(defaults.resolve(try Self.combo("Ctrl+Down")) == nil)

        let b = KeyBindings([ShortcutAction.nextSpotUp.id: "Ctrl+Down"])
        #expect(b.resolve(try Self.combo("Ctrl+Down")) == .nextSpotUp, "an existing override keeps working")
        #expect(b.resolve(try Self.combo("Cmd+Down")) == nil, "the new default is free once remapped")
        #expect(b.resolve(try Self.combo("Cmd+Up")) == .nextSpotDown)
    }

    @Test func emptyOverrideRemovesShortcutAndInvalidKeepsDefault() {
        let b = KeyBindings([ShortcutAction.tune.id: "", ShortcutAction.help.id: "Q"])

        #expect(b.comboFor(.tune) == nil)
        #expect(b.comboFor(.help) == ShortcutAction.help.defaultCombo(), "Q without a modifier is not accepted")
    }

    @Test func conflictIsReportedAndOverrideWins() throws {
        let b = KeyBindings([ShortcutAction.help.id: "Alt+U"])

        #expect(b.conflicts(.help) == [.toggleRun])
        #expect(b.resolve(try Self.combo("Alt+U")) == .help)
    }
}
