/// Wire JSON reader — a rewrite of what Java `WireJson.fromBytes` does with the message bytes (Jackson 2.22:
/// `ByteSourceJsonBootstrapper`, `UTF8StreamJsonParser`, `BeanDeserializer` over the canonical record
/// constructor, `NumberDeserializers`, `StringDeserializer`, `InstantDeserializer`). Measured by probes and the generator
/// a maintainer-only probe (section `sync.JSONR`); error = `WireJsonFailure` (Java: any exception → wrapped in
/// `SyncSerializationException`).
///
/// Parser:
/// - a UTF-8 BOM at the start is skipped; a start from which Jackson infers UTF-16/UTF-32 (a zero byte
///   among the first four, BOM `FE FF`/`FF FE`) Swift **rejects** (Java would decode the text differently — a divergence,
///   station messages are always UTF-8 starting with `{`).
/// - root: `{` (record), the literal `null` (→ `nil`), anything else is an error; **nothing is read after the root value**
///   (trailing garbage and invalid UTF-8 after `}` pass).
/// - whitespace only space, `\t`, `\n`, `\r`; no comments, apostrophes, unquoted names, trailing commas,
///   `NaN`/`Infinity`, `+1`, leading zeros, `1.`, `.5`.
/// - the literal `true`/`false`/`null` must not continue with a letter, digit, `_`, DEL or a byte ≥ 0x80.
/// - strings: control characters < 0x20 only escaped; escapes `\" \\ \/ \b \f \n \r \t \uXXXX`; UTF-8 **like Jackson**:
///   overlong forms (`C0 80`) pass, encoded surrogates (`ED A0 80`) are an error, four-byte sequences
///   `F0`–`F7` are decomposed by Jackson's formula even above U+10FFFF, `80`–`BF` and `F8`–`FF` at the start are an error.
///   The resulting UTF-16 is converted to `String` — lone surrogates (`\ud800`, a decomposition above U+10FFFF) become
///   U+FFFD (Java keeps them).
/// - numbers: at most 1 000 digits of the integer part (integer), or integer + decimal + exponent (decimal);
///   nesting depth at most 1 000.
///
/// Record: unknown keys are skipped (with full syntax checking); a repeated known key overwrites the value
/// **until all components are seen** — as soon as the record is complete, Jackson builds it and another known key
/// is an error (`No fallback setter/field`), unknown ones are still skipped. Missing components have the default value.
enum WireJsonReader {

    struct Failure: Error {}

    static func decodeRoot(_ bytes: [UInt8], fields: [WireField]) throws(Failure) -> [WireValue]? {
        var parser = Parser(bytes: bytes)
        try parser.skipBomOrRejectEncoding()
        parser.skipWhitespace()
        guard let first = parser.peek() else { throw Failure() }
        if first == 0x7B {
            return try parser.parseRecord(fields)
        }
        if first == 0x6E {
            try parser.literal("null")
            return nil
        }
        throw Failure()
    }

    struct Parser {
        let bytes: [UInt8]
        var pos = 0
        var depth = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        func peek() -> UInt8? {
            pos < bytes.count ? bytes[pos] : nil
        }

        mutating func next() throws(Failure) -> UInt8 {
            guard pos < bytes.count else { throw Failure() }
            let b: UInt8 = bytes[pos]
            pos += 1
            return b
        }

        /// `ByteSourceJsonBootstrapper.detectEncoding`: skip the UTF-8 BOM, reject UTF-16/32.
        mutating func skipBomOrRejectEncoding() throws(Failure) {
            let n: Int = bytes.count
            if n >= 4 {
                let quad: UInt32 = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8
                    | UInt32(bytes[3])
                let utf32: Bool = quad >> 8 == 0 || quad & 0x00FF_FFFF == 0 || quad & ~UInt32(0x00FF_0000) == 0
                    || quad & ~UInt32(0x0000_FF00) == 0
                let bom16: Bool = quad >> 16 == 0xFEFF || quad >> 16 == 0xFFFE
                if quad == 0x0000_FEFF || quad == 0xFFFE_0000 || bom16 || utf32 {
                    throw Failure()
                }
                if quad >> 8 == 0xEF_BBBF {
                    pos = 3
                    return
                }
            }
            if n >= 2 && (bytes[0] == 0 || bytes[1] == 0) {
                throw Failure()
            }
        }

        mutating func skipWhitespace() {
            while pos < bytes.count {
                let b: UInt8 = bytes[pos]
                guard b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D else { return }
                pos += 1
            }
        }

        mutating func expect(_ byte: UInt8) throws(Failure) {
            guard try next() == byte else { throw Failure() }
        }

        mutating func enter() throws(Failure) {
            depth += 1
            if depth > 1_000 {
                throw Failure()
            }
        }

        /// Literal after the first character (`peek`) and the end check (`_matchToken` + `_checkMatchEnd`).
        mutating func literal(_ word: String) throws(Failure) {
            for byte in word.utf8 {
                guard try next() == byte else { throw Failure() }
            }
            guard let b = peek() else { return }
            if b >= 0x80 || b == 0x7F || b == 0x5F {
                throw Failure()
            }
            let digit: Bool = b >= 0x30 && b <= 0x39
            let letter: Bool = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            if digit || letter {
                throw Failure()
            }
        }

        // MARK: - record

        mutating func parseRecord(_ fields: [WireField]) throws(Failure) -> [WireValue] {
            try expect(0x7B)
            try enter()
            var values: [WireValue] = fields.map { WireValue.missing($0.kind) }
            var seen = [Bool](repeating: false, count: fields.count)
            var seenCount = 0
            skipWhitespace()
            if peek() == 0x7D {
                pos += 1
                depth -= 1
                return values
            }
            while true {
                skipWhitespace()
                guard peek() == 0x22 else { throw Failure() }
                let name: [UInt16] = try parseStringUnits(isName: true)
                skipWhitespace()
                try expect(0x3A)
                skipWhitespace()
                if let index = fields.firstIndex(where: { $0.name.utf16.elementsEqual(name) }) {
                    if seenCount == fields.count {
                        throw Failure()
                    }
                    values[index] = try parseValue(fields[index].kind)
                    if !seen[index] {
                        seen[index] = true
                        seenCount += 1
                    }
                } else {
                    try skipValue()
                }
                skipWhitespace()
                let b: UInt8 = try next()
                if b == 0x7D {
                    depth -= 1
                    return values
                }
                guard b == 0x2C else { throw Failure() }
            }
        }

        // MARK: - values

        enum Token {
            case string(String)
            case integer(String)
            case decimal(String)
            case bool(Bool)
            case null
        }

        /// Scalar token (or an error for `[`); `{` is handled by the caller.
        mutating func scalarToken() throws(Failure) -> Token {
            guard let b = peek() else { throw Failure() }
            switch b {
            case 0x22:
                let units: [UInt16] = try parseStringUnits()
                return .string(String(decoding: units, as: UTF16.self))
            case 0x74:
                try literal("true")
                return .bool(true)
            case 0x66:
                try literal("false")
                return .bool(false)
            case 0x6E:
                try literal("null")
                return .null
            case 0x2D, 0x30...0x39:
                return try parseNumber()
            default:
                throw Failure()
            }
        }

        mutating func parseValue(_ kind: WireKind) throws(Failure) -> WireValue {
            if peek() == 0x7B {
                guard case .record(let fields) = kind else {
                    throw Failure()
                }
                return .record(try parseRecord(fields))
            }
            let token: Token = try scalarToken()
            return try WireCoercion.coerce(token, to: kind)
        }

        mutating func skipValue() throws(Failure) {
            guard let b = peek() else { throw Failure() }
            if b == 0x7B {
                pos += 1
                try enter()
                skipWhitespace()
                if peek() == 0x7D {
                    pos += 1
                    depth -= 1
                    return
                }
                while true {
                    skipWhitespace()
                    guard peek() == 0x22 else { throw Failure() }
                    _ = try parseStringUnits(isName: true)
                    skipWhitespace()
                    try expect(0x3A)
                    skipWhitespace()
                    try skipValue()
                    skipWhitespace()
                    let c: UInt8 = try next()
                    if c == 0x7D {
                        depth -= 1
                        return
                    }
                    guard c == 0x2C else { throw Failure() }
                }
            }
            if b == 0x5B {
                pos += 1
                try enter()
                skipWhitespace()
                if peek() == 0x5D {
                    pos += 1
                    depth -= 1
                    return
                }
                while true {
                    skipWhitespace()
                    try skipValue()
                    skipWhitespace()
                    let c: UInt8 = try next()
                    if c == 0x5D {
                        depth -= 1
                        return
                    }
                    guard c == 0x2C else { throw Failure() }
                }
            }
            _ = try scalarToken()
        }

        // MARK: - numbers

        /// `_parsePosNumber`/`_parseNegNumber`: JSON syntax, leading zero forbidden, length limit of 1 000 digits.
        mutating func parseNumber() throws(Failure) -> Token {
            let start: Int = pos
            if peek() == 0x2D {
                pos += 1
            }
            let intStart: Int = pos
            guard let first = peek(), first >= 0x30 && first <= 0x39 else { throw Failure() }
            pos += 1
            if first == 0x30, let b = peek(), b >= 0x30 && b <= 0x39 {
                throw Failure()
            }
            skipDigits()
            let intLength: Int = pos - intStart
            var fracLength = 0
            var expLength = 0
            var isDecimal = false
            if peek() == 0x2E {
                pos += 1
                let fracStart: Int = pos
                skipDigits()
                fracLength = pos - fracStart
                guard fracLength > 0 else { throw Failure() }
                isDecimal = true
            }
            if let e = peek(), e == 0x65 || e == 0x45 {
                pos += 1
                if let sign = peek(), sign == 0x2B || sign == 0x2D {
                    pos += 1
                }
                let expStart: Int = pos
                skipDigits()
                expLength = pos - expStart
                guard expLength > 0 else { throw Failure() }
                isDecimal = true
            }
            let text = String(decoding: bytes[start..<pos], as: UTF8.self)
            if isDecimal {
                guard intLength + fracLength + expLength <= 1_000 else { throw Failure() }
                return .decimal(text)
            }
            guard intLength <= 1_000 else { throw Failure() }
            return .integer(text)
        }

        mutating func skipDigits() {
            while let b = peek(), b >= 0x30 && b <= 0x39 {
                pos += 1
            }
        }

        // MARK: - strings

        /// String in quotes as UTF-16 units (`_finishString2`, `_decodeUtf8_2/3/4`, `_decodeEscaped`).
        /// The key name (`parseEscapedName` + `addName`) has the same UTF-8 rules, but an escaped surrogate must
        /// form a pair (`😀`); a lone one is an error. A key compared with record components is ASCII only,
        /// so how Jackson assembles characters from the key bytes (differently from values) does not matter.
        mutating func parseStringUnits(isName: Bool = false) throws(Failure) -> [UInt16] {
            try expect(0x22)
            var units: [UInt16] = []
            while true {
                let c: UInt8 = try next()
                if c == 0x22 {
                    return units
                }
                if c == 0x5C {
                    let unit: UInt16 = try escaped()
                    if isName && unit >= 0xD800 && unit <= 0xDFFF {
                        guard unit <= 0xDBFF, try next() == 0x5C else { throw Failure() }
                        let low: UInt16 = try escaped()
                        guard low >= 0xDC00 && low <= 0xDFFF else { throw Failure() }
                        units += [unit, low]
                        continue
                    }
                    units.append(unit)
                    continue
                }
                if c < 0x20 {
                    throw Failure()
                }
                if c < 0x80 {
                    units.append(UInt16(c))
                    continue
                }
                try decodeMultiByte(c, into: &units)
            }
        }

        mutating func continuation() throws(Failure) -> Int {
            let d: UInt8 = try next()
            guard d & 0xC0 == 0x80 else { throw Failure() }
            return Int(d & 0x3F)
        }

        mutating func decodeMultiByte(_ lead: UInt8, into units: inout [UInt16]) throws(Failure) {
            if lead & 0xE0 == 0xC0 {
                let value: Int = Int(lead & 0x1F) << 6 | (try continuation())
                units.append(UInt16(value))
            } else if lead & 0xF0 == 0xE0 {
                let c1: Int = try continuation()
                let c2: Int = try continuation()
                let value: Int = Int(lead & 0x0F) << 12 | c1 << 6 | c2
                guard value < 0xD800 || value > 0xDFFF else { throw Failure() }
                units.append(UInt16(value))
            } else if lead & 0xF8 == 0xF0 {
                let c1: Int = try continuation()
                let c2: Int = try continuation()
                let c3: Int = try continuation()
                let value: Int = (Int(lead & 0x07) << 18 | c1 << 12 | c2 << 6 | c3) - 0x10000
                let high: Int = 0xD800 | (value >> 10)
                units.append(UInt16(truncatingIfNeeded: high))
                units.append(UInt16(0xDC00 | (value & 0x3FF)))
            } else {
                throw Failure()
            }
        }

        mutating func escaped() throws(Failure) -> UInt16 {
            let c: UInt8 = try next()
            switch c {
            case 0x22, 0x5C, 0x2F: return UInt16(c)
            case 0x62: return 0x08
            case 0x66: return 0x0C
            case 0x6E: return 0x0A
            case 0x72: return 0x0D
            case 0x74: return 0x09
            case 0x75:
                var value: UInt16 = 0
                for _ in 0..<4 {
                    let h: UInt8 = try next()
                    guard let digit = Self.hexValue(h) else { throw Failure() }
                    value = value << 4 | digit
                }
                return value
            default:
                throw Failure()
            }
        }

        static func hexValue(_ b: UInt8) -> UInt16? {
            switch b {
            case 0x30...0x39: return UInt16(b - 0x30)
            case 0x41...0x46: return UInt16(b - 0x37)
            case 0x61...0x66: return UInt16(b - 0x57)
            default: return nil
            }
        }
    }
}
