import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM's VHF-and-up entry keys: Alt+= searches the typed call and grid in the call history (Check window), Alt+-
/// toggles the grid field through the call history's grids, and a right-click on a band button moves the last logged
/// station to that band (a local spot) or passes the typed call to the network station on that band.
@MainActor @Suite struct VhfEntryKeysTests {

    static func vhf() async throws -> TestApp {
        let app = try await TestApp.make()
        var setup = ContestSetup()
        setup.sentExchange = ["loc": "JO70FC"]
        let started: Bool = await app.model.contest.createAndStart(definitionId: "iaru-r1-vhf", setup: setup)
        try #require(started, "activation failed: \(app.model.status.message)")
        return app
    }

    static let history = CallHistory.parse([
        "!!Order!!,Call,Name,Loc1,Loc2",
        "OK1ABC,Pavel,JN79FX,JN79",
        "DL1XYZ,Hans,,",
    ])

    @Test func altMinusTogglesTheCallHistoryGridsAndTheTypedOne() async throws {
        let app = try await Self.vhf()
        let entry: EntryModel = app.model.entry
        entry.callHistory = { Self.history }
        entry.callChanged("OK1ABC")
        entry.editContestField("loc", "JO70AA")
        entry.runShortcut(.gridToggle)
        #expect(entry.form.contestExchange["loc"] == "JN79FX")
        entry.runShortcut(.gridToggle)
        #expect(entry.form.contestExchange["loc"] == "JN79")
        entry.runShortcut(.gridToggle)
        #expect(entry.form.contestExchange["loc"] == "JO70AA", "the typed grid stays in the cycle")
        entry.runShortcut(.gridToggle)
        #expect(entry.form.contestExchange["loc"] == "JN79FX")

        // Another call: the old typed grid is forgotten.
        entry.callChanged("DL1XYZ")
        entry.runShortcut(.gridToggle)
        #expect(app.model.status.message == "Call history nezná pro tuto volačku žádný lokátor")
    }

    @Test func altMinusOutsideAGridContestSaysSo() async throws {
        let app = try await TestApp.make()
        app.model.entry.runShortcut(.gridToggle)
        #expect(app.model.status.message == "Závod nemá pole lokátoru")
        app.model.entry.runShortcut(.gridSearch)
        #expect(app.model.status.message == "Závod nemá pole lokátoru")
    }

    @Test func altEqualsOpensTheCheckWindowWithTheReverseLookup() async throws {
        let app = try await Self.vhf()
        let entry: EntryModel = app.model.entry
        entry.runShortcut(.gridSearch)
        #expect(app.model.status.message == "Napiš volačku nebo lokátor, který se má hledat")
        #expect(!app.model.windows.isOpen("check"))

        app.model.config.config.checkReverseEnabled = false
        app.model.config.config.checkHiddenPanes = [CheckPane.reverse.rawValue]
        entry.editContestField("loc", "JN79")
        entry.runShortcut(.gridSearch)
        #expect(app.model.windows.isOpen("check"))
        #expect(app.model.config.config.checkReverseEnabled)
        #expect(app.model.check.visiblePanes.contains(.reverse))
        #expect(app.model.status.message == "Zpětné hledání v call history zapnuto (okno Check)")
        #expect(await app.savedConfigFlushed().checkReverseEnabled)
    }

    @Test func rightClickOnABandButtonStoresTheLastStationThere() async throws {
        let app = try await Self.vhf()
        let entry: EntryModel = app.model.entry
        entry.setFrequency("432210")
        entry.setFrequency("144300")
        entry.callChanged("OK1ABC")
        entry.editContestField("rst", "599")
        entry.editContestField("nr", "5")
        entry.editContestField("loc", "JN79FX")
        entry.submit()
        await entry.settle()
        #expect(app.model.logbook.rows.count == 1)

        entry.bandButtonSecondaryClick(band: .cm70, mode: .cw, startKHz: 432_000)
        #expect(entry.form.freqHz == 432_210_000, "the last frequency used on 70 cm")
        let spot: DxSpot? = app.model.dxCluster.spots.snapshot().first { $0.dxCall == "OK1ABC" }
        #expect(spot?.freqHz == 432_210_000)
        #expect(spot?.selfSpotted == true)
        #expect(app.model.status.message == "OK1ABC uložen do bandmapy na 70cm")

        // A band never used: the segment start.
        entry.bandButtonSecondaryClick(band: .m6, mode: .cw, startKHz: 50_090)
        #expect(entry.form.freqHz == 50_090_000)
    }

    @Test func rightClickWithACallPassesItToTheStationOnThatBand() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await eventually("A sees B") { a.cluster.peers.first?.online == true }
        b.model.rig.qsy(21_025_000)
        b.clusterClock.advance(by: 1_000)
        await eventually("A sees B's frequency") { a.cluster.peers.first?.status.freqHz == 21_025_000 }

        a.model.entry.callChanged("dl1abc")
        a.model.entry.bandButtonSecondaryClick(band: .m40, mode: .cw, startKHz: 7_000)
        #expect(a.status == "Pass: na pásmu 40m není žádná stanice sítě")

        a.model.entry.bandButtonSecondaryClick(band: .m15, mode: .cw, startKHz: 21_000)
        await eventually("B has the spot") {
            b.model.dxCluster.spots.snapshot().contains { $0.spotter == "PASS-OP1" && $0.dxCall == "DL1ABC" }
        }
        await eventually("A's status") { a.status == "Pass: DL1ABC předáno stanici OP2" }
    }
}
