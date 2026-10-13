import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The band map's top bar and programmable buttons (`BandmapModel+TopBar`): SH/DX, CQ, RIT, the mode, Wide/Narrow
/// and the buttons' states, macros, text commands, raw CAT and keys. Fake rig and network only; nothing transmits.
@MainActor @Suite struct BandmapTopBarTests {

    static func buttons(_ list: [(String, String)]) -> (inout AppConfig, FakeTelnetServer) -> Void {
        { config, _ in config.dxCluster.bandmapButtons = list.map { DxClusterCommand(label: $0.0, command: $0.1) } }
    }

    @Test func shDxNeedsTheCluster() async throws {
        let app = try await SpotApp.make()
        app.model.bandmap.showDx()
        #expect(app.model.status.message == "DX Cluster není připojen")
    }

    @Test func cqRitAndMode() async throws {
        let app = try await SpotApp.make()
        let model: AppModel = app.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        #expect(!bandmap.canJumpToCq)
        model.operating.onCqSent(14_030_000)
        model.operating.runMode = .searchAndPounce
        #expect(bandmap.canJumpToCq)
        model.rig.qsy(14_060_000)
        bandmap.jumpToCq()
        #expect(model.rig.tuning.tunedFreqHz == 14_030_000)
        #expect(model.operating.runMode == .run)
        #expect(bandmap.ritText == "RIT 0")
        model.entry.setMode(.cw)
        #expect(bandmap.modeText == "CW")
        model.entry.callChanged("OK1ABC")
        bandmap.setMode("USB")
        #expect(model.entry.form.mode == .ssb)
        #expect(model.entry.form.call == "OK1ABC")
        #expect(bandmap.filterIsNarrow == nil)
        bandmap.toggleFilterWidth()
        #expect(model.status.message == "Šířka filtru: připoj TRX (CAT)")
    }

    /// A button cycles through its `|` states; macros and text commands run without clearing the call, transmitting
    /// macros and unknown ones are refused, raw CAT without a rig says so.
    @Test func buttonsRunTheirStates() async throws {
        let app = try await SpotApp.make(configure: Self.buttons([
            ("Run|S&P", "{RUN} | {S&P}"), ("", "14100;CW"), ("Bad", "{F1}"), ("Cat", "{CAT T 1}"),
            ("Raw", "{CAT L AF 0.5}"), ("Text", "HELLO"),
        ]))
        let model: AppModel = app.model
        let bandmap: BandmapModel = model.bandmap
        model.rig.qsy(14_025_000)
        model.entry.callChanged("OK1ABC")
        model.operating.runMode = .searchAndPounce
        #expect(bandmap.buttonLabel(0) == "Run")
        bandmap.pressButton(0)
        #expect(model.operating.runMode == .run)
        #expect(bandmap.buttonLabel(0) == "S&P")
        bandmap.pressButton(0)
        #expect(model.operating.runMode == .searchAndPounce)
        #expect(bandmap.buttonLabel(0) == "Run")
        #expect(bandmap.buttonLabel(1) == "1")
        bandmap.pressButton(1)
        #expect(model.rig.tuning.tunedFreqHz == 14_100_000)
        #expect(model.entry.form.mode == .cw)
        #expect(model.entry.form.call == "OK1ABC")
        bandmap.pressButton(2)
        #expect(model.status.message == "{F1}: tlačítko bandmapy ho neprovede")
        bandmap.pressButton(3)
        #expect(model.status.message.hasPrefix("CAT T 1: command T is not allowed"))
        bandmap.pressButton(4)
        await eventually("raw CAT answered") { model.status.message.hasPrefix("CAT L AF 0.5:") }
        bandmap.pressButton(5)
        #expect(model.status.message == "„HELLO“ není příkaz")
        bandmap.pressButton(9)
    }

    @Test func keysPressTheButtons() async throws {
        let app = try await SpotApp.make(configure: Self.buttons([("Run", "{RUN}"), ("S&P", "{S&P}")]))
        let model: AppModel = app.model
        let bandmap: BandmapModel = model.bandmap
        let flags: UInt = AwtKeyCodes.macOptionFlag | AwtKeyCodes.macCommandFlag | AwtKeyCodes.macShiftFlag
        func key(_ code: UInt16, _ letter: String, _ flags: UInt, kind: MacKeyEvent.Kind = .keyDown) -> MacKeyEvent {
            MacKeyEvent(kind: kind, keyCode: code, characters: "", charactersIgnoringModifiers: letter,
                        modifierFlags: flags)
        }
        model.operating.runMode = .searchAndPounce
        #expect(bandmap.handleButtonKey(key(0x1D, "0", flags)))
        #expect(model.operating.runMode == .run)
        #expect(bandmap.handleButtonKey(key(0x1D, "0", flags, kind: .keyUp)))
        #expect(bandmap.handleButtonKey(key(0x12, "1", flags)))
        #expect(model.operating.runMode == .searchAndPounce)
        // No such button, or not all three modifiers: left alone.
        #expect(!bandmap.handleButtonKey(key(0x13, "2", flags)))
        #expect(!bandmap.handleButtonKey(key(0x1D, "0", AwtKeyCodes.macOptionFlag | AwtKeyCodes.macShiftFlag)))
    }

    @Test func theEditorSavesTheButtons() async throws {
        let app = try await SpotApp.make()
        let bandmap: BandmapModel = app.model.bandmap
        bandmap.editButtons(2)
        #expect(bandmap.editingButtons == 2)
        bandmap.saveButtons([DxClusterCommand(label: "A", command: "CW"), DxClusterCommand(label: " ", command: "")])
        #expect(bandmap.buttons == [DxClusterCommand(label: "A", command: "CW")])
        #expect(await app.app.savedConfigFlushed().dxCluster.bandmapButtons.count == 1)
        bandmap.openSpotFilter()
        #expect(bandmap.showSpotFilter)
    }

    /// Wide/Narrow switches the rig's passband through raw CAT (the fake answers 500 Hz in CW: wide → narrow).
    @Test func wideNarrowSendsThePassband() async throws {
        let fake = try FakeRigctld(mode: "CW")
        defer { fake.stop() }
        let keying = try await KeyingApp.make(configure: { config, _ in config.rig = fakeRigConfig(fake.port) })
        await keying.connectRig(fake)
        let bandmap: BandmapModel = keying.model.bandmap
        #expect(bandmap.filterIsNarrow == false)
        bandmap.toggleFilterWidth()
        await eventually("passband sent") { fake.commands.contains { $0.hasSuffix("M CW 250") } }
    }
}
