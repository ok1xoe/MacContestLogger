import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The rig sessions (`CC:32-172`, `AS:130-143`): the inert default, connecting to a fake
/// `rigctld`, the mirror of the snapshot, adoption, a lost connection, the order of commands on the lane.
@MainActor @Suite struct RigModelTests {

    // MARK: - inert hardware

    @Test func theDefaultEnvironmentAndAnInertProductionAreInert() {
        let environment = AppModel.Environment(dataDir: URL(fileURLWithPath: "/nonexistent"), dxccDir: nil,
                                               rescoreClock: ManualClock(), geometryClock: ManualClock())
        #expect(environment.hardware.isInert)
        #expect(AppModel.Environment.production(processEnvironment: ["MCL_INERT_HARDWARE": "1"]).hardware.isInert)
        #expect(HardwarePorts.production(environment: ["MCL_INERT_HARDWARE": "1"]).isInert)
        #expect(!HardwarePorts.production(environment: [:]).isInert)
        // The inert hardware covers the Settings tools too: no rig scan, fldigi probe, serial or CoreAudio listing.
        let tools: SettingsToolPorts = AppModel.Environment.production(
            processEnvironment: ["MCL_INERT_HARDWARE": "1"]).settingsToolPorts
        #expect(tools.rigScan is NoRigScan)
        #expect(tools.rigList is NoRigList)
        #expect(tools.devices is NoDevices)
        #expect(tools.fldigi is NoFldigi)
    }

    /// An inert switch is a safeguard: any value it is present with means inert, only an absent variable or exactly
    /// `"0"` keeps the live ports.
    @Test(arguments: [
        (nil, false), ("0", false), ("1", true), ("", true), ("true", true), ("no", true),
    ] as [(String?, Bool)])
    func anyValueOfTheInertSwitchButZeroIsInert(_ value: String?, _ inert: Bool) {
        let variable: String = HardwarePorts.inertVariable
        let environment: [String: String] = value.map { [variable: $0] } ?? ["MCL_OTHER": "1"]
        #expect(HardwarePorts.isInert(environment, variable: variable) == inert)
        #expect(HardwarePorts.production(environment: environment).isInert == inert)
        #expect(HardwarePorts.isInert(environment, variable: "MCL_INERT_NETWORK") == false)
    }

    /// Every inert port refuses before any I/O; CAT stays disconnected and says so only in the CAT log.
    @Test func inertPortsOpenNothing() async throws {
        let app = try await TestApp.make { config, _ in
            config.footswitchPort = "/dev/cu.never-opened"
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/cu.never-opened"
        }
        let rig: MCLAppModel.RigModel = app.model.rig
        rig.toggle(vfo: 0)
        await rig.settle()
        await app.model.peripherals.settle()
        await runMainQueue()
        #expect(!rig.cat1.connected)
        #expect(rig.cat1.statusMessage == nil)
        #expect(rig.status(vfo: 0) == "TRX odpojen")
        #expect(app.model.catLog.lines.isEmpty)
        app.model.catLog.open()
        #expect(app.model.catLog.lines.last?.hasSuffix("· Hardware disabled (MCL_INERT_HARDWARE)") == true)
        app.model.catLog.close()
        #expect(!app.model.peripherals.otrspOpen)
        let ports: HardwarePorts = .inert
        #expect(throws: InertHardwareError.self) { try ports.openOtrsp("/dev/cu.x") }
        #expect(throws: InertHardwareError.self) { try ports.makeRotctld("127.0.0.1", 1) }
        #expect(throws: InertHardwareError.self) { try ports.rotorUdp("127.0.0.1", 1, "x") }
        #expect(throws: AudioIOError.self) { try ports.playPcm([0, 0], .capture, nil, { false }) }
        // The CAT log of the app is its own file in the data directory (`App.kt:138`).
        #expect(FileManager.default.fileExists(atPath: app.dataDir.appendingPathComponent("cat.log").path))
    }

    // MARK: - connecting

    /// `CONNECT_RUNNING` to a fake daemon: „Připojuji (%s)…" at once, then the mirror fills from `onChange`; the main
    /// entry window follows the rig (field, mode by Mode Control, tuned frequency) and the status line shows the
    /// active rig's status.
    @Test func connectsMirrorsAndTheEntryFollows() async throws {
        let fake = try FakeRigctld(freqHz: 14_025_000, mode: "CW")
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port, label: "Fake 1")
        }
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.toggle(vfo: 0)
        await eventually("connecting") { rig.cat1.statusMessage == "Připojuji (Fake 1)…" || rig.cat1.connected }
        await eventually("first state") { rig.cat1.state != nil }
        #expect(rig.cat1.connected)
        #expect(rig.cat1.statusMessage == "TRX: 14025.0 kHz  CW")
        #expect(rig.catConnected)
        #expect(rigApp.entry.form.freqKHz == "14025.00")
        #expect(rigApp.entry.form.mode == .cw)
        #expect(rig.tuning.tunedFreqHz == 14_025_000)
        #expect(StatusLine.of(rigApp.model).message == "TRX: 14025.0 kHz  CW")
        rigApp.model.status.showVerbatim("něco")
        #expect(StatusLine.of(rigApp.model).message == "něco")
        // The LED again: disconnect, the default text translated when shown.
        rig.toggle(vfo: 0)
        await eventually("disconnected") { !rig.cat1.connected }
        #expect(rig.cat1.statusMessage == nil)
        #expect(rig.status(vfo: 0) == "TRX odpojen")
        #expect(rigApp.hardware.daemonStarts == 0)
    }

    /// `LAUNCH_DAEMON` with something already listening: adopted — no daemon started, and `disconnect` never ends
    /// it (the fake still accepts connections afterwards).
    @Test func adoptedDaemonIsNeverTerminated() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port, mode: .launchDaemon)
        }
        rigApp.hardware.listen(on: fake.port)
        await rigApp.connect()
        #expect(rigApp.rig.cat1.connected)
        rigApp.model.catLog.open()
        #expect(rigApp.model.catLog.lines.contains { $0.contains("už běžel rigctld") })
        rigApp.model.catLog.close()
        rigApp.rig.toggle(vfo: 0)
        await eventually("disconnected") { !rigApp.rig.cat1.connected }
        await rigApp.rig.settle()
        #expect(rigApp.hardware.daemonStarts == 0)
        #expect(fake.stillListening())
    }

    /// The first failed poll: `disconnect(tr("Spojení s rigem ztraceno"))`, no reconnect.
    @Test func aLostConnectionIsReported() async throws {
        let fake = try FakeRigctld()
        fake.dropNextRead()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }
        rigApp.rig.toggle(vfo: 0)
        await eventually("lost") { rigApp.rig.cat1.statusMessage == "Spojení s rigem ztraceno" }
        #expect(!rigApp.rig.cat1.connected)
        #expect(rigApp.rig.cat1.state == nil)
        #expect(StatusLine.of(rigApp.model).message == "Spojení s rigem ztraceno")
    }

    /// A connection that fails: `tr("Připojení selhalo: %s")` with the client's message.
    @Test func aFailedConnectionIsReported() async throws {
        let fake = try FakeRigctld()
        let port: Int = fake.port
        fake.stop()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(port)
        }
        rigApp.rig.toggle(vfo: 0)
        await eventually("failed") { rigApp.rig.cat1.statusMessage?.hasPrefix("Připojení selhalo: ") == true }
        #expect(rigApp.rig.cat1.statusMessage == "Připojení selhalo: Nelze se připojit k rigctld na 127.0.0.1:\(port)")
    }

    /// An error Kotlin does not catch (not a `CatException`): shown in the status line and written to the CAT log.
    @Test func anUnexpectedErrorIsShownAndLogged() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }
        rigApp.hardware.failConnectUnexpectedly("socket broke")
        rigApp.rig.toggle(vfo: 0)
        await eventually("error shown") { rigApp.status == "socket broke" }
        rigApp.model.catLog.open()
        #expect(rigApp.model.catLog.lines.last?.hasSuffix("· socket broke") == true)
        rigApp.model.catLog.close()
        #expect(!rigApp.rig.cat1.connected)
    }

    /// The rig's commands keep their order on its lane: QSY, mode, RIT, split, as asked.
    @Test func commandsKeepTheirOrderOnTheLane() async throws {
        let fake = try FakeRigctld()
        let rigApp = try await RigApp.make { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }
        await rigApp.connect()
        let rig: MCLAppModel.RigModel = rigApp.rig
        rig.qsy(7_010_000, mode: .cw)
        rig.setRit(120)
        rig.setSplit(7_012_000)
        rig.swapVfo()
        rig.setOtherVfo(7_015_000)
        await rigApp.settle()
        #expect(fake.writes == ["F 7010000", "M CW 0", "J 120", "U RIT 1", "S 1 VFOB", "I 7012000", "G XCHG",
                                "V VFOB", "F 7015000", "V VFOA"])
        #expect(rig.rit.ritHz == 120)
    }

    /// Both rigs read the one live mapping; `applyModeSettings` changes it at once (start-up, Settings).
    @Test func modeSettingsGoToTheSharedMapping() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.dataMode = "FT8"
            config.rttyAfsk = true
        }
        #expect(rigApp.rig.modeStore.mapping == HamlibModeMapping(dataMode: .ft8, rttyAfsk: true))
        rigApp.model.config.config.dataMode = "PSK"
        rigApp.model.config.config.rttyAfsk = false
        rigApp.rig.applyModeSettings()
        #expect(rigApp.rig.modeStore.mapping == HamlibModeMapping(dataMode: .psk, rttyAfsk: false))
    }

    /// `loggedMode` by Mode Control: ALWAYS gives the fixed mode, BANDPLAN the segment's.
    @Test func loggedModeFollowsModeControl() async throws {
        let rigApp = try await RigApp.make { config, _ in
            config.modeRule = "ALWAYS"
            config.modeAlways = "RTTY"
        }
        #expect(rigApp.rig.loggedMode(.cw, freqHz: 14_025_000) == .rtty)
        rigApp.model.config.config.modeRule = "BANDPLAN"
        #expect(rigApp.rig.loggedMode(.ssb, freqHz: 14_025_000) == .cw)
        rigApp.model.config.config.modeRule = "nonsense"
        #expect(rigApp.rig.loggedMode(.ssb, freqHz: 14_025_000) == .ssb)
    }

    /// DEBUGCAT opens the CAT log window; its lines follow the log while it is open (listener removed on close).
    @Test func debugCatOpensTheCatLog() async throws {
        let rigApp = try await RigApp.make()
        rigApp.entry.callChanged("DEBUGCAT")
        rigApp.entry.handle(.enter(ctrl: false, step: .logQso(ctrlEnter: false)))
        #expect(rigApp.model.windows.isOpen("catLog"))
        let catLog: CatLogModel = rigApp.model.catLog
        catLog.open()
        let before: Int = catLog.lines.count
        try rigApp.model.rig.catLog.info("hello")
        await eventually("line") { catLog.lines.count == before + 1 }
        catLog.close()
        try rigApp.model.rig.catLog.info("after close")
        await runMainQueue()
        #expect(catLog.lines.count == before + 1)
        catLog.clear()
        #expect(catLog.lines.isEmpty)
    }
}
