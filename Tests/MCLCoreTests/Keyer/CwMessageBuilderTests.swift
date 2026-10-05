import Foundation
import Testing
@testable import MCLCore

/// Port of `keyer/CwMessageBuilderTest` (13) + `CWB.*` measurements (maintainer-only probe) and `KCH.*`,
/// `KUN.*`, `KSER.*`, `KTIME.*`, `KFLT.*` (maintainer-only probe). Fingerprints = `grep '^<prefix>'
/// out-en_US.tsv | shasum -a 256`.
@Suite struct CwMessageBuilderTests {

    private typealias Ctx = CwMessageBuilder.Context

    private static let ctx = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "K1A", serial: 7, rst: "599",
                                 exchange: "15", cutNumbers: false, leadingZeros: false)

    private static func text(_ template: String) -> String {
        CwMessageBuilder.build(template, ctx).plainText()
    }

    private static func textOf(_ message: CwMessage) -> String {
        var out = ""
        for case .text(let t) in message.parts {
            out += t
        }
        return JavaText.trim(out)
    }

    // MARK: - Port of CwMessageBuilderTest

    @Test func myCallAndHisCall() {
        #expect(Self.text("cq test {MYCALL} {MYCALL} test") == "CQ TEST OK1XOE OK1XOE TEST")
        #expect(Self.text("*") == "OK1XOE")
        #expect(Self.text("!") == "DL1ABC")
        #expect(Self.text("{CALL}") == "DL1ABC")
    }

    @Test func hisCallFallsBackToLastLogged() {
        // N1MM: "!" with an empty callsign field sends the last logged one.
        let empty = Ctx(myCall: "OK1XOE", hisCall: "", lastLogged: "K1A", serial: 7, rst: "599", exchange: "",
                        cutNumbers: false, leadingZeros: false)
        #expect(CwMessageBuilder.build("tu !", empty).plainText() == "TU K1A")
    }

    @Test func exchangeAndReport() {
        #expect(Self.text("{SENTRSTCUT} {EXCH}") == "5NN 15")
        #expect(Self.text("{SENTRST} {EXCH}") == "599 15")
    }

    @Test func serialPlainCutAndWithLeadingZeros() {
        let cut = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 109, rst: "599", exchange: "#",
                      cutNumbers: true, leadingZeros: false)
        let zeros = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "#",
                        cutNumbers: false, leadingZeros: true)
        let both = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "#",
                       cutNumbers: true, leadingZeros: true)

        #expect(Self.text("#") == "7")
        #expect(CwMessageBuilder.build("#", cut).plainText() == "1TN")
        #expect(CwMessageBuilder.build("#", zeros).plainText() == "007")
        #expect(CwMessageBuilder.build("#", both).plainText() == "TT7")
        // {EXCH} with a serial number (WPX): the number is formatted the same way.
        #expect(CwMessageBuilder.build("{SENTRSTCUT} {EXCH}", cut).plainText() == "5NN 1TN")
    }

    @Test func prosignsAndSpeedChanges() {
        let parts = CwMessageBuilder.build("<<5nn>> tu+", Self.ctx).parts
        let expected: [CwMessage.Part] = [
            .speed(2), .speed(2), .text("5NN"), .speed(-2), .speed(-2), .text(" TU"), .prosign("AR"),
        ]
        #expect(parts == expected)
        #expect(CwMessageBuilder.build("<<5nn>> tu+", Self.ctx).plainText() == "5NN TU AR")
    }

    @Test func allProsigns() {
        let parts = CwMessageBuilder.build("]+[=", Self.ctx).parts
        #expect(parts == [.prosign("SK"), .prosign("AR"), .prosign("AS"), .prosign("BT")])
    }

    @Test func halfSpaceBecomesSpaceAndSpacesCollapse() {
        #expect(Self.text("cq~test") == "CQ TEST")
        #expect(Self.text("  cq    test  ") == "CQ TEST")
    }

    @Test func controlMacrosBecomeActions() {
        let m = CwMessageBuilder.build("tu * test{LOG}{WIPE}{RUN}", Self.ctx)

        #expect(m.plainText() == "TU OK1XOE TEST")
        #expect(m.actions == [.log, .wipe, .run])
        #expect(CwMessageBuilder.build("{S&P}", Self.ctx).actions == [.searchAndPounce])
    }

    @Test func unknownMacroIsReportedAndDropped() {
        let m = CwMessageBuilder.build("cq {SOMEMACRO}test", Self.ctx)

        #expect(m.plainText() == "CQ TEST")
        #expect(m.unknownMacros.contains("{SOMEMACRO}"))
    }

    @Test func unsendableCharactersAreDropped() {
        #expect(Self.text("ok!!".replacingOccurrences(of: "!!", with: "") + "\u{20AC}") == "OK")
        #expect(Self.text("qrl? de *") == "QRL? DE OK1XOE")
        #expect(Self.text("5nn/p.,") == "5NN/P.,")
    }

    @Test func emptyTemplateGivesEmptyMessage() {
        #expect(CwMessageBuilder.build("", Self.ctx).isEmpty)
        #expect(CwMessageBuilder.build(nil, Self.ctx).isEmpty)
        #expect(CwMessageBuilder.build("{WIPE}", Self.ctx).isEmpty)
    }

    @Test func roverAndCountyLineMacros() {
        let rover = Ctx(myCall: "W1AW", hisCall: "K1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "",
                        cutNumbers: false, leadingZeros: false, roverQth: "HAM", countyLine: [])
        let line = Ctx(myCall: "W1AW", hisCall: "K1ABC", lastLogged: "", serial: 7, rst: "599", exchange: "",
                       cutNumbers: false, leadingZeros: false, roverQth: "HAM", countyLine: ["DAD", "JEF", "WAL"])

        #expect(CwMessageBuilder.build("{SENTRSTCUT} {ROVERQTH}{COUNTYLINE}", rover).plainText() == "5NN HAM")
        #expect(CwMessageBuilder.build("{SENTRSTCUT} {ROVERQTH}{COUNTYLINE}", line).plainText() == "5NN DAD/JEF/WAL")
    }

    @Test func stationMacrosTimeAndChaining() {
        let station = CwMessageBuilder.StationData(name: "TOM", grid: "JO70FC", cqZone: "15", ituZone: "28",
                                                   state: "", operator: "OK1ABC")
        let c = Ctx(myCall: "OK1XOE", hisCall: "W1AW", lastLogged: "DL1ABC", serial: 5, rst: "599", exchange: "15",
                    cutNumbers: false, leadingZeros: false, roverQth: "", countyLine: [], cutStyle: .tn,
                    station: station, functionKeys: ["CQ TEST *", "! 599 #", "TU *"],
                    now: KeyerProbe.instant(2026, 11, 28, 12, 34, 0))
        let template = "{LOGGEDCALL} {MYNAME} {MYGRID} {MYCQZONE} {MYITUZONE} {OPERATOR} {TIME} {NR}"
        #expect(Self.textOf(CwMessageBuilder.build(template, c)) == "DL1ABC TOM JO70FC 15 28 OK1ABC 1234 5")
        let chained = Self.textOf(CwMessageBuilder.build("{F2} {F3}", c))
        #expect(JavaText.trim(Self.collapse(chained)) == "W1AW 599 5 TU OK1XOE")
        let m = CwMessageBuilder.build("{CLEARRIT}{CQFREQ}{NOSPLIT}", c)
        #expect(m.actions == [.clearRit, .cqFrequency, .splitOff])
        #expect(m.unknownMacros.isEmpty)
    }

    private static func collapse(_ text: String) -> String {
        var out = ""
        for ch in text where !(ch == " " && out.last == " ") {
            out.append(ch)
        }
        return out
    }

    // MARK: - CWB.build measurements (research/ProbeP6)

    private static let researchTemplates: [String] = [
        "", "cq test *", "  cq    test  ", "cq~test", "~~cq", "tu+", "+tu", "<<5nn>> tu+", "]+[=", "] ", " ]x",
        "a ] b", "a]b", "<", ">", "<>", " < cq", "cq <", "{", "cq {", "cq {mycall", "{MYCALL}{CALL}", "{mycall}",
        "{MyCall}", "{{MYCALL}}", "{MY CALL}", "{}", "{SOMEMACRO}test",
        "{LOG}{WIPE}{RUN}{S&P}{CLEARRIT}{RITCLEAR}{CQFREQ}{NOSPLIT}", "{log}", "#", "{NR}", "{EXCH}", "{SENTRST}",
        "{SENTRSTCUT}", "{ROVERQTH}{COUNTYLINE}", "{LOGGEDCALL}", "{TIME}",
        "{MYNAME} {MYGRID} {MYLOC} {MYCQZONE} {MYZONE} {MYITUZONE} {MYSTATE} {OPERATOR}", "{F1}", "{F2} {F3}",
        "{f1}", "{F4}", "{F5}", "{F6}", "{F7}", "{F12}", "{F13}", "{F0}", "{F01}", "ok!!\u{20AC}", "qrl? de *",
        "5nn/p.,", "ok1\u{017E}\u{00E1}", "stra\u{00DF}e", "\u{0131}i", "\u{FB01}x", "a\tb", "a\nb", "a\u{00A0}b",
        "\u{2003}x", "x_y&z@", "*!#", "!", "\u{1F600} cq", "cq \u{1F600}", "5NN-15", "a  ]  b", "~", "  ",
        "{EXCH}#", "{CALL}{CALL}",
    ]

    private static let station = CwMessageBuilder.StationData(name: "TOM", grid: "JO70FC", cqZone: "15",
                                                              ituZone: "28", state: "", operator: "OK1ABC")

    /// Probe contexts; Java `null` in lists/style/station = the default value (the same behaviour),
    /// `null` in the text fields of the `emptycall` context (`exchange`, `roverQth`) = `""` (also the same).
    private static let researchContexts: [(String, Ctx)] = [
        ("base", Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "K1A", serial: 7, rst: "599", exchange: "15 #",
                     cutNumbers: false, leadingZeros: false, roverQth: "HAM", countyLine: [], cutStyle: .tn,
                     station: station,
                     functionKeys: ["CQ TEST *", "! 599 #", "TU *", "{F1} {F2}", "{F5}", "{F4}", "", "", "x", "y", "z",
                                    "{f12}"],
                     now: KeyerProbe.instant(2026, 11, 28, 12, 34, 56))),
        ("cutzeros", Ctx(myCall: "ok1xoe", hisCall: "  dl1abc  ", lastLogged: "K1A", serial: 109, rst: "599",
                         exchange: "#", cutNumbers: true, leadingZeros: true, roverQth: "", countyLine: ["DAD", "JEF"],
                         now: nil)),
        ("emptycall", Ctx(myCall: "OK1XOE", hisCall: "", lastLogged: " k1a ", serial: 0, rst: "5NN", exchange: "",
                          cutNumbers: true, leadingZeros: false, now: nil)),
        ("big", Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "", serial: 1090, rst: "599", exchange: "#",
                    cutNumbers: true, leadingZeros: true, roverQth: "", countyLine: [], cutStyle: .tauedn,
                    station: station, now: KeyerProbe.instant(1999, 12, 31, 23, 59, 59.999))),
    ]

    private static func researchRows(_ name: String, _ c: Ctx) -> [String] {
        var rows: [String] = []
        for template in researchTemplates {
            let m = CwMessageBuilder.build(template, c)
            let ms20 = CwTiming.estimateMillis(m, wpm: 20)
            let ms3 = CwTiming.estimateMillis(m, wpm: 3)
            let result = KeyerProbe.describe(m) + " ms20=" + String(ms20) + " ms3=" + String(ms3)
            rows.append(ProbeText.row("CWB.build", [name, ProbeText.esc(template), ProbeText.esc(result)]))
        }
        let nullTemplate = KeyerProbe.parts(CwMessageBuilder.build(nil, c))
        rows.append(ProbeText.row("CWB.build", [name, "<null>", nullTemplate]))
        return rows
    }

    @Test(arguments: [
        ("base", "1ebca0e81dd0bf9d0b70a59fc2aecda12a7222edeb43cb1df37cb469492a5011"),
        ("cutzeros", "4ad8a319b1fd4941fafcfe9d3bcf3d6d1586352699fd35ccaacc54ce16cd3549"),
        ("emptycall", "baf15d5313e7bc43d415cca1c8add23d6819fef8afe8fce890ba04fd722848e9"),
        ("big", "a974473ffe7f80ca6167711759170fb304685257bc7964e8380945d6d905e4e0"),
    ])
    func measuredResearchCorpus(name: String, digest: String) throws {
        let c = try #require(Self.researchContexts.first { $0.0 == name }?.1)
        let rows = Self.researchRows(name, c)
        #expect(rows.count == 73)
        #expect(ProbeText.digest(rows) == digest)
    }

    /// The probe's `nulls` context (`myCall`, `hisCall`, `lastLogged`, `rst` = `null`, serial −5, zeros, LEADING_T):
    /// — Swift has `""`. All rows match except templates with `*`/`{MYCALL}`/`{SENTRST}`;
    /// there Java transmits `NULL` or reports an unknown macro. The fingerprint = the Java rows without those seven templates
    /// (`grep -P '^CWB.build\tnulls\t' | grep -vP '\t(cq test \*|…)\t' | shasum -a 256`).
    @Test func measuredNullContextDivergesOnlyWhereDecided() {
        let c = Ctx(myCall: "", hisCall: "", lastLogged: "", serial: -5, rst: "", exchange: "#", cutNumbers: false,
                    leadingZeros: true, cutStyle: .leadingT, now: nil)
        let divergent: [String: String] = [
            // Java: [T'CQ TEST NULL'], ms20=6060
            "cq test *": "[T'CQ TEST '] plain='CQ TEST' actions=[] unknown=[] empty=false ms20=3540 ms3=14160",
            // Java: unknown=[{MYCALL}]
            "{MYCALL}{CALL}": "[] plain='' actions=[] unknown=[] empty=true ms20=0 ms3=0",
            "{mycall}": "[] plain='' actions=[] unknown=[] empty=true ms20=0 ms3=0",
            "{MyCall}": "[] plain='' actions=[] unknown=[] empty=true ms20=0 ms3=0",
            // Java: unknown=[{SENTRST}]
            "{SENTRST}": "[] plain='' actions=[] unknown=[] empty=true ms20=0 ms3=0",
            // Java: QRL? DE NULL
            "qrl? de *": "[T'QRL? DE '] plain='QRL? DE' actions=[] unknown=[] empty=false ms20=4500 ms3=18000",
            // Java: NULL0-5
            "*!#": "[T'0-5'] plain='0-5' actions=[] unknown=[] empty=false ms20=2940 ms3=11760",
        ]
        var rows: [String] = []
        for row in Self.researchRows("nulls", c) {
            let columns = row.components(separatedBy: "\t")
            if let expected = divergent[columns[2]] {
                #expect(columns[3] == expected, "\(columns[2])")
            } else {
                rows.append(row)
            }
        }
        #expect(rows.count == 66)
        #expect(ProbeText.digest(rows) == "935e0d94c32255ec7fe50ec20280619ed3c4cd69906bcf3e280e7c655097e85c")
    }

    /// `CWB.cut` (without a Java `null` input — a non-optional `String` in Swift).
    @Test func measuredCut() {
        #expect(CwMessageBuilder.cut("") == "")
        #expect(CwMessageBuilder.cut("599") == "5NN")
        #expect(CwMessageBuilder.cut("5990") == "5NNT")
        #expect(CwMessageBuilder.cut("9 0") == "N T")
        #expect(CwMessageBuilder.cut("\u{0669}") == "\u{0669}")
    }

    /// MARK: - Measurement keyer/ProbeKeyer

    private static let noon = KeyerProbe.instant(2026, 11, 28, 12, 34, 56)

    private static func keyerCtx(serial: Int, exchange: String, cut: Bool, zeros: Bool, style: CutStyle,
                                 functionKeys: [String], now: Date?) -> Ctx {
        Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: "K1A", serial: serial, rst: "599", exchange: exchange,
            cutNumbers: cut, leadingZeros: zeros, roverQth: "", countyLine: [], cutStyle: style, station: .empty,
            functionKeys: functionKeys, now: now)
    }

    /// `KCH.build`: chaining of F-keys — a cycle F1↔F2, F1 onto itself, a chain longer than the depth, a `null`
    /// item (= ""), a short list, lowercase `f`, unclosed brackets, F10–F12.
    @Test func measuredFunctionKeyChaining() {
        let sets: [[String]] = [
            ["{F2}", "{F1}"],
            ["{F1}"],
            ["a {F2}", "b {F3}", "c {F4}", "d {F5}", "e"],
            ["x", "", "", "{F2}{f2}", "{F12}", "{F13}"],
            ["cq {F2", "{MYCALL}{F3}", "}{F1}{"],
            ["{F10}", "{F11}", "{F12}", "z", "", "", "", "", "", "TEN", "ELEVEN", "{F1}"],
        ]
        let templates = ["{F1}", "{F2}", "{F3}", "{F4}", "{F5}", "{F6}", "{F10}", "{F11}", "{F12}", "{F1}{F1}",
                         "x{F1}y", "{f1}", "{F 1}", "{F1 }", "{F01}", "{F1}}", "{{F1}}", "{F1", "F1}"]
        var rows: [String] = []
        for (index, keys) in sets.enumerated() {
            let c = Self.keyerCtx(serial: 7, exchange: "15", cut: false, zeros: false, style: .tn,
                                  functionKeys: keys, now: Self.noon)
            for template in templates {
                let result = KeyerProbe.describe(CwMessageBuilder.build(template, c))
                rows.append(ProbeText.row("KCH.build", [String(index), ProbeText.esc(template),
                                                          ProbeText.esc(result)]))
            }
        }
        #expect(rows.count == 114)
        #expect(ProbeText.digest(rows) == "0fdf29faed130e2ba77bc0020632ad0fc9286c07aeaf113a28647d59395ffe9e")
        // Readable samples: the cycle ends with an unknown macro at depth 3, the chain inserts at most three levels.
        #expect(rows[0] == "KCH.build\t0\t{F1}\t[] plain='' actions=[] unknown=[{F2}] empty=true")
        #expect(rows[38] == "KCH.build\t2\t{F1}\t[T'A B C '] plain='A B C' actions=[] unknown=[{F4}] empty=false")
    }

    /// `KUN.build`: unknown macros, brackets, uppercase of macros (`ı`, `ſ`, `ß`, `ﬁ`), spaces inside.
    @Test func measuredUnknownMacros() {
        let templates = [
            "{FOO}", "{FOO}{BAR}{FOO}", "cq {MY CALL} test", "{ MYCALL}", "{MYCALL }", "}{", "{{}}", "{}{}", "{EXCH",
            "a{b{c}d}e", "{log}{Log}{LOG}", "{s&p}", "{S&P }", "{\u{0131}og}", "{lo\u{017F}g}", "{stra\u{00DF}e}",
            "{\u{FB01}}", "{MYCALL}\u{00A0}{CALL}", "{\u{00E9}}", "{\u{1F600}}", "{TIME}{time}",
            "{SENTRSTCUT}{sentrstcut}", "{NR}{nr}{Nr}", "{EXCH}{exch}", "{OPERATOR}{operator}", "{MYLOC}{MYZONE}",
            "{CALL}{call}", "{LOGGEDCALL}", "{ROVERQTH}", "{COUNTYLINE}",
        ]
        let station = CwMessageBuilder.StationData(name: "TOM", grid: "JO70FC", cqZone: "15", ituZone: "28",
                                                   state: "NY", operator: "OK1ABC")
        let c = Ctx(myCall: "OK1XOE", hisCall: "DL1ABC", lastLogged: " k1a ", serial: 42, rst: "579",
                    exchange: "15 #", cutNumbers: false, leadingZeros: false, roverQth: "HAM", countyLine: [],
                    cutStyle: .tn, station: station, functionKeys: [], now: Self.noon)
        let rows: [String] = templates.map { template in
            let result = KeyerProbe.describe(CwMessageBuilder.build(template, c))
            return ProbeText.row("KUN.build", [ProbeText.esc(template), ProbeText.esc(result)])
        }
        #expect(ProbeText.digest(rows) == "11cf1b957440dea1223e02185bda2e1d0915882ed21bc9ce27c6172e5b88404e")
        #expect(CwMessageBuilder.build("a{b{c}d}e", c).unknownMacros == ["{B{C}"])
        #expect(CwMessageBuilder.build("{stra\u{00DF}e}", c).unknownMacros == ["{STRASSE}"])
    }

    /// `KSER.build`: all `CutStyle` × serial number (0, 7, 9, 10, 90, 109, 1090, 99999, −5, −90,
    /// `Integer.MAX_VALUE`, `MIN_VALUE`) × cut × leading zeros; `#`, `{EXCH}` = `"15 #/#"`, `{SENTRSTCUT}`.
    @Test func measuredSerialFormatting() {
        let serials = [0, 7, 9, 10, 90, 109, 1090, 99999, -5, -90, Int(Int32.max), Int(Int32.min)]
        var rows: [String] = []
        for style in CutStyle.allCases {
            for serial in serials {
                for cut in [false, true] {
                    for zeros in [false, true] {
                        let c = Self.keyerCtx(serial: serial, exchange: "15 #/#", cut: cut, zeros: zeros,
                                              style: style, functionKeys: [], now: Self.noon)
                        let columns: [String] = [
                            style.rawValue, String(serial), String(cut), String(zeros),
                            CwMessageBuilder.build("#", c).plainText(),
                            CwMessageBuilder.build("{EXCH}", c).plainText(),
                            CwMessageBuilder.build("{SENTRSTCUT}", c).plainText(),
                        ]
                        rows.append(ProbeText.row("KSER.build", columns.map { ProbeText.esc($0) }))
                    }
                }
            }
        }
        #expect(rows.count == 432)
        #expect(ProbeText.digest(rows) == "eca46afc5754b300f3d54d655f5430526b4ed174781621b80ac91f1320b3d6d8")
    }

    /// `KTIME.build`: `{TIME}` = `HHmm` UTC, truncated (23:59:59.999 → 2359, before the epoch 23:59:59.5 → 2359),
    /// year 10000, daylight-saving transitions play no role; `nil` → "".
    @Test func measuredTimeMacro() {
        let cases: [(Date?, String)] = [
            (KeyerProbe.instant(2026, 11, 28, 23, 59, 59.999), "2359"),
            (KeyerProbe.instant(2026, 11, 29, 0, 0, 0), "0000"),
            (KeyerProbe.instant(1969, 12, 31, 23, 59, 59.5), "2359"),
            (KeyerProbe.instant(1970, 1, 1, 0, 0, 0), "0000"),
            (KeyerProbe.instant(1900, 1, 1, 9, 5, 0), "0905"),
            (KeyerProbe.instant(10000, 6, 1, 7, 8, 9), "0708"),
            (KeyerProbe.instant(2026, 3, 29, 1, 30, 0), "0130"),
            (KeyerProbe.instant(2026, 10, 25, 2, 30, 0), "0230"),
            (nil, ""),
        ]
        for (now, expected) in cases {
            let c = Self.keyerCtx(serial: 7, exchange: "", cut: false, zeros: false, style: .tn, functionKeys: [],
                                  now: now)
            #expect(CwMessageBuilder.build("{TIME}", c).plainText() == expected)
        }
    }

    /// `KFLT.unit`: every UTF-16 unit of the BMP in the template `q<char>q` — printed only those that change the result
    /// against `[T'QQ']` (95: transmittable ASCII, macros, prosigns, speed and full uppercase `ß`, `ı`, `ŉ`,
    /// `ſ`, `ǰ`, U+1E96–U+1E9A, ligatures U+FB00–U+FB06). Half of a surrogate pair is a lone
    /// unit in Java, here U+FFFD — the filter drops both.
    @Test func measuredCharacterFilterOverWholeBmp() {
        let c = Self.keyerCtx(serial: 7, exchange: "15", cut: false, zeros: false, style: .tn, functionKeys: [],
                              now: Self.noon)
        var rows: [String] = []
        for unit in 0...0xFFFF {
            let template = JavaChar.string([0x71, UInt16(unit), 0x71])
            let m = CwMessageBuilder.build(template, c)
            let parts = KeyerProbe.parts(m)
            if parts != "[T'QQ']" {
                let hex = String(unit, radix: 16).uppercased()
                let code = String(repeating: "0", count: 4 - hex.count) + hex
                let columns = [code, parts, KeyerProbe.javaList(m.actions.map(\.rawValue)),
                               KeyerProbe.javaList(m.unknownMacros)]
                rows.append(ProbeText.row("KFLT.unit", columns.map { ProbeText.esc($0) }))
            }
        }
        #expect(rows.count == 95)
        #expect(ProbeText.digest(rows) == "a4ba80268278cc6d3b285e878e54a597b787fa3025c0c98e58c382cde2361b5a")
        // KFLT.extra: characters outside the BMP are dropped whole.
        for extra in ["\u{1F600}", "\u{10428}", "\u{1D400}", "\u{1F1E8}\u{1F1FF}"] {
            #expect(CwMessageBuilder.build("q" + extra + "q", c).parts == [.text("QQ")])
        }
    }
}
