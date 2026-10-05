import Foundation
import Testing
@testable import MCLCore

/// Port of `QsoSortTest.java` — logbook sorting for the table in the "QSO overview" window.
@Suite struct QsoSortTests {

    private func qso(_ call: String?, _ time: String?) -> Qso {
        var q = Qso()
        if let call { q.call = call }
        // An empty callsign is represented as "" (Java `null`) — `Qso.call`
        // is not optional in Swift.
        q.timestampUtc = time.flatMap { ISO8601DateFormatter().date(from: $0) }
        return q
    }

    private func calls(_ qsos: [Qso]) -> [String?] {
        qsos.map { $0.call.isEmpty ? nil : $0.call }
    }

    // MARK: - `QsoSortTest.sortsByTimeBothDirections`

    @Test func sortsByTimeBothDirections() {
        let log = [
            qso("B", "2026-08-14T08:00:00Z"),
            qso("A", "2026-08-14T07:00:00Z"),
            qso("C", "2026-08-14T09:00:00Z"),
        ]
        #expect(calls(QsoSort.sort(log, key: .time, ascending: true)) == ["A", "B", "C"])
        #expect(calls(QsoSort.sort(log, key: .time, ascending: false)) == ["C", "B", "A"])
    }

    // MARK: - `QsoSortTest.sortsByCallCaseInsensitivelyWithTimeAsTiebreak`

    @Test func sortsByCallCaseInsensitivelyWithTimeAsTiebreak() {
        let log = [
            qso("OK2ABC", "2026-08-14T07:00:00Z"),
            qso("ok1xoe", "2026-08-14T09:00:00Z"),
            qso("OK1XOE", "2026-08-14T08:00:00Z"),
        ]
        // `call` normalizes to upper case, both OK1XOE are ordered by time.
        let asc = QsoSort.sort(log, key: .call, ascending: true)
        #expect(calls(asc) == ["OK1XOE", "OK1XOE", "OK2ABC"])
        #expect(asc[0].timestampUtc == ISO8601DateFormatter().date(from: "2026-08-14T08:00:00Z"))
    }

    // MARK: - `QsoSortTest.emptyValuesStayLastInBothDirections`

    @Test func emptyValuesStayLastInBothDirections() {
        let log = [
            qso("B", "2026-08-14T08:00:00Z"),
            qso(nil, "2026-08-14T07:00:00Z"),
            qso("A", "2026-08-14T09:00:00Z"),
        ]
        #expect(calls(QsoSort.sort(log, key: .call, ascending: true)) == ["A", "B", nil])
        #expect(calls(QsoSort.sort(log, key: .call, ascending: false)) == ["B", "A", nil])
    }

    // MARK: - `QsoSortTest.sortsBandByFrequency`

    @Test func sortsBandByFrequency() {
        var m20 = qso("A", "2026-08-14T07:00:00Z")
        m20.freqHz = 14_074_000
        var m40 = qso("B", "2026-08-14T08:00:00Z")
        m40.freqHz = 7_030_000
        var m20b = qso("C", "2026-08-14T09:00:00Z")
        m20b.freqHz = 14_010_000
        #expect(
            calls(QsoSort.sort([m20, m40, m20b], key: .band, ascending: true)) == ["B", "C", "A"])
    }

    // MARK: - `QsoSortTest.sortsSerialsNumericallyNotLexically`

    @Test func sortsSerialsNumericallyNotLexically() {
        var a = qso("A", "2026-08-14T07:00:00Z")
        a.serialRcvd = 9
        var b = qso("B", "2026-08-14T08:00:00Z")
        b.serialRcvd = 100
        var c = qso("C", "2026-08-14T09:00:00Z")
        c.serialRcvd = 57
        #expect(
            calls(QsoSort.sort([a, b, c], key: .serialRcvd, ascending: true)) == ["A", "C", "B"])
    }

    // MARK: - `QsoSortTest.sortsByModeAndExchange`

    @Test func sortsByModeAndExchange() {
        var a = qso("A", "2026-08-14T07:00:00Z")
        a.mode = .ssb
        a.exchangeRcvd = "JO60"
        var b = qso("B", "2026-08-14T08:00:00Z")
        b.mode = .cw
        b.exchangeRcvd = "JN79"
        #expect(calls(QsoSort.sort([a, b], key: .mode, ascending: true)) == ["B", "A"])
        #expect(calls(QsoSort.sort([a, b], key: .exchange, ascending: true)) == ["B", "A"])
    }

    // MARK: - `QsoSortTest.doesNotMutateInput`

    @Test func doesNotMutateInput() {
        let log = [qso("B", "2026-08-14T08:00:00Z"), qso("A", "2026-08-14T07:00:00Z")]
        _ = QsoSort.sort(log, key: .call, ascending: true)
        #expect(calls(log) == ["B", "A"])
    }

    // MARK: - sort stability (our own guarantee, `QsoSort.stableSort`)

    /// QSOs with the same callsign and the same time (i.e. the same sort key
    /// on both comparator levels) must keep their original order — exactly
    /// as in Java (`List.sort` is stable). `Array.sorted` has been stable
    /// since SE-0372 too (verified by experiment, see `QsoSort.swift`), so
    /// this test would pass even without `stableSort`; but it documents our own
    /// guarantee (index as tiebreak), not a stdlib promise that could change
    /// in the future.
    @Test func stableSortPreservesOriginalOrderForEqualKeys() {
        let time = ISO8601DateFormatter().date(from: "2026-08-14T07:00:00Z")
        var log: [Qso] = []
        for i in 0..<50 {
            var q = Qso()
            q.call = "SAME"
            q.timestampUtc = time
            q.serialRcvd = i // distinguishes elements, but is not sorted by
            log.append(q)
        }
        let sorted = QsoSort.sort(log, key: .call, ascending: true)
        #expect(sorted.map { $0.serialRcvd } == Array(0..<50))
    }
}
