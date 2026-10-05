import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ContestValidatorTest` (1 `@Test` + 6 parameterised) and new
/// cases with findings measured by the probe `ProbeVal.java` (maintainer-only probe,
/// JDK 21). The order of findings and their texts are a contract — the definition editor shows them
/// in order and `DefinitionUpdater` reports the first of them.
@Suite struct ContestValidatorTests {

    // MARK: - Java ContestValidatorTest

    @Test(arguments: ["cq-ww-cw", "cq-ww-ssb", "cq-wpx-cw", "cq-160-cw", "ok-om-dx-cw", "dx"])
    func bundledDefinitionsAreValid(_ id: String) throws {
        let definition = try ContestDefinitionLoaderTests.bundled(id + ".yaml")
        let report = ContestValidator.validate(definition)
        #expect(report.isValid, "contest \(id) has errors:\n\(report)")
    }

    @Test func brokenDefinitionReportsErrors() throws {
        let definition = try ContestDefinitionLoader.loadFile(Self.brokenFixture())
        let report = ContestValidator.validate(definition)
        #expect(!report.isValid, "a broken definition must have errors")
        #expect(report.errors.count >= 2, "expected more errors, got: \(report.errors)")
        #expect(report.issues.count >= report.errors.count,
                "the overall list of findings must contain all errors")
        // Beyond Java: the exact list measured on JDK 21.
        #expect(Self.lines(report) == [
            "[WARNING] chybí metadata.name",
            "[ERROR] pole 'rst' má neplatný regex: Unclosed character class near index 0\n[\n^",
            "[ERROR] pole 'zone' odkazuje na nedefinovanou stationClass 'nonexistent'",
            "[ERROR] multiplier 'm1' from='nosuchfield' není 'callsign' ani id přijatého exchange pole",
            "[ERROR] cabrillo.sentOrder odkazuje na neexistující sent pole 'rst'",
        ])
        #expect(report.errors.count == 4)
    }

    /// Beyond Java: all 22 definitions from `contest-data/contests/` have no findings
    /// in Java (measured by `ProbeVal`), and so in Swift too.
    @Test func allBundledDefinitionsHaveNoFindings() throws {
        let definitions = try ContestCatalog.fromDir(ContestDefinitionLoaderTests.contestsDir())
        #expect(definitions.count == 22)
        for definition in definitions {
            let report = ContestValidator.validate(definition)
            #expect(report.issues.isEmpty, "contest \(definition.id ?? "?") has findings:\n\(report)")
        }
    }

    // MARK: - helpers

    static func brokenFixture() throws -> URL {
        let dir = try #require(Bundle.module.url(forResource: "contests-broken", withExtension: nil))
        return dir.appendingPathComponent("broken.yaml")
    }

    static func lines(_ report: ValidationReport) -> [String] {
        report.issues.map { "[\($0.severity)] \($0.message)" }
    }

    static func validate(_ yaml: String) throws -> ValidationReport {
        ContestValidator.validate(try ContestDefinitionLoader.load(Data(yaml.utf8)))
    }

    /// Common base without findings (sections the given case does not examine).
    static let base = """
        schemaVersion: 1
        id: t
        metadata: { name: T }
        bands: [20m]
        modes: [CW]
        scoring: { qsoPoints: { mode: SUM }, total: q }
        cabrillo: { contestName: X }

        """

    // MARK: - order and texts of findings (measured)

    /// `{}` → exactly 8 findings in check order (source 3.5).
    @Test func emptyObjectGivesEightFindingsInOrder() throws {
        let report = try Self.validate("{}")
        #expect(Self.lines(report) == [
            "[ERROR] schemaVersion musí být kladné",
            "[ERROR] chybí id závodu",
            "[WARNING] chybí metadata.name",
            "[ERROR] chybí bands",
            "[ERROR] chybí modes",
            "[ERROR] chybí exchange",
            "[ERROR] chybí scoring",
            "[WARNING] chybí cabrillo (export nebude možný)",
        ])
        #expect(report.errors.count == 6)
        #expect(report.hasErrors)
    }

    /// A duplicate is reported at the second (and every further) occurrence, before its own errors.
    @Test func duplicateMultiplierReportedAtSecondOccurrenceFirst() throws {
        let report = try Self.validate(Self.base + """
            exchange: { received: [ { id: r, type: RST } ] }
            multipliers:
              - { id: m, set: s, scope: PER_BAND, from: callsign }
              - { id: m }
              - { id: m, set: s, scope: ONCE, from: r }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] duplicitní multiplier id 'm'",
            "[ERROR] multiplier 'm' nemá set",
            "[ERROR] multiplier 'm' nemá scope",
            "[ERROR] multiplier 'm' nemá from",
            "[ERROR] duplicitní multiplier id 'm'",
        ])
    }

    @Test func validDefinitionHasNoFindings() throws {
        let report = try Self.validate(Self.base + "exchange: { received: [ { id: r, type: RST } ] }")
        #expect(report.issues.isEmpty)
        #expect(report.isValid)
        #expect(!report.hasErrors)
        #expect(report.description == "OK (bez nálezů)")
    }

    @Test func nilDefinition() {
        let report = ContestValidator.validate(nil)
        #expect(Self.lines(report) == ["[ERROR] definice je null"])
        #expect(report.description == "[ERROR] definice je null\n")
    }

    /// Java `toString`: a line "[SEVERITY] message\n" for every finding.
    @Test func descriptionMatchesJavaToString() throws {
        let report = try Self.validate("{}")
        #expect(report.description == """
            [ERROR] schemaVersion musí být kladné
            [ERROR] chybí id závodu
            [WARNING] chybí metadata.name
            [ERROR] chybí bands
            [ERROR] chybí modes
            [ERROR] chybí exchange
            [ERROR] chybí scoring
            [WARNING] chybí cabrillo (export nebude možný)

            """)
        #expect(report.errors == [
            "schemaVersion musí být kladné", "chybí id závodu", "chybí bands",
            "chybí modes", "chybí exchange", "chybí scoring",
        ])
    }

    // MARK: - null versus "" (source 7.4, ContestValidator lines)

    @Test func emptyStrings() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: ''
            metadata: { name: '' }
            bands: [20m]
            modes: [CW]
            exchange: { received: [ { id: r, type: RST, validation: { regex: '' }, appliesWhen: { workedClass: '' } } ] }
            scoring: { qsoPoints: { mode: SUM }, total: '' }
            multipliers: [ { id: m, set: '', scope: ONCE, from: '' } ]
            cabrillo: { contestName: X }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] chybí id závodu",
            "[WARNING] chybí metadata.name",
            "[ERROR] pole 'r' odkazuje na nedefinovanou stationClass ''",
            "[ERROR] chybí scoring.total (formule)",
            "[ERROR] multiplier 'm' nemá set",
            "[ERROR] multiplier 'm' nemá from",
        ])
    }

    @Test func nullStrings() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: ~
            metadata: { name: ~ }
            bands: [20m]
            modes: [CW]
            exchange: { received: [ { id: r, type: RST, validation: { regex: ~ }, appliesWhen: { workedClass: ~ } } ] }
            scoring: { qsoPoints: { mode: SUM }, total: ~ }
            multipliers: [ { id: m, set: ~, scope: ONCE, from: ~ } ]
            cabrillo: { contestName: X }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] chybí id závodu",
            "[WARNING] chybí metadata.name",
            "[ERROR] chybí scoring.total (formule)",
            "[ERROR] multiplier 'm' nemá set",
            "[ERROR] multiplier 'm' nemá from",
        ])
    }

    /// `stationClass` with `id: ""` is added to the set, so `workedClass: ""` passes;
    /// it itself then gets "stationClass bez id".
    @Test func emptyStationClassIdSatisfiesEmptyWorkedClass() throws {
        let report = try Self.validate(Self.base + """
            stationClasses: [ { id: '' } ]
            exchange: { received: [ { id: r, type: RST, appliesWhen: { workedClass: '' } } ] }
            multipliers: [ { id: m, set: s, scope: ONCE, from: r, appliesWhen: { workedClass: '' } } ]
            """)
        #expect(Self.lines(report) == ["[ERROR] stationClass bez id"])
    }

    /// `nil` list elements: Java handles them (`f == null`, `m == null`, `sc == null`)
    /// and prints `'null'` in the `cabrillo` order.
    @Test func nullListElements() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: t
            metadata: { name: T }
            bands: [ ~ ]
            modes: [CW]
            scoring: { qsoPoints: { mode: SUM }, total: q }
            stationClasses: [ ~ ]
            exchange: { sent: [ ~ ], received: [ ~ ] }
            multipliers: [ ~ ]
            cabrillo: { contestName: X, sentOrder: [ ~ ], receivedOrder: [ ~ ] }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] exchange.sent obsahuje pole bez id",
            "[ERROR] exchange.received obsahuje pole bez id",
            "[ERROR] multiplier bez id",
            "[ERROR] cabrillo.sentOrder odkazuje na neexistující sent pole 'null'",
            "[ERROR] cabrillo.receivedOrder odkazuje na neexistující received pole 'null'",
            "[ERROR] stationClass bez id",
        ])
    }

    @Test func emptySections() throws {
        let report = try Self.validate("""
            schemaVersion: -1
            id: t
            metadata: {}
            bands: []
            modes: []
            exchange: {}
            scoring: {}
            """)
        #expect(Self.lines(report) == [
            "[ERROR] schemaVersion musí být kladné",
            "[WARNING] chybí metadata.name",
            "[ERROR] chybí bands",
            "[ERROR] chybí modes",
            "[ERROR] exchange.received nesmí být prázdné",
            "[ERROR] chybí scoring.qsoPoints",
            "[ERROR] chybí scoring.total (formule)",
            "[WARNING] chybí cabrillo (export nebude možný)",
        ])
    }

    @Test func emptyQsoPointsAndReceived() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: t
            metadata: { name: T }
            bands: [20m]
            modes: [CW]
            cabrillo: { contestName: X }
            exchange: { received: [] , sent: [ { type: RST } ] }
            scoring: { qsoPoints: {} }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] exchange.received nesmí být prázdné",
            "[ERROR] exchange.sent obsahuje pole bez id",
            "[ERROR] scoring.qsoPoints.mode musí být FIRST_MATCH nebo SUM",
            "[ERROR] chybí scoring.total (formule)",
        ])
    }

    /// All sections at once: order sent → received → scoring → multipliers →
    /// cabrillo → stationClasses.
    @Test func fullOrder() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: t
            metadata: { name: T }
            bands: [20m]
            modes: [CW]
            stationClasses: [ { id: W }, { id: ~ } ]
            exchange:
              sent: [ { id: s1 }, { id: '' } ]
              received: [ { id: r1, appliesWhen: { workedClass: X } }, ~ ]
            scoring: { qsoPoints: {}, total: ' ' }
            multipliers:
              - { id: m1, from: zz, appliesWhen: { workedClass: Y } }
              - { id: m1, set: s, scope: ONCE, from: r1 }
              - ~
            cabrillo: { sentOrder: [s1, x, ''], receivedOrder: [r1, y] }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] pole 's1' nemá type",
            "[ERROR] exchange.sent obsahuje pole bez id",
            "[ERROR] pole 'r1' nemá type",
            "[ERROR] pole 'r1' odkazuje na nedefinovanou stationClass 'X'",
            "[ERROR] exchange.received obsahuje pole bez id",
            "[ERROR] scoring.qsoPoints.mode musí být FIRST_MATCH nebo SUM",
            "[ERROR] chybí scoring.total (formule)",
            "[ERROR] multiplier 'm1' nemá set",
            "[ERROR] multiplier 'm1' nemá scope",
            "[ERROR] multiplier 'm1' from='zz' není 'callsign' ani id přijatého exchange pole",
            "[ERROR] multiplier 'm1' odkazuje na nedefinovanou stationClass 'Y'",
            "[ERROR] duplicitní multiplier id 'm1'",
            "[ERROR] multiplier bez id",
            "[ERROR] cabrillo.sentOrder odkazuje na neexistující sent pole 'x'",
            "[ERROR] cabrillo.receivedOrder odkazuje na neexistující received pole 'y'",
            "[ERROR] stationClass bez id",
        ])
    }

    @Test func missingCabrilloIsWarningOnly() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: t
            bands: [20m]
            modes: [CW]
            exchange: { received: [ { id: r, type: RST } ] }
            scoring: { qsoPoints: { mode: SUM }, total: q }
            stationClasses: [ ~ ]
            """)
        #expect(Self.lines(report) == [
            "[WARNING] chybí metadata.name",
            "[WARNING] chybí cabrillo (export nebude možný)",
            "[ERROR] stationClass bez id",
        ])
    }

    // MARK: - period.sessions (via Tour.parse)

    static let sessionsMessage = "[ERROR] period.sessions: start musí být hhmm (UTC) a minutes aspoň 5"

    @Test(arguments: [
        ("{ start: '1200', minutes: 30 }", true),
        ("{ minutes: 30 }", false),
        ("{ start: '1200' }", false),
        ("{ start: '1200', minutes: 4 }", false),
        ("{}", false),
        ("{ start: ' 0000 ', minutes: 1440 }", false),  // " 0000 /1440" → trim leaves a space before "/"
        ("{ start: '2400', minutes: -30 }", false),
    ])
    func sessions(_ sessions: String, valid: Bool) throws {
        let report = try Self.validate(Self.base + """
            exchange: { received: [ { id: r, type: RST } ] }
            period: { sessions: \(sessions) }
            """)
        #expect(Self.lines(report) == (valid ? [] : [Self.sessionsMessage]))
    }

    // MARK: - regex, from, blank

    /// Syntax errors: text exactly like Java `PatternSyntaxException.getMessage()`.
    @Test func invalidRegexUsesJavaMessage() throws {
        let report = try Self.validate(Self.base + #"""
            exchange:
              received:
                - { id: a, type: RST, validation: { regex: '[' } }
                - { id: b, type: RST, validation: { regex: 'a{2,1}' } }
                - { id: c, type: RST, validation: { regex: '(?<x>a)(?<x>b)' } }
                - { id: d, type: RST, validation: { regex: "\tx(" } }
                - { id: g, type: RST, validation: { regex: '\d+' } }
                - { id: h, type: RST, validation: { regex: '*' } }
            """#)
        #expect(Self.lines(report) == [
            "[ERROR] pole 'a' má neplatný regex: Unclosed character class near index 0\n[\n^",
            "[ERROR] pole 'b' má neplatný regex: Illegal repetition range near index 5\na{2,1}\n     ^",
            "[ERROR] pole 'c' má neplatný regex: Named capturing group <x> is already defined near index 11\n(?<x>a)(?<x>b)\n           ^",
            "[ERROR] pole 'd' má neplatný regex: Unclosed group near index 3\n\tx(",
            "[ERROR] pole 'h' má neplatný regex: Dangling meta character '*' near index 0\n*\n^",
        ])
    }

    /// Recorded divergence: constructs the `JavaRegex`
    /// adapter does not translate, Java accepts (no finding), Swift reports an ERROR with the
    /// adapter's text.
    @Test func unsupportedRegexIsErrorUnlikeJava() throws {
        let report = try Self.validate(Self.base + #"""
            exchange:
              received:
                - { id: e, type: RST, validation: { regex: '\p{javaLowerCase}' } }
                - { id: f, type: RST, validation: { regex: '(?x) a' } }
            """#)
        let lines = Self.lines(report)
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("[ERROR] pole 'e' má neplatný regex: vlastnost \\p{javaLowerCase}") == true)
        #expect(lines.last?.hasPrefix("[ERROR] pole 'f' má neplatný regex: příznak (?x)") == true)
    }

    /// `"callsign".equalsIgnoreCase(from)` by units: `ſ` and `İ` pass, a space does not.
    @Test func fromCallsignIgnoresCaseLikeJava() throws {
        let report = try Self.validate(Self.base + """
            exchange: { received: [ { id: r, type: RST } ] }
            multipliers:
              - { id: a, set: s, scope: ONCE, from: CALLSIGN }
              - { id: b, set: s, scope: ONCE, from: "CALL\\u017fIGN" }
              - { id: c, set: s, scope: ONCE, from: "callS\\u0130gn" }
              - { id: d, set: s, scope: ONCE, from: R }
              - { id: e, set: s, scope: ONCE, from: ' callsign' }
            """)
        #expect(Self.lines(report) == [
            "[ERROR] multiplier 'd' from='R' není 'callsign' ani id přijatého exchange pole",
            "[ERROR] multiplier 'e' from=' callsign' není 'callsign' ani id přijatého exchange pole",
        ])
    }

    /// `isBlank` like Java: U+2003, U+3000 and U+001C are blank, NBSP is not.
    @Test func blankIsJavaIsBlank() throws {
        let report = try Self.validate("""
            schemaVersion: 1
            id: "\\u00a0"
            metadata: { name: "\\u2003" }
            bands: [20m]
            modes: [CW]
            scoring: { qsoPoints: { mode: SUM }, total: q }
            cabrillo: { contestName: X }
            exchange: { received: [ { id: "\\u2003", type: RST }, { id: "\\u00a0" } ] }
            multipliers: [ { id: "\\u3000" } ]
            stationClasses: [ { id: "\\u001c" } ]
            """)
        #expect(Self.lines(report) == [
            "[WARNING] chybí metadata.name",
            "[ERROR] exchange.received obsahuje pole bez id",
            "[ERROR] pole '\u{00A0}' nemá type",
            "[ERROR] multiplier bez id",
            "[ERROR] stationClass bez id",
        ])
    }
}
