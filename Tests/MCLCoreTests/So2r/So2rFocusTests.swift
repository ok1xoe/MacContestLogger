import Foundation
import Testing
@testable import MCLCore

/// N1MM's two foci (SO2R): the entry (RX) focus and the transmit focus, the setup of the SO2R options, Winkeyer's
/// second key output and Ctrl+F1–F12 on the alternate radio. In-memory transports only.
@Suite struct So2rFocusTests {

    // MARK: - foci

    @Test func backslashMovesOnlyTheEntryFocusInSo2r() throws {
        var vfo = VfoState(radioMode: "SO2R")
        let toRig2Switch: VfoSwitch? = vfo.activate(1, tunedFreqHz: 14_025_000, rxOnly: true)
        let toRig2 = try #require(toRig2Switch)
        #expect(toRig2.hardware == .otrspRx(rig: 2, stereo: false))
        #expect(vfo.activeVfo == 1 && vfo.txVfo == 0 && vfo.fociSplit)
        #expect(vfo.activeCatIndex == 1 && vfo.txCatIndex == 0)
        // An F-key in rig 2's window moves the transmit focus there.
        let first: Bool = vfo.claimTx(1)
        let again: Bool = vfo.claimTx(1)
        #expect(first && !again)
        #expect(vfo.txVfo == 1 && !vfo.fociSplit)
    }

    @Test func bothFociMoveWithoutRxOnly() throws {
        var vfo = VfoState(radioMode: "SO2R")
        _ = vfo.activate(1, tunedFreqHz: 14_025_000, rxOnly: true)
        // Pause with split foci: the transmit focus joins the entry focus, nothing else changes.
        let joinSwitch: VfoSwitch? = vfo.activate(1, tunedFreqHz: 7_010_000)
        let join = try #require(joinSwitch)
        #expect(join.hardware == .otrspFocus(rig: 2, stereo: false))
        #expect(join.tunedFreqHz == nil)
        #expect(vfo.txVfo == 1 && vfo.activeVfo == 1)
        let none: VfoSwitch? = vfo.activate(1, tunedFreqHz: 7_010_000)
        #expect(none == nil)
        // Both foci back to rig 1 (Ctrl+←), with rig 1's remembered frequency.
        let backSwitch: VfoSwitch? = vfo.activate(0, tunedFreqHz: 7_010_000)
        let back = try #require(backSwitch)
        #expect(back.hardware == .otrspFocus(rig: 1, stereo: false))
        #expect(back.tunedFreqHz == 14_025_000)
        #expect(vfo.txVfo == 0 && vfo.activeVfo == 0)
    }

    @Test func oneRigKeepsTheFociTogether() throws {
        var vfo = VfoState(radioMode: "SO2V")
        let toBSwitch: VfoSwitch? = vfo.activate(1, tunedFreqHz: 14_025_000, rxOnly: true)
        let toB = try #require(toBSwitch)
        #expect(toB.hardware == .selectVfo(b: true))
        #expect(vfo.txVfo == 1)
        let claimed: Bool = vfo.claimTx(0)
        #expect(!claimed && vfo.txVfo == 1)
        var single = VfoState(radioMode: "SO1V")
        let singleClaimed: Bool = single.claimTx(1)
        #expect(!singleClaimed)
    }

    @Test func leavingSo2rJoinsTheFoci() {
        var vfo = VfoState(radioMode: "SO2R")
        _ = vfo.activate(1, tunedFreqHz: 14_025_000, rxOnly: true)
        #expect(vfo.fociSplit)
        _ = vfo.syncRadioMode("SO2V")
        #expect(vfo.txVfo == 1 && !vfo.fociSplit)
    }

    @Test func rxFocusStatus() {
        #expect(RigTexts.rxFocus(2, txRig: 1).czech == "Příjem: rig 2 (vysílá rig 1)")
        #expect(RigTexts.rxFocus(2, txRig: 2).czech == "Aktivní rig 2")
        #expect(RigTexts.txFocus(2).czech == "Vysílá rig 2")
    }

    // MARK: - setup

    @Test func setupKeepsOnlyNonDefaultValues() {
        var setup = So2rSetup(["swapLeadMs": "0", "duelingCqMs": "250", "unknown": "1", "ctrlFx": "true"])
        #expect(setup.values == ["duelingCqMs": "250"])
        #expect(setup.millis(.duelingCqMs) == 250)
        #expect(setup.flag(.ctrlFx) && setup.flag(.stereoMacros))
        #expect(!setup.flag(.focusOther))
        setup.set(.swapTailMs, millis: 99_999)
        #expect(setup.millis(.swapTailMs) == 2_000)
        setup.set(.ctrlFx, flag: false)
        setup.set(.duelingCqMs, millis: 100)
        #expect(setup.values == ["swapTailMs": "2000", "ctrlFx": "false"])
        #expect(So2rSetup(["swapLeadMs": "abc"]).millis(.swapLeadMs) == 0)
        #expect(So2rSetup.parseMillis(" 150 ") == 150)
        #expect(So2rSetup.parseMillis("-1") == nil)
        #expect(So2rSetup.parseMillis("3000") == nil)
    }

    @Test func setupIsStoredInTheConfig() throws {
        var config = AppConfig()
        var setup: So2rSetup = config.so2r
        setup.set(.swapLeadMs, millis: 30)
        config.so2r = setup
        let data: Data = try JSONEncoder().encode(config)
        let back: AppConfig = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(back.so2rSetup == ["swapLeadMs": "30"])
        #expect(back.so2r.millis(.swapLeadMs) == 30)
    }

    // MARK: - Winkeyer second output

    @Test func secondOutputSwapsTheKeyPin() {
        var options = CwKeyingOptions()
        #expect(options.winkeyerPinConfig == 0x07)
        #expect(options.winkeyerPinConfig(output: 1) == 0x07)
        #expect(options.winkeyerPinConfig(output: 2) == 0x0B)
        options.wkPtt = false
        options.wkHangTime = 2
        #expect(options.winkeyerPinConfig(output: 2) == 0x2A)
    }

    @Test func winkeyerWritesThePinConfiguration() throws {
        let pipe = PipeTransport()
        let keyer = WinkeyerKeyer(transport: pipe)
        defer {
            keyer.close()
            pipe.finish()
        }
        pipe.feed([31])
        #expect(try keyer.hostOpen(timeoutMs: 30_000) == 31)
        pipe.resetSent()
        try keyer.setPinConfig(0x0B)
        #expect(pipe.sent == [0x09, 0x0B])
    }

    // MARK: - keys

    @Test func ctrlFunctionKeysGoToTheAlternateRadio() {
        let ctrl: Int32 = AwtKeyCodes.ctrlDownMask
        let f1: Int32 = AwtKeyCodes.vkF1
        let press = AwtKeyStroke(vk: f1 + 2, location: 1, modifiers: ctrl, phase: .pressed)
        let one = EntryKeyContext(bindings: KeyBindings(nil))
        #expect(EntryKeyRouter.route(press, context: one) == .functionKey(2, shift: false, ctrlShift: false))
        let two = EntryKeyContext(bindings: KeyBindings(nil), twoRadios: true)
        #expect(EntryKeyRouter.route(press, context: two) == .alternateFunctionKey(2))
        // Ctrl+Shift+F3 still records.
        let record = AwtKeyStroke(vk: f1 + 2, location: 1, modifiers: ctrl | AwtKeyCodes.shiftDownMask,
                                  phase: .pressed)
        #expect(EntryKeyRouter.route(record, context: two) == .functionKey(2, shift: true, ctrlShift: true))
        // Ctrl+Enter keeps its flag for the alternate ESM.
        let esm = EntryKeyContext(bindings: KeyBindings(nil), esmActive: true, twoRadios: true)
        let enter = AwtKeyStroke(vk: AwtKeyCodes.vkEnter, location: 1, modifiers: ctrl, phase: .released)
        #expect(EntryKeyRouter.route(enter, context: esm) == .enter(ctrl: true, step: .esm))
    }

    @Test func pauseIsF15AndTheSwapsAltF5F6() {
        #expect(ShortcutAction.focusSwap.defaultCombo().format() == "F15")
        #expect(ShortcutAction.swapRadios.defaultCombo().format() == "Alt+F5")
        #expect(ShortcutAction.swapRadiosKeepFocus.defaultCombo().format() == "Alt+F6")
        #expect(EntryActionAvailability.area(of: .focusSwap) == .radio)
    }
}
