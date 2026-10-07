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
        /// The app's "now" (the on-air budget counts by it); `advance` moves it with the clock.
        let now: Box<Date>

        /// The PTT commands the rig received, a release's repeated `T 0` (lane and fresh connection) counted once.
        var keyed: [String] {
            var out: [String] = []
            for write in rig.writes where write.hasPrefix("T ") && write != out.last {
                out.append(write)
            }
            return out
        }

        func advance(by ms: Int) {
            now.value = now.value.addingTimeInterval(Double(ms) / 1000)
            clock.advance(by: ms)
        }

        var model: AppModel { keying.model }
        var plugins: PluginWindowsModel { keying.model.pluginWindows }
    }

    static func make(permissions: [String], granted: [String], cw: Bool = false,
                     others: [String] = [], pollIntervalMs: Int64? = nil,
                     extra: [String: PluginJSON] = [:]) async throws -> Rig {
        let fake = try FakeRigctld(mode: cw ? "CW" : "USB")
        let clock = ManualClock()
        let now = Box<Date>(Date(timeIntervalSince1970: 1_790_000_000))
        var fields: [String: PluginJSON] = [
            "protocol": .int(1), "name": .string("Web"), "process": .bool(false),
            "permissions": .array(permissions.map { .string($0) }), "events": .array([.string("qso-logged")]),
            "windows": .array([.object(["id": .string("main"), "kind": .string("web"), "page": .string("index.html")])]),
        ]
        fields.merge(extra) { _, new in new }
        let manifest: PluginJSON = .object(fields)
        let keying = try await KeyingApp.make(configure: { config, dataDir in
            config.rig = fakeRigConfig(fake.port)
            if cw {
                winkeyerConfig(&config)
            }
            for name in ["web"] + others {
                let dir: URL = dataDir.appendingPathComponent("plugins/" + name, isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let named: String = name == "web" ? manifest.serialized()
                    : manifest.serialized().replacingOccurrences(of: "\"Web\"", with: "\"" + name + "\"")
                try named
                    .write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
                try "<html></html>".write(to: dir.appendingPathComponent("index.html"), atomically: true,
                                          encoding: .utf8)
            }
        }, adjust: { environment in
            environment.integrationClock = clock
            _ = pollIntervalMs
            // The app's "now" moves only with the test: the CAT rate limit and the on-air budget count by it.
            environment.now = { now.value }
            environment.network.plugins = PluginsPorts(makeRunner: { _, _ in nil }, launchWindowPlugin: { _, _, _ in
                preconditionFailure("a web-only plugin starts no process")
            })
        }, pollIntervalMs: pollIntervalMs)
        await keying.connectRig(fake)
        if cw {
            keying.entry.setMode(.cw)
        }
        let plugins: PluginWindowsModel = keying.model.pluginWindows
        await plugins.rescan()
        for name in ["web"] + others {
            plugins.answerConsent(name, granted: granted, shown: plugins.consentPermissions(name))
            plugins.open("plugin:" + name + "/main")
        }
        return Rig(keying: keying, rig: fake, clock: clock, now: now)
    }

    static func ask(_ rig: Rig, _ method: String, _ params: [String: PluginJSON] = [:],
                    plugin: String = "web") async -> PluginJSON {
        await rig.plugins.webAnswer("plugin:" + plugin + "/main", method: method, params: params)
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
        // Esc blocked plugin keying until the operator allows it again.
        rig.plugins.allowTransmissions()
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
        rig.clock.advance(by: PluginWindowsModel.pttCooldownMs)
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

    // MARK: - security review

    /// Keying again while keyed never extends the time limit; after the forced release the plugin cools down.
    @Test func thePttTimeLimitCannotBeExtended() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.clock.advance(by: 29_000)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        rig.clock.advance(by: 1_000)
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1", "T 0"], "the second on neither re-keyed nor extended: \(rig.rig.writes)")
        #expect(rig.plugins.pttHolder == nil)
        // The cool-down.
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["code"] == .string("refused"))
        rig.clock.advance(by: PluginWindowsModel.pttCooldownMs)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(false)])
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
    }

    /// Revoking `transmit` releases the plugin's PTT and stops its message at once.
    @Test func revokingTransmitStopsEverything() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true)
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string("CQ TEST")])
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        rig.plugins.setGrants("web", [])
        await rig.keying.settle()
        #expect(key.events.last == "abort")
        #expect(rig.plugins.transmitting == nil)
        rig.plugins.setGrants("web", ["transmit"])
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.plugins.setGrants("web", [])
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.model.rig.pluginPttRig == nil)
        #expect(rig.plugins.pttHolder == nil)
    }

    /// A `T 1` the rig's `rigctld` refuses is never taken as "not keyed": `T 0` follows at once, and only when that
    /// gets through is nothing owed; refused too, the release is owed. One whose outcome is unknown (the connection
    /// dropped) is released and owed until a `T 0` gets through.
    @Test func aRefusedKeyIsReleasedAtOnceAndAnUnknownOneIsOwed() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        rig.rig.reject("T 1")
        let answer: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(answer["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(Self.pttCommands(rig) == ["T 1", "T 0"])
        #expect(!rig.model.rig.pluginPttUnconfirmed)
        #expect(rig.model.rig.pluginPttRig == nil)
        // `T 0` refused as well: owed.
        rig.rig.unreject("T 1")
        rig.rig.reject("T")
        rig.model.rig.freshPttRelease = { _, _ in false }
        rig.model.rig.releaseRetries = 0
        rig.model.rig.releaseSlowRetryMs = 3_600_000
        rig.plugins.allowTransmissions()
        _ = await rig.model.rig.pluginPtt(true)
        await rig.model.rig.settle()
        #expect(rig.model.rig.pluginPttUnconfirmed)
        rig.rig.unreject("T")
        rig.model.rig.retryPluginRelease()
        await eventually("released by hand") { !rig.model.rig.pluginPttUnconfirmed }
        // The outcome unknown: the connection drops on `T 1`; its `T 0` fails too — owed, and only a `T 0` that gets
        // through (here: the next connection's) clears it.
        rig.rig.drop(on: "T 1")
        _ = await rig.model.rig.pluginPtt(true)
        await rig.model.rig.settle()
        #expect(rig.model.rig.pluginPttUnconfirmed)
        #expect(rig.model.rig.pluginPttRig == nil)
        await eventually("lost") { !rig.model.rig.connected(vfo: 0) }
        rig.model.rig.toggle(vfo: 0)
        await eventually("released on the next connection") {
            rig.model.rig.connected(vfo: 0) && !rig.model.rig.pluginPttUnconfirmed
        }
        #expect(Self.pttCommands(rig).last == "T 0")
    }

    /// Esc releases a plugin's PTT and still stops the keyer; the indicator goes.
    @Test func escReleasesThePttAndStopsTheKeyerToo() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true)
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string("CQ")])
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        #expect(rig.model.entry.stopSending())
        await rig.keying.settle()
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(key.events.last == "abort")
        #expect(rig.plugins.pttHolder == nil)
        rig.keying.clock.advance(by: 60_000)
        rig.clock.advance(by: PluginWindowsModel.transmitCheckMs)
        #expect(rig.plugins.transmitting == nil)
        // The indicator's Stop works without the entry window.
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.plugins.stopTransmission()
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.plugins.transmitting == nil)
    }

    /// Another plugin cannot release the holder's PTT (nor the operator's), and the indicator names the holder.
    @Test func onlyTheHolderReleasesThePtt() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], others: ["other"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(rig.plugins.transmitting == "Web")
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(false)], plugin: "other")["result"] != nil)
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1"])
        #expect(rig.plugins.pttHolder == "web")
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(false)])
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1", "T 0"])
    }

    /// A rig that drops its connection while a plugin keyed it: the state is cleared, `T 0` goes out first on the
    /// next connection.
    @Test func aLostRigClearsThePluginPtt() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"],
                                      pollIntervalMs: 20)
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(rig.model.rig.pluginPttRig == 0)
        rig.rig.dropNextRead()
        await eventually("lost") { !rig.model.rig.connected(vfo: 0) }
        #expect(rig.model.rig.pluginPttRig == nil)
        #expect(rig.plugins.pttHolder == nil)
        // The next connection releases first.
        rig.model.rig.toggle(vfo: 0)
        await eventually("reconnected and released") {
            rig.model.rig.connected(vfo: 0) && rig.rig.writes.last == "T 0"
        }
    }

    /// All plugins together send at most `catPerSecondTotal` raw commands a second.
    @Test func rawCatIsLimitedAcrossPlugins() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"], others: ["other"])
        defer { rig.rig.stop() }
        var limited = 0
        for index in 0..<20 {
            let answer: PluginJSON = await Self.ask(rig, "cat.send", ["command": .string("f")],
                                                    plugin: index % 2 == 0 ? "web" : "other")
            if answer["error"]?["code"] == .string("rate_limited") {
                limited += 1
            }
        }
        #expect(limited == 20 - PluginWindowsModel.catPerSecondTotal)
        // A smuggled keying word never reaches the rig.
        #expect(await Self.ask(rig, "cat.send", ["command": .string("f T 1")], plugin: "web")["error"]?["code"] != nil)
        await rig.model.rig.settle()
        #expect(!rig.rig.commands.contains { $0.contains("T 1") })
    }

    // MARK: - second security review

    /// While one plugin holds the PTT, another's `on` is refused: alternating plugins cannot keep the rig keyed
    /// beyond the time limit.
    @Test func aSecondPluginCannotTakeOverThePtt() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], others: ["other"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.advance(by: 25_000)
        let taken: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)], plugin: "other")
        #expect(taken["error"]?["message"] == .string("another plugin holds the PTT"))
        rig.advance(by: 5_000)
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1", "T 0"])
        #expect(rig.plugins.pttHolder == nil)
    }

    /// Esc (and the indicator's Stop) during a plugin transmission blocks plugin keying until the operator allows it.
    @Test func escAndStopStick() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        _ = rig.model.entry.stopSending()
        #expect(rig.plugins.transmissionsBlocked)
        let again: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(again["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1", "T 0"])
        rig.plugins.allowTransmissions()
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        rig.plugins.stopTransmission()
        #expect(rig.plugins.transmissionsBlocked)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(rig.keyed == ["T 1", "T 0", "T 1", "T 0"])
        // Esc without a plugin on the air blocks nothing.
        rig.plugins.allowTransmissions()
        _ = rig.model.entry.stopSending()
        #expect(!rig.plugins.transmissionsBlocked)
    }

    /// Plugin CAT commands queued before a stop are dropped: the safety `T 0` never waits behind them.
    @Test func aStopJumpsQueuedPluginCat() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit", "cat"], granted: ["transmit", "cat"])
        defer { rig.rig.stop() }
        // The held reply must not time out on a slow runner before the stop.
        rig.model.rig.pluginCat?.setReplyTimeout(ms: 120_000)
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.holdAnswer(to: "+f")
        async let first: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        async let second: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("m")])
        await eventually("second queued") { rig.model.rig.pluginCat?.pendingCount == 2 }
        _ = rig.model.entry.stopSending()
        rig.rig.releaseAnswer()
        _ = await first
        let dropped: PluginJSON = await second
        #expect(dropped["error"]?["message"] == .string("cancelled by a stop or release"))
        // The `T 0` goes out on the lane or, when Esc closed the stalled connection, over a fresh one.
        await eventually("released") { rig.rig.commands.contains("T 0") }
        #expect(rig.keyed == ["T 1", "T 0"])
        #expect(rig.rig.commands.filter { $0.hasPrefix("+") } == ["+f"])
    }

    /// The page policy is fixed by what the manifest asks for: a plugin asking for transmit or cat never gets
    /// inline scripts, even when its manifest asks for them and nothing is granted; one that asks for neither does.
    @Test func inlineScriptsFollowTheRequestedPermissions() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: [],
                                      extra: ["webInlineScripts": .bool(true)])
        defer { rig.rig.stop() }
        let setup = try #require(rig.plugins.webSetup(Self.key))
        #expect(setup.contentSecurityPolicy.contains("script-src 'self';"))
        let plain = try await Self.make(permissions: ["read", "ui"], granted: [],
                                        extra: ["webInlineScripts": .bool(true)])
        defer { plain.rig.stop() }
        let inline = try #require(plain.plugins.webSetup(Self.key))
        #expect(inline.contentSecurityPolicy.contains("script-src 'self' 'unsafe-inline';"))
    }

    /// A plugin's message is cut at the message limit; the plugins' on-air budget refuses more once used up; a CW
    /// call queue holds at most two texts.
    @Test func theOnAirBudget() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true)
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string(String(repeating: "CQ TEST ", count: 20))])
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        rig.advance(by: 60_000)
        await rig.keying.settle()
        #expect(key.events.last == "abort")
        #expect(rig.model.messages.lines.map(\.text).contains("[Web] Zpráva pluginu přerušena po 60 s"))
        #expect(rig.plugins.transmitting == nil)
        // Two texts during one transmission, not a third.
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string("A")])
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string("B")])
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string("C")])["error"]?["code"] == .string("busy"))
        _ = await Self.ask(rig, "tx.stop")
        // The budget: 10 % of 5 minutes = 30 s, already used by the first message.
        rig.plugins.setDutyPercent(10)
        let over: PluginJSON = await Self.ask(rig, "tx.sendCw", ["text": .string("D")])
        #expect(over["error"]?["message"]?.stringValue?.contains("on-air budget") == true)
        // Five minutes later it is free again.
        rig.advance(by: 300_000)
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string("E")])["result"] != nil)
    }

    /// A plugin process whose `transmit` is revoked while its `T 1` is on the way: the PTT is released at once and
    /// the plugin gets the permission error (nothing stays keyed until the time limit).
    @Test func aRevokeDuringAKeyReleasesAtOnce() async throws {
        let fake = try FakeRigctld(mode: "USB")
        defer { fake.stop() }
        let keying = try await KeyingApp.make(configure: { config, _ in
            config.rig = fakeRigConfig(fake.port)
        }, adjust: { environment in
            environment.integrationClock = ManualClock()
            environment.network.plugins = PluginsPorts(makeRunner: { _, _ in nil }, launchWindowPlugin: { package, env, handlers in
                precondition(package.directory.contains("mcl-app-model-"), "test plugins only")
                return PluginsPorts.liveLauncher(package, env, handlers)
            })
        })
        await keying.connectRig(fake)
        let dir: URL = keying.app.dataDir.appendingPathComponent("plugins/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"protocol":1,"permissions":["read","ui","transmit"],"windows":[{"id":"main"}]}"#
            .write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        let run: URL = dir.appendingPathComponent("run")
        try """
            #!/bin/sh
            IFS= read -r hello
            echo '{"type":"request","id":1,"method":"tx.ptt","params":{"on":true}}'
            IFS= read -r answer
            printf '%s\\n' "$answer" > answer.json
            while IFS= read -r line; do :; done
            """.write(to: run, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)
        let plugins: PluginWindowsModel = keying.model.pluginWindows
        await plugins.rescan()
        plugins.answerConsent("demo", granted: ["transmit"], shown: ["transmit"])
        fake.holdAnswer(to: "T 1")
        plugins.open("plugin:demo/main")
        await eventually("keying held") { fake.isHoldingAnswer }
        plugins.setGrants("demo", [])
        fake.releaseAnswer()
        let answer: URL = dir.appendingPathComponent("answer.json")
        await eventually("answered") { FileManager.default.fileExists(atPath: answer.path) }
        let reply: String = try String(contentsOf: answer, encoding: .utf8)
        #expect(reply.contains("\"permission\""))
        await keying.model.rig.settle()
        #expect(fake.writes.last == "T 0")
        #expect(keying.model.rig.pluginPttRig == nil)
        #expect(plugins.pttHolder == nil)
        await plugins.shutdown()
    }

    // MARK: - third security review

    /// A plugin CAT command whose reply never comes must not keep the rig keyed: Esc closes that connection and the
    /// `T 0` goes out at once (over a fresh connection when the rig's own is gone).
    @Test func escReleasesEvenBehindAStalledPluginCatCommand() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit", "cat"], granted: ["transmit", "cat"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.holdAnswer(to: "+f")
        async let stalled: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        _ = rig.model.entry.stopSending()
        await eventually("released while the CAT reply is still missing") { rig.rig.writes.contains("T 0") }
        #expect(rig.rig.isHoldingAnswer)
        #expect(rig.model.rig.pluginPttRig == nil)
        rig.rig.releaseAnswer()
        _ = await stalled
    }

    /// The same with the time limit.
    @Test func theTimeLimitReleasesEvenBehindAStalledPluginCatCommand() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit", "cat"], granted: ["transmit", "cat"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.holdAnswer(to: "+f")
        async let stalled: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        rig.advance(by: PluginSettings.defaultPttTimeoutSeconds * 1000)
        await eventually("released") { rig.rig.writes.contains("T 0") }
        #expect(rig.rig.isHoldingAnswer)
        rig.rig.releaseAnswer()
        _ = await stalled
    }

    /// Esc while a plugin's `T 1` is on its way blocks plugin transmissions, and that key is released at once.
    @Test func escDuringAKeyBlocksAndReleases() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        rig.rig.holdAnswer(to: "T 1")
        async let keyed: PluginJSON = Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        await eventually("held") { rig.rig.isHoldingAnswer }
        _ = rig.model.entry.stopSending()
        #expect(rig.plugins.transmissionsBlocked)
        rig.rig.releaseAnswer()
        let answer: PluginJSON = await keyed
        #expect(answer["error"] != nil)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.plugins.pttHolder == nil)
    }

    /// The web path: a grant revoked while a key is on its way gives the permission error and releases.
    @Test func aWebRevokeDuringAKeyIsAPermissionError() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        rig.rig.holdAnswer(to: "T 1")
        async let keyed: PluginJSON = Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        await eventually("held") { rig.rig.isHoldingAnswer }
        rig.plugins.setGrants("web", [])
        rig.rig.releaseAnswer()
        let answer: PluginJSON = await keyed
        #expect(answer["error"]?["code"] == .string("permission"))
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
        #expect(rig.model.rig.pluginPttRig == nil)
    }

    /// The cool-down is global; a voluntary release pauses briefly; a PTT never outlasts the rest of the budget.
    @Test func cooldownsAndTheBudgetAreGlobal() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], others: ["other"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.advance(by: 30_000)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)], plugin: "other")["error"]?["code"]
            == .string("refused"))
        rig.advance(by: PluginWindowsModel.pttCooldownMs)
        // A voluntary release: a short pause for everyone.
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)], plugin: "other")
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(false)], plugin: "other")
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["code"] == .string("refused"))
        rig.advance(by: PluginWindowsModel.pttRekeyMs)
        await rig.model.rig.settle()
        // 10 % of 5 minutes = 30 s, all used: refused. 40 %: 120 s, 30 used, so 90 s left — more than the limit.
        rig.plugins.setDutyPercent(10)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["message"]?.stringValue?
            .contains("budget") == true)
        rig.plugins.setDutyPercent(20)
        // 60 s budget, 30 used: the PTT is cut after the 30 s left, not after its 30 s limit plus overshoot.
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.advance(by: 29_000)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 1")
        rig.advance(by: 1_000)
        await rig.model.rig.settle()
        #expect(rig.rig.writes.last == "T 0")
    }

    /// The message cap is global, and chained messages share one limit from the start of the transmission.
    @Test func messageLimitsAreGlobalAndContinuous() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true,
                                      others: ["other"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string(String(repeating: "CQ ", count: 60))])
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        rig.advance(by: 50_000)
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string(String(repeating: "TEST ", count: 30))])["result"]
            != nil)
        #expect(rig.plugins.transmitting == "Web")
        #expect(rig.plugins.messagesInTransmission == 2)
        #expect(await Self.ask(rig, "tx.sendCw", ["text": .string("X")], plugin: "other")["error"]?["code"]
            == .string("busy"))
        rig.advance(by: 10_000)
        await rig.keying.settle()
        #expect(key.events.last == "abort")
        #expect(rig.model.messages.lines.map(\.text).contains("[Web] Zpráva pluginu přerušena po 60 s"))
    }

    // MARK: - fourth security review

    /// A plugin's stalled raw CAT command never touches the operator's connection: its release goes out on the rig's
    /// lane at once and the polls go on.
    @Test func aStalledPluginCommandLeavesTheOperatorsConnectionAlone() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit", "cat"], granted: ["transmit", "cat"],
                                      pollIntervalMs: 50)
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.holdAnswer(to: "+f")
        async let stalled: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(false)])
        await eventually("released") { rig.keyed == ["T 1", "T 0"] }
        let polls: Int = rig.rig.commands.filter { $0 == "f" }.count
        await eventually("still polling") { rig.rig.commands.filter { $0 == "f" }.count >= polls + 3 }
        #expect(rig.model.rig.connected(vfo: 0))
        #expect(rig.model.rig.cat1.statusMessage != "Spojení s rigem ztraceno")
        rig.rig.releaseAnswer()
        _ = await stalled
    }

    /// The fresh-connection release goes to the rigctld the rig was connected to, whatever the settings say now.
    @Test func theFreshReleaseUsesTheConnectedEndpoint() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.model.config.config.rig.port = 9
        let before: Int = rig.rig.connectionCount
        rig.rig.dropNextRead()
        await eventually("lost") { !rig.model.rig.connected(vfo: 0) }
        await eventually("released over a fresh connection") {
            rig.rig.connectionCount > before && rig.rig.writes.last == "T 0"
        }
        await rig.model.rig.settle()
        #expect(!rig.model.rig.pluginPttUnconfirmed)
    }

    /// The quit waits for a release over a fresh connection before the rigs go.
    @Test func theQuitWaitsForTheFreshRelease() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        let before: Int = rig.rig.connectionCount
        let atDisconnect = Box<(pending: Bool, connections: Int)?>(nil)
        let rigModel: MCLAppModel.RigModel = rig.model.rig
        rigModel.beforeShutdownDisconnect = {
            atDisconnect.value = (!rigModel.pendingReleases.isEmpty, rig.rig.connectionCount)
        }
        await rigModel.shutdown()
        let state = try #require(atDisconnect.value)
        #expect(!state.pending, "the fresh release finished before the rigs were disconnected")
        #expect(state.connections > before)
        #expect(rig.rig.writes.filter { $0 == "T 0" }.count >= 2)
    }

    /// A PTT or a message never runs past the rest of the on-air budget.
    @Test func noTransmissionOutrunsTheBudget() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], cw: true)
        defer { rig.rig.stop() }
        // A 30 s PTT, the cool-down, then a 15 % budget (45 s) has 15 s left: the next PTT is cut after 15 s.
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.advance(by: 30_000)
        rig.advance(by: PluginWindowsModel.pttCooldownMs)
        await rig.model.rig.settle()
        rig.plugins.setDutyPercent(15)
        // 45 s budget, 30 used: 15 s left.
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        rig.advance(by: 14_000)
        await rig.model.rig.settle()
        #expect(rig.keyed.last == "T 1")
        rig.advance(by: 1_000)
        await rig.model.rig.settle()
        #expect(rig.keyed.last == "T 0")
        // Five minutes later the window is empty; 30 s of the 45 s budget used by a PTT leave 15 s for a message.
        rig.advance(by: 300_000)
        await rig.model.rig.settle()
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.advance(by: 30_000)
        rig.advance(by: PluginWindowsModel.pttCooldownMs)
        await rig.model.rig.settle()
        _ = await Self.ask(rig, "tx.sendCw", ["text": .string(String(repeating: "CQ ", count: 60))])
        await rig.keying.settle()
        let key: FakeCwKeyer = try #require(rig.keying.keying.lastKeyer)
        rig.advance(by: 14_000)
        await rig.keying.settle()
        #expect(key.events.last != "abort")
        rig.advance(by: 1_000)
        await rig.keying.settle()
        #expect(key.events.last == "abort")
    }

    /// The web view is rebuilt when the plugin's manifest changes (its identity changes).
    @Test func aChangedManifestRebuildsTheWebView() async throws {
        let rig = try await Self.make(permissions: ["read", "ui"], granted: [])
        defer { rig.rig.stop() }
        let before: String = rig.plugins.webIdentity(Self.key)
        let file: URL = rig.keying.app.dataDir.appendingPathComponent("plugins/web/plugin.json")
        let text: String = try String(contentsOf: file, encoding: .utf8)
        try text.replacingOccurrences(of: "\"process\":false", with: "\"process\":false,\"webInlineScripts\":true")
            .write(to: file, atomically: true, encoding: .utf8)
        await rig.plugins.rescan()
        #expect(rig.plugins.webIdentity(Self.key) != before)
        await rig.plugins.rescan()
        let again: String = rig.plugins.webIdentity(Self.key)
        await rig.plugins.rescan()
        #expect(rig.plugins.webIdentity(Self.key) == again)
    }

    // MARK: - fifth security review

    static func pttCommands(_ rig: Rig) -> [String] {
        rig.rig.commands.filter { $0.hasPrefix("T ") }
    }

    /// The repro: a poll held on the lane, a plugin `T 1` queued behind it, Esc. The fresh `T 0` goes first and must
    /// not confirm; the queued `T 1` is dropped before it is written; the lane `T 0` confirms.
    @Test func aQueuedKeyCannotOvertakeTheRelease() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        rig.rig.holdAnswer(to: "f")
        await eventually("poll held") { rig.rig.isHoldingAnswer }
        async let keyed: PluginJSON = Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        await eventually("T 1 queued on the lane") { rig.model.rig.pluginKeysInFlight[0] == 1 }
        _ = rig.model.entry.stopSending()
        await eventually("fresh T 0") { Self.pttCommands(rig).contains("T 0") }
        await rig.model.rig.settlePluginReleases()
        #expect(rig.model.rig.pluginPttUnconfirmed, "a fresh T 0 sent while a key was queued does not confirm")
        rig.rig.releaseAnswer()
        let answer: PluginJSON = await keyed
        #expect(answer["error"] != nil)
        await eventually("confirmed by the lane") { !rig.model.rig.pluginPttUnconfirmed }
        #expect(!Self.pttCommands(rig).contains("T 1"), "the stale key was dropped: \(Self.pttCommands(rig))")
        #expect(Self.pttCommands(rig).last == "T 0")
    }

    /// A key already on the wire when the release came: once it completes, another `T 0` follows at once.
    @Test func aKeyCompletingAfterARequestedReleaseIsReleasedAgain() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        rig.rig.holdAnswer(to: "T 1")
        // The rig layer itself (the plugin model re-checks after the key too, which would hide it).
        let model = rig.model.rig
        async let keyed: String? = model.pluginPtt(true)
        await eventually("T 1 on the wire") { rig.rig.isHoldingAnswer }
        #expect(model.releasePluginPtt())
        rig.rig.releaseAnswer()
        #expect(await keyed == "released meanwhile")
        // Besides the lane `T 0` queued behind the key, another release follows the late key.
        await eventually("released again after the key") {
            let commands = Self.pttCommands(rig)
            guard let key = commands.firstIndex(of: "T 1") else { return false }
            return commands[(key + 1)...].filter { $0 == "T 0" }.count >= 2 && !model.pluginPttUnconfirmed
        }
        #expect(Self.pttCommands(rig).last == "T 0")
        #expect(model.pluginPttRig == nil)
    }

    /// The rig drops after a key and every `T 0` fails: the release stays owed (no plugin keys) until the next
    /// connection's `T 0` gets through.
    @Test func aDroppedRigStaysOwedUntilItsNextConnection() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        // No timed retries and no fresh-connection release: only the next connection's lane `T 0` can confirm.
        rig.model.rig.releaseRetries = 0
        rig.model.rig.freshPttRelease = { _, _ in false }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.reject("T")
        rig.rig.dropNextRead()
        await eventually("lost") { !rig.model.rig.connected(vfo: 0) }
        await rig.model.rig.settle()
        #expect(rig.model.rig.pluginPttUnconfirmed)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["message"]
            == .string("an earlier PTT release is not confirmed yet"))
        rig.rig.unreject("T")
        rig.model.rig.toggle(vfo: 0)
        await eventually("confirmed on the next connection") {
            rig.model.rig.connected(vfo: 0) && !rig.model.rig.pluginPttUnconfirmed
        }
        #expect(Self.pttCommands(rig).last == "T 0")
    }

    /// The plugins' CAT connection closes when no plugin needs it (revoke, quit); queued commands of a revoked
    /// plugin are dropped; the queue is bounded.
    @Test func thePluginCatConnectionIsClosedAndBounded() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        let channel = try #require(rig.model.rig.pluginCat)
        // Held replies must not time out on a slow runner.
        channel.setReplyTimeout(ms: 120_000)
        _ = await Self.ask(rig, "cat.send", ["command": .string("f")])
        #expect(channel.isOpen)
        rig.plugins.setGrants("web", [])
        #expect(!channel.isOpen)
        rig.plugins.setGrants("web", ["cat"])
        // Queued commands of a revoked plugin are dropped.
        rig.rig.holdAnswer(to: "+f")
        async let first: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        async let second: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("m")])
        await eventually("second queued") { rig.model.rig.pluginCat?.pendingCount == 2 }
        rig.plugins.setGrants("web", [])
        rig.rig.releaseAnswer()
        _ = await first
        #expect(await second["error"] != nil)
        #expect(!rig.rig.commands.contains("+m"))
        // The bound.
        rig.rig.holdAnswer(to: "+f")
        let busy = Box<Int>(0)
        let done = Box<Int>(0)
        for _ in 0..<(PluginCatChannel.maxPending + 4) {
            rig.model.rig.sendRawCat("f") { result in
                if case .failure(let error) = result, error.message.hasPrefix("busy") { busy.value += 1 }
                done.value += 1
            }
        }
        await eventually("busy answered") { busy.value == 4 }
        rig.rig.releaseAnswer()
        await eventually("all answered") { done.value == PluginCatChannel.maxPending + 4 }
        // The quit closes it.
        _ = await Self.ask(rig, "cat.send", ["command": .string("f")])
        await rig.model.rig.shutdown()
        #expect(!channel.isOpen)
    }

    /// A refused lane `T 0` is retried while the rig stays connected; the retry confirms.
    @Test func aFailedLaneReleaseIsRetried() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.reject("T")
        _ = rig.model.entry.stopSending()
        await eventually("lane T 0 refused") { rig.model.rig.releaseAttempts[0] == 1 }
        #expect(rig.model.rig.pluginPttUnconfirmed)
        rig.rig.unreject("T")
        await eventually("retried and confirmed") { !rig.model.rig.pluginPttUnconfirmed }
        #expect(Self.pttCommands(rig).last == "T 0")
    }

    /// A key asked for after the operator stopped plugin transmissions never reaches the rig, even when it got past
    /// the plugin model's check before the stop.
    @Test func aKeyAfterTheOperatorsStopNeverReachesTheRig() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        _ = rig.model.entry.stopSending()
        #expect(rig.plugins.transmissionsBlocked)
        await eventually("release confirmed") { !rig.model.rig.pluginPttUnconfirmed }
        // The rig layer alone would key now; the operator's stop still holds.
        #expect(await rig.model.pluginKey(true) == "the operator stopped plugin transmissions")
        await rig.model.rig.settle()
        #expect(Self.pttCommands(rig).filter { $0 == "T 1" }.count == 1)
    }

    // MARK: - sixth security review

    /// A fresh-connection `T 0` of an older release never confirms a newer one: release #1 is confirmed on the lane
    /// while its fresh `T 0` is still on its way; a plugin keys, release #2 comes while that `T 1` is on the wire;
    /// the late fresh `T 0` of #1 must not clear #2.
    @Test func anOlderFreshReleaseNeverConfirmsANewerOne() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        let model = rig.model.rig
        let gate = NSCondition()
        let open = Box<Bool>(false)
        let done = Box<Int>(0)
        model.freshPttRelease = { _, _ in
            gate.lock()
            while !open.value { gate.wait() }
            done.value += 1
            gate.unlock()
            return true
        }
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await eventually("release #1 confirmed on the lane") { !model.pluginPttUnconfirmed }
        rig.rig.holdAnswer(to: "T 1")
        async let keyed: String? = model.pluginPtt(true)
        await eventually("T 1 on the wire") { rig.rig.isHoldingAnswer }
        #expect(model.releasePluginPtt())
        gate.withLock {
            open.value = true
            gate.broadcast()
        }
        await eventually("the fresh T 0s went out") { gate.withLock { done.value } == 2 }
        await model.settlePluginReleases()
        #expect(model.pluginPttUnconfirmed, "a fresh T 0 of release #1 confirmed release #2")
        rig.rig.releaseAnswer()
        _ = await keyed
        await eventually("confirmed after the key") { !model.pluginPttUnconfirmed }
        #expect(Self.pttCommands(rig).last == "T 0")
    }

    /// A rig whose `rigctld` refuses `T 0`: the owed release is not resent on every poll; after the quick retries the
    /// warning offers „Uvolnit znovu", which releases once the rig accepts.
    @Test func aRefusedReleaseDoesNotFloodTheRig() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        let model = rig.model.rig
        model.releaseRetries = 0
        model.releaseSlowRetryMs = 3_600_000
        #expect(await model.pluginPtt(true) == nil)
        rig.rig.reject("T")
        #expect(model.releasePluginPtt())
        await eventually("cannot confirm") { model.pluginPttCannotConfirm.contains(0) }
        await model.settle()
        let tried: Int = rig.rig.commands.filter { $0 == "T 0" }.count
        let polls: Int = rig.rig.commands.filter { $0 == "f" }.count
        await eventually("five more polls") { rig.rig.commands.filter { $0 == "f" }.count >= polls + 5 }
        #expect(rig.rig.commands.filter { $0 == "T 0" }.count == tried, "T 0 resent per poll")
        #expect(model.pluginPttUnconfirmed)
        rig.rig.unreject("T")
        model.retryPluginRelease()
        await eventually("released by hand") { !model.pluginPttUnconfirmed }
        #expect(model.pluginPttCannotConfirm.isEmpty)
    }

    /// After the quick retries a refused release is retried slowly, on the lane and over a fresh connection.
    @Test func aRefusedReleaseKeepsBeingRetriedSlowly() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        let model = rig.model.rig
        model.releaseRetries = 0
        model.releaseSlowRetryMs = 20
        let fresh = Box<Int>(0)
        let lock = NSLock()
        model.freshPttRelease = { _, _ in
            lock.withLock { fresh.value += 1 }
            return false
        }
        #expect(await model.pluginPtt(true) == nil)
        rig.rig.reject("T")
        #expect(model.releasePluginPtt())
        await eventually("retried on the lane") { rig.rig.commands.filter { $0 == "T 0" }.count >= 3 }
        await eventually("retried over a fresh connection") { lock.withLock { fresh.value } >= 3 }
        rig.rig.unreject("T")
        await eventually("confirmed by a slow retry") { !model.pluginPttUnconfirmed }
    }

    /// A plugin that loses `transmit` while its `T 1` waits on the lane: the key is dropped before it is written.
    @Test func aRevokeDropsAKeyStillQueued() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        rig.rig.holdAnswer(to: "f")
        await eventually("poll held") { rig.rig.isHoldingAnswer }
        async let keyed: PluginJSON = Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        await eventually("T 1 queued on the lane") { rig.model.rig.pluginKeysInFlight[0] == 1 }
        rig.plugins.setGrants("web", [])
        rig.rig.releaseAnswer()
        let answer: PluginJSON = await keyed
        #expect(answer["error"]?["code"] == .string("permission"))
        await eventually("confirmed") { !rig.model.rig.pluginPttUnconfirmed }
        #expect(!Self.pttCommands(rig).contains("T 1"), "\(Self.pttCommands(rig))")
    }

    /// The release epoch is per rig: a release of the second rig never drops a plugin key queued for the first.
    @Test func aReleaseOfTheOtherRigLeavesThisRigsKey() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer {
            rig.rig.releaseAnswer()
            rig.rig.stop()
        }
        let model = rig.model.rig
        #expect(model.lanes.count == 2)
        rig.rig.holdAnswer(to: "f")
        await eventually("poll held") { rig.rig.isHoldingAnswer }
        async let keyed: String? = model.pluginPtt(true)
        await eventually("T 1 queued on the lane") { model.pluginKeysInFlight[0] == 1 }
        model.requestRelease(1, waitForOperator: false)
        #expect(model.pluginKeyEpoch(0) == 0)
        rig.rig.releaseAnswer()
        #expect(await keyed == nil)
        #expect(Self.pttCommands(rig) == ["T 1"])
        #expect(model.pluginPttRig == 0)
        model.pluginPttOwed.remove(1)
        model.releasePluginPtt()
        await eventually("released") { !model.pluginPttUnconfirmed }
    }

    /// A plugin release never cuts the operator's own transmission on the rig: its `T 0` waits until that ended.
    @Test func aPluginReleaseWaitsForTheOperatorsTransmission() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        let model = rig.model.rig
        let operatorOn = Box<Bool>(false)
        model.operatorKeying = { _ in operatorOn.value }
        #expect(await model.pluginPtt(true) == nil)
        operatorOn.value = true
        // The plugin side's release (its own `off`, the time limit, a revoke, its end).
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(Self.pttCommands(rig) == ["T 1"], "the release cut the operator")
        #expect(model.pluginPttUnconfirmed)
        operatorOn.value = false
        await eventually("released after the operator") { !model.pluginPttUnconfirmed }
        #expect(Self.pttCommands(rig).last == "T 0")
        // Esc stops the operator's transmission too: its release never waits.
        rig.plugins.allowTransmissions()
        #expect(await model.pluginPtt(true) == nil)
        operatorOn.value = true
        _ = rig.model.entry.stopSending()
        await eventually("released at once") { Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed }
    }

    /// The quit drops queued plugin CAT and closes the plugin connection before the rigs disconnect.
    @Test func theQuitClosesThePluginCatConnectionFirst() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer { rig.rig.stop() }
        let channel = try #require(rig.model.rig.pluginCat)
        _ = await Self.ask(rig, "cat.send", ["command": .string("f")])
        #expect(channel.isOpen)
        let openAtDisconnect = Box<Bool?>(nil)
        rig.model.rig.beforeShutdownDisconnect = { openAtDisconnect.value = channel.isOpen }
        await rig.model.rig.shutdown()
        #expect(openAtDisconnect.value == false)
    }

    /// A rig that disconnects closes the plugin CAT connection (reopened with the next command).
    @Test func aRigDisconnectClosesThePluginCatConnection() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer { rig.rig.stop() }
        let channel = try #require(rig.model.rig.pluginCat)
        _ = await Self.ask(rig, "cat.send", ["command": .string("f")])
        #expect(channel.isOpen)
        rig.model.rig.toggle(vfo: 0)
        await eventually("disconnected") { !rig.model.rig.connected(vfo: 0) }
        await eventually("closed") { !channel.isOpen }
        rig.model.rig.toggle(vfo: 0)
        await eventually("connected") { rig.model.rig.connected(vfo: 0) }
        let again: PluginJSON = await Self.ask(rig, "cat.send", ["command": .string("f")])
        #expect(again["result"]?["code"] == .int(0))
        #expect(channel.isOpen)
    }

    /// A raw CAT command carries the epoch of its admission: a stop or revoke between admission and the rig drops it.
    @Test func aCatCommandCarriesItsAdmissionEpoch() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "cat"], granted: ["cat"])
        defer { rig.rig.stop() }
        let admitted: Int = rig.model.rig.pluginCatEpoch.withLock { $0 }
        rig.model.rig.pluginCatIdle(close: false)
        let result = await PluginRpc.answer(method: "cat.send", params: ["command": .string("m")], permissions: ["cat"],
                                            context: rig.plugins.context, catEpoch: admitted)
        guard case .failure(let failure) = result else {
            Issue.record("sent although stopped since its admission")
            return
        }
        #expect(failure.message == "cancelled by a stop or release")
        #expect(!rig.rig.commands.contains("+m"))
    }

    // MARK: - seventh security review

    /// Esc and „Uvolnit znovu" never wait for the operator; a release waits at most the PTT time limit.
    @Test func aWaitingReleaseIsOverriddenAndBounded() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        let model = rig.model.rig
        model.operatorKeying = { _ in true }
        model.pluginReleaseDeferralLimitMs = { 3_600_000 }
        // Esc.
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(Self.pttCommands(rig) == ["T 1"])
        _ = rig.model.entry.stopSending()
        await eventually("Esc released") { Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed }
        await model.settle()
        // „Uvolnit znovu".
        rig.plugins.allowTransmissions()
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(Self.pttCommands(rig).last == "T 1")
        model.retryPluginRelease()
        await eventually("released by hand") { Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed }
        await model.settle()
        // The bound.
        model.pluginReleaseDeferralLimitMs = { 30 }
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await eventually("released after the limit") {
            Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed
        }
    }

    /// The end of the operator's transmission is seen at once (no poll).
    @Test func aWaitingReleaseFollowsTheOperatorAndTheConnection() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        let model = rig.model.rig
        let flag = OperatorFlag()
        flag.on = true
        model.operatorKeying = { _ in flag.on }
        model.pluginReleaseDeferralLimitMs = { 3_600_000 }
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(model.pluginReleaseDeferred.contains(0))
        flag.on = false
        await eventually("released when the operator ended") {
            Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed
        }
    }

    /// A rig lost while a release waits for the operator: released at once (over a fresh connection).
    @Test func aWaitingReleaseGoesWhenTheRigIsLost() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"], pollIntervalMs: 50)
        defer { rig.rig.stop() }
        let model = rig.model.rig
        model.operatorKeying = { _ in true }
        model.pluginReleaseDeferralLimitMs = { 3_600_000 }
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(model.pluginReleaseDeferred.contains(0))
        rig.rig.dropNextRead()
        await eventually("lost") { !model.connected(vfo: 0) }
        await eventually("released on the disconnect") {
            Self.pttCommands(rig).last == "T 0" && !model.pluginPttUnconfirmed
        }
        #expect(model.pluginReleaseDeferred.isEmpty)
    }

    /// The footswitch's end releases a plugin release that waited for it; the quit releases one still waiting before
    /// the rigs disconnect.
    @Test func theFootswitchEndAndTheQuitReleaseAWaitingRelease() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        let model = rig.model.rig
        model.pluginReleaseDeferralLimitMs = { 3_600_000 }
        #expect(await model.pluginPtt(true) == nil)
        model.footswitchPttRig = 0
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(model.pluginReleaseDeferred.contains(0))
        model.footswitch(false)
        await eventually("released after the footswitch") { !model.pluginPttUnconfirmed }
        #expect(Self.pttCommands(rig).suffix(2) == ["T 0", "T 0"])
        // The quit.
        model.operatorKeying = { _ in true }
        rig.plugins.allowTransmissions()
        #expect(await model.pluginPtt(true) == nil)
        #expect(model.releasePluginPtt())
        await model.settle()
        #expect(model.pluginReleaseDeferred.contains(0))
        // The quit's transmit release (before anything disconnects).
        model.closeTransmit()
        await model.settle()
        #expect(model.pluginReleaseDeferred.isEmpty)
        #expect(Self.pttCommands(rig).last == "T 0")
        #expect(!model.pluginPttUnconfirmed)
    }
}

@Observable @MainActor
final class OperatorFlag {
    var on = false
}
