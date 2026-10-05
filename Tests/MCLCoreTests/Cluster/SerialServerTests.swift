import Testing
@testable import MCLCore

/// Port `SerialServerTest.java` (2 testy): serial server nad `InMemorySyncTransport`.
@Suite struct SerialServerTests {

    @Test func twoStationsNeverGetTheSameNumber() throws {
        let t = InMemorySyncTransport()
        let a = StationNetwork(transport: t, stationId: "STN1", clock: { JavaInstant.now() })
        let b = StationNetwork(transport: t, stationId: "STN2", clock: { JavaInstant.now() })
        let atA = Collected<SerialReply>()
        let atB = Collected<SerialReply>()
        a.onSerialReplies { atA.add($0) }
        b.onSerialReplies { atB.add($0) }

        try a.requestSerial("r1")
        try b.requestSerial("r2")
        try a.requestSerial("r3")

        #expect(atA.values.map(\.serial) == [1, 3])
        #expect(atB.values.map(\.serial) == [2])
        #expect(atB.values[0].requestId == "r2")
    }

    @Test func numbersContinueAfterLoggedSerials() throws {
        let t = InMemorySyncTransport()
        let q = QsoWire(timestampUtc: JavaInstant.now(), call: "DL1ABC", freqHz: 14_025_000, band: "M20", mode: "CW",
                        rstSent: "599", rstRcvd: "599", exchangeSent: "", exchangeRcvd: "", serialSent: 57,
                        serialRcvd: 12, operator: "OK1XOE", comment: nil, dxccEntity: nil, dxccName: nil,
                        continent: nil)
        try t.publishInsert(QsoCommand(stationId: "STN9", uuid: "u1", clientTimestampUtc: JavaInstant.now(), qso: q))
        let a = StationNetwork(transport: t, stationId: "STN1", clock: { JavaInstant.now() })
        let got = Collected<SerialReply>()
        a.onSerialReplies { got.add($0) }
        try a.requestSerial("x")
        #expect(got.values[0].serial == 58, "58 follows the sent 57")
    }
}
