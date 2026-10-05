import Foundation

/// Reading `dxcc.json` the way the Java Jackson reads it.
///
/// The Java `DxccResolver` and `DxccCodeIndex` both map the file with Jackson into private
/// records with `@JsonIgnoreProperties(ignoreUnknown = true)`. Jackson is **not
/// strict about types** and its tolerance is part of the behaviour: `~/dxcc-json/` is a
/// **foreign data set** that the operator does not write and we do not control. Had the port
/// rejected a file that the Java version reads, the application would be left without DXCC --
/// and thus without dupe checking, without multipliers and without a score. Rejecting is
/// a worse error than accepting; **crashing** is the worst of all.
///
/// Everything below is **measured on Java v1.1.1** (JDK 21, Jackson 2.22) with one-off
/// probes, not guessed; the probes were not kept, the measured result is
/// this table, pinned in `DxccResolverTests`:
///
/// | input | Jackson |
/// |---|---|
/// | key missing / `null` | default value (`0`, `false`, `nil`) |
/// | `"503"`, `" 7 "`, `"+7"`, `"007"` into `int` | `503`, `7`, `7`, `7` (trim like `String.trim()`) |
/// | `""` into `int` | `0` |
/// | `"abc"`, `"7.0"`, `"1e3"`, `"\u{00A0}7"` into `int` | error of the whole file |
/// | `1.9`, `-1.9`, `0.9`, `1e3` into `int` | `1`, `-1`, `0`, `1000` (truncated toward zero) |
/// | `2147483647.0` / `2147483647.4` into `int` | `2147483647` / **error** -- the range is checked **before** truncation |
/// | `2147483648`, `-2147483649`, `1e20`, `2.9e9` into `int` | error (the Java `int` is 32-bit) |
/// | `true` into `int` | error |
/// | `123`, `1.50`, `1e2`, `1E+2`, `-0`, `1e400` into `String` | **`"123"`, `"1.50"`, `"1e2"`, `"1E+2"`, `"-0"`, `"1e400"`** -- the original literal text |
/// | `true` into `String` | `"true"` |
/// | `"true"`, `"True"`, `"TRUE"` into `boolean` | `true` |
/// | `"false"`, `"False"`, `"FALSE"` into `boolean` | `false` |
/// | `"tRuE"`, `"fAlSe"`, `"yes"`, `"1"` into `boolean` | error of the whole file |
/// | `""`, `"  "` into `boolean` | `false` |
/// | `0`, `2`, `2147483648` into `boolean` | `false`, `true`, `true` (no range check) |
/// | `0.0`, `1.5` into `boolean` | error |
/// | scalar instead of a list, `[true]` in `List<Integer>` | error |
/// | `["15"]`, `[1.7]` in `List<Integer>` | `[15]`, `[1]` |
/// | `[15, null]`, `[null]` | **`[15, null]`, `[null]`** -- the `null` element stays |
/// | duplicate key while the record **is not complete** | the last wins, but **every occurrence is converted** (`{"entityCode":"abc","entityCode":1}` -> error) |
/// | duplicate key when the record **is already complete** | error ("No fallback setter/field defined for creator property") |
/// | duplicate **unknown** key | always ignored |
/// | content **after** the end of the JSON (`{...}xx`, two objects in a row) | reads the first value, ignores the rest |
/// | `null` content (the whole document) | **`NullPointerException`** (`"raw" is null`) |
/// | BOM at the start | skipped |
/// | nesting to depth 1000 / 1001 | passes / error |
/// | numeric literal with 1000 / 1001 **digits** | passes / error |
/// | `01`, `+7`, `0x10`, `NaN`, trailing comma, comment, apostrophes | error |
/// | unescaped control character in text, bad escape, bad UTF-8 | error |
///
/// Because of the rows about duplicate keys, content after the end and distinguishing `0`/`0.0`,
/// there is neither `JSONSerialization` nor `JSONDecoder` here:
/// - `JSONSerialization` keeps the **first** value of a duplicate key (Jackson the
///   last), does not preserve key order at all (and the rule about
///   a complete record depends on it), rejects content after the end of the JSON, and in `NSNumber`
///   after parsing one cannot reliably tell whether the source had `0` or `0.0`
///   (Jackson distinguishes them: `0` into `boolean` passes, `0.0` is an error),
/// - `JSONDecoder` moreover does not bend types at all.
///
/// Hence the module has its own small JSON reader (strict RFC 8259 plus the Jackson
/// deviations: BOM, content after the end, key order with duplicates, limits on depth
/// and number length), which for numbers remembers the **original literal text** -- that
/// is exactly what Jackson puts into `String` fields.
///
/// The reader is **iterative**, with its own frame stack: a recursive version
/// crashed on stack overflow (signal 10) already at depth ~600, i.e. before
/// it could reach the Java limit of 1000. Crashing on a foreign data file is
/// worse than accepting it and than rejecting it.
///
/// The only known deliberate divergence: a **lone surrogate in an escape** (`"\ud800"`).
/// Java accepts it (an unpaired `char` results), Swift `String` cannot
/// represent it, so here it is a file error. Silently replacing it with U+FFFD would mean
/// corrupting the entity name.
enum DxccJson {

    /// Maximum nesting depth, like `StreamReadConstraints.getMaxNestingDepth()`.
    /// Measured: depth 1000 passes, 1001 is an error.
    static let maxNestingDepth = 1000

    /// Maximum number of **digits** in a numeric literal, like
    /// `StreamReadConstraints.getMaxNumberLength()`. Measured: the sign, decimal
    /// point and `e` do not count, the digits of the mantissa and exponent do --
    /// `0.` + 999 digits passes, `0.` + 1000 does not, `1e` + 999 passes, `1e` + 1000 does not.
    static let maxNumberDigits = 1000

    // MARK: - Hodnota JSONu

    /// Parsed value. For numbers the **literal text** is kept, because Jackson
    /// gives it in this form into `String` fields, and a flag whether it was
    /// an integer literal (`0` vs. `0.0` behave differently).
    enum Value {
        case null
        case bool(Bool)
        case number(text: String, isInteger: Bool)
        case string(String)
        case array([Value])
        case object(Object)
    }

    /// A JSON object as a **list of key occurrences** in the original order, not a map.
    /// Order and duplicates are part of the behaviour here: Jackson converts every
    /// occurrence and once a record is complete, any further property of it is an error.
    struct Object {
        var entries: [(key: String, value: Value)]
    }

    // MARK: - Parsing

    /// Parses the input: detects the byte encoding, skips **one** BOM, reads the
    /// **first** value and ignores any further content (just like
    /// `ObjectMapper.readValue`).
    static func parse(_ data: Data, message: String) throws -> Value {
        let text = try decodeBytes(data, message: message)
        var reader = Reader(scalars: Array(text.unicodeScalars))
        do {
            return try reader.readDocument()
        } catch let failure as Failure {
            throw DxccError(message: message, cause: failure.reason)
        }
    }

    /// Encoding that the Java `ByteSourceJsonBootstrapper` can detect.
    private enum ByteEncoding {
        case utf8
        case utf16LittleEndian
        case utf16BigEndian
        case utf32LittleEndian
        case utf32BigEndian
    }

    /// Detects the encoding from the first four bytes and converts the input to text -- the same
    /// as the Java `ByteSourceJsonBootstrapper.detectEncoding()`.
    ///
    /// Measured on Java v1.1.1: it accepts **UTF-8, UTF-16LE, UTF-16BE, UTF-32LE
    /// and UTF-32BE, with a BOM and without** (without a BOM it is recognized by the layout of
    /// null bytes in the first four). When **fewer than four bytes** are available,
    /// detection does not run and UTF-8 is assumed (that is why a lone `FF FE`
    /// ends with an error, not an empty document). The byte orders "2143" and "3412"
    /// (`00 00 xx 00`, `00 xx 00 00`) are rejected by Java -- `CharConversionException`.
    ///
    /// `~/dxcc-json/dxcc.json` is a foreign data set; if someone re-saved it
    /// from a Windows editor as UTF-16, the Java application reads it and the Swift one
    /// would reject it without this -- and without DXCC there is no dupe check, multipliers
    /// or score.
    ///
    /// **Only one BOM.** `EF BB BF EF BB BF{...}` is an error in Java (`JsonParseException`),
    /// three BOMs too. Foundation, however, swallows one BOM itself in `String(data:encoding:.utf8)`,
    /// so with an additional removal two would be tolerated; the text is therefore
    /// built via `String(decoding:as:UTF8.self)`, which keeps the BOM, and
    /// the single BOM is trimmed here from the bytes. For UTF-16/32 the variant
    /// with **explicit** endianness is used for decoding, which does not swallow the BOM either.
    private static func decodeBytes(_ data: Data, message: String) throws -> String {
        let head = [UInt8](data.prefix(4))
        var encoding = ByteEncoding.utf8
        var bomLength = 0
        if head.count == 4 {
            let quad = (UInt32(head[0]) << 24) | (UInt32(head[1]) << 16)
                | (UInt32(head[2]) << 8) | UInt32(head[3])
            let firstTwo = quad >> 16
            switch quad {
            case 0x0000_FEFF:
                (encoding, bomLength) = (.utf32BigEndian, 4)
            case 0xFFFE_0000:
                (encoding, bomLength) = (.utf32LittleEndian, 4)
            case 0x0000_FFFE:
                throw DxccError(message: message, cause: "nepodporované pořadí bajtů UCS-4 (2143)")
            case 0xFEFF_0000:
                throw DxccError(message: message, cause: "nepodporované pořadí bajtů UCS-4 (3412)")
            default:
                if firstTwo == 0xFEFF {
                    (encoding, bomLength) = (.utf16BigEndian, 2)
                } else if firstTwo == 0xFFFE {
                    (encoding, bomLength) = (.utf16LittleEndian, 2)
                } else if quad >> 8 == 0x00EF_BBBF {
                    (encoding, bomLength) = (.utf8, 3)
                } else if quad >> 8 == 0 {
                    encoding = .utf32BigEndian // 00 00 00 xx
                } else if quad & 0x00FF_FFFF == 0 {
                    encoding = .utf32LittleEndian // xx 00 00 00
                } else if quad & ~UInt32(0x00FF_0000) == 0 {
                    throw DxccError(message: message, cause: "nepodporované pořadí bajtů UCS-4 (3412)")
                } else if quad & ~UInt32(0x0000_FF00) == 0 {
                    throw DxccError(message: message, cause: "nepodporované pořadí bajtů UCS-4 (2143)")
                } else if firstTwo & 0xFF00 == 0 {
                    encoding = .utf16BigEndian // 00 xx 00 xx
                } else if firstTwo & 0x00FF == 0 {
                    encoding = .utf16LittleEndian // xx 00 xx 00
                }
            }
        }
        let body = bomLength == 0 ? data : data.dropFirst(bomLength)
        switch encoding {
        case .utf8:
            // `String(data:encoding:)` only verifies validity (returns `nil`); the text is
            // built with `String(decoding:)` so that a possible **further** BOM stays
            // a character and ends with an error as in Java.
            guard String(data: body, encoding: .utf8) != nil else {
                throw DxccError(message: message, cause: "vstup není platné UTF-8")
            }
            return String(decoding: body, as: UTF8.self)
        case .utf16LittleEndian:
            return try decode(body, as: .utf16LittleEndian, named: "UTF-16LE", message: message)
        case .utf16BigEndian:
            return try decode(body, as: .utf16BigEndian, named: "UTF-16BE", message: message)
        case .utf32LittleEndian:
            return try decode(body, as: .utf32LittleEndian, named: "UTF-32LE", message: message)
        case .utf32BigEndian:
            return try decode(body, as: .utf32BigEndian, named: "UTF-32BE", message: message)
        }
    }

    private static func decode(_ body: Data, as encoding: String.Encoding, named: String,
                               message: String) throws -> String {
        guard let text = String(data: body, encoding: encoding) else {
            throw DxccError(message: message, cause: "vstup není platné \(named)")
        }
        return text
    }

    /// Walks the record's properties in **order of occurrence** and passes them to `handle`.
    ///
    /// Copies the Java `PropertyValueBuffer` for a record: unknown keys are
    /// ignored (`@JsonIgnoreProperties(ignoreUnknown = true)`), every occurrence of
    /// a known key is converted (so a bad value fails the file even when
    /// a later occurrence overwrites it), the last occurrence wins -- **but only until the record
    /// is complete**. Once all creator properties have appeared, Jackson
    /// builds the record and any further property of it ends with the error "No fallback
    /// setter/field defined for creator property". Measured; in the real
    /// `dxcc.json` the full set is on every entity, so this is not exotic.
    static func walkCreatorProperties(_ object: Object, creatorKeys: Set<String>, message: String,
                                      handle: (String, Value) throws -> Void) throws {
        var seen: Set<String> = []
        for entry in object.entries {
            guard creatorKeys.contains(entry.key) else { continue }
            if seen.count == creatorKeys.count {
                throw DxccError(message: message,
                                cause: "vlastnost \(entry.key) přišla znovu, když už byl záznam úplný")
            }
            try handle(entry.key, entry.value)
            seen.insert(entry.key)
        }
    }

    /// List of records from the `dxcc` array, or `nil` when the key is missing or is `null`.
    /// Elements may be objects or `null` (the Java Jackson maps a `null` element to a
    /// `null` record; only working with it fails with `NullPointerException`).
    static func entityValues(_ root: Value, message: String) throws -> [Value]? {
        if case .null = root {
            // Java `raw.dxcc()` on a `null` mapping result -> NullPointerException.
            throw DxccError(kind: .nullPointer, message: message, cause: "obsah je null")
        }
        guard case .object(let object) = root else {
            throw DxccError(message: message, cause: "nejvyšší úroveň není objekt JSON")
        }
        // `RawFile` has a single creator property, so a second occurrence of `dxcc` is
        // an error ("Should never call `set()` on setterless property ('dxcc')").
        var dxcc: Value?
        try walkCreatorProperties(object, creatorKeys: ["dxcc"], message: message) { _, value in
            dxcc = value
        }
        switch dxcc {
        case nil, .some(.null):
            return nil
        case .some(.array(let items)):
            for item in items {
                switch item {
                case .object, .null:
                    continue
                default:
                    throw DxccError(message: message, cause: "prvek pole dxcc není objekt")
                }
            }
            return items
        default:
            throw DxccError(message: message, cause: "pole dxcc není seznam")
        }
    }

    // MARK: - Scalar conversions as done by Jackson

    /// `int` field (the Java `int` is **32-bit** -- larger numbers are an error).
    static func int(_ value: Value?, key: String, message: String) throws -> Int {
        switch value {
        case nil, .some(.null):
            return 0
        case .some(.number(let text, true)):
            guard let wide = Int64(text), let narrow = Int32(exactly: wide) else {
                throw DxccError(message: message, cause: "\(key): \(text) se nevejde do 32bitového čísla")
            }
            return Int(narrow)
        case .some(.number(let text, false)):
            guard let parsed = Double(text) else {
                throw DxccError(message: message, cause: "\(key): \(text) není číslo")
            }
            // Jackson checks the range **on the untruncated** number: 2147483647.9
            // is "out of range of int", even though it would fit after truncation.
            guard parsed >= -2_147_483_648, parsed <= 2_147_483_647 else {
                throw DxccError(message: message, cause: "\(key): \(text) je mimo rozsah 32bitového čísla")
            }
            return Int(parsed.rounded(.towardZero))
        case .some(.string(let raw)):
            let text = JavaText.trim(raw)
            if text.isEmpty { return 0 }
            guard let narrow = Int32(text) else {
                throw DxccError(message: message, cause: "\(key): „\(raw)“ není 32bitové číslo")
            }
            return Int(narrow)
        default:
            throw DxccError(message: message, cause: "\(key): nečekaný typ pro číslo")
        }
    }

    /// Pole typu `boolean`.
    static func bool(_ value: Value?, key: String, message: String) throws -> Bool {
        switch value {
        case nil, .some(.null):
            return false
        case .some(.bool(let flag)):
            return flag
        case .some(.number(let text, true)):
            // Jackson does not check the range here: 2147483648 and larger is "non-zero".
            guard let wide = Int64(text) else { return true }
            return wide != 0
        case .some(.string(let raw)):
            let text = JavaText.trim(raw)
            if text.isEmpty { return false }
            // Jackson compares **exactly** these forms, not case-insensitively.
            if text == "true" || text == "True" || text == "TRUE" { return true }
            if text == "false" || text == "False" || text == "FALSE" { return false }
            throw DxccError(message: message, cause: "\(key): „\(raw)“ není pravdivostní hodnota")
        default:
            throw DxccError(message: message, cause: "\(key): nečekaný typ pro pravdivostní hodnotu")
        }
    }

    /// `String` field; a missing key and `null` give `nil`. A number is taken
    /// as the **original literal text** (Jackson does exactly that -- `1.50` -> `"1.50"`).
    static func string(_ value: Value?, key: String, message: String) throws -> String? {
        switch value {
        case nil, .some(.null):
            return nil
        case .some(.string(let text)):
            return text
        case .some(.number(let text, _)):
            return text
        case .some(.bool(let flag)):
            return flag ? "true" : "false"
        default:
            throw DxccError(message: message, cause: "\(key): nečekaný typ pro text")
        }
    }

    /// `List<Integer>` field. A `null` element stays `null` -- the Java list tolerates it
    /// and a zero in its place would be **a different zone number**, not a missing value.
    static func intList(_ value: Value?, key: String, message: String) throws -> [Int?]? {
        guard let items = try list(value, key: key, message: message) else { return nil }
        return try items.map { item in
            if case .null = item { return nil }
            return try int(item, key: key, message: message)
        }
    }

    /// `List<String>` field; a `null` element stays `null`.
    static func stringList(_ value: Value?, key: String, message: String) throws -> [String?]? {
        guard let items = try list(value, key: key, message: message) else { return nil }
        return try items.map { item in
            if case .null = item { return nil }
            return try string(item, key: key, message: message)
        }
    }

    private static func list(_ value: Value?, key: String, message: String) throws -> [Value]? {
        switch value {
        case nil, .some(.null):
            return nil
        case .some(.array(let items)):
            return items
        default:
            throw DxccError(message: message, cause: "\(key): čekal se seznam")
        }
    }

    // MARK: - Reader

    private struct Failure: Error {
        let reason: String
    }

    /// Strict JSON reader (RFC 8259) with the Jackson deviations described on the type.
    ///
    /// Nesting is kept in its own `frames` stack, not in recursion -- a deep
    /// (even valid) file must not crash the process.
    private struct Reader {

        /// A container in progress. `pendingKey` is the key whose value is currently being read
        /// (unused for an array).
        private struct Frame {
            let isArray: Bool
            var items: [Value] = []
            var entries: [(key: String, value: Value)] = []
            var pendingKey: String = ""
        }

        let scalars: [Unicode.Scalar]
        var index = 0

        /// Reads **one** value; what follows it is not its concern (like Jackson).
        mutating func readDocument() throws -> Value {
            var frames: [Frame] = []
            var finished: Value

            reading: while true {
                skipWhitespace()
                guard let scalar = peek() else { throw Failure(reason: "prázdný vstup") }
                switch scalar {
                case "{":
                    index += 1
                    try checkDepth(frames.count + 1)
                    skipWhitespace()
                    if peek() == "}" {
                        index += 1
                        finished = .object(Object(entries: []))
                    } else {
                        var frame = Frame(isArray: false)
                        frame.pendingKey = try readKey()
                        frames.append(frame)
                        continue reading
                    }
                case "[":
                    index += 1
                    try checkDepth(frames.count + 1)
                    skipWhitespace()
                    if peek() == "]" {
                        index += 1
                        finished = .array([])
                    } else {
                        frames.append(Frame(isArray: true))
                        continue reading
                    }
                case "\"":
                    finished = .string(try readString())
                case "t":
                    try expect("true")
                    finished = .bool(true)
                case "f":
                    try expect("false")
                    finished = .bool(false)
                case "n":
                    try expect("null")
                    finished = .null
                default:
                    finished = try readNumber()
                }

                // Attach the finished value to the parent; when the parent closes, continue
                // the same way one level up.
                closing: while true {
                    guard !frames.isEmpty else { return finished }
                    let last = frames.count - 1
                    if frames[last].isArray {
                        frames[last].items.append(finished)
                        skipWhitespace()
                        switch peek() {
                        case ",":
                            index += 1
                            continue reading
                        case "]":
                            index += 1
                            finished = .array(frames.removeLast().items)
                            continue closing
                        default:
                            throw Failure(reason: "v seznamu se čekala „,“ nebo „]“")
                        }
                    } else {
                        frames[last].entries.append((key: frames[last].pendingKey, value: finished))
                        skipWhitespace()
                        switch peek() {
                        case ",":
                            index += 1
                            frames[last].pendingKey = try readKey()
                            continue reading
                        case "}":
                            index += 1
                            finished = .object(Object(entries: frames.removeLast().entries))
                            continue closing
                        default:
                            throw Failure(reason: "v objektu se čekala „,“ nebo „}“")
                        }
                    }
                }
            }
        }

        private func checkDepth(_ depth: Int) throws {
            guard depth <= maxNestingDepth else {
                throw Failure(reason: "zanoření JSONu (\(depth)) překračuje povolený limit \(maxNestingDepth)")
            }
        }

        /// Reads `"key":` and returns the key.
        private mutating func readKey() throws -> String {
            skipWhitespace()
            guard peek() == "\"" else { throw Failure(reason: "čekal se název klíče v uvozovkách") }
            let key = try readString()
            skipWhitespace()
            guard peek() == ":" else { throw Failure(reason: "za klíčem „\(key)“ chybí dvojtečka") }
            index += 1
            return key
        }

        private mutating func readString() throws -> String {
            index += 1 // opening quote
            var out = String.UnicodeScalarView()
            while true {
                guard let scalar = next() else { throw Failure(reason: "neuzavřený text") }
                if scalar == "\"" {
                    return String(out)
                }
                if scalar == "\\" {
                    out.append(try readEscape())
                    continue
                }
                if scalar.value < 0x20 {
                    throw Failure(reason: "neescapovaný řídicí znak v textu")
                }
                out.append(scalar)
            }
        }

        private mutating func readEscape() throws -> Unicode.Scalar {
            guard let scalar = next() else { throw Failure(reason: "neuzavřený escape") }
            switch scalar {
            case "\"": return "\""
            case "\\": return "\\"
            case "/": return "/"
            case "b": return "\u{08}"
            case "f": return "\u{0C}"
            case "n": return "\n"
            case "r": return "\r"
            case "t": return "\t"
            case "u": return try readUnicodeEscape()
            default: throw Failure(reason: "neznámý escape „\\\(scalar)“")
            }
        }

        private mutating func readUnicodeEscape() throws -> Unicode.Scalar {
            let first = try readHexQuad()
            if let scalar = Unicode.Scalar(first) {
                return scalar
            }
            // Surrogate pair: after 0xD800...0xDBFF must come 0xDC00...0xDFFF.
            guard (0xD800...0xDBFF).contains(first), peek() == "\\", peek(1) == "u" else {
                throw Failure(reason: "osamocený náhradní znak v escapu \\u")
            }
            index += 2
            let second = try readHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw Failure(reason: "osamocený náhradní znak v escapu \\u")
            }
            let combined = 0x10000 + (first - 0xD800) * 0x400 + (second - 0xDC00)
            guard let scalar = Unicode.Scalar(combined) else {
                throw Failure(reason: "neplatný náhradní pár v escapu \\u")
            }
            return scalar
        }

        private mutating func readHexQuad() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let scalar = next(), let digit = hexDigit(scalar) else {
                    throw Failure(reason: "escape \\u nemá čtyři šestnáctkové číslice")
                }
                value = value * 16 + digit
            }
            return value
        }

        private func hexDigit(_ scalar: Unicode.Scalar) -> UInt32? {
            switch scalar {
            case "0"..."9": return scalar.value - 0x30
            case "a"..."f": return scalar.value - 0x61 + 10
            case "A"..."F": return scalar.value - 0x41 + 10
            default: return nil
            }
        }

        /// A number per RFC 8259: no leading `+`, no leading zeros, no
        /// `NaN`/`Infinity`, no hexadecimal -- Jackson rejects all of this
        /// too (measured). In addition a limit on the number of digits applies.
        private mutating func readNumber() throws -> Value {
            let start = index
            var isInteger = true
            var digits = 0
            if peek() == "-" { index += 1 }
            guard let first = peek(), isDigit(first) else {
                throw Failure(reason: "neplatná hodnota JSON")
            }
            if first == "0" {
                index += 1
                digits += 1
                if let after = peek(), isDigit(after) {
                    throw Failure(reason: "číslo nesmí mít vedoucí nulu")
                }
            } else {
                while let scalar = peek(), isDigit(scalar) {
                    index += 1
                    digits += 1
                }
            }
            if peek() == "." {
                isInteger = false
                index += 1
                guard let after = peek(), isDigit(after) else {
                    throw Failure(reason: "za desetinnou tečkou chybí číslice")
                }
                while let scalar = peek(), isDigit(scalar) {
                    index += 1
                    digits += 1
                }
            }
            if peek() == "e" || peek() == "E" {
                isInteger = false
                index += 1
                if peek() == "+" || peek() == "-" { index += 1 }
                guard let after = peek(), isDigit(after) else {
                    throw Failure(reason: "v exponentu chybí číslice")
                }
                while let scalar = peek(), isDigit(scalar) {
                    index += 1
                    digits += 1
                }
            }
            guard digits <= maxNumberDigits else {
                throw Failure(reason: "číslo má \(digits) číslic, povolený limit je \(maxNumberDigits)")
            }
            return .number(text: String(String.UnicodeScalarView(scalars[start..<index])), isInteger: isInteger)
        }

        private func isDigit(_ scalar: Unicode.Scalar) -> Bool {
            ("0"..."9").contains(scalar)
        }

        private mutating func expect(_ word: String) throws {
            for scalar in word.unicodeScalars {
                guard next() == scalar else { throw Failure(reason: "neplatná hodnota JSON") }
            }
        }

        /// JSON whitespace: space, tab, CR, LF (nothing else).
        private mutating func skipWhitespace() {
            while let scalar = peek(), scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                index += 1
            }
        }

        private func peek(_ offset: Int = 0) -> Unicode.Scalar? {
            let position = index + offset
            return position < scalars.count ? scalars[position] : nil
        }

        private mutating func next() -> Unicode.Scalar? {
            guard index < scalars.count else { return nil }
            defer { index += 1 }
            return scalars[index]
        }
    }
}
