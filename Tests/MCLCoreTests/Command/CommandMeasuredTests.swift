import Testing
@testable import MCLCore

/// `CallFieldCommands.parse` and `OperatorCommand.parse` against Java v1.1.1 (probe
/// a maintainer-only probe, table `CommandMeasured`): overflow
/// (`ArithmeticException: Overflow` from `longValueExact`, silent `long` wraparound for the shift and partial
/// frequency), `HALF_UP` over decimal notation, non-ASCII digits (fullwidth, Arabic, Devanagari),
/// whitespace (NBSP, U+2003, U+3000, control), letter case incl. the expanding `toUpperCase` mappings
/// (`ı` → `I`, `ſ` → `S`, `ß` → `SS`, KELVIN SIGN stays and does not give the keyword), all keywords
/// in seven variants, edges of all bands ±1 Hz and 1,000 random inputs.
@Suite struct CommandMeasuredTests {

    private static func rows(_ id: String) -> [[String]] {
        ProbeRows.rows(CommandMeasured.rows, id)
    }

    /// Java `String.valueOf(Optional<CallFieldCommand>)` (the record `toString`), or `THROW …` like the probe.
    static func javaString(_ run: () throws(JavaArithmeticError) -> CallFieldCommand?) -> String {
        do {
            guard let command = try run() else { return "Optional.empty" }
            return "Optional[\(javaRecord(command))]"
        } catch {
            return "THROW ArithmeticException: \(error.message)"
        }
    }

    static func javaRecord(_ command: CallFieldCommand) -> String {
        switch command {
        case .qsy(let hz): return "Qsy[freqHz=\(hz)]"
        case .otherVfo(let hz): return "OtherVfo[freqHz=\(hz)]"
        case .split(let hz): return "Split[txFreqHz=\(hz)]"
        case .splitOff: return "SplitOff[]"
        case .runScript(let name): return "RunScript[name=\(name)]"
        case .rit(let hz): return "Rit[offsetHz=\(hz)]"
        case .swapVfo: return "SwapVfo[]"
        case .changeMode(let mode): return "ChangeMode[mode=\(mode.rawValue)]"
        case .login(let op): return "Login[operator=\(op)]"
        case .wipeLog: return "WipeLog[]"
        case .version: return "Version[]"
        case .exportAdif: return "ExportAdif[]"
        case .exportCabrillo: return "ExportCabrillo[]"
        case .importLog: return "ImportLog[]"
        case .esmOn: return "EsmOn[]"
        case .esmOff: return "EsmOff[]"
        case .autoRunSp(let on): return "AutoRunSp[enabled=\(on)]"
        case .setTour(let params): return "SetTour[params=\(params)]"
        case .tourOff: return "TourOff[]"
        case .bonusStations(let calls): return "BonusStations[calls=\(calls)]"
        case .roverQth(let county): return "RoverQth[county=\(county)]"
        case .countyLine(let counties): return "CountyLine[counties=\(counties)]"
        case .countyLineOff: return "CountyLineOff[]"
        case .spotMe(let comment): return "SpotMe[comment=\(comment)]"
        case .appAction(let action): return "AppAction[action=\(action.rawValue)]"
        case .toggle(let setting, let on): return "Toggle[setting=\(setting.rawValue), on=\(on)]"
        case .cutNumbers(let style): return "CutNumbers[style=\(style?.rawValue ?? "null")]"
        case .openSettingsTab(let key): return "OpenSettingsTab[tabKey=\(key)]"
        case .rescore: return "Rescore[]"
        case .openSetup: return "OpenSetup[]"
        case .networkOn: return "NetworkOn[]"
        case .networkOff: return "NetworkOff[]"
        case .invalid(let message): return "Invalid[message=\(message)]"
        }
    }

    /// Rows `input freq secondVFO ctrl result`; comparison by UTF-16 units.
    private static func check(_ id: String, expectedCount: Int) {
        let rows: [[String]] = Self.rows(id)
        #expect(rows.count == expectedCount, "\(id)")
        var mismatches: Int = 0
        for row in rows {
            let input: String = row[0]
            let freq: Int64 = Int64(row[1])!
            let other: Int64 = Int64(row[2])!
            let ctrl: Bool = row[3] == "true"
            let actual: String = javaString { () throws(JavaArithmeticError) -> CallFieldCommand? in
                try CallFieldCommands.parse(input, currentFreqHz: freq, otherVfoHz: other, ctrlEnter: ctrl)
            }
            if !JavaText.equals(actual, row[4]) {
                mismatches += 1
                if mismatches <= 20 {
                    Issue.record("\(id) \(input.debugDescription) \(freq) \(other) \(ctrl): \(actual) ≠ \(row[4])")
                }
            }
        }
        #expect(mismatches == 0, "\(id)")
    }

    @Test func edgeCorpusMatchesJava() {
        Self.check("CMD", expectedCount: 932)
    }

    @Test func allKeywordVariantsMatchJava() {
        Self.check("WORD", expectedCount: 711)
    }

    @Test func bandEdgesMatchJava() {
        Self.check("EDGE", expectedCount: 1_352)
    }

    @Test func fuzzMatchesJava() {
        Self.check("FUZZ", expectedCount: 1_000)
    }

    @Test func operatorCommandMatchesJava() {
        let rows: [[String]] = Self.rows("OP")
        #expect(rows.count == 20)
        for row in rows {
            let actual: String = OperatorCommand.parse(row[0]).map { "Optional[OperatorCommand[operator=\($0.operator)]]" }
                ?? "Optional.empty"
            #expect(JavaText.equals(actual, row[1]), "\(row[0].debugDescription): \(actual) ≠ \(row[1])")
        }
        #expect(Self.rows("OP.null") == [["Optional.empty", "Optional.empty"]])
        #expect(OperatorCommand.parse(nil) == nil)
        #expect(Self.javaString { () throws(JavaArithmeticError) -> CallFieldCommand? in
            try CallFieldCommands.parse(nil, currentFreqHz: 0)
        } == "Optional.empty")
    }

    /// A typed error carries the Java message; Ctrl+Enter and the second VFO change nothing about it.
    @Test func overflowThrowsJavaArithmeticException() {
        #expect(throws: JavaArithmeticError(message: "Overflow")) {
            try CallFieldCommands.parse("9999999999999999", currentFreqHz: 14_074_000)
        }
        #expect(throws: JavaArithmeticError(message: "Overflow")) {
            try CallFieldCommands.parse("/9999999999999999", currentFreqHz: 0, otherVfoHz: 7_010_000, ctrlEnter: true)
        }
        #expect(JavaArithmeticError(message: "Overflow").description == "java.lang.ArithmeticException: Overflow")
    }

    /// `ARGUMENT_KEYWORDS` — commands for which space in the callsign field does not jump into the exchange.
    @Test func argumentKeywordsAreJavaSet() {
        let words: [String] = ["OPON", "LOGIN", "TOUR", "BONUS", "ROVERQTH", "COUNTYLINE", "SPOTME", "RIT", "SCRIPT"]
        let expected: Set<JavaStringKey> = Set(words.map { JavaStringKey($0) })
        #expect(CallFieldCommands.argumentKeywords == expected)
        #expect(words.allSatisfy { CallFieldCommands.isArgumentKeyword($0) })
        #expect(!CallFieldCommands.isArgumentKeyword("opon"))
    }

    /// Java `setScale(0, HALF_UP)` over `BigDecimal` — the first discarded digit decides.
    @Test func bigDecimalSetScaleHalfUp() throws {
        let cases: [(String, Int64?)] = [
            ("0.5", 1), ("-0.5", -1), ("0.4999", 0), ("-0.4999", 0), ("0.05", 0), ("9.5", 10),
            ("99.5", 100), ("-99.5", -100), ("123", 123), ("0", 0), ("-0.0", 0), ("1.000", 1),
            ("9223372036854775807.4", Int64.max), ("9223372036854775807.5", nil),
            ("-9223372036854775808.4", Int64.min), ("-9223372036854775808.5", nil),
        ]
        for (text, expected) in cases {
            let value: JavaBigDecimal = try #require(JavaBigDecimal(text))
            #expect(value.setScaleZeroHalfUp().longValueExact() == expected, "\(text)")
        }
    }
}
