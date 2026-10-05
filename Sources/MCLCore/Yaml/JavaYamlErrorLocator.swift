import Foundation

/// Line and column of a YAML syntax error **as Java reports it**.
///
/// ## Why a separate pass
///
/// Java reads YAML with Jackson on top of SnakeYAML 2.5 and reports the error via
/// `JsonProcessingException.getLocation()`. That **does not point at the error**:
/// `YAMLParser.currentLocation()` returns the end of the **last event** that
/// Jackson received from SnakeYAML (`_lastEvent.getEndMark()`), and Jackson
/// attaches it to the exception whether the scanner, the parser, or Jackson itself
/// threw. Measured: `a: [1, 2` reports 1:9 (end of scalar `2`), `a: !! 1` 1:2
/// (end of key `a`), `%YAML 1.2 junk` 1:1 (only `StreamStart` so far).
///
/// Which event is "last" depends on SnakeYAML internals: the scanner
/// does not emit a token that could be a simple key (`savePossibleSimpleKey`)
/// until it has read further and decided whether a `:` follows it -- and an error in that
/// look-ahead arrives **before** the event of that token. Add the empty scalars
/// at the start of the next token (`processEmptyScalar`), the zero widths of block
/// collections... The `YamlParser` reader works line by line and sees none of this, so
/// inferring it from the reader would be guessing case by case.
///
/// That is why this file **re-implements the SnakeYAML 2.5 scanner and event parser**
/// (`ScannerImpl`, `ParserImpl`, `StreamReader`) and, on top of them, Jackson's
/// `YAMLParser.nextToken` loop, to the extent needed for the error position:
/// tokens and events carry marks (`Mark`), scalars also their value and tag --
/// Jackson itself fails on number conversion (`s: .inf`, `!!float abc`,
/// "Malformed numeric value") at the end of that scalar, and that has to be recognised
/// in the right order relative to SnakeYAML errors. The conversion asks
/// `YamlScalarResolver`, i.e. the same Jackson model the reader uses.
/// It runs on **every** input before the reader (`YamlParser.read`):
/// a "Java fails" verdict rejects the input here too (`rejectWhatJavaRejects`),
/// and when Java succeeds, the reader reads only the text up to the end of the root node
/// (`Outcome.success(rootEnd:)`), because Jackson reads no further. It determines
/// neither the tree nor the node positions -- the reader builds those. On the error path it
/// still computes the Java position (`relocate`).
///
/// The column is counted in code points like `StreamReader` (and `U+FEFF` does not
/// advance the column; line breaks are `\n`, `\r`, `\r\n`, NEL, U+2028, U+2029).
enum JavaYamlErrorLocator {

    /// Result of the pass.
    enum Outcome: Equatable {
        /// Java would throw; the position (1-based) is the end of the last event,
        /// for nesting deeper than 1000 it is -1:-1 as in Java (see `JacksonLoop`).
        case failure(line: Int, column: Int)
        /// Java would read the document. `rootEnd` is the index (in code points
        /// of the text) of the end of the event with which Jackson finished the root node --
        /// neither `readTree` nor the loader's `readValue` reads further (default
        /// `FAIL_ON_TRAILING_TOKENS=false`). `nil` when there is no root (empty
        /// document).
        case success(rootEnd: Int?)
    }

    /// Recomputes the error position from `YamlParser` to Java's.
    ///
    /// When Java fails on the input, the position is the end of its last event.
    /// When it reads it (recorded divergences where we reject more than it does, e.g.
    /// `&x: 1`), our reader's position stays. Only `.syntax` changes; the error
    /// kind and text do not, `.unsupported` and `.type` stay as they are.
    static func relocate(_ error: YamlError, in text: String) -> YamlError {
        guard error.kind == .syntax else { return error }
        switch locate(text) {
        case .failure(let line, let column):
            return YamlError(kind: error.kind, message: error.message, line: line, column: column)
        case .success:
            return error
        }
    }

    /// Walks the text like Jackson over SnakeYAML (`ObjectMapper.readTree`).
    static func locate(_ text: String) -> Outcome {
        var jackson = JacksonLoop(parser: EventParser(scanner: Scanner(text)))
        return jackson.run()
    }
}

// MARK: - Mark

/// `org.yaml.snakeyaml.error.Mark` -- zero-based line and column, `index`
/// in code points from the start of the input.
private struct Mark: Equatable {
    var index: Int
    var line: Int
    var column: Int

    /// How Jackson converts it (`_locationFor`): both + 1.
    var position: YamlPosition { YamlPosition(line: line + 1, column: column + 1) }
}

/// A SnakeYAML or Jackson error. Neither the text nor the mark of the problem is needed --
/// Jackson reports the end of the last event anyway.
private struct JavaFailure: Error {}

// MARK: - Reading by code points (`StreamReader`)

private struct Reader {
    let data: [UInt32]
    private(set) var pointer = 0
    private(set) var line = 0
    private(set) var column = 0

    init(_ text: String) {
        data = text.unicodeScalars.map(\.value)
    }

    var index: Int { pointer }
    var mark: Mark { Mark(index: pointer, line: line, column: column) }

    /// `peek(k)`; past the end of input `\0` as in Java.
    func peek(_ offset: Int = 0) -> UInt32 {
        pointer + offset < data.count ? data[pointer + offset] : 0
    }

    /// `StreamReader.forward`: a line break resets the column, `U+FEFF` does not advance it.
    /// `\r` is a break only when not followed by `\n` (and not at the end of input).
    mutating func forward(_ length: Int = 1) {
        var i = 0
        while i < length, pointer < data.count {
            let c = data[pointer]
            pointer += 1
            if isLineBreak(c) || (c == 0x0D && pointer < data.count && data[pointer] != 0x0A) {
                line += 1
                column = 0
            } else if c != 0xFEFF {
                column += 1
            }
            i += 1
        }
    }

    /// `StreamReader.prefixForward`: advances by `length` and the column **without exceptions**
    /// adds the whole `length` (that is what Java does -- it is only called over a span without breaks).
    mutating func prefixForward(_ length: Int) {
        pointer = min(pointer + length, data.count)
        column += length
    }

    /// `prefix(n)` -- at most `n` points from the current position.
    func prefix(_ length: Int) -> ArraySlice<UInt32> {
        data[pointer..<min(pointer + length, data.count)]
    }

    func prefixEquals(_ text: String) -> Bool {
        Array(prefix(text.unicodeScalars.count)) == text.unicodeScalars.map(\.value)
    }

    /// `prefix(n)` as text.
    func prefixString(_ length: Int) -> String {
        scalarString(prefix(length))
    }
}

/// Text from code points. A lone half of a surrogate pair (`"\uD800"`)
/// cannot be held by `String`; it is replaced with U+FFFD -- this does not affect number conversion.
private func scalarString<S: Sequence>(_ values: S) -> String where S.Element == UInt32 {
    var view = String.UnicodeScalarView()
    for value in values { view.append(Unicode.Scalar(value) ?? "\u{FFFD}") }
    return String(view)
}

// MARK: - Character classes (`Constant`)

private func isLineBreak(_ c: UInt32) -> Bool {
    c == 0x0A || c == 0x85 || c == 0x2028 || c == 0x2029
}

/// `Constant.NULL_OR_LINEBR`: `\0`, `\r` and line breaks.
private func isNullOrLineBreak(_ c: UInt32) -> Bool {
    c == 0 || c == 0x0D || isLineBreak(c)
}

/// `Constant.NULL_BL_LINEBR`: plus space.
private func isNullBlankOrLineBreak(_ c: UInt32) -> Bool {
    c == 0x20 || isNullOrLineBreak(c)
}

/// `Constant.NULL_BL_T_LINEBR`: plus tab.
private func isNullBlankTabOrLineBreak(_ c: UInt32) -> Bool {
    c == 0x09 || isNullBlankOrLineBreak(c)
}

private func contains(_ set: String, _ c: UInt32) -> Bool {
    set.unicodeScalars.contains { $0.value == c }
}

/// `Constant.ALPHA`: ASCII letters, digits, `-` and `_`.
private func isAlpha(_ c: UInt32) -> Bool {
    (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)
        || c == 0x2D || c == 0x5F
}

/// `Constant.URI_CHARS`.
private func isUriChar(_ c: UInt32) -> Bool {
    isAlpha(c) || contains("-;/?:@&=+$,_.!~*'()[]%", c)
}

/// `Character.isDigit` -- **all** Unicode decimal digits, not just ASCII.
private func isJavaDigit(_ c: UInt32) -> Bool {
    Unicode.Scalar(c)?.properties.generalCategory == .decimalNumber
}

/// `Character.digit(c, 16)`: Unicode decimal digits, `a-f`/`A-F`
/// and their full-width forms.
private func isJavaHexDigit(_ c: UInt32) -> Bool {
    isJavaDigit(c)
        || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
        || (c >= 0xFF21 && c <= 0xFF26) || (c >= 0xFF41 && c <= 0xFF46)
}

/// Digit value per `Character.digit(c, 16)`.
private func javaHexValue(_ c: UInt32) -> Int {
    switch c {
    case 0x41...0x46: return Int(c - 0x41 + 10)
    case 0x61...0x66: return Int(c - 0x61 + 10)
    case 0xFF21...0xFF26: return Int(c - 0xFF21 + 10)
    case 0xFF41...0xFF46: return Int(c - 0xFF41 + 10)
    default:
        let value = Unicode.Scalar(c)?.properties.numericValue ?? 0
        return Int(value)
    }
}

/// `Integer.parseInt(text, 16)` -- returns `nil` where Java throws
/// `NumberFormatException` (optional sign, at least one digit, `int` range).
private func javaParseHex(_ text: ArraySlice<UInt32>) -> Int? {
    var chars = text
    var negative = false
    if let first = chars.first, first == 0x2B || first == 0x2D {
        negative = first == 0x2D
        chars = chars.dropFirst()
    }
    guard !chars.isEmpty, chars.allSatisfy(isJavaHexDigit) else { return nil }
    var value = 0
    for c in chars {
        value = value * 16 + javaHexValue(c)
        if value > Int(Int32.max) + 1 { return nil }
    }
    if negative { value = -value }
    guard value >= Int(Int32.min), value <= Int(Int32.max) else { return nil }
    return value
}

// MARK: - Tokeny

private enum TokenID: Equatable {
    case streamStart, streamEnd, directive, documentStart, documentEnd
    case blockSequenceStart, blockMappingStart, blockEnd
    case flowSequenceStart, flowMappingStart, flowSequenceEnd, flowMappingEnd
    case key, value, blockEntry, flowEntry, alias, anchor, tag, scalar
}

private struct Token {
    let id: TokenID
    let start: Mark
    let end: Mark
    /// Directive: name; `%YAML` carries a version, `%TAG` a handle and prefix.
    var directiveName: String? = nil
    var yamlVersion: (major: Int, minor: Int)? = nil
    var tagDirective: (handle: String, prefix: String)? = nil
    /// Tag: handle (`nil` for `!<…>` and a bare `!`) and suffix.
    var tagHandle: String? = nil
    var tagSuffix: String = ""
    /// Scalar: value and whether it is plain.
    var value: String = ""
    var plain: Bool = false
}

private struct SimpleKey {
    let tokenNumber: Int
    let required: Bool
    let index: Int
    let line: Int
    let column: Int
    let mark: Mark
}

// MARK: - Scanner (`ScannerImpl`)

/// Port of `org.yaml.snakeyaml.scanner.ScannerImpl` (SnakeYAML 2.5) without comment
/// tokens (Jackson does not enable them) and without composing values. The order of calls, checks
/// and read advances is preserved, because **when** the error arrives depends on it.
private struct Scanner {
    var reader: Reader
    var done = false
    var flowLevel = 0
    var tokens: [Token] = []
    var lastToken: Token?
    var tokensTaken = 0
    var indent = -1
    var indents: [Int] = []
    var allowSimpleKey = true
    /// `LinkedHashMap<Integer, SimpleKey>` -- insertion order by flow level.
    var possibleSimpleKeys: [(level: Int, key: SimpleKey)] = []

    init(_ text: String) {
        reader = Reader(text)
        let mark = reader.mark
        addToken(Token(id: .streamStart, start: mark, end: mark))
    }

    // MARK: scanner public interface

    mutating func check(_ choices: TokenID...) throws -> Bool {
        while try needMoreTokens() { try fetchMoreTokens() }
        guard let first = tokens.first else { return false }
        return choices.contains(first.id)
    }

    mutating func peekToken() throws -> Token {
        while try needMoreTokens() { try fetchMoreTokens() }
        return tokens[0]
    }

    mutating func getToken() -> Token {
        tokensTaken += 1
        return tokens.removeFirst()
    }

    // MARK: control

    private mutating func addToken(_ token: Token) {
        lastToken = token
        tokens.append(token)
    }

    private mutating func addToken(at index: Int, _ token: Token) {
        if index == tokens.count { lastToken = token }
        tokens.insert(token, at: index)
    }

    private mutating func needMoreTokens() throws -> Bool {
        if done { return false }
        if tokens.isEmpty { return true }
        try stalePossibleSimpleKeys()
        return nextPossibleSimpleKey() == tokensTaken
    }

    private mutating func fetchMoreTokens() throws {
        scanToNextToken()
        try stalePossibleSimpleKeys()
        unwindIndent(reader.column)
        let c = reader.peek()
        switch c {
        case 0:
            try fetchStreamEnd()
            return
        case 0x25: // %
            if checkDirective() { try fetchDirective(); return }
        case 0x2D: // -
            if checkDocumentStart() { try fetchDocumentIndicator(start: true); return }
            if checkBlockEntry() { try fetchBlockEntry(); return }
        case 0x2E: // .
            if checkDocumentEnd() { try fetchDocumentIndicator(start: false); return }
        case 0x5B: // [
            try fetchFlowCollectionStart(mapping: false); return
        case 0x7B: // {
            try fetchFlowCollectionStart(mapping: true); return
        case 0x5D: // ]
            try fetchFlowCollectionEnd(mapping: false); return
        case 0x7D: // }
            try fetchFlowCollectionEnd(mapping: true); return
        case 0x2C: // ,
            try fetchFlowEntry(); return
        case 0x3F: // ?
            if checkKey() { try fetchKey(); return }
        case 0x3A: // :
            if checkValue() { try fetchValue(); return }
        case 0x2A: // *
            try fetchAnchorOrAlias(anchor: false); return
        case 0x26: // &
            try fetchAnchorOrAlias(anchor: true); return
        case 0x21: // !
            try fetchTag(); return
        case 0x7C, 0x3E: // | >
            if flowLevel == 0 { try fetchBlockScalar(); return }
        case 0x27, 0x22: // ' "
            try fetchFlowScalar(double: c == 0x22); return
        default:
            break
        }
        if checkPlain() {
            try fetchPlain()
            return
        }
        // „found character … that cannot start any token"
        throw JavaFailure()
    }

    private func nextPossibleSimpleKey() -> Int {
        possibleSimpleKeys.first?.key.tokenNumber ?? -1
    }

    private mutating func stalePossibleSimpleKeys() throws {
        var kept: [(level: Int, key: SimpleKey)] = []
        for entry in possibleSimpleKeys {
            let key = entry.key
            if key.line != reader.line || reader.index - key.index > 1024 {
                // „while scanning a simple key … could not find expected ':'"
                if key.required { throw JavaFailure() }
            } else {
                kept.append(entry)
            }
        }
        possibleSimpleKeys = kept
    }

    private mutating func savePossibleSimpleKey() throws {
        let required = flowLevel == 0 && indent == reader.column
        // „A simple key is required only if it is the first token in the current line"
        guard allowSimpleKey || !required else { throw JavaFailure() }
        if allowSimpleKey {
            try removePossibleSimpleKey()
            let key = SimpleKey(tokenNumber: tokensTaken + tokens.count, required: required,
                                index: reader.index, line: reader.line, column: reader.column,
                                mark: reader.mark)
            possibleSimpleKeys.append((flowLevel, key))
        }
    }

    private mutating func removePossibleSimpleKey() throws {
        guard let position = possibleSimpleKeys.firstIndex(where: { $0.level == flowLevel })
        else { return }
        let key = possibleSimpleKeys.remove(at: position).key
        if key.required { throw JavaFailure() }
    }

    private mutating func unwindIndent(_ column: Int) {
        guard flowLevel == 0 else { return }
        while indent > column {
            let mark = reader.mark
            indent = indents.removeLast()
            addToken(Token(id: .blockEnd, start: mark, end: mark))
        }
    }

    private mutating func addIndent(_ column: Int) -> Bool {
        guard indent < column else { return false }
        indents.append(indent)
        indent = column
        return true
    }

    // MARK: fetch*

    private mutating func fetchStreamEnd() throws {
        unwindIndent(-1)
        try removePossibleSimpleKey()
        allowSimpleKey = false
        possibleSimpleKeys.removeAll()
        let mark = reader.mark
        addToken(Token(id: .streamEnd, start: mark, end: mark))
        done = true
    }

    private mutating func fetchDirective() throws {
        unwindIndent(-1)
        try removePossibleSimpleKey()
        allowSimpleKey = false
        addToken(try scanDirective())
    }

    private mutating func fetchDocumentIndicator(start: Bool) throws {
        unwindIndent(-1)
        try removePossibleSimpleKey()
        allowSimpleKey = false
        let startMark = reader.mark
        reader.forward(3)
        addToken(Token(id: start ? .documentStart : .documentEnd, start: startMark, end: reader.mark))
    }

    private mutating func fetchFlowCollectionStart(mapping: Bool) throws {
        try savePossibleSimpleKey()
        flowLevel += 1
        allowSimpleKey = true
        let startMark = reader.mark
        reader.forward(1)
        addToken(Token(id: mapping ? .flowMappingStart : .flowSequenceStart,
                       start: startMark, end: reader.mark))
    }

    private mutating func fetchFlowCollectionEnd(mapping: Bool) throws {
        try removePossibleSimpleKey()
        flowLevel -= 1
        allowSimpleKey = false
        let startMark = reader.mark
        reader.forward()
        addToken(Token(id: mapping ? .flowMappingEnd : .flowSequenceEnd,
                       start: startMark, end: reader.mark))
    }

    private mutating func fetchFlowEntry() throws {
        allowSimpleKey = true
        try removePossibleSimpleKey()
        let startMark = reader.mark
        reader.forward()
        addToken(Token(id: .flowEntry, start: startMark, end: reader.mark))
    }

    private mutating func fetchBlockEntry() throws {
        if flowLevel == 0 {
            // „sequence entries are not allowed here"
            guard allowSimpleKey else { throw JavaFailure() }
            if addIndent(reader.column) {
                let mark = reader.mark
                addToken(Token(id: .blockSequenceStart, start: mark, end: mark))
            }
        }
        allowSimpleKey = true
        try removePossibleSimpleKey()
        let startMark = reader.mark
        reader.forward()
        addToken(Token(id: .blockEntry, start: startMark, end: reader.mark))
    }

    private mutating func fetchKey() throws {
        if flowLevel == 0 {
            // „mapping keys are not allowed here"
            guard allowSimpleKey else { throw JavaFailure() }
            if addIndent(reader.column) {
                let mark = reader.mark
                addToken(Token(id: .blockMappingStart, start: mark, end: mark))
            }
        }
        allowSimpleKey = flowLevel == 0
        try removePossibleSimpleKey()
        let startMark = reader.mark
        reader.forward()
        addToken(Token(id: .key, start: startMark, end: reader.mark))
    }

    private mutating func fetchValue() throws {
        if let position = possibleSimpleKeys.firstIndex(where: { $0.level == flowLevel }) {
            let key = possibleSimpleKeys.remove(at: position).key
            addToken(at: key.tokenNumber - tokensTaken,
                     Token(id: .key, start: key.mark, end: key.mark))
            if flowLevel == 0, addIndent(key.column) {
                addToken(at: key.tokenNumber - tokensTaken,
                         Token(id: .blockMappingStart, start: key.mark, end: key.mark))
            }
            allowSimpleKey = false
        } else {
            // „mapping values are not allowed here"
            if flowLevel == 0, !allowSimpleKey { throw JavaFailure() }
            if flowLevel == 0, addIndent(reader.column) {
                let mark = reader.mark
                addToken(Token(id: .blockMappingStart, start: mark, end: mark))
            }
            allowSimpleKey = flowLevel == 0
            try removePossibleSimpleKey()
        }
        let startMark = reader.mark
        reader.forward()
        addToken(Token(id: .value, start: startMark, end: reader.mark))
    }

    private mutating func fetchAnchorOrAlias(anchor: Bool) throws {
        try savePossibleSimpleKey()
        allowSimpleKey = false
        addToken(try scanAnchor(anchor: anchor))
    }

    private mutating func fetchTag() throws {
        try savePossibleSimpleKey()
        allowSimpleKey = false
        addToken(try scanTag())
    }

    private mutating func fetchBlockScalar() throws {
        allowSimpleKey = true
        try removePossibleSimpleKey()
        addToken(try scanBlockScalar())
    }

    private mutating func fetchFlowScalar(double: Bool) throws {
        try savePossibleSimpleKey()
        allowSimpleKey = false
        addToken(try scanFlowScalar(double: double))
    }

    private mutating func fetchPlain() throws {
        try savePossibleSimpleKey()
        allowSimpleKey = false
        addToken(scanPlain())
    }

    // MARK: check*

    private func checkDirective() -> Bool { reader.column == 0 }

    private func checkDocumentStart() -> Bool {
        reader.column == 0 && reader.prefixEquals("---") && isNullBlankTabOrLineBreak(reader.peek(3))
    }

    private func checkDocumentEnd() -> Bool {
        reader.column == 0 && reader.prefixEquals("...") && isNullBlankTabOrLineBreak(reader.peek(3))
    }

    private func checkBlockEntry() -> Bool { isNullBlankTabOrLineBreak(reader.peek(1)) }

    private func checkKey() -> Bool { flowLevel != 0 || isNullBlankTabOrLineBreak(reader.peek(1)) }

    private func checkValue() -> Bool { flowLevel != 0 || isNullBlankTabOrLineBreak(reader.peek(1)) }

    private func checkPlain() -> Bool {
        let c = reader.peek()
        let startsPlain = !isNullBlankTabOrLineBreak(c) && !contains("-?:,[]{}#&*!|>'\"%@`", c)
        return startsPlain
            || (!isNullBlankTabOrLineBreak(reader.peek(1))
                && (c == 0x2D || (flowLevel == 0 && (c == 0x3F || c == 0x3A))))
    }

    // MARK: scan*

    private mutating func scanToNextToken() {
        if reader.index == 0, reader.peek() == 0xFEFF { reader.forward() }
        var found = false
        while !found {
            var ff = 0
            while reader.peek(ff) == 0x20 { ff += 1 }
            if ff > 0 { reader.forward(ff) }
            if reader.peek() == 0x23 { scanComment() }
            if scanLineBreak() {
                if flowLevel == 0 { allowSimpleKey = true }
            } else {
                found = true
            }
        }
    }

    private mutating func scanComment() {
        reader.forward()
        var length = 0
        while !isNullOrLineBreak(reader.peek(length)) { length += 1 }
        reader.prefixForward(length)
    }

    private mutating func scanDirective() throws -> Token {
        let startMark = reader.mark
        reader.forward()
        let name = try scanDirectiveName()
        var token = Token(id: .directive, start: startMark, end: startMark, directiveName: name)
        let endMark: Mark
        if name == "YAML" {
            token.yamlVersion = try scanYamlDirectiveValue()
            endMark = reader.mark
        } else if name == "TAG" {
            token.tagDirective = try scanTagDirectiveValue()
            endMark = reader.mark
        } else {
            endMark = reader.mark
            var ff = 0
            while !isNullOrLineBreak(reader.peek(ff)) { ff += 1 }
            if ff > 0 { reader.forward(ff) }
        }
        try scanDirectiveIgnoredLine()
        return Token(id: .directive, start: startMark, end: endMark, directiveName: name,
                     yamlVersion: token.yamlVersion, tagDirective: token.tagDirective)
    }

    private mutating func scanDirectiveName() throws -> String {
        var length = 0
        while isAlpha(reader.peek(length)) { length += 1 }
        guard length > 0 else { throw JavaFailure() }
        let name = reader.prefixString(length)
        reader.prefixForward(length)
        guard isNullBlankOrLineBreak(reader.peek()) else { throw JavaFailure() }
        return name
    }

    private mutating func scanYamlDirectiveValue() throws -> (major: Int, minor: Int) {
        while reader.peek() == 0x20 { reader.forward() }
        let major = try scanYamlDirectiveNumber()
        guard reader.peek() == 0x2E else { throw JavaFailure() }
        reader.forward()
        let minor = try scanYamlDirectiveNumber()
        guard isNullBlankOrLineBreak(reader.peek()) else { throw JavaFailure() }
        return (major, minor)
    }

    private mutating func scanYamlDirectiveNumber() throws -> Int {
        guard isJavaDigit(reader.peek()) else { throw JavaFailure() }
        var length = 0
        while isJavaDigit(reader.peek(length)) { length += 1 }
        let digits = reader.prefix(length)
        reader.prefixForward(length)
        // „found a number which cannot represent a valid version"
        guard length <= 3 else { throw JavaFailure() }
        return digits.reduce(0) { $0 * 10 + javaHexValue($1) }
    }

    private mutating func scanTagDirectiveValue() throws -> (handle: String, prefix: String) {
        while reader.peek() == 0x20 { reader.forward() }
        let handle = try scanTagHandle()
        guard reader.peek() == 0x20 else { throw JavaFailure() }
        while reader.peek() == 0x20 { reader.forward() }
        let prefix = try scanTagUri()
        guard isNullBlankOrLineBreak(reader.peek()) else { throw JavaFailure() }
        return (handle, prefix)
    }

    private mutating func scanDirectiveIgnoredLine() throws {
        while reader.peek() == 0x20 { reader.forward() }
        if reader.peek() == 0x23 { scanComment() }
        let c = reader.peek()
        if !scanLineBreak(), c != 0 { throw JavaFailure() }
    }

    private mutating func scanAnchor(anchor: Bool) throws -> Token {
        let startMark = reader.mark
        reader.forward()
        var length = 0
        var c = reader.peek(length)
        while !isNullBlankTabOrLineBreak(c), !contains(":,[]{}/.*&", c) {
            length += 1
            c = reader.peek(length)
        }
        guard length > 0 else { throw JavaFailure() }
        reader.prefixForward(length)
        c = reader.peek()
        guard isNullBlankTabOrLineBreak(c) || contains("?:,]}%@`", c) else { throw JavaFailure() }
        return Token(id: anchor ? .anchor : .alias, start: startMark, end: reader.mark)
    }

    private mutating func scanTag() throws -> Token {
        let startMark = reader.mark
        var c = reader.peek(1)
        var handle: String?
        let suffix: String
        if c == 0x3C { // <
            reader.forward(2)
            suffix = try scanTagUri()
            guard reader.peek() == 0x3E else { throw JavaFailure() }
            reader.forward()
        } else if isNullBlankTabOrLineBreak(c) {
            suffix = "!"
            reader.forward()
        } else {
            var length = 1
            var useHandle = false
            while !isNullBlankOrLineBreak(c) {
                if c == 0x21 {
                    useHandle = true
                    break
                }
                length += 1
                c = reader.peek(length)
            }
            if useHandle {
                handle = try scanTagHandle()
            } else {
                handle = "!"
                reader.forward()
            }
            suffix = try scanTagUri()
        }
        guard isNullBlankOrLineBreak(reader.peek()) else { throw JavaFailure() }
        return Token(id: .tag, start: startMark, end: reader.mark, tagHandle: handle, tagSuffix: suffix)
    }

    private mutating func scanBlockScalar() throws -> Token {
        let folded = reader.peek() == 0x3E
        var chunks = ""
        let startMark = reader.mark
        reader.forward()
        let (chomping, increment) = try scanBlockScalarIndicators()
        try scanBlockScalarIgnoredLine()
        var minIndent = indent + 1
        if minIndent < 1 { minIndent = 1 }
        var breaks: String
        var endMark: Mark
        let blockIndent: Int
        if increment == -1 {
            let (text, maxIndent, mark) = scanBlockScalarIndentation()
            breaks = text
            endMark = mark
            blockIndent = max(minIndent, maxIndent)
        } else {
            blockIndent = minIndent + increment - 1
            (breaks, endMark) = scanBlockScalarBreaks(blockIndent)
        }
        var lineBreak = ""
        while reader.column == blockIndent, reader.peek() != 0 {
            chunks += breaks
            let leadingNonSpace = reader.peek() != 0x20 && reader.peek() != 0x09
            var length = 0
            while !isNullOrLineBreak(reader.peek(length)) { length += 1 }
            chunks += reader.prefixString(length)
            reader.prefixForward(length)
            lineBreak = scanLineBreakText()
            (breaks, endMark) = scanBlockScalarBreaks(blockIndent)
            if reader.column == blockIndent, reader.peek() != 0 {
                if folded, lineBreak == "\n", leadingNonSpace,
                   reader.peek() != 0x20, reader.peek() != 0x09 {
                    if breaks.isEmpty { chunks += " " }
                } else {
                    chunks += lineBreak
                }
            } else {
                break
            }
        }
        // `chompTailIsNotFalse` / `chompTailIsTrue`
        if chomping != false { chunks += lineBreak }
        if chomping == true { chunks += breaks }
        return Token(id: .scalar, start: startMark, end: endMark, value: chunks)
    }

    /// Returns the chomping (`true` = `+`, `false` = `-`, `nil` = unspecified)
    /// and the indentation increment (`-1` = unspecified).
    private mutating func scanBlockScalarIndicators() throws -> (Bool?, Int) {
        var chomping: Bool?
        var increment = -1
        var c = reader.peek()
        if c == 0x2D || c == 0x2B {
            chomping = c == 0x2B
            reader.forward()
            c = reader.peek()
            if isJavaDigit(c) {
                increment = javaHexValue(c)
                // „expected indentation indicator in the range 1-9, but found 0"
                if increment == 0 { throw JavaFailure() }
                reader.forward()
            }
        } else if isJavaDigit(c) {
            increment = javaHexValue(c)
            if increment == 0 { throw JavaFailure() }
            reader.forward()
            c = reader.peek()
            if c == 0x2D || c == 0x2B {
                chomping = c == 0x2B
                reader.forward()
            }
        }
        guard isNullBlankOrLineBreak(reader.peek()) else { throw JavaFailure() }
        return (chomping, increment)
    }

    private mutating func scanBlockScalarIgnoredLine() throws {
        while reader.peek() == 0x20 { reader.forward() }
        if reader.peek() == 0x23 { scanComment() }
        let c = reader.peek()
        if !scanLineBreak(), c != 0 { throw JavaFailure() }
    }

    private mutating func scanBlockScalarIndentation() -> (String, Int, Mark) {
        var chunks = ""
        var maxIndent = 0
        var endMark = reader.mark
        while isLineBreak(reader.peek()) || reader.peek() == 0x20 || reader.peek() == 0x0D {
            if reader.peek() != 0x20 {
                chunks += scanLineBreakText()
                endMark = reader.mark
            } else {
                reader.forward()
                if reader.column > maxIndent { maxIndent = reader.column }
            }
        }
        return (chunks, maxIndent, endMark)
    }

    private mutating func scanBlockScalarBreaks(_ indent: Int) -> (String, Mark) {
        var chunks = ""
        var endMark = reader.mark
        var col = reader.column
        while col < indent, reader.peek() == 0x20 {
            reader.forward()
            col += 1
        }
        while true {
            let lineBreak = scanLineBreakText()
            if lineBreak.isEmpty { break }
            chunks += lineBreak
            endMark = reader.mark
            col = reader.column
            while col < indent, reader.peek() == 0x20 {
                reader.forward()
                col += 1
            }
        }
        return (chunks, endMark)
    }

    private mutating func scanFlowScalar(double: Bool) throws -> Token {
        var chunks: [UInt32] = []
        let startMark = reader.mark
        let quote = reader.peek()
        reader.forward()
        try scanFlowScalarNonSpaces(double: double, into: &chunks)
        while reader.peek() != quote {
            try scanFlowScalarSpaces(into: &chunks)
            try scanFlowScalarNonSpaces(double: double, into: &chunks)
        }
        reader.forward()
        return Token(id: .scalar, start: startMark, end: reader.mark, value: scalarString(chunks))
    }

    /// `ESCAPE_REPLACEMENTS` SnakeYAMLu.
    private static let escapeReplacements: [UInt32: UInt32] = [
        0x30: 0x00, 0x61: 0x07, 0x62: 0x08, 0x74: 0x09, 0x6E: 0x0A, 0x76: 0x0B,
        0x66: 0x0C, 0x72: 0x0D, 0x65: 0x1B, 0x20: 0x20, 0x22: 0x22, 0x5C: 0x5C,
        0x4E: 0x85, 0x5F: 0xA0, 0x4C: 0x2028, 0x50: 0x2029,
    ]

    private mutating func scanFlowScalarNonSpaces(double: Bool, into chunks: inout [UInt32]) throws {
        while true {
            var length = 0
            while true {
                let c = reader.peek(length)
                if isNullBlankTabOrLineBreak(c) || c == 0x27 || c == 0x22 || c == 0x5C { break }
                length += 1
            }
            if length != 0 {
                chunks.append(contentsOf: reader.prefix(length))
                reader.prefixForward(length)
            }
            let c = reader.peek()
            if !double, c == 0x27, reader.peek(1) == 0x27 {
                chunks.append(0x27)
                reader.forward(2)
            } else if (double && c == 0x27) || (!double && (c == 0x22 || c == 0x5C)) {
                chunks.append(c)
                reader.forward()
            } else if double, c == 0x5C {
                reader.forward()
                let e = reader.peek()
                if let replacement = Self.escapeReplacements[e] {
                    chunks.append(replacement)
                    reader.forward()
                } else if e == 0x78 || e == 0x75 || e == 0x55 { // x u U
                    let width = e == 0x78 ? 2 : (e == 0x75 ? 4 : 8)
                    reader.forward()
                    let hex = reader.prefix(width)
                    // `NOT_HEXA` looks for anything outside [0-9A-Fa-f]; a shorter remainder
                    // at the end of input passes and parseInt converts it.
                    let asciiHex = hex.allSatisfy {
                        ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66)
                    }
                    guard asciiHex else { throw JavaFailure() }
                    // `Integer.parseInt` (empty → NumberFormatException) and then
                    // `appendCodePoint` (above U+10FFFF → IllegalArgumentException).
                    guard let code = javaParseHex(hex), code >= 0, code <= 0x10FFFF else {
                        throw JavaFailure()
                    }
                    chunks.append(UInt32(code))
                    reader.forward(width)
                } else if scanLineBreak() {
                    chunks.append(contentsOf: try scanFlowScalarBreaks())
                } else {
                    // „found unknown escape character"
                    throw JavaFailure()
                }
            } else {
                return
            }
        }
    }

    private mutating func scanFlowScalarSpaces(into chunks: inout [UInt32]) throws {
        var length = 0
        while reader.peek(length) == 0x20 || reader.peek(length) == 0x09 { length += 1 }
        let whitespaces = reader.prefix(length)
        reader.prefixForward(length)
        // „found unexpected end of stream"
        if reader.peek() == 0 { throw JavaFailure() }
        let lineBreak = scanLineBreakText()
        if !lineBreak.isEmpty {
            let breaks = try scanFlowScalarBreaks()
            if lineBreak != "\n" {
                chunks.append(contentsOf: lineBreak.unicodeScalars.map(\.value))
            } else if breaks.isEmpty {
                chunks.append(0x20)
            }
            chunks.append(contentsOf: breaks)
        } else {
            chunks.append(contentsOf: whitespaces)
        }
    }

    private mutating func scanFlowScalarBreaks() throws -> [UInt32] {
        var chunks: [UInt32] = []
        while true {
            if (reader.prefixEquals("---") || reader.prefixEquals("..."))
                && isNullBlankTabOrLineBreak(reader.peek(3)) {
                // „found unexpected document separator"
                throw JavaFailure()
            }
            while reader.peek() == 0x20 || reader.peek() == 0x09 { reader.forward() }
            let lineBreak = scanLineBreakText()
            if lineBreak.isEmpty { return chunks }
            chunks.append(contentsOf: lineBreak.unicodeScalars.map(\.value))
        }
    }

    private mutating func scanPlain() -> Token {
        var chunks = ""
        let startMark = reader.mark
        var endMark = startMark
        let plainIndent = indent + 1
        var spaces = ""
        while true {
            var length = 0
            if reader.peek() == 0x23 { break }
            while true {
                let c = reader.peek(length)
                if isNullBlankTabOrLineBreak(c)
                    || (c == 0x3A && (isNullBlankTabOrLineBreak(reader.peek(length + 1))
                                      || (flowLevel != 0 && contains(",[]{}", reader.peek(length + 1)))))
                    || (flowLevel != 0 && contains(",?[]{}", c)) {
                    break
                }
                length += 1
            }
            if length == 0 { break }
            allowSimpleKey = false
            chunks += spaces
            chunks += reader.prefixString(length)
            reader.prefixForward(length)
            endMark = reader.mark
            spaces = scanPlainSpaces()
            if spaces.isEmpty || reader.peek() == 0x23 || (flowLevel == 0 && reader.column < plainIndent) {
                break
            }
        }
        return Token(id: .scalar, start: startMark, end: endMark, value: chunks, plain: true)
    }

    private mutating func scanPlainSpaces() -> String {
        var length = 0
        while reader.peek(length) == 0x20 || reader.peek(length) == 0x09 { length += 1 }
        let whitespaces = reader.prefixString(length)
        reader.prefixForward(length)
        let lineBreak = scanLineBreakText()
        guard !lineBreak.isEmpty else { return whitespaces }
        allowSimpleKey = true
        // `"---".equals(prefix) || "...".equals(prefix) && …` -- `---` without
        // checking the following character, exactly per Java operator precedence.
        if reader.prefixEquals("---")
            || (reader.prefixEquals("...") && isNullBlankTabOrLineBreak(reader.peek(3))) {
            return ""
        }
        var breaks = ""
        while true {
            if reader.peek() == 0x20 {
                reader.forward()
            } else {
                let next = scanLineBreakText()
                if next.isEmpty { break }
                breaks += next
                if reader.prefixEquals("---")
                    || (reader.prefixEquals("...") && isNullBlankTabOrLineBreak(reader.peek(3))) {
                    return ""
                }
            }
        }
        if lineBreak != "\n" { return lineBreak + breaks }
        return breaks.isEmpty ? " " : breaks
    }

    private mutating func scanTagHandle() throws -> String {
        var c = reader.peek()
        guard c == 0x21 else { throw JavaFailure() }
        var length = 1
        c = reader.peek(length)
        if c != 0x20 {
            while isAlpha(c) {
                length += 1
                c = reader.peek(length)
            }
            guard c == 0x21 else {
                reader.forward(length)
                throw JavaFailure()
            }
            length += 1
        }
        let handle = reader.prefixString(length)
        reader.prefixForward(length)
        return handle
    }

    private mutating func scanTagUri() throws -> String {
        var chunks = ""
        var length = 0
        var c = reader.peek(length)
        while isUriChar(c) {
            if c == 0x25 {
                chunks += reader.prefixString(length)
                reader.prefixForward(length)
                length = 0
                chunks += try scanUriEscapes()
            } else {
                length += 1
            }
            c = reader.peek(length)
        }
        if length != 0 {
            chunks += reader.prefixString(length)
            reader.prefixForward(length)
        }
        // „expected URI"
        guard !chunks.isEmpty else { throw JavaFailure() }
        return chunks
    }

    private mutating func scanUriEscapes() throws -> String {
        var bytes: [UInt8] = []
        while reader.peek() == 0x25 {
            reader.forward()
            guard let code = javaParseHex(reader.prefix(2)) else { throw JavaFailure() }
            bytes.append(UInt8(truncatingIfNeeded: code))
            reader.forward(2)
        }
        // `UriEncoder.decode` -- strict UTF-8, otherwise "expected URI in UTF-8".
        var decoded: [UInt32] = []
        let failed = transcode(bytes.makeIterator(), from: UTF8.self, to: UTF32.self,
                               stoppingOnError: true, into: { decoded.append($0) })
        if failed { throw JavaFailure() }
        return scalarString(decoded)
    }

    /// `scanLineBreak`: `\r\n`, `\r`, `\n` and NEL yield `"\n"`, U+2028/U+2029
    /// themselves; without a break `""`.
    private mutating func scanLineBreakText() -> String {
        let c = reader.peek()
        if c == 0x0D || c == 0x0A || c == 0x85 {
            if c == 0x0D, reader.peek(1) == 0x0A { reader.forward(2) } else { reader.forward() }
            return "\n"
        }
        if c == 0x2028 || c == 0x2029 {
            reader.forward()
            return scalarString([c])
        }
        return ""
    }

    private mutating func scanLineBreak() -> Bool {
        !scanLineBreakText().isEmpty
    }
}

// MARK: - Event parser (`ParserImpl`)

private enum EventID {
    case streamStart, streamEnd, documentStart, documentEnd, alias, scalar
    case sequenceStart, sequenceEnd, mappingStart, mappingEnd
}

private struct Event {
    let id: EventID
    let start: Mark
    let end: Mark
    /// Scalar: value, resolved tag (`nil` = none) and whether it is plain.
    var value: String = ""
    var tag: String? = nil
    var plain: Bool = false
}

/// `ParserImpl` states (productions). Comment states are missing -- without comment
/// tokens they are never entered.
private enum Production {
    case streamStart, implicitDocumentStart, documentStart, documentEnd, documentContent
    case blockNode
    case blockSequenceFirstEntry, blockSequenceEntryKey
    case indentlessSequenceEntryKey
    case blockMappingFirstKey, blockMappingKey, blockMappingValue
    case flowSequenceFirstEntry, flowSequenceEntry(first: Bool)
    case flowSequenceEntryMappingKey, flowSequenceEntryMappingValue, flowSequenceEntryMappingEnd
    case flowMappingFirstKey, flowMappingKey(first: Bool), flowMappingValue, flowMappingEmptyValue
}

private struct EventParser {
    var scanner: Scanner
    var state: Production? = .streamStart
    var states: [Production] = []
    /// Handles and their prefixes valid in the document (`directives.getTags()`).
    var tagPrefixes: [String: String] = Self.defaultTags

    static let defaultTags = ["!": "!", "!!": "tag:yaml.org,2002:"]

    init(scanner: Scanner) {
        self.scanner = scanner
    }

    mutating func getEvent() throws -> Event? {
        guard let current = state else { return nil }
        return try produce(current)
    }

    private mutating func popState() -> Production? {
        states.popLast()
    }

    private mutating func produce(_ production: Production) throws -> Event {
        switch production {
        case .streamStart:
            let token = scanner.getToken()
            state = .implicitDocumentStart
            return Event(id: .streamStart, start: token.start, end: token.end)

        case .implicitDocumentStart:
            if !(try scanner.check(.directive, .documentStart, .streamEnd)) {
                let token = try scanner.peekToken()
                states.append(.documentEnd)
                state = .blockNode
                return Event(id: .documentStart, start: token.start, end: token.start)
            }
            return try produce(.documentStart)

        case .documentStart:
            while try scanner.check(.documentEnd) { _ = scanner.getToken() }
            if !(try scanner.check(.streamEnd)) {
                let startMark = try scanner.peekToken().start
                try processDirectives()
                if !(try scanner.check(.streamEnd)) {
                    // „expected '<document start>', but found …"
                    guard try scanner.check(.documentStart) else { throw JavaFailure() }
                    let token = scanner.getToken()
                    states.append(.documentEnd)
                    state = .documentContent
                    return Event(id: .documentStart, start: startMark, end: token.end)
                }
            }
            let token = scanner.getToken()
            // „Unexpected end of stream. States left"
            guard states.isEmpty else { throw JavaFailure() }
            state = nil
            return Event(id: .streamEnd, start: token.start, end: token.end)

        case .documentEnd:
            var token = try scanner.peekToken()
            let startMark = token.start
            var endMark = startMark
            if try scanner.check(.documentEnd) {
                token = scanner.getToken()
                endMark = token.end
            }
            state = .documentStart
            return Event(id: .documentEnd, start: startMark, end: endMark)

        case .documentContent:
            if try scanner.check(.directive, .documentStart, .documentEnd, .streamEnd) {
                let event = emptyScalar(try scanner.peekToken().start)
                state = popState()
                return event
            }
            return try parseNode(block: true, indentlessSequence: false)

        case .blockNode:
            return try parseNode(block: true, indentlessSequence: false)

        case .blockSequenceFirstEntry:
            _ = scanner.getToken()
            return try produce(.blockSequenceEntryKey)

        case .blockSequenceEntryKey:
            if try scanner.check(.blockEntry) {
                let token = scanner.getToken()
                if !(try scanner.check(.blockEntry, .blockEnd)) {
                    states.append(.blockSequenceEntryKey)
                    return try parseNode(block: true, indentlessSequence: false)
                }
                state = .blockSequenceEntryKey
                return emptyScalar(token.end)
            }
            // „while parsing a block collection … expected <block end>"
            guard try scanner.check(.blockEnd) else { throw JavaFailure() }
            let token = scanner.getToken()
            state = popState()
            return Event(id: .sequenceEnd, start: token.start, end: token.end)

        case .indentlessSequenceEntryKey:
            if try scanner.check(.blockEntry) {
                let token = scanner.getToken()
                if !(try scanner.check(.blockEntry, .key, .value, .blockEnd)) {
                    states.append(.indentlessSequenceEntryKey)
                    return try parseNode(block: true, indentlessSequence: false)
                }
                state = .indentlessSequenceEntryKey
                return emptyScalar(token.end)
            }
            let token = try scanner.peekToken()
            state = popState()
            return Event(id: .sequenceEnd, start: token.start, end: token.end)

        case .blockMappingFirstKey:
            _ = scanner.getToken()
            return try produce(.blockMappingKey)

        case .blockMappingKey:
            if try scanner.check(.key) {
                let token = scanner.getToken()
                if !(try scanner.check(.key, .value, .blockEnd)) {
                    states.append(.blockMappingValue)
                    return try parseNode(block: true, indentlessSequence: true)
                }
                state = .blockMappingValue
                return emptyScalar(token.end)
            }
            // „while parsing a block mapping … expected <block end>"
            guard try scanner.check(.blockEnd) else { throw JavaFailure() }
            let token = scanner.getToken()
            state = popState()
            return Event(id: .mappingEnd, start: token.start, end: token.end)

        case .blockMappingValue:
            if try scanner.check(.value) {
                let token = scanner.getToken()
                if !(try scanner.check(.key, .value, .blockEnd)) {
                    states.append(.blockMappingKey)
                    return try parseNode(block: true, indentlessSequence: true)
                }
                state = .blockMappingKey
                return emptyScalar(token.end)
            } else if try scanner.check(.scalar) {
                states.append(.blockMappingKey)
                return try parseNode(block: true, indentlessSequence: true)
            }
            state = .blockMappingKey
            return emptyScalar(try scanner.peekToken().start)

        case .flowSequenceFirstEntry:
            _ = scanner.getToken()
            return try produce(.flowSequenceEntry(first: true))

        case .flowSequenceEntry(let first):
            if !(try scanner.check(.flowSequenceEnd)) {
                if !first {
                    // „while parsing a flow sequence … expected ',' or ']'"
                    guard try scanner.check(.flowEntry) else { throw JavaFailure() }
                    _ = scanner.getToken()
                }
                if try scanner.check(.key) {
                    let token = try scanner.peekToken()
                    state = .flowSequenceEntryMappingKey
                    return Event(id: .mappingStart, start: token.start, end: token.end)
                } else if !(try scanner.check(.flowSequenceEnd)) {
                    states.append(.flowSequenceEntry(first: false))
                    return try parseNode(block: false, indentlessSequence: false)
                }
            }
            let token = scanner.getToken()
            // `if (!scanner.checkToken(Token.ID.Comment))` -- Java looks at the next
            // token **before** it emits the end of the sequence, so an error after `]`
            // (`a: [1]<TAB>`) arrives even before this event.
            _ = try scanner.check(.streamEnd)
            state = popState()
            return Event(id: .sequenceEnd, start: token.start, end: token.end)

        case .flowSequenceEntryMappingKey:
            let token = scanner.getToken()
            if !(try scanner.check(.value, .flowEntry, .flowSequenceEnd)) {
                states.append(.flowSequenceEntryMappingValue)
                return try parseNode(block: false, indentlessSequence: false)
            }
            state = .flowSequenceEntryMappingValue
            return emptyScalar(token.end)

        case .flowSequenceEntryMappingValue:
            if try scanner.check(.value) {
                let token = scanner.getToken()
                if !(try scanner.check(.flowEntry, .flowSequenceEnd)) {
                    states.append(.flowSequenceEntryMappingEnd)
                    return try parseNode(block: false, indentlessSequence: false)
                }
                state = .flowSequenceEntryMappingEnd
                return emptyScalar(token.end)
            }
            state = .flowSequenceEntryMappingEnd
            return emptyScalar(try scanner.peekToken().start)

        case .flowSequenceEntryMappingEnd:
            state = .flowSequenceEntry(first: false)
            let token = try scanner.peekToken()
            return Event(id: .mappingEnd, start: token.start, end: token.end)

        case .flowMappingFirstKey:
            _ = scanner.getToken()
            return try produce(.flowMappingKey(first: true))

        case .flowMappingKey(let first):
            if !(try scanner.check(.flowMappingEnd)) {
                if !first {
                    // „while parsing a flow mapping … expected ',' or '}'"
                    guard try scanner.check(.flowEntry) else { throw JavaFailure() }
                    _ = scanner.getToken()
                }
                if try scanner.check(.key) {
                    let token = scanner.getToken()
                    if !(try scanner.check(.value, .flowEntry, .flowMappingEnd)) {
                        states.append(.flowMappingValue)
                        return try parseNode(block: false, indentlessSequence: false)
                    }
                    state = .flowMappingValue
                    return emptyScalar(token.end)
                } else if !(try scanner.check(.flowMappingEnd)) {
                    states.append(.flowMappingEmptyValue)
                    return try parseNode(block: false, indentlessSequence: false)
                }
            }
            let token = scanner.getToken()
            // The same comment peek as at the end of a flow sequence.
            _ = try scanner.check(.streamEnd)
            state = popState()
            return Event(id: .mappingEnd, start: token.start, end: token.end)

        case .flowMappingValue:
            if try scanner.check(.value) {
                let token = scanner.getToken()
                if !(try scanner.check(.flowEntry, .flowMappingEnd)) {
                    states.append(.flowMappingKey(first: false))
                    return try parseNode(block: false, indentlessSequence: false)
                }
                state = .flowMappingKey(first: false)
                return emptyScalar(token.end)
            }
            state = .flowMappingKey(first: false)
            return emptyScalar(try scanner.peekToken().start)

        case .flowMappingEmptyValue:
            state = .flowMappingKey(first: false)
            return emptyScalar(try scanner.peekToken().start)
        }
    }

    /// `processDirectives` -- only what can fail: two `%YAML`, version ≠ 1.x,
    /// the same handle twice; and the set of handles for `parseNode`.
    private mutating func processDirectives() throws {
        var handles = tagPrefixes
        for key in Self.defaultTags.keys { handles[key] = nil }
        var sawYaml = false
        while try scanner.check(.directive) {
            let token = scanner.getToken()
            if token.directiveName == "YAML" {
                // „found duplicate YAML directive"
                if sawYaml { throw JavaFailure() }
                // „found incompatible YAML document (version 1.* is required)"
                guard token.yamlVersion?.major == 1 else { throw JavaFailure() }
                sawYaml = true
            } else if token.directiveName == "TAG", let directive = token.tagDirective {
                // „duplicate tag handle"
                if handles[directive.handle] != nil { throw JavaFailure() }
                handles[directive.handle] = directive.prefix
            }
        }
        for (key, prefix) in Self.defaultTags where handles[key] == nil { handles[key] = prefix }
        tagPrefixes = handles
    }

    private mutating func parseNode(block: Bool, indentlessSequence: Bool) throws -> Event {
        if try scanner.check(.alias) {
            let token = scanner.getToken()
            state = popState()
            return Event(id: .alias, start: token.start, end: token.end)
        }
        var startMark: Mark?
        var endMark: Mark?
        var hasProperty = false
        var tagToken: Token?
        if try scanner.check(.anchor) {
            let token = scanner.getToken()
            startMark = token.start
            endMark = token.end
            hasProperty = true
            if try scanner.check(.tag) {
                let tag = scanner.getToken()
                endMark = tag.end
                tagToken = tag
            }
        } else if try scanner.check(.tag) {
            let tag = scanner.getToken()
            startMark = tag.start
            endMark = tag.end
            tagToken = tag
            hasProperty = true
            if try scanner.check(.anchor) {
                endMark = scanner.getToken().end
            }
        }
        var tag: String?
        if let tagToken {
            if let handle = tagToken.tagHandle {
                // „while parsing a node … found undefined tag handle"
                guard let prefix = tagPrefixes[handle] else { throw JavaFailure() }
                tag = prefix + tagToken.tagSuffix
            } else {
                tag = tagToken.tagSuffix
            }
        }
        if startMark == nil {
            let mark = try scanner.peekToken().start
            startMark = mark
            endMark = mark
        }
        let start = startMark!
        if indentlessSequence, try scanner.check(.blockEntry) {
            let end = try scanner.peekToken().end
            state = .indentlessSequenceEntryKey
            return Event(id: .sequenceStart, start: start, end: end)
        }
        if try scanner.check(.scalar) {
            let token = scanner.getToken()
            state = popState()
            return Event(id: .scalar, start: start, end: token.end,
                         value: token.value, tag: tag, plain: token.plain)
        }
        if try scanner.check(.flowSequenceStart) {
            let end = try scanner.peekToken().end
            state = .flowSequenceFirstEntry
            return Event(id: .sequenceStart, start: start, end: end)
        }
        if try scanner.check(.flowMappingStart) {
            let end = try scanner.peekToken().end
            state = .flowMappingFirstKey
            return Event(id: .mappingStart, start: start, end: end)
        }
        if block, try scanner.check(.blockSequenceStart) {
            let end = try scanner.peekToken().start
            state = .blockSequenceFirstEntry
            return Event(id: .sequenceStart, start: start, end: end)
        }
        if block, try scanner.check(.blockMappingStart) {
            let end = try scanner.peekToken().start
            state = .blockMappingFirstKey
            return Event(id: .mappingStart, start: start, end: end)
        }
        if hasProperty {
            state = popState()
            return Event(id: .scalar, start: start, end: endMark!, tag: tag, plain: true)
        }
        // „while parsing a block/flow node … expected the node content"
        throw JavaFailure()
    }

    private func emptyScalar(_ mark: Mark) -> Event {
        Event(id: .scalar, start: mark, end: mark, plain: true)
    }
}

// MARK: - Jackson loop (`YAMLParser.nextToken` + `readTree`)

/// Jackson takes events until it has read **one** root value
/// (`readTree` without `FAIL_ON_TRAILING_TOKENS`). It itself rejects a non-scalar key
/// ("Expected a field name") and a decimal number it cannot convert ("Malformed
/// numeric value"). The position of every error is the end of the last event it
/// took -- including the one it failed on itself.
///
/// Position exception: nesting depth above `maxNestingDepth`
/// (`StreamReadConstraints`, "Document nesting depth (1001) exceeds the maximum
/// allowed (1000…)") is a `StreamConstraintsException` **without a position**, Java
/// reports -1:-1 (measured by `ProbeErr`). Jackson stops on it right at the 1001st start
/// of a collection, so we do too -- otherwise the pass would keep scanning the rest of the deep
/// input (flow `[[[…` is quadratic in depth in SnakeYAML).
private struct JacksonLoop {
    var parser: EventParser

    /// `StreamReadConstraints.DEFAULT_MAX_DEPTH` Jacksonu 2.22.
    static let maxNestingDepth = 1000

    private enum Context { case object(expectingName: Bool), array }

    mutating func run() -> JavaYamlErrorLocator.Outcome {
        var lastEvent: Event?
        var contexts: [Context] = []
        var sawRootValue = false
        do {
            while let event = try parser.getEvent() {
                lastEvent = event
                if case .object(expectingName: true)? = contexts.last {
                    switch event.id {
                    case .mappingEnd:
                        contexts.removeLast()
                        if contexts.isEmpty { return .success(rootEnd: event.end.index) }
                        markValueDone(&contexts)
                        continue
                    case .scalar:
                        contexts[contexts.count - 1] = .object(expectingName: false)
                        continue
                    default:
                        // „Expected a field name (Scalar value in YAML), got this instead"
                        throw JavaFailure()
                    }
                }
                switch event.id {
                case .streamStart, .documentStart, .documentEnd:
                    continue
                case .streamEnd:
                    return .success(rootEnd: nil)
                case .scalar, .alias:
                    if event.id == .scalar, !Self.jacksonDecodes(event) { throw JavaFailure() }
                    if contexts.isEmpty { sawRootValue = true }
                    markValueDone(&contexts)
                case .mappingStart:
                    contexts.append(.object(expectingName: true))
                    if contexts.count > Self.maxNestingDepth { return .failure(line: -1, column: -1) }
                case .sequenceStart:
                    contexts.append(.array)
                    if contexts.count > Self.maxNestingDepth { return .failure(line: -1, column: -1) }
                case .sequenceEnd:
                    contexts.removeLast()
                    if contexts.isEmpty { return .success(rootEnd: event.end.index) }
                    markValueDone(&contexts)
                case .mappingEnd:
                    // „Not expecting END_OBJECT but a value"
                    throw JavaFailure()
                }
                if sawRootValue { return .success(rootEnd: rootScalarEnd(event)) }
            }
            return .success(rootEnd: nil)
        } catch {
            let end = lastEvent?.end.position ?? YamlPosition(line: 1, column: 1)
            return .failure(line: end.line, column: end.column)
        }
    }

    /// Where the reader may stop after a root scalar: the end of its event.
    ///
    /// Exception: a **plain** scalar ending in a colon (`b:` in `a` + `b::  2`,
    /// Java "a b:") would, once cut, have `:` at the end of the text and the reader would
    /// make a key of it. Such a scalar is extended to the end of the line; the rest of the line after ": "
    /// is terminated by the reader itself (`plainText`).
    private func rootScalarEnd(_ event: Event) -> Int {
        let data = parser.scanner.reader.data
        let end = event.end.index
        guard event.id == .scalar, event.plain, end > event.start.index,
              end <= data.count, data[end - 1] == 0x3A else { return end }
        var index = end
        while index < data.count, !isLineBreak(data[index]), data[index] != 0x0D { index += 1 }
        return index
    }

    /// Does Jackson convert the scalar value (`YAMLParser._decodeScalar` and then
    /// `getNumberValue`)? Only a decimal number can fail; the conversion model is
    /// `YamlScalarResolver`, same as in the reader. An integer outside `Int`
    /// (`.unsupported` for us) is a `BigInteger` in Java, so it passes.
    private static func jacksonDecodes(_ event: Event) -> Bool {
        if event.value.isEmpty { return true }
        do {
            if event.tag == nil || event.tag == "!" {
                // Implicit typing: plain without a tag, or anything with a `!` tag.
                if event.plain || event.tag == "!" {
                    _ = try YamlScalarResolver.resolve(event.value, line: 0, column: 0)
                }
                return true
            }
            let prefix = "tag:yaml.org,2002:"
            guard let tag = event.tag, tag.hasPrefix(prefix) else { return true }
            let name = tag.dropFirst(prefix.count).split(separator: ",", omittingEmptySubsequences: false).first
            guard name == "float" else { return true }
            _ = try YamlScalarResolver.resolve(tag: .float, text: event.value, line: 0, column: 0)
            return true
        } catch let error as YamlError {
            return error.kind != .syntax
        } catch {
            return true
        }
    }

    /// The value in the object has been read -- the next key is awaited.
    private func markValueDone(_ contexts: inout [Context]) {
        if case .object? = contexts.last {
            contexts[contexts.count - 1] = .object(expectingName: true)
        }
    }
}
