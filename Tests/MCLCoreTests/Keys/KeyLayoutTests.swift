import Testing
@testable import MCLCore

/// `AwtKeyCodes.translateForLayout` and the entry routing on US and Czech (QWERTZ and QWERTY) layouts and the keypad
/// Enter. The events carry what macOS reports for the layout: `kVK` and `charactersIgnoringModifiers`.
@Suite struct KeyLayoutTests {

    private static let defaults = KeyBindings(nil)
    private static let numericPad: UInt = AwtKeyCodes.macNumericPadFlag

    enum Layout: Sendable {
        case us, czechQwertz, czechQwerty
    }

    /// kVK → typed character, per layout, for the keys these tests use.
    private static func chars(_ layout: Layout, _ kVK: UInt16) -> String {
        switch (layout, kVK) {
        case (.us, 0x29): ";"
        case (.us, 0x27): "'"
        case (.us, 0x1B): "-"
        case (.us, 0x18): "="
        case (.us, 0x2A): "\\"
        case (.us, 0x32): "`"
        case (.us, 0x10): "y"
        case (.us, 0x06): "z"
        case (.czechQwertz, 0x29), (.czechQwerty, 0x29): "ů"
        case (.czechQwertz, 0x27), (.czechQwerty, 0x27): "§"
        case (.czechQwertz, 0x1B), (.czechQwerty, 0x1B): "="
        case (.czechQwertz, 0x21), (.czechQwerty, 0x21): "ú"
        case (.czechQwertz, 0x10): "z"
        case (.czechQwertz, 0x06): "y"
        case (.czechQwerty, 0x10): "y"
        case (.czechQwerty, 0x06): "z"
        default: ""
        }
    }

    private static func event(_ layout: Layout, _ kVK: UInt16, _ kind: MacKeyEvent.Kind = .keyDown,
                              shift: Bool = false) -> MacKeyEvent {
        let text = chars(layout, kVK)
        return MacKeyEvent(kind: kind, keyCode: kVK, characters: text, charactersIgnoringModifiers: text,
                           modifierFlags: shift ? AwtKeyCodes.macShiftFlag : 0)
    }

    private static func stroke(_ layout: Layout, _ kVK: UInt16, _ kind: MacKeyEvent.Kind = .keyDown) throws -> AwtKeyStroke {
        try #require(AwtKeyCodes.translateForLayout(event(layout, kVK, kind)))
    }

    private static func keypadEnter(_ kind: MacKeyEvent.Kind, keyCode: UInt16 = 0x4C) -> MacKeyEvent {
        MacKeyEvent(kind: kind, keyCode: keyCode, characters: "\u{3}", charactersIgnoringModifiers: "\u{3}",
                    modifierFlags: numericPad)
    }

    // MARK: - Semicolon, quote, equals

    @Test(arguments: [Layout.us, .czechQwertz, .czechQwerty])
    func semicolonKeyPositionIsSemicolon(_ layout: Layout) throws {
        let stroke = try Self.stroke(layout, 0x29)
        #expect(stroke.vk == AwtKeyCodes.vkSemicolon)
        #expect(Self.defaults.resolve(KeyCombo(ctrl: false, alt: false, shift: false, meta: false, keyCode: stroke.vk))
            == .sendCallExchange)
    }

    @Test func jdkTranslationAloneStillGivesTheExtendedCodeForUring() throws {
        let stroke = try #require(AwtKeyCodes.translate(Self.event(.czechQwertz, 0x29)))
        #expect(stroke.vk == 0x0100_016F)
    }

    @Test(arguments: [Layout.czechQwertz, .czechQwerty])
    func paragraphSignIsNotTheTuAndLogKey(_ layout: Layout) throws {
        let stroke = try Self.stroke(layout, 0x27)
        #expect(stroke.vk == AwtKeyCodes.vkUndefined)
        #expect(Self.defaults.resolve(KeyCombo(ctrl: false, alt: false, shift: false, meta: false, keyCode: stroke.vk))
            == nil)
        #expect(EntryKeyRouter.route(stroke, context: EntryKeyContext(bindings: Self.defaults)) == .passThrough)
    }

    @Test func usApostropheStillTuAndLog() throws {
        let stroke = try Self.stroke(.us, 0x27)
        #expect(stroke.vk == AwtKeyCodes.vkQuote)
        #expect(Self.defaults.resolve(KeyCombo(ctrl: false, alt: false, shift: false, meta: false, keyCode: stroke.vk))
            == .tuAndLog)
    }

    @Test func typedApostropheOnCzechIsTheQuoteKey() throws {
        // Czech: the apostrophe is Shift + a key elsewhere; the typed character selects the code.
        let event = MacKeyEvent(kind: .keyDown, keyCode: 0x2A, characters: "'", charactersIgnoringModifiers: "'")
        #expect(AwtKeyCodes.translateForLayout(event)?.vk == AwtKeyCodes.vkQuote)
    }

    @Test(arguments: [Layout.us, .czechQwertz, .czechQwerty])
    func equalsIsReachableForEsm(_ layout: Layout) throws {
        // US types "=" on kVK 0x18, Czech on kVK 0x1B.
        let kVK: UInt16 = layout == .us ? 0x18 : 0x1B
        let down = try Self.stroke(layout, kVK, .keyDown)
        #expect(down.vk == AwtKeyCodes.vkEquals)
        let esm = EntryKeyContext(bindings: Self.defaults, esmActive: true, hasLastSent: true)
        #expect(EntryKeyRouter.route(down, context: esm) == .resendLast)
    }

    @Test func czechMinusPositionOfUsIsNotEqualsOnUs() throws {
        let stroke = try Self.stroke(.us, 0x1B)
        #expect(stroke.vk == AwtKeyCodes.vkMinus)
    }

    @Test func shiftedUsSemicolonKeepsThePosition() throws {
        let event = MacKeyEvent(kind: .keyDown, keyCode: 0x29, characters: ":", charactersIgnoringModifiers: ":",
                                modifierFlags: AwtKeyCodes.macShiftFlag)
        let stroke = try #require(AwtKeyCodes.translateForLayout(event))
        #expect(stroke.vk == AwtKeyCodes.vkSemicolon)
        #expect(stroke.isShiftDown)
    }

    // MARK: - Letters, arrows, function keys stay as in the JDK

    @Test func yAndZFollowTheTypedCharacter() throws {
        #expect(try Self.stroke(.czechQwertz, 0x10).vk == 90) // Z
        #expect(try Self.stroke(.czechQwertz, 0x06).vk == 89) // Y
        #expect(try Self.stroke(.czechQwerty, 0x10).vk == 89)
        #expect(try Self.stroke(.czechQwerty, 0x06).vk == 90)
        #expect(try Self.stroke(.us, 0x10).vk == 89)
    }

    @Test func letterOnABracketPositionIsTheBracketKey() throws {
        #expect(try Self.stroke(.czechQwertz, 0x21).vk == AwtKeyCodes.vkOpenBracket)
    }

    @Test func letterOnADigitPositionKeepsTheExtendedCode() throws {
        let event = MacKeyEvent(kind: .keyDown, keyCode: 0x13, characters: "š", charactersIgnoringModifiers: "š")
        let stroke = try #require(AwtKeyCodes.translateForLayout(event))
        #expect(stroke.vk == 0x0100_0161)
    }

    @Test func arrowsAndFunctionKeysAreUntouched() throws {
        let left = MacKeyEvent(kind: .keyDown, keyCode: 0x7B, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}")
        #expect(AwtKeyCodes.translateForLayout(left) == AwtKeyCodes.translate(left))
        let f5 = MacKeyEvent(kind: .keyDown, keyCode: 0x60, characters: "\u{F708}", charactersIgnoringModifiers: "\u{F708}")
        #expect(AwtKeyCodes.translateForLayout(f5)?.vk == 116)
    }

    @Test func keypadKeysKeepTheirCodes() throws {
        let plus = MacKeyEvent(kind: .keyDown, keyCode: 0x45, characters: "+", charactersIgnoringModifiers: "+",
                               modifierFlags: Self.numericPad)
        #expect(AwtKeyCodes.translateForLayout(plus)?.vk == 107)
        let comma = MacKeyEvent(kind: .keyDown, keyCode: 0x5F, characters: ",", charactersIgnoringModifiers: ",",
                                modifierFlags: Self.numericPad)
        let stroke = try #require(AwtKeyCodes.translateForLayout(comma))
        #expect(stroke.vk == 44 && stroke.location == AwtKeyCodes.keyLocationNumpad)
    }

    @Test func deadKeyStaysDead() throws {
        // Czech ´ (dead acute): characters is empty, the dead-key table decides.
        let event = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "´",
                                deadKeyCharacter: 0x00B4)
        #expect(AwtKeyCodes.translateForLayout(event)?.vk == 129)
    }

    // MARK: - Keypad Enter

    @Test(arguments: [UInt16(0x4C), UInt16(0x34)])
    func keypadEnterIsReturn(_ keyCode: UInt16) throws {
        let release = try #require(AwtKeyCodes.translateForLayout(Self.keypadEnter(.keyUp, keyCode: keyCode)))
        #expect(release.isKey(AwtKeyCodes.vkEnter))
        let context = EntryKeyContext(bindings: Self.defaults)
        #expect(EntryKeyRouter.route(release, context: context) == .enter(ctrl: false, step: .logQso(ctrlEnter: false)))
    }

    @Test func keypadEnterPressIsSwallowedLikeReturnPress() throws {
        let press = try #require(AwtKeyCodes.translateForLayout(Self.keypadEnter(.keyDown)))
        let returnPress = try Self.returnStroke(.keyDown)
        let context = EntryKeyContext(bindings: Self.defaults)
        #expect(EntryKeyRouter.route(press, context: context) == EntryKeyRouter.route(returnPress, context: context))
    }

    @Test func keypadEnterRunsEsmAndTakesSuggestionsLikeReturn() throws {
        let release = try #require(AwtKeyCodes.translateForLayout(Self.keypadEnter(.keyUp)))
        let esm = EntryKeyContext(bindings: Self.defaults, esmActive: true)
        #expect(EntryKeyRouter.route(release, context: esm) == .enter(ctrl: false, step: .esm))
        let pick = EntryKeyContext(bindings: Self.defaults, scpPick: 2, suggestionCount: 3)
        #expect(EntryKeyRouter.route(release, context: pick) == .enter(ctrl: false, step: .takeSuggestion(2)))
    }

    @Test func keypadEnterWithCtrlIsCtrlEnterOnACommand() throws {
        var event = Self.keypadEnter(.keyUp)
        event.modifierFlags |= AwtKeyCodes.macControlFlag
        let release = try #require(AwtKeyCodes.translateForLayout(event))
        let command = EntryKeyContext(bindings: Self.defaults, hasCommand: true)
        #expect(EntryKeyRouter.route(release, context: command) == .enter(ctrl: true, step: .logQso(ctrlEnter: true)))
    }

    @Test func plainTranslateStillMakesKeypadEnterANumpadKey() throws {
        // The JDK-faithful layer is unchanged; only the layout layer promotes it.
        let release = try #require(AwtKeyCodes.translate(Self.keypadEnter(.keyUp)))
        #expect(release.location == AwtKeyCodes.keyLocationNumpad)
    }

    @Test func enterKeyCodes() {
        #expect(AwtKeyCodes.isMacEnterKey(0x24))
        #expect(AwtKeyCodes.isMacEnterKey(0x4C))
        #expect(!AwtKeyCodes.isMacEnterKey(0x35))
    }

    private static func returnStroke(_ kind: MacKeyEvent.Kind) throws -> AwtKeyStroke {
        let event = MacKeyEvent(kind: kind, keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r")
        return try #require(AwtKeyCodes.translateForLayout(event))
    }
}
