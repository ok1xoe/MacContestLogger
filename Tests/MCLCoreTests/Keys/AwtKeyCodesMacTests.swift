import Foundation
import Testing
@testable import MCLCore

/// `AwtKeyCodes.fromMac` against the `keyTable` of JDK 21 `AWTEvent.m` (`Fixtures/awt-mac-keycodes-jdk21.tsv`,
/// a maintainer-only probe) and the modifier masks against JDK 21 `InputEvent`
/// (maintainer-only probe, rows `MASK`).
@Suite struct AwtKeyCodesMacTests {

    private struct Row {
        let kvk: UInt16
        let name: String
        let code: Int32
    }

    private static func fixture() throws -> [Row] {
        let url = try #require(Bundle.module.url(forResource: "awt-mac-keycodes-jdk21", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [Row] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            try #require(cols.count == 3, "\(line)")
            let kvk = try #require(UInt16(cols[0].dropFirst(2), radix: 16))
            let code = try #require(Int32(cols[2]))
            rows.append(Row(kvk: kvk, name: String(cols[1]), code: code))
        }
        return rows
    }

    @Test func all128MacKeyCodesMatchJdk21() throws {
        let rows = try Self.fixture()
        #expect(rows.count == 128)
        for (index, row) in rows.enumerated() {
            #expect(Int(row.kvk) == index)
            // The VK name in the fixture resolves to the same code in the JDK 21 VK table.
            #expect(AwtKeyCodes.code(named: row.name) == row.code, "\(row.name)")
            let expected: Int32? = row.code == 0 ? nil : row.code
            #expect(AwtKeyCodes.fromMac(keyCode: row.kvk) == expected, "kVK \(row.kvk) \(row.name)")
        }
        #expect(rows.filter { $0.code == 0 }.count == 15)
    }

    @Test func outsideTheTableIsNil() {
        #expect(AwtKeyCodes.fromMac(keyCode: 128) == nil)
        #expect(AwtKeyCodes.fromMac(keyCode: 0xFFFF) == nil)
    }

    @Test func knownKeys() {
        #expect(AwtKeyCodes.fromMac(keyCode: 0x24) == 10) // Return → VK_ENTER
        #expect(AwtKeyCodes.fromMac(keyCode: 0x4C) == 10) // keypad Enter → VK_ENTER
        #expect(AwtKeyCodes.fromMac(keyCode: 0x35) == 27) // Escape
        #expect(AwtKeyCodes.fromMac(keyCode: 0x30) == 9) // Tab
        #expect(AwtKeyCodes.fromMac(keyCode: 0x31) == 32) // Space
        #expect(AwtKeyCodes.fromMac(keyCode: 0x7A) == 112) // F1
        #expect(AwtKeyCodes.fromMac(keyCode: 0x37) == AwtKeyCodes.vkMeta) // left Command
        // keyTable entry of the right Command is VK_UNDEFINED; its real key events come from
        // `NsKeyModifiersToJavaKeyInfo` (flagsChanged), which the table does not model.
        #expect(AwtKeyCodes.fromMac(keyCode: 0x36) == nil)
        #expect(AwtKeyCodes.fromMac(keyCode: 0x3F) == nil) // fn
    }

    @Test func modifierMasksMatchJdk21() {
        #expect(AwtKeyCodes.shiftDownMask == 64)
        #expect(AwtKeyCodes.ctrlDownMask == 128)
        #expect(AwtKeyCodes.metaDownMask == 256)
        #expect(AwtKeyCodes.altDownMask == 512)
    }

    /// Raw bits of `NSEvent.ModifierFlags` (AppKit `NSEventModifierFlag*`), written out because the core has no AppKit.
    @Test func modifiersFromMacFlags() {
        #expect(AwtKeyCodes.macShiftFlag == 0x2_0000)
        #expect(AwtKeyCodes.macControlFlag == 0x4_0000)
        #expect(AwtKeyCodes.macOptionFlag == 0x8_0000)
        #expect(AwtKeyCodes.macCommandFlag == 0x10_0000)
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0) == 0)
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x4_0000) == 128) // Control → Ctrl
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x8_0000) == 512) // Option → Alt
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x2_0000) == 64) // Shift
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x10_0000) == 256) // Command → Meta
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x1E_0000) == 960)
        // Caps Lock (1 << 16), numeric pad (1 << 21), help (1 << 22), function (1 << 23) and device bits are ignored.
        #expect(AwtKeyCodes.modifiers(fromMacFlags: 0x01E1_0000 | 0x0000_0108) == 0)
    }
}
