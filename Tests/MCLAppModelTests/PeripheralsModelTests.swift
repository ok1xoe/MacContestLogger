import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The footswitch (`AS:636-665`, `EP:864-870`): opened by the configuration on the peripherals lane, PTT on the
/// active rig, F1 and Enter in the active entry window.
@MainActor @Suite struct PeripheralsModelTests {

    /// A blank port opens nothing; the pin falls back to CTS; a reload closes the old switch first.
    @Test func reloadFollowsTheConfiguration() async throws {
        let rigApp = try await RigApp.make()
        await rigApp.settle()
        #expect(rigApp.hardware.events.isEmpty)
        rigApp.model.config.config.footswitchPort = "/dev/fake-fs"
        rigApp.model.config.config.footswitchPin = "DSR"
        rigApp.model.peripherals.reloadFootswitch()
        rigApp.model.config.config.footswitchPin = "dsr"
        rigApp.model.peripherals.reloadFootswitch()
        rigApp.model.config.config.footswitchPort = " "
        rigApp.model.peripherals.reloadFootswitch()
        await rigApp.settle()
        #expect(rigApp.hardware.events == [
            "footswitch open /dev/fake-fs DSR", "footswitch close", "footswitch open /dev/fake-fs CTS",
            "footswitch close",
        ])
        #expect(!rigApp.hardware.footswitchOpen)
    }

    /// PTT holds the active rig's transmitter while pressed; the release reaches the rig that was keyed.
    @Test func pttKeysTheActiveRig() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.radioMode = "SO2R"
            config.rig = fakeRigConfig(fake1.port)
            config.rig2 = fakeRigConfig(fake2.port)
        }
        await rigApp.settle()
        await rigApp.connect(vfo: 0)
        rigApp.rig.toggle(vfo: 1)
        await eventually("rig 2") { rigApp.rig.cat2.state != nil }
        rigApp.hardware.press(true)
        await eventually("PTT on") { fake1.writes == ["T 1"] }
        // The active rig changes while the pedal is down: the release still goes to rig 1.
        rigApp.rig.activateVfo(1)
        rigApp.hardware.press(false)
        await eventually("PTT off") { fake1.writes == ["T 1", "T 0"] }
        rigApp.hardware.press(true)
        rigApp.hardware.press(false)
        await eventually("rig 2 keyed") { fake2.writes == ["T 1", "T 0"] }
        #expect(rigApp.model.peripherals.footswitchPresses == 0)
    }

    /// Two press edges with an SO2R switch between them (no release in between): the rig keyed first is released
    /// before the other one is keyed, so it never stays keyed; the final release goes to the rig keyed last.
    @Test func aSecondPressReleasesTheRigKeyedFirst() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.radioMode = "SO2R"
            config.rig = fakeRigConfig(fake1.port)
            config.rig2 = fakeRigConfig(fake2.port)
        }
        await rigApp.settle()
        await rigApp.connect(vfo: 0)
        rigApp.rig.toggle(vfo: 1)
        await eventually("rig 2") { rigApp.rig.cat2.state != nil }
        rigApp.hardware.press(true)
        await eventually("rig 1 keyed") { fake1.writes == ["T 1"] }
        rigApp.rig.activateVfo(1)
        rigApp.hardware.press(true)
        await eventually("rig 2 keyed") { fake2.writes == ["T 1"] }
        await rigApp.settle()
        #expect(fake1.writes == ["T 1", "T 0"])
        #expect(rigApp.rig.footswitchPttRig == 1)
        rigApp.hardware.press(false)
        await eventually("rig 2 released") { fake2.writes == ["T 1", "T 0"] }
        await rigApp.settle()
        #expect(fake1.writes == ["T 1", "T 0"])
        #expect(rigApp.rig.footswitchPttRig == nil)
    }

    /// A reload (Settings) with the pedal held releases the PTT before the switch closes; an action changed away from
    /// PTT while held still releases on the pedal's release.
    @Test func aHeldPttIsReleasedOnReloadAndAfterAnActionChange() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        await rigApp.connect()
        rigApp.hardware.press(true)
        await eventually("PTT on") { fake.writes == ["T 1"] }
        rigApp.model.peripherals.reloadFootswitch()
        await rigApp.settle()
        #expect(fake.writes == ["T 1", "T 0"])
        #expect(rigApp.hardware.events.suffix(2) == ["footswitch close", "footswitch open /dev/fake-fs CTS"])
        rigApp.hardware.press(true)
        await eventually("PTT on again") { fake.writes.count == 3 }
        rigApp.model.config.config.footswitchAction = "F1"
        rigApp.hardware.press(false)
        await eventually("released") { fake.writes == ["T 1", "T 0", "T 1", "T 0"] }
        #expect(rigApp.model.peripherals.footswitchPresses == 0)
    }

    /// A user-initiated disconnect of the keyed rig (the LED, „Reset interfaces", a rig scan, a reconnect) releases
    /// the footswitch PTT first: `T 0` reaches the rig before its connection closes.
    @Test func aHeldPttIsReleasedBeforeTheRigDisconnects() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.settle()
        let rig: MCLAppModel.RigModel = rigApp.rig
        // (name, the disconnect, whether the rig connects again afterwards)
        let disconnects: [(String, @MainActor () async -> Void, Bool)] = [
            ("LED", { rig.toggle(vfo: 0) }, false),
            ("reset", { rig.resetInterfaces() }, true),
            ("scan", { await rig.disconnectForScan(reason: "scan") }, false),
            ("reconnect", { rig.reconnect(disconnectFirst: true) }, true),
        ]
        var expected: [String] = []
        for (name, disconnect, reconnects) in disconnects {
            if !rig.cat1.connected {
                await rigApp.connect()
            }
            rigApp.hardware.press(true)
            expected.append("T 1")
            await eventually("PTT on (\(name))") { fake.writes == expected }
            await disconnect()
            await rigApp.settle()
            expected.append("T 0")
            #expect(fake.writes == expected, "\(name)")
            // The reconnect of a reset / reconnect runs on the session's own connect thread: wait until it ended, so
            // the pedal's release below meets a known connection state.
            if reconnects {
                await eventually("reconnected (\(name))") { rig.cat1.state != nil }
            }
            // The pedal's release afterwards goes to the active rig as Kotlin's would (nothing without a rig).
            rigApp.hardware.press(false)
            await rigApp.settle()
            if reconnects {
                expected.append("T 0")
            }
            await eventually("settled (\(name))") { fake.writes == expected }
        }
    }

    /// F1: the active window sends F1 (the keyer gets it); only the press counts.
    @Test func f1SendsTheFirstMessage() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "F1"
        }
        await rigApp.settle()
        rigApp.entry.setFrequency("14025")
        rigApp.entry.setMode(.cw)
        rigApp.hardware.press(true)
        await eventually("press") { rigApp.model.peripherals.footswitchPresses == 1 }
        rigApp.hardware.press(false)
        await runMainQueue()
        #expect(rigApp.model.peripherals.footswitchPresses == 1)
        #expect(rigApp.keyer.keys == [[0]])
    }

    /// ENTER: without ESM it logs the QSO.
    @Test func enterLogs() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "ENTER"
        }
        try await rigApp.app.startCqWwCw()
        await rigApp.settle()
        rigApp.entry.callChanged("DL1ABC")
        rigApp.entry.editContestField("zone", "14")
        rigApp.hardware.press(true)
        await eventually("press") { rigApp.model.peripherals.footswitchPresses == 1 }
        await rigApp.entry.settle()
        await rigApp.model.logbook.settleMutations()
        #expect(rigApp.model.logbook.rows.map(\.call) == ["DL1ABC"])
    }

    /// A switch that cannot be opened shows its message (the inert hardware's here).
    @Test func anOpenFailureIsShown() async throws {
        let app = try await TestApp.make { config, _ in
            config.footswitchPort = "/dev/cu.never-opened"
        }
        await app.model.peripherals.settle()
        await runMainQueue()
        #expect(app.model.status.message == "Hardware disabled (MCL_INERT_HARDWARE)")
    }
}
