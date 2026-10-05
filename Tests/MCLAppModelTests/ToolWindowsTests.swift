import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The info and tool windows in the app (`App.kt:162-193, 645-677`): what the menu opens and with which
/// ids, what is saved and restored, the two modes of the world map, the goal windows following the Info window's flags,
/// the models closing with their windows, and the simulator window's start text. The views are thin; what they read is
/// tested here. Nothing is keyed or sent.
@MainActor @Suite struct ToolWindowsTests {

    // MARK: - menu actions and the saved ids

    /// The items open the Kotlin ids; the ones Kotlin never saves (`simulator`, the goal windows) stay out of the
    /// config; the saved list keeps Kotlin's order with the `mult:` windows last.
    @Test func menuItemsOpenTheKotlinIdsAndOnlyThePersistedOnesAreSaved() async throws {
        let tool = try await ToolApp.make()
        let model: AppModel = tool.model
        for id in ["mult.cq", "window.simulator", "window.statistics", "mult.map", "window.rate", "mult.dxcc",
                   "window.qtc"] {
            #expect(MenuActions.perform(id, app: model) == nil, "\(id)")
        }
        #expect(model.windows.isOpen("simulator"))
        let saved: [String] = await tool.app.savedConfigFlushed().openWindows
        #expect(saved == ["log", "rate", "statistics", "qtc", "worldmap", "mult:cq", "mult:dxcc"])
        // The status never says a window is unavailable.
        #expect(model.status.message != EntryTexts.unavailable)
        model.windows.setOpen("mult:cq", false)
        model.windows.setOpen("simulator", false)
        #expect(await tool.app.savedConfigFlushed().openWindows == ["log", "rate", "statistics", "qtc", "worldmap",
                                                                    "mult:dxcc"])
    }

    /// The windows of the previous run reopen from the saved ids: the app opens every implemented one (the goal windows
    /// and the simulator are never reopened), and the DXCC map remembers its mode.
    @Test func theSavedWindowsAreRestored() async throws {
        let tool = try await ToolApp.make(configure: { config, _ in
            config.openWindows = ["log", "rate", "mult:dxcc", "worldmap-dxcc", "goals", "mult:other", "mult:nothing"]
        })
        let reopened: Set<String> = Set(tool.model.windows.openIds.filter {
            WindowsModel.implemented.contains($0) && !WindowsModel.notPersisted.contains($0)
        })
        #expect(reopened == ["log", "rate", "worldmap-dxcc", "mult:dxcc", "mult:other"])
        // An id the app does not know is kept for the JVM version that shares the file.
        #expect(tool.model.windows.isOpen("mult:nothing"))
        #expect(tool.model.worldMap.startDxcc)
    }

    // MARK: - the world map

    /// `mult.map` opens the squares, `window.dxccmap` the DXCC dots (`worldMapStartDxcc`): the saved id follows the mode,
    /// the two ids never stay together, and the model opens in the mode asked for.
    @Test func theMapOpensInTheModeOfItsMenuItem() async throws {
        let tool = try await ToolApp.make()
        try await tool.start("cq-ww-cw")
        let model: AppModel = tool.model
        let map: WorldMapWindowModel = model.worldMap

        #expect(MenuActions.perform("mult.map", app: model) == nil)
        #expect(!map.startDxcc)
        #expect(model.windows.isOpen("worldmap") && !model.windows.isOpen("worldmap-dxcc"))
        map.open()
        #expect(!map.dxccMode)
        #expect(!map.needsContest)
        map.close()

        #expect(MenuActions.perform("window.dxccmap", app: model) == nil)
        #expect(map.startDxcc)
        #expect(model.windows.isOpen("worldmap-dxcc") && !model.windows.isOpen("worldmap"))
        #expect(await tool.app.savedConfigFlushed().openWindows == ["log", "worldmap-dxcc"])
        map.open()
        #expect(map.dxccMode)
        map.close()

        // The window's own close (the user) removes whichever id is open, with one save.
        model.windows.setWorldMapOpen(false)
        #expect(!model.windows.isWorldMapOpen)
        #expect(await tool.app.savedConfigFlushed().openWindows == ["log"])
        await tool.tools.settle()
    }

    /// Without a contest the map starts in the DXCC mode whichever item opened it, and the squares say why they are
    /// empty.
    @Test func theSquaresNeedAContest() async throws {
        let tool = try await ToolApp.make()
        let map: WorldMapWindowModel = tool.model.worldMap
        _ = MenuActions.perform("mult.map", app: tool.model)
        map.open()
        #expect(map.dxccMode)
        map.dxccMode = false
        #expect(map.needsContest)
        #expect(map.noContestText == "Čtverce jsou násobiče gridového závodu — žádný aktivní závod.")
        map.close()
        await tool.tools.settle()
    }

    /// A map without outlines (no `dxcc.geojson`) is empty and nothing fails: the scene is drawn from empty values.
    @Test func aMapWithoutOutlinesIsEmpty() async throws {
        let tool = try await ToolApp.make()
        let map: WorldMapWindowModel = tool.model.worldMap
        map.open()
        await tool.tools.settle()
        #expect(map.geoLoaded)
        #expect(map.geo.rings.isEmpty)
        map.setCanvas(width: 400, height: 200)
        await tool.tools.settle()
        #expect(map.dots.isEmpty)
        map.close()
    }

    // MARK: - the goal windows

    /// The Info menu's „Upravit cíle…" and „Cíle z dřívějšího deníku…" open their windows through the model's flags; the
    /// flags and the ids stay in step both ways, and neither is saved.
    @Test func theGoalWindowsFollowTheInfoFlags() async throws {
        let tool = try await ToolApp.make()
        let model: AppModel = tool.model
        model.info.perform(.editGoals)
        #expect(model.windows.isOpen("goals"))
        model.info.perform(.goalsFromLog)
        #expect(model.windows.isOpen("goals-from-log"))
        #expect(await tool.app.savedConfigFlushed().openWindows == ["log"])
        // The window closes itself after a save or an import: the flag goes false and the id leaves.
        model.info.showGoalEditor = false
        model.info.showGoalFromLog = false
        #expect(!model.windows.isOpen("goals"))
        #expect(!model.windows.isOpen("goals-from-log"))
    }

    // MARK: - the models close with their windows

    /// Every window model that holds a subscription or a timer lets it go on `close()`; the spot feed has the
    /// observers of the map and the multiplier windows only while they are open, and the Info tick stops.
    @Test func closingTheWindowsReleasesTheSubscriptionsAndTicks() async throws {
        let tool = try await ToolApp.make()
        let model: AppModel = tool.model
        let feed: SpotFeed = model.spotFeed
        let baseline: Int = feed.observerCount
        model.worldMap.open()
        for kind in MultGridLayout.kinds {
            model.multGrid(kind: kind).open()
        }
        #expect(feed.observerCount == baseline + 1 + MultGridLayout.kinds.count)
        model.info.open()
        model.statistics.open()
        model.scoreWindow.open()
        model.dupesheet.open()
        #expect(model.info.isOpen && model.statistics.isOpen && model.scoreWindow.isOpen && model.dupesheet.isOpen)
        let before: JavaInstant = model.info.now
        tool.now.advance(seconds: 5)
        tool.clock.advance(by: 1_000)
        #expect(model.info.now != before)

        model.worldMap.close()
        for kind in MultGridLayout.kinds {
            model.multGrid(kind: kind).close()
        }
        model.info.close()
        model.statistics.close()
        model.scoreWindow.close()
        model.dupesheet.close()
        #expect(feed.observerCount == baseline)
        let stopped: JavaInstant = model.info.now
        tool.now.advance(seconds: 5)
        tool.clock.advance(by: 1_000)
        #expect(model.info.now == stopped)
        await tool.tools.settle()
    }

    /// The quit closes every window model too (a window that is open when the app ends).
    @Test func theQuitClosesTheWindowModels() async throws {
        let tool = try await ToolApp.make()
        let model: AppModel = tool.model
        let baseline: Int = model.spotFeed.observerCount
        model.worldMap.open()
        model.multGrid(kind: "dxcc").open()
        model.info.open()
        tool.tools.shutdown()
        #expect(!model.info.isOpen && !model.worldMap.isOpen && !model.multGrid(kind: "dxcc").isOpen)
        #expect(model.spotFeed.observerCount == baseline)
    }

    // MARK: - the multiplier windows

    /// One model per kind (the window's `mult-<kind>` geometry id is the view's), made once.
    @Test func eachKindHasItsOwnModel() async throws {
        let tool = try await ToolApp.make()
        let model: AppModel = tool.model
        #expect(MultGridLayout.kinds.count == 7)
        let first: MultGridModel = model.multGrid(kind: "grid")
        #expect(first === model.multGrid(kind: "grid"))
        #expect(first !== model.multGrid(kind: "dxcc"))
        #expect(first.title == "Velké čtverce")
        #expect(!first.contestActive)
        #expect(first.noContestText == "Žádný aktivní závod.")
    }

    // MARK: - the simulator window

    /// The window shows the start text of the model: the refusal while an outward service is live (nothing starts), the
    /// running hint after a start, nothing after a stop. It starts nothing itself.
    @Test func theSimulatorWindowShowsTheStartText() async throws {
        let app = try await TestApp.make()
        let simulator: SimulatorModel = app.model.simulator
        #expect(simulator.startNotice == nil)

        simulator.liveOutwardService = { "cluster" }
        simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await simulator.settle()
        #expect(!simulator.isOn && !simulator.isStarting)
        #expect(simulator.startNotice == "Simulátor: nejdřív vypni cluster, nebo použij zkušební závod")
        #expect(app.model.status.message == simulator.startNotice)

        simulator.liveOutwardService = { nil }
        simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await simulator.settle()
        #expect(simulator.isOn)
        #expect(simulator.startNotice == app.model.status.message)
        #expect(simulator.startNotice?.hasPrefix("Simulátor běží") == true)

        // The window's close stops the session and clears the text.
        simulator.windowClosed()
        #expect(!simulator.isOn)
        #expect(simulator.startNotice == nil)
    }

    /// Closing the window id (what the user's close does) stops a running session, with no help from the view.
    @Test func closingTheSimulatorWindowStopsTheSession() async throws {
        let app = try await TestApp.make()
        let simulator: SimulatorModel = app.model.simulator
        #expect(MenuActions.perform("window.simulator", app: app.model) == nil)
        simulator.start(settings: SimulatorModelTests.settings, noise: 0.15)
        await simulator.settle()
        #expect(simulator.isOn)
        #expect(simulator.keyingRefusal != nil)
        app.model.windows.setOpen("simulator", false)
        #expect(!simulator.isOn)
        #expect(simulator.keyingRefusal == nil)
        #expect(simulator.startNotice == nil)
    }

    /// The form's values reach the model unchanged: the digits filter, the defaults of an empty field.
    @Test func theSimulatorFormMakesTheSettingsKotlinDoes() {
        #expect(SimulatorSession.digits("2a2", limit: 2) == "22")
        let defaults = SimulatorSession.settings(activity: 3, minWpm: "", maxWpm: "", spread: "")
        #expect(defaults == PileupSimulator.Settings(activity: 3, minWpm: 22, maxWpm: 22, pitchSpreadHz: 300))
        let given = SimulatorSession.settings(activity: 6, minWpm: "18", maxWpm: "30", spread: "450")
        #expect(given == PileupSimulator.Settings(activity: 6, minWpm: 18, maxWpm: 30, pitchSpreadHz: 450))
    }
}
