import Foundation

/// `JavaProperties.load` read error — Java `IllegalArgumentException`
/// from `Properties.load` (a broken `\uXXXX` escape). The text is Java's verbatim.
public struct JavaPropertiesError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// A file in the `java.util.Properties` (JDK 21) format, as read by
/// `Properties.load(InputStream)` and written by `Properties.store(OutputStream, …)`.
///
/// It serves the manifest of `DefinitionUpdater`: Java v1.1.1 and the Swift version share
/// the same data directory, so a manifest written by one must be readable by the other with the same
/// pairs. Keys and values are held as **UTF-16 units** — keys are compared like
/// Java `String.equals` (NFC and NFD `é` are two keys) and a lone surrogate
/// from `\uD800` passes through reading and writing unchanged.
///
/// Reading (`load0` + `LineReader` + `loadConvert`):
/// - bytes as **Latin-1** (`load(InputStream)`), not UTF-8,
/// - a comment = a logical line whose first non-white character is `#` or `!`,
/// - leading white characters of a line `' '`, `\t`, `\f`; line ends `\n`, `\r`, `\r\n`,
/// - an odd number of `\` at the end of a line = continuation (leading white characters of the next line
///   are dropped, a comment is not recognized on it), at the end of the file the `\` is dropped,
/// - the key ends at the first unescaped `=`, `:` or white character, then white
///   characters and at most one `=`/`:` are skipped,
/// - escapes `\uXXXX`, `\t`, `\r`, `\n`, `\f`, otherwise `\x` → `x`; a bad `\uXXXX`
///   → „Malformed \uxxxx encoding.",
/// - a repeated key: the last one wins.
///
/// Writing (`store0` with `escUnicode = true`): the comment (`writeComments`), the line
/// with the date, then `key=value` **sorted by key** (`String.compareTo`,
/// JDK 18+), line ends `\n`, Latin-1 bytes.
public struct JavaProperties: Equatable, Sendable {

    /// Key → value, both in UTF-16 units.
    private var storage: [[UInt16]: [UInt16]] = [:]

    public init() {}

    /// Java `getProperty`/`setProperty`; a `nil` key removes (`remove`).
    public subscript(key: String) -> String? {
        get { storage[Array(key.utf16)].map { String(decoding: $0, as: UTF16.self) } }
        set { storage[Array(key.utf16)] = newValue.map { Array($0.utf16) } }
    }

    public var count: Int { storage.count }

    /// Pairs sorted by key by UTF-16 units (the write order of `store`).
    public var entries: [(key: String, value: String)] {
        sortedStorage.map { (String(decoding: $0.key, as: UTF16.self), String(decoding: $0.value, as: UTF16.self)) }
    }

    private var sortedStorage: [(key: [UInt16], value: [UInt16])] {
        storage.map { (key: $0.key, value: $0.value) }.sorted { $0.key.lexicographicallyPrecedes($1.key) }
    }

    // MARK: - reading

    /// Java `Properties.load(InputStream)`.
    public static func load(_ data: Data) throws(JavaPropertiesError) -> JavaProperties {
        // `(char)(byte & 0xFF)` — Latin-1, each byte one unit.
        let input = data.map { UInt16($0) }
        var properties = JavaProperties()
        var reader = LineReader(input: input)
        while let line = reader.readLine() {
            var keyLength = 0
            var valueStart = line.count
            var hasSeparator = false
            var precedingBackslash = false
            while keyLength < line.count {
                let c = line[keyLength]
                if (c == equals || c == colon) && !precedingBackslash {
                    valueStart = keyLength + 1
                    hasSeparator = true
                    break
                } else if isBlank(c) && !precedingBackslash {
                    valueStart = keyLength + 1
                    break
                }
                precedingBackslash = c == backslash ? !precedingBackslash : false
                keyLength += 1
            }
            while valueStart < line.count {
                let c = line[valueStart]
                if !isBlank(c) {
                    if !hasSeparator && (c == equals || c == colon) {
                        hasSeparator = true
                    } else {
                        break
                    }
                }
                valueStart += 1
            }
            let key = try loadConvert(line[0..<keyLength])
            let value = try loadConvert(line[valueStart...])
            properties.storage[key] = value
        }
        return properties
    }

    /// Java `LineReader.readLine` — one logical line without comments,
    /// continuation and leading white characters; `nil` at the end of input.
    private struct LineReader {
        let input: [UInt16]
        var offset = 0

        mutating func readLine() -> [UInt16]? {
            var line: [UInt16] = []
            var skipWhiteSpace = true
            var appendedLineBegin = false
            var precedingBackslash = false
            while true {
                guard offset < input.count else {
                    if line.isEmpty { return nil }
                    return precedingBackslash ? Array(line.dropLast()) : line
                }
                let c = input[offset]
                offset += 1
                if skipWhiteSpace {
                    if isBlank(c) { continue }
                    if !appendedLineBegin && (c == cr || c == lf) { continue }
                    skipWhiteSpace = false
                    appendedLineBegin = false
                }
                if line.isEmpty && (c == hash || c == bang) {
                    // Comment: the rest of the line dropped; no line end = end of input.
                    while offset < input.count, input[offset] != cr, input[offset] != lf {
                        offset += 1
                    }
                    guard offset < input.count else { return nil }
                    offset += 1
                    skipWhiteSpace = true
                    continue
                }
                if c != lf && c != cr {
                    line.append(c)
                    precedingBackslash = c == backslash ? !precedingBackslash : false
                    continue
                }
                // End of line.
                if line.isEmpty {
                    skipWhiteSpace = true
                    continue
                }
                guard offset < input.count else {
                    return precedingBackslash ? Array(line.dropLast()) : line
                }
                if precedingBackslash {
                    // A `\` at the end of a line does not belong to the line; continues with the next one.
                    line.removeLast()
                    skipWhiteSpace = true
                    appendedLineBegin = true
                    precedingBackslash = false
                    if c == cr && input[offset] == lf {
                        offset += 1
                    }
                } else {
                    return line
                }
            }
        }
    }

    /// Java `loadConvert`: expands escapes. `LineReader` does not leave an unescaped
    /// `\` at the end, so the character after `\` always exists.
    private static func loadConvert(_ text: ArraySlice<UInt16>) throws(JavaPropertiesError) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            var c = text[index]
            index += 1
            guard c == backslash else {
                out.append(c)
                continue
            }
            c = text[index]
            index += 1
            if c == UInt16(UInt8(ascii: "u")) {
                guard index <= text.endIndex - 4 else { throw malformed }
                var value: UInt16 = 0
                for _ in 0..<4 {
                    let digit = text[index]
                    index += 1
                    // The digit value separately and then `<< 4 | d`: in `UInt16` the intermediate sum
                    // `(value << 4) + digit` would overflow (e.g. `￿`) and Swift would crash.
                    let nibble: UInt16
                    switch digit {
                    case UInt16(UInt8(ascii: "0"))...UInt16(UInt8(ascii: "9")): nibble = digit - UInt16(UInt8(ascii: "0"))
                    case UInt16(UInt8(ascii: "a"))...UInt16(UInt8(ascii: "f")): nibble = digit - UInt16(UInt8(ascii: "a")) + 10
                    case UInt16(UInt8(ascii: "A"))...UInt16(UInt8(ascii: "F")): nibble = digit - UInt16(UInt8(ascii: "A")) + 10
                    default: throw malformed
                    }
                    value = (value << 4) | nibble
                }
                out.append(value)
            } else {
                switch c {
                case UInt16(UInt8(ascii: "t")): out.append(tab)
                case UInt16(UInt8(ascii: "r")): out.append(cr)
                case UInt16(UInt8(ascii: "n")): out.append(lf)
                case UInt16(UInt8(ascii: "f")): out.append(formFeed)
                default: out.append(c)
                }
            }
        }
        return out
    }

    private static let malformed = JavaPropertiesError(message: "Malformed \\uxxxx encoding.")

    // MARK: - writing

    /// Java `Properties.store(OutputStream, comments)`: the date line is
    /// `Date.toString()` (`EEE MMM dd HH:mm:ss zzz yyyy`, in English) in `timeZone`.
    /// The zone abbreviation comes from ICU, so it may differ from Java (`GMT+2` instead of `CEST`);
    /// Java and `load` both read this line as a comment.
    public func store(comments: String?, date: Date = Date(), timeZone: TimeZone = .current) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return store(comments: comments, dateLine: formatter.string(from: date))
    }

    /// Writes with the given date-line text (without `#`) — for byte comparison with Java.
    func store(comments: String?, dateLine: String) -> Data {
        var out: [UInt16] = []
        if let comments {
            Self.writeComments(Array(comments.utf16), into: &out)
        }
        // Java `bw.write("#" + new Date())` — outside `writeComments`, without escapes;
        // a character outside Latin-1 would be written by the encoder as `?`.
        out.append(Self.hash)
        out += dateLine.utf16.map { $0 > 0xFF ? UInt16(UInt8(ascii: "?")) : $0 }
        out.append(Self.lf)
        for (key, value) in sortedStorage {
            Self.saveConvert(key, escapeSpace: true, into: &out)
            out.append(Self.equals)
            Self.saveConvert(value, escapeSpace: false, into: &out)
            out.append(Self.lf)
        }
        // Everything is ≤ U+00FF (larger characters are escaped) — Latin-1 byte by byte.
        return Data(out.map { UInt8(truncatingIfNeeded: $0) })
    }

    /// Java `writeComments`: characters above U+00FF as `\uXXXX` (upper-case hex),
    /// Latin-1 characters raw, `\n`/`\r`/`\r\n` → a new line with `#` if the next
    /// character is not `#`/`!`.
    private static func writeComments(_ comments: [UInt16], into out: inout [UInt16]) {
        out.append(hash)
        var current = 0
        while current < comments.count {
            let c = comments[current]
            if c > 0xFF {
                appendUnicodeEscape(c, into: &out)
            } else if c == lf || c == cr {
                out.append(lf)
                if c == cr && current != comments.count - 1 && comments[current + 1] == lf {
                    current += 1
                }
                if current == comments.count - 1 || (comments[current + 1] != hash && comments[current + 1] != bang) {
                    out.append(hash)
                }
            } else {
                out.append(c)
            }
            current += 1
        }
        out.append(lf)
    }

    /// Java `saveConvert(…, escapeUnicode = true)`.
    private static func saveConvert(_ text: [UInt16], escapeSpace: Bool, into out: inout [UInt16]) {
        for (index, c) in text.enumerated() {
            if c > 61 && c < 127 {
                if c == backslash { out.append(backslash) }
                out.append(c)
                continue
            }
            switch c {
            case space:
                if index == 0 || escapeSpace { out.append(backslash) }
                out.append(space)
            case tab: out += [backslash, UInt16(UInt8(ascii: "t"))]
            case lf: out += [backslash, UInt16(UInt8(ascii: "n"))]
            case cr: out += [backslash, UInt16(UInt8(ascii: "r"))]
            case formFeed: out += [backslash, UInt16(UInt8(ascii: "f"))]
            case equals, colon, hash, bang: out += [backslash, c]
            default:
                if c < 0x20 || c > 0x7E {
                    appendUnicodeEscape(c, into: &out)
                } else {
                    out.append(c)
                }
            }
        }
    }

    private static func appendUnicodeEscape(_ c: UInt16, into out: inout [UInt16]) {
        let digits = Array("0123456789ABCDEF".utf16)
        out += [backslash, UInt16(UInt8(ascii: "u"))]
        for shift in stride(from: 12, through: 0, by: -4) {
            out.append(digits[Int((c >> UInt16(shift)) & 0xF)])
        }
    }

    // MARK: - characters

    private static func isBlank(_ c: UInt16) -> Bool { c == space || c == tab || c == formFeed }

    private static let space = UInt16(UInt8(ascii: " "))
    private static let tab = UInt16(UInt8(ascii: "\t"))
    private static let lf = UInt16(UInt8(ascii: "\n"))
    private static let cr = UInt16(UInt8(ascii: "\r"))
    private static let formFeed: UInt16 = 0x0C
    private static let equals = UInt16(UInt8(ascii: "="))
    private static let colon = UInt16(UInt8(ascii: ":"))
    private static let hash = UInt16(UInt8(ascii: "#"))
    private static let bang = UInt16(UInt8(ascii: "!"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
}
