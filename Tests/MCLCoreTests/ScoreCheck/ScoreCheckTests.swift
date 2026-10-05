import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `cli/ScoreCheckTest` — 12 tests of scoring and verdict (11 `evaluate`
/// and helpers + `verdictByTwoThresholds`). The remaining 14 tests of `ScoreCheckTest` (CLI options,
/// HTTP, reports) and the whole `BatchValidatorTest` (9) stay in Java.
///
/// The fixtures are byte-for-byte the same as in Java: `dxcc-test.json` via `DxccResolver` (without
/// `DxccSpecialCases`, like `ScoreCheckTest.setUp`) and `contest-data/`.
@Suite struct ScoreCheckTests {

    let dxcc: DxccResolver
    let registry: MultiplierSetRegistry
    let defs: [ContestDefinition]

    init() throws {
        dxcc = try SessionFixture.dxcc()
        registry = try SessionFixture.registry(dxcc)
        defs = try ContestCatalog.fromDir(SessionFixture.contestData().appendingPathComponent("contests"))
    }

    private func evaluate(_ file: String, _ content: String) throws -> ScoreCheck.Result {
        try ScoreCheck.evaluate(fileName: file, content: content, definitions: defs, dxcc: dxcc, registry: registry)
    }

    private static func log(_ claimed: Int) -> String {
        """
        START-OF-LOG: 3.0
        CONTEST: CQ-WW-SSB
        CALLSIGN: OK1XOE
        CLAIMED-SCORE: \(claimed)
        QSO: 14042 PH 2026-06-17 1200 OK1XOE 59 14 DL1ABC 59 14
        QSO: 14042 PH 2026-06-17 1201 OK1XOE 59 14 W1AW 59 05
        END-OF-LOG:

        """
    }

    // MARK: - port of ScoreCheckTest

    @Test func okWhenClaimedMatches() throws {
        // points 1+3=4, mult zones{14,5}=2 + countries{DE,US}=2 => 4*4 = 16
        let r = try evaluate("test.log", Self.log(16))
        #expect(r.contest == "CQ-WW-SSB")
        #expect(r.computed == 16)
        #expect(r.claimed == 16)
        #expect(r.pass)
    }

    @Test func failedWhenClaimedDiffers() throws {
        let r = try evaluate("test.log", Self.log(999))
        #expect(r.computed == 16)
        #expect(!r.pass)
    }

    @Test func failsOnUnknownContest() throws {
        let r = try evaluate("x.log", "CONTEST: NEZNAMY\nCLAIMED-SCORE: 0\nCALLSIGN: OK1XOE\n")
        #expect(!r.pass)
        #expect(r.error == "neznámý závod: NEZNAMY")
    }

    @Test func stripBlankRemovesNbspAndBom() {
        #expect(ScoreCheck.stripBlank("\u{00A0} CQ-WPX-SSB") == "CQ-WPX-SSB")   // NBSP after the colon
        #expect(ScoreCheck.stripBlank("\u{FEFF}X\u{00A0}") == "X")               // BOM + NBSP at the edges
        #expect(ScoreCheck.stripBlank("  Y  ") == "Y")                           // ordinary spaces
    }

    @Test func resolvesContestDespiteNbspHeader() throws {
        // CONTEST: <NBSP> CQ-WW-SSB — formerly "unknown contest" because of an untrimmed NBSP
        let log = Self.log(16).replacingOccurrences(of: "CONTEST: CQ-WW-SSB", with: "CONTEST:\u{00A0} CQ-WW-SSB")
        let r = try evaluate("nbsp.log", log)
        #expect(r.contest == "CQ-WW-SSB")
        #expect(r.error == nil)
        #expect(r.pass)
    }

    private static func wwDigiLog(_ claimed: Int) -> String {
        """
        START-OF-LOG: 3.0
        CONTEST: WW-DIGI
        CALLSIGN: OK1XOE
        CLAIMED-SCORE: \(claimed)
        QSO: 14074 DG 2025-08-30 1200 OK1XOE JO70 W1AW FN31
        QSO: 14074 DG 2025-08-30 1201 OK1XOE JO70 DL1ABC JO31
        END-OF-LOG:

        """
    }

    @Test func wwDigiDistancePointsAndGridFieldMultiplier() throws {
        // JO70→FN31 ≈ 6464 km → 3 b.; JO70→JO31 ≈ 570 km → 1 b. ⇒ 4 body
        // multiplier = fields {FN, JO} on 20m = 2 ⇒ score 4*2 = 8
        let r = try evaluate("wwdigi.log", Self.wwDigiLog(8))
        #expect(r.error == nil)
        #expect(r.qsoCount == 2)
        #expect(r.qsoPoints == 4, "distance points 3+1")
        #expect(r.multTotal == 2, "multiplier = 2-character fields {FN, JO}")
        #expect(r.computed == 8)
        #expect(r.pass)
    }

    @Test func wwDigiFieldMultiplierDedupedWithinBandPerBandAcross() throws {
        // the same field FN twice on 20m → 1×; field JO on 40m → +1 ⇒ multiplier 2
        let log = """
            CONTEST: WW-DIGI
            CALLSIGN: OK1XOE
            CLAIMED-SCORE: 1
            QSO: 14074 DG 2025-08-30 1200 OK1XOE JO70 W1AW   FN31
            QSO: 14074 DG 2025-08-30 1201 OK1XOE JO70 K2ABC  FN20
            QSO:  7074 DG 2025-08-30 1202 OK1XOE JO70 DL1ABC JO01
            END-OF-LOG:

            """
        let r = try evaluate("wwdigi2.log", log)
        #expect(r.error == nil)
        #expect(r.multTotal == 2, "field FN on 20m once + field JO on 40m = 2 (per band, 2-character)")
    }

    @Test func cqWpxNorthAmericaPointException() throws {
        // W1AW (US/NA): VE3 20m NA↔NA=2, VE2 40m NA↔NA=4, DL1 20m other continent=3, K2 same country=1 ⇒ 10
        // multipliers = prefixes {VE3, VE2, DL1, K2} = 4 ⇒ score 40
        let log = """
            START-OF-LOG: 3.0
            CONTEST: CQ-WPX-CW
            CALLSIGN: W1AW
            CLAIMED-SCORE: 40
            QSO: 14000 CW 2025-05-24 1200 W1AW 599 1 VE3XYZ 599 1
            QSO:  7000 CW 2025-05-24 1201 W1AW 599 2 VE2ABC 599 2
            QSO: 14000 CW 2025-05-24 1202 W1AW 599 3 DL1ABC 599 3
            QSO: 14000 CW 2025-05-24 1203 W1AW 599 4 K2XX 599 4
            END-OF-LOG:

            """
        let r = try evaluate("wpx.log", log)
        #expect(r.error == nil)
        #expect(r.qsoPoints == 10, "NA exception: NA↔NA 2/4 pts, same country 1 pt")
        #expect(r.multTotal == 4)
        #expect(r.computed == 40)
        #expect(r.pass)
    }

    @Test func resolvesContestWithTrailingYear() throws {
        // CONTEST: CQ-WW-SSB 2005 — the year in the header formerly "unknown contest"
        let log = Self.log(16).replacingOccurrences(of: "CONTEST: CQ-WW-SSB", with: "CONTEST: CQ-WW-SSB 2005")
        let r = try evaluate("year.log", log)
        #expect(r.error == nil, "the year in the header must not prevent recognising the contest")
        #expect(r.computed == 16)
        #expect(r.pass)
    }

    @Test func resolvesContestWithHyphenYear() throws {
        // CONTEST: CQ-WW-SSB-2005 — the hyphen variant
        let log = Self.log(16).replacingOccurrences(of: "CONTEST: CQ-WW-SSB", with: "CONTEST: CQ-WW-SSB-2005")
        let r = try evaluate("hyear.log", log)
        #expect(r.error == nil)
        #expect(r.pass)
    }

    @Test func verdictByTwoThresholds() throws {
        let near = ScoreCheck.Result(file: "f", contest: "C", qsoCount: 1, qsoPoints: 100, multTotal: 10,
                                     multByGroup: JavaLinkedMap(), computed: 990, claimed: 1000, pass: false,
                                     unresolvedCalls: [], error: nil) // -1 %
        let nearDiffPct = try #require(near.diffPct)
        #expect(abs(nearDiffPct - -1.0) <= 0.001)
        #expect(near.verdict(okPct: 1.0, failPct: 3.0) == .ok)       // do 1 % = OK
        #expect(near.verdict(okPct: 0.5, failPct: 3.0) == .close)    // 0.5 < 1 ≤ 3 = CLOSE
        #expect(near.verdict(okPct: 0.0, failPct: 0.5) == .failed)   // nad 0,5 = FAILED

        let far = ScoreCheck.Result(file: "f", contest: "C", qsoCount: 1, qsoPoints: 100, multTotal: 10,
                                    multByGroup: JavaLinkedMap(), computed: 900, claimed: 1000, pass: false,
                                    unresolvedCalls: [], error: nil) // -10 %
        #expect(far.verdict(okPct: 1.0, failPct: 3.0) == .failed)
    }

    @Test func skipsChecklogAndMissingClaimed() {
        #expect(ScoreCheck.isChecklog("CONTEST: CQ-WW-SSB\nCATEGORY-OPERATOR: CHECKLOG\n"))
        #expect(ScoreCheck.isChecklog("CATEGORY: CHECKLOG\n"))
        #expect(!ScoreCheck.isChecklog("CATEGORY-POWER: HIGH\n"))

        #expect(ScoreCheck.skipReason("CATEGORY: CHECKLOG\nCLAIMED-SCORE: 100\n") == "checklog")
        #expect(ScoreCheck.skipReason("CONTEST: CQ-WW-SSB\nQSO: x\n") == "bez CLAIMED-SCORE")
        #expect(ScoreCheck.skipReason("CONTEST: CQ-WW-SSB\nCLAIMED-SCORE: 100\nQSO: x\n") == nil)
    }

    // MARK: - verdict outside the Java tests

    @Test func verdictEdges() {
        func result(computed: Int64, claimed: Int64?, pass: Bool, error: String? = nil) -> ScoreCheck.Result {
            ScoreCheck.Result(file: "f", contest: nil, qsoCount: 0, qsoPoints: 0, multTotal: 0,
                              multByGroup: JavaLinkedMap(), computed: computed, claimed: claimed, pass: pass,
                              unresolvedCalls: [], error: error)
        }
        // claimed 0 and a match: pass → OK, even though the deviation cannot be computed
        #expect(result(computed: 0, claimed: 0, pass: true).verdict(okPct: 0, failPct: 3) == .ok)
        #expect(result(computed: 5, claimed: 0, pass: false).diffPct == nil)
        #expect(result(computed: 5, claimed: 0, pass: false).verdict(okPct: 0, failPct: 3) == .failed)
        #expect(result(computed: 5, claimed: nil, pass: false).verdict(okPct: 0, failPct: 3) == .failed)
        #expect(result(computed: 1000, claimed: 1000, pass: false, error: "x").verdict(okPct: 0, failPct: 3) == .failed)
        // Java `computed - claimed` in `long` wraps (only then to double)
        let wrapped = result(computed: Int64.min, claimed: 1, pass: false).diffPct
        #expect(wrapped == 100.0 * Double(Int64.max) / 1.0)
    }

    // MARK: - an error of the whole log (an exception anywhere in evaluate)

    /// A sequence-number overflow in WPX (Java `NumberFormatException` from `ExchangeEngine`)
    /// discards the **whole** log — not even the QSOs before it are counted.
    @Test func serialOverflowFailsWholeLog() throws {
        let log = "CONTEST: CQ-WPX-CW\nCALLSIGN: W1AW\nCLAIMED-SCORE: 1\n"
            + "QSO: 14000 CW 2025-05-24 1200 W1AW 599 1 VE3XYZ 599 1\n"
            + "QSO: 14000 CW 2025-05-24 1201 W1AW 599 2 DL1ABC 599 4294967295\n"
        #expect(throws: ScoreCheck.Failure(javaClass: "NumberFormatException",
                                           message: "For input string: \"4294967295\"")) {
            try evaluate("wpx.log", log)
        }
        let outcome = ScoreCheck.check(fileName: "wpx.log", content: log, definitions: defs, dxcc: dxcc,
                                       registry: registry)
        #expect(outcome.status == .exception)
        #expect(outcome.exceptionClass == "NumberFormatException")
        #expect(outcome.result.error == "For input string: \"4294967295\"")
        #expect(outcome.result.contest == nil)
        #expect(outcome.result.claimed == nil)
        #expect(outcome.result.qsoCount == 0)
    }

    /// An error in the `scoring.total` expression (Java `IllegalArgumentException` from `score()`) and an error
    /// in the station-class expression (from `activeReceivedFields`) — both an error of the whole log; the error types
    /// of the session API (`ExpressionError` / `ContestSessionError`) are unified here into `Failure`.
    @Test func expressionErrorsFailWholeLog() throws {
        let badTotal = try ContestDefinitionLoader.load(Data("""
            id: bad-total
            modes: [CW]
            exchange: { received: [ { id: rst, type: RST } ] }
            scoring: { total: "qsoPoints +" }
            cabrillo: { contestName: BAD-TOTAL, sentOrder: [rst], receivedOrder: [rst] }
            """.utf8))
        let badClass = try ContestDefinitionLoader.load(Data("""
            id: bad-class
            modes: [CW]
            stationClasses: [ { id: x, when: { expr: "1 +" } } ]
            exchange: { received: [ { id: rst, type: RST } ] }
            cabrillo: { contestName: BAD-CLASS, sentOrder: [rst], receivedOrder: [rst] }
            """.utf8))
        let defs = [badTotal, badClass]
        for name in ["BAD-TOTAL", "BAD-CLASS"] {
            let log = "CONTEST: \(name)\nCALLSIGN: OK1XOE\nQSO: 14000 CW 2025-05-24 1200 OK1XOE 599 DL1ABC 599\n"
            let outcome = ScoreCheck.check(fileName: "x.log", content: log, definitions: defs, dxcc: dxcc,
                                           registry: registry)
            #expect(outcome.status == .exception, "\(name)")
            #expect(outcome.exceptionClass == "IllegalArgumentException", "\(name)")
            #expect(outcome.result.error != nil, "\(name)")
        }
    }

    /// A `nil` item of `scoring.qsoPoints.rules` before a `perKm` rule: Java (measured by the probe
    /// `ProbeScoreCheck`, JDK 21) crashes in `usesPerKm` with a `NullPointerException` "Cannot invoke
    /// "…ContestDefinition$PointRule.value()" because "r" is null" → `EXC` of the whole log. Swift
    /// returns an error of the same category with its own text (a deliberate divergence from Java v1.1.1).
    @Test func nilPointRuleFailsWholeLogLikeJavaNpe() throws {
        let def = try ContestDefinitionLoader.load(Data("""
            id: null-rule
            modes: [CW]
            exchange: { received: [ { id: rst, type: RST } ] }
            scoring:
              qsoPoints:
                default: 1
                rules: [ ~, { when: {}, value: { perKm: { field: grid, factor: 1 } } } ]
            cabrillo: { contestName: NULL-RULE, sentOrder: [rst], receivedOrder: [rst] }
            """.utf8))
        let log = "CONTEST: NULL-RULE\nCALLSIGN: OK1XOE\nQSO: 14000 CW 2025-05-24 1200 OK1XOE 599 DL1ABC 599\n"
        let outcome = ScoreCheck.check(fileName: "nr.log", content: log, definitions: [def], dxcc: dxcc,
                                       registry: registry)
        #expect(outcome.status == .exception)
        #expect(outcome.exceptionClass == "NullPointerException")
        #expect(outcome.result.error == "null prvek scoring.qsoPoints.rules")
        #expect(outcome.result.qsoCount == 0)
    }

    @Test func failureCategoriesFollowJavaExceptionClasses() {
        let nfe = ContestSessionError.exchange(ExchangeError(kind: .numberFormat, message: "m"))
        #expect(ScoreCheck.Failure(nfe).javaClass == "NumberFormatException")
        let pse = ContestSessionError.exchange(ExchangeError(kind: .patternSyntax, message: "m"))
        #expect(ScoreCheck.Failure(pse).javaClass == "PatternSyntaxException")
        let iae = ExpressionError(kind: .illegalArgument, message: "m")
        #expect(ScoreCheck.Failure(iae).javaClass == "IllegalArgumentException")
        #expect(ScoreCheck.Failure(ExpressionError(kind: .numberFormat, message: "m")).javaClass
            == "NumberFormatException")
        #expect(ScoreCheck.Failure(ExpressionError(kind: .patternSyntax, message: "m")).javaClass
            == "PatternSyntaxException")
        #expect(ScoreCheck.Failure(ExpressionError(kind: .nestingTooDeep, message: "m")).javaClass
            == "StackOverflowError")
        let mult = ContestSessionError.multiplier(.failure("Neznámá sada násobičů: x"))
        #expect(ScoreCheck.Failure(mult).javaClass == "MultiplierException")
        #expect(ScoreCheck.Failure(mult).message == "Neznámá sada násobičů: x")
    }

    // MARK: - decoding and DXCC selection

    /// `scoreCheck` reads UTF-8 strictly (`Files.readString`): an invalid sequence = "nelze načíst";
    /// a leading BOM stays a character (it is removed only by `stripBlank` in the header).
    @Test func strictUtf8KeepsBom() throws {
        #expect(ScoreCheck.decode(Data([0xEF, 0xBB, 0xBF, 0x41])) == "\u{FEFF}A")
        #expect(ScoreCheck.decode(Data([0x41, 0xFF])) == nil)
        #expect(ScoreCheck.decode(Data([0xED, 0xA0, 0x80])) == nil)   // a surrogate in UTF-8
        #expect(ScoreCheck.decode(Data()) == "")
        let outcome = ScoreCheck.check(fileName: "bad.log", data: Data([0x43, 0xFF]), definitions: defs,
                                       dxcc: dxcc, registry: registry)
        #expect(outcome.status == .unreadable)
        #expect(outcome.result.error == "nelze načíst")
        #expect(outcome.skipReason == nil)
    }

    @Test func loadDxccPrefersCtyDatAndFallsBackToJson() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scorecheck-dxcc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let json = root.appendingPathComponent("json")
        let both = root.appendingPathComponent("both")
        let ctyDir = root.appendingPathComponent("ctydir")
        let none = root.appendingPathComponent("none")
        let badJson = root.appendingPathComponent("badjson")
        for dir in [json, both, ctyDir, none, badJson] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let jsonData = try DxccTestFixture.data()
        let ctyData = try ScoreCheckMeasuredTests.ctyMini()
        try jsonData.write(to: json.appendingPathComponent("dxcc.json"))
        try jsonData.write(to: both.appendingPathComponent("dxcc.json"))
        try ctyData.write(to: both.appendingPathComponent("cty.dat"))
        // a cty.dat that cannot be read (a directory) → falls back to dxcc.json
        try FileManager.default.createDirectory(at: ctyDir.appendingPathComponent("cty.dat"),
                                                withIntermediateDirectories: true)
        try jsonData.write(to: ctyDir.appendingPathComponent("dxcc.json"))
        try Data("{".utf8).write(to: badJson.appendingPathComponent("dxcc.json"))

        let j = try #require(ScoreCheck.loadDxcc(directory: json))
        #expect(j.source == .dxccJson)
        #expect(j.lookup.resolve("OK1XOE") != nil)
        #expect(j.lookup.resolve("TC1A") == nil)   // Turkey is only in the mini cty.dat
        let b = try #require(ScoreCheck.loadDxcc(directory: both))
        #expect(b.source == .ctyDat)
        #expect(b.lookup.resolve("TC1A")?.primaryPrefix == "TA")   // only in the mini cty.dat
        #expect(ScoreCheck.loadDxcc(directory: ctyDir)?.source == .dxccJson)
        #expect(ScoreCheck.loadDxcc(directory: none) == nil)
        #expect(ScoreCheck.loadDxcc(directory: badJson) == nil)
    }
}
