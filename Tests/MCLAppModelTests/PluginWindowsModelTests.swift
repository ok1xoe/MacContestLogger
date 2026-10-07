import Darwin
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

        #expect(try Self.value(await Self.answer("contest.multipliers", context: context)) == .null)
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

    // MARK: - review fixes

    static func pid(_ dir: URL) -> Int32? {
        lines(dir.appendingPathComponent("pid")).first.flatMap { Int32($0) }
    }

    static func alive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// Closing the window of a plugin that ignores `SIGTERM` still ends it: the model holds the stopped process
    /// until it exits, and the kill fallback fires.
    @Test func closingTheWindowEndsAStubbornPlugin() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.plugin(app, body: """
            trap '' TERM
            echo $$ > pid
            IFS= read -r hello
            \(Self.setText("up"))
            exec sleep 600
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("up") { Self.shownText(model.session("demo")) == "up" }
        let pid: Int32 = try #require(Self.pid(dir))
        model.windowClosed(Self.key)
        #expect(model.retiring.count == 1)
        await eventually("killed and reaped") { model.retiring.isEmpty && !Self.alive(pid) }
        #expect(model.session("demo")?.phase == .stopped)
    }

    /// A late exit of an earlier run never touches a later run, even when the session was replaced because the
    /// manifest changed (one generation counter for every run).
    @Test func aLateExitOfAnEarlierRunLeavesTheNewRunAlone() async throws {
        let app = try await IntegrationApp.make()
        let body: String = "trap '' TERM\nIFS= read -r hello\n" + Self.setText("up") + "\nexec sleep 600"
        try Self.plugin(app, body: body)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("first run") { Self.shownText(model.session("demo")) == "up" }
        // A changed manifest (another permission set), then close and reopen: a new session object.
        try Self.plugin(app, permissions: ["ui", "read"], body: "IFS= read -r hello\n" + Self.setText("second")
                        + "\n" + Self.echoLoop)
        await model.rescan()
        model.windowClosed(Self.key)
        model.open(Self.key)
        await eventually("second run") { Self.shownText(model.session("demo")) == "second" }
        await eventually("the first run ended") { model.retiring.isEmpty }
        await drainMainQueue()
        #expect(model.session("demo")?.phase == .running)
        await model.shutdown()
    }

    /// A plugin flooding `set` and `log`: the latest content wins, the messages stay within the run's budget, and
    /// the hops to the main actor stay far below the number of lines.
    @Test func aFloodingPluginIsCoalescedAndBounded() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, body: """
            IFS= read -r hello
            i=0
            while [ $i -lt 3000 ]; do
              echo '{"type":"set","window":"main","content":{"elements":[{"type":"text","text":"busy"}]}}'
              echo '{"type":"log","text":"line"}'
              i=$((i + 1))
            done
            \(Self.setText("last"))
            \(Self.echoLoop)
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        let inbox: PluginInbox = try #require(model.session("demo")?.inbox)
        await eventually("answered") { model.session("demo")?.phase == .running }
        // The render throttle runs on the manual clock: let it render whatever is pending until the last content
        // (the hello timeout is past once the plugin answered).
        await eventually("last content") {
            app.integrationClock.advance(by: PluginWindowsModel.renderIntervalMs)
            return Self.shownText(model.session("demo")) == "last"
        }
        let lines: Int = Self.texts(app).filter { $0 == "[demo] line" }.count
        // (the messages window keeps only its latest lines, so the count is bounded rather than exact here)
        #expect(lines > 0 && lines <= PluginWindowsModel.outputLinesPerRun)
        #expect(Self.texts(app).contains("[demo] další výstup pluginu se nezobrazuje"))
        #expect(inbox.hopCount < 6_000)
        await model.shutdown()
    }

    /// The inbox, driven from the main thread without letting the main queue run: one hop for any number of
    /// messages, the latest `set` per window, the output budget applied before the hop.
    @Test func theInboxCoalescesIntoOneHop() async {
        let delivered = Box<[PluginInbox.Batch]>([])
        let inbox = PluginInbox(outputBudget: 3) { batch in delivered.value.append(batch) }
        for index in 0..<1_000 {
            inbox.receive(.set(window: "main", content: PluginUIContent(elements: [.text(String(index), style: .normal)])))
        }
        inbox.receive(.set(window: "side", content: PluginUIContent()))
        for _ in 0..<10 {
            inbox.receive(.log("x"))
            inbox.stderr("e")
        }
        inbox.protocolError("bad")
        inbox.protocolError("bad")
        #expect(inbox.hopCount == 1)
        await drainMainQueue()
        #expect(delivered.value.count == 1)
        let batch: PluginInbox.Batch = delivered.value[0]
        #expect(batch.sets.map(\.window) == ["main", "side"])
        #expect(batch.sets.first?.content.elements == [.text("999", style: .normal)])
        #expect(batch.items == [.output("x"), .output("e"), .output("x"), .outputSuppressed, .protocolError("bad")])
    }

    /// Past `maxQueued` messages the reader blocks until the main actor took them (the plugin's output pauses).
    @Test func theInboxPausesTheReaderWhenFull() async {
        let delivered = Box<Int>(0)
        let inbox = PluginInbox(outputBudget: 10) { batch in delivered.value += batch.items.count }
        let sent = OSAllocatedUnfairLock(initialState: 0)
        let reader = Thread {
            for index in 0..<(PluginInbox.maxQueued + 10) {
                inbox.receive(.request(id: .int(Int64(index)), method: "log.count", params: [:]))
                sent.withLock { $0 += 1 }
            }
        }
        reader.start()
        // The main actor is held here (no await): no hop can run, so the reader must stop at the limit.
        while sent.withLock({ $0 }) < PluginInbox.maxQueued {
            sched_yield()
        }
        for _ in 0..<10_000 {
            sched_yield()
        }
        #expect(sent.withLock { $0 } == PluginInbox.maxQueued)
        #expect(delivered.value == 0)
        await eventually("all delivered") { delivered.value == PluginInbox.maxQueued + 10 }
        #expect(sent.withLock { $0 } == PluginInbox.maxQueued + 10)
        inbox.close()
    }

    /// At most `maxRequestsInFlight` requests are answered at a time; the rest get `busy` at once.
    @Test func requestsBeyondTheCapAreBusy() async throws {
        let app = try await IntegrationApp.make()
        let dir: URL = try Self.plugin(app, body: """
            IFS= read -r hello
            for i in 1 2 3 4 5 6; do echo "{\\"type\\":\\"request\\",\\"id\\":$i,\\"method\\":\\"log.count\\"}"; done
            \(Self.echoLoop)
            """)
        // Hold the logbook queue so the first requests stay in flight.
        let release = DispatchSemaphore(value: 0)
        let holding = OSAllocatedUnfairLock(initialState: false)
        let handle: LogbookHandle = app.model.database.handle
        let blocker = Task.detached {
            try? await handle.run { _ in
                holding.withLock { $0 = true }
                release.wait()
            }
        }
        await eventually("queue held") { holding.withLock { $0 } }
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        let log: URL = dir.appendingPathComponent("in.log")
        await eventually("two busy answers") { Self.lines(log).count == 2 }
        let busy: [PluginJSON] = Self.lines(log).compactMap(Self.json)
        #expect(busy.allSatisfy { $0["error"]?["code"] == .string("busy") })
        #expect(Set(busy.compactMap { $0["id"]?.intValue }) == [5, 6])
        release.signal()
        await blocker.value
        await eventually("all six answered") { Self.lines(log).count == 6 }
        #expect(Self.lines(log).compactMap(Self.json).filter { $0["result"]?["count"] != nil }.count == 4)
        await model.shutdown()
    }

    /// A plugin that closes its own input is not hung: the app stops sending, the window keeps working.
    @Test func aPluginClosingItsInputIsNotHung() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, events: ["qso-logged"], body: """
            IFS= read -r hello
            exec 0<&-
            \(Self.setText("no input"))
            exec sleep 600
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("up") { Self.shownText(model.session("demo")) == "no input" }
        for _ in 0..<5 {
            app.plugins.fire(.qsoLogged, json: "{}")
            model.click(Self.key, target: "x")
        }
        let connection = try #require(model.session("demo")?.connection as? PluginProcess)
        await connection.settleInput()
        model.click(Self.key, target: "x")
        await drainMainQueue()
        #expect(model.session("demo")?.phase == .running)
        await model.shutdown()
    }

    /// `set` needs the `ui` permission.
    @Test func setWithoutTheUiPermissionIsIgnored() async throws {
        let app = try await IntegrationApp.make()
        try Self.plugin(app, permissions: ["read"], body: """
            IFS= read -r hello
            \(Self.setText("forbidden"))
            echo '{"type":"log","text":"after"}'
            \(Self.echoLoop)
            """)
        let model: PluginWindowsModel = app.model.pluginWindows
        await model.rescan()
        model.open(Self.key)
        await eventually("log seen") { Self.texts(app).contains("[demo] after") }
        await eventually("reported") { Self.texts(app).contains("[demo] chyba protokolu: set needs the ui permission") }
        #expect(model.session("demo")?.contents["main"] == nil)
        await model.shutdown()
    }
}

/// A mutable value for closures of one test.
final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
