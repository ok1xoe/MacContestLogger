import Foundation
@testable import MCLCore
import Testing

/// N1MM function key files (`.mc`): positional Run / S&P messages, comments, blank lines and labels.
@Suite struct McFunctionKeysTests {

    @Test func runThenSpByPosition() throws {
        var lines: [String] = ["# CW messages", "#RUN"]
        for n in 1...12 {
            lines.append("F\(n) Run\(n),run \(n)")
        }
        lines.append("# S&P")
        for n in 1...12 {
            lines.append("F\(n) S&&P\(n),sp \(n)")
        }
        let keys = try #require(McFunctionKeys.parse(lines.joined(separator: "\r\n") + "\r\n"))
        #expect(keys.run.count == 12 && keys.sp.count == 12)
        #expect(keys.run[0] == FunctionKeyMessage(label: "Run1", text: "run 1"))
        #expect(keys.run[11] == FunctionKeyMessage(label: "Run12", text: "run 12"))
        #expect(keys.sp[0] == FunctionKeyMessage(label: "S&P1", text: "sp 1"))
        #expect(keys.sp[11].text == "sp 12")
    }

    /// Blank lines are messages (N1MM); missing S&P messages repeat the Run ones; no comma = an empty message; only
    /// the label's own key name is dropped.
    @Test func blankLinesMissingSpAndLabels() throws {
        let text = "F1 Cq,cq test *\n\nF3 Tu,tu, ee\nF1 Odd\n#comment\n F5 His,!\n"
        let keys = try #require(McFunctionKeys.parse(text))
        #expect(keys.run[0] == FunctionKeyMessage(label: "Cq", text: "cq test *"))
        #expect(keys.run[1] == FunctionKeyMessage(label: "", text: ""))
        #expect(keys.run[2] == FunctionKeyMessage(label: "Tu", text: "tu, ee"))
        #expect(keys.run[3] == FunctionKeyMessage(label: "F1 Odd", text: ""))
        #expect(keys.run[4] == FunctionKeyMessage(label: "His", text: "!"))
        #expect(keys.run[5] == FunctionKeyMessage(label: "Empty", text: ""))
        #expect(keys.sp == keys.run)
        #expect(McFunctionKeys.parse("# only\n\n\n") == nil)
    }

    @Test func formatRoundTrips() throws {
        let keys = FunctionKeySet(run: CwKeyerConfig.defaultRun(), sp: CwKeyerConfig.defaultSp())
        let text: String = McFunctionKeys.format(keys, title: "CW")
        #expect(text.hasPrefix("# CW\n# RUN Messages\nF1 Cq,cq test {MYCALL} {MYCALL} test\n"))
        #expect(text.contains("# S&P Messages\nF1 Qrl?,qrl? de {MYCALL}\n"))
        #expect(McFunctionKeys.parse(text) == keys)
        let odd = FunctionKeySet(run: [FunctionKeyMessage(label: "S&P, x", text: "a")], sp: [])
        let parsed = try #require(McFunctionKeys.parse(McFunctionKeys.format(odd, title: "x")))
        #expect(parsed.run[0] == FunctionKeyMessage(label: "S&P  x", text: "a"))
    }

    @Test func kindsReadAndWriteTheirSets() {
        var config = AppConfig()
        let keys = FunctionKeySet(run: [FunctionKeyMessage(label: "A", text: "a")],
                                  sp: [FunctionKeyMessage(label: "B", text: "b")])
        FunctionKeyKind.digital.set(keys, in: &config)
        #expect(config.digital.runMessages[0].label == "A")
        #expect(config.digital.runMessages.count == VoiceKeyerConfig.keyCount)
        #expect(FunctionKeyKind.digital.messages(in: config).sp[0].text == "b")
        #expect(FunctionKeyKind.cw.messages(in: config).run == CwKeyerConfig.defaultRun())
    }
}
