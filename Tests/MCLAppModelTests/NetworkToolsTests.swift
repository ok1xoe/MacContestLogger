import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM Network Status → Messages / Actions in the app: the trace, the call for help, the configuration mismatch
/// warnings, the serial reset at all stations and the time from the master station. Stations talk over an in-memory
/// hub; nothing reaches a socket and the alert is a counter.
@MainActor @Suite struct NetworkToolsTests {

    @MainActor final class Counter {
        var value = 0
    }

    private static func pair(configureB: @escaping (inout AppConfig) -> Void = { _ in },
                             bNow: TestNow? = nil) async throws -> (a: NetStation, b: NetStation) {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: bNow ?? now, configure: configureB)
        try await a.activate()
        try await b.activate()
        await eventually("A sees B") { a.cluster.peers.first?.online == true }
        await eventually("B sees A") { b.cluster.peers.first?.online == true }
        return (a, b)
    }

    @Test func callForHelpAlertsTheOtherStationAndBothTraceIt() async throws {
        let (a, b) = try await Self.pair()
        let alerts = Counter()
        b.network.alert = { alerts.value += 1 }
        a.network.callForHelp(to: "OP2")
        await eventually("B alerted") { alerts.value == 1 }
        await eventually("B's status") { b.status.hasPrefix("POMOC: stanice OP1") && b.status.hasSuffix("volá o pomoc") }
        await eventually("A's status") { a.status == "Volání o pomoc odesláno: OP2" }
        #expect(a.network.tools.trace.contains { $0.outgoing && $0.type == "HELP" && $0.peer == "OP2" })
        #expect(b.network.tools.trace.contains { !$0.outgoing && $0.type == "HELP" && $0.peer == "OP1" })
        // Not a chat line.
        #expect(b.network.chat.lines.isEmpty)
        b.network.clearTrace()
        #expect(b.network.tools.trace.isEmpty)
    }

    @Test func withoutTheNetworkTheToolsSaySo() async throws {
        let hub = InMemorySyncTransport()
        let c = try await NetStation.make(id: "OP3", hub: hub, enabled: false)
        c.network.callForHelp(to: "")
        #expect(c.status == "Síťový deník není připojený")
        c.network.resetSerialsEverywhere()
        #expect(c.status == "Síťový deník není připojený")
    }

    @Test func theSetupsAreExchangedAndAMismatchIsWarnedOnce() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        a.network.ownProfile = { StationProfile(version: "1.0.0", contest: "CQ-WW-CW", category: "OPERATOR=MULTI-OP") }
        b.network.ownProfile = { StationProfile(version: "1.0.1", contest: "CQ-WW-CW", category: "OPERATOR=MULTI-OP") }
        try await a.activate()
        try await b.activate()
        await eventually("A knows B") { a.network.tools.profiles["OP2"]?.version == "1.0.1" }
        await eventually("B knows A") { b.network.tools.profiles["OP1"]?.version == "1.0.0" }
        await eventually("A sees B online") { a.cluster.peers.first?.online == true }
        #expect(a.network.mismatchWarnings.map(\.czech) == ["Stanice OP2 má jinou verzi programu (1.0.1, tato 1.0.0)"])

        // B opens another contest: the change goes out with the next round and A warns about it.
        b.network.ownProfile = { StationProfile(version: "1.0.0", contest: "CQ-WPX-CW", category: "OPERATOR=MULTI-OP") }
        b.clusterClock.advance(by: 1_000)
        await eventually("A got the new contest") { a.network.tools.profiles["OP2"]?.contest == "CQ-WPX-CW" }
        #expect(a.network.mismatchWarnings.map(\.czech)
            == ["Stanice OP2 má otevřený jiný závod (CQ-WPX-CW, tato CQ-WW-CW)"])
        #expect(a.status == "⚠ Stanice OP2 má otevřený jiný závod (CQ-WPX-CW, tato CQ-WW-CW)")
        // N1MM's Message Window: every new difference also goes to the Info window's program messages.
        #expect(a.model.messages.lines.map(\.text) == [
            "Stanice OP2 má jinou verzi programu (1.0.1, tato 1.0.0)",
            "Stanice OP2 má otevřený jiný závod (CQ-WPX-CW, tato CQ-WW-CW)",
        ])
        #expect(a.network.tools.trace.contains { $0.type == "HELLO" })
    }

    /// N1MM reports a different entry category (multi-single versus multi-two) in the Message Window once.
    @Test func aCategoryMismatchIsAProgramMessage() async throws {
        let hub = InMemorySyncTransport()
        let now = NetStation.start()
        let a = try await NetStation.make(id: "OP1", hub: hub, now: now)
        let b = try await NetStation.make(id: "OP2", hub: hub, now: now)
        a.network.ownProfile = { StationProfile(contest: "CQ-WW-CW", category: "OPERATOR=MULTI-OP TRANSMITTER=ONE") }
        b.network.ownProfile = { StationProfile(contest: "CQ-WW-CW", category: "OPERATOR=MULTI-OP TRANSMITTER=TWO") }
        try await a.activate()
        try await b.activate()
        await eventually("A sees B online") { a.cluster.peers.first?.online == true }
        await eventually("A knows B") { !a.network.mismatchWarnings.isEmpty }
        await eventually("A's message") { !a.model.messages.lines.isEmpty }
        let expected = "Stanice OP2 má jinou kategorii (OPERATOR=MULTI-OP TRANSMITTER=TWO, tato "
            + "OPERATOR=MULTI-OP TRANSMITTER=ONE)"
        #expect(a.model.messages.lines.map(\.text) == [expected])
        // The same difference is not repeated on the next round.
        b.clusterClock.advance(by: 1_000)
        a.clusterClock.advance(by: 1_000)
        #expect(a.model.messages.lines.count == 1)
    }

    @Test func serialResetMovesEveryStationPastTheHighestSentSerial() async throws {
        let (a, b) = try await Self.pair()
        await a.log("DL1ABC")
        await eventually("B has it") { b.model.logbook.rows.count == 1 }
        // Another station reports serial 56 as the highest sent: the next one here is 57.
        b.network.receive(NetMessageWire(type: NetMessageWire.serialReset, id: "x", fromStation: "OP9",
                                         fromOperator: "", toStation: "", text: "", call: nil, freqHz: 56, mode: nil,
                                         timestampUtc: nil))
        #expect(b.model.logbook.nextSerial == 57)
        #expect(b.status == "Stanice OP9 nastavila pořadová čísla: další je 57")
        // A lower number never moves a station back.
        b.network.receive(NetMessageWire(type: NetMessageWire.serialReset, id: "y", fromStation: "OP9",
                                         fromOperator: "", toStation: "", text: "", call: nil, freqHz: 3, mode: nil,
                                         timestampUtc: nil))
        #expect(b.model.logbook.nextSerial == 57)
        // A's reset sends the highest serial of its log; A continues after it, B after its own higher floor.
        let highest: Int = NetworkTools.maxSentSerial(a.model.logbook.rows)
        #expect(highest == 1)
        a.network.resetSerialsEverywhere()
        await eventually("A's status") { a.status == "Pořadová čísla na všech stanicích pokračují od 2" }
        await eventually("B traced it") { b.network.tools.trace.contains { $0.type == "SERIALRESET" && $0.peer == "OP1" } }
        #expect(b.model.logbook.nextSerial == 57)
    }

    @Test func aStationTakesTheMastersTime() async throws {
        // The master's clock is 2.5 s ahead of B's.
        let ahead = TestNow(NetStation.start().date.addingTimeInterval(2.5))
        let hub = InMemorySyncTransport()
        let b = try await NetStation.make(id: "OP2", hub: hub, configure: { $0.cluster.timeFromMaster = true })
        let m = try await NetStation.make(id: "OP1", hub: hub, now: ahead, configure: { $0.cluster.master = true })
        try await m.activate()
        try await b.activate()
        await eventually("B knows the master") { b.network.masterStation == "OP1" }
        b.clusterClock.advance(by: 1_000)
        await eventually("B synchronised") { b.network.tools.masterOffsetMs != nil }
        #expect(b.network.tools.masterOffsetMs == 2_500)
        #expect(b.network.tools.masterStation == "OP1")
        await eventually("B's status") { b.status == "Čas master stanice OP1: odchylka +2.50 s (čas QSO opravován)" }
        // The QSO time follows the master's clock.
        await b.settle()
        let applied: TimeInterval? = try? await b.model.database.handle.run { $0.service.clockOffset }
        #expect(applied == 2.5)
        // The master itself never asks; the next round within 10 minutes does not ask again.
        let requests: Int = b.network.tools.trace.filter { $0.type == "TIMEREQ" }.count
        b.clusterClock.advance(by: 1_000)
        await b.settle()
        #expect(b.network.tools.trace.filter { $0.type == "TIMEREQ" }.count == requests)
        #expect(!m.network.tools.trace.contains { $0.outgoing && $0.type == "TIMEREQ" })
    }

    @Test func withoutTheSwitchNoTimeIsAskedFor() async throws {
        let hub = InMemorySyncTransport()
        let b = try await NetStation.make(id: "OP2", hub: hub)
        let m = try await NetStation.make(id: "OP1", hub: hub, configure: { $0.cluster.master = true })
        try await m.activate()
        try await b.activate()
        await eventually("B knows the master") { b.network.masterStation == "OP1" }
        b.clusterClock.advance(by: 1_000)
        await b.settle()
        #expect(!b.network.tools.trace.contains { $0.type == "TIMEREQ" })
        #expect(b.network.tools.masterOffsetMs == nil)
    }
}
