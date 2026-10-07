import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `scripting/` against Java v1.1.1: scenarios and values verbatim from the probe
/// a maintainer-only probe (output `scripting-probe.tsv`, `<ROOT>` = working
/// directory). Synthetic scripts in a temporary directory; blocking `fire` on its own thread. The time limits of the successful
/// path are generous guards (Java 5,000/10,000 ms — they do not affect the result).
@Suite(.ioSafetyNet) struct ScriptingMeasuredTests {

    typealias Fixture = ScriptingFixture

    // MARK: - MacroScript (rows `MACRO`)

    @Test func macroScriptRows() throws {
        let m: String = try #require(Fixture.makeDirectory())
        defer { Fixture.remove(m) }
        Fixture.write(m + "/run20.txt", Array("# přechod na 20 m CW\nCW\n\n14025\nRIT 0\n".utf8))
        let crlf: String = "\u{FEFF}CW\r\n  \t14025 \r\r\n#x\r\n\u{00A0}SPLIT\u{00A0}\n\u{2003}RIT\u{2003}\nkonec"
        Fixture.write(m + "/crlf.txt", Array(crlf.utf8))
        Fixture.write(m + "/bad.txt", [0x43, 0x57, 0x0A, 0xFF, 0x0A])
        Fixture.write(m + "/latin.txt", [0x43, 0xE9, 0x0A])
        Fixture.mkdirs(m + "/dir.txt")
        Fixture.write(m + "/key.txt", Array("K\n".utf8))
        Fixture.write(m + "/a_b-1.txt", Array("AB\n".utf8))
        Fixture.write(m + "/empty.txt", [])
        Fixture.write(m + "/comments.txt", Array("# a\n   # b\n\n".utf8))
        Fixture.write(m + "/locked.txt", Array("X\n".utf8))
        chmod(m + "/locked.txt", 0)

        let run20: [String] = ["CW", "14025", "RIT 0"]
        #expect(MacroScript.load(m, "RUN20") == run20)
        #expect(MacroScript.load(m, "  run20\t") == run20)
        #expect(MacroScript.load(m, "crlf") == ["\u{FEFF}CW", "14025", "\u{00A0}SPLIT\u{00A0}", "RIT", "konec"])
        #expect(MacroScript.load(m, "\u{212A}ey") == ["K"])
        #expect(MacroScript.load(m, "A_B-1") == ["AB"])
        #expect(MacroScript.load(m, "empty") == [])
        #expect(MacroScript.load(m, "comments") == [])
        let empty: [String?] = ["bad", "latin", "dir", "missing", "../etc", "run20.txt", "a/b", "\u{0130}", "", "   ",
                                nil, "locked", "\u{00A0}run20"]
        for name in empty {
            #expect(MacroScript.load(m, name) == nil, "\(String(describing: name))")
        }
    }

    // MARK: - PluginRunner (rows `PLUGIN.*`)

    @Test func dirNames() {
        #expect(PluginRunner.Event.allCases.map(PluginRunner.dirName) == [
            "qso-logged", "contest-opened", "spot-received", "qso-edited", "qso-deleted", "contest-closed",
            "app-started", "app-quitting", "band-changed", "mode-changed", "frequency-changed", "self-spotted",
            "new-multiplier", "score-changed", "score-reported", "clublog-upload",
        ])
    }

    @Test func missingDirectoriesGiveNoPlugins() async throws {
        let w: String = try #require(Fixture.makeDirectory())
        defer { Fixture.remove(w) }
        let runner = PluginRunner(root: w + "/plugins", timeoutMs: 120_000)
        #expect(runner.plugins(.qsoLogged).isEmpty)
        Fixture.mkdirs(w + "/plugins/qso-logged")
        let r: [PluginRunner.Result] = await onOwnThread { runner.fire(.spotReceived, json: "{}") }
        #expect(r.isEmpty)
    }

    /// Selection (without non-executable, hidden, directories and dangling links; a link to a script yes) and order by bytes.
    @Test func selectionAndOrder() async throws {
        let w: String = try #require(Fixture.makeDirectory())
        defer { Fixture.remove(w) }
        let q: String = w + "/plugins/qso-logged"
        Fixture.script(q, "echo.sh", "#!/bin/sh\necho \"event=$MCL_EVENT\"\ncat\n")
        Fixture.write(q + "/notes.txt", Array("nespustitelný".utf8))
        Fixture.script(q, ".hidden", "#!/bin/sh\necho hidden\n")
        Fixture.mkdirs(q + "/subdir")
        let names: [(String, String)] = [("b", "b"), ("_u", "_u"), ("10", "10"), ("9", "9"), ("\u{00E9}", "e-acute"),
                                         ("~t", "tilde")]
        for (name, text) in names {
            Fixture.script(q, name, "#!/bin/sh\necho \(text)\n")
        }
        symlink(q + "/b", q + "/link")
        symlink(q + "/nothing", q + "/dangling")

        let runner = PluginRunner(root: w + "/plugins", timeoutMs: 120_000)
        let listed: [String] = runner.plugins(.qsoLogged).map(PluginRunner.fileName)
        #expect(listed == ["10", "9", "_u", "b", "echo.sh", "link", "~t", "\u{00E9}"])
        let json: String = "{\"call\":\"W1AW\",\"x\":\"ž😀\"}"
        let r: [PluginRunner.Result] = await onOwnThread { runner.fire(.qsoLogged, json: json) }
        let expected: [PluginRunner.Result] = [
            .init(plugin: "10", exitCode: 0, output: ["10"]), .init(plugin: "9", exitCode: 0, output: ["9"]),
            .init(plugin: "_u", exitCode: 0, output: ["_u"]), .init(plugin: "b", exitCode: 0, output: ["b"]),
            .init(plugin: "echo.sh", exitCode: 0, output: ["event=qso-logged", json]),
            .init(plugin: "link", exitCode: 0, output: ["b"]), .init(plugin: "~t", exitCode: 0, output: ["tilde"]),
            .init(plugin: "\u{00E9}", exitCode: 0, output: ["e-acute"]),
        ]
        #expect(r == expected)
    }

    /// Exit codes, signals, stderr, 50 lines, line endings, UTF-8, a script without `#!`, launch errors, environment,
    /// a large JSON on the plugin's stdin that it does not read, and the output of a background child after exit.
    @Test func resultsMatchJava() async throws {
        let w: String = try #require(Fixture.makeDirectory())
        defer { Fixture.remove(w) }
        let c: String = w + "/plugins/contest-opened"
        Fixture.script(c, "01-exit3", "#!/bin/sh\necho before\nexit 3\n")
        Fixture.script(c, "02-kill9", "#!/bin/sh\necho dying\nkill -9 $$\n")
        Fixture.script(c, "03-term", "#!/bin/sh\nkill -TERM $$\n")
        Fixture.script(c, "04-stderr", "#!/bin/sh\necho out\necho err >&2\necho out2\n")
        Fixture.script(c, "05-many", "#!/bin/sh\ni=1\nwhile [ $i -le 60 ]; do echo L$i; i=$((i+1)); done\n")
        Fixture.script(c, "06-endings", "#!/bin/sh\nprintf 'a\\r\\nb\\rc\\n\\nd'\n")
        Fixture.script(c, "07-utf8", "#!/bin/sh\nprintf '\\355\\240\\200A\\377B\\342\\202\\nC\\360\\237\\230\\200\\n'\n")
        Fixture.script(c, "08-noshebang", "echo \"noshebang $MCL_EVENT $0\"\nexit 4\n")
        Fixture.script(c, "09-badinterp", "#!/nonexistent/interp\necho never\n")
        Fixture.script(c, "10-noexecinterp", "#!" + c + "/notes\necho never\n")
        Fixture.write(c + "/notes", Array("x".utf8))
        Fixture.script(c, "11-env", "#!/bin/sh\necho \"[$MCL_EVENT]\"\n[ -n \"$PATH\" ] && echo path\n")
        Fixture.script(c, "12-nostdin", "#!/bin/sh\necho quick\n")
        Fixture.script(c, "13-empty", "#!/bin/sh\n")
        Fixture.script(c, "14-blanklines", "#!/bin/sh\nprintf '\\n\\n\\n'\n")
        Fixture.script(c, "15-background", "#!/bin/sh\n(sleep 1; echo late) &\necho early\n")
        let big: String = "{\"k\":\"" + String(repeating: "x", count: 200_000) + "\"}"

        let runner = PluginRunner(root: w + "/plugins", timeoutMs: 120_000)
        let r: [PluginRunner.Result] = await onOwnThread { runner.fire(.contestOpened, json: big) }
        let many: [String] = (1...50).map { "L\($0)" }
        let cannot: String = "nelze spustit: Cannot run program \"" + c
        let expected: [PluginRunner.Result] = [
            .init(plugin: "01-exit3", exitCode: 3, output: ["before"]),
            .init(plugin: "02-kill9", exitCode: 137, output: ["dying"]),
            .init(plugin: "03-term", exitCode: 143, output: []),
            .init(plugin: "04-stderr", exitCode: 0, output: ["out", "err", "out2"]),
            .init(plugin: "05-many", exitCode: 0, output: many),
            .init(plugin: "06-endings", exitCode: 0, output: ["a", "b", "c", "", "d"]),
            .init(plugin: "07-utf8", exitCode: 0, output: ["\u{FFFD}A\u{FFFD}B\u{FFFD}", "C😀"]),
            .init(plugin: "08-noshebang", exitCode: 4, output: ["noshebang contest-opened \(c)/08-noshebang"]),
            .init(plugin: "09-badinterp", exitCode: -1,
                  output: [cannot + "/09-badinterp\": error=2, No such file or directory"]),
            .init(plugin: "10-noexecinterp", exitCode: -1,
                  output: [cannot + "/10-noexecinterp\": error=13, Permission denied"]),
            .init(plugin: "11-env", exitCode: 0, output: ["[contest-opened]", "path"]),
            .init(plugin: "12-nostdin", exitCode: 0, output: ["quick"]),
            .init(plugin: "13-empty", exitCode: 0, output: []),
            .init(plugin: "14-blanklines", exitCode: 0, output: ["", "", ""]),
            .init(plugin: "15-background", exitCode: 0, output: ["early"]),
        ]
        #expect(r.count == expected.count)
        for (got, want) in zip(r, expected) {
            #expect(got == want)
        }
    }

    /// Limit: Java `plugin překročil časový limit 300 ms — ukončen` and code −1; a plugin that fills the output pipe
    /// blocks and ends at the limit (output is read only after exit). The probe row `huge-output` has a limit of
    /// 3,000 ms and the text `… 3000 ms …`; the test replays it with a 300 ms limit (same behaviour, 2.7 s shorter) —
    /// so this row is not verbatim from the probe, only by matching behaviour.
    @Test func timeoutsMatchJava() async throws {
        let w: String = try #require(Fixture.makeDirectory())
        defer { Fixture.remove(w) }
        let s: String = w + "/plugins/spot-received"
        Fixture.script(s, "slow.sh", "#!/bin/sh\necho started\nsleep 5\n")
        let runner = PluginRunner(root: w + "/plugins", timeoutMs: 300)
        let slow: [PluginRunner.Result] = await onOwnThread { runner.fire(.spotReceived, json: "{}") }
        let message: String = "plugin překročil časový limit 300 ms — ukončen"
        #expect(slow == [.init(plugin: "slow.sh", exitCode: -1, output: [message])])

        unlink(s + "/slow.sh")
        let line: String = "0123456789012345678901234567890123456789012345678901234567890123456789"
        let body: String = "#!/bin/sh\ni=0\nwhile [ $i -lt 2000 ]; do echo \(line); i=$((i+1)); done\necho done\n"
        Fixture.script(s, "huge.sh", body)
        let huge: [PluginRunner.Result] = await onOwnThread { runner.fire(.spotReceived, json: "{}") }
        #expect(huge == [.init(plugin: "huge.sh", exitCode: -1, output: [message])])
    }

    // MARK: - Events JSON (rows `JSON`)

    @Test func eventJsonMatchesJackson() {
        let text: String = "a\"b\\c/d\te\nf\u{0001}g\u{007F}h\u{2028}i\u{00E9}j😀k"
        let qso: [(String, PluginEventJson.Value)] = [
            ("time", .string("2026-10-02T12:34:56.789Z")), ("call", .string("OK1XOE")), ("band", .string("20m")),
            ("freqHz", .number(14_025_000)), ("mode", .string("CW")), ("rstSent", .string("599")),
            ("rstRcvd", .string("")), ("exchangeSent", .string(nil)), ("exchangeRcvd", .string(text)),
            ("operator", .string(nil)), ("contestId", .string("cqww-cw")),
            ("uuid", .string("0f8fad5b-d9cb-469f-a165-70867728950e")),
        ]
        let qsoParts: [String] = [
            #"{"time":"2026-10-02T12:34:56.789Z","call":"OK1XOE","band":"20m","freqHz":14025000,"#,
            #""mode":"CW","rstSent":"599","rstRcvd":"","exchangeSent":null,"#,
            "\"exchangeRcvd\":\"a\\\"b\\\\c/d\\te\\nf\\u0001g\u{007F}h\u{2028}i\u{00E9}j😀k\",",
            #""operator":null,"contestId":"cqww-cw","uuid":"0f8fad5b-d9cb-469f-a165-70867728950e"}"#,
        ]
        let qsoJson: String = qsoParts.joined()
        #expect(PluginEventJson.object(qso) == qsoJson)
        let spot = DxSpot(spotter: "OK1KHL-#", freqHz: -1, dxCall: "JA1ABC", comment: "")
        #expect(PluginEventJson.spotReceived(spot) == #"{"dxCall":"JA1ABC","freqHz":-1,"spotter":"OK1KHL-#","comment":""}"#)
        #expect(PluginEventJson.contestOpened(contestId: "x", name: nil, call: "OK1XOE")
            == #"{"contestId":"x","name":null,"call":"OK1XOE"}"#)
        #expect(PluginEventJson.object([]) == "{}")
        #expect(PluginEventJson.object([("freqHz", .number(Int64.min))]) == #"{"freqHz":-9223372036854775808}"#)
    }

    /// `qsoData` from Kotlin: key order, time as `Instant.toString()`, ADIF band, mode as the enum name.
    @Test func qsoEventUsesKotlinFieldOrder() {
        var qso = Qso()
        qso.timestampUtc = Date(timeIntervalSince1970: 1_790_000_000.5)
        qso.call = "ok1xoe"
        qso.freqHz = 14_025_000
        qso.mode = .cw
        qso.rstSent = "599"
        qso.contestId = "cqww-cw"
        let parts: [String] = [
            #"{"time":"2026-09-21T14:13:20.500Z","call":"OK1XOE","band":"20m","freqHz":14025000,"#,
            #""mode":"CW","rstSent":"599","rstRcvd":"","exchangeSent":"","exchangeRcvd":"","operator":"","#,
            #""contestId":"cqww-cw","uuid":""}"#,
        ]
        let expected: String = parts.joined()
        #expect(PluginEventJson.qsoLogged(qso) == expected)
    }
}
