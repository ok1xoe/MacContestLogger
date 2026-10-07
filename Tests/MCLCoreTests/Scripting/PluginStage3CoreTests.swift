import Foundation
import Testing
@testable import MCLCore

/// Window plugins, the transmitting part: the raw CAT policy and command, the web window's manifest, load policy and
/// content rules.
@Suite(.ioSafetyNet) struct PluginStage3CoreTests {

    @Test func theCatPolicyAllowsReadingAndTuningOnly() {
        for allowed in ["f", "F 14025000", "m", "M USB 2400", "V VFOA", "s", "S 1 VFOB", "j", "J 100", "L RFPOWER 0.5",
                        "l KEYSPD", "t", "y", "Y 1 0", "\\get_freq", "\\get_level KEYSPD", "\\dump_caps"] {
            #expect(PluginCatPolicy.refusal(allowed) == nil, "\(allowed) must be allowed")
        }
        for refused in ["T 1", "\\set_ptt 1", "b CQ TEST", "\\send_morse CQ", "w FA;", "W FA; 0", "q", "Q", "\\halt",
                        "G TUNE", "U TUNER 1", "L TUNE 1", "+f", ";f", "|f", "f\nT 1", "f\r", "", "   ",
                        "\\set_freq 14025000", "\\send_voice_mem 1", String(repeating: "f", count: 121), "ř"] {
            #expect(PluginCatPolicy.refusal(refused) != nil, "\(refused.debugDescription) must be refused")
        }
    }

    /// A raw command goes out in the extended form and comes back as its lines and `RPRT` code; both directions are
    /// in the CAT log.
    @Test func aRawCommandReturnsItsLinesAndCode() async throws {
        let server = try FakeLineServer(lines: [
            "+f": ["get_freq:", "Frequency: 14074000", "RPRT 0"],
            "+V": ["set_vfo: VFOX", "RPRT -11"],
        ])
        defer { server.stop() }
        let port: Int = server.port
        let log = CatTrafficLog(maxLines: 1000)
        let replies: [RigRawReply] = try await onOwnThread {
            let client = try RigctldClient(host: "localhost", port: port, log: log)
            defer { client.close() }
            return [try client.sendRaw("f"), try client.sendRaw("V VFOX")]
        }
        #expect(replies[0] == RigRawReply(lines: ["get_freq:", "Frequency: 14074000"], code: 0))
        #expect(replies[1] == RigRawReply(lines: ["set_vfo: VFOX"], code: -11))
        #expect(server.allCommands == ["+f", "+V VFOX"])
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
    }

    @Test func theWebPolicyKeepsThePageInItsDirectory() throws {
        let dir: String = try #require(ScriptingFixture.makeDirectory())
        defer { ScriptingFixture.remove(dir) }
        ScriptingFixture.mkdirs(dir + "/plugin/web")
        let plugin: String = dir + "/plugin"
        let hosts = ["api.example.org"]
        func allows(_ text: String) -> Bool {
            PluginWebPolicy.allows(URL(string: text) ?? URL(fileURLWithPath: text), directory: plugin, hosts: hosts)
        }
        #expect(allows("file://" + plugin + "/web/index.html"))
        #expect(allows("file://" + plugin + "/web/app.js"))
        #expect(!allows("file://" + plugin + "/../secret.txt"))
        #expect(!allows("file://" + dir + "/other/x.html"))
        #expect(!allows("file:///etc/passwd"))
        #expect(allows("https://api.example.org/v1/data"))
        #expect(allows("https://eu.api.example.org/v1"))
        #expect(!allows("http://api.example.org/v1"))
        #expect(!allows("https://example.org/"))
        #expect(!allows("https://api.example.org.evil.net/"))
        #expect(!allows("wss://api.example.org/"))
        #expect(!allows("javascript:alert(1)"))
        #expect(allows("about:blank"))
        // A symbolic link out of the directory does not lead out.
        try FileManager.default.createSymbolicLink(atPath: plugin + "/web/out", withDestinationPath: "/etc")
        #expect(!allows("file://" + plugin + "/web/out/hosts"))
    }

    @Test func theContentRulesBlockAllButTheListedHosts() throws {
        let rules = try PluginJSON.parse(PluginWebPolicy.contentRules(hosts: ["api.example.org"]))
        let list: [PluginJSON] = try #require(rules.arrayValue)
        #expect(list.count == 3)
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
