import Foundation
import Testing
@testable import MCLCore

/// `DxccMultiplierSet` against Java. The expected values were measured by the `ProbeSets` probe
/// with the same fake resolver (Java anonymous `DxccLookup`).
@Suite struct DxccMultiplierSetTests {

    /// `adifDxcc` deliberately different from `entityCode`: the set key is `entityCode`.
    static let czech = DxccEntity(
        entityCode: 503, name: "Czech Republic", countryCode: "CZ", continents: ["EU"],
        cq: [15], itu: [28], lat: 50, lon: 15, primaryPrefix: "OK", adifDxcc: 999)
    static let allNull = DxccEntity(
        entityCode: 7, name: nil, countryCode: nil, continents: nil,
        cq: nil, itu: nil, lat: 0, lon: 0, primaryPrefix: nil, adifDxcc: nil)
    static let canada = DxccEntity(
        entityCode: 1, name: "Canada", countryCode: "CA", continents: ["NA", "EU"],
        cq: [], itu: [], lat: 0, lon: 0, primaryPrefix: "VE", adifDxcc: 1)
    /// The same `entityCode` as `czech` — overwrites it at its position.
    static let duplicate = DxccEntity(
        entityCode: 503, name: "Dup", countryCode: "XX", continents: [],
        cq: [], itu: [], lat: 0, lon: 0, primaryPrefix: "X", adifDxcc: 1)

    struct Lookup: DxccLookup {
        func resolve(_ callsign: String?) -> DxccEntity? {
            guard let callsign, callsign.hasPrefix("OK") else { return nil }
            return DxccMultiplierSetTests.czech
        }

        func entities() -> [DxccEntity] {
            [DxccMultiplierSetTests.czech, DxccMultiplierSetTests.allNull,
             DxccMultiplierSetTests.canada, DxccMultiplierSetTests.duplicate]
        }
    }

    let set = DxccMultiplierSet(id: "dxcc", resolver: Lookup())

    @Test func enumeratesEntitiesByEntityCode() {
        #expect(set.id == "dxcc")
        #expect(set.enumerable)
        // Java: [503 → Dup (overwritten in place), 7 → null, 1 → Canada]
        #expect(set.values == [
            MultiplierValue(key: "503", label: "Dup",
                            attributes: ["countryCode": "XX", "prefix": "X", "continent": ""]),
            MultiplierValue(key: "7", label: nil,
                            attributes: ["countryCode": "", "prefix": "", "continent": ""]),
            MultiplierValue(key: "1", label: "Canada",
                            attributes: ["countryCode": "CA", "prefix": "VE", "continent": "NA"]),
        ])
    }

    /// Without normalisation: `"0503"` and `" 503"` are not `"503"`; `"999"` is
    /// `adifDxcc`, not the key.
    @Test(arguments: [
        ("503", true), ("0503", false), (" 503", false), ("7", true), ("1", true),
        ("999", false),
    ])
    func isExpectedWithoutNormalization(_ key: String, _ expected: Bool) {
        #expect(set.isExpected(key) == expected)
    }

    @Test func isExpectedNilIsFalse() {
        #expect(set.isExpected(nil) == false)
    }

    @Test(arguments: [
        ("OK1XOE" as String?, Resolution.valid("503")),
        ("DL1ABC", .invalid("neznámá DXCC entita: DL1ABC")),
        (nil, .invalid("neznámá DXCC entita: null")),
        ("", .invalid("neznámá DXCC entita: ")),
        (" ", .invalid("neznámá DXCC entita:  ")),
    ])
    func deriveFromCallsign(_ callsign: String?, _ expected: Resolution) {
        #expect(set.deriveFromCallsign(callsign) == expected)
        // the country is derived from the callsign, never from the exchange field
        #expect(set.normalize(callsign) == .unsupported)
    }
}
