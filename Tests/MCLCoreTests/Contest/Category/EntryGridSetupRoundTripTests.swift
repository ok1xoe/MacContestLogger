import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `EntryGridSetupRoundTripTest`: setup (SSB/20M) → JSON → `ContestStore`
/// → back → `EntryGridPolicy`.
@Suite struct EntryGridSetupRoundTripTests {

    @Test func ssb20mSurvivesStoreRoundTripAndYieldsPhOnly() throws {
        let config = ConfigStore(file: URL(fileURLWithPath: "/tmp/unused-entrygrid-test.json"))

        // Setup as from NewContestWindow: MODE=SSB, BAND=20M
        var setup = ContestSetup()
        setup.category = ["MODE": "SSB", "BAND": "20M"]
        let setupJson = config.toJSON(setup)

        // Save to the DB snapshot (as createAndStartContest)
        let store = try ContestStore(try LogbookRepository.inMemory())
        let contestId = "test-contest-id"
        try store.insert(ContestStore.ContestRow(
            contestId: contestId, definitionId: "cq-ww-ssb", name: "Test", startedAt: nil, endedAt: nil,
            definitionYaml: "bands: [20m]\nmodes: [SSB]", setupJson: setupJson, stationJson: "{}"))

        // Load back (as activeContestSetup)
        let backJson = try #require(try store.find(contestId)).setupJson
        let back = try #require(config.fromJSON(backJson, as: ContestSetup.self),
                                "deserialized setup must not be nil")

        let modeCategory = back.category["MODE"]
        let bandCategory = back.category["BAND"]
        #expect(modeCategory == "SSB")
        #expect(bandCategory == "20M")

        // Policy: PH column only, 20m band only
        #expect(EntryGridPolicy.columnsFor(modeCategory, ["SSB"]) == [.PH])
        #expect(EntryGridPolicy.bandsFor(bandCategory, ["20m"]) == [.m20])
    }
}
