import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The whole quit order in one recorded run (a deliberate divergence from Java v1.1.1).
///
/// Kotlin `quit` (`App.kt:197-207`, `AS:2143`) against Swift `AppModel.shutdown()` (`AppModel.swift`, "shutdown"):
///
/// | # | Kotlin                        | Swift step (recorded name) |
/// |---|-------------------------------|-------------------------------------------------------------|
/// | 0 | —                             | `releaseTransmit`: PTT, tune, CW and voice released first |
/// | 0 | —                             | `infoTools`: watchers and window models stop |
/// | 0 | `shutdownKeyers()` saves cfg  | early config save (a write tagged `infoTools`) |
/// | 1 | `shutdownKeyers()`            | `keyers` (CQ repeat, voice, fldigi, CW keyer, then the simulator) |
/// | — | —                             | `autoBackup.stop`, settles, config save, database drain |
/// | 2 | `cat.disconnect`              | `cat` (both rigs, footswitch, OTRSP, rotator, recorder, audio) |
/// | 3 | `dxCluster.disconnect`        | `dxCluster` (main and parallel connections, callbook lane) |
/// | 4 | `stopCluster()`               | `cluster` |
/// | 5 | `stopBroadcast`, `stopWsjtx`, `stopN1mm`, `stopAdifUdp` | `integrations` (+ online services; the Club Log queue is lost) |
/// | 6 | `closeDatabase()`             | `database.close` (forced backup inside), `database.closed` |
/// | — | —                             | `geometry.flush`, `config.flushed` |
/// | — | —                             | `dxClusterDrain` (cluster threads, callbook lane, plugins) |
///
/// The steps without a port are recorded through the model's `quitStepObserver`; everything else is the real
/// services over fakes (fake `rigctld`, fake keying hardware, an in-memory sync transport, loopback sockets).
/// The recorder also captures, at the entry of each step, which effects already happened — so a swap of two steps
/// changes both the step list and the effect sets. Nothing real is touched.
@MainActor @Suite struct ShutdownSequenceTests {

    /// The step names in the order of `AppModel.shutdown()`.
    static let order: [String] = [
        "releaseTransmit", "infoTools", "keyers", "autoBackup.stop", "cat", "dxCluster", "cluster", "integrations",
        "database.close", "database.closed", "geometry.flush", "config.flushed", "dxClusterDrain",
    ]

    // MARK: - tests

    @Test func theWholeQuitRunsInTheDocumentedOrder() async throws {
        let rig = try await QuitRig.make()
        await rig.shutdown()
        #expect(rig.recorder.steps == Self.order)
    }

    /// The effects at the entry of every step: each item of the documented list happens at its own step and not
    /// before (a swap shows as an effect early or missing).
    @Test func everyItemHappensAtItsOwnStep() async throws {
        let rig = try await QuitRig.make()
        let running: Set<String> = rig.effects()
        #expect(running.isEmpty, "nothing has ended before the quit: \(running.sorted())")
        await rig.shutdown()
        let seen: [String: [String]] = rig.recorder.entryEffects
        // `releaseTransmit` closes the keyer itself (the `keyers` step repeats it as a backstop).
        let afterTransmit: [String] = ["keyerClosed", "tuneOff"]
        let afterKeyers: [String] = afterTransmit
        let afterCat: [String] = afterKeyers + [
            "rig1Disconnected", "rig2Disconnected", "footswitchClosed", "otrspClosed", "rotatorStopped",
            "recordingStopped", "audioStopped",
        ]
        let afterDx: [String] = afterCat + ["dxClosed", "dxParallelClosed"]
        let afterCluster: [String] = afterDx + ["clusterStopped"]
        let afterIntegrations: [String] = afterCluster + ["integrationsClosed", "clubLogQueueDropped"]
        let afterDatabase: [String] = afterIntegrations + ["backupWritten", "databaseClosed"]
        #expect(seen["releaseTransmit"] == [])
        #expect(seen["infoTools"] == afterTransmit.sorted())
        #expect(seen["keyers"] == afterTransmit.sorted())
        #expect(seen["autoBackup.stop"] == afterKeyers.sorted())
        #expect(seen["cat"] == afterKeyers.sorted())
        #expect(seen["dxCluster"] == afterCat.sorted())
        #expect(seen["cluster"] == afterDx.sorted())
        #expect(seen["integrations"] == afterCluster.sorted())
        #expect(seen["database.close"] == afterIntegrations.sorted())
        #expect(seen["database.closed"] == afterDatabase.sorted())
        #expect(seen["geometry.flush"] == afterDatabase.sorted())
        #expect(seen["config.flushed"] == afterDatabase.sorted())
        #expect(seen["dxClusterDrain"] == afterDatabase.sorted())
    }

    /// The simulator is still running while the transmit is released and stops with the keyers, before the rigs.
    @Test func theSimulatorStopsAfterTheTransmitReleaseAndBeforeTheRigs() async throws {
        let rig = try await QuitRig.make(withSimulator: true)
        #expect(rig.simulator.isOn)
        await rig.shutdown()
        let seen: [String: [String]] = rig.recorder.entryEffects
        #expect(seen["infoTools"]?.contains("simulatorStopped") == false)
        #expect(seen["keyers"]?.contains("simulatorStopped") == false)
        #expect(seen["autoBackup.stop"]?.contains("simulatorStopped") == true)
        #expect(seen["cat"]?.contains("rig1Disconnected") == false)
        #expect(rig.audio.sink?.closes == 1)
    }

    /// The backup is written inside the close, before the connection closes: it is on disk at the end of the close
    /// step, holds the QSO, and no failure message was shown.
    @Test func theForcedBackupIsWrittenBeforeTheDatabaseCloses() async throws {
        let rig = try await QuitRig.make()
        await rig.shutdown()
        #expect(rig.recorder.steps.firstIndex(of: "database.close")! < rig.recorder.steps.firstIndex(of: "database.closed")!)
        let seen: [String: [String]] = rig.recorder.entryEffects
        #expect(seen["database.close"]?.contains("backupWritten") == false)
        #expect(seen["database.close"]?.contains("databaseClosed") == false)
        #expect(seen["database.closed"]?.contains("backupWritten") == true)
        #expect(seen["database.closed"]?.contains("databaseClosed") == true)
        #expect(!rig.app.model.status.message.contains("záloha selhala"))
        let backups: [URL] = rig.backupFiles()
        #expect(backups.count == 1)
        let size = try FileManager.default.attributesOfItem(atPath: try #require(backups.first).path)[.size] as? Int
        #expect((size ?? 0) > 1_000)
    }

    /// The geometry and the config reach the disk after the database closed (the config writes: the early save, the
    /// save after the settles, and the geometry flush, each tagged with the last step that ran before it).
    @Test func theConfigAndGeometryAreFlushedAfterTheDatabaseClose() async throws {
        let rig = try await QuitRig.make()
        await rig.shutdown()
        let writes: [QuitRig.Write] = rig.writes.all
        #expect(writes.map(\.tag) == ["infoTools", "autoBackup.stop", "geometry.flush"], "\(writes)")
        #expect(writes.map(\.hasGeometry) == [false, false, true])
        // The write with the geometry carries the pending window frame and was enqueued after the database closed.
        #expect(rig.recorder.writesAtEntry["database.closed"] == 2)
        #expect(rig.recorder.writesAtEntry["geometry.flush"] == 2)
        #expect(rig.recorder.writesAtEntry["config.flushed"] == 3)
        #expect(rig.recorder.writesAtEntry["dxClusterDrain"] == 3)
        let saved: AppConfig = rig.app.savedConfig()
        #expect(saved.windowGeometry["bandmap"] != nil)
    }

    /// The DX cluster drain (cluster threads, callbook lane, plugins in flight) is the last step: the plugin that was
    /// released at its entry has finished by the time the quit returns, after the config was flushed.
    @Test func theDxClusterDrainIsLast() async throws {
        let rig = try await QuitRig.make()
        #expect(!FileManager.default.fileExists(atPath: rig.pluginMarker.path))
        await rig.shutdown()
        #expect(rig.recorder.steps.last == "dxClusterDrain")
        #expect(FileManager.default.fileExists(atPath: rig.pluginMarker.path))
        #expect(rig.recorder.entryEffects["dxClusterDrain"]?.contains("pluginDone") != true)
    }

    /// A second quit request starts no second sequence: the gate (the only caller of `shutdown()`) cancels every
    /// request while the first one is pending; and should `shutdown()` ever run again over the closed services it
    /// changes nothing that can be observed (no second backup, the database stays closed, no failure shown).
    @Test func aSecondShutdownRepeatsNothing() async throws {
        var gate = TerminationGate()
        gate.bootstrapStarted()
        _ = gate.bootstrapSucceeded()
        #expect(gate.requestTermination() == .terminateLater(startShutdown: true))
        #expect(gate.requestTermination() == .terminateCancel)
        #expect(gate.requestTermination() == .terminateCancel)

        let rig = try await QuitRig.make()
        await rig.shutdown()
        let backups: [URL] = rig.backupFiles()
        let status: String = rig.app.model.status.message
        await rig.app.model.shutdown()
        #expect(rig.backupFiles() == backups)
        #expect(rig.app.model.database.handle.isClosed)
        #expect(rig.app.model.status.message == status)
        // The order of the second run is the same (every service is idempotent).
        let second: [String] = Array(rig.recorder.steps.dropFirst(Self.order.count))
        #expect(second == Self.order)
        #expect(rig.app.savedConfig().windowGeometry["bandmap"] != nil)
    }

    /// The list of windows the real-quit script opens (`scripts/quit-e2e.py`, scenario `all-windows`) is every id the
    /// app persists: a new window id without an entry there fails here.
    @Test func theQuitScriptOpensEveryPersistentWindow() throws {
        let script: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../scripts/quit-e2e.py").standardized
        let text: String = try String(contentsOf: script, encoding: .utf8)
        var persistent: Set<String> = WindowsModel.implemented.subtracting(WindowsModel.notPersisted)
        persistent.subtract(WindowsModel.multWindowIds)
        persistent.remove("worldmap")
        for id in persistent.sorted() {
            #expect(text.contains("\"\(id)\""), "\(id) is missing from ALL_WINDOWS of quit-e2e.py")
        }
        for kind in MultGridLayout.kinds {
            #expect(text.contains("\"\(kind)\""), "mult kind \(kind) is missing from MULT_KINDS")
        }
    }

    /// The steps are recorded in this order only because `shutdown()` runs them so: a recorder of the ports alone
    /// (the unit contract of `ShutdownServices`) sees every port exactly once.
    @Test func everyPortIsCalledExactlyOnce() async throws {
        let rig = try await QuitRig.make()
        await rig.shutdown()
        for name in ["releaseTransmit", "keyers", "cat", "dxCluster", "cluster", "integrations", "dxClusterDrain"] {
            #expect(rig.recorder.steps.filter { $0 == name }.count == 1, "\(name)")
        }
    }
}

// MARK: - the recorder

@MainActor final class QuitRecorder {
    var steps: [String] = []
    var entryEffects: [String: [String]] = [:]
    var writesAtEntry: [String: Int] = [:]
    var effects: () -> Set<String> = { [] }
    var tag: ((String) -> Void)?
    var writeCount: () -> Int = { 0 }

    func enter(_ name: String) {
        steps.append(name)
        if entryEffects[name] == nil {
            entryEffects[name] = effects().sorted()
            writesAtEntry[name] = writeCount()
        }
        tag?(name)
    }
}

// MARK: - the app

@MainActor struct QuitRig {

    struct Write: Sendable {
        let tag: String
        let hasGeometry: Bool
    }

    /// The config writes of the quit. A write runs later on the writer's queue, so its step is read from the snapshot
    /// itself: every step stamps its name into `station.call` when it begins, and the snapshot is taken at enqueue.
    final class WriteLog: @unchecked Sendable {
        static let stamp = "STEP-"
        private let lock = NSLock()
        private var writes: [Write] = []

        var all: [Write] { lock.withLock { writes } }
        var count: Int { lock.withLock { writes.count } }

        func record(_ config: AppConfig) {
            guard config.station.call.hasPrefix(Self.stamp) else { return }
            let tag: String = String(config.station.call.dropFirst(Self.stamp.count))
            lock.withLock { writes.append(Write(tag: tag, hasGeometry: config.windowGeometry["bandmap"] != nil)) }
        }
    }

    let app: TestApp
    let keying: KeyingApp
    let rig1: FakeRigctld
    let rig2: FakeRigctld
    let rotctld: FakeRigctld
    let dxMain: FakeTelnetServer
    let dxParallel: FakeTelnetServer
    let simAudio: SimAudioFactory
    let network: NetStation
    let recorder: QuitRecorder
    let writes: WriteLog
    let pluginMarker: URL
    let pluginGo: URL
    let integrationUdp: UdpSink
    let clusterTransport: LinkedTransport
    let rotatorClock: ManualClock
    let simulated: Bool

    var model: AppModel { app.model }
    var simulator: SimulatorModel { app.model.simulator }
    var audio: SimAudioFactory { simAudio }

    /// `withSimulator`: the simulator refuses to start while the cluster runs, so the run with the simulator has no cluster.
    static func make(withSimulator: Bool = false) async throws -> QuitRig {
        let rig1 = try FakeRigctld(freqHz: 14_025_000)
        let rig2 = try FakeRigctld(freqHz: 7_010_000)
        let rotctld = try FakeRigctld()
        let dxMain = try FakeTelnetServer()
        let dxParallel = try FakeTelnetServer()
        let simAudio = SimAudioFactory()
        let writes = WriteLog()
        let recorder = QuitRecorder()
        let udp = UdpSink()
        let hub = InMemorySyncTransport()
        let transport = LinkedTransport(hub: hub)
        let online = ScriptedOnline()
        online.scriptClubLog([.RETRY])
        let probe = ScriptedClockProbe()
        let counts = UdpFactoryCounts()
        let hardware = FakeHardware()
        let fakeKeying = FakeKeyingHardware()
        let keyerClock = ManualClock()
        let radioClock = ManualClock()
        let rotatorClock = ManualClock()
        let clusterClock = ManualClock()
        let sleeper = TestSleeper()
        let http = FakeHttpGetter()
        let opener = RecordingUrlOpener()
        let now = TestNow(Date(timeIntervalSince1970: 1_800_000_000))
        var dataFile: URL?
        let app = try await TestApp.make(now: now, configure: { config, dataDir in
            winkeyerConfig(&config)
            config.radioMode = "SO2R"
            config.otrspPort = "/dev/fake-otrsp"
            config.footswitchPort = "/dev/fake-fs"
            config.footswitchAction = "PTT"
            config.rig = fakeRigConfig(rig1.port, label: "Rig 1")
            config.rig2 = fakeRigConfig(rig2.port, label: "Rig 2")
            config.rotatorHost = "127.0.0.1"
            config.rotatorPort = rotctld.port
            config.recordingsDir = dataDir.appendingPathComponent("rec").path
            config.cluster.enabled = !withSimulator
            config.cluster.brokerHost = "broker.invalid"
            config.cluster.stationId = "OP1"
            config.dxCluster.favorites = [dxParallel.favorite(name: "RBN", parallel: true)]
            // The simulator refuses to start while an outward service (Club Log, broadcast) is on.
            if !withSimulator {
                OnlineServicesTests.clubLog(&config)
                config.broadcast.contactsEnabled = true
                config.broadcast.contactsTargets = "127.0.0.1:\(udp.port)"
            }
            ReceiveIntegrationTests.enableWsjtx(&config)
            config.ntpServer = "ntp.example.test"
            dataFile = dataDir.appendingPathComponent("config.json")
        }, adjust: { environment in
            environment.hardware = fakeKeying.ports(over: hardware.ports)
            environment.keyerClock = keyerClock
            environment.rotatorClock = rotatorClock
            environment.radioWindowClock = radioClock
            environment.clusterClock = clusterClock
            simAudio.install(into: &environment)
            var ports: NetworkPorts = IntegrationApp.ports(online: online, probe: probe, counts: counts)
            ports.makeSession = NetworkPorts.sessions(sleep: sleeper.sleep)
            ports.http = http
            ports.urlOpener = opener.opener
            ports.makeSyncTransport = { _, _ in transport }
            ports.isInert = false
            environment.network = ports
            let file: URL = environment.dataDir.appendingPathComponent("config.json")
            environment.configWriter = ConfigWriter { config in
                writes.record(config)
                try ConfigWriter.writeFile(config, to: file)
            }
        })
        _ = dataFile
        let keying = KeyingApp(app: app, hardware: hardware, keying: fakeKeying, clock: keyerClock,
                               radioClock: radioClock)
        let station = NetStation(keying: keying, transport: transport, clusterClock: clusterClock,
                                 made: MadeTransports())
        let marker: URL = app.dir.child("plugin-done")
        let go: URL = app.dir.child("plugin-go")
        let rigSet = QuitRig(app: app, keying: keying, rig1: rig1, rig2: rig2, rotctld: rotctld, dxMain: dxMain,
                             dxParallel: dxParallel, simAudio: simAudio, network: station, recorder: recorder,
                             writes: writes, pluginMarker: marker, pluginGo: go, integrationUdp: udp,
                             clusterTransport: transport, rotatorClock: rotatorClock, simulated: withSimulator)
        try await rigSet.prepare(online: online, hardware: hardware, withSimulator: withSimulator)
        return rigSet
    }

    /// Brings every service into the state a contest has: rigs connected, a tune carrier on, the simulator, the
    /// receiver audio and the recorder running, the clusters connected, a QSO queued for Club Log, a plugin in
    /// flight, a window geometry pending.
    private func prepare(online: ScriptedOnline, hardware: FakeHardware, withSimulator: Bool) async throws {
        try await app.startCqWwCw()
        if !withSimulator {
            await eventually("cluster up") { network.cluster.isRunning && network.cluster.connected }
        }
        model.rig.toggle(vfo: 0)
        await eventually("rig 1") { model.rig.snapshot(vfo: 0).state != nil }
        model.rig.toggle(vfo: 1)
        await eventually("rig 2") { model.rig.snapshot(vfo: 1).state != nil }
        await eventually("footswitch and OTRSP open") {
            let events: [String] = hardware.events
            return events.contains("otrsp open /dev/fake-otrsp") && events.contains("footswitch open /dev/fake-fs CTS")
        }
        await eventually("parallel connected") { model.dxCluster.parallel.values.first?.connected == true }
        model.dxCluster.connect(dxMain.favorite(name: "Main"))
        await eventually("main connected") { model.dxCluster.connected }
        // A plugin that runs until released: the quit's last step awaits it (queued runs would be skipped).
        let started: URL = pluginGo.deletingLastPathComponent().appendingPathComponent("plugin-started")
        let script = "echo 1 > '\(started.path)'\nn=0\nwhile [ ! -f '\(pluginGo.path)' ] && [ $n -lt 200 ]; do sleep 0.05; "
            + "n=$((n+1)); done\necho done > '\(pluginMarker.path)'"
        let dir: URL = app.dataDir.appendingPathComponent("plugins/qso-logged", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent("p.sh")
        try ("#!/bin/sh\n" + script + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        await app.logContestQso(call: "OK1ABC", zone: "15")
        if !withSimulator {
            await eventually("queued for Club Log") { model.onlineServices.clubLogQueued == 1 }
        }
        await eventually("plugin started") { FileManager.default.fileExists(atPath: started.path) }
        keying.keyer.setTune(true)
        await keying.settle()
        let acquired: String? = await model.audio.acquire("waterfall")
        #expect(acquired == nil)
        await model.recording.setRecording(true)
        #expect(model.recording.isRecording)
        if withSimulator {
            model.simulator.start(settings: SimulatorModelTests.settings, noise: 0.1)
            await model.simulator.settle()
            #expect(model.simulator.isOn)
        }
        model.geometry.windowChanged(id: "bandmap", frame: CGRect(x: 100, y: 200, width: 460, height: 640),
                                     persistSize: true, mainScreenHeight: 1_000)
        wire(hardware: hardware)
    }

    /// Wraps the ports and the observer; from here every step is recorded.
    private func wire(hardware: FakeHardware) {
        let model: AppModel = self.model
        let recorder: QuitRecorder = self.recorder
        let writes: WriteLog = self.writes
        let go: URL = pluginGo
        recorder.effects = { [self] in effects() }
        recorder.writeCount = { writes.count }
        recorder.tag = { name in model.config.config.station.call = WriteLog.stamp + name }
        func wrap(_ name: String, _ port: @escaping @MainActor () async -> Void,
                  before: @escaping @MainActor () -> Void = {}) -> @MainActor () async -> Void {
            {
                recorder.enter(name)
                before()
                await port()
            }
        }
        model.shutdownServices.releaseTransmit = wrap("releaseTransmit", model.shutdownServices.releaseTransmit)
        model.shutdownServices.keyers = wrap("keyers", model.shutdownServices.keyers)
        model.shutdownServices.cat = wrap("cat", model.shutdownServices.cat)
        model.shutdownServices.dxCluster = wrap("dxCluster", model.shutdownServices.dxCluster)
        model.shutdownServices.cluster = wrap("cluster", model.shutdownServices.cluster)
        model.shutdownServices.integrations = wrap("integrations", model.shutdownServices.integrations)
        model.shutdownServices.dxClusterDrain = wrap("dxClusterDrain", model.shutdownServices.dxClusterDrain,
                                                     before: { FileManager.default.createFile(atPath: go.path, contents: Data()) })
        model.quitStepObserver = { name in recorder.enter(name) }
    }

    func shutdown() async {
        await model.shutdown()
    }

    func backupFiles() -> [URL] {
        let dir: URL = app.dataDir.appendingPathComponent("backups", isDirectory: true)
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".sqlite") }.map { dir.appendingPathComponent($0) }
    }

    /// What has ended (observed from the services themselves).
    func effects() -> Set<String> {
        var done: Set<String> = []
        let events: [String] = keying.hardware.events
        let keyerEvents: [String] = keying.keying.lastKeyer?.events ?? []
        if keyerEvents.contains("tune off") { done.insert("tuneOff") }
        if keyerEvents.contains("close") { done.insert("keyerClosed") }
        if simulated && !model.simulator.isOn { done.insert("simulatorStopped") }
        if !model.rig.snapshot(vfo: 0).connected { done.insert("rig1Disconnected") }
        if !model.rig.snapshot(vfo: 1).connected { done.insert("rig2Disconnected") }
        if events.contains("footswitch close") { done.insert("footswitchClosed") }
        if events.contains("otrsp close") { done.insert("otrspClosed") }
        if rotatorClock.pendingCount == 0 { done.insert("rotatorStopped") }
        if !model.recording.isRecording { done.insert("recordingStopped") }
        if !model.audio.capture.isRunning { done.insert("audioStopped") }
        if !model.dxCluster.connected { done.insert("dxClosed") }
        if model.dxCluster.parallel.values.allSatisfy({ !$0.connected }) { done.insert("dxParallelClosed") }
        if !model.cluster.isRunning { done.insert("clusterStopped") }
        if model.integrations.isClosed { done.insert("integrationsClosed") }
        if model.onlineServices.clubLogQueued == 0 { done.insert("clubLogQueueDropped") }
        if !backupFiles().isEmpty { done.insert("backupWritten") }
        if model.database.handle.isClosed { done.insert("databaseClosed") }
        if FileManager.default.fileExists(atPath: pluginMarker.path) { done.insert("pluginDone") }
        return done
    }
}
