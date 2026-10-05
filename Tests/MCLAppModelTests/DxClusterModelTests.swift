import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// An app over a temporary data directory whose network is a fake telnet node on `127.0.0.1`, a scripted callbook
/// HTTP and a recording browser — never a real host.
@MainActor
struct SpotApp {
    let app: TestApp
    let server: FakeTelnetServer
    let sleeper: TestSleeper
    let http: FakeHttpGetter
    let opener: RecordingUrlOpener
    let spotClock: ManualClock

    var model: AppModel { app.model }
    var dx: DxClusterModel { app.model.dxCluster }

    static func make(now: TestNow? = nil, configure: @escaping (inout AppConfig, FakeTelnetServer) -> Void = { _, _ in },
                     adjust: @escaping (inout AppModel.Environment) -> Void = { _ in }) async throws -> SpotApp {
        let server = try FakeTelnetServer()
        let sleeper = TestSleeper()
        let http = FakeHttpGetter()
        let opener = RecordingUrlOpener()
        let clock = ManualClock()
        let app = try await TestApp.make(now: now, configure: { config, _ in
            configure(&config, server)
        }, adjust: { environment in
            environment.network = NetworkPorts(makeSession: NetworkPorts.sessions(sleep: sleeper.sleep), http: http,
                                               urlOpener: opener.opener)
            environment.spotClock = clock
            adjust(&environment)
        })
        return SpotApp(app: app, server: server, sleeper: sleeper, http: http, opener: opener, spotClock: clock)
    }

    /// The traffic log as one text.
    var logText: String {
        dx.log.snapshot().joined(separator: "\n")
    }

    func settle() async {
        await dx.settle()
        await model.callbook.settle()
        await runMainQueue()
    }

    /// Connects the main connection to `fav` and waits for the state.
    func connectMain(_ fav: DxClusterFavorite) async {
        dx.connect(fav)
        await eventually("main connected") { dx.connected }
        await eventually("node accepted") { server.connectionCount >= 1 }
    }
}

/// The main DX cluster connection over a fake node: the mirrored state, login with the
/// password after 400 ms on the injected sleep, `BYE`, a lost connection, spots into the buffer, the self-spot
/// messages, WWV, unexpected errors, the ports and the favourite/macro saves.
@MainActor @Suite struct DxClusterModelTests {

    static let ownRbnSpot = "DX de DL1ABC-#:  14025.0  OK1XOE   CW 21 dB 25 WPM CQ  1234Z"
    static let ownHumanSpot = "DX de OK1ABC:    14025.0  OK1XOE   tnx QSO          1234Z"

    @Test func connectsLogsInAndLogsOut() async throws {
        let spot = try await SpotApp.make()
        let fav: DxClusterFavorite = spot.server.favorite(name: "Fake", login: "OK1XXX", password: "secret")
        #expect(spot.dx.statusText == "Odpojeno")
        await spot.connectMain(fav)
        #expect(spot.dx.statusText == "Připojeno k Fake")
        #expect(spot.dx.currentFavorite == fav)

        spot.sleeper.hold()
        spot.dx.login(fav)
        await eventually("password wait") { spot.sleeper.requests == [400] }
        await eventually("login name sent") { spot.server.lines(0) == ["OK1XXX"] }
        // The status hop may still be queued behind the test's own resumption: wait for it, never read it once.
        await eventually("logging-in status") { spot.dx.statusText == "Přihlašuji jako OK1XXX…" }
        spot.sleeper.release()
        await eventually("password sent") { spot.server.lines(0) == ["OK1XXX", "secret"] }
        await spot.settle()
        #expect(spot.logText.contains("» OK1XXX"))
        #expect(spot.logText.contains("· (heslo odesláno)"))
        #expect(!spot.dx.loggedIn)

        spot.server.push("Hello OK1XXX, this is a fake node")
        await eventually("logged in") { spot.dx.loggedIn }
        #expect(spot.dx.statusText == "Přihlášeno jako OK1XXX")

        spot.dx.logout()
        await eventually("BYE sent") { spot.server.lines(0).last == "BYE" }
        await eventually("logging-out status") { spot.dx.statusText == "Odhlašuji…" }
        await spot.settle()
        #expect(!spot.dx.loggedIn)
        #expect(spot.logText.contains("» BYE"))
    }

    @Test func aLostConnectionShowsItsText() async throws {
        let spot = try await SpotApp.make()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.dropAll()
        await eventually("lost") { !spot.dx.connected }
        #expect(spot.dx.statusText == "Spojení ztraceno: DX cluster ukončil spojení")
        #expect(spot.dx.currentFavorite == nil)
    }

    @Test func toggleDisconnectsWithKotlinsUntranslatedText() async throws {
        let spot = try await SpotApp.make()
        let fav: DxClusterFavorite = spot.server.favorite(name: "")
        spot.dx.toggle(fav)
        await eventually("connected") { spot.dx.connected }
        #expect(spot.dx.statusText == "Připojeno k 127.0.0.1")
        spot.dx.toggle(fav)
        await eventually("disconnected") { !spot.dx.connected }
        #expect(spot.dx.statusText == "Odpojeno")
    }

    @Test func spotsReachTheBufferTheFeedAndThePorts() async throws {
        let spot = try await SpotApp.make()
        let order = SpotPortLog()
        spot.dx.pluginSpot = { order.add("plugin " + $0.dxCall) }
        spot.dx.spotShare = { order.add("share " + $0.dxCall) }
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        let before: Int = spot.model.spotFeed.revision
        spot.server.push("DX de OK1ABC:     14030.0  OH2AS         CQ up 2          1234Z")
        spot.server.push("DX de OK1ABC:     7010.0  DL5XX         599          1234Z")
        await eventually("two spots") { spot.dx.spots.snapshot().count == 2 }
        await eventually("feed moved") { spot.model.spotFeed.revision > before }
        // The buffer is filled before the ports run on the reader thread, and the feed may coalesce: wait for both.
        await eventually("feed has both") { spot.model.spotFeed.snapshot().map(\.dxCall) == ["OH2AS", "DL5XX"] }
        await eventually("ports ran") { order.entries.count == 4 }
        #expect(order.entries == ["plugin OH2AS", "share OH2AS", "plugin DL5XX", "share DL5XX"])
        #expect(spot.logText.contains("DX de OK1ABC:     14030.0  OH2AS"))
    }

    @Test func selfSpotsGoToTheMessages() async throws {
        let spot = try await SpotApp.make()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push(Self.ownRbnSpot)
        await eventually("rbn message") { spot.model.messages.lines.count == 1 }
        spot.server.push(Self.ownHumanSpot)
        await eventually("human message") { spot.model.messages.lines.count == 2 }
        let texts: [String] = spot.model.messages.lines.map(\.text)
        #expect(texts == ["RBN: DL1ABC-# tě slyší na 14025,0 kHz, 21 dB, 25 WPM",
                          "Byl jsi spotnut: OK1ABC na 14025,0 kHz"])
    }

    @Test func wwvIsKeptForTheInfoWindow() async throws {
        let spot = try await SpotApp.make()
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        spot.server.push("WWV de VE7CC <18Z> :   SFI=142, A=8, K=3, No Storms -> No Storms")
        await eventually("wwv") { spot.dx.lastWwv != nil }
        #expect(spot.dx.lastWwv?.sfi == 142)
    }

    @Test func unexpectedErrorsGoToTheLogAndTheStatus() async throws {
        let spot = try await SpotApp.make()
        spot.dx.sink.unexpected(DxClusterException("boom"))
        await runMainQueue()
        #expect(spot.model.status.message == "boom")
        #expect(spot.logText.hasSuffix("· boom"))
    }

    /// Kotlin keeps 90 minutes until a Settings OK applies `spotBufferMinutes` (pinned).
    @Test func theBufferAgeFollowsSettingsOnly() async throws {
        let now = TestNow(Date(timeIntervalSince1970: 1_800_000_000))
        let spot = try await SpotApp.make(now: now) { config, _ in
            config.dxCluster.spotBufferMinutes = 5
        }
        spot.dx.spots.add(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        now.advance(seconds: 6 * 60)
        #expect(spot.dx.spots.snapshot().count == 1)
        spot.dx.setBufferMinutes()
        #expect(spot.dx.spots.snapshot().isEmpty)
    }

    @Test func theFavouriteChoiceSavesOnlyItsName() async throws {
        let spot = try await SpotApp.make { config, server in
            config.dxCluster.favorites = [server.favorite(name: "A"), server.favorite(name: "B")]
        }
        #expect(spot.dx.selection == "A")
        spot.dx.selectFavorite("B")
        #expect(spot.dx.selectedFavorite?.name == "B")
        let saved: AppConfig = await spot.app.savedConfigFlushed()
        #expect(saved.dxCluster.lastFavorite == "B")
        spot.dx.resetSelection()
        #expect(spot.dx.selection == "B")
    }

    @Test func aMacroIsSavedTrimmed() async throws {
        let spot = try await SpotApp.make()
        #expect(spot.dx.macros.count == 10)
        spot.dx.saveMacro(index: 2, label: "  Spots  ", command: " SH/DX 50 ")
        let saved: AppConfig = await spot.app.savedConfigFlushed()
        #expect(saved.dxCluster.commands[2] == DxClusterCommand(label: "Spots", command: "SH/DX 50"))
        #expect(saved.dxCluster.commands.count == 10)
    }

    @Test func aFailedMacroSaveIsReported() async throws {
        let spot = try await SpotApp.make(adjust: { environment in
            environment.configWriter = ConfigWriter { _ in throw JavaIOError("disk full") }
        })
        spot.dx.saveMacro(index: 0, label: "X", command: "Y")
        await spot.model.config.flush()
        await eventually("status") { spot.model.status.message == "Uložení tlačítka selhalo (disk full)" }
    }

    @Test func myCallFollowsTheStation() async throws {
        let spot = try await SpotApp.make()
        #expect(spot.dx.mainLane.session.myCall == "OK1XOE")
        spot.model.config.config.station.call = "OK1XXX"
        spot.dx.applyMyCall()
        await spot.settle()
        #expect(spot.dx.mainLane.session.myCall == "OK1XXX")
    }
}

/// The order the spot ports ran in (written on the reader thread).
final class SpotPortLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    var entries: [String] {
        lock.withLock { list }
    }

    func add(_ entry: String) {
        lock.withLock { list.append(entry) }
    }
}
