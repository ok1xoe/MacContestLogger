import Foundation

/// "Cut" number style in CW (N1MM Configurer → Function Keys → Cut Number Style):
/// digits are replaced by shorter characters (0 → T, 9 → N…). It applies only to serial
/// numbers, the `{SENTRSTCUT}` report is always 5NN. Mirrors Java
/// `cz.ok1xoe.maccontestlogger.keyer.CutStyle`.
public enum CutStyle: String, Codable, Equatable, Sendable, CaseIterable {
    /// T1234567890 — only leading zeros as T (007 → TT7, 030 → T30).
    case leadingT = "LEADING_T"
    /// O1234567890 — only leading zeros as O.
    case leadingO = "LEADING_O"
    /// T123456789T — all zeros T.
    case allT = "ALL_T"
    /// O123456789O — all zeros O.
    case allO = "ALL_O"
    /// T12345678NT — zeros T, nines N.
    case tn = "TN"
    /// O12345678NO — zeros O, nines N.
    case on = "ON"
    /// TA2345678NT — plus one as A.
    case tan = "TAN"
    /// TA234E678NT — plus five as E.
    case taen = "TAEN"
    /// TAU34E67DNT — 0 1 2 5 8 9 → T A U E D N.
    case tauedn = "TAUEDN"

    private var map: String {
        switch self {
        case .leadingT: "T123456789"
        case .leadingO: "O123456789"
        case .allT: "T123456789"
        case .allO: "O123456789"
        case .tn: "T12345678N"
        case .on: "O12345678N"
        case .tan: "TA2345678N"
        case .taen: "TA234E678N"
        case .tauedn: "TAU34E67DN"
        }
    }

    private var leadingOnly: Bool {
        switch self {
        case .leadingT, .leadingO: true
        default: false
        }
    }

    /// Description for Settings.
    public var label: String {
        switch self {
        case .leadingT: "Úvodní nuly T (007 → TT7)"
        case .leadingO: "Úvodní nuly O (007 → OO7)"
        case .allT: "Všechny nuly T (030 → T3T)"
        case .allO: "Všechny nuly O (030 → O3O)"
        case .tn: "T a N (097 → TN7)"
        case .on: "O a N (097 → ON7)"
        case .tan: "T, A, N (191 → ANA)"
        case .taen: "T, A, E, N (1590 → AENT)"
        case .tauedn: "T, A, U, E, D, N (plné zkratky)"
        }
    }

    /// Converts digits according to the style; leaves other characters unchanged. Like Java by UTF-16 units
    /// (`charAt`): digits are ASCII `0`–`9` only, a combining character after a digit is a separate "other"
    /// character (`0\u{0301}` → `T\u{0301}`), Arabic digits stay.
    public func apply(_ digits: String) -> String {
        let units = Array(digits.utf16)
        let mapUnits = Array(map.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var leading = true
        for i in units.indices {
            let c = units[i]
            guard c >= 0x30 && c <= 0x39 else {
                out.append(c)
                leading = false
                continue
            }
            let lastChar = i == units.count - 1
            let replace = !leadingOnly || (leading && c == 0x30 && !lastChar)
            out.append(replace ? mapUnits[Int(c - 0x30)] : c)
            if c != 0x30 { leading = false }
        }
        return JavaChar.string(out)
    }
}
