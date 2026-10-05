import Testing
@testable import MCLCore

/// `CallbookPolicy` against `ui/AppState.kt` of v1.1.1 (`lookupCallbook` `:311-334`, `sourceAllows` `:415-425`,
/// `fetchMerged` `:427-443`, `prefetchGridsForSpots` `:449-470`); the key and the length gate measured on the JVM
/// (`spots-core-probe.tsv`, area `callKey`).
@Suite struct CallbookPolicyTests {

    static func record(_ grid: String, _ name: String, _ cq: String, _ itu: String) -> HamQthRecord {
        HamQthRecord(grid: grid, name: name, cqZone: cq, ituZone: itu)
    }

    static func spot(_ call: String, comment: String = "") -> DxSpot {
        DxSpot(spotter: "S", freqHz: 14_074_000, dxCall: call, comment: comment)
    }

    @Test func keyAndLengthGateMatchTheJvm() throws {
        let rows = SpotsCoreProbeTable.area("callKey")
        #expect(rows.count == 13)
        for row in rows {
            let input = String(row.input.dropFirst().dropLast())
            let key = CallbookPolicy.key(input)
            let allowed = CallbookPolicy.lookupKey(call: input, hamQthConfigured: true, qrzConfigured: false) != nil
            #expect("[" + key + "] " + String(key.utf16.count) + " " + String(allowed) == row.result, "\(row.input)")
        }
    }

    /// The gate looks only at `configured()` — `isEnabled` plays no part there.
    @Test func lookupGateIgnoresEnabled() {
        #expect(CallbookPolicy.lookupKey(call: "ok1abc", hamQthConfigured: false, qrzConfigured: false) == nil)
        #expect(CallbookPolicy.lookupKey(call: "ok1abc", hamQthConfigured: false, qrzConfigured: true) == "OK1ABC")
        #expect(CallbookPolicy.lookupKey(call: "ok", hamQthConfigured: true, qrzConfigured: true) == nil)
        // Configured but disabled: the gate passes, then no source is asked (the lane caches EMPTY).
        #expect(CallbookPolicy.lookupKey(call: "ok1abc", hamQthConfigured: true, qrzConfigured: false) == "OK1ABC")
        #expect(CallbookPolicy.lookupSources(hamQthEnabled: false, hamQthConfigured: true, qrzEnabled: true,
                                             qrzConfigured: false).isEmpty)
        // Enabled without credentials is never asked.
        #expect(CallbookPolicy.lookupSources(hamQthEnabled: true, hamQthConfigured: false, qrzEnabled: true,
                                             qrzConfigured: true) == [.qrz])
        #expect(CallbookPolicy.lookupSources(hamQthEnabled: true, hamQthConfigured: true, qrzEnabled: true,
                                             qrzConfigured: true) == [.hamQth, .qrz])
    }

    /// `sourceAllows`: enabled and configured; empty modes or an unknown category allow; uppercase on both sides.
    @Test func sourceAllows() {
        #expect(!CallbookPolicy.sourceAllows(enabled: false, configured: true, modes: [], category: nil))
        #expect(!CallbookPolicy.sourceAllows(enabled: true, configured: false, modes: [], category: nil))
        #expect(CallbookPolicy.sourceAllows(enabled: true, configured: true, modes: [], category: "CW"))
        #expect(CallbookPolicy.sourceAllows(enabled: true, configured: true, modes: ["DIGI"], category: nil))
        #expect(CallbookPolicy.sourceAllows(enabled: true, configured: true, modes: ["digi"], category: "Digi"))
        #expect(!CallbookPolicy.sourceAllows(enabled: true, configured: true, modes: ["DIGI"], category: "CW"))
        #expect(!CallbookPolicy.sourceAllows(enabled: true, configured: true, modes: [" DIGI"], category: "DIGI"))
    }

    /// The typed-call merge (`fields == nil`): first non-blank per field, HamQTH before QRZ.
    @Test func mergeTakesTheFirstNonBlankValue() {
        let hamQth = Self.record("JO70", "", " ", "28")
        let qrz = Self.record("JN89", "Jan", "15", "")
        #expect(CallbookPolicy.merge([(hamQth, nil), (qrz, nil)]) == Self.record("JO70", "Jan", "15", "28"))
        // A blank value is kept only when no later source has a better one.
        #expect(CallbookPolicy.merge([(Self.record(" ", "", "", ""), nil), (.empty, nil)])
            == Self.record("", "", "", ""))
        #expect(CallbookPolicy.merge([(Self.record(" ", "", "", ""), nil)]) == Self.record(" ", "", "", ""))
        #expect(CallbookPolicy.merge([]) == .empty)
    }

    /// `fetchMerged`: each source contributes only its `fetchFields` (matched exactly).
    @Test func mergeFiltersByFetchFields() {
        let hamQth = Self.record("JO70", "Petr", "15", "28")
        let qrz = Self.record("JN89", "Jan", "14", "27")
        #expect(CallbookPolicy.merge([(hamQth, ["grid"]), (qrz, ["name", "cqZone", "ituZone", "grid"])])
            == Self.record("JO70", "Jan", "14", "27"))
        #expect(CallbookPolicy.merge([(hamQth, ["Grid", "cqzone"]), (qrz, [])]) == .empty)
    }

    /// `prefetchGridsForSpots`: needs a lookup contest and a configured client; non-empty key, not cached, no offline
    /// grid, allowed by a source; one spot per key in buffer order.
    @Test func prefetchSelection() {
        #expect(!CallbookPolicy.prefetchAllowed(needsLookup: false, hamQthConfigured: true, qrzConfigured: true))
        #expect(!CallbookPolicy.prefetchAllowed(needsLookup: true, hamQthConfigured: false, qrzConfigured: false))
        #expect(CallbookPolicy.prefetchAllowed(needsLookup: true, hamQthConfigured: false, qrzConfigured: true))
        let spots = [Self.spot("ok1abc", comment: "first"), Self.spot(" "), Self.spot("DL1CACHED"),
                     Self.spot("G4GRID"), Self.spot("W1CW", comment: "cw"), Self.spot("OK1ABC", comment: "second"),
                     Self.spot("SP9X")]
        let selected = CallbookPolicy.prefetchSelection(
            spots: spots, cached: { $0 == "DL1CACHED" }, hasOfflineGrid: { $0 == "G4GRID" },
            allows: { $0.comment != "cw" })
        #expect(selected == [spots[0], spots[6]])
    }

    /// `hamQthRecordFor` and the cache hit: a cached `EMPTY` is nothing.
    @Test func usableRecord() {
        #expect(CallbookPolicy.usable(nil) == nil)
        #expect(CallbookPolicy.usable(.empty) == nil)
        #expect(CallbookPolicy.usable(Self.record(" ", "\t", "", "")) == nil)
        #expect(CallbookPolicy.usable(Self.record("JO70", "", "", "")) == Self.record("JO70", "", "", ""))
    }
}
