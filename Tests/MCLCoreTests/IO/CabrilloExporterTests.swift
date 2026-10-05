import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/CabrilloExporterTest` (19 tests). The definitions are inline YAML via
/// `ContestDefinitionLoader` as in Java; received fields without `ContestSession` (`allReceived`),
/// so `receivedFields` does not throw. Measured edges (alignment by UTF-16, 500 Hz, the same time,
/// wrapping) are in `CabrilloExportMeasuredTests`.
@Suite struct CabrilloExporterTests {

    typealias Field = ContestDefinition.ExchangeField

    static let cqwwYaml = """
        schemaVersion: 1
        id: cq-ww-cw
        metadata: { name: "CQ WW DX Contest — CW" }
        bands: [160m, 80m, 40m, 20m, 15m, 10m]
        modes: [CW]
        exchange:
          sent:
            - { id: rst,  type: RST,     source: AUTO_RST }
            - { id: zone, type: CQ_ZONE, source: FROM_STATION }
          received:
            - { id: rst,  type: RST,     required: true }
            - { id: zone, type: CQ_ZONE, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        cabrillo: { contestName: CQ-WW-CW, sentOrder: [rst, zone], receivedOrder: [rst, zone] }

        """

    static let okomYaml = """
        schemaVersion: 1
        id: ok-om-dx-cw
        metadata: { name: "OK-OM DX" }
        bands: [80m, 40m, 20m]
        modes: [CW]
        exchange:
          sent:
            - { id: rst, type: RST,  source: AUTO_RST }
            - { id: out, type: TEXT, source: FROM_STATION }
          received:
            - { id: rst,      type: RST,      required: true }
            - { id: district, type: DISTRICT, required: true, appliesWhen: { workedClass: okom } }
            - { id: nr,       type: SERIAL,   required: true, appliesWhen: { workedClass: dx } }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        cabrillo: { contestName: OK-OM-DX-CW, sentOrder: [rst, out], receivedOrder: [rst, district, nr] }

        """

    static let wpxYaml = """
        schemaVersion: 1
        id: cq-wpx-ssb
        metadata: { name: "CQ WPX SSB" }
        bands: [20m, 2m, 70cm]
        modes: [SSB]
        exchange:
          sent:
            - { id: rst, type: RST,    source: AUTO_RST }
            - { id: nr,  type: SERIAL, source: AUTO_SERIAL }
          received:
            - { id: rst, type: RST,    required: true }
            - { id: nr,  type: SERIAL, required: true }
        scoring:
          qsoPoints: { mode: FIRST_MATCH, default: 1 }
          total: "qsoPoints"
        cabrillo: { contestName: CQ-WPX-SSB, sentOrder: [rst, nr], receivedOrder: [rst, nr] }

        """

    static func def(_ yaml: String) throws -> ContestDefinition {
        try ContestDefinitionLoader.load(Data(yaml.utf8))
    }

    static func allReceived(_ d: ContestDefinition) -> (String) throws -> [Field]? {
        let received: [Field] = (d.exchange?.received ?? []).compactMap { $0 }
        return { _ in received }
    }

    static func station() -> StationConfig {
        var s = StationConfig()
        s.call = "OK1XOE"
        s.name = "Tomas Kaplan"
        s.address1 = "Nam. 1"
        s.city = "Praha"
        s.zip = "11000"
        s.country = "Czech Republic"
        s.gridSquare = "JO70"
        s.club = "OK1KHL"
        s.email = "ok1xoe@example.com"
        return s
    }

    static func instant(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        if text.contains(".") {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }
        return formatter.date(from: text)!
    }

    static func qso(_ time: String, _ call: String, _ freqHz: Int, _ mode: Mode?, _ rstSent: String = "",
                    _ serialSent: Int? = nil, _ exchangeRcvd: String = "") -> Qso {
        var q = Qso()
        q.timestampUtc = instant(time)
        q.call = call
        q.freqHz = freqHz
        q.mode = mode
        q.rstSent = rstSent
        q.serialSent = serialSent
        q.exchangeRcvd = exchangeRcvd
        return q
    }

    static func map(_ pairs: (String, String)...) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs.map { ($0.0, $0.1) })
    }

    /// Java `cqwwSsb`: the phone version of CQ WW — FM stays an ordinary QSO.
    static func cqwwSsb(_ qsos: [Qso]) throws -> CabrilloExporter.Input {
        let d = try def(cqwwYaml.replacingOccurrences(of: "modes: [CW]", with: "modes: [SSB]"))
        var input = CabrilloExporter.Input(definition: d, station: station(), qsos: qsos,
                                           receivedFields: allReceived(d))
        input.category = map(("MODE", "SSB"))
        input.sentExchange = map(("zone", "15"))
        input.createdBy = "MacContestLogger 1.0.0"
        return input
    }

    static func cqww(_ qsos: [Qso]) throws -> CabrilloExporter.Input {
        let d = try def(cqwwYaml)
        var input = CabrilloExporter.Input(definition: d, station: station(), qsos: qsos,
                                           receivedFields: allReceived(d))
        input.category = map(("OPERATOR", "SINGLE-OP"), ("BAND", "ALL"), ("MODE", "CW"), ("POWER", "LOW"),
                             ("ASSISTED", "NON-ASSISTED"), ("TRANSMITTER", "ONE"), ("OVERLAY", "N/A"))
        input.sentExchange = map(("zone", "15"))
        input.claimedScore = 1234
        input.createdBy = "MacContestLogger 1.0.0"
        return input
    }

    static func qsoLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).filter { $0.hasPrefix("QSO:") }
    }

    // MARK: - port of CabrilloExporterTest

    /// Java `headerFollowsCabrillo3`.
    @Test func headerFollowsCabrillo3() throws {
        var input = try Self.cqww([])
        input.soapbox = "Skvělé podmínky"
        let text = try CabrilloExporter.export(input).text

        #expect(text.hasPrefix("START-OF-LOG: 3.0\n"))
        let expected: [String] = [
            "CONTEST: CQ-WW-CW\n", "CALLSIGN: OK1XOE\n", "CATEGORY-OPERATOR: SINGLE-OP\n",
            "CATEGORY-BAND: ALL\n", "CATEGORY-MODE: CW\n", "CATEGORY-POWER: LOW\n",
            "CATEGORY-ASSISTED: NON-ASSISTED\n", "CATEGORY-TRANSMITTER: ONE\n", "CLAIMED-SCORE: 1234\n",
            "CLUB: OK1KHL\n", "NAME: Tomas Kaplan\n", "ADDRESS: Nam. 1\n", "ADDRESS-CITY: Praha\n",
            "ADDRESS-POSTALCODE: 11000\n", "ADDRESS-COUNTRY: Czech Republic\n", "EMAIL: ok1xoe@example.com\n",
            "GRID-LOCATOR: JO70\n", "CREATED-BY: MacContestLogger 1.0.0\n",
        ]
        for line in expected {
            #expect(text.contains(line), "\(line)")
        }
        #expect(!text.contains("CATEGORY-OVERLAY"), "N/A is not written — it is not a valid Cabrillo value")
        #expect(text.contains("SOAPBOX: Skvele podminky\n"), "diacritics gone — Cabrillo is ASCII")
        #expect(text.hasSuffix("END-OF-LOG:\n"))
    }

    /// Java `qsoLineHasFreqModeDateTimeAndBothExchanges`.
    @Test func qsoLineHasFreqModeDateTimeAndBothExchanges() throws {
        let q = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_300, .cw, "599", 1, "599 14")

        let lines = Self.qsoLines(try CabrilloExporter.export(try Self.cqww([q])).text)

        #expect(lines == ["QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14"])
    }

    /// Java `columnsAreAlignedAcrossQsos`.
    @Test func columnsAreAlignedAcrossQsos() throws {
        let qsos = [
            Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 1_830_000, .cw, "599", 1, "599 14"),
            Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .cw, "579", 2, "599 5"),
        ]

        let lines = Self.qsoLines(try CabrilloExporter.export(try Self.cqww(qsos)).text)

        #expect(lines[0] == "QSO:  1830 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 14")
        #expect(lines[1] == "QSO: 14025 CW 2026-11-28 0002 OK1XOE 579 15 K1A    599 5")
    }

    /// Java `qsosAreSortedByTime`.
    @Test func qsosAreSortedByTime() throws {
        let qsos = [
            Self.qso("2026-11-28T00:05:00Z", "K1A", 14_025_000, .cw, "599", 2, "599 5"),
            Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_026_000, .cw, "599", 1, "599 14"),
        ]

        let lines = Self.qsoLines(try CabrilloExporter.export(try Self.cqww(qsos)).text)

        #expect(lines[0].contains("DL1ABC"))
        #expect(lines[1].contains("K1A"))
    }

    /// Java `serialFromQsoAndBandDesignatorAboveHf`.
    @Test func serialFromQsoAndBandDesignatorAboveHf() throws {
        let d = try Self.def(Self.wpxYaml)
        let qsos = [
            Self.qso("2026-03-28T10:00:00Z", "OK2A", 14_250_000, .ssb, "59", 7, "59 12"),
            Self.qso("2026-03-28T10:01:00Z", "OK2B", 144_300_000, .ssb, "59", 8, "59 3"),
            Self.qso("2026-03-28T10:02:00Z", "OK2C", 432_200_000, .fm, "59", 9, "59 4"),
        ]
        let input = CabrilloExporter.Input(definition: d, station: Self.station(), qsos: qsos,
                                           receivedFields: Self.allReceived(d))

        let lines = Self.qsoLines(try CabrilloExporter.export(input).text)

        #expect(lines[0] == "QSO: 14250 PH 2026-03-28 1000 OK1XOE 59 7 OK2A 59 12")
        #expect(lines[1] == "QSO:   144 PH 2026-03-28 1001 OK1XOE 59 8 OK2B 59 3")
        #expect(lines[2] == "QSO:   432 FM 2026-03-28 1002 OK1XOE 59 9 OK2C 59 4")
    }

    /// Java `conditionalExchangeWritesOnlyFieldsActiveForTheCall`.
    @Test func conditionalExchangeWritesOnlyFieldsActiveForTheCall() throws {
        let d = try Self.def(Self.okomYaml)
        // The OK/OM other station sends the district, DX the serial number — like workedClass in the engine.
        let received: [Field] = (d.exchange?.received ?? []).compactMap { $0 }
        let active: (String) throws -> [Field]? = { call in
            let workedClass = call.hasPrefix("OK") ? "okom" : "dx"
            return received.filter { f in
                guard let applies = f.appliesWhen else { return true }
                return JavaText.equals(applies.workedClass ?? "", workedClass)
            }
        }
        let qsos = [
            Self.qso("2026-12-05T00:01:00Z", "OK1ABC", 3_520_000, .cw, "599", 1, "599 APH"),
            Self.qso("2026-12-05T00:02:00Z", "DL1ABC", 3_521_000, .cw, "599", 2, "599 17"),
        ]
        var input = CabrilloExporter.Input(definition: d, station: Self.station(), qsos: qsos, receivedFields: active)
        input.sentExchange = Self.map(("out", "APH"))

        let lines = Self.qsoLines(try CabrilloExporter.export(input).text)

        #expect(lines[0] == "QSO: 3520 CW 2026-12-05 0001 OK1XOE 599 APH OK1ABC 599 APH")
        #expect(lines[1] == "QSO: 3521 CW 2026-12-05 0002 OK1XOE 599 APH DL1ABC 599 17")
    }

    /// Java `missingReceivedValueIsFlaggedNotShifted`.
    @Test func missingReceivedValueIsFlaggedNotShifted() throws {
        let q = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599")

        let r = try CabrilloExporter.export(try Self.cqww([q]))

        // A missing value holds its column (nothing shifts); the row has since been
        // written as an X-QSO, because an incomplete QSO makes no sense to claim.
        #expect(r.text.contains("\nX-QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 15 DL1ABC 599 -"), "\(r.text)")
        #expect(r.warnings.contains { $0.contains("DL1ABC") })
    }

    /// Java `rstAndSerialFallBackToQsoColumns`.
    @Test func rstAndSerialFallBackToQsoColumns() throws {
        // Imported QSOs have no exchangeRcvd — the report and number are only in their own columns.
        let d = try Self.def(Self.wpxYaml)
        var q = Self.qso("2026-03-28T10:00:00Z", "OK2A", 14_250_000, .ssb, "59", 7)
        q.rstRcvd = "58"
        q.serialRcvd = 33
        let input = CabrilloExporter.Input(definition: d, station: Self.station(), qsos: [q],
                                           receivedFields: Self.allReceived(d))

        let r = try CabrilloExporter.export(input)

        #expect(Self.qsoLines(r.text).first == "QSO: 14250 PH 2026-03-28 1000 OK1XOE 59 7 OK2A 58 33")
        #expect(r.warnings.isEmpty)
    }

    /// Java `operatorsFromSetupOrFromLog`.
    @Test func operatorsFromSetupOrFromLog() throws {
        var a = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        a.operator = "OK1XOE"
        var b = Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .cw, "599", 2, "599 5")
        b.operator = "OK1KZ"

        #expect(try CabrilloExporter.export(try Self.cqww([a, b])).text.contains("OPERATORS: OK1XOE OK1KZ\n"))
        var input = try Self.cqww([a, b])
        input.operators = "OK1XOE OK1KZ OK1HX"
        #expect(try CabrilloExporter.export(input).text.contains("OPERATORS: OK1XOE OK1KZ OK1HX\n"))
    }

    /// Java `longSoapboxIsWrappedAndMultilinePreserved`.
    @Test func longSoapboxIsWrappedAndMultilinePreserved() throws {
        let words: [String] = Array(repeating: "slovo", count: 20)
        var input = try Self.cqww([])
        input.soapbox = "Prvni radek\n" + words.joined(separator: " ")

        let text = try CabrilloExporter.export(input).text

        let box = text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("SOAPBOX:") }
        #expect(box.first == "SOAPBOX: Prvni radek")
        #expect(box.count >= 3)
        #expect(box.allSatisfy { $0.utf16.count <= 75 })
    }

    /// Java `transmitterIdColumnForMultiTwo`.
    @Test func transmitterIdColumnForMultiTwo() throws {
        var a = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        a.stationId = "run"
        var b = Self.qso("2026-11-28T00:02:00Z", "K1A", 7_025_000, .cw, "599", 2, "599 5")
        b.stationId = "mult"
        var input = try Self.cqww([a, b])
        input.category = Self.map(("OPERATOR", "MULTI-OP"), ("TRANSMITTER", "TWO"))

        let lines = Self.qsoLines(try CabrilloExporter.export(input).text)

        #expect(lines[0].hasSuffix(" 0"))
        #expect(lines[1].hasSuffix(" 1"))
    }

    /// Java `categoryValuesAreMappedToCabrilloVocabulary`.
    @Test func categoryValuesAreMappedToCabrilloVocabulary() throws {
        var input = try Self.cqww([])
        input.category = Self.map(("MODE", "DIGITAL"), ("BAND", "70CM"))

        let text = try CabrilloExporter.export(input).text

        #expect(text.contains("CATEGORY-MODE: DIGI\n"))
        #expect(text.contains("CATEGORY-BAND: 432\n"))
    }

    /// Java `missingCallsignIsWarned`.
    @Test func missingCallsignIsWarned() throws {
        let d = try Self.def(Self.cqwwYaml)
        var s = Self.station()
        s.call = ""

        let r = try CabrilloExporter.export(CabrilloExporter.Input(definition: d, station: s, qsos: [],
                                                                   receivedFields: Self.allReceived(d)))

        #expect(!r.warnings.isEmpty)
    }

    /// Java `roundTripThroughCabrilloReader`.
    @Test func roundTripThroughCabrilloReader() throws {
        let q = Self.qso("2026-11-28T13:45:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")

        let back = try CabrilloReader().read(try CabrilloExporter.export(try Self.cqww([q])).text)

        #expect(back.count == 1)
        #expect(back.first?.call == "DL1ABC")
        #expect(back.first?.timestampUtc == Self.instant("2026-11-28T13:45:00Z"))
        #expect(back.first?.mode == .cw)
    }

    /// Java `storedSentExchangeOverridesSetupPerQso`.
    @Test func storedSentExchangeOverridesSetupPerQso() throws {
        // Rover: the district changes during the contest, the QSO stores the one it was transmitted from.
        var a = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        a.exchangeSent = "599 16"
        var b = Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .cw, "599", 2, "599 5")
        b.exchangeSent = "599 -" // an empty field → the default from the setup

        let lines = Self.qsoLines(try CabrilloExporter.export(try Self.cqww([a, b])).text)

        #expect(lines[0] == "QSO: 14025 CW 2026-11-28 0001 OK1XOE 599 16 DL1ABC 599 14")
        #expect(lines[1] == "QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 K1A    599 5")
    }

    /// Java `xqsoIsWrittenAsXQsoLine`.
    @Test func xqsoIsWrittenAsXQsoLine() throws {
        let a = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        var b = Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .cw, "599", 2, "599 5")
        b.xqso = true

        let text = try CabrilloExporter.export(try Self.cqww([a, b])).text

        #expect(text.contains("\nQSO: 14025 CW 2026-11-28 0001"))
        #expect(text.contains("\nX-QSO: 14025 CW 2026-11-28 0002 OK1XOE 599 15 K1A"))
    }

    /// Java `qsoInAModeTheContestDoesNotHaveIsWrittenAsXQso`.
    @Test func qsoInAModeTheContestDoesNotHaveIsWrittenAsXQso() throws {
        // CQ WW CW has modes: [CW]. An FT8 contact (typically from WSJT-X) does not count toward the score,
        // so the program should not even claim it — in the file it belongs as an X-QSO.
        let cw = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        let ft8 = Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .ft8, "599", 2, "599 5")

        let r = try CabrilloExporter.export(try Self.cqww([cw, ft8]))

        #expect(r.text.contains("\nQSO: 14025 CW 2026-11-28 0001"))
        #expect(r.text.contains("\nX-QSO: 14025 DG 2026-11-28 0002"))
        #expect(r.warnings.contains { $0.contains("K1A") && $0.contains("X-QSO") },
                "the export should warn about the relabelling: \(r.warnings)")
    }

    /// Java `qsoWithAnIncompleteExchangeIsWrittenAsXQso`.
    @Test func qsoWithAnIncompleteExchangeIsWrittenAsXQso() throws {
        // A zone is missing — the row would go to the robot as claimed and could not be verified.
        let plne = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .cw, "599", 1, "599 14")
        let neuplne = Self.qso("2026-11-28T00:02:00Z", "K1A", 14_025_000, .cw, "599", 2, "599")

        let r = try CabrilloExporter.export(try Self.cqww([plne, neuplne]))

        #expect(r.text.contains("\nQSO: 14025 CW 2026-11-28 0001"))
        #expect(r.text.contains("\nX-QSO: 14025 CW 2026-11-28 0002"), "\(r.text)")
        #expect(r.warnings.contains { $0.contains("K1A") && $0.contains("X-QSO") },
                "the export should warn about the relabelling: \(r.warnings)")
    }

    /// Java `modeOfTheSameFamilyStaysANormalQso`.
    @Test func modeOfTheSameFamilyStaysANormalQso() throws {
        // A strict name match would throw out valid contacts — FM in a phone contest stays a QSO.
        let fm = Self.qso("2026-11-28T00:01:00Z", "DL1ABC", 14_025_000, .fm, "59", 1, "59 14")

        let text = try CabrilloExporter.export(try Self.cqwwSsb([fm])).text

        #expect(text.contains("\nQSO: 14025 FM 2026-11-28 0001"), "\(text)")
    }
}
