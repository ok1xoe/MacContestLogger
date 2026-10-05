import Foundation
import Testing
@testable import MCLCore

/// Port of `BulkEditTest.java` — bulk edits of selected QSOs (see `BulkEdit.swift`).
@Suite struct BulkEditTests {

    private func qso(_ id: Int64, _ time: String?) -> Qso {
        var q = Qso()
        q.id = id
        q.call = "K\(id)A"
        q.timestampUtc = time.map { ISO8601DateFormatter().date(from: $0)! }
        q.freqHz = 14_025_000
        q.mode = .cw
        return q
    }

    // MARK: - `BulkEditTest.operatorModeAndFrequency`

    @Test func operatorModeAndFrequency() {
        var qsos = [qso(1, "2026-11-28T12:00:00Z"), qso(2, "2026-11-28T12:01:00Z")]

        BulkEdit.setOperator(&qsos, operator: " ok1kz ")
        BulkEdit.setMode(&qsos, mode: .ssb)
        BulkEdit.setFrequencyHz(&qsos, freqHz: 7_150_000)

        #expect(qsos[1].operator == "OK1KZ")
        #expect(qsos[0].mode == .ssb)
        #expect(qsos[0].band == .m40) // band from frequency

        BulkEdit.setOperator(&qsos, operator: "")
        #expect(qsos[0].operator == "")
    }

    // MARK: - `BulkEditTest.parseFrequencyAndShift`

    @Test func parseFrequencyAndShift() {
        #expect(BulkEdit.parseFrequencyKHz("14025,5") == 14_025_500)
        #expect(BulkEdit.parseFrequencyKHz("12345") == nil)
        #expect(BulkEdit.parseShift("+5") == TimeInterval(5 * 60))
        #expect(BulkEdit.parseShift("-5") == TimeInterval(-5 * 60))
        #expect(BulkEdit.parseShift("1:30") == TimeInterval(90 * 60))
        #expect(BulkEdit.parseShift("-2h") == TimeInterval(-120 * 60))
        #expect(BulkEdit.parseShift("-90m") == TimeInterval(-90 * 60))
        #expect(BulkEdit.parseShift("abc") == nil)
        #expect(BulkEdit.parseShift("0") == nil)
    }

    // MARK: - no Java ancestor: deliberate divergence from `BigDecimal.longValueExact()`

    @Test func exponentialNotationIsRejected() {
        // Java's `BigDecimal("1.4025e4").movePointRight(3).longValueExact()` would
        // accept the exponential notation and compute the same 14 025 000 Hz as
        // from "14025" — but `exactHz` deliberately rejects it (an operator never types an exponent
        // into the kHz field on screen, see the comment at
        // `parseFrequencyKHz`/`exactHz`). The test pins this divergence so that nobody
        // "fixes" it in the wrong direction later.
        #expect(BulkEdit.parseFrequencyKHz("1.4025e4") == nil)
        #expect(BulkEdit.parseFrequencyKHz("1e4") == nil)
    }

    // MARK: - `BulkEditTest.shiftMovesAllTimes`

    @Test func shiftMovesAllTimes() {
        var qsos = [qso(1, "2026-11-28T12:00:00Z"), qso(2, nil)]

        BulkEdit.shiftTime(&qsos, by: -3600)

        #expect(qsos[0].timestampUtc == ISO8601DateFormatter().date(from: "2026-11-28T11:00:00Z")!)
        #expect(qsos[1].timestampUtc == nil)
    }

    // MARK: - `BulkEditTest.interpolationSpreadsTimesBetweenFirstAndLast`

    @Test func interpolationSpreadsTimesBetweenFirstAndLast() {
        // Paper log: all QSOs entered with the first one's time, the last corrected manually.
        var qsos = [
            qso(1, "2026-11-28T12:00:00Z"), qso(2, "2026-11-28T12:00:00Z"),
            qso(3, "2026-11-28T12:00:00Z"), qso(4, "2026-11-28T12:00:00Z"),
            qso(5, "2026-11-28T12:40:00Z"),
        ]

        #expect(BulkEdit.interpolateTime(&qsos))

        let f = ISO8601DateFormatter()
        #expect(qsos[0].timestampUtc == f.date(from: "2026-11-28T12:00:00Z")!)
        #expect(qsos[1].timestampUtc == f.date(from: "2026-11-28T12:10:00Z")!)
        #expect(qsos[2].timestampUtc == f.date(from: "2026-11-28T12:20:00Z")!)
        #expect(qsos[3].timestampUtc == f.date(from: "2026-11-28T12:30:00Z")!)
        #expect(qsos[4].timestampUtc == f.date(from: "2026-11-28T12:40:00Z")!)
    }

    // MARK: - `BulkEditTest.interpolationNeedsThreeQsos`

    @Test func interpolationNeedsThreeQsos() {
        var qsos = [qso(1, "2026-11-28T12:00:00Z"), qso(2, "2026-11-28T12:05:00Z")]
        #expect(!BulkEdit.interpolateTime(&qsos))
    }
}
