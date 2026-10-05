import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `LogWarningsTest` (5 cases). `ScpDatabase` is replaced by a predicate over
/// a set — `analyze` calls only `contains` on it. The order of messages and keys against Java is verified by
/// `LogbookMeasuredTests`.
@Suite struct LogWarningsTests {

    typealias Field = ContestDefinition.ExchangeField

    static let cqww: [Field] = [
        Field(id: "rst", type: .RST, required: true, source: nil, appliesWhen: nil, validation: nil),
        Field(id: "zone", type: .CQ_ZONE, required: true, source: nil, appliesWhen: nil, validation: nil),
    ]
    static let wpx: [Field] = [
        Field(id: "rst", type: .RST, required: true, source: nil, appliesWhen: nil, validation: nil),
        Field(id: "nr", type: .SERIAL, required: true, source: nil, appliesWhen: nil, validation: nil),
    ]

    static func qso(_ id: Int64, _ call: String, _ exch: String) -> Qso {
        var q = Qso()
        q.id = id
        q.call = call
        q.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200 + Double(id) * 60)
        q.exchangeRcvd = exch
        return q
    }

    static func dl14(_ call: String) -> Set<Int?>? {
        call.hasPrefix("DL") ? [14] : []
    }

    static func run(_ qsos: [Qso], _ fields: [Field], _ scp: Set<String>?) -> LogWarnings.Warnings {
        let inScp: ((String) -> Bool)? = scp.map { set in { set.contains($0) } }
        return LogWarnings.analyze(qsos, receivedFields: { _ in fields }, inScp: inScp,
                                   cqZones: dl14, ituZones: { _ in [] })
    }

    @Test func exchangeDifferingAcrossBandsIsFlaggedOnBothQsos() throws {
        let w = Self.run([Self.qso(1, "K1ABC", "599 5"), Self.qso(2, "K1ABC", "579 4")], Self.cqww, nil)

        #expect(try #require(w[1]?.first).contains("zone"))
        #expect(try #require(w[2]?.first).contains("4 / 5"))
    }

    @Test func reportAndSerialChangesAreNormal() {
        #expect(Self.run([Self.qso(1, "K1ABC", "599 5"), Self.qso(2, "K1ABC", "579 5")], Self.cqww, nil).isEmpty)
        #expect(Self.run([Self.qso(1, "K1ABC", "599 12"), Self.qso(2, "K1ABC", "599 345")], Self.wpx, nil).isEmpty)
    }

    @Test func callNotInScpIsFlagged() {
        let scp: Set<String> = ["K1ABC", "DL1ABC"]

        let w = Self.run([Self.qso(1, "K1ABC", "599 5"), Self.qso(2, "K1ABX", "599 5")], Self.cqww, scp)

        #expect(!w.containsKey(1))
        #expect(w[2] == ["volačka není v master.scp"])
    }

    @Test func zoneNotMatchingCountryIsFlagged() throws {
        let w = Self.run([Self.qso(1, "DL1ABC", "599 15"), Self.qso(2, "DL2XYZ", "599 14")], Self.cqww, nil)

        #expect(try #require(w[1]?.first).hasPrefix("CQ zóna 15 nesedí k zemi (14)"))
        #expect(!w.containsKey(2))
    }

    @Test func xqsoIsIgnored() {
        var x = Self.qso(2, "K1ABC", "599 4")
        x.xqso = true

        #expect(Self.run([Self.qso(1, "K1ABC", "599 5"), x], Self.cqww, nil).isEmpty)
    }

    // MARK: - Beyond the Java tests

    /// Key order = order of the first warning; the "differ" messages are in the order of Java's `HashMap`.
    @Test func keysFollowFirstWarningThenJavaHashOrder() {
        // Measured on Java (ProbeLogbook): only "differs" → order by the HashMap of callsigns
        var log: [Qso] = []
        var id: Int64 = 100
        for call in ["ZZ9ZZ", "AA1AA", "OK1XOE", "W1AW", "DL1ABC", "K1ABC", "VE3XX"] {
            log.append(Self.qso(id, call, "599 1"))
            log.append(Self.qso(id + 1, call, "599 2"))
            id += 2
        }
        let w = LogWarnings.analyze(log, receivedFields: { _ in Self.cqww }, inScp: nil,
                                    cqZones: { _ in [] }, ituZones: { _ in [] })
        #expect(w.ids == [102, 103, 110, 111, 108, 109, 100, 101, 112, 113, 106, 107, 104, 105])
    }

    /// An error from `receivedFields` (in Swift `ContestSession.activeReceivedFields` throws) propagates
    /// out as in Java.
    @Test func receivedFieldsErrorPropagates() {
        struct Boom: Error {}
        #expect(throws: Boom.self) {
            _ = try LogWarnings.analyze([Self.qso(1, "K1ABC", "599 5")], receivedFields: { _ in throw Boom() },
                                        inScp: nil, cqZones: { _ in [] }, ituZones: { _ in [] })
        }
    }

    /// A zone set with a `null` element: Java prints a single element as "null"; with another element
    /// Java's sort crashes with an NPE — Swift is lenient (`null` first) — a deliberate
    /// divergence from Java v1.1.1.
    @Test func nullZoneElement() {
        let log = [Self.qso(1, "DL1ABC", "599 5")]
        let only = LogWarnings.analyze(log, receivedFields: { _ in Self.cqww }, inScp: nil,
                                       cqZones: { _ in [nil] }, ituZones: { _ in [] })
        #expect(only[1] == ["CQ zóna 5 nesedí k zemi (null)"])
        let mixed = LogWarnings.analyze(log, receivedFields: { _ in Self.cqww }, inScp: nil,
                                        cqZones: { _ in [7, nil, 3] }, ituZones: { _ in [] })
        #expect(mixed[1] == ["CQ zóna 5 nesedí k zemi (null/3/7)"])
        // zone in the set → no warning even with a null element
        let hit = LogWarnings.analyze(log, receivedFields: { _ in Self.cqww }, inScp: nil,
                                      cqZones: { _ in [5, nil] }, ituZones: { _ in [] })
        #expect(hit.isEmpty)
    }
}
