import Foundation
import Testing
@testable import MCLCore

/// Cluster-sync wire behaviour measured on Java v1.1.1 (Jackson 2.22; a probe over `WireJson`, values verbatim)
/// and the `markDeleted` case with a `null` time. The whole space of coercions and the fuzzer are covered by the generator
/// a maintainer-only probe (sections `sync.*`); here are the pinned cases that are easiest to get wrong in Swift.
@Suite struct SyncMeasuredTests {

    /// An outer `nil` = a read error, an inner `nil` = Java `null`.
    static func read<T: WireMessage>(_ json: String, _ type: T.Type) -> T?? {
        do {
            let value: T? = try WireJson.fromBytes(Array(json.utf8), as: type)
            return .some(value)
        } catch {
            return .none
        }
    }

    static func instant(_ text: String) -> JavaInstant? {
        JavaInstant.parseIsoInstant(text)
    }

    // MARK: - writing

    @Test func writerEscapesLikeJackson() {
        let spot = SpotWire(stationId: "OP1", spotter: "a\"b\\c\u{1}\u{1F}\u{8}\t\n\u{C}\r é /</\u{2028}\u{7F}",
                            freqHz: 1, dxCall: "😀", comment: nil)
        var expected = "{\"stationId\":\"OP1\",\"spotter\":\"a\\\"b\\\\c\\u0001\\u001F\\b\\t\\n\\f\\r é /</\u{2028}\u{7F}\","
        expected += "\"freqHz\":1,\"dxCall\":\"😀\",\"comment\":null}"
        #expect(WireJson.toJson(spot) == expected)
    }

    /// The wire (`toBytes`, Jackson `UTF8JsonGenerator`) writes a character above U+FFFF as an escaped pair of surrogates;
    /// `toJson` (Writer) raw.
    @Test func bytesEscapeAstralCharacters() {
        let spot = SpotWire(stationId: "OP1", spotter: "😀x", freqHz: 1, dxCall: "x", comment: nil)
        let bytes = String(decoding: WireJson.toBytes(spot), as: UTF8.self)
        #expect(bytes == "{\"stationId\":\"OP1\",\"spotter\":\"\\uD83D\\uDE00x\",\"freqHz\":1,\"dxCall\":\"x\",\"comment\":null}")
        #expect(WireJson.toJson(spot).contains("\"😀x\""))
    }

    @Test(arguments: [
        ("2026-10-01T12:00:00.000000100Z", "2026-10-01T12:00:00.000000100Z"),
        ("-0001-01-01T00:00:00.120Z", "-0001-01-01T00:00:00.120Z"),
        ("+1000000000-12-31T23:59:59.999999999Z", "+1000000000-12-31T23:59:59.999999999Z"),
        ("-1000000000-01-01T00:00:00Z", "-1000000000-01-01T00:00:00Z"),
    ])
    func instantsWriteAsIsoInstant(text: String, written: String) throws {
        let at: JavaInstant? = Self.instant(text)
        #expect(at != nil)
        let cmd = DeleteCommand(stationId: "OP1", uuid: "u", clientTimestampUtc: at)
        #expect(WireJson.toJson(cmd) == "{\"stationId\":\"OP1\",\"uuid\":\"u\",\"clientTimestampUtc\":\"" + written + "\"}")
    }

    // MARK: - reading: coercions

    @Test func scalarsCoerceLikeJackson() throws {
        let state = try #require(Self.read("{\"version\":\"5\",\"deleted\":\"true\",\"uuid\":123,\"stationId\":true}",
                                           QsoState.self) ?? nil)
        #expect(state.version == 5 && state.deleted && state.uuid == "123" && state.stationId == "true")
        let truncated = try #require(Self.read("{\"version\":5.7,\"deleted\":1}", QsoState.self) ?? nil)
        #expect(truncated.version == 5 && truncated.deleted)
        let wire = try #require(Self.read("{\"serialSent\":1.5,\"xqso\":\"TRUE\"}", QsoWire.self) ?? nil)
        #expect(wire.serialSent == 1 && wire.xqso == true)
        #expect(Self.read("{\"xqso\":\"yes\"}", QsoWire.self) == nil)
        #expect(Self.read("{\"qsoCount\":2147483648}", StationStatusWire.self) == nil)
        let status = try #require(Self.read("{\"freqHz\":\" +7 \",\"online\":\"  \"}", StationStatusWire.self) ?? nil)
        #expect(status.freqHz == 7 && !status.online)
        let unicode = try #require(Self.read("{\"freqHz\":\"null\",\"qsoCount\":\"\\u0663\"}", StationStatusWire.self) ?? nil)
        #expect(unicode.freqHz == 0 && unicode.qsoCount == 3)
        let rounded = try #require(Self.read("{\"freqHz\":9223372036854775806.9}", StationStatusWire.self) ?? nil)
        #expect(rounded.freqHz == Int.max)
    }

    @Test(arguments: [
        ("\"2026-10-01T12:00:00+02:00\"", "2026-10-01T10:00:00Z"),
        ("\"2026-10-01T12:00:00+00\"", "2026-10-01T12:00:00Z"),
        ("\"2026-10-01T24:00:00Z\"", "2026-10-02T00:00:00Z"),
        ("\"2026-10-01T23:59:60Z\"", "2026-10-01T23:59:59Z"),
        ("\"+12026-01-01T00:00:00Z\"", "+12026-01-01T00:00:00Z"),
        ("1700000000", "2023-11-14T22:13:20Z"),
        ("1700000000.25", "2023-11-14T22:13:20.250Z"),
        ("\"1700000000.25\"", "2023-11-14T22:13:20.250Z"),
        ("1e64", "1970-01-01T00:00:00Z"),
        ("18446744073709551616.5", "1970-01-01T00:00:00.500Z"),
    ])
    func instantsReadLikeJackson(token: String, instant: String) throws {
        let wire = try #require(Self.read("{\"timestampUtc\":" + token + "}", QsoWire.self) ?? nil)
        #expect(wire.timestampUtc?.toString() == instant)
    }

    @Test(arguments: ["\"2026-10-01T12:00Z\"", "\"12026-01-01T00:00:00Z\""])
    func instantsRejectedLikeJackson(token: String) {
        #expect(Self.read("{\"timestampUtc\":" + token + "}", QsoWire.self) == nil)
    }

    // MARK: - reading: structure

    @Test func rootNullIsNilAndOtherRootsFail() throws {
        let null: SerialRequest?? = Self.read("null", SerialRequest.self)
        #expect(null != nil && null! == nil)
        #expect(throws: SyncSerializationError(message: "Nelze deserializovat SerialRequest")) {
            try WireJson.fromBytes(Array("[]".utf8), as: SerialRequest.self)
        }
    }

    @Test func trailingContentAndBomAndUnknownFieldsPass() throws {
        #expect(Self.read("{\"stationId\":\"a\"} trailing", SerialRequest.self)??.stationId == "a")
        #expect(Self.read("\u{FEFF}{\"stationId\":\"a\"}", SerialRequest.self)??.stationId == "a")
        let unknown = Self.read("{\"stationId\":\"a\",\"requestId\":\"r\",\"x\":{\"y\":[1,2]}}", SerialRequest.self)
        #expect(unknown??.requestId == "r")
        #expect(Self.read("{\"station\\u0049d\":\"a\"}", SerialRequest.self)??.stationId == "a")
    }

    /// A repeated key overwrites the value until the record is complete; after the last missing component it is an error.
    @Test func duplicateKeyWinsOnlyBeforeRecordIsComplete() {
        #expect(Self.read("{\"stationId\":\"a\",\"stationId\":\"b\"}", SerialRequest.self)??.stationId == "b")
        #expect(Self.read("{\"stationId\":\"a\",\"requestId\":\"r\",\"stationId\":\"b\"}", SerialRequest.self) == nil)
    }

    /// An escaped lone surrogate is allowed in a value (Java keeps it, Swift `U+FFFD`), an error in a key.
    @Test func loneSurrogateEscapes() {
        #expect(Self.read("{\"stationId\":\"\\ud83d\"}", SerialRequest.self)??.stationId == "\u{FFFD}")
        #expect(Self.read("{\"\\ud83d\":1}", SerialRequest.self) == nil)
    }

    // MARK: -, a state without a time and without a callsign

    /// `markDeleted` with a `null` time (Java: a tombstone without a payload) writes `NULL` to `updated_at_utc`.
    @Test func markDeletedWithoutTimeStoresNull() throws {
        let repo = try LogbookRepository.inMemory()
        defer { repo.close() }
        var q = Qso()
        q.call = "DL1ABC"
        q.uuid = "u1"
        q.version = 1
        q.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000)
        try repo.upsertByUuid(q)
        try repo.markDeleted(uuid: "u1", version: 2, updatedAtUtc: nil)
        let back = try #require(try repo.findByUuid("u1"))
        #expect(back.deleted && back.version == 2 && back.updatedAtUtc == nil)
    }

    /// `insert` assigns a `uuid` like Java `UUID.randomUUID().toString()` (lowercase) also in place of a blank `uuid`.
    @Test func insertAssignsLowercaseUuidLikeJava() throws {
        let repo = try LogbookRepository.inMemory()
        defer { repo.close() }
        var q = Qso()
        q.call = "DL1ABC"
        q.uuid = "  "
        try repo.insert(&q)
        #expect(q.uuid.count == 36)
        #expect(q.uuid == q.uuid.lowercased())
    }

    @Test func coordinatorRejectsNullStateAndStateWithoutCall() throws {
        let repo = try LogbookRepository.inMemory()
        defer { repo.close() }
        let logbook = LogbookService(repository: repo)
        let coord = SyncCoordinator(logbook: logbook, transport: InMemorySyncTransport(), stationId: "OP1", onChange: nil)
        #expect(throws: SyncNullStateError()) { try coord.onState(nil) }
        let noPayload = QsoState(uuid: "u1", stationId: "OP2", version: 1, updatedAtUtc: nil, deleted: false, qso: nil)
        let insertError = #expect(throws: LogbookError.self) { try coord.onState(noPayload) }
        #expect(insertError?.message == "Nelze uložit QSO")
        #expect(try logbook.findAllIncludingDeleted().isEmpty)

        let wire = QsoWire(timestampUtc: nil, call: "DL1ABC", freqHz: 14_025_000, band: nil, mode: nil, rstSent: nil,
                           rstRcvd: nil, exchangeSent: nil, exchangeRcvd: nil, serialSent: nil, serialRcvd: nil,
                           operator: nil, comment: nil, dxccEntity: nil, dxccName: nil, continent: nil)
        try coord.onState(QsoState(uuid: "u1", stationId: "OP2", version: 1, updatedAtUtc: nil, deleted: false, qso: wire))
        let newer = QsoState(uuid: "u1", stationId: "OP2", version: 2, updatedAtUtc: nil, deleted: false, qso: nil)
        let updateError = #expect(throws: LogbookError.self) { try coord.onState(newer) }
        #expect(updateError?.message == "Nelze aktualizovat QSO")
        // An older or equal version without a callsign is dropped without an error (Java does not write).
        let older = QsoState(uuid: "u1", stationId: "OP2", version: 1, updatedAtUtc: nil, deleted: false, qso: nil)
        try coord.onState(older)
        #expect(try logbook.findAllIncludingDeleted()[0].call == "DL1ABC")
    }
}
