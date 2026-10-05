import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ContestReplayTest` (6) + errors to the caller, half-done state
/// and background replay with takeover on the main thread (like `ContestController.replayed` +
/// `adopt` in Kotlin).
@Suite struct ContestReplayTests {

    private func fresh() throws -> ContestSession {
        try SessionFixture.session("@cq-ww-ssb.yaml", myCall: "OK1XOE")
    }

    /// `2026-11-28T12:00:00Z`.
    static let t0: Int64 = 1_795_867_200

    private static func qso(_ minute: Int64, _ call: String, _ freqHz: Int, _ exch: String) -> Qso {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: TimeInterval(t0 + 60 * minute))
        q.call = call
        q.freqHz = freqHz
        q.mode = .ssb
        q.exchangeRcvd = exch
        return q
    }

    private static func log() -> [Qso] {
        [qso(0, "DL1ABC", 14_200_000, "59 14"),
         qso(1, "W1AW", 14_210_000, "59 5"),
         qso(2, "VE3XX", 7_150_000, "59 4")]
    }

    /// Reference score: QSOs logged live, one after another.
    private func liveScore(_ qsos: [Qso]) throws -> Int64 {
        let s = try fresh()
        for q in qsos {
            _ = try s.replayLogged(call: q.call, band: try #require(q.band).adif, mode: try #require(q.mode).rawValue,
                                   exchangeRcvdFlat: q.exchangeRcvd, serialRcvd: q.serialRcvd)
        }
        return try s.score().total
    }

    @Test func replayEqualsLiveLogging() throws {
        let qsos = Self.log()

        let out = ContestReplay.replay(try fresh(), qsos)

        #expect(out.replayed == 3)
        #expect(out.skipped == 0)
        #expect(try out.session.score().total == liveScore(qsos))
    }

    @Test func editedQsoChangesScore() throws {
        var qsos = Self.log()
        let before = try ContestReplay.replay(try fresh(), qsos).session.score().total

        // Zone correction W1AW 5 → 14: zone 5 disappears as a multiplier (14 already has DL1ABC).
        qsos[1].exchangeRcvd = "59 14"
        let after = try ContestReplay.replay(try fresh(), qsos).session.score().total

        #expect(after == (try liveScore(qsos)))
        #expect(before != after)
    }

    @Test func deletedQsoIsNotCounted() throws {
        var qsos = Self.log()
        qsos[2].deleted = true

        let out = ContestReplay.replay(try fresh(), qsos)

        #expect(out.replayed == 2)
        #expect(try out.session.score().total == liveScore(Array(qsos[0..<2])))
    }

    @Test func replayFollowsTimeNotStorageOrder() throws {
        // The import adds an older QSO to the DB at the end — the new multiplier belongs to the earlier one,
        // the dupe is the later one. The result must not depend on the order in the list.
        let byTime = Self.log()
        let shuffled = [byTime[2], byTime[0], byTime[1]]

        #expect(try ContestReplay.replay(try fresh(), byTime).session.score()
                == ContestReplay.replay(try fresh(), shuffled).session.score())
    }

    @Test func qsoWithoutBandIsSkippedNotFatal() throws {
        var qsos = Self.log()
        var broken = Qso()
        broken.timestampUtc = Date(timeIntervalSince1970: TimeInterval(Self.t0 + 1_800))
        broken.call = "OK2ABC"
        qsos.append(broken)

        let out = ContestReplay.replay(try fresh(), qsos)

        #expect(out.replayed == 3)
        #expect(out.skipped == 1)
        #expect(out.skips.map(\.reason) == [.missingBand])
    }

    @Test func xqsoIsNotScored() throws {
        var qsos = Self.log()
        qsos[2].xqso = true

        let out = ContestReplay.replay(try fresh(), qsos)

        #expect(out.replayed == 2)
        #expect(try out.session.score().total == liveScore(Array(qsos[0..<2])))
    }

    // MARK: - error to the caller (review 2 focus)

    /// Expression deeper than 12: Java computes it, Swift rejects it (a deliberate divergence from Java v1.1.1). Replay
    /// skips the QSO like a Java `RuntimeException`, but **returns** the error — the UI shows a message
    /// instead of a silent zero. The counts do not change.
    @Test func failedQsoErrorIsAvailableToTheCaller() throws {
        let deep = String(repeating: "(", count: 13) + "1" + String(repeating: ")", count: 13)
        let yaml = "{id: t, modes: [CW, SSB], scoring: {qsoPoints: {rules: [{when: {mode: SSB}, value: {expr: \""
            + deep + "\"}}], default: 2}, total: \"qsoPoints\"}}"
        let s = try SessionFixture.session(yaml)
        var cw = Self.qso(0, "DL1ABC", 14_025_000, "")
        cw.mode = .cw
        let ssb = Self.qso(1, "W1AW", 14_200_000, "")
        var noCall = Self.qso(2, "", 14_025_000, "")
        noCall.mode = .cw

        let out = ContestReplay.replay(s, [ssb, cw, noCall])

        #expect(out.replayed == 1)
        #expect(out.skipped == 2)
        #expect(out.skips.count == out.skipped)
        #expect(out.skips.map(\.qso.call) == ["W1AW", ""])
        guard case .error(.expression(let e))? = out.skips.first?.reason else {
            Issue.record("expected expression error, got \(String(describing: out.skips.first?.reason))")
            return
        }
        #expect(e.kind == .nestingTooDeep)
        #expect(e.message.hasPrefix("Příliš hluboké zanoření ve výrazu: "))
        #expect(out.skips[1].reason == .missingCall)
        #expect(out.errors.count == 1)
        #expect(out.firstError == .expression(e))
        #expect(try out.session.score().total == 2, "the rest of the log is counted")
    }

    /// Decision 2: the bonus throws only after the multiplier and the first bonus are written — the QSO is
    /// `skipped`, but the multiplier and the bonus stay in the session (like Java, measured `partial-bonus`).
    @Test func failedQsoKeepsPartialStateLikeJava() throws {
        let yaml = "{id: t, modes: [CW, SSB], multipliers: [{id: c, set: dxcc_entities, from: callsign, "
            + "scope: PER_BAND}], scoring: {qsoPoints: {default: 1}, bonuses: [{id: a, value: {fixed: 7}, "
            + "scope: PER_BAND}, {id: b, when: {mode: SSB}, value: {expr: \"2 *\"}}], "
            + "total: \"qsoPoints * multTotal + bonusPoints\"}}"
        let s = try SessionFixture.session(yaml)
        let ssb = Self.qso(0, "W1AW", 7_025_000, "")

        let out = ContestReplay.replay(s, [ssb])

        #expect(out.replayed == 0)
        #expect(out.skipped == 1)
        guard case .error(.expression)? = out.skips.first?.reason else {
            Issue.record("expected expression error, got \(String(describing: out.skips.first?.reason))")
            return
        }
        let score = try out.session.score()
        #expect(score.qsoCount == 0)
        #expect(score.multTotal == 1, "multiplier stayed")
        #expect(score.bonusPoints == 7, "first bonus stayed")
    }

    /// The listener is called only for replayed QSOs, in replay order; skipped ones it does not see.
    @Test func listenerSeesReplayedQsosInReplayOrder() throws {
        var qsos = Self.log()
        qsos[0].timestampUtc = nil                     // null time goes to the end
        qsos[1].freqHz = 0
        qsos[1].band = nil                             // no band → skipped
        var seen: [String] = []

        let out = ContestReplay.replay(try fresh(), qsos) { q, r in
            seen.append(q.call + ":\(r.counted)")
        }

        #expect(seen == ["VE3XX:true", "DL1ABC:true"])
        #expect(out.replayed == 2)
        #expect(out.skipped == 1)
    }

    // MARK: - threads (review 1 focus)

    /// Like `requestRescore`: the session is built and replayed in the background, the main thread
    /// takes over the finished result (`Outcome` is `Sendable`) and continues logging.
    @Test func replayOnBackgroundIsAdoptedOnMainActor() async throws {
        let dxccData = try DxccTestFixture.data()
        let multipliers = try SessionFixture.contestData().appendingPathComponent("multipliers")
        let definition = try SessionFixture.definition("@cq-ww-ssb.yaml")
        let snapshot = Self.log()

        let outcome = try await Task.detached {
            let dxcc = try DxccResolver.fromData(dxccData)
            let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(multipliers)
            let session = ContestSession(definition: definition, dxcc: dxcc, registry: registry, myCall: "OK1XOE")
            return ContestReplay.replay(session, snapshot)
        }.value

        let expected = try liveScore(snapshot)
        try await MainActor.run {
            #expect(outcome.replayed == 3)
            #expect(try outcome.session.score().total == expected)
            let dupe = try outcome.session.preview(call: "DL1ABC", band: "20m", mode: "SSB",
                                                   receivedRaw: SessionFixture.raw(("rst", "59"), ("zone", "14")))
            #expect(dupe.dupe)
        }
    }
}
