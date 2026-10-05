import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `CountyListImportTest` (2 cases) and cases measured by the probe
/// `ProbeCounty.java` (maintainer-only probe, JDK 21). The output of `write` and
/// `qsoPartyTemplate` is compared **byte for byte** with what Java produced.
@Suite struct CountyListImportTests {

    static func pairs(_ lines: [String]) -> [String] {
        CountyListImport.parse(lines).map { "\($0.code)=\($0.label)" }
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountyListImportTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Java CountyListImportTest

    @Test func parsesVariousSeparators() {
        let parsed = CountyListImport.parse(["# seznam", "Code,County", "adam,Adams", "ALLE;Allen",
                                             "ASHL\tAshland", "ASHT Ashtabula", "adam,Dup"])
        #expect(parsed.map(\.code) == ["ADAM", "ALLE", "ASHL", "ASHT"])
        #expect(parsed[0].label == "Adams")
    }

    @Test func writesLoadableSetAndTemplateIsValid() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mult = dir.appendingPathComponent("multipliers")
        // Java `Map.of` has no order; Swift takes the array order.
        #expect(try CountyListImport.write(mult, setId: "xqp_counties", name: "X QSO Party",
                                           values: [(code: "AAA", label: "Alpha"), (code: "BBB", label: "Beta")]) == 2)
        let dxcc = try DxccResolver.fromData(DxccTestFixture.data())
        let registry = try MultiplierSetRegistry(dxcc: dxcc).loadDir(mult)
        let set = try registry.get("xqp_counties")
        #expect(set.isExpected("aaa"))
        #expect(!set.isExpected("ZZZ"))
        #expect(throws: CountyListImportError.self) {
            try CountyListImport.write(mult, setId: "Bad Id", name: "x", values: [(code: "A", label: "a")])
        }
        let yaml = CountyListImport.qsoPartyTemplate("xqp", "X QSO Party", "xqp_counties")
        let check = DefinitionEditing.check(yaml, fileId: "xqp", knownSets: ["xqp_counties", "na_areas"])
        #expect(!check.hasErrors, "\(check.issues)")
    }

    // MARK: - parse (measured)

    @Test func measuredParseCases() {
        #expect(Self.pairs(["ab , Alpha, Beta"]) == ["AB=Alpha  Beta"])          // two spaces
        #expect(Self.pairs(["CD  Charlie Delta"]) == ["CD=Charlie Delta"])
        #expect(Self.pairs(["Eé;x"]).isEmpty)                                     // É outside [A-Z]
        #expect(Self.pairs(["TOOLONGCODE1,x"]).isEmpty)
        #expect(Self.pairs(["ONLY"]) == ["ONLY=ONLY"])
        #expect(Self.pairs(["12/3-X\tq"]) == ["12/3-X=q"])
        #expect(Self.pairs(["AB,"]) == ["AB="])                                   // an empty label is kept
        #expect(Self.pairs(["KÓD,x"]).isEmpty)
        #expect(Self.pairs(["Code,County", "KEY,x", "abbr,x", "ABBREV,x", "Zkratka,x", "kod,x"]).isEmpty)
        #expect(Self.pairs(["  # c", "", "   "]).isEmpty)
    }

    @Test func firstOccurrenceWinsAndOrderIsKept() {
        #expect(Self.pairs(["zz,1", "aa,2", "ZZ,3", "m,4", "aa,5"]) == ["ZZ=1", "AA=2", "M=4"])
    }

    @Test func javaStripAndTrimDifferences() {
        // strip() removes U+3000, but `\s` and trim() do not: the code "ZZ\u{3000}" does not pass the regex.
        #expect(Self.pairs(["\u{3000}zz\u{3000},\u{3000}L\u{3000}"]).isEmpty)
        // trim() strips control characters from the code: "AB\u{01}" is the code AB.
        #expect(Self.pairs(["ab\u{01},x"]) == ["AB=x"])
        // `ı` (U+0131) becomes I under the full toUpperCase.
        #expect(Self.pairs(["ıx,y"]) == ["IX=y"])
        #expect(Self.pairs(["straße,z"]) == ["STRASSE=z"])
    }

    @Test func commasInLabelAreReplacedPerScalar() {
        #expect(Self.pairs(["a,\u{301}b,c"]) == ["A=\u{301}b c"])   // comma + combining character
        #expect(Self.pairs(["q , , r"]) == ["Q=  r"])
        #expect(Self.pairs(["cd;;e"]) == ["CD=;e"])
    }

    @Test func hashIsDetectedOnFirstUtf16UnitOnly() {
        // Swift `hasPrefix("#")` would not recognise "#" + a combining character as a comment; Java does.
        #expect(Self.pairs(["#\u{301}ab,x"]).isEmpty)
    }

    // MARK: - write (byte for byte against Java)

    static let expectedCsv = "# X \"Q\" Party é (key,label) — importováno\nZZ,Zed\nAA,Ay, é é\nM,\n"
    static let expectedYaml = """
        schemaVersion: 1
        id: xqp_counties
        kind: FIXED
        keyType: TEXT
        enumerable: true
        metadata: { name: "X 'Q' Party é" }
        valuesFile: xqp_counties.csv

        """

    @Test func writeMatchesJavaBytes() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mult = dir.appendingPathComponent("multipliers")
        let values = [(code: "ZZ", label: "Zed"), (code: "AA", label: "Ay, é é"), (code: "M", label: "")]
        #expect(try CountyListImport.write(mult, setId: "xqp_counties", name: "X \"Q\" Party é", values: values) == 3)
        let csv = try Data(contentsOf: mult.appendingPathComponent("xqp_counties.csv"))
        let yaml = try Data(contentsOf: mult.appendingPathComponent("xqp_counties.yaml"))
        #expect(csv == Data(Self.expectedCsv.utf8))
        #expect(yaml == Data(Self.expectedYaml.utf8))
        #expect(yaml.last == 0x0A)
        // Does not write atomically, overwrites an existing file and does not crash.
        #expect(try CountyListImport.write(mult, setId: "xqp_counties", name: "n", values: [(code: "A", label: "b")]) == 1)
        #expect(try Data(contentsOf: mult.appendingPathComponent("xqp_counties.csv"))
                == Data("# n (key,label) — importováno\nA,b\n".utf8))
    }

    @Test func quoteFollowedByCombiningMarkIsReplacedLikeJava() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try CountyListImport.write(dir, setId: "a", name: "x\"\u{301}y", values: [(code: "A", label: "b")])
        let yaml = try String(contentsOf: dir.appendingPathComponent("a.yaml"), encoding: .utf8)
        #expect(yaml.contains("metadata: { name: \"x'\u{301}y\" }"))
    }

    @Test func writeRejectsBadIdAndEmptyValues() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let one = [(code: "A", label: "a")]
        for bad in ["Bad", "", "bad\n", "a-b", "ab "] {
            do {
                try CountyListImport.write(dir, setId: bad, name: "x", values: one)
                Issue.record("should have failed: \(bad.debugDescription)")
            } catch {
                #expect(error.message == "Id sady smí mít jen malá písmena, číslice a _: " + bad)
            }
        }
        do {
            try CountyListImport.write(dir, setId: "ok", name: "x", values: [])
            Issue.record("should have failed")
        } catch {
            #expect(error.message == "Seznam neobsahuje žádný kód")
        }
        // An invalid id is checked before the empty list.
        do {
            try CountyListImport.write(dir, setId: "Bad", name: "x", values: [])
            Issue.record("should have failed")
        } catch {
            #expect(error.message.hasPrefix("Id sady"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
    }

    // MARK: - qsoPartyTemplate (byte for byte against Java)

    static let expectedTemplate = """
        schemaVersion: 1
        id: xqp
        metadata:
          name: "X 'Q' Party"
          description: "QSO party: stanice ze státu posílají okres, ostatní stát/provincii. ROVERQTH = můj okres."
        period: { durationHours: 24 }
        bands: [160m, 80m, 40m, 20m, 15m, 10m]
        modes: [CW, SSB]

        stationClasses:
          - { id: instate, when: { dxccIn: [US, K] } }
          - { id: other,   when: { not: { dxccIn: [US, K] } } }

        exchange:
          sent:
            - { id: rst,    type: RST,      source: AUTO_RST }
            - { id: county, type: DISTRICT, source: ROVER_QTH }
          received:
            - { id: rst, type: RST,      required: true }
            - { id: qth, type: DISTRICT, required: true }   # okres (stanice ze státu) nebo stát

        scoring:
          qsoPoints:
            mode: FIRST_MATCH
            default: 1
            rules:
              - { when: { mode: CW }, value: { fixed: 2 } }
          total: "qsoPoints * multTotal"

        multipliers:
          - { id: counties, set: xqp_counties,     from: qth, scope: ONCE }
          - { id: states,   set: na_areas, from: qth, scope: ONCE }

        dupe: { scope: PER_BAND_MODE }

        cabrillo: { contestName: XQP, sentOrder: [rst, county], receivedOrder: [rst, qth] }
        ui:
          entryOrder: [call, qth]
          logColumns: [time, call, band, mode, rst, qth, points, mult]

        """

    @Test func templateMatchesJavaBytes() {
        #expect(CountyListImport.qsoPartyTemplate("xqp", "X \"Q\" Party", "xqp_counties") == Self.expectedTemplate)
    }

    @Test func templateInsertsIdUppercasedAndDoesNotFormatName() {
        // Java `formatted` does not evaluate `%s` in arguments; the id is inserted unquoted.
        let yaml = CountyListImport.qsoPartyTemplate("abç", "100%s $1", "set")
        #expect(yaml.contains("id: abç\n"))
        #expect(yaml.contains("  name: \"100%s $1\"\n"))
        #expect(yaml.contains("set: set,     from: qth"))
        #expect(yaml.contains("contestName: ABÇ,"))
    }
}
