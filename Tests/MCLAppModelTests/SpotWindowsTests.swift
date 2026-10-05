import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The spot windows in the app (`App.kt:162-165, 314-330, 645-662`): their menu actions and Kotlin ids, the saved
/// `openWindows`, the wheel mapping of the Bandmap, the filter sheet's logic and the DX Cluster console's clearing.
/// The rig and the network are inert; nothing transmits.
@MainActor @Suite struct SpotWindowsTests {

    static let menuToWindow: [(menu: String, window: String)] = [
        ("window.availmult", "availMult"), ("window.dxcluster", "dxCluster"), ("window.bandmap", "bandmap"),
        ("window.blacklist", "blacklist"),
    ]

    /// Every menu item opens its window (Kotlin `showXxx = true`), the id is saved in `openWindows` in Kotlin's order
    /// (`availMult`, `dxCluster`, `bandmap`, `blacklist`), and a closed window leaves the list.
    @Test func menuItemsOpenTheWindows() async throws {
        let app = try await TestApp.make()
        // Opened in a different order than Kotlin saves them.
        for (menu, window) in Self.menuToWindow.reversed() {
            #expect(app.model.menu.isImplemented(menu), "\(menu)")
            #expect(WindowsModel.implemented.contains(window), "\(window)")
            #expect(MenuActions.perform(menu, app: app.model) == nil)
            #expect(app.model.windows.isOpen(window), "\(window)")
        }
        #expect(await app.savedConfigFlushed().openWindows == ["log", "availMult", "dxCluster", "bandmap", "blacklist"])
        app.model.windows.setOpen("dxCluster", false)
        #expect(await app.savedConfigFlushed().openWindows == ["log", "availMult", "bandmap", "blacklist"])
        #expect(WindowsModel.spotWindows.allSatisfy { WindowsModel.implemented.contains($0) })
    }

    /// The menu has the four items with their labels (the file's `menu.json` ids are lower case).
    @Test func theMenuIdsMapToTheKotlinWindowIds() {
        for (menu, window) in Self.menuToWindow {
            #expect(WindowsModel.menuWindows[menu] == window)
        }
        #expect(WindowsModel.menuWindows["window.catlog"] == "catLog")
        #expect(Set(WindowsModel.menuWindows.values).isSubset(of: WindowsModel.implemented))
    }

    /// The windows saved by the previous run reopen: the app opens every saved id it implements, and the other ids stay.
    @Test func savedWindowsAreRestored() async throws {
        let app = try await TestApp.make(configure: { config, _ in
            config.openWindows = ["log", "availMult", "dxCluster", "bandmap", "blacklist", "someLaterWindow"]
        })
        let reopened: [String] = app.model.windows.openIds.filter { WindowsModel.implemented.contains($0) }
        #expect(reopened == ["log", "availMult", "dxCluster", "bandmap", "blacklist"])
        #expect(app.model.windows.isOpen("someLaterWindow"))
    }

    /// The DX Cluster shortcut toggles the window (`EP:936`).
    @Test func theShortcutTogglesTheDxClusterWindow() async throws {
        let app = try await TestApp.make()
        app.model.entry.runShortcut(.dxClusterWindow)
        #expect(app.model.windows.isOpen("dxCluster"))
        app.model.entry.runShortcut(.dxClusterWindow)
        #expect(!app.model.windows.isOpen("dxCluster"))
    }

    // MARK: - the console

    /// „Vymazat": the log is empty and the console is redrawn (the log's listener does not fire on `clear`).
    @Test func clearingTheLogRedrawsTheConsole() async throws {
        let spot = try await SpotApp.make()
        let dx: DxClusterModel = spot.dx
        try dx.log.info("one")
        await runMainQueue()
        #expect(dx.log.snapshot().count == 1)
        let revision: Int = dx.logRevision
        dx.clearLog()
        #expect(dx.log.snapshot().isEmpty)
        #expect(dx.logRevision == revision + 1)
        try dx.log.info("two")
        await runMainQueue()
        #expect(dx.log.snapshot().count == 1)
        #expect(dx.logRevision == revision + 2)
    }

    /// The window selects the saved favourite when it opens, and the choice is saved as `lastFavorite`.
    @Test func theFavouriteIsChosenWhenTheWindowOpens() async throws {
        let spot = try await SpotApp.make(configure: { config, server in
            config.dxCluster.favorites = [
                DxClusterFavorite(name: "A", host: FakeTelnetServer.host, port: server.port, login: "", password: ""),
                DxClusterFavorite(name: "B", host: FakeTelnetServer.host, port: server.port, login: "", password: ""),
            ]
            config.dxCluster.lastFavorite = "B"
        })
        let dx: DxClusterModel = spot.dx
        dx.resetSelection()
        #expect(dx.selectedFavorite?.name == "B")
        dx.selectFavorite("A")
        #expect(dx.selectedFavorite?.name == "A")
        #expect(spot.model.config.config.dxCluster.lastFavorite == "A")
    }

    // MARK: - the Bandmap's wheel

    /// A notched wheel: one event, one step with its raw deltas; Compose's `dy` is the negated Cocoa delta, so rolling
    /// up (positive `scrollingDeltaY`) is `dy < 0` = the frequency goes up.
    @Test func aNotchedWheelMapsToComposeDeltas() {
        var wheel = BandmapWheel()
        let up = wheel.feed(deltaX: 0, deltaY: 1, precise: false, momentum: false)
        #expect(up.count == 1 && up[0].dy == -1 && up[0].dx == 0)
        // A big notch delta is still one step per event (Kotlin).
        let down = wheel.feed(deltaX: 0, deltaY: -30, precise: false, momentum: false)
        #expect(down.count == 1 && down[0].dy == 30)
        // Shift+wheel arrives horizontally (the core takes the dominant axis).
        let shifted = wheel.feed(deltaX: 2, deltaY: 0, precise: false, momentum: false)
        #expect(shifted.count == 1 && shifted[0].dx == -2 && shifted[0].dy == 0)
        // A zero event is no step (it would be read as „down").
        #expect(wheel.feed(deltaX: 0, deltaY: 0, precise: false, momentum: false).isEmpty)
    }

    /// A trackpad: the travel is summed, one step per 10 points with the remainder kept, so a fast swipe is several
    /// steps; momentum after the fingers lift is ignored.
    @Test func aTrackpadStepsPerTenPointsKeepingTheRemainder() {
        var wheel = BandmapWheel()
        #expect(wheel.feed(deltaX: 0, deltaY: 4, precise: true, momentum: false).isEmpty)
        #expect(wheel.feed(deltaX: 0, deltaY: 4, precise: true, momentum: false).isEmpty)
        let one = wheel.feed(deltaX: 0, deltaY: 4, precise: true, momentum: false)
        #expect(one.count == 1 && one[0].dy == -1 && one[0].dx == 0)
        // 2 points remain: 2 + 35 = 37 -> three steps, 7 remain.
        let fast = wheel.feed(deltaX: 0, deltaY: 35, precise: true, momentum: false)
        #expect(fast.count == 3 && fast.allSatisfy { $0.dy == -1 })
        let next = wheel.feed(deltaX: 0, deltaY: 3, precise: true, momentum: false)
        #expect(next.count == 1)
        // Down, and a momentum event is ignored without touching the sum.
        #expect(wheel.feed(deltaX: 0, deltaY: -25, precise: true, momentum: true).isEmpty)
        let down = wheel.feed(deltaX: 0, deltaY: -25, precise: true, momentum: false)
        #expect(down.count == 2 && down.allSatisfy { $0.dy == 1 })
        // Shift+trackpad moves on x.
        wheel.reset()
        let sideways = wheel.feed(deltaX: 21, deltaY: 0, precise: true, momentum: false)
        #expect(sideways.count == 2 && sideways.allSatisfy { $0.dx == -1 && $0.dy == 0 })
    }

    @Test func theConsoleDiffAppendsAndTrims() {
        // Nothing changed / unrelated / cleared.
        #expect(ConsoleDiff.plan(old: ["a", "b"], new: ["a", "b"]) == .none)
        #expect(ConsoleDiff.plan(old: [], new: []) == .none)
        #expect(ConsoleDiff.plan(old: ["a", "b"], new: []) == .rebuild)
        #expect(ConsoleDiff.plan(old: [], new: ["a"]) == .rebuild)
        #expect(ConsoleDiff.plan(old: ["a", "b"], new: ["x", "y"]) == .rebuild)
        // Appended lines.
        #expect(ConsoleDiff.plan(old: ["a", "b"], new: ["a", "b", "c", "d"]) == .update(deleteUTF16: 0, append: "\nc\nd"))
        // The cap dropped the head: "ab" + separator = 3 units, "č" counts UTF-16 units.
        #expect(ConsoleDiff.plan(old: ["ab", "č", "d"], new: ["č", "d", "e"]) == .update(deleteUTF16: 3, append: "\ne"))
        // Head dropped, nothing appended.
        #expect(ConsoleDiff.plan(old: ["a", "b"], new: ["b"]) == .update(deleteUTF16: 2, append: ""))
        // Repeated lines: the first cut that lines up wins and the result is still the new text.
        let old: [String] = ["x", "x", "y"]
        let new: [String] = ["x", "y", "z"]
        let plan = ConsoleDiff.plan(old: old, new: new)
        var text: String = old.joined(separator: "\n")
        if case .update(let deleted, let append) = plan {
            text = String(decoding: Array(text.utf16.dropFirst(deleted)), as: UTF16.self) + append
        } else {
            text = new.joined(separator: "\n")
        }
        #expect(text == new.joined(separator: "\n"))
    }

    /// The mapped delta drives the model: rolling up tunes up by the step, rolling down tunes down.
    @Test func theMappedWheelMovesTheFrequencyTheRightWay() async throws {
        let spot = try await SpotApp.make()
        let model: AppModel = spot.model
        model.rig.qsy(14_100_000)
        let step: Int64 = Int64(model.config.config.dxCluster.wheelStepHz)
        var wheel = BandmapWheel()
        let upSteps = wheel.feed(deltaX: 0, deltaY: 1, precise: false, momentum: false)
        let up = try #require(upSteps.first)
        model.bandmap.wheel(dx: up.dx, dy: up.dy, ctrl: false, shift: false)
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000 + step)
        let downSteps = wheel.feed(deltaX: 0, deltaY: -1, precise: false, momentum: false)
        let down = try #require(downSteps.first)
        model.bandmap.wheel(dx: down.dx, dy: down.dy, ctrl: false, shift: false)
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
        // Ctrl+wheel up zooms in.
        let span: Int64 = model.bandmap.viewport.spanHz
        model.bandmap.wheel(dx: up.dx, dy: up.dy, ctrl: true, shift: false)
        #expect(model.bandmap.viewport.spanHz == span / 2)
    }

    // MARK: - the filter sheet

    @Test func theFilterSheetKnowsTheContestsBandsAndModes() async throws {
        let spot = try await SpotApp.make()
        let avail: AvailMultModel = spot.model.availMult
        #expect(avail.supportedBands.isEmpty && avail.supportedModes.isEmpty)
        try await spot.app.startCqWwCw()
        #expect(avail.supportedModes == ["CW"])
        #expect(avail.supportedBands.contains(.m20) && !avail.supportedBands.contains(.m6))

        // The group button ticks the supported bands of the group, and unticks them when all are ticked.
        avail.setDefaults(bands: [], modes: [])
        let hf: AvailMultModel.BandGroup = AvailMultModel.bandGroups[0]
        avail.toggleGroup(hf)
        let supportedHF: Set<Band> = avail.supportedBands.intersection(hf.bands)
        #expect(avail.bands == supportedHF)
        avail.toggleGroup(hf)
        #expect(avail.bands.isEmpty)
        // A partly ticked group is completed.
        avail.setBand(.m20, ticked: true)
        avail.toggleGroup(hf)
        #expect(avail.bands == supportedHF)
        // A group without a supported band does nothing.
        avail.toggleGroup(AvailMultModel.bandGroups[3])
        #expect(avail.bands == supportedHF)
        // No microwave band is supported by this (HF) definition either.
        avail.setBand(.m20, ticked: false)
        #expect(!avail.bands.contains(.m20))
        avail.setMode("CW", ticked: true)
        avail.setMode("DIGI", ticked: true)
        avail.setMode("DIGI", ticked: false)
        #expect(avail.modes == ["CW"])
    }

    @Test func theFilterSheetLabelsAreKotlins() {
        #expect(AvailMultModel.bandGroups.map(\.title) == ["HF", "VHF", "UHF", "Mw"])
        #expect(AvailMultModel.bandGroups.flatMap(\.bands).count == Band.allCases.count)
        let labels: [String] = Band.allCases.map { AvailMultModel.bandLabel($0) }
        #expect(labels == ["1.8", "3.5", "5", "7", "10", "14", "18", "21", "24", "28", "50", "144", "430",
                           "1296", "2.3G", "3.4G", "5.7G", "10G"])
        #expect(AvailMultModel.bandGroups[1].extra == ["222"])
        #expect(AvailMultModel.bandGroups[2].extra == ["902"])
        #expect(AvailMultModel.bandGroups[3].extra == ["24G"])
        #expect(AvailMultModel.modeChoices.map(\.label) == ["CW", "Phone", "Digi"])
    }

    // MARK: - the band notes

    @Test func aBandNoteMarkIsTheRoundedFrequency() {
        var note = BandNote()
        note.freqKHz = 14_025.5
        #expect(BandNotes.markHz(note) == 14_025_500)
        note.freqKHz = 7_010.0004
        #expect(BandNotes.markHz(note) == 7_010_000)
        note.freqKHz = 0
        #expect(BandNotes.markHz(note) == nil)
    }
}
