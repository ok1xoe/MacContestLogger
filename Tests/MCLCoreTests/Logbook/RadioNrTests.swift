import Foundation
import Testing
@testable import MCLCore

/// N1MM `RadioNr` per QSO: stored in the log (with a migration of older files), kept in the deleted-QSO archive and
/// the journal, carried by the sync wire as an optional extension, and exported to ADIF / Cabrillo / N1MM UDP.
@Suite struct RadioNrTests {

    static func qso(_ call: String = "DL1ABC", radio: Int) -> Qso {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: 1_795_000_000)
        q.call = call
        q.freqHz = 14_025_000
        q.mode = .cw
        q.rstSent = "599"
        q.rstRcvd = "599"
        q.radioNr = radio
        return q
    }

    // MARK: - log

    @Test func radioNumberIsPersistedAndUpdated() throws {
        let repo = try LogbookRepository.inMemory()
        var q = Self.qso(radio: 2)
        _ = try repo.insert(&q)
        var back = try #require(try repo.findAll().first)
        #expect(back.radioNr == 2)

        back.radioNr = 1
        try repo.update(back)
        #expect(try repo.findAll().first?.radioNr == 1)
    }

    @Test func deletedArchiveKeepsTheRadio() throws {
        let repo = try LogbookRepository.inMemory()
        var q = Self.qso(radio: 2)
        _ = try repo.insert(&q)
        try repo.archiveDeleted([q], at: Date(timeIntervalSince1970: 1_795_000_100))
        #expect(try repo.findDeleted(contestId: "").first?.qso.radioNr == 2)
    }

    @Test func anOlderLogFileGetsTheColumn() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mcl-radionr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("old.db")
        // The tables as the previous version created them (no radio_nr).
        let old = try SQLiteDatabase.open(at: file.path)
        let columns = """
            id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp_utc INTEGER NOT NULL, call TEXT NOT NULL,
            freq_hz INTEGER NOT NULL, band TEXT, mode TEXT, rst_sent TEXT, rst_rcvd TEXT, exchange_sent TEXT,
            exchange_rcvd TEXT, serial_sent INTEGER, serial_rcvd INTEGER, points INTEGER NOT NULL DEFAULT 0,
            multiplier INTEGER NOT NULL DEFAULT 0, run_mode TEXT, operator TEXT, comment TEXT, dxcc_entity INTEGER,
            dxcc_name TEXT, continent TEXT, uuid TEXT, station_id TEXT, version INTEGER NOT NULL DEFAULT 0,
            updated_at_utc INTEGER, deleted INTEGER NOT NULL DEFAULT 0, contest_id TEXT,
            xqso INTEGER NOT NULL DEFAULT 0
            """
        try old.execute("CREATE TABLE qso (" + columns + ")")
        try old.execute("CREATE TABLE deleted_qso (" + columns
                        + ", deleted_at_utc INTEGER NOT NULL, original_id INTEGER)")
        try old.execute("INSERT INTO qso (timestamp_utc, call, freq_hz, contest_id, uuid) "
                        + "VALUES (1795000000000, 'OK1AB', 14025000, 'c1', 'u-old')")
        old.close()

        let repo = try LogbookRepository(url: file)
        defer { repo.close() }
        let kept = try #require(try repo.findAll(contestId: "c1").first)
        #expect(kept.call == "OK1AB")
        #expect(kept.radioNr == 0)
        var q = Self.qso(radio: 2)
        q.contestId = "c1"
        _ = try repo.insert(&q)
        try repo.archiveDeleted([q], at: Date(timeIntervalSince1970: 1_795_000_100))
        #expect(try repo.findDeleted(contestId: "c1").first?.qso.radioNr == 2)
    }

    @Test func journalCarriesTheRadioAndReadsOlderLines() throws {
        let back = JournalQso(Self.qso(radio: 2)).qso
        #expect(back.radioNr == 2)

        var json = try #require(String(data: try JSONEncoder().encode(JournalQso(Self.qso(radio: 2))),
                                       encoding: .utf8))
        json = json.replacingOccurrences(of: ",\"radioNr\":2", with: "")
            .replacingOccurrences(of: "\"radioNr\":2,", with: "")
        #expect(!json.contains("radioNr"))
        let old = try JSONDecoder().decode(JournalQso.self, from: Data(json.utf8))
        #expect(old.qso.radioNr == 0)
    }

    // MARK: - sync wire

    @Test func theWireCarriesAKnownRadio() throws {
        let wire: QsoWire = WireMapper.toWire(Self.qso(radio: 2))
        let json: String = WireJson.toJson(wire)
        #expect(json.hasSuffix(",\"xqso\":null,\"radioNr\":2}"))
        let read = try #require(try WireJson.fromBytes(Array(json.utf8), as: QsoWire.self))
        let state = QsoState(uuid: "u", stationId: "s", version: 1, updatedAtUtc: JavaInstant.now(), deleted: false,
                             qso: read)
        #expect(WireMapper.toQso(state).radioNr == 2)
    }

    /// Without a known radio the message is exactly the v1.1.1 one, and a v1.1.1 message reads as "not known".
    @Test func anUnknownRadioLeavesTheV111MessageUnchanged() throws {
        let json: String = WireJson.toJson(WireMapper.toWire(Self.qso(radio: 0)))
        #expect(!json.contains("radioNr"))
        #expect(json.hasSuffix(",\"xqso\":null}"))
        let read = try #require(try WireJson.fromBytes(Array(json.utf8), as: QsoWire.self))
        #expect(read.radioNr == nil)
    }

    /// Jackson's rule (a known key after all components were seen is an error) still holds for the v1.1.1 fields,
    /// but the extension may come after them.
    @Test func theExtensionMayFollowAllV111Fields() throws {
        let json: String = WireJson.toJson(WireMapper.toWire(Self.qso(radio: 2)))
        #expect(try WireJson.fromBytes(Array(json.utf8), as: QsoWire.self)?.radioNr == 2)
        let repeated: String = json.replacingOccurrences(of: "}", with: ",\"call\":\"X\"}")
        #expect(throws: SyncSerializationError.self) {
            _ = try WireJson.fromBytes(Array(repeated.utf8), as: QsoWire.self)
        }
    }

    // MARK: - exports and imports

    @Test func adifCarriesN1mmRadioFields() throws {
        var writer = AdifWriter()
        writer.n1mmFields = true
        let text: String = writer.toAdif([Self.qso(radio: 2), Self.qso("K1A", radio: 0)])
        #expect(text.contains("<APP_N1MM_RADIO_NR:1>2 <APP_N1MM_RUN1RUN2:1>2 "))
        #expect(text.components(separatedBy: "APP_N1MM_RADIO_NR").count == 2, "an unknown radio is not written")
        #expect(!AdifWriter().toAdif([Self.qso(radio: 2)]).contains("RADIO_NR"), "the v1.1.1 record stays as it was")

        let back: [Qso] = try AdifReader().read(text)
        #expect(back.map(\.radioNr) == [2, 0])
    }

    @Test func n1mmContactInfoBringsTheRadio() {
        let xml = "<contactinfo><call>DL1ABC</call><radionr>2</radionr></contactinfo>"
        #expect(N1mmContactParser.parse(xml)?.qso.radioNr == 2)
        #expect(N1mmContactParser.parse("<contactinfo><call>DL1ABC</call></contactinfo>")?.qso.radioNr == 0)
    }

    /// Multi-Two from one computer: the radio is the transmitter number (N1MM Run1/Run2).
    @Test func cabrilloMultiTwoFromOneComputerUsesTheRadio() throws {
        var a = CabrilloExporterTests.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        a.radioNr = 2
        var b = CabrilloExporterTests.qso("2026-11-28T00:02:00Z", "K1A", 7_025_000, .cw, "599", 2, "599 5")
        b.radioNr = 1
        var input = try CabrilloExporterTests.cqww([a, b])
        input.category = CabrilloExporterTests.map(("OPERATOR", "MULTI-OP"), ("TRANSMITTER", "TWO"))

        let lines = CabrilloExporterTests.qsoLines(try CabrilloExporter.export(input).text)

        #expect(lines[0].hasSuffix(" 1"))
        #expect(lines[1].hasSuffix(" 0"))
    }
}
