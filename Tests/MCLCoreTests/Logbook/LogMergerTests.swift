import Foundation
import Testing
@testable import MCLCore

/// Port of `LogMergerTest.java` — merging logbooks (see `LogMerger.swift`).
@Suite struct LogMergerTests {

    private func qso(_ at: String, _ call: String, _ hz: Int, _ mode: Mode) -> Qso {
        var q = Qso()
        q.timestampUtc = ISO8601DateFormatter().date(from: at)!
        q.call = call
        q.freqHz = hz
        q.mode = mode
        return q
    }

    // MARK: - `LogMergerTest.addsOnlyNewQsos`

    @Test func addsOnlyNewQsos() {
        let mine = [qso("2026-11-28T12:00:00Z", "W1AW", 14_025_000, .cw)]
        let other = [
            qso("2026-11-28T12:01:30Z", "w1aw", 14_026_000, .cw), // the same one (clock 90 s off)
            qso("2026-11-28T12:10:00Z", "W1AW", 14_026_000, .cw), // a different QSO (10 min later)
            qso("2026-11-28T12:00:00Z", "W1AW", 7_010_000, .cw), // a different band
            qso("2026-11-28T12:20:00Z", "DL1ABC", 14_030_000, .cw),
            qso("2026-11-28T12:20:30Z", "DL1ABC", 14_030_000, .cw), // a duplicate within the merged log
        ]

        let r = LogMerger.merge(existing: mine, incoming: other)
        #expect(r.toAdd.count == 3)
        #expect(r.duplicates == 2)
    }
}

// MARK: - Callsign normalization: `isBlank()` for skipping, `trim()` for comparison

/// `LogMerger.java` performs **two different** operations on the callsign, each with a different set
/// of whitespace characters:
/// - skipping an incoming QSO: `q.getCall() == null || q.getCall().isBlank()`
///   — i.e. `Character.isWhitespace`, which does **not** consider U+00A0, U+2007 or U+202F
///   whitespace, but does consider U+3000,
/// - comparing two QSOs: `getCall().trim().toUpperCase(Locale.ROOT)` — i.e.
///   characters ≤ U+0020, where U+00A0 stays and DEL (U+007F) too.
///
/// Swift's `.whitespacesAndNewlines` does neither: U+00A0, U+2007 and U+3000 are
/// dropped and control characters kept. A `trim()` on all three lines would be wrong,
/// but Java has `isBlank()` on the skipping line — Java decides.
///
/// Measured on Java v1.1.1 (JDK 21, `-Duser.language=en`):
/// | callsign | `isBlank()` | `merge` toAdd | `same("OK1XOE", …)` |
/// |---|---|---|---|
/// | `OK1XOE` | false | 1 | true |
/// | `ok1xoe` | false | 1 | true |
/// | `\u{00A0}` | **false** | **1** | false |
/// | `\u{007F}` | false | 1 | false |
/// | `\u{3000}` | **true** | **0** | – |
/// | `   ` / `` | true | 0 | false |
/// | `\u{00A0}OK1XOE` | false | 1 | **false** |
/// | `\u{2007}OK1XOE` | false | 1 | **false** |
/// | `\u{007F}OK1XOE` | false | 1 | **false** |
/// | `\u{0001}OK1XOE` | false | 1 | true |
@Suite struct LogMergerCallNormalizationTests {

    private func qso(_ call: String, _ hz: Int = 14_025_000, _ mode: Mode = .cw) -> Qso {
        var q = Qso()
        q.timestampUtc = Date(timeIntervalSince1970: 1_767_225_600)
        q.call = call
        q.freqHz = hz
        q.mode = mode
        return q
    }

    /// The skipping line: Java `isBlank()`. A non-breaking space is **not** a whitespace
    /// character, so a QSO with the callsign `\u{00A0}` gets into the merge.
    @Test func blankIsMeasuredByJavaIsBlank() {
        #expect(LogMerger.merge(existing: [], incoming: [qso("\u{00A0}")]).toAdd.count == 1)
        #expect(LogMerger.merge(existing: [], incoming: [qso("\u{2007}")]).toAdd.count == 1)
        #expect(LogMerger.merge(existing: [], incoming: [qso("\u{202F}")]).toAdd.count == 1)
        // The DEL control character (U+007F) is not dropped by Java `trim()` and `isBlank()` does not
        // consider it whitespace — the QSO passes.
        #expect(LogMerger.merge(existing: [], incoming: [qso("\u{007F}")]).toAdd.count == 1)
        // U+3000, on the other hand, is whitespace per `Character.isWhitespace` — the QSO is skipped.
        #expect(LogMerger.merge(existing: [], incoming: [qso("\u{3000}")]).toAdd.count == 0)
        #expect(LogMerger.merge(existing: [], incoming: [qso("   ")]).toAdd.count == 0)
        #expect(LogMerger.merge(existing: [], incoming: [qso("")]).toAdd.count == 0)
    }

    /// The comparison line: Java `trim()`. A callsign with a non-breaking space is **not**
    /// the same QSO, a callsign with the control character U+0001 is.
    @Test func callsignComparisonUsesJavaTrim() {
        let a = qso("OK1XOE")
        #expect(LogMerger.same(a, qso("OK1XOE")))
        #expect(LogMerger.same(a, qso("ok1xoe")))
        #expect(LogMerger.same(a, qso("\u{0001}OK1XOE")))
        #expect(LogMerger.same(a, qso("\tOK1XOE")))
        #expect(!LogMerger.same(a, qso("\u{00A0}OK1XOE")))
        #expect(!LogMerger.same(a, qso("OK1XOE\u{00A0}")))
        #expect(!LogMerger.same(a, qso("\u{2007}OK1XOE")))
        #expect(!LogMerger.same(a, qso("\u{007F}OK1XOE")))
    }

    /// Operational consequence: a logbook with `OK1XOE` and a merged one with `\u{00A0}OK1XOE`
    /// are **two different** QSOs for Java, so it is added, not skipped.
    @Test func nbspCallsignIsNotConsideredDuplicate() {
        let mine = [qso("OK1XOE")]
        let other = [qso("\u{00A0}OK1XOE")]
        let r = LogMerger.merge(existing: mine, incoming: other)
        #expect(r.toAdd.count == 1)
        #expect(r.duplicates == 0)
    }

    /// A control character is trimmed, on the other hand, so it is a duplicate.
    @Test func controlCharacterInCallsignIsTrimmed() {
        let mine = [qso("OK1XOE")]
        let other = [qso("\u{0001}OK1XOE")]
        let r = LogMerger.merge(existing: mine, incoming: other)
        #expect(r.toAdd.isEmpty)
        #expect(r.duplicates == 1)
    }
}
