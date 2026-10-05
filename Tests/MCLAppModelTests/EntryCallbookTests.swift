import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The callbook in the entry window: the lookup 700 ms after the last change of the call, only for
/// the active window and only kept for the call still typed; the line `"Callbook: " + describe`; the prefill
/// `CallbookPrefill.prefill(rec) + callHistory.prefill` (the call history wins) with the filled values taken back;
/// and the spot calls in Check partial and N+1. HTTP is a scripted getter (no socket).
@MainActor @Suite struct EntryCallbookTests {

    /// CQ WW CW with HamQTH credentials and an optional call history.
    static func app(callHistory: String = "") async throws -> SpotApp {
        let spot = try await SpotApp.make { config, _ in
            CallbookModelTests.credentials(&config, qrz: false)
        }
        if !callHistory.isEmpty {
            let url: URL = spot.app.dataDir.appendingPathComponent("CALLHISTORY.txt")
            try Data(callHistory.utf8).write(to: url)
            spot.model.config.config.callHistoryFile = url.path
            spot.model.callData.reloadCallHistory()
            await spot.model.callData.settle()
        }
        try await spot.app.startCqWwCw()
        return spot
    }

    /// Types into the main window and lets the suggestions see it.
    static func type(_ spot: SpotApp, _ call: String) async {
        spot.model.entry.callChanged(call)
        await runMainQueue()
    }

    static func advance(_ spot: SpotApp, _ milliseconds: Int) async {
        spot.app.suggestionClock.advance(by: milliseconds)
        await spot.model.callbook.settle()
        await runMainQueue()
        await runMainQueue()
    }

    static func hamQthAsked(_ spot: SpotApp) -> [String] {
        spot.http.urls.filter { $0.contains("callsign=") }
    }

    @Test func theLookupWaits700MsAfterTheLastChange() async throws {
        let spot = try await Self.app()
        spot.http.hamQth(call: "OK1ABC", name: "Jan", cq: "15")
        await Self.type(spot, "OK1AB")
        await Self.advance(spot, 500)
        await Self.type(spot, "OK1ABC")
        await Self.advance(spot, 699)
        #expect(Self.hamQthAsked(spot).isEmpty)
        await Self.advance(spot, 1)
        #expect(Self.hamQthAsked(spot).count == 1)
        #expect(Self.hamQthAsked(spot).first?.contains("OK1ABC") == true)
        #expect(spot.model.callbook.callbookRecord?.call == "OK1ABC")
        #expect(spot.model.suggestions.callbookLine == "Callbook: Jan · CQ 15")
        // The prefill follows the record 250 ms later.
        await Self.advance(spot, 250)
        #expect(spot.model.entry.form.contestExchange["zone"] == "15")
        #expect(spot.model.suggestions.chFilled["zone"] == "15")
        // Another call: the line goes at once, the filled zone is taken back.
        await Self.type(spot, "OK1ABD")
        #expect(spot.model.suggestions.callbookLine == nil)
        await Self.advance(spot, 250)
        #expect(spot.model.entry.form.contestExchange["zone"] == nil)
    }

    /// The result of a lookup is kept only while the active window still has the call (Kotlin `typedCall`).
    @Test func aLateResultForAnotherCallIsNotShown() async throws {
        let spot = try await Self.app()
        spot.http.hamQth(call: "OK1ABC", cq: "15")
        await Self.type(spot, "OK1ABC")
        spot.app.suggestionClock.advance(by: 700)
        spot.model.entry.callChanged("OK2XYZ")
        await spot.model.callbook.settle()
        await runMainQueue()
        #expect(spot.model.callbook.callbookRecord == nil)
        #expect(spot.model.callbook.record(for: "OK1ABC")?.cqZone == "15")
    }

    /// The call history wins over the callbook; the callbook fills what the call history lacks.
    @Test func theCallHistoryWinsOverTheCallbook() async throws {
        let spot = try await Self.app(callHistory: "!!Order!!,Call,CQZone\nOK1ABC,14\nOK1ABD,\n")
        spot.http.hamQth(call: "OK1ABC", cq: "15")
        spot.http.hamQth(call: "OK1ABD", cq: "16")
        await Self.type(spot, "OK1ABC")
        await Self.advance(spot, 700)
        await Self.advance(spot, 250)
        #expect(spot.model.suggestions.callbookLine == "Callbook: CQ 15")
        #expect(spot.model.entry.form.contestExchange["zone"] == "14")
        await Self.type(spot, "OK1ABD")
        await Self.advance(spot, 700)
        await Self.advance(spot, 250)
        #expect(spot.model.entry.form.contestExchange["zone"] == "16")
    }

    /// Only the active window looks the call up (`if (active)`); the inactive one shows a record only for its call.
    @Test func onlyTheActiveWindowLooksUp() async throws {
        let spot = try await SpotApp.make { config, _ in
            CallbookModelTests.credentials(&config, qrz: false)
            config.radioMode = "SO2V"
        }
        spot.http.hamQth(call: "OK1VFB", cq: "15")
        let second: EntryModel = spot.model.vfoB.entry
        second.isWindowShown = true
        #expect(!second.isActivePanel)
        second.callChanged("OK1VFB")
        await runMainQueue()
        await Self.advance(spot, 700)
        #expect(Self.hamQthAsked(spot).isEmpty)
        #expect(spot.model.vfoB.suggestions.callbookLine == nil)
    }

    /// Kotlin `LaunchedEffect(call) { delay(700); if (active) … }` reads `active` when the pause starts: a window that
    /// was active then still looks its call up after it became inactive.
    @Test func activityIsReadWhenThePauseStarts() async throws {
        let spot = try await SpotApp.make { config, _ in
            CallbookModelTests.credentials(&config, qrz: false)
            config.radioMode = "SO2V"
        }
        spot.http.hamQth(call: "OK1ABC", cq: "15")
        spot.model.vfoB.entry.isWindowShown = true
        await Self.type(spot, "OK1ABC")
        spot.model.rig.activateVfo(1)
        #expect(!spot.model.entry.isActivePanel)
        await Self.advance(spot, 700)
        #expect(Self.hamQthAsked(spot).count == 1)
    }

    /// The spot calls of the buffer join Check partial (source `SPOT`, underlined) and N+1.
    @Test func spotCallsJoinTheSuggestions() async throws {
        let spot = try await SpotApp.make()
        spot.model.dxCluster.spots.add(DxSpot(spotter: "OK1RR", freqHz: 14_030_000, dxCall: "OK1SPT", comment: ""))
        await Self.type(spot, "OK1S")
        await spot.model.suggestions.settle()
        #expect(spot.model.suggestions.partial.contains(PartialCheck.Suggestion(call: "OK1SPT", source: .SPOT)))
        await Self.type(spot, "OK1SPU")
        await spot.model.suggestions.settle()
        #expect(spot.model.suggestions.nPlusOne.contains("OK1SPT"))
    }
}
