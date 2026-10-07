import Foundation
@testable import MCLAppModel
@testable import MCLCore
import Testing

/// Window plugins that reach the rig: raw CAT and transmitting, always through the app's own keyer, voice and PTT
/// paths (a fake rigctld and fake keyers — never real hardware), with Esc, the PTT time limit, a plugin's stop, the
/// quit and the keying gate releasing or refusing; and the web window's bridge on the model side.
@MainActor @Suite struct PluginStage3ModelTests {

    static let key = "plugin:web/main"

    /// A keying app whose plugin model may run plugins (no process is ever started here: the plugin is web-only)
    /// and whose plugin clock is manual.
    @MainActor struct Rig {
        let keying: KeyingApp
        let rig: FakeRigctld
        let clock: ManualClock

        var model: AppModel { keying.model }
        var plugins: PluginWindowsModel { keying.model.pluginWindows }
    }

    static func make(permissions: [String], granted: [String], cw: Bool = false) async throws -> Rig {
        let fake = try FakeRigctld(mode: cw ? "CW" : "USB")
        let clock = ManualClock()
        let manifest: PluginJSON = .object([
            "protocol": .int(1), "name": .string("Web"), "process": .bool(false),
            "permissions": .array(permissions.map { .string($0) }), "events": .array([.string("qso-logged")]),
            "windows": .array([.object(["id": .string("main"), "kind": .string("web"), "page": .string("index.html")])]),
        ])
        let keying = try await KeyingApp.make(configure: { config, dataDir in
            config.rig = fakeRigConfig(fake.port)
            if cw {
                winkeyerConfig(&config)
            }
            let dir: URL = dataDir.appendingPathComponent("plugins/web", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try manifest.serialized().write(to: dir.appendingPathComponent("plugin.json"), atomically: true,
                                            encoding: .utf8)
            try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        }, adjust: { environment in
            environment.integrationClock = clock
            // A fixed "now": the CAT rate limit counts by the app's clock, never by how fast the test runs.
            let fixed = Date(timeIntervalSince1970: 1_790_000_000)
            environment.now = { fixed }
            environment.network.plugins = PluginsPorts(makeRunner: { _, _ in nil }, launchWindowPlugin: { _, _, _ in
                preconditionFailure("a web-only plugin starts no process")
            })
        })
        await keying.connectRig(fake)
        if cw {
            keying.entry.setMode(.cw)
        }
        let plugins: PluginWindowsModel = keying.model.pluginWindows
        await plugins.rescan()
        plugins.answerConsent("web", granted: granted, shown: plugins.consentPermissions("web"))
        plugins.open(Self.key)
        return Rig(keying: keying, rig: fake, clock: clock)
    }

    static func ask(_ rig: Rig, _ method: String, _ params: [String: PluginJSON] = [:]) async -> PluginJSON {
        await rig.plugins.webAnswer(Self.key, method: method, params: params)
    }

    // MARK: - raw CAT

    @Test func aRawCatCommandReachesTheRigAndItsLog() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer { rig.rig.stop() }
        #expect(rig.plugins.session("web")?.phase == .running)
        let answer: PluginJSON = await Self.ask(rig, "cat.send", ["command": .string("f")])
        #expect(answer["result"]?["code"] == .int(0))
        #expect(rig.rig.commands.contains("+f"))
        #expect(rig.model.rig.catLog.snapshot().contains { $0.contains("+f") })
        // A keying command never leaves the app.
        let refused: PluginJSON = await Self.ask(rig, "cat.send", ["command": .string("T 1")])
        #expect(refused["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(!rig.rig.commands.contains { $0.contains("T 1") })
    }

    @Test func rawCatIsRateLimited() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer { rig.rig.stop() }
        var limited = 0
        for _ in 0..<(PluginWindowsModel.catPerSecond + 3) {
            let answer: PluginJSON = await Self.ask(rig, "cat.send", ["command": .string("f")])
            if answer["error"]?["code"] == .string("rate_limited") {
                limited += 1
            }
        }
        #expect(limited == 3)
    }

    // MARK: - PTT

    @Test func pttIsReleasedByEscTheTimeLimitAStopAndTheQuit() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        // Esc.
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 1")
        #expect(rig.plugins.pttHolder == "web")
        #expect(rig.plugins.transmitting == "Web")
        #expect(rig.model.entry.stopSending())
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.model.rig.pluginPttRig == nil)
        // The time limit (30 s of the manual clock).
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.clock.advance(by: 29_999)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 1")
        rig.clock.advance(by: 1)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.plugins.pttHolder == nil)
        #expect(rig.model.messages.lines.map(\.text).contains("[Web] PTT pluginu uvolněno po 30 s"))
        // The plugin stops (its window closes).
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.plugins.windowClosed(Self.key)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.model.rig.pluginPttRig == nil)
        // The quit's transmit release, and nothing keys afterwards.
        rig.plugins.open(Self.key)
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.model.rig.closeTransmit()
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        let afterQuit: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(afterQuit["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
    }

    @Test func theKeyingGateAndTheMissingGrantRefuseThePtt() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: [])
        defer { rig.rig.stop() }
        let denied: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(denied["error"]?["code"] == .string("permission"))
        rig.plugins.setGrants("web", ["transmit"])
        rig.model.rig.keyingGate = { EntryStatus.verbatim("Simulátor běží") }
        let gated: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(gated["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(!rig.rig.writes.contains("T 1"))
        #expect(rig.plugins.pttHolder == nil)
    }

    // MARK: - keyer paths

    @Test func cwAndFunctionKeysGoThroughTheKeyer() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true)
        defer { rig.rig.stop() }
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string("TEST")])["result"] != nil)
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        #expect(key.events.contains { $0.hasPrefix("send ") && $0.contains("TEST") })
        #expect(rig.plugins.transmitting == "Web")
        _ = await Self.ask(rig, "tx.fkey", ["key": .int(1)])
        await rig.keying.settle()
        #expect(key.events.filter { $0.hasPrefix("send ") }.count == 2)
        // Esc stops the plugin's message like any other.
        #expect(await Self.ask(rig, "tx.stop")["result"]?["stopped"] == .bool(true))
        await rig.keying.settle()
        #expect(key.events.last == "abort")
        // Once the keyer is quiet, the indicator goes.
        rig.keying.clock.advance(by: 60_000)
        rig.clock.advance(by: 500)
        #expect(rig.plugins.transmitting == nil)
        #expect(await Self.ask(rig, "tx.fkey", ["key": .int(13)])["error"]?["code"] == .string("invalid_params"))
        rig.keying.entry.setMode(.ssb)
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string("TEST")])["error"]?["message"]
            == .string("not in CW"))
    }

    // MARK: - web bridge

    @Test func theWebBridgeAnswersAndListens() async throws {
        let rig = try await Self.make(permissions: ["read", "ui"], granted: [])
        defer { rig.rig.stop() }
        #expect(await Self.ask(rig, "log.count")["result"]?["count"] == .int(0))
        #expect(await Self.ask(rig, "rig.qsy", ["freqHz": .int(14_025_000)])["error"]?["code"] == .string("permission"))
        let received = Box<[String]>([])
        let listener: Int = try #require(rig.plugins.addWebListener(Self.key) { line in
            MainHop.post { received.value.append(line) }
        })
        rig.model.plugins.fire(.qsoLogged, json: #"{"call":"OK1ABC"}"#)
        rig.model.plugins.fire(.contestOpened, json: "{}")
        await eventually("event") { !received.value.isEmpty }
        await drainMainQueue()
        #expect(received.value.count == 1)
        #expect(received.value.first.flatMap { try? PluginJSON.parse($0) }?["event"] == .string("qso-logged"))
        rig.plugins.removeWebListener(listener)
        rig.model.plugins.fire(.qsoLogged, json: "{}")
        await drainMainQueue()
        #expect(received.value.count == 1)
        #expect(await rig.plugins.webAnswer("plugin:web/none", method: "log.count", params: [:])["error"]?["code"]
            == .string("unavailable"))
    }

    @Test func aWebPluginWaitsForItsConsent() async throws {
        let fake = try FakeRigctld(mode: "USB")
        defer { fake.stop() }
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: [])
        defer { rig.rig.stop() }
        // Granted nothing, but decided: running. A new undecided permission would make it wait (stage 2 rules).
        #expect(rig.plugins.session("web")?.phase == .running)
        #expect(rig.plugins.consentPermissions("web").isEmpty)
    }

    /// A plugin process that crashes while it holds the PTT leaves nothing keyed.
    @Test func aCrashingPluginReleasesItsPtt() async throws {
        let app = try await IntegrationApp.make()
        try PluginWindowsModelTests.plugin(app, permissions: ["read", "ui", "transmit"], body: """
            IFS= read -r hello
            echo '{"type":"request","id":1,"method":"tx.ptt","params":{"on":true}}'
            IFS= read -r answer
            exit 7
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.answerConsent("demo", granted: ["transmit"], shown: ["transmit"])
        model.open(PluginWindowsModelTests.key)
        await eventually("ended") { model.session("demo")?.phase == .exited(7) }
        #expect(model.pttHolder == nil)
        #expect(app.model.rig.pluginPttRig == nil)
        #expect(model.transmitting == nil)
    }
}
