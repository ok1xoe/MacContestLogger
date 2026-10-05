import Foundation
import Testing
@testable import MCLCore

/// Port of the Java `ExchangeEngineTest` (8 tests, 1:1) and pinned properties outside the
/// `ExchangeMeasured` table: serial number above 2³¹−1 (review 4 focus), `ExchangeValue` equality
/// by UTF-16, `nil` elements.
@Suite struct ExchangeEngineTests {
    typealias ExchangeField = ContestDefinition.ExchangeField
    typealias FieldValidation = ContestDefinition.FieldValidation

    private let engine = ExchangeEngine()

    private static func field(_ id: String, _ type: ContestDefinition.FieldType, _ validation: FieldValidation?)
        -> ExchangeField {
        ExchangeField(id: id, type: type, required: true, source: nil, appliesWhen: nil, validation: validation)
    }

    private static func load(_ file: String) throws -> ContestDefinition {
        try ContestDefinitionLoader.loadFile(PointsCalculatorTests.contestsDirectory().appendingPathComponent(file))
    }

    // MARK: - Java ExchangeEngineTest

    @Test func rstValidation() throws {
        let rst = Self.field("rst", .RST, nil)
        #expect(try engine.parse(rst, "599").valid)
        #expect(try engine.parse(rst, "59").valid)
        #expect(try !engine.parse(rst, "5x9").valid)
    }

    @Test func zoneNumericWithRange() throws {
        let zone = Self.field("zone", .CQ_ZONE, FieldValidation(regex: nil, min: 1, max: 40, length: nil))
        let ok = try engine.parse(zone, "07")
        #expect(ok.valid)
        #expect(ok.canonical == "7")                      // canonicalization without leading zero
        #expect(try !engine.parse(zone, "50").valid)       // out of range
        #expect(try !engine.parse(zone, "abc").valid)      // non-numeric
    }

    @Test func textCodeUppercased() throws {
        let value = try engine.parse(Self.field("state", .STATE, nil), "ca")
        #expect(value.valid)
        #expect(value.canonical == "CA")
    }

    @Test func activeFieldsDependOnWorkedClass() throws {
        let definition = try Self.load("cq-160-cw.yaml")
        let wve = engine.activeReceivedFields(definition, "wve").map(\.id)
        let dx = engine.activeReceivedFields(definition, "dx").map(\.id)
        #expect(wve == ["rst", "state"])
        #expect(dx == ["rst", "zone"])
    }

    @Test func parsesWholeLine() throws {
        let definition = try Self.load("cq-ww-cw.yaml")
        let parsed = try engine.parseLine(definition.exchange?.received ?? [], "599 14")
        #expect(parsed["rst"]?.canonical == "599")
        #expect(parsed["zone"]?.canonical == "14")
    }

    @Test func sentDefaultsFromModeAndStation() throws {
        let definition = try Self.load("cq-ww-cw.yaml")
        let context = ExchangeContext(mode: .cw, nextSerial: 1, station: JavaLinkedMap([("zone", "14")]))
        let defaults = engine.sentDefaults(definition, context)
        #expect(defaults["rst"] == "599")   // AUTO_RST by mode
        #expect(defaults["zone"] == "14")   // FROM_STATION
    }

    /// The sent exchange is shown in the header of the entry window (AppState.sentExchangeText).
    /// For free logging it is just the report — and that follows the mode.
    @Test func sentDefaultsForFreeLoggingAreOnlyTheReport() throws {
        let definition = try Self.load("dx.yaml")
        let cw = engine.sentDefaults(definition, ExchangeContext(mode: .cw, nextSerial: 1, station: JavaLinkedMap()))
        #expect(cw == JavaLinkedMap([("rst", "599")]))
        let ssb = engine.sentDefaults(definition, ExchangeContext(mode: .ssb, nextSerial: 1, station: JavaLinkedMap()))
        #expect(ssb == JavaLinkedMap([("rst", "59")]))
    }

    /// Contest with a serial number: the sent exchange includes the serial too (WPX).
    @Test func sentDefaultsIncludeSerialWhenContestUsesIt() throws {
        let definition = try Self.load("cq-wpx-cw.yaml")
        let defaults = engine.sentDefaults(definition, ExchangeContext(mode: .cw, nextSerial: 42, station: JavaLinkedMap()))
        #expect(defaults["rst"] == "599")
        #expect(defaults["nr"] == "42")
    }

    // MARK: - review 4 focus: number above 2³¹−1

    /// Java: `Integer.parseInt` in `NumericHandler` throws an uncaught `NumberFormatException`
    /// (latent UI crash). Swift throws `ExchangeError` with the same text — not a process crash.
    @Test(arguments: [ContestDefinition.FieldType.SERIAL, .INTEGER, .CQ_ZONE, .ITU_ZONE])
    func numberOverIntMaxThrowsLikeJava(_ type: ContestDefinition.FieldType) throws {
        let field = Self.field("nr", type, nil)
        #expect(try engine.parse(field, "2147483647").canonical == "2147483647")
        #expect(throws: ExchangeError(kind: .numberFormat, message: "For input string: \"2147483648\"")) {
            try engine.parse(field, " 2147483648 ")
        }
        #expect(throws: ExchangeError(kind: .numberFormat, message: "For input string: \"99999999999\"")) {
            try engine.parse(field, "99999999999")
        }
        #expect(throws: ExchangeError.self) {
            try engine.parseLine([field], "99999999999999999999999999999999")
        }
    }

    /// In the `min`/`max` validation of a text field the overflow is just "očekáváno číslo" (Java catches it).
    @Test func overflowInValidationIsInvalidNotError() throws {
        let field = Self.field("t", .TEXT, FieldValidation(regex: nil, min: 1, max: nil, length: nil))
        let value = try engine.parse(field, "2147483648")
        #expect(value == .invalid("2147483648", "očekáváno číslo"))
    }

    // MARK: - bad regex in the definition (review 4 focus)

    /// Java's `PatternSyntaxException` is swallowed; a pattern the adapter does not translate is ignored by Swift
    /// the same way (Java translates and uses it — a recorded divergence).
    @Test func invalidOrUnsupportedRegexIsIgnored() throws {
        for regex in ["(", "[a-", "\\p{javaLowerCase}+", "(?x) A B C"] {
            let field = Self.field("t", .TEXT, FieldValidation(regex: regex, min: nil, max: nil, length: nil))
            #expect(try engine.parse(field, "abd") == .valid("abd", "ABD"), "\(regex)")
        }
    }

    // MARK: - ExchangeValue

    /// A Java record compares texts by UTF-16 — canonically equal values do **not** match.
    @Test func valueEqualityIsUtf16() {
        #expect(ExchangeValue.valid("\u{C5}", "\u{C5}") != .valid("A\u{30A}", "A\u{30A}"))
        #expect(ExchangeValue.valid("x", "\u{212A}") != .valid("x", "K"))
        #expect(ExchangeValue.invalid("a", "e") != .invalid("a", nil))
        #expect(ExchangeValue.invalid(nil, nil) == .invalid(nil, nil))
        #expect(ExchangeValue.valid("a", "A") == .valid("a", "A"))
        #expect(ExchangeValue.valid("a", nil) != .invalid("a", nil))
        #expect(JavaLinkedMap([("k", ExchangeValue.valid("\u{C5}", "\u{C5}"))])
                != JavaLinkedMap([("k", ExchangeValue.valid("A\u{30A}", "A\u{30A}"))]))
    }

    @Test func emptyValueIsJavas() {
        #expect(ExchangeValue.empty() == ExchangeValue(raw: "", canonical: nil, valid: false, error: "prázdné"))
    }

    // MARK: - nil elements (Java NPE → leniency)

    @Test func nilFieldElementsAreSkipped() throws {
        let a = Self.field("a", .TEXT, nil)
        let definition = ContestDefinition(id: "x", exchange: ContestDefinition.Exchange(
            sent: [nil, ExchangeField(id: "s", type: nil, required: false, source: .AUTO_RST, appliesWhen: nil,
                                      validation: nil)],
            received: [nil, a]))
        #expect(engine.activeReceivedFields(definition, nil).map(\.id) == ["a"])
        #expect(engine.sentDefaults(definition, .of(.ssb, 1)) == JavaLinkedMap([("s", "59")]))
        // the token position belongs to the `nil` element too: `a` gets the second token
        #expect(try engine.parseLine([nil, a], "p q") == JavaLinkedMap([("a", .valid("q", "Q"))]))
    }

    @Test func contextDefaults() {
        let context = ExchangeContext.of(.cw, 7)
        #expect(context.station.isEmpty)
        #expect(context.roverQth == "")
        #expect(ExchangeContext(mode: nil, nextSerial: 1, station: JavaLinkedMap()).roverQth == "")
    }
}
