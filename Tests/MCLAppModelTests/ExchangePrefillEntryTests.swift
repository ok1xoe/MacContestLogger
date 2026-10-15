import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM ARRL DX: a W/VE station working DX gets the DX station's default power in the empty Power field when the
/// space bar leaves the call field; a typed power is never replaced. The table is the definition's `prefill`.
@MainActor @Suite struct ExchangePrefillEntryTests {

    static let definition = """
        schemaVersion: 1
        id: prefill-entry-test
        metadata: { name: "Prefill entry test" }
        bands: [20m]
        modes: [CW]
        stationClasses:
          - { id: wve, when: { entityIn: [291, 1] } }
          - { id: dx,  when: { not: { entityIn: [291, 1] } } }
        exchange:
          sent:
            - { id: rst, type: RST, source: AUTO_RST }
          received:
            - { id: rst, type: RST, required: true }
            - { id: power, type: TEXT, required: true, appliesWhen: { workedClass: dx },
                prefill: [ { when: { entityIn: [230] }, value: "200" }, { value: "100" } ] }
        scoring: { qsoPoints: { mode: FIRST_MATCH, default: 1, rules: [] }, total: "qsoPoints" }
        dupe: { scope: PER_BAND }
        """

    static func app() async throws -> TestApp {
        let app = try await TestApp.make { config, dataDir in
            // The fixture definitions plus the test one, in a copy (the fixture corpus stays as it is).
            let copy: URL = dataDir.deletingLastPathComponent().appendingPathComponent("contest-data")
            try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
            try Data(Self.definition.utf8).write(to: copy.appendingPathComponent("contests/prefill-entry-test.yaml"))
            config.contestDataDir = copy.path
            config.station.call = "K1AR"
        }
        let started: Bool = await app.model.contest.createAndStart(definitionId: "prefill-entry-test",
                                                                   setup: ContestSetup())
        try #require(started, "activation failed: \(app.model.status.message)")
        return app
    }

    @Test func theSpaceBarFillsTheDefaultPower() async throws {
        let app = try await Self.app()
        let entry: EntryModel = app.model.entry
        entry.callChanged("DL1ABC")
        entry.jumpToExchange()
        #expect(entry.form.contestExchange["power"] == "200")

        entry.wipe()
        entry.callChanged("OK1AB")
        entry.jumpToExchange()
        #expect(entry.form.contestExchange["power"] == "100")
    }

    @Test func aTypedPowerStays() async throws {
        let app = try await Self.app()
        let entry: EntryModel = app.model.entry
        entry.callChanged("DL1ABC")
        entry.editContestField("power", "KW")
        entry.jumpToExchange()
        #expect(entry.form.contestExchange["power"] == "KW")
    }

    @Test func aWveStationHasNothingToFill() async throws {
        let app = try await Self.app()
        let entry: EntryModel = app.model.entry
        entry.callChanged("W1AW")
        entry.jumpToExchange()
        #expect(entry.form.contestExchange["power"] == nil)
    }
}
