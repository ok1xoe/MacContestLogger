import Foundation
import Testing
@testable import MCLCore

/// Helpers of the ported Java tests of `callhistory/`.
enum CallHistoryTestSupport {

    /// Java `new ExchangeField(id, type, true, null, null, null, null)`.
    static func field(_ id: String?, _ type: ContestDefinition.FieldType?) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil,
                                        validation: nil)
    }

    /// Java `Map.of(k, v, …)`.
    static func map(_ pairs: (String, String)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs.map { (Optional($0.0), Optional($0.1)) })
    }

    /// A temporary directory (Java `@TempDir`); deleted after the body.
    static func withTemporaryDirectory(_ body: (String) throws -> Void) throws {
        let template: String = FileManager.default.temporaryDirectory.path + "/mcl-callhistory.XXXXXX"
        var bytes: [CChar] = Array(template.utf8CString)
        guard let made = mkdtemp(&bytes) else {
            Issue.record("mkdtemp failed: \(errno)")
            return
        }
        let directory = String(cString: made)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try body(directory)
    }
}

/// Port of the Java `callhistory/CallHistoryTest` (3 tests).
@Suite struct CallHistoryTests {

    private static let file: [String] = [
        "# N1MM call history",
        "!!Order!!,Call,Name,State,CQZone,Exch1",
        "W1AW,Hiram,CT,5,",
        "ok1xoe,Tomas,,15,JN79",
        "DL1ABC,,,14,28",
    ]

    private typealias S = CallHistoryTestSupport

    @Test func parsesOrderAndLooksUpCaseInsensitive() {
        let ch = CallHistory.parse(Self.file)
        #expect(ch.size == 3)
        #expect(ch.lookup("OK1XOE")?["name"] == "Tomas")
        #expect(ch.lookup("K1XX") == nil)
    }

    @Test func prefillsByIdThenTypeThenExch1() {
        let ch = CallHistory.parse(Self.file)
        let cqww = [S.field("rst", .RST), S.field("zone", .CQ_ZONE)]
        #expect(ch.prefill("W1AW", cqww) == S.map(("zone", "5")), "by type → CQZone")

        let naqp = [S.field("name", .TEXT), S.field("state", .STATE)]
        #expect(ch.prefill("W1AW", naqp) == S.map(("name", "HIRAM"), ("state", "CT")), "by id")

        let one = [S.field("rst", .RST), S.field("nr", .SERIAL), S.field("power", .INTEGER)]
        #expect(ch.prefill("DL1ABC", one) == S.map(("power", "28")), "the only free field ← Exch1")
        #expect(ch.prefill("K1XX", cqww) == S.map())
    }

    @Test func defaultOrderWithoutHeader() {
        let ch = CallHistory.parse(["W1AW,Hiram,,,,CT"])
        #expect(ch.lookup("W1AW")?["state"] == "CT")
    }
}

/// Port of the Java `callhistory/CallHistoryReverseTest` (2 tests).
@Suite struct CallHistoryReverseTests {

    private typealias S = CallHistoryTestSupport

    private let ch = CallHistory.parse([
        "!!Order!!,Call,Name,State",
        "W1AW,Hiram,CT",
        "K1ABC,Hiram,MA",
        "N1XX,Bob,CT",
    ])
    private let naqp = [S.field("name", .TEXT), S.field("state", .STATE)]

    @Test func findsCallsMatchingAllGivenValues() {
        #expect(ch.reverse(S.map(("name", "hiram")), naqp, limit: 10) == ["K1ABC", "W1AW"])
        #expect(ch.reverse(S.map(("name", "HIRAM"), ("state", "CT")), naqp, limit: 10) == ["W1AW"])
        #expect(ch.reverse(S.map(("name", ""), ("state", "ct")), naqp, limit: 10) == ["N1XX", "W1AW"])
    }

    @Test func nothingToSearch() {
        #expect(ch.reverse(S.map(), naqp, limit: 10) == [])
        #expect(ch.reverse(S.map(("name", "Nobody")), naqp, limit: 10) == [])
        #expect(ch.reverse(S.map(("name", "Hiram")), naqp, limit: 1).count == 1)
    }
}

/// Port of the Java `callhistory/CallHistoryUpdateTest` (1 test): merging with the log and writing/reading a file.
@Suite struct CallHistoryUpdateTests {

    private typealias S = CallHistoryTestSupport

    @Test func mergesLogValuesAndRoundTrips() throws {
        try S.withTemporaryDirectory { dir in
            let ch = CallHistory.parse(["!!Order!!,Call,Name", "W1AW,Hiram"])
            let zone = S.field("zone", .CQ_ZONE)
            let name = S.field("name", .TEXT)
            #expect(ch.columnFor(zone) == "cqzone")
            #expect(ch.columnFor(name) == "name")

            let updates = JavaLinkedMap<JavaLinkedMap<String>>([
                ("W1AW", S.map(("cqzone", "5"))),
                ("ok1xoe", S.map(("cqzone", "15"), ("name", "Tomas"))),
            ])
            let updated = ch.withUpdates(updates)
            let file = dir + "/ch.txt"
            try updated.save(file)

            let back = CallHistory.load(file)
            #expect(back.size == 2)
            #expect(back.lookup("W1AW") == S.map(("call", "W1AW"), ("name", "Hiram"), ("cqzone", "5")))
            #expect(back.lookup("OK1XOE")?["cqzone"] == "15")
            #expect(updated.toLines()[1] == "!!Order!!,Call,Name,CQZone")
        }
    }
}

/// Port of the Java `callhistory/CallHistoryUpdaterTest` (1 test) over `cq-ww-ssb` from `contest-data/`.
@Suite struct CallHistoryUpdaterTests {

    static func qso(_ minute: Int, _ call: String, _ exchange: String) -> Qso {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: 1_795_867_200 + TimeInterval(60 * minute))
        q.call = call
        q.freqHz = 14_200_000
        q.mode = .ssb
        q.exchangeRcvd = exchange
        return q
    }

    @Test func takesExchangeFromLogNewestWins() throws {
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        let defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
        let def = try #require(defs.first { $0.id == "cq-ww-ssb" })
        let session = ContestSession(definition: def, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: nil)

        let updates = try CallHistoryUpdater.updates(session, [
            Self.qso(5, "W1AW", "59 5"),
            Self.qso(0, "W1AW", "59 4"),   // older — the newer zone 5 overwrites it
            Self.qso(1, "DL1ABC", "59 14"),
        ], CallHistory.empty)

        let expected = JavaLinkedMap<JavaLinkedMap<String>>([
            ("W1AW", CallHistoryTestSupport.map(("cqzone", "5"))),
            ("DL1ABC", CallHistoryTestSupport.map(("cqzone", "14"))),
        ])
        #expect(updates == expected)
    }
}
