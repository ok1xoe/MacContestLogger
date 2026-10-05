import Foundation

/// A port of the subset of Jackson 2.22's `UTF8StreamJsonParser` (with `ByteSourceJsonBootstrapper` and
/// `JsonReadContext`) that `ProfileMerge` needs: the same tokens, the same lazy string decoding, the same
/// locations and the same parse-error texts under Jackson's default features (no comments, no single quotes,
/// no unquoted names, no leading zeros, no `NaN`). The whole input is one buffer.
///
/// Jackson's fast path for `true`/`false`/`null` is taken only when the literal is not at the end of its input
/// buffer (8000 bytes for a file); the fast path accepts a following byte below `'0'` that is still a Java
/// identifier part (`true$`), the slow path rejects it. With one buffer the slow path is reached only at the end
/// of the input, so for files over 8000 bytes such an invalid literal can be judged differently.
final class JacksonUtf8Parser {

    enum Token: Equatable, Sendable {
        case startObject, endObject, startArray, endArray, fieldName
        case string, numberInt, numberFloat, valueTrue, valueFalse, valueNull

        /// `JsonToken.name()`.
        var javaName: String {
            switch self {
            case .startObject: return "START_OBJECT"
            case .endObject: return "END_OBJECT"
            case .startArray: return "START_ARRAY"
            case .endArray: return "END_ARRAY"
            case .fieldName: return "FIELD_NAME"
            case .string: return "VALUE_STRING"
            case .numberInt: return "VALUE_NUMBER_INT"
            case .numberFloat: return "VALUE_NUMBER_FLOAT"
            case .valueTrue: return "VALUE_TRUE"
            case .valueFalse: return "VALUE_FALSE"
            case .valueNull: return "VALUE_NULL"
            }
        }

        /// `JsonToken.asString()` of the structural and literal tokens.
        var literal: String? {
            switch self {
            case .startObject: return "{"
            case .endObject: return "}"
            case .startArray: return "["
            case .endArray: return "]"
            case .valueTrue: return "true"
            case .valueFalse: return "false"
            case .valueNull: return "null"
            default: return nil
            }
        }

        var isScalarValue: Bool {
            switch self {
            case .string, .numberInt, .numberFloat, .valueTrue, .valueFalse, .valueNull: return true
            default: return false
            }
        }
    }

    /// `JsonParser.NumberType` of the current number.
    enum NumberType: Equatable {
        case int, long, bigInteger, double
    }

    private enum ContextKind {
        case root, array, object
    }

    private struct Context {
        var kind: ContextKind
        var index: Int = -1
        var name: String?
        var line: Int
        var column: Int

        var typeDesc: String {
            switch kind {
            case .root: return "root"
            case .array: return "Array"
            case .object: return "Object"
            }
        }

        /// `JsonReadContext.expectComma()` (also advances the index).
        mutating func expectComma() -> Bool {
            index += 1
            return kind != .root && index > 0
        }
    }

    private let bytes: [UInt8]
    private var ptr: Int
    private let end: Int
    private var row: Int = 1
    private var rowStart: Int
    private var tokenRow: Int = 1
    private var tokenCol: Int = 0
    private var nameRow: Int = 1
    private var nameCol: Int = 0
    private var contexts: [Context]
    private var pendingAfterName: Token?
    private var tokenIncomplete: Bool = false
    private var text: String = ""
    private var intLength: Int = 0
    private var negative: Bool = false

    /// The current token (`nil` before the first one and after the end of input).
    private(set) var currentToken: Token?

    init(_ data: Data) {
        let raw: [UInt8] = [UInt8](data)
        let decoded: (bytes: [UInt8], start: Int) = Self.bootstrap(raw)
        bytes = decoded.bytes
        ptr = decoded.start
        rowStart = decoded.start
        end = decoded.bytes.count
        contexts = [Context(kind: .root, line: 1, column: 0)]
    }

    // MARK: - Encoding detection (`ByteSourceJsonBootstrapper`)

    /// The UTF-8 BOM is skipped only with at least four bytes of input; UTF-16 and UTF-32 (by BOM or by zero
    /// bytes) are re-encoded to UTF-8 so that the byte parser can read them (Jackson reads them with its
    /// char-based parser: the columns of non-ASCII content differ).
    private static func bootstrap(_ raw: [UInt8]) -> (bytes: [UInt8], start: Int) {
        if raw.count >= 4 {
            let quad: UInt32 = UInt32(raw[0]) << 24 | UInt32(raw[1]) << 16 | UInt32(raw[2]) << 8 | UInt32(raw[3])
            if quad == 0x0000_FEFF {
                return transcode(raw, from: 4, encoding: .utf32BigEndian)
            }
            if quad == 0xFFFE_0000 {
                return transcode(raw, from: 4, encoding: .utf32LittleEndian)
            }
            if quad >> 16 == 0xFEFF {
                return transcode(raw, from: 2, encoding: .utf16BigEndian)
            }
            if quad >> 16 == 0xFFFE {
                return transcode(raw, from: 2, encoding: .utf16LittleEndian)
            }
            if quad >> 8 == 0xEFBBBF {
                return (raw, 3)
            }
            if quad >> 8 == 0 {
                return transcode(raw, from: 0, encoding: .utf32BigEndian)
            }
            if quad & 0x00FF_FFFF == 0 {
                return transcode(raw, from: 0, encoding: .utf32LittleEndian)
            }
            return utf16ByZeroBytes(raw)
        }
        if raw.count >= 2 {
            return utf16ByZeroBytes(raw)
        }
        return (raw, 0)
    }

    private static func utf16ByZeroBytes(_ raw: [UInt8]) -> (bytes: [UInt8], start: Int) {
        if raw[0] == 0 {
            return transcode(raw, from: 0, encoding: .utf16BigEndian)
        }
        if raw[1] == 0 {
            return transcode(raw, from: 0, encoding: .utf16LittleEndian)
        }
        return (raw, 0)
    }

    private static func transcode(_ raw: [UInt8], from start: Int,
                                  encoding: String.Encoding) -> (bytes: [UInt8], start: Int) {
        let body: Data = Data(raw[start...])
        guard let decoded = String(data: body, encoding: encoding) else { return (raw, 0) }
        return ([UInt8](decoded.utf8), 0)
    }

    // MARK: - Locations

    /// `currentLocation()`: the position after the last consumed byte.
    var currentLocation: JacksonLocation {
        JacksonLocation(line: row, column: ptr - rowStart + 1)
    }

    /// `_currentLocationMinusOne()`: the position of the last consumed byte.
    private var locationMinusOne: JacksonLocation {
        JacksonLocation(line: row, column: ptr - rowStart)
    }

    /// `currentTokenLocation()`: the start of the current token.
    var tokenLocation: JacksonLocation {
        if currentToken == .fieldName {
            return JacksonLocation(line: nameRow, column: nameCol)
        }
        return JacksonLocation(line: tokenRow, column: tokenCol)
    }

    /// The current field name (`currentName()`).
    var currentName: String? {
        contexts[contexts.count - 1].name
    }

    // MARK: - Tokens

    /// `nextFieldName()`: the next token, returning its name when it is a field name.
    func nextFieldName() throws(JacksonFailure) -> String? {
        let token: Token? = try nextToken()
        return token == .fieldName ? currentName : nil
    }

    /// `nextToken()`.
    @discardableResult
    func nextToken() throws(JacksonFailure) -> Token? {
        if currentToken == .fieldName {
            return nextAfterName()
        }
        if tokenIncomplete {
            try finishString(store: false)
        }
        var byte: Int = try skipWhitespaceOrEnd()
        if byte < 0 {
            currentToken = nil
            return nil
        }
        if byte == 0x5D {
            try closeScope(array: true)
            return update(.endArray)
        }
        if byte == 0x7D {
            try closeScope(array: false)
            return update(.endObject)
        }
        if contexts[contexts.count - 1].expectComma() {
            if byte != 0x2C {
                let desc: String = contexts[contexts.count - 1].typeDesc
                throw unexpectedChar(byte, "was expecting comma to separate " + desc + " entries")
            }
            byte = try skipWhitespace()
        }
        if contexts[contexts.count - 1].kind != .object {
            updateLocation()
            return try nextTokenNotInObject(byte)
        }
        nameRow = row
        nameCol = ptr - rowStart
        let name: String = try parseName(byte)
        contexts[contexts.count - 1].name = name
        currentToken = .fieldName
        byte = try skipColon()
        updateLocation()
        pendingAfterName = try valueAfterName(byte)
        return currentToken
    }

    private func update(_ token: Token) -> Token {
        currentToken = token
        return token
    }

    private func updateLocation() {
        tokenRow = row
        tokenCol = ptr - rowStart
    }

    private func nextAfterName() -> Token? {
        let token: Token? = pendingAfterName
        pendingAfterName = nil
        if token == .startArray {
            contexts.append(Context(kind: .array, line: tokenRow, column: tokenCol))
        } else if token == .startObject {
            contexts.append(Context(kind: .object, line: tokenRow, column: tokenCol))
        }
        currentToken = token
        return token
    }

    private func valueAfterName(_ byte: Int) throws(JacksonFailure) -> Token {
        switch byte {
        case 0x22:
            tokenIncomplete = true
            return .string
        case 0x2D:
            return try parseSignedNumber(negative: true)
        case 0x2B:
            return try handleUnexpectedValue(byte)
        case 0x2E:
            return try handleUnexpectedValue(byte)
        case 0x30...0x39:
            return try parseUnsignedNumber(byte)
        case 0x66:
            try matchLiteral("false")
            return .valueFalse
        case 0x6E:
            try matchLiteral("null")
            return .valueNull
        case 0x74:
            try matchLiteral("true")
            return .valueTrue
        case 0x5B:
            return .startArray
        case 0x7B:
            return .startObject
        default:
            return try handleUnexpectedValue(byte)
        }
    }

    private func nextTokenNotInObject(_ byte: Int) throws(JacksonFailure) -> Token {
        switch byte {
        case 0x22:
            tokenIncomplete = true
            return update(.string)
        case 0x5B:
            contexts.append(Context(kind: .array, line: tokenRow, column: tokenCol))
            return update(.startArray)
        case 0x7B:
            contexts.append(Context(kind: .object, line: tokenRow, column: tokenCol))
            return update(.startObject)
        case 0x74:
            try matchLiteral("true")
            return update(.valueTrue)
        case 0x66:
            try matchLiteral("false")
            return update(.valueFalse)
        case 0x6E:
            try matchLiteral("null")
            return update(.valueNull)
        case 0x2D:
            return update(try parseSignedNumber(negative: true))
        case 0x30...0x39:
            return update(try parseUnsignedNumber(byte))
        default:
            return update(try handleUnexpectedValue(byte))
        }
    }

    private func closeScope(array: Bool) throws(JacksonFailure) {
        updateLocation()
        let context: Context = contexts[contexts.count - 1]
        let matches: Bool = array ? context.kind == .array : context.kind == .object
        if !matches {
            let actual: Character = array ? "]" : "}"
            if context.kind == .root {
                let scope: String = array ? "Array" : "Object"
                throw readError("Unexpected close marker '\(actual)': no open \(scope) to close", locationMinusOne)
            }
            let expected: Character = array ? "}" : "]"
            let start: String = JacksonLocation(line: context.line, column: context.column).description
            let text: String = "Unexpected close marker '\(actual)': expected '\(expected)' (for "
                + context.typeDesc + " starting at " + start + ")"
            throw readError(text, locationMinusOne)
        }
        contexts.removeLast()
    }

    // MARK: - Text and numbers

    /// `getText()`: finishes a pending string.
    func getText() throws(JacksonFailure) -> String? {
        guard let token = currentToken else { return nil }
        switch token {
        case .string:
            if tokenIncomplete {
                tokenIncomplete = false
                try finishString(store: true)
            }
            return text
        case .fieldName:
            return currentName
        case .numberInt, .numberFloat:
            return text
        default:
            return token.literal
        }
    }

    /// `getValueAsString()`: text of strings, names and scalars, `nil` otherwise.
    func valueAsString() throws(JacksonFailure) -> String? {
        guard let token = currentToken else { return nil }
        switch token {
        case .string, .fieldName, .numberInt, .numberFloat, .valueTrue, .valueFalse:
            return try getText()
        default:
            return nil
        }
    }

    /// `getNumberType()` (integers: up to 9 digits `int`, 10 digits in range `int`, up to 19 digits in range
    /// `long`, otherwise `BigInteger`; fractions always `double`).
    var numberType: NumberType {
        if currentToken == .numberFloat {
            return .double
        }
        if intLength <= 9 {
            return .int
        }
        guard let value = Int64(text) else { return .bigInteger }
        return Int32(exactly: value) != nil ? .int : .long
    }

    /// `getIntValue()` / `getValueAsInt()` of a number token.
    func intValue() throws(JacksonFailure) -> Int32 {
        if currentToken == .numberFloat {
            let value: Double = doubleValue
            guard value >= -2_147_483_648.0, value <= 2_147_483_647.0 else { throw overflow("int") }
            return Int32(value)
        }
        guard let value = Int64(text), let small = Int32(exactly: value) else { throw overflow("int") }
        return small
    }

    /// `getLongValue()` / `getValueAsLong()` of a number token.
    func longValue() throws(JacksonFailure) -> Int64 {
        if currentToken == .numberFloat {
            let value: Double = doubleValue
            guard value >= -9.223_372_036_854_775_808e18, value <= 9.223_372_036_854_775_807e18 else {
                throw overflow("long")
            }
            return value >= 9.223_372_036_854_775_807e18 ? Int64.max : Int64(value)
        }
        guard let value = Int64(text) else { throw overflow("long") }
        return value
    }

    /// `getDoubleValue()` of a number token.
    var doubleValue: Double {
        Double(text) ?? 0
    }

    private func overflow(_ type: String) -> JacksonFailure {
        let range: String = type == "int"
            ? "(-2147483648 - 2147483647)"
            : "(-9223372036854775808 - 9223372036854775807)"
        let message: String = "Numeric value (" + longIntegerDesc(text) + ") out of range of " + type + " " + range
        return JacksonFailure(javaClass: JacksonFailure.inputCoercionException, originalMessage: message,
                              location: currentLocation)
    }

    private func longIntegerDesc(_ raw: String) -> String {
        var length: Int = raw.utf16.count
        if length < 1000 {
            return raw
        }
        if raw.hasPrefix("-") {
            length -= 1
        }
        return "[Integer with \(length) digits]"
    }

    // MARK: - Whitespace

    private func skipWhitespaceOrEnd() throws(JacksonFailure) -> Int {
        while ptr < end {
            let byte: Int = Int(bytes[ptr])
            ptr += 1
            if byte > 0x20 {
                if byte == 0x2F {
                    throw unexpectedChar(0x2F, Self.commentHint)
                }
                return byte
            }
            try whitespace(byte)
        }
        if contexts[contexts.count - 1].kind != .root {
            let context: Context = contexts[contexts.count - 1]
            let marker: String = context.kind == .array ? "Array" : "Object"
            let start: String = JacksonLocation(line: context.line, column: context.column).description
            throw eofError(": expected close marker for " + marker + " (start marker at " + start + ")")
        }
        return -1
    }

    private func skipWhitespace() throws(JacksonFailure) -> Int {
        while ptr < end {
            let byte: Int = Int(bytes[ptr])
            ptr += 1
            if byte > 0x20 {
                if byte == 0x2F {
                    throw unexpectedChar(0x2F, Self.commentHint)
                }
                return byte
            }
            try whitespace(byte)
        }
        let desc: String = contexts[contexts.count - 1].typeDesc
        throw readError("Unexpected end-of-input within/between " + desc + " entries", currentLocation)
    }

    private func skipColon() throws(JacksonFailure) -> Int {
        var gotColon: Bool = false
        while ptr < end {
            let byte: Int = Int(bytes[ptr])
            ptr += 1
            if byte > 0x20 {
                if byte == 0x2F {
                    throw unexpectedChar(0x2F, Self.commentHint)
                }
                if gotColon {
                    return byte
                }
                if byte != 0x3A {
                    throw unexpectedChar(byte, "was expecting a colon to separate field name and value")
                }
                gotColon = true
            } else {
                try whitespace(byte)
            }
        }
        let desc: String = contexts[contexts.count - 1].typeDesc
        throw eofError(" within/between " + desc + " entries")
    }

    private static let commentHint: String =
        "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)"

    private func whitespace(_ byte: Int) throws(JacksonFailure) {
        switch byte {
        case 0x20, 0x09:
            return
        case 0x0A:
            row += 1
            rowStart = ptr
        case 0x0D:
            if ptr < end, bytes[ptr] == 0x0A {
                ptr += 1
            }
            row += 1
            rowStart = ptr
        default:
            var message: String = "Illegal character (" + Self.charDesc(byte)
                + "): only regular white space (\\r, \\n, \\t) is allowed between tokens"
            if byte == 0x1E {
                message += " (consider enabling `JsonReadFeature.ALLOW_RS_CONTROL_CHAR` to allow use of"
                    + " Record Separators (\\u001E))"
            }
            throw readError(message, currentLocation)
        }
    }

    // MARK: - Names

    private func parseName(_ first: Int) throws(JacksonFailure) -> String {
        if first != 0x22 {
            let char: Int = try decodeCharForError(first) & 0xFFFF
            throw unexpectedChar(char, "was expecting double-quote to start field name")
        }
        var nameBytes: [UInt8] = []
        while true {
            guard ptr < end else { throw eofError(" in field name") }
            var unit: Int = Int(bytes[ptr])
            ptr += 1
            if unit == 0x22 {
                break
            }
            if unit < 0x20 {
                throw unquotedControl(unit, "name")
            }
            if unit != 0x5C {
                nameBytes.append(UInt8(unit))
                continue
            }
            unit = try decodeEscaped()
            if unit >= 0xD800, unit <= 0xDBFF {
                unit = try lowSurrogate(after: unit)
            } else if unit >= 0xDC00, unit <= 0xDFFF {
                throw readError("Unexpected low surrogate in field name: 0x" + Self.hex(unit), currentLocation)
            }
            Self.appendUtf8(unit, to: &nameBytes)
        }
        return try decodeName(nameBytes)
    }

    private func lowSurrogate(after high: Int) throws(JacksonFailure) -> Int {
        guard ptr < end else { throw eofError(" in field name") }
        if bytes[ptr] != 0x5C {
            let got: String = Self.hex(Int(bytes[ptr]))
            throw readError("Broken surrogate pair in field name: expected '\\' to start low surrogate, got 0x"
                            + got, currentLocation)
        }
        ptr += 1
        let low: Int = try decodeEscaped()
        if low < 0xDC00 || low > 0xDFFF {
            let got: String = String(format: "%04X", low)
            throw readError("Broken surrogate pair in field name: expected low surrogate, got 0x" + got,
                            currentLocation)
        }
        return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
    }

    private static func appendUtf8(_ scalar: Int, to out: inout [UInt8]) {
        if scalar < 0x80 {
            out.append(UInt8(scalar))
        } else if scalar < 0x800 {
            out.append(UInt8(0xC0 | (scalar >> 6)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        } else if scalar < 0x10000 {
            out.append(UInt8(0xE0 | (scalar >> 12)))
            out.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        } else {
            out.append(UInt8(truncatingIfNeeded: 0xF0 | (scalar >> 18)))
            out.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
            out.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        }
    }

    /// `addName()`: UTF-8 decoding of the collected name bytes, with Jackson's quad arithmetic for the error texts
    /// (a continuation byte is reported together with the higher bytes of its 32-bit quad, sign-extended).
    private func decodeName(_ raw: [UInt8]) throws(JacksonFailure) -> String {
        let length: Int = raw.count
        var units: [UInt16] = []
        var index: Int = 0
        func shifted(_ at: Int) -> Int32 {
            var quad: UInt32 = 0
            let base: Int = (at >> 2) << 2
            for offset in 0..<4 {
                let position: Int = base + offset
                let byte: UInt32 = position < length ? UInt32(raw[position]) : 0
                quad = quad << 8 | byte
            }
            let shift: UInt32 = UInt32((3 - (at & 3)) << 3)
            return Int32(bitPattern: quad) >> shift
        }
        while index < length {
            var char: Int = Int(raw[index])
            index += 1
            if char > 127 {
                var needed: Int
                if char & 0xE0 == 0xC0 {
                    char &= 0x1F
                    needed = 1
                } else if char & 0xF0 == 0xE0 {
                    char &= 0x0F
                    needed = 2
                } else if char & 0xF8 == 0xF0 {
                    char &= 0x07
                    needed = 3
                } else {
                    throw readError("Invalid UTF-8 start byte 0x" + Self.hex(char), currentLocation)
                }
                if index + needed > length {
                    throw eofError(" in field name")
                }
                var next: Int32 = shifted(index)
                index += 1
                if next & 0xC0 != 0x80 {
                    throw invalidMiddle(Int(next))
                }
                char = (char << 6) | Int(next & 0x3F)
                if needed > 1 {
                    next = shifted(index)
                    index += 1
                    if next & 0xC0 != 0x80 {
                        throw invalidMiddle(Int(next))
                    }
                    char = (char << 6) | Int(next & 0x3F)
                    if needed == 2 {
                        if char >= 0xD800, char <= 0xDFFF {
                            throw surrogate(char)
                        }
                    } else {
                        next = shifted(index)
                        index += 1
                        if next & 0xC0 != 0x80 {
                            throw invalidMiddle(Int(next & 0xFF))
                        }
                        char = (char << 6) | Int(next & 0x3F)
                    }
                }
                if needed > 2 {
                    char -= 0x10000
                    units.append(UInt16(truncatingIfNeeded: 0xD800 + (char >> 10)))
                    char = 0xDC00 | (char & 0x03FF)
                }
            }
            units.append(UInt16(truncatingIfNeeded: char))
        }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: - Strings

    /// `_finishString2` (`store`) / `_skipString`: UTF-8 decoding with Jackson's checks (no check of overlong
    /// forms; only decoding, not skipping, rejects an encoded surrogate).
    private func finishString(store: Bool) throws(JacksonFailure) {
        tokenIncomplete = false
        var units: [UInt16] = []
        while true {
            guard ptr < end else { throw invalidEof() }
            let byte: Int = Int(bytes[ptr])
            ptr += 1
            if byte == 0x22 {
                break
            }
            if byte == 0x5C {
                let unit: Int = try decodeEscaped()
                if store {
                    units.append(UInt16(truncatingIfNeeded: unit))
                }
                continue
            }
            if byte < 0x20 {
                throw unquotedControl(byte, "string value")
            }
            if byte < 0x80 {
                if store {
                    units.append(UInt16(byte))
                }
                continue
            }
            try decodeMultiByte(byte, store: store, into: &units)
        }
        if store {
            text = String(decoding: units, as: UTF16.self)
        }
    }

    private func decodeMultiByte(_ lead: Int, store: Bool, into units: inout [UInt16]) throws(JacksonFailure) {
        let needed: Int
        var char: Int
        if lead & 0xE0 == 0xC0 {
            needed = 1
            char = lead & 0x1F
        } else if lead & 0xF0 == 0xE0 {
            needed = 2
            char = lead & 0x0F
        } else if lead & 0xF8 == 0xF0 {
            needed = 3
            char = lead & 0x07
        } else {
            throw readError("Invalid UTF-8 start byte 0x" + Self.hex(lead), currentLocation)
        }
        for _ in 0..<needed {
            guard ptr < end else { throw invalidEof() }
            let next: Int = Int(bytes[ptr])
            ptr += 1
            if next & 0xC0 != 0x80 {
                throw invalidMiddle(next)
            }
            char = (char << 6) | (next & 0x3F)
        }
        guard store else { return }
        if needed == 2, char >= 0xD800, char <= 0xDFFF {
            throw surrogate(char)
        }
        if needed == 3 {
            let value: Int = char - 0x10000
            units.append(UInt16(truncatingIfNeeded: 0xD800 | (value >> 10)))
            units.append(UInt16(truncatingIfNeeded: 0xDC00 | (value & 0x3FF)))
        } else {
            units.append(UInt16(truncatingIfNeeded: char))
        }
    }

    /// `_decodeEscaped()`: the UTF-16 unit of an escape after the backslash.
    private func decodeEscaped() throws(JacksonFailure) -> Int {
        guard ptr < end else {
            throw JacksonFailure(javaClass: JacksonFailure.eofException,
                                 originalMessage: "Unexpected end-of-input in character escape sequence",
                                 location: currentLocation)
        }
        let byte: Int = Int(bytes[ptr])
        ptr += 1
        switch byte {
        case 0x62: return 0x08
        case 0x74: return 0x09
        case 0x6E: return 0x0A
        case 0x66: return 0x0C
        case 0x72: return 0x0D
        case 0x22, 0x2F, 0x5C: return byte
        case 0x75: break
        default:
            let char: Int = try decodeCharForError(byte) & 0xFFFF
            throw readError("Unrecognized character escape " + Self.charDesc(char), locationMinusOne)
        }
        var value: Int = 0
        for _ in 0..<4 {
            guard ptr < end else {
                throw JacksonFailure(javaClass: JacksonFailure.eofException,
                                     originalMessage: "Unexpected end-of-input in character escape sequence",
                                     location: currentLocation)
            }
            let digitByte: Int = Int(bytes[ptr])
            ptr += 1
            guard let digit = Self.hexValue(digitByte) else {
                throw unexpectedChar(digitByte, "expected a hex-digit for character escape sequence")
            }
            value = (value << 4) | digit
        }
        return value
    }

    private static func hexValue(_ byte: Int) -> Int? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x37
        case 0x61...0x66: return byte - 0x57
        default: return nil
        }
    }

    /// `_decodeCharForError()`: the code point starting with `first` (multi-byte UTF-8 is consumed).
    private func decodeCharForError(_ first: Int) throws(JacksonFailure) -> Int {
        var char: Int = first & 0xFF
        guard char > 0x7F else { return char }
        let needed: Int
        if char & 0xE0 == 0xC0 {
            char &= 0x1F
            needed = 1
        } else if char & 0xF0 == 0xE0 {
            char &= 0x0F
            needed = 2
        } else if char & 0xF8 == 0xF0 {
            char &= 0x07
            needed = 3
        } else {
            throw readError("Invalid UTF-8 start byte 0x" + Self.hex(char), currentLocation)
        }
        for _ in 0..<needed {
            guard ptr < end else { throw invalidEof() }
            let next: Int = Int(bytes[ptr])
            ptr += 1
            if next & 0xC0 != 0x80 {
                throw invalidMiddle(next)
            }
            char = (char << 6) | (next & 0x3F)
        }
        return char
    }

    // MARK: - Literals and numbers

    /// `_matchTrue`/`_matchFalse`/`_matchNull` (first letter already consumed).
    private func matchLiteral(_ literal: String) throws(JacksonFailure) {
        let letters: [UInt8] = Array(literal.utf8)
        let start: Int = ptr
        if start + letters.count - 1 < end {
            var matches: Bool = true
            for offset in 1..<letters.count where bytes[start + offset - 1] != letters[offset] {
                matches = false
                break
            }
            if matches {
                let after: Int = Int(bytes[start + letters.count - 1])
                if after < 0x30 || after | 0x20 == 0x7D {
                    ptr = start + letters.count - 1
                    return
                }
            }
        }
        try matchToken(letters, from: 1)
    }

    /// `_matchToken2(matchStr, i)`.
    private func matchToken(_ letters: [UInt8], from first: Int) throws(JacksonFailure) {
        var index: Int = first
        while index < letters.count {
            if ptr >= end || bytes[ptr] != letters[index] {
                let matched: String = String(decoding: letters[0..<index], as: UTF8.self)
                throw try invalidToken(matched)
            }
            ptr += 1
            index += 1
        }
        guard ptr < end else { return }
        let next: Int = Int(bytes[ptr])
        if next >= 0x30, next != 0x5D, next != 0x7D {
            let char: Int = try decodeCharForError(next) & 0xFFFF
            if Self.isJavaIdentifierPart(char) {
                let matched: String = String(decoding: letters, as: UTF8.self)
                throw try invalidToken(matched)
            }
        }
    }

    private func parseUnsignedNumber(_ first: Int) throws(JacksonFailure) -> Token {
        negative = false
        var digits: [UInt8] = []
        var char: Int = first
        if char == 0x30 {
            char = try verifyNoLeadingZeroes()
        }
        digits.append(UInt8(char))
        return try parseNumberRest(digits)
    }

    private func parseSignedNumber(negative isNegative: Bool) throws(JacksonFailure) -> Token {
        negative = isNegative
        var digits: [UInt8] = [0x2D]
        guard ptr < end else { throw invalidEof() }
        var char: Int = Int(bytes[ptr])
        ptr += 1
        if char <= 0x30 {
            if char != 0x30 {
                if char == 0x2E {
                    return try handleUnexpectedValue(0x2E)
                }
                return try handleInvalidNumberStart(char, negative: true)
            }
            char = try verifyNoLeadingZeroes()
        } else if char > 0x39 {
            return try handleInvalidNumberStart(char, negative: true)
        }
        digits.append(UInt8(char))
        return try parseNumberRest(digits)
    }

    private func parseNumberRest(_ start: [UInt8]) throws(JacksonFailure) -> Token {
        var digits: [UInt8] = start
        var intLen: Int = 1
        while true {
            guard ptr < end else {
                return try resetInt(digits, intLen)
            }
            let char: Int = Int(bytes[ptr])
            ptr += 1
            if char < 0x30 || char > 0x39 {
                if char == 0x2E || char | 0x20 == 0x65 {
                    return try parseFloat(digits, char)
                }
                ptr -= 1
                try verifyRootSpace()
                return try resetInt(digits, intLen)
            }
            intLen += 1
            digits.append(UInt8(char))
        }
    }

    private func resetInt(_ digits: [UInt8], _ intLen: Int) throws(JacksonFailure) -> Token {
        if let failure = JacksonFailure.numberLength(intLen) {
            throw failure
        }
        text = String(decoding: digits, as: UTF8.self)
        intLength = intLen
        return .numberInt
    }

    private func verifyNoLeadingZeroes() throws(JacksonFailure) -> Int {
        guard ptr < end else { return 0x30 }
        let next: Int = Int(bytes[ptr])
        if next < 0x30 || next > 0x39 {
            return 0x30
        }
        throw readError("Invalid numeric value: Leading zeroes not allowed", currentLocation)
    }

    private func parseFloat(_ start: [UInt8], _ first: Int) throws(JacksonFailure) -> Token {
        var digits: [UInt8] = start
        var char: Int = first
        var eof: Bool = false
        if char == 0x2E {
            digits.append(0x2E)
            var fraction: Int = 0
            while true {
                guard ptr < end else {
                    eof = true
                    break
                }
                char = Int(bytes[ptr])
                ptr += 1
                if char < 0x30 || char > 0x39 {
                    break
                }
                fraction += 1
                digits.append(UInt8(char))
            }
            if fraction == 0 {
                throw unexpectedNumberChar(char, "Decimal point not followed by a digit")
            }
        }
        if char | 0x20 == 0x65 {
            digits.append(UInt8(char))
            guard ptr < end else { throw invalidEof() }
            char = Int(bytes[ptr])
            ptr += 1
            if char == 0x2D || char == 0x2B {
                digits.append(UInt8(char))
                guard ptr < end else { throw invalidEof() }
                char = Int(bytes[ptr])
                ptr += 1
            }
            var exponent: Int = 0
            while char >= 0x30, char <= 0x39 {
                exponent += 1
                digits.append(UInt8(char))
                guard ptr < end else {
                    eof = true
                    break
                }
                char = Int(bytes[ptr])
                ptr += 1
            }
            if exponent == 0 {
                throw unexpectedNumberChar(char, "Exponent indicator not followed by a digit")
            }
        }
        if !eof {
            ptr -= 1
            try verifyRootSpace()
        }
        // `resetFloat`: integer, fraction and exponent digits (the text without sign, point and `e`/sign).
        let signs: Int = digits.filter { $0 == 0x2D || $0 == 0x2B || $0 == 0x2E || $0 | 0x20 == 0x65 }.count
        if let failure = JacksonFailure.numberLength(digits.count - signs) {
            throw failure
        }
        text = String(decoding: digits, as: UTF8.self)
        intLength = 0
        return .numberFloat
    }

    /// `_verifyRootSpace`: a root-level number must be followed by white space (the caller pushed it back).
    private func verifyRootSpace() throws(JacksonFailure) {
        guard contexts[contexts.count - 1].kind == .root else { return }
        let char: Int = Int(bytes[ptr])
        ptr += 1
        switch char {
        case 0x20, 0x09:
            return
        case 0x0D:
            ptr -= 1
        case 0x0A:
            row += 1
            rowStart = ptr
        default:
            throw unexpectedChar(char, "Expected space separating root-level values")
        }
    }

    private func handleInvalidNumberStart(_ first: Int, negative isNegative: Bool) throws(JacksonFailure) -> Token {
        var char: Int = first
        if char == 0x49 {
            guard ptr < end else {
                throw JacksonFailure(javaClass: JacksonFailure.eofException,
                                     originalMessage: "Unexpected end-of-input in a Number value",
                                     location: currentLocation)
            }
            char = Int(Int8(bitPattern: bytes[ptr]))
            ptr += 1
            var match: [UInt8] = []
            if char == 0x4E {
                match = Array((isNegative ? "-INF" : "+INF").utf8)
            } else if char == 0x6E {
                match = Array((isNegative ? "-Infinity" : "+Infinity").utf8)
            }
            if !match.isEmpty {
                try matchToken(match, from: 3)
                let token: String = String(decoding: match, as: UTF8.self)
                throw readError("Non-standard token '" + token
                                + "': enable `JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS` to allow", currentLocation)
            }
        }
        if !isNegative {
            // Only reached through a leading plus sign (`hasSign`), which the default features reject.
            throw unexpectedNumberChar(0x2B, "JSON spec does not allow numbers to have plus signs: enable"
                                       + " `JsonReadFeature.ALLOW_LEADING_PLUS_SIGN_FOR_NUMBERS` to allow")
        }
        throw unexpectedNumberChar(char, "expected digit (0-9) to follow minus sign, for valid numeric value")
    }

    /// `_handleUnexpectedValue`: a byte that cannot start a value.
    private func handleUnexpectedValue(_ char: Int) throws(JacksonFailure) -> Token {
        let context: Context = contexts[contexts.count - 1]
        switch char {
        case 0x5D where context.kind == .array, 0x2C, 0x7D:
            throw unexpectedChar(char, "expected a value")
        case 0x4E:
            try matchToken(Array("NaN".utf8), from: 1)
            throw readError("Non-standard token 'NaN': enable `JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS` to allow",
                            currentLocation)
        case 0x49:
            try matchToken(Array("Infinity".utf8), from: 1)
            throw readError("Non-standard token 'Infinity': enable `JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS`"
                            + " to allow", currentLocation)
        case 0x2B:
            guard ptr < end else {
                throw JacksonFailure(javaClass: JacksonFailure.eofException,
                                     originalMessage: "Unexpected end-of-input in a Number value",
                                     location: currentLocation)
            }
            let next: Int = Int(bytes[ptr])
            ptr += 1
            return try handleInvalidNumberStart(next, negative: false)
        default:
            break
        }
        if Self.isJavaIdentifierStart(char) {
            let first: String = Self.charString(char & 0xFFFF)
            throw try invalidToken(first, consumed: 1)
        }
        throw unexpectedChar(char, "expected a valid value (JSON String, Number, Array, Object or token 'null',"
                             + " 'true' or 'false')")
    }

    // MARK: - Errors

    /// `_reportInvalidToken(matchedPart)`: the token is extended by the following Java identifier characters.
    private func invalidToken(_ matched: String, consumed: Int? = nil) throws(JacksonFailure) -> JacksonFailure {
        let length: Int = consumed ?? matched.utf16.count
        let start: JacksonLocation = JacksonLocation(line: row, column: ptr - length - rowStart + 1)
        var token: String = matched
        var count: Int = matched.utf16.count
        while ptr < end {
            let byte: Int = Int(bytes[ptr])
            ptr += 1
            let char: Int = try decodeCharForError(byte) & 0xFFFF
            if !Self.isJavaIdentifierPart(char) {
                break
            }
            token += Self.charString(char)
            count += 1
            if count >= 256 {
                token += "..."
                break
            }
        }
        let message: String = "Unrecognized token '" + token
            + "': was expecting (JSON String, Number, Array, Object or token 'null', 'true' or 'false')"
        return readError(message, start)
    }

    private func unexpectedChar(_ char: Int, _ comment: String) -> JacksonFailure {
        readError("Unexpected character (" + Self.charDesc(char) + "): " + comment, locationMinusOne)
    }

    private func unexpectedNumberChar(_ char: Int, _ comment: String) -> JacksonFailure {
        readError("Unexpected character (" + Self.charDesc(char) + ") in numeric value: " + comment, locationMinusOne)
    }

    private func unquotedControl(_ char: Int, _ context: String) -> JacksonFailure {
        readError("Illegal unquoted character (" + Self.charDesc(char)
                  + "): has to be escaped using backslash to be included in " + context, locationMinusOne)
    }

    private func invalidMiddle(_ value: Int) -> JacksonFailure {
        readError("Invalid UTF-8 middle byte 0x" + Self.hex(value), currentLocation)
    }

    private func surrogate(_ value: Int) -> JacksonFailure {
        readError("Invalid UTF-8: Illegal surrogate character 0x" + Self.hex(value), currentLocation)
    }

    /// `_reportInvalidEOF()`: " in " + the current token.
    private func invalidEof() -> JacksonFailure {
        eofError(" in " + (currentToken?.javaName ?? "null"))
    }

    private func eofError(_ message: String) -> JacksonFailure {
        JacksonFailure(javaClass: JacksonFailure.eofException, originalMessage: "Unexpected end-of-input" + message,
                       location: currentLocation)
    }

    private func readError(_ message: String, _ location: JacksonLocation) -> JacksonFailure {
        JacksonFailure(javaClass: JacksonFailure.parseException, originalMessage: message, location: location)
    }

    /// `ParserMinimalBase._getCharDesc(int)`.
    static func charDesc(_ code: Int) -> String {
        let char: Int = code & 0xFFFF
        if char < 0x20 || (char >= 0x7F && char <= 0x9F) {
            return "(CTRL-CHAR, code " + String(code) + ")"
        }
        if code > 255 {
            return "'" + charString(char) + "' (code " + String(code) + " / 0x" + hex(code) + ")"
        }
        return "'" + charString(char) + "' (code " + String(code) + ")"
    }

    /// One Java `char` as a string (a lone surrogate becomes U+FFFD).
    static func charString(_ unit: Int) -> String {
        String(decoding: [UInt16(truncatingIfNeeded: unit)], as: UTF16.self)
    }

    /// `Integer.toHexString`.
    static func hex(_ value: Int) -> String {
        String(UInt32(truncatingIfNeeded: value), radix: 16)
    }

    /// `Character.isJavaIdentifierStart(int)`.
    static func isJavaIdentifierStart(_ code: Int) -> Bool {
        guard let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: code)) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .letterNumber, .currencySymbol, .connectorPunctuation:
            return true
        default:
            return false
        }
    }

    /// `Character.isJavaIdentifierPart(char)`.
    static func isJavaIdentifierPart(_ code: Int) -> Bool {
        if isJavaIdentifierStart(code) {
            return true
        }
        if (0x00...0x08).contains(code) || (0x0E...0x1B).contains(code) || (0x7F...0x9F).contains(code) {
            return true
        }
        guard let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: code)) else { return false }
        switch scalar.properties.generalCategory {
        case .decimalNumber, .spacingMark, .nonspacingMark, .format:
            return true
        default:
            return false
        }
    }
}
