import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The Settings ports of the radio tools: after OK the antenna index, the footswitch, the radio mode and the mode
/// mapping follow, and the reconnect reads the CAT state at its step; a rig scan disconnects CAT first.
@MainActor @Suite struct RigSettingsPortsTests {

    static func app(rig port: Int, recorder: EffectRecorder) async throws -> RigApp {
        try await RigApp.make(configure: { config, dataDir in
            let copy: URL = dataDir.appendingPathComponent("copied-data")
            try FileManager.default.copyItem(at: Fixtures.contestData, to: copy)
            config.contestDataDir = copy.path
            config.rig = fakeRigConfig(port, label: "Fake")
            // Only 20 m antennas: the reconnected rig on 40 m selects none, so the reset index stays observable.
            config.antennas = Array(RigVfoTests.antennas.prefix(2))
        }, adjust: { environment in
            environment.settingsServices = recorder.services { nil }
        })
    }

    static func draft(_ settings: SettingsModel) async throws -> ConfigurerDraft {
        settings.open()
        await settings.settle()
        return try #require(settings.draft)
    }

    /// After OK the live ports run in the plan's order: the antenna index is forgotten, the footswitch reopens,
    /// SO2R opens OTRSP, the mode mapping follows; a changed rig reconnects with a disconnect first because CAT is
    /// connected when the step runs (`reconnectCat` reads `catConnected()` there).
    @Test func okRunsThePortsAndReconnectsTheRig() async throws {
        let fake1 = try FakeRigctld()
        let fake2 = try FakeRigctld(freqHz: 7_010_000)
        let recorder = EffectRecorder()
        let rigApp = try await Self.app(rig: fake1.port, recorder: recorder)
        let rig: MCLAppModel.RigModel = rigApp.rig
        await rigApp.connect()
        #expect(rig.antenna.currentIndex == 0)
        let settings: SettingsModel = rigApp.model.settings
        #expect(settings.services.catConnected())
        var draft: ConfigurerDraft = try await Self.draft(settings)
        draft.rigPort = String(fake2.port)
        draft.footswitchPort = "/dev/fake-fs"
        draft.radioMode = "SO2R"
        draft.otrspPort = "/dev/fake-otrsp"
        draft.dataMode = "FT8"
        settings.draft = draft
        #expect(await settings.confirm())
        #expect(recorder.effects.last == .reconnectCat(disconnectFirst: true))
        #expect(rig.antenna.currentIndex == nil)
        #expect(rig.antenna.current?.name == "Yagi")
        #expect(rig.vfo.so2r)
        #expect(rig.modeStore.mapping.dataMode == .ft8)
        await eventually("reconnected to the new rig") { rig.cat1.state?.freqHz == 7_010_000 }
        await rigApp.settle()
        #expect(rigApp.hardware.events.contains("footswitch open /dev/fake-fs CTS"))
        #expect(rigApp.hardware.events.contains("otrsp open /dev/fake-otrsp"))
        #expect(fake2.connectionCount == 1)
        #expect(!settings.services.catConnected() == !rig.catConnected)
    }

    /// „Uložit a připojit" with CAT down: connect without a disconnect, with `config.rig`.
    @Test func saveAndConnectWithCatDown() async throws {
        let fake = try FakeRigctld()
        let recorder = EffectRecorder()
        let rigApp = try await Self.app(rig: fake.port, recorder: recorder)
        let settings: SettingsModel = rigApp.model.settings
        #expect(!settings.services.catConnected())
        _ = try await Self.draft(settings)
        #expect(await settings.confirm(reconnectRig: true))
        // The plan carries the candidate; the step reads `catConnected()` (false) and connects without a disconnect.
        #expect(recorder.effects.last == .reconnectCat(disconnectFirst: true))
        await eventually("connected") { rigApp.rig.cat1.state != nil }
        #expect(rigApp.rig.cat1.statusMessage == "TRX: 14025.0 kHz  CW")
    }

    /// The reconnect takes the active rig with `config.rig` — in SO2R with rig 2 active, rig 2 is connected
    /// with rig 1's configuration (Kotlin).
    @Test func reconnectUsesTheActiveRigWithRigOnesConfiguration() async throws {
        let fake = try FakeRigctld()
        let recorder = EffectRecorder()
        let rigApp = try await RigApp.make(configure: { config, _ in
            config.radioMode = "SO2R"
            config.rig = fakeRigConfig(fake.port, label: "Rig 1")
        }, adjust: { environment in
            environment.settingsServices = recorder.services { nil }
        })
        rigApp.rig.activateVfo(1)
        rigApp.model.settings.services.reconnectCat(false)
        await eventually("rig 2 connected") { rigApp.rig.cat2.state != nil }
        #expect(!rigApp.rig.cat1.connected)
        #expect(rigApp.rig.status(vfo: 1) == "TRX: 14025.0 kHz  CW")
    }

    /// `disconnectCat("scan")` before a scan: the active rig is disconnected and the call returns only then.
    @Test func theScanDisconnectsCatFirst() async throws {
        let fake = try FakeRigctld()
        let scan = LiveRigScan()
        let rigApp = try await RigApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }, adjust: { environment in
            environment.settingsToolPorts = SettingsToolPorts(rigScan: scan)
        })
        await rigApp.connect()
        await scan.disconnectCat(reason: "scan")
        await runMainQueue()
        #expect(!rigApp.rig.cat1.connected)
        #expect(rigApp.rig.cat1.statusMessage == "scan")
    }

    /// A profile with `antennas` forgets the antenna index too (through the same port).
    @Test func resetAntennaIndexPort() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.antennas = RigVfoTests.antennas
        }
        rigApp.entry.setFrequency("14025")
        #expect(rigApp.rig.antenna.currentIndex == 0)
        rigApp.model.settings.services.resetAntennaIndex()
        #expect(rigApp.rig.antenna.currentIndex == nil)
    }
}
