import Foundation

/// Exception of the Cabrillo reader — Java class and text.
public enum CabrilloReaderError: Error, Equatable, Sendable {
    /// `java.lang.NumberFormatException` from `Integer.parseInt` (a numeric exchange overflows `int`).
    /// The text is Java's (`For input string: "99999999999"`); the gate compares only the class.
    case numberFormat(message: String)
    /// `java.io.UncheckedIOException("Nelze načíst Cabrillo: <path>", cause)` from `readFile`:
    /// the file cannot be read or is not valid UTF-8 (`causeClass` =
    /// `java.nio.charset.MalformedInputException`).
    case unreadable(message: String, causeClass: String)

    /// Full name of the Java exception class.
    public var javaClass: String {
        switch self {
        case .numberFormat: return "java.lang.NumberFormatException"
        case .unreadable: return "java.io.UncheckedIOException"
        }
    }
}

/// Cabrillo log reader — port of `io/CabrilloReader.java` (Java v1.1.1) **including its
/// heuristic bugs**. Parses `QSO:` and `X-QSO:` lines in the standard
/// layout `QSO: freq mode date time <sent...> <rcvd...>`. The counterpart is determined heuristically
/// as the second callsign on the line; the received RST and exchange follow. Hence:
/// - a 6-character locator or `5NN` before the counterpart's callsign is also taken as a "callsign"
///   (CR3, CR15) and the exchange shifts;
/// - a VHF frequency in kHz (`144`, `50`) gives 144 000 / 50 000 Hz and **no band** (CR2);
/// - a single callsign on the line (only our own) = the counterpart (CR5);
/// - a numeric exchange overflowing `int` fails the whole read with `NumberFormatException` (CR8).
///
/// The text is split the Java way, not with Swift facilities:
/// - lines `split("\\r?\\n")` — a lone `\r` does **not** end a line (CR10); Swift's `Character`
///   would treat `\r\n` as one character, so splitting is done over UTF-8 bytes;
/// - `trim()` = characters ≤ U+0020 (neither BOM nor NBSP is trimmed — CR12, CR19);
/// - tokens `split("\\s+")` with Java's ASCII `\s` = `[ \t\n\u{0B}\f\r]` (NBSP does not split — CR13).
///
/// All separators are ASCII, and in UTF-8 a byte < 0x80 is never part of a multi-byte
/// character, so splitting by bytes is exactly splitting by characters.
public struct CabrilloReader: Sendable {

    public init() {}

    /// Java `readFile(Path)`: `Files.readString` (strict UTF-8, BOM is **kept**), then `read`.
    /// Read or decoding error → `.unreadable` (Java `UncheckedIOException`).
    public func readFile(_ url: URL) throws(CabrilloReaderError) -> [Qso] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(message: "Nelze načíst Cabrillo: \(url.path)", causeClass: "java.io.IOException")
        }
        guard let text = Utf8Text.decodeKeepingBom(data) else {
            throw .unreadable(message: "Nelze načíst Cabrillo: \(url.path)",
                              causeClass: "java.nio.charset.MalformedInputException")
        }
        return try read(text)
    }

    /// Java `read(String)`.
    public func read(_ content: String) throws(CabrilloReaderError) -> [Qso] {
        var out: [Qso] = []
        let bytes: [UInt8] = Array(content.utf8)
        var lineStart = 0
        var index = 0
        while index <= bytes.count {
            if index == bytes.count || bytes[index] == 0x0A {
                if let qso = try parseLine(bytes, lineStart, index) {
                    out.append(qso)
                }
                lineStart = index + 1
            }
            index += 1
        }
        return out
    }

    // MARK: - line

    /// One line `[start, end)` without `\n`. A possible `\r` before `\n` (Java `\r?`) is trimmed by `trim`.
    private func parseLine(_ bytes: [UInt8], _ start: Int, _ end: Int) throws(CabrilloReaderError) -> Qso? {
        var lo = start
        var hi = end
        while lo < hi, bytes[lo] <= 0x20 { lo += 1 }
        while hi > lo, bytes[hi - 1] <= 0x20 { hi -= 1 }
        // `t.toUpperCase().startsWith("X-QSO:")` / `"QSO:"`.
        let prefix: Int
        let xqso: Bool
        if let length = Self.upperPrefixLength(bytes, lo, hi, "X-QSO:") {
            prefix = length
            xqso = true
        } else if let length = Self.upperPrefixLength(bytes, lo, hi, "QSO:") {
            prefix = length
            xqso = false
        } else {
            return nil
        }
        guard var qso = try parseQsoLine(bytes, lo + prefix, hi) else { return nil }
        qso.xqso = xqso
        return qso
    }

    /// Length in bytes of the prefix `[lo, hi)` whose Java `toUpperCase()` is exactly `prefix` (ASCII).
    /// Java compares the uppercased line and then takes `t.substring(prefix.length())` from the **original**
    /// — this works because every character that uppercases to `Q`, `S`, `O`, `X`, `-` or `:` is
    /// one UTF-16 unit and yields one character (`ſ` U+017F → `S`).
    private static func upperPrefixLength(_ bytes: [UInt8], _ lo: Int, _ hi: Int, _ prefix: String) -> Int? {
        var position = lo
        for expected in prefix.utf8 {
            guard position < hi else { return nil }
            let lead = bytes[position]
            if lead < 0x80 {
                let upper = (lead >= 0x61 && lead <= 0x7A) ? lead - 0x20 : lead
                guard upper == expected else { return nil }
                position += 1
            } else {
                let width = utf8Width(lead)
                guard position + width <= hi,
                      let scalar = String(decoding: bytes[position..<position + width], as: UTF8.self)
                          .unicodeScalars.first,
                      scalar.properties.uppercaseMapping == String(UnicodeScalar(expected))
                else { return nil }
                position += width
            }
        }
        return position - lo
    }

    private static func utf8Width(_ lead: UInt8) -> Int {
        if lead >= 0xF0 { return 4 }
        if lead >= 0xE0 { return 3 }
        return 2
    }

    /// Java `\s`: space, `\t`, `\n`, `\u{0B}`, `\f`, `\r`.
    private static func isJavaSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    /// Java `rest.trim().split("\\s+")` over `[lo, hi)`. After `trim` it neither starts nor ends
    /// with a `\s` character (all are ≤ U+0020), so no empty tokens arise — except for an empty
    /// rest, where Java returns `[""]` (length 1 < 6, the line is discarded anyway).
    private static func tokens(_ bytes: [UInt8], _ lo: Int, _ hi: Int) -> [ArraySlice<UInt8>] {
        var start = lo
        var end = hi
        while start < end, bytes[start] <= 0x20 { start += 1 }
        while end > start, bytes[end - 1] <= 0x20 { end -= 1 }
        var out: [ArraySlice<UInt8>] = []
        var tokenStart = start
        var index = start
        while index < end {
            if isJavaSpace(bytes[index]) {
                out.append(bytes[tokenStart..<index])
                while index < end, isJavaSpace(bytes[index]) { index += 1 }
                tokenStart = index
            } else {
                index += 1
            }
        }
        out.append(bytes[tokenStart..<end])
        return out
    }

    private static func string(_ token: ArraySlice<UInt8>) -> String {
        String(decoding: token, as: UTF8.self)
    }

    private func parseQsoLine(_ bytes: [UInt8], _ lo: Int, _ hi: Int) throws(CabrilloReaderError) -> Qso? {
        let tok = Self.tokens(bytes, lo, hi)
        if tok.count < 6 {
            return nil
        }
        // from index 4 we look for callsigns (1st = own station, 2nd = counterpart)
        var calls: [Int] = []
        for i in 4..<tok.count where Self.isCallsign(tok[i]) {
            calls.append(i)
            if calls.count == 2 { break }
        }
        let hisIdx: Int
        if calls.count >= 2 {
            hisIdx = calls[1]
        } else if calls.count == 1 {
            hisIdx = calls[0]
        } else {
            return nil
        }

        var q = Qso()
        q.call = Self.string(tok[hisIdx])
        if let kHz = JavaDouble.parseDouble(Self.string(tok[0])) {
            // `Math.round(Double.parseDouble(freqKHz) * 1000.0)`; error → the frequency stays 0.
            q.freqHz = Int(JavaMath.round(kHz * 1000.0))
        }
        q.mode = Self.mapMode(Self.string(tok[1]))
        q.timestampUtc = Self.parseInstant(Self.string(tok[2]), Self.string(tok[3]))
        if hisIdx + 1 < tok.count {
            q.rstRcvd = Self.string(tok[hisIdx + 1])
        }
        if hisIdx + 2 < tok.count {
            let exch = tok[(hisIdx + 2)...].map(Self.string).joined(separator: " ")
            q.exchangeRcvd = exch
            // `exch.matches("\\d+")` (ASCII digits) → `Integer.parseInt(exch)` **without try**.
            if !exch.isEmpty, exch.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
                guard let serial = JavaInteger.parseInt(exch) else {
                    throw .numberFormat(message: "For input string: \"\(exch)\"")
                }
                q.serialRcvd = Int(serial)
            }
        }
        return q
    }

    /// Java `CALLSIGN.matcher(tok.toUpperCase()).matches()` with the pattern
    /// `[A-Z0-9/]*[0-9][A-Z][A-Z0-9/]*`: the uppercased token consists entirely of `[A-Z0-9/]` and somewhere in it
    /// a digit stands right before a letter. A non-ASCII token is uppercased by Swift's `uppercased()`
    /// (full mapping like Java `toUpperCase()`; `ſ` → `S`, `ﬁ` → `FI`).
    static func isCallsign(_ token: ArraySlice<UInt8>) -> Bool {
        if token.allSatisfy({ $0 < 0x80 }) {
            return isUpperCallsign(token.lazy.map { ($0 >= 0x61 && $0 <= 0x7A) ? $0 - 0x20 : $0 })
        }
        return isUpperCallsign(string(token).uppercased().utf8)
    }

    private static func isUpperCallsign<S: Sequence>(_ upper: S) -> Bool where S.Element == UInt8 {
        var previousDigit = false
        var digitLetter = false
        for byte in upper {
            let digit = byte >= 0x30 && byte <= 0x39
            let letter = byte >= 0x41 && byte <= 0x5A
            guard digit || letter || byte == 0x2F else { return false }
            if letter && previousDigit { digitLetter = true }
            previousDigit = digit
        }
        return digitLetter
    }

    /// Java `mapMode`: `switch (m.toUpperCase())`, otherwise `Mode.fromAdif(m)`.
    static func mapMode(_ m: String) -> Mode? {
        switch m.uppercased() {
        case "CW": return .cw
        case "PH", "SSB", "USB", "LSB": return .ssb
        case "FM": return .fm
        case "RY", "RTTY": return .rtty
        case "DG", "DI", "DIGI": return .digital
        default: return Mode.from(adif: m)
        }
    }

    // MARK: - date and time

    /// Java `parseInstant`: `LocalDate.parse(date, ofPattern("yyyy-MM-dd"))` (resolver style SMART),
    /// `time.replace(":", "")`, hours = UTF-16 units 0–2, minutes 2–4 only when length ≥ 4,
    /// both `Integer.parseInt` (also accepts other Unicode digits and a sign: `١٢٠٠` = 12:00,
    /// `+1+2` = 01:02), `LocalTime.of(hh, mm)`. Any error → `nil`.
    static func parseInstant(_ date: String, _ time: String) -> Date? {
        guard let epochDay = parseEpochDay(date) else { return nil }
        let units: [UInt16] = Array(time.utf16).filter { $0 != 0x3A } // ':'
        guard units.count >= 2,
              let hh = JavaInteger.parseInt(String(decoding: units[0..<2], as: UTF16.self))
        else { return nil }
        var mm: Int32 = 0
        if units.count >= 4 {
            guard let minutes = JavaInteger.parseInt(String(decoding: units[2..<4], as: UTF16.self)) else {
                return nil
            }
            mm = minutes
        }
        guard (0...23).contains(hh), (0...59).contains(mm) else { return nil }
        let seconds: Int64 = epochDay * 86_400 + Int64(hh) * 3_600 + Int64(mm) * 60
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// `LocalDate.parse(text, DateTimeFormatter.ofPattern("yyyy-MM-dd"))` → day since the epoch.
    ///
    /// The pattern is strict parsing with resolver style SMART (JDK 21, measured):
    /// - `yyyy` = `YEAR_OF_ERA`, 4–19 digits, `SignStyle.EXCEEDS_PAD`: without a sign **exactly
    ///   4** digits, with `+` **more than 4** (`+02026` passes, `02026` does not), `-` is always an error
    ///   (a negative era year is invalid); year 1…999 999 999;
    /// - `MM`, `dd` exactly two digits, no sign; month 1–12, day 1–31;
    /// - SMART: a day past the end of the month is reduced to the last day (30 Feb → 28 Feb, 31 Apr → 30 Apr);
    /// - digits ASCII only (`DecimalStyle.STANDARD`), the whole text must be consumed.
    static func parseEpochDay(_ text: String) -> Int64? {
        let units: [UInt16] = Array(text.utf16)
        var index = 0
        var plus = false
        if let first = units.first, first == 0x2B || first == 0x2D {
            guard first == 0x2B else { return nil }
            plus = true
            index = 1
        }
        let yearStart = index
        var year: Int64 = 0
        while index < units.count, index - yearStart < 19, isAsciiDigit(units[index]) {
            // Above 10 digits no valid value is possible (except leading zeros) — saturate.
            year = min(year * 10 + Int64(units[index] - 0x30), 10_000_000_000)
            index += 1
        }
        let yearDigits = index - yearStart
        if plus ? yearDigits <= 4 : yearDigits != 4 { return nil }
        guard index < units.count, units[index] == 0x2D else { return nil }
        guard let month = twoDigits(units, index + 1),
              index + 3 < units.count, units[index + 3] == 0x2D,
              let day = twoDigits(units, index + 4),
              index + 6 == units.count
        else { return nil }
        guard (1...999_999_999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        let clamped: Int64 = min(day, monthLength(year, month))
        return epochDay(year, month, clamped)
    }

    private static func isAsciiDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func twoDigits(_ units: [UInt16], _ at: Int) -> Int64? {
        guard at + 1 < units.count, isAsciiDigit(units[at]), isAsciiDigit(units[at + 1]) else { return nil }
        return Int64(units[at] - 0x30) * 10 + Int64(units[at + 1] - 0x30)
    }

    private static func isLeap(_ year: Int64) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    private static func monthLength(_ year: Int64, _ month: Int64) -> Int64 {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Java `LocalDate.toEpochDay()` (proleptic Gregorian calendar).
    private static func epochDay(_ year: Int64, _ month: Int64, _ day: Int64) -> Int64 {
        var total: Int64 = 365 * year
        if year >= 0 {
            total += (year + 3) / 4 - (year + 99) / 100 + (year + 399) / 400
        } else {
            total -= year / -4 - year / -100 + year / -400
        }
        total += (367 * month - 362) / 12
        total += day - 1
        if month > 2 {
            total -= 1
            if !isLeap(year) { total -= 1 }
        }
        return total - 719_528
    }
}
