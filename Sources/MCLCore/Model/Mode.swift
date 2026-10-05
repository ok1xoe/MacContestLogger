import Foundation

/// Operating mode of a QSO. `adif` corresponds to the ADIF field MODE.
public enum Mode: String, CaseIterable, Codable, Sendable {
    case cw = "CW"
    case ssb = "SSB"
    case fm = "FM"
    case am = "AM"
    case rtty = "RTTY"
    case psk = "PSK"
    case ft8 = "FT8"
    case ft4 = "FT4"
    case jt65 = "JT65"
    case digital = "DIGITAL"

    public var adif: String { rawValue }

    /// Default RST report: 599 for CW and digital, 59 for phone.
    public var defaultRst: String {
        switch self {
        case .ssb, .fm, .am: "59"
        default: "599"
        }
    }

    /// Data (digital) modes.
    public var isDigital: Bool {
        switch self {
        case .rtty, .psk, .ft8, .ft4, .jt65, .digital: true
        default: false
        }
    }

    /// Derives the mode from the value of the ADIF field `MODE`, exactly like Java
    /// `Mode.fromAdif`: `value.trim().toUpperCase()`.
    ///
    /// The trim is **Java `trim()`** (`JavaText.trim`), not Swift
    /// `.whitespacesAndNewlines` — a no-break space and the like in the value
    /// stay and the mode is then not recognised. Same reason as for `Band.from(adif:)`:
    /// the mode is part of the comparison in `LogMerger.same`.
    ///
    /// The Java loop tests `m.adif.equals(v) || m.name().equals(v)`; for all
    /// ten modes `name()` is identical to `adif`, so the second condition adds nothing
    /// and is missing in Swift without consequence.
    public static func from(adif value: String?) -> Mode? {
        guard let value else { return nil }
        let v = JavaText.trim(value).uppercased()
        if let m = allCases.first(where: { $0.adif == v }) { return m }
        switch v {
        case "USB", "LSB": return .ssb
        default: return nil
        }
    }
}
