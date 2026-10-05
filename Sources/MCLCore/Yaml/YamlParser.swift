import Foundation

/// Reader for the supported subset of YAML.
///
/// Why custom: Java uses Jackson (`jackson-dataformat-yaml` + SnakeYAML),
/// Swift must not have an external dependency. That is only tolerable because
/// our YAML is a verifiably limited subset — none of the files in `contest-data/`
/// contain anchors, aliases or block scalars.
///
/// **Typing of unquoted scalars follows Jackson, not the YAML spec** (see
/// `YamlScalarResolver`). Values in the contest definitions rely on it: `160m` must
/// be text, `48` a number.
///
/// This file handles scalars (including multi-line and block `|`/`>`), type
/// tags (`!!str`, `!!int`…) and the `%TAG` directive, block maps and block
/// sequences nested by indentation including the explicit key (`? key` / `: value`),
/// flow notation (`{}`, `[]`), comments and **anchors** (`&name`, which are discarded
/// just as in Java — see `anchorTokenEnd`). Constructs outside the subset
/// (aliases) are rejected **loudly** as `YamlError.Kind.unsupported`, never
/// swallowed as text — see `unsupportedStart`.
///
/// **The reader must read everything `YamlWriter` writes** — the writer is used by
/// `BandPlanFile.write` and a file the application saves itself must be loadable
/// again. The three shapes the writer produces therefore have support, even though
/// nobody wrote them in `contest-data/`: content on the `---` line (root scalar,
/// `{}`, `[]`), the explicit key `? ` (empty, multi-line or ≥128 UTF-16
/// units) and `Int.min`. This is guarded by
/// `YamlWriterTests.roundTripThroughWriterCoversEveryValueKind`.
///
/// Contest definitions **never** go through the tree by the path "read, modify,
/// write": the Java `DefinitionEditing` works with **text** (a template via
/// `String.formatted`, `withId` as a regex replacement of one line, `save`
/// writes the user's text), so comments and formatting of the definition are preserved.
/// Swift has to copy this (measured on Java v1.1.1).
///
/// Besides the tree, the reader can also return **node positions** (`parseDocument(_:)`,
/// `YamlPositions`) — line and column in the type errors of
/// `YamlDecoder` rely on them. They are collected while building the tree; `parse(_:)` does not collect them.
///
/// The line and column of a **syntax** error are Java's: Jackson
/// reports them at the end of the last event it received from SnakeYAML, not at the place
/// of the error (`a: [1, 2` → 1:9). `JavaYamlErrorLocator` computes them, see
/// `javaPositioned`.
///
/// **What Java rejects, we reject too, and what it does not read past the root node, we do not read
/// either**: the text is first run through the SnakeYAML port — see `read`.
public enum YamlParser {

    /// Parses the whole document. An empty document is `.null`.
    ///
    /// For empty input Java returns `MissingNode`, not `NullNode`; for our
    /// callers both behave the same (missing value → default).
    public static func parse(_ text: String) throws -> YamlValue {
        try read(text, recordsPositions: false).root
    }

    /// Parses the document and returns the tree **with node positions**.
    ///
    /// The tree is **the same** as from `parse(_:)` — positions are collected alongside it, while
    /// building it (see `YamlPositions`), with no additional searching in the text.
    /// Parser errors are the same too.
    public static func parseDocument(_ text: String) throws -> YamlDocument {
        try read(text, recordsPositions: true)
    }

    /// Shared reading for `parse` and `parseDocument`.
    ///
    /// First the text is run through the SnakeYAML port (`JavaYamlErrorLocator.locate`)
    /// and it is read according to its verdict:
    ///
    /// - **Java reads the input** → the reader reads only the text **up to the end of the root
    ///   node**. Jackson does not read on (`readTree` and the loader's `readValue`,
    ///   `FAIL_ON_TRAILING_TOKENS=false`), so Java silently discards content after the root
    ///   — even invalid: `[1] x` → `[1]`, `  id: x` + `name: y` →
    ///   `{"id":"x"}`. We copy this (a deliberate choice,
    ///   "Java errors are copied", just like the second document after `---`).
    /// - **Java rejects the input** → the reader reads the whole text; its own
    ///   syntax error gets the Java position (`javaPositioned`), and when the
    ///   reader finds nothing, the safeguard rejects the input (`rejectWhatJavaRejects`).
    static func read(_ text: String, recordsPositions: Bool) throws -> YamlDocument {
        let outcome = JavaYamlErrorLocator.locate(text)
        var source = text
        if case .success(let rootEnd?) = outcome {
            let scalars = text.unicodeScalars
            if rootEnd < scalars.count {
                let cut = scalars.index(scalars.startIndex, offsetBy: rootEnd)
                source = String(scalars[..<cut])
            }
        }
        let lines = SourceLine.split(source)
        var parser = BlockParser(lines: lines, recordsPositions: recordsPositions)
        let root: YamlValue
        do {
            root = try parser.parseDocument()
        } catch let tooDeep as NestingTooDeep {
            // Own position (start of the collection over the limit), no moving
            // to the Java one: Java reads up to depth 1000, above that it reports -1:-1.
            throw YamlError(message: "příliš hluboké zanoření: víc než \(maxNestingDepth) úrovní map a sekvencí",
                            line: tooDeep.line,
                            column: codePointColumn(line: tooDeep.line, column: tooDeep.column,
                                                    lines: lines))
        } catch {
            throw javaPositioned(error, text: text, lines: lines)
        }
        try rejectWhatJavaRejects(outcome)
        return YamlDocument(root: root, positions: parser.positions,
                            isEmptyStream: parser.isEmptyStream, shadowed: parser.shadowed)
    }

    /// The most nested collections (maps and sequences, block and flow,
    /// counted like Jackson's `StreamReadConstraints.maxNestingDepth`: the root
    /// collection is level 1, the single-pair map `[x: y]` is a level too). Deeper
    /// input is a syntax error — a **divergence from Java**, which reads up to depth
    /// 1000 (a deliberate divergence from Java v1.1.1).
    ///
    /// Why a limit: the reader is recursive and on a Swift concurrency thread (stack
    /// 512 KB) deep nesting would overflow the stack and bring down the whole process —
    /// the definition is downloaded by `DefinitionUpdater` from the network. Why 16: real definitions
    /// have at most 7 levels (the test `type-deep-condition.yaml` 9). The most expensive
    /// reader path is flow with an anchor and a tag on every level (`[&a !!seq [&a …`);
    /// in a **debug** build (how tests run) on a 512 KB thread it crashed from
    /// 11 levels, after splitting the recursive functions (see `flowNodeValue`) from 32;
    /// the other reader paths and the definition decoder (`Condition.not`) go higher.
    /// 16 is thus roughly half of the worst case. Release crashes around 100.
    /// The depth limit is a deliberate divergence from Java v1.1.1; guarded by `YamlNestingDepthTests`.
    static let maxNestingDepth = 16

    /// Throws a syntax error when Java (Jackson `readTree` over
    /// SnakeYAML 2.5) would **reject** input that our reader read.
    ///
    /// Why a safeguard after reading instead of fixes in the reader: fuzzing found
    /// about twenty classes of such inputs (a comma or `]` at the start of a key,
    /// an invalid escape in a quoted key, a tab after an anchor, an incomplete
    /// directive, `%YAML 11.3`, two tags on a sequence item…), each
    /// in a different corner of the SnakeYAML scanner. `JavaYamlErrorLocator` is a port of that
    /// scanner and parser and its verdict "Java fails / does not fail" agrees with Java
    /// on all 176,977 fuzz inputs (61,500 accepted, 115,477 rejected,
    /// all positions identical) — see a maintainer-only probe.
    /// It does not decide the tree's **value**, only acceptance; the reader still builds the tree.
    ///
    /// The position is Java's (end of the last event), the message text our own.
    static func rejectWhatJavaRejects(_ outcome: JavaYamlErrorLocator.Outcome) throws {
        if case .failure(let line, let column) = outcome {
            throw YamlError(message: "neplatný zápis YAML", line: line, column: column)
        }
    }

    /// Error position as Java shows it — see `JavaYamlErrorLocator`.
    ///
    /// The reader itself counts the error column as an offset in `Character` (graphemes)
    /// on the line; it is first converted to **code points** (that is how SnakeYAML counts),
    /// then the syntax error is moved to where Jackson puts it: to the end of the
    /// last event before the error. Neither the kind nor the text of the error changes.
    static func javaPositioned(_ error: Error, text: String, lines: [SourceLine]) -> Error {
        guard let own = error as? YamlError, own.kind == .syntax else { return error }
        let converted = YamlError(kind: own.kind, message: own.message, line: own.line,
                                  column: codePointColumn(line: own.line, column: own.column,
                                                          lines: lines))
        return JavaYamlErrorLocator.relocate(converted, in: text)
    }

    /// Column `column` (from 1, in graphemes after the line indent) converted to
    /// code points. Indents are spaces, so one point per character.
    static func codePointColumn(line: Int, column: Int, lines: [SourceLine]) -> Int {
        guard line >= 1, line <= lines.count else { return column }
        let source = lines[line - 1]
        let indent = source.leadingSpaces
        guard column - 1 > indent else { return column }
        let body = Array(source.raw.unicodeScalars.dropFirst(indent))
        let graphemes = Array(String(String.UnicodeScalarView(body)))
        let taken = graphemes.prefix(column - 1 - indent)
        return indent + taken.reduce(0) { $0 + $1.unicodeScalars.count } + 1
            + max(0, column - 1 - indent - graphemes.count)
    }
}

/// A collection over `YamlParser.maxNestingDepth`; `read` turns it into a `YamlError`
/// with its own position (column in graphemes like the other reader errors).
struct NestingTooDeep: Error {
    let line: Int
    let column: Int
}

// MARK: - Lines

/// One input line: number, indent and content without the indent and without trailing
/// spaces. Empty content = empty line.
struct SourceLine {
    let number: Int
    let indent: Int
    let text: String
    /// Was there a tab in the trailing spaces that were cut off the line?
    ///
    /// Java rejects it everywhere after the last closed node where a further
    /// token is expected (`b: [1] <TAB>`, `d: "x" <TAB>`, `a: <TAB>`), but after a plain
    /// scalar `scanPlainSpaces` swallows it (`a: 1 <TAB>` passes). Only `scanLine` can
    /// decide that, so it is merely remembered here.
    let trailingTab: Bool
    /// The whole line unchanged. A block scalar takes its content **literally** — trailing
    /// spaces are content in it (`a: |` + `  x  ` is "x  \n") and the indent
    /// is measured in characters — so `text` with trimmed spaces is not enough for it.
    /// For the same reason the block header and `parseBlockScalar` read from `raw`: `text`
    /// would hide whether `|` was followed by a tab or a space and a tab.
    let raw: String
    /// The line break that **ended** this line — as returned
    /// by SnakeYAML's `ScannerImpl.scanLineBreak`, not as it was in the file:
    /// for `\n`, `\r\n`, `\r` and NEL (U+0085) it is `"\n"`, for U+2028 and U+2029
    /// **the character itself**. The last element of `lines` has it empty ("the file does not
    /// continue"), so it also reveals text without a trailing break.
    ///
    /// Folding relies on this difference: a single break `"\n"` folds into a space,
    /// whereas a single U+2028 folds **into itself** (measured: `a: x<U+2028>␣␣y` is
    /// "x<U+2028>y", `a: x␣␣y" through `\n` is "x y"). See `foldBreaks(_:)`.
    let terminator: String
    /// Column (from 1) of a tab in the leading spaces, if there is one.
    ///
    /// Java rejects it ("found character '\t' that cannot start any token"), but
    /// **inside a block scalar** after the block indent it is ordinary content
    /// (measured: `a: |` + `  <TAB>x` is "\tx\n"). Splitting into lines therefore only
    /// remembers the error and throws it only for whoever takes the line other than as a block
    /// scalar — see `tabInIndent(_:)`.
    let indentTabColumn: Int?

    var isBlank: Bool { text.isEmpty }

    /// A line holding only a comment. It can be recognised without context (the first
    /// character of the content is `#`) and it matters: a comment line is **not** an empty
    /// line — it ends a multi-line plain scalar, whereas an empty one merely breaks it
    /// (measured: `a: x` + `  # c` + `  y` Java rejects).
    ///
    /// Continuation lines of a **quoted** scalar do not follow this; `parseQuoted`
    /// takes them literally, because `#` is content in them.
    var isCommentOnly: Bool { text.first == "#" }

    /// Splits the text into lines. A tab in the indent is only **remembered**
    /// (`indentTabColumn`); throwing it here is not possible, because in a block scalar
    /// it may be content.
    ///
    /// Note on the last element: text ending with a line break yields an empty element
    /// at the end which is **not a line** — it is merely the marker "the file ended
    /// with a break". A block scalar needs to tell these apart, because without a trailing
    /// break even "clip" gives no trailing break (measured).
    static func split(_ text: String) -> [SourceLine] {
        var out: [SourceLine] = []
        for (offset, line) in splitOnLineBreaks(text).enumerated() {
            let number = offset + 1
            var indent = 0
            var tabColumn: Int?
            var index = line.body.startIndex
            while index < line.body.endIndex {
                let ch = line.body[index]
                if ch == " " {
                    indent += 1
                } else {
                    if ch == "\t" { tabColumn = indent + 1 }
                    break
                }
                index = line.body.index(after: index)
            }
            let body = String(line.body[index...])
            // YAML discards trailing spaces and tabs on a plain scalar.
            let tail = body.reversed().prefix(while: { $0 == " " || $0 == "\t" })
            let trimmed = String(body.dropLast(tail.count))
            out.append(SourceLine(number: number, indent: trimmed.isEmpty ? 0 : indent,
                                  text: trimmed, trailingTab: tail.contains("\t"),
                                  raw: line.body, terminator: line.terminator,
                                  indentTabColumn: tabColumn))
        }
        return out
    }

    /// Splits the text into lines and says for each **which break** ended it.
    ///
    /// Port of `ScannerImpl.scanLineBreak` (SnakeYAML 2.5): a line break is `\r\n`,
    /// `\r`, `\n`, NEL (U+0085), U+2028 and U+2029 — and the first four are reported as
    /// `"\n"`, whereas U+2028/U+2029 **as the character itself**. Folding relies on this,
    /// see `BlockParser.foldBreaks(_:)`.
    ///
    /// Measured on Java that these are **full** breaks, not just different
    /// folding: `a: 1<U+2028>b: 2` is a map with **two** keys, `a: 1 # c<U+2028>b: 2`
    /// too (the comment ends at the break), `a:<U+2028>  <U+2028>  b: 1` nests
    /// and `a: \|` + `  x<U+2028>    y` has the block indent measured after that break
    /// ("x<U+2028>  y\n"). Without it the reader would treat them as ordinary characters
    /// mid-line and silently lose keys.
    ///
    /// It iterates over **Unicode scalars**, not `Character`: `\r\n` is a single
    /// grapheme in Swift, so `split(separator: "\n")` would break on it.
    private static func splitOnLineBreaks(_ text: String)
        -> [(body: String, terminator: String)] {
        var out: [(body: String, terminator: String)] = []
        var current = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "\r":
                // `\r\n` is one break; a lone `\r` too, and both yield "\n".
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
                out.append((String(String.UnicodeScalarView(current)), "\n"))
                current = String.UnicodeScalarView()
            case "\n", "\u{85}":
                out.append((String(String.UnicodeScalarView(current)), "\n"))
                current = String.UnicodeScalarView()
            case "\u{2028}", "\u{2029}":
                out.append((String(String.UnicodeScalarView(current)),
                            String(String.UnicodeScalarView([scalar]))))
                current = String.UnicodeScalarView()
            default:
                current.append(scalar)
            }
            index += 1
        }
        // Last element: text ending with a break yields an empty element here
        // which is **not a line** — it is merely the marker "the file ended with a break". A block
        // scalar needs to tell these apart, because without a trailing break
        // even "clip" gives no trailing break (measured). An empty `terminator` is exactly that.
        out.append((String(String.UnicodeScalarView(current)), ""))
        return out
    }

    /// Number of leading **spaces** (a tab stops it — SnakeYAML does not measure
    /// the indent with it either).
    var leadingSpaces: Int {
        var count = 0
        for ch in raw {
            if ch == " " { count += 1 } else { break }
        }
        return count
    }
}

/// A type tag as Jackson sees it after resolution.
///
/// At file level (not nested in the parser), because it is needed in the signature
/// and `YamlScalarResolver`.
enum YamlTag {
    /// A lone `!`. Jackson takes it as "no tag" and types implicitly.
    case nonSpecific
    case str, int, float, bool, null
    /// Unknown (`!!foo`), local (`!x`) or foreign URI. Jackson turns the value
    /// into **text** — it does not reject it (measured).
    case other
}

// MARK: - Block structure parser

private struct BlockParser {

    var lines: [SourceLine]
    var index = 0

    /// Tag namespace prefixes. The default pair is from YAML 1.1
    /// (`SnakeYAML` has them in `ScannerImpl`/`ParserImpl.DEFAULT_TAGS`); the `%TAG`
    /// directive overrides them and may add other handles (`!e!`).
    var tagPrefixes: [String: String] = ["!": "!", "!!": "tag:yaml.org,2002:"]
    /// Handles that the directive explicitly declared **in this stream**. A second
    /// directive for the same handle is an error in Java ("duplicate tag handle"),
    /// and without this set even the first `%TAG !!` would be taken as a duplicate.
    var declaredTagHandles: Set<String> = []

    // MARK: node positions (only for `parseDocument`)

    /// Collect positions? `parse(_:)` does not, so its behaviour and speed
    /// stay exactly as before positions were introduced.
    let recordsPositions: Bool
    var positions = YamlPositions()
    /// Overwritten occurrences of duplicate keys, see `YamlDocument.shadowedValues(of:)`.
    var shadowed: [YamlPath: [YamlValue]] = [:]
    /// Path to the node currently being read.
    var pathComponents: [YamlPath.Component] = []
    /// Do not record positions — a flow map key is being read, which is also a node (`flowNode`),
    /// but Jackson does not report the key's position for the value.
    var suppressRecording = 0
    /// End of the most recently read plain or quoted scalar.
    var lastScalarEnd: YamlPosition?
    /// There is no document in the input (only empty lines, comments, directives).
    var isEmptyStream = true
    /// Code point sums for converting an offset in `[Character]` to a column —
    /// flow on one long line asks repeatedly about the same line.
    var columnCache: (line: Int, indent: Int, count: Int, prefix: [Int])?
    /// Number of currently open collections (maps and sequences, block and flow),
    /// guarded against `YamlParser.maxNestingDepth`.
    var depth = 0

    init(lines: [SourceLine], recordsPositions: Bool = false) {
        self.lines = lines
        self.recordsPositions = recordsPositions
        if recordsPositions, let last = lines.last {
            positions.endOfInput = YamlPosition(line: last.number,
                                                column: last.raw.unicodeScalars.count + 1)
        }
    }

    /// Column (from 1, in code points) of the character `chars[offset]` on line `line`.
    ///
    /// The parser counts offsets in `Character` (graphemes), SnakeYAML in code
    /// points — `"e\u{301}"` is one grapheme but two columns. Indents are
    /// spaces, so one code point per character.
    mutating func codePointColumn(_ line: SourceLine, _ chars: [Character], _ offset: Int) -> Int {
        if let cache = columnCache, cache.line == line.number, cache.indent == line.indent,
           cache.count == chars.count {
            return line.indent + 1 + cache.prefix[offset]
        }
        var prefix = [0]
        prefix.reserveCapacity(chars.count + 1)
        for ch in chars { prefix.append(prefix[prefix.count - 1] + ch.unicodeScalars.count) }
        columnCache = (line.number, line.indent, chars.count, prefix)
        return line.indent + 1 + prefix[offset]
    }

    /// Records the start of a node on the current path (when it does not have one yet — tag
    /// and anchor are outside, so they win).
    mutating func recordStart(line: Int, column: Int) {
        guard recordsPositions, suppressRecording == 0 else { return }
        positions.recordStart(YamlPath(pathComponents), YamlPosition(line: line, column: column))
    }

    mutating func recordStart(_ line: SourceLine, _ chars: [Character], _ offset: Int) {
        guard recordsPositions, suppressRecording == 0 else { return }
        recordStart(line: line.number, column: codePointColumn(line, chars, offset))
    }

    /// Records the end of a scalar that has just ended (`lastScalarEnd`), if
    /// the value really is a scalar.
    mutating func recordScalarEnd(of value: YamlValue) {
        guard recordsPositions, suppressRecording == 0, let end = lastScalarEnd else { return }
        switch value {
        case .mapping, .sequence: return
        default: positions.recordEnd(YamlPath(pathComponents), end)
        }
    }

    /// End of a scalar right after `chars[offset - 1]` on line `line`.
    mutating func noteScalarEnd(_ line: SourceLine, _ chars: [Character], _ offset: Int) {
        guard recordsPositions else { return }
        lastScalarEnd = YamlPosition(line: line.number, column: codePointColumn(line, chars, offset))
    }

    /// Enters the value of key `key`. When the key already exists in the map (`existing`),
    /// the current value is pushed aside together with its positions as an overwritten occurrence — Java reads it
    /// when mapping to a record too, see `YamlPath.Component.shadowedKey`.
    mutating func enterKey(_ key: String, replacing existing: YamlValue?) {
        guard recordsPositions else { return }
        let parent = YamlPath(pathComponents)
        pathComponents.append(.key(key))
        guard let existing else { return }
        let path = YamlPath(pathComponents)
        let target = parent.appending(.shadowedKey(key, occurrence: shadowed[path]?.count ?? 0))
        positions.move(path, to: target)
        for (inner, values) in shadowed where inner != path && inner.hasPrefix(path) {
            shadowed[inner] = nil
            shadowed[YamlPath(target.components + inner.components.dropFirst(path.components.count))] = values
        }
        shadowed[path, default: []].append(existing)
    }

    /// Opens another nesting level of a collection starting at `line`:`column`
    /// (column in graphemes, like reader errors). Above `maxNestingDepth` it throws
    /// `NestingTooDeep` — before recursion would overflow the stack.
    mutating func enterCollection(line: Int, column: Int) throws {
        guard depth < YamlParser.maxNestingDepth else {
            throw NestingTooDeep(line: line, column: column)
        }
        depth += 1
    }

    /// Start of a block collection on the next significant line: records its position
    /// and opens a nesting level (`leaveCollection` is up to the caller).
    mutating func openBlockCollection() throws {
        guard let first = try peekSignificant() else {
            try enterCollection(line: lines.last?.number ?? 1, column: 1)
            return
        }
        recordStart(line: first.number, column: first.indent + 1)
        try enterCollection(line: first.number, column: first.indent + 1)
    }

    mutating func leaveCollection() {
        depth -= 1
    }

    mutating func enterIndex(_ index: Int) {
        guard recordsPositions else { return }
        pathComponents.append(.index(index))
    }

    mutating func leave() {
        guard recordsPositions else { return }
        pathComponents.removeLast()
    }

    // MARK: document

    mutating func parseDocument() throws -> YamlValue {
        // Directives (`%YAML`, `%TAG`, even unknown) Java accepts — but only
        // at the start of the stream and only when `---` follows. `%TAG` is moreover
        // not discarded, see `readTagDirective`.
        let hadDirectives = try skipDirectives()
        // The leading `---` is in our data (bandplan.yaml, digi_frequencies.yaml)
        // and **may be followed by content** — the writer thus writes a root scalar
        // and an empty collection (`--- null`, `--- {}`).
        var hadStartMarker = false
        if let first = try peekSignificant(), first.indent == 0, isStartMarker(first) {
            let content = try startMarkerContent(first)
            index += 1
            hadStartMarker = true
            // The content is inserted as a virtual line at the column where it really is
            // in the file, and reading then continues by the ordinary root node path.
            if let content { lines.insert(content, at: index) }
        }
        if hadStartMarker { isEmptyStream = false }
        if hadDirectives, !hadStartMarker {
            // `%YAML 1.2` + `a: 1` Java rejects ("expected '<document start>'"),
            // but `%YAML 1.2` with no further content returns empty (measured).
            guard let next = try peekSignificant() else { return .null }
            throw error(next, "po direktivě se čeká „---\"")
        }
        // `...` without a preceding `---` and without content Java rejects; otherwise `---`
        // and `...` merely end the document and Java **quietly** returns the first.
        // (A `---` at the start was already handled by `isStartMarker`, so only
        // `...` gets here.)
        if !hadStartMarker, let first = try peekSignificant(), isDocumentBoundary(first) {
            throw error(first, "konec dokumentu („...\") bez obsahu")
        }
        truncateAtDocumentBoundary()
        guard let first = try peekSignificant() else { return .null }
        isEmptyStream = false
        let kind = nodeKind(try code(first))
        // A scalar at the document root has no block above it, so its
        // continuation lines may be indented any way (even to zero).
        let value = try parseNode(indent: first.indent, scalarBase: -1)
        // `readTree` reads **one** value. For a scalar and a flow collection the
        // document ends there and Jackson silently discards the rest (measured: `[1, 2]` +
        // `b: 3` gives `[1,2]`, `hello` + `# c` + `world` gives "hello"). A block
        // collection, by contrast, reads on, so foreign content after it is an error in Java too.
        switch kind {
        case .scalar, .flow:
            lines.removeSubrange(min(index, lines.count)...)
        case .mapping, .sequence:
            if let extra = try peekSignificant() {
                throw error(extra, "za koncem dokumentu pokračuje další obsah")
            }
        }
        return value
    }

    /// Reads directives at the start of the stream; returns whether there were any.
    ///
    /// Measured on Java: `%YAML 1.2` + `---` + content is read and the directive is
    /// discarded — even an unknown one (`%FOO bar` passes). `%TAG` is **not** discarded though,
    /// its prefix is actually applied to tags (see `readTagDirective`).
    /// Comments and empty
    /// lines before and after the directive do not matter. The shape is checked though: a lone
    /// `%`, `%YAML1.2` and two `%YAML` directives Java rejects. An indented `%` is no longer
    /// a directive (Java: "found character '%' that cannot start any token"),
    /// so we do not catch it here and it falls through as a plain scalar starting with `%`.
    ///
    /// A directive **in the middle** of a document (`a: 1` + `%YAML 1.2`) Jackson silently
    /// swallows — the document ends there for it and it returns only `{"a":1}`. We
    /// do not copy that: telling the directive here apart from a continuation line
    /// of a multi-line plain scalar (`hello` + `%x` is "hello %x" in Java) is not possible
    /// without a full scanner and silently discarding content is exactly what this
    /// reader avoids. It ends with a loud error.
    mutating func skipDirectives() throws -> Bool {
        var found = false
        var seenYaml = false
        while let line = try peekSignificant(), line.indent == 0, line.text.first == "%" {
            switch try directiveName(line) {
            case "YAML":
                guard !seenYaml else { throw error(line, "direktiva „%YAML\" je dvakrát") }
                seenYaml = true
                // After the `%YAML` value only spaces and a comment may follow; `%YAML 1.2 junk`
                // Java rejects (measured 1:11). The version number itself is **not verified**,
                // (`%YAML 2.0` and `%YAML abc` Java rejects, we do not).
                try checkDirectiveIgnoredLine(line, from: skipDirectiveValue(line, from: 5))
            case "TAG":
                try readTagDirective(line)
            default:
                // An unknown directive Java **does not check** at all: `%FOO bar baz`
                // and `%FOO bar #c` pass (measured), because `scanDirective`
                // merely skips the rest of the line for an unknown name.
                break
            }
            found = true
            index += 1
        }
        return found
    }

    /// Where the directive value ends — the first space after a non-empty run from `from`.
    /// Serves only `%YAML`, for which "skip what you did not check" is enough.
    func skipDirectiveValue(_ line: SourceLine, from: Int) -> Int {
        let chars = Array(line.raw)
        var i = from
        while i < chars.count, chars[i] == " " { i += 1 }
        while i < chars.count, chars[i] != " " { i += 1 }
        return i
    }

    /// `ScannerImpl.scanDirectiveIgnoredLine`: after the directive value only
    /// **spaces** and then end of line or a comment may follow.
    ///
    /// Measured on Java: `%TAG !! tag:yaml.org,2002: # c` passes,
    /// `%TAG !! tag:yaml.org,2002:   ` (spaces only) passes,
    /// `%TAG !! tag:yaml.org,2002:# c` is error 1:27 ("expected ' '"),
    /// `%TAG !! tag:yaml.org,2002:<TAB># c` error 1:27,
    /// `%TAG !! tag:yaml.org,2002: junk` error 1:28 ("expected a comment or
    /// a line break"), `%YAML 1.2 # c` passes and `%YAML 1.2 junk` is error 1:11.
    /// Read from `line.raw`, because `line.text` has trailing spaces trimmed.
    func checkDirectiveIgnoredLine(_ line: SourceLine, from: Int) throws {
        let chars = Array(line.raw)
        var i = from
        // The space is mandatory: `#` or a tab right after the value is an error.
        guard i < chars.count, chars[i] == " " else {
            if i < chars.count {
                throw error(line, "za hodnotou direktivy se čeká mezera", column: i + 1)
            }
            return
        }
        while i < chars.count, chars[i] == " " { i += 1 }
        guard i == chars.count || chars[i] == "#" else {
            throw error(line, "za hodnotou direktivy smí být jen komentář", column: i + 1)
        }
    }

    /// `%TAG <handle> <prefix>` — remembers the namespace prefix.
    ///
    /// This is **not** cosmetic: as long as `%TAG` was discarded, the **type** of the value
    /// diverged, i.e. that silent and dangerous class of difference.
    /// Measured on Java (Jackson 2.22.0 + SnakeYAML 2.5):
    ///
    /// | input (directive + `---` + body) | Java |
    /// |---|---|
    /// | `%TAG !! tag:yaml.org,2002:` + `a: !!int "7"` | `7` (number) |
    /// | `%TAG !! tag:example.com,2000:` + `a: !!int "7"` | "7" (**text**) |
    /// | `%TAG !e! tag:yaml.org,2002:` + `a: !e!int "7"` | `7` (**number**) |
    /// | `%TAG !e! tag:yaml.org,2002:` + `a: !e!float "1.5"` | `1.5` |
    /// | `%TAG ! tag:yaml.org,2002:` + `a: !int "7"` | `7` |
    /// | `%TAG ! tag:x,2000:` + `a: !foo 1` | "1" |
    /// | `%TAG !e! !` + `a: !e!int "7"` | "7" (prefix `!` → `!int`) |
    /// | `%TAG !! tag%3Ayaml.org,2002%3A` + `a: !!int "7"` | `7` (escapes are resolved) |
    /// | `%TAG !ab_c-1! tag:yaml.org,2002:` + `k: !ab_c-1!int "7"` | `7` |
    /// | `%TAG !! tag:x,2000:` + `k: !<tag:yaml.org,2002:int> "7"` | `7` (the verbatim form is untouched) |
    /// | `%TAG ! tag:x,2000:` + `k: ! 1` | `1` (a lone `!` is untouched) |
    /// | `%TAG !! a:` + `%TAG !! b:` | error 2:1 "duplicate tag handle" |
    /// | `%TAG !!` | error 1:8 ("expected ' '") |
    /// | `%TAG !!tag:a,2000:` | error 1:8 |
    /// | `%TAG !a b! tag:x,2000:` | error 1:8 ("expected '!'") |
    /// | `%TAG !! ` | error 1:9 ("expected URI") |
    /// | `%TAG e tag:a,2000:` | error 1:6 ("expected '!'") |
    mutating func readTagDirective(_ line: SourceLine) throws {
        // Read from `line.raw`, because `line.text` has trailing spaces trimmed
        // and Java tells `%TAG !!` (error 1:8, "expected ' '") from `%TAG !!␣`
        // (error 1:9, "expected URI") apart.
        let chars = Array(line.raw)
        var i = 4  // after "%TAG"
        while i < chars.count, chars[i] == " " { i += 1 }
        guard i < chars.count, chars[i] == "!" else {
            throw error(line, "v direktivě „%TAG\" se čeká handle začínající „!\"",
                        column: i + 1)
        }
        let handleStart = i
        i += 1
        while i < chars.count, chars[i].isASCII,
              chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == "_" {
            i += 1
        }
        if i > handleStart + 1 {
            // `!name!` — the closing "!" is mandatory.
            guard i < chars.count, chars[i] == "!" else {
                throw error(line, "handle direktivy „%TAG\" musí končit „!\"", column: i + 1)
            }
            i += 1
        } else if i < chars.count, chars[i] == "!" {
            i += 1  // `!!`
        }
        let handle = String(chars[handleStart..<i])
        guard i < chars.count, chars[i] == " " else {
            throw error(line, "za handlem direktivy „%TAG\" se čeká mezera", column: i + 1)
        }
        while i < chars.count, chars[i] == " " { i += 1 }
        let prefixStart = i
        while i < chars.count, Self.isTagChar(chars[i]) { i += 1 }
        guard i > prefixStart else {
            throw error(line, "v direktivě „%TAG\" se čeká předpona", column: i + 1)
        }
        // After the prefix only spaces and a comment may follow — `%TAG !! tag:x,2000: junk`
        // Java rejects, whereas `… # c` it accepts (measured).
        try checkDirectiveIgnoredLine(line, from: i)
        guard declaredTagHandles.insert(handle).inserted else {
            throw error(line, "direktiva „%TAG\" je pro handle „\(handle)\" dvakrát")
        }
        tagPrefixes[handle] = try decodeUriEscapes(String(chars[prefixStart..<i]),
                                                   line: line, column: prefixStart + 1)
    }

    /// The directive name after `%`. SnakeYAML takes letters, digits, `-` and `_`
    /// and after the name wants a space or end of line.
    func directiveName(_ line: SourceLine) throws -> String {
        let chars = Array(line.text)
        var i = 1
        while i < chars.count, chars[i].isASCII,
              chars[i].isLetter || chars[i].isNumber || chars[i] == "-" || chars[i] == "_" {
            i += 1
        }
        guard i > 1 else {
            throw error(line, "za „%\" se čeká jméno direktivy", column: 2)
        }
        guard i == chars.count || chars[i] == " " else {
            throw error(line, "jméno direktivy smí mít jen písmena, číslice, „-\" a „_\"",
                        column: i + 1)
        }
        return String(chars[1..<i])
    }

    /// Discards everything from the first `---` or `...` at the start of a line.
    ///
    /// Measured on Java: `---\na: 1\n---\nb: 2` gives `{"a":1}` and `a: 1\n...`
    /// also `{"a":1}` — the second document is **not an error**, Jackson simply reads
    /// only the first. We copy this, because Java is the anchor.
    /// An **empty line** stays in place of the marker, not nothing: the line break before the marker
    /// is real and a block scalar relies on it (`a: |` + `  x` + `---` has
    /// the value "x\n" in Java, not "x"). `peekSignificant` skips the empty line,
    /// so it affects nothing else.
    mutating func truncateAtDocumentBoundary() {
        for position in index..<lines.count where isDocumentBoundary(lines[position]) {
            // The marker is now the **last** line, so `terminator` is empty
            // ("nothing further"). The break **before** the marker is carried by the previous line
            // and that does not change, so the block scalar does not lose its trailing break.
            let marker = SourceLine(number: lines[position].number, indent: 0, text: "",
                                    trailingTab: false, raw: "", terminator: "",
                                    indentTabColumn: nil)
            lines.replaceSubrange(position..., with: [marker])
            return
        }
    }

    /// Document boundary: `---` or `...` at the start of a line, either alone or
    /// with content after a space.
    ///
    /// That the shape with content counts too is measured: `a: 1` + `--- b: 2` gives in Java
    /// `{"a":1}`, `a: 1` + `... b` too and `hello` + `--- x` gives "hello". Without it
    /// we would silently make a key "--- b" out of the second document. `---x: 1` conversely
    /// is **not** a boundary (the marker wants a space after it) and is the key "---x".
    ///
    /// A tab after the marker **does not cancel** the boundary: `a: 1` + `---<TAB>b: 2` gives
    /// `{"a":1}` in Java too (measured). For the **leading** marker it is conversely
    /// a syntax error and `parseDocument` handles it.
    func isDocumentBoundary(_ line: SourceLine) -> Bool {
        guard line.indent == 0 else { return false }
        return ["---", "..."].contains {
            line.text == $0 || line.text.hasPrefix($0 + " ") || line.text.hasPrefix($0 + "\t")
        }
    }

    /// The leading document marker `---`, alone or with content after a space.
    /// `---x` is **not** a marker (it is the key "---x").
    func isStartMarker(_ line: SourceLine) -> Bool {
        line.text == "---" || line.text.hasPrefix("--- ") || line.text.hasPrefix("---\t")
    }

    /// Content after the leading `---` as a virtual line, or `nil` when there is none.
    /// The indent of the virtual line is the **real column** of the content, so
    /// positions in errors and in the block scalar header stay correct.
    ///
    /// Measured on Java (Jackson 2.22.0 + SnakeYAML 2.5) — and the split is
    /// essential, because Java **handles one part of the shapes correctly and silently
    /// mangles the other**:
    ///
    /// | shape | Java | we |
    /// |---|---|---|
    /// | `--- null`, `--- 1`, `--- hello`, `--- "x y"`, `--- 'a # b'` | scalar | we read |
    /// | `--- \|` + `  x`, `--- >` + `  x` | block scalar | we read |
    /// | `--- !!str 1`, `--- !!map` + `a: 1` | the tag is applied | we read |
    /// | `--- {}`, `--- []`, `--- [1,2]`, `--- {a: 1}` | flow collection | we read |
    /// | `--- # c`, `---   null` | comment / more spaces | we read |
    /// | `--- hello` + `world` | "hello world" | we read |
    /// | `--- a: 1`, `--- a:`, `--- "x": 1` | **"a" and discards the rest** | `.unsupported` |
    /// | `--- - 1`, `--- -` | error 1:5 | `.syntax` 1:5 |
    /// | `--- ? a` | error 1:5 | `.syntax` 1:5 |
    ///
    /// A blanket rejection was too broad: it arose from measuring
    /// `--- a: 1`, but Java does not mangle a scalar or a flow collection, so rejecting there
    /// merely meant refusing a file the Java application loads — and the writer
    /// produces exactly such a file.
    mutating func startMarkerContent(_ line: SourceLine) throws -> SourceLine? {
        // The column is **computed** — the content may follow several spaces (`---   null`
        // has its content at column 7), and a tab between the marker and the content Java
        // rejects as a syntax error at that tab (measured:
        // `--- <TAB>a: 1` → 1:5, `---<TAB>a: 1` → 1:4).
        let chars = Array(line.text)
        var offset = 3
        var tabOffset: Int?
        while offset < chars.count, chars[offset] == " " || chars[offset] == "\t" {
            if chars[offset] == "\t", tabOffset == nil { tabOffset = offset }
            offset += 1
        }
        if let tab = tabOffset {
            throw error(line, "tabulátor nelze použít jako oddělovač", column: tab + 1)
        }
        guard offset < chars.count else { return nil }
        // `raw` is padded with spaces so that `indent + relative offset` still
        // points at the same file character (needed by `tagToken` and the block
        // scalar header).
        let rawChars = Array(line.raw)
        let virtual = SourceLine(
            number: line.number, indent: offset, text: String(chars[offset...]),
            trailingTab: line.trailingTab,
            raw: String(repeating: " ", count: offset)
                + String(rawChars[min(offset, rawChars.count)...]),
            terminator: line.terminator, indentTabColumn: nil)
        switch nodeKind(try code(virtual)) {
        case .sequence:
            throw error(line, "položka sekvence nemůže začínat na řádku s „---\"",
                        column: offset + 1)
        case .mapping where isExplicitKey(try code(virtual)):
            throw error(line, "výslovný klíč („? \") nemůže začínat na řádku s „---\"",
                        column: offset + 1)
        case .mapping:
            // The only shape Java silently mangles: it takes the first key as text
            // and discards the rest. We reject loudly, so that no key "--- a" arises from it.
            throw error(line, "bloková mapa na řádku s „---\" není podporovaná",
                        kind: .unsupported, column: offset + 1)
        case .flow, .scalar:
            return virtual
        }
    }

    /// Node starting on the current line.
    ///
    /// - Parameters:
    ///   - indent: indent of this node (for a map and sequence their own).
    ///   - scalarBase: indent of the **enclosing block collection** — continuation
    ///     lines of a multi-line scalar must be indented more than it.
    ///   - properties: tag and anchor that belong to the node from an earlier line
    ///     (`a: !!str` + `  1`), see `NodeProperties`. On a map and sequence it
    ///     does not apply (a tag on a collection is discarded, as before).
    mutating func parseNode(indent: Int, scalarBase: Int,
                            properties: NodeProperties = .none) throws -> YamlValue {
        guard let line = try peekSignificant() else { return .null }
        let chars = try code(line)
        switch nodeKind(chars) {
        case .sequence:
            return try parseSequence(indent: indent)
        case .mapping:
            return try parseMapping(indent: indent)
        case .flow, .scalar:
            index += 1
            return try parseScalar(line: line, chars: chars, offset: 0, scalarBase: scalarBase,
                                   properties: properties)
        }
    }

    /// Tag and anchor of a node that stood on a line **without a value** (`a: !!str`,
    /// `a: &x`, `- !t`) — the value is on the next line and the properties belong to it.
    ///
    /// Java (SnakeYAML `parseNode`) takes at most one tag and one anchor per node, even
    /// across lines: `a: &x` + `  !!str x` is "x", but `a: !t` + `  !t x`
    /// and `a: &x` + `  &y 1` it rejects (measured `ProbeErr`). Without carrying properties
    /// the reader would read a chain of such lines by recursion per line up to a stack
    /// overflow (NEW-1) and would discard the tag on the next line:
    /// `a: !!str` + `  1` would be a number, Java gives the text "1".
    struct NodeProperties {
        var tag: YamlTag?
        var anchor: Bool

        static let none = NodeProperties(tag: nil, anchor: false)
    }

    /// What starts on the line. Flow is tested **first**: `{ id: wve }` does have
    /// a colon with a space, but it is not a map in the block sense, and `{a: 1}: v`
    /// is an error in Java, not a map with the key "{a".
    enum NodeKind { case flow, sequence, mapping, scalar }

    func nodeKind(_ chars: [Character]) -> NodeKind {
        guard let first = chars.first else { return .scalar }
        if first == "[" || first == "{" { return .flow }
        if isSequenceEntry(chars) { return .sequence }
        // An explicit key creates a map even without a colon on the same line: a lone `? a`
        // is `{"a":null}` in Java and `- ? b` is `[{"b":null}]` (measured).
        if isExplicitKey(chars) { return .mapping }
        if keySeparatorOffset(chars) != nil { return .mapping }
        return .scalar
    }

    /// The explicit key indicator: `?` followed by a space, or `?` at the end of the
    /// line. `?x` and `?:` are **not** indicators and Java reads them as text
    /// (`?: 1` → key "?", `?a: 1` → key "?a"; measured).
    func isExplicitKey(_ chars: [Character], _ offset: Int = 0) -> Bool {
        guard offset < chars.count, chars[offset] == "?" else { return false }
        return offset + 1 == chars.count || chars[offset + 1] == " "
    }

    // MARK: maps

    mutating func parseMapping(indent: Int) throws -> YamlValue {
        var map = YamlMapping()
        // A block map starts with the first key (even its tag or anchor).
        try openBlockCollection()
        defer { leaveCollection() }
        // The loop body holds only the recursive call; the line and key checks are
        // in non-recursive helper functions (see `flowNodeValue`).
        while let line = try peekSignificant() {
            if line.indent < indent { break }
            let chars = try mappingEntryCode(line, indent: indent)
            if isExplicitKey(chars) {
                let entry = try parseExplicitEntry(line: line, chars: chars, indent: indent, in: map)
                map.set(entry.key, entry.value)
                continue
            }
            let head = try blockMappingKey(line, chars)
            index += 1
            enterKey(head.key, replacing: map[head.key])
            let value: YamlValue
            if let valueOffset = try keyLineValueOffset(line, chars, separator: head.separator) {
                value = try parseScalar(line: line, chars: chars,
                                        offset: valueOffset, scalarBase: indent)
            } else {
                value = try parseValueOnFollowingLines(blockIndent: indent,
                                                       allowSameIndentSequence: true)
            }
            leave()
            map.set(head.key, value)
        }
        return .mapping(map)
    }

    /// Code of the line on which a block map pair is to start at indent `indent`.
    func mappingEntryCode(_ line: SourceLine, indent: Int) throws -> [Character] {
        if line.indent > indent {
            throw error(line, "nečekané odsazení uvnitř mapy")
        }
        let chars = try code(line)
        if isSequenceEntry(chars) {
            throw error(line, "položka sekvence tam, kde se čeká klíč mapy")
        }
        return chars
    }

    /// Key of a simple block map pair and the offset of its `: ` separator.
    func blockMappingKey(_ line: SourceLine,
                         _ chars: [Character]) throws -> (key: String, separator: Int) {
        guard let separator = keySeparatorOffset(chars) else {
            throw error(line, "chybí oddělovač klíče „: \"")
        }
        // A tab after the key (`a:<TAB>b` and `a: <TAB>`) was already rejected by
        // `code(_:)` — the scanner reports it anywhere a token is expected.
        // The key is also a token position: `*x: 1` is not the key "*x", but
        // a construct outside our subset (Java rejects it — see
        // `unsupportedStart`).
        if let bad = unsupportedStart(chars, 0) {
            throw error(line, bad.message, kind: bad.kind)
        }
        // A tag and anchor **before the key** are discarded: `!!str a: 1` is `{"a":1}`
        // in Java, `!!int 1: x` is `{"1":"x"}`, `&x a: 1` is `{"a":1}`
        // and both may also come one after the other in **any** order (`&x !!str a: 1`
        // and `!!str &x a: 1`; measured). Java accepts neither two tags nor two anchors.
        var keyStart = 0
        var sawTag = false
        var sawAnchor = false
        while keyStart < chars.count {
            if chars[keyStart] == "!" {
                if sawTag {
                    throw error(line, "dvě značky typu za sebou",
                                column: line.indent + keyStart + 1)
                }
                sawTag = true
                let end = try tagToken(chars, keyStart, line: line).end
                keyStart = firstNonSpace(chars, from: end) ?? end
            } else if chars[keyStart] == "&" {
                if sawAnchor {
                    throw error(line, "dvě kotvy za sebou",
                                column: line.indent + keyStart + 1)
                }
                sawAnchor = true
                let end = try anchorTokenEnd(chars, keyStart, line: line)
                keyStart = firstNonSpace(chars, from: end) ?? end
            } else {
                break
            }
        }
        // After discarding the prefixes the token position matters again here: `&x *y: 1`
        // and `!!str *y: 1` Java rejects.
        if keyStart > 0, keyStart < chars.count, let bad = unsupportedStart(chars, keyStart) {
            throw error(line, bad.message, kind: bad.kind, column: line.indent + keyStart + 1)
        }
        return (try blockKey(chars, from: keyStart, upTo: separator, line: line), separator)
    }

    /// Start of the value on the key's line, or `nil` when nothing follows `: `.
    func keyLineValueOffset(_ line: SourceLine, _ chars: [Character],
                            separator: Int) throws -> Int? {
        guard let valueOffset = firstNonSpace(chars, from: separator + 1) else { return nil }
        // A scalar or flow collection may be on the key's line. A nested
        // block map or sequence cannot start there — Java reports an error
        // on `v: abc:` and `parsePlain` rejects that colon too.
        if isSequenceEntry(Array(chars[valueOffset...])) {
            throw error(line, "bloková sekvence nemůže začínat na řádku klíče",
                        column: line.indent + valueOffset + 1)
        }
        return valueOffset
    }

    // MARK: - explicit key (`? key` / `: value`)

    /// One block map pair written explicitly: `? key` on one line
    /// and `: value` on the next, both at the map's indent.
    ///
    /// Why the reader handles it: **the writer writes it.** Jackson's `Emitter` switches to this
    /// shape for a key that is empty, multi-line or has ≥128 UTF-16 units
    /// (`ALLOW_LONG_KEYS` is off), so without this
    /// path the reader could not read what our writer has just written.
    ///
    /// Measured on Java (Jackson 2.22.0 + SnakeYAML 2.5) — Java handles this shape
    /// **correctly**, so we copy it:
    ///
    /// | input | Java |
    /// |---|---|
    /// | `? ""` + `: 1` | `{"":1}` |
    /// | `? a` + `: 1` | `{"a":1}` |
    /// | `? a` (without `:`) | `{"a":null}` |
    /// | a lone `?` | `{"":null}` |
    /// | `?` + `  abc` + `: 1` | `{"abc":1}` |
    /// | `? abc` + `  def` + `: 1` | `{"abc def":1}` (folded) |
    /// | `? 'ab ab` + `  cd '` + `: 1` | `{"ab ab cd ":1}` |
    /// | `? \|` + `  abc` + `: 1` | `{"abc\n":1}` |
    /// | `? null`, `? ~`, `? 1.5` | the key is the **original text**: "null", "~", "1.5" |
    /// | `? !!int 7`, `? !!null x` | key "7" and "x" respectively (the tag is not applied to the key) |
    /// | `? a` + `: x: 1` | `{"a":{"x":1}}` — a block **may** start on the `:` line |
    /// | `? a` + `: - 1` + `  - 2` | `{"a":[1,2]}` |
    /// | `? a` + `:` + `- 1` | `{"a":[1]}` |
    /// | `? a` + `: ? b` | `{"a":{"b":null}}` |
    /// | `? a` + `: 1` + `a: 2` | `{"a":2}` (the last wins) |
    /// | `? a` + `b: 2` | `{"a":null,"b":2}` |
    /// | `? a` + `? b` | `{"a":null,"b":null}` (a set) |
    /// | `? a` + `  : 1` | error 3:3 (colon indented more than `?`) |
    /// | `? a` + `: 1` + `: 2` | error 3:1 |
    /// | `? a` + `:1` | error (without a space it is not a separator) |
    /// | `? a: 1`, `? {a: 1}`, `? [1,2]`, `? - 1` | error: a collection cannot be a key |
    ///
    /// Errors on an indented colon and on a second colon follow from the ordinary
    /// map path (value missing → `null`, and the next line is then unexpected),
    /// so this function does not guard against them itself.
    mutating func parseExplicitEntry(line: SourceLine, chars: [Character], indent: Int,
                                     in map: YamlMapping) throws -> (key: String, value: YamlValue) {
        index += 1
        let key: String
        if let keyOffset = firstNonSpace(chars, from: 1) {
            key = try explicitKeyText(line: line, chars: chars, offset: keyOffset, indent: indent)
        } else {
            // Nothing follows `?` on the line: the key is on more indented lines,
            // or missing and empty.
            key = try explicitKeyOnFollowingLines(indent: indent)
        }
        enterKey(key, replacing: map[key])
        defer { leave() }
        // `: value` must be at the **same** indent as `?`; otherwise the value
        // is missing and `null` (the map itself then rejects an indented colon).
        guard let next = try peekSignificant(), next.indent == indent else { return (key, .null) }
        let valueChars = try code(next)
        guard valueChars.first == ":",
              valueChars.count == 1 || valueChars[1] == " " else { return (key, .null) }
        index += 1
        guard let valueOffset = firstNonSpace(valueChars, from: 1) else {
            return (key, try parseValueOnFollowingLines(blockIndent: indent,
                                                        allowSameIndentSequence: true))
        }
        // A block map and sequence **may** start on the explicit colon's line
        // (unlike a simple key), so the content is inserted as a
        // virtual line, just like after a sequence dash.
        return (key, try parseEntryContent(line: next, chars: valueChars, offset: valueOffset,
                                           blockIndent: indent, allowSameIndentSequence: true))
    }

    /// Text of an explicit key. In Jackson a key is always the **scalar's text**, not
    /// its typed value (`? null` gives the key "null", `? !!null x` the key "x").
    mutating func explicitKeyText(line: SourceLine, chars: [Character], offset: Int,
                                  indent: Int, sawAnchor: Bool = false,
                                  sawTag: Bool = false) throws -> String {
        if let bad = unsupportedStart(chars, offset) {
            throw error(line, bad.message, kind: bad.kind, column: line.indent + offset + 1)
        }
        switch chars[offset] {
        case "\"", "'":
            return try parseQuoted(line: line, chars: chars, offset: offset,
                                   double: chars[offset] == "\"")
        case "|", ">":
            return try parseBlockScalar(line: line, offset: offset, scalarBase: indent)
        case "!":
            // The tag is not applied to the key, only discarded — just as
            // for a simple key (`!!int 1: x` is `{"1":"x"}`). Two tags
            // on one node Java rejects; without this check a chain of tags
            // `? !a !a !a …` on one line would overflow the stack through recursion.
            if sawTag {
                throw error(line, "dvě značky typu za sebou", column: line.indent + offset + 1)
            }
            let end = try tagToken(chars, offset, line: line).end
            guard let next = firstNonSpace(chars, from: end) else { return "" }
            return try explicitKeyText(line: line, chars: chars, offset: next, indent: indent,
                                       sawAnchor: sawAnchor, sawTag: true)
        case "&":
            // The anchor is discarded too: `? &x a` + `: 1` is `{"a":1}`, and it works
            // together with a tag in both orders (measured). Two anchors
            // on one key Java rejects — even when a tag is between them
            // (`? &x !!str &y a`), hence it is carried by recursion in `sawAnchor`.
            if sawAnchor {
                throw error(line, "dvě kotvy za sebou", column: line.indent + offset + 1)
            }
            let end = try anchorTokenEnd(chars, offset, line: line)
            guard let next = firstNonSpace(chars, from: end) else { return "" }
            return try explicitKeyText(line: line, chars: chars, offset: next, indent: indent,
                                       sawAnchor: true, sawTag: sawTag)
        case "[", "{":
            throw error(line, "kolekce nemůže být klíčem mapy",
                        column: line.indent + offset + 1)
        default:
            // A collection cannot be a key — Jackson reports "Expected a field name".
            // Applies to `? - 1`, `? a: 1` and nested `? ? a`.
            let rest = Array(chars[offset...])
            if isSequenceEntry(rest) || isExplicitKey(rest) || keySeparatorOffset(rest) != nil {
                throw error(line, "kolekce nemůže být klíčem mapy",
                            column: line.indent + offset + 1)
            }
            return try plainText(line: line, chars: chars, offset: offset, scalarBase: indent)
        }
    }

    /// Key on the lines after a lone `?`. A more indented line is the key, anything
    /// else means an empty key (measured: a lone `?` gives `{"":null}`).
    mutating func explicitKeyOnFollowingLines(indent: Int) throws -> String {
        guard let next = try peekSignificant(), next.indent > indent else { return "" }
        let chars = try code(next)
        index += 1
        return try explicitKeyText(line: next, chars: chars, offset: 0, indent: indent)
    }

    // MARK: sequences

    mutating func parseSequence(indent: Int) throws -> YamlValue {
        var items: [YamlValue] = []
        // A block sequence starts with the first dash.
        try openBlockCollection()
        defer { leaveCollection() }
        while let line = try peekSignificant() {
            if line.indent < indent { break }
            let chars = try code(line)
            if line.indent > indent {
                throw error(line, "nečekané odsazení uvnitř sekvence")
            }
            guard isSequenceEntry(chars) else { break }
            index += 1
            enterIndex(items.count)
            if let valueOffset = firstNonSpace(chars, from: 1) {
                items.append(try parseEntryContent(line: line, chars: chars,
                                                   offset: valueOffset, blockIndent: indent))
            } else {
                // A dash without a value is `null`; a dash at the same indent on
                // the next line is the **next item**, not a nested sequence.
                items.append(try parseValueOnFollowingLines(blockIndent: indent,
                                                            allowSameIndentSequence: false))
            }
            leave()
        }
        return .sequence(items)
    }

    // MARK: values

    /// Content of a sequence item that starts on the same line as the dash —
    /// and likewise content after the explicit colon (`: value`).
    ///
    /// When it is a map or another sequence (`- a: 1`, `- - x`, `: x: 1`), a
    /// virtual line with the content from `offset` is inserted and reading continues the usual way —
    /// that naturally catches the further keys of that map, indented to the content column.
    mutating func parseEntryContent(line: SourceLine, chars: [Character],
                                    offset: Int, blockIndent: Int,
                                    allowSameIndentSequence: Bool = false) throws -> YamlValue {
        let rest = Array(chars[offset...])
        switch nodeKind(rest) {
        case .sequence, .mapping:
            let contentIndent = line.indent + offset
            // `rest` is already code without a comment, so a trailing tab is not carried
            // over — `code(_:)` verified it on the original line. `raw` is
            // padded with spaces so that `line.indent + offset` still points at the same
            // character (`tagToken` and the block scalar header need it).
            // `terminator` is taken over from the original line — the virtual line stands
            // in its place, so the same break ends it.
            lines.insert(SourceLine(number: line.number, indent: contentIndent,
                                    text: String(rest), trailingTab: false,
                                    raw: String(repeating: " ", count: contentIndent) + String(rest),
                                    terminator: line.terminator,
                                    indentTabColumn: nil), at: index)
            return try parseNode(indent: contentIndent, scalarBase: blockIndent)
        case .flow, .scalar:
            return try parseScalar(line: line, chars: chars, offset: offset,
                                   scalarBase: blockIndent,
                                   allowSameIndentSequence: allowSameIndentSequence)
        }
    }

    /// Value on the following lines. A more indented line is a nested node,
    /// a dash at the same indent is a block sequence (Jackson accepts it), anything
    /// else means the value is missing → `null`.
    mutating func parseValueOnFollowingLines(blockIndent: Int,
                                             allowSameIndentSequence: Bool,
                                             properties: NodeProperties = .none) throws -> YamlValue {
        try valueOnFollowingLines(blockIndent: blockIndent,
                                  allowSameIndentSequence: allowSameIndentSequence,
                                  properties: properties) ?? .null
    }

    /// The same, but `nil` when there is **no** value on the next lines — a tag needs this
    /// to distinguish it from the value `null` (`a: !!null` + `  x` is `null` from `x`,
    /// a lone `a: !!str` is an empty text from the tag).
    mutating func valueOnFollowingLines(blockIndent: Int, allowSameIndentSequence: Bool,
                                        properties: NodeProperties) throws -> YamlValue? {
        guard let next = try peekSignificant() else { return nil }
        if next.indent > blockIndent {
            return try parseNode(indent: next.indent, scalarBase: blockIndent, properties: properties)
        }
        if allowSameIndentSequence, next.indent == blockIndent, isSequenceEntry(try code(next)) {
            return try parseSequence(indent: blockIndent)
        }
        return nil
    }

    // MARK: scalars

    /// A construct that starts at the token position with something outside our subset.
    /// `nil` means "there is nothing like that here".
    ///
    /// Called at **every token position** in block context — at the start of a
    /// value (`parseScalar`) and at the start of a map key (`parseMapping`,
    /// `explicitKeyText`) — and also in flow (`flowNode`). Without it the
    /// construct would be silently read as text and the definition loaded halfway.
    ///
    /// Measured on Java (Jackson 2.22.0 + SnakeYAML 2.5): Jackson does **not resolve**
    /// the alias `*x`, it returns the anchor name as text (`b: *x` → `"x"`, even when no
    /// anchor `x` exists; likewise in flow and in the value of the `<<` key). That is
    /// nonsense that would show up in a contest definition only as a wrong score,
    /// so we reject it **loudly** as `.unsupported`.
    ///
    /// **An anchor `&name` is not in the list** — the reader reads
    /// and discards it, because Java does so and does so sensibly
    /// (`a: &x 1` → `1`). See `anchorTokenEnd` and `parseAnchored`.
    ///
    /// `%`, `@` and `` ` `` are conversely `.syntax` — Java rejects them at a token position
    /// too ("found character … that cannot start any token"). Directives
    /// at the start of the stream (`%YAML`) are handled by `skipDirectives` before it gets here.
    ///
    /// Block scalars (`|`, `>`), tags (`!!str`) and the explicit key (`? `)
    /// are **not** in the list — the reader handles them because Java does, and rejecting would
    /// mean that a definition the Java application loads is refused by the Swift one.
    func unsupportedStart(_ chars: [Character],
                          _ offset: Int) -> (message: String, kind: YamlError.Kind)? {
        switch chars[offset] {
        case "*":
            return ("alias („*\") není podporovaný", .unsupported)
        case "%", "@", "`":
            return ("znak „\(chars[offset])\" nesmí začínat plain skalár", .syntax)
        default:
            return nil
        }
    }

    /// Scalar starting on `line` from `offset`. Line `line` is already consumed.
    ///
    /// - Parameter allowSameIndentSequence: applies only to a tag after which nothing
    ///   follows on the line (`a: !!seq` + `- 1`). Java accepts such a sequence at the same
    ///   indent, but not after a sequence dash — the same distinction as
    ///   in `parseValueOnFollowingLines`.
    mutating func parseScalar(line: SourceLine, chars: [Character], offset: Int,
                              scalarBase: Int,
                              allowSameIndentSequence: Bool = true,
                              properties: NodeProperties = .none) throws -> YamlValue {
        // The node starts here — even when it is only a tag or an anchor before the value
        // (Jackson reports `a: !!int 42` at column 4, not 10).
        recordStart(line, chars, offset)
        lastScalarEnd = nil
        let value = try parseScalarValue(line: line, chars: chars, offset: offset,
                                         scalarBase: scalarBase,
                                         allowSameIndentSequence: allowSameIndentSequence,
                                         properties: properties)
        recordScalarEnd(of: value)
        return value
    }

    mutating func parseScalarValue(line: SourceLine, chars: [Character], offset: Int,
                                   scalarBase: Int,
                                   allowSameIndentSequence: Bool,
                                   properties: NodeProperties) throws -> YamlValue {
        // The recursive path holds only the fork, see `flowNodeValue`.
        switch chars[offset] {
        case "[", "{":
            // A tag on a flow collection is discarded, even when it stood on an earlier line.
            return try parseFlow(line: line, chars: chars, offset: offset)
        case "!":
            return try parseTagged(line: line, chars: chars, offset: offset, scalarBase: scalarBase,
                                   allowSameIndentSequence: allowSameIndentSequence,
                                   properties: properties)
        case "&":
            return try parseAnchored(line: line, chars: chars, offset: offset,
                                     scalarBase: scalarBase,
                                     allowSameIndentSequence: allowSameIndentSequence,
                                     properties: properties)
        default:
            if let tag = properties.tag {
                // A tag from an earlier line (`a: !!str` + `  1` → "1").
                return try taggedLeaf(tag, line: line, chars: chars, valueOffset: offset,
                                      scalarBase: scalarBase)
            }
            return try parseLeafScalar(line: line, chars: chars, offset: offset,
                                       scalarBase: scalarBase)
        }
    }

    /// A scalar that does not start with a flow collection, tag or anchor. The non-recursive
    /// part of `parseScalarValue`.
    mutating func parseLeafScalar(line: SourceLine, chars: [Character], offset: Int,
                                  scalarBase: Int) throws -> YamlValue {
        // `unsupportedStart` knows only `*`, `%`, `@` and `` ` ``, so the check
        // here instead of before the fork does not change the order.
        if let bad = unsupportedStart(chars, offset) {
            throw error(line, bad.message, kind: bad.kind, column: line.indent + offset + 1)
        }
        switch chars[offset] {
        case "\"":
            return .string(try parseQuoted(line: line, chars: chars, offset: offset, double: true))
        case "'":
            return .string(try parseQuoted(line: line, chars: chars, offset: offset, double: false))
        case "|", ">":
            return .string(try parseBlockScalar(line: line, offset: offset, scalarBase: scalarBase))
        case "]", "}", ",":
            // A closing bracket or comma must not **start** a value (Java rejects
            // that too). Inside a plain scalar it is conversely just text: `a: 1]`
            // is "1]" and `a: 1,2` is "1,2".
            throw error(line, "znak „\(chars[offset])\" nesmí začínat hodnotu",
                        column: line.indent + offset + 1)
        case "?" where isExplicitKey(chars, offset):
            // An explicit key is a key, not a value: `a: ? b` and `a: ?` Java rejects
            // ("mapping keys are not allowed here", measured 1:4), so it is a
            // syntax error, not an unsupported construct.
            throw error(line, "výslovný klíč („? \") nemůže být hodnotou",
                        column: line.indent + offset + 1)
        default:
            return try parsePlain(line: line, chars: chars, offset: offset, scalarBase: scalarBase)
        }
    }

    // MARK: anchors

    /// End of the anchor token `&name`, i.e. the index of the first character **after** the name.
    ///
    /// In Java an anchor is **discarded and the value stays** — `a: &x 1` is `1`,
    /// `&x a: 1` is `{"a":1}`, `a: &x |` + a block is that block, a lone `a: &x` is
    /// `null`, an anchor may be combined with a tag in **both** orders
    /// (`&x !!int 1` and `!!int &x 1`), may be on a sequence item, in flow,
    /// on the root after `---`, may have the same name twice and need not be used by
    /// any alias. All measured on Java 21 (Jackson 2.22.0 + SnakeYAML 2.5).
    /// This behaviour is **sensible**, so we copy it.
    ///
    /// The name is `[alphanumeric, _, -]` and must have at least one character (Java accepts
    /// even a non-Latin letter: `&kotvá 1` is `1`). Only a space
    /// or end of line may follow the name — and inside flow notation also `,`, `]` and `}`, because
    /// they end the anchor there (`[&x]` is `[null]`). A tab after the anchor is rejected
    /// by Java too ("while scanning for the next token").
    ///
    /// **Recorded divergences.** SnakeYAML allows further characters after the name
    /// and the result is then nonsense — measured: `a: &x"q"` gives `null` (the value
    /// `"q"` vanishes), likewise `&x'q'`, `&x#k`, `&x%1`, `&x@1`, `&x` + `` ` ``
    /// and `&x?1`; `a: &x:y 1` gives the text `":y 1"` and `&x: 1` gives an **empty key**
    /// `{"":1}`. Without a space it swallows even what looks like a tag:
    /// `a: &x!!str 1` gives the **number** `1`, not the text "1", so `!!str` vanishes
    /// (whereas `a: &x !!str 1` with a space correctly gives "1"). All of that is a silent
    /// discarding or rewriting of what the user wrote, so the second
    /// half of the rule applies here: reject **loudly**. Other characters in the name
    /// (`&x.y`, `&x[1]`, `&x,1`, `&x]1`) and an empty name (`a: &`) are rejected
    /// by Java itself.
    func anchorTokenEnd(_ chars: [Character], _ offset: Int, line: SourceLine,
                        inFlow: Bool = false) throws -> Int {
        var end = offset + 1
        while end < chars.count, Self.isAnchorNameChar(chars[end]) {
            end += 1
        }
        if end == offset + 1 {
            throw error(line, "kotva („&\") musí mít jméno", column: line.indent + end + 1)
        }
        if end < chars.count, !Self.isAnchorTerminator(chars[end], inFlow: inFlow) {
            throw error(line, "znak „\(chars[end])\" nesmí být ve jménu kotvy",
                        column: line.indent + end + 1)
        }
        return end
    }

    /// A character that may stand right after the anchor name. `!` is **not** among them:
    /// SnakeYAML takes it into the name, so `&x!!str 1` is the number `1` in Java
    /// and the tag silently vanishes (measured) — hence we reject it.
    static func isAnchorTerminator(_ character: Character, inFlow: Bool) -> Bool {
        if character == " " {
            return true
        }
        return inFlow && (character == "," || character == "]" || character == "}")
    }

    /// An anchor name character. Java accepts even a non-Latin letter (`&kotvá`), so
    /// `isLetter`/`isNumber` is tested, not just ASCII.
    static func isAnchorNameChar(_ character: Character) -> Bool {
        character == "_" || character == "-" || character.isLetter || character.isNumber
    }

    /// A node with an anchor. The anchor is discarded and the value after it is returned — whether it is on the same
    /// line or (when nothing follows the anchor) on the next lines.
    ///
    /// Two anchors on one node Java rejects (`a: &x &y 1` → "while parsing
    /// a block mapping"), so it is an error here too.
    mutating func parseAnchored(line: SourceLine, chars: [Character], offset: Int,
                                scalarBase: Int,
                                allowSameIndentSequence: Bool,
                                properties: NodeProperties) throws -> YamlValue {
        if properties.anchor {
            // The anchor was already on an earlier line (`a: &x` + `  &y 1`).
            throw error(line, "dvě kotvy za sebou", column: line.indent + offset + 1)
        }
        let carried = NodeProperties(tag: properties.tag, anchor: true)
        guard let valueOffset = try anchoredValueOffset(line: line, chars: chars, offset: offset) else {
            // `a: &x` + an indented map/sequence, or a lone `a: &x` (→ `null`).
            // Java accepts a sequence at the same indent (`a: &x` + `- 1` is `[1]`),
            // not after a sequence dash — the same distinction as for a tag.
            if let value = try valueOnFollowingLines(
                blockIndent: scalarBase, allowSameIndentSequence: allowSameIndentSequence,
                properties: carried) {
                return value
            }
            // The value is missing. With a tag from an earlier line it is an empty scalar
            // with the tag, as for a lone `a: !!str` (`a: !!str` + `  &x` → "").
            guard let tag = properties.tag else { return .null }
            return try taggedScalar(tag, "", plain: true, line: line.number,
                                    column: line.indent + offset + 1)
        }
        return try parseScalar(line: line, chars: chars, offset: valueOffset,
                               scalarBase: scalarBase,
                               allowSameIndentSequence: allowSameIndentSequence,
                               properties: carried)
    }

    /// Start of the value after the anchor on the same line, `nil` = the line ends after the anchor.
    /// The non-recursive part of `parseAnchored`.
    func anchoredValueOffset(line: SourceLine, chars: [Character], offset: Int) throws -> Int? {
        let end = try anchorTokenEnd(chars, offset, line: line)
        guard let valueOffset = firstNonSpace(chars, from: end) else { return nil }
        if chars[valueOffset] == "&" {
            throw error(line, "dvě kotvy za sebou", column: line.indent + valueOffset + 1)
        }
        if isSequenceEntry(Array(chars[valueOffset...])) {
            // `a: &x - 1` Java rejects ("sequence entries are not allowed here").
            throw error(line, "bloková sekvence („- \") nemůže začínat za kotvou",
                        column: line.indent + valueOffset + 1)
        }
        return valueOffset
    }

    /// A plain (unquoted) scalar, possibly composed of several lines. Lines are
    /// folded as in YAML: one break = space, an empty line = break.
    mutating func parsePlain(line: SourceLine, chars: [Character],
                             offset: Int, scalarBase: Int) throws -> YamlValue {
        let text = try plainText(line: line, chars: chars, offset: offset, scalarBase: scalarBase)
        return try YamlScalarResolver.resolve(text, line: line.number,
                                              column: line.indent + offset + 1)
    }

    /// Folded text of a plain scalar — without typing, so the path with a
    /// tag can use it too (`!!str x` + a continuation line is "x y" in Java).
    mutating func plainText(line: SourceLine, chars: [Character],
                            offset: Int, scalarBase: Int) throws -> String {
        var segments = [String(chars[offset...])]
        /// Breaks between segments. The invariant `breaks.count == segments.count - 1` holds,
        /// because `fold` pairs them by index.
        var breaks: [String] = []
        /// The line the last segment came from — its `terminator` is the break
        /// that ends the segment.
        var lastLine = line
        func appendSegment(_ text: String, endedBy previous: SourceLine) {
            breaks.append(previous.terminator)
            segments.append(text)
        }
        try rejectKeySeparator(in: Array(chars[offset...]), line: line, baseColumn: line.indent + offset)
        // A comment after the value **ends** the scalar — continuation lines no longer
        // belong to it (measured: `a: x #c` + `  y` is an error in Java, not "x y").
        var folds = !hasComment(line)
        noteScalarEnd(line, chars, chars.count)

        while folds {
            var lookahead = index
            while lookahead < lines.count, lines[lookahead].isBlank {
                try tabInIndent(lines[lookahead])
                lookahead += 1
            }
            guard lookahead < lines.count else { break }
            let next = lines[lookahead]
            // A comment line ends the scalar too; `index` does not move, so
            // the enclosing block looks at the following content itself (and rejects
            // any indent, just like Java).
            if next.isCommentOnly { break }
            guard next.indent > scalarBase else { break }
            // A line starting with `---` at column 1 ends the root plain scalar
            // **always**, even when it is not a document boundary (`---1`): SnakeYAML
            // has in `scanPlainSpaces` the condition
            // `"---".equals(prefix) || "...".equals(prefix) && blank`, where
            // `&&` binds only to `...`. Jackson then does not read the rest (`x` + `---1` is
            // "x" in Java, measured). We copy it. A nested scalar does not get here —
            // its continuation is indented.
            if scalarBase < 0, next.indent == 0, next.text.hasPrefix("---") {
                lines.removeSubrange(lookahead...)
                index = lines.count
                break
            }
            // A continuation line is read **from inside the plain scalar**, not from the
            // token position: `[`, `{`, `>`, `!`, `"` at its start are ordinary
            // characters (`a` + `{b: 1}` is "a {b" in Java, `x` + `  !# c` is
            // "x !# c"; measured). A dash too: `a: x` + `  - 1` gives "x - 1".
            try tabInIndent(next)
            let nextScan = scanPlainContinuation(Array(next.text))
            var nextChars = Array(next.text)
            if let comment = nextScan.comment {
                var end = comment
                while end > 0, nextChars[end - 1] == " " || nextChars[end - 1] == "\t" { end -= 1 }
                nextChars = Array(nextChars[0..<end])
            }
            folds = nextScan.comment == nil
            /// Empty lines between the last segment and `next` — each contributes
            /// an empty segment and its break.
            func appendBlankLines() {
                for position in index..<lookahead {
                    appendSegment("", endedBy: lastLine)
                    lastLine = lines[position]
                }
            }
            if let separator = nextScan.keySeparator {
                // Inside a block collection that is an error in Java ("mapping values are
                // not allowed here"). Not at the document root: `hello` + `b: 2`
                // gives "hello b" and Jackson does not read the rest at all.
                guard scalarBase < 0 else {
                    throw error(next, "dvojtečka v hodnotě: mapa tady začínat nemůže",
                                column: next.indent + separator + 1)
                }
                appendBlankLines()
                // The segment before the colon without trailing spaces and tabs — **only
                // those**, like `scanPlainSpaces` in SnakeYAML. Foundation's `.whitespaces`
                // would strip NBSP and U+3000 too, which are content in Java
                // (`a` + `b<U+3000>: c` → "a b<U+3000>"; measured).
                var headEnd = separator
                while headEnd > 0, nextChars[headEnd - 1] == " " || nextChars[headEnd - 1] == "\t" {
                    headEnd -= 1
                }
                let head = String(nextChars[0..<headEnd])
                if !head.isEmpty { appendSegment(head, endedBy: lastLine) }
                lines.removeSubrange(lookahead...)
                index = lines.count
                break
            }
            appendBlankLines()
            appendSegment(String(nextChars), endedBy: lastLine)
            noteScalarEnd(next, nextChars, nextChars.count)
            lastLine = next
            index = lookahead + 1
        }

        return fold(segments, breaks: breaks)
    }

    /// A quoted scalar as the **whole value** — after the closing quote only
    /// a comment may follow.
    mutating func parseQuoted(line: SourceLine, chars: [Character],
                              offset: Int, double: Bool) throws -> String {
        let end = try scanQuoted(line: line, chars: chars, offset: offset, double: double)
        // On the first line `code(_:)` discarded the comment; on a continuation line
        // it did not, because that is read literally (`#` is content inside quotes).
        if let trailing = firstNonSpace(end.chars, from: end.offset), end.chars[trailing] != "#" {
            throw error(end.line, "za uzavírací uvozovkou pokračuje text",
                        column: end.line.indent + trailing + 1)
        } else if firstNonSpace(end.chars, from: end.offset) == nil, !hasComment(end.line),
                  end.line.trailingTab {
            // `d: "x" <TAB>` Java rejects (after a comment not — that tab is
            // part of it). On the first line `code(_:)` catches it, on a continuation
            // line (read literally) only this does.
            throw error(end.line, "tabulátor nelze použít jako oddělovač")
        }
        return end.value
    }

    /// Reads a quoted scalar and returns it together with the position **after** the closing
    /// quote. It may extend over further lines (in our data `multipliers/iaru_hq.yaml`
    /// does this); they are read literally, because `#` inside
    /// quotes is not a comment.
    mutating func scanQuoted(line: SourceLine, chars: [Character], offset: Int, double: Bool)
        throws -> (value: String, line: SourceLine, chars: [Character], offset: Int) {
        let quote: Character = double ? "\"" : "'"
        var segments: [String] = []
        var breaks: [String] = []
        var current = chars
        var currentLine = line
        var position = offset + 1

        while true {
            if let end = closingQuote(current, from: position, quote: quote, double: double) {
                segments.append(String(current[position..<end]))
                let folded = fold(segments, breaks: breaks,
                                  escapedBreaks: double, closedByQuote: true)
                let value = double
                    ? try unescape(folded, line: currentLine)
                    // In single quotes the only escape is a doubled apostrophe.
                    : folded.replacingOccurrences(of: "''", with: "'")
                noteScalarEnd(currentLine, current, end + 1)
                return (value, currentLine, current, end + 1)
            }
            // `SourceLine.text` cut off trailing spaces and tabs; here we
            // restore them from `raw`, because after a backslash they are content
            // (`"x\ ` + `"` → "x  ", see `fold`). `fold` strips the others anyway.
            let trailingBlanks = String(currentLine.raw.reversed()
                .prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            segments.append(String(current[position...]) + trailingBlanks)
            guard index < lines.count else {
                throw error(line, "neuzavřené uvozovky", column: line.indent + offset + 1)
            }
            breaks.append(currentLine.terminator)
            currentLine = lines[index]
            index += 1
            current = Array(currentLine.text)
            position = 0
        }
    }

    // MARK: - block scalars (`|`, `>`)

    /// How trailing line breaks are handled. SnakeYAML calls it "chomping".
    enum Chomping {
        /// No indicator: exactly one trailing break stays.
        case clip
        /// `-`: no trailing break.
        case strip
        /// `+`: all trailing breaks stay.
        case keep
    }

    /// A block scalar starting on `line` from `offset` (`|` or `>`). Line
    /// `line` is already consumed, `index` points at the first line after the header.
    ///
    /// The procedure is a port of SnakeYAML's `ScannerImpl.scanBlockScalar` and **all**
    /// its deviations from the YAML spec are measured on Java (measured). The least
    /// obvious points:
    /// - Folding to a space with `>` applies only when neither the previous nor
    ///   the following line is indented **more** than the block and there is no
    ///   empty line between them. Otherwise the break stays literal.
    /// - The block indent is derived as the **maximum** of leading spaces over the leading
    ///   space-only lines **and** the first content line. A space-only line longer than
    ///   the content therefore empties the block and Java then rejects the content.
    /// - When the file does not end with a line break, even "clip" gives no trailing break.
    /// - Trailing spaces on a content line are content, so `line.raw` is read,
    ///   not `line.text`.
    mutating func parseBlockScalar(line: SourceLine, offset: Int,
                                   scalarBase: Int) throws -> String {
        let (folded, chomping, increment) = try blockHeader(line: line, offset: offset)

        // SnakeYAML: `min_indent = this.indent + 1`, at least 1.
        let minIndent = max(scalarBase + 1, 1)
        let indent: Int
        if let increment {
            indent = minIndent + increment - 1
        } else {
            var maxIndent = 0
            var scan = index
            while scan < lines.count {
                let candidate = lines[scan]
                maxIndent = max(maxIndent, candidate.leadingSpaces)
                // A line of spaces only (even empty) does not stop the detection.
                guard candidate.leadingSpaces == candidate.raw.count else { break }
                scan += 1
            }
            indent = max(minIndent, maxIndent)
        }

        var out = ""
        var pendingBreaks = skipBlockBreaks(indent: indent)
        /// The break after the last content line; at the end of a file without a break `""`.
        /// It is taken **from the line** (`terminator`), because U+2028 and U+2029 stay
        /// themselves (measured: `a: |` + `  x<U+2028>  y` is "x<U+2028>y\n",
        /// `a: |` + `  x<U+2028>` is "x<U+2028>").
        var lineBreak = ""

        while let content = blockContentLine(indent: indent) {
            out += pendingBreaks.joined()
            out += content.text
            lineBreak = lines[index].terminator
            index += 1
            pendingBreaks = skipBlockBreaks(indent: indent)
            guard let next = blockContentLine(indent: indent) else { break }
            // SnakeYAML: a break folds into a space only for `>`, only when it is the single
            // break, it is `"\n"` and neither of the two lines starts with a space or
            // tab.
            if folded, lineBreak == "\n", content.startsWithNonSpace, next.startsWithNonSpace {
                if pendingBreaks.isEmpty { out += " " }
            } else {
                out += lineBreak
            }
        }

        switch chomping {
        case .clip, .keep:
            out += lineBreak
        case .strip:
            break
        }
        if chomping == .keep {
            out += pendingBreaks.joined()
        }
        return out
    }

    /// Block header: `|`/`>` followed by at most one chomping indicator and one
    /// indent digit (in any order), then only a comment.
    ///
    /// Read from `line.raw` so that a tab after `|` is detected (Java reports a different
    /// error for `a: |<TAB>` than for `a: | <TAB>`) — `line.text` has trailing
    /// spaces and tabs trimmed.
    func blockHeader(line: SourceLine, offset: Int) throws
        -> (folded: Bool, chomping: Chomping, increment: Int?) {
        let chars = Array(line.raw)
        var i = line.indent + offset
        let folded = chars[i] == ">"
        i += 1
        var chomping = Chomping.clip
        var increment: Int?

        func digit(_ ch: Character) -> Int? {
            guard let value = ch.wholeNumberValue, ch.isASCII, ch.isNumber else { return nil }
            return value
        }
        func readIncrement() throws {
            guard let value = digit(chars[i]) else { return }
            guard value > 0 else {
                throw error(line, "odsazení blokového skaláru musí být 1 až 9, ne 0", column: i + 1)
            }
            increment = value
            i += 1
        }

        if i < chars.count, chars[i] == "-" || chars[i] == "+" {
            chomping = chars[i] == "+" ? .keep : .strip
            i += 1
            if i < chars.count { try readIncrement() }
        } else if i < chars.count {
            try readIncrement()
            if increment != nil, i < chars.count, chars[i] == "-" || chars[i] == "+" {
                chomping = chars[i] == "+" ? .keep : .strip
                i += 1
            }
        }
        // After the indicators a space or end of line must follow.
        guard i == chars.count || chars[i] == " " else {
            throw error(line, "za „\(folded ? ">" : "|")\" se čeká indikátor osekání nebo odsazení",
                        column: i + 1)
        }
        while i < chars.count, chars[i] == " " { i += 1 }
        guard i == chars.count || chars[i] == "#" else {
            throw error(line, "za hlavičkou blokového skaláru smí být jen komentář", column: i + 1)
        }
        return (folded, chomping, increment)
    }

    /// A content line of the block at the current `index`, or `nil` when the block ends there.
    ///
    /// A content line is one that has at least `indent` leading spaces and has something
    /// at column `indent`. A line that ends at that column is an empty
    /// line (handled by `skipBlockBreaks`), and a line with a smaller indent ends the block.
    func blockContentLine(indent: Int) -> (text: String, startsWithNonSpace: Bool)? {
        guard index < lines.count else { return nil }
        let line = lines[index]
        let spaces = line.leadingSpaces
        let chars = Array(line.raw)
        guard spaces >= indent, indent < chars.count else { return nil }
        let text = String(chars[indent...])
        let first = chars[indent]
        return (text, first != " " && first != "\t")
    }

    /// Swallows the empty lines of the block and returns the **breaks** that arose from them —
    /// not just their count, because U+2028 and U+2029 are emitted as themselves
    /// (measured: `a: |+` + `  x<U+2028>  y<U+2028><U+2028>` is
    /// "x<U+2028>y<U+2028><U+2028>\n").
    ///
    /// The last element of `lines` for text ending with a break is an empty marker that is
    /// not a line — no break arises from it, and it is recognised by an empty
    /// `terminator` (the only line that has it empty is the last one).
    mutating func skipBlockBreaks(indent: Int) -> [String] {
        var breaks: [String] = []
        while index < lines.count {
            let line = lines[index]
            let spaces = line.leadingSpaces
            guard min(indent, spaces) == line.raw.count else { break }
            if !line.terminator.isEmpty { breaks.append(line.terminator) }
            index += 1
        }
        return breaks
    }

    // MARK: - type tags (`!!str`, `!!int`…)

    /// Characters SnakeYAML accepts in a tag (`URI_CHARS_FOR_TAG_PREFIX`).
    /// `#` is **not** among them, so `a: !!str#x 1` is an error, whereas `!!str,x`
    /// and `!!str:` are valid tags (measured).
    static let tagChars = Set("-;/?:@&=+$,_.!~*'()[]%")

    static func isTagChar(_ ch: Character) -> Bool {
        (ch.isASCII && (ch.isLetter || ch.isNumber)) || tagChars.contains(ch)
    }

    /// Where a tag token starting at `chars[start] == "!"` ends. It only scans
    /// — it does not verify the shape, that is up to `tagToken`. It must match the line scanner,
    /// otherwise a colon in a tag (`!!str:`) would be mistaken for a key separator.
    static func tagTokenEnd(_ chars: [Character], _ start: Int) -> Int {
        var i = start + 1
        // Verbatim form `!<tag:…>`.
        if i < chars.count, chars[i] == "<" {
            i += 1
            while i < chars.count, chars[i] != ">" { i += 1 }
            if i < chars.count { i += 1 }
            return i
        }
        while i < chars.count, isTagChar(chars[i]) { i += 1 }
        return i
    }

    /// Reads the tag at `chars[offset]` and returns it with the position after it.
    ///
    /// A space or end of line must follow the tag — this is verified on `line.raw`,
    /// because `chars` came without the comment and `a: !!str#x 1` is an error in Java,
    /// not a `!!str` tag with a value.
    func tagToken(_ chars: [Character], _ offset: Int,
                  line: SourceLine) throws -> (tag: YamlTag, end: Int) {
        let end = Self.tagTokenEnd(chars, offset)
        let rawChars = Array(line.raw)
        let rawEnd = line.indent + end
        if rawEnd < rawChars.count, rawChars[rawEnd] != " " {
            throw error(line, "za značkou typu se čeká mezera", column: rawEnd + 1)
        }
        let text = String(chars[offset..<end])
        return (try resolveTag(text, line: line, column: line.indent + offset + 1,
                               endColumn: rawEnd + 1), end)
    }

    /// Resolves percent escapes in the URI part of a tag and then translates it.
    ///
    /// SnakeYAML decodes them (`ScannerImpl.scanTagUri` → `scanUriEscapes`), so
    /// `!!%69%6e%74 "7"` is **`int`** in Java, not text. That is a silent **type** difference,
    /// i.e. the dangerous class: the value would differ, rather than the file being rejected.
    /// (With `!!%73%74%72 001` it is not visible — "001" comes out the same either way.)
    ///
    /// Only the **URI part** is decoded, not the "handle" (`!`, `!!`, `!e!`) — SnakeYAML
    /// takes that with `scanTagHandle`, which does not resolve escapes.
    /// - Parameter endColumn: column **after** the tag; the missing type name is reported
    ///   there, because Java reports it there too ("expected URI, but found ␣").
    func resolveTag(_ text: String, line: SourceLine,
                    column: Int, endColumn: Int) throws -> YamlTag {
        if text == "!" { return .nonSpecific }
        // The verbatim form must be closed; `!<tag:…` without `>` Java rejects, we make it
        // (as before) an unknown tag, i.e. text.
        if text.hasPrefix("!<"), text.hasSuffix(">") {
            let inner = String(text.dropFirst(2).dropLast())
            let uri = try decodeUriEscapes(inner, line: line, column: column)
            return Self.resolveTag(verbatimUri: uri)
        }
        // `!handle!suffix`: the second `!` closes the handle. Without it the handle is `!`.
        let scalars = Array(text.unicodeScalars)
        var separator: Int?
        for index in 1..<scalars.count where scalars[index] == "!" {
            separator = index
            break
        }
        let suffixStart = (separator ?? 0) + 1
        let handle = String(String.UnicodeScalarView(scalars[0..<suffixStart]))
        let rawSuffix = String(String.UnicodeScalarView(scalars[suffixStart...]))
        // A handle without a type name (`!!`, `!e!`) Java rejects — measured `a: !! 1`
        // at 1:6 and `a: !e! 1` at 1:7, both "expected URI, but found  (32)".
        guard !rawSuffix.isEmpty else {
            throw error(line, "značka „\(text)\" nemá jméno typu", column: endColumn)
        }
        // The handle prefix is from `%TAG`, otherwise the default. **An undefined handle Java
        // rejects** ("found undefined tag handle !e!", measured `a: !e!foo 1`
        // at 1:4) — we used to silently turn it into text.
        guard let prefix = tagPrefixes[handle] else {
            throw error(line, "nedefinovaný handle značky „\(handle)\"", column: column)
        }
        let suffix = try decodeUriEscapes(rawSuffix, line: line, column: column)
        return Self.resolveTag(verbatimUri: prefix + suffix)
    }

    /// Resolves `%XX` in a URI. A port of `scanUriEscapes`: a contiguous run of escapes is
    /// collected into bytes and those are decoded as **one** UTF-8 sequence
    /// (`!!%C4%8D` is thus "č"). A bad escape and invalid UTF-8 Java **rejects**,
    /// so we reject them too — otherwise we would silently accept as text what Java does not.
    func decodeUriEscapes(_ uri: String, line: SourceLine, column: Int) throws -> String {
        guard uri.contains("%") else { return uri }
        let scalars = Array(uri.unicodeScalars)
        var out = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "%" else {
                out.append(scalars[index])
                index += 1
                continue
            }
            var bytes: [UInt8] = []
            while index < scalars.count, scalars[index] == "%" {
                guard index + 2 < scalars.count else {
                    throw error(line, "ve značce typu se za „%\" čekají dvě šestnáctkové číslice",
                                column: column)
                }
                let pair = String(String.UnicodeScalarView(scalars[(index + 1)...(index + 2)]))
                guard let value = Self.parseTagEscape(pair) else {
                    throw error(line, "ve značce typu se za „%\" čekají dvě šestnáctkové číslice",
                                column: column)
                }
                bytes.append(value)
                index += 3
            }
            guard let decoded = String(bytes: bytes, encoding: .utf8) else {
                throw error(line, "procentové escapy ve značce typu nejsou platné UTF-8",
                            column: column)
            }
            out.append(contentsOf: decoded.unicodeScalars)
        }
        return String(out)
    }

    /// The pair of characters after `%` into a byte. Java reads this with `Integer.parseInt(…, 16)`
    /// and casts the result to `byte`, so it accepts a sign too (`%+1` is byte 1,
    /// `%-1` byte 0xFF — and that then does not pass as UTF-8; measured).
    static func parseTagEscape(_ pair: String) -> UInt8? {
        guard let value = Int(pair, radix: 16) else { return nil }
        return UInt8(truncatingIfNeeded: value)
    }

    /// Translates the tag notation into what Jackson makes of it.
    ///
    /// For tags from `tag:yaml.org,2002:` Jackson cuts off the prefix and
    /// **truncates the name at the first comma**, so `!!int,x` is still `int` (measured).
    static func resolveTag(verbatimUri uri: String) -> YamlTag {
        // Jackson compares the resulting tag with "!", so `!<!>` is the same as `!`
        // (`a: !<!> "1"` → number 1, measured).
        if uri == "!" { return .nonSpecific }
        let prefix = "tag:yaml.org,2002:"
        guard uri.hasPrefix(prefix) else { return .other }
        var name = String(uri.dropFirst(prefix.count))
        if let comma = name.firstIndex(of: ",") { name = String(name[..<comma]) }
        switch name {
        case "str": return .str
        case "int": return .int
        case "float": return .float
        case "bool": return .bool
        case "null": return .null
        default: return .other
        }
    }

    /// A value with a tag at `chars[offset] == "!"`.
    mutating func parseTagged(line: SourceLine, chars: [Character], offset: Int, scalarBase: Int,
                              allowSameIndentSequence: Bool,
                              properties: NodeProperties = .none) throws -> YamlValue {
        if properties.tag != nil {
            // The tag was already on an earlier line (`a: !t` + `  !t x`).
            throw error(line, "dvě značky typu za sebou", column: line.indent + offset + 1)
        }
        let head = try tagHead(line: line, chars: chars, offset: offset,
                               sawAnchor: properties.anchor)
        guard let valueOffset = head.valueOffset else {
            // Nothing follows the tag on the line: the value is on the next lines
            // (a block map or sequence — on a collection the tag is discarded; a scalar
            // gets the tag), or missing and it is an empty scalar.
            if let value = try valueOnFollowingLines(
                blockIndent: scalarBase, allowSameIndentSequence: allowSameIndentSequence,
                properties: NodeProperties(tag: head.tag, anchor: properties.anchor || head.sawAnchor)) {
                return value
            }
            return try taggedScalar(head.tag, "", plain: true, line: line.number,
                                    column: line.indent + offset + 1)
        }
        if chars[valueOffset] == "[" || chars[valueOffset] == "{" {
            // A tag on a flow collection is discarded (`a: !!str [1,2]` is `[1,2]`).
            return try parseFlow(line: line, chars: chars, offset: valueOffset)
        }
        return try taggedLeaf(head.tag, line: line, chars: chars, valueOffset: valueOffset,
                              scalarBase: scalarBase)
    }

    /// The tag at `chars[offset]` and the start of the value after it (and after any
    /// anchor), `nil` = the line ends. The non-recursive part of `parseTagged`.
    /// `sawAnchor`: the node's anchor was already on an earlier line (`a: &x` + `  !!str &y 1`).
    func tagHead(line: SourceLine, chars: [Character], offset: Int,
                 sawAnchor anchorBefore: Bool) throws -> (tag: YamlTag, valueOffset: Int?, sawAnchor: Bool) {
        let (tag, end) = try tagToken(chars, offset, line: line)

        // An anchor between the tag and the value is discarded: `a: !!int &x 1` is `1`
        // and `a: !!int &x "1"` too `1` (measured). A second anchor Java rejects.
        var searchFrom = end
        var sawAnchor = anchorBefore
        while let anchor = firstNonSpace(chars, from: searchFrom), chars[anchor] == "&" {
            if sawAnchor {
                throw error(line, "dvě kotvy za sebou", column: line.indent + anchor + 1)
            }
            sawAnchor = true
            searchFrom = try anchorTokenEnd(chars, anchor, line: line)
        }
        return (tag, firstNonSpace(chars, from: searchFrom), sawAnchor)
    }

    /// A scalar with a tag on the tag's line (not a flow collection). The non-recursive part
    /// `parseTagged`.
    mutating func taggedLeaf(_ tag: YamlTag, line: SourceLine, chars: [Character],
                             valueOffset: Int, scalarBase: Int) throws -> YamlValue {
        // A typing error points at the **value**, not the tag — just as
        // for an untagged scalar, where `parsePlain` reports its start.
        let column = line.indent + valueOffset + 1
        switch chars[valueOffset] {
        case "|", ">":
            let text = try parseBlockScalar(line: line, offset: valueOffset, scalarBase: scalarBase)
            return try taggedScalar(tag, text, plain: false, line: line.number, column: column)
        case "\"", "'":
            let text = try parseQuoted(line: line, chars: chars, offset: valueOffset,
                                       double: chars[valueOffset] == "\"")
            return try taggedScalar(tag, text, plain: false, line: line.number, column: column)
        case "!":
            // Two tags in a row Java rejects ("expected <block end>, but found '<tag>'").
            throw error(line, "dvě značky typu za sebou", column: line.indent + valueOffset + 1)
        default:
            if let bad = unsupportedStart(chars, valueOffset) {
                throw error(line, bad.message, kind: bad.kind,
                            column: line.indent + valueOffset + 1)
            }
            if isExplicitKey(chars, valueOffset) {
                throw error(line, "výslovný klíč („? \") nemůže být hodnotou",
                            column: line.indent + valueOffset + 1)
            }
            // `plainText` rejects a colon in the value itself (`a: !!str b: 1` is
            // an error at that colon in Java).
            let text = try plainText(line: line, chars: chars, offset: valueOffset,
                                     scalarBase: scalarBase)
            return try taggedScalar(tag, text, plain: true, line: line.number, column: column)
        }
    }

    /// Value of a scalar according to the tag.
    ///
    /// With the tag `!` (and `!<!>`) Jackson types **implicitly regardless of the notation
    /// style** — a quoted and a block scalar like plain (measured:
    /// `a: ! "1"` → number 1, `! 'true'` → `true`, `! ""` → `null`, `! "0x10"`
    /// → 16, `a: ! >` + `  1` → 1, `! "1.5"` → 1.5; `! ".inf"` is an error like
    /// plain `.inf`). `plain` therefore does not decide for `!`.
    func taggedScalar(_ tag: YamlTag, _ text: String, plain: Bool,
                      line: Int, column: Int) throws -> YamlValue {
        if case .nonSpecific = tag {
            return try YamlScalarResolver.resolve(text, line: line, column: column)
        }
        // An empty value with **any** explicit tag is an empty text, not
        // `null` — even for `!!int` and `!!null` (measured; without a tag it is `null`).
        if text.isEmpty { return .string("") }
        return try YamlScalarResolver.resolve(tag: tag, text: text, line: line, column: column)
    }

    // MARK: - flow notation

    /// Cursor inside flow notation. Flow is not governed by indent and may spread over
    /// further lines (measured: `a: [1,` + `2]` is `[1,2]`, even though `2` is at
    /// column 0), so the cursor carries the line it is currently on.
    struct FlowCursor {
        var line: SourceLine
        /// Content of the line without a trailing comment.
        var chars: [Character]
        /// Did this line end with a comment? A plain scalar is then not folded onto the next line
        /// (measured: `a: [x #c` + `, y]` is `["x","y"]`).
        var hadComment: Bool
        var offset: Int

        var atLineEnd: Bool { offset >= chars.count }
        var column: Int { line.indent + offset + 1 }
    }

    /// One loaded node inside flow — besides the value it also carries what it could
    /// be a key by, and where it started and ended (a key must not extend onto the next line).
    struct FlowNode {
        let value: YamlValue
        /// Text for use as a map key; `nil` for collections (Jackson rejects those as a
        /// key: "Expected a field name").
        let keyText: String?
        let line: SourceLine
        let column: Int
        let endLineNumber: Int
    }

    /// A flow collection starting at `chars[offset]` (`[` or `{`). Line `line`
    /// is already consumed; flow takes further lines itself.
    mutating func parseFlow(line: SourceLine, chars: [Character], offset: Int) throws -> YamlValue {
        var cursor = FlowCursor(line: line, chars: chars,
                                hadComment: hasComment(line), offset: offset)
        let node = try flowNode(&cursor)
        // After the closing bracket only a comment may follow — `a: [1] x` and `{a: 1}: v`
        // are an error in Java.
        while !cursor.atLineEnd, cursor.chars[cursor.offset] == " " { cursor.offset += 1 }
        if !cursor.atLineEnd, cursor.chars[cursor.offset] != "#" {
            throw error(cursor.line, "za koncem flow notace pokračuje text", column: cursor.column)
        }
        if cursor.atLineEnd, !cursor.hadComment, cursor.line.trailingTab {
            // `b: [1] <TAB>` Java rejects; on the line where flow started `code(_:)` catches it,
            // on the line where it ended only this does. After a comment not —
            // `b: [1] # c<TAB>` Java reads.
            throw error(cursor.line, "tabulátor nelze použít jako oddělovač")
        }
        return node.value
    }

    /// Moves the cursor to the next significant character; also crosses onto further lines.
    /// `false` means "no more content" (i.e. unclosed flow notation).
    mutating func flowToken(_ cursor: inout FlowCursor) throws -> Bool {
        while true {
            while !cursor.atLineEnd, cursor.chars[cursor.offset] == " " { cursor.offset += 1 }
            if !cursor.atLineEnd {
                if cursor.chars[cursor.offset] == "\t" {
                    throw error(cursor.line, "tabulátor nelze použít jako oddělovač ve flow notaci",
                                column: cursor.column)
                }
                // At a position where a token is expected `#` is **always** a comment —
                // even without a space before it (measured: `a: [1,#c` + `2]` → `[1,2]`).
                if cursor.chars[cursor.offset] == "#" {
                    cursor.offset = cursor.chars.count
                    cursor.hadComment = true
                    continue
                }
                return true
            }
            guard let next = try nextFlowLine() else { return false }
            cursor.line = next
            cursor.chars = try code(next)
            cursor.hadComment = hasComment(next)
            cursor.offset = 0
        }
    }

    /// The next line for flow: empty and comment-only lines are skipped.
    mutating func nextFlowLine() throws -> SourceLine? {
        while index < lines.count {
            let line = lines[index]
            try tabInIndent(line)
            index += 1
            if line.isBlank || line.isCommentOnly { continue }
            return line
        }
        return nil
    }

    /// A node inside flow: a nested collection, quoted or plain scalar.
    mutating func flowNode(_ cursor: inout FlowCursor) throws -> FlowNode {
        let node = try flowNodeValue(&cursor)
        // Only a scalar has `keyText`; collections do not record an end.
        if node.keyText != nil { recordScalarEnd(of: node.value) }
        return node
    }

    /// The recursive path (`flowNodeValue` → `flowSequence`/`flowMapping`/
    /// `flowTagged`/`flowAnchored` → `flowNode` → …) holds **only the fork**;
    /// scalars and errors are in non-recursive helper functions. A debug
    /// build gives every function a stack frame for all its local
    /// values at once, so a large body on the recursive path would be paid for
    /// at every nesting level — see `YamlParser.maxNestingDepth`.
    mutating func flowNodeValue(_ cursor: inout FlowCursor) throws -> FlowNode {
        let start = try flowNodeStart(&cursor)
        switch cursor.chars[cursor.offset] {
        case "[":
            let value = try flowSequence(&cursor)
            return FlowNode(value: value, keyText: nil, line: start.line,
                            column: start.column, endLineNumber: cursor.line.number)
        case "{":
            let value = try flowMapping(&cursor)
            return FlowNode(value: value, keyText: nil, line: start.line,
                            column: start.column, endLineNumber: cursor.line.number)
        case "!":
            return try flowTagged(&cursor, startLine: start.line, startColumn: start.column)
        case "&":
            return try flowAnchored(&cursor, startLine: start.line, startColumn: start.column)
        default:
            return try flowLeaf(&cursor, startLine: start.line, startColumn: start.column)
        }
    }

    /// Start of a node in flow: moves the cursor to its first character and records the position.
    mutating func flowNodeStart(_ cursor: inout FlowCursor) throws -> (line: SourceLine, column: Int) {
        guard try flowToken(&cursor) else {
            throw error(cursor.line, "neuzavřená flow notace: chybí hodnota", column: cursor.column)
        }
        recordStart(cursor.line, cursor.chars, cursor.offset)
        lastScalarEnd = nil
        return (cursor.line, cursor.column)
    }

    /// A node in flow that is not a collection, tag or anchor: a quoted or
    /// plain scalar, otherwise an error. Non-recursive, see `flowNodeValue`.
    mutating func flowLeaf(_ cursor: inout FlowCursor, startLine: SourceLine,
                           startColumn: Int) throws -> FlowNode {
        // `unsupportedStart` knows only `*`, `%`, `@` and `` ` `` — those do not belong in the fork
        // of `flowNodeValue`, so it is checked only here and the order is
        // the same as when it stood before it.
        if let bad = unsupportedStart(cursor.chars, cursor.offset) {
            throw error(cursor.line, bad.message, kind: bad.kind, column: cursor.column)
        }
        switch cursor.chars[cursor.offset] {
        case "\"", "'":
            let double = cursor.chars[cursor.offset] == "\""
            let end = try scanQuoted(line: cursor.line, chars: cursor.chars,
                                     offset: cursor.offset, double: double)
            // The rest of the line after the quote is ordinary flow content, only any trailing
            // comment must vanish from it (continuation lines are read literally).
            let rest = truncatingComment(end.chars, from: end.offset)
            cursor.line = end.line
            cursor.chars = rest.chars
            cursor.hadComment = rest.hadComment
            cursor.offset = end.offset
            return FlowNode(value: .string(end.value), keyText: end.value, line: startLine,
                            column: startColumn, endLineNumber: cursor.line.number)
        case ",", "]", "}", ":":
            throw error(cursor.line, "ve flow notaci chybí hodnota před „\(cursor.chars[cursor.offset])\"",
                        column: cursor.column)
        case "-" where isSequenceEntry(Array(cursor.chars[cursor.offset...])):
            // A dash with a space is a block sequence indicator even inside flow,
            // so it is an error (measured: `a: [- y]` Java rejects). Without a space
            // it is ordinary text: `[-x]` is "-x".
            throw error(cursor.line, "bloková sekvence („- \") nemůže být uvnitř flow notace",
                        column: cursor.column)
        case "?":
            // Inside flow `?` is an indicator even without a space after it, so
            // unlike in a block we always reject it. Java reads `[? b]`
            // (`{"b":null}`), we do not — but loudly.
            throw error(cursor.line, "explicitní klíč („?\") není podporovaný",
                        kind: .unsupported, column: cursor.column)
        case "|", ">":
            // A block scalar does not exist inside flow and Java reports it as a
            // syntax error ("found character '|' that cannot start any
            // token"), not as an unsupported construct (measured).
            throw error(cursor.line,
                        "znak „\(cursor.chars[cursor.offset])\" nesmí začínat hodnotu ve flow notaci",
                        column: cursor.column)
        default:
            return try flowPlain(&cursor)
        }
    }

    /// A node with an anchor inside flow. The anchor is discarded and the node after it is returned;
    /// when no value follows (`[&x]`, `{a: &x}`) it is `null` — measured,
    /// Java gives `[null]` and `{"a":null}`.
    mutating func flowAnchored(_ cursor: inout FlowCursor, startLine: SourceLine,
                               startColumn: Int) throws -> FlowNode {
        if let empty = try flowAnchorPrefix(&cursor, startLine: startLine, startColumn: startColumn) {
            return empty
        }
        return try flowNode(&cursor)
    }

    /// An anchor in flow with no value after it (`[&x]` → `null`), otherwise `nil`
    /// and the cursor stands on the value. The non-recursive part of `flowAnchored`.
    mutating func flowAnchorPrefix(_ cursor: inout FlowCursor, startLine: SourceLine,
                                   startColumn: Int) throws -> FlowNode? {
        cursor.offset = try anchorTokenEnd(cursor.chars, cursor.offset, line: cursor.line,
                                           inFlow: true)
        guard try flowToken(&cursor) else {
            throw error(cursor.line, "neuzavřená flow notace: chybí hodnota", column: cursor.column)
        }
        if ",]}".contains(cursor.chars[cursor.offset]) {
            return FlowNode(value: .null, keyText: nil, line: startLine,
                            column: startColumn, endLineNumber: cursor.line.number)
        }
        if cursor.chars[cursor.offset] == "&" {
            throw error(cursor.line, "dvě kotvy za sebou", column: cursor.column)
        }
        return nil
    }

    /// A node with a tag inside flow. On a collection the tag is discarded, on a scalar
    /// it is applied just as in a block.
    mutating func flowTagged(_ cursor: inout FlowCursor, startLine: SourceLine,
                             startColumn: Int) throws -> FlowNode {
        let prefix = try flowTagPrefix(&cursor, startLine: startLine, startColumn: startColumn)
        if let done = prefix.done { return done }
        let inner = try flowNode(&cursor)
        return try flowTaggedNode(prefix.tag, quoted: prefix.quoted, inner: inner,
                                  startLine: startLine, startColumn: startColumn)
    }

    /// A tag (and any anchor after it) in flow. `done` is the finished node when
    /// no value follows; otherwise the cursor stands on the value and `quoted` says
    /// whether it starts with a quote. The non-recursive part of `flowTagged`.
    mutating func flowTagPrefix(_ cursor: inout FlowCursor, startLine: SourceLine,
                                startColumn: Int) throws -> (tag: YamlTag, quoted: Bool, done: FlowNode?) {
        let (tag, end) = try tagToken(cursor.chars, cursor.offset, line: cursor.line)
        cursor.offset = end
        guard try flowToken(&cursor) else {
            throw error(cursor.line, "za značkou typu chybí hodnota", column: cursor.column)
        }
        // An anchor between the tag and the value is discarded — and it must be discarded **here**,
        // not only in `flowNode`, because otherwise `quoted` below would be computed from `&`
        // and `[!!int &x "1"]` would not come out as `1` (measured).
        var sawAnchor = false
        while cursor.chars[cursor.offset] == "&" {
            if sawAnchor {
                throw error(cursor.line, "dvě kotvy za sebou", column: cursor.column)
            }
            sawAnchor = true
            cursor.offset = try anchorTokenEnd(cursor.chars, cursor.offset, line: cursor.line,
                                           inFlow: true)
            guard try flowToken(&cursor) else {
                throw error(cursor.line, "za značkou typu chybí hodnota", column: cursor.column)
            }
        }
        if sawAnchor, ",]}".contains(cursor.chars[cursor.offset]) {
            // `[!!str &x]` Java reads as `[""]` (whereas `[!!str]` it rejects).
            let done = FlowNode(value: try taggedScalar(tag, "", plain: true,
                                                        line: startLine.number, column: startColumn),
                                keyText: "", line: startLine, column: startColumn,
                                endLineNumber: cursor.line.number)
            return (tag, false, done)
        }
        if cursor.chars[cursor.offset] == "!" {
            throw error(cursor.line, "dvě značky typu za sebou", column: cursor.column)
        }
        let quoted = cursor.chars[cursor.offset] == "\"" || cursor.chars[cursor.offset] == "'"
        return (tag, quoted, nil)
    }

    /// A node with a tag from an already read value `inner`.
    func flowTaggedNode(_ tag: YamlTag, quoted: Bool, inner: FlowNode, startLine: SourceLine,
                        startColumn: Int) throws -> FlowNode {
        // `keyText` is `nil` exactly for collections — the tag is discarded there.
        guard let text = inner.keyText else {
            return FlowNode(value: inner.value, keyText: nil, line: startLine,
                            column: startColumn, endLineNumber: inner.endLineNumber)
        }
        let value = try taggedScalar(tag, text, plain: !quoted,
                                     line: startLine.number, column: startColumn)
        return FlowNode(value: value, keyText: text, line: startLine,
                        column: startColumn, endLineNumber: inner.endLineNumber)
    }

    static let flowSequenceName = "sekvence („[\")"
    static let flowMappingName = "mapa („{\")"

    mutating func flowSequence(_ cursor: inout FlowCursor) throws -> YamlValue {
        let open = cursor.line
        let openColumn = cursor.column
        try enterCollection(line: open.number, column: openColumn)
        defer { leaveCollection() }
        cursor.offset += 1
        var items: [YamlValue] = []
        if try flowCollectionIsEmpty(&cursor, closing: "]", open, openColumn, Self.flowSequenceName) {
            return .sequence(items)
        }
        while true {
            enterIndex(items.count)
            items.append(try flowSequenceEntry(&cursor))
            leave()
            if try flowSequenceAdvance(&cursor, open, openColumn) {
                return .sequence(items)
            }
        }
    }

    /// After the opening bracket: is the collection closed right away (`[]`, `{}`)?
    mutating func flowCollectionIsEmpty(_ cursor: inout FlowCursor, closing: Character,
                                        _ open: SourceLine, _ openColumn: Int,
                                        _ what: String) throws -> Bool {
        guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, what) }
        guard cursor.chars[cursor.offset] == closing else { return false }
        cursor.offset += 1
        return true
    }

    /// After a flow sequence item: `true` = the sequence ended, `false` = another
    /// item (cursor on it).
    mutating func flowSequenceAdvance(_ cursor: inout FlowCursor, _ open: SourceLine,
                                      _ openColumn: Int) throws -> Bool {
        guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, Self.flowSequenceName) }
        switch cursor.chars[cursor.offset] {
        case "]":
            cursor.offset += 1
            return true
        case ",":
            cursor.offset += 1
            guard try flowToken(&cursor) else {
                throw unclosedFlow(open, openColumn, Self.flowSequenceName)
            }
            // A trailing comma is allowed: `[1, 2,]`.
            if cursor.chars[cursor.offset] == "]" {
                cursor.offset += 1
                return true
            }
            return false
        case "}":
            throw error(cursor.line, "flow sekvence „[\" je uzavřená „}\"", column: cursor.column)
        default:
            throw error(cursor.line, "ve flow sekvenci se čeká „,\" nebo „]\"", column: cursor.column)
        }
    }

    /// A flow sequence item. `[x: y]` is a **single-pair map** — YAML allows it
    /// and Java reads it so (measured: `{"x":"y"}`).
    mutating func flowSequenceEntry(_ cursor: inout FlowCursor) throws -> YamlValue {
        let key = try flowNode(&cursor)
        guard let name = try flowSequencePairKey(&cursor, key) else { return key.value }
        // A single-pair map is another nesting level in Jackson, just like `{x: y}`.
        try enterCollection(line: key.line.number, column: key.column)
        defer { leaveCollection() }
        var value = YamlValue.null
        enterKey(name, replacing: nil)
        if !",]}".contains(cursor.chars[cursor.offset]) {
            value = try flowNode(&cursor).value
        }
        leave()
        return .mapping(YamlMapping([(name, value)]))
    }

    /// The key of a single-pair map in a sequence, when after the node `key` there is a colon on
    /// the same line; the cursor then stands on the value. `nil` = an ordinary item.
    mutating func flowSequencePairKey(_ cursor: inout FlowCursor, _ key: FlowNode) throws -> String? {
        guard try flowToken(&cursor), cursor.chars[cursor.offset] == ":",
              cursor.line.number == key.endLineNumber else {
            return nil
        }
        cursor.offset += 1
        let name = try flowKey(key)
        guard try flowToken(&cursor) else {
            throw error(cursor.line, "neuzavřená flow notace: chybí hodnota", column: cursor.column)
        }
        return name
    }

    mutating func flowMapping(_ cursor: inout FlowCursor) throws -> YamlValue {
        let open = cursor.line
        let openColumn = cursor.column
        try enterCollection(line: open.number, column: openColumn)
        defer { leaveCollection() }
        cursor.offset += 1
        var map = YamlMapping()
        if try flowCollectionIsEmpty(&cursor, closing: "}", open, openColumn, Self.flowMappingName) {
            return .mapping(map)
        }
        while true {
            suppressRecording += 1
            let key = try flowNode(&cursor)
            suppressRecording -= 1
            let name = try flowKey(key)
            var value = YamlValue.null
            enterKey(name, replacing: map[name])
            defer { leave() }
            if try flowMappingHasValue(&cursor, key, open, openColumn) {
                value = try flowNode(&cursor).value
            }
            map.set(name, value)
            if try flowMappingAdvance(&cursor, open, openColumn) {
                return .mapping(map)
            }
        }
    }

    /// After a flow map key: does a value follow? `true` = the cursor stands on it.
    mutating func flowMappingHasValue(_ cursor: inout FlowCursor, _ key: FlowNode,
                                      _ open: SourceLine, _ openColumn: Int) throws -> Bool {
        guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, Self.flowMappingName) }
        // Inside flow `:` is a separator **always**, even without a space after it
        // (measured: `{"x":1}` → `{"x":1}`). A plain scalar, however, keeps `:` without
        // a space within itself, so `{x:1}` has the key "x:1".
        guard cursor.chars[cursor.offset] == ":", cursor.line.number == key.endLineNumber else {
            return false
        }
        cursor.offset += 1
        guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, Self.flowMappingName) }
        // `{x: , y: 1}` — the value is missing, it is `null`.
        return !",}".contains(cursor.chars[cursor.offset])
    }

    /// After a flow map pair: `true` = the map ended, `false` = another pair.
    mutating func flowMappingAdvance(_ cursor: inout FlowCursor, _ open: SourceLine,
                                     _ openColumn: Int) throws -> Bool {
        guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, Self.flowMappingName) }
        switch cursor.chars[cursor.offset] {
        case "}":
            cursor.offset += 1
            return true
        case ",":
            cursor.offset += 1
            guard try flowToken(&cursor) else { throw unclosedFlow(open, openColumn, Self.flowMappingName) }
            if cursor.chars[cursor.offset] == "}" {
                cursor.offset += 1
                return true
            }
            return false
        case "]":
            throw error(cursor.line, "flow mapa „{\" je uzavřená „]\"", column: cursor.column)
        default:
            throw error(cursor.line, "ve flow mapě se čeká „,\" nebo „}\"", column: cursor.column)
        }
    }

    /// A map key from a loaded node. A key is always text (Jackson `{48: x}` gives
    /// the key "48") and **must not** extend onto the next line (measured: Java
    /// rejects `{x` + `  y: 1}`, whereas it accepts a multi-line value).
    func flowKey(_ node: FlowNode) throws -> String {
        guard let text = node.keyText else {
            throw error(node.line, "flow kolekce nemůže být klíčem mapy", column: node.column)
        }
        guard node.line.number == node.endLineNumber else {
            throw error(node.line, "klíč flow mapy nesmí přesahovat na další řádek",
                        column: node.column)
        }
        return text
    }

    /// A plain (unquoted) scalar inside flow. Besides spaces and end of line it is
    /// ended by `,`, `[`, `]`, `{`, `}`, `?` and a colon acting as a separator —
    /// hence `[x}y]` is an error, whereas in a block `a: 1]` is simply the text "1]".
    mutating func flowPlain(_ cursor: inout FlowCursor) throws -> FlowNode {
        let startLine = cursor.line
        let startColumn = cursor.column
        var segments: [String] = []
        var breaks: [String] = []
        /// Start of the last segment — the end of the scalar is after its last
        /// non-space character.
        var lastStart = cursor.offset

        while true {
            let start = cursor.offset
            lastStart = start
            while !cursor.atLineEnd, !isFlowPlainTerminator(cursor.chars, cursor.offset) {
                cursor.offset += 1
            }
            segments.append(String(cursor.chars[start..<cursor.offset]))
            // Folding continues only from a line that did not end with a comment, and only onto a
            // line that is not comment-only.
            guard cursor.atLineEnd, !cursor.hadComment else { break }
            var lookahead = index
            while lookahead < lines.count, lines[lookahead].isBlank {
                try tabInIndent(lines[lookahead])
                lookahead += 1
            }
            guard lookahead < lines.count, !lines[lookahead].isCommentOnly else { break }
            let next = lines[lookahead]
            // An empty line gives a break, not a space (measured: `[x` + `` + `  y]`
            // is `"x\ny"`), and U+2028 gives itself (`[x<U+2028>  y]` is
            // "x<U+2028>y") — both are handled by `foldBreaks`.
            breaks.append(cursor.line.terminator)
            for position in index..<lookahead {
                segments.append("")
                breaks.append(lines[position].terminator)
            }
            index = lookahead + 1
            cursor.line = next
            cursor.chars = try code(next)
            cursor.hadComment = hasComment(next)
            cursor.offset = 0
        }

        var endOffset = cursor.offset
        while endOffset > lastStart, cursor.chars[endOffset - 1] == " " || cursor.chars[endOffset - 1] == "\t" {
            endOffset -= 1
        }
        noteScalarEnd(cursor.line, cursor.chars, endOffset)
        let text = trimmingTrailingBlanks(fold(segments, breaks: breaks))
        let value = try YamlScalarResolver.resolve(text, line: startLine.number, column: startColumn)
        return FlowNode(value: value, keyText: text, line: startLine,
                        column: startColumn, endLineNumber: cursor.line.number)
    }

    /// SnakeYAML: in flow context a plain scalar is ended by `,?[]{}` and a colon
    /// followed by a space, tab, end of line or `,[]{}`. Hence
    /// `[12:30]` is text, but `[x:]` a single-pair map.
    func isFlowPlainTerminator(_ chars: [Character], _ i: Int) -> Bool {
        switch chars[i] {
        case ",", "[", "]", "{", "}", "?":
            return true
        case ":":
            guard i + 1 < chars.count else { return true }
            return " \t,[]{}".contains(chars[i + 1])
        default:
            return false
        }
    }

    func trimmingTrailingBlanks(_ text: String) -> String {
        String(text.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
    }

    func unclosedFlow(_ line: SourceLine, _ column: Int, _ what: String) -> YamlError {
        error(line, "neuzavřená flow \(what)", column: column)
    }

    /// Finds the closing quote from `from`. `nil` means "there is none on this line".
    func closingQuote(_ chars: [Character], from: Int, quote: Character, double: Bool) -> Int? {
        var i = from
        while i < chars.count {
            let ch = chars[i]
            if double, ch == "\\" {
                i += 2
                continue
            }
            if ch == quote {
                // In single quotes `''` is an escaped apostrophe.
                if !double, i + 1 < chars.count, chars[i + 1] == "'" {
                    i += 2
                    continue
                }
                return i
            }
            i += 1
        }
        return nil
    }

    /// What a **group** of consecutive line breaks folds into.
    ///
    /// Port of `ScannerImpl.scanPlainSpaces`/`scanFlowScalarBreaks`: the first break
    /// of the group folds into a space only when it is `"\n"` **and** it is alone in
    /// the group; otherwise a `"\n"` at the start of the group is discarded and all other
    /// breaks are emitted **literally**. U+2028 and U+2029 thus always come out as
    /// themselves, because they are not `"\n"`.
    ///
    /// Measured on Java (Jackson 2.22.0 + SnakeYAML 2.5), `a: x<breaks>␣␣y`:
    ///
    /// | group | Java |
    /// |---|---|
    /// | `\n` | "x y" |
    /// | `U+2028` | "x<U+2028>y" |
    /// | `U+2029` | "x<U+2029>y" |
    /// | `\n\n` | "x\ny" |
    /// | `U+2028 U+2028` | "x<U+2028><U+2028>y" |
    /// | `U+2028 \n` | "x<U+2028>\ny" |
    /// | `\n U+2028` | "x<U+2028>y" |
    /// | `\n U+2028 \n` | "x<U+2028>\ny" |
    /// | `U+2028 \n \n` | "x<U+2028>\n\ny" |
    /// | `\n \n U+2028` | "x\n<U+2028>y" |
    /// | `U+2029 U+2028` | "x<U+2029><U+2028>y" |
    ///
    /// For a group of only `"\n"` this gives exactly what the reader did before
    /// (one break = space, N empty lines = N breaks), so the `"\n"` path
    /// is **not changed** by this.
    static func foldBreaks(_ breaks: [String]) -> String {
        guard let first = breaks.first else { return "" }
        if breaks.count == 1 { return first == "\n" ? " " : first }
        return (first == "\n" ? "" : first) + breaks.dropFirst().joined()
    }

    /// Folds the lines of a scalar. `breaks[i]` is the break between `segments[i]`
    /// and `segments[i+1]`, so there is one fewer of them than segments.
    ///
    /// `escapedBreaks` applies to double quotes: a backslash at the end of a
    /// line **swallows** the break (`"a\` + break + `  b"` is "ab" in Java, not "a b"),
    /// and swallows U+2028 too (measured: `a: "x\<U+2028>␣␣y"` is "xy"). The rest of
    /// the group is still emitted (`a: "x\<U+2028><U+2028>␣␣y"` is "x<U+2028>y").
    func fold(_ segments: [String], breaks: [String],
              escapedBreaks: Bool = false, closedByQuote: Bool = false) -> String {
        var out = ""
        /// Breaks since the last non-empty segment.
        var group: [String] = []
        var joinWithoutSpace = false
        for (offset, segment) in segments.enumerated() {
            // Whitespace is stripped **around a line break**: at the start of
            // a continuation line always, at the end only when a break
            // really follows. The last segment ends with the closing quote, so its
            // trailing spaces are content — measured: `"aaa` + `  bbb   "` is
            // "aaa bbb   " (10 characters), not "aaa bbb".
            var piece = segment
            if offset > 0 {
                piece = String(piece.drop(while: { $0 == " " || $0 == "\t" }))
            }
            if offset + 1 < segments.count {
                let trimmed = trimmingTrailingBlanks(piece)
                // An escaped space or tab (`\ `, `\<TAB>`) is content, not
                // whitespace before a break: `"x\ ` + `"` is "x  " in Java (measured).
                // Exactly that one character after an odd number of
                // backslashes is kept.
                if escapedBreaks, trimmed.count < piece.count,
                   trimmed.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 {
                    piece = trimmed + String(piece[piece.index(piece.startIndex, offsetBy: trimmed.count)])
                } else {
                    piece = trimmed
                }
            }
            var swallowsBreak = false
            if escapedBreaks, offset + 1 < segments.count,
               piece.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 {
                piece.removeLast()
                swallowsBreak = true
            }
            if offset == 0 {
                out = piece
                joinWithoutSpace = swallowsBreak
                continue
            }
            group.append(offset - 1 < breaks.count ? breaks[offset - 1] : "\n")
            if piece.isEmpty, !swallowsBreak { continue }
            if joinWithoutSpace {
                // A backslash swallows the **first** break of the group; the rest stays.
                out += group.dropFirst().joined() + piece
            } else {
                out += Self.foldBreaks(group) + piece
            }
            group = []
            joinWithoutSpace = swallowsBreak
        }
        // A scalar ending with empty lines: the quote comes after them, so they are
        // content. The same rule applies to them as between segments (measured:
        // `"aaa` + `   "` is "aaa ", `"aaa` + `` + `   "` is "aaa\n",
        // `a: 'x<U+2028>   '` is "x<U+2028>").
        //
        // When the last non-empty segment ended with a backslash, it swallows the first
        // break of the group here too (measured: `"x\` + `"` is "x",
        // `a: "\` + `  "` is "", earlier "x " and " ").
        if closedByQuote, !group.isEmpty {
            out += joinWithoutSpace ? group.dropFirst().joined() : Self.foldBreaks(group)
        }
        return out
    }

    /// Resolves the escapes of double quotes.
    func unescape(_ text: String, line: SourceLine) throws -> String {
        var out = ""
        var chars = Array(text)[...]
        while let ch = chars.first {
            chars = chars.dropFirst()
            guard ch == "\\" else {
                out.append(ch)
                continue
            }
            guard let escape = chars.first else {
                throw error(line, "text končí zpětným lomítkem")
            }
            chars = chars.dropFirst()
            switch escape {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "0": out.append("\0")
            case "a": out.append("\u{07}")
            case "b": out.append("\u{08}")
            case "f": out.append("\u{0C}")
            case "v": out.append("\u{0B}")
            case "e": out.append("\u{1B}")
            case "\"", "\\", " ": out.append(escape)
            // YAML 1.1/1.2: NEL, NBSP, LS, PS. `\/` and `\'` SnakeYAML
            // does **not** accept in double quotes (measured) — neither do we.
            case "N": out.append("\u{85}")
            case "_": out.append("\u{A0}")
            case "L": out.append("\u{2028}")
            case "P": out.append("\u{2029}")
            case "x", "u", "U":
                let width = escape == "x" ? 2 : (escape == "u" ? 4 : 8)
                guard chars.count >= width else {
                    throw error(line, "neúplný escape „\\\(escape)\"")
                }
                let digits = String(chars.prefix(width))
                chars = chars.dropFirst(width)
                guard let code = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw error(line, "neplatný escape „\\\(escape)\(digits)\"")
                }
                out.append(Character(scalar))
            default:
                throw error(line, "neznámý escape „\\\(escape)\"")
            }
        }
        return out
    }

    // MARK: helpers

    /// Returns the next significant line — empty and comment-only lines are skipped.
    ///
    /// A comment may be indented any way; it has no effect on the block structure
    /// (measured: `a:` + `    # c` + `  b: 1` Java reads as `{"a":{"b":1}}`).
    mutating func peekSignificant() throws -> SourceLine? {
        while index < lines.count, lines[index].isBlank || lines[index].isCommentOnly {
            try tabInIndent(lines[index])
            index += 1
        }
        if index < lines.count { try tabInIndent(lines[index]) }
        return index < lines.count ? lines[index] : nil
    }

    /// Throws the deferred "tab in indent" error.
    ///
    /// Splitting into lines only remembers it, because after the block scalar's indent
    /// a tab is content. Only lines taken by someone else get here —
    /// there Java rejects a tab, even on a line that is otherwise empty
    /// (`a: 1` + `<TAB>` + `b: 2` is an error at 2:1).
    func tabInIndent(_ line: SourceLine) throws {
        if let column = line.indentTabColumn {
            throw YamlError(message: "tabulátor nelze použít k odsazení",
                            line: line.number, column: column)
        }
    }

    // MARK: line scanning (comments, key separator, tabs)

    /// What the scanner knows about a line. All of this arises in **one pass**, because
    /// otherwise it cannot be decided: to tell whether a quote opens
    /// a quoted scalar or is just a character in the middle of a plain scalar, the line must
    /// be walked from the start, distinguishing positions where a token is expected from the inside of a
    /// plain scalar. That is exactly what `ScannerImpl` in SnakeYAML does.
    struct LineScan {
        /// Offset of the `#` that starts the comment.
        var comment: Int?
        /// Offset of the `:` that separates key from value on the line (outside flow).
        var keySeparator: Int?
        /// Offset of a tab found where a token is expected — an error in Java
        /// („found character '\t' that cannot start any token").
        var tabAtToken: Int?
        /// Did the line end at a position where a token is expected? Not after a plain scalar,
        /// because `scanPlainSpaces` swallows trailing spaces and tabs.
        var endsAtTokenPosition = true
    }

    /// Walks the line (or its end from `from`, which is also a token position).
    ///
    /// The rules are transcribed from SnakeYAML and measured on Java:
    /// - **A quote opens a quoted scalar only at a token position.** Inside
    ///   a plain scalar it is an ordinary character — `name: Field Day 'B # only SSB` has
    ///   the value "Field Day 'B" in Java, `a-'b: 1` is a map with the key "a-'b"
    ///   and `a: x 'y z' # c` is "x 'y z'". Note: after a space **inside** a plain
    ///   scalar we do not return to a token position, the scalar continues.
    /// - **`#` is a comment** at a token position always (`a: [1]# c` → `[1]`),
    ///   otherwise only with a space or tab before it (`a: 1# c` → "1# c").
    /// - **`:` separates a key** when followed by a space, tab or end of line;
    ///   inside flow (`[…]`, `{…}`) always, but `flowMapping` handles it there,
    ///   so it is not recorded here.
    /// - When a quote does not end on the line, the rest is the content of a multi-line
    ///   scalar: no comment, no separator.
    func scanLine(_ chars: [Character], from: Int = 0) -> LineScan {
        var scan = LineScan()
        var i = from
        var flowLevel = 0

        while i < chars.count {
            // At a token position **only spaces** are skipped (like
            // `scanToNextToken`), so a tab here is an error.
            while i < chars.count, chars[i] == " " { i += 1 }
            guard i < chars.count else {
                scan.endsAtTokenPosition = true
                return scan
            }
            scan.endsAtTokenPosition = true
            let ch = chars[i]

            if ch == "\t" {
                scan.tabAtToken = i
                return scan
            }
            if ch == "#" {
                scan.comment = i
                return scan
            }
            if ch == "!" {
                // A type tag is one token. Without this a colon in it
                // (`!!str:` is a valid tag) would be mistaken for a key separator.
                i = Self.tagTokenEnd(chars, i)
                continue
            }
            if (ch == "|" || ch == ">"), flowLevel == 0 {
                // Block scalar header: after the indicators only a
                // comment may follow, and the block content is on the next lines, so scanning
                // ends here. `endsAtTokenPosition` is cleared so that a trailing
                // tab is reported by `blockHeader` — it knows the right column.
                scan.endsAtTokenPosition = false
                var j = i + 1
                while j < chars.count, "+-0123456789".contains(chars[j]) { j += 1 }
                let indicatorsEnd = j
                while j < chars.count, chars[j] == " " { j += 1 }
                if j < chars.count, chars[j] == "#", j > indicatorsEnd { scan.comment = j }
                return scan
            }
            if ch == "\"" || ch == "'" {
                guard let end = closingQuote(chars, from: i + 1, quote: ch, double: ch == "\"") else {
                    // A multi-line quoted scalar — the rest of the line is content.
                    scan.endsAtTokenPosition = false
                    return scan
                }
                i = end + 1
                continue
            }
            if ch == ":", flowLevel > 0 || i + 1 == chars.count
                || chars[i + 1] == " " || chars[i + 1] == "\t" {
                if flowLevel == 0, scan.keySeparator == nil { scan.keySeparator = i }
                i += 1
                continue
            }
            if ch == "[" || ch == "{" {
                flowLevel += 1
                i += 1
                continue
            }
            if ch == "]" || ch == "}" {
                flowLevel = max(0, flowLevel - 1)
                i += 1
                continue
            }
            if ch == "," {
                i += 1
                continue
            }
            if ch == "-", flowLevel == 0,
               i + 1 == chars.count || chars[i + 1] == " " || chars[i + 1] == "\t" {
                i += 1
                continue
            }
            // Plain scalar: `scanPlain` + `scanPlainSpaces`.
            scanPlainOnLine(chars, &i, flowLevel: flowLevel, into: &scan)
            if scan.comment != nil { return scan }
        }
        return scan
    }

    /// A plain scalar on one line as SnakeYAML reads it: runs
    /// without spaces alternate with spaces/tabs between them. The scalar ends when after the spaces
    /// comes `#` (a comment) or an indicator.
    func scanPlainOnLine(_ chars: [Character], _ i: inout Int,
                         flowLevel: Int, into scan: inout LineScan) {
        scan.endsAtTokenPosition = false
        while true {
            let chunkStart = i
            while i < chars.count, !isPlainChunkEnd(chars, i, flowLevel: flowLevel) { i += 1 }
            if i == chunkStart {
                scan.endsAtTokenPosition = true
                // A colon after spaces is a key separator — the plain scalar
                // ends at it and the outer loop takes `:` (`key : value` is in Java
                // `{"key":"value"}`, SnakeYAML ends `scanPlain` at ": " and then
                // `fetchValue` makes the whole scalar a simple key).
                if chars[i] == ":" { return }
                // An indicator right away that the outer loop does not consume (in flow
                // e.g. `?`). We skip it, otherwise the scanner would loop forever.
                i += 1
                return
            }
            if i >= chars.count { return }
            let spaceStart = i
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
            if i == spaceStart {
                scan.endsAtTokenPosition = true
                return
            }
            // `SourceLine` cut off trailing spaces and tabs, but if there were any here,
            // the scalar ends with them (and a tab in them is not an error).
            if i >= chars.count { return }
            if chars[i] == "#" {
                scan.comment = i
                return
            }
        }
    }

    /// A continuation line of a block plain scalar (without indent), read like
    /// `scanPlain` in SnakeYAML **inside** a scalar: runs and spaces, no
    /// indicators. The scalar on the line ends only with a colon followed by a space or end of
    /// line (`keySeparator`) or `#` after a space (`comment`).
    func scanPlainContinuation(_ chars: [Character]) -> LineScan {
        var scan = LineScan()
        var i = 0
        if !chars.isEmpty, !isPlainChunkEnd(chars, 0, flowLevel: 0) {
            scanPlainOnLine(chars, &i, flowLevel: 0, into: &scan)
        }
        // In block context a run ends without a space after it only at a separator.
        if scan.comment == nil, i < chars.count, chars[i] == ":" { scan.keySeparator = i }
        return scan
    }

    /// Where one run of a plain scalar ends. `NULL_BL_T_LINEBR` in SnakeYAML, plus
    /// `:` acting as a separator and in flow also `,?[]{}`.
    func isPlainChunkEnd(_ chars: [Character], _ i: Int, flowLevel: Int) -> Bool {
        let ch = chars[i]
        if ch == " " || ch == "\t" { return true }
        if ch == ":" {
            guard i + 1 < chars.count else { return true }
            let next = chars[i + 1]
            if next == " " || next == "\t" { return true }
            return flowLevel > 0 && ",[]{}".contains(next)
        }
        if flowLevel > 0, ",?[]{}".contains(ch) { return true }
        return false
    }

    /// Content of the line without a trailing comment and without spaces before it.
    ///
    /// It is also the place where **tabs are verified**: a tab where a
    /// token is expected Java rejects (`b: [1] <TAB>`, `a: <TAB>`, `a: [1,<TAB>`).
    /// After a plain scalar a trailing tab is conversely fine (`a: 1 <TAB>`).
    func code(_ line: SourceLine) throws -> [Character] {
        try tabInIndent(line)
        let chars = Array(line.text)
        let scan = scanLine(chars)
        try rejectTabs(scan, line: line)
        guard let start = scan.comment else { return chars }
        var end = start
        while end > 0, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
        return Array(chars[0..<end])
    }

    func hasComment(_ line: SourceLine) -> Bool { scanLine(Array(line.text)).comment != nil }

    func rejectTabs(_ scan: LineScan, line: SourceLine) throws {
        if let tab = scan.tabAtToken {
            throw error(line, "tabulátor nelze použít jako oddělovač",
                        column: line.indent + tab + 1)
        }
        // A trailing tab after a comment belongs to the comment — it reaches to the end of the
        // line (`a: [1] # c<TAB>` and `a: "x" # c<TAB>` Java reads; measured).
        if scan.endsAtTokenPosition, scan.comment == nil, line.trailingTab {
            throw error(line, "tabulátor nelze použít jako oddělovač")
        }
    }

    /// Discards a trailing comment starting at `from` or later. Characters before
    /// `from` stay untouched — flow needs it when content continues after the closing
    /// quote.
    func truncatingComment(_ chars: [Character], from: Int) -> (chars: [Character], hadComment: Bool) {
        guard let start = scanLine(chars, from: from).comment else { return (chars, false) }
        var end = start
        while end > from, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
        return (Array(chars[0..<end]), true)
    }

    func isSequenceEntry(_ chars: [Character]) -> Bool {
        guard chars.first == "-" else { return false }
        return chars.count == 1 || chars[1] == " "
    }

    /// Offset of the colon that separates key from value. `a:b` is not a key
    /// (measured: `v: http://x` is text), `a-'b: 1` conversely is.
    func keySeparatorOffset(_ chars: [Character]) -> Int? {
        scanLine(chars).keySeparator
    }

    /// A plain scalar must not contain a key separator — Java reports an error for `v: abc:`
    /// and for `a: 1` + an indented `b: 2`, not text.
    func rejectKeySeparator(in chars: [Character], line: SourceLine, baseColumn: Int) throws {
        if let separator = keySeparatorOffset(chars) {
            throw error(line, "dvojtečka v hodnotě: mapa tady začínat nemůže",
                        column: baseColumn + separator + 1)
        }
    }

    func firstNonSpace(_ chars: [Character], from: Int) -> Int? {
        var i = from
        while i < chars.count, chars[i] == " " { i += 1 }
        return i < chars.count ? i : nil
    }

    /// A block map key. A key is always text (Jackson `48:` gives the key "48"),
    /// for a quoted one the quotes are removed and **escapes resolved** — Java has
    /// for `"a\tb": 1` a key with a tab and for `'a''b': 1` the key "a'b" (measured).
    /// `flowKey` does the same via `scanQuoted`, so the two paths do not diverge.
    ///
    /// An unquoted empty key (`: 1`) is an error in Java; `"": 1` is conversely
    /// a valid empty key.
    func blockKey(_ chars: [Character], from: Int, upTo separator: Int,
                  line: SourceLine) throws -> String {
        var end = separator
        while end > from, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
        var start = from
        while start < end, chars[start] == " " { start += 1 }
        guard start < end else {
            throw error(line, "chybí klíč před „: \"", column: line.indent + start + 1)
        }
        let quote = chars[start]
        if quote == "\"" || quote == "'",
           let close = closingQuote(chars, from: start + 1, quote: quote, double: quote == "\""),
           close == end - 1 {
            let inner = String(chars[(start + 1)..<close])
            if quote == "\"" { return try unescape(inner, line: line) }
            return inner.replacingOccurrences(of: "''", with: "'")
        }
        return String(chars[start..<end])
    }

    /// An error with the reader's **own** position — the place where the reader recognised the error.
    ///
    /// Beware of the numbers in comments on individual `throw`s in this file
    /// ("measured 1:11", "error 3:3"): those are the **SnakeYAML problem marks**
    /// as measured on Java, and the reader imitates them as the error location. The user
    /// however gets from Java the position from Jackson — the end of the last event before
    /// the error —, and `YamlParser.javaPositioned` computes it via
    /// `JavaYamlErrorLocator`. The own position remains only where
    /// Java reads the input without an error (recorded divergences).
    func error(_ line: SourceLine, _ message: String,
               kind: YamlError.Kind = .syntax, column: Int? = nil) -> YamlError {
        YamlError(kind: kind, message: message, line: line.number,
                  column: column ?? line.indent + 1)
    }
}

// MARK: - Scalar typing

/// Determines the type of an unquoted scalar **like Jackson**, not like the YAML spec.
///
/// The procedure is transcribed from the pair Java relies on:
/// 1. `org.yaml.snakeyaml.resolver.Resolver` assigns a tag by patterns
///    (BOOL, INT, FLOAT, NULL; other tags lead to text),
/// 2. `com.fasterxml.jackson.dataformat.yaml.YAMLParser._decodeNumberScalar`
///    computes the number — and what it does not compute (sexagesimal), it leaves as text.
///
/// The tags TIMESTAMP, MERGE and YAML we do not distinguish: Jackson returns them as
/// text anyway, exactly like an untagged scalar.
enum YamlScalarResolver {

    /// Words SnakeYAML takes as a boolean. The single-character `y`/`n`
    /// and mixed case (`yEs`) are **not** in the list — measured on Java.
    private static let booleanWords: [String: Bool] = [
        "yes": true, "Yes": true, "YES": true,
        "no": false, "No": false, "NO": false,
        "true": true, "True": true, "TRUE": true,
        "false": false, "False": false, "FALSE": false,
        "on": true, "On": true, "ON": true,
        "off": false, "Off": false, "OFF": false,
    ]

    // SnakeYAML has even a lone space in the NULL pattern, but it does not reach us
    // — a plain scalar is trimmed before typing.
    private static let nullWords: Set<String> = ["~", "null", "Null", "NULL"]

    /// SnakeYAML no longer tests longer text for a number (`limit` on the INT and FLOAT patterns).
    private static let numberLimit = 1024

    static func resolve(_ text: String, line: Int, column: Int) throws -> YamlValue {
        if text.isEmpty { return .null }
        if nullWords.contains(text) { return .null }
        if let flag = booleanWords[text] { return .bool(flag, raw: text) }
        let chars = Array(text)
        if chars.count <= numberLimit {
            if matchesInteger(chars) {
                return try decodeInteger(text, chars: chars, line: line, column: column)
            }
            if matchesFloat(chars) {
                return try decodeFloat(text, line: line, column: column)
            }
        }
        return .string(text)
    }

    /// Typing of a scalar that has an **explicit** tag. Non-empty text, the tag
    /// is not `!` — `BlockParser.taggedScalar` takes care of both.
    ///
    /// Measured on Java (Jackson `_decodeScalar` with a non-empty `typeTag`):
    /// - `!!int` and `!!bool` try the conversion and when it fails return **text**
    ///   (`!!int abc` → "abc", `!!bool 1` → "1"),
    /// - `!!float` conversely **rejects** a notation it cannot handle ("Malformed numeric
    ///   value '.inf'"),
    /// - `!!null` discards the content (`!!null yes` → `null`),
    /// - `!!str` and every other tag gives text.
    static func resolve(tag: YamlTag, text: String,
                        line: Int, column: Int) throws -> YamlValue {
        switch tag {
        case .str, .other, .nonSpecific:
            return .string(text)
        case .null:
            return .null
        case .bool:
            guard let flag = jacksonBoolean(text) else { return .string(text) }
            return .bool(flag, raw: text)
        case .int:
            return try decodeIntegerTag(text, line: line, column: column)
        case .float:
            return try decodeFloat(text, line: line, column: column)
        }
    }

    /// Jackson's `_matchYAMLBoolean` — a wider set than implicit typing:
    /// it accepts `y`/`n` too and is case-insensitive (measured: `a: y` is text
    /// "y", but `a: !!bool y` is `true`, and `!!bool yEs` too).
    private static func jacksonBoolean(_ text: String) -> Bool? {
        switch text.count {
        case 1:
            switch text {
            case "y", "Y": return true
            case "n", "N": return false
            default: return nil
            }
        case 2:
            if text.caseInsensitiveCompare("no") == .orderedSame { return false }
            if text.caseInsensitiveCompare("on") == .orderedSame { return true }
            return nil
        case 3:
            if text.caseInsensitiveCompare("yes") == .orderedSame { return true }
            if text.caseInsensitiveCompare("off") == .orderedSame { return false }
            return nil
        case 4:
            return text.caseInsensitiveCompare("true") == .orderedSame ? true : nil
        case 5:
            return text.caseInsensitiveCompare("false") == .orderedSame ? false : nil
        default:
            return nil
        }
    }

    // MARK: patterns

    /// SnakeYAML `Resolver.INT`: binary, octal, decimal, hexadecimal
    /// and sexagesimal, underscores allowed.
    private static func matchesInteger(_ chars: [Character]) -> Bool {
        var i = 0
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        let body = Array(chars[i...])
        if body.isEmpty { return false }
        if body == ["0"] { return true }
        if body[0] == "0", body.count >= 2 {
            if body[1] == "b" { return matchesRadix(Array(body[2...]), digits: "01") }
            if body[1] == "x" { return matchesRadix(Array(body[2...]), digits: "0123456789abcdefABCDEF") }
            return matchesRadix(Array(body[1...]), digits: "01234567")
        }
        // decimal or sexagesimal
        guard body[0] >= "1", body[0] <= "9" else { return false }
        var j = 1
        while j < body.count, body[j].isASCII, body[j].isNumber || body[j] == "_" { j += 1 }
        if j == body.count { return true }
        return matchesSexagesimalTail(Array(body[j...]), fraction: .forbidden)
    }

    /// `_*<digit>[<digit>_]*` — the shape of digits after `0b`, `0x` and after an octal zero.
    private static func matchesRadix(_ chars: [Character], digits: String) -> Bool {
        var i = 0
        while i < chars.count, chars[i] == "_" { i += 1 }
        guard i < chars.count, digits.contains(chars[i]) else { return false }
        i += 1
        while i < chars.count, digits.contains(chars[i]) || chars[i] == "_" { i += 1 }
        return i == chars.count
    }

    private enum Fraction { case forbidden, required }

    /// `(?::[0-5]?[0-9])+`, for the decimal variant also `\.[0-9_]*` at the end.
    private static func matchesSexagesimalTail(_ chars: [Character], fraction: Fraction) -> Bool {
        var i = 0
        var groups = 0
        while i < chars.count, chars[i] == ":" {
            i += 1
            if i + 1 < chars.count, chars[i] >= "0", chars[i] <= "5", isDigit(chars[i + 1]) {
                i += 2
            } else if i < chars.count, isDigit(chars[i]) {
                i += 1
            } else {
                return false
            }
            groups += 1
        }
        guard groups > 0 else { return false }
        switch fraction {
        case .forbidden:
            return i == chars.count
        case .required:
            guard i < chars.count, chars[i] == "." else { return false }
            i += 1
            while i < chars.count, isDigit(chars[i]) || chars[i] == "_" { i += 1 }
            return i == chars.count
        }
    }

    private static func isDigit(_ ch: Character) -> Bool { ch >= "0" && ch <= "9" }

    /// SnakeYAML `Resolver.FLOAT`.
    private static func matchesFloat(_ chars: [Character]) -> Bool {
        var i = 0
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        let body = Array(chars[i...])
        if body.isEmpty { return false }
        // `.inf` (with a sign) and `.nan` (without)
        if body == ["."] { return false }
        if body.count > 1, body[0] == "." {
            let word = String(body.dropFirst())
            if ["inf", "Inf", "INF"].contains(word) { return true }
            if ["nan", "NaN", "NAN"].contains(word) { return i == 0 }
        }
        // `.[0-9_]+([eE][-+]?[0-9]+)?`
        if body[0] == "." {
            var j = 1
            var digits = 0
            while j < body.count, isDigit(body[j]) || body[j] == "_" {
                if isDigit(body[j]) { digits += 1 }
                j += 1
            }
            guard digits > 0 else { return false }
            return j == body.count || matchesExponent(Array(body[j...]))
        }
        guard isDigit(body[0]) else { return false }
        var j = 1
        while j < body.count, isDigit(body[j]) || body[j] == "_" { j += 1 }
        if j == body.count { return false }  // whole number, not decimal
        if body[j] == "." {
            j += 1
            while j < body.count, isDigit(body[j]) || body[j] == "_" { j += 1 }
            return j == body.count || matchesExponent(Array(body[j...]))
        }
        if body[j] == "e" || body[j] == "E" {
            return matchesExponent(Array(body[j...]))
        }
        if body[j] == ":" {
            return matchesSexagesimalTail(Array(body[j...]), fraction: .required)
        }
        return false
    }

    /// `[eE][-+]?[0-9]+`
    private static func matchesExponent(_ chars: [Character]) -> Bool {
        guard let first = chars.first, first == "e" || first == "E" else { return false }
        var i = 1
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        guard i < chars.count else { return false }
        while i < chars.count, isDigit(chars[i]) { i += 1 }
        return i == chars.count
    }

    // MARK: computation

    /// Jackson `_decodeNumberScalar`. What Jackson does not compute (sexagesimal),
    /// it returns as text — we copy that.
    private static func decodeInteger(_ text: String, chars: [Character],
                                      line: Int, column: Int) throws -> YamlValue {
        var i = 0
        var negative = false
        if chars[0] == "-" { negative = true; i = 1 } else if chars[0] == "+" { i = 1 }
        if chars[i] == "0" {
            i += 1
            if i == chars.count { return .int(0, raw: text) }
            switch chars[i] {
            case "b", "B":
                return try integer(String(chars[(i + 1)...]), radix: 2, negative: negative,
                                   text: text, line: line, column: column)
            case "x", "X":
                return try integer(String(chars[(i + 1)...]), radix: 16, negative: negative,
                                   text: text, line: line, column: column)
            default:
                return try integer(String(chars[i...]), radix: 8, negative: negative,
                                   text: text, line: line, column: column)
            }
        }
        var j = i
        while j < chars.count, isDigit(chars[j]) || chars[j] == "_" { j += 1 }
        guard j == chars.count else { return .string(text) }  // sexagesimal → text
        return try integer(String(chars[i...]), radix: 10, negative: negative,
                           text: text, line: line, column: column)
    }

    /// Java has `BigInteger` for large numbers, Swift only `Int`. Out of range we therefore
    /// **report an error** — silently rounding to `Double` would mean returning
    /// a different value than Java has. There is no such number in `contest-data/`.
    ///
    /// The sign goes **into** `Int(_:radix:)`, not onto the result: the magnitude of `Int.min`
    /// does not fit into `Int`, but the value does, and Java reads it (measured
    /// `a: -9223372036854775808` → `-9223372036854775808`). The writer produces it,
    /// so the symmetry of reader and writer relies on it. It also applies to
    /// hexadecimal and underscore notation (`-0x8000000000000000`,
    /// `-9_223_372_036_854_775_808`).
    private static func integer(_ digits: String, radix: Int, negative: Bool,
                                text: String, line: Int, column: Int) throws -> YamlValue {
        let cleaned = digits.replacingOccurrences(of: "_", with: "")
        guard let value = Int(negative ? "-" + cleaned : cleaned, radix: radix) else {
            throw YamlError(kind: .unsupported,
                            message: "celé číslo „\(text)\" se nevejde do Int (Java tu má BigInteger)",
                            line: line, column: column)
        }
        return .int(value, raw: text)
    }

    /// Jackson `_decodeNumberIntTag` — the path for the **explicit** tag `!!int`.
    ///
    /// The `Resolver.INT` pattern is **not used** here (and that is a measured difference from
    /// implicit typing): `!!int 0X10` is 16, whereas untagged `0X10` is
    /// text, because the pattern accepts only a lowercase `x`. A notation that does not convert to a number
    /// is not an error — it is text (`!!int abc` → "abc").
    private static func decodeIntegerTag(_ text: String,
                                         line: Int, column: Int) throws -> YamlValue {
        let chars = Array(text)
        var i = 0
        var negative = false
        if chars[0] == "-" { negative = true; i = 1 } else if chars[0] == "+" { i = 1 }
        guard i < chars.count else { return .string(text) }
        if chars[i] == "0" {
            i += 1
            if i == chars.count { return .int(0, raw: text) }
            switch chars[i] {
            case "b", "B":
                return try taggedInteger(chars[(i + 1)...], radix: 2, negative: negative,
                                         text: text, line: line, column: column)
            case "x", "X":
                return try taggedInteger(chars[(i + 1)...], radix: 16, negative: negative,
                                         text: text, line: line, column: column)
            default:
                return try taggedInteger(chars[i...], radix: 8, negative: negative,
                                         text: text, line: line, column: column)
            }
        }
        return try taggedInteger(chars[i...], radix: 10, negative: negative,
                                 text: text, line: line, column: column)
    }

    /// Digits of a tagged integer. An invalid notation gives **text** (Jackson
    /// does not throw for `!!int`, it just does not convert); an error remains only for a number that
    /// does not fit into `Int` — Java has `BigInteger` there. The sign is passed into
    /// `Int(_:radix:)` for the same reason as in `integer(_:…)` (measured:
    /// `a: !!int -9223372036854775808` and `!!int -0x8000000000000000` give `Int.min`).
    private static func taggedInteger(_ digits: ArraySlice<Character>, radix: Int, negative: Bool,
                                      text: String, line: Int, column: Int) throws -> YamlValue {
        let cleaned = digits.filter { $0 != "_" }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.hexDigitValue.map { $0 < radix } ?? false })
        else { return .string(text) }
        guard let value = Int(negative ? "-" + String(cleaned) : String(cleaned), radix: radix) else {
            throw YamlError(kind: .unsupported,
                            message: "celé číslo „\(text)\" se nevejde do Int (Java tu má BigInteger)",
                            line: line, column: column)
        }
        return .int(value, raw: text)
    }

    /// Jackson `_cleanYamlFloat` + the later `getDoubleValue()`. What does not convert to double
    /// (`.inf`, `.nan`, sexagesimal `1:30.5`) is an **error** in Java —
    /// we copy that, silent text would be worse here.
    private static func decodeFloat(_ text: String, line: Int, column: Int) throws -> YamlValue {
        var cleaned = text.replacingOccurrences(of: "_", with: "")
        if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        guard let value = Double(cleaned), value.isFinite else {
            throw YamlError(message: "neplatné desetinné číslo „\(text)\"", line: line, column: column)
        }
        return .double(value, raw: text)
    }
}
