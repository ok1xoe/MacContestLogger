import Foundation
import Testing
@testable import MCLCore

/// `ContestSession` beyond the Java tests: concurrency (built in the background, taken over by the main
/// actor), errors that must reach the caller, preview time and recorded leniencies.
@Suite struct ContestSessionTests {

    // MARK: - concurrency (review 1 focus)

    /// Java pattern `ContestReplay` → `adopt`: the session is created and replays QSOs in `Task.detached`,
    /// then it is handed to the main actor, which keeps working with it. Compiled under Swift 6 strict
    /// concurrency, because `ContestSession` is `Sendable` (state behind a lock).
    @Test func sessionBuiltInBackgroundIsAdoptedOnMainActor() async throws {
        let dxccData = try DxccTestFixture.data()
        let multipliers = try SessionFixture.contestData().appendingPathComponent("multipliers")
        let definition = try SessionFixture.definition("@cq-ww-cw.yaml")

        let built = try await Task.detached {
            let dxcc = try DxccResolver.fromData(dxccData)
            let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(multipliers)
            let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
            session.setBonusStations(["DL1ABC"])
            _ = try session.log(call: "DL1ABC", band: "20m", mode: "CW",
                                receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "14")), atEpochSecond: 0)
            return session
        }.value

        try await MainActor.run {
            let again = try built.preview(call: "DL1ABC", band: "20m", mode: "CW",
                                          receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "14")))
            #expect(again.context.bonusStation, "bonus stations set in the background still apply after the takeover")
            #expect(again.multipliers.allSatisfy { $0.state == .knownAlreadyWorked })
            _ = try built.log(call: "W1AW", band: "20m", mode: "CW",
                              receivedRaw: SessionFixture.raw(("rst", "599"), ("zone", "5")), atEpochSecond: 60)
            let score = try built.score()
            #expect(score.qsoCount == 2)
            #expect(score.total == 16)   // (1 + 3) × 4
        }
    }

    /// The same object written from many tasks at once: nothing is lost (state is behind a lock).
    @Test func concurrentLogsAreNotLost() async throws {
        let session = try SessionFixture.session("@dx.yaml")
        await withTaskGroup(of: Void.self) { group in
            for task in 0..<8 {
                group.addTask {
                    for n in 0..<50 {
                        _ = try? session.log(call: "DL\(task)A\(n)", band: "20m", mode: "CW",
                                             receivedRaw: SessionFixture.raw(("rst", "599")), atEpochSecond: 0)
                    }
                }
            }
        }
        let score = try session.score()
        #expect(score.qsoCount == 400)
        #expect(score.qsoPoints == 400)
    }

    // MARK: - errors to the caller

    /// An expression nested deeper than 12 (Java computes it, Swift rejects it — a deliberate divergence from Java v1.1.1):
    /// the error **reaches the caller** from `log` and `score`, never a silent zero. `log` throws a single type,
    /// `ContestSessionError`, and the session stays usable after the error (replay counts `skipped`).
    @Test func expressionNestedTooDeepReachesTheCaller() throws {
        let deep = String(repeating: "(", count: 13) + "1" + String(repeating: ")", count: 13)
        let yaml = "{id: t, scoring: {qsoPoints: {rules: [{when: {mode: SSB}, value: {expr: \"" + deep
            + "\"}}], default: 1}, total: \"qsoPoints\"}}"
        let s = try SessionFixture.session(yaml)

        #expect(throws: ContestSessionError.self) {
            _ = try s.log(call: "DL1ABC", band: "20m", mode: "SSB", receivedRaw: nil, atEpochSecond: 0)
        }
        do {
            _ = try s.log(call: "DL1ABC", band: "20m", mode: "SSB", receivedRaw: nil, atEpochSecond: 0)
            Issue.record("log must throw")
        } catch {
            guard case .expression(let e) = error else {
                Issue.record("expected expression, got \(error)")
                return
            }
            #expect(e.kind == .nestingTooDeep)
        }
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: nil, atEpochSecond: 0)
        #expect(try s.score().qsoCount == 1, "the faulty QSO is not counted, the next one is")

        let total = try SessionFixture.session("{id: t, scoring: {total: \"" + deep + "\"}}")
        #expect(throws: ExpressionError.self) { _ = try total.score() }
    }

    /// A number above 2³¹−1 in a numeric exchange field: `log`, `preview`, `exchangeComplete` throw
    /// `.exchange` (Java `NumberFormatException`), nothing is written.
    @Test func exchangeNumberOverflowIsAnError() throws {
        let s = try SessionFixture.session("@cq-ww-cw.yaml")
        let raw = SessionFixture.raw(("rst", "599"), ("zone", "2147483648"))
        #expect(throws: ContestSessionError.exchange(ExchangeError(kind: .numberFormat,
                                                                    message: "For input string: \"2147483648\""))) {
            _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw)
        }
        #expect(throws: ContestSessionError.self) { _ = try s.exchangeComplete(call: "DL1ABC", receivedRaw: raw) }
        #expect(try s.score().qsoCount == 0)
    }

    /// Decision 2: non-transactional `log` — a multiplier written before the error in the bonus stays,
    /// the QSO is not counted even in dupe (Java behaviour, also measured in the `partial-bonus-expr` table).
    @Test func failedLogKeepsCommittedMultipliers() throws {
        let yaml = "{id: t, modes: [CW], multipliers: [{id: c, set: dxcc_entities, from: callsign, scope: PER_BAND}], "
            + "scoring: {qsoPoints: {default: 1}, bonuses: [{id: b, when: {expr: \"1 +\"}, value: {fixed: 5}}], "
            + "total: \"qsoPoints * multTotal + bonusPoints\"}}"
        let s = try SessionFixture.session(yaml)
        #expect(throws: ContestSessionError.self) {
            _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: nil, atEpochSecond: 0)
        }
        let score = try s.score()
        #expect(score.qsoCount == 0)
        #expect(score.multTotal == 1)
        #expect(s.tracker.distinctForBinding("c") == 1)
        let again = try s.preview(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: nil)
        #expect(!again.dupe)
        #expect(again.multipliers.first?.isNew == false)
    }

    // MARK: - time

    /// Decision 6: `preview(at:)` with the default value "now" (like Java `Instant.now()`); with a given
    /// time the preview can be evaluated in the TOUR session the QSO belongs to.
    @Test func previewTimeDefaultsToNowAndCanBeGiven() throws {
        let s = try SessionFixture.session("@cq-ww-cw.yaml")
        s.setTour(Tour.parse("1200/30"))
        #expect(s.tour != nil)
        let raw = SessionFixture.raw(("rst", "599"), ("zone", "14"))
        let t0: Int64 = 1_795_867_500
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, atEpochSecond: t0)

        let inSession = Date(timeIntervalSince1970: TimeInterval(t0 + 300))
        #expect(try s.preview(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, at: inSession).dupe)
        let nextSession = Date(timeIntervalSince1970: TimeInterval(t0 + 1_800))
        #expect(try !s.preview(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, at: nextSession).dupe)
        let longAgo = Date(timeIntervalSince1970: 0)
        #expect(try !s.preview(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, at: longAgo).dupe)
    }

    /// `log(at: Date)` and `log(atEpochSecond:)` give the same (fraction of a second floored like `Instant`).
    @Test func dateAndEpochSecondVariantsAgree() throws {
        let s = try SessionFixture.session("@cq-ww-cw.yaml")
        s.setTour(Tour.parse("0000/60"))
        #expect(s.tour != nil)
        let raw = SessionFixture.raw(("rst", "599"), ("zone", "14"))
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw,
                      at: Date(timeIntervalSince1970: 3_599.5))
        #expect(try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, atEpochSecond: 3_000).dupe)
        #expect(try !s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: raw, atEpochSecond: 3_600).dupe)
    }

    // MARK: - recorded leniencies (a deliberate divergence from Java v1.1.1)

    /// `multipliers: [~, …]` in `multiplierGrid`: Java NPE (`b.set()`); Swift skips the element.
    @Test func gridSkipsNilBinding() throws {
        let s = try SessionFixture.session("{id: g, multipliers: [~, {id: c, set: dxcc_entities, from: callsign}]}")
        _ = try s.log(call: "DL1ABC", band: "20m", mode: "CW", receivedRaw: nil, atEpochSecond: 0)
        let grid = try s.multiplierGrid(bands: [.m20]) { _, _ in true }
        #expect(grid.available)
        #expect(grid.worked == 1)
        #expect(grid.rows.first { $0.prefix == "DL" }?.workedBands == ["20m"])
    }

    /// An unknown set in `multiplierGrid` throws like Java (`MultiplierException`).
    @Test func gridWithUnknownSetThrows() throws {
        let s = try SessionFixture.session("{id: g, multipliers: [{id: x, set: nope, from: callsign}]}")
        #expect(throws: ContestSessionError.multiplier(.failure("multiplikátorová sada 'nope' není v registru"))) {
            _ = try s.multiplierGrid(bands: [.m20]) { _, _ in true }
        }
    }

    /// `exchange.sent: [~, ROVER_QTH]` in `ownQthFromSent`: Java NPE; Swift keeps the index
    /// (`nil` field = "not ROVER_QTH"), so the county is the second token.
    @Test func ownQthKeepsIndexOverNilSentField() throws {
        let s = try SessionFixture.session("{id: q, exchange: {sent: [~, {id: qth, type: TEXT, source: ROVER_QTH}]}}")
        #expect(s.ownQthFromSent("599 DAD") == "DAD")
        #expect(s.ownQthFromSent("599") == nil)
    }

    /// `multiplierLabels` over a value without a key: Java NPE in `Map.copyOf`; Swift omits it.
    @Test func labelsSkipValueWithoutKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let set = "id: s\nkind: FIXED\nvalues:\n  - { label: A, attributes: { prefix: AA } }\n"
            + "  - { key: B, attributes: { prefix: BB } }\n  - { key: C, attributes: { prefix: \" \" } }\n"
        try Data(set.utf8).write(to: dir.appendingPathComponent("s.yaml"))
        let dxcc = try SessionFixture.dxcc()
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(dir)
        let s = ContestSession(definition: try SessionFixture.definition("{id: t}"), dxcc: dxcc, registry: registry,
                               myCall: "OK1XOE")
        #expect(s.multiplierLabels(setId: "s") == JavaLinkedMap([("B", "BB")]))
    }
}
