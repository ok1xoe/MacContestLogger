import Foundation

/// Writes a `YamlValue` tree to YAML text.
///
/// Why our own: Java writes YAML with Jackson
/// (`YamlObjectMapper.create().writerWithDefaultPrettyPrinter()`), and Swift must not have an
/// external dependency. `BandPlanFile.write` writes the **user's file**
/// (`contest-data/bandplan.yaml`), so the format is not ours to choose — it is the format
/// Java wrote there, and any difference is a change to the user's data.
///
/// The output is therefore not "some valid YAML" but **exactly what Jackson prints**
/// with default settings (`YAMLGenerator` over SnakeYAML 2.5). Measured on Java 21
/// (see `YamlWriterTests`), the strongest level: `write(YamlParser.parse(bandplan))`
/// gives byte for byte the same file as the one in the repository.
///
/// Jackson rules found (each pinned by a test):
/// - the document starts with `---` (`WRITE_DOC_START_MARKER`) and ends with a single line break,
/// - **text is always in double quotes** (`MINIMIZE_QUOTES` is off),
///   so `"48"`, `"true"`, `"~"` and `"001"` come back as text,
/// - numbers, `true`/`false` and `null` are written without quotes,
/// - an empty mapping is `{}`, an empty sequence `[]`,
/// - indentation of 2 spaces, but a block **sequence in a mapping is not indented** (`INDENT_ARRAYS`
///   is off), so `- ` is at the key's column,
/// - a **key** is quoted only when needed (`StringQuotingChecker.Default`),
/// - lines are wrapped at column 80 (`SPLIT_LINES`), for values, not for keys,
/// - `Double` is written with Java's `Double.toString` (see `JavaDouble`).
///
/// Key order is the order in `YamlMapping` (Jackson has `LinkedHashMap`, so it is also
/// insertion order). The original scalar spelling (`YamlValue.raw`) is **not used** —
/// the output is canonical, exactly as in Java, where Jackson's tree does not hold `raw` at all.
public enum YamlWriter {

    /// Writes the tree as a whole YAML document (including `---` and the trailing line break).
    public static func write(_ value: YamlValue) -> String {
        var emitter = YamlEmitter()
        emitter.writeDocument(value)
        return emitter.out
    }
}

// MARK: - Scalar style

/// Scalar writing style. Jackson asks only for `plain` and `double`; `single` is chosen
/// by SnakeYAML when `plain` is not possible (`chooseStyle`).
enum YamlScalarStyle {
    case plain
    case single
    case double
}

/// What `analyzeScalar` finds out about a scalar — which styles are permissible for it.
/// Port of `org.yaml.snakeyaml.emitter.ScalarAnalysis`; `allowBlock` stays here only
/// for fidelity of the decision logic (Jackson never asks for a block scalar).
struct YamlScalarAnalysis {
    var empty: Bool
    var multiline: Bool
    var allowFlowPlain: Bool
    var allowBlockPlain: Bool
    var allowSingleQuoted: Bool
    var allowBlock: Bool
}

// MARK: - Emitter

/// Port of `org.yaml.snakeyaml.emitter.Emitter` for the subset of events that
/// Jackson's `YAMLGenerator` produces from our tree: one document, block mappings,
/// block sequences, empty collections in flow form and scalars in `plain`
/// or `double` style.
///
/// SnakeYAML's state machine is dissolved into recursion here, but **the order of writes,
/// the indentation stack and the `whitespace`/`indention`/`column` flags are the same** —
/// line wrapping and the decision when to write a line break depend on them.
struct YamlEmitter {

    /// Finished text.
    var out = ""

    // MARK: state of the writer (names from SnakeYAML)

    /// The column at which writing continues. Counted in **UTF-16 units**,
    /// because Java adds `String.length()` there — so 2 for characters outside the BMP.
    private var column = 0
    /// Was the last written character whitespace?
    private var whitespace = true
    /// Is the writer still in the indentation (nothing "substantive" on the line yet)?
    private var indention = true
    /// Current indentation; `nil` = none yet (before the first node).
    private var indent: Int?
    private var indents: [Int?] = []
    private var flowLevel = 0
    /// Is a key being written that fits on one line? Then it is **not wrapped**.
    private var simpleKeyContext = false
    /// Is the parent node a mapping? Decides the "indentless" block sequence.
    private var mappingContext = false

    // MARK: settings (values with which Jackson produces the Emitter)

    /// `DumperOptions.getIndent()` = 2.
    private let bestIndent = 2
    /// `DumperOptions.getWidth()` = 80. Jackson does not reset it.
    private let bestWidth = 80
    /// `SPLIT_LINES` is on.
    private let splitLines = true
    /// `ALLOW_LONG_KEYS` is off, so the default 128 stays. A key that is
    /// **longer than or equal to** it is written in the explicit form `? key` / `: value`.
    private let maxSimpleKeyLength = 128
    /// `DumperOptions.isAllowUnicode()` = true, so diacritics and emoji go into the
    /// output verbatim, not escaped.
    private let allowUnicode = true

    // MARK: - document

    /// `ExpectDocumentStart` with `explicit == true` (Jackson writes `---`) and
    /// `ExpectDocumentEnd`, which adds a line break at the end.
    mutating func writeDocument(_ value: YamlValue) {
        writeIndent()
        writeIndicator("---", needWhitespace: true, whitespace: false, indentation: false)
        node(value, mapping: false, simpleKey: false)
        // ExpectDocumentEnd: writeIndent() at the end gives exactly one line break.
        writeIndent()
    }

    // MARK: - nodes

    /// `expectNode`: sets the contexts and decides block/flow form. An empty
    /// collection goes to flow (`checkEmptySequence`/`checkEmptyMapping`), hence
    /// `{}` and `[]`.
    private mutating func node(_ value: YamlValue, mapping: Bool, simpleKey: Bool) {
        mappingContext = mapping
        simpleKeyContext = simpleKey
        switch value {
        case .null:
            scalar("null", requested: .plain)
        case .bool(let flag, _):
            scalar(flag ? "true" : "false", requested: .plain)
        case .int(let number, _):
            scalar(String(number), requested: .plain)
        case .double(let number, _):
            scalar(JavaDouble.toString(number), requested: .plain)
        case .string(let text):
            scalar(text, requested: .double)
        case .sequence(let items):
            if items.isEmpty {
                flowEmpty(open: "[", close: "]")
            } else {
                blockSequence(items)
            }
        case .mapping(let map):
            if map.isEmpty {
                flowEmpty(open: "{", close: "}")
            } else {
                blockMapping(map)
            }
        }
    }

    /// Empty collection in flow form — `expectFlowSequence`/`expectFlowMapping`,
    /// where the very first event closes the collection.
    private mutating func flowEmpty(open: String, close: String) {
        writeIndicator(open, needWhitespace: true, whitespace: true, indentation: false)
        flowLevel += 1
        increaseIndent(flow: true, indentless: false)
        indent = indents.removeLast()
        flowLevel -= 1
        writeIndicator(close, needWhitespace: false, whitespace: false, indentation: false)
    }

    /// `expectBlockSequence` + `ExpectBlockSequenceItem`.
    ///
    /// "Indentless" is why `- ` in a mapping is at the key's column: after `:`
    /// `indention` is turned off, so a sequence in a mapping does not increase the indentation.
    private mutating func blockSequence(_ items: [YamlValue]) {
        let indentless = mappingContext && !indention
        increaseIndent(flow: false, indentless: indentless)
        for item in items {
            writeIndent()
            writeIndicator("-", needWhitespace: true, whitespace: false, indentation: true)
            node(item, mapping: false, simpleKey: false)
        }
        indent = indents.removeLast()
    }

    /// `expectBlockMapping` + `ExpectBlockMappingKey`/`…SimpleValue`/`…Value`.
    private mutating func blockMapping(_ map: YamlMapping) {
        increaseIndent(flow: false, indentless: false)
        for (key, value) in map.pairs {
            writeIndent()
            let requested: YamlScalarStyle = Self.needToQuoteName(key) ? .double : .plain
            if checkSimpleKey(key) {
                scalarNode(key, requested: requested, mapping: true, simpleKey: true)
                writeIndicator(":", needWhitespace: false, whitespace: false, indentation: false)
                node(value, mapping: true, simpleKey: false)
            } else {
                // An empty, multi-line or too long key is written by Java
                // in the explicit form `? key` on one line and `: value` on the next.
                writeIndicator("?", needWhitespace: true, whitespace: false, indentation: true)
                scalarNode(key, requested: requested, mapping: true, simpleKey: false)
                writeIndent()
                writeIndicator(":", needWhitespace: true, whitespace: false, indentation: true)
                node(value, mapping: true, simpleKey: false)
            }
        }
        indent = indents.removeLast()
    }

    /// A scalar as a node — sets the contexts like `expectNode` and writes it.
    private mutating func scalarNode(_ text: String, requested: YamlScalarStyle,
                                     mapping: Bool, simpleKey: Bool) {
        mappingContext = mapping
        simpleKeyContext = simpleKey
        scalar(text, requested: requested)
    }

    /// `expectScalar` + `processScalar`.
    private mutating func scalar(_ text: String, requested: YamlScalarStyle) {
        increaseIndent(flow: true, indentless: false)
        let analysis = Self.analyzeScalar(text, allowUnicode: allowUnicode)
        let style = chooseStyle(requested: requested, analysis: analysis)
        // A key is never wrapped (`split = !simpleKeyContext && splitLines`).
        let split = !simpleKeyContext && splitLines
        switch style {
        case .plain: writePlain(text, split: split)
        case .single: writeSingleQuoted(text, split: split)
        case .double: writeDoubleQuoted(text, split: split)
        }
        indent = indents.removeLast()
    }

    /// `increaseIndent`.
    private mutating func increaseIndent(flow: Bool, indentless: Bool) {
        indents.append(indent)
        if indent == nil {
            indent = flow ? bestIndent : 0
        } else if !indentless {
            indent! += bestIndent
        }
    }

    /// `checkSimpleKey` for a scalar key: the length is measured in **UTF-16 units**
    /// (`String.length()`), an empty or multi-line key is not simple.
    private func checkSimpleKey(_ key: String) -> Bool {
        let analysis = Self.analyzeScalar(key, allowUnicode: allowUnicode)
        return key.utf16.count < maxSimpleKeyLength && !analysis.empty && !analysis.multiline
    }

    /// `chooseScalarStyle` for the styles Jackson asks for.
    ///
    /// `double` is always respected. `plain` (numbers, `true`/`false`, `null`
    /// and unquoted keys) is downgraded to `single`, or down to `double` if
    /// it would otherwise be read differently than it was written.
    private func chooseStyle(requested: YamlScalarStyle,
                             analysis: YamlScalarAnalysis) -> YamlScalarStyle {
        if requested == .double { return .double }
        // Jackson sends ImplicitTuple(true, true), so the tag is never forced.
        if !(simpleKeyContext && (analysis.empty || analysis.multiline))
            && ((flowLevel != 0 && analysis.allowFlowPlain)
                || (flowLevel == 0 && analysis.allowBlockPlain)) {
            return .plain
        }
        if analysis.allowSingleQuoted && !(simpleKeyContext && analysis.multiline) {
            return .single
        }
        return .double
    }

    // MARK: - when Jackson quotes a key

    /// Keys that Jackson quotes because YAML would read them as a different value
    /// (`StringQuotingChecker.RESERVED_KEYWORDS`).
    private static let reservedKeywords: Set<String> = [
        "false", "False", "FALSE", "n", "N", "no", "No", "NO",
        "null", "Null", "NULL", "on", "On", "ON", "off", "Off", "OFF",
        "true", "True", "TRUE", "y", "Y", "yes", "Yes", "YES",
    ]

    /// `StringQuotingChecker.Default.needToQuoteName`: a reserved word, something that
    /// starts like a number, or a control character.
    ///
    /// Mind `looksLikeYAMLNumber` — Jackson looks **only at the first character**,
    /// so it quotes `160m` and `-x` too, which are not numbers (measured).
    static func needToQuoteName(_ name: String) -> Bool {
        isReservedKeyword(name) || looksLikeYamlNumber(name) || nameHasQuotableChar(name)
    }

    private static func isReservedKeyword(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return true }  // empty key
        switch first {
        case "F", "N", "O", "T", "Y", "f", "n", "o", "t", "y":
            return reservedKeywords.contains(name)
        case "~":
            return true
        default:
            return false
        }
    }

    private static func looksLikeYamlNumber(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        switch first {
        case "+", "-", ".", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return true
        default:
            return false
        }
    }

    private static func nameHasQuotableChar(_ name: String) -> Bool {
        name.unicodeScalars.contains { $0.value < 0x20 }
    }

    // MARK: - scalar analysis

    /// Line breaks per SnakeYAML (`Constant.LINEBR`) — `\r` is **not** among them.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\u{85}" || scalar == "\u{2028}" || scalar == "\u{2029}"
    }

    /// `Constant.NULL_BL_T` — NUL, space, tab.
    private static func isNullBlankTab(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0 || scalar == " " || scalar == "\t"
    }

    /// `Constant.NULL_BL_T_LINEBR`.
    private static func isNullBlankTabLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        isNullBlankTab(scalar) || scalar == "\r" || isLineBreak(scalar)
    }

    /// `Emitter.hasLeadingZero` — `007` must not be written without quotes, because it would
    /// be read as an octal number.
    private static func hasLeadingZero(_ scalars: [Unicode.Scalar]) -> Bool {
        guard scalars.count > 1, scalars[0] == "0" else { return false }
        for scalar in scalars.dropFirst() {
            let isDigitOrUnderscore = (scalar.value >= 0x30 && scalar.value <= 0x39) || scalar == "_"
            if !isDigitOrUnderscore { return false }
        }
        return true
    }

    /// `Emitter.analyzeScalar` — a literal port, including quirks taken over
    /// for fidelity (`followedByWhitespace` is updated to the character **after** the next one
    /// and carries the `isLineBreak` of the previous character).
    ///
    /// Indexed by **Unicode scalars**, not by UTF-16 units. For the
    /// decisions it makes no difference: all compared characters are ASCII and the tests
    /// "first/last character" and "a character after the next one exists" come out the same.
    static func analyzeScalar(_ text: String, allowUnicode: Bool) -> YamlScalarAnalysis {
        let scalars = Array(text.unicodeScalars)
        if scalars.isEmpty {
            return YamlScalarAnalysis(empty: true, multiline: false, allowFlowPlain: false,
                                      allowBlockPlain: false, allowSingleQuoted: true,
                                      allowBlock: true)
        }

        var blockIndicators = false
        var flowIndicators = false
        var lineBreaks = false
        var specialCharacters = false
        let leadingZeroNumber = hasLeadingZero(scalars)

        var leadingSpace = false
        var leadingBreak = false
        var trailingSpace = false
        var trailingBreak = false
        var breakSpace = false
        var spaceBreak = false

        if text.hasPrefix("---") || text.hasPrefix("...") {
            blockIndicators = true
            flowIndicators = true
        }

        var precededByWhitespace = true
        var followedByWhitespace = scalars.count == 1 || isNullBlankTabLineBreak(scalars[1])
        var previousSpace = false
        var previousBreak = false

        var index = 0
        while index < scalars.count {
            let c = scalars[index]
            if index == 0 {
                if "#,[]{}&*!|>'\"%@`".unicodeScalars.contains(c) {
                    flowIndicators = true
                    blockIndicators = true
                }
                if c == "?" || c == ":" {
                    flowIndicators = true
                    if followedByWhitespace { blockIndicators = true }
                }
                if c == "-" && followedByWhitespace {
                    flowIndicators = true
                    blockIndicators = true
                }
            } else {
                if ",?[]{}".unicodeScalars.contains(c) {
                    flowIndicators = true
                }
                if c == ":" {
                    flowIndicators = true
                    if followedByWhitespace { blockIndicators = true }
                }
                if c == "#" && precededByWhitespace {
                    flowIndicators = true
                    blockIndicators = true
                }
            }

            let lineBreak = isLineBreak(c)
            if lineBreak { lineBreaks = true }
            if !(c == "\n" || (0x20 <= c.value && c.value <= 0x7E)) {
                if c.value == 0x85 || (0xA0...0xD7FF).contains(c.value)
                    || (0xE000...0xFFFD).contains(c.value)
                    || (0x10000...0x10FFFF).contains(c.value) {
                    if !allowUnicode { specialCharacters = true }
                } else {
                    specialCharacters = true
                }
            }

            if c == " " {
                if index == 0 { leadingSpace = true }
                if index == scalars.count - 1 { trailingSpace = true }
                if previousBreak { breakSpace = true }
                previousSpace = true
                previousBreak = false
            } else if lineBreak {
                if index == 0 { leadingBreak = true }
                if index == scalars.count - 1 { trailingBreak = true }
                if previousSpace { spaceBreak = true }
                previousSpace = false
                previousBreak = true
            } else {
                previousSpace = false
                previousBreak = false
            }

            index += 1
            precededByWhitespace = isNullBlankTab(c) || lineBreak
            followedByWhitespace = true
            if index + 1 < scalars.count {
                followedByWhitespace = isNullBlankTab(scalars[index + 1]) || lineBreak
            }
        }

        var allowFlowPlain = true
        var allowBlockPlain = true
        var allowSingleQuoted = true
        var allowBlock = true

        if leadingSpace || leadingBreak || trailingSpace || trailingBreak || leadingZeroNumber {
            allowFlowPlain = false
            allowBlockPlain = false
        }
        if trailingSpace {
            allowBlock = false
        }
        if breakSpace {
            allowFlowPlain = false
            allowBlockPlain = false
            allowSingleQuoted = false
        }
        if spaceBreak || specialCharacters {
            allowFlowPlain = false
            allowBlockPlain = false
            allowSingleQuoted = false
            allowBlock = false
        }
        if lineBreaks { allowFlowPlain = false }
        if flowIndicators { allowFlowPlain = false }
        if blockIndicators { allowBlockPlain = false }

        return YamlScalarAnalysis(empty: false, multiline: lineBreaks,
                                  allowFlowPlain: allowFlowPlain, allowBlockPlain: allowBlockPlain,
                                  allowSingleQuoted: allowSingleQuoted, allowBlock: allowBlock)
    }

    // MARK: - writer

    /// Writes text and advances the column. The column is counted in UTF-16 units,
    /// because Java adds `String.length()` there.
    private mutating func emit(_ text: String) {
        column += text.utf16.count
        out += text
    }

    /// `writeIndicator`.
    private mutating func writeIndicator(_ indicator: String, needWhitespace: Bool,
                                         whitespace: Bool, indentation: Bool) {
        if !self.whitespace && needWhitespace {
            column += 1
            out += " "
        }
        self.whitespace = whitespace
        self.indention = self.indention && indentation
        emit(indicator)
    }

    /// `writeIndent` — a line break (only when needed) and indentation.
    private mutating func writeIndent() {
        let target = indent ?? 0
        if !indention || column > target || (column == target && !whitespace) {
            writeLineBreak()
        }
        writeWhitespace(target - column)
    }

    private mutating func writeWhitespace(_ length: Int) {
        guard length > 0 else { return }
        whitespace = true
        column += length
        out += String(repeating: " ", count: length)
    }

    /// `writeLineBreak(null)` — `DumperOptions.LineBreak.UNIX`, i.e. `\n`
    /// (`USE_PLATFORM_LINE_BREAKS` is off).
    private mutating func writeLineBreak(_ data: String = "\n") {
        whitespace = true
        indention = true
        column = 0
        out += data
    }

    // MARK: scalars

    /// `Emitter.ESCAPE_REPLACEMENTS`. The key is a **UTF-16 unit**, because it is
    /// looked up unit by unit as Java does (`ESCAPE_REPLACEMENTS.containsKey(ch)`).
    private static let escapeReplacements: [UInt16: String] = [
        0x00: "0", 0x07: "a", 0x08: "b", 0x09: "t", 0x0A: "n",
        0x0B: "v", 0x0C: "f", 0x0D: "r", 0x1B: "e", 0x22: "\"",
        0x5C: "\\", 0x85: "N", 0xA0: "_", 0x2028: "L", 0x2029: "P",
    ]

    /// `StreamReader.isPrintable`.
    private static func isPrintable(_ value: UInt32) -> Bool {
        (value >= 0x20 && value <= 0x7E) || value == 0x9 || value == 0xA || value == 0xD
            || value == 0x85 || (0xA0...0xD7FF).contains(value)
            || (0xE000...0xFFFD).contains(value) || (0x10000...0x10FFFF).contains(value)
    }

    private static func text(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }

    private static func text(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// `writeDoubleQuoted` — the only style in which Jackson writes text values.
    ///
    /// Line wrapping is what keeps the output readable even to Jackson: the break is hidden
    /// behind `\` and a space at the start of the continuation is introduced by another `\`, so the value
    /// stays literal.
    ///
    /// Indexed in **UTF-16 units**, not by Unicode scalars, because the wrapping arithmetic
    /// depends on it: after writing a character outside the BMP Java moves `end`
    /// by one unit (`end++` for `charCount == 2`) and then sets `start` to
    /// `end + 1`, so in the wrapping test it gets `end - start == -1` and the boundary
    /// `end < length - 1` lies one unit higher. A port by scalars gave `-2`
    /// and a break one character elsewhere — with an emoji in a contest's `description:` the output would
    /// diverge from Jackson (measured on `"a "×38 + "😀b"` and `"😀"×40`).
    private mutating func writeDoubleQuoted(_ value: String, split: Bool) {
        writeIndicator("\"", needWhitespace: true, whitespace: false, indentation: false)
        let units = Array(value.utf16)
        var start = 0
        var end = 0
        while end <= units.count {
            let unit: UInt16? = end < units.count ? units[end] : nil
            if unit == nil || Self.needsDoubleQuoteHandling(unit!) {
                if start < end {
                    emit(Self.text(units[start..<end]))
                    start = end
                }
                if let unit {
                    let data: String
                    if let replacement = Self.escapeReplacements[unit] {
                        data = "\\" + replacement
                    } else {
                        // A surrogate pair is composed back into a code point like
                        // `Character.toCodePoint`; a Swift `String` cannot carry a lone
                        // surrogate, so the second unit is always there.
                        var codePoint = UInt32(unit)
                        var pair = false
                        if Self.isHighSurrogate(unit), end + 1 < units.count,
                           Self.isLowSurrogate(units[end + 1]) {
                            codePoint = 0x10000
                                + (UInt32(unit) - 0xD800) * 0x400
                                + (UInt32(units[end + 1]) - 0xDC00)
                            pair = true
                        }
                        if allowUnicode, Self.isPrintable(codePoint),
                           let scalar = Unicode.Scalar(codePoint) {
                            data = String(Character(scalar))
                            if pair { end += 1 }
                        } else if unit <= 0xFF {
                            data = "\\x" + Self.hex(codePoint, digits: 2)
                        } else if pair {
                            end += 1
                            data = "\\U" + Self.hex(codePoint, digits: 8)
                        } else {
                            data = "\\u" + Self.hex(codePoint, digits: 4)
                        }
                    }
                    emit(data)
                    start = end + 1
                }
            }
            if (0 < end && end < units.count - 1) && (unit == 0x20 || start >= end)
                && (column + (end - start)) > bestWidth && split {
                var data: String
                if start >= end {
                    data = "\\"
                } else {
                    data = Self.text(units[start..<end]) + "\\"
                }
                if start < end { start = end }
                emit(data)
                writeIndent()
                whitespace = false
                indention = false
                if start < units.count, units[start] == 0x20 {
                    emit("\\")
                }
            }
            end += 1
        }
        writeIndicator("\"", needWhitespace: false, whitespace: false, indentation: false)
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool { (0xD800...0xDBFF).contains(unit) }
    private static func isLowSurrogate(_ unit: UInt16) -> Bool { (0xDC00...0xDFFF).contains(unit) }

    /// Units at which `writeDoubleQuoted` interrupts a literal run. Note that
    /// `\u{FEFF}` belongs here, but no escape exists for it, so it is **written
    /// verbatim** (measured: the output contains the bytes `ef bb bf`).
    private static func needsDoubleQuoteHandling(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x22, 0x5C, 0x85, 0x2028, 0x2029, 0xFEFF:
            return true
        default:
            return !(0x20 <= unit && unit <= 0x7E)
        }
    }

    private static func hex(_ value: UInt32, digits: Int) -> String {
        let text = String(value, radix: 16, uppercase: false)
        if text.count >= digits { return text }
        return String(repeating: "0", count: digits - text.count) + text
    }

    /// `writeSingleQuoted` — SnakeYAML chooses it for a key that cannot go without
    /// quotes (`a: b`, `#c`, `*x`), but needs no double quotes because of its content.
    private mutating func writeSingleQuoted(_ value: String, split: Bool) {
        writeIndicator("'", needWhitespace: true, whitespace: false, indentation: false)
        let scalars = Array(value.unicodeScalars)
        var spaces = false
        var breaks = false
        var start = 0
        var end = 0
        while end <= scalars.count {
            let ch: Unicode.Scalar? = end < scalars.count ? scalars[end] : nil
            if spaces {
                if ch == nil || ch != " " {
                    if start + 1 == end && column > bestWidth && split && start != 0
                        && end != scalars.count {
                        writeIndent()
                    } else {
                        emit(Self.text(scalars[start..<end]))
                    }
                    start = end
                }
            } else if breaks {
                if ch == nil || !Self.isLineBreak(ch!) {
                    if scalars[start] == "\n" { writeLineBreak() }
                    for br in scalars[start..<end] {
                        if br == "\n" {
                            writeLineBreak()
                        } else {
                            writeLineBreak(String(Character(br)))
                        }
                    }
                    writeIndent()
                    start = end
                }
            } else {
                if ch == nil || Self.isLineBreak(ch!) || ch == " " || ch == "'" {
                    if start < end {
                        emit(Self.text(scalars[start..<end]))
                        start = end
                    }
                }
            }
            if ch == "'" {
                column += 2
                out += "''"
                start = end + 1
            }
            if let ch {
                spaces = ch == " "
                breaks = Self.isLineBreak(ch)
            }
            end += 1
        }
        writeIndicator("'", needWhitespace: false, whitespace: false, indentation: false)
    }

    /// `writePlain` — numbers, `true`/`false`, `null` and keys that do not
    /// need quotes.
    private mutating func writePlain(_ value: String, split: Bool) {
        // `openEnded` from Java has no business here: we write a single document, so
        // it would only show up before a second `---`.
        if value.isEmpty { return }
        if !whitespace {
            column += 1
            out += " "
        }
        whitespace = false
        indention = false
        let scalars = Array(value.unicodeScalars)
        var spaces = false
        var breaks = false
        var start = 0
        var end = 0
        while end <= scalars.count {
            let ch: Unicode.Scalar? = end < scalars.count ? scalars[end] : nil
            if spaces {
                if ch != " " {
                    if start + 1 == end && column > bestWidth && split {
                        writeIndent()
                        whitespace = false
                        indention = false
                    } else {
                        emit(Self.text(scalars[start..<end]))
                    }
                    start = end
                }
            } else if breaks {
                if ch == nil || !Self.isLineBreak(ch!) {
                    if scalars[start] == "\n" { writeLineBreak() }
                    for br in scalars[start..<end] {
                        if br == "\n" {
                            writeLineBreak()
                        } else {
                            writeLineBreak(String(Character(br)))
                        }
                    }
                    writeIndent()
                    whitespace = false
                    indention = false
                    start = end
                }
            } else {
                if ch == nil || Self.isLineBreak(ch!) || ch == " " {
                    emit(Self.text(scalars[start..<end]))
                    start = end
                }
            }
            if let ch {
                spaces = ch == " "
                breaks = Self.isLineBreak(ch)
            }
            end += 1
        }
    }
}
