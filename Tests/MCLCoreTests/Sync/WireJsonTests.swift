import Testing
@testable import MCLCore

/// Port of `WireJsonTest.java` from the `:sync-shared` submodule (6 tests; outside the count of 208 application tests — `:sync-shared`
/// stays in Java, the Swift client needs a counterpart of `WireJson`).
@Suite struct WireJsonTests {

    static func sampleWire() -> QsoWire {
        QsoWire(timestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:00Z"), call: "OK1ABC", freqHz: 14_025_000,
                band: "B20M", mode: "CW", rstSent: "599", rstRcvd: "599", exchangeSent: "001", exchangeRcvd: "042",
                serialSent: 1, serialRcvd: 42, operator: "OK1XOE", comment: "", dxccEntity: 503,
                dxccName: "Czech Republic", continent: "EU")
    }

    @Test func qsoStateRoundTrips() throws {
        let state = QsoState(uuid: "9f1c0c2e-aaaa", stationId: "OP1", version: 3,
                             updatedAtUtc: JavaInstant.parseIsoInstant("2026-06-29T12:34:56.789Z"), deleted: false,
                             qso: Self.sampleWire())

        let json: [UInt8] = WireJson.toBytes(state)
        let back = try #require(try WireJson.fromBytes(json, as: QsoState.self))

        #expect(back == state)
        #expect(back.qso?.call == "OK1ABC")
        #expect(back.version == 3)
    }

    @Test func insertCommandRoundTrips() throws {
        let cmd = QsoCommand(stationId: "OP1", uuid: "9f1c0c2e-aaaa",
                             clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:30:01Z"), qso: Self.sampleWire())

        #expect(try WireJson.fromBytes(WireJson.toBytes(cmd), as: QsoCommand.self) == cmd)
    }

    @Test func deleteCommandRoundTrips() throws {
        let del = DeleteCommand(stationId: "OP1", uuid: "9f1c0c2e-aaaa",
                                clientTimestampUtc: JavaInstant.parseIsoInstant("2026-06-29T12:40:00Z"))

        #expect(try WireJson.fromBytes(WireJson.toBytes(del), as: DeleteCommand.self) == del)
    }

    @Test func stateNeverCarriesPointsOrMultiplier() {
        // Drift guard: the score/multiplier is not transferred over the network (each station computes it itself).
        let json: String = WireJson.toJson(QsoState(uuid: "u", stationId: "OP1", version: 1,
                                                    updatedAtUtc: JavaInstant.parseIsoInstant("2026-06-29T12:34:56Z"),
                                                    deleted: false, qso: Self.sampleWire()))
        #expect(!json.contains("points"))
        #expect(!json.contains("multiplier"))
    }

    @Test func timestampsAreIsoStringsNotEpoch() {
        let json: String = WireJson.toJson(Self.sampleWire())
        #expect(json.contains("2026-06-29T12:30:00Z"))
    }

    @Test func unknownFieldsAreIgnored() throws {
        var json = "{\"uuid\":\"u\",\"stationId\":\"OP1\",\"version\":1,"
        json += "\"updatedAtUtc\":\"2026-06-29T12:34:56Z\",\"deleted\":false,"
        json += "\"qso\":{\"call\":\"OK1ABC\",\"freqHz\":14025000},"
        json += "\"somethingNew\":\"future field\"}"
        let back = try #require(try WireJson.fromBytes(Array(json.utf8), as: QsoState.self))
        #expect(back.qso?.call == "OK1ABC")
    }
}
