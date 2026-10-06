import Foundation
import Testing
@testable import MCLCore

/// `AwtKeyCodes.translate` against JDK 21 `AWTEvent.m` (`Fixtures/awt-mac-chars-jdk21.tsv`,
/// a maintainer-only probe): the character branch of `NsCharToJavaVirtualKeyCode`,
/// the dead-key table, the `keyTable` locations and `NsKeyModifiersToJavaKeyInfo`. Layout cases feed the
/// characters macOS reports for the layout (`charactersIgnoringModifiers` keeps Shift).
@Suite struct AwtKeyTranslateTests {

    private static func fixtureLines(_ name: String) throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    private static func rows(_ type: String) throws -> [[String]] {
        try fixtureLines("awt-mac-chars-jdk21")
            .filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
            .filter { $0.first == type }
    }

    private static func hex(_ text: String) throws -> Int {
        try #require(Int(text.dropFirst(2), radix: 16), "\(text)")
    }

    // MARK: - Fixture

    @Test func fixtureComesFromTheSameSourceAsTheKeyTable() throws {
        let chars = try #require(try Self.fixtureLines("awt-mac-chars-jdk21").first)
        let table = try #require(try Self.fixtureLines("awt-mac-keycodes-jdk21").first)
        let sha = "b478c7e80024525964f6ffe3f89fa5d0aabab02b5bc4d36aacca84c743424bb8"
        #expect(chars.contains("jdk-21+35"))
        #expect(chars.contains("(sha256 \(sha))"))
        #expect(table.contains("(sha256 \(sha))"))
    }

    @Test func locationsOfAll128KeyTableEntries() throws {
        let rows = try Self.rows("LOCATION")
        #expect(rows.count == 128)
        let names: [String: Int32] = [
            "STANDARD": AwtKeyCodes.keyLocationStandard, "NUMPAD": AwtKeyCodes.keyLocationNumpad,
            "UNKNOWN": AwtKeyCodes.keyLocationUnknown,
        ]
        for (index, row) in rows.enumerated() {
            #expect(try Self.hex(row[1]) == index)
            let location = try #require(names[row[3]])
            #expect(AwtKeyCodes.macKeyLocation(index) == location, "kVK \(row[1])")
            // A key without a letter or digit goes to the positional table with its location.
            let event = MacKeyEvent(kind: .keyDown, keyCode: UInt16(index), characters: "\u{F8FF}",
                                    charactersIgnoringModifiers: "\u{F8FF}")
            let stroke = try #require(AwtKeyCodes.translate(event))
            #expect(stroke.vk == (AwtKeyCodes.fromMac(keyCode: UInt16(index)) ?? 0))
            #expect(stroke.location == location)
        }
    }

    @Test func deadKeyTableMatchesJdk21() throws {
        let rows = try Self.rows("DEAD")
        #expect(rows.count == 18)
        #expect(AwtKeyCodes.deadKeyTable.count == 18)
        for row in rows {
            let char = UInt16(try Self.hex(row[1]))
            let code = try #require(Int32(row[3]))
            #expect(AwtKeyCodes.code(named: row[2]) == code)
            #expect(AwtKeyCodes.deadKeyTable[char] == code, "\(row[1])")
            let event = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "x",
                                    deadKeyCharacter: char)
            #expect(AwtKeyCodes.translate(event) == AwtKeyStroke(vk: code, location: 0, modifiers: 0, phase: .pressed))
        }
    }

    @Test func modifierTableMatchesJdk21() throws {
        let rows = try Self.rows("MODIFIER")
        #expect(rows.count == AwtKeyCodes.modifierKeys.count)
        for (row, key) in zip(rows, AwtKeyCodes.modifierKeys) {
            #expect(UInt(try Self.hex(row[2])) == key.mask, "\(row[1])")
            #expect(UInt16(row[3]) == key.left)
            #expect(UInt16(row[4]) == key.right)
            #expect(Int32(row[6]) == key.vk)
            #expect(AwtKeyCodes.code(named: row[5]) == key.vk)
        }
    }

    @Test func rulesMatchJdk21() throws {
        let rules = try Self.rows("RULE")
        let byName = Dictionary(uniqueKeysWithValues: rules.map { ($0[1], Array($0.dropFirst(2))) })
        #expect(byName["LETTER_EXTENDED_BASE"] == ["0x01000000"])
        #expect(AwtKeyCodes.extendedLetterBase == 0x0100_0000)
        #expect(byName["LETTER_EXTENDED_ADD"] == ["32"])
        #expect(byName["NUMPAD_KVK_EXCLUSIVE"] == ["81", "93"])
        #expect(byName["NUMPAD_FLAG"] == ["0x200000"])
        #expect(AwtKeyCodes.macNumericPadFlag == 0x200000)
    }

    // MARK: - Character branch

    private static func vk(_ kvk: UInt16, _ chars: String, flags: UInt = 0) -> Int32? {
        let event = MacKeyEvent(kind: .keyDown, keyCode: kvk, characters: chars, charactersIgnoringModifiers: chars,
                                modifierFlags: flags)
        return AwtKeyCodes.translate(event)?.vk
    }

    private static let shift: UInt = AwtKeyCodes.macShiftFlag

    @Test func czechQwertz() {
        #expect(Self.vk(0x06, "y") == 89) // US Z position types y → VK_Y
        #expect(Self.vk(0x10, "z") == 90) // US Y position types z → VK_Z
        // Top row "+ěščřžýáíé": "+" is positional VK_1, the letters get extended codes.
        let row: [(UInt16, String, Int32)] = [
            (0x12, "+", 49), (0x13, "ě", 0x0100_011B), (0x14, "š", 0x0100_0161), (0x15, "č", 0x0100_010D),
            (0x17, "ř", 0x0100_0159), (0x16, "ž", 0x0100_017E), (0x1A, "ý", 0x0100_00FD), (0x1C, "á", 0x0100_00E1),
            (0x19, "í", 0x0100_00ED), (0x1D, "é", 0x0100_00E9),
        ]
        for (kvk, char, code) in row {
            #expect(Self.vk(kvk, char) == code, "\(char)")
        }
        // With Shift the same keys type digits → VK_1…VK_0.
        #expect(Self.vk(0x12, "1", flags: Self.shift) == 49)
        #expect(Self.vk(0x13, "2", flags: Self.shift) == 50)
        #expect(Self.vk(0x1D, "0", flags: Self.shift) == 48)
        // "ů" on the US ";" key is an extended code, Shift ('"') falls back to VK_SEMICOLON.
        #expect(Self.vk(0x29, "ů") == 0x0100_016F)
        #expect(Self.vk(0x29, "\"", flags: Self.shift) == AwtKeyCodes.vkSemicolon)
        // "§" on the US "'" key is not a letter → VK_QUOTE.
        #expect(Self.vk(0x27, "§") == AwtKeyCodes.vkQuote)
        // tolower in the C locale folds only A–Z: "Ů" keeps its own code.
        #expect(Self.vk(0x29, "Ů", flags: Self.shift) == 0x0100_016E)
        #expect(Self.vk(0x00, "A", flags: Self.shift) == 65)
    }

    @Test func germanQwertz() {
        #expect(Self.vk(0x06, "y") == 89)
        #expect(Self.vk(0x10, "z") == 90)
        #expect(Self.vk(0x29, "ö") == 0x0100_00F6)
        #expect(Self.vk(0x27, "ä") == 0x0100_00E4)
        #expect(Self.vk(0x21, "ü") == 0x0100_00FC)
        #expect(Self.vk(0x1B, "ß") == 0x0100_00DF)
        #expect(Self.vk(0x2C, "-") == AwtKeyCodes.fromMac(keyCode: 0x2C)) // positional VK_SLASH
    }

    @Test func frenchAzerty() {
        #expect(Self.vk(0x00, "q") == 81)
        #expect(Self.vk(0x0C, "a") == 65)
        #expect(Self.vk(0x0D, "z") == 90)
        #expect(Self.vk(0x06, "w") == 87)
        #expect(Self.vk(0x29, "m") == 77)
        // "," sits on the US M key and is not a letter → positional VK_M.
        #expect(Self.vk(0x2E, ",") == 77)
        #expect(Self.vk(0x12, "&") == 49)
        #expect(Self.vk(0x12, "1", flags: Self.shift) == 49)
        #expect(Self.vk(0x13, "é") == 0x0100_00E9)
    }

    @Test func usLettersAndDigitsEqualThePositionalTable() {
        let letters: [(UInt16, String)] = [
            (0x00, "a"), (0x0B, "b"), (0x08, "c"), (0x02, "d"), (0x0E, "e"), (0x03, "f"), (0x05, "g"), (0x04, "h"),
            (0x22, "i"), (0x26, "j"), (0x28, "k"), (0x25, "l"), (0x2E, "m"), (0x2D, "n"), (0x1F, "o"), (0x23, "p"),
            (0x0C, "q"), (0x0F, "r"), (0x01, "s"), (0x11, "t"), (0x20, "u"), (0x09, "v"), (0x0D, "w"), (0x07, "x"),
            (0x10, "y"), (0x06, "z"), (0x12, "1"), (0x1D, "0"), (0x29, ";"), (0x27, "'"), (0x18, "="),
        ]
        for (kvk, char) in letters {
            #expect(Self.vk(kvk, char) == AwtKeyCodes.fromMac(keyCode: kvk), "\(char)")
            if char >= "a" && char <= "z" {
                #expect(Self.vk(kvk, char.uppercased(), flags: Self.shift) == AwtKeyCodes.fromMac(keyCode: kvk))
            }
        }
    }

    @Test func numericKeypad() {
        let pad: UInt = AwtKeyCodes.macNumericPadFlag
        let one = MacKeyEvent(kind: .keyDown, keyCode: 0x53, characters: "1", charactersIgnoringModifiers: "1",
                              modifierFlags: pad)
        #expect(AwtKeyCodes.translate(one) == AwtKeyStroke(vk: 97, location: 4, modifiers: 0, phase: .pressed))
        #expect(Self.vk(0x5C, "9", flags: pad) == 105)
        #expect(Self.vk(0x53, "1") == 49) // no numeric-pad flag → VK_1
        #expect(Self.vk(0x12, "1", flags: pad) == 49) // flag outside 81 < kVK < 93
        let enter = MacKeyEvent(kind: .keyDown, keyCode: 0x4C, characters: "\u{03}", charactersIgnoringModifiers: "\u{03}",
                                modifierFlags: pad)
        #expect(AwtKeyCodes.translate(enter) == AwtKeyStroke(vk: 10, location: 4, modifiers: 0, phase: .pressed))
        #expect(Self.vk(0x41, ".", flags: pad) == 110) // VK_DECIMAL
        #expect(Self.vk(0x51, "=", flags: pad) == AwtKeyCodes.vkEquals)
    }

    @Test func altWithDeadKey() {
        let option: UInt = AwtKeyCodes.macOptionFlag
        // US Option+E is a dead acute: no characters, the layout gives "´" → VK_DEAD_ACUTE, location UNKNOWN.
        let dead = MacKeyEvent(kind: .keyDown, keyCode: 0x0E, characters: "", charactersIgnoringModifiers: "e",
                               modifierFlags: option, deadKeyCharacter: 0x00B4)
        #expect(AwtKeyCodes.translate(dead) == AwtKeyStroke(vk: 129, location: 0, modifiers: 512, phase: .pressed))
        // Czech Option+E types "€": the VK comes from "e".
        let euro = MacKeyEvent(kind: .keyDown, keyCode: 0x0E, characters: "€", charactersIgnoringModifiers: "e",
                               modifierFlags: option)
        #expect(AwtKeyCodes.translate(euro) == AwtKeyStroke(vk: 69, location: 1, modifiers: 512, phase: .pressed))
        // Czech dead keys: "´" and Shift "ˇ" on the US "=" key.
        let acute = MacKeyEvent(kind: .keyUp, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "´",
                                deadKeyCharacter: 0x00B4)
        #expect(AwtKeyCodes.translate(acute) == AwtKeyStroke(vk: 129, location: 0, modifiers: 0, phase: .released))
        let caron = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "ˇ",
                                modifierFlags: Self.shift, deadKeyCharacter: 0x02C7)
        #expect(AwtKeyCodes.translate(caron)?.vk == 138)
        // A dead key whose character is not in the table: JDK delivers no event.
        let unknown = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "x",
                                  deadKeyCharacter: 0x0041)
        #expect(AwtKeyCodes.translate(unknown) == nil)
        let none = MacKeyEvent(kind: .keyDown, keyCode: 0x18, characters: "", charactersIgnoringModifiers: "x")
        #expect(AwtKeyCodes.translate(none) == nil)
        // Czech Option+M and Option+O type nothing and are no dead keys: still Alt+M / Alt+O (Mark, Store).
        let altM = MacKeyEvent(kind: .keyDown, keyCode: 0x2E, characters: "", charactersIgnoringModifiers: "m",
                               modifierFlags: option)
        #expect(AwtKeyCodes.translate(altM) == AwtKeyStroke(vk: 77, location: 1, modifiers: 512, phase: .pressed))
        let altO = MacKeyEvent(kind: .keyUp, keyCode: 0x1F, characters: "", charactersIgnoringModifiers: "o",
                               modifierFlags: option)
        #expect(AwtKeyCodes.translate(altO) == AwtKeyStroke(vk: 79, location: 1, modifiers: 512, phase: .released))
        #expect(AwtKeyCodes.translateForLayout(altM)?.vk == 77)
        // `nil` characters is not a dead key.
        let noChars = MacKeyEvent(kind: .keyDown, keyCode: 0x0E, characters: nil, charactersIgnoringModifiers: "e")
        #expect(AwtKeyCodes.translate(noChars)?.vk == 69)
    }

    @Test func functionAndPageKeysAreUnchangedAgainstThePositionalTable() throws {
        let fKeys: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (index, kvk) in fKeys.enumerated() {
            let scalar = try #require(Unicode.Scalar(UInt32(0xF704 + index)))
            let char = String(Character(scalar))
            let flags: UInt = 1 << 23 // NSEvent.ModifierFlags.function
            let stroke = AwtKeyCodes.translate(
                MacKeyEvent(kind: .keyDown, keyCode: kvk, characters: char, charactersIgnoringModifiers: char, modifierFlags: flags))
            #expect(stroke == AwtKeyStroke(vk: AwtKeyCodes.vkF1 + Int32(index), location: 1, modifiers: 0, phase: .pressed))
            #expect(AwtKeyCodes.fromMac(keyCode: kvk) == AwtKeyCodes.vkF1 + Int32(index))
        }
        #expect(Self.vk(0x74, "\u{F72C}") == AwtKeyCodes.vkPageUp)
        #expect(Self.vk(0x79, "\u{F72D}") == AwtKeyCodes.vkPageDown)
        #expect(Self.vk(0x7E, "\u{F700}") == AwtKeyCodes.vkUp)
        #expect(Self.vk(0x7D, "\u{F701}") == AwtKeyCodes.vkDown)
        #expect(Self.vk(0x24, "\r") == AwtKeyCodes.vkEnter)
        #expect(Self.vk(0x35, "\u{1B}") == AwtKeyCodes.vkEscape)
        #expect(Self.vk(0x30, "\u{19}", flags: Self.shift) == AwtKeyCodes.vkTab) // Shift+Tab types back-tab
        #expect(Self.vk(0x31, " ") == AwtKeyCodes.vkSpace)
        // Empty characters → CHAR_UNDEFINED → positional.
        #expect(AwtKeyCodes.translate(MacKeyEvent(kind: .keyDown, keyCode: 0x7A))?.vk == AwtKeyCodes.vkF1)
        // kVK beyond the table → VK_UNDEFINED, location UNKNOWN.
        #expect(AwtKeyCodes.translate(MacKeyEvent(kind: .keyDown, keyCode: 0x80))
            == AwtKeyStroke(vk: 0, location: 0, modifiers: 0, phase: .pressed))
    }

    @Test func phaseRepeatAndModifiers() {
        let all: UInt = AwtKeyCodes.macShiftFlag | AwtKeyCodes.macControlFlag | AwtKeyCodes.macOptionFlag
            | AwtKeyCodes.macCommandFlag
        let down = MacKeyEvent(kind: .keyDown, keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r",
                               modifierFlags: all, isARepeat: true)
        let stroke = AwtKeyCodes.translate(down)
        #expect(stroke == AwtKeyStroke(vk: 10, location: 1, modifiers: 64 | 128 | 256 | 512, phase: .pressed, isRepeat: true))
        let up = MacKeyEvent(kind: .keyUp, keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r")
        #expect(AwtKeyCodes.translate(up) == AwtKeyStroke(vk: 10, location: 1, modifiers: 0, phase: .released))
    }

    // MARK: - flagsChanged

    private static func flags(_ kvk: UInt16, from previous: UInt, to current: UInt) -> AwtKeyStroke? {
        AwtKeyCodes.translate(MacKeyEvent(kind: .flagsChanged, keyCode: kvk, modifierFlags: current,
                                          previousModifierFlags: previous))
    }

    @Test func modifierKeysWithLocation() {
        let s = AwtKeyCodes.macShiftFlag
        let c = AwtKeyCodes.macControlFlag
        let m = AwtKeyCodes.macCommandFlag
        let a = AwtKeyCodes.macOptionFlag
        let device: UInt = 0x2 // NX_DEVICELSHIFTKEYMASK, ignored
        #expect(Self.flags(56, from: 0, to: s | device) == AwtKeyStroke(vk: 16, location: 2, modifiers: 64, phase: .pressed))
        #expect(Self.flags(56, from: s | device, to: 0) == AwtKeyStroke(vk: 16, location: 2, modifiers: 0, phase: .released))
        #expect(Self.flags(60, from: 0, to: s) == AwtKeyStroke(vk: 16, location: 3, modifiers: 64, phase: .pressed))
        #expect(Self.flags(59, from: 0, to: c) == AwtKeyStroke(vk: 17, location: 2, modifiers: 128, phase: .pressed))
        #expect(Self.flags(62, from: c, to: 0) == AwtKeyStroke(vk: 17, location: 3, modifiers: 0, phase: .released))
        #expect(Self.flags(55, from: 0, to: m) == AwtKeyStroke(vk: 157, location: 2, modifiers: 256, phase: .pressed))
        #expect(Self.flags(54, from: 0, to: m) == AwtKeyStroke(vk: 157, location: 3, modifiers: 256, phase: .pressed))
        #expect(Self.flags(58, from: 0, to: a) == AwtKeyStroke(vk: 18, location: 2, modifiers: 512, phase: .pressed))
        #expect(Self.flags(58, from: a, to: 0) == AwtKeyStroke(vk: 18, location: 2, modifiers: 0, phase: .released))
        // Shift held while Control goes down: only Control changed.
        #expect(Self.flags(59, from: s, to: s | c) == AwtKeyStroke(vk: 17, location: 2, modifiers: 192, phase: .pressed))
    }

    @Test func rightOptionIsAlwaysAPressedStandardAlt() {
        let a = AwtKeyCodes.macOptionFlag
        #expect(Self.flags(61, from: 0, to: a) == AwtKeyStroke(vk: 18, location: 1, modifiers: 512, phase: .pressed))
        #expect(Self.flags(61, from: a, to: 0) == AwtKeyStroke(vk: 18, location: 1, modifiers: 0, phase: .pressed))
    }

    @Test func capsLockHelpAndUnknownChanges() {
        let caps = AwtKeyCodes.macCapsLockFlag
        #expect(Self.flags(57, from: 0, to: caps) == AwtKeyStroke(vk: 20, location: 1, modifiers: 0, phase: .pressed))
        #expect(Self.flags(57, from: caps, to: 0) == AwtKeyStroke(vk: 20, location: 1, modifiers: 0, phase: .released))
        #expect(Self.flags(0x72, from: 0, to: AwtKeyCodes.macHelpFlag)?.vk == 156)
        // Only Fn (1 << 23) changed: VK_UNDEFINED, UNKNOWN, pressed — JDK still delivers it.
        #expect(Self.flags(63, from: 0, to: 1 << 23) == AwtKeyStroke(vk: 0, location: 0, modifiers: 0, phase: .pressed))
        // The first changed row in table order wins; a kVK of another key gives STANDARD.
        let s = AwtKeyCodes.macShiftFlag
        let c = AwtKeyCodes.macControlFlag
        #expect(Self.flags(59, from: 0, to: s | c) == AwtKeyStroke(vk: 16, location: 1, modifiers: 192, phase: .pressed))
    }
}
