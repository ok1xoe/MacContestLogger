import Foundation
@testable import MCLAppModel
@testable import MCLCore
import os
import Testing

/// Window plugins in the app: tiny `/bin/sh` plugins in the test's own data directory (never the user's), started
/// through the real launcher. Every wait is on something the plugin wrote or the model shows; the hello timeout and
/// the render throttle run on the test's manual clock.
@MainActor @Suite struct PluginWindowsModelTests {

    static let key = "plugin:demo/main"

    /// Logs every input line after `hello` into `in.log` (in the plugin's directory, its working directory).
    static let echoLoop = #"while IFS= read -r line; do printf '%s\n' "$line" >> in.log; done"#

    static func setText(_ text: String) -> String {
        #"echo '{"type":"set","window":"main","content":{"elements":[{"type":"text","text":""# + text + #""}]}}'"#
    }

    /// Writes `plugins/<name>/plugin.json` and the executable `run`.
    @discardableResult
    static func plugin(_ app: IntegrationApp, name: String = "demo", events: [String] = [],
                       permissions: [String] = ["read", "ui"], body: String) throws -> URL {
        let dir: URL = app.app.dataDir.appendingPathComponent("plugins/" + name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest: PluginJSON = .object([
            "protocol": .int(1), "name": .string(name), "permissions": .array(permissions.map { .string($0) }),
            "events": .array(events.map { .string($0) }),
            "windows": .array([.object(["id": .string("main"), "title": .string("Demo " + name)])]),
        ])
        try manifest.serialized().write(to: dir.appendingPathComponent("plugin.json"), atomically: true,
                                        encoding: .utf8)
        let run: URL = dir.appendingPathComponent("run")
        try ("#!/bin/sh\n" + body + "\n").write(to: run, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: run.path)
        return dir
    }

    static func lines(_ file: URL) -> [String] {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    static func json(_ line: String) -> PluginJSON? {
        try? PluginJSON.parse(line)
    }

    static func texts(_ app: IntegrationApp) -> [String] {
        app.model.messages.lines.map(\.text)
    }

    static func shownText(_ session: PluginSession?) -> String? {
        guard case .text(let text, _)? = session?.contents["main"]?.elements.first else { return nil }
        return text
    }

    // MARK: - lifecycle

    @Test func openingAWindowStartsThePluginWhichGetsHelloAndShowsItsContent() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.plugin(app, body: """
            IFS= read -r hello
            printf '%s\\n' "$hello" > hello.json
            \(Self.setText("hi"))
            \(Self.echoLoop)
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        #expect(model.menuWindows.map(\.key) == [Self.key])
        #expect(model.menuWindows.map(\.title) == ["Demo demo"])
        #expect(model.session("demo") == nil)

        model.open(Self.key)
        #expect(app.model.windows.isOpen(Self.key))
        await eventually("content") { Self.shownText(model.session("demo")) == "hi" }
        #expect(model.session("demo")?.phase == .running)
        #expect(model.banner(Self.key) == nil)
        let hello: PluginJSON = try #require(Self.lines(dir.appendingPathComponent("hello.json")).first.flatMap(Self.json))
        #expect(hello["type"] == .string("hello"))
        #expect(hello["protocol"] == .int(1))
        #expect(hello["windows"] == .array([.string("main")]))
        #expect(hello["contest"] == .null)

        // The user closes the only window: the plugin stops, no banner; opening again starts a new run.
        model.windowClosed(Self.key)
        #expect(!app.model.windows.isOpen(Self.key))
        #expect(model.session("demo")?.phase == .stopped)
        model.open(Self.key)
        await eventually("running again") { model.session("demo")?.phase == .running }
        await model.shutdown()
    }

    /// The window ids are kept in `openWindows` (so they reopen at start); a restored window starts its plugin
    /// once the directory was read.
    @Test func aRestoredWindowStartsAfterTheScan() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, body: "IFS= read -r hello\n" + Self.setText("restored") + "\n" + Self.echoLoop)
        let model: PluginWindowsModel = app.model.pluginWindows
        model.open(Self.key)
        let saved: AppConfig = await app.app.savedConfigFlushed()
        #expect(saved.openWindows.contains(Self.key))
        await model.rescan()
        await eventually("started by the scan") { Self.shownText(model.session("demo")) == "restored" }
        await model.shutdown()
    }

    @Test func eventsGoOnlyToSubscribersAndClicksComeBack() async throws {
        let app = try await IntegrationApp.make()
        let body: String = "IFS= read -r hello\n" + Self.setText("up") + "\n" + Self.echoLoop
        let subscribed: URL = try Self.plugin(app, name: "sub", events: ["qso-logged", "spot-received"], body: body)
        let other: URL = try Self.plugin(app, name: "other", body: body)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open("plugin:sub/main")
        model.open("plugin:other/main")
        await eventually("both up") {
            Self.shownText(model.session("sub")) == "up" && Self.shownText(model.session("other")) == "up"
        }
        app.plugins.fire(.qsoLogged, json: #"{"call":"OK1ABC"}"#)
        app.model.dxCluster.pluginSpot(DxSpot(spotter: "OK1XYZ", freqHz: 14_025_000, dxCall: "DL1AA", comment: ""))
        model.click("plugin:other/main", target: "bands", row: 2, rowId: "r40")
        model.click("plugin:sub/main", target: "go")

        let subLog: URL = subscribed.appendingPathComponent("in.log")
        let otherLog: URL = other.appendingPathComponent("in.log")
        await eventually("sub heard everything") { Self.lines(subLog).count == 3 }
        await eventually("other got its click") { !Self.lines(otherLog).isEmpty }
        let events: [PluginJSON] = Self.lines(subLog).compactMap(Self.json)
        #expect(events[0]["type"] == .string("event"))
        #expect(events[0]["event"] == .string("qso-logged"))
        #expect(events[0]["data"]?["call"] == .string("OK1ABC"))
        #expect(events[1]["event"] == .string("spot-received"))
        #expect(events[1]["data"]?["dxCall"] == .string("DL1AA"))
        #expect(events[2]["type"] == .string("ui"))
        // The events were queued before the click: had they gone to the other plugin, they would precede it.
        let click: PluginJSON = try #require(Self.lines(otherLog).first.flatMap(Self.json))
        #expect(Self.lines(otherLog).count == 1)
        #expect(click["type"] == .string("ui"))
        #expect(click["window"] == .string("main"))
        #expect(click["action"] == .string("click"))
        #expect(click["target"] == .string("bands"))
        #expect(click["row"] == .int(2))
        #expect(click["rowId"] == .string("r40"))
        await model.shutdown()
    }

    @Test func aCrashKeepsTheContentWithABannerAndRestartRunsItAgain() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, body: #"""
            n=$(cat count 2>/dev/null || echo 0)
            n=$((n + 1))
            echo $n > count
            IFS= read -r hello
            echo "{\"type\":\"set\",\"window\":\"main\",\"content\":{\"elements\":[{\"type\":\"text\",\"text\":\"run $n\"}]}}"
            exit 3
            """#)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("ended") { model.session("demo")?.phase == .exited(3) }
        #expect(Self.shownText(model.session("demo")) == "run 1")
        #expect(model.banner(Self.key) == "Plugin skončil (kód 3)")
        #expect(model.session("demo")?.canRestart == true)
        #expect(Self.texts(app).contains("[demo] Plugin skončil (kód 3)"))

        model.restart("demo")
        app.integrationClock.advance(by: PluginWindowsModel.renderIntervalMs)
        await eventually("second run") { Self.shownText(model.session("demo")) == "run 2" }
        await eventually("ended again") { model.session("demo")?.phase == .exited(3) }
        await model.shutdown()
    }

    /// No answer to `hello` within 10 s of the (manual) clock: the plugin is stopped as hung.
    @Test func aPluginThatNeverAnswersIsHung() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, body: Self.echoLoop)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        #expect(model.session("demo")?.phase == .starting)
        app.integrationClock.advance(by: PluginWindowsModel.helloTimeoutMs - 1)
        #expect(model.session("demo")?.phase == .starting)
        app.integrationClock.advance(by: 1)
        #expect(model.session("demo")?.phase == .hung)
        #expect(model.banner(Self.key) == "Plugin neodpovídá — byl zastaven")
        #expect(Self.texts(app).contains("[demo] Plugin neodpovídá — byl zastaven"))
        #expect(model.session("demo")?.canRestart == true)
    }

    /// A plugin that answers but never reads its input: once its unread input passes the limit it is hung.
    @Test func aPluginThatStopsReadingIsHung() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, events: ["qso-logged"], body: """
            echo '{"type":"ready"}'
            exec sleep 600
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("ready") { model.session("demo")?.phase == .running }
        let big: String = "{\"pad\":\"" + String(repeating: "x", count: 100_000) + "\"}"
        for _ in 0..<(2 * PluginProcess.maxPendingInputBytes / 100_000) {
            app.plugins.fire(.qsoLogged, json: big)
        }
        await eventually("hung") { model.session("demo")?.phase == .hung }
    }

    @Test func malformedLinesAreReportedOnceAndIgnored() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, body: """
            IFS= read -r hello
            echo 'not json'
            echo 'not json'
            echo '{"type":"set","window":"nope","content":{"elements":[]}}'
            echo '{"type":"log","text":"hello from the plugin"}'
            echo 'oops' >&2
            \(Self.setText("still fine"))
            \(Self.echoLoop)
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("content") { Self.shownText(model.session("demo")) == "still fine" }
        await eventually("stderr shown") { Self.texts(app).contains("[demo] oops") }
        let texts: [String] = Self.texts(app)
        #expect(texts.filter { $0 == "[demo] chyba protokolu: malformed JSON" }.count == 1)
        #expect(texts.contains("[demo] chyba protokolu: set for an unknown window nope"))
        #expect(texts.contains("[demo] hello from the plugin"))
        #expect(model.session("demo")?.phase == .running)
        await model.shutdown()
    }

    @Test func aPermissionThisVersionLacksIsRefused() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.plugin(app, permissions: ["read", "ui", "transmit"],
                                       body: "touch started\n" + Self.echoLoop)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        let refusal = "[demo] Plugin vyžaduje oprávnění, které tato verze neumí: transmit"
        #expect(Self.texts(app).contains(refusal))
        model.open(Self.key)
        #expect(model.session("demo")?.phase == .refused(["transmit"]))
        #expect(model.banner(Self.key) == "Plugin vyžaduje oprávnění, které tato verze neumí: transmit")
        #expect(model.session("demo")?.canRestart == false)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("started").path))
        // A second scan does not repeat the message.
        await model.rescan()
        #expect(Self.texts(app).filter { $0 == refusal }.count == 1)
    }

    @Test func underTheInertSwitchesNothingStarts() async throws {
        let app = try await IntegrationApp.make(adjust: { environment in
            environment.network.plugins = .inert
        })
        let dir: URL = try Self.plugin(app, body: "touch started\n" + Self.echoLoop)
        let model: PluginWindowsModel = app.model.pluginWindows
        #expect(!model.isActive)
        await model.rescan()
        model.open(Self.key)
        #expect(model.session("demo")?.phase == .disabled)
        #expect(model.banner(Self.key) == "Pluginy jsou v tomto režimu vypnuté")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("started").path))
    }

    @Test func aMissingPluginHasABanner() async throws {
        let app = try await IntegrationApp.make()
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open("plugin:gone/main")
        #expect(model.banner("plugin:gone/main") == "Plugin gone nebyl nalezen")
        #expect(model.title("plugin:gone/main") == "gone")
    }

    /// The quit: the subscribers hear `app-quitting`, every input is closed, and a plugin that ignores both the end
    /// of its input and `SIGTERM` is killed after the grace — the quit is not held by it.
    @Test func theQuitStopsEveryPlugin() async throws {
        let app = try await IntegrationApp.make()
        let polite: URL = try Self.plugin(app, name: "polite", events: ["app-quitting"],
                                          body: "IFS= read -r hello\n" + Self.setText("up") + "\n" + Self.echoLoop)
        try Self.plugin(app, name: "stubborn", body: """
            trap '' TERM
            IFS= read -r hello
            \(Self.setText("up"))
            exec sleep 600
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        model.quitGraceMs = 100
        await model.rescan()
        model.open("plugin:polite/main")
        model.open("plugin:stubborn/main")
        await eventually("both up") {
            Self.shownText(model.session("polite")) == "up" && Self.shownText(model.session("stubborn")) == "up"
        }
        let connections: [any PluginConnection] = ["polite", "stubborn"].compactMap { model.session($0)?.connection }
        #expect(connections.count == 2)
        await app.model.shutdown()
        // The quit's wait is bounded; the exits themselves are awaited here (a slow runner may lag behind).
        for connection in connections {
            await connection.waitForExit()
        }
        #expect(connections.allSatisfy { !$0.isRunning })
        let quitting: PluginJSON? = Self.lines(polite.appendingPathComponent("in.log")).first.flatMap(Self.json)
        #expect(quitting?["event"] == .string("app-quitting"))
        // Windows closing during the quit are not the user's: the ids stay for the next start.
        #expect(app.model.windows.isOpen("plugin:polite/main"))
    }

    // MARK: - requests

    @Test func requestsAreAnsweredThroughTheProcess() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        let dir: URL = try Self.plugin(app, body: """
            IFS= read -r hello
            printf '%s\\n' "$hello" > hello.json
            echo '{"type":"request","id":1,"method":"log.count"}'
            echo '{"type":"request","id":"b","method":"no.such"}'
            echo '{"type":"request","id":3,"method":"log.query","params":{"band":"20m"}}'
            echo '{"type":"request","id":4,"method":"log.query","params":{"contest":"sideways"}}'
            \(Self.echoLoop)
            """)
        let reads = OSAllocatedUnfairLock<[Bool]>(initialState: [])
        let model: PluginWindowsModel = app.model.pluginWindows
        model.readProbe = { onMain in reads.withLock { $0.append(onMain) } }
        await model.rescan()
        model.open(Self.key)
        let log: URL = dir.appendingPathComponent("in.log")
        await eventually("four answers") { Self.lines(log).count == 4 }
        let answers: [String: PluginJSON] = Dictionary(uniqueKeysWithValues: Self.lines(log).compactMap { line in
            Self.json(line).flatMap { json in json["id"].map { ($0.serialized(), json) } }
        })
        #expect(answers["1"]?["result"]?["count"] == .int(1))
        #expect(answers["\"b\""]?["error"]?["code"] == .string("unknown_method"))
        #expect(answers["3"]?["result"]?["qsos"]?.arrayValue?.first?["call"] == .string("OK1ABC"))
        #expect(answers["3"]?["result"]?["total"] == .int(1))
        #expect(answers["4"]?["error"]?["code"] == .string("invalid_params"))
        #expect(model.session("demo")?.phase == .running)
        let hello: PluginJSON? = Self.lines(dir.appendingPathComponent("hello.json")).first.flatMap(Self.json)
        #expect(hello?["contest"]?["id"] != nil)
        // Both database reads (the invalid request reads nothing) ran off the main thread.
        #expect(reads.withLock { $0 } == [false, false])
        await model.shutdown()
    }

    static func context(handle: LogbookHandle) -> PluginHostContext {
        var context = PluginHostContext()
        context.handle = { handle }
        context.rig = { PluginRigState(radio: 1, freqHz: 7_025_000, mode: "CW", catConnected: false) }
        context.spots = {
            [DxSpot(spotter: "A", freqHz: 14_025_000, dxCall: "DL1AA", comment: "cq"),
             DxSpot(spotter: "B", freqHz: 7_010_000, dxCall: "OH2BB", comment: "")]
        }
        return context
    }

    static func answer(_ method: String, _ params: [String: PluginJSON] = [:], permissions: [String] = ["read", "ui"],
                       context: PluginHostContext) async -> Result<PluginJSON, PluginRpc.Failure> {
        await PluginRpc.answer(method: method, params: params, permissions: permissions, context: context)
    }

    static func value(_ result: Result<PluginJSON, PluginRpc.Failure>) throws -> PluginJSON {
        // The raw answers are parsed back as a plugin reads them.
        try PluginJSON.parse(try result.get().serialized())
    }

    @Test func everyReadMethodAnswersFromAnInMemoryLogbook() async throws {
        let handle: LogbookHandle = try LogbookHandle.inMemory()
        var uuids: [String] = []
        for (call, band) in [("OK1ABC", Band.m20), ("DL1XYZ", Band.m40), ("OK2DEF", Band.m20)] {
            var qso = Qso()
            qso.call = call
            qso.band = band
            qso.mode = .cw
            qso.uuid = UUID().uuidString
            qso.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000)
            uuids.append(qso.uuid)
            _ = try handle.withDatabase { try $0.repository.insert(&qso) }
        }
        let context: PluginHostContext = Self.context(handle: handle)

        let query = try Self.value(await Self.answer("log.query", ["band": .string("20m")], context: context))
        #expect(query["qsos"]?.arrayValue?.compactMap { $0["call"]?.stringValue } == ["OK1ABC", "OK2DEF"])
        #expect(query["qsos"]?.arrayValue?.first?["freqHz"] != nil)
        #expect(query["total"] == .int(2))
        let page = try Self.value(await Self.answer("log.query", ["limit": .int(1), "order": .string("desc")],
                                                    context: context))
        #expect(page["qsos"]?.arrayValue?.count == 1)
        #expect(page["total"] == .int(3))
        #expect(try Self.value(await Self.answer("log.count", ["call": .string("OK")], context: context))["count"]
            == .int(2))
        #expect(try Self.value(await Self.answer("log.get", ["uuid": .string(uuids[1])], context: context))["call"]
            == .string("DL1XYZ"))
        #expect(try Self.value(await Self.answer("log.get", ["uuid": .string("nope")], context: context)) == .null)
        #expect(try Self.value(await Self.answer("contest.active", context: context)) == .null)
        #expect(try Self.value(await Self.answer("contest.score", context: context)) == .null)
        let rig = try Self.value(await Self.answer("rig.state", context: context))
        #expect(rig["band"] == .string("40m"))
        #expect(rig["radio"] == .int(1))
        #expect(rig["mode"] == .string("CW"))
        let spots = try Self.value(await Self.answer("spots.list", ["band": .string("20m")], context: context))
        #expect(spots["spots"]?.arrayValue?.compactMap { $0["dxCall"]?.stringValue } == ["DL1AA"])

        #expect(await Self.answer("contest.multipliers", context: context) == .failure(PluginRpc.Failure(
            code: "not_implemented", message: "contest.multipliers is not available in protocol 1 yet")))
        #expect(await Self.answer("cat.send", context: context) == .failure(PluginRpc.Failure(
            code: "unknown_method", message: "unknown method cat.send")))
        #expect(await Self.answer("log.count", permissions: ["ui"], context: context) == .failure(PluginRpc.Failure(
            code: "permission", message: "log.count needs the read permission")))
        #expect(await Self.answer("log.get", context: context) == .failure(PluginRpc.Failure(
            code: "invalid_params", message: "log.get needs a uuid")))
        #expect(await Self.answer("log.count", context: PluginHostContext()) == .failure(PluginRpc.Failure(
            code: "unavailable", message: "no logbook is open")))
    }

    @Test func theScoreIsTheScoreWindowsBreakdown() async throws {
        let app = try await IntegrationApp.make()
        try await app.app.startCqWwCw()
        await app.app.logContestQso(call: "OK1ABC", zone: "15")
        await app.app.logContestQso(call: "W1AW", zone: "5", freqKHz: "7025")
        let context: PluginHostContext = app.model.pluginWindows.context
        let active = try Self.value(await Self.answer("contest.active", context: context))
        #expect(active["id"] == .string(try #require(app.model.contest.activeId)))
        let score = try Self.value(await Self.answer("contest.score", context: context))
        let state: ScoreState = try #require(app.model.contest.score)
        #expect(score["qsos"] == .int(Int64(state.qsoCount)))
        #expect(score["total"] == .int(state.total))
        #expect(score["mults"] == .int(Int64(state.multTotal)))
        #expect(score["bands"]?.arrayValue?.compactMap { $0["band"]?.stringValue } == ["40m", "20m"])
        #expect(score["bands"]?.arrayValue?.compactMap { $0["qsos"]?.intValue }.reduce(0, +) == 2)
        let rig = try Self.value(await Self.answer("rig.state", context: context))
        #expect(rig["freqHz"] == .int(7_025_000))
    }

    // MARK: - content

    /// At most one render per interval: the first `set` shows at once, a burst shows its latest content once
    /// at the end of the interval, an idle interval renders nothing.
    @Test func rendersAreThrottled() throws {
        let clock = ManualClock()
        let package = PluginPackage(manifest: try PluginManifest.parse(
            Array(#"{"protocol":1,"windows":[{"id":"main"}]}"#.utf8), directoryName: "demo"),
                                    directory: "/x", executable: "/x/run")
        let session = PluginSession(package: package)
        func content(_ text: String) -> PluginUIContent {
            PluginUIContent(elements: [.text(text, style: .normal)])
        }
        session.receive(window: "main", content: content("1"), clock: clock)
        #expect(session.renderCount == 1)
        #expect(Self.shownText(session) == "1")
        session.receive(window: "main", content: content("2"), clock: clock)
        session.receive(window: "main", content: content("3"), clock: clock)
        #expect(session.renderCount == 1)
        clock.advance(by: PluginWindowsModel.renderIntervalMs - 1)
        #expect(session.renderCount == 1)
        clock.advance(by: 1)
        #expect(session.renderCount == 2)
        #expect(Self.shownText(session) == "3")
        clock.advance(by: PluginWindowsModel.renderIntervalMs)
        #expect(session.renderCount == 2)
        #expect(clock.pendingCount == 0)
        session.receive(window: "main", content: content("4"), clock: clock)
        #expect(session.renderCount == 3)
        #expect(Self.shownText(session) == "4")
    }

    /// A toggle flips in the shown content at once (also inside tabs) and the plugin hears `change`.
    @Test func togglesFlipAtOnceAndAreSent() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.plugin(app, body: """
            IFS= read -r hello
            echo '{"type":"set","window":"main","content":{"elements":[{"type":"toggle","id":"cw","label":"CW","value":false},{"type":"tabs","id":"t","tabs":[{"id":"a","elements":[{"type":"toggle","id":"ssb","value":true}]}]}]}}'
            \(Self.echoLoop)
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("content") { model.session("demo")?.contents["main"] != nil }
        model.toggle(Self.key, target: "cw", value: true)
        model.toggle(Self.key, target: "ssb", value: false)
        model.selectTab(Self.key, target: "t", tab: "a")
        let elements: [PluginUIElement] = try #require(model.session("demo")?.contents["main"]?.elements)
        #expect(elements[0] == .toggle(id: "cw", label: "CW", value: true))
        #expect(elements[1] == .tabs(id: "t", tabs: [PluginUITab(id: "a", title: "a", elements: [
            .toggle(id: "ssb", label: "ssb", value: false),
        ])]))
        let log: URL = dir.appendingPathComponent("in.log")
        await eventually("three events") { Self.lines(log).count == 3 }
        let sent: [PluginJSON] = Self.lines(log).compactMap(Self.json)
        #expect(sent[0]["action"] == .string("change"))
        #expect(sent[0]["value"] == .bool(true))
        #expect(sent[1]["target"] == .string("ssb"))
        #expect(sent[2]["action"] == .string("select"))
        #expect(sent[2]["value"] == .string("a"))
        await model.shutdown()
    }
}
