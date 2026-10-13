/// Visible dupesheet (N1MM): worked callsigns for the current band / mode by the contest's dupe
/// rules, split into columns by the area digit (OK1… → 1). Callsigns without a
/// digit go to the `#` column. Port of Java `logbook/Dupesheet`.
///
/// **X-QSOs are not left out** (as in Java), deleted QSOs and empty
/// callsigns are. Columns and callsigns are sorted by UTF-16 (Java `TreeMap<Character>` /
/// `TreeSet<String>`): `#` (0x23) before `0`, `K` and KELVIN SIGN are two different callsigns. The Swift-only
/// `Order.suffix` sorts the callsigns of a column by their suffix instead (N1MM).
public enum Dupesheet {

    /// Column for callsigns without a digit.
    public static let noDigit: Character = "#"

    /// One column: the area digit and sorted unique callsigns.
    public struct Column: Equatable, Sendable {
        public let key: Character
        public let calls: [String]
    }

    /// Result of `build`: columns sorted by the UTF-16 value of the key.
    public struct Sheet: Equatable, Sendable {
        public let columns: [Column]

        /// Callsigns of the column (Java `get`), `nil` = the column does not exist. The key is compared by UTF-16.
        public subscript(_ key: Character) -> [String]? {
            columns.first { JavaText.equals(String($0.key), String(key)) }?.calls
        }

        public var isEmpty: Bool { columns.isEmpty }
    }

    /// The order of the calls in a column.
    public enum Order: Sendable {
        /// By the whole call (UTF-16), the Java order.
        case call
        /// By the suffix (N1MM Visible Dupesheet: "each call area is sorted by suffix"), then by the whole call.
        case suffix
    }

    /// - Parameters:
    ///   - band: band (ADIF, e.g. `20m`); `nil` = all
    ///   - mode: mode (e.g. `CW`, compared with the mode name by UTF-16); `nil` = all
    ///   - scope: the contest's dupe scope; `nil` = per band (free logging)
    ///   - order: the order of the calls in a column (`.call` = Java's)
    public static func build(_ qsos: [Qso], band: String?, mode: String?,
                             scope: ContestDefinition.Scope?, order: Order = .call) -> Sheet {
        let sc = scope ?? .PER_BAND
        let byBand = sc == .PER_BAND || sc == .PER_BAND_MODE
        let byMode = sc == .PER_MODE || sc == .PER_BAND_MODE
        var columns: [UInt16: [[UInt16]: String]] = [:]
        for q in qsos {
            if q.deleted || JavaText.isBlank(q.call) { continue }
            if byBand, let band, !(q.band.map { JavaText.equals($0.adif, band) } ?? false) { continue }
            if byMode, let mode, !(q.mode.map { JavaText.equals($0.rawValue, mode) } ?? false) { continue }
            let call = JavaText.trim(q.call).uppercased()
            columns[areaDigitUnit(call), default: [:]][Array(call.utf16)] = call
        }
        let sorted = columns.keys.sorted().map { unit -> Column in
            let calls: [String]
            switch order {
            case .call:
                calls = columns[unit]!.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map(\.value)
            case .suffix:
                calls = columns[unit]!.map { (suffix: suffixUnits($0.key), call: $0.key, text: $0.value) }
                    .sorted { lhs, rhs in
                        lhs.suffix != rhs.suffix
                            ? lhs.suffix.lexicographicallyPrecedes(rhs.suffix)
                            : lhs.call.lexicographicallyPrecedes(rhs.call)
                    }
                    .map(\.text)
            }
            return Column(key: Character(Unicode.Scalar(unit)!), calls: calls)
        }
        return Sheet(columns: sorted)
    }

    /// Area digit: the first digit (`Character.isDigit`, so also decimal digits
    /// of Unicode other than ASCII) of the **longest** part between slashes (the first on equal length);
    /// `#` without a digit.
    public static func areaDigit(_ call: String) -> Character {
        Character(Unicode.Scalar(areaDigitUnit(call))!)
    }

    /// The suffix of a call: what follows the last digit of the base call (the longest part between slashes), e.g.
    /// `OK1XOE` → `XOE`, `DL/OK1XOE/P` → `XOE`, `3DA0RU` → `RU`. A call without a digit is its own suffix.
    public static func suffix(_ call: String) -> String {
        String(decoding: suffixUnits(Array(call.utf16)), as: UTF16.self)
    }

    private static func suffixUnits(_ units: [UInt16]) -> [UInt16] {
        let base: ArraySlice<UInt16> = baseUnits(units)
        guard let last = base.lastIndex(where: { JavaChar.isDigit($0) }) else { return units }
        return Array(base[(last + 1)...])
    }

    /// `split("/")` + the longest part (the first on equal length); empty parts are never longer than "".
    private static func baseUnits(_ units: [UInt16]) -> ArraySlice<UInt16> {
        var base: ArraySlice<UInt16> = []
        var start = 0
        for i in 0...units.count where i == units.count || units[i] == 0x2F {
            let part = units[start..<i]
            if part.count > base.count { base = part }
            start = i + 1
        }
        return base
    }

    private static func areaDigitUnit(_ call: String) -> UInt16 {
        // `Character.isDigit` never returns true for half of a surrogate pair,
        // so the resulting unit is always a standalone scalar.
        baseUnits(Array(call.utf16)).first { JavaChar.isDigit($0) } ?? 0x23
    }
}
