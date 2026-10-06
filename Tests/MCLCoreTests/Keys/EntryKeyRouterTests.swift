import Testing
@testable import MCLCore

/// `EntryKeyRouter.route` against Kotlin `EntryPanel` `keys` (`EP:940-1005`), `fieldKeys` (`EP:1012-1024`) and
/// the call field's space bar (`EP:1109-1118`): one table row per event, in Kotlin's order of checks.
@Suite struct EntryKeyRouterTests {

    private static let defaults = KeyBindings(nil)
    private static let shift: Int32 = AwtKeyCodes.shiftDownMask
    private static let ctrl: Int32 = AwtKeyCodes.ctrlDownMask
    private static let alt: Int32 = AwtKeyCodes.altDownMask
    private static let meta: Int32 = AwtKeyCodes.metaDownMask

    private static func down(_ vk: Int32, _ modifiers: Int32 = 0, location: Int32 = 1) -> AwtKeyStroke {
        AwtKeyStroke(vk: vk, location: location, modifiers: modifiers, phase: .pressed)
    }

    private static func up(_ vk: Int32, _ modifiers: Int32 = 0, location: Int32 = 1) -> AwtKeyStroke {
        AwtKeyStroke(vk: vk, location: location, modifiers: modifiers, phase: .released)
    }

    private static func route(_ stroke: AwtKeyStroke, _ context: EntryKeyContext = EntryKeyContext(bindings: defaults))
        -> EntryKeyDecision {
        EntryKeyRouter.route(stroke, context: context)
    }

    private static let enter = AwtKeyCodes.vkEnter
    private static let escape = AwtKeyCodes.vkEscape
    private static let f1 = AwtKeyCodes.vkF1

    @Test func onKeyUpSetIsKotlins() {
        let onKeyUp = Set(ShortcutAction.allCases.filter(\.onKeyUp))
        #expect(onKeyUp == [.logWithoutSending, .forceLog, .operator])
    }

    @Test func shortcutConsumesBothPhasesAndFiresOnItsPhase() {
        // Ctrl+W (WIPE) fires on press.
        #expect(Self.route(Self.down(87, Self.ctrl)) == .action(.wipe))
        #expect(Self.route(Self.up(87, Self.ctrl)) == .consume)
        // ON_KEY_UP: Alt+Enter, Ctrl+Alt+Enter, Ctrl+O fire on release.
        #expect(Self.route(Self.down(Self.enter, Self.alt)) == .consume)
        #expect(Self.route(Self.up(Self.enter, Self.alt)) == .action(.logWithoutSending))
        #expect(Self.route(Self.up(Self.enter, Self.ctrl | Self.alt)) == .action(.forceLog))
        #expect(Self.route(Self.down(79, Self.ctrl)) == .consume)
        #expect(Self.route(Self.up(79, Self.ctrl)) == .action(.operator))
        // Shortcuts match by code only: Alt + keypad Enter is LOG_WITHOUT_SENDING too.
        #expect(Self.route(Self.up(Self.enter, Self.alt, location: 4)) == .action(.logWithoutSending))
        // ";" and "'" without modifiers.
        #expect(Self.route(Self.down(AwtKeyCodes.vkSemicolon)) == .action(.sendCallExchange))
        #expect(Self.route(Self.down(AwtKeyCodes.vkQuote)) == .action(.tuAndLog))
    }

    @Test func shortcutBeforeFunctionKeys() {
        #expect(Self.route(Self.down(Self.f1 + 6, Self.alt)) == .action(.splitPrompt))
        #expect(Self.route(Self.up(Self.f1 + 6, Self.alt)) == .consume)
        let remapped = EntryKeyContext(bindings: KeyBindings(["tune": "F5"]))
        #expect(Self.route(Self.down(Self.f1 + 4), remapped) == .action(.tune))
    }

    @Test func functionKeys() {
        #expect(Self.route(Self.down(Self.f1 + 6)) == .functionKey(6, shift: false, ctrlShift: false))
        #expect(Self.route(Self.up(Self.f1 + 6)) == .consume)
        #expect(Self.route(Self.down(Self.f1 + 1, Self.shift)) == .functionKey(1, shift: true, ctrlShift: false))
        #expect(Self.route(Self.down(Self.f1 + 2, Self.ctrl | Self.shift)) == .functionKey(2, shift: true, ctrlShift: true))
        #expect(Self.route(Self.down(Self.f1, Self.ctrl)) == .functionKey(0, shift: false, ctrlShift: false))
        #expect(Self.route(Self.down(Self.f1 + 11)) == .functionKey(11, shift: false, ctrlShift: false))
        // F13 is not a message key.
        #expect(Self.route(Self.down(61_440)) == .passThrough)
        // Auto-repeat presses repeat the message (AWT repeats KEY_PRESSED).
        let repeated = AwtKeyStroke(vk: Self.f1, location: 1, modifiers: 0, phase: .pressed, isRepeat: true)
        #expect(Self.route(repeated) == .functionKey(0, shift: false, ctrlShift: false))
    }

    @Test func cwSpeed() {
        let cw = EntryKeyContext(bindings: Self.defaults, isCw: true)
        #expect(Self.route(Self.down(AwtKeyCodes.vkPageUp), cw) == .cwSpeed(1))
        #expect(Self.route(Self.down(AwtKeyCodes.vkPageDown), cw) == .cwSpeed(-1))
        #expect(Self.route(Self.up(AwtKeyCodes.vkPageUp), cw) == .passThrough)
        #expect(Self.route(Self.down(AwtKeyCodes.vkPageUp)) == .passThrough)
        // Ctrl+PgUp is a binding (BAND_UP).
        #expect(Self.route(Self.down(AwtKeyCodes.vkPageUp, Self.ctrl), cw) == .action(.bandUp))
    }

    @Test func escape() {
        let sending = EntryKeyContext(bindings: Self.defaults, isSending: true, scpPick: 1, suggestionCount: 3)
        #expect(Self.route(Self.up(Self.escape), sending) == .escape(.stopSending))
        let picked = EntryKeyContext(bindings: Self.defaults, scpPick: 0, suggestionCount: 3)
        #expect(Self.route(Self.up(Self.escape), picked) == .escape(.cancelSuggestion))
        #expect(Self.route(Self.up(Self.escape)) == .escape(.wipe))
        #expect(Self.route(Self.down(Self.escape)) == .passThrough)
        #expect(Self.route(Self.up(Self.escape, Self.ctrl)) == .escape(.wipe))
    }

    @Test func enter() {
        let picked = EntryKeyContext(bindings: Self.defaults, esmActive: true, scpPick: 2, suggestionCount: 3,
                                     hasCommand: true)
        #expect(Self.route(Self.up(Self.enter), picked) == .enter(ctrl: false, step: .takeSuggestion(2)))
        let command = EntryKeyContext(bindings: Self.defaults, esmActive: true, hasCommand: true)
        #expect(Self.route(Self.up(Self.enter, Self.ctrl), command) == .enter(ctrl: true, step: .logQso(ctrlEnter: true)))
        let esm = EntryKeyContext(bindings: Self.defaults, esmActive: true)
        #expect(Self.route(Self.up(Self.enter), esm) == .enter(ctrl: false, step: .esm))
        #expect(Self.route(Self.up(Self.enter, Self.ctrl)) == .enter(ctrl: true, step: .logQso(ctrlEnter: false)))
        #expect(Self.route(Self.down(Self.enter)) == .passThrough)
        // Sending only matters for Esc.
        let sending = EntryKeyContext(bindings: Self.defaults, isSending: true)
        #expect(Self.route(Self.up(Self.enter), sending) == .enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        // The keypad Enter is Compose's NumPadEnter, not Enter.
        #expect(Self.route(Self.up(Self.enter, location: 4)) == .passThrough)
    }

    @Test func equalsInEsm() {
        let esmSent = EntryKeyContext(bindings: Self.defaults, esmActive: true, hasLastSent: true)
        let esm = EntryKeyContext(bindings: Self.defaults, esmActive: true)
        #expect(Self.route(Self.down(AwtKeyCodes.vkEquals), esmSent) == .resendLast)
        #expect(Self.route(Self.up(AwtKeyCodes.vkEquals), esmSent) == .consume)
        #expect(Self.route(Self.down(AwtKeyCodes.vkEquals), esm) == .consume)
        #expect(Self.route(Self.down(AwtKeyCodes.vkEquals, Self.shift), esmSent) == .resendLast)
        #expect(Self.route(Self.down(AwtKeyCodes.vkEquals)) == .passThrough)
        #expect(Self.route(Self.down(AwtKeyCodes.vkEquals, location: 4), esmSent) == .passThrough)
    }

    @Test func arrows() {
        func context(_ pick: Int, _ count: Int) -> EntryKeyContext {
            EntryKeyContext(bindings: Self.defaults, scpPick: pick, suggestionCount: count)
        }
        let downKey = AwtKeyCodes.vkDown
        let upKey = AwtKeyCodes.vkUp
        #expect(Self.route(Self.down(downKey), context(-1, 3)) == .scpMove(by: 1, to: 0))
        #expect(Self.route(Self.down(downKey), context(2, 3)) == .scpMove(by: 1, to: 2))
        #expect(Self.route(Self.down(upKey), context(0, 3)) == .scpMove(by: -1, to: -1))
        #expect(Self.route(Self.down(upKey), context(-1, 3)) == .scpMove(by: -1, to: -1))
        #expect(Self.route(Self.down(upKey), context(-1, 0)) == .tune(-1))
        #expect(Self.route(Self.down(downKey), context(-1, 0)) == .tune(1))
        #expect(Self.route(Self.up(downKey), context(-1, 3)) == .passThrough)
        // Cmd+↓ is a binding (NEXT_SPOT_UP; Ctrl+arrows belong to Mission Control), Alt+Shift+↓ too (NEXT_SELF_UP).
        #expect(Self.route(Self.down(downKey, Self.meta), context(-1, 3)) == .action(.nextSpotUp))
        #expect(Self.route(Self.down(upKey, Self.meta), context(-1, 3)) == .action(.nextSpotDown))
        #expect(Self.route(Self.down(downKey, Self.ctrl), context(-1, 3)) != .action(.nextSpotUp))
        #expect(Self.route(Self.down(downKey, Self.alt | Self.shift), context(-1, 3)) == .action(.nextSelfUp))
    }

    @Test func fieldKeysComeBeforeShortcuts() {
        let call = EntryKeyContext(bindings: Self.defaults, field: .call)
        let exchange = EntryKeyContext(bindings: Self.defaults, field: .exchange)
        let time = EntryKeyContext(bindings: Self.defaults, field: .time)
        let tab = AwtKeyCodes.vkTab
        let space = AwtKeyCodes.vkSpace
        #expect(Self.route(Self.down(tab), call) == .focusMove(by: 1, skipReports: false))
        #expect(Self.route(Self.down(tab, Self.shift), exchange) == .focusMove(by: -1, skipReports: false))
        #expect(Self.route(Self.up(tab), call) == .consume)
        // Alt+Tab is still the field's Tab; Ctrl+Tab goes on to the binding (DX_CLUSTER_WINDOW).
        #expect(Self.route(Self.down(tab, Self.alt), call) == .focusMove(by: 1, skipReports: false))
        #expect(Self.route(Self.down(tab, Self.ctrl), call) == .action(.dxClusterWindow))
        #expect(Self.route(Self.down(tab), time) == .passThrough)
        #expect(Self.route(Self.down(space), exchange) == .focusMove(by: 1, skipReports: true))
        #expect(Self.route(Self.up(space), exchange) == .consume)
        #expect(Self.route(Self.down(space), time) == .passThrough)
    }

    @Test func spaceInTheCallField() {
        func call(_ text: String) -> EntryKeyContext {
            EntryKeyContext(bindings: Self.defaults, field: .call, callText: text)
        }
        let space = AwtKeyCodes.vkSpace
        #expect(Self.route(Self.down(space), call("OK1XOE")) == .jumpToExchange)
        #expect(Self.route(Self.up(space), call("OK1XOE")) == .consume)
        #expect(Self.route(Self.down(space), call("")) == .jumpToExchange)
        // Commands with an argument keep the space (trimmed, upper-cased, first word).
        #expect(Self.route(Self.down(space), call("OPON")) == .passThrough)
        #expect(Self.route(Self.down(space), call("  tour 5")) == .passThrough)
        #expect(Self.route(Self.down(space), call("countyline")) == .passThrough)
        #expect(Self.route(Self.down(space), call("TOURX")) == .jumpToExchange)
        #expect(EntryKeyRouter.firstWord("\u{00A0}opon x") == "OPON")
    }

    @Test func shiftKeysReportShiftHeld() {
        let left = AwtKeyStroke(vk: AwtKeyCodes.vkShift, location: 2, modifiers: Self.shift, phase: .pressed)
        let right = AwtKeyStroke(vk: AwtKeyCodes.vkShift, location: 3, modifiers: 0, phase: .released)
        #expect(Self.route(left) == .shiftHeld(true, then: .passThrough))
        #expect(Self.route(right) == .shiftHeld(false, then: .passThrough))
        let withMeta = AwtKeyStroke(vk: AwtKeyCodes.vkShift, location: 2, modifiers: Self.shift | Self.meta, phase: .pressed)
        #expect(Self.route(withMeta) == .shiftHeld(true, then: .passThrough))
        // A Shift with STANDARD location (two flags changed at once) is not Key.ShiftLeft/ShiftRight.
        let standard = AwtKeyStroke(vk: AwtKeyCodes.vkShift, location: 1, modifiers: Self.shift, phase: .pressed)
        #expect(Self.route(standard) == .passThrough)
        // In the time field too (it has `keys`).
        let time = EntryKeyContext(bindings: Self.defaults, field: .time)
        #expect(Self.route(left, time) == .shiftHeld(true, then: .passThrough))
    }

    @Test func unboundCommandPassesThrough() {
        #expect(Self.route(Self.down(81, Self.meta)) == .passThrough) // ⌘Q
        #expect(Self.route(Self.down(67, Self.meta)) == .passThrough) // ⌘C
        #expect(Self.route(Self.up(Self.enter, Self.meta)) == .passThrough)
        #expect(Self.route(Self.up(Self.escape, Self.meta)) == .passThrough)
        #expect(Self.route(Self.down(Self.f1, Self.meta)) == .passThrough)
        #expect(Self.route(Self.down(AwtKeyCodes.vkMeta, Self.meta, location: 2)) == .passThrough)
        let bound = EntryKeyContext(bindings: KeyBindings(["help": "Cmd+K"]))
        #expect(Self.route(Self.down(75, Self.meta), bound) == .action(.help))
        #expect(Self.route(Self.up(75, Self.meta), bound) == .consume)
    }

    @Test func unboundAltPassesThrough() {
        // Czech Option+E types "€": VK_E with Alt and no binding → the field gets it.
        let euro = MacKeyEvent(kind: .keyDown, keyCode: 0x0E, characters: "€", charactersIgnoringModifiers: "e",
                               modifierFlags: AwtKeyCodes.macOptionFlag)
        let euroStroke = AwtKeyCodes.translate(euro)
        #expect(euroStroke.map { Self.route($0) } == .passThrough)
        // US Option+E is a dead acute.
        let dead = MacKeyEvent(kind: .keyDown, keyCode: 0x0E, characters: "", charactersIgnoringModifiers: "e",
                               modifierFlags: AwtKeyCodes.macOptionFlag, deadKeyCharacter: 0x00B4)
        let deadStroke = AwtKeyCodes.translate(dead)
        #expect(deadStroke.map { Self.route($0) } == .passThrough)
        #expect(Self.route(Self.down(69, Self.ctrl)) == .passThrough)
        // Bound Alt combinations still act: Alt+W (WIPE_UNDO).
        #expect(Self.route(Self.down(87, Self.alt)) == .action(.wipeUndo))
    }

    @Test func layoutsThroughTranslate() throws {
        // Czech "ů" on the US ";" key has an extended code: the ";" binding does not fire.
        let u = MacKeyEvent(kind: .keyDown, keyCode: 0x29, characters: "ů", charactersIgnoringModifiers: "ů")
        let uStroke = try #require(AwtKeyCodes.translate(u))
        #expect(Self.route(uStroke) == .passThrough)
        // Czech "§" on the US "'" key is VK_QUOTE: TU_AND_LOG.
        let para = MacKeyEvent(kind: .keyDown, keyCode: 0x27, characters: "§", charactersIgnoringModifiers: "§")
        let paraStroke = try #require(AwtKeyCodes.translate(para))
        #expect(Self.route(paraStroke) == .action(.tuAndLog))
        // Czech Ctrl+W: the key types "w" in every layout here.
        let w = MacKeyEvent(kind: .keyDown, keyCode: 0x0D, characters: "\u{17}", charactersIgnoringModifiers: "w",
                            modifierFlags: AwtKeyCodes.macControlFlag)
        let wStroke = try #require(AwtKeyCodes.translate(w))
        #expect(Self.route(wStroke) == .action(.wipe))
        // Czech "=" sits on the US "-" key (kVK 0x1B) and is not a letter → positional VK_MINUS, so the ESM
        // "=" resend is unreachable on a Czech layout (as in Kotlin on JDK 21).
        let equals = MacKeyEvent(kind: .keyDown, keyCode: 0x1B, characters: "=", charactersIgnoringModifiers: "=")
        let equalsStroke = try #require(AwtKeyCodes.translate(equals))
        #expect(equalsStroke.vk == 45)
        let esmSent = EntryKeyContext(bindings: Self.defaults, esmActive: true, hasLastSent: true)
        #expect(Self.route(equalsStroke, esmSent) == .passThrough)
        // AZERTY: Ctrl on the US W key types "z" → Ctrl+Z (no binding).
        let z = MacKeyEvent(kind: .keyDown, keyCode: 0x0D, characters: "\u{1A}", charactersIgnoringModifiers: "z",
                            modifierFlags: AwtKeyCodes.macControlFlag)
        let zStroke = try #require(AwtKeyCodes.translate(z))
        #expect(Self.route(zStroke) == .passThrough)
        // The left Shift via flagsChanged.
        let shiftDown = MacKeyEvent(kind: .flagsChanged, keyCode: 56, modifierFlags: AwtKeyCodes.macShiftFlag)
        let shiftStroke = try #require(AwtKeyCodes.translate(shiftDown))
        #expect(Self.route(shiftStroke) == .shiftHeld(true, then: .passThrough))
        // The right Option never releases in JDK 21 — it is not a Shift, so routing ignores it.
        let rightOption = MacKeyEvent(kind: .flagsChanged, keyCode: 61, modifierFlags: 0,
                                      previousModifierFlags: AwtKeyCodes.macOptionFlag)
        let optionStroke = try #require(AwtKeyCodes.translate(rightOption))
        #expect(Self.route(optionStroke) == .passThrough)
    }
}
