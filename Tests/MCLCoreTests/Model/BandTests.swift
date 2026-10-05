import Foundation
import Testing
@testable import MCLCore

@Suite struct BandTests {
    @Test func resolvesTwentyMetersFromFrequency() {
        #expect(Band.from(frequencyHz: 14_074_000) == .m20)
    }

    @Test func resolvesFortyMetersFromFrequency() {
        #expect(Band.from(frequencyHz: 7_120_000) == .m40)
    }

    @Test func returnsNilForFrequencyOutsideHamBands() {
        #expect(Band.from(frequencyHz: 100_000) == nil)
    }

    @Test func parsesBandFromAdif() {
        #expect(Band.from(adif: "15m") == .m15)
    }

    @Test func cwDefaultRstIs599AndSsbIs59() {
        #expect(Mode.cw.defaultRst == "599")
        #expect(Mode.ssb.defaultRst == "59")
    }
}

// MARK: - `from(adif:)`: Java `trim()`, not Swift `.whitespacesAndNewlines`

/// `Band.fromAdif` and `Mode.fromAdif` in Java normalise the input via
/// `value.trim().toLowerCase()` resp. `.toUpperCase()`. Java `trim()` drops
/// characters ≤ U+0020, but **keeps** the non-breaking space U+00A0 (and U+2007, U+202F, U+3000
/// or DEL) — and then the band/mode is not recognised.
///
/// Why this is not just cosmetic: the Java dupe key is
/// `call.trim().toUpperCase() + '|' + band.name()`, so **the band is part of the
/// key**, and `LogMerger.same` compares it too. When `getBand()` comes out `null`,
/// `DupeChecker.add` **does not index** the QSO at all. A Swift trim would drop U+00A0,
/// recognise the band, index the QSO — and produce a **false duplicate**.
///
/// Measured on Java v1.1.1 (JDK 21, `-Duser.language=en`):
/// | `BAND` | `Band.fromAdif` | `MODE` | `Mode.fromAdif` |
/// |---|---|---|---|
/// | `20m` / `20M` / ` 20m ` | `M20` | `CW` / `cw` / ` CW ` | `CW` |
/// | `\t20m` / `\u{000B}20m` | `M20` | `\tCW` | `CW` |
/// | `\u{0001}20m` / `20m\u{0001}` | `M20` | `\u{0001}CW` | `CW` |
/// | – | – | `\u{0001}usb` | `SSB` |
/// | `\u{00A0}20m` | **nil** | `\u{00A0}CW` | **nil** |
/// | `20m\u{00A0}` | **nil** | `CW\u{00A0}` | **nil** |
/// | `20\u{00A0}m` | **nil** | – | – |
/// | `\u{2007}20m` | **nil** | `\u{2007}CW` | **nil** |
/// | `\u{202F}20m` | **nil** | – | – |
/// | `\u{3000}20m` | **nil** | `\u{3000}CW` | **nil** |
/// | `\u{007F}20m` | **nil** | `\u{007F}CW` | **nil** |
/// | `` / `   ` / `\u{00A0}` / `nil` | nil | `` / `   ` / `nil` | nil |
///
/// `toLowerCase()` and `toUpperCase()` are without `Locale` in Java; under `en` they are
/// identical to `Locale.ROOT` (measured for all 1,112,064 code points, 0 differences),
/// so Swift `lowercased()`/`uppercased()` stay.
@Suite struct BandModeAdifNormalizationTests {

    @Test func bandIsTrimmedWithJavaTrim() {
        // Java `trim()` drops → the band is recognised.
        #expect(Band.from(adif: "20m") == .m20)
        #expect(Band.from(adif: "20M") == .m20)
        #expect(Band.from(adif: " 20m ") == .m20)
        #expect(Band.from(adif: "\t20m") == .m20)
        #expect(Band.from(adif: "\u{000B}20m") == .m20)
        #expect(Band.from(adif: "\u{0001}20m") == .m20)
        #expect(Band.from(adif: "20m\u{0001}") == .m20)
        // Java `trim()` does not drop → the band is **not recognised**.
        #expect(Band.from(adif: "\u{00A0}20m") == nil)
        #expect(Band.from(adif: "20m\u{00A0}") == nil)
        #expect(Band.from(adif: "20\u{00A0}m") == nil)
        #expect(Band.from(adif: "\u{2007}20m") == nil)
        #expect(Band.from(adif: "\u{202F}20m") == nil)
        #expect(Band.from(adif: "\u{3000}20m") == nil)
        #expect(Band.from(adif: "\u{007F}20m") == nil)
        #expect(Band.from(adif: "") == nil)
        #expect(Band.from(adif: "   ") == nil)
        #expect(Band.from(adif: "\u{00A0}") == nil)
        #expect(Band.from(adif: nil) == nil)
    }

    @Test func modeIsTrimmedWithJavaTrim() {
        #expect(Mode.from(adif: "CW") == .cw)
        #expect(Mode.from(adif: "cw") == .cw)
        #expect(Mode.from(adif: " CW ") == .cw)
        #expect(Mode.from(adif: "\tCW") == .cw)
        #expect(Mode.from(adif: "\u{0001}CW") == .cw)
        // The fallback mapping USB/LSB → SSB applies even after trimming a control character.
        #expect(Mode.from(adif: "usb") == .ssb)
        #expect(Mode.from(adif: "\u{0001}usb") == .ssb)
        // Non-breaking spaces, U+3000 and DEL are kept by Java `trim()` → the mode is not recognised.
        #expect(Mode.from(adif: "\u{00A0}CW") == nil)
        #expect(Mode.from(adif: "CW\u{00A0}") == nil)
        #expect(Mode.from(adif: "\u{2007}CW") == nil)
        #expect(Mode.from(adif: "\u{3000}CW") == nil)
        #expect(Mode.from(adif: "\u{007F}CW") == nil)
        #expect(Mode.from(adif: "\u{00A0}usb") == nil)
        #expect(Mode.from(adif: "") == nil)
        #expect(Mode.from(adif: "   ") == nil)
        #expect(Mode.from(adif: nil) == nil)
    }

    /// The consequence down to the dupe key. A QSO whose band came from an ADIF-shaped string
    /// with a non-breaking space has `band == nil` in Java, so
    /// `DupeChecker.add` **does not index it at all** and `isDupe` is `false`.
    /// Measured on Java: `BAND=20m` → indexed, dupe true;
    /// `BAND=\u{00A0}20m` → not indexed, dupe **false**;
    /// `BAND=\u{0001}20m` → indexed, dupe true;
    /// `BAND=\u{3000}20m` → not indexed, dupe **false**.
    @Test func bandFromAdifDecidesDupeIndexing() {
        func indexedThenDupe(band: String) -> Bool {
            var q = Qso()
            q.call = "OK1XOE"
            q.band = Band.from(adif: band)
            var checker = DupeChecker(existing: [])
            checker.add(q)
            return checker.isDupe(call: "OK1XOE", band: .m20)
        }
        #expect(indexedThenDupe(band: "20m"))
        #expect(indexedThenDupe(band: "\u{0001}20m"))
        // A false duplicate: a Swift trim would drop U+00A0, recognise the band
        // and index the QSO — Java does not index it.
        #expect(!indexedThenDupe(band: "\u{00A0}20m"))
        #expect(!indexedThenDupe(band: "\u{3000}20m"))
    }

    /// The same for merging: the band is part of the comparison in `LogMerger.same`.
    /// Measured on Java: `same(20m, \u{00A0}20m)` = false, `same(20m, \u{0001}20m)` = true.
    @Test func bandFromAdifDecidesMerging() {
        func sameAsM20(band: String) -> Bool {
            var a = Qso()
            a.call = "OK1XOE"
            a.band = .m20
            a.mode = .cw
            a.timestampUtc = Date(timeIntervalSince1970: 1_767_225_600)
            var b = a
            b.band = Band.from(adif: band)
            return LogMerger.same(a, b)
        }
        #expect(sameAsM20(band: "20m"))
        #expect(sameAsM20(band: "\u{0001}20m"))
        #expect(!sameAsM20(band: "\u{00A0}20m"))
    }
}

// MARK: - Microwave bands (post-port, outside Java v1.1.1 parity)

@Suite struct MicrowaveBandTests {

    private static let ranges: [(band: Band, low: Int, high: Int)] = [
        (.cm23, 1_240_000_000, 1_300_000_000),
        (.cm13, 2_300_000_000, 2_450_000_000),
        (.cm9, 3_300_000_000, 3_500_000_000),
        (.cm6, 5_650_000_000, 5_925_000_000),
        (.cm3, 10_000_000_000, 10_500_000_000),
    ]

    @Test func rangesFollowAdif() {
        for r in Self.ranges {
            #expect(r.band.lowHz == r.low && r.band.highHz == r.high, "\(r.band)")
            #expect(Band.from(frequencyHz: r.low) == r.band)
            #expect(Band.from(frequencyHz: r.high) == r.band)
            #expect(Band.from(frequencyHz: r.low - 1) == nil)
            #expect(Band.from(frequencyHz: r.high + 1) == nil)
            #expect(r.band.isMicrowave)
        }
    }

    @Test func javaBandsAndTheirOrdinalsAreUnchanged() {
        #expect(Array(Band.allCases.prefix(13)) == Band.javaV111Cases)
        #expect(Band.javaV111Cases.map(\.rawValue) == ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m",
                                                      "10m", "6m", "2m", "70cm"])
        #expect(Band.javaV111Cases.allSatisfy { !$0.isMicrowave })
        #expect(Band.allCases.suffix(5).map(\.rawValue) == ["23cm", "13cm", "9cm", "6cm", "3cm"])
        // 70 cm keeps its Java range (ADIF has 420-450 MHz, Java 430-440 MHz).
        #expect(Band.cm70.lowHz == 430_000_000 && Band.cm70.highHz == 440_000_000)
        #expect(Band.from(frequencyHz: 440_000_001) == nil)
    }

    @Test func gapsAndSatelliteFrequencies() {
        #expect(Band.from(frequencyHz: 1_427_750_000) == nil)   // between 23 and 13 cm, not amateur
        #expect(Band.from(frequencyHz: 2_400_250_000) == .cm13) // QO-100 uplink
        #expect(Band.from(frequencyHz: 10_489_750_000) == .cm3) // QO-100 downlink
        #expect(Band.from(frequencyHz: 739_750_000) == nil)     // LNB intermediate frequency
    }

    @Test func adifNameIsParsed() {
        #expect(Band.from(adif: "23CM ") == .cm23)
        #expect(Band.from(adif: "13cm") == .cm13)
        #expect(Band.from(adif: "3cm") == .cm3)
    }

    @Test func theGateSwitchRestoresTheJavaTable() {
        #expect(Band.javaV111Table == false)
        Band.$javaV111Table.withValue(true) {
            #expect(Band.from(frequencyHz: 1_296_200_000) == nil)
            #expect(Band.from(adif: "23cm") == nil)
            #expect(Band.from(frequencyHz: 144_300_000) == .m2)
            #expect(Band.from(adif: "70CM") == .cm70)
        }
        #expect(Band.from(frequencyHz: 1_296_200_000) == .cm23)
    }

    @Test func qsoDerivesTheMicrowaveBand() {
        var q = Qso()
        q.freqHz = 10_368_100_000
        #expect(q.band == .cm3)
    }

    @Test func wireCarriesTheJavaStyleNames() {
        for r in Self.ranges {
            var q = Qso()
            q.call = "OK1ABC"
            q.freqHz = r.low
            let wire = WireMapper.toWire(q)
            #expect(wire.band == r.band.javaName)
            let state = QsoState(uuid: "u", stationId: "s", version: 1, updatedAtUtc: JavaInstant.now(),
                                 deleted: false, qso: wire)
            #expect(WireMapper.toQso(state).band == r.band)
        }
        #expect(Band.cm3.javaName == "CM3")
    }
}
