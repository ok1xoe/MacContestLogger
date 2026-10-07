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
        #expect(rig.rig.writes == ["T 1", "T 0"], "the second on neither re-keyed nor extended: \(rig.rig.writes)")
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

    /// A refused `T 1` is followed by `T 0` and reported to the plugin; without a rig the PTT is refused.
    @Test func aFailedKeyIsReleasedAndReported() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit"], granted: ["transmit"])
        defer { rig.rig.stop() }
        rig.rig.reject("T")
        let answer: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(answer["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        // `T 1` refused → `T 0` at once; that was refused too, so the rig stays recorded as keyed and Esc sends `T 0`
        // again.
        #expect(rig.rig.commands.filter { $0.hasPrefix("T ") } == ["T 1", "T 0"])
        #expect(rig.model.rig.pluginPttRig == 0)
        // The time limit still runs for it.
        #expect(rig.plugins.pttHolder == "web")
        _ = rig.model.entry.stopSending()
        await rig.model.rig.settle()
        // Esc: `T 0` on the rig's lane (refused again), then over a fresh connection (refused too): owed, and said.
        await eventually("fresh release tried") {
            rig.rig.commands.filter { $0.hasPrefix("T ") } == ["T 1", "T 0", "T 0", "T 0"]
        }
        await eventually("told") {
            rig.model.status.message == "PTT pluginu se nepodařilo uvolnit — zkontroluj vysílač!"
        }
        #expect(rig.model.rig.pluginPttRig == nil)
        #expect(rig.plugins.pttHolder == nil)
        rig.plugins.allowTransmissions()
        // No rig: refused, nothing recorded.
        rig.model.rig.toggle(vfo: 0)
        await eventually("disconnected") { !rig.model.rig.connected(vfo: 0) }
        let noRig: PluginJSON = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        #expect(noRig["error"]?["message"] == .string("no rig connected"))
        #expect(rig.model.rig.pluginPttRig == nil)
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
        #expect(rig.rig.writes == ["T 1"])
        #expect(rig.plugins.pttHolder == "web")
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(false)])
        await rig.model.rig.settle()
        #expect(rig.rig.writes == ["T 1", "T 0"])
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
        #expect(rig.rig.writes == ["T 1", "T 0"])
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
        #expect(rig.rig.writes == ["T 1", "T 0"])
        rig.plugins.allowTransmissions()
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["result"] != nil)
        rig.plugins.stopTransmission()
        #expect(rig.plugins.transmissionsBlocked)
        #expect(await Self.ask(rig, "tx.ptt", ["on": .bool(true)])["error"]?["code"] == .string("refused"))
        await rig.model.rig.settle()
        #expect(rig.rig.writes == ["T 1", "T 0", "T 1", "T 0"])
        // Esc without a plugin on the air blocks nothing.
        rig.plugins.allowTransmissions()
        _ = rig.model.entry.stopSending()
        #expect(!rig.plugins.transmissionsBlocked)
    }

    /// Plugin CAT commands queued before a stop are dropped: the safety `T 0` never waits behind them.
    @Test func aStopJumpsQueuedPluginCat() async throws {
        let rig = try await Self.make(permissions: ["read", "ui", "transmit", "cat"], granted: ["transmit", "cat"])
        defer { rig.rig.stop() }
        _ = await Self.ask(rig, "tx.ptt", ["on": .bool(true)])
        rig.rig.holdAnswer(to: "+f")
        async let first: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("f")])
        await eventually("held") { rig.rig.isHoldingAnswer }
        async let second: PluginJSON = Self.ask(rig, "cat.send", ["command": .string("m")])
        await drainMainQueue()
        _ = rig.model.entry.stopSending()
        rig.rig.releaseAnswer()
        _ = await first
        let dropped: PluginJSON = await second
        #expect(dropped["error"]?["message"] == .string("cancelled by a stop or release"))
        // The `T 0` goes out on the lane or, when Esc closed the stalled connection, over a fresh one.
        await eventually("released") { rig.rig.commands.contains("T 0") }
        let commands: [String] = rig.rig.commands.filter { $0.hasPrefix("+") || $0.hasPrefix("T ") }
        #expect(commands == ["T 1", "+f", "T 0"])
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
}
