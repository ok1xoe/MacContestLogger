import Foundation
import Testing
@testable import MCLCore

/// Verifies DXCC exceptions that depend on the callsign shape and that prefix data cannot
/// express. The fake delegate imitates `~/dxcc-json`: it returns every `KG4*`
/// callsign as Guantanamo (entity 105), other US callsigns as USA (291).
///
/// The first five tests are a port of the Java `DxccSpecialCasesTest`; the rest measures
/// the boundaries of the rule and what happens when the delegate does not know `W1AW`.
@Suite struct DxccSpecialCasesTests {

    private static let usa = DxccEntity(
        entityCode: 291, name: "United States of America", countryCode: "US", continents: ["NA"],
        cq: [3, 4, 5], itu: [6, 7, 8], lat: .nan, lon: .nan)
    private static let gtmo = DxccEntity(
        entityCode: 105, name: "Guantanamo Bay", countryCode: "US", continents: ["NA"],
        cq: [8], itu: [11], lat: .nan, lon: .nan)
    private static let cz = DxccEntity(
        entityCode: 503, name: "Czech Republic", countryCode: "CZ", continents: ["EU"],
        cq: [15], itu: [28], lat: .nan, lon: .nan)

    /// Imitates the data: every KG4 → Guantanamo, W/K/N (except KG4) → USA, OK → Czechia.
    private struct Fake: DxccLookup {
        /// When `false`, the delegate does not know even `W1AW` — the correction then does not apply.
        var knowsUsa = true

        func resolve(_ callsign: String?) -> DxccEntity? {
            let c = DxccResolver.normalize(callsign ?? "")
            if c.hasPrefix("KG4") { return DxccSpecialCasesTests.gtmo }
            if knowsUsa, c.hasPrefix("W") || c.hasPrefix("K") || c.hasPrefix("N") {
                return DxccSpecialCasesTests.usa
            }
            if c.hasPrefix("OK") { return DxccSpecialCasesTests.cz }
            return nil
        }

        func entities() -> [DxccEntity] {
            [DxccSpecialCasesTests.usa, DxccSpecialCasesTests.gtmo, DxccSpecialCasesTests.cz]
        }
    }

    private let resolver = DxccSpecialCases(Fake())

    // MARK: - Port of the Java DxccSpecialCasesTest

    @Test func kg4WithTwoCharSuffixStaysGuantanamo() {
        #expect(resolver.resolve("KG4AB")?.entityCode == 105)
        #expect(resolver.resolve("KG4NE")?.entityCode == 105)
    }

    @Test func kg4WithThreeCharSuffixBecomesUsa() {
        #expect(resolver.resolve("KG4IGC")?.entityCode == 291)
        #expect(resolver.resolve("KG4CUY")?.entityCode == 291)
        #expect(resolver.resolve("KG4WOJ")?.entityCode == 291)
    }

    @Test func kg4WithOneCharSuffixBecomesUsa() {
        #expect(resolver.resolve("KG4W")?.entityCode == 291)
    }

    @Test func kg4PortableSuffixIgnoredForLengthRule() {
        // KG4IGC/M → base KG4IGC (3 characters) = USA
        #expect(resolver.resolve("KG4IGC/M")?.entityCode == 291)
        // KG4AB/P → base KG4AB (2 characters) = Guantanamo
        #expect(resolver.resolve("KG4AB/P")?.entityCode == 105)
    }

    @Test func nonKg4CallsUnchanged() {
        #expect(resolver.resolve("W1AW")?.entityCode == 291)
        #expect(resolver.resolve("OK1XOE")?.entityCode == 503)
    }

    // MARK: - Additionally measured behaviours

    @Test func boundaryIsExactlyTwoAlphanumericCharacters() {
        // Zero characters and a non-alphanumeric suffix = USA, not Guantanamo.
        #expect(resolver.resolve("KG4")?.entityCode == 291)
        #expect(resolver.resolve("KG4A-")?.entityCode == 291, "a hyphen is not letterOrDigit")
        #expect(resolver.resolve("KG4A.")?.entityCode == 291)
        // Unicode letters and digits are counted (Character.isLetterOrDigit).
        #expect(resolver.resolve("KG4\u{00C1}B")?.entityCode == 105)
        #expect(resolver.resolve("KG4\u{0660}\u{0661}")?.entityCode == 105, "Arabic digits are Nd")
        // An emoji has length 2 in UTF-16, but both halves are surrogates → USA.
        #expect(resolver.resolve("KG4\u{1F388}")?.entityCode == 291)
    }

    /// Cases that distinguish Java counting (UTF-16 units
    /// + `Character.isLetterOrDigit`) from reading by graphemes with
    /// `isLetter || isNumber`. Without them both variants pass the same way, because
    /// the emoji above does not discriminate — a surrogate is not letterOrDigit in either
    /// reading. All values are measured on Java v1.1.1.
    @Test func suffixLengthCountsByUtf16UnitsAndJavaCategories() {
        // A + combining diaeresis + B: three units in UTF-16 → USA.
        // By graphemes it would be two graphemes (Ä, B), both letters → Guantanamo.
        #expect(resolver.resolve("KG4A\u{0308}B")?.entityCode == 291)
        #expect(resolver.resolve("KG4A\u{0301}")?.entityCode == 291,
                "a combining acute is not counted as a letter")
        // Superscript two (category No): Java `isDigit` is false → USA.
        // Swift `Character.isNumber` is true for it → would give Guantanamo.
        #expect(resolver.resolve("KG4\u{00B2}\u{00B2}")?.entityCode == 291)
        // Roman numeral I (category Nl): same.
        #expect(resolver.resolve("KG4\u{2160}\u{2160}")?.entityCode == 291)
        // An underscore is not letterOrDigit in either reading — a check that
        // a two-character suffix alone is not enough.
        #expect(resolver.resolve("KG4_A")?.entityCode == 291)
    }

    @Test func emptyCallsignGoesStraightToDelegate() {
        #expect(resolver.resolve(nil) == nil)
        #expect(resolver.resolve("") == nil)
        #expect(resolver.resolve("   ") == nil)
        // A non-breaking space does not pass Java isBlank, but the delegate does not know it anyway.
        #expect(resolver.resolve("\u{00A0}") == nil)
    }

    @Test func withoutKnownUsaCallsignDelegateResultStays() {
        // No hard-wired fallback: when the delegate does not know W1AW, KG4IGC stays
        // Guantanamo — exactly as Java does it.
        let without = DxccSpecialCases(Fake(knowsUsa: false))
        #expect(without.resolve("KG4IGC")?.entityCode == 105)
        #expect(without.resolve("KG4AB")?.entityCode == 105)
    }

    @Test func whenBaseIsAlreadyUsaNothingChanges() throws {
        // baseAlreadyUsa: a delegate that returns KG4 directly as USA passes unchanged.
        struct AllUsa: DxccLookup {
            func resolve(_ callsign: String?) -> DxccEntity? { DxccSpecialCasesTests.usa }
            func entities() -> [DxccEntity] { [DxccSpecialCasesTests.usa] }
        }
        let r = DxccSpecialCases(AllUsa())
        let e = try #require(r.resolve("KG4IGC"))
        #expect(e.entityCode == 291)
    }

    @Test func kg4UnknownToDelegate() {
        // The delegate does not know KG4* at all, but knows W1AW → the correction substitutes USA.
        struct OnlyUsaProbe: DxccLookup {
            func resolve(_ callsign: String?) -> DxccEntity? {
                DxccResolver.normalize(callsign ?? "") == "W1AW" ? DxccSpecialCasesTests.usa : nil
            }
            func entities() -> [DxccEntity] { [DxccSpecialCasesTests.usa] }
        }
        let r = DxccSpecialCases(OnlyUsaProbe())
        #expect(r.resolve("KG4IGC")?.entityCode == 291, "base is nothing, USA is substituted")
        #expect(r.resolve("KG4AB") == nil, "a two-character suffix does not trigger the correction")
    }

    @Test func entitiesIsPureDelegation() {
        #expect(resolver.entities().count == 3)
        #expect(resolver.entities().map(\.entityCode) == [291, 105, 503])
    }

    @Test func decoratorCanBeComposedOverCtyDxccResolver() {
        // Composability: the same decorator must wrap CtyDxccResolver too.
        let source = """
            United States: 05: 08: NA: 37.53: 91.67: 5.0: K:
                K,N,W,AA;
            Guantanamo Bay: 08: 11: NA: 20.00: 75.00: 5.0: KG4:
                KG4;
            """
        let cty = CtyDxccResolver.parse(source)
        let wrapped = DxccSpecialCases(cty)
        #expect(cty.resolve("KG4IGC")?.name == "Guantanamo Bay", "without the decorator it is Guantanamo")
        #expect(wrapped.resolve("KG4IGC")?.name == "United States")
        #expect(wrapped.resolve("KG4AB")?.name == "Guantanamo Bay")
        #expect(wrapped.entities().count == 2)
    }
}
