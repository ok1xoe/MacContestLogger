import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM keys for the rig: Alt+' (wide / narrow filter), Ctrl+Alt+R (CW reverse), Shift+PgUp/PgDn (the secondary CW
/// speed step) and the rotator keys' N1MM defaults. Fake rig and keyer only; nothing transmits.
@MainActor @Suite struct KeyboardRadioKeysTests {

    @Test func filterAndCwReverseGoThroughRawCat() async throws {
        let fake = try FakeRigctld(mode: "CW")
        defer { fake.stop() }
        let keying = try await KeyingApp.make(configure: { config, _ in config.rig = fakeRigConfig(fake.port) })
        await keying.connectRig(fake)
        keying.entry.runShortcut(.toggleFilter)
        await eventually("passband sent") { fake.commands.contains { $0.hasSuffix("M CW 250") } }
        keying.entry.runShortcut(.cwReverse)
        #expect(keying.model.status.message == "CW reverse zapnut")
        await eventually("CW reverse sent") { fake.commands.contains { $0.contains("M CWR ") } }
    }

    @Test func withoutARigTheyOnlySaySo() async throws {
        let app = try await SpotApp.make()
        app.model.entry.runShortcut(.cwReverse)
        #expect(app.model.status.message == "CW reverse: připoj TRX (CAT)")
        app.model.entry.runShortcut(.toggleFilter)
        #expect(app.model.status.message == "Šířka filtru: připoj TRX (CAT)")
    }

    @Test func secondaryCwSpeedStep() async throws {
        let app = try await KeyingApp.make(configure: { config, _ in
            winkeyerConfig(&config)
            config.cwSpeedStep = 3
            config.cwSpeedStepSecondary = 1
        })
        app.entry.setMode(.cw)
        app.entry.handle(.cwSpeedSecondary(1))
        #expect(app.keyer.cwSpeed == 29)
        app.entry.handle(.cwSpeed(1))
        #expect(app.keyer.cwSpeed == 32)
        app.entry.handle(.cwSpeedSecondary(-1))
        #expect(app.keyer.cwSpeed == 31)
    }

    /// N1MM: Alt+L long path, Ctrl+Alt+J stop, Ctrl+Alt+R CW reverse; RIT clear moved to Ctrl+Alt+Shift+R.
    @Test func defaultKeysFollowN1mm() throws {
        let keys = KeyBindings(nil)
        #expect(keys.resolve(try #require(KeyCombo.parse("Alt+L"))) == .rotorLong)
        #expect(keys.resolve(try #require(KeyCombo.parse("Ctrl+Alt+J"))) == .rotorStop)
        #expect(keys.resolve(try #require(KeyCombo.parse("Alt+J"))) == .rotorTurn)
        #expect(keys.resolve(try #require(KeyCombo.parse("Ctrl+Alt+R"))) == .cwReverse)
        #expect(keys.resolve(try #require(KeyCombo.parse("Ctrl+Alt+Shift+R"))) == .ritClear)
        #expect(keys.resolve(try #require(KeyCombo.parse("Alt+'"))) == .toggleFilter)
        for action in ShortcutAction.allCases {
            #expect(keys.conflicts(action).isEmpty, "\(action.name)")
        }
    }
}
