import Testing
@testable import MCLCore

/// A port of the Java `SpotExchangeEstimatorTest` (9 tests) over the fixture `dxcc-test.json`.
/// Edge cases measured on Java are in `GrabMeasuredTests.estimateMatchesJava`.
@Suite struct SpotExchangeEstimatorTests {

    private func dxcc() throws -> DxccResolver {
        try DxccResolver.fromData(DxccTestFixture.data())
    }

    private static func field(_ id: String, _ estimate: String?) -> ContestDefinition.ExchangeField {
        ContestDefinition.ExchangeField(id: id, type: .TEXT, required: true, source: nil,
                                        appliesWhen: nil, validation: nil, estimate: estimate)
    }

    @Test func estimatesItuZoneFromCallsign() throws {
        // OK1ABC → CZ → ITU zone 28
        let est = SpotExchangeEstimator.estimate([Self.field("exch", "ituZone")], "OK1ABC", try dxcc())
        #expect(est["exch"] == "28")
    }

    @Test func estimatesGridFromLookup() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("grid", "grid")], "OK1ABC", try dxcc(),
                                                 hqCalls: JavaLinkedMap(), gridByCall: JavaLinkedMap([("OK1ABC", "JO70")]))
        #expect(est["grid"] == "JO70")
    }

    @Test func gridWithoutLookupIsEmpty() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("grid", "grid")], "OK1ABC", try dxcc(),
                                                 hqCalls: JavaLinkedMap(), gridByCall: JavaLinkedMap())
        #expect(est["grid"] == nil)
    }

    @Test func estimatesCqZoneAndContinent() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("z", "cqZone"), Self.field("c", "continent")],
                                                 "OK1ABC", try dxcc())
        #expect(est["z"] == "15")
        #expect(est["c"] == "EU")
    }

    @Test func fieldWithoutEstimateIsIgnored() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("rst", nil), Self.field("exch", "ituZone")],
                                                 "OK1ABC", try dxcc())
        #expect(est["rst"] == nil)
        #expect(est["exch"] == "28")
    }

    @Test func unknownCallsignYieldsEmpty() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("exch", "ituZone")], "XYZ999QQ", try dxcc())
        #expect(est.isEmpty)
    }

    @Test func iaruExchHqCallGivesAbbreviation() throws {
        let hq = JavaLinkedMap<String>([("DA0HQ", "DARC")])
        let est = SpotExchangeEstimator.estimate([Self.field("exch", "iaruExch")], "DA0HQ", try dxcc(), hqCalls: hq)
        #expect(est["exch"] == "DARC")
    }

    @Test func iaruExchNonHqGivesItuZone() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("exch", "iaruExch")], "OK1ABC", try dxcc(),
                                                 hqCalls: JavaLinkedMap([("DA0HQ", "DARC")]))
        #expect(est["exch"] == "28") // OK → CZ → ITU 28
    }

    @Test func iaruExchWithoutHqMapFallsBackToZone() throws {
        let est = SpotExchangeEstimator.estimate([Self.field("exch", "iaruExch")], "OK1ABC", try dxcc(),
                                                 hqCalls: JavaLinkedMap())
        #expect(est["exch"] == "28")
    }

    // MARK: - port properties

    /// Java NPE on a `nil` element of `received` → Swift skips it (recorded leniency).
    @Test func nilElementIsSkipped() throws {
        let est = SpotExchangeEstimator.estimate([nil, Self.field("exch", "ituZone")], "OK1ABC", try dxcc())
        #expect(est["exch"] == "28")
        #expect(est.count == 1)
    }
}
