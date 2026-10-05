import Foundation
import Testing
@testable import MCLCore

/// The AWT `VK_*` table in the source (`AwtKeyCodes+Table.swift`) against a fixture from JDK 21
/// (`Fixtures/awt-vk-codes-jdk21.tsv`, maintainer-only probe).
@Suite struct AwtKeyCodesTests {

    private struct Row: Equatable {
        let index: Int
        let name: String
        let code: Int32
    }

    private static func fixture() throws -> [Row] {
        let url = try #require(Bundle.module.url(forResource: "awt-vk-codes-jdk21", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [Row] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            try #require(cols.count == 3, "\(line)")
            let index = try #require(Int(cols[0]))
            let code = try #require(Int32(cols[2]))
            rows.append(Row(index: index, name: String(cols[1]), code: code))
        }
        return rows
    }

    @Test func tableMatchesJdk21Fixture() throws {
        let expected = try Self.fixture()
        #expect(expected.count == 189)
        var actual: [Row] = []
        for (offset, entry) in AwtKeyCodes.entries.enumerated() {
            actual.append(Row(index: offset + 1, name: entry.name, code: entry.code))
        }
        #expect(actual == expected)
    }

    /// `CODES` takes all names, `NAMES` the first name of a code (`putIfAbsent`): 188 codes,
    /// the only collision 108 → `SEPARATER`.
    @Test func lookupsFollowJavaPutIfAbsent() throws {
        let rows = try Self.fixture()
        var firstName: [Int32: String] = [:]
        for row in rows {
            #expect(AwtKeyCodes.code(named: row.name) == row.code, "\(row.name)")
            if firstName[row.code] == nil { firstName[row.code] = row.name }
        }
        #expect(firstName.count == 188)
        for (code, name) in firstName {
            #expect(AwtKeyCodes.name(of: code) == name, "\(code)")
        }
        #expect(AwtKeyCodes.name(of: 108) == "SEPARATER")
        #expect(AwtKeyCodes.code(named: "SEPARATOR") == 108)
        #expect(AwtKeyCodes.code(named: "\u{212A}") == nil)
    }

    /// Named constants (`isModifierKey`, `isAllowedShortcut`) match the table.
    @Test func namedConstantsMatchTable() {
        let pairs: [(Int32, String)] = [
            (AwtKeyCodes.vkShift, "SHIFT"), (AwtKeyCodes.vkControl, "CONTROL"), (AwtKeyCodes.vkAlt, "ALT"),
            (AwtKeyCodes.vkMeta, "META"), (AwtKeyCodes.vkAltGraph, "ALT_GRAPH"), (AwtKeyCodes.vkF1, "F1"),
            (AwtKeyCodes.vkF24, "F24"), (AwtKeyCodes.vkSemicolon, "SEMICOLON"), (AwtKeyCodes.vkQuote, "QUOTE"),
            (AwtKeyCodes.vkBackSlash, "BACK_SLASH"), (AwtKeyCodes.vkBackQuote, "BACK_QUOTE"),
        ]
        for (code, name) in pairs {
            #expect(AwtKeyCodes.code(named: name) == code, "\(name)")
        }
    }
}
