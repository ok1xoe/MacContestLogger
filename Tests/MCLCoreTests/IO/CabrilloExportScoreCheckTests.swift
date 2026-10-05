import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/CabrilloExportScoreCheckTest` (3 tests): the exported Cabrillo must
/// pass the own `ScoreCheck` with a matching CLAIMED-SCORE. The definitions from `contest-data/`
/// and `dxcc-test.json` — byte-for-byte the same as in Java. All 22 definitions against values
/// measured in Java are in `CabrilloExportMeasuredTests.roundTripMatchesJavaForAllDefinitions`.
@Suite struct CabrilloExportScoreCheckTests {

    let dxcc: DxccResolver
    let registry: MultiplierSetRegistry
    let defs: [ContestDefinition]

    init() throws {
        dxcc = try SessionFixture.dxcc()
        registry = try SessionFixture.registry(dxcc)
        defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
    }

    private func def(_ id: String) throws -> ContestDefinition {
        try #require(defs.first { $0.id == id })
    }

    /// Logs a QSO like the entry window: a session + a QSO with the exchange in the order of the active fields.
    private struct Logged {
        let qsos: [Qso]
        let score: Int64
    }

    private func log(_ session: ContestSession, _ rows: [[String]], _ mode: Mode) throws -> Logged {
        var qsos: [Qso] = []
        let start = CabrilloExporterTests.instant("2026-11-28T12:00:00Z")
        for (index, r) in rows.enumerated() {
            let call = r[0]
            let freq = try #require(Int(r[1]))
            var exch = JavaLinkedMap<String>()
            let fields = try session.activeReceivedFields(call: call)
            for (i, field) in fields.enumerated() {
                exch.put(field.id, r[2 + i])
            }
            let band = try #require(Band.from(frequencyHz: freq)).adif
            try session.log(call: call, band: band, mode: mode.rawValue, receivedRaw: exch)
            var q = Qso()
            q.timestampUtc = start.addingTimeInterval(TimeInterval(60 * index))
            q.call = call
            q.freqHz = freq
            q.mode = mode
            q.rstSent = mode.defaultRst
            q.serialSent = index + 1
            q.exchangeRcvd = exch.entries.map { $0.value ?? "null" }.joined(separator: " ")
            qsos.append(q)
        }
        return Logged(qsos: qsos, score: try session.score().total)
    }

    private func exportAndCheck(_ d: ContestDefinition, _ session: ContestSession, _ logged: Logged,
                                _ sentExchange: JavaLinkedMap<String>) throws -> ScoreCheck.Result {
        var station = StationConfig()
        station.call = "OK1XOE"
        var input = CabrilloExporter.Input(definition: d, station: station, qsos: logged.qsos,
                                           receivedFields: { try session.activeReceivedFields(call: $0) })
        input.sentExchange = sentExchange
        input.claimedScore = logged.score
        let text = try CabrilloExporter.export(input).text
        return try ScoreCheck.evaluate(fileName: "export.log", content: text, definitions: defs, dxcc: dxcc,
                                       registry: registry)
    }

    private func session(_ d: ContestDefinition) -> ContestSession {
        ContestSession(definition: d, dxcc: dxcc, registry: registry, myCall: "OK1XOE", myGrid: nil)
    }

    /// Java `cqWwSsbExportPassesScoreCheck`.
    @Test func cqWwSsbExportPassesScoreCheck() throws {
        let d = try def("cq-ww-ssb")
        let s = session(d)
        let logged = try log(s, [
            ["DL1ABC", "14200000", "59", "14"],
            ["W1AW", "14210000", "59", "5"],
            ["VE3XX", "7150000", "57", "4"],
        ], .ssb)

        let r = try exportAndCheck(d, s, logged, CabrilloExporterTests.map(("zone", "15")))

        #expect(r.error == nil)
        #expect(r.qsoCount == 3)
        #expect(logged.score > 0)
        #expect(r.computed == logged.score)
        #expect(r.pass, "CLAIMED-SCORE from the export must match the recomputation")
    }

    /// Java `cqWpxSerialExportPassesScoreCheck`.
    @Test func cqWpxSerialExportPassesScoreCheck() throws {
        let d = try def("cq-wpx-cw")
        let s = session(d)
        let logged = try log(s, [
            ["DL1ABC", "14025000", "599", "12"],
            ["W1AW", "21025000", "599", "345"],
            ["OK2ABC", "7025000", "599", "7"],
        ], .cw)

        let r = try exportAndCheck(d, s, logged, JavaLinkedMap())

        #expect(r.error == nil)
        #expect(r.qsoCount == 3)
        #expect(r.pass)
    }

    /// Java `okOmConditionalExchangeExportPassesScoreCheck`.
    @Test func okOmConditionalExchangeExportPassesScoreCheck() throws {
        let d = try def("ok-om-dx-cw")
        let s = session(d)
        let logged = try log(s, [
            ["OK2ABC", "3520000", "599", "APH"],
            ["DL1ABC", "3525000", "599", "17"],
            ["W1AW", "7025000", "599", "3"],
        ], .cw)

        let r = try exportAndCheck(d, s, logged, CabrilloExporterTests.map(("out", "APH")))

        #expect(r.error == nil)
        #expect(r.qsoCount == 3)
        #expect(r.computed == logged.score)
        #expect(r.pass)
    }
}
