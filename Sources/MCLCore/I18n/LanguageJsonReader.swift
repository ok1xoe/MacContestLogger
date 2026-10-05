/// Reader of the language file `lang_<code>.json` — a rewrite of what Java
/// `LanguageCatalog.load` does with its bytes (Jackson 2.22 `ObjectMapper.readValue(in, Map.class)` + `Map.copyOf`). Measured
/// by the maintainer-only probe (rows `L.load`, `L.limit`); result `nil` = Java returns an empty map.
///
/// - Encoding per `ByteSourceJsonBootstrapper.detectEncoding`: a UTF-8 BOM is skipped, UTF-16 BE/LE (BOM
///   `FE FF`/`FF FE` or a zero byte in the first two) and UTF-32 BE/LE (BOM or zero bytes) are **decoded**
///   (Java reads them, a user file from Notepad can look like that), UCS-4 `2143`/`3412` is an error.
///   UTF-16 is decoded like the Java `InputStreamReader` (replacement: an unpaired high surrogate swallows the following
///   unit too, an unpaired low one and a remainder at the end → `U+FFFD`); UTF-32 like `UTF32Reader` (above U+10FFFF an error,
///   an incomplete quad at the end is ignored). The decoded text goes into the same byte reader as UTF-8 — it is
///   valid, so it behaves like the Java character parser; only key names are not checked in it for surrogate
///   pairs (`ReaderBasedJsonParser`), in UTF-8 they are (`parseEscapedName`).
/// - Syntax, UTF-8, numbers and depth: `WireJsonReader.Parser` (measured with the same Jackson).
/// - Root: an object, or the literal `null` (→ empty map); anything else is an error. **Nothing after the root is read.**
/// - `StreamReadConstraints` limits: key name at most 50 000 bytes of UTF-8 (in UTF-16/32 characters), string
///   at most 20 000 000 UTF-16 units, number 1 000 digits, nesting 1 000.
/// - Duplicate key: the last occurrence wins (even over `null`). If a top-level key ends up
///   `null`, **the whole file is dropped** (`Map.copyOf` → NPE). Non-string values (number, object, array,
///   `true`) Java leaves in the map and `tr()` fails on them (`ClassCastException`); Swift **omits** them
///   — the key then falls back to the Czech original.
/// - Keys are equal by UTF-16 units (`JavaStringKey`; NFC and NFD `é` are two keys). A lone
///   surrogate (Java keeps it) becomes `U+FFFD` in a Swift `String`.
enum LanguageJsonReader {

    private typealias Parser = WireJsonReader.Parser
    private typealias Failure = WireJsonReader.Failure

    static let maxNameLength = 50_000
    static let maxStringLength = 20_000_000

    private enum Value {
        case string(String)
        case null
        case other
    }

    /// Translation map, or `nil` when Java would return an empty map.
    static func read(_ bytes: [UInt8]) -> [JavaStringKey: String]? {
        guard let input = decode(bytes) else { return nil }
        var reader = MapReader(parser: Parser(bytes: input.utf8), utf8: input.isUtf8)
        do {
            return try reader.readRoot()
        } catch {
            return nil
        }
    }

    // MARK: - encoding

    private struct Input {
        let utf8: [UInt8]
        let isUtf8: Bool
    }

    private enum Encoding {
        case utf8(skip: Int)
        case utf16(bigEndian: Bool, skip: Int)
        case utf32(bigEndian: Bool, skip: Int)
    }

    /// `ByteSourceJsonBootstrapper.detectEncoding` (`handleBOM`, `checkUTF32`, `checkUTF16`).
    private static func detect(_ bytes: [UInt8]) -> Encoding? {
        let n: Int = bytes.count
        if n >= 4 {
            let b0 = UInt32(bytes[0]) << 24
            let b1 = UInt32(bytes[1]) << 16
            let b2 = UInt32(bytes[2]) << 8
            let quad: UInt32 = b0 | b1 | b2 | UInt32(bytes[3])
            switch quad {
            case 0x0000_FEFF: return .utf32(bigEndian: true, skip: 4)
            case 0xFFFE_0000: return .utf32(bigEndian: false, skip: 4)
            case 0x0000_FFFE, 0xFEFF_0000: return nil
            default: break
            }
            let msw: UInt32 = quad >> 16
            if msw == 0xFEFF { return .utf16(bigEndian: true, skip: 2) }
            if msw == 0xFFFE { return .utf16(bigEndian: false, skip: 2) }
            if quad >> 8 == 0xEF_BBBF { return .utf8(skip: 3) }
            if quad >> 8 == 0 { return .utf32(bigEndian: true, skip: 0) }
            if quad & 0x00FF_FFFF == 0 { return .utf32(bigEndian: false, skip: 0) }
            if quad & ~UInt32(0x00FF_0000) == 0 || quad & ~UInt32(0x0000_FF00) == 0 { return nil }
            return utf16Check(msw) ?? .utf8(skip: 0)
        }
        if n >= 2 {
            let i16: UInt32 = UInt32(bytes[0]) << 8 | UInt32(bytes[1])
            return utf16Check(i16) ?? .utf8(skip: 0)
        }
        return .utf8(skip: 0)
    }

    private static func utf16Check(_ i16: UInt32) -> Encoding? {
        if i16 & 0xFF00 == 0 { return .utf16(bigEndian: true, skip: 0) }
        if i16 & 0x00FF == 0 { return .utf16(bigEndian: false, skip: 0) }
        return nil
    }

    private static func decode(_ bytes: [UInt8]) -> Input? {
        guard let encoding = detect(bytes) else { return nil }
        switch encoding {
        case .utf8(let skip):
            return Input(utf8: skip == 0 ? bytes : Array(bytes[skip...]), isUtf8: true)
        case .utf16(let bigEndian, let skip):
            let units: [UInt16] = utf16Units(bytes, from: skip, bigEndian: bigEndian)
            return Input(utf8: Array(String(decoding: units, as: UTF16.self).utf8), isUtf8: false)
        case .utf32(let bigEndian, let skip):
            guard let text = utf32Text(bytes, from: skip, bigEndian: bigEndian) else { return nil }
            return Input(utf8: Array(text.utf8), isUtf8: false)
        }
    }

    /// Java decoder `UTF-16BE`/`UTF-16LE` with replacement (`UnicodeDecoder` + `StreamDecoder`): a high surrogate
    /// followed by anything other than a low one = one malformed byte quad → one `U+FFFD`; an unpaired low one →
    /// `U+FFFD`; an incomplete remainder at the end → one `U+FFFD`.
    private static func utf16Units(_ bytes: [UInt8], from start: Int, bigEndian: Bool) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity((bytes.count - start) / 2)
        var i: Int = start
        func unit(_ at: Int) -> UInt16 {
            let a = UInt16(bytes[at])
            let b = UInt16(bytes[at + 1])
            return bigEndian ? a << 8 | b : b << 8 | a
        }
        while bytes.count - i >= 2 {
            let c: UInt16 = unit(i)
            if c < 0xD800 || c > 0xDFFF {
                out.append(c)
                i += 2
                continue
            }
            if c >= 0xDC00 {
                out.append(0xFFFD)
                i += 2
                continue
            }
            guard bytes.count - i >= 4 else { break }
            let low: UInt16 = unit(i + 2)
            if low >= 0xDC00 && low <= 0xDFFF {
                out += [c, low]
            } else {
                out.append(0xFFFD)
            }
            i += 4
        }
        if i < bytes.count {
            out.append(0xFFFD)
        }
        return out
    }

    /// `UTF32Reader`: a code point above U+10FFFF is an error (Java reports it as soon as it reads it — even after the root
    /// in the same batch), an incomplete quad at the end is not read. Java passes a surrogate as a code point as a `char`
    /// unchanged — two in a row (D83D, DE00) thus form a valid character, a lone one stays lone (here `U+FFFD`).
    /// That is why UTF-16 units are composed, not scalars.
    private static func utf32Text(_ bytes: [UInt8], from start: Int, bigEndian: Bool) -> String? {
        var units: [UInt16] = []
        var i: Int = start
        while bytes.count - i >= 4 {
            let b: [UInt32] = bigEndian
                ? [UInt32(bytes[i]), UInt32(bytes[i + 1]), UInt32(bytes[i + 2]), UInt32(bytes[i + 3])]
                : [UInt32(bytes[i + 3]), UInt32(bytes[i + 2]), UInt32(bytes[i + 1]), UInt32(bytes[i])]
            let value: UInt32 = b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
            guard value <= 0x10_FFFF else { return nil }
            if value > 0xFFFF {
                units.append(UInt16(truncatingIfNeeded: 0xD800 + ((value - 0x10000) >> 10)))
                units.append(UInt16(truncatingIfNeeded: 0xDC00 | (value & 0x3FF)))
            } else {
                units.append(UInt16(value))
            }
            i += 4
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - map

    private struct MapReader {
        var parser: Parser
        /// Byte input (`UTF8StreamJsonParser`): name length in bytes, surrogate pairs in names.
        let utf8: Bool

        mutating func readRoot() throws(Failure) -> [JavaStringKey: String] {
            parser.skipWhitespace()
            guard let first = parser.peek() else { throw Failure() }
            if first == 0x6E {
                try parser.literal("null")
                return [:]
            }
            guard first == 0x7B else { throw Failure() }
            let values: [JavaStringKey: Value] = try readObject()
            var out: [JavaStringKey: String] = [:]
            for (key, value) in values {
                switch value {
                case .null:
                    throw Failure()
                case .string(let text):
                    out[key] = text
                case .other:
                    continue
                }
            }
            return out
        }

        /// Top-level object: the last occurrence of a key wins.
        mutating func readObject() throws(Failure) -> [JavaStringKey: Value] {
            try parser.expect(0x7B)
            try parser.enter()
            var values: [JavaStringKey: Value] = [:]
            parser.skipWhitespace()
            if parser.peek() == 0x7D {
                parser.pos += 1
                parser.depth -= 1
                return values
            }
            while true {
                let key: String = try name()
                values[JavaStringKey(key)] = try value()
                if try endOfMember(close: 0x7D) {
                    return values
                }
            }
        }

        /// Key name with a colon after it.
        mutating func name() throws(Failure) -> String {
            parser.skipWhitespace()
            guard parser.peek() == 0x22 else { throw Failure() }
            let start: Int = parser.pos
            let units: [UInt16] = try parser.parseStringUnits(isName: utf8)
            if nameLength(units, rawStart: start + 1, rawEnd: parser.pos - 1) > maxNameLength {
                throw Failure()
            }
            parser.skipWhitespace()
            try parser.expect(0x3A)
            parser.skipWhitespace()
            return String(decoding: units, as: UTF16.self)
        }

        /// Name length for `validateNameLength`: in the byte parser bytes (raw bytes without escapes,
        /// with escapes the UTF-8 encoding of the characters), in the character one UTF-16 units.
        func nameLength(_ units: [UInt16], rawStart: Int, rawEnd: Int) -> Int {
            guard utf8 else { return units.count }
            if !parser.bytes[rawStart..<rawEnd].contains(0x5C) {
                return rawEnd - rawStart
            }
            var length = 0
            for unit in units {
                if unit < 0x80 {
                    length += 1
                } else if unit < 0x800 {
                    length += 2
                } else if unit >= 0xDC00 && unit <= 0xDFFF {
                    length += 1  // second half of a pair: pair = 4 bytes (3 + 1)
                } else {
                    length += 3
                }
            }
            return length
        }

        mutating func value() throws(Failure) -> Value {
            guard let b = parser.peek() else { throw Failure() }
            switch b {
            case 0x22:
                return .string(try string())
            case 0x6E:
                try parser.literal("null")
                return .null
            default:
                try skip()
                return .other
            }
        }

        mutating func string() throws(Failure) -> String {
            let units: [UInt16] = try parser.parseStringUnits()
            if units.count > maxStringLength {
                throw Failure()
            }
            return String(decoding: units, as: UTF16.self)
        }

        /// A value that does not go into the map (number, literal, object, array) — with a full syntax check.
        mutating func skip() throws(Failure) {
            guard let b = parser.peek() else { throw Failure() }
            switch b {
            case 0x22:
                _ = try string()
            case 0x7B:
                parser.pos += 1
                try parser.enter()
                parser.skipWhitespace()
                if parser.peek() == 0x7D {
                    parser.pos += 1
                    parser.depth -= 1
                    return
                }
                while true {
                    _ = try name()
                    try skip()
                    if try endOfMember(close: 0x7D) { return }
                }
            case 0x5B:
                parser.pos += 1
                try parser.enter()
                parser.skipWhitespace()
                if parser.peek() == 0x5D {
                    parser.pos += 1
                    parser.depth -= 1
                    return
                }
                while true {
                    parser.skipWhitespace()
                    try skip()
                    if try endOfMember(close: 0x5D) { return }
                }
            default:
                _ = try parser.scalarToken()
            }
        }

        /// After a value a comma (`false`), or a closing bracket (`true`, pops up one level).
        mutating func endOfMember(close: UInt8) throws(Failure) -> Bool {
            parser.skipWhitespace()
            let c: UInt8 = try parser.next()
            if c == close {
                parser.depth -= 1
                return true
            }
            guard c == 0x2C else { throw Failure() }
            return false
        }
    }
}
