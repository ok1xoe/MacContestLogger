import Foundation
import Testing
@testable import MCLCore

@Suite struct QsoEditFormTests {

    private func sample() -> Qso {
        var qso = Qso()
        qso.id = 7
        qso.timestampUtc = Date(timeIntervalSince1970: 1_700_000_000)
        qso.call = "DL1ABC"
        qso.freqHz = 14_025_000
        qso.mode = .cw
        qso.rstSent = "599"
        qso.rstRcvd = "579"
        qso.serialSent = 12
        qso.exchangeRcvd = "579 14"
        qso.operator = "OK1XOE"
        return qso
    }

    @Test func anUntouchedFormChangesNothing() {
        let qso: Qso = sample()
        #expect(QsoEditForm(qso).apply(to: qso) == .success(qso))
    }

    @Test func everyFieldIsApplied() throws {
        let qso: Qso = sample()
        var form = QsoEditForm(qso)
        #expect(form.freqKHz == "14025.00")
        #expect(form.time == "2023-11-14 22:13:20")
        form.time = "2023-11-14 22:15:00"
        form.call = " ok1aa "
        form.freqKHz = "7025,5"
        form.mode = "ssb"
        form.rstSent = "59"
        form.rstRcvd = "57"
        form.serialSent = "13"
        form.serialRcvd = "4"
        form.exchange = "57 15"
        form.note = " QSB "
        form.operator = "ok1abc"
        form.xqso = true
        let edited: Qso = try form.apply(to: qso).get()
        #expect(edited.timestampUtc == Date(timeIntervalSince1970: 1_700_000_100))
        #expect(edited.call == "OK1AA")
        #expect(edited.freqHz == 7_025_500)
        #expect(edited.band == .m40)
        #expect(edited.mode == .ssb)
        #expect(edited.rstSent == "59")
        #expect(edited.rstRcvd == "57")
        #expect(edited.serialSent == 13)
        #expect(edited.serialRcvd == 4)
        #expect(edited.exchangeRcvd == "57 15")
        #expect(edited.comment == "QSB")
        #expect(edited.operator == "OK1ABC")
        #expect(edited.xqso)
        #expect(edited.id == 7)
    }

    @Test func problemsAreReported() {
        let qso: Qso = sample()
        var form = QsoEditForm(qso)
        form.call = " "
        #expect(form.apply(to: qso) == .failure(.blankCall))
        form = QsoEditForm(qso)
        form.time = "2023-13-45"
        #expect(form.apply(to: qso) == .failure(.time("2023-13-45")))
        form = QsoEditForm(qso)
        form.freqKHz = "abc"
        #expect(form.apply(to: qso) == .failure(.frequency("abc")))
        form = QsoEditForm(qso)
        form.mode = "XYZ"
        #expect(form.apply(to: qso) == .failure(.mode("XYZ")))
        form = QsoEditForm(qso)
        form.serialRcvd = "1a"
        #expect(form.apply(to: qso) == .failure(.serial("1a")))
    }
}
