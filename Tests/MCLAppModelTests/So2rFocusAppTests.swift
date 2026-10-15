import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM's separate entry (RX) and transmit focus in SO2R through the entry windows: `\`, Pause, Ctrl+←/→, an F-key
/// that brings the transmit focus, Ctrl+F1–F12 and Ctrl+Enter on the alternate radio, the radio swap times and
/// Alt+F5 / Alt+F6. Fake rigctld daemons on the loopback, a recording OTRSP controller and a recording keyer — nothing
/// real is opened or keyed.
@MainActor @Suite struct So2rFocusAppTests {

    private static func so2r(_ config: inout AppConfig) {
        config.radioMode = "SO2R"
        config.otrspPort = "/dev/fake-otrsp"
        config.esm.enabled = true
        for index in 0..<12 {
            config.cwKeyer.runMessages[index] = FunctionKeyMessage(label: "K", text: "F\(index + 1)")
            config.cwKeyer.spMessages[index] = FunctionKeyMessage(label: "K", text: "F\(index + 1)")
        }
    }

    private static func otrspCommands(_ app: RigApp) -> [String] {
        app.hardware.events.filter { $0.hasPrefix("otrsp ") && !$0.hasPrefix("otrsp open") }
    }

    private static func make(_ configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (RigApp, EntryModel) {
        let app = try await RigApp.make { config, _ in
            so2r(&config)
            configure(&config)
        }
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        await app.settle()
        return (app, second)
    }

    @Test func anFKeyBringsTheTransmitFocus() async throws {
        let (app, second) = try await Self.make()
        let rig: MCLAppModel.RigModel = app.rig
        app.entry.runShortcut(.switchRadio)
        #expect(rig.vfo.activeVfo == 1 && rig.vfo.txVfo == 0)
        second.handle(.functionKey(0, shift: false, ctrlShift: false))
        await app.settle()
        #expect(rig.vfo.txVfo == 1)
        #expect(app.keyer.keys == [[0]])
        #expect(Self.otrspCommands(app) == ["otrsp RX2", "otrsp TX2"])
        // The keyer keys the rig with the transmit focus.
        #expect(app.model.keyer.activeRigLane() === rig.lanes[1])
    }

    @Test func pauseJoinsOrSwapsBothFoci() async throws {
        let (app, second) = try await Self.make()
        let rig: MCLAppModel.RigModel = app.rig
        app.entry.runShortcut(.switchRadio)
        // Split foci: Pause brings the transmit focus to the entry focus.
        second.runShortcut(.focusSwap)
        #expect(rig.vfo.activeVfo == 1 && rig.vfo.txVfo == 1)
        // Both in rig 2's window: Pause moves both to rig 1.
        second.runShortcut(.focusSwap)
        #expect(rig.vfo.activeVfo == 0 && rig.vfo.txVfo == 0)
        #expect(rig.focusVfoRequest == 0)
        await app.settle()
        #expect(Self.otrspCommands(app) == ["otrsp RX2", "otrsp TX2", "otrsp RX2", "otrsp TX1", "otrsp RX1"])
    }

    @Test func ctrlArrowsMoveBothFoci() async throws {
        let (app, _) = try await Self.make()
        let rig: MCLAppModel.RigModel = app.rig
        app.entry.runShortcut(.digitalRight)
        #expect(rig.vfo.activeVfo == 1 && rig.vfo.txVfo == 1)
        // A CW contest does not open the Digital Interface.
        #expect(!app.model.windows.isOpen("digitalinterface2"))
        app.model.vfoB.entry.runShortcut(.digitalLeft)
        #expect(rig.vfo.activeVfo == 0 && rig.vfo.txVfo == 0)
    }

    @Test func ctrlFunctionKeySendsOnTheAlternateRadio() async throws {
        let (app, second) = try await Self.make()
        let rig: MCLAppModel.RigModel = app.rig
        app.entry.callChanged("DL1ABC")
        app.entry.handle(.alternateFunctionKey(0))
        await app.settle()
        // The entry focus stays here, the transmit focus is rig 2's and stays there afterwards.
        #expect(rig.vfo.activeVfo == 0)
        #expect(rig.vfo.txVfo == 1)
        #expect(app.keyer.keys == [[0]])
        #expect(Self.otrspCommands(app) == ["otrsp TX2"])
        #expect(second.form.call.isEmpty)
        // Ctrl+Enter: the other window's next ESM step (its CQ with an empty call), on its radio.
        app.entry.handle(.enter(ctrl: true, step: .esm))
        #expect(app.keyer.transmissions.count == 2)
        #expect(rig.vfo.activeVfo == 0 && rig.vfo.txVfo == 1)
        // A message from this window takes the transmit focus back.
        app.entry.handle(.functionKey(1, shift: false, ctrlShift: false))
        await app.settle()
        #expect(rig.vfo.txVfo == 0)
        #expect(Self.otrspCommands(app) == ["otrsp TX2", "otrsp TX1"])
    }

    @Test func swapTimesDelayTheNextKeying() async throws {
        let (app, _) = try await Self.make { config in
            var setup: So2rSetup = config.so2r
            setup.set(.swapLeadMs, millis: 40)
            setup.set(.swapTailMs, millis: 100)
            config.so2r = setup
        }
        let rig: MCLAppModel.RigModel = app.rig
        var keying: Set<Int> = [0]
        rig.operatorKeying = { keying.contains($0) }
        // Rig 1 transmits (an interrupted CQ): tail + lead.
        rig.claimTx(1)
        #expect(rig.takeTxSwapDelay() == 140)
        #expect(rig.takeTxSwapDelay() == 0)
        keying = []
        rig.claimTx(0)
        #expect(rig.takeTxSwapDelay() == 40)
        // No swap, no pause.
        rig.claimTx(0)
        #expect(rig.takeTxSwapDelay() == 0)
        let keyer: KeyerModel = app.model.keyer
        rig.claimTx(1)
        #expect(keyer.so2rKeying().delayMs == 40)
        #expect(keyer.so2rKeying().winkeyerPins == nil)
    }

    @Test func winkeyerSecondOutputFollowsTheTransmitFocus() async throws {
        let (app, _) = try await Self.make { config in
            config.cwKeyer.method = .winkeyer
            var setup: So2rSetup = config.so2r
            setup.set(.winkeyerSecondOutput, flag: true)
            config.so2r = setup
        }
        let keyer: KeyerModel = app.model.keyer
        #expect(keyer.so2rKeying().winkeyerPins == 0x07)
        app.rig.claimTx(1)
        #expect(keyer.so2rKeying().winkeyerPins == 0x0B)
    }

    @Test func altF5SwapsTheRadiosAndTheFocus() async throws {
        let fake1 = try FakeRigctld(freqHz: 14_025_000)
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        defer {
            fake1.stop()
            fake2.stop()
        }
        let (app, second) = try await Self.make { config in
            config.rig = fakeRigConfig(fake1.port, label: "Rig 1")
            config.rig2 = fakeRigConfig(fake2.port, label: "Rig 2")
        }
        let rig: MCLAppModel.RigModel = app.rig
        await app.connect(vfo: 0)
        rig.toggle(vfo: 1)
        await eventually("rig 2") { rig.cat2.state != nil }
        second.setFrequency("7010")
        app.entry.callChanged("DL1ABC")
        second.callChanged("W1AW")
        app.entry.runShortcut(.swapRadiosKeepFocus)
        await app.settle()
        #expect(fake1.writes.contains("F 7010000"))
        #expect(fake2.writes.contains("F 14025000"))
        #expect(app.entry.form.call == "W1AW")
        #expect(second.form.call == "DL1ABC")
        #expect(second.form.freqKHz == "14025.00")
        #expect(rig.vfo.activeVfo == 0)
        app.entry.runShortcut(.swapRadios)
        await app.settle()
        #expect(app.entry.form.call == "DL1ABC" && second.form.call == "W1AW")
        #expect(rig.vfo.activeVfo == 1)
        #expect(rig.vfo.txVfo == 0)
    }

    @Test func altF6NeedsTwoRadios() async throws {
        let app = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
        }
        app.model.vfoB.entry.isWindowShown = true
        app.entry.runShortcut(.swapRadiosKeepFocus)
        #expect(app.status.contains("SO2R"))
    }

    @Test func so2rMenuSavesTheOptions() async throws {
        let app = try await TestApp.make()
        let model: AppModel = app.model
        #expect(!MenuActions.isChecked("so2r.winkeyer2", app: model))
        #expect(MenuActions.perform("so2r.winkeyer2", app: model) == nil)
        #expect(MenuActions.isChecked("so2r.winkeyer2", app: model))
        #expect(model.config.config.so2rSetup == ["winkeyerSecondOutput": "true"])
        MenuActions.applySo2rMillis(.swapLeadMs, text: "25", config: model.config, status: model.status)
        #expect(model.config.config.so2r.millis(.swapLeadMs) == 25)
        MenuActions.applySo2rMillis(.swapTailMs, text: "5000", config: model.config, status: model.status)
        #expect(model.status.message == "Neplatný čas (0–2000 ms)")
        #expect(model.config.config.so2r.millis(.swapTailMs) == 0)
    }

    /// SO2R: the CQ repeat stays on the radio it was switched on in while the operator types on the other one.
    @Test func cqRepeatStaysOnTheRunRadio() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.radioMode = "SO2R"
            config.runMode.repeatSeconds = 0.2
        })
        let second: EntryModel = app.model.vfoB.entry
        second.isWindowShown = true
        for entry in [app.entry, second] {
            entry.setMode(.cw)
        }
        func sends() -> Int {
            (app.keying.lastKeyer?.events ?? []).filter { $0.hasPrefix("send ") }.count
        }
        app.entry.runShortcut(.cqRepeat)
        await runMainQueue()
        await app.settle()
        #expect(sends() == 1)
        app.entry.runShortcut(.switchRadio)
        second.callChanged("W1AW")
        await runMainQueue()
        #expect(app.model.rig.vfo.activeVfo == 1)
        for _ in 0..<40 where sends() < 2 {
            app.clock.advance(by: 1_000)
            await app.settle()
        }
        #expect(sends() >= 2)
        #expect(app.model.operating.cqRepeat)
        #expect(app.model.rig.vfo.txVfo == 0)
        #expect(second.form.call == "W1AW")
    }
}
