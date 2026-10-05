import Foundation
import Testing
@testable import MCLCore

/// Replays the `ReplayMeasured` cases (maintainer-only probe)
/// through the Swift `ContestReplay` and compares with Java: `replayed`/`skipped`, the order and result of
/// listener calls and the whole score. Covers faulty QSOs (no band, empty callsign, number above
/// 2³¹−1, missing exchange, FT8 / mode `nil`, `nil` time, deleted, X-QSO), stable sorting,
/// half-done state after an exception and three generated logs of 300 QSOs
/// (cq-ww-cw, iaru-hf, cq-wpx-cw).
@Suite struct ReplayMeasuredTests {

    /// Scenarios where Swift knowingly differs: value = the Swift row.
    static let divergent: [String: String] = [
        // expression deeper than 12: Java computes it (`replayed=3 skipped=0`), Swift skips the QSO and returns the error
        "deep-expression": "replayed=2 skipped=1\t0:true:2;2:true:2\t"
            + "qsoCount=2 qsoPoints=4 mult=0 groups=[] bonus=0 qtc=0 total=4 qtcCount=0",
    ]

    static func expectedRows() throws -> [String: String] {
        var out: [String: String] = [:]
        for line in ReplayMeasured.expected.split(separator: "\n", omittingEmptySubsequences: true) {
            let p = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            try #require(p.count == 2, "table row: \(line)")
            out[p[0]] = p[1]
        }
        return out
    }

    /// Row `Q` → `Qso` like the probe (`~` callsign / exchange = Java `null`, `""` in Swift).
    static func qso(_ f: [String], id: Int64) -> Qso {
        let unesc = SessionMeasuredTests.unesc
        var q = Qso()
        q.id = id
        q.call = unesc(f[1]) ?? ""
        q.freqHz = Int(f[2])!
        q.mode = f[3] == "~" ? nil : Mode(rawValue: f[3])!
        q.exchangeRcvd = unesc(f[4]) ?? ""
        q.serialRcvd = f[5] == "~" ? nil : Int(f[5])!
        q.timestampUtc = f[6] == "~" ? nil : Date(timeIntervalSince1970: TimeInterval(Int64(f[6])!))
        q.exchangeSent = unesc(f[7]) ?? ""
        q.deleted = f[8].contains("d")
        q.xqso = f[8].contains("x")
        return q
    }

    /// Replays all scenarios; returns (scenario, row, result).
    static func replayAll() throws -> [(String, String, ContestReplay.Outcome)] {
        let unesc = SessionMeasuredTests.unesc
        let dxcc = try SessionFixture.dxcc()
        let registry = try SessionFixture.registry(dxcc)
        var out: [(String, String, ContestReplay.Outcome)] = []
        var name = ""
        var session: ContestSession?
        var qsos: [Qso] = []
        for line in ReplayMeasured.cases.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = SessionMeasuredTests.columns(line)
            switch f[0] {
            case "S":
                name = f[1]
                session = ContestSession(definition: try SessionFixture.definition(f[2]), dxcc: dxcc,
                                         registry: registry, myCall: unesc(f[3]), myGrid: unesc(f[4]),
                                         myItuZone: unesc(f[5]))
                qsos = []
            case "T":
                let tour = Tour.parse(unesc(f[1]))
                try #require(tour != nil, "tour \(f[1])")
                try #require(session).setTour(tour)
            case "Q":
                qsos.append(qso(f, id: Int64(qsos.count)))
            case "X":
                var trace: [String] = []
                let outcome = ContestReplay.replay(try #require(session), qsos) { q, r in
                    trace.append("\(q.id!):\(r.counted):\(r.points)")
                }
                let row = "replayed=\(outcome.replayed) skipped=\(outcome.skipped)\t"
                    + trace.joined(separator: ";") + "\t" + SessionMeasuredTests.score(outcome.session)
                out.append((name, row, outcome))
            default:
                preconditionFailure("unknown row \(line)")
            }
        }
        return out
    }

    @Test func everyReplayMatchesJava() throws {
        let expected = try Self.expectedRows()
        let actual = try Self.replayAll()
        #expect(actual.count == expected.count, "scenario count")
        for (name, row, outcome) in actual {
            #expect(outcome.skips.count == outcome.skipped, "\(name): every skip has a reason")
            if let pinned = Self.divergent[name] {
                #expect(row == pinned, "\(name) (known divergence)")
                #expect(expected[name] != pinned, "\(name): Java really differs")
                continue
            }
            #expect(row == expected[name], "\(name)")
        }
    }

    /// Skip reasons in the manual scenarios: Java swallows them, Swift returns them (review 2 focus).
    @Test func skipReasonsAreReported() throws {
        let byName = Dictionary(uniqueKeysWithValues: try Self.replayAll().map { ($0.0, $0.2) })

        let inventory = try #require(byName["inventory"])
        #expect(inventory.skips.map(\.qso.id) == [2, 3, 4])
        guard case .error(.exchange(let nfe))? = inventory.skips.first?.reason else {
            Issue.record("inventory: expected exchange error")
            return
        }
        #expect(nfe.kind == .numberFormat)
        #expect(inventory.skips[1].reason == .missingCall)
        #expect(inventory.skips[2].reason == .missingBand)

        let calls = try #require(byName["calls"])
        #expect(calls.skips.map(\.reason) == [.missingCall, .missingCall, .missingCall, .missingCall])

        let deep = try #require(byName["deep-expression"])
        guard case .expression(let e)? = deep.firstError else {
            Issue.record("deep-expression: expected expression error")
            return
        }
        #expect(e.kind == .nestingTooDeep)
    }
}
