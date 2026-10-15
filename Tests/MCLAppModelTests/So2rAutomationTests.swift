import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM's SO2R automation: Dueling CQs (Ctrl+B) over the keyer clock, FocusOther, the `{CTRLFx}` and stereo / OTRSP
/// macro switches and the SO2V option „Repeating CQ Ends With VFOB Window Entry". Fake Winkeyer, recording OTRSP;
/// nothing real is keyed.
@MainActor @Suite struct So2rAutomationTests {

    private static func make(_ configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (KeyingApp, EntryModel) {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2R"
            configure(&config)
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        app.entry.setFrequency("14025")
        second.setFrequency("7010")
        return (app, second)
    }

    private static func sends(_ app: KeyingApp) -> Int {
        (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }.count
    }

    /// Advances the keyer clock in steps until `condition` holds (or a minute of program time has passed).
    private static func advance(_ app: KeyingApp, until condition: () -> Bool) async {
        for _ in 0..<600 where !condition() {
            app.clock.advance(by: 100)
            await app.settle()
        }
    }

    @Test func duelingCqsAlternateBetweenTheRadios() async throws {
        let (app, _) = try await Self.make()
        let rig: MCLAppModel.RigModel = app.model.rig
        app.entry.runShortcut(.duelingCq)
        await app.settle()
        #expect(app.model.operating.duelingCq)
        #expect(app.model.operating.runMode == .run)
        #expect(Self.sends(app) == 1)
        #expect(rig.vfo.txVfo == 0)
        await Self.advance(app) { Self.sends(app) >= 2 }
        #expect(Self.sends(app) == 2)
        #expect(rig.vfo.txVfo == 1)
        // The entry focus stayed where it was.
        #expect(rig.vfo.activeVfo == 0)
        await Self.advance(app) { Self.sends(app) >= 3 }
        #expect(rig.vfo.txVfo == 0)
        // Esc ends it.
        #expect(app.entry.stopSending())
        #expect(!app.model.operating.duelingCq)
        let count: Int = Self.sends(app)
        for _ in 0..<50 {
            app.clock.advance(by: 100)
        }
        await app.settle()
        #expect(Self.sends(app) == count)
    }

    @Test func aTypedCallPausesAQsyEndsIt() async throws {
        let (app, second) = try await Self.make()
        app.entry.runShortcut(.duelingCq)
        await app.settle()
        second.callChanged("W1AW")
        for _ in 0..<100 {
            app.clock.advance(by: 100)
            await app.settle()
        }
        #expect(Self.sends(app) == 1)
        #expect(app.model.operating.duelingCq)
        second.callChanged("")
        await Self.advance(app) { Self.sends(app) >= 2 }
        #expect(Self.sends(app) == 2)
        app.entry.setFrequency("14026")
        await Self.advance(app) { !app.model.operating.duelingCq }
        #expect(!app.model.operating.duelingCq)
        #expect(app.status.contains("Dueling CQ vypnuto"))
    }

    @Test func duelingNeedsTwoRadios() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
        })
        app.entry.runShortcut(.duelingCq)
        #expect(!app.model.operating.duelingCq)
        #expect(app.status.contains("SO2R"))
        await app.settle()
        #expect(Self.sends(app) == 0)
    }

    @Test func focusOtherMovesTheEntryFocusWhileTheRunRadioSends() async throws {
        let (app, second) = try await Self.make { config in
            var setup: So2rSetup = config.so2r
            setup.set(.focusOther, flag: true)
            config.so2r = setup
        }
        let rig: MCLAppModel.RigModel = app.model.rig
        // A CQ from rig 1: rig 1 is the run radio, the focus goes to rig 2 while it is sent.
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        await runMainQueue()
        #expect(rig.vfo.activeVfo == 1)
        #expect(rig.vfo.txVfo == 0)
        await Self.advance(app) { !app.keyer.isSending }
        await runMainQueue()
        #expect(rig.vfo.activeVfo == 0)
        // An unworked call typed on the S&P radio keeps the focus there.
        app.entry.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        await runMainQueue()
        #expect(rig.vfo.activeVfo == 1)
        second.callChanged("W1AW")
        await Self.advance(app) { !app.keyer.isSending }
        await runMainQueue()
        #expect(rig.vfo.activeVfo == 1)
        // Ctrl+Shift+K switches it off.
        second.runShortcut(.focusOther)
        #expect(!app.model.config.config.so2r.flag(.focusOther))
    }

    @Test func macroSwitches() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
            config.cwKeyer.runMessages[9] = FunctionKeyMessage(label: "K", text: "{CTRLF2}")
            config.cwKeyer.spMessages[9] = FunctionKeyMessage(label: "K", text: "{CTRLF2}")
            config.cwKeyer.runMessages[10] = FunctionKeyMessage(label: "K", text: "{STEREOON}{OTRSPOTHER RX}")
            config.cwKeyer.spMessages[10] = FunctionKeyMessage(label: "K", text: "{STEREOON}{OTRSPOTHER RX}")
        }
        let second: EntryModel = rigApp.model.vfoB.entry
        second.isWindowShown = true
        rigApp.entry.setMode(.cw)
        second.setMode(.cw)
        await rigApp.settle()
        rigApp.entry.runShortcut(.toggleCtrlFx)
        rigApp.entry.runShortcut(.toggleStereoMacros)
        #expect(rigApp.model.config.config.so2rSetup == ["ctrlFx": "false", "stereoMacros": "false"])
        rigApp.entry.handle(.functionKey(9, shift: false, ctrlShift: false))
        rigApp.entry.handle(.functionKey(10, shift: false, ctrlShift: false))
        await rigApp.settle()
        #expect(rigApp.keyer.transmissions.isEmpty)
        #expect(!rigApp.model.rig.vfo.stereo)
        #expect(rigApp.hardware.events == ["otrsp open /dev/fake-otrsp"])
        rigApp.entry.runShortcut(.toggleCtrlFx)
        rigApp.entry.handle(.functionKey(9, shift: false, ctrlShift: false))
        await rigApp.settle()
        #expect(rigApp.keyer.keys == [[1]])
    }

    @Test func so2vRepeatEndsWithVfoBEntry() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2V"
            var setup: So2rSetup = config.so2r
            setup.set(.so2vRepeatEndsWithVfoB, flag: true)
            config.so2r = setup
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        app.model.operating.setCqRepeat(true)
        second.callChanged("W1AW")
        #expect(!app.model.operating.cqRepeat)
        app.model.operating.setCqRepeat(true)
        app.entry.callChanged("DL1ABC")
        #expect(app.model.operating.cqRepeat)
    }

    @Test func so2rMenuToggles() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        for id in ["so2r.focusOtherAlways", "so2r.ctrlFx", "so2r.stereoMacros", "so2r.so2vRepeat"] {
            let before: Bool = MenuActions.isChecked(id, app: model)
            #expect(MenuActions.perform(id, app: model) == nil)
            #expect(MenuActions.isChecked(id, app: model) != before, "\(id)")
        }
        #expect(MenuActions.perform("so2r.dueling", app: model) == nil)
        #expect(!MenuActions.isChecked("so2r.dueling", app: model))
        MenuActions.applySo2rMillis(.duelingCqMs, text: "300", config: model.config, status: model.status)
        #expect(model.config.config.so2r.millis(.duelingCqMs) == 300)
    }
}
