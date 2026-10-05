import Testing
@testable import MCLCore

/// Does a QSO in the given mode belong to the contest? The first four tests are a port of the Java
/// `ModeEligibilityTest`; the table below them is measured on Java
/// (maintainer-only probe, JDK 21.0.2).
@Suite struct ModeEligibilityTests {

    // MARK: - port of the Java ModeEligibilityTest (4)

    @Test func otherFamilyDoesNotCount() {
        #expect(!ModeEligibility.counts(["CW"], "FT8"))
        #expect(!ModeEligibility.counts(["CW"], "SSB"))
        #expect(!ModeEligibility.counts(["SSB"], "CW"))
        #expect(!ModeEligibility.counts(["RTTY"], "CW"))
    }

    @Test func sameFamilyCountsEvenWithADifferentName() {
        // VHF contests list [CW, SSB], but FM is common on VHF — it must not be dropped.
        #expect(ModeEligibility.counts(["CW", "SSB"], "FM"))
        #expect(ModeEligibility.counts(["SSB"], "AM"))
        // ww-digi lists [DIGITAL], FT8 and FT4 come from WSJT-X.
        #expect(ModeEligibility.counts(["DIGITAL"], "FT8"))
        #expect(ModeEligibility.counts(["DIGITAL"], "FT4"))
        // cq-wpx-rtty lists [RTTY], generic DIGITAL and PSK belong there too.
        #expect(ModeEligibility.counts(["RTTY"], "DIGITAL"))
        #expect(ModeEligibility.counts(["RTTY"], "PSK"))
    }

    @Test func exactNameCounts() {
        #expect(ModeEligibility.counts(["CW"], "CW"))
        #expect(ModeEligibility.counts(["CW", "SSB", "RTTY", "DIGITAL"], "FT8"))
        #expect(ModeEligibility.counts(["SSB"], "USB")) // ADIF abbreviation
    }

    @Test func withoutUsableInputNothingIsExcluded() {
        #expect(ModeEligibility.counts(nil, "FT8"))
        #expect(ModeEligibility.counts([], "FT8"))
        #expect(ModeEligibility.counts(["CW"], nil))
        #expect(ModeEligibility.counts(["CW"], ""))
        #expect(ModeEligibility.counts(["CW"], "NĚCO NOVÉHO"))
        #expect(ModeEligibility.counts(["PŘEKLEP"], "FT8")) // a faulty definition does not restrict
    }

    // MARK: - measured on Java

    struct Row: Sendable, CustomStringConvertible {
        let modes: [String?]?
        let qso: String?
        let java: Bool
        var description: String { "\(String(describing: modes)) / \(String(describing: qso))" }
    }

    /// A `null` element of the definition is skipped (`Mode.fromAdif(null)` → `null`) — Java semantics,
    /// no crash; `[~]` is thus "nothing recognised" → does not restrict. The mode is read with Java `trim()`
    /// (NBSP is not stripped → mode unknown → does not exclude) and `toUpperCase()` (`ſ` → `S`).
    static let measured: [Row] = [
        Row(modes: [nil, "CW"], qso: "FT8", java: false),
        Row(modes: [nil], qso: "FT8", java: true),
        Row(modes: ["cw"], qso: " cw ", java: true),
        Row(modes: ["CW"], qso: "usb", java: false),
        Row(modes: ["SSB"], qso: "lsb", java: true),
        Row(modes: ["SSB"], qso: "Usb", java: true),
        Row(modes: [" SSB\t"], qso: "FM", java: true),
        Row(modes: ["\u{00A0}CW"], qso: "SSB", java: true),
        Row(modes: ["CW"], qso: "\u{00A0}SSB", java: true),
        Row(modes: ["PHONE"], qso: "SSB", java: true),
        Row(modes: ["CW", "PHONE"], qso: "SSB", java: false),
        Row(modes: ["DIGITAL"], qso: "CW", java: false),
        Row(modes: ["FT8"], qso: "RTTY", java: true),
        Row(modes: ["AM"], qso: "FM", java: true),
        Row(modes: ["JT65"], qso: "PSK", java: true),
        Row(modes: [""], qso: "CW", java: true),
        Row(modes: ["", "SSB"], qso: "CW", java: false),
        Row(modes: nil, qso: nil, java: true),
        Row(modes: [], qso: nil, java: true),
        Row(modes: ["CW"], qso: "   ", java: true),
        Row(modes: ["\u{017F}SB"], qso: "CW", java: false),
        Row(modes: ["CW"], qso: "cW", java: true),
    ]

    @Test(arguments: measured)
    func matchesJava(_ row: Row) {
        #expect(ModeEligibility.counts(row.modes, row.qso) == row.java)
    }
}
