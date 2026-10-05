import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `io/LogExportsTest` (2 tests) + full match with Java over the logs
/// `ExportsFixture` (reference `ExportsMeasured`, maintainer-only probe).
@Suite struct LogExportsTests {

    /// Java `csvQuotesAndOrder`.
    @Test func csvQuotesAndOrder() {
        let csv = LogExports.csv(ExportsFixture.testLog())
        // Java `csv.split("\\r\\n")` (drops the trailing empty piece).
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 4)
        #expect(lines[1].hasPrefix("2026-11-28 12:00,DL1ABC,40m,7010.0,CW"))
        #expect(lines[2].hasSuffix(",\"tnx, \"\"73\"\"\""))
    }

    /// Java `textAndSummary`.
    @Test func textAndSummary() throws {
        let log = ExportsFixture.testLog()
        let t = LogExports.text("CQ WW CW — OK1XOE", log)
        #expect(t.contains("W1AW"))
        let score = ScoreState(qsoCount: 3, qsoPoints: 7, multTotal: 3, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 0, total: 21)
        let s = try LogExports.summary("CQ WW CW", "OK1XOE", score, log)
        #expect(s.contains("QSO 3 · body 7 · násobiče 3 · skóre 21"))
        #expect(s.contains("20m"))
        let lines = s.split(separator: "\n").map(String.init)
        #expect(lines.contains { $0.hasPrefix("Celkem") && JavaText.trim($0).hasSuffix("3") })
    }

    // MARK: - Match with Java

    @Test func testLogMatchesJava() throws {
        let log = ExportsFixture.testLog()
        #expect(ExportsFixture.bytes(LogExports.csv(log)) == ExportsFixture.bytes(ExportsMeasured.testCsv.joined()))
        #expect(ExportsFixture.bytes(LogExports.text("CQ WW CW — OK1XOE", log)) == ExportsFixture.bytes(ExportsMeasured.testText.joined()))
        let score = ScoreState(qsoCount: 3, qsoPoints: 7, multTotal: 3, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 0, total: 21)
        let summary = try LogExports.summary("CQ WW CW", "OK1XOE", score, log)
        #expect(ExportsFixture.bytes(summary) == ExportsFixture.bytes(ExportsMeasured.testSummary.joined()))
    }

    /// `…050 Hz` → `%.1f` HALF_UP (`14025.1`), quotes, CR, LF, commas, a quote with a combining
    /// character (Swift `Character` would not find it in `contains("\"")`), a QSO without time at the end,
    /// deleted omitted, two QSOs with the same time in input order, frequency 0 without a band.
    @Test func edgeCsvMatchesJava() {
        let csv = LogExports.csv(ExportsFixture.edgeLog(withUntimed: true))
        #expect(ExportsFixture.bytes(csv) == ExportsFixture.bytes(ExportsMeasured.edgeCsv.joined()))
    }

    /// Column widths by UTF-16 (`OK1ŽÁ`, emoji), `X-QSO ` before the note, `\r\n` literally,
    /// a title longer than 20 UTF-16 units (emoji = 2).
    @Test func edgeTextMatchesJava() {
        let text = LogExports.text("Mistrovství ČR — OK1ŽÁ/P 😀", ExportsFixture.edgeLog(withUntimed: true))
        #expect(ExportsFixture.bytes(text) == ExportsFixture.bytes(ExportsMeasured.edgeText.joined()))
        #expect(ExportsFixture.bytes(LogExports.text("Závod 😀", [])) == ExportsFixture.bytes(ExportsMeasured.shortTitleText.joined()))
    }

    @Test func emptyCsvIsHeaderOnly() {
        #expect(ExportsFixture.bytes(LogExports.csv([])) == ExportsFixture.bytes(ExportsMeasured.emptyCsv.joined()))
    }

    @Test func summaryWithoutScoreMatchesJava() throws {
        let s = try LogExports.summary("Závod", "OK1ŽÁ", nil, ExportsFixture.edgeLog(withUntimed: false))
        #expect(ExportsFixture.bytes(s) == ExportsFixture.bytes(ExportsMeasured.edgeSummaryNil.joined()))
    }

    @Test func summaryWithQtcMatchesJava() throws {
        let score = ScoreState(qsoCount: 5, qsoPoints: 12, multTotal: 4, multByGroup: JavaLinkedMap<Int32>(),
                               bonusPoints: 0, qtcPoints: 3, total: 60)
        let s = try LogExports.summary("WAE", "OK1XOE", score, ExportsFixture.edgeLog(withUntimed: false))
        #expect(ExportsFixture.bytes(s) == ExportsFixture.bytes(ExportsMeasured.edgeSummaryQtc.joined()))
    }

    /// The first QSO has a time, the last does not → Java `NullPointerException: temporal`.
    @Test func summaryWithUntimedLastThrowsLikeJava() {
        let log = ExportsFixture.edgeLog(withUntimed: true)
        let java: [UInt8] = ExportsFixture.bytes(ExportsMeasured.edgeSummaryUntimedLast.joined())
        #expect(java == ExportsFixture.bytes("EXC java.lang.NullPointerException: temporal"))
        #expect(throws: LogExportsError.nullPointer(message: "temporal")) {
            try LogExports.summary("Závod", "OK1XOE", nil, log)
        }
        #expect(LogExportsError.nullPointer(message: "temporal").javaClass == "java.lang.NullPointerException")
    }

    /// Only QSOs without time: no "Období" row; an empty log: a table without columns.
    @Test func summaryWithoutTimesMatchesJava() throws {
        let untimed = ExportsFixture.edgeLog(withUntimed: true).filter { $0.timestampUtc == nil }
        let s = try LogExports.summary("Závod", "OK1XOE", nil, untimed)
        #expect(ExportsFixture.bytes(s) == ExportsFixture.bytes(ExportsMeasured.untimedOnlySummary.joined()))
        #expect(ExportsFixture.bytes(try LogExports.summary("", "", nil, [])) == ExportsFixture.bytes(ExportsMeasured.emptySummary.joined()))
    }

    @Test func cellQuotesOnlyWhenNeeded() {
        #expect(LogExports.cell("") == "")
        #expect(LogExports.cell("abc") == "abc")
        #expect(LogExports.cell("a\r\nb") == "\"a\r\nb\"")
        #expect(LogExports.cell("\"\u{0301}") == "\"\"\"\u{0301}\"")
        #expect(LogExports.cell("\u{0301}") == "\u{0301}")
    }
}

/// `LogStatistics.pivot` — only the part needed by `LogExports.summary`;
/// measured over the same edge log for all dimensions.
@Suite struct LogStatisticsPivotTests {

    typealias PivotCase = (row: LogStatistics.Dimension, col: LogStatistics.Dimension, expected: [String])

    static let pivotCases: [PivotCase] = [
        (.BAND, .MODE, ExportsMeasured.pivot_BAND_MODE),
        (.MODE, .BAND, ExportsMeasured.pivot_MODE_BAND),
        (.HOUR, .COUNTRY, ExportsMeasured.pivot_HOUR_COUNTRY),
        (.DAY, .OPERATOR, ExportsMeasured.pivot_DAY_OPERATOR),
        (.CONTINENT, .RUN_SP, ExportsMeasured.pivot_CONTINENT_RUN_SP),
        (.NONE, .NONE, ExportsMeasured.pivot_NONE_NONE),
    ]

    @Test(arguments: pivotCases)
    func pivotMatchesJava(row: LogStatistics.Dimension, col: LogStatistics.Dimension, expected: [String]) {
        let p = LogStatistics.pivot(ExportsFixture.edgeLog(withUntimed: true), row, col)
        #expect(ExportsFixture.pivotText(p) == expected.joined())
    }

    @Test func missingCellsAreZero() {
        let p = LogStatistics.pivot([], .BAND, .MODE)
        #expect(p.rows.isEmpty && p.cols.isEmpty && p.total == 0)
        #expect(p.count("20m", "CW") == 0)
        #expect(p.rowTotal("20m") == nil)
    }

    /// Labels from `LogStatistics.Dimension` (Java v1.1.1).
    @Test func labels() {
        let labels = LogStatistics.Dimension.allCases.map(\.label)
        #expect(labels == ["Hodina UTC", "Den", "Pásmo", "Mód", "Kontinent", "Země", "Operátor", "Run / S&P", "—"])
    }
}

/// `UtcStamp` against `DateTimeFormatter.ofPattern(…).withZone(UTC)`: seconds truncated down,
/// a leap day, year 1 and before our era (year of era), year 10000 with a `+` sign.
@Suite struct UtcStampTests {

    @Test func matchesJavaDateTimeFormatter() throws {
        for line in ExportsMeasured.utcStamps {
            let parts = JavaText.trim(line).components(separatedBy: "|")
            let millis = try #require(Int64(parts[0]))
            let s = try #require(UtcStamp(Date(timeIntervalSince1970: Double(millis) / 1000)))
            let edi = s.yy + s.MM + s.dd + ";" + s.HH + s.mm + ";" + s.yyyy + s.MM + s.dd
            let time = LogExports.time(Date(timeIntervalSince1970: Double(millis) / 1000))
            #expect(ExportsFixture.bytes(time) == ExportsFixture.bytes(parts[1]), "\(millis)")
            let hour = s.MM + "-" + s.dd + " " + s.HH + "Z"
            #expect(ExportsFixture.bytes(edi) == ExportsFixture.bytes(parts[2]), "\(millis)")
            #expect(ExportsFixture.bytes(hour) == ExportsFixture.bytes(parts[3]), "\(millis)")
        }
    }

    /// Outside the `Int64` seconds range (Java cannot have such an `Instant`) → `nil`; the exports then write
    /// an empty time, the pivot `?` — like `AdifWriter`, which omits the date.
    @Test func outOfRangeIsMissingTime() {
        let far = Date(timeIntervalSince1970: 1e300)
        #expect(UtcStamp(far) == nil)
        #expect(LogExports.time(far).isEmpty)
        var q = Qso()
        q.timestampUtc = far
        #expect(LogStatistics.key(.HOUR, q) == "?")
    }
}

/// Guard against drift of inputs: `ExportsFixture` must build the **same** logs as the probe — otherwise
/// the `ExportsMeasured` reference would compare a different input.
@Suite struct ExportsFixtureDriftTests {

    typealias LogCase = (name: String, log: [Qso], java: [String])

    static let logCases: [LogCase] = [
        ("testLog", ExportsFixture.testLog(), ExportsMeasured.inputTestLog),
        ("edgeLog", ExportsFixture.edgeLog(withUntimed: true), ExportsMeasured.inputEdgeLog),
        ("edgeTimedLog", ExportsFixture.edgeLog(withUntimed: false), ExportsMeasured.inputEdgeTimedLog),
        ("ediTestLog", ExportsFixture.ediTestLog(), ExportsMeasured.inputEdiTestLog),
        ("ediEdgeLog", ExportsFixture.ediEdgeLog(), ExportsMeasured.inputEdiEdgeLog),
    ]

    static let logNames: [String] = logCases.map(\.name)

    /// The argument is just the log name — the failure output then does not contain the whole `Qso`.
    @Test(arguments: logNames)
    func inputsMatchProbe(name: String) throws {
        let entry = try #require(Self.logCases.first { $0.name == name })
        let (log, java) = (entry.log, entry.java)
        let swift = ExportsFixture.lines(log.map(ExportsFixture.inputLine).joined())
        let expected = java.map { ExportsFixture.bytes($0) }
        #expect(swift.count == expected.count, "\(name): number of rows")
        for (index, pair) in zip(swift, expected).enumerated() {
            #expect(pair.0 == pair.1, "\(name) row \(index): \(String(decoding: pair.0, as: UTF8.self))")
        }
    }
}
