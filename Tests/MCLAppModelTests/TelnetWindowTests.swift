import Foundation
@testable import MCLAppModel
@testable import MCLCore
import os
import Testing

/// A `{WAIT}` that only ends when the test releases it (no wall clock).
final class ButtonWaitGate: Sendable {
    private struct State {
        var requests: [Int] = []
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var requests: [Int] { state.withLock { $0.requests } }

    var wait: @Sendable (Int) async -> Void {
        { [self] ms in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                state.withLock { s in
                    s.requests.append(ms)
                    s.waiting.append(continuation)
                }
            }
        }
    }

    func release() {
        let waiting: [CheckedContinuation<Void, Never>] = state.withLock { s in
            defer { s.waiting = [] }
            return s.waiting
        }
        waiting.forEach { $0.resume() }
    }
}

/// The DX Cluster window's N1MM Telnet options over fake nodes on `127.0.0.1`: the button macros `{WAIT}` and `{CONN}`,
/// auto logon when the window opens, the node software from the greeting and the band map's formatted SH/DX, and
/// loading button sets.
@MainActor @Suite struct TelnetWindowTests {

    @Test func waitHoldsTheRestOfAButton() async throws {
        let spot = try await SpotApp.make()
        let gate = ButtonWaitGate()
        spot.dx.buttonWait = gate.wait
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.dx.runButton("SH/WWV {WAIT} SH/WCY")
        spot.dx.runButton("SH/USERS")
        await eventually("first part sent") { spot.server.lines(0) == ["SH/WWV"] }
        await eventually("waiting 5 s") { gate.requests == [5_000] }
        #expect(spot.server.lines(0) == ["SH/WWV"])
        gate.release()
        await eventually("the rest and the next press") { spot.server.lines(0) == ["SH/WWV", "SH/WCY", "SH/USERS"] }
        await spot.settle()
        spot.dx.runButton("BYE")
        await eventually("an ordinary button at once") { spot.server.lines(0).last == "BYE" }
    }

    @Test func connSwitchesToTheNamedClusterAndLogsIn() async throws {
        let rbn = try FakeTelnetServer()
        defer { rbn.stop() }
        let spot = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [server.favorite(name: "Node"),
                                          rbn.favorite(name: "RBN", login: "OK1XXX")]
        })
        await spot.connectMain(spot.dx.favorites[0])
        spot.dx.runButton("{CONN} rbn")
        await eventually("RBN connected") { rbn.connectionCount == 1 && spot.dx.currentFavorite?.name == "RBN" }
        await eventually("logged in by itself") { rbn.lines(0) == ["OK1XXX"] }
        await eventually("the first node closed") { spot.server.openConnections == 0 }
        #expect(spot.dx.selection == "RBN")
        #expect(spot.model.config.config.dxCluster.lastFavorite == "RBN")

        spot.dx.runButton("{CONN} nowhere")
        #expect(spot.model.status.message == "{CONN}: cluster nowhere není v seznamu")
    }

    @Test func autoLogonConnectsWhenTheWindowOpens() async throws {
        let off = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [server.favorite(name: "Fake", login: "OK1XXX")]
        })
        off.dx.windowOpened()
        await off.settle()
        #expect(!off.dx.connecting && !off.dx.connected)
        #expect(off.server.connectionCount == 0)

        let on = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [server.favorite(name: "Fake", login: "OK1XXX")]
            config.dxCluster.autoLogon = true
        })
        on.dx.resetSelection()
        on.dx.windowOpened()
        await eventually("connected") { on.dx.connected }
        await eventually("login sent") { on.server.lines(0) == ["OK1XXX"] }
        on.dx.windowOpened()
        await on.settle()
        #expect(on.server.connectionCount == 1)
    }

    @Test func theGreetingPicksTheShDxFormat() async throws {
        let spot = try await SpotApp.make()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        #expect(spot.dx.detectedSoftware == nil)
        #expect(spot.dx.software == .dxSpider)
        spot.model.bandmap.showDx()
        await eventually("DXSpider format") { spot.server.lines(0) == ["SH/DX 30"] }

        spot.server.push("Welcome to the AR-Cluster node")
        await eventually("detected") { spot.dx.detectedSoftware == .arCluster }
        spot.dx.setShowDxCount(12)
        spot.model.bandmap.showDx()
        await eventually("AR-Cluster format") { spot.server.lines(0).last == "SH/DX/12" }

        spot.dx.setSoftware(.dxSpider)
        #expect(spot.model.config.config.dxCluster.clusterSoftware == "dxspider")
        spot.model.bandmap.showDx()
        await eventually("chosen software wins") { spot.server.lines(0).last == "SH/DX 12" }

        spot.dx.disconnect("Odpojeno")
        await eventually("disconnected") { !spot.dx.connected }
        #expect(spot.dx.detectedSoftware == nil)
    }

    @Test func buttonSetsLoadAndSave() async throws {
        let spot = try await SpotApp.make()
        #expect(spot.dx.buttonsFileText.contains("\nSH/DX,SH/DX\n"))
        #expect(spot.dx.loadButtons("RBN,{CONN} RBN\nWWV,SH/WWV 5\n"))
        #expect(spot.dx.macros[0] == DxClusterCommand(label: "RBN", command: "{CONN} RBN"))
        #expect(spot.dx.macros[1] == DxClusterCommand(label: "WWV", command: "SH/WWV 5"))
        #expect(spot.dx.macros[2] == DxClusterConfig.defaultCommands()[2])
        #expect(spot.model.config.config.dxCluster.commands[0].command == "{CONN} RBN")
        #expect(!spot.dx.loadButtons("# nothing\n"))
        #expect(spot.model.status.message == "Soubor neobsahuje žádné tlačítko")
        spot.dx.setShowButtons(false)
        #expect(!spot.model.config.config.dxCluster.showButtons)
    }

    @Test func theConsoleGreysFilteredSpots() async throws {
        let spot = try await SpotApp.make()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push("DX de DL1XX:     14025.0  DL1ABC       CW                             1200Z")
        spot.server.push("DX de DL1XX:     28025.0  K1ABC        CW                             1200Z")
        await eventually("two spots") { spot.dx.spots.snapshot().count == 2 }
        let analysis: SpotAnalysisModel = spot.model.spotAnalysis
        let before: [ConsoleLine] = spot.dx.consoleLines(analyzer: analysis.current(), analysisRevision: analysis.revision)
        #expect(before.filter { $0.spot != nil }.map(\.tint) == [.cw, .cw])
        var filter = SpotFilter.default
        filter.setBand(.m10, on: false)
        spot.dx.setSpotFilter(filter)
        let after: [ConsoleLine] = spot.dx.consoleLines(analyzer: analysis.current(), analysisRevision: analysis.revision)
        #expect(after.filter { $0.spot != nil }.map(\.tint) == [.cw, .filtered])
        #expect(after.count == before.count)
    }
}

/// The band map's and the console's spot menus: N1MM's cluster queries about a station, the spot history and
/// „Jump to this spot". Fake node on `127.0.0.1` only.
@MainActor @Suite struct TelnetSpotMenuTests {

    @Test func queriesNeedTheClusterAndFollowItsSoftware() async throws {
        let spot = try await SpotApp.make()
        spot.model.bandmap.query(.station, call: "OK1ABC")
        #expect(spot.model.status.message == "DX Cluster není připojen")
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.model.bandmap.query(.lastSpots, call: "ok1abc")
        spot.dx.query(.sun, call: "VK9X")
        await eventually("queries sent") { spot.server.lines(0) == ["SH/DX 10 OK1ABC", "SH/SUN VK9X"] }
        spot.dx.setSoftware(.arCluster)
        spot.dx.query(.lastSpots, call: "OK1ABC")
        spot.dx.query(.qrz, call: "not a call")
        spot.dx.query(.qsl, call: "OK1ABC")
        await eventually("AR-Cluster format") {
            spot.server.lines(0).suffix(2) == ["SH/DX/10 OK1ABC", "SH/QSL OK1ABC"]
        }
    }

    @Test func receivedSpotsGoToTheHistory() async throws {
        let spot = try await SpotApp.make(configure: { config, _ in config.station.call = "OK1XOE" })
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push("DX de DL1XX:     14025.0  OK1ABC       CW                             1200Z")
        spot.server.push("DX de DL2XX:     14025.1  OK1ABC       CW                             1201Z")
        spot.server.push("DX de DL1ABC-#:  14030.0  OK1XOE       CW 21 dB 25 WPM CQ             1202Z")
        await eventually("three in the history") { spot.dx.spotHistory.count == 3 }
        #expect(spot.dx.history(of: "OK1ABC").map(\.spot.spotter) == ["DL1XX", "DL2XX"])
        // The buffer keeps one spot per call; the history keeps each report.
        #expect(spot.dx.spots.snapshot().filter { $0.dxCall == "OK1ABC" }.count == 1)

        let bandmap: BandmapModel = spot.model.bandmap
        bandmap.showHistory(of: " ok1abc ")
        #expect(bandmap.historyCall == "OK1ABC")
        bandmap.showMyHistory()
        #expect(bandmap.historyCall == "OK1XOE")
        #expect(spot.dx.history(of: bandmap.historyCall ?? "").map(\.spot.spotter) == ["DL1ABC-#"])
    }

    @Test func myHistoryNeedsMyCall() async throws {
        let spot = try await SpotApp.make(configure: { config, _ in config.station.call = "" })
        spot.model.bandmap.showMyHistory()
        #expect(spot.model.bandmap.historyCall == nil)
        #expect(spot.model.status.message == "Není zadaná vlastní značka (Nastavení → Stanice)")
    }

    @Test func jumpToThisSpotTunesTheRadio() async throws {
        let spot = try await SpotApp.make()
        spot.model.rig.qsy(14_010_000)
        spot.model.bandmap.jumpToSpot(DxSpot(spotter: "DL1XX", freqHz: 14_025_300, dxCall: "OK1ABC", comment: "CW"))
        #expect(spot.model.rig.tuning.tunedFreqHz == 14_025_300)
    }
}
