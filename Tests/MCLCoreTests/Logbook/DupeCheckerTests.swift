import Foundation
import Testing
@testable import MCLCore

/// Port of `DupeCheckerTest.java` — fast duplicate check (dupe check) as in
/// N1MM+. In Phase 1 a QSO is a dupe if the given callsign has already been worked
/// on the same band (see `DupeChecker.swift`).
@Suite struct DupeCheckerTests {

    private func qso(_ call: String, _ freqHz: Int) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = freqHz
        return q
    }

    // MARK: - `DupeCheckerTest.detectsDupeOnSameBand`

    @Test func detectsDupeOnSameBand() {
        let checker = DupeChecker(existing: [qso("DL1ABC", 14_074_000)])
        #expect(checker.isDupe(call: "dl1abc", band: .m20)) // case-insensitive
    }

    // MARK: - `DupeCheckerTest.sameCallOnDifferentBandIsNotDupe`

    @Test func sameCallOnDifferentBandIsNotDupe() {
        let checker = DupeChecker(existing: [qso("DL1ABC", 14_074_000)])
        #expect(!checker.isDupe(call: "DL1ABC", band: .m40))
    }

    // MARK: - `DupeCheckerTest.addUpdatesIndex`

    @Test func addUpdatesIndex() {
        var checker = DupeChecker(existing: [])
        #expect(!checker.isDupe(call: "OK1XOE", band: .m15))
        checker.add(qso("OK1XOE", 21_205_000))
        #expect(checker.isDupe(call: "OK1XOE", band: .m15))
    }

    // MARK: - `DupeCheckerTest.deletedQsoDoesNotCreateDupe`

    @Test func deletedQsoDoesNotCreateDupe() {
        var tomb = qso("DL1ABC", 14_074_000)
        tomb.deleted = true
        let checker = DupeChecker(existing: [tomb])
        // a deleted (tombstone) QSO must not block logging it again
        #expect(!checker.isDupe(call: "DL1ABC", band: .m20))
    }
}

// MARK: - Callsign normalization: Java `trim()`, not Swift `.whitespacesAndNewlines`

/// `DupeChecker.java` builds the key via `call.trim().toUpperCase()`. Java's
/// `trim()` drops characters ≤ U+0020, but **keeps the non-breaking space U+00A0 and
/// U+2007 or DEL**. Swift's `.whitespacesAndNewlines` does exactly the
/// opposite: it drops U+00A0 and U+2007 and keeps control characters.
///
/// A wrong answer here means the operator rejects a valid QSO as a
/// dupe, or logs a duplicate. Callsigns with U+00A0 commonly arrive
/// from cluster spots and web pastes.
///
/// Measured on Java v1.1.1 (JDK 21, `-Duser.language=en`), logbook `[OK1XOE]` on 20 m:
/// | query | Java |
/// |---|---|
/// | `OK1XOE` | true |
/// | `ok1xoe` | true |
/// | `\u{0001}OK1XOE` | true |
/// | `\tOK1XOE` | true |
/// | `OK1XOE  ` | true |
/// | `\u{00A0}OK1XOE` | **false** |
/// | `OK1XOE\u{00A0}` | **false** |
/// | `\u{2007}OK1XOE` | **false** |
/// | `\u{007F}OK1XOE` | **false** |
@Suite struct DupeCheckerCallNormalizationTests {

    private func qso(_ call: String, _ freqHz: Int) -> Qso {
        var q = Qso()
        q.call = call
        q.freqHz = freqHz
        return q
    }

    /// The logbook contains a plain `OK1XOE`; queries with whitespace and control characters.
    @Test func queryForPlainCallsignInLogbook() {
        let checker = DupeChecker(existing: [qso("OK1XOE", 14_025_000)])
        // Java trim() drops it — dupe.
        #expect(checker.isDupe(call: "OK1XOE", band: .m20))
        #expect(checker.isDupe(call: "ok1xoe", band: .m20))
        #expect(checker.isDupe(call: "\u{0001}OK1XOE", band: .m20))
        #expect(checker.isDupe(call: "\tOK1XOE", band: .m20))
        #expect(checker.isDupe(call: "OK1XOE  ", band: .m20))
        // Java trim() does not drop it — not a dupe.
        #expect(!checker.isDupe(call: "\u{00A0}OK1XOE", band: .m20))
        #expect(!checker.isDupe(call: "OK1XOE\u{00A0}", band: .m20))
        #expect(!checker.isDupe(call: "\u{2007}OK1XOE", band: .m20))
        #expect(!checker.isDupe(call: "\u{007F}OK1XOE", band: .m20))
    }

    /// Operational consequence for the operator: the same callsign with a non-breaking space
    /// and without it is **not** the same QSO. Java measured: logbook `[\u{00A0}OK1XOE]`
    /// → `isDupe("OK1XOE")` = false, `isDupe("\u{00A0}OK1XOE")` = true.
    @Test func nonBreakingSpaceIsDifferentCallsign() {
        let checker = DupeChecker(existing: [qso("\u{00A0}OK1XOE", 14_025_000)])
        #expect(!checker.isDupe(call: "OK1XOE", band: .m20))
        #expect(checker.isDupe(call: "\u{00A0}OK1XOE", band: .m20))
    }

    /// A control character, on the other hand, **must** be trimmed: logbook `[\u{0001}OK1XOE]` already has
    /// `Qso.call` stored as `OK1XOE`, and the query `\u{0001}OK1XOE` must be a dupe.
    @Test func controlCharacterIsTrimmed() {
        let checker = DupeChecker(existing: [qso("\u{0001}OK1XOE", 14_025_000)])
        #expect(checker.isDupe(call: "OK1XOE", band: .m20))
        #expect(checker.isDupe(call: "\u{0001}OK1XOE", band: .m20))
        #expect(!checker.isDupe(call: "\u{00A0}OK1XOE", band: .m20))
    }
}
