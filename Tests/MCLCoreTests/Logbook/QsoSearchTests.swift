import Foundation
import Testing
@testable import MCLCore

/// Port of `QsoSearchTest.java` — full-text search over the logbook for the
/// "QSO overview" window (prefixes `call:`, `nr:`, `ex:`, `band:`, `mode:`, `rst:`,
/// `date:`, free text across columns, AND between terms).
@Suite struct QsoSearchTests {

    private func qso(_ call: String, _ nrTx: Int?, _ nrRx: Int?, _ exchange: String?) -> Qso {
        var q = Qso()
        q.call = call
        q.serialSent = nrTx
        q.serialRcvd = nrRx
        // We represent a Java `null` exchange as "" — in Swift `exchangeRcvd`
        // is not optional (the Swift `Qso` model differs from Java's).
        q.exchangeRcvd = exchange ?? ""
        q.freqHz = 14_074_000 // → 20M
        q.mode = .cw
        q.rstSent = "599"
        q.rstRcvd = "579"
        q.timestampUtc = ISO8601DateFormatter().date(from: "2026-08-14T07:12:33Z")
        return q
    }

    // MARK: - `QsoSearchTest.emptyQueryReturnsInputUntouched`

    @Test func emptyQueryReturnsInputUntouched() {
        // Java tests `assertSame` (reference identity) on a one-element
        // list; `Qso`/`[Qso]` are value types in Swift without identity,
        // so identity cannot be verified the same way. For the test to actually verify something
        // (not merely pass because a one-element list cannot be reordered), it has
        // two elements with distinguishable callsigns and compares the whole array (content
        // and order) — a reimplementation that rebuilt the output
        // (e.g. in reverse order) would fail this test.
        let log = [qso("OK1XOE", 1, 2, "JN79"), qso("DL1ABC", 3, 4, "JO60")]
        #expect(QsoSearch.filter(log, "   ").map(\.call) == log.map(\.call))
        #expect(QsoSearch.filter(log, nil).map(\.call) == log.map(\.call))
    }

    // MARK: - `QsoSearchTest.freeTextMatchesCallCaseInsensitively`

    @Test func freeTextMatchesCallCaseInsensitively() {
        #expect(QsoSearch.matches(qso("OK1XOE", 1, 2, "JN79"), "ok1"))
        #expect(!QsoSearch.matches(qso("OK1XOE", 1, 2, "JN79"), "dl"))
    }

    // MARK: - `QsoSearchTest.freeTextMatchesExchangeAndLocator`

    @Test func freeTextMatchesExchangeAndLocator() {
        #expect(QsoSearch.matches(qso("DL1ABC", 1, 2, "JN79"), "jn79"))
        #expect(QsoSearch.matches(qso("DL1ABC", 1, 2, "JO60RA"), "JO60"))
    }

    // MARK: - `QsoSearchTest.freeNumberMatchesEitherSerialExactly`

    @Test func freeNumberMatchesEitherSerialExactly() {
        let q = qso("OK1XOE", 57, 132, nil)
        #expect(QsoSearch.matches(q, "57"))
        #expect(QsoSearch.matches(q, "132"))
        #expect(!QsoSearch.matches(q, "13")) // not a prefix, exact match only
    }

    // MARK: - `QsoSearchTest.freeTextMatchesBandAndMode`

    @Test func freeTextMatchesBandAndMode() {
        let q = qso("OK1XOE", 1, 2, nil)
        #expect(QsoSearch.matches(q, "20M"))
        #expect(QsoSearch.matches(q, "cw"))
    }

    // MARK: - `QsoSearchTest.prefixNarrowsToSingleColumn`

    @Test func prefixNarrowsToSingleColumn() {
        let q = qso("OK1XOE", 57, 132, "JN79")
        #expect(QsoSearch.matches(q, "call:ok1"))
        #expect(!QsoSearch.matches(q, "call:jn79")) // exchange is not counted
        #expect(QsoSearch.matches(q, "ex:JN79"))
        #expect(!QsoSearch.matches(q, "ex:OK1"))
        #expect(QsoSearch.matches(q, "nrtx:57"))
        #expect(!QsoSearch.matches(q, "nrtx:132"))
        #expect(QsoSearch.matches(q, "nrrx:132"))
        #expect(QsoSearch.matches(q, "nr:57"))
        #expect(QsoSearch.matches(q, "band:20"))
        #expect(QsoSearch.matches(q, "mode:CW"))
        #expect(QsoSearch.matches(q, "rstrx:579"))
        #expect(!QsoSearch.matches(q, "rsttx:579"))
        #expect(QsoSearch.matches(q, "rst:579"))
        #expect(QsoSearch.matches(q, "date:2026-08-14"))
        #expect(!QsoSearch.matches(q, "date:2026-08-15"))
    }

    // MARK: - `QsoSearchTest.unknownPrefixFallsBackToFreeText`

    @Test func unknownPrefixFallsBackToFreeText() {
        // A callsign with a colon must not break the filter.
        #expect(!QsoSearch.matches(qso("OK1XOE", 1, 2, nil), "foo:ok1"))
        #expect(QsoSearch.matches(qso("OK1XOE", 1, 2, "A:B"), "a:b"))
    }

    // MARK: - `QsoSearchTest.emptyPrefixValueDoesNotFilter`

    @Test func emptyPrefixValueDoesNotFilter() {
        #expect(QsoSearch.matches(qso("OK1XOE", 1, 2, nil), "call:"))
    }

    // MARK: - `QsoSearchTest.multipleTermsAreAnded`

    @Test func multipleTermsAreAnded() {
        let q = qso("OK1XOE", 57, 132, "JN79")
        #expect(QsoSearch.matches(q, "ok1 nrrx:132"))
        #expect(!QsoSearch.matches(q, "ok1 nrrx:5"))
    }

    // MARK: - `QsoSearchTest.filterKeepsOrderAndSelectsMatches`

    @Test func filterKeepsOrderAndSelectsMatches() {
        let log = [
            qso("OK1XOE", 1, 10, "JN79"),
            qso("DL1ABC", 2, 20, "JO60"),
            qso("OK2ABC", 3, 30, "JN99"),
        ]
        let found = QsoSearch.filter(log, "ok")
        #expect(found.count == 2)
        #expect(found[0].call == "OK1XOE")
        #expect(found[1].call == "OK2ABC")
    }

    // MARK: - `QsoSearchTest.nullFieldsDoNotThrow`

    @Test func nullFieldsDoNotThrow() {
        let empty = Qso()
        #expect(!QsoSearch.matches(empty, "ok1"))
        #expect(!QsoSearch.matches(empty, "call:ok1"))
        #expect(!QsoSearch.matches(empty, "nr:1"))
        #expect(!QsoSearch.matches(empty, "date:2026"))
    }
}
