import Foundation
import Testing
@testable import MCLCore

/// Replays the `ingest` rows of `IntegrationsProbe.java` — `AppState.onN1mmContact` and `importAdifRecord` of the
/// Kotlin v1.1.1 over an in-memory logbook and a real `ContestController` — through `ExternalQsoIngest`, the
/// contest runtime and the log list, and compares outcome, status text and the logged QSO.
@Suite struct ExternalQsoIngestTests {

    typealias F = IntegrationsFixture

    static let contests: [String: String] = ["cqww": "cq-ww-cw", "wwdigi": "ww-digi", "wpx": "cq-wpx-cw"]

    /// The probe's `qsoText`.
    static func qsoText(_ q: Qso, withTime: Bool) -> String {
        func text(_ value: String) -> String { F.escape(value.isEmpty ? nil : value) }
        func num(_ value: Int?) -> String { value.map { String($0) } ?? "null" }
        let time: String = withTime ? q.timestampUtc.map { JavaInstant(date: $0).toString() } ?? "null" : "-"
        let cols: [String] = [
            F.escape(q.call), q.band?.adif ?? "<null>", q.mode?.rawValue ?? "<null>", String(q.freqHz),
            text(q.rstSent), text(q.rstRcvd), text(q.exchangeSent), text(q.exchangeRcvd), num(q.serialSent),
            num(q.serialRcvd), text(q.comment), q.runMode.rawValue, String(q.imported), time,
        ]
        return cols.joined(separator: "|")
    }

    static func hasTimestamp(_ input: String) -> Bool {
        let pattern = "(?s).*timestamp>\\d{4}-\\d\\d-\\d\\d \\d\\d:\\d\\d:\\d\\d<.*"
        return input.range(of: pattern, options: .regularExpression) != nil || input.contains("qso_date")
    }

    /// One probe row replayed; returns the columns after the input.
    static func replay(_ row: [String], runtime: ContestRuntime, logged: inout [Qso]) -> [String] {
        let isN1mm: Bool = row[2] == "n1mm"
        let input: String = F.unescape(row[3])
        // The closure is only called synchronously inside this function, on the test's thread.
        nonisolated(unsafe) let fields = runtime
        let snapshot = IngestSnapshot(
            qsos: logged, isContestActive: runtime.isActive,
            exchangeFields: { call throws(ExpressionError) in try fields.exchangeFields(call: call) },
            nextSerial: logged.count + 1, runMode: .searchAndPounce, ownCall: F.ownCall)
        let outcome: IngestOutcome = isN1mm
            ? ExternalQsoIngest.n1mm(input, snapshot: snapshot)
            : ExternalQsoIngest.adif(input, source: row[2], snapshot: snapshot)
        switch outcome {
        case .drop:
            return ["drop"]
        case .status(let status):
            return ["status", F.escape(status.czech)]
        case .log(let ingested):
            logged.append(ingested.qso)
            let withTime = hasTimestamp(input)
            do {
                let result = try runtime.log(call: ingested.call, band: ingested.bandAdif, mode: ingested.modeName,
                                             exchange: ingested.receivedRaw)
                let counted: Bool = result?.counted ?? true
                return ["log", String(counted), F.escape(ingested.status(counted: counted).czech),
                        qsoText(ingested.qso, withTime: withTime)]
            } catch {
                let message: String = String(describing: error)
                let status = ExternalQsoIngest.failureStatus(source: ingested.source, message: message)
                return ["logfail", "-", F.escape(status.czech), qsoText(ingested.qso, withTime: withTime)]
            }
        }
    }

    @Test func rowsMatchJvm() throws {
        let rows = F.rows("ingest")
        #expect(rows.count > 50)
        var tags: [String] = []
        for row in rows where !tags.contains(row[1]) { tags.append(row[1]) }
        var replayed = 0
        for tag in tags {
            let contest: String? = Self.contests[tag]
            let runtime = try F.runtime(contest: contest)
            var logged: [Qso] = []
            for row in rows where row[1] == tag {
                let swift: [String] = Self.replay(row, runtime: runtime, logged: &logged)
                let java: [String] = Array(row[4...])
                if swift != java {
                    Issue.record("\(tag) \(row[2]) \(row[3])\nSwift: \(swift)\nJava:  \(java)")
                }
                replayed += 1
            }
        }
        #expect(replayed == rows.count)
    }

    // MARK: - branches the probe rows cannot pin by themselves

    static func snapshot(active: Bool = true, qsos: [Qso] = [], nextSerial: Int = 1,
                         fields: @escaping @Sendable (String) throws(ExpressionError) -> [ContestDefinition.ExchangeField]
                             = { _ in [] }) -> IngestSnapshot {
        IngestSnapshot(qsos: qsos, isContestActive: active, exchangeFields: fields, nextSerial: nextSerial,
                       runMode: .run, ownCall: F.ownCall)
    }

    static let xml = "<contactinfo><app>N1MM</app><call>DL1ABC</call><mode>CW</mode><txfreq>1402500</txfreq>"
        + "<timestamp>2026-10-03 10:00:00</timestamp><StationName>OK1ZZZ</StationName></contactinfo>"

    @Test func ownEchoIsExactAndCaseSensitive() {
        #expect(ExternalQsoIngest.isOwnEcho(app: "MacContestLogger", stationName: nil, ownCall: "OK1XOE"))
        #expect(!ExternalQsoIngest.isOwnEcho(app: "maccontestlogger", stationName: nil, ownCall: "OK1XOE"))
        #expect(ExternalQsoIngest.isOwnEcho(app: nil, stationName: "OK1XOE", ownCall: "OK1XOE"))
        #expect(!ExternalQsoIngest.isOwnEcho(app: nil, stationName: "ok1xoe", ownCall: "OK1XOE"))
        #expect(!ExternalQsoIngest.isOwnEcho(app: nil, stationName: nil, ownCall: ""))
        #expect(!ExternalQsoIngest.isOwnEcho(app: "N1MM", stationName: nil, ownCall: "OK1XOE"))
    }

    /// The order of the checks: parse, echo, dedup, then the active-contest test — a duplicate is silent even
    /// without a contest.
    @Test func duplicateIsDroppedBeforeTheContestIsChecked() throws {
        let first = ExternalQsoIngest.n1mm(Self.xml, snapshot: Self.snapshot())
        guard case .log(let ingested) = first else {
            Issue.record("expected a QSO to log, got \(first)")
            return
        }
        let again = ExternalQsoIngest.n1mm(Self.xml, snapshot: Self.snapshot(active: false, qsos: [ingested.qso]))
        guard case .drop = again else {
            Issue.record("expected a silent drop, got \(again)")
            return
        }
        let inactive = ExternalQsoIngest.n1mm(Self.xml, snapshot: Self.snapshot(active: false))
        guard case .status(let status) = inactive else {
            Issue.record("expected a status, got \(inactive)")
            return
        }
        #expect(status.czech == "N1MM: přijato QSO DL1ABC, ale není aktivní závod — neuloženo")
        guard case .drop = ExternalQsoIngest.n1mm("<contactinfo></contactinfo>", snapshot: Self.snapshot(active: false)) else {
            Issue.record("a message without a call is dropped")
            return
        }
    }

    @Test func serialSentComesFromTheSnapshotNotTheMessage() throws {
        let outcome = ExternalQsoIngest.n1mm(Self.xml.replacingOccurrences(of: "<call>", with: "<sntnr>99</sntnr><call>"),
                                             snapshot: Self.snapshot(nextSerial: 42))
        guard case .log(let ingested) = outcome else {
            Issue.record("expected a QSO to log")
            return
        }
        #expect(ingested.qso.serialSent == 42)
        #expect(ingested.qso.runMode == .run)
        #expect(ingested.qso.imported)
        #expect(ingested.modeName == "CW")
        #expect(ingested.bandAdif == "20m")
    }

    @Test func defaultModeNamesDifferBetweenN1mmAndAdif() throws {
        let n1mm = ExternalQsoIngest.n1mm("<contactinfo><call>DL1ABC</call></contactinfo>", snapshot: Self.snapshot())
        guard case .log(let a) = n1mm else {
            Issue.record("expected a QSO to log")
            return
        }
        #expect(a.modeName == "SSB")
        #expect(a.qso.mode == nil)
        #expect(a.bandAdif == "")
        let adif = ExternalQsoIngest.adif("<call:6>DL1ABC <eor>", source: "ADIF", snapshot: Self.snapshot())
        guard case .log(let b) = adif else {
            Issue.record("expected a QSO to log")
            return
        }
        #expect(b.modeName == "FT8")
        #expect(b.qso.mode == nil)
    }

    @Test func exchangeFieldFailureBecomesTheFailureStatus() {
        let boom = ExpressionError(kind: .illegalArgument, message: "boom")
        let failing: @Sendable (String) throws(ExpressionError) -> [ContestDefinition.ExchangeField] = { _ throws(ExpressionError) in
            throw boom
        }
        guard case .status(let n1) = ExternalQsoIngest.n1mm(Self.xml, snapshot: Self.snapshot(fields: failing)) else {
            Issue.record("expected a status")
            return
        }
        #expect(n1.czech == "N1MM: import selhal (boom)")
        guard case .status(let ad) = ExternalQsoIngest.adif("<call:6>DL1ABC <eor>", source: "WSJT-X",
                                                            snapshot: Self.snapshot(fields: failing)) else {
            Issue.record("expected a status")
            return
        }
        #expect(ad.czech == "WSJT-X: import selhal (boom)")
        #expect(ExternalQsoIngest.failureStatus(source: "ADIF", message: nil).czech == "ADIF: import selhal (null)")
    }

    @Test func statusTextsOfALoggedQso() {
        let qso = Qso()
        let n1mm = IngestedQso(qso: qso, call: "DL1ABC", bandAdif: "20m", modeName: "RTTY",
                               receivedRaw: JavaLinkedMap<String>(), source: "N1MM")
        #expect(n1mm.status(counted: true).czech == "N1MM: importováno QSO DL1ABC")
        #expect(n1mm.status(counted: false).czech == "N1MM: QSO DL1ABC v módu RTTY — závod ho nemá, do skóre se nepočítá")
        let adif = IngestedQso(qso: qso, call: "DL1ABC", bandAdif: "20m", modeName: "FT4",
                               receivedRaw: JavaLinkedMap<String>(), source: "WSJT-X")
        #expect(adif.status(counted: true).czech == "WSJT-X: importováno QSO DL1ABC")
        #expect(adif.status(counted: false).czech == "WSJT-X: QSO DL1ABC v módu FT4 — závod ho nemá, do skóre se nepočítá")
    }

    @Test func flatExchangeJoinsTheFilledFieldsInDefinitionOrder() throws {
        let runtime = try F.runtime(contest: "cq-ww-cw")
        let fields = try runtime.exchangeFields(call: "DL1ABC")
        #expect(fields.count == 2)
        let raw = JavaLinkedMap([("zone", " 14 "), ("rst", "599"), ("extra", "x")])
        #expect(ExternalQsoIngest.flatExchange(fields, raw) == "599 14")
        #expect(ExternalQsoIngest.flatExchange(fields, JavaLinkedMap([("zone", "\u{00A0}")])) == nil)
        #expect(ExternalQsoIngest.flatExchange(fields, JavaLinkedMap<String>()) == nil)
        #expect(ExternalQsoIngest.flatExchange([], raw) == nil)
    }
}
