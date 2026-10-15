import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The multi-user macros, the stack target's wipe, the ADIF of one network station and the Op / Stn log columns in
/// the app. Stations talk over an in-memory hub; nothing reaches a socket.
@MainActor @Suite struct MultiOpMacrosTests {

    private static func pair() async throws -> (a: NetStation, b: NetStation) {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        try await a.activate()
        try await b.activate()
        await eventually("A sees B") { a.cluster.peers.first?.online == true }
        return (a, b)
    }

    @Test func messageMacroTalksToTheNamedStation() async throws {
        let (a, b) = try await Self.pair()
        a.network.sendMacroMessage("OP2 need 20m mult")
        await eventually("B got it") { b.network.chat.lines.last?.text == "need 20m mult" }
        await eventually("A's own line") { a.network.chat.lines.last?.to == "OP2" }
    }

    @Test func passMsgPassesTheLastQsoAndRemembersTheFrequency() async throws {
        let (a, b) = try await Self.pair()
        b.model.rig.qsy(14_025_000)
        b.clusterClock.advance(by: 1_000)
        await eventually("A sees B's frequency") { a.cluster.peers.first?.status.freqHz == 14_025_000 }
        #expect(a.network.macroPassTargets() == [MacroPassTarget(station: "OP2", freqHz: 14_025_000, passHz: 0,
                                                                 run: a.network.macroPassTargets().first?.run ?? false)])
        a.network.passLastQso("14000", call: "DL1ABC")
        await eventually("B has the spot") {
            b.model.dxCluster.spots.snapshot().contains { $0.spotter == "PASS-OP1" && $0.dxCall == "DL1ABC" }
        }
        #expect(a.network.lastPassedFreqHz == 14_025_000)
        a.network.passLastQso("OP9", call: "DL1ABC")
        #expect(a.status == "{PASSMSG}: v síti není stanice OP9")
    }

    @Test func theStackersCallIsWipedWhenTheTargetLogsIt() async throws {
        let (a, b) = try await Self.pair()
        a.network.stackCall(to: "OP2", call: "DL1ABC")
        await eventually("B stacked") { b.model.callStack.calls == ["DL1ABC"] }
        await a.settle()
        a.model.entry.callChanged("DL1ABC")
        await b.log("DL1ABC")
        await eventually("A wiped") { a.model.entry.form.call.isEmpty }
        #expect(a.network.stackedCalls.isEmpty)
    }

    @Test func aCallNotStackedForTheLoggerStays() async throws {
        let (a, b) = try await Self.pair()
        a.model.entry.callChanged("DL1ABC")
        await b.log("DL1ABC")
        await eventually("A has B's QSO") { a.model.logbook.rows.contains { $0.call == "DL1ABC" } }
        await a.settle()
        #expect(a.model.entry.form.call == "DL1ABC")
    }

    @Test func adifOfOneStationAndTheMultiOpColumns() async throws {
        let (a, b) = try await Self.pair()
        await a.log("DL1AAA")
        await b.log("DL2BBB")
        await eventually("A has both") { a.model.logbook.rows.count == 2 }
        #expect(a.model.logbook.visibleColumns.suffix(2) == [.op, .station])

        let window = AdifRangeModel(logbook: a.model.logbook, now: Date())
        #expect(window.stations == ["OP1", "OP2"])
        window.station = "OP2"
        #expect(window.qsoCount == 1)
        #expect(window.suggestedName.hasPrefix("maccontestlogger-OP2-"))
        let file: URL = a.app.dir.child("op2.adi")
        await a.model.exports.exportAdif(to: file, station: "OP2")
        let text: String = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("DL2BBB"))
        #expect(!text.contains("DL1AAA"))
    }

    @Test func aSingleStationLogHasNoMultiOpColumns() async throws {
        let app = try await TestApp.make()
        try await app.startCqWwCw()
        #expect(!app.model.logbook.visibleColumns.contains(.op))
        #expect(!app.model.logbook.visibleColumns.contains(.station))
    }
}
