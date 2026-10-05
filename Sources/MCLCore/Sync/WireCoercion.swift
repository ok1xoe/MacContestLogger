/// Jackson 2.22 coercions when reading a record component (default `CoercionConfig`, `ALLOW_COERCION_OF_SCALARS`,
/// `ACCEPT_FLOAT_AS_INT`, `READ_DATE_TIMESTAMPS_AS_NANOSECONDS` enabled). Measured by a probe on the Java
/// `WireJson` (generator section `sync.JSONR`):
///
/// | component | string | integer | decimal | `true`/`false` | `null` |
/// |---|---|---|---|---|---|
/// | `String` | itself | token text (`-0`, `1E+2`) | token text | `"true"`/`"false"` | `nil` |
/// | `long`/`int` | `trim`, `""`/only ≤ U+0020/`"null"` → 0, otherwise `Long.parseLong` (+, Unicode digits) and range | range, otherwise error | via `Double`, out-of-range error, otherwise truncation | error | 0 |
/// | `Integer` | like `int`, empty/`"null"` → `nil` | like `int` | like `int` | error | `nil` |
/// | `boolean`/`Boolean` | `true`/`True`/`TRUE`, `false`/`False`/`FALSE`, empty/`"null"` → false/`nil`, otherwise error | ≠ 0 | error | value | false/`nil` |
/// | `Instant` | `trim`, empty → `nil`; digits only → seconds, with one dot → seconds.fraction; otherwise `ISO_INSTANT` (zero offset `+00`, `+0000`, `+00:00` → `Z`) | epoch seconds | `BigDecimal` → seconds + nanoseconds (Jackson `DecimalUtils`) | error | `nil` |
/// | record | error | error | error | error | `nil` |
///
/// An array (`[…]`) is an error for all types, an object only for a nested record.
enum WireCoercion {

    typealias Token = WireJsonReader.Parser.Token
    typealias Failure = WireJsonReader.Failure

    static func coerce(_ token: Token, to kind: WireKind) throws(Failure) -> WireValue {
        switch kind {
        case .string:
            return .string(stringValue(token))
        case .long:
            return .long(try longValue(token))
        case .int:
            return .int(try intValue(token, box: false) ?? 0)
        case .bool:
            return .bool(try boolValue(token, box: false) ?? false)
        case .intBox:
            return .intBox(try intValue(token, box: true))
        case .boolBox:
            return .boolBox(try boolValue(token, box: true))
        case .instant:
            return .instant(try instantValue(token))
        case .record:
            guard case .null = token else { throw Failure() }
            return .record(nil)
        }
    }

    static func stringValue(_ token: Token) -> String? {
        switch token {
        case .string(let s): return s
        case .integer(let text), .decimal(let text): return text
        case .bool(let b): return b ? "true" : "false"
        case .null: return nil
        }
    }

    /// `_isBlank`: all UTF-16 units ≤ U+0020 (an empty string is handled separately by the caller).
    static func isBlank(_ s: String) -> Bool {
        s.utf16.allSatisfy { $0 <= 0x20 }
    }

    /// String for numeric/boolean coercion after `_checkFromStringCoercion` + `trim` + the textual `null` check;
    /// `nil` = the result is "null" (empty, only ≤ U+0020, or `"null"`).
    static func coercibleText(_ s: String) -> String? {
        if s.isEmpty || isBlank(s) {
            return nil
        }
        let trimmed: String = JavaText.trim(s)
        return trimmed == "null" ? nil : trimmed
    }

    // MARK: - integers

    static func longValue(_ token: Token) throws(Failure) -> Int64 {
        switch token {
        case .integer(let text):
            guard let v = Int64(text) else { throw Failure() }
            return v
        case .decimal(let text):
            let d: Double = try double(text)
            guard d >= -9.223372036854775808e18, d <= 9.223372036854775807e18 else { throw Failure() }
            return d >= 9.223372036854775807e18 ? Int64.max : Int64(d)
        case .string(let s):
            guard let text = coercibleText(s) else { return 0 }
            guard text.utf16.count <= 1_000 else { throw Failure() }
            do {
                return try JavaInteger.parseLong(text)
            } catch {
                throw Failure()
            }
        case .bool:
            throw Failure()
        case .null:
            return 0
        }
    }

    /// `int` (`box == false`, "null" → 0) or `Integer` (`box == true`, "null" → `nil`).
    static func intValue(_ token: Token, box: Bool) throws(Failure) -> Int32? {
        switch token {
        case .integer(let text):
            guard let v = Int64(text), let i = Int32(exactly: v) else { throw Failure() }
            return i
        case .decimal(let text):
            let d: Double = try double(text)
            guard d >= -2_147_483_648.0, d <= 2_147_483_647.0 else { throw Failure() }
            return Int32(d)
        case .string(let s):
            guard let text = coercibleText(s) else { return box ? nil : 0 }
            guard text.utf16.count <= 1_000 else { throw Failure() }
            let parsed: Int64
            do {
                parsed = try JavaInteger.parseLong(text)
            } catch {
                throw Failure()
            }
            guard let i = Int32(exactly: parsed) else { throw Failure() }
            return i
        case .bool:
            throw Failure()
        case .null:
            return box ? nil : 0
        }
    }

    static func double(_ text: String) throws(Failure) -> Double {
        guard let d = Double(text) else { throw Failure() }
        return d
    }

    // MARK: - booleans

    static func boolValue(_ token: Token, box: Bool) throws(Failure) -> Bool? {
        switch token {
        case .bool(let b):
            return b
        case .integer(let text):
            return text != "0" && text != "-0"
        case .decimal:
            throw Failure()
        case .null:
            return box ? nil : false
        case .string(let s):
            guard let text = coercibleText(s) else { return box ? nil : false }
            if text == "true" || text == "True" || text == "TRUE" {
                return true
            }
            if text == "false" || text == "False" || text == "FALSE" {
                return false
            }
            throw Failure()
        }
    }

    // MARK: - instant

    static func instantValue(_ token: Token) throws(Failure) -> JavaInstant? {
        switch token {
        case .integer(let text):
            guard let v = Int64(text), let instant = JavaInstant.ofEpochSecond(v) else { throw Failure() }
            return instant
        case .decimal(let text):
            guard let decimal = JavaBigDecimal(text) else { throw Failure() }
            return try fromDecimal(decimal)
        case .string(let s):
            return try instantFromString(s)
        case .bool:
            throw Failure()
        case .null:
            return nil
        }
    }

    /// `InstantDeserializer._fromString` for `ISO_INSTANT`.
    static func instantFromString(_ s: String) throws(Failure) -> JavaInstant? {
        let text: String = JavaText.trim(s)
        if text.isEmpty {
            return nil
        }
        switch countPeriods(text) {
        case 0:
            if let seconds = try? JavaInteger.parseLong(text) {
                guard let instant = JavaInstant.ofEpochSecond(seconds) else { throw Failure() }
                return instant
            }
        case 1:
            if let decimal = JavaBigDecimal(text) {
                return try fromDecimal(decimal)
            }
        default:
            break
        }
        guard let instant = JavaInstant.parseIsoInstant(replaceZeroOffsetAsZ(text)) else { throw Failure() }
        return instant
    }

    /// `_countPeriods(str, false)`: number of dots if the text consists only of ASCII digits and dots (with an optional `-` at
    /// the start), otherwise −1.
    static func countPeriods(_ text: String) -> Int {
        var units = Substring(text).utf16[...]
        if units.first == 0x2D {
            units = units.dropFirst()
        }
        var dots = 0
        for unit in units {
            if unit == 0x2E {
                dots += 1
            } else if unit < 0x30 || unit > 0x39 {
                return -1
            }
        }
        return dots
    }

    /// `replaceZeroOffsetAsZ`: after the last `+` exactly `00`, `0000` or `00:00` → `Z`.
    static func replaceZeroOffsetAsZ(_ text: String) -> String {
        let units = Array(text.utf16)
        guard let plus = units.lastIndex(of: 0x2B) else { return text }
        let tail = String(decoding: units[(plus + 1)...], as: UTF16.self)
        guard tail == "00" || tail == "0000" || tail == "00:00" else { return text }
        return String(decoding: units[..<plus], as: UTF16.self) + "Z"
    }

    /// `DecimalUtils.extractSecondsAndNanos(value, …, false)` + `Instant.ofEpochSecond(s, ns)`.
    ///
    /// Seconds = `BigDecimal.longValue()` (the low 64 bits of the integer part — overflow for huge values),
    /// nanoseconds = `(value·10⁹ − seconds·10⁹).intValue()`, which is always the first 9 decimal digits with the
    /// sign of the value (the difference on overflow is a multiple of 2⁶⁴·10⁹, whose low 32 bits are zero). A value
    /// below 10⁻⁹ and a value with scale below −63 (`1e64`, `1.5e300`) give the epoch.
    static func fromDecimal(_ value: JavaBigDecimal) throws(Failure) -> JavaInstant {
        let digits: [UInt8] = value.digits
        guard !digits.isEmpty else { return JavaInstant.epoch }
        let scaledNanos: Int64 = value.scale - 9
        guard scaledNanos >= Int64(Int32.min) else { throw Failure() }
        if Int64(digits.count) - scaledNanos <= 0 || value.scale < -63 {
            return JavaInstant.epoch
        }
        var integerPart: [UInt8]
        var fractionPart: [UInt8]
        if value.scale <= 0 {
            integerPart = digits + [UInt8](repeating: 0, count: Int(-value.scale))
            fractionPart = []
        } else {
            let scale = Int(value.scale)
            if digits.count > scale {
                integerPart = Array(digits[..<(digits.count - scale)])
                fractionPart = Array(digits[(digits.count - scale)...])
            } else {
                integerPart = []
                fractionPart = [UInt8](repeating: 0, count: scale - digits.count) + digits
            }
        }
        var low: UInt64 = 0
        for digit in integerPart {
            low = low &* 10 &+ UInt64(digit)
        }
        if value.negative {
            low = 0 &- low
        }
        var nanos: Int64 = 0
        for index in 0..<9 {
            nanos = nanos * 10 + Int64(index < fractionPart.count ? fractionPart[index] : 0)
        }
        if value.negative {
            nanos = -nanos
        }
        guard let instant = JavaInstant.ofEpochSecond(Int64(bitPattern: low), nanos) else { throw Failure() }
        return instant
    }
}
