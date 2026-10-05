import Foundation
import Testing
@testable import MCLCore

/// `CabrilloExporter` and `QtcPlanner.cabrilloLine` against values measured in Java v1.1.1
/// (`Fixtures/cabrillo-export-java.tsv`, maintainer-only probe):
/// - rows `E`/`X` — scenarios (the whole text, QSO count, warnings; an `export` exception), which are
///   built here from the same inputs as the probe;
/// - rows `F` — `toAscii`, `wrap`, `cabrilloLine`;
/// - rows `Q`/`S`/`T`/`C` — export → `ScoreCheck.evaluate` over all 22 `contest-data` definitions.
@Suite struct CabrilloExportMeasuredTests {

    typealias Field = ContestDefinition.ExchangeField

    /// The parsed reference.
    struct Reference {
        /// `E`/`X` by scenario id: `qsoCount`, `text`, `warnings` (joined by `\n`), or an exception.
        var outcomes: [String: [String]] = [:]
        var functions: [[String]] = []
        var inputs: [String: [[String]]] = [:]
        var scores: [String: Int64] = [:]
        var exports: [String: [String]] = [:]
        var checks: [String: [String]] = [:]
        var order: [String] = []
    }

    static func reference() throws -> Reference {
        let url = try #require(Bundle.module.url(forResource: "cabrillo-export-java", withExtension: "tsv"))
        let text = try String(contentsOf: url, encoding: .utf8)
        var ref = Reference()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            switch cols[0] {
            case "V": break
            case "E", "X": ref.outcomes[cols[1]] = cols
            case "F": ref.functions.append(cols)
            case "Q": ref.inputs[cols[1], default: []].append(cols)
            case "S":
                ref.scores[cols[1]] = Int64(cols[2])
                ref.order.append(cols[1])
            case "T": ref.exports[cols[1]] = cols
            case "C": ref.checks[cols[1]] = cols
            default: Issue.record("unknown row \(cols[0])")
            }
        }
        return ref
    }

    static func unescape(_ text: String) -> String {
        String(decoding: IoEdgeFixture.unescape(text) ?? [], as: UTF16.self)
    }

    /// Compares the export result with the `E` row (or an exception with the `X` row).
    static func check(_ id: String, _ input: CabrilloExporter.Input, _ ref: Reference) {
        guard let row = ref.outcomes[id] else {
            Issue.record("scenario \(id) is missing in the reference")
            return
        }
        do {
            let r = try CabrilloExporter.export(input)
            #expect(row[0] == "E", "\(id): Java threw an exception \(row)")
            guard row[0] == "E" else { return }
            #expect(String(r.qsoCount) == row[2], "\(id): qsoCount")
            #expect(r.text == unescape(row[3]), "\(id): text\n\(r.text)")
            #expect(r.warnings.joined(separator: "\n") == unescape(row[4]), "\(id): warnings \(r.warnings)")
        } catch let error as CabrilloExportError {
            #expect(row[0] == "X", "\(id): Swift threw \(error)")
            guard row[0] == "X" else { return }
            #expect(error.javaClass == row[2], "\(id)")
            #expect(error == .illegalArgument(message: unescape(row[3])), "\(id)")
        } catch {
            Issue.record("\(id): unexpected error \(error)")
        }
    }

    // MARK: - building the inputs (a mirror of the probe)

    struct Env {
        let dxcc: DxccResolver
        let registry: MultiplierSetRegistry
        let defs: [ContestDefinition]
        let cqww: ContestDefinition
        let session: ContestSession

        init() throws {
            dxcc = try SessionFixture.dxcc()
            registry = try SessionFixture.registry(dxcc)
            defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
            let cqww = try #require(defs.first { $0.id == "cq-ww-cw" })
            self.cqww = cqww
            session = ContestSession(definition: cqww, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: nil)
        }

        func input(_ definition: ContestDefinition, _ station: StationConfig, _ qsos: [Qso]) -> CabrilloExporter.Input {
            let session = self.session
            return CabrilloExporter.Input(definition: definition, station: station, qsos: qsos,
                                          receivedFields: { try session.activeReceivedFields(call: $0) })
        }
    }

    static func qso(_ time: String?, _ call: String, _ freqHz: Int, _ mode: Mode?, received: String = "") -> Qso {
        var q = Qso()
        q.timestampUtc = time.map { CabrilloExporterTests.instant($0) }
        q.call = call
        q.freqHz = freqHz
        q.mode = mode
        q.exchangeRcvd = received
        return q
    }

    static var ok1xoe: StationConfig {
        var s = StationConfig()
        s.call = "OK1XOE"
        return s
    }

    static let zone15: JavaLinkedMap<String> = JavaLinkedMap([("zone", "15")])

    static func minute(_ i: Int) -> String {
        "2026-11-28T00:" + (i < 10 ? "0" : "") + String(i) + ":00Z"
    }

    // MARK: - scenarios

    /// `ce1`: the header (NFD, emoji, `\n` in the address, category), 500 Hz, the same time, omitted QSOs,
    /// a deleted QSO, a manual X-QSO, an empty callsign, a stored sent exchange, QTC.
    @Test func fullLogMatchesJava() throws {
        let env = try Env()
        var st = StationConfig()
        st.call = " ok1xoe "
        st.name = "Tomáš Łukasz Straße 😀"
        st.address1 = "Nám. 1\nPraha"
        st.address2 = "   "
        st.city = "Praha"
        st.email = "ok1xoe@example.com"
        var qs: [Qso] = []
        var c1 = Self.qso("2026-11-28T00:00:59Z", "DL1ABC", 14_025_500, .cw, received: "599 14")
        c1.rstSent = "599"; c1.serialSent = 1; c1.operator = "ok1xoe"; qs.append(c1)
        var c2 = Self.qso("2026-11-28T00:00:00Z", "ok1žá", 14_024_500, .cw, received: "599 15")
        c2.operator = "OK1KZ"; qs.append(c2)
        var c3 = Self.qso("2026-11-28T00:02:00Z", "W1AW", 0, .cw, received: "599 5")
        c3.band = .m40; qs.append(c3)
        qs.append(Self.qso("2026-11-28T00:03:00Z", "K1A", 0, .cw, received: "599 5"))
        qs.append(Self.qso(nil, "K1B", 7_010_000, .cw, received: "599 5"))
        var c6 = Self.qso("2026-11-28T00:04:00Z", "K1C", 7_400_000, .cw, received: "599 5")
        c6.band = .m40; qs.append(c6)
        qs.append(Self.qso("2026-11-28T00:05:00Z", "K1D", 50_100_000, nil, received: "599 5"))
        qs.append(Self.qso("2026-11-28T00:06:00Z", "K1E", 1_830_000, .ft8, received: "5 99 straße"))
        qs.append(Self.qso("2026-11-28T00:06:00Z", "K1F", 1_830_000, .cw, received: "599"))
        var c10 = Self.qso("2026-11-28T00:07:00Z", "K1G", 3_500_000, .cw, received: "599 5")
        c10.deleted = true; c10.operator = "DELETED"; qs.append(c10)
        var c11 = Self.qso("2026-11-28T00:08:00Z", "K1H", 5_351_500, .cw, received: "599 5")
        c11.xqso = true; qs.append(c11)
        qs.append(Self.qso("2026-11-28T00:09:00Z", "", 14_000_000, .cw, received: "599 5"))
        var c13 = Self.qso("2026-11-28T00:10:00Z", "K1I", 432_100_000, .cw, received: "599 5")
        c13.exchangeSent = "599 - 99"; qs.append(c13)
        var c14 = Self.qso("2026-11-28T00:11:00Z", "K1J", 144_100_000, .cw, received: "599 5")
        c14.rstSent = "  "; qs.append(c14)

        var input = env.input(env.cqww, st, qs)
        input.category = JavaLinkedMap([("OVERLAY", "n/a"), ("MODE", "ph"), ("BAND", "23cm"),
                                        ("OPERATOR", "single-op"), ("POWER", " ")])
        input.sentExchange = Self.zone15
        input.claimedScore = 0
        let words: [String] = Array(repeating: "slovo ", count: 15)
        input.soapbox = "Skvělé podmínky, " + words.joined() + "\r\nDruhý  odstavec\n\nTřetí"
        input.createdBy = "MacContestLogger 1.1.1"
        input.qtcs = [
            QtcRecord(id: 1, contestId: "x", sent: true, partnerCall: "dl1abc", groupNr: 3, groupSize: 10,
                      qsoTime: "0001", qsoCall: "ok1žá", qsoSerial: 7,
                      at: CabrilloExporterTests.instant("2026-11-28T00:20:00Z"), freqHz: 14_025_999, mode: "usb"),
            QtcRecord(id: 2, contestId: "x", sent: false, partnerCall: "W1AW", groupNr: 12, groupSize: 5,
                      qsoTime: "0002", qsoCall: "K1ABCDEFGHIJKLMNOP", qsoSerial: 12345,
                      at: CabrilloExporterTests.instant("2026-11-28T00:21:00Z"), freqHz: 7_000_000, mode: nil),
        ]
        let ref = try Self.reference()
        Self.check("ce1", input, ref)

        // Anchored measured rows — readable even without the reference.
        let text = try CabrilloExporter.export(input).text
        #expect(text.contains("\nQSO: 14025 CW 2026-11-28 0000 OK1XOE 599 15 OK1ZA  599 15\n"))
        #expect(text.contains("\nQSO: 14026 CW 2026-11-28 0000 OK1XOE 599 15 DL1ABC 599 14\n"))
        #expect(text.contains("\nX-QSO:  1830 DG 2026-11-28 0006 OK1XOE 599 15 K1E    5   99\n"
                              + "X-QSO:  1830 CW 2026-11-28 0006 OK1XOE 599 15 K1F    599 -\n"))
        #expect(text.contains("\nNAME: Tomas ?ukasz Stra?e ?\nADDRESS: Nam. 1\nPraha\n"))
    }

    /// `ce2` (an empty log without a callsign) and `ce3` (Multi-Two, operators with separators).
    @Test func emptyLogAndMultiTwoMatchJava() throws {
        let env = try Env()
        let ref = try Self.reference()
        var empty = StationConfig()
        empty.call = ""
        Self.check("ce2", env.input(env.cqww, empty, []), ref)

        let ids: [String] = ["", "", "run", "mult", "third"] // Java null ≡ ""
        var m2: [Qso] = []
        for (i, id) in ids.enumerated() {
            var x = Self.qso("2026-11-28T01:0" + String(i) + ":00Z", "DL" + String(i) + "AB", 14_025_000, .cw,
                             received: "599 14")
            x.stationId = id
            m2.append(x)
        }
        var input = env.input(env.cqww, empty, m2)
        input.category = JavaLinkedMap([("TRANSMITTER", "two")])
        input.operators = " ok1a,ok1b;; ok1c\tok1d "
        Self.check("ce3", input, ref)
    }

    /// Review focus: the column width is Java `String.length()` (UTF-16) **before** `toAscii` —
    /// decomposed `É` (2 units → 1 character), precomposed `ŽÁ`, emoji (2 → one `?`), `ß` → `SS`,
    /// NBSP in the exchange (not `\s`, does not split a token).
    @Test func columnWidthsCountUtf16BeforeAscii() throws {
        let env = try Env()
        let rows: [(String, String)] = [
            ("OK1E\u{0301}", "599 14"), ("ok1žá", "599 15"), ("K1😀", "599 5"),
            ("DL1ABC", "599 😀"), ("W1AW", "599 ß"), ("VE3XX", "599 4\u{0301}"), ("G4ABC", "599\u{00A0}x 14"),
        ]
        var qs: [Qso] = []
        for (i, row) in rows.enumerated() {
            qs.append(Self.qso(Self.minute(i), row.0, 14_025_000, .cw, received: row.1))
        }
        var input = env.input(env.cqww, Self.ok1xoe, qs)
        input.sentExchange = Self.zone15
        Self.check("align", input, try Self.reference())

        let lines = CabrilloExporterTests.qsoLines(try CabrilloExporter.export(input).text)
        #expect(lines[0] == "QSO: 14025 CW 2026-11-28 0000 OK1XOE 599 15 OK1E  599   14")
        #expect(lines[1] == "QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 OK1ZA  599   15")
        #expect(lines[2] == "QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 K1?   599   5")
        #expect(lines[6] == "QSO: 14025 CW 2026-11-28 0006 OK1XOE 599 15 G4ABC  599?X 14")
    }

    /// Review focus: QSOs with the same time in input order (stable sort), a fraction of a second
    /// sorts, but is truncated in the output; a QSO without a time is omitted with a warning.
    @Test func sameTimeKeepsInputOrder() throws {
        let env = try Env()
        let calls: [String] = ["K1C", "K1A", "K1NT", "K1B", "K1E", "K1D"]
        let times: [String?] = ["2026-11-28T00:05:00Z", "2026-11-28T00:05:00Z", nil, "2026-11-28T00:05:30Z",
                                "2026-11-28T00:01:00Z", "2026-11-28T00:05:00.500Z"]
        var qs: [Qso] = []
        for (call, time) in zip(calls, times) {
            qs.append(Self.qso(time, call, 14_025_000, .cw, received: "599 5"))
        }
        var input = env.input(env.cqww, Self.ok1xoe, qs)
        input.sentExchange = Self.zone15
        Self.check("sametime", input, try Self.reference())

        let r = try CabrilloExporter.export(input)
        let order = CabrilloExporterTests.qsoLines(r.text).map { $0.split(separator: " ")[8] }
        #expect(order == ["K1E", "K1C", "K1A", "K1D", "K1B"])
        #expect(r.warnings == ["QSO K1NT vynecháno — chybí pásmo/frekvence nebo čas"])
    }

    /// Review focus: kHz as `Math.round(hz / 1000.0)` (half up), VHF band designation,
    /// without a frequency the lower band edge.
    @Test func frequencyRoundsHalfUpToKilohertz() throws {
        let env = try Env()
        let freqs: [Int] = [14_024_500, 14_025_500, 7_000_499, 3_500_500, 1_830_500, 28_999_999, 0,
                            21_000_001, 52_000_000, 145_500_000, 431_000_000, 10_100_500]
        var qs: [Qso] = []
        for (i, freq) in freqs.enumerated() {
            var q = Self.qso(Self.minute(i), "K" + String(i) + "F", freq, .cw, received: "599 5")
            if freq == 0 { q.band = .m6 }
            qs.append(q)
        }
        var input = env.input(env.cqww, Self.ok1xoe, qs)
        input.sentExchange = Self.zone15
        Self.check("freq500", input, try Self.reference())

        let khz = CabrilloExporterTests.qsoLines(try CabrilloExporter.export(input).text).map {
            $0.dropFirst(4).split(separator: " ")[0]
        }
        #expect(khz == ["14025", "14026", "7000", "3501", "1831", "29000", "50", "21000", "50", "144", "432", "10101"])
    }

    /// Review focus: SOAPBOX wraps at 66 UTF-16 units (75 − `SOAPBOX: `) **before**
    /// `toAscii` — emoji and decomposed `é` take 2, the row after conversion is shorter; a word longer
    /// than 66 is not wrapped; `\r\n`, empty paragraphs, tab, NBSP (does not split a word).
    @Test func soapboxWrapsByUtf16Length() throws {
        let env = try Env()
        let longZ: String = String(repeating: "ž", count: 66) + " " + String(repeating: "ž", count: 65) + " a"
        let first = "Příliš žluťoučký kůň úpěl ďábelské ódy 😀😀😀 a pak ještě jednou e\u{0301}e\u{0301} "
        let second = "slovo slovo 😀 slovo slovo slovo slovo slovo slovo\u{00A0}nbsp slovo slovo\r\n"
        let third = String(repeating: "x", count: 70) + " krátké\n\n\nTřetí odstavec\t s tabulátorem "
        var input = env.input(env.cqww, Self.ok1xoe, [])
        input.soapbox = first + second + third + longZ
        Self.check("soapbox", input, try Self.reference())

        let box = try CabrilloExporter.export(input).text.split(separator: "\n").filter { $0.hasPrefix("SOAPBOX:") }
        #expect(box[0] == "SOAPBOX: Prilis zlutoucky kun upel dabelske ody ??? a pak jeste jednou")
        #expect(box[1] == "SOAPBOX: ee slovo slovo ? slovo slovo slovo slovo slovo slovo?nbsp slovo")
        #expect(box[3].utf16.count == 79) // 70 × x — a long word is not wrapped
    }

    /// The category dictionary, N/A, a negative CLAIMED-SCORE, an empty CREATED-BY.
    @Test func categoriesMatchJava() throws {
        let env = try Env()
        let ref = try Self.reference()
        var input = env.input(env.cqww, Self.ok1xoe, [])
        input.category = JavaLinkedMap([
            ("MODE", " phone "), ("BAND", "70cm"), ("OPERATOR", " N/a "), ("ASSISTED", "assisted"),
            ("STATION", "fixed"), ("TIME", "24-hours"), ("TRANSMITTER", "one"), ("OVERLAY", "classic"),
            ("POWER", "qrp"), ("UNKNOWN", "x"),
        ])
        input.claimedScore = -5
        input.createdBy = "  "
        Self.check("category", input, ref)

        for mode in ["ft8", "FT4", "psk", "jt65", "PH", "digi", "ssb", "rtty"] {
            var single = env.input(env.cqww, Self.ok1xoe, [])
            single.category = JavaLinkedMap([("MODE", mode), ("BAND", mode == "PH" ? "23CM" : "20M")])
            Self.check("catmode-" + JavaText.toLowerCase(mode), single, ref)
        }
    }

    /// Operators from the log: order of first occurrence, duplicates, empty ones, `ß` → `SS`.
    @Test func operatorsFromLogMatchJava() throws {
        let env = try Env()
        let ops: [String] = [" ok1kz ", "OK1XOE", "", "   ", "ok1kz", "OK1HX", "ok1ß"]
        var qs: [Qso] = []
        for (i, op) in ops.enumerated() {
            var q = Self.qso(Self.minute(i), "K" + String(i) + "O", 14_025_000, .cw, received: "599 5")
            q.operator = op
            qs.append(q)
        }
        Self.check("operators", env.input(env.cqww, Self.ok1xoe, qs), try Self.reference())
    }

    /// A stored sent exchange: fewer tokens, `-`, a control character, more tokens, `rstSent`, a mode outside the contest.
    @Test func storedSentExchangeMatchesJava() throws {
        let env = try Env()
        let stored: [String] = ["", "579", "- 16", "\u{0001}", "599 16 99", " 5nn\t07 ", "-"]
        var qs: [Qso] = []
        for (i, sent) in stored.enumerated() {
            var q = Self.qso(Self.minute(i), "K" + String(i) + "S", 14_025_000, i == 6 ? .ssb : .cw,
                             received: "599 5")
            q.exchangeSent = sent
            q.rstSent = i == 2 ? "ignored" : i == 3 ? "  " : "559"
            qs.append(q)
        }
        var input = env.input(env.cqww, Self.ok1xoe, qs)
        input.sentExchange = JavaLinkedMap([("zone", " 1 5 ")])
        Self.check("sentstored", input, try Self.reference())
    }

    /// A received exchange: fallback `rstRcvd`/`serialRcvd`, `receivedFields` → `nil`, more tokens,
    /// fields in `sentOrder`/`receivedOrder` that the definition does not know.
    @Test func receivedExchangeMatchesJava() throws {
        let yaml = CabrilloExporterTests.wpxYaml.replacingOccurrences(
            of: "sentOrder: [rst, nr], receivedOrder: [rst, nr]",
            with: "sentOrder: [rst, nr, nr, bogus], receivedOrder: [nr, rst, bogus]")
        let wpx = try CabrilloExporterTests.def(yaml)
        var r1 = Self.qso("2026-03-28T10:00:00Z", "OK2A", 14_250_000, .ssb)
        r1.rstRcvd = "58"; r1.serialRcvd = 33; r1.serialSent = 7
        var r2 = Self.qso("2026-03-28T10:01:00Z", "OK2B", 14_250_000, .ssb, received: "57 12 extra")
        r2.rstRcvd = "11"
        let r3 = Self.qso("2026-03-28T10:02:00Z", "NULL1", 14_250_000, .ssb, received: "57 12")
        var r4 = Self.qso("2026-03-28T10:03:00Z", "OK2C", 14_250_000, .ssb, received: "57")
        r4.serialRcvd = -4
        let received: [Field] = (wpx.exchange?.received ?? []).compactMap { $0 }
        let input = CabrilloExporter.Input(definition: wpx, station: Self.ok1xoe, qsos: [r1, r2, r3, r4],
                                           receivedFields: { $0 == "NULL1" ? nil : received })
        Self.check("received", input, try Self.reference())
    }

    /// A definition without a `cabrillo:` block / with an empty `contestName` → `IllegalArgumentException`
    /// with the same text; a definition with only `contestName` (without field order and without an exchange).
    @Test func definitionWithoutCabrilloMatchesJava() throws {
        let ref = try Self.reference()
        let base = "schemaVersion: 1\nid: x\nmetadata: { name: X }\nbands: [20m]\nmodes: [CW]\nexchange:\n"
            + "  sent: []\n  received: []\nscoring:\n  qsoPoints: { mode: FIRST_MATCH, default: 1 }\n"
            + "  total: \"qsoPoints\"\n"
        let none: (String) throws -> [Field]? = { _ in [] }
        let nocab = try CabrilloExporterTests.def(base)
        Self.check("nocab", CabrilloExporter.Input(definition: nocab, station: Self.ok1xoe, qsos: [],
                                                   receivedFields: none), ref)
        let blank = try CabrilloExporterTests.def(base + "cabrillo: { contestName: \"  \" }\n")
        Self.check("blankcab", CabrilloExporter.Input(definition: blank, station: Self.ok1xoe, qsos: [],
                                                      receivedFields: none), ref)
        #expect(throws: CabrilloExportError.illegalArgument(
            message: "Definice závodu nemá blok cabrillo: — export do Cabrilla není možný")) {
            try CabrilloExporter.export(CabrilloExporter.Input(definition: nocab, station: Self.ok1xoe, qsos: [],
                                                               receivedFields: none))
        }

        let bare = "schemaVersion: 1\nid: y\nmetadata: { name: Y }\nbands: [20m]\nmodes: [CW, SSB]\n"
            + "scoring:\n  qsoPoints: { mode: FIRST_MATCH, default: 1 }\n  total: \"qsoPoints\"\n"
            + "cabrillo: { contestName: Y }\n"
        let b1 = Self.qso("2026-11-28T00:00:00Z", "DL1ABC", 14_025_000, .fm, received: "599 14")
        Self.check("bare", CabrilloExporter.Input(definition: try CabrilloExporterTests.def(bare),
                                                  station: Self.ok1xoe, qsos: [b1], receivedFields: none), ref)
    }

    /// An error from `receivedFields` (a Java exception from `Function`) passes through `export` unchanged.
    @Test func receivedFieldsErrorPropagates() throws {
        struct Boom: Error, Equatable {}
        let d = try CabrilloExporterTests.def(CabrilloExporterTests.cqwwYaml)
        let q = Self.qso("2026-11-28T00:00:00Z", "DL1ABC", 14_025_000, .cw, received: "599 14")
        let input = CabrilloExporter.Input(definition: d, station: Self.ok1xoe, qsos: [q],
                                           receivedFields: { _ in throw Boom() })
        #expect(throws: Boom()) { try CabrilloExporter.export(input) }
    }

    // MARK: - functions

    @Test func helperFunctionsMatchJava() throws {
        let ref = try Self.reference()
        let qtcs: [QtcRecord] = Self.qtcCases()
        var qtcIndex = 0
        for row in ref.functions {
            switch row[1] {
            case "toAscii":
                #expect(CabrilloExporter.toAscii(Self.unescape(row[2])) == Self.unescape(row[3]), "\(row)")
            case "wrap":
                let lines = CabrilloExporter.wrap(Self.unescape(row[2]), width: Int(row[3])!)
                #expect(lines.joined(separator: "\n") + "|" + String(lines.count) == Self.unescape(row[4]), "\(row)")
            case "qtc":
                let line = QtcPlanner.cabrilloLine(qtcs[qtcIndex], "OK1XOE")
                #expect(line == Self.unescape(row[3]), "\(row)")
                qtcIndex += 1
            default:
                Issue.record("unknown function \(row[1])")
            }
        }
        #expect(qtcIndex == qtcs.count)
    }

    /// The same QTCs as the probe (`functions`), in the same order.
    static func qtcCases() -> [QtcRecord] {
        func record(_ sent: Bool, _ partner: String, _ nr: Int, _ size: Int, _ time: String, _ call: String,
                    _ serial: Int, _ at: String, _ freq: Int64, _ mode: String?) -> QtcRecord {
            QtcRecord(contestId: nil, sent: sent, partnerCall: partner, groupNr: nr, groupSize: size, qsoTime: time,
                      qsoCall: call, qsoSerial: serial, at: CabrilloExporterTests.instant(at), freqHz: freq, mode: mode)
        }
        let newYear = "2026-01-01T00:00:00Z"
        return [
            record(true, "dl1abc", 3, 10, "0001", "ok1žá", 7, "2026-11-28T00:20:59Z", 14_025_999, "usb"),
            record(false, "W1AW", 12, 5, "0002", "K1ABCDEFGHIJKLMNOP", 12345, "2026-11-28T23:59:00Z", 7_000_000, nil),
            record(true, "K1ABCDEFGHIJKLMNOPQ", 123, 1234, "2359", "x", -1, newYear, 999, "fm"),
            record(false, "ß", 1, 1, "", "", 0, newYear, 123_456_789, "rtty"),
            record(true, "s", 1, 1, "1", "c", 99999, newYear, 0, "Lsb"),
            record(true, "s", 1, 1, "1", "c", 1, newYear, 1_000, "psk"),
            record(true, "s", 1, 1, "1", "c", 1, newYear, -1_500, "am"),
            record(true, "s", 1, 1, "1", "c", 1, newYear, 1_000, "ssb"),
        ]
    }

    // MARK: - export → ScoreCheck over all definitions

    /// For each of the 22 definitions: log QSOs via `ContestSession` (inputs from the `Q` rows), the score
    /// like Java (`S`), the export byte for byte like Java (`T`) and `ScoreCheck.evaluate` of the export like Java
    /// (`C`). VHF contests (`iaru-r1-*`, `marconi-memorial`) do **not** pass the check in Java
    /// (`qsoCount 0`, `computed 0` × claimed 882) — a measured Java property, here it is just repeated.
    @Test func roundTripMatchesJavaForAllDefinitions() throws {
        let env = try Env()
        let ref = try Self.reference()
        #expect(ref.order.count == 22)
        #expect(ref.order == env.defs.compactMap(\.id))
        let sent = JavaLinkedMap<String>([
            ("zone", "15"), ("qth", "OK"), ("power", "100"), ("exch", "28"), ("loc", "JO70FC"), ("out", "APH"),
            ("grid", "JO70"), ("state", ""),
        ])
        for d in env.defs {
            let id = try #require(d.id)
            let session = ContestSession(definition: d, dxcc: env.dxcc, registry: env.registry, myCall: "OK1XOE",
                                         myGrid: "JO70FC")
            var qsos: [Qso] = []
            for row in ref.inputs[id] ?? [] {
                let index = Int(row[2])!
                let freq = Int(row[4])!
                let mode = try #require(Mode(rawValue: row[5]))
                var exch = JavaLinkedMap<String>()
                for pair in row.dropFirst(6) {
                    let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    exch.put(parts[0], parts[1])
                }
                #expect(try session.activeReceivedFields(call: row[3]).map(\.id) == exch.keys, "\(id) \(row)")
                let at = CabrilloExporterTests.instant("2026-11-28T12:00:00Z").addingTimeInterval(TimeInterval(60 * index))
                let band = try #require(Band.from(frequencyHz: freq))
                try session.log(call: row[3], band: band.adif, mode: mode.rawValue, receivedRaw: exch, at: at)
                var q = Qso()
                q.timestampUtc = at
                q.call = row[3]
                q.freqHz = freq
                q.mode = mode
                q.rstSent = mode.defaultRst
                q.serialSent = index + 1
                q.exchangeRcvd = exch.entries.map { $0.value ?? "null" }.joined(separator: " ")
                qsos.append(q)
            }
            let score = try session.score().total
            #expect(score == ref.scores[id], "\(id): skóre session")

            var station = StationConfig()
            station.call = "OK1XOE"
            station.gridSquare = "JO70FC"
            var input = CabrilloExporter.Input(definition: d, station: station, qsos: qsos,
                                               receivedFields: { try session.activeReceivedFields(call: $0) })
            input.sentExchange = sent
            input.claimedScore = score
            let r = try CabrilloExporter.export(input)
            let t = try #require(ref.exports[id])
            #expect(String(r.qsoCount) == t[2], "\(id): qsoCount")
            #expect(r.text == Self.unescape(t[3]), "\(id): text\n\(r.text)")
            #expect(r.warnings.joined(separator: "\n") == Self.unescape(t[4]), "\(id): warnings")

            let c = try ScoreCheck.evaluate(fileName: "export.log", content: r.text, definitions: env.defs,
                                            dxcc: env.dxcc, registry: env.registry)
            // Texts like the probe (`esc`: non-ASCII `\uXXXX`, `\N` = null), so that Czech text is compared too.
            func esc(_ text: String?) -> String { IoEdgeFixture.escape(text.map { Array($0.utf16) }) }
            let groups = c.multByGroup.entries.map { esc($0.key ?? "null") + "=" + String($0.value ?? 0) }
            let actual: [String] = [
                "C", id, esc(c.contest), String(c.qsoCount), String(c.qsoPoints), String(c.multTotal),
                groups.joined(separator: ","), String(c.computed), c.claimed.map { String($0) } ?? "\\N",
                c.pass ? "true" : "false", c.unresolvedCalls.joined(separator: ","), esc(c.error),
            ]
            #expect(actual == ref.checks[id], "\(id): ScoreCheck")
        }
    }

    // MARK: - performance

    /// 10,000 QSOs via a real `ContestSession` (cq-ww-cw) in a debug build; the time is only printed.
    @Test func tenThousandQsosExport() throws {
        let env = try Env()
        let start = CabrilloExporterTests.instant("2026-11-28T00:00:00Z")
        let qsos: [Qso] = (0..<10_000).map { i in
            var q = Qso()
            q.timestampUtc = start.addingTimeInterval(TimeInterval((i * 7919) % 172_800))
            q.call = (i % 3 == 0 ? "DL" : i % 3 == 1 ? "W" : "OK") + String(i % 10) + "T" + String(i)
            q.freqHz = 14_000_000 + (i % 350) * 1_000 + 500
            q.mode = .cw
            q.rstSent = "599"
            q.serialSent = i + 1
            q.exchangeRcvd = "599 " + String(i % 40 + 1)
            q.operator = i % 2 == 0 ? "OK1XOE" : "OK1KZ"
            return q
        }
        var input = env.input(env.cqww, Self.ok1xoe, qsos)
        input.sentExchange = Self.zone15
        input.soapbox = "Tomáš 😀 " + String(repeating: "slovo ", count: 200)
        var result: CabrilloExporter.Result?
        let elapsed = try ContinuousClock().measure { result = try CabrilloExporter.export(input) }
        let r = try #require(result)
        print("CabrilloExportPerformance: 10 000 QSO, \(r.text.utf8.count) B — export \(elapsed)")
        #expect(r.qsoCount == 10_000)
        #expect(r.warnings.isEmpty)
    }
}
