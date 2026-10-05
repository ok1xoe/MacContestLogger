import Testing
@testable import MCLCore

/// Port of `NetMessagesTest.java` (4 tests): chat, station handover (pass) and call stacking via `StationNetwork`
/// over `InMemorySyncTransport`.
@Suite struct NetMessagesTests {

    private static func network(_ t: InMemorySyncTransport, _ id: String) -> StationNetwork {
        StationNetwork(transport: t, stationId: id, clock: { JavaInstant.now() })
    }

    @Test func chatGoesToAllOrToOneStationNotBackToSender() throws {
        let t = InMemorySyncTransport()
        let a = Self.network(t, "STN1")
        let b = Self.network(t, "STN2")
        let c = Self.network(t, "STN3")
        let atA = Collected<String?>()
        let atB = Collected<String?>()
        let atC = Collected<String?>()
        a.onMessages { atA.add($0.text) }
        b.onMessages { atB.add($0.text) }
        c.onMessages { atC.add($0.text) }

        try a.send(NetMessageWire.chat, operator: "OK1XOE", to: "", text: "ahoj všichni", call: nil, freqHz: 0, mode: nil)
        try a.send(NetMessageWire.chat, operator: "OK1XOE", to: "STN3", text: "jen pro 3", call: nil, freqHz: 0, mode: nil)

        #expect(atA.values.isEmpty)
        #expect(atB.values == ["ahoj všichni"])
        #expect(atC.values == ["ahoj všichni", "jen pro 3"])
    }

    @Test func wireRoundTrip() throws {
        let m = NetMessageWire(type: NetMessageWire.pass, id: "1", fromStation: "STN1", fromOperator: "OK1XOE",
                               toStation: "STN2", text: "", call: "DL1ABC", freqHz: 7_025_000, mode: "CW",
                               timestampUtc: "2026-11-28T12:00:00Z")
        #expect(try WireJson.fromBytes(WireJson.toBytes(m), as: NetMessageWire.self) == m)
    }

    @Test func passCarriesCallAndTargetFrequencyToOneStation() throws {
        let t = InMemorySyncTransport()
        let run = Self.network(t, "RUN1")
        let mult = Self.network(t, "MULT")
        let other = Self.network(t, "RUN2")
        let atMult = Collected<NetMessageWire>()
        let atOther = Collected<NetMessageWire>()
        mult.onMessages { atMult.add($0) }
        other.onMessages { atOther.add($0) }

        try run.send(NetMessageWire.pass, operator: "OK1XOE", to: "MULT", text: "u mě 14025.0", call: "DL1ABC",
                     freqHz: 7_012_000, mode: "CW")

        #expect(atMult.count == 1)
        #expect(atMult.values[0].call == "DL1ABC")
        #expect(atMult.values[0].freqHz == 7_012_000)
        #expect(atMult.values[0].fromStation == "RUN1")
        #expect(atOther.values.isEmpty)
    }

    @Test func stackReachesRunnerAndStatusCarriesEntryCall() throws {
        let t = InMemorySyncTransport()
        let partner = Self.network(t, "PARTNER")
        let runner = Self.network(t, "RUN1")
        let atRunner = Collected<NetMessageWire>()
        runner.onMessages { atRunner.add($0) }
        try partner.start(nil)
        try runner.start(nil)

        try partner.send(NetMessageWire.stack, operator: "OK1ABC", to: "RUN1", text: "", call: "K1ZZ", freqHz: 0,
                         mode: nil)
        #expect(atRunner.values[0].call == "K1ZZ")
        #expect(atRunner.values[0].type == NetMessageWire.stack)

        try runner.publish(StationStatusWire(stationId: "RUN1", operator: "OK1XOE", stationType: "", band: "20m",
                                             mode: "CW", freqHz: 14_025_000, runMode: "RUN", qsoCount: 10,
                                             transmitting: false, online: true, timestampUtc: nil, entryCall: "DL1A"))
        #expect(partner.peers()[0].status.entryCall == "DL1A")
    }
}
