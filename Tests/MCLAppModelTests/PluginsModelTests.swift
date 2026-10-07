import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// The plugins: scripts in the test's own temporary directory (`/bin/sh`, `echo`, no
/// network), never the user's `plugins` directory.
/// A runner that counts the directory listings and whether one ran on the main thread.
final class ListingRunner: PluginRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var listings: [Bool] = []
    private var fires = 0
    let hasPlugins: Bool

    init(hasPlugins: Bool) {
        self.hasPlugins = hasPlugins
    }

    /// For each listing: `true` when it ran on the main thread.
    var listedOnMain: [Bool] {
        lock.withLock { listings }
    }

    var fireCount: Int {
        lock.withLock { fires }
    }

    func plugins(_ event: PluginRunner.Event) -> [String] {
        lock.withLock { listings.append(Thread.isMainThread) }
        return hasPlugins ? ["fake.sh"] : []
    }

    func fire(_ event: PluginRunner.Event, json: String) -> [PluginRunner.Result] {
        fire(event, json: json, deadline: { nil })
    }

    func fire(_ event: PluginRunner.Event, json: String, deadline: @Sendable () -> Date?) -> [PluginRunner.Result] {
        lock.withLock { fires += 1 }
        return [PluginRunner.Result(plugin: "fake.sh", exitCode: 0, output: ["ran"])]
    }
}

@MainActor @Suite struct PluginsModelTests {

    /// The directory listing of the pre-check happens on the plugin lane — neither the QSO event (main
    /// actor) nor a spot (reader thread) lists the directory on its own thread.
    @Test func thePluginListingNeverRunsOnTheCallingThread() async throws {
        for hasPlugins in [false, true] {
            let runner = ListingRunner(hasPlugins: hasPlugins)
            let app = try await IntegrationApp.make(adjust: { environment in
                environment.network.plugins = PluginsPorts { _, _ in runner }
            })
            app.plugins.fire(.qsoLogged, json: "{}")
            let spot = DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: "")
            let readerDone = Done()
            let handler = app.plugins.spotHandler
            let reader = Thread {
                handler(spot)
                Task { @MainActor in readerDone.value = true }
            }
            reader.start()
            await eventually("reader returned") { readerDone.value }
            await app.plugins.settle()
            // The start-up's APP_STARTED, the QSO event and the spot: three listings, all on the lane.
            #expect(runner.listedOnMain.count == 3)
            #expect(!runner.listedOnMain.contains(true))
            #expect(runner.fireCount == (hasPlugins ? 3 : 0))
        }
    }

    /// Writes an executable `sh` script `name` into `<data dir>/plugins/<event dir>/`.
    static func plugin(_ app: IntegrationApp, event: String, name: String = "p.sh", body: String) throws {
        let dir: URL = app.app.dataDir.appendingPathComponent("plugins/\(event)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file: URL = dir.appendingPathComponent(name)
        try ("#!/bin/sh\n" + body + "\n").write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    static func messageTexts(_ app: IntegrationApp) -> [String] {
        app.model.messages.lines.map(\.text)
    }

    @Test func aLiveQsoRunsTheQsoLoggedPluginsAndShowsTheirOutput() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, event: "qso-logged", body: "echo hello\necho \"event $MCL_EVENT\"")
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("output shown") { Self.messageTexts(app).contains("[p.sh] hello") }
        #expect(Self.messageTexts(app).contains("[p.sh] event qso-logged"))
        #expect(app.model.messages.revision >= 1)
    }

    @Test func aNonZeroExitCodeIsAMessage() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, event: "qso-logged", body: "exit 3")
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("exit code shown") { Self.messageTexts(app).contains("[p.sh] skončil s kódem 3") }
    }

    /// An import (WSJT-X, N1MM, ADIF) is not a live QSO: the plugin does not run.
    @Test func anImportedQsoRunsNoPlugin() async throws {
        let sender = UdpSink()
        defer { sender.close() }
        let app = try await IntegrationApp.make(configure: { config, _ in
            config.adifUdp.receiveEnabled = true
            config.adifUdp.receiveBind = "127.0.0.1:45005"
        })
        let marker: URL = app.app.dir.child("ran")
        try Self.plugin(app, event: "qso-logged", body: "echo x >> '\(marker.path)'")
        try await app.app.startCqWwCw()
        await eventually("listening") { app.integrations.adifPort != nil }
        let port: Int = try #require(app.integrations.adifPort)
        let ingests = ReceiveIntegrationTests.countIngests(app)
        sender.send(ReceiveIntegrationTests.ownAdif, toPort: port)
        await eventually("ingested") { ingests.value == 1 }
        #expect(app.model.logbook.rows.count == 1)
        await app.plugins.settle()
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        // A QSO logged here does run it.
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("ran for the live QSO") { FileManager.default.fileExists(atPath: marker.path) }
    }

    /// `CONTEST_OPENED` on an opening activation (RELOAD), not on the reopening after a data reload.
    @Test func contestOpenedFiresOnOpenAndNotOnReopen() async throws {
        let app = try await IntegrationApp.make()
        let marker: URL = app.app.dir.child("opened")
        try Self.plugin(app, event: "contest-opened", body: "echo \"$(cat)\" >> '\(marker.path)'")
        try await app.app.startCqWwCw()
        await eventually("fired once") { Self.lines(marker).count == 1 }
        #expect(Self.lines(marker).first?.contains("\"contestId\":") == true)
        #expect(Self.lines(marker).first?.contains("\"call\":\"OK1XOE\"") == true)

        await app.model.contest.reloadContestData()
        await app.plugins.settle()
        #expect(Self.lines(marker).count == 1)

        await app.model.contest.reloadAll()
        await eventually("fired by RELOAD") { Self.lines(marker).count == 2 }
    }

    @Test func aSpotRunsTheSpotReceivedPlugins() async throws {
        let app = try await IntegrationApp.make()
        let marker: URL = app.app.dir.child("spot")
        try Self.plugin(app, event: "spot-received", body: "echo \"$(cat)\" >> '\(marker.path)'")
        app.model.dxCluster.pluginSpot(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: "CQ"))
        await eventually("fired") { Self.lines(marker).count == 1 }
        let json: String = try #require(Self.lines(marker).first)
        #expect(json == "{\"dxCall\":\"OH2AS\",\"freqHz\":14030000,\"spotter\":\"OK1ABC\",\"comment\":\"CQ\"}")
    }

    @Test func noPluginsNoMessages() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.plugins.settle()
        #expect(Self.messageTexts(app).isEmpty)
    }

    /// Plugins run local executables: with the inert plugin port (either switch) nothing fires.
    @Test func inertPluginsRunNothing() async throws {
        let app = try await IntegrationApp.make(adjust: { environment in
            environment.network.plugins = .inert
        })
        let marker: URL = app.app.dir.child("ran")
        try Self.plugin(app, event: "qso-logged", body: "echo x >> '\(marker.path)'")
        #expect(!app.plugins.isActive)
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.plugins.settle()
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    /// The quit waits for a run in flight after the database closed, and later events fire nothing.
    @Test func theQuitDrainsThePluginLane() async throws {
        // The runner's 10 s limit counts from the plugin's start to the end of the whole quit, which a slow CI runner
        // can exceed; a plugin killed at its limit would leave no marker. Only a hang may reach this limit.
        let app = try await IntegrationApp.make(adjust: { environment in
            environment.network.plugins = PluginsPorts { root, _ in PluginRunner(root: root, timeoutMs: 600_000) }
        })
        let marker: URL = app.app.dir.child("slow")
        try Self.plugin(app, event: "qso-logged", body: "sleep 0.3\necho done >> '\(marker.path)'")
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.model.shutdown()
        #expect(FileManager.default.fileExists(atPath: marker.path))
        app.plugins.fire(.qsoLogged, json: "{}")
        await app.plugins.settle()
        #expect(Self.lines(marker).count == 1)
    }

    static func lines(_ file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    /// With no plugin for the event nothing is queued on the lane.
    @Test func noPluginForTheEventQueuesNoJob() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, event: "contest-opened", body: "true")
        let before: Int = app.plugins.completedRuns
        app.plugins.fire(.qsoLogged, json: "{}")
        app.model.dxCluster.pluginSpot(DxSpot(spotter: "OK1ABC", freqHz: 14_030_000, dxCall: "OH2AS", comment: ""))
        await app.plugins.settle()
        #expect(app.plugins.completedRuns == before)
        app.plugins.fire(.contestOpened, json: "{}")
        await eventually("a handled event runs") { app.plugins.completedRuns == before + 1 }
    }

    /// The quit's wait for plugins is bounded as a whole — a plugin that would start after the deadline is not
    /// started (the running one finishes within its own limit).
    @Test func theQuitDoesNotStartPluginsPastTheDeadline() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = app.app.dir.child("marks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Each plugin holds until the test releases the gate, so the first one is still running when the quit
        // deadline is set, however slow the machine is.
        let gate: String = dir.appendingPathComponent("gate").path
        for name in ["p1.sh", "p2.sh", "p3.sh"] {
            try Self.plugin(app, event: "qso-logged", name: name,
                            body: "touch '\(dir.path)/\(name).start'\n"
                                + "while [ ! -e '\(gate)' ]; do sleep 0.05; done\n"
                                + "touch '\(dir.path)/\(name).end'")
        }
        app.plugins.quitBoundMs = 0
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await eventually("first plugin running") {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("p1.sh.start").path)
        }
        app.plugins.startQuitDeadline()
        FileManager.default.createFile(atPath: gate, contents: nil)
        await app.plugins.drain()
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("p1.sh.end").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("p2.sh.start").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("p3.sh.start").path))
    }

    /// The deadline also cuts a running plugin short: it is killed at the deadline, the others are not started.
    @Test func aDeadlineKillsTheRunningPlugin() throws {
        let dir = try TempDir()
        let root: URL = dir.child("plugins/qso-logged")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.sh", "b.sh"] {
            let file: URL = root.appendingPathComponent(name)
            try "#!/bin/sh\nexec sleep 30\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let runner = PluginRunner(root: dir.child("plugins").path, timeoutMs: 10_000)
        let end: Date = Date(timeIntervalSinceNow: 0.4)
        let results: [PluginRunner.Result] = runner.fire(.qsoLogged, json: "{}", deadline: { end })
        #expect(results.map(\.plugin) == ["a.sh", "b.sh"])
        #expect(results.allSatisfy { $0.exitCode == -1 })
        #expect(results.allSatisfy { $0.output.first?.hasPrefix("plugin překročil časový limit") == true })
    }
}
