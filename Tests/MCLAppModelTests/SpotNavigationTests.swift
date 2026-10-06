import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spot actions of the entry window: the navigation (dupes skipped, multipliers, own spots,
/// the six texts), Alt+D within 200 Hz and onto the blacklist, Mark, Store, Spot It, Ctrl+P, SPOTME and the beacons.
/// A spot reaches only the `FakeTelnetServer` on 127.0.0.1, and only from the action under test; the rig is inert.
@MainActor @Suite struct SpotNavigationTests {

    static func spot(_ call: String, _ freqHz: Int, selfSpotted: Bool = false) -> DxSpot {
        DxSpot(spotter: "OK1RR", freqHz: freqHz, dxCall: call, comment: "", selfSpotted: selfSpotted)
    }

    /// CQ WW CW with DL1ABC (zone 14) logged on 20 m.
    static func contestApp(now: TestNow? = nil) async throws -> SpotApp {
        let spot = try await SpotApp.make(now: now)
        try await spot.app.startCqWwCw()
        await spot.app.logContestQso(call: "DL1ABC", zone: "14")
        await spot.model.logbook.settleMutations()
        return spot
    }

    // MARK: - navigation

    @Test func navigationSkipsDupesAndFollowsTheFilters() async throws {
        let spot = try await Self.contestApp()
        let model: AppModel = spot.model
        let navigation: SpotNavigation = model.spotNavigation
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("DL1ABC", 14_022_000))
        buffer.add(Self.spot("DL2XYZ", 14_025_000))
        buffer.add(Self.spot("W1AW", 14_030_000))
        buffer.add(Self.spot("OK2SELF", 14_040_000, selfSpotted: true))
        model.rig.qsy(14_020_000)

        navigation.jump(direction: 1)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(model.entry.form.call == "DL2XYZ")
        navigation.jump(direction: 1, onlyMult: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(model.entry.form.call == "W1AW")
        navigation.jump(direction: -1)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        // DL1ABC below is a dupe: skipped.
        navigation.jump(direction: -1)
        #expect(model.rig.tuning.tunedFreqHz == 14_025_000)
        #expect(model.status.message == "Žádný spot níž na pásmu")
        navigation.jump(direction: 1, onlySelf: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_040_000)
        navigation.jump(direction: 1, onlyMult: true)
        #expect(model.status.message == "Žádný násobič výš na pásmu")
        navigation.jump(direction: -1, onlySelf: true)
        #expect(model.status.message == "Žádný vlastní spot níž na pásmu")
        navigation.jump(direction: 1)
        #expect(model.status.message == "Žádný spot výš na pásmu")
        navigation.jump(direction: -1, onlyMult: true)
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        navigation.jump(direction: -1, onlyMult: true)
        #expect(model.status.message == "Žádný násobič níž na pásmu")
        navigation.jump(direction: 1, onlySelf: true)
        navigation.jump(direction: 1, onlySelf: true)
        #expect(model.status.message == "Žádný vlastní spot výš na pásmu")
    }

    /// An own spot counts even when it is a dupe (the predicate is only `selfSpotted`).
    @Test func ownSpotsIncludeDupes() async throws {
        let spot = try await Self.contestApp()
        let model: AppModel = spot.model
        model.dxCluster.spots.add(Self.spot("DL1ABC", 14_022_000, selfSpotted: true))
        model.rig.qsy(14_030_000)
        model.entry.runShortcut(.nextSelfDown)
        #expect(model.rig.tuning.tunedFreqHz == 14_022_000)
        model.rig.qsy(14_030_000)
        model.entry.runShortcut(.nextSpotDown)
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(model.status.message == "Žádný spot níž na pásmu")
    }

    // MARK: - Alt+D, Mark, Store

    /// Alt+D with an empty field takes the nearest spot within 200 Hz of the tuned frequency (inclusive); every spot of
    /// that call goes; Alt+Shift+D also blacklists it.
    @Test func removeSpotWithin200HzAndBlacklist() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        let buffer: SpotBuffer = model.dxCluster.spots
        buffer.add(Self.spot("W1AW", 14_030_000))
        buffer.add(Self.spot("DL2XYZ", 14_025_000))
        // (The entry field shows 10 Hz steps and feeds them back, so 210 Hz is the next step past 200.)
        model.rig.qsy(14_030_210)
        model.spotNavigation.removeSpotOf(call: "", blacklist: true)
        #expect(model.status.message == "Alt+D: na frekvenci ani v poli volačky není spot")
        model.rig.qsy(14_030_200)
        model.spotNavigation.removeSpotOf(call: " ", blacklist: true)
        #expect(model.status.message == "Spot W1AW odstraněn a dán na blacklist")
        #expect(buffer.snapshot().map(\.dxCall) == ["DL2XYZ"])
        #expect(model.config.config.dxCluster.callBlacklist.map(\.value) == ["W1AW"])
        // The call of the field (Kotlin `trim().uppercase()`), without the blacklist.
        model.entry.callChanged(" dl2xyz")
        model.entry.runShortcut(.removeSpot)
        #expect(model.status.message == "Spot DL2XYZ odstraněn")
        #expect(buffer.snapshot().isEmpty)
        #expect(model.config.config.dxCluster.callBlacklist.count == 1)
    }

    /// Alt+M marks the field's frequency (`*%.1f`, a decimal point in every language); the button refocuses.
    @Test func markPutsAMarkSpot() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.setFrequency("14031.56")
        model.entry.runShortcut(.mark)
        #expect(model.dxCluster.spots.snapshot() == [
            DxSpot(spotter: "MARK", freqHz: 14_031_560, dxCall: "*14031.6", comment: "obsazeno", selfSpotted: true),
        ])
        #expect(model.status.message == "Frekvence 14031.6 kHz označena v bandmapě")
        let focus: Int = model.entry.focusRequest
        model.entry.markButton()
        #expect(model.entry.focusRequest == focus + 1)
        model.status.clear()
        // Without a frequency (no rig, empty field) nothing is added and the status says why.
        model.entry.setFrequency("")
        model.entry.runShortcut(.mark)
        #expect(model.dxCluster.spots.snapshot().count == 1)
        #expect(model.status.message == Self.noFrequency)
        model.status.clear()
        model.entry.markButton()
        #expect(model.dxCluster.spots.snapshot().count == 1)
        #expect(model.status.message == Self.noFrequency)
    }

    static let noFrequency = "Není zadaný kmitočet — připoj rádio nebo ho zadej do pole kmitočtu"

    /// Store without a frequency adds no spot at 0 Hz and does not claim it stored anything (Alt+O and the button).
    @Test func storeNeedsAFrequency() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.setFrequency("")
        model.entry.callChanged("ok1abc")
        model.entry.runShortcut(.store)
        #expect(model.dxCluster.spots.snapshot().isEmpty)
        #expect(model.status.message == Self.noFrequency)
        model.status.clear()
        model.entry.storeCall()
        #expect(model.dxCluster.spots.snapshot().isEmpty)
        #expect(model.status.message == Self.noFrequency)
        // A blank call is still reported first; with a frequency the store works.
        model.entry.callChanged("")
        model.entry.storeCall()
        #expect(model.status.message == "Store: zadej volačku")
        model.entry.setFrequency("14025")
        model.entry.callChanged("ok1abc")
        model.entry.storeCall()
        #expect(model.dxCluster.spots.snapshot().map(\.freqHz) == [14_025_000])
    }

    /// Spot It and Ctrl+P never send a spot at 0 Hz to the cluster, connected or not; Ctrl+P does not even prompt.
    @Test func clusterSpotsNeedAFrequency() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        model.entry.setFrequency("")
        model.entry.callChanged("dl1abc")
        model.entry.spotIt()
        #expect(model.status.message == Self.noFrequency)
        model.status.clear()
        model.entry.runShortcut(.spotWithComment)
        #expect(model.status.message == Self.noFrequency)
        #expect(model.dialogs.textPrompt == nil)
        #expect(spot.server.lines(0).isEmpty)
        // Alt+D without a call finds no spot near 0 Hz and just says so.
        model.entry.callChanged("")
        model.entry.runShortcut(.removeSpot)
        #expect(model.status.message == "Alt+D: na frekvenci ani v poli volačky není spot")
    }

    /// Store (Alt+O): the call of the field into the band map as my own spot; a blank call or a command is refused.
    @Test func storePutsTheCallIntoTheBandMap() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.setFrequency("14025")
        model.entry.runShortcut(.store)
        #expect(model.status.message == "Store: zadej volačku")
        model.entry.callChanged("14030")
        model.entry.runShortcut(.store)
        #expect(model.status.message == "Store: zadej volačku")
        #expect(model.dxCluster.spots.snapshot().isEmpty)
        model.entry.callChanged("ok1abc ")
        model.entry.storeCall()
        #expect(model.dxCluster.spots.snapshot() == [
            DxSpot(spotter: "OK1XOE", freqHz: 14_025_000, dxCall: "OK1ABC", comment: "self", selfSpotted: true),
        ])
        #expect(model.status.message == "ok1abc uloženo do bandmapy")
        // A stored call is never sent anywhere.
        #expect(spot.server.connectionCount == 0)
    }

    // MARK: - spots to the cluster

    @Test func spotItSendsOverTheMainConnection() async throws {
        let spot = try await Self.contestApp()
        let model: AppModel = spot.model
        // Not connected: nothing is sent.
        model.entry.setFrequency("14025.3")
        model.entry.callChanged("dl1xyz")
        model.entry.spotIt()
        #expect(model.status.message == "Spot: DX cluster není připojený (okno DX Cluster)")
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        model.entry.runShortcut(.spotIt)
        #expect(model.status.message == "Spot odeslán: DX 14025.3 DL1XYZ")
        await eventually("spot sent") { spot.server.lines(0) == ["DX 14025.3 DL1XYZ"] }
        // An empty field: the last logged QSO.
        model.entry.wipe()
        model.entry.spotIt()
        await eventually("last QSO sent") { spot.server.lines(0).last == "DX 14025.0 DL1ABC" }
        // A command in the field is not a call.
        model.entry.callChanged("7010")
        model.entry.spotIt()
        await eventually("last QSO again") { spot.server.lines(0).count == 3 }
        #expect(spot.server.lines(0).last == "DX 14025.0 DL1ABC")
    }

    @Test func spotItWithoutAnythingToSpot() async throws {
        let spot = try await SpotApp.make()
        spot.model.entry.spotIt()
        #expect(spot.model.status.message == "Spot: není co spotovat")
    }

    /// Ctrl+P: the prompt „Spot <call>" (not translated); OK sends the comment. Without a call, the hint.
    @Test func spotWithCommentPromptsAndSends() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.runShortcut(.spotWithComment)
        #expect(model.status.message == "Ctrl+P: zadej volačku ke spotu")
        #expect(model.dialogs.textPrompt == nil)
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        model.entry.setFrequency("14025")
        model.entry.callChanged("dl1abc ")
        model.entry.runShortcut(.spotWithComment)
        let prompt = try #require(model.dialogs.textPrompt)
        #expect(prompt.title == .verbatim("Spot dl1abc"))
        #expect(prompt.hint == ContestMessage("Komentář ke spotu"))
        #expect(spot.server.lines(0).isEmpty)
        model.dialogs.submitPrompt(" UP 2 ")
        await eventually("spot sent") { spot.server.lines(0) == ["DX 14025.0 DL1ABC UP 2"] }
    }

    /// SPOTME: my call at the field's frequency, `CQ` without a comment, and the self-spot warning.
    @Test func spotMeSendsMyCall() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.setFrequency("14025")
        await Self.enter(model, "SPOTME")
        #expect(model.status.message == "Spot: DX cluster není připojený (okno DX Cluster)")
        await spot.connectMain(spot.server.favorite(name: "Fake"))
        await Self.enter(model, "SPOTME")
        await eventually("spot sent") { spot.server.lines(0) == ["DX 14025.0 OK1XOE CQ"] }
        #expect(model.status.message
                == "Spot odeslán: DX 14025.0 OK1XOE CQ (self-spot — ověř, že ho propozice závodu povolují)")
        await Self.enter(model, "SPOTME RUN 599")
        await eventually("comment sent") { spot.server.lines(0).last == "DX 14025.0 OK1XOE RUN 599" }
        #expect(model.entry.form.call.isEmpty)
        #expect(model.logbook.rows.isEmpty)
    }

    static func enter(_ model: AppModel, _ text: String) async {
        model.entry.callChanged(text)
        model.entry.submit()
        await model.entry.settle()
    }

    // MARK: - beacons

    /// BEACONS asks for the file (the menu request); the beacons stay for the header's hours, a bad line is counted.
    @Test func beaconsLoadForTheirHours() async throws {
        let now = TestNow(Date(timeIntervalSince1970: 1_800_000_000))
        let spot = try await SpotApp.make(now: now)
        let model: AppModel = spot.model
        await Self.enter(model, "BEACONS")
        #expect(model.menu.pendingMenuAction == "beacons.load")
        #expect(MenuActions.performPending(app: model) == .openBeacons)

        let file: URL = spot.app.dataDir.appendingPathComponent("Beacons.txt")
        let text = "# Hours to stay in bandmap\n60\n# call;frequency;locator;comment\n"
            + "OZ7IGY/B;144471,1;JO55WM;\nGB3VHF/B;144430.4;JO01DH;QRG\nbroken line\n"
        try Data(text.utf8).write(to: file)
        model.spotNavigation.loadBeacons(url: file)
        await model.spotNavigation.settle()
        #expect(model.status.message == "BEACONS: 2 majáků v bandmapě na 60 h · 1 řádků nešlo přečíst")
        #expect(model.dxCluster.spots.snapshot().map(\.dxCall) == ["OZ7IGY/B", "GB3VHF/B"])
        #expect(model.dxCluster.spots.snapshot().map(\.spotter) == ["BEACONS", "BEACONS"])
        // An ordinary spot ages out after 90 minutes; the beacons stay for 60 hours.
        model.dxCluster.spots.add(Self.spot("W1AW", 14_030_000))
        now.advance(seconds: 59 * 3_600)
        #expect(model.dxCluster.spots.snapshot().map(\.dxCall) == ["OZ7IGY/B", "GB3VHF/B"])
        now.advance(seconds: 3_601)
        #expect(model.dxCluster.spots.snapshot().isEmpty)
    }

    @Test func anUnreadableBeaconFile() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.spotNavigation.loadBeacons(url: spot.app.dataDir.appendingPathComponent("missing.txt"))
        await model.spotNavigation.settle()
        #expect(model.status.message == "BEACONS: nelze číst missing.txt")
        #expect(model.dxCluster.spots.snapshot().isEmpty)
    }

    /// The DX Cluster window shortcut toggles the window once it exists; before that it is unavailable.
    @Test func dxClusterWindowShortcut() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.entry.runShortcut(.dxClusterWindow)
        if WindowsModel.implemented.contains("dxCluster") {
            #expect(model.windows.isOpen("dxCluster"))
            model.entry.runShortcut(.dxClusterWindow)
            #expect(!model.windows.isOpen("dxCluster"))
        } else {
            #expect(model.status.message == "Zatím nedostupné")
        }
    }
}
