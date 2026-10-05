import Foundation
import Testing
@testable import MCLCore

/// `WpxMultiplierSet` against Java. The expected values were measured by the `ProbeSets` probe.
///
/// A note in the Java sources warns that `PrefixExtractor.wpx` may return
/// `""` and the set then `VALID("")`. In reality this is **unreachable**:
/// `wpx` returns `""` only for `null`/blank input and the set rejects that earlier
/// (`INVALID("prázdná volačka")`); otherwise `prefixOf` always returns something (`"/"` →
/// `"0"`). The tests therefore pin the measured behaviour, not `VALID("")`.
@Suite struct WpxMultiplierSetTests {

    let set = WpxMultiplierSet(id: "wpx_prefixes")

    @Test func isOpenSet() {
        #expect(set.id == "wpx_prefixes")
        #expect(set.enumerable == false)
        #expect(set.values.isEmpty)
        #expect(set.isExpected(nil))
        #expect(set.isExpected(""))
        #expect(set.isExpected("cokoli"))
    }

    @Test(arguments: [
        ("ok1" as String?, Resolution.valid("OK1")),
        (" ok1 ", .valid("OK1")),
        ("", .invalid("prázdný prefix")),
        ("  ", .invalid("prázdný prefix")),
        (nil, .invalid("prázdný prefix")),
        ("\u{2003}", .invalid("prázdný prefix")),
        ("\u{A0}ok1", .valid("\u{A0}OK1")),      // trim does not strip NBSP
        ("straße", .valid("STRASSE")),
    ])
    func normalizeWithoutShapeCheck(_ raw: String?, _ expected: Resolution) {
        #expect(set.normalize(raw) == expected)
    }

    @Test(arguments: [
        ("ok1xoe/p" as String?, Resolution.valid("OK1")),
        ("OK1XOE", .valid("OK1")),
        (" ok1xoe ", .valid("OK1")),
        ("", .invalid("prázdná volačka")),
        (" ", .invalid("prázdná volačka")),
        (nil, .invalid("prázdná volačka")),
        ("/", .valid("0")),
        ("//", .valid("0")),
        ("/p", .valid("P0")),
        ("p/", .valid("P0")),
        ("abc", .valid("AB0")),
        ("\u{A0}ok1xoe", .valid("\u{A0}OK1")),
        ("123", .valid("123")),
        ("/QRP", .valid("QR0")),
    ])
    func deriveFromCallsign(_ callsign: String?, _ expected: Resolution) {
        #expect(set.deriveFromCallsign(callsign) == expected)
    }
}
