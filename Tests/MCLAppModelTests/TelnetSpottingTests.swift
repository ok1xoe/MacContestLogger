import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM Telnet window's spotting options over a fake node on `127.0.0.1`: the spot comment and its macros in Spot
/// It, Ctrl+P and `{SPOTME}`, the opt-in „Spot all S&P QSOs", and the special calls.
@MainActor @Suite struct TelnetSpottingTests {

    /// CQ WW CW with DL1ABC (zone 14) logged.
    static func contestApp() async throws -> SpotApp {
        let spot = try await SpotApp.make()
        try await spot.app.startCqWwCw()
        await spot.app.logContestQso(call: "DL1ABC", zone: "14")
        await spot.model.logbook.settleMutations()
        return spot
    }

    /// Logs `call` in `mode` at `kHz` (the run mode chosen after tuning).
    static func log(_ spot: SpotApp, _ call: String, zone: String, kHz: String, mode: RunMode) async {
        let entry: EntryModel = spot.model.entry
        entry.setFrequency(kHz)
        spot.model.operating.select(mode, freqHz: entry.form.freqHz)
        entry.callChanged(call)
        entry.editContestField("zone", zone)
        entry.submit()
        await entry.settle()
        await spot.model.logbook.settleMutations()
    }

    @Test func spotItAndCtrlPUseTheSpotComment() async throws {
        let spot = try await Self.contestApp()
        let model: AppModel = spot.model
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.dx.setSpotComment("CQWW {mode}\n z{ZONE} {GRIDSQUARE}")
        #expect(spot.dx.spotComment == "CQWW {mode}  z{ZONE} {GRIDSQUARE}")
        model.entry.setFrequency("14025.3")
        model.entry.callChanged("dl1xyz")
        model.entry.editContestField("zone", "15")
        model.entry.spotIt()
        await eventually("field spot") { spot.server.lines(0) == ["DX 14025.3 DL1XYZ CQWW CW z15"] }
        model.entry.runShortcut(.spotWithComment)
        #expect(model.dialogs.textPrompt?.initial == "CQWW CW z15")
        model.dialogs.cancelPrompt()
        model.entry.wipe()
        model.entry.spotIt()
        await eventually("last QSO with its logged zone") {
            spot.server.lines(0).last == "DX 14025.0 DL1ABC CQWW CW z14"
        }
    }

    @Test func spotMeMacroSpotsMyStation() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        model.entry.setMode(.cw)
        model.entry.setFrequency("14025")
        model.entry.performMacroAction(.spotMe)
        await eventually("CQ") { spot.server.lines(0) == ["DX 14025.0 OK1XOE CQ"] }
        spot.dx.setSpotComment("{MODE} test")
        model.entry.performMacroAction(.spotMe)
        await eventually("with the comment") { spot.server.lines(0).last == "DX 14025.0 OK1XOE CW test" }
    }

    @Test func spotAllSpQsosIsOptInAndOnlyForNewSpQsos() async throws {
        let spot = try await Self.contestApp()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        #expect(!spot.dx.spotAllSpQsos)
        await Self.log(spot, "OK1AAA", zone: "15", kHz: "14030", mode: .searchAndPounce)
        await spot.settle()
        #expect(spot.server.lines(0).isEmpty)

        spot.dx.setSpotAllSpQsos(true)
        spot.dx.setSpotComment("{ZONE}")
        await Self.log(spot, "OK1BBB", zone: "15", kHz: "14031", mode: .searchAndPounce)
        await eventually("S&P QSO spotted") { spot.server.lines(0) == ["DX 14031.0 OK1BBB 15"] }

        // Run, a dupe and a call already in the band map are not spotted.
        await Self.log(spot, "OK1CCC", zone: "15", kHz: "14032", mode: .run)
        await Self.log(spot, "OK1BBB", zone: "15", kHz: "14031", mode: .searchAndPounce)
        spot.dx.spots.add(DxSpot(spotter: "DL1XX", freqHz: 14_033_400, dxCall: "OK1DDD", comment: ""))
        await Self.log(spot, "OK1DDD", zone: "15", kHz: "14033", mode: .searchAndPounce)
        await spot.settle()
        #expect(spot.server.lines(0) == ["DX 14031.0 OK1BBB 15"])

        // Not connected: silently nothing.
        spot.dx.disconnect("Odpojeno")
        await eventually("disconnected") { !spot.dx.connected }
        await Self.log(spot, "OK1EEE", zone: "15", kHz: "14034", mode: .searchAndPounce)
        #expect(spot.model.status.message != "Spot: DX cluster není připojený (okno DX Cluster)")
        #expect(spot.model.config.config.dxCluster.spotAllSpQsos)
    }

    @Test func specialCallsGetTheHeart() async throws {
        let spot = try await Self.contestApp()
        let bandmap: BandmapModel = spot.model.bandmap
        spot.dx.setSpecialCalls(text: "w1aw, OK1ABC\nOK1ABC")
        #expect(spot.dx.specialCalls == ["W1AW", "OK1ABC"])
        #expect(bandmap.isSpecialCall("W1AW/M"))
        #expect(!bandmap.isSpecialCall("K1ZZ"))
        let w1aw = DxSpot(spotter: "DL1XX", freqHz: 14_030_000, dxCall: "W1AW", comment: "")
        #expect(bandmap.drawnLabel(w1aw).hasPrefix("W1AW\u{2665}"))

        #expect(spot.dx.importSpecialCalls("Type=FAVORITES SubType=\nK1ZZ\nW1AW\n") == 1)
        #expect(spot.model.status.message == "Zvláštní volačky: přidáno 1")
        #expect(spot.dx.specialCallsFileText == "Type=FAVORITES SubType=\nW1AW\nOK1ABC\nK1ZZ\n")
        spot.dx.clearSpecialCalls()
        #expect(!bandmap.isSpecialCall("W1AW"))

        // The contest's bonus stations count while the option is on.
        spot.model.contest.runtime.setSessionExtras(tour: nil, bonusStations: ["N1MM"])
        #expect(bandmap.isSpecialCall("N1MM"))
        spot.dx.setSpecialCallsIncludeBonus(false)
        #expect(!bandmap.isSpecialCall("N1MM"))
    }
}
