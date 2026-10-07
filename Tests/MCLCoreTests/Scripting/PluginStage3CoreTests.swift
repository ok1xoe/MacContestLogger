import Foundation
import Testing
@testable import MCLCore

/// Window plugins, the transmitting part: the raw CAT policy and command, the web window's manifest, load policy and
/// content rules.
@Suite(.ioSafetyNet) struct PluginStage3CoreTests {

    @Test func theCatPolicyIsAnExactGrammar() {
        for allowed in ["f", "F 14025000", "m", "M USB 2400", "V VFOA", "s", "S 1 VFOB", "I 14030000", "j", "J 100",
                        "Z -50", "l KEYSPD", "l RFPOWER", "L KEYSPD 28", "L AF 0.5", "t", "y", "Y 1 0", "\\get_freq",
                        "\\get_level KEYSPD"] {
            #expect(PluginCatPolicy.refusal(allowed) == nil, "\(allowed) must be allowed")
        }
        for refused in [
            // Smuggled words: rigctld reads a stream of words.
            "f T 1", "L RFPOWER 0.5 T 1", "F 14025000 T 1", "m T", "\\get_freq T 1",
            // Missing words would swallow the app's next command.
            "L", "F", "M USB", "S 1", "V", "J", "Y 1",
            // Keying, raw bytes, tuner, power, daemon, dumps.
            "T 1", "\\set_ptt 1", "b CQ TEST", "\\send_morse CQ", "w FA;", "W FA; 0", "q", "Q", "\\halt",
            "G TUNE", "U TUNER 1", "L TUNE 1", "L RFPOWER 0.5", "L RFPOWER 1", "1", "_", "\\dump_caps",
            "\\dump_state", "\\chk_vfo", "\\set_freq 14025000", "\\send_voice_mem 1",
            // Separators and forms.
            "+f", ";f", "|f", "f;T 1", "f|T 1", "f \\set_ptt 1", "f\nT 1", "f\r", "", "   ",
            // Values.
            "F 100", "F 99999999999", "F abc", "M MORSE 0", "M USB -1", "V VFOZ", "J 200000", "L KEYSPD 200",
            "L AF 2", "Y 9 0", String(repeating: "f", count: 121), "ř",
        ] {
            #expect(PluginCatPolicy.refusal(refused) != nil, "\(refused.debugDescription) must be refused")
        }
        let transmitting = PluginCatPolicy.Context(transmitting: true, transverter: false)
        #expect(PluginCatPolicy.refusal("Y 2 0", context: transmitting) != nil)
        #expect(PluginCatPolicy.refusal("f", context: transmitting) == nil)
        let transverter = PluginCatPolicy.Context(transmitting: false, transverter: true)
        #expect(PluginCatPolicy.refusal("F 144050000", context: transverter) != nil)
        #expect(PluginCatPolicy.refusal("I 144050000", context: transverter) != nil)
        #expect(PluginCatPolicy.refusal("m", context: transverter) == nil)
    }

    /// A reply longer than the limit is never left in the socket: the connection is closed.
    @Test func anOverlongRawReplyClosesTheConnection() async throws {
        let long: [String] = (0..<1_000).map { "line \($0) " + String(repeating: "x", count: 40) } + ["RPRT 0"]
        let medium: [String] = (0..<100).map { "line \($0)" } + ["RPRT 0"]
        let server = try FakeLineServer(lines: ["+\\dump_caps": long, "+f": medium])
        defer { server.stop() }
        let port: Int = server.port
        let outcome: (Int, Bool, Bool) = try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, log: CatTrafficLog(maxLines: 10))
            defer { client.close() }
            let lines: Int = try client.sendRaw("f").lines.count
            var threw = false
            do {
                _ = try client.sendRaw("\\dump_caps")
            } catch {
                threw = true
            }
            return (lines, threw, client.isConnected())
        }
        #expect(outcome.0 == 100)
        #expect(outcome.1)
        #expect(!outcome.2)
    }

    /// A raw command goes out in the extended form and comes back as its lines and `RPRT` code; both directions are
    /// in the CAT log.
    @Test func aRawCommandReturnsItsLinesAndCode() async throws {
        let server = try FakeLineServer(lines: [
            "+f": ["get_freq:", "Frequency: 14074000", "RPRT 0"],
            "+V": ["set_vfo: VFOB", "RPRT -11"],
        ])
        defer { server.stop() }
        let port: Int = server.port
        let log = CatTrafficLog(maxLines: 1000)
        let replies: [RigRawReply] = try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, log: log)
            defer { client.close() }
            return [try client.sendRaw("f"), try client.sendRaw("V VFOB")]
        }
        #expect(replies[0] == RigRawReply(lines: ["get_freq:", "Frequency: 14074000"], code: 0))
        #expect(replies[1] == RigRawReply(lines: ["set_vfo: VFOB"], code: -11))
        #expect(server.allCommands == ["+f", "+V VFOB"])
        #expect(log.snapshot().contains { $0.contains("+f") })
        #expect(log.snapshot().contains { $0.contains("Frequency: 14074000") })
    }

    @Test func webWindowsInTheManifest() throws {
        func manifest(_ json: String) throws -> PluginManifest {
            try PluginManifest.parse(Array(json.utf8), directoryName: "demo")
        }
        let web = try manifest("""
            {"protocol":1,"process":false,"permissions":["read","ui","cat","transmit"],"webHosts":["api.example.org"],
             "windows":[{"id":"map","kind":"web","page":"web/index.html"},{"id":"main"}]}
            """)
        #expect(!web.hasProcess)
        #expect(web.window("map")?.page == "web/index.html")
        #expect(web.window("main")?.isWeb == false)
        #expect(web.webHosts == ["api.example.org"])
        #expect(web.unsupportedPermissions.isEmpty)
        #expect(PluginManifest.offByDefault.isSuperset(of: ["cat", "transmit", "spots.send"]))
        for bad in [
            #"{"protocol":1,"windows":[{"id":"m","kind":"web","page":"../x.html"}]}"#,
            #"{"protocol":1,"windows":[{"id":"m","kind":"web","page":"x.js"}]}"#,
            #"{"protocol":1,"windows":[{"id":"m","kind":"web"}]}"#,
            #"{"protocol":1,"windows":[{"id":"m","kind":"canvas"}]}"#,
            #"{"protocol":1,"webHosts":["https://x.org"],"windows":[{"id":"m"}]}"#,
            #"{"protocol":1,"process":false,"windows":[{"id":"m"}]}"#,
            #"{"protocol":1,"process":false,"actions":[{"id":"a"}],"windows":[{"id":"m","kind":"web","page":"i.html"}]}"#,
        ] {
            #expect(throws: ContestMessage.self, "\(bad)") { try manifest(bad) }
        }
        #expect(try manifest(#"{"protocol":1,"webInlineScripts":true,"windows":[{"id":"m","kind":"web","page":"i.html"}]}"#)
            .webInlineScripts)
    }

    @Test func theWebPolicyKeepsThePageInItsDirectory() throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        ScriptingFixture.mkdirs(dir + "/plugin/web")
        ScriptingFixture.write(dir + "/plugin/web/index.html", Array("<p>".utf8))
        let plugin: String = dir + "/plugin"
        let hosts = ["api.example.org"]
        func url(_ text: String) -> URL { URL(string: text)! }
        #expect(PluginWebPolicy.pageURL("web/index.html")?.absoluteString == "mcl-plugin://local/web/index.html")
        #expect(PluginWebPolicy.file(for: url("mcl-plugin://local/web/index.html"), directory: plugin)?.lastPathComponent
            == "index.html")
        #expect(PluginWebPolicy.file(for: url("mcl-plugin://local/../secret"), directory: plugin) == nil)
        #expect(PluginWebPolicy.file(for: url("mcl-plugin://local/web/%2E%2E/%2E%2E/x"), directory: plugin) == nil)
        #expect(PluginWebPolicy.file(for: url("mcl-plugin://other/web/index.html"), directory: plugin) == nil)
        #expect(PluginWebPolicy.file(for: url("file://" + plugin + "/web/index.html"), directory: plugin) == nil)
        try FileManager.default.createSymbolicLink(atPath: plugin + "/web/out", withDestinationPath: "/etc")
        #expect(PluginWebPolicy.file(for: url("mcl-plugin://local/web/out/hosts"), directory: plugin) == nil)
        // Navigations: the main frame stays on the plugin's pages.
        func nav(_ text: String, main: Bool) -> Bool {
            PluginWebPolicy.allowsNavigation(url(text), mainFrame: main, directory: plugin, hosts: hosts)
        }
        #expect(nav("mcl-plugin://local/web/index.html", main: true))
        #expect(!nav("https://api.example.org/", main: true))
        #expect(nav("https://api.example.org/embed", main: false))
        #expect(!nav("https://evil.example.net/", main: false))
        for scheme in ["data:text/html,<script>x</script>", "blob:mcl-plugin://local/1", "javascript:alert(1)",
                       "file:///etc/passwd", "http://api.example.org/"] {
            #expect(!nav(scheme, main: true) && !nav(scheme, main: false), "\(scheme)")
        }
        // Subresources.
        func load(_ text: String) -> Bool { PluginWebPolicy.allowsLoad(url(text), directory: plugin, hosts: hosts) }
        #expect(load("https://eu.api.example.org/v1"))
        #expect(load("data:image/png;base64,AA=="))
        #expect(!load("https://api.example.org.evil.net/"))
        #expect(!load("wss://api.example.org/"))
        // Messages: only the main frame of a plugin page.
        #expect(PluginWebPolicy.acceptsMessage(mainFrame: true, originScheme: "mcl-plugin", originHost: "local"))
        #expect(!PluginWebPolicy.acceptsMessage(mainFrame: false, originScheme: "mcl-plugin", originHost: "local"))
        #expect(!PluginWebPolicy.acceptsMessage(mainFrame: true, originScheme: "https", originHost: "api.example.org"))
        #expect(!PluginWebPolicy.acceptsMessage(mainFrame: true, originScheme: "file", originHost: ""))
    }

    @Test func theContentSecurityPolicyForbidsInlineScriptsByDefault() {
        let strict: String = PluginWebPolicy.contentSecurityPolicy(hosts: ["api.example.org"], inlineScripts: false)
        #expect(strict.contains("script-src 'self';"))
        #expect(!strict.contains("unsafe-inline'; object-src"))
        #expect(strict.contains("object-src 'none'"))
        #expect(strict.contains("connect-src 'self' https://api.example.org https://*.api.example.org"))
        #expect(PluginWebPolicy.contentSecurityPolicy(hosts: [], inlineScripts: true)
            .contains("script-src 'self' 'unsafe-inline'"))
        #expect(PluginWebPolicy.bridgeScript.contains("location.protocol !== \"mcl-plugin:\""))
    }

    @Test func theContentRulesBlockAllButTheListedHosts() throws {
        let rules = try PluginJSON.parse(PluginWebPolicy.contentRules(hosts: ["api.example.org"]))
        let list: [PluginJSON] = try #require(rules.arrayValue)
        #expect(list.count == 3)
        #expect(list[1]["trigger"]?["url-filter"] == .string("^(mcl-plugin|data|blob):"))
        #expect(list[0]["action"]?["type"] == .string("block"))
        #expect(list[0]["trigger"]?["url-filter"] == .string(".*"))
        #expect(list[1]["action"]?["type"] == .string("ignore-previous-rules"))
        let filter: String = try #require(list[2]["trigger"]?["url-filter"]?.stringValue)
        let regex = try NSRegularExpression(pattern: filter)
        func matches(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        #expect(matches("https://api.example.org/x"))
        #expect(matches("https://eu.api.example.org/"))
        #expect(!matches("https://api.example.org.evil.net/"))
        #expect(!matches("http://api.example.org/"))
        #expect(try PluginJSON.parse(PluginWebPolicy.contentRules(hosts: [])).arrayValue?.count == 2)
    }
}
