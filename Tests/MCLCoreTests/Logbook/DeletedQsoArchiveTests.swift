import Foundation
import Testing
@testable import MCLCore

/// N1MM DELETEDQS: the archive of deleted QSOs in the logbook database, and the edit form's calendar and serial
/// arrows.
@Suite struct DeletedQsoArchiveTests {

    private static func qso(_ call: String, contest: String, at seconds: TimeInterval) -> Qso {
        var qso = Qso()
        qso.call = call
        qso.freqHz = 7_025_000
        qso.mode = .cw
        qso.exchangeRcvd = "599 15"
        qso.serialRcvd = 42
        qso.contestId = contest
        qso.timestampUtc = Date(timeIntervalSince1970: seconds)
        return qso
    }

    @Test func deletingKeepsACopyPerContestNewestFirst() throws {
        var clock: TimeInterval = 1_000_000
        let service = LogbookService(repository: try LogbookRepository.inMemory(),
                                     now: { Date(timeIntervalSince1970: clock) })
        service.activeContestId = "CQWW"
        var a = Self.qso("OK1AA", contest: "CQWW", at: 100)
        var b = Self.qso("DL1ABC", contest: "CQWW", at: 200)
        try service.log(&a)
        try service.log(&b)
        _ = try LogbookMutations.delete([a], in: service)
        clock += 60
        _ = try LogbookMutations.delete([b], in: service, tombstone: true)
        let kept = try service.findDeleted()
        #expect(kept.map(\.qso.call) == ["DL1ABC", "OK1AA"])
        #expect(kept.map(\.deletedAt) == [Date(timeIntervalSince1970: clock), Date(timeIntervalSince1970: clock - 60)])
        let first = try #require(kept.last)
        #expect(first.qso.id == a.id)
        #expect(first.qso.serialRcvd == 42)
        #expect(first.qso.exchangeRcvd == "599 15")
        #expect(first.qso.timestampUtc == Date(timeIntervalSince1970: 100))
        #expect(!kept[0].qso.deleted, "a tombstoned QSO is archived as it was, not as a tombstone")
        // Another contest has its own.
        service.activeContestId = "WPX"
        #expect(try service.findDeleted().isEmpty)
        try service.repository.removeDeleted(archiveIds: [first.archiveId])
        service.activeContestId = "CQWW"
        #expect(try service.findDeleted().map(\.qso.call) == ["DL1ABC"])
    }

    @Test func theFormSteppersAndCalendar() {
        #expect(QsoEditForm.steppedSerial("41", by: 1) == "42")
        #expect(QsoEditForm.steppedSerial(" 2 ", by: -1) == "1")
        #expect(QsoEditForm.steppedSerial("1", by: -1) == "1")
        #expect(QsoEditForm.steppedSerial("", by: 1) == "1")
        var form = QsoEditForm(Self.qso("OK1AA", contest: "", at: 1_700_000_000))
        #expect(form.date == Date(timeIntervalSince1970: 1_700_000_000))
        form.date = Date(timeIntervalSince1970: 1_700_000_060)
        #expect(form.time == LogTableColumns.editTimeText(Date(timeIntervalSince1970: 1_700_000_060)))
        form.time = "nonsense"
        #expect(form.date == nil)
    }
}
