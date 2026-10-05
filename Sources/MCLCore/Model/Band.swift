import Foundation

/// Amateur band with a frequency range. `adif` corresponds to the ADIF field BAND.
/// Ranges are in Hz and are used to derive the band from the current VFO frequency.
public enum Band: String, CaseIterable, Codable, Sendable {
    case m160 = "160m"
    case m80 = "80m"
    case m60 = "60m"
    case m40 = "40m"
    case m30 = "30m"
    case m20 = "20m"
    case m17 = "17m"
    case m15 = "15m"
    case m12 = "12m"
    case m10 = "10m"
    case m6 = "6m"
    case m2 = "2m"
    case cm70 = "70cm"
    // Microwave bands: a deliberate post-port addition (ranges per ADIF 3.1.x). Java v1.1.1 ends at 70 cm.
    case cm23 = "23cm"
    case cm13 = "13cm"
    case cm9 = "9cm"
    case cm6 = "6cm"
    case cm3 = "3cm"

    public var adif: String { rawValue }

    /// The 13 bands of Java v1.1.1 (160 m – 70 cm), in the Java ordinal order.
    public static let javaV111Cases: [Band] = [
        .m160, .m80, .m60, .m40, .m30, .m20, .m17, .m15, .m12, .m10, .m6, .m2, .cm70,
    ]

    /// `true` for the post-port microwave bands (23 cm and up), which Java v1.1.1 does not know.
    public var isMicrowave: Bool {
        switch self {
        case .cm23, .cm13, .cm9, .cm6, .cm3: true
        default: false
        }
    }

    /// Test-only seam: while `true` (task-local), `from(frequencyHz:)` and `from(adif:)` search only
    /// `javaV111Cases`, i.e. behave exactly like Java v1.1.1. It exists so that the Java parity gates keep
    /// replaying their frozen reference fixtures (which know nothing above 70 cm) without regenerating them.
    /// The product never sets it; only the test targets do (`Band.$javaV111Table.withValue(true) { ... }`).
    /// A task-local does not cross `Thread`/`DispatchQueue` boundaries: capture the value and rebind it there.
    @TaskLocal public static var javaV111Table: Bool = false

    private static var lookupCases: [Band] { javaV111Table ? javaV111Cases : allCases }

    public var lowHz: Int {
        switch self {
        case .m160: 1_800_000
        case .m80: 3_500_000
        case .m60: 5_330_000
        case .m40: 7_000_000
        case .m30: 10_100_000
        case .m20: 14_000_000
        case .m17: 18_068_000
        case .m15: 21_000_000
        case .m12: 24_890_000
        case .m10: 28_000_000
        case .m6: 50_000_000
        case .m2: 144_000_000
        case .cm70: 430_000_000
        case .cm23: 1_240_000_000
        case .cm13: 2_300_000_000
        case .cm9: 3_300_000_000
        case .cm6: 5_650_000_000
        case .cm3: 10_000_000_000
        }
    }

    public var highHz: Int {
        switch self {
        case .m160: 2_000_000
        case .m80: 4_000_000
        case .m60: 5_410_000
        case .m40: 7_300_000
        case .m30: 10_150_000
        case .m20: 14_350_000
        case .m17: 18_168_000
        case .m15: 21_450_000
        case .m12: 24_990_000
        case .m10: 29_700_000
        case .m6: 54_000_000
        case .m2: 148_000_000
        case .cm70: 440_000_000
        case .cm23: 1_300_000_000
        case .cm13: 2_450_000_000
        case .cm9: 3_500_000_000
        case .cm6: 5_925_000_000
        case .cm3: 10_500_000_000
        }
    }

    /// Derives the band from a frequency in Hz. The order matches the order of `allCases`, as in Java.
    public static func from(frequencyHz: Int) -> Band? {
        lookupCases.first { frequencyHz >= $0.lowHz && frequencyHz <= $0.highHz }
    }

    /// Derives the band from the value of the ADIF field `BAND`, exactly like Java
    /// `Band.fromAdif`: `value.trim().toLowerCase()`.
    ///
    /// The trim is **Java `trim()`** (`JavaText.trim`, characters ≤ U+0020), not Swift
    /// `.whitespacesAndNewlines`. The no-break space U+00A0 (and U+2007, U+202F,
    /// U+3000, DEL) stays in the value, so the band is **not recognised** and
    /// `nil` results — and that matters only in the dupe check: the Java dupe key is
    /// `call.trim().toUpperCase() + '|' + band.name()`, so the band is part of it
    /// and `DupeChecker.add` **does not index** a QSO with `band == nil` at all
    /// (`LogMerger.same` likewise compares the band). A Swift trim would drop U+00A0,
    /// recognise the band and index the QSO — thus producing a false dupe.
    ///
    /// `toLowerCase()` in Java is without a `Locale`; under `en` it is identical
    /// to `Locale.ROOT` (measured for all 1 112 064 code points, 0 differences),
    /// so Swift `lowercased()` is the right counterpart.
    public static func from(adif value: String?) -> Band? {
        guard let value else { return nil }
        let v = JavaText.trim(value).lowercased()
        return lookupCases.first { $0.adif == v }
    }
}
