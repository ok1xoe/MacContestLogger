import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The sub receiver (N1MM Alt+F12 dual watch, Ctrl+Alt+D in SO2V) over a fake rigctld on the loopback, and the rotor
/// of the radio with the entry focus (SO2R). Nothing transmits.
@MainActor @Suite struct So2rRadiosTests {

    private static func dualWatch(_ fake: FakeRigctld) -> [String] {
        fake.commands.filter { $0.contains("DUAL_WATCH") }
    }

    @Test func altF12TogglesTheSubReceiverOnARigThatHasOne() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let rigApp = try await RigApp.make { config, _ in
            var rig: RigConfig = fakeRigConfig(fake.port)
            rig.subReceiverOn = true
            config.rig = rig
        }
        await rigApp.connect()
        await rigApp.settle()
        #expect(Self.dualWatch(fake).count == 1)
        #expect(rigApp.rig.subReceiverOn)
        rigApp.entry.runShortcut(.copyToVfoB)
        await rigApp.settle()
        #expect(!rigApp.rig.subReceiverOn)
        #expect(Self.dualWatch(fake).last?.hasSuffix("DUAL_WATCH 0") == true)
        #expect(rigApp.status == "Druhý přijímač vypnut")
        rigApp.entry.runShortcut(.copyToVfoB)
        await rigApp.settle()
        #expect(Self.dualWatch(fake).last?.hasSuffix("DUAL_WATCH 1") == true)
        #expect(!fake.commands.contains { $0.hasPrefix("T ") })
    }

    @Test func altF12CopiesToVfoBOtherwise() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.connect()
        rigApp.entry.runShortcut(.copyToVfoB)
        await rigApp.settle()
        #expect(Self.dualWatch(fake).isEmpty)
        #expect(rigApp.status.hasPrefix("VFO B"))
    }

    @Test func ctrlAltDCallsCqOnVfoAWithTheSubReceiver() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000)
        defer { fake.stop() }
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2V"
            config.rig = fakeRigConfig(fake.port)
        }
        rigApp.model.vfoB.entry.isWindowShown = true
        await rigApp.connect()
        rigApp.rig.activateVfo(1)
        await rigApp.settle()
        rigApp.model.vfoB.entry.runShortcut(.so2vDualCq)
        await rigApp.settle()
        #expect(rigApp.rig.vfo.activeVfo == 0)
        #expect(rigApp.model.operating.cqRepeat)
        #expect(rigApp.model.operating.cqRepeatWindow == 0)
        #expect(Self.dualWatch(fake).last?.hasSuffix("DUAL_WATCH 1") == true)
        rigApp.entry.runShortcut(.so2vDualCq)
        await rigApp.settle()
        #expect(!rigApp.model.operating.cqRepeat)
        #expect(Self.dualWatch(fake).last?.hasSuffix("DUAL_WATCH 0") == true)
        // Outside SO2V it says so.
        rigApp.model.config.config.radioMode = "SO2R"
        rigApp.rig.syncRadioModeFromConfig()
        rigApp.entry.runShortcut(.so2vDualCq)
        #expect(rigApp.status.contains("SO2V"))
    }

    @Test func theRotorFollowsTheRadioWithTheFocus() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.radioMode = "SO2R"
            config.antennas = [
                AntennaEntry(code: 1, name: "Yagi 20", bands: "20m", sector: "", rotors: "R20"),
                AntennaEntry(code: 2, name: "Yagi 40", bands: "40m", sector: "", rotors: "R40"),
            ]
        }
        rigApp.model.vfoB.entry.isWindowShown = true
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.qsy(14_025_000)
        rig.rememberInactiveFrequency(7_010_000, vfo: 1)
        #expect(rig.rotator.beamTargets().map(\.key) == ["R20"])
        rig.activateVfo(1, rxOnly: true)
        #expect(rig.currentBand == .m40)
        #expect(rig.rotator.beamTargets().map(\.key) == ["R40"])
    }
}
