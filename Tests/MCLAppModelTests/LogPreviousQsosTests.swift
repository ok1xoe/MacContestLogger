import Foundation
import Testing
@testable import MCLAppModel
@testable import MCLCore

/// N1MM's lower pane of the log window (the previous QSOs of the typed call) and „Show rates to this QSO in Info".
@MainActor @Suite struct LogPreviousQsosTests {

    private func app() async throws -> PortedApp {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "W1AW", zone: "5")
        await app.log(call: "DL1ABC", zone: "14", freqKHz: "7025")
        await app.log(call: "W1AW", zone: "5", freqKHz: "7025")
        await app.model.logbook.settle()
        return app
    }

    @Test func thePaneShowsTheTypedCallsQsos() async throws {
        let app = try await app()
        let table = LogTableModel(app: app.model)
        #expect(table.typedCall.isEmpty)
        #expect(table.previousQsos.isEmpty)
        app.model.entry.callChanged("w1aw")
        #expect(table.typedCall == "W1AW")
        let rows: [Qso] = table.previousQsos
        #expect(rows.count == 2)
        #expect(rows.map(\.band) == [.m20, .m40])
        app.model.entry.callChanged("OK1XYZ")
        #expect(table.previousQsos.isEmpty)
    }

    @Test func aPaneLineCarriesTheQsosFields() {
        var qso = Qso()
        qso.call = "W1AW"
        qso.freqHz = 14_025_000
        qso.mode = .cw
        qso.rstSent = "599"
        qso.rstRcvd = "599"
        qso.serialSent = 12
        qso.exchangeRcvd = "5"
        qso.comment = "QSL"
        qso.timestampUtc = Date(timeIntervalSince1970: 0)
        let line: String = LogTableModel.previousLine(qso)
        #expect(line.contains("20M") || line.contains("20m"))
        #expect(line.contains("#12"))
        #expect(line.contains("· QSL"))
    }

    @Test func ratesAtAQsoUseTheLogUpToIt() async throws {
        let app = try await app()
        let first: Qso = try #require(app.model.logbook.rows.first)
        let table = LogTableModel(app: app.model)
        let id: Int64 = try #require(first.id)
        #expect(table.menuItems(forRow: id).contains(.ratesToHere))
        table.perform(.ratesToHere, row: id)
        let info: InfoModel = app.model.info
        let at = try #require(info.ratesAt)
        #expect(at.call == "W1AW")
        #expect(at.time == first.timestampUtc)
        #expect(at.stats == ContestStats.of([first]))
        #expect(app.model.windows.isOpen("rate"))
        info.showCurrentRates()
        #expect(info.ratesAt == nil)
    }
}
