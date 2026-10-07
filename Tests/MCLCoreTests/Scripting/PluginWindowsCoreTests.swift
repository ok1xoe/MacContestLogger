import Darwin
import Foundation
import os
import Testing
@testable import MCLCore

/// Window plugins (protocol 1): the manifest and the catalog, the JSON-lines codec, the declarative content, the
/// log-query filters and the streaming process (tiny `/bin/sh` scripts in a temporary directory).
@Suite struct PluginManifestTests {

    static func manifest(_ json: String, dir: String = "demo") throws -> PluginManifest {
        try PluginManifest.parse(Array(json.utf8), directoryName: dir)
    }

    @Test func aValidManifestIsRead() throws {
        let manifest = try Self.manifest("""
            {"protocol":1,"name":"QSOs by band","version":"1.0","permissions":["read","ui"],
             "events":["qso-logged","contest-opened"],"run":"run.py",
             "windows":[{"id":"main","title":"By band","size":[400,300]},{"id":"second"}]}
            """)
        #expect(manifest.id == "demo")
        #expect(manifest.name == "QSOs by band")
        #expect(manifest.version == "1.0")
        #expect(manifest.permissions == ["read", "ui"])
        #expect(manifest.events == ["qso-logged", "contest-opened"])
        #expect(manifest.run == "run.py")
        #expect(manifest.windows.count == 2)
        #expect(manifest.window("main")?.title == "By band")
        #expect(manifest.window("main")?.width == 400)
        #expect(manifest.window("second")?.title == "QSOs by band")
        #expect(manifest.window("second")?.width == nil)
        #expect(manifest.unsupportedPermissions.isEmpty)
    }

    @Test func defaultsAreTheDirectoryNameAndRun() throws {
        let manifest = try Self.manifest(#"{"protocol":1,"windows":[{"id":"main"}]}"#)
        #expect(manifest.name == "demo")
        #expect(manifest.run == "run")
        #expect(manifest.permissions.isEmpty)
    }

    /// A permission this version does not grant parses (the plugin is listed), but is named as unsupported, so the
    /// plugin is never started.
    @Test func anUnknownPermissionIsReportedNotDropped() throws {
        let manifest = try Self.manifest(
            #"{"protocol":1,"permissions":["read","ui","cat","transmit"],"windows":[{"id":"main"}]}"#)
        #expect(manifest.unsupportedPermissions == ["cat", "transmit"])
    }

    @Test(arguments: [
        (#"{"protocol":2,"windows":[{"id":"main"}]}"#, "plugin.json: protokol %s, tato verze umí jen %s"),
        (#"{"windows":[{"id":"main"}]}"#, "plugin.json: chybí číslo protokolu"),
        (#"{"protocol":1}"#, "plugin.json: chybí okna (windows)"),
        (#"{"protocol":1,"windows":[]}"#, "plugin.json: chybí okna (windows)"),
        (#"{"protocol":1,"windows":[{"title":"x"}]}"#, "plugin.json: okno bez platného id"),
        (#"{"protocol":1,"windows":[{"id":"a"},{"id":"a"}]}"#, "plugin.json: okno %s je uvedeno dvakrát"),
        (#"{"protocol":1,"events":["qso-typed"],"windows":[{"id":"a"}]}"#, "plugin.json: neznámá událost %s"),
        (#"{"protocol":1,"events":"qso-logged","windows":[{"id":"a"}]}"#, "plugin.json: %s musí být seznam textů"),
        (#"{"protocol":1,"run":"../evil","windows":[{"id":"a"}]}"#,
         "plugin.json: neplatná cesta ke spustitelnému souboru %s"),
        (#"{"protocol":1,"run":"/bin/sh","windows":[{"id":"a"}]}"#,
         "plugin.json: neplatná cesta ke spustitelnému souboru %s"),
        ("[1,2]", "plugin.json není platný JSON objekt"),
        ("{not json", "plugin.json není platný JSON objekt"),
    ])
    func badManifestsAreRefused(json: String, key: String) {
        #expect(throws: ContestMessage.self) { try Self.manifest(json) }
        do {
            _ = try Self.manifest(json)
        } catch {
            #expect((error as? ContestMessage)?.key == key)
        }
    }

    @Test func windowKeysRoundTrip() {
        let key: String = PluginCatalog.windowKey(plugin: "qso-by-band", window: "main")
        #expect(key == "plugin:qso-by-band/main")
        #expect(PluginCatalog.parseWindowKey(key)?.plugin == "qso-by-band")
        #expect(PluginCatalog.parseWindowKey(key)?.window == "main")
        #expect(PluginCatalog.parseWindowKey("rate") == nil)
        #expect(PluginCatalog.parseWindowKey("plugin:../x/main") == nil)
        #expect(PluginCatalog.parseWindowKey("plugin:x") == nil)
    }

    /// The event plugins (`plugins/<event>/`) and the window plugins (`plugins/<name>/plugin.json`) never see each
    /// other: the catalog skips directories without a manifest and refuses an event name with one; the event runner
    /// lists only the event directories.
    @Test func legacyEventDirectoriesAndWindowPluginsAreSeparate() throws {
        let root: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(root) }
        ScriptingFixture.script(root + "/qso-logged", "legacy.sh", "#!/bin/sh\necho legacy\n")
        ScriptingFixture.mkdirs(root + "/contest-opened")
        ScriptingFixture.write(root + "/contest-opened/plugin.json",
                               Array(#"{"protocol":1,"windows":[{"id":"main"}]}"#.utf8))
        ScriptingFixture.mkdirs(root + "/byband")
        ScriptingFixture.write(root + "/byband/plugin.json",
                               Array(#"{"protocol":1,"name":"By band","windows":[{"id":"main"}]}"#.utf8))
        ScriptingFixture.script(root + "/byband", "run", "#!/bin/sh\nexit 0\n")
        ScriptingFixture.mkdirs(root + "/broken")
        ScriptingFixture.write(root + "/broken/plugin.json", Array("{".utf8))
        ScriptingFixture.mkdirs(root + "/notes")

        let scan: PluginCatalog.Scan = PluginCatalog.scan(root: root)
        #expect(scan.packages.map(\.id) == ["byband"])
        #expect(scan.packages.first?.executable == root + "/byband/run")
        #expect(scan.problems.map(\.plugin) == ["broken", "contest-opened"])
        #expect(scan.problems.last?.message.key == "název adresáře je vyhrazen pro událostní pluginy")

        let runner = PluginRunner(root: root, timeoutMs: 10_000)
        #expect(runner.plugins(.qsoLogged) == [root + "/qso-logged/legacy.sh"])
        #expect(runner.plugins(.contestOpened).isEmpty)
        #expect(PluginCatalog.reservedNames.count == PluginRunner.Event.allCases.count)
        #expect(PluginCatalog.reservedNames.contains("qso-logged"))
    }

    @Test func aMissingPluginsDirectoryIsEmpty() {
        let scan = PluginCatalog.scan(root: "/nonexistent/mcl-plugins")
        #expect(scan.packages.isEmpty && scan.problems.isEmpty)
    }
}

@Suite struct PluginWireProtocolTests {

    static func lines(_ outputs: [PluginLineFramer.Output]) -> [String] {
        outputs.compactMap { output in
            if case .line(let bytes) = output { return String(decoding: bytes, as: UTF8.self) }
            return nil
        }
    }

    @Test func linesAreSplitAcrossReads() {
        var framer = PluginLineFramer()
        #expect(Self.lines(framer.feed(Array("{\"a\":1}\n{\"b\"".utf8))) == ["{\"a\":1}"])
        #expect(Self.lines(framer.feed(Array(":2}\r\n\n   \n{\"c\":3}".utf8))) == ["{\"b\":2}"])
        #expect(Self.lines(framer.finish()) == ["{\"c\":3}"])
    }

    /// A line over the limit is dropped whole, reported once, and the next line is read normally.
    @Test func anOverlongLineIsDroppedAndTheStreamGoesOn() {
        var framer = PluginLineFramer(limit: 16)
        var outputs: [PluginLineFramer.Output] = framer.feed(Array(String(repeating: "x", count: 10).utf8))
        outputs += framer.feed(Array(String(repeating: "y", count: 10).utf8))
        outputs += framer.feed(Array("zzz\n{\"ok\":1}\n".utf8))
        #expect(outputs.filter { $0 == .overflow }.count == 1)
        #expect(Self.lines(outputs) == ["{\"ok\":1}"])
        #expect(PluginLineFramer.maxLineBytes == 1_048_576)
    }

    @Test func inboundMessagesAreDecoded() throws {
        #expect(try PluginInbound.decode(Array(#"{"type":"ready"}"#.utf8)) == .ready)
        #expect(try PluginInbound.decode(Array(#"{"type":"log","text":"hi"}"#.utf8)) == .log("hi"))
        #expect(try PluginInbound.decode(Array(#"{"type":"future"}"#.utf8)) == .unknown("future"))
        let request = try PluginInbound.decode(Array(
            #"{"type":"request","id":7,"method":"log.count","params":{"band":"20m"}}"#.utf8))
        #expect(request == .request(id: .int(7), method: "log.count", params: ["band": .string("20m")]))
        let set = try PluginInbound.decode(Array(
            #"{"type":"set","window":"main","content":{"elements":[{"type":"text","text":"Hi","style":"title"}]}}"#
                .utf8))
        #expect(set == .set(window: "main", content: PluginUIContent(elements: [.text("Hi", style: .title)])))
    }

    @Test(arguments: [
        "{not json", "[1]", #"{"text":"no type"}"#, #"{"type":"set","window":"main"}"#,
        #"{"type":"set","window":"main","content":[]}"#, #"{"type":"request","method":"log.count"}"#,
        #"{"type":"request","id":{},"method":"x"}"#, #"{"type":"request","id":1}"#,
    ])
    func malformedLinesAreErrors(line: String) {
        #expect(throws: PluginJSON.ParseError.self) { try PluginInbound.decode(Array(line.utf8)) }
    }

    @Test func invalidUtf8IsAnError() {
        #expect(throws: PluginJSON.ParseError.self) {
            try PluginInbound.decode([0x7B, 0x22, 0xFF, 0x22, 0x3A, 0x31, 0x7D])
        }
    }

    static func qso(_ call: String) -> Qso {
        var qso = Qso()
        qso.call = call
        return qso
    }

    @Test func outboundLinesAreSingleLineJson() throws {
        let hello: String = PluginOutbound.hello(PluginOutbound.Hello(
            appVersion: "0.9.0", contestId: "cqww-cw", contestName: "CQ WW\nCW", band: "20m", mode: "CW",
            windows: ["main"], permissions: ["read", "ui"]))
        #expect(!hello.contains("\n"))
        let parsed: PluginJSON = try PluginJSON.parse(hello)
        #expect(parsed["type"] == .string("hello"))
        #expect(parsed["protocol"] == .int(1))
        #expect(parsed["app"]?["version"] == .string("0.9.0"))
        #expect(parsed["contest"]?["id"] == .string("cqww-cw"))
        #expect(parsed["contest"]?["name"] == .string("CQ WW\nCW"))
        #expect(parsed["windows"] == .array([.string("main")]))
        let none: PluginJSON = try PluginJSON.parse(PluginOutbound.hello(PluginOutbound.Hello(
            appVersion: nil, contestId: nil, contestName: nil, band: nil, mode: nil, windows: [], permissions: [])))
        #expect(none["contest"] == .null)

        let event: String = PluginOutbound.event("qso-logged", json: PluginEventJson.qsoLogged(Self.qso("OK1ABC")))
        #expect(event.hasPrefix("{\"data\":{\"time\":"))
        #expect(try PluginJSON.parse(event)["data"]?["call"] == .string("OK1ABC"))

        let ui = try PluginJSON.parse(PluginOutbound.ui(window: "main", action: "click", target: "log", row: 3,
                                                        rowId: nil))
        #expect(ui["row"] == .int(3))
        #expect(ui["rowId"] == .null)
        #expect(ui["value"] == nil)
        let error = try PluginJSON.parse(PluginOutbound.error(id: .string("a"), code: "permission", message: "no"))
        #expect(error["error"]?["code"] == .string("permission"))
        #expect(try PluginJSON.parse(PluginOutbound.response(id: .int(1), result: .raw("[1,2]")))["result"]
            == .array([.int(1), .int(2)]))
    }

    @Test func jsonValuesRoundTrip() throws {
        let value: PluginJSON = .object([
            "s": .string("a\"b\\c\u{1}é😀"), "i": .int(-5), "d": .double(1.5), "w": .double(3), "b": .bool(true),
            "n": .null, "a": .array([.int(1), .string("x")]),
        ])
        let parsed: PluginJSON = try PluginJSON.parse(value.serialized())
        #expect(parsed["s"] == .string("a\"b\\c\u{1}é😀"))
        #expect(parsed["i"] == .int(-5))
        #expect(parsed["d"] == .double(1.5))
        #expect(parsed["w"]?.intValue == 3)
        #expect(parsed["b"] == .bool(true))
        #expect(parsed["n"] == .null)
        #expect(parsed["a"] == .array([.int(1), .string("x")]))
    }
}

@Suite struct PluginUIContentTests {

    static func content(_ elements: String) throws -> PluginUIContent {
        try PluginUIContent.parse(try PluginJSON.parse("{\"elements\":" + elements + "}"))
    }

    @Test func everyElementTypeIsRead() throws {
        let content = try Self.content("""
            [{"type":"text","text":"Score","style":"title"},
             {"type":"text","text":"careful","style":"warn"},
             {"type":"table","id":"bands","columns":["Band",{"title":"QSOs","align":"right"}],
              "rows":[["20m",12],{"id":"r40","cells":["40m",{"text":"3","style":"mult"}],"style":"dupe"}]},
             {"type":"list","id":"calls","items":["OK1ABC",{"id":"x","text":"DL1XX","style":"new"}]},
             {"type":"button","id":"refresh","label":"Refresh"},
             {"type":"button","id":"off","label":"Off","enabled":false},
             {"type":"toggle","id":"cw","label":"CW only","value":true},
             {"type":"progress","value":30,"max":20,"label":"Goal"},
             {"type":"tabs","id":"t","tabs":[{"id":"a","title":"A","elements":[{"type":"text","text":"in A"}]},
                                            {"title":"B","elements":[]}]}]
            """)
        #expect(content.warnings.isEmpty)
        #expect(content.elements.count == 9)
        #expect(content.elements[0] == .text("Score", style: .title))
        #expect(content.elements[1] == .text("careful", style: .warn))
        let table = PluginUITable(id: "bands", columns: [
            PluginUIColumn(title: "Band", alignRight: false), PluginUIColumn(title: "QSOs", alignRight: true),
        ], rows: [
            PluginUIRow(id: nil, cells: [PluginUICell(text: "20m", style: .normal), PluginUICell(text: "12", style: .normal)],
                        style: .normal),
            PluginUIRow(id: "r40", cells: [PluginUICell(text: "40m", style: .normal), PluginUICell(text: "3", style: .mult)],
                        style: .dupe),
        ], truncated: false)
        #expect(content.elements[2] == .table(table))
        #expect(content.elements[3] == .list(PluginUIList(id: "calls", items: [
            PluginUIListItem(id: nil, text: "OK1ABC", style: .normal), PluginUIListItem(id: "x", text: "DL1XX", style: .new),
        ])))
        #expect(content.elements[4] == .button(id: "refresh", label: "Refresh", enabled: true))
        #expect(content.elements[5] == .button(id: "off", label: "Off", enabled: false))
        #expect(content.elements[6] == .toggle(id: "cw", label: "CW only", value: true))
        #expect(content.elements[7] == .progress(value: 20, max: 20, label: "Goal"))
        #expect(content.elements[8] == .tabs(id: "t", tabs: [
            PluginUITab(id: "a", title: "A", elements: [.text("in A", style: .normal)]),
            PluginUITab(id: "1", title: "B", elements: []),
        ]))
    }

    /// What this version does not understand is left out with a warning, the rest is shown.
    @Test func unknownPartsAreLeftOutWithWarnings() throws {
        let content = try Self.content("""
            [{"type":"canvas"},{"text":"no type"},{"type":"button"},{"type":"text","text":"x","style":"rainbow"},
             {"type":"text","text":"kept"}]
            """)
        #expect(content.elements == [.text("x", style: .normal), .text("kept", style: .normal)])
        #expect(content.warnings.count == 4)
    }

    @Test func tablesAreCutAtTheRowLimit() throws {
        let rows: String = "[" + (0...PluginUIContent.maxRows).map { "[\"\($0)\"]" }.joined(separator: ",") + "]"
        let content = try Self.content("[{\"type\":\"table\",\"rows\":" + rows + "}]")
        guard case .table(let table) = content.elements.first else {
            Issue.record("no table")
            return
        }
        #expect(table.rows.count == PluginUIContent.maxRows)
        #expect(table.truncated)
        #expect(content.warnings.count == 1)
    }

    @Test func tabsNestOnlySoDeep() throws {
        var elements: String = "[{\"type\":\"text\",\"text\":\"deep\"}]"
        for _ in 0...PluginUIContent.maxDepth {
            elements = "[{\"type\":\"tabs\",\"tabs\":[{\"id\":\"a\",\"elements\":" + elements + "}]}]"
        }
        let content = try Self.content(elements)
        #expect(content.warnings.contains { $0.contains("nested") })
    }
}

@Suite struct PluginLogQueryTests {

    static func qso(_ call: String, band: Band, mode: Mode, minute: Int) -> Qso {
        var qso = Qso()
        qso.call = call
        qso.band = band
        qso.mode = mode
        qso.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000 + Double(minute * 60))
        return qso
    }

    static let log: [Qso] = [
        qso("OK1ABC", band: .m20, mode: .cw, minute: 0), qso("DL1XYZ", band: .m40, mode: .cw, minute: 1),
        qso("OK2DEF", band: .m20, mode: .ssb, minute: 2), qso("OM3ABC", band: .m20, mode: .cw, minute: 3),
    ]

    @Test func filtersCombine() throws {
        var query = try PluginLogQuery.parse(["band": .string("20m"), "mode": .string("cw")])
        #expect(query.apply(Self.log).page.map(\.call) == ["OK1ABC", "OM3ABC"])
        query = try PluginLogQuery.parse(["call": .string("ok")])
        #expect(query.apply(Self.log).page.map(\.call) == ["OK1ABC", "OK2DEF"])
        query = try PluginLogQuery.parse(["callContains": .string("abc"), "order": .string("desc")])
        #expect(query.apply(Self.log).page.map(\.call) == ["OM3ABC", "OK1ABC"])
        query = try PluginLogQuery.parse(["since": .string("2026-09-21T14:14:00Z"), "until": .string("2026-09-21T14:16:00Z")])
        #expect(query.apply(Self.log).page.map(\.call) == ["DL1XYZ", "OK2DEF"])
        query = try PluginLogQuery.parse(["limit": .int(1), "offset": .int(1)])
        let result = query.apply(Self.log)
        #expect(result.page.map(\.call) == ["DL1XYZ"])
        #expect(result.total == 4)
        #expect(try PluginLogQuery.parse(["contest": .string("all")]).scope == .all)
        #expect(try PluginLogQuery.parse([:]).scope == .active)
        #expect(try PluginLogQuery.parse(["limit": .int(1_000_000)]).limit == PluginLogQuery.maxLimit)
    }

    @Test(arguments: [
        ["contest": PluginJSON.string("other")], ["since": .string("yesterday")], ["limit": .int(-1)],
        ["offset": .string("2")], ["order": .string("up")],
    ])
    func badParametersAreRefused(params: [String: PluginJSON]) {
        #expect(throws: PluginLogQuery.Invalid.self) { try PluginLogQuery.parse(params) }
    }
}

/// The streaming process: lines are delivered while the plugin runs, stdin is written while it reads, stderr and the
/// exit code come back. Each wait is a signal (an `AsyncStream` of what the handlers saw), never a sleep.
@Suite(.ioSafetyNet) struct PluginProcessTests {

    enum Seen: Equatable, Sendable {
        case message(PluginInbound)
        case error(String)
        case stderr(String)
        case exited(Int32)
    }

    static func process(_ dir: String, _ body: String) -> (PluginProcess, AsyncStream<Seen>) {
        ScriptingFixture.script(dir, "run", "#!/bin/sh\n" + body + "\n")
        let (stream, continuation) = AsyncStream<Seen>.makeStream()
        let handlers = PluginProcess.Handlers(
            message: { continuation.yield(.message($0)) }, protocolError: { continuation.yield(.error($0)) },
            stderr: { continuation.yield(.stderr($0)) },
            exited: { code in
                continuation.yield(.exited(code))
                continuation.finish()
            })
        return (PluginProcess(executable: dir + "/run", directory: dir, environment: ["MCL_X": "42"],
                              handlers: handlers), stream)
    }

    @Test func linesFlowBothWaysWhileThePluginRuns() async throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        let (process, stream) = Self.process(dir, """
            echo '{"type":"ready"}'
            read line
            echo "{\\"type\\":\\"log\\",\\"text\\":\\"$MCL_X $(pwd -P)\\"}"
            echo 'not json'
            echo 'oops' >&2
            read rest
            exit 4
            """)
        try process.start()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .message(.ready))
        #expect(process.isRunning)
        #expect(process.send("{\"type\":\"event\"}"))
        // Stdout and stderr are separate pipes: their lines may come in either order.
        var rest: [Seen] = []
        var sentEnd = false
        while let seen = await iterator.next() {
            rest.append(seen)
            let logged: Bool = rest.contains { if case .message(.log) = $0 { return true } else { return false } }
            if !sentEnd && logged && rest.contains(.stderr("oops")) && rest.contains(.error("malformed JSON")) {
                sentEnd = true
                process.closeInput()
            }
        }
        // The environment variable reached the plugin, and it runs in its own directory.
        let text: String? = rest.compactMap { seen -> String? in
            if case .message(.log(let text)) = seen { return text }
            return nil
        }.first
        #expect(text?.hasPrefix("42 /") == true)
        #expect(text?.hasSuffix("/" + (dir as NSString).lastPathComponent) == true)
        #expect(rest.contains(.error("malformed JSON")))
        #expect(rest.last == .exited(4))
        #expect(!process.isRunning)
        #expect(!process.send("late"))
    }

    /// `terminate` ends a plugin that ignores `SIGTERM` and its input's end with `SIGKILL` after the grace.
    @Test func terminateEscalatesToKill() async throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        let (process, stream) = Self.process(dir, """
            trap '' TERM
            echo '{"type":"ready"}'
            exec sleep 600
            """)
        try process.start()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .message(.ready))
        process.terminate(graceMs: 100)
        await process.waitForExit()
        #expect(!process.isRunning)
        var last: Seen?
        while let seen = await iterator.next() {
            last = seen
        }
        #expect(last == .exited(128 + SIGKILL))
    }

    @Test func aMissingExecutableDoesNotStart() throws {
        let process = PluginProcess(executable: "/nonexistent/run", directory: "/", environment: [:],
                                    handlers: PluginProcess.Handlers(message: { _ in }, protocolError: { _ in },
                                                                     stderr: { _ in }, exited: { _ in }))
        #expect(throws: ProcessRunnerError.self) { try process.start() }
        #expect(!process.send("x"))
    }
}
