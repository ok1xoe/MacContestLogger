import Foundation
import Testing
@testable import MCLCore

/// Tests of `DxccFiller` — a port of the Java `DxccFillerTest` (11 tests) including its
/// fake resolver and Czech names, plus two tests on the places where the Java
/// `null` and the Swift empty `String` in the `Qso` port meet.
@Suite struct DxccFillerTests {

    private static let ok = DxccEntity(
        entityCode: 503, name: "Czech Republic", countryCode: "OK", continents: ["EU"],
        cq: [15], itu: [28], lat: 50.0, lon: 15.0)
    private static let usa = DxccEntity(
        entityCode: 291, name: "United States", countryCode: "K", continents: ["NA"],
        cq: [5], itu: [8], lat: 40.0, lon: -75.0)

    /// Fake after the Java anonymous `DxccLookup`: OK* → Czechia, W* → USA, otherwise nothing.
    private struct Lookup: DxccLookup {
        func resolve(_ callsign: String?) -> DxccEntity? {
            guard let callsign else { return nil }
            if callsign.hasPrefix("OK") { return DxccFillerTests.ok }
            if callsign.hasPrefix("W") { return DxccFillerTests.usa }
            return nil // unknown callsign
        }

        func entities() -> [DxccEntity] {
            [DxccFillerTests.ok, DxccFillerTests.usa]
        }
    }

    private let lookup = Lookup()

    private func qso(_ call: String) -> Qso {
        var q = Qso()
        q.call = call
        return q
    }

    // MARK: - Port of the Java DxccFillerTest

    @Test func fillsCountryFromCallsign() {
        var q = qso("OK1DXX")
        #expect(DxccFiller.fill(&q, lookup))
        #expect(q.dxccEntity == 503)
        #expect(q.dxccName == "Czech Republic")
        #expect(q.continent == "EU")
    }

    @Test func importedValuesAreNotOverwritten() {
        // A foreign log may have the country determined more precisely than the prefix guesses.
        var q = qso("OK1DXX")
        q.dxccEntity = 291
        q.dxccName = "United States"
        q.continent = "NA"
        #expect(!DxccFiller.fill(&q, lookup))
        #expect(q.dxccEntity == 291)
        #expect(q.dxccName == "United States")
    }

    @Test func fillsOnlyWhatIsMissing() {
        var q = qso("OK1DXX")
        q.dxccName = "Česko" // a manual name stays
        #expect(DxccFiller.fill(&q, lookup))
        #expect(q.dxccName == "Česko")
        #expect(q.dxccEntity == 503)
        #expect(q.continent == "EU")
    }

    @Test func unknownOrMissingCallsignChangesNothing() {
        var unknown = qso("XYZ9ABC")
        #expect(!DxccFiller.fill(&unknown, lookup))
        #expect(unknown.dxccEntity == nil)

        // Java `qso(null)` cannot be expressed in Swift — Qso.call is non-optional
        // and the setter trims its input, so a "missing callsign" is an empty string.
        var noCall = Qso()
        #expect(!DxccFiller.fill(&noCall, lookup))

        var blank = qso("   ")
        #expect(!DxccFiller.fill(&blank, lookup))
    }

    @Test func nullArgumentsAreSafe() {
        // Java `fill(null, lookup)` and `fillAll(null, lookup)` cannot be passed —
        // an `inout` parameter has no nil. The rest of the Java test applies unchanged.
        var q = qso("OK1DXX")
        #expect(!DxccFiller.fill(&q, nil))
        #expect(q.dxccEntity == nil)
        var list = [qso("OK1DXX")]
        #expect(DxccFiller.fillAll(&list, nil).isEmpty)
        #expect(list[0].dxccEntity == nil, "the log must not change with a nil resolver")
        var empty: [Qso] = []
        #expect(DxccFiller.fillAll(&empty, lookup).isEmpty)
    }

    @Test func refillOverwritesEvenOldWrongCountry() {
        // Exactly the case the action was created for: the stored number was the order
        // of the record in cty.dat, not the DXCC number.
        var q = qso("OK1DXX")
        q.dxccEntity = 213
        q.dxccName = "Czech Republic"
        q.continent = "EU"
        #expect(DxccFiller.refill(&q, lookup))
        #expect(q.dxccEntity == 503)
    }

    @Test func refillLeavesQsoWithoutRecognizedCountryAlone() {
        var q = qso("XYZ9ABC")
        q.dxccEntity = 999
        q.dxccName = "Ruční název"
        #expect(!DxccFiller.refill(&q, lookup))
        #expect(q.dxccEntity == 999)
        #expect(q.dxccName == "Ruční název")
    }

    @Test func refillReportsChangeOnlyWhenSomethingReallyChanged() {
        var q = qso("OK1DXX")
        q.dxccEntity = 503
        q.dxccName = "Czech Republic"
        q.continent = "EU"
        #expect(!DxccFiller.refill(&q, lookup), "nothing to fix = no write to the log")
    }

    @Test func refillKeepsAdifNumberFieldEmptyWhenNoNumber() {
        let withoutNumber = DxccEntity(
            entityCode: 169, name: "Sicily", countryCode: "IT9", continents: ["EU"],
            cq: [15], itu: [28], lat: 37.0, lon: 14.0, primaryPrefix: "IT9", adifDxcc: nil)
        struct Sicily: DxccLookup {
            let entity: DxccEntity
            func resolve(_ callsign: String?) -> DxccEntity? { entity }
            func entities() -> [DxccEntity] { [entity] }
        }
        var q = qso("IT9ABC")
        q.dxccEntity = 169
        #expect(DxccFiller.refill(&q, Sicily(entity: withoutNumber)))
        #expect(q.dxccEntity == nil, "better nothing than a number that is not DXCC")
        #expect(q.dxccName == "Sicily")
    }

    @Test func refillAllReturnsOnlyChanged() {
        var wrong = qso("OK1DXX")
        wrong.dxccEntity = 213
        var correct = qso("W1AW")
        correct.dxccEntity = 291
        correct.dxccName = "United States"
        correct.continent = "NA"

        var list = [wrong, correct]
        let changed = DxccFiller.refillAll(&list, lookup)
        #expect(changed.count == 1)
        #expect(changed[0].call == "OK1DXX")
        #expect(list[0].dxccEntity == 503, "the log is mutated in place as in Java")
        var withNil = [qso("OK1DXX")]
        #expect(DxccFiller.refillAll(&withNil, nil).isEmpty)
        var empty: [Qso] = []
        #expect(DxccFiller.refillAll(&empty, lookup).isEmpty)
    }

    @Test func fillAllReturnsOnlyChangedQsos() {
        let fresh = qso("OK1DXX")
        var alreadyFilled = qso("W1AW")
        alreadyFilled.dxccEntity = 291
        alreadyFilled.dxccName = "United States"
        alreadyFilled.continent = "NA"
        let unknown = qso("XYZ9ABC")

        var list = [fresh, alreadyFilled, unknown]
        let changed = DxccFiller.fillAll(&list, lookup)
        #expect(changed.count == 1)
        #expect(changed[0].call == "OK1DXX")
    }

    // MARK: - Additionally measured behaviours

    @Test func fillDoesNotWriteNumberWhenEntityHasNone() {
        // The name and continent are filled in, the ADIF number stays empty — Java
        // `needsEntity && e.adifDxcc() != null`.
        let withoutNumber = DxccEntity(
            entityCode: 169, name: "Sicily", countryCode: "IT9", continents: ["EU"],
            cq: [15], itu: [28], lat: 37.0, lon: 14.0, primaryPrefix: "IT9", adifDxcc: nil)
        struct Sicily: DxccLookup {
            let entity: DxccEntity
            func resolve(_ callsign: String?) -> DxccEntity? { entity }
            func entities() -> [DxccEntity] { [entity] }
        }
        var q = qso("IT9ABC")
        #expect(DxccFiller.fill(&q, Sicily(entity: withoutNumber)))
        #expect(q.dxccEntity == nil)
        #expect(q.dxccName == "Sicily")
        #expect(q.continent == "EU")
    }

    @Test func fillIsIdempotentAndRefillAfterItReportsNoChange() {
        var q = qso("OK1DXX")
        #expect(DxccFiller.fill(&q, lookup))
        #expect(!DxccFiller.fill(&q, lookup), "the second call has nothing left to fill in")
        #expect(!DxccFiller.refill(&q, lookup), "and the recount finds no difference")
    }

    /// A callsign with a non-breaking space **at the start** must not get a country. Java
    /// `Qso.setCall` uses `trim()`, which does not drop U+00A0, so the
    /// resolver does not resolve it and `fill` writes nothing. Measured on Java v1.1.1 with a fake
    /// resolver and over the real `cty.dat`: `fill[NBSP + OK1DXX] => false`,
    /// `fill[NBSP + KG4IGC] => false`.
    ///
    /// If the callsign were trimmed with Swift's `.whitespacesAndNewlines`, we would write
    /// 503 / Czech Republic / EU where Java writes nothing — and for
    /// `NBSP + KG4IGC` even Guantanamo. Callsigns with U+00A0 come from cluster
    /// spots and web copies routinely, so this is not hypothetical.
    @Test func callsignWithNonBreakingSpaceGetsNoCountry() {
        // A non-breaking space **in front** blocks recognition.
        for call in ["\u{00A0}OK1DXX", "\u{00A0}W1AW"] {
            var q = qso(call)
            #expect(q.call == call, "NBSP must stay in the value: \(call)")
            #expect(!DxccFiller.fill(&q, lookup), "\(call)")
            #expect(q.dxccEntity == nil, "\(call)")
            #expect(q.dxccName.isEmpty, "\(call)")
            #expect(q.continent.isEmpty, "\(call)")
            #expect(!DxccFiller.refill(&q, lookup), "\(call)")
        }
        // **At the end** it does not — the prefix is looked up only at the start of the callsign, so the country is
        // filled in, but the NBSP stays stored (measured on Java and over the real
        // cty.dat: `fill[OK1DXX<NBSP>] => true, Czech Republic`).
        var trailing = qso("OK1DXX\u{00A0}")
        #expect(trailing.call == "OK1DXX\u{00A0}", "trim() does not drop NBSP at the end either")
        #expect(DxccFiller.fill(&trailing, lookup))
        #expect(trailing.dxccEntity == 503)
        // A control character, on the contrary, is trimmed and the country is filled in.
        var control = qso("\u{0001}OK1DXX")
        #expect(control.call == "OK1DXX")
        #expect(DxccFiller.fill(&control, lookup))
        #expect(control.dxccEntity == 503)
    }

    @Test func fillEmptyEntityNamesDoNotOverwrite() {
        // Java `isBlank`: neither an empty name nor an empty continent is written,
        // and the field thus stays "missing" even after the number is filled in.
        let withoutName = DxccEntity(
            entityCode: 1, name: "  ", countryCode: "XX", continents: [""],
            cq: [1], itu: [1], lat: .nan, lon: .nan)
        struct Fake: DxccLookup {
            let entity: DxccEntity
            func resolve(_ callsign: String?) -> DxccEntity? { entity }
            func entities() -> [DxccEntity] { [entity] }
        }
        var q = qso("XX1AA")
        #expect(DxccFiller.fill(&q, Fake(entity: withoutName)))
        #expect(q.dxccEntity == 1)
        #expect(q.dxccName.isEmpty)
        #expect(q.continent.isEmpty)
    }
}
