import Testing
@testable import MCLCore

/// `KeyCombo`, `ShortcutAction` and `KeyBindings` against values measured on Java v1.1.1:
/// rows `KC.*`/`KB` from a maintainer-only probe and `KP.*` from
/// a maintainer-only probe.
@Suite struct KeyComboMeasuredTests {

    /// The Java probe output for `parse`: `empty`, or `format code=… allowed=…`.
    private static func describe(_ text: String) -> String {
        guard let combo = KeyCombo.parse(text) else {
            return "empty"
        }
        return "\(combo.format()) code=\(combo.keyCode) allowed=\(combo.isAllowedShortcut)"
    }

    /// `KC.parse` (probe.txt).
    private static let parseRows: [(String, String)] = [
        ("Ctrl++", "empty"),
        ("ctrl + s", "Ctrl+S code=83 allowed=true"),
        ("Ctrl+", "empty"),
        ("+", "empty"),
        ("Alt+\u{2325}", "empty"),
        ("Cmd+;", "Cmd+SEMICOLON code=59 allowed=true"),
        ("F25", "empty"),
        ("F24", "F24 code=61451 allowed=true"),
        ("Ctrl+Alt", "empty"),
        ("a+b", "B code=66 allowed=false"),
        ("ctrl+pgup", "Ctrl+PAGE_UP code=33 allowed=true"),
        ("Shift+A", "Shift+A code=65 allowed=false"),
        ("A", "A code=65 allowed=false"),
        (";", "SEMICOLON code=59 allowed=true"),
        ("'", "QUOTE code=222 allowed=true"),
        ("\\", "empty"),
        ("BACK_SLASH", "BACK_SLASH code=92 allowed=true"),
        ("Ctrl+Alt+Del", "Ctrl+Alt+DELETE code=127 allowed=true"),
        ("Ctrl + + ", "empty"),
        ("Ctrl+-", "Ctrl+MINUS code=45 allowed=true"),
        ("Ctrl+=", "Ctrl+EQUALS code=61 allowed=true"),
        ("Ctrl+PLUS", "Ctrl+PLUS code=521 allowed=true"),
        ("ctrl+ENTER\n", "Ctrl+ENTER code=10 allowed=true"),
        ("Ctrl+0", "Ctrl+0 code=48 allowed=true"),
        ("Ctrl+Numpad0", "Ctrl+NUMPAD0 code=96 allowed=true"),
        ("Ctrl+NUMPAD0", "Ctrl+NUMPAD0 code=96 allowed=true"),
        ("Ctrl+\u{DF}", "empty"),
        ("Ctrl+UNDEFINED", "Ctrl+UNDEFINED code=0 allowed=true"),
        ("Ctrl+SHIFT", "empty"),
        ("Ctrl+ALT_GRAPH", "Ctrl+ALT_GRAPH code=65406 allowed=false"),
        ("Ctrl+Option+K", "Ctrl+Alt+K code=75 allowed=true"),
        ("Ctrl+Escape", "Ctrl+ESCAPE code=27 allowed=true"),
    ]

    /// `KP.parse` (keys-probe.txt): inputs where a Swift `String` (canonical equality, Unicode
    /// `\s`, `.`) differs from Java's.
    private static let edgeRows: [(String, String)] = [
        ("Ctrl+\u{212A}", "empty"),
        ("\u{37E}", "empty"),
        ("Ctrl+\u{37E}", "empty"),
        ("A+\u{2028}B", "empty"),
        ("A +\u{2028}", "empty"),
        ("Ctrl+\u{85}K", "empty"),
        ("+A", "A code=65 allowed=false"),
        ("A++B", "B code=66 allowed=false"),
        ("Ctrl + \nK", "Ctrl+K code=75 allowed=true"),
        ("\u{2318}+\u{21E7}+K", "Shift+Cmd+K code=75 allowed=true"),
        ("ctrl+\u{DF}", "empty"),
        ("Ctrl+separator", "Ctrl+SEPARATER code=108 allowed=true"),
        ("Ctrl+\u{A0}K", "empty"),
        ("\u{3000}", "empty"),
        ("Ctrl+F1", "Ctrl+F1 code=112 allowed=true"),
        ("Ctrl+Pgdown", "Ctrl+PAGE_DOWN code=34 allowed=true"),
        ("Ins", "INSERT code=155 allowed=true"),
        ("Return", "ENTER code=10 allowed=false"),
        ("Apostrophe", "QUOTE code=222 allowed=true"),
        ("Ctrl+Opt+Esc", "Ctrl+Alt+ESCAPE code=27 allowed=true"),
        ("Command+Shift+Control+Alt+X", "Ctrl+Alt+Shift+Cmd+X code=88 allowed=true"),
    ]

    @Test func parseMatchesJava() {
        for (input, expected) in Self.parseRows {
            #expect(Self.describe(input) == expected, "\(input.debugDescription)")
        }
        for (input, expected) in Self.edgeRows {
            #expect(Self.describe(input) == expected, "\(input.debugDescription)")
        }
        #expect(KeyCombo.parse(nil) == nil)
        #expect(KeyCombo.parse("") == nil)
    }

    @Test func formatMatchesJava() {
        let unknown = KeyCombo(ctrl: true, alt: false, shift: false, meta: false, keyCode: 0x12345)
        let negative = KeyCombo(ctrl: false, alt: false, shift: false, meta: false, keyCode: -5)
        #expect(unknown.format() == "Ctrl+0x12345")
        #expect(negative.format() == "0xfffffffb")
        #expect(KeyCombo(ctrl: false, alt: false, shift: false, meta: false, keyCode: 108).format() == "SEPARATER")

        // KP.format: Alt+Shift+Cmd + code → text, isModifierKey, isAllowedShortcut.
        let rows: [(Int32, String, Bool, Bool)] = [
            (108, "SEPARATER", false, true),
            (-1, "0xffffffff", false, true),
            (0, "UNDEFINED", false, true),
            (65_535, "0xffff", false, true),
            (Int32.max, "0x7fffffff", false, true),
            (Int32.min, "0x80000000", false, true),
            (16, "SHIFT", true, false),
            (157, "META", true, false),
        ]
        for (code, name, modifier, allowed) in rows {
            let combo = KeyCombo(ctrl: false, alt: true, shift: true, meta: true, keyCode: code)
            #expect(combo.format() == "Alt+Shift+Cmd+\(name)", "\(code)")
            #expect(KeyCombo.isModifierKey(code) == modifier, "\(code)")
            #expect(combo.isAllowedShortcut == allowed, "\(code)")
        }
    }

    /// `KC.default` (probe.txt): the id and format of the default key of all 55 actions in Java order.
    @Test func defaultsMatchJava() {
        let expected: [String] = [
            "send_call_exch SEMICOLON", "tu_log QUOTE", "log_quiet Alt+ENTER", "force_log Ctrl+Alt+ENTER",
            "wipe Ctrl+W", "wipe_undo Alt+W", "delete_last Ctrl+D", "note Ctrl+N", "find Ctrl+F",
            "inc_nr Ctrl+U", "esm Ctrl+M", "cut Ctrl+G", "yank Alt+Y", "fkeys Alt+K", "help Alt+H",
            "operator Ctrl+O", "run Alt+U", "jump_cq Alt+Q", "repeat Alt+R", "repeat_time Ctrl+R",
            "tune Ctrl+T", "split_on Ctrl+S", "split_toggle Ctrl+Alt+S", "split_prompt Alt+F7",
            "prev_freq Alt+F8", "swap_vfo Alt+F10", "auto_runsp Alt+F11", "copy_vfo Alt+F12",
            "rit_up Ctrl+Alt+RIGHT", "rit_down Ctrl+Alt+LEFT", "rit_clear Ctrl+Alt+R",
            "switch_radio BACK_SLASH", "so2r_stereo BACK_QUOTE", "cw_keyboard Ctrl+K",
            "pass_call Ctrl+Alt+P", "pop_stack Ctrl+Alt+K", "rotor_turn Alt+J", "rotor_long Ctrl+Alt+J",
            "rotor_stop Alt+L", "next_antenna Ctrl+Alt+A", "band_up Ctrl+PAGE_UP", "band_down Ctrl+PAGE_DOWN",
            "spot_up Cmd+DOWN", "spot_down Cmd+UP", "mult_up Ctrl+Alt+DOWN", "mult_down Ctrl+Alt+UP",
            "self_up Alt+Shift+DOWN", "self_down Alt+Shift+UP", "spot Alt+P", "spot_comment Ctrl+P",
            "store Alt+O", "mark Alt+M", "remove_spot Alt+D", "remove_blacklist Alt+Shift+D",
            "dx_window Ctrl+TAB",
        ]
        let actual: [String] = ShortcutAction.allCases.map { "\($0.id) \($0.defaultCombo().format())" }
        #expect(actual == expected)
        #expect(ShortcutAction.byId("wipe") == .wipe)
        #expect(ShortcutAction.byId("WIPE") == nil)
        #expect(ShortcutAction.byId(nil) == nil)
    }

    /// `KB` (probe.txt) a `KP.kb` (keys-probe.txt).
    @Test func bindingsMatchJava() throws {
        let kb = KeyBindings(["wipe": "Ctrl+D", "note": "", "find": "garbage", "esm": "A"])
        #expect(kb.conflicts(.deleteLast) == [.wipe])
        #expect(kb.resolve(try #require(KeyCombo.parse("Ctrl+D"))) == .wipe)
        #expect(kb.comboFor(.note) == nil)
        #expect(kb.comboFor(.find)?.format() == "Ctrl+F")
        #expect(kb.comboFor(.toggleEsm)?.format() == "Ctrl+M")

        // Two remappings to the same key: the later one in Java order wins (SPOT_IT after WIPE).
        let two = KeyBindings([
            "spot": "Ctrl+Alt+Z", "wipe": "Ctrl+Alt+Z", "help": "   ", "nonexistent": "Ctrl+Q", "tune": "Shift+F1",
        ])
        #expect(two.resolve(try #require(KeyCombo.parse("Ctrl+Alt+Z"))) == .spotIt)
        #expect(two.conflicts(.wipe) == [.spotIt])
        #expect(two.comboFor(.help) == nil)
        #expect(two.comboFor(.tune)?.format() == "Shift+F1")
        #expect(two.resolve(try #require(KeyCombo.parse("Ctrl+W"))) == nil)
    }
}
