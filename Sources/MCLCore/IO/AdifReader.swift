import Foundation

/// ADIF reader — port of `io/AdifReader.java` (v1.1.1) **including the Java bugs**.
///
/// Fields `<NAME:LEN>value`, records separated by `<EOR>`, header up to `<EOH>`; unrecognised fields
/// are ignored. Algorithm:
/// - `<eoh>` and `<eor>` are searched for in **Java's `toLowerCase()` of the whole text** and the found
///   index is applied to the original. `U+0130` (İ) has a lowercase form of two units, so the
///   indices after it shift — Java then throws `StringIndexOutOfBoundsException`
///   (`JavaIndexOutOfBoundsError`) and the whole import fails; Swift does the same;
/// - the body is split on `<eor>` **before** the fields are read (`<EOR>` inside a value truncates the record);
/// - the field length is in **UTF-16 units**, `valStart + len` overflows like a Java `int`,
///   the end is clamped to the end of the record, a negative length throws;
/// - the last occurrence of a field wins; a QSO is created only from a record with a non-empty callsign.
///
/// Divergences (a deliberate divergence from Java v1.1.1): the model's text fields are `""` where Java returns
/// `null`; a cut in the middle of a surrogate pair yields `U+FFFD` instead of a lone
/// surrogate (`JavaChar.string`); keys of the raw map are Swift `String`s,
/// so canonically equal but differently encoded keys (`é` vs. `e` + U+0301) merge.
public struct AdifReader: Sendable {

    public init() {}

    /// Reads the file strictly as UTF-8 keeping the BOM (`Files.readString`).
    /// Unreadable file → `UncheckedIOError("Nelze načíst ADIF: <path>")`; a parse error
    /// passes through as `JavaIndexOutOfBoundsError`.
    public func readFile(_ file: URL) throws -> [Qso] {
        let content: String
        do {
            content = try Utf8Text.readFileKeepingBom(file)
        } catch {
            throw UncheckedIOError(message: "Nelze načíst ADIF: " + file.path, cause: error)
        }
        return try read(content)
    }

    /// QSOs from all records with a non-blank (Java `isBlank`) callsign.
    public func read(_ content: String) throws(JavaIndexOutOfBoundsError) -> [Qso] {
        var out: [Qso] = []
        for fields in try readRecords(content) {
            if let call = fields["call"], !JavaText.isBlank(call) {
                out.append(Self.toQso(fields))
            }
        }
        return out
    }

    /// Raw field maps (keys via Java `toLowerCase()`), one per span between `<eor>`;
    /// empty maps are omitted.
    public func readRecords(_ content: String) throws(JavaIndexOutOfBoundsError) -> [[String: String]] {
        let units = Array(content.utf16)
        let eoh = JavaText.indexOf(Self.lowerUnits(content, units), Self.eohTag)
        let body = eoh >= 0 ? try JavaText.substring(units, eoh + 5) : content
        var out: [[String: String]] = []
        for record in try Self.splitIgnoreCase(body) {
            let fields = try Self.parseFields(record)
            if !fields.isEmpty {
                out.append(fields)
            }
        }
        return out
    }

    // MARK: - Rozbor

    private static let eohTag: [UInt16] = Array("<eoh>".utf16)
    private static let eorTag: [UInt16] = Array("<eor>".utf16)
    private static let lt: [UInt16] = [0x3C]
    private static let gt: [UInt16] = [0x3E]
    private static let colon: UInt16 = 0x3A

    /// `splitIgnoreCase(text, "<eor>")`: indices from the lowercase copy, slices from the original.
    private static func splitIgnoreCase(_ text: String) throws(JavaIndexOutOfBoundsError) -> [[UInt16]] {
        let units = Array(text.utf16)
        let lower = lowerUnits(text, units)
        var parts: [[UInt16]] = []
        var from = 0
        var index = JavaText.indexOf(lower, eorTag, from: from)
        while index >= 0 {
            parts.append(Array(try JavaText.substring(units, from, index).utf16))
            from = index + eorTag.count
            index = JavaText.indexOf(lower, eorTag, from: from)
        }
        parts.append(Array(try JavaText.substring(units, from).utf16))
        return parts
    }

    private static func parseFields(_ record: [UInt16]) throws(JavaIndexOutOfBoundsError) -> [String: String] {
        var fields: [String: String] = [:]
        var i = 0
        while true {
            i = JavaText.indexOf(record, lt, from: i)
            if i < 0 { break }
            let gtIndex = JavaText.indexOf(record, gt, from: i)
            if gtIndex < 0 { break }
            let parts = splitOnColon(record[(i + 1)..<gtIndex])
            guard parts.count >= 2 else {
                i = gtIndex + 1 // tag without length (EOH/EOR) — skip
                continue
            }
            let name = lowerName(trimUnits(parts[0]))
            guard let len = JavaInteger.parseInt(String(decoding: trimUnits(parts[1]), as: UTF16.self)) else {
                i = gtIndex + 1
                continue
            }
            let valStart = gtIndex + 1
            // `valStart + len` as a Java `int` (overflow gives a negative end → exception).
            let valEnd = min(Int(JavaMath.addInt(Int32(valStart), len)), record.count)
            fields[name] = try JavaText.substring(record, valStart, valEnd)
            i = valEnd
        }
        return fields
    }

    /// Units of Java `text.toLowerCase()`; pure ASCII text (the common case) directly by
    /// units, otherwise via `JavaText.toLowerCase` (U+0130 → 2 units, Unicode 15.0).
    private static func lowerUnits(_ text: String, _ units: [UInt16]) -> [UInt16] {
        guard units.allSatisfy({ $0 < 0x80 }) else { return Array(JavaText.toLowerCase(text).utf16) }
        return units.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }
    }

    /// Java `trim()` over UTF-16 units (characters ≤ U+0020 are all in the BMP, so this is exact).
    private static func trimUnits(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var slice = units
        while let first = slice.first, first <= 0x20 { slice.removeFirst() }
        while let last = slice.last, last <= 0x20 { slice.removeLast() }
        return slice
    }

    /// Java `toLowerCase()` of the field name; pure ASCII names (the common case) without conversion to scalars.
    private static func lowerName(_ units: ArraySlice<UInt16>) -> String {
        guard units.allSatisfy({ $0 < 0x80 }) else {
            return JavaText.toLowerCase(String(decoding: units, as: UTF16.self))
        }
        return String(decoding: units.map { $0 >= 0x41 && $0 <= 0x5A ? $0 + 0x20 : $0 }, as: UTF16.self)
    }

    /// Java `tag.split(":")`: without a colon `[tag]`, otherwise parts with trailing empty ones
    /// removed (so `"a:"` → `["a"]`, `"::"` → `[]`).
    private static func splitOnColon(_ tag: ArraySlice<UInt16>) -> [ArraySlice<UInt16>] {
        guard tag.contains(colon) else { return [tag] }
        var parts = tag.split(separator: colon, omittingEmptySubsequences: false)
        while let last = parts.last, last.isEmpty {
            parts.removeLast()
        }
        return parts
    }

    // MARK: - QSO

    private static func toQso(_ f: [String: String]) -> Qso {
        var q = Qso()
        q.call = f["call"] ?? ""
        if let freq = f["freq"], !JavaText.isBlank(freq), let mhz = JavaDouble.parseDouble(JavaText.trim(freq)) {
            q.freqHz = Int(JavaMath.round(mhz * 1_000_000.0))
        }
        if q.band == nil, let band = f["band"], let parsed = Band.from(adif: band) {
            q.band = parsed
        }
        if let mode = f["mode"] {
            q.mode = Mode.from(adif: mode)
        }
        q.timestampUtc = parseInstant(f["qso_date"], f["time_on"])
        q.rstSent = f["rst_sent"] ?? ""
        q.rstRcvd = f["rst_rcvd"] ?? ""
        q.serialSent = intOrNil(f["stx"])
        q.serialRcvd = intOrNil(f["srx"])
        // SRX_STRING = the whole received exchange (as our export also writes it, with the report at
        // the start). The report is stripped so ImportedExchange does not add it twice.
        if let srx = f["srx_string"], !JavaText.isBlank(srx) {
            var ex = JavaText.trim(srx)
            let rst = q.rstRcvd
            if !JavaText.isBlank(rst) {
                let rstTrimmed = Array(JavaText.trim(rst).utf16)
                let exUnits = Array(ex.utf16)
                let prefixed = exUnits.starts(with: rstTrimmed + [0x20])
                if exUnits == rstTrimmed || prefixed {
                    ex = JavaText.trim(String(decoding: exUnits[rstTrimmed.count...], as: UTF16.self))
                }
            }
            q.exchangeRcvd = ex
        }
        if let stx = f["stx_string"], !JavaText.isBlank(stx) {
            q.exchangeSent = JavaText.trim(stx)
        }
        q.operator = f["operator"] ?? ""
        q.comment = f["comment"] ?? ""
        return q
    }

    /// `parseInstant`: date `yyyyMMdd` (strict, SMART), time `HH[mm[ss]]` via
    /// `Integer.parseInt` over two UTF-16 units; any Java `RuntimeException`
    /// (short time, non-numeric characters, `2400`, `125960`) → `nil`.
    private static func parseInstant(_ date: String?, _ time: String?) -> Date? {
        guard let date, !JavaText.isBlank(date) else { return nil }
        guard let day = JavaLocalDate.parseDate(JavaText.trim(date), separator: nil) else { return nil }
        var second: Int64 = 0
        if let time, !JavaText.isBlank(time) {
            let units = Array(JavaText.trim(time).utf16)
            guard let hh = parsePart(units, 0) else { return nil }
            var mm: Int32 = 0
            var ss: Int32 = 0
            if units.count >= 4 {
                guard let value = parsePart(units, 2) else { return nil }
                mm = value
            }
            if units.count >= 6 {
                guard let value = parsePart(units, 4) else { return nil }
                ss = value
            }
            guard let value = JavaLocalDate.secondOfDay(hour: hh, minute: mm, second: ss) else { return nil }
            second = value
        }
        return JavaLocalDate.instant(epochDay: day, secondOfDay: second)
    }

    /// `Integer.parseInt(tt.substring(from, from + 2))`; short text or non-number → `nil`.
    private static func parsePart(_ units: [UInt16], _ from: Int) -> Int32? {
        guard let part = try? JavaText.substring(units, from, from + 2) else { return nil }
        return JavaInteger.parseInt(part)
    }

    private static func intOrNil(_ s: String?) -> Int? {
        guard let s, !JavaText.isBlank(s), let value = JavaInteger.parseInt(JavaText.trim(s)) else {
            return nil
        }
        return Int(value)
    }
}
