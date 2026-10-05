import Testing
@testable import MCLCore

/// `QsoContext` — predicates over entities and access to the received fields. There is no Java test
/// for it; the values are measured by the maintainer-only probe
/// (JDK 21.0.2).
@Suite struct QsoContextTests {

    private static func entity(_ code: Int, _ continents: [String?]?) -> DxccEntity {
        DxccEntity(entityCode: code, name: "N\(code)", countryCode: "C\(code)", continents: continents,
                   cq: [], itu: [], lat: .nan, lon: .nan)
    }

    struct PairRow: Sendable, CustomStringConvertible {
        let label: String
        let worked: DxccEntity?
        let own: DxccEntity?
        let ownDxcc: Bool
        let workedContinent: String?
        let ownContinent: String?
        let sameContinent: Bool
        let otherContinent: Bool
        var description: String { label }
    }

    /// Continents are compared with Java `equals` by UTF-16: `eu` ≠ `EU` and `A`+U+030A ≠ U+00C5
    /// (Swift `==` would treat them as equal). A `null` first element = continent unknown.
    static let pairs: [PairRow] = [
        PairRow(label: "null/null", worked: nil, own: nil, ownDxcc: false,
                workedContinent: nil, ownContinent: nil, sameContinent: false, otherContinent: false),
        PairRow(label: "EU/null", worked: entity(1, ["EU"]), own: nil, ownDxcc: false,
                workedContinent: "EU", ownContinent: nil, sameContinent: false, otherContinent: false),
        PairRow(label: "null/EU", worked: nil, own: entity(1, ["EU"]), ownDxcc: false,
                workedContinent: nil, ownContinent: "EU", sameContinent: false, otherContinent: false),
        PairRow(label: "same code EU/EU", worked: entity(1, ["EU"]), own: entity(1, ["EU"]), ownDxcc: true,
                workedContinent: "EU", ownContinent: "EU", sameContinent: true, otherContinent: false),
        PairRow(label: "diff code EU/EU", worked: entity(1, ["EU"]), own: entity(2, ["EU"]), ownDxcc: false,
                workedContinent: "EU", ownContinent: "EU", sameContinent: true, otherContinent: false),
        PairRow(label: "EU/NA", worked: entity(1, ["EU"]), own: entity(2, ["NA"]), ownDxcc: false,
                workedContinent: "EU", ownContinent: "NA", sameContinent: false, otherContinent: true),
        PairRow(label: "eu/EU", worked: entity(1, ["eu"]), own: entity(2, ["EU"]), ownDxcc: false,
                workedContinent: "eu", ownContinent: "EU", sameContinent: false, otherContinent: true),
        PairRow(label: "nullList/EU", worked: entity(1, nil), own: entity(2, ["EU"]), ownDxcc: false,
                workedContinent: nil, ownContinent: "EU", sameContinent: false, otherContinent: false),
        PairRow(label: "[]/EU", worked: entity(1, []), own: entity(2, ["EU"]), ownDxcc: false,
                workedContinent: nil, ownContinent: "EU", sameContinent: false, otherContinent: false),
        PairRow(label: "[null,EU]/EU", worked: entity(1, [nil, "EU"]), own: entity(2, ["EU"]), ownDxcc: false,
                workedContinent: nil, ownContinent: "EU", sameContinent: false, otherContinent: false),
        PairRow(label: "[null]/[null]", worked: entity(1, [nil]), own: entity(2, [nil]), ownDxcc: false,
                workedContinent: nil, ownContinent: nil, sameContinent: false, otherContinent: false),
        PairRow(label: "EU/nullList", worked: entity(1, ["EU"]), own: entity(2, nil), ownDxcc: false,
                workedContinent: "EU", ownContinent: nil, sameContinent: false, otherContinent: false),
        PairRow(label: "same code nullList", worked: entity(7, nil), own: entity(7, nil), ownDxcc: true,
                workedContinent: nil, ownContinent: nil, sameContinent: false, otherContinent: false),
        PairRow(label: "A+U+030A/U+00C5", worked: entity(1, ["A\u{030A}"]), own: entity(2, ["\u{00C5}"]),
                ownDxcc: false, workedContinent: "A\u{030A}", ownContinent: "\u{00C5}",
                sameContinent: false, otherContinent: true),
    ]

    private static func utf16(_ text: String?) -> [UInt16]? { text.map { Array($0.utf16) } }

    @Test(arguments: pairs)
    func entityPredicatesMatchJava(_ row: PairRow) {
        let ctx = QsoContext(call: nil, band: nil, mode: nil, received: nil,
                             workedEntity: row.worked, ownEntity: row.own, workedClass: nil)
        #expect(ctx.ownDxcc == row.ownDxcc)
        #expect(Self.utf16(ctx.workedContinent) == Self.utf16(row.workedContinent))
        #expect(Self.utf16(ctx.ownContinent) == Self.utf16(row.ownContinent))
        #expect(ctx.sameContinent == row.sameContinent)
        #expect(ctx.otherContinent == row.otherContinent)
    }

    @Test func shortInitDefaultsLikeJava() {
        let ctx = QsoContext(call: "OK1XOE", band: "20m", mode: "CW", received: nil,
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(ctx.ownGrid == nil)
        #expect(ctx.ownItuZone == nil)
        #expect(ctx.ownQth == nil)
        #expect(ctx.bonusStation == false)
    }

    // MARK: - received fields

    @Test func withoutReceivedEverythingIsAbsent() {
        let ctx = QsoContext(call: nil, band: nil, mode: nil, received: nil,
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(ctx.fieldCanonical("x") == nil)
        #expect(ctx.fieldRaw("x") == nil)
        #expect(!ctx.fieldPresent("x"))
        #expect(ctx.fieldCanonical(nil) == nil)
    }

    struct FieldRow: Sendable, CustomStringConvertible {
        let id: String?
        let canonical: String?
        let raw: String?
        let present: Bool
        var description: String {
            id.map { $0.unicodeScalars.map { $0.isASCII ? String($0) : "\\u{\(String($0.value, radix: 16))}" }.joined() }
                ?? "nil"
        }
    }

    /// Java `LinkedHashMap`: a `null` id is a valid key, an invalid field has `canonical` `null`
    /// and `present` false, a `null` value = the field is missing, a valid field with `canonical` `null` is
    /// "present", `K` and KELVIN SIGN are two different fields.
    static let fieldRows: [FieldRow] = [
        FieldRow(id: "v", canonical: "C1", raw: "r1", present: true),
        FieldRow(id: "inv", canonical: nil, raw: "r2", present: false),
        FieldRow(id: "nul", canonical: nil, raw: nil, present: false),
        FieldRow(id: nil, canonical: "CN", raw: "rn", present: true),
        FieldRow(id: "vnull", canonical: nil, raw: "r3", present: true),
        FieldRow(id: "K", canonical: "ASCII", raw: "k1", present: true),
        FieldRow(id: "\u{212A}", canonical: "KELVIN", raw: "k2", present: true),
        FieldRow(id: "missing", canonical: nil, raw: nil, present: false),
    ]

    private static let received = JavaLinkedMap<ExchangeValue>([
        ("v", .valid("r1", "C1")),
        ("inv", .invalid("r2", "chyba")),
        ("nul", nil),
        (nil, .valid("rn", "CN")),
        ("vnull", ExchangeValue(raw: "r3", canonical: nil, valid: true, error: nil)),
        ("K", .valid("k1", "ASCII")),
        ("\u{212A}", .valid("k2", "KELVIN")),
    ])

    @Test(arguments: fieldRows)
    func receivedFieldsMatchJava(_ row: FieldRow) {
        let ctx = QsoContext(call: nil, band: nil, mode: nil, received: Self.received,
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(ctx.fieldCanonical(row.id) == row.canonical)
        #expect(ctx.fieldRaw(row.id) == row.raw)
        #expect(ctx.fieldPresent(row.id) == row.present)
    }

    @Test func kelvinDoesNotFindAsciiK() {
        let ctx = QsoContext(call: nil, band: nil, mode: nil,
                             received: JavaLinkedMap([("K", .valid("k1", "ASCII"))]),
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(ctx.fieldCanonical("\u{212A}") == nil)
        #expect(ctx.fieldCanonical("K") == "ASCII")
    }

    /// Recorded leniency: Java over an immutable `Map.of()`
    /// (the `StationClassifier` probe context) fails on `get(null)` with a `NullPointerException`;
    /// `JavaLinkedMap` behaves like a `LinkedHashMap` → the field is missing.
    @Test func nilIdOverEmptyReceivedIsAbsentNotACrash() {
        let ctx = QsoContext(call: nil, band: nil, mode: nil, received: JavaLinkedMap(),
                             workedEntity: nil, ownEntity: nil, workedClass: nil)
        #expect(ctx.fieldCanonical(nil) == nil)
        #expect(ctx.fieldRaw(nil) == nil)
        #expect(!ctx.fieldPresent(nil))
        #expect(ctx.fieldCanonical("x") == nil)
    }
}
