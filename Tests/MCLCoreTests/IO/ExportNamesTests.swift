import Foundation
import Testing
@testable import MCLCore

/// `ExportNames` against the real Kotlin `AppState.cabrilloFileName()` of v1.1.1, called via reflection
/// (maintainer-only probe, rows `CAB`; Kotlin `trim`/`isBlank`/`uppercase`).
@Suite struct ExportNamesTests {

    private static let yaml = """
        schemaVersion: 1
        id: cq-ww-cw
        metadata: { name: "CQ WW CW" }
        bands: [20m]
        modes: [CW]
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        cabrillo: { contestName: CQ-WW-CW, sentOrder: [rst], receivedOrder: [rst] }

        """

    /// `"<nodef>"` = no definition, `"<nocab>"` = definition without a `cabrillo` block, `nil` = no name.
    private static func definition(_ name: String?) throws -> ContestDefinition? {
        if name == "<nodef>" {
            return nil
        }
        var def = try ContestDefinitionLoader.load(Data(yaml.utf8))
        if name == "<nocab>" {
            def.cabrillo = nil
        } else {
            def.cabrillo?.contestName = name
        }
        return def
    }

    /// (contest name, station call, expected) — measured on JDK 21 + kotlin-stdlib 2.1.20.
    private static let measured: [(String?, String, String)] = [
        ("<nodef>", "", "log.log"),
        ("<nodef>", " ", "log.log"),
        ("<nodef>", "ok1xoe", "OK1XOE.log"),
        ("<nodef>", " OK1XOE ", "OK1XOE.log"),
        ("<nodef>", "ok1xoe/p", "OK1XOE_P.log"),
        ("<nodef>", "/", "_.log"),
        ("<nodef>", "//", "__.log"),
        ("<nodef>", "\u{00A0}", "log.log"),
        ("<nodef>", "\u{00A0}ok1xoe\u{00A0}", "OK1XOE.log"),
        ("<nodef>", "\u{0001}ok1\u{0001}", "\u{0001}OK1\u{0001}.log"),
        ("<nodef>", "\u{2007}", "log.log"),
        ("<nodef>", "\u{3000}ok1\u{3000}", "OK1.log"),
        ("<nodef>", "straße", "STRASSE.log"),
        ("<nodef>", "\u{01C6}1", "\u{01C4}1.log"),
        ("<nodef>", "i1abc", "I1ABC.log"),
        ("<nodef>", "ok1xoe\t", "OK1XOE.log"),
        ("<nodef>", "ok\u{00A0}/1", "OK\u{00A0}_1.log"),
        ("<nocab>", "ok1xoe/p", "OK1XOE_P.log"),
        (nil, "ok1xoe", "OK1XOE.log"),
        ("", "ok1xoe", "OK1XOE.log"),
        (" ", "ok1xoe", "OK1XOE.log"),
        ("\u{00A0}", "ok1xoe", "OK1XOE.log"),
        ("CQ-WW-CW", "", "log-CQ-WW-CW.log"),
        ("CQ-WW-CW", "ok1xoe/p", "OK1XOE_P-CQ-WW-CW.log"),
        ("CQ-WW-CW", "\u{0001}ok1\u{0001}", "\u{0001}OK1\u{0001}-CQ-WW-CW.log"),
        (" CQ WW ", "ok1xoe", "OK1XOE-CQ WW.log"),
        ("\u{00A0}X\u{00A0}", "ok1xoe", "OK1XOE-X.log"),
        ("cq/ww", "ok1xoe", "OK1XOE-cq/ww.log"),
        ("cq/ww", "/", "_-cq/ww.log"),
        ("\u{0001}A\u{0001}", "ok1xoe", "OK1XOE-\u{0001}A\u{0001}.log"),
        ("\u{0001}A\u{0001}", "\u{3000}ok1\u{3000}", "OK1-\u{0001}A\u{0001}.log"),
    ]

    @Test func cabrilloFileNameMatchesKotlin() throws {
        for (name, call, expected) in Self.measured {
            let def = try Self.definition(name)
            let actual = ExportNames.cabrilloFileName(stationCall: call, definition: def)
            #expect(actual.utf16.elementsEqual(expected.utf16), "\(String(describing: name)) / \(call) → \(actual)")
        }
    }

    @Test func adifDefaultName() {
        #expect(ExportNames.adifDefaultName == "maccontestlogger.adi")
    }
}
