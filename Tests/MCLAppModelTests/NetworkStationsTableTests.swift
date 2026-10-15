import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM Network Status → Stations in the app: Run1/Run2 reaches the other station, the last QSO and the pass
/// frequency of a station show in its row, and the chosen columns are saved. Stations talk over an in-memory hub.
@MainActor @Suite struct NetworkStationsTableTests {

    @Test func aRun2StationIsSeenAsRun2WithItsLastQsoAndPassFrequency() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now, configure: {
            $0.cluster.stationType = .run
            $0.cluster.runNumber = 2
        })
        try await a.activate()
        try await b.activate()
        await eventually("A sees B as RUN2") { a.cluster.peers.first?.status.stationType == "RUN2" }

        await b.log("DL1ABC")
        await eventually("A has B's QSO") { a.model.logbook.rows.contains { $0.call == "DL1ABC" } }
        b.network.setPassFrequency("14123.5")
        await eventually("A knows B's pass frequency") { a.network.chat.passFrequencies["OP2"] == 14_123_500 }

        let peer: StationNetwork.Peer = try #require(a.cluster.peers.first)
        let extras: NetworkStationExtras = try #require(a.network.stationExtras()["OP2"])
        #expect(extras.lastQso.hasPrefix("DL1ABC "))
        #expect(NetTexts.cell(.pass, peer, extras: extras, translator: .source) == "14123.5")
        #expect(NetTexts.cell(.type, peer, extras: extras, translator: .source) == "RUN2")
        // A's own QSOs are not B's.
        #expect(a.network.stationExtras()["OP1"] == nil)
    }

    @Test func chosenColumnsAreSavedAndTheDefaultIsStoredAsEmpty() async throws {
        let app = try await TestApp.make()
        let network: NetworkModel = app.model.network
        #expect(network.columns == NetworkStationColumn.defaultOrder)
        network.toggleColumn(.rate100)
        #expect(!network.columns.contains(.rate100))
        network.moveColumn(.state, by: -1)
        #expect(network.columns.suffix(2) == [.state, .lastQso])
        let saved: AppConfig = await app.savedConfigFlushed()
        #expect(NetworkStationColumn.resolve(saved.cluster.statusColumns) == network.columns)
        network.resetColumns()
        #expect(await app.savedConfigFlushed().cluster.statusColumns == [])
        #expect(network.columns == NetworkStationColumn.defaultOrder)
    }

    @Test func ctrlAltMShowsTheNumberedRunType() async throws {
        let app = try await TestApp.make(configure: { config, _ in
            config.cluster.stationType = .mult
            config.cluster.runNumber = 1
        })
        app.model.entry.toggleStationType()
        #expect(app.model.status.message == "Typ stanice: RUN1")
        #expect(app.model.info.stationTypeText == "RUN1")
    }
}
