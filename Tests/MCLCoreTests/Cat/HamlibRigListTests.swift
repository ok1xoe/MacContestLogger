import Testing
@testable import MCLCore

/// Port of `cat/HamlibRigListTest` (`parses…`, `skipsHeaderRow`; `listNeverEmpty` is in `HamlibRigListProcessTests`)
/// + `RL.*` measurements over the real `rigctl -l` of hamlib 4.7.1 (maintainer-only probe).
@Suite struct HamlibRigListTests {

    @Test func parsesModelNumberManufacturerAndModel() throws {
        let m = try #require(HamlibRigList.parseLine(
            "  2011  Kenwood                TS-570                  20231210.0      Stable    rig"))
        #expect(m.number == 2011)
        #expect(m.mfg == "Kenwood")
        #expect(m.model == "TS-570")
    }

    @Test func skipsHeaderRow() {
        #expect(HamlibRigList.parseLine(" Rig #  Mfg                    Model                   Version") == nil)
    }

    /// Rows of the `RL.parseLine` probe (input + `number|mfg|model|toString`, or `<empty>`) over the whole
    /// `rigctl -l` output — SHA-256 fingerprint as `grep $'^RL.parseLine\t' out-en_US.tsv | shasum -a 256`;
    /// 311 of 312 rows recognised (header not).
    @Test func measuredRealRigList() throws {
        let lines = try HamlibRigListFixture.lines()
        var rows: [String] = []
        var parsed = 0
        for line in lines {
            let result: String
            if let m = HamlibRigList.parseLine(line) {
                parsed += 1
                result = "\(m.number)|\(m.mfg)|\(m.model)|\(m.description)"
            } else {
                result = "<empty>"
            }
            rows.append(ProbeText.row("RL.parseLine", [ProbeText.esc(line), ProbeText.esc(result)]))
        }
        #expect(lines.count == 312)
        #expect(parsed == 311)
        #expect(ProbeText.digest(rows) == "0aa21454f5863e9763b621b30451df2058c6a66cc7d2965e22c937ea3c4f815d")
        // Readable samples from the same table.
        #expect(rows[4] == "RL.parseLine\t     5  TRXManager             TRXManager 5.7.630+     20210613.0      "
            + "Stable      RIG_MODEL_TRXMANAGER_RIG\t5|TRXManager|TRXManager|5 \\u2014 TRXManager TRXManager")
    }

    /// `RL.parseLineEdge`: `Integer.parseInt` (`+12`, Arabic digits, overflow), the version ends the model
    /// (`1.0`, six or more digits), status words only with exact letter case.
    @Test func measuredEdgeLines() {
        let cases: [(String, String)] = [
            ("", "<empty>"), ("  ", "<empty>"), ("x y z", "<empty>"), ("12 A", "<empty>"),
            ("12 A B", "12|A|B"), ("+12 Mfg Model", "12|Mfg|Model"), ("\u{0661}\u{0662} Mfg M", "12|Mfg|M"),
            ("2147483648 M X", "<empty>"), ("7 Mfg Model 1.0", "7|Mfg|Model"), ("7 Mfg Model Beta", "7|Mfg|Model"),
            ("7 Mfg Model beta", "7|Mfg|Model beta"), ("7 Mfg 123456", "7|Mfg|"), ("7 Mfg 12345 X", "7|Mfg|12345 X"),
            ("7 Mfg IC-7300 Stable rig", "7|Mfg|IC-7300"),
        ]
        for (line, expected) in cases {
            let actual: String = HamlibRigList.parseLine(line).map { "\($0.number)|\($0.mfg)|\($0.model)" } ?? "<empty>"
            #expect(actual == expected, "\(line)")
        }
    }

    /// `RL.extra` (maintainer-only probe): splitting is Java `\s+` (ASCII whitespace only — NBSP and
    /// U+2003 do not split a token, U+000B/U+000C do), `trim` also takes U+001C at the edge, `.` in the version pattern does not take
    /// U+0085/U+2028, `\d` is ASCII only, status words and `New` only with exact letter case.
    @Test func measuredJavaRegexSemantics() {
        let cases: [(String, String)] = [
            ("7 Mfg A\u{00A0}B C", "7|Mfg|A\u{00A0}B C"), ("7\tMfg\u{000B}A\u{000C}B", "7|Mfg|A B"),
            ("7 Mfg 1.0\u{0085} X", "7|Mfg|1.0\u{0085} X"), ("7 Mfg 1.0x X", "7|Mfg|"),
            ("7 Mfg \u{0661}23456 X", "7|Mfg|\u{0661}23456 X"), ("7 Mfg A\u{2003}B", "7|Mfg|A\u{2003}B"),
            ("\u{001C}7 Mfg M", "7|Mfg|M"), ("7 Mfg M\u{001C} N", "7|Mfg|M\u{001C} N"), ("7 Mfg 1.2.3 X", "7|Mfg|"),
            ("7 Mfg 1. X", "7|Mfg|1. X"), ("7 Mfg 12.3\u{2028} X", "7|Mfg|12.3\u{2028} X"), ("7 Mfg New Model", "7|Mfg|"),
            ("7 Mfg STABLE X", "7|Mfg|STABLE X"), ("-0 Mfg M", "0|Mfg|M"), ("007 Mfg M", "7|Mfg|M"),
            ("7 \u{00C9}lan \u{0130}C-7300 Untested", "7|\u{00C9}lan|\u{0130}C-7300"),
        ]
        for (line, expected) in cases {
            let actual: String = HamlibRigList.parseLine(line).map { "\($0.number)|\($0.mfg)|\($0.model)" } ?? "<empty>"
            #expect(Array(actual.utf16) == Array(expected.utf16), "\(ProbeText.esc(line))")
        }
    }
}
