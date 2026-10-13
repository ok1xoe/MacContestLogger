import Foundation
import MCLCore
import Testing
@testable import MCLAppModel

/// The Check window (`window.check`), Alt+Y through it and the call field's ✓ / ? (View → „Zobrazovat ? u neznámých
/// volaček").
@MainActor @Suite(.mainActorSafetyNet) struct CheckModelTests {

    private func spot(_ app: PortedApp, _ call: String, times: Int) {
        for index in 0..<times {
            app.model.dxCluster.spots.add(DxSpot(spotter: "OK1S\(index)", freqHz: 14_025_000, dxCall: call,
                                                 comment: ""))
        }
    }

    private func refreshed(_ app: PortedApp) async {
        app.model.check.refresh()
        await app.model.check.settle()
    }

    @Test func panesSearchTheLogMasterScpSpotsFromThreeSpotsAndTheCallHistory() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "OK1XOB", zone: "15")
        app.model.callData.adoptScp(ScpDatabase.of(["OK1XOE", "OK1XD", "DL1ABC"]))
        app.model.callData.adoptCallHistory(CallHistory.parse(["!!Order!!,Call,Name", "OK1XOA,Pavel"]), path: "")
        spot(app, "OK1XOC", times: 3)
        spot(app, "OK1XOD", times: 2)
        let check: CheckModel = app.model.check
        check.open()
        app.entry.callChanged("OK1XO")
        await refreshed(app)
        let calls: [CheckPane: [String]] = Dictionary(uniqueKeysWithValues: check.panes.map {
            ($0.pane, $0.matches.map(\.call))
        })
        #expect(calls[.log] == ["OK1XOB"])
        #expect(calls[.scp] == ["OK1XOE", "OK1XD"])
        #expect(calls[.telnet] == ["OK1XOC"])
        #expect(calls[.callHistory] == ["OK1XOA"])
        #expect(check.panes.first { $0.pane == .scp }?.total == 3)
        #expect(check.query == "OK1XO")
        // Two spots are enough once the threshold is lowered.
        check.update { $0.telnetMinSpots = 2 }
        await refreshed(app)
        #expect(check.panes.first { $0.pane == .telnet }?.matches.map(\.call) == ["OK1XOC", "OK1XOD"])
        #expect(app.model.config.config.checkTelnetMinSpots == 2)
        check.close()
        #expect(!check.isOpen)
    }

    @Test func hiddenPanesAndTheWindowsMenuItem() async throws {
        let app = try await PortedApp.make()
        let check: CheckModel = app.model.check
        #expect(check.visiblePanes == [.log, .scp, .telnet, .callHistory, .reverse])
        check.update { $0.hidden.insert(.telnet) }
        #expect(!check.visiblePanes.contains(.telnet))
        check.update { $0.reverseEnabled = false }
        #expect(check.visiblePanes == [.log, .scp, .callHistory])
        #expect(WindowsModel.menuWindows["window.check"] == "check")
        #expect(app.model.menu.isImplemented("window.check"))
    }

    @Test func altYCyclesThroughThePanesInTheYankOrderSkippingDupes() async throws {
        let app = try await PortedApp.make()
        try await app.startCqWw()
        await app.log(call: "OK1ABD", zone: "15")
        app.model.callData.adoptScp(ScpDatabase.of(["OK1ABC", "OK1ABD", "OK1ABE"]))
        app.entry.setFrequency("14025")
        app.entry.callChanged("OK1AB")
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.call == "OK1ABC")
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.call == "OK1ABE")
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.call == "OK1ABC")
        // Dupes allowed: the logged call (log pane first) comes first.
        app.model.check.update { $0.yankAllowsDupes = true }
        app.entry.callChanged("OK1AB")
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.call == "OK1ABD")
    }

    @Test func altYInAnExchangeFieldTakesTheExchangePanesValue() async throws {
        let app = try await PortedApp.make()
        try await app.start("test-qp")
        app.entry.callChanged("K1ABC")
        app.entry.editContestField("cnty", "AP")
        let check: CheckModel = app.model.check
        check.open()
        await refreshed(app)
        #expect(check.exchangeField == "cnty")
        #expect(check.exchangeValues.map(\.key) == ["APA", "APB"])
        app.entry.focusedField = { .contest("cnty") }
        app.entry.runShortcut(.yankScp)
        #expect(app.entry.form.contestExchange["cnty"] == "APA")
    }

    @Test func reverseLookupSearchesTheLogAndTheCallHistory() async throws {
        let app = try await PortedApp.make()
        try await app.start("test-qp")
        app.entry.setFrequency("14025")
        app.entry.setMode(.cw)
        app.entry.callChanged("W1AW")
        app.entry.editContestField("cnty", "ABK")
        app.entry.submit()
        await app.settle()
        try #require(app.model.logbook.rows.count == 1)
        app.model.callData.adoptCallHistory(CallHistory.parse(["!!Order!!,Call,Cnty", "K1ABC,ABL", "N1XX,APA"]),
                                            path: "")
        let check: CheckModel = app.model.check
        check.open()
        app.entry.callChanged("")
        app.entry.editContestField("cnty", "AB")
        await refreshed(app)
        #expect(check.reverse == ["K1ABC", "W1AW"])
        // A threshold above the typed length searches nothing; anywhere in the value finds more.
        check.update { $0.reverseThreshold = 3 }
        await refreshed(app)
        #expect(check.reverse.isEmpty)
        check.update {
            $0.reverseThreshold = 1
            $0.reverseFromStart = false
        }
        app.entry.editContestField("cnty", "A")
        await refreshed(app)
        #expect(check.reverse == ["K1ABC", "N1XX", "W1AW"])
    }

    @Test func callFieldMarkAndTheViewMenuToggle() async throws {
        let app = try await PortedApp.make()
        app.model.callData.adoptScp(ScpDatabase.of(["OK1XOE"]))
        let check: CheckModel = app.model.check
        app.entry.callChanged("OK")
        #expect(check.mark(for: app.entry) == .none)
        app.entry.callChanged("OK1XOE")
        guard case .matched = check.mark(for: app.entry) else {
            Issue.record("expected a check mark")
            return
        }
        app.entry.callChanged("ZZ9ZZZ")
        #expect(check.mark(for: app.entry) == .unmatched)
        #expect(MenuActions.isChecked("view.unmatchedMark", app: app.model))
        _ = MenuActions.perform("view.unmatchedMark", app: app.model)
        #expect(!MenuActions.isChecked("view.unmatchedMark", app: app.model))
        #expect(check.mark(for: app.entry) == .none)
        // Without any Check shown (no SCP row, window closed) there is no mark.
        _ = MenuActions.perform("view.unmatchedMark", app: app.model)
        app.model.config.config.scpSuggestionsEnabled = false
        #expect(check.mark(for: app.entry) == .none)
        check.open()
        #expect(check.mark(for: app.entry) == .unmatched)
    }
}
