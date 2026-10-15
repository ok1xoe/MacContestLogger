import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The N1MM footswitch modes beyond PTT / ESM Enter / F1: F2–F4, F11, F12, Esc and the other entry window. The
/// footswitch is a scripted fake (no serial port); the rig is a fake `rigctld` on a loopback port.
@MainActor @Suite struct FootswitchActionsTests {

    private static func make(_ action: String, radioMode: String = "SO1V") async throws -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = radioMode
            config.rig = fakeRigConfig(fake.port)
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = action
            for set in [\CwKeyerConfig.runMessages, \CwKeyerConfig.spMessages] {
                var messages: [FunctionKeyMessage] = config.cwKeyer[keyPath: set]
                messages[10] = FunctionKeyMessage(label: "F11", text: "TEST")
                messages[11] = FunctionKeyMessage(label: "F12", text: "TEST")
                config.cwKeyer[keyPath: set] = messages
            }
        }
        await rigApp.connect()
        await rigApp.settle()
        rigApp.entry.setMode(.cw)
        return (rigApp, fake)
    }

    private static func tap(_ rigApp: RigApp) async {
        let before: Int = rigApp.model.peripherals.footswitchPresses
        rigApp.hardware.press(true)
        await eventually("press") { rigApp.model.peripherals.footswitchPresses == before + 1 }
        rigApp.hardware.press(false)
        await runMainQueue()
    }

    @Test(arguments: [("F2", 1), ("F3", 2), ("F4", 3), ("F11", 10), ("F12", 11)])
    func functionKeyActionsSendTheirKey(action: String, key: Int) async throws {
        let (rigApp, fake) = try await Self.make(action)
        await Self.tap(rigApp)
        #expect(rigApp.keyer.keys == [[key]])
        #expect(!fake.writes.contains("T 1"))
    }

    /// ESC stops sending: the CQ repeat goes off and the rig is not keyed.
    @Test func escStopsSending() async throws {
        let (rigApp, fake) = try await Self.make("ESC")
        rigApp.model.operating.applyCqRepeat(true)
        await Self.tap(rigApp)
        #expect(!rigApp.model.operating.cqRepeat)
        #expect(!fake.writes.contains("T 1"))
    }

    /// SWITCH_RADIOS asks for the other entry window in SO2V; in SO1V nothing happens.
    @Test func switchRadiosMovesToTheOtherWindow() async throws {
        let (so2v, _) = try await Self.make("SWITCH_RADIOS", radioMode: "SO2V")
        await Self.tap(so2v)
        #expect(so2v.rig.focusVfoRequest == 1)
        let (so1v, _) = try await Self.make("SWITCH_RADIOS")
        await Self.tap(so1v)
        #expect(so1v.rig.focusVfoRequest == nil)
        #expect(so1v.keyer.keys.isEmpty)
    }
}
