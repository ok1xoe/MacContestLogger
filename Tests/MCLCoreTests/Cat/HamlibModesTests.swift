import os
import Testing
@testable import MCLCore

/// Port of `cat/HamlibModesTest` + `HM.*` measurements (maintainer-only probe, `…/cat/`).
///
/// Java holds the setting in a global `static volatile` (`HamlibModes.configure`); Swift carries it as the value
/// `HamlibModeMapping` — the default value corresponds to the Java default `DIGITAL`/`false`.
@Suite struct HamlibModesTests {

    private let modes = HamlibModeMapping.default

    @Test func mapsHamlibModesToOurModes() {
        #expect(modes.toMode("USB") == .ssb)
        #expect(modes.toMode("LSB") == .ssb)
        #expect(modes.toMode("CWR") == .cw)
        #expect(modes.toMode("PKTUSB") == .digital)
        #expect(modes.toMode("FM") == .fm)
        #expect(modes.toMode("UNKNOWN") == nil)
    }

    @Test func choosesSidebandByFrequency() {
        #expect(modes.toHamlib(.ssb, freqHz: 7_120_000) == "LSB")
        #expect(modes.toHamlib(.ssb, freqHz: 14_200_000) == "USB")
        #expect(modes.toHamlib(.cw, freqHz: 7_010_000) == "CW")
        #expect(modes.toHamlib(.ft8, freqHz: 14_074_000) == "PKTUSB")
    }

    // MARK: - Measurements (JDK 21.0.2, en_US)

    /// The probe configuration in the order `afsk` × `dataMode` (`null` and non-data `SSB` → `DIGITAL`).
    private static let configs: [(Mode?, Bool)] = [
        (.digital, false), (.ft8, false), (.ssb, false), (nil, false),
        (.digital, true), (.ft8, true), (.ssb, true), (nil, true),
    ]

    private static let toModeInputs: [String] = [
        "USB", "usb", " LSB ", "CW", "CWR", "RTTY", "RTTYR", "AM", "SAM", "SAL", "SAH", "AMS", "DSB", "FM",
        "WFM", "PKTFM", "PKTUSB", "PKTLSB", "PKTAM", "FAX", "ECSSUSB", "C4FM", "", "None", "cw\u{0130}", "rtty",
    ]

    /// `HM.toMode`: a row for `DIGITAL`/`SSB`/`null`; with `FT8` only `PKTUSB`/`PKTLSB` change to `FT8`.
    private static let toModeDigital = "SSB,SSB,SSB,CW,CW,RTTY,RTTY,AM,AM,AM,AM,AM,SSB,FM,FM,FM,DIGITAL,DIGITAL,"
        + "null,null,null,null,null,null,null,RTTY"
    private static let toModeFt8 = "SSB,SSB,SSB,CW,CW,RTTY,RTTY,AM,AM,AM,AM,AM,SSB,FM,FM,FM,FT8,FT8,"
        + "null,null,null,null,null,null,null,RTTY"

    @Test func measuredToMode() {
        for (dataMode, afsk) in Self.configs {
            let mapping = HamlibModeMapping(dataMode: dataMode, rttyAfsk: afsk)
            let actual: String = Self.toModeInputs.map { mapping.toMode($0)?.rawValue ?? "null" }.joined(separator: ",")
            let expected = dataMode == .ft8 ? Self.toModeFt8 : Self.toModeDigital
            #expect(actual == expected, "\(String(describing: dataMode))/\(afsk)")
        }
    }

    /// `HM.toHamlib`: modes in the order `Mode.values()` × frequency `{0, 9 999 999, 10 000 000, −1}`, at the end
    /// `toHamlib(null, 0)`. `dataMode` does not matter, `afsk` changes only RTTY to `PKTLSB`.
    @Test func measuredToHamlib() {
        let frequencies: [Int64] = [0, 9_999_999, 10_000_000, -1]
        let fsk = "CW CW CW CW LSB LSB USB LSB FM FM FM FM AM AM AM AM RTTY RTTY RTTY RTTY "
            + String(repeating: "PKTUSB ", count: 20) + "USB"
        let afsk = "CW CW CW CW LSB LSB USB LSB FM FM FM FM AM AM AM AM PKTLSB PKTLSB PKTLSB PKTLSB "
            + String(repeating: "PKTUSB ", count: 20) + "USB"
        for (dataMode, rttyAfsk) in Self.configs {
            let mapping = HamlibModeMapping(dataMode: dataMode, rttyAfsk: rttyAfsk)
            var results: [String] = []
            for mode in Mode.allCases {
                for freq in frequencies {
                    results.append(mapping.toHamlib(mode, freqHz: freq))
                }
            }
            results.append(mapping.toHamlib(nil, freqHz: 0))
            #expect(results.joined(separator: " ") == (rttyAfsk ? afsk : fsk))
        }
    }

    /// `HM.extra` (maintainer-only probe): `trim()` takes only characters ≤ U+0020 (NBSP not),
    /// `toUpperCase` converts a long `ſ` to `S`, a dotless `ı` to `I`, and leaves a fullwidth `Ｕ` alone.
    @Test func measuredToModeCaseAndTrim() {
        let cases: [(String?, Mode?)] = [
            ("\u{017F}am", .am), ("d\u{017F}b", .ssb), ("\u{00A0}USB", nil), ("USB\u{000B}", .ssb),
            ("\u{001C}CW\u{001F}", .cw), ("cw", .cw), ("pktu\u{017F}b", .digital), ("r\u{0131}tty", nil),
            ("fm\u{200B}", nil), ("\u{FF35}SB", nil), (nil, nil),
        ]
        for (input, expected) in cases {
            #expect(modes.toMode(input) == expected, "\(ProbeText.esc(input))")
        }
    }

    /// The provider is read on every call — a change in Settings applies immediately even to a running connection
    /// (Java `static volatile`).
    @Test func providerIsReadOnEveryCall() {
        let box = MappingBox(.default)
        let provider: HamlibModeProvider = { box.value }
        #expect(provider().toMode("PKTUSB") == .digital)
        box.value = HamlibModeMapping(dataMode: .ft8, rttyAfsk: true)
        #expect(provider().toMode("PKTUSB") == .ft8)
        #expect(provider().toHamlib(.rtty, freqHz: 14_080_000) == "PKTLSB")
    }
}

/// A mutable value behind a lock for the provider test.
private final class MappingBox: Sendable {
    private let stored: OSAllocatedUnfairLock<HamlibModeMapping>

    init(_ value: HamlibModeMapping) {
        stored = OSAllocatedUnfairLock(initialState: value)
    }

    var value: HamlibModeMapping {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
