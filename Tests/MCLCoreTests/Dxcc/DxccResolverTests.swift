import Foundation
import Testing
@testable import MCLCore

/// Tests of `DxccResolver`.
///
/// The first four tests are a port of the Java `DxccResolverTest` (`resolvesBasicCalls`,
/// `portablePrefixOverridesDxcc`, `entityCarriesContinentAndZones`,
/// `deletedAndUnknownAreNotResolved`). The rest pins behaviour that the Java
/// tests do not cover and that was **measured on a running Java v1.1.1**: malformed input, ties in prefix score, splitting the prefix list
/// and Jackson's tolerance for types.
///
/// The fixture is small (`Fixtures/dxcc-test.json`, a verbatim copy of the Java
/// test fixture) — the external data set `~/dxcc-json/` is not copied into the repo
/// and the resolver does not read paths anyway, only `Data`.
@Suite struct DxccResolverTests {

    /// Without an argument the shared fixture `Fixtures/dxcc-test.json` (a copy of the Java
    /// test fixture, also used by `MultiplierSetRegistryTests`).
    private static func resolver(_ json: String? = nil) throws -> DxccResolver {
        guard let json else { return try DxccResolver.fromData(DxccTestFixture.data()) }
        return try DxccResolver.fromData(Data(json.utf8))
    }

    // MARK: Java DxccResolverTest

    @Test func resolvesBasicCalls() throws {
        let r = try Self.resolver()
        #expect(r.resolve("OK1XOE")?.countryCode == "CZ")
        #expect(r.resolve("W1AW")?.countryCode == "US")
        #expect(r.resolve("VE3XYZ")?.countryCode == "CA")
        #expect(r.resolve("DL1ABC")?.countryCode == "DE")
    }

    @Test func portablePrefixOverridesDxcc() throws {
        let r = try Self.resolver()
        // W1/OK1XOE = an OK operator in the USA → DXCC = USA
        #expect(r.resolve("W1/OK1XOE")?.countryCode == "US")
        // OK1XOE/P = still Czechia
        #expect(r.resolve("OK1XOE/P")?.countryCode == "CZ")
    }

    @Test func entityCarriesContinentAndZones() throws {
        let cz = try #require(try Self.resolver().resolve("OK1XOE"))
        #expect(cz.primaryContinent == "EU")
        #expect(cz.cq?.contains(15) == true)
    }

    @Test func deletedAndUnknownAreNotResolved() throws {
        let r = try Self.resolver()
        #expect(r.resolve("XX9XX") == nil, "a deleted entity must not be returned")
        #expect(r.resolve("QQ9QQ") == nil, "unknown callsign → empty")
    }

    // MARK: empty input and memoization

    @Test func blankCallsignsResolveToNothing() throws {
        let r = try Self.resolver()
        #expect(r.resolve(nil) == nil)
        #expect(r.resolve("") == nil)
        #expect(r.resolve("   ") == nil)
        #expect(r.resolve("\t") == nil)
    }

    /// Java `resolve` normalizes and memoizes — the second call must give the same result.
    @Test func repeatedResolveGivesSameAnswer() throws {
        let r = try Self.resolver()
        let first = r.resolve("  ok1xoe  ")
        let second = r.resolve("OK1XOE")
        #expect(first?.entityCode == 503)
        #expect(second == first)
        #expect(r.resolve("QQ9QQ") == nil)
        #expect(r.resolve("QQ9QQ") == nil)
    }

    // MARK: entities()

    /// The order of `entities()` is the order in the JSON `dxcc` array after filtering (Java
    /// `List`), so it is part of the behaviour — measured: `ORDER [CC, AA]`.
    @Test func entitiesKeepJsonOrderAndDropSkippedRecords() throws {
        let r = try Self.resolver("""
            {"dxcc":[
              {"entityCode":3,"countryCode":"CC","prefixRegex":"^C.*"},
              {"entityCode":1,"countryCode":"AA","prefixRegex":"^A.*"},
              {"entityCode":2,"countryCode":"BB","prefixRegex":"^B.*","deleted":true},
              {"entityCode":4,"countryCode":"DD","prefixRegex":"  "},
              {"entityCode":5,"countryCode":"EE"},
              {"entityCode":6,"countryCode":"FF","prefixRegex":"["}
            ]}
            """)
        #expect(r.entities().map(\.countryCode) == ["CC", "AA"])
    }

    /// Entities from `dxcc.json` have no coordinates — always `NaN` (the Java constructor
    /// passes it there hard-coded).
    @Test func entitiesFromJsonHaveNoCoordinates() throws {
        let cz = try #require(try Self.resolver().resolve("OK1XOE"))
        #expect(cz.lat.isNaN)
        #expect(cz.lon.isNaN)
        #expect(cz.hasLatLon == false)
        #expect(cz.adifDxcc == 503)
    }

    // MARK: choosing the most specific match

    /// A longer matching prefix wins even if the entity comes later in the array — measured
    /// `LONGER BB`.
    @Test func longestMatchingPrefixWins() throws {
        let r = try Self.resolver("""
            {"dxcc":[
              {"entityCode":11,"countryCode":"AA","prefix":"O","prefixRegex":"^O[A-Z0-9]*$"},
              {"entityCode":22,"countryCode":"BB","prefix":"OK1","prefixRegex":"^OK[A-Z0-9]*$"}
            ]}
            """)
        #expect(r.resolve("OK1XOE")?.countryCode == "BB")
    }

    /// With an equal score the **first** record in the array wins (Java `score > bestScore`)
    /// — measured `TIE AA` / `TIE-REV BB`.
    @Test func tieGoesToFirstEntityInFile() throws {
        let first = """
            {"dxcc":[
              {"entityCode":11,"countryCode":"AA","prefix":"OK","prefixRegex":"^OK[0-9].*"},
              {"entityCode":22,"countryCode":"BB","prefix":"OK","prefixRegex":"^OK[0-9].*"}
            ]}
            """
        let secondJson = """
            {"dxcc":[
              {"entityCode":22,"countryCode":"BB","prefix":"OK","prefixRegex":"^OK[0-9].*"},
              {"entityCode":11,"countryCode":"AA","prefix":"OK","prefixRegex":"^OK[0-9].*"}
            ]}
            """
        #expect(try Self.resolver(first).resolve("OK1XOE")?.countryCode == "AA")
        #expect(try Self.resolver(secondJson).resolve("OK1XOE")?.countryCode == "BB")
    }

    /// The regex must match the **whole** callsign (Java `Matcher.matches()`),
    /// not just its beginning.
    @Test func patternMustMatchWholeCallsign() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"AA","prefix":"OK","prefixRegex":"^OK[0-9]"}]}
            """)
        #expect(r.resolve("OK1") != nil)
        #expect(r.resolve("OK1XOE") == nil)
    }

    // MARK: primary prefix and list splitting

    @Test func primaryPrefixIsFirstInList() throws {
        let r = try Self.resolver()
        #expect(r.resolve("OK1XOE")?.primaryPrefix == "OK")
        #expect(r.resolve("W1AW")?.primaryPrefix == "K")
    }

    /// Java `prefix.toUpperCase().split("\\s*,\\s*")`: spaces around the comma are
    /// eaten, spaces at the edges are not — measured `primaryPrefix=[ OK]`.
    @Test func prefixListSplitKeepsOuterSpaces() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":" ok , ol ","prefixRegex":"^OK.*"}]}
            """)
        #expect(r.entities().first?.primaryPrefix == " OK")
    }

    /// An empty `prefix` yields one empty prefix (Java `"".split(…)` → `[""]`),
    /// so the primary prefix is an empty string, **not** `countryCode`.
    @Test func emptyPrefixStringBecomesEmptyPrimaryPrefix() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":"","prefixRegex":"^OK.*"}]}
            """)
        #expect(r.entities().first?.primaryPrefix == "")
    }

    /// A lone comma, however, yields an **empty list** (Java `split` drops trailing
    /// empty elements), and then `countryCode` is used — measured `P[comma] primaryPrefix=CZ`.
    @Test func prefixOfOnlyCommasFallsBackToCountryCode() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":",","prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "CZ")
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":",,","prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "CZ")
        // Trailing empty elements are dropped, leading ones are not.
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":"OK,,","prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "OK")
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":",OK","prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "")
    }

    /// A missing `prefix` → primary prefix = `countryCode`.
    @Test func missingPrefixFallsBackToCountryCode() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "CZ")
    }

    // MARK: normalize

    /// The table is a 1:1 output of the Java `DxccResolver.normalize` (measured).
    @Test func normalizeMatchesJava() {
        let expected: [(String, String)] = [
            ("ok1xoe", "OK1XOE"),
            ("  ok1xoe  ", "OK1XOE"),
            ("OK1XOE/P", "OK1XOE"),
            ("W1/OK1XOE", "W1"),
            ("DL/W1ABC", "DL"),
            ("OK1XOE/QRP", "OK1XOE"),
            ("OK1XOE/3", "OK1XOE"),
            ("OK1XOE/13", "13"),
            ("/", ""),
            ("///", ""),
            ("P/M", "PM"),
            ("OK/", "OK"),
            ("/OK1XOE", "OK1XOE"),
            ("F/OK1XOE/M", "F"),
            ("OK1XOE/p", "OK1XOE"),
            ("9A/OK1XOE/P", "9A"),
            ("K1ABC/VE3", "VE3"),
            ("OK1XOE/AM", "OK1XOE"),
            ("ok1xoe/mm", "OK1XOE"),
            ("A/B/C", "C"),
        ]
        for (input, result) in expected {
            #expect(DxccResolver.normalize(input) == result, "normalize(\(input))")
        }
    }

    // MARK: malformed input (measured on Java — no Java test covers it)

    /// Java measurement: malformed, empty and otherwise-shaped JSON ends
    /// `DxccException("Nelze parsovat DXCC data")`.
    @Test func malformedInputThrowsParseError() {
        for input in ["{\"dxcc\": [", "", "   ", "hello", "[]", "42", "{\"dxcc\": {}}"] {
            #expect(throws: DxccError.self) {
                _ = try DxccResolver.fromData(Data(input.utf8))
            }
            do {
                _ = try DxccResolver.fromData(Data(input.utf8))
                Issue.record("input \(input) should have ended with an error")
            } catch let failure as DxccError {
                #expect(failure.kind == .parse, "input \(input)")
                #expect(failure.message == "Nelze parsovat DXCC data")
            } catch {
                Issue.record("unexpected error type: \(error)")
            }
        }
    }

    /// Java measurement: valid JSON **without** a `dxcc` field (or with `"dxcc": null`)
    /// crashes in Java with `NullPointerException`, i.e. differently from malformed JSON.
    /// In Swift it is `kind == .nullPointer`.
    @Test func missingEntityListIsDistinctFromParseError() {
        for input in ["{}", "{\"dxcc\": null}", "{\"jine\": 1}"] {
            do {
                _ = try DxccResolver.fromData(Data(input.utf8))
                Issue.record("input \(input) should have ended with an error")
            } catch let failure as DxccError {
                #expect(failure.kind == .nullPointer, "input \(input)")
            } catch {
                Issue.record("unexpected error type: \(error)")
            }
        }
    }

    /// A non-numeric `entityCode` cannot be converted by Jackson → error for the whole file.
    @Test func nonNumericEntityCodeThrows() {
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":"abc","prefixRegex":"^OK.*"}]}
                """.utf8))
        }
    }

    /// Jackson maps the whole file before filtering, so a type error
    /// brings the file down even in a record that would be skipped anyway — measured
    /// (`bad-code-in-deleted`, `bad-cq-in-deleted`, `bad-code-no-regex`).
    @Test func typeErrorInSkippedRecordStillFailsTheFile() {
        for input in [
            #"{"dxcc":[{"entityCode":"abc","deleted":true,"prefixRegex":"^OK.*"}]}"#,
            #"{"dxcc":[{"entityCode":1,"cq":15,"deleted":true,"prefixRegex":"^OK.*"}]}"#,
            #"{"dxcc":[{"entityCode":"abc"}]}"#,
        ] {
            #expect(throws: DxccError.self) {
                _ = try DxccResolver.fromData(Data(input.utf8))
            }
        }
    }

    // MARK: Jackson's type tolerance (measured)

    /// Jackson takes a number in a string as a number (`"503"` → 503, `" 7 "` → 7,
    /// `""` → 0) and truncates a decimal number (`1.9` → 1).
    @Test func numbersInStringsAreCoercedLikeJackson() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":"503","prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 503)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":" 7 ","prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 7)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":"","prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 0)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1.9,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 1)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":null,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 0)
    }

    /// `deleted` as text: Jackson takes **only** the shapes `true|True|TRUE`
    /// and `false|False|FALSE`, a non-zero number is `true`; empty text, `0` and `null`
    /// leave the entity alone — measured (`deleted="TRUE"` → 0 entities, `deleted=2` → 0,
    /// `deleted=0` → 1). Other shapes (`"tRuE"`) bring down the **whole file**, see
    /// `unusualBooleanSpellingFailsTheWholeFile`.
    @Test func deletedFlagIsCoercedLikeJackson() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":"TRUE","prefixRegex":"^OK.*"}]}
            """).entities().isEmpty)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":2,"prefixRegex":"^OK.*"}]}
            """).entities().isEmpty)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":0,"prefixRegex":"^OK.*"}]}
            """).entities().count == 1)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":"","prefixRegex":"^OK.*"}]}
            """).entities().count == 1)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":null,"prefixRegex":"^OK.*"}]}
            """).entities().count == 1)
    }

    /// Unknown properties are ignored (`@JsonIgnoreProperties(ignoreUnknown = true)`).
    @Test func unknownPropertiesAreIgnored() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"^OK.*","flag":"🇨🇿","notes":null}],"verze":3}
            """)
        #expect(r.entities().count == 1)
    }

    /// Lists must be lists — a scalar in `cq` is an error for the whole file in Java.
    @Test func scalarInsteadOfListThrows() {
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":1,"cq":15,"prefixRegex":"^OK.*"}]}
                """.utf8))
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":1,"continent":"EU","prefixRegex":"^OK.*"}]}
                """.utf8))
        }
    }

    /// Numbers in text inside the zone list are also converted by Jackson.
    @Test func zoneListAcceptsNumbersInStrings() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"cq":["15"],"itu":[28.7],"prefixRegex":"^OK.*"}]}
            """)
        #expect(r.entities().first?.cq == [15])
        #expect(r.entities().first?.itu == [28])
    }

    // MARK: additionally measured Jackson behaviour

    /// `0` and `0.0` are **not** the same: `deleted: 0` is `false` (entity stays),
    /// `deleted: 0.0` is an error for the whole file. Likewise `1` vs. `1.0`.
    /// The custom JSON reader stands on this difference — `JSONSerialization`
    /// would not tell `0` from `0.0` after parsing.
    @Test func integerAndFloatingZeroAreNotInterchangeable() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":0,"prefixRegex":"^OK.*"}]}
            """).entities().count == 1)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":2,"prefixRegex":"^OK.*"}]}
            """).entities().isEmpty)
        for malformed in [#"{"dxcc":[{"entityCode":1,"deleted":0.0,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"deleted":1.0,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"deleted":1.5,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"deleted":0e0,"prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
        // Conversely, for a number the distinction shows in the value: `1.9` is truncated, `1` is 1.
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1.9,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 1)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1e3,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 1000)
    }

    /// Java `int` is **32-bit**: what does not fit brings down the whole file.
    /// Previously the port silently accepted it and sent it out as a DXCC number into ADIF.
    @Test func intOutOfRangeFailsTheWholeFile() throws {
        for malformed in [#"{"dxcc":[{"entityCode":2147483648,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":-2147483649,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":"2147483648","prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1e20,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":2.9e9,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":12345678901234567890,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"cq":[2147483648],"prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
        // Boundary valid values pass.
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":2147483647,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 2_147_483_647)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":-2147483648,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == -2_147_483_648)
    }

    /// Jackson compares text for `boolean` **exactly**: any letter case other than
    /// `true|True|TRUE` / `false|False|FALSE` is an error for the whole file, not "true".
    /// Previously the port silently dropped such an entity — silent data loss.
    @Test func unusualBooleanSpellingFailsTheWholeFile() throws {
        for shape in ["true", "True", "TRUE"] {
            #expect(try Self.resolver("""
                {"dxcc":[{"entityCode":1,"deleted":"\(shape)","prefixRegex":"^OK.*"}]}
                """).entities().isEmpty, "shape \(shape)")
        }
        for shape in ["false", "False", "FALSE"] {
            #expect(try Self.resolver("""
                {"dxcc":[{"entityCode":1,"deleted":"\(shape)","prefixRegex":"^OK.*"}]}
                """).entities().count == 1, "shape \(shape)")
        }
        for shape in ["tRuE", "TRue", "fAlSe", "yes", "1", "\\u00a0true"] {
            #expect(throws: DxccError.self, "shape \(shape)") {
                _ = try DxccResolver.fromData(Data("""
                    {"dxcc":[{"entityCode":1,"deleted":"\(shape)","prefixRegex":"^OK.*"}]}
                    """.utf8))
            }
        }
        // Spaces around are, however, removed (by Java `trim()`).
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":" true ","prefixRegex":"^OK.*"}]}
            """).entities().isEmpty)
    }

    /// Duplicate key inside an entity: the **last** value wins.
    @Test func lastDuplicateKeyWinsInsideEntity() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"name":"A","name":"B","prefixRegex":"^OK.*"}]}
            """).entities().first?.name == "B")
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"entityCode":2,"prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 2)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"cq":[1],"cq":[2],"prefixRegex":"^OK.*"}]}
            """).entities().first?.cq == [2])
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"name":"A","name":null,"prefixRegex":"^OK.*"}]}
            """).entities().first?.name == nil)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"deleted":true,"deleted":false,"prefixRegex":"^OK.*"}]}
            """).entities().count == 1)
    }

    /// A duplicate top-level `dxcc` key is, on the contrary, an error — Java Jackson
    /// reports "Should never call `set()` on setterless property ('dxcc')" there.
    @Test func duplicateTopLevelDxccKeyThrows() {
        for malformed in [#"{"dxcc":[],"dxcc":[{"entityCode":9,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":null,"dxcc":[{"entityCode":9,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":9,"prefixRegex":"^OK.*"}],"x":1,"dxcc":[]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
    }

    /// Jackson ignores content **after** the end of the JSON (reads the first value and that's it).
    @Test func trailingContentIsIgnored() throws {
        let base = #"{"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"^OK.*"}]}"#
        for input in [base + "xx", base + #"{"dxcc":[]}"#, base + "   \n"] {
            let r = try Self.resolver(input)
            #expect(r.entities().count == 1, "input \(input)")
            #expect(r.entities().first?.countryCode == "CZ")
        }
        // A trailing comma **inside** the JSON is still an error.
        for malformed in [#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],}"#,
                      #"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"},]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
    }

    /// A number in a `String` field is taken as the **original literal text**
    /// (`1.50` stays `"1.50"`, `1e2` stays `"1e2"`) — not as `Double.toString`.
    @Test func numberInStringFieldKeepsItsLiteralText() throws {
        for (literal, expected) in [("1.5", "1.5"), ("1.50", "1.50"), ("1e2", "1e2"),
                                     ("1.0E20", "1.0E20"), ("100", "100"), ("0.0", "0.0"),
                                     ("-0.0", "-0.0"), ("12345678901234567890", "12345678901234567890"),
                                     ("1e400", "1e400"), ("0.30000000000000004", "0.30000000000000004")] {
            let r = try Self.resolver("""
                {"dxcc":[{"entityCode":1,"name":\(literal),"prefixRegex":"^OK.*"}]}
                """)
            #expect(r.entities().first?.name == expected, "literal \(literal)")
        }
        // The same for `prefix` (and thus `primaryPrefix`) and for `prefixRegex`,
        // which is then compiled as a regex and the entity stays.
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefix":1.5,"prefixRegex":"^OK.*"}]}
            """).entities().first?.primaryPrefix == "1.5")
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"prefixRegex":1.0}]}
            """).entities().count == 1)
        // `true`/`false` in a text field gives "true"/"false".
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"name":true,"prefixRegex":"^OK.*"}]}
            """).entities().first?.name == "true")
    }

    /// `null` inside a zone/continent list **stays** `null`. Zero would be a different
    /// zone, not a missing value, and rejecting the file would leave the application without DXCC.
    @Test func nullInsideZoneListStaysNull() throws {
        let zones = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"cq":[15,null],"itu":[null],"prefixRegex":"^OK.*"}]}
            """).entities().first
        #expect(zones?.cq == [15, nil])
        #expect(zones?.itu == [nil])
        let continents = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"continent":[null,"EU"],"prefixRegex":"^OK.*"}]}
            """).entities().first
        #expect(continents?.continents == [nil, "EU"])
        // Java `continents.getFirst()` is then `null`, not "EU".
        #expect(continents?.primaryContinent == nil)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"continent":[null],"prefixRegex":"^OK.*"}]}
            """).entities().first?.continents == [nil])
        // `true` in a number list is still an error.
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":1,"cq":[true],"prefixRegex":"^OK.*"}]}
                """.utf8))
        }
    }

    /// A `null` **element** of the `dxcc` array: Java `e.deleted()` on it fails with
    /// `NullPointerException`, not `DxccException`.
    @Test func nullEntityElementIsNullPointerKind() {
        do {
            _ = try DxccResolver.fromData(Data(#"{"dxcc":[null]}"#.utf8))
            Issue.record("should have ended with an error")
        } catch let failure as DxccError {
            #expect(failure.kind == .nullPointer)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        // A scalar instead of an object is, on the contrary, an ordinary mapping error.
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data(#"{"dxcc":[5]}"#.utf8))
        }
    }

    /// Text with a number is trimmed before conversion by Java `trim()`, which
    /// **keeps** the non-breaking space — such input is therefore an error.
    @Test func nonBreakingSpaceIsNotTrimmedFromNumbers() throws {
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":" 7 ","prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 7)
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":"+7","prefixRegex":"^OK.*"}]}
            """).entities().first?.entityCode == 7)
        for malformed in [#"{"dxcc":[{"entityCode":" 7","prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":"7.0","prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":"1e3","prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
    }

    /// A `prefixRegex` of non-breaking spaces is **not** empty (Java `isBlank()`
    /// does not consider U+00A0 whitespace), so the entity is not skipped.
    @Test func nonBreakingSpaceRegexIsNotBlank() throws {
        let r = try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"\\u00a0"}]}
            """)
        #expect(r.entities().count == 1)
        #expect(r.resolve("\u{00a0}")?.countryCode == "CZ")
        // Ordinary spaces are empty.
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"  "}]}
            """).entities().isEmpty)
    }

    /// A callsign made only of non-breaking spaces is not empty according to Java `isBlank()`,
    /// so it passes normalization (and finds nothing) — it is not dropped right away.
    @Test func nonBreakingSpaceCallsignIsNotBlank() {
        #expect(DxccResolver.normalize("\u{00a0}OK1XOE") == "\u{00a0}OK1XOE")
        #expect(DxccResolver.normalize("\u{01}OK1XOE") == "OK1XOE")
    }

    // MARK: reader limits and the complete-record rule

    /// Deep nesting must not bring down the process. The Java limit is 1000: depth 1000
    /// passes, 1001 is a `DxccException`. The recursive reader here died on signal 10
    /// already around depth 600, i.e. before it ever reached the limit.
    ///
    /// Depth is counted as in Jackson — the root object is 1. The test builds the nesting
    /// into an **unknown** key so that entity mapping does not depend on the depth.
    @Test func deepNestingIsBoundedInsteadOfCrashing() throws {
        func input(depth: Int) -> String {
            let k = depth - 1 // root object + k nested arrays
            return #"{"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"^OK.*"}],"x":"#
                + String(repeating: "[", count: k) + String(repeating: "]", count: k) + "}"
        }
        // Deep but valid files pass — including depths where the old
        // reader failed (≈600), and at the limit boundary.
        for depth in [3, 500, 700, 900, 999, 1000] {
            let r = try Self.resolver(input(depth: depth))
            #expect(r.entities().count == 1, "depth \(depth)")
            #expect(r.resolve("OK1XOE")?.countryCode == "CZ", "depth \(depth)")
        }
        // Beyond the limit comes an error, not a crash.
        for depth in [1001, 1002, 1200, 5000] {
            #expect(throws: DxccError.self, "depth \(depth)") {
                _ = try DxccResolver.fromData(Data(input(depth: depth).utf8))
            }
        }
        // The same for the index, so the limits do not drift apart.
        #expect(try DxccCodeIndex.fromData(Data(input(depth: 1000).utf8)).code("?", "?") == nil)
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(input(depth: 1001).utf8))
        }
    }

    /// Length of a numeric literal: Jackson counts **digits** (of mantissa and exponent),
    /// not the sign, the dot or `e`. 1000 digits pass, 1001 is an error.
    @Test func numberLiteralLengthIsBounded() throws {
        func digits(_ n: Int) -> String { String(repeating: "1", count: n) }
        // 1000 digits in an unknown key and in a text field pass.
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":"# + digits(1000) + "}")
            .entities().count == 1)
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"name":"# + digits(1000) + #","prefixRegex":"^OK.*"}]}"#)
            .entities().first?.name == digits(1000))
        // The sign is not counted: "-" + 1000 digits still passes.
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":-"# + digits(1000) + "}")
            .entities().count == 1)
        // The dot and "e" are not counted, the exponent digits are.
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":0."# + digits(999) + "}")
            .entities().count == 1)
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":1e"# + digits(999) + "}")
            .entities().count == 1)
        for exceeded in [#"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":"# + digits(1001) + "}",
                           #"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":-"# + digits(1001) + "}",
                           #"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":0."# + digits(1000) + "}",
                           #"{"dxcc":[{"entityCode":1,"prefixRegex":"^OK.*"}],"x":1e"# + digits(1000) + "}",
                           #"{"dxcc":[{"entityCode":1,"name":"# + digits(1001) + #","prefixRegex":"^OK.*"}]}"#,
                           #"{"dxcc":[{"entityCode":1,"name":0."# + digits(1200) + #","prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self) {
                _ = try DxccResolver.fromData(Data(exceeded.utf8))
            }
        }
    }

    /// A duplicate key wins only **until the record is complete**. The resolver's
    /// `RawEntity` has nine properties; once all of them have appeared, any further
    /// occurrence is an error for the whole file ("No fallback setter/field defined for
    /// creator property"). The real `dxcc.json` carries the full set on every entity,
    /// so this is the realistic shape, not an exotic one.
    @Test func duplicateAfterCompleteRecordThrows() throws {
        let nine = [#""entityCode":1"#, #""name":"A""#, #""countryCode":"CZ""#, #""continent":["EU"]"#,
                     #""cq":[15]"#, #""itu":[28]"#, #""prefix":"OK""#, #""prefixRegex":"^OK.*""#,
                     #""deleted":false"#]
        func entity(_ count: Int, _ extra: String...) -> String {
            "{\"dxcc\":[{" + (nine.prefix(count) + extra).joined(separator: ",") + "}]}"
        }
        // Eight properties + duplicate name + the ninth → the last wins, passes.
        #expect(try Self.resolver(entity(8, #""name":"B""#, nine[8])).entities().first?.name == "B")
        // All nine and **then** a duplicate key → error.
        for dup in [#""name":"B""#, #""deleted":true"#, #""entityCode":2"#, #""cq":[1]"#] {
            #expect(throws: DxccError.self, "duplicate \(dup)") {
                _ = try DxccResolver.fromData(Data(entity(9, dup).utf8))
            }
        }
        // Even if an unknown key is between them.
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data(entity(9, #""flag":1"#, #""name":"B""#).utf8))
        }
        // A duplicate **unknown** key is fine even for a complete record.
        #expect(try Self.resolver(entity(9, #""flag":1"#, #""flag":2"#)).entities().count == 1)
        // And an incomplete record (without `deleted`) passes even with a duplicate.
        #expect(try Self.resolver(entity(8, #""name":"B""#)).entities().first?.name == "B")
    }

    /// Every occurrence is converted, even if the next one overwrites it — a bad value therefore
    /// brings the file down, even if "the last wins" would give a valid one.
    @Test func everyDuplicateOccurrenceIsConverted() {
        for malformed in [#"{"dxcc":[{"entityCode":"abc","entityCode":1,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"entityCode":"abc","prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"cq":15,"cq":[1],"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"name":[1],"name":"A","prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
    }

    /// The `int` range is checked **before** truncation: `2147483647.9` is
    /// "out of range of int" in Java, even though it would fit after truncation. A coarse test with `1e20`
    /// does not catch it, because that passes in both variants.
    @Test func doubleRangeIsCheckedBeforeTruncation() throws {
        for outside in ["2147483647.9", "2147483647.4", "-2147483648.9", "-2147483648.4", "2.1474836479e9"] {
            #expect(throws: DxccError.self, "value \(outside)") {
                _ = try DxccResolver.fromData(Data("""
                    {"dxcc":[{"entityCode":\(outside),"prefixRegex":"^OK.*"}]}
                    """.utf8))
            }
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":1,"cq":[2147483647.9],"prefixRegex":"^OK.*"}]}
                """.utf8))
        }
        // Boundary values without a fraction pass and truncation toward zero still applies.
        for (literal, expected) in [("2147483647.0", 2_147_483_647), ("-2147483648.0", -2_147_483_648),
                                     ("2.147483647e9", 2_147_483_647), ("1.9", 1), ("-1.9", -1),
                                     ("0.9", 0), ("-0.9", 0)] {
            #expect(try Self.resolver("""
                {"dxcc":[{"entityCode":\(literal),"prefixRegex":"^OK.*"}]}
                """).entities().first?.entityCode == expected, "value \(literal)")
        }
        #expect(try Self.resolver("""
            {"dxcc":[{"entityCode":1,"cq":[2147483647.0],"prefixRegex":"^OK.*"}]}
            """).entities().first?.cq == [2_147_483_647])
    }

    /// Content `null` (the whole document) is a `NullPointerException` ("raw" is
    /// null) in Java, not `DxccException` — the third such place in the package.
    @Test func nullDocumentIsNullPointerKind() {
        for input in ["null", "null xx", "  null  "] {
            do {
                _ = try DxccResolver.fromData(Data(input.utf8))
                Issue.record("input \(input) should have ended with an error")
            } catch let failure as DxccError {
                #expect(failure.kind == .nullPointer, "input \(input)")
            } catch {
                Issue.record("unexpected error type: \(error)")
            }
        }
        // Another scalar at the root is, on the contrary, an ordinary mapping error.
        do {
            _ = try DxccResolver.fromData(Data("true".utf8))
            Issue.record("should have ended with an error")
        } catch let failure as DxccError {
            #expect(failure.kind == .parse)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// JSON strictness matches Jackson: a leading zero, `+7`, hex, `NaN`,
    /// a comment, apostrophes, an unescaped control character and bad UTF-8 do not pass;
    /// a BOM at the start does.
    @Test func jsonStrictnessMatchesJackson() throws {
        for malformed in [#"{"dxcc":[{"entityCode":01,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":+7,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":0x10,"prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":NaN,"prefixRegex":"^OK.*"}]}"#,
                      #"{'dxcc':[]}"#,
                      #"{"dxcc":[] /* pozn */ }"#,
                      "{\"dxcc\":[{\"entityCode\":1,\"name\":\"a\nb\",\"prefixRegex\":\"^OK.*\"}]}",
                      #"{"dxcc":[{"entityCode":1,"name":"\q","prefixRegex":"^OK.*"}]}"#,
                      #"{"dxcc":[{"entityCode":1,"name":"\ud800","prefixRegex":"^OK.*"}]}"#] {
            #expect(throws: DxccError.self, "input \(malformed)") {
                _ = try DxccResolver.fromData(Data(malformed.utf8))
            }
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data([0x7B, 0x22, 0x64, 0x78, 0x63, 0x63, 0x22, 0x3A, 0x5B,
                                                0x7B, 0x22, 0x6E, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D, 0x5D, 0x7D]))
        }
        let withBom = "\u{FEFF}" + #"{"dxcc":[{"entityCode":1,"countryCode":"CZ","prefixRegex":"^OK.*"}]}"#
        #expect(try Self.resolver(withBom).entities().count == 1)
        // A surrogate pair in an escape must pass.
        #expect(try Self.resolver(#"{"dxcc":[{"entityCode":1,"name":"🇨","prefixRegex":"^OK.*"}]}"#)
            .entities().first?.name == "🇨")
    }

    /// Concurrent lookup of new callsigns (patterns are evaluated outside the shared lock,
    /// each thread over its own set of compiled patterns) gives the same as a serial lookup,
    /// even when many threads look up the same new callsign at once.
    @Test func concurrentResolveMatchesSerial() async throws {
        let data = try DxccTestFixture.data()
        // In steps with explicit types: a single `+` chain over array literals is something the older compiler
        // in CI (Xcode 16) cannot type-check in time.
        let prefixes: [String] = ["OK", "OL", "W", "K", "N", "AA", "VE", "VO", "DL", "DA", "XX", "ZZ", "DL/OK", "W1/"]
        let suffixes: [String] = ["ABC", "XY", "Q", "/P", ""]
        let calls: [String] = (0..<400).map { (i: Int) -> String in
            let prefix: String = prefixes[i % 14]
            let digit: String = String(i % 10)
            let suffix: String = suffixes[i % 5]
            return prefix + digit + suffix
        }
        let serial = try DxccResolver.fromData(data)
        let expected = calls.map { serial.resolve($0)?.entityCode }
        let shared = try DxccResolver.fromData(data)
        let results = await withTaskGroup(of: [Int?].self) { group in
            for t in 0..<8 {
                group.addTask {
                    // Each task goes in a different order so that new callsigns meet each other.
                    let order = t % 2 == 0 ? Array(calls.indices) : Array(calls.indices.reversed())
                    var out = [Int?](repeating: nil, count: calls.count)
                    for i in order { out[i] = shared.resolve(calls[i])?.entityCode }
                    return out
                }
            }
            var all: [[Int?]] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results.count == 8)
        for result in results {
            #expect(result == expected)
        }
    }
}
