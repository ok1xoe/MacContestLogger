import Foundation
import Testing
@testable import MCLCore

/// The `score` rows of `IntegrationsProbe.java` (`AppState.reportScoreIfDue` of the Kotlin v1.1.1 with a stand-in
/// `ScorePoster` that records the call — no HTTP) against `ScoreReportPolicy`, `ScoreXml` and the contest runtime.
@Suite struct ScoreReportPolicyTests {

    typealias F = IntegrationsFixture

    static let now = JavaInstant.ofEpochSecond(1_791_021_600, 123_456_000)!

    static func mask(_ text: String) -> String {
        text.replacingOccurrences(of: "\\d{4}-\\d{2}-\\d{2}T[\\d:.]+Z", with: "<instant>", options: .regularExpression)
            .replacingOccurrences(of: "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", with: "<instant>", options: .regularExpression)
            // The status shows `HH:mm:ss UTC` where Java printed the raw Instant (deliberate divergence).
            .replacingOccurrences(of: "\\d{2}:\\d{2}:\\d{2} UTC", with: "<instant>", options: .regularExpression)
    }

    /// The QSO the probe imported before reporting (ADIF: DL1ABC, 20m CW, report 599, zone 14).
    static func importedQso() -> Qso {
        var q = Qso()
        q.call = "DL1ABC"
        q.timestampUtc = Date(timeIntervalSince1970: 1_791_021_600)
        q.band = .m20
        q.mode = .cw
        q.rstRcvd = "599"
        q.exchangeRcvd = "599 14"
        return q
    }

    /// One probe row replayed: the decision, the post (a recorded stand-in), the status and the remembered values.
    /// Columns: index, contest, enabled, force, age (s), same revision, post code, failure, then the results.
    @Test func rowsMatchJvm() throws {
        let rows = F.rows("score")
        #expect(rows.count == 15)
        for row in rows {
            let contest: String? = row[2] == "none" ? nil : row[2]
            let enabled = row[3] == "true"
            let force = row[4] == "true"
            let age = Int64(row[5])!
            let sameRevision = row[6] == "true"
            let code = Int(row[7])!
            let failing: Bool = row[8] != "-"
            let failure: String? = row[8] == "<null>" ? nil : F.unescape(row[8])
            let last = JavaInstant.ofEpochSecond(Self.now.epochSecond - age, Int64(Self.now.nano))!
            let revision: Int64 = 7
            let lastRevision: Int64 = sameRevision ? 7 : 3

            let runtime = try F.runtime(contest: contest)
            if contest != nil {
                try runtime.log(call: "DL1ABC", band: "20m", mode: "CW",
                                exchange: JavaLinkedMap([("rst", "599"), ("zone", "14")]))
            }
            let definition = runtime.definition
            let due = ScoreReportPolicy.due(force: force, enabled: enabled, hasDefinition: definition != nil,
                                            revision: revision, lastRevision: lastRevision, now: Self.now,
                                            lastAt: last, minutes: 5)
            var posts = 0
            var url = "-"
            var movedAt = false
            var revisionAfter = lastRevision
            var status: String = ScoreReportPolicy.idleStatus
            var xml = "<none>"
            if due, let definition, let score = runtime.score {
                let station = ScoreReportPolicy.station(call: F.ownCall, operators: "OK1XOE OK1ABC", club: "OKCC",
                                                        cqZone: "15", ituZone: "28", gridSquare: "JN79xx",
                                                        category: ["OPERATOR": "SINGLE-OP", "POWER": "LOW"])
                let contestName = ScoreReportPolicy.contestName(cabrilloName: definition.cabrillo?.contestName,
                                                                definitionId: definition.id)
                let session = try #require(runtime.freshSession())
                let breakdown = try ScoreBreakdown.compute(session, [Self.importedQso()])
                xml = ScoreXml.build(contestName: contestName, station: station, score: score, breakdown: breakdown,
                                     withBreakdown: true, version: "vývojová verze", now: Self.now.date)
                posts = 1
                url = "http://probe.invalid/post/"
                let result: ScoreReportPolicy.PostResult = failing ? .failure(failure) : .http(code)
                let outcome = ScoreReportPolicy.outcome(result, total: score.total, now: Self.now)
                status = outcome.status.czech
                movedAt = true
                if outcome.accepted { revisionAfter = revision }
            }
            let swift: [String] = [
                "posts=\(posts)", "url=\(url)", "atMoved=\(movedAt)", "rev=\(revisionAfter)", F.escape(Self.mask(status)),
                F.escape(Self.mask(xml)),
            ]
            let java: [String] = Array(row[9...])
            if swift != java {
                Issue.record("row \(row[1])\nSwift: \(swift)\nJava:  \(java)")
            }
        }
    }

    // MARK: - decisions pinned from the source (the probe cannot pick the clock)

    static func due(force: Bool = false, enabled: Bool = true, hasDefinition: Bool = true, revision: Int64 = 2,
                    lastRevision: Int64 = 1, ageSeconds: Int64 = 600, minutes: Int = 5) -> Bool {
        let last = JavaInstant.ofEpochSecond(Self.now.epochSecond - ageSeconds, Int64(Self.now.nano))!
        return ScoreReportPolicy.due(force: force, enabled: enabled, hasDefinition: hasDefinition, revision: revision,
                                     lastRevision: lastRevision, now: Self.now, lastAt: last, minutes: minutes)
    }

    @Test func dueNeedsEnabledOrForceAndADefinition() {
        #expect(Self.due())
        #expect(!Self.due(enabled: false))
        #expect(Self.due(force: true, enabled: false))
        #expect(!Self.due(hasDefinition: false))
        #expect(!Self.due(force: true, hasDefinition: false))
    }

    @Test func dueNeedsAChangedLogAndWholeMinutes() {
        #expect(!Self.due(revision: 1, lastRevision: 1))
        #expect(Self.due(force: true, revision: 1, lastRevision: 1, ageSeconds: 0))
        // 4 min 59 s truncates to 4 minutes: not yet; 5 min 0 s is due.
        #expect(!Self.due(ageSeconds: 299, minutes: 5))
        #expect(Self.due(ageSeconds: 300, minutes: 5))
        #expect(!Self.due(ageSeconds: 119, minutes: 2))
        #expect(Self.due(ageSeconds: 120, minutes: 2))
        // A clock that went back: a negative duration truncates toward zero, below any interval.
        #expect(!Self.due(ageSeconds: -600, minutes: 2))
    }

    @Test func nanosecondsBorrowASecond() {
        let last = JavaInstant.ofEpochSecond(1000, 900_000_000)!
        let now = JavaInstant.ofEpochSecond(1060, 100_000_000)!
        #expect(ScoreReportPolicy.wholeMinutes(from: last, to: now) == 0) // 59.2 s
        let later = JavaInstant.ofEpochSecond(1060, 900_000_000)!
        #expect(ScoreReportPolicy.wholeMinutes(from: last, to: later) == 1)
        #expect(ScoreReportPolicy.wholeMinutes(from: .epoch, to: Self.now) > 1_000_000)
    }

    @Test func contestNameFallsBackToTheIdOnlyWithoutACabrilloName() {
        #expect(ScoreReportPolicy.contestName(cabrilloName: "CQ-WW-CW", definitionId: "cq-ww-cw") == "CQ-WW-CW")
        #expect(ScoreReportPolicy.contestName(cabrilloName: nil, definitionId: "cq-ww-cw") == "cq-ww-cw")
        #expect(ScoreReportPolicy.contestName(cabrilloName: "", definitionId: "cq-ww-cw") == "")
    }

    @Test func stationTakesOperatorsFromTheSetupOrTheCall() {
        let category = ["POWER": "LOW"]
        func ops(_ operators: String?) -> String? {
            ScoreReportPolicy.station(call: "OK1XOE", operators: operators, club: "C", cqZone: "15", ituZone: "28",
                                      gridSquare: "JN79", category: category).ops
        }
        #expect(ops("OK1XOE OK1ABC") == "OK1XOE OK1ABC")
        #expect(ops(nil) == "OK1XOE")
        #expect(ops("") == "OK1XOE")
        #expect(ops("  \u{00A0}") == "OK1XOE")
        let st = ScoreReportPolicy.station(call: "OK1XOE", operators: nil, club: "C", cqZone: "15", ituZone: "28",
                                           gridSquare: "JN79", category: nil)
        #expect(st == ScoreXml.Station(call: "OK1XOE", ops: "OK1XOE", club: "C", cqZone: "15", ituZone: "28",
                                       grid: "JN79", category: [:]))
    }

    @Test func outcomeTextsAndWhatIsRemembered() {
        let at = JavaInstant.ofEpochSecond(1_791_021_600, 123_456_000)!
        let ok = ScoreReportPolicy.outcome(.http(200), total: 1234, now: at)
        #expect(ok.accepted)
        #expect(ok.status.czech == "Skóre 1234 odesláno 10:00:00 UTC (HTTP 200)")
        #expect(ScoreReportPolicy.outcome(.http(299), total: 1, now: at).accepted)
        #expect(!ScoreReportPolicy.outcome(.http(199), total: 1, now: at).accepted)
        let bad = ScoreReportPolicy.outcome(.http(500), total: 1, now: at)
        #expect(!bad.accepted)
        #expect(bad.status.czech == "Server vrátil HTTP 500")
        #expect(ScoreReportPolicy.outcome(.http(300), total: 1, now: at).status.czech == "Server vrátil HTTP 300")
        let failed = ScoreReportPolicy.outcome(.failure("Connection refused"), total: 1, now: at)
        #expect(!failed.accepted)
        #expect(failed.status.czech == "Odeslání skóre selhalo: Connection refused")
        #expect(ScoreReportPolicy.outcome(.failure(nil), total: 1, now: at).status.czech == "Odeslání skóre selhalo: null")
        #expect(ScoreReportPolicy.idleStatus == "Skóre se zatím neodesílalo")
    }

    @Test func rejectionTextAppendsTheServerReason() {
        let at = JavaInstant.ofEpochSecond(1_791_021_600, 0)!
        #expect(ScoreReportPolicy.outcome(.rejected(404, detail: "Contest not supported"), total: 1, now: at).status.czech
                == "Server vrátil HTTP 404: Contest not supported")
    }

    @Test func failureTextsAreReadable() {
        let at = JavaInstant.ofEpochSecond(1_791_021_600, 0)!
        let url = "https://example.invalid/post/"
        func text(_ error: JavaHttpError) -> String {
            ScoreReportPolicy.outcome(ScoreReportPolicy.result(failure: error, url: url), total: 1, now: at).status.czech
        }
        #expect(text(.io(JavaIOError(nil, javaClass: "java.net.ConnectException")))
                == "Odeslání skóre selhalo: server nedostupný (example.invalid)")
        #expect(text(.io(JavaIOError("x", javaClass: "java.net.UnknownHostException")))
                == "Odeslání skóre selhalo: server nedostupný (example.invalid)")
        #expect(text(.io(JavaIOError("request timed out", javaClass: "java.net.http.HttpTimeoutException")))
                == "Odeslání skóre selhalo: vypršel čas (example.invalid)")
        #expect(text(.io(JavaIOError("HTTP connect timed out", javaClass: "java.net.http.HttpConnectTimeoutException")))
                == "Odeslání skóre selhalo: vypršel čas (example.invalid)")
        #expect(text(.illegalArgument(JavaIllegalArgumentError(message: "Illegal character in query at index 3")))
                == "Odeslání skóre selhalo: neplatná adresa")
        #expect(text(.io(JavaIOError("boom", javaClass: "javax.net.ssl.SSLHandshakeException")))
                == "Odeslání skóre selhalo: boom")
    }
}
