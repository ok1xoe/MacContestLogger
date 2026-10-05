import Foundation
import Testing
@testable import MCLCore

/// Table `GrabMeasured` (maintainer-only probe, JDK 21.0.2):
/// `ExchangeGrab.normalize` (upper → trim → edges by UTF-16 units), `ExchangeGrab.route`
/// (shape of all 17 types, validation `regex` → `length` → `min`/`max`, a bad regex throws, emptiness of
/// values in `current`, `nil` id, UTF-16 keys), successive `route` over one map
/// and `SpotExchangeEstimator.estimate` (estimate kinds, `trim` of the kind, HQ/grid maps, first `null` zone).
///
/// The result is composed as in the probe: grab `id=value`, no `empty`, map `key=value;…`,
/// error `EXC PatternSyntaxException: message`; texts via `ExchangeMeasuredTests.esc`.
@Suite struct GrabMeasuredTests {

    private static func esc(_ text: String?) -> String {
        ExchangeMeasuredTests.esc(text)
    }

    private static func describe(_ grab: ExchangeGrab.Grab?) -> String {
        guard let grab else { return "empty" }
        return esc(grab.fieldId) + "=" + esc(grab.value)
    }

    private static func fields(_ inner: String?) throws -> [ContestDefinition.ExchangeField?]? {
        guard let inner else { return nil }
        return try ExchangeMeasuredTests.definition("{exchange: {received: [" + inner + "]}}").exchange?.received
    }

    private static func outcome(_ body: () throws(ExchangeError) -> String) -> String {
        do {
            return try body()
        } catch {
            return ExchangeMeasuredTests.exception(error)
        }
    }

    /// Fake `DxccLookup` with the same table as `FakeDxcc` in the probe (exact callsign).
    final class FakeDxcc: DxccLookup {
        private static func entity(_ code: Int, _ continents: [String?]?, _ cq: [Int?]?,
                                   _ itu: [Int?]?) -> DxccEntity {
            DxccEntity(entityCode: code, name: "N\(code)", countryCode: "C\(code)", continents: continents,
                       cq: cq, itu: itu, lat: .nan, lon: .nan)
        }

        let table = JavaLinkedMap<DxccEntity>([
            ("NI1A", entity(1, ["EU"], [nil, 5], [nil, 3])),
            ("EI1A", entity(2, ["EU"], [], [])),
            ("NU1A", entity(3, nil, nil, nil)),
            ("NC1A", entity(4, [nil, "EU"], [14], [28])),
            ("EC1A", entity(5, [], [14], [28])),
            ("BC1A", entity(6, [" "], [14], [28])),
            (" sp1a ", entity(7, ["EU"], [15], [29])),
        ])

        func resolve(_ callsign: String?) -> DxccEntity? {
            guard let callsign else { return nil }
            return table[callsign]
        }

        func entities() -> [DxccEntity] {
            table.entries.compactMap { $0.value }
        }
    }

    // MARK: - divergences

    /// Rows where Java fails with an NPE; Swift is lenient: a `nil` element of the fields is skipped, a field
    /// with `type == nil` accepts nothing, a `nil` id is looked up in `current` as key `nil` (Java `HashMap`,
    /// not `Map.of()`), `current` is a non-optional map (the test passes an empty one for Java `null`).
    static let lenient: [String: String] = [
        "R/bad-regex-after-null-element": "EXC PatternSyntaxException: Unclosed\\u0020group\\u0020near\\u0020index\\u00201\\u000A(",
        "R/null-element": "rst=599",
        "R/null-element-after-match": "rst=599",
        "R/null-type": "empty",
        "R/null-type-after": "rst=599",
        "R/current-null-accepting": "rst=599",
        "R/null-id-immutable": "~=599",
        "R/null-id-immutable-filled": "~=599",
        "E/null-element": "exch=28",
    ]

    /// Rows where Swift returns a different result than Java: a regex the `JavaRegex` adapter does not translate
    /// (`.unsupported`) is ignored (Java translates and uses it).
    static let divergent: [String: String] = [
        "R/regex-java-lower": "t=ABC",
        "R/regex-comments": "t=ABD",
    ]

    private static func expected(_ kind: String, _ label: String, _ java: GrabMeasured.Outcome) -> String? {
        if let swift = divergent[kind + "/" + label] {
            return swift
        }
        switch java {
        case .text(let text): return text
        case .npe: return lenient[kind + "/" + label]
        }
    }

    // MARK: - tables

    @Test(arguments: GrabMeasured.normalize)
    func normalizeMatchesJava(_ row: GrabMeasured.NormalizeRow) throws {
        let expected = try #require(Self.expected("N", row.label, row.java), "NPE row without a pinned value")
        #expect(Self.esc(ExchangeGrab.normalize(row.token)) == expected)
    }

    @Test(arguments: GrabMeasured.route)
    func routeMatchesJava(_ row: GrabMeasured.RouteRow) throws {
        let fields = try Self.fields(row.fields)
        let current = JavaLinkedMap<String>(row.current ?? [])
        let swift = Self.outcome { () throws(ExchangeError) in
            Self.describe(try ExchangeGrab.route(fields, current, row.token))
        }
        let expected = try #require(Self.expected("R", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }

    @Test(arguments: GrabMeasured.sequence)
    func sequenceMatchesJava(_ row: GrabMeasured.SequenceRow) throws {
        let fields = try Self.fields(row.fields)
        var exchange = JavaLinkedMap<String>()
        var steps: [String] = []
        for token in row.tokens {
            let grab = try ExchangeGrab.route(fields, exchange, token)
            if let grab {
                exchange.put(grab.fieldId, grab.value)
            }
            steps.append(Self.describe(grab))
        }
        let expected = try #require(Self.expected("Q", row.label, row.java), "NPE row without a pinned value")
        #expect(steps.joined(separator: ";") == expected)
    }

    @Test(arguments: GrabMeasured.estimate)
    func estimateMatchesJava(_ row: GrabMeasured.EstimateRow) throws {
        let dxcc: (any DxccLookup)?
        switch row.dxcc {
        case .fixture: dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        case .fake: dxcc = FakeDxcc()
        case .none: dxcc = nil
        }
        let result = SpotExchangeEstimator.estimate(
            try Self.fields(row.fields), row.call, dxcc,
            hqCalls: row.hq.map { JavaLinkedMap($0) },
            gridByCall: row.grid.map { JavaLinkedMap($0) })
        let swift = ExchangeMeasuredTests.map(result, Self.esc)
        let expected = try #require(Self.expected("E", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }
}
