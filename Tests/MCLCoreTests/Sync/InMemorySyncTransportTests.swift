import Testing
@testable import MCLCore

/// Port of `InMemorySyncTransportTest.java` from the `:sync-shared` submodule (2 tests; outside the count of 208 application tests).
@Suite struct InMemorySyncTransportTests {

    private static func wire(_ call: String) -> QsoWire {
        QsoWire(timestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:00Z"), call: call, freqHz: 14_025_000,
                band: "B20M", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: "001", exchangeRcvd: "042",
                serialSent: 1, serialRcvd: 42, operator: "OK1XOE", comment: "", dxccEntity: 503,
                dxccName: "Czech Republic", continent: "EU")
    }

    private static func cmd(_ uuid: String, _ call: String) -> QsoCommand {
        QsoCommand(stationId: "OP1", uuid: uuid, clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:01Z"),
                   qso: wire(call))
    }

    @Test func assignsMonotonicVersionPerUuid() throws {
        let t = InMemorySyncTransport()
        let received = Collected<QsoState>()
        try t.subscribeState { if let s = $0 { received.add(s) } }
        t.connect()

        try t.publishInsert(Self.cmd("uuid-A", "DL1ABC"))
        try t.publishUpdate(Self.cmd("uuid-A", "DL1XYZ"))
        try t.publishDelete(DeleteCommand(stationId: "OP1", uuid: "uuid-A",
                                          clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:40:00Z")))

        let states: [QsoState] = received.values
        #expect(states.count == 3)
        #expect(states[0].version == 1)
        #expect(states[1].version == 2)
        #expect(states[2].version == 3)
        #expect(states[2].deleted)
        #expect(states[2].qso?.call == "DL1XYZ") // a tombstone keeps the last payload
    }

    @Test func replaysRetainedStateToLateSubscriber() throws {
        let t = InMemorySyncTransport()
        t.connect()
        try t.publishInsert(Self.cmd("uuid-A", "DL1ABC")) // nobody subscribes yet

        let received = Collected<QsoState>()
        try t.subscribeState { if let s = $0 { received.add(s) } } // a late subscriber → retained replay

        #expect(received.count == 1)
        #expect(received.values[0].qso?.call == "DL1ABC")
    }
}
