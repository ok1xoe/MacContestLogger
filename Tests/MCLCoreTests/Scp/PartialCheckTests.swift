import Testing
@testable import MCLCore

/// The Java `scp/PartialCheckTest` (3 tests).
@Suite struct PartialCheckTests {

    @Test func logAndSpotsBeatScpAtSameRank() {
        let suggestions = PartialCheck.merge("K1",
                                             logCalls: ["OK1XOE", "dl1abc"],
                                             spotCalls: ["K1ABC", "W1AW"],
                                             scpMatches: ["K1AA", "K1ABC", "OK1XOE"],
                                             limit: 10)

        #expect(suggestions == [
            PartialCheck.Suggestion(call: "K1ABC", source: .SPOT),
            PartialCheck.Suggestion(call: "K1AA", source: .SCP),
            PartialCheck.Suggestion(call: "OK1XOE", source: .LOG)])
    }

    @Test func callOnlyInLogIsSuggested() {
        let suggestions = PartialCheck.merge("OK2", logCalls: ["OK2NEW"], spotCalls: [], scpMatches: [], limit: 5)
        #expect(suggestions == [PartialCheck.Suggestion(call: "OK2NEW", source: .LOG)])
    }

    @Test func shortQueryAndLimit() {
        #expect(PartialCheck.merge("K", logCalls: ["K1A"], spotCalls: [], scpMatches: [], limit: 5) == [])
        #expect(PartialCheck.merge("K1", logCalls: ["K1A", "K1B"], spotCalls: [], scpMatches: [], limit: 1).count == 1)
    }
}
