import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// N1MM Ctrl+S (split on, then listening RX ↔ TX), Alt+S (RX back to TX) and „Reset RX freq when running split".
@MainActor @Suite struct SplitKeysTests {

    private func splitApp(_ configure: @escaping (inout AppConfig) -> Void = { _ in }) async throws
        -> (RigApp, FakeRigctld) {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        fake.setSplit(true, txHz: 14_030_000)
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
            configure(&config)
        }
        await rigApp.connect()
        #expect(rigApp.rig.activeState?.split == true)
        return (rigApp, fake)
    }

    @Test func ctrlSListensOnTheTransmitFrequencyAndBack() async throws {
        let (rigApp, fake) = try await splitApp()
        rigApp.entry.runShortcut(.splitOn)
        await rigApp.settle()
        #expect(rigApp.status == "Split: poslech na TX 14030.0 kHz")
        rigApp.entry.runShortcut(.splitOn)
        await rigApp.settle()
        #expect(rigApp.status == "Split: poslech na RX 14025.0 kHz")
        #expect(fake.writes == ["F 14030000", "F 14025000"])
    }

    @Test func altSPutsTheReceiverOnTheTransmitFrequency() async throws {
        let (rigApp, fake) = try await splitApp()
        #expect(ShortcutAction.resetRx.defaultKeys == "Alt+S")
        #expect(EntryActionAvailability.area(of: .resetRx) == .radio)
        rigApp.entry.runShortcut(.resetRx)
        await rigApp.settle()
        #expect(rigApp.status == "Split: RX na TX 14030.0 kHz")
        #expect(fake.writes == ["F 14030000"])
    }

    @Test func altSWithoutSplitSaysSo() async throws {
        let (rigApp, fake) = try await RigTuningTests.connected()
        rigApp.entry.runShortcut(.resetRx)
        await rigApp.settle()
        #expect(rigApp.status == "Split není zapnutý")
        #expect(fake.writes.isEmpty)
    }

    @Test func aRunQsoResetsTheReceiverOnlyWithTheOption() async throws {
        let (off, offFake) = try await splitApp()
        off.model.operating.runMode = .run
        try await RigVfoTests.logAQso(off)
        #expect(!offFake.writes.contains("F 14030000"))
        let (on, onFake) = try await splitApp { $0.resetRxAfterRunQso = true }
        on.model.operating.runMode = .run
        try await RigVfoTests.logAQso(on)
        #expect(onFake.writes.contains("F 14030000"))
    }
}
