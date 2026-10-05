import Foundation

/// Parses a standard N1MM `<contactinfo>` UDP message into a `Qso` + auxiliary fields. Port of Java
/// `n1mmrecv/N1mmContactParser`: contactinfo is flat XML, a tag regex is enough; the frequency is
/// in tens of Hz (×10 to Hz).
///
/// Java behaviour (measured on v1.1.1):
/// - tag `<name\s*>(.*?)</name>` with `CASE_INSENSITIVE | DOTALL` (ASCII case only,
///   `\s` = ASCII whitespace), first occurrence, value `trim()`, empty → `null`;
/// - **XML entities are not decoded** (`A&amp;B` → callsign `A&AMP;B`);
/// - time `yyyy-MM-dd HH:mm:ss` with `ResolverStyle.SMART`: `2026-02-30` → 28 Feb, `24:00:00` →
///   midnight of the next day, field widths strict (`2026-1-01` → `null`);
/// - `sntnr`/`rcvnr` `Integer.parseInt` (overflow → `null`, `+5` → 5), frequency
///   `Long.parseLong` × 10 with wraparound, error → 0.
///
/// Representation divergence: Java `null` for `rstSent`/`rstRcvd` is an empty string in the Swift `Qso`.
public enum N1mmContactParser {

    public struct ParsedContact: Equatable, Sendable {
        public let qso: Qso
        /// Java `LinkedHashMap` (insertion order): `rst_rcvd`, `srx_string`, `gridsquare`.
        public let fields: JavaLinkedMap<String>
        public let app: String?
        public let stationName: String?
    }

    /// Returns `nil` if the XML has no non-empty `<call>` (Java `isBlank`).
    public static func parse(_ xml: String?) -> ParsedContact? {
        guard let xml else { return nil }
        let units = Array(xml.utf16)
        guard let call = tag(units, "call"), !JavaText.isBlank(call) else { return nil }
        var q = Qso()
        q.call = call
        if let mode = tag(units, "mode") {
            q.mode = Mode.from(adif: mode)
        }
        let tens = parseLongSafe(firstNonBlank(tag(units, "txfreq"), tag(units, "rxfreq")))
        q.freqHz = Int(tens &* 10)
        let rcv = tag(units, "rcv")
        let rcvNr = tag(units, "rcvnr")
        q.rstSent = tag(units, "snt") ?? ""
        q.rstRcvd = rcv ?? ""
        q.serialSent = intOrNull(tag(units, "sntnr")).map { Int($0) }
        q.serialRcvd = intOrNull(rcvNr).map { Int($0) }
        q.timestampUtc = parseTs(tag(units, "timestamp"))

        var fields = JavaLinkedMap<String>()
        putIfPresent(&fields, "rst_rcvd", rcv)
        putIfPresent(&fields, "srx_string", rcvNr)
        putIfPresent(&fields, "gridsquare", tag(units, "gridsquare"))

        return ParsedContact(qso: q, fields: fields, app: tag(units, "app"), stationName: tag(units, "StationName"))
    }

    // MARK: - Tag

    /// `Pattern.compile("<" + name + "\\s*>(.*?)</" + name + ">", CASE_INSENSITIVE | DOTALL).find()`.
    /// The leftmost opening tag; if it has no closing tag after it, no later one has either → `null`.
    static func tag(_ xml: [UInt16], _ name: String) -> String? {
        let nameUnits = Array(name.utf16)
        var start = 0
        while start < xml.count {
            if let contentStart = matchOpen(xml, at: start, nameUnits) {
                guard let contentEnd = findClose(xml, from: contentStart, nameUnits) else { return nil }
                let value = JavaText.trim(JavaChar.string(Array(xml[contentStart..<contentEnd])))
                return value.isEmpty ? nil : value
            }
            start += 1
        }
        return nil
    }

    /// `<name\s*>` at position `at` → index after `>`.
    private static func matchOpen(_ xml: [UInt16], at index: Int, _ name: [UInt16]) -> Int? {
        guard xml[index] == 0x3C, matchName(xml, at: index + 1, name) else { return nil }
        var i = index + 1 + name.count
        while i < xml.count, JavaChar.isRegexSpace(xml[i]) { i += 1 }
        guard i < xml.count, xml[i] == 0x3E else { return nil }
        return i + 1
    }

    /// First `</name>` from `from` → index of its start (lazy `.*?` with `DOTALL`).
    private static func findClose(_ xml: [UInt16], from: Int, _ name: [UInt16]) -> Int? {
        var i = from
        while i + 3 + name.count <= xml.count {
            if xml[i] == 0x3C, xml[i + 1] == 0x2F, matchName(xml, at: i + 2, name),
               xml[i + 2 + name.count] == 0x3E {
                return i
            }
            i += 1
        }
        return nil
    }

    /// Name match regardless of case — `CASE_INSENSITIVE` without `UNICODE_CASE`
    /// compares case only for ASCII (tag names are ASCII).
    private static func matchName(_ xml: [UInt16], at index: Int, _ name: [UInt16]) -> Bool {
        guard index + name.count <= xml.count else { return false }
        for (offset, unit) in name.enumerated() where asciiLower(xml[index + offset]) != asciiLower(unit) {
            return false
        }
        return true
    }

    private static func asciiLower(_ unit: UInt16) -> UInt16 {
        unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit
    }

    // MARK: - Values

    private static func putIfPresent(_ map: inout JavaLinkedMap<String>, _ key: String, _ value: String?) {
        if let value, !JavaText.isBlank(value) {
            map.put(key, JavaText.trim(value))
        }
    }

    private static func parseLongSafe(_ s: String?) -> Int64 {
        guard let s, !JavaText.isBlank(s) else { return 0 }
        return (try? JavaInteger.parseLong(JavaText.trim(s))) ?? 0
    }

    private static func intOrNull(_ s: String?) -> Int32? {
        guard let s, !JavaText.isBlank(s) else { return nil }
        return JavaInteger.parseInt(JavaText.trim(s))
    }

    private static func firstNonBlank(_ values: String?...) -> String? {
        values.first { $0.map { !JavaText.isBlank($0) } ?? false } ?? nil
    }

    /// `LocalDateTime.parse(s.trim(), ofPattern("yyyy-MM-dd HH:mm:ss")).toInstant(UTC)`; error → `nil`.
    static func parseTs(_ s: String?) -> Date? {
        guard let s, !JavaText.isBlank(s) else { return nil }
        return parseLocalDateTimeUtc(JavaText.trim(s))
    }

    /// `LocalDateTime.parse(s, ofPattern("yyyy-MM-dd HH:mm:ss")).toInstant(UTC)` of the text as is (no trim);
    /// error → `nil`. Shared with the time cell of the log table (`LogTableEdit`).
    static func parseLocalDateTimeUtc(_ s: String) -> Date? {
        let units = Array(s.utf16)
        // A date cannot contain a space, so the literal ' ' is the first space in the text.
        guard let space = units.firstIndex(of: 0x20) else { return nil }
        guard let day = JavaLocalDate.parseDate(JavaChar.string(Array(units[..<space])), separator: 0x2D),
              let time = parseTime(Array(units[(space + 1)...]))
        else { return nil }
        let epochDay = day + time.excessDays
        guard epochDay <= maxEpochDay else { return nil } // `plusDays` past LocalDate.MAX throws
        return JavaLocalDate.instant(epochDay: epochDay, secondOfDay: time.secondOfDay)
    }

    /// `HH:mm:ss` (exactly 2 ASCII digits) and SMART `resolveTime`: minutes and seconds in range,
    /// hour 0…23, or `24:00:00` = midnight of the next day (`Period.ofDays(1)`).
    private static func parseTime(_ units: [UInt16]) -> (secondOfDay: Int64, excessDays: Int64)? {
        guard units.count == 8, units[2] == 0x3A, units[5] == 0x3A,
              let hour = twoDigits(units, 0), let minute = twoDigits(units, 3), let second = twoDigits(units, 6),
              minute <= 59
        else { return nil }
        if hour == 24 && minute == 0 && second == 0 { return (0, 1) }
        guard hour <= 23, second <= 59 else { return nil }
        return (hour * 3600 + minute * 60 + second, 0)
    }

    private static func twoDigits(_ units: [UInt16], _ at: Int) -> Int64? {
        let high = units[at]
        let low = units[at + 1]
        guard (0x30...0x39).contains(high), (0x30...0x39).contains(low) else { return nil }
        return Int64(high - 0x30) * 10 + Int64(low - 0x30)
    }

    /// `LocalDate.MAX` (+999999999-12-31).
    private static let maxEpochDay: Int64 = JavaLocalDate.epochDay(year: 999_999_999, month: 12, day: 31)
}
