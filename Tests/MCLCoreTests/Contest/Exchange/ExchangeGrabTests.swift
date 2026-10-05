import Testing
@testable import MCLCore

/// Port of the Java `ExchangeGrabTest` (15 tests) and pinned port properties
/// (a bad regex throws, an untranslatable one is ignored, `nil` elements). Edge cases
/// measured on Java are in `GrabMeasuredTests`.
@Suite struct ExchangeGrabTests {

    private typealias Field = ContestDefinition.ExchangeField
    private typealias Validation = ContestDefinition.FieldValidation

    private static func f(_ id: String, _ type: ContestDefinition.FieldType?, _ v: Validation?) -> Field {
        Field(id: id, type: type, required: true, source: .MANUAL, appliesWhen: nil, validation: v)
    }

    /// Received CQ WW RTTY exchange: report, CQ zone 1–40, state (W/VE only).
    private static let cqww: [Field?] = [
        f("rst", .RST, nil),
        f("zone", .CQ_ZONE, Validation(regex: nil, min: 1, max: 40, length: nil)),
        f("state", .STATE, nil),
    ]

    private static func map(_ pairs: [(String?, String?)]) -> JavaLinkedMap<String> {
        JavaLinkedMap(pairs)
    }

    private static func route(_ fields: [Field?], _ current: [(String?, String?)],
                              _ token: String?) throws -> ExchangeGrab.Grab? {
        try ExchangeGrab.route(fields, map(current), token)
    }

    // MARK: - ported Java tests

    @Test func reportGoesToRst() throws {
        let g = try #require(try Self.route(Self.cqww, [], "599"))
        #expect(g.fieldId == "rst")
        #expect(g.value == "599")
    }

    @Test func numberInZoneRangeGoesToZone() throws {
        #expect(try Self.route(Self.cqww, [("rst", "599")], "15")?.fieldId == "zone")
    }

    @Test func twoDigitZoneDoesNotFallIntoRstBecauseRstHasThreeDigits() throws {
        #expect(try Self.route(Self.cqww, [], "15")?.fieldId == "zone")
    }

    @Test func numberOutOfZoneRangeDoesNotGoToZone() throws {
        #expect(try Self.route(Self.cqww, [("rst", "599")], "77") == nil)
    }

    @Test func stateGoesToState() throws {
        #expect(try Self.route(Self.cqww, [("rst", "599"), ("zone", "5")], "CT")?.fieldId == "state")
    }

    @Test func emptyFieldTakesPrecedence() throws {
        #expect(try Self.route(Self.cqww, [("rst", "599"), ("zone", "")], "14")?.fieldId == "zone")
    }

    @Test func whenEverythingIsFilledFirstMatchingIsOverwritten() throws {
        #expect(try Self.route(Self.cqww, [("rst", "599"), ("zone", "15")], "14")?.fieldId == "zone")
    }

    @Test func edgeCharactersAreTrimmedAndLowercaseIsUppercased() throws {
        let g = try #require(try Self.route(Self.cqww, [("rst", "599"), ("zone", "5")], "(ct)"))
        #expect(g.fieldId == "state")
        #expect(g.value == "CT")
    }

    @Test func callsignGoesNowhere() throws {
        #expect(try Self.route(Self.cqww, [], "OK1XOE") == nil)
    }

    @Test func serialNumberRespectsLength() throws {
        let fields: [Field?] = [
            Self.f("rst", .RST, nil),
            Self.f("nr", .SERIAL, Validation(regex: nil, min: nil, max: nil, length: 3)),
        ]
        #expect(try Self.route(fields, [("rst", "599")], "007")?.fieldId == "nr")
        #expect(try Self.route(fields, [("rst", "599")], "7") == nil)
    }

    @Test func locatorGoesToLocator() throws {
        let fields: [Field?] = [Self.f("grid", .LOCATOR, nil)]
        #expect(try Self.route(fields, [], "JN88wx")?.fieldId == "grid")
        #expect(try Self.route(fields, [], "JN") == nil)
    }

    @Test func regexFromDefinitionDecides() throws {
        let fields: [Field?] = [Self.f("sect", .TEXT, Validation(regex: "[A-Z]{2,3}", min: nil, max: nil, length: nil))]
        #expect(try Self.route(fields, [], "OH")?.fieldId == "sect")
        #expect(try Self.route(fields, [], "OHIOX") == nil)
    }

    /// Line from a W/VE station: both exchange parts must find their field. Java keeps a `HashMap` here;
    /// `route` only reads from it (`get`), so iteration order does not leak into the result.
    @Test func doubleExchangeZoneAndStateFindTheirFields() throws {
        var exch = JavaLinkedMap<String>()
        for token in ["599", "05", "NY"] {
            let g = try #require(try ExchangeGrab.route(Self.cqww, exch, token), "nikam nevede: \(token)")
            exch.put(g.fieldId, g.value)
        }
        #expect(exch["rst"] == "599")
        #expect(exch["zone"] == "05")
        #expect(exch["state"] == "NY")
    }

    @Test func secondNumberOnLineHasNowhereToGo() throws {
        // "599 05 05" — a repeated zone must not pose as another field.
        #expect(try Self.route(Self.cqww, [("rst", "599"), ("zone", "05")], "05")?.fieldId == "zone",
                "the same zone is overwritten, nothing else is offered")
    }

    @Test func emptyTokenReturnsNothing() throws {
        #expect(try Self.route(Self.cqww, [], "  ") == nil)
        #expect(try Self.route(Self.cqww, [], "***") == nil)
    }

    // MARK: - port properties

    /// Review 4 focus: a bad regex in the definition is an error (Java's uncaught
    /// `PatternSyntaxException` with the same text), not a process crash or silent ignoring.
    @Test func invalidRegexThrowsJavaMessage() {
        let fields: [Field?] = [
            Self.f("a", .TEXT, nil),
            Self.f("t", .TEXT, Validation(regex: "(", min: nil, max: nil, length: nil)),
        ]
        #expect(throws: ExchangeError(kind: .patternSyntax, message: "Unclosed group near index 1\n(")) {
            try ExchangeGrab.route(fields, JavaLinkedMap(), "ABC")
        }
        // An empty token or a `nil` field list never reaches compilation — as in Java.
        #expect(throws: Never.self) { try ExchangeGrab.route(fields, JavaLinkedMap(), "***") }
    }

    /// A regex that the `JavaRegex` adapter does not translate is ignored (same as in `ExchangeEngine`);
    /// Java translates and uses it — a recorded divergence.
    @Test func unsupportedRegexIsIgnored() throws {
        let fields: [Field?] = [Self.f("t", .TEXT, Validation(regex: "\\p{javaLowerCase}+", min: nil, max: nil, length: nil))]
        #expect(try ExchangeGrab.route(fields, JavaLinkedMap(), "ABC") == ExchangeGrab.Grab(fieldId: "t", value: "ABC"))
    }

    /// Java NPE (`nil` element, `type == nil`) → Swift skips the `nil` element, a field without a type accepts nothing.
    @Test func nilElementsAreLenient() throws {
        let fields: [Field?] = [nil, Self.f("t", nil, nil), Self.f("rst", .RST, nil)]
        #expect(try ExchangeGrab.route(fields, JavaLinkedMap(), "599")?.fieldId == "rst")
        #expect(try ExchangeGrab.route(nil, JavaLinkedMap(), "599") == nil)
    }

    /// Equality of `Grab` like a Java record: texts compared by UTF-16 (`Å` ≠ `A` + ring).
    @Test func grabEqualityIsUtf16() {
        #expect(ExchangeGrab.Grab(fieldId: "\u{C5}", value: "1") != ExchangeGrab.Grab(fieldId: "A\u{30A}", value: "1"))
        #expect(ExchangeGrab.Grab(fieldId: nil, value: "K") != ExchangeGrab.Grab(fieldId: nil, value: "\u{212A}"))
        #expect(ExchangeGrab.Grab(fieldId: nil, value: "1") == ExchangeGrab.Grab(fieldId: nil, value: "1"))
    }
}
