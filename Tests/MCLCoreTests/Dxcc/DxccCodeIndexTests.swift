import Foundation
import Testing
@testable import MCLCore

/// Tests of `DxccCodeIndex`.
///
/// The first ten tests are a port of the Java `DxccCodeIndexTest` (including its
/// fixture and Czech names). The rest pins behaviour measured on Java v1.1.1
/// the `normalize` table, alias precedence over the entity's own
/// name, Jackson's tolerance and the error paths.
///
/// Collection order is **not tested**: Java `byName`/`byPrefix` are `HashMap`s
/// and `nameClash`/`prefixClash` are `HashSet`s, so no order is guaranteed and
/// the index is queried only by key. An order test would be flaky.
@Suite struct DxccCodeIndexTests {

    /// Excerpt of dxcc.json including traps: diacritics, shared prefix, deleted entity.
    /// Same content as the Java fixture in `DxccCodeIndexTest`.
    private static let json = """
        { "dxcc": [
          { "entityCode": 504, "name": "Slovakia", "countryCode": "SK", "continent": ["EU"],
            "cq": [15], "itu": [28], "prefix": "OM", "prefixRegex": "^OM[A-Z0-9/]*$", "deleted": false },
          { "entityCode": 218, "name": "Czechoslovakia", "countryCode": "CS", "continent": ["EU"],
            "cq": [15], "itu": [28], "prefix": "OK,OL,OM", "prefixRegex": "^O[KLM][A-Z0-9/]*$", "deleted": true },
          { "entityCode": 230, "name": "Germany", "countryCode": "DE", "continent": ["EU"],
            "cq": [14], "itu": [28], "prefix": "DA,DL,DK", "prefixRegex": "^D[ALK][A-Z0-9/]*$", "deleted": false },
          { "entityCode": 125, "name": "Juan Fernández Islands", "countryCode": "CL", "continent": ["SA"],
            "cq": [12], "itu": [14], "prefix": "CE0", "prefixRegex": "^CE0Z[A-Z0-9/]*$", "deleted": false },
          { "entityCode": 24, "name": "Bouvet Island", "countryCode": "BV", "continent": ["AF"],
            "cq": [38], "itu": [67], "prefix": "3Y", "prefixRegex": "^3Y[A-Z0-9/]*$", "deleted": false },
          { "entityCode": 199, "name": "Peter I Island", "countryCode": "AQ", "continent": ["AN"],
            "cq": [12], "itu": [72], "prefix": "3Y", "prefixRegex": "^3Y[A-Z0-9/]*$", "deleted": false },
          { "entityCode": 248, "name": "Italy", "countryCode": "IT", "continent": ["EU"],
            "cq": [15], "itu": [28], "prefix": "I", "prefixRegex": "^I[A-Z0-9/]*$", "deleted": false }
        ] }
        """

    private static func index(_ text: String = json) throws -> DxccCodeIndex {
        try DxccCodeIndex.fromData(Data(text.utf8))
    }

    // MARK: Java DxccCodeIndexTest

    @Test func differentNameOfSameCountryIsFoundByPrefix() throws {
        // cty.dat says "Slovak Republic", dxcc.json "Slovakia" — the OM prefix links them.
        #expect(try Self.index().code("Slovak Republic", "OM") == 504)
    }

    @Test func deletedEntityPrefixDoesNotBlock() throws {
        // OM also has the defunct Czechoslovakia; if it were counted, the prefix would be ambiguous.
        #expect(try Self.index().code("Neznámé jméno", "OM") == 504)
    }

    @Test func findsByNameEvenIfNotPrimaryPrefix() throws {
        #expect(try Self.index().code("Germany", "DL") == 230)
    }

    @Test func prefixOutsideFirstInListAlsoApplies() throws {
        #expect(try Self.index().code("Fed. Rep. of Germany", "DL") == 230)
    }

    @Test func diacriticsInNameAreHarmless() throws {
        #expect(try Self.index().code("Juan Fernandez Islands", "CE0Z") == 125)
    }

    @Test func ambiguousPrefixIsNotUsed() throws {
        // 3Y belongs to both Bouvet and Peter I — no guessing allowed.
        #expect(try Self.index().code("Neznámý ostrov", "3Y/x") == nil)
    }

    @Test func nameDecidesEvenIfPrefixIsAmbiguous() throws {
        #expect(try Self.index().code("Peter I Island", "3Y/p") == 199)
    }

    @Test func waeEntityMapsToParentCountry() throws {
        // cty.dat lists Sicily because of WAE; for DXCC it is Italy.
        #expect(try Self.index().code("Sicily", "IT9") == 248)
    }

    @Test func unknownEntityReturnsNothing() throws {
        #expect(try Self.index().code("Neznámá země", "QQ") == nil)
    }

    @Test func emptyInputsAreHarmless() throws {
        let index = try Self.index()
        #expect(index.code(nil, nil) == nil)
        #expect(index.code("", "") == nil)
    }

    // MARK: ambiguity and collisions (measured)

    /// The same number under several prefixes is not a collision (Java `putIfAbsent` + `prev != code`),
    /// whereas the same **name** under two different numbers disappears from the index entirely
    /// — measured `IDX same-code-prefix=504 name-clash=empty`.
    @Test func sameCodeTwiceIsNotAClashButSameNameIs() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":504,"name":"Slovakia","prefix":"OM,OM,om"},
                     {"entityCode":100,"name":"Slovakia","prefix":"XX"}]}
            """)
        #expect(index.code("?", "OM") == 504)
        #expect(index.code("Slovakia", nil) == nil)
        #expect(index.code("?", "om") == 504)
        #expect(index.code("?", "XX") == 100)
    }

    /// The prefix is trimmed and upper-cased before lookup — measured `prefix-pad=999`.
    @Test func prefixLookupTrimsAndUppercases() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":248,"name":"Italy","prefix":"I"},
                     {"entityCode":999,"name":"Sicily","prefix":"IT9"}]}
            """)
        #expect(index.code("?", "  it9  ") == 999)
        #expect(index.code("?", nil) == nil)
    }

    /// An alias takes precedence even when the source has its **own** entity for that name:
    /// "Sicily" resolves to Italy (248), not to the Sicilian record (999)
    /// — measured `IDX3 sicily=248`.
    @Test func aliasWinsOverDirectNameMatch() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":248,"name":"Italy","prefix":"I"},
                     {"entityCode":999,"name":"Sicily","prefix":"IT9"}]}
            """)
        #expect(index.code("Sicily", "IT9") == 248)
    }

    /// Empty keys do not get into the maps — measured `IDX2 empty-prefix=empty`.
    @Test func emptyKeysAreNotStored() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":1,"name":"A","prefix":","},{"entityCode":2,"name":"B","prefix":" "}]}
            """)
        #expect(index.code("?", "") == nil)
        #expect(index.code("?", " ") == nil)
        #expect(index.code("A", nil) == 1)
    }

    /// All aliases from the Java `ALIASES` must lead to the parent entity.
    @Test func allAliasesResolveToTheirParent() throws {
        let index = try Self.index("""
            {"dxcc":[
              {"entityCode":24,"name":"Bouvet Island"},
              {"entityCode":199,"name":"Peter I Island"},
              {"entityCode":217,"name":"Desventuradas Islands"},
              {"entityCode":177,"name":"Minami Tori Shima"},
              {"entityCode":192,"name":"Ogasawara Islands"},
              {"entityCode":111,"name":"Heard Island and McDonald Islands"},
              {"entityCode":117,"name":"International Telecommunication Union Headquarters"},
              {"entityCode":206,"name":"Austria"},
              {"entityCode":279,"name":"Scotland"},
              {"entityCode":248,"name":"Italy"},
              {"entityCode":259,"name":"Svalbard"},
              {"entityCode":390,"name":"Turkey"}
            ]}
            """)
        #expect(index.code("Bouvet", nil) == 24)
        #expect(index.code("Peter 1 Is", nil) == 199)
        #expect(index.code("San Felix and San Ambrosio", nil) == 217)
        #expect(index.code("Minami Torishima", nil) == 177)
        #expect(index.code("Ogasawara", nil) == 192)
        #expect(index.code("Heard Is", nil) == 111)
        #expect(index.code("ITU Headquarters", nil) == 117)
        #expect(index.code("Vienna Intl Ctr", nil) == 206)
        #expect(index.code("Shetland Is", nil) == 279)
        #expect(index.code("African Italy", nil) == 248)
        #expect(index.code("Sicily", nil) == 248)
        #expect(index.code("Bear Is", nil) == 259)
        #expect(index.code("European Turkey", nil) == 390)
    }

    // MARK: normalize (the table is a 1:1 output of the Java DxccCodeIndex.normalize)

    @Test func normalizeMatchesJava() {
        let expected: [(String?, String)] = [
            ("Juan Fernández Islands", "juan fernandez is"),
            ("Slovak Republic", "slovak rep"),
            ("Fed. Rep. of Germany", "fed rep germany"),
            ("St. Vincent", "st vincent"),
            ("Saint Helena", "st helena"),
            ("Heard Is.", "heard is"),
            ("ITU HQ", "itu headquarters"),
            ("Bear Is", "bear is"),
            ("European Turkey", "european turkey"),
            ("Sicily", "sicily"),
            ("African Italy", "african italy"),
            ("Vienna Intl Ctr", "vienna intl ctr"),
            ("Shetland Is", "shetland is"),
            ("Peter 1 Is", "peter 1 is"),
            ("San Felix & San Ambrosio", "san felix and san ambrosio"),
            ("Minami Torishima", "minami torishima"),
            ("Ogasawara", "ogasawara"),
            ("Bouvet", "bouvet"),
            ("Turks & Caicos Islands", "turks and caicos is"),
            ("Isle of Man", "isle man"),
            ("Republic of Korea", "rep korea"),
            ("Åland Islands", "aland is"),
            ("Côte d'Ivoire", "cote d ivoire"),
            ("  Spaced   Name  ", "spaced name"),
            ("", ""),
            ("ISLAND", "is"),
            ("Islands of Fed Republic", "is fed rep"),
            ("Christmas Island", "christmas is"),
            ("Federated States of Micronesia", "federated states micronesia"),
            ("Fisherman's Isl", "fisherman s is"),
            ("United Nations HQ", "united nations headquarters"),
            ("Mount Athos", "mount athos"),
            ("Straße", "stra e"),
            ("of", ""),
            ("is", "is"),
            (nil, ""),
        ]
        for (input, result) in expected {
            #expect(DxccCodeIndex.normalize(input) == result, "normalize(\(input ?? "nil"))")
        }
    }

    // MARK: error paths (measured)

    /// Bad JSON ends with `DxccException("Nelze načíst čísla DXCC z dxcc.json")`.
    @Test func malformedInputThrowsParseError() {
        for input in ["{\"dxcc\": [", "", "hello", "[]"] {
            do {
                _ = try DxccCodeIndex.fromData(Data(input.utf8))
                Issue.record("input \(input) should have ended with an error")
            } catch let failure as DxccError {
                #expect(failure.kind == .parse, "input \(input)")
                #expect(failure.message == "Nelze načíst čísla DXCC z dxcc.json")
            } catch {
                Issue.record("unexpected error type: \(error)")
            }
        }
    }

    /// **Unlike `DxccResolver`**, a missing or `null` `dxcc` field is not
    /// an error — an empty index results. Measured `I[dxcc-null] OK`, `I[no-key] OK`.
    @Test func missingEntityListGivesEmptyIndexUnlikeResolver() throws {
        for input in ["{}", "{\"dxcc\": null}"] {
            let index = try Self.index(input)
            #expect(index.code("Germany", "DL") == nil)
        }
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("{}".utf8))
        }
    }

    /// The index reads only `entityCode`, `name`, `prefix` and `deleted`; other fields
    /// (even wrongly typed) are ignored — measured `I[cq-scalar] OK`,
    /// `I[prefixRegex-scalar] OK`, where `DxccResolver` fails on the same input.
    @Test func fieldsOutsideItsOwnDtoAreIgnored() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":1,"name":"A","cq":15,"continent":"EU","prefixRegex":5}]}
            """)
        #expect(index.code("A", nil) == 1)
        #expect(throws: DxccError.self) {
            _ = try DxccResolver.fromData(Data("""
                {"dxcc":[{"entityCode":1,"name":"A","cq":15,"prefixRegex":"^A.*"}]}
                """.utf8))
        }
    }

    /// Jackson bends types here too: `deleted:"TRUE"` drops the entity, `name:123`
    /// becomes the text "123", `prefix:9` becomes "9" — measured.
    @Test func jacksonCoercionsApplyHereToo() throws {
        #expect(try Self.index("""
            {"dxcc":[{"entityCode":1,"name":"A","deleted":"TRUE"}]}
            """).code("A", nil) == nil)
        let numbers = try Self.index("""
            {"dxcc":[{"entityCode":1,"name":123,"prefix":9}]}
            """)
        #expect(numbers.code("123", nil) == 1)
        #expect(numbers.code("?", "9") == 1)
    }

    /// An entity without a name is skipped (Java `name == null` → `continue`),
    /// so even its prefix does not get into the index.
    @Test func entityWithoutNameIsSkippedEntirely() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":1,"prefix":"ZZ"}]}
            """)
        #expect(index.code("?", "ZZ") == nil)
    }

    // MARK: additional cases

    /// The prefix key is made with Java `trim()`, which **keeps** the non-breaking
    /// space. "OK\u{00A0}" is therefore the key "OK\u{00A0}", not "OK" — a query for "OK"
    /// must not return anything. (Swift `.whitespacesAndNewlines` would drop U+00A0
    /// and the index would return a DXCC number where Java returns nothing.)
    @Test func nonBreakingSpaceStaysInPrefixKey() throws {
        let index = try Self.index("""
            {"dxcc":[{"entityCode":7,"name":"A","prefix":"OK\\u00a0"}]}
            """)
        #expect(index.code(nil, "OK") == nil)
        #expect(index.code(nil, "OK\u{00a0}") == 7)
        // Ordinary spaces, on the other hand, are trimmed on both sides.
        let withSpaces = try Self.index("""
            {"dxcc":[{"entityCode":7,"name":"A","prefix":" OK "}]}
            """)
        #expect(withSpaces.code(nil, "OK") == 7)
        #expect(withSpaces.code(nil, "  ok  ") == 7)
    }

    /// A duplicate `dxcc` key is an error here too; within an entity the last one wins.
    @Test func duplicateKeysBehaveLikeJackson() throws {
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[{"entityCode":1,"name":"A"}],"dxcc":[]}"#.utf8))
        }
        let lastOne = try Self.index("""
            {"dxcc":[{"entityCode":1,"name":"A","name":"B","prefix":"OK"}]}
            """)
        #expect(lastOne.code("A", nil) == nil)
        #expect(lastOne.code("B", nil) == 1)
        #expect(lastOne.code(nil, "OK") == 1)
    }

    /// A `null` element of the `dxcc` array is a Java `NullPointerException` here too
    /// (`e.deleted()` on `null`), not `DxccException`.
    @Test func nullEntityElementIsNullPointerKind() {
        do {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[null]}"#.utf8))
            Issue.record("should have ended with an error")
        } catch let failure as DxccError {
            #expect(failure.kind == .nullPointer)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// Content after the end of the JSON is ignored (same as for the resolver).
    @Test func trailingContentIsIgnored() throws {
        let index = try Self.index(#"{"dxcc":[{"entityCode":1,"name":"A"}]}xx"#)
        #expect(index.code("A", nil) == 1)
    }

    /// An overflow of the Java 32-bit `int` brings down the file here too.
    @Test func intOutOfRangeFailsTheWholeFile() {
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[{"entityCode":2147483648,"name":"A"}]}"#.utf8))
        }
    }

    /// An unusual letter case in the textual `deleted` is an error for the whole file,
    /// not a silent loss of the entity.
    @Test func unusualBooleanSpellingFailsTheWholeFile() {
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[{"entityCode":1,"name":"A","deleted":"tRuE"}]}"#.utf8))
        }
    }

    // MARK: further cases

    /// The index's `RawEntity` has **four** properties (not nine like the resolver), so
    /// it is complete sooner and a duplicate key after that brings down the whole file. The same file
    /// can therefore pass the resolver and not the index — that count is part of the behaviour.
    @Test func duplicateAfterCompleteRecordThrows() throws {
        let complete = #""entityCode":1,"name":"A","prefix":"OK","deleted":false"#
        for dup in [#""entityCode":9"#, #""name":"Other""#, #""prefix":"XX""#, #""deleted":true"#] {
            #expect(throws: DxccError.self, "duplicate \(dup)") {
                _ = try DxccCodeIndex.fromData(Data("{\"dxcc\":[{\(complete),\(dup)}]}".utf8))
            }
        }
        // Three properties + duplicate → the last wins, passes.
        let incomplete = try Self.index("""
            {"dxcc":[{"entityCode":1,"name":"A","name":"B","prefix":"OK"}]}
            """)
        #expect(incomplete.code("B", nil) == 1)
        #expect(incomplete.code("A", nil) == nil)
        // A duplicate unknown key (for the index `cq` is unknown) is fine.
        #expect(try Self.index("{\"dxcc\":[{\(complete),\"cq\":1,\"cq\":2}]}").code("A", nil) == 1)
        // Different property count: four + a duplicate `name` bring down the index,
        // but the resolver (nine properties) passes the same file.
        let fourPlusDup = """
            {"dxcc":[{"entityCode":1,"name":"A","prefix":"OK","deleted":false,"name":"B","prefixRegex":"^OK.*"}]}
            """
        #expect(try DxccResolver.fromData(Data(fourPlusDup.utf8)).entities().first?.name == "B")
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(fourPlusDup.utf8))
        }
    }

    /// Every occurrence is converted, even if the next one overwrites it.
    @Test func everyDuplicateOccurrenceIsConverted() {
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[{"entityCode":"abc","entityCode":1,"name":"A"}]}"#.utf8))
        }
    }

    /// A `null` content is a Java `NullPointerException` here too ("raw" is null).
    @Test func nullDocumentIsNullPointerKind() {
        do {
            _ = try DxccCodeIndex.fromData(Data("null".utf8))
            Issue.record("should have ended with an error")
        } catch let failure as DxccError {
            #expect(failure.kind == .nullPointer)
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// The `int` range is checked before truncation here too.
    @Test func doubleRangeIsCheckedBeforeTruncation() throws {
        #expect(throws: DxccError.self) {
            _ = try DxccCodeIndex.fromData(Data(#"{"dxcc":[{"entityCode":2147483647.9,"name":"A"}]}"#.utf8))
        }
        #expect(try Self.index(#"{"dxcc":[{"entityCode":2147483647.0,"name":"A"}]}"#)
            .code("A", nil) == 2_147_483_647)
    }
}
