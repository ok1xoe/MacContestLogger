import Foundation

/// Translation of a Java pattern (`java.util.regex.Pattern`, JDK 21.0.2) to ICU.
///
/// It is a **port of Java's parser** (`Pattern.expr/sequence/atom/closure/group0/
/// escape/clazz/range/family`) with the same cursor helpers (`peek/next/read/
/// skip/unread`) over an array of code points terminated by two zeros. Thanks to that,
/// not only the interpretation of the pattern matches but also the **Java syntax errors** — description and index
/// (`cursor - 1`) — and all the quirks of classes (`[]a]`, `[a&&]`, `[^a[b]]`…).
///
/// Instead of Java nodes, ICU text is generated in which everything is explicit:
/// - every character class (also `\d`, `\p{L}`, `.`, a single character under `(?i)`) is
///   computed as a set of code points and printed as `[\x{…}-\x{…}…]`;
/// - anchors `^ $ \Z \b \B \R` are printed as lookarounds following Java's
///   `Caret/Dollar/Bound/LineEnding.match`;
/// - flags `(?i) (?m) (?s) (?d)` are not passed to ICU — the translator tracks them
///   and they show up in the generated sets and anchors.
///
/// What cannot be converted is rejected as `JavaRegexError.Kind.unsupported`.
struct JavaRegexTranslator {

    struct Output {
        let icu: String
        let groupCount: Int
        let groupNames: [String: Int]
    }

    static func translate(_ pattern: String) throws(JavaRegexError) -> Output {
        var translator = JavaRegexTranslator(pattern: pattern)
        return try translator.run()
    }

    // MARK: - Java flags (values from `Pattern`)

    private static let unixLines = 0x01
    private static let caseInsensitive = 0x02
    private static let comments = 0x04
    private static let multiline = 0x08
    private static let dotall = 0x20
    private static let unicodeCase = 0x40
    private static let canonEq = 0x80
    private static let unicodeCharacterClass = 0x100

    /// Repetition ceiling in ICU (`{n}` above 2^24 − 1 is rejected by ICU, Java accepts up to 2^31 − 1).
    private static let icuMaxRepetition = 16_777_215

    /// How many nonspacing marks before the `\b` position it still inspects. Java looks for
    /// the base character without limit; an ICU look-behind must have a bounded length.
    static let boundMarkRun = 100

    // MARK: - Parser state

    private let pattern: String
    private var temp: [Int32]
    private var patternLength: Int
    private var cursor = 0
    private var flags0 = 0
    private var capturingGroupCount = 1
    private var namedGroups: [String: Int] = [:]
    /// Result of `escape()` for a node outside a class (Java's `root`).
    private var root = ""
    /// Result of `escape()` for a class (Java's `predicate`).
    private var predicate = CodePointSet.empty
    /// Group nesting: because of the look-behind rules.
    private var frames: [Frame] = []
    /// Number of currently open groups and character classes, guarded against
    /// `maxNestingDepth`.
    private var nesting = 0

    /// Maximum number of nested groups and character classes combined. A deeper pattern
    /// is rejected by the adapter as `.unsupported` — a **divergence from Java**, which
    /// does not limit depth (a deliberate divergence from Java v1.1.1).
    ///
    /// Why: the translator is recursive (`sequence` → `expr` → `group0`, resp.
    /// `clazz` → `clazz`) and a pattern also arrives from the network (`validation.regex`
    /// in a definition downloaded by `DefinitionUpdater`). On a thread with 512 KB
    /// in a debug build it crashed from 31–33 nested groups (~15 kB of stack per
    /// level) and from 86–93 classes; 16 is roughly half. Real patterns have 1–2.
    static let maxNestingDepth = 16

    /// Opens the next level of a group or class starting at index `start`.
    private mutating func enterNesting(at start: Int) throws(JavaRegexError) {
        guard nesting < Self.maxNestingDepth else {
            throw JavaRegexError(kind: .unsupported,
                                 reason: "příliš hluboké zanoření skupin a znakových tříd"
                                     + " (víc než \(Self.maxNestingDepth))",
                                 index: start, pattern: pattern)
        }
        nesting += 1
    }

    private enum Frame {
        case lookbehind(hasBackref: Bool)
        case lookahead
        case other
    }

    private init(pattern: String) {
        self.pattern = pattern
        var points = pattern.unicodeScalars.map { Int32(bitPattern: $0.value) }
        patternLength = points.count
        points.append(0)
        points.append(0)
        temp = points
    }

    private mutating func run() throws(JavaRegexError) -> Output {
        removeQEQuoting()
        let body = try expr()
        if patternLength != cursor {
            if peek() == ch(")") {
                throw error("Unmatched closing ')'")
            } else if cursor == patternLength + 1 && temp[patternLength - 1] == ch("\\") {
                throw error("Unescaped trailing backslash")
            } else {
                throw error("Unexpected internal error")
            }
        }
        let groups = capturingGroupCount - 1
        return Output(icu: Self.resolveBackrefs(body, groupCount: groups), groupCount: groups, groupNames: namedGroups)
    }

    // MARK: - Cursor helpers (1:1 with `Pattern`)

    private func ch(_ c: Unicode.Scalar) -> Int32 { Int32(c.value) }

    private func at(_ index: Int) -> Int32 {
        index >= 0 && index < temp.count ? temp[index] : 0
    }

    private func has(_ flag: Int) -> Bool { flags0 & flag != 0 }

    private func peek() -> Int32 { at(cursor) }

    private mutating func read() -> Int32 {
        let c = at(cursor)
        cursor += 1
        return c
    }

    private mutating func next() -> Int32 {
        cursor += 1
        return at(cursor)
    }

    private mutating func nextEscaped() -> Int32 { next() }

    private mutating func skip() -> Int32 {
        let c = at(cursor + 1)
        cursor += 2
        return c
    }

    private mutating func unread() { cursor -= 1 }

    private mutating func accept(_ expected: Unicode.Scalar, _ message: String) throws(JavaRegexError) {
        let c = at(cursor)
        cursor += 1
        if c != ch(expected) {
            throw error(message)
        }
    }

    private mutating func mark(_ c: Int32) {
        if patternLength < temp.count { temp[patternLength] = c }
    }

    private func error(_ reason: String) -> JavaRegexError {
        JavaRegexError(kind: .syntax, reason: reason, index: cursor - 1, pattern: pattern)
    }

    private func unsupported(_ reason: String) -> JavaRegexError {
        JavaRegexError(kind: .unsupported, reason: reason, index: max(cursor - 1, 0), pattern: pattern)
    }

    // MARK: - \Q…\E (Java's `RemoveQEQuoting`)

    private mutating func removeQEQuoting() {
        let pLen = patternLength
        var i = 0
        while i < pLen - 1 {
            if temp[i] != ch("\\") {
                i += 1
            } else if temp[i + 1] != ch("Q") {
                i += 2
            } else {
                break
            }
        }
        if i >= pLen - 1 { return }
        var out = Array(temp[0..<i])
        i += 2
        var inQuote = true
        var beginQuote = true
        while i < pLen {
            let c = temp[i]
            i += 1
            if !Self.isAscii(c) || Self.isAsciiAlpha(c) {
                out.append(c)
            } else if Self.isAsciiDigit(c) {
                if beginQuote {
                    // `\x`/`\u`/`\0` may precede the quote and a digit would stick to it.
                    out.append(contentsOf: [ch("\\"), ch("x"), ch("3")])
                }
                out.append(c)
            } else if c != ch("\\") {
                if inQuote { out.append(ch("\\")) }
                out.append(c)
            } else if inQuote {
                if at(i) == ch("E") {
                    i += 1
                    inQuote = false
                } else {
                    out.append(ch("\\"))
                    out.append(ch("\\"))
                }
            } else {
                if at(i) == ch("Q") {
                    i += 1
                    inQuote = true
                    beginQuote = true
                    continue
                } else {
                    out.append(c)
                    if i != pLen {
                        out.append(temp[i])
                        i += 1
                    }
                }
            }
            beginQuote = false
        }
        patternLength = out.count
        out.append(0)
        out.append(0)
        temp = out
    }

    // MARK: - Expressions

    private mutating func expr() throws(JavaRegexError) -> String {
        var alternatives: [String] = []
        while true {
            alternatives.append(try sequence())
            if peek() != ch("|") {
                return alternatives.joined(separator: "|")
            }
            _ = next()
        }
    }

    private mutating func sequence() throws(JavaRegexError) -> String {
        var out = ""
        loop: while true {
            var c = peek()
            var node: String
            switch c {
            case ch("("):
                if let group = try group0() {
                    out += group
                }
                continue loop
            case ch("["):
                node = Self.classText(try clazz(consume: true))
            case ch("\\"):
                c = nextEscaped()
                if c == ch("p") || c == ch("P") {
                    var oneLetter = true
                    let complement = c == ch("P")
                    c = next()
                    if c != ch("{") {
                        unread()
                    } else {
                        oneLetter = false
                    }
                    node = Self.classText(try family(singleLetter: oneLetter, complement: complement))
                } else {
                    unread()
                    node = try atom()
                }
            case ch("^"):
                _ = next()
                if has(Self.multiline) {
                    node = has(Self.unixLines) ? Self.unixCaret : Self.caret
                } else {
                    node = Self.begin
                }
            case ch("$"):
                _ = next()
                node = Self.dollar(multiline: has(Self.multiline), unixLines: has(Self.unixLines))
            case ch("."):
                _ = next()
                if has(Self.dotall) {
                    node = Self.classText(.all)
                } else if has(Self.unixLines) {
                    node = Self.classText(Self.unixDotSet)
                } else {
                    node = Self.classText(Self.dotSet)
                }
            case ch("|"), ch(")"):
                break loop
            case ch("]"), ch("}"):
                node = try atom()
            case ch("?"), ch("*"), ch("+"):
                _ = next()
                throw error("Dangling meta character '\(Character(Unicode.Scalar(UInt8(c))))'")
            case 0:
                if cursor >= patternLength {
                    break loop
                }
                node = try atom()
            default:
                node = try atom()
            }
            out += try closure(node, isGroup: false)
        }
        return out
    }

    /// Java `atom()`: a sequence of literals (slice) or a single node from `escape()`.
    /// Before a quantifier Java splits off the last character of the slice, so the quantifier
    /// applies only to it — hence each character is emitted as a separate atom.
    private mutating func atom() throws(JavaRegexError) -> String {
        var chars: [Int32] = []
        var prev = -1
        var c = peek()
        loop: while true {
            switch c {
            case ch("*"), ch("+"), ch("?"), ch("{"):
                if chars.count > 1 {
                    cursor = prev
                    chars.removeLast()
                }
                break loop
            case ch("$"), ch("."), ch("^"), ch("("), ch("["), ch("|"), ch(")"):
                break loop
            case ch("\\"):
                c = nextEscaped()
                if c == ch("p") || c == ch("P") {
                    if !chars.isEmpty {
                        unread()
                        break loop
                    }
                    let complement = c == ch("P")
                    var oneLetter = true
                    c = next()
                    if c != ch("{") {
                        unread()
                    } else {
                        oneLetter = false
                    }
                    return Self.classText(try family(singleLetter: oneLetter, complement: complement))
                }
                unread()
                prev = cursor
                let value = try escape(inClass: false, create: chars.isEmpty, isRange: false)
                if value >= 0 {
                    chars.append(value)
                    c = peek()
                    continue loop
                } else if chars.isEmpty {
                    return root
                }
                cursor = prev
                break loop
            case 0:
                if cursor >= patternLength {
                    break loop
                }
                prev = cursor
                chars.append(c)
                c = next()
            default:
                prev = cursor
                chars.append(c)
                c = next()
            }
        }
        if chars.isEmpty {
            return "(?:)"
        }
        return chars.map { Self.classOrLiteral(single($0)) }.joined()
    }

    // MARK: - Groups and flags

    private mutating func group0() throws(JavaRegexError) -> String? {
        // A group starts at `(` (the cursor stands on it). `(?i)` without
        // a body is counted too — before it is recognized that it is not a group; the limit is far away.
        try enterNesting(at: cursor)
        defer { nesting -= 1 }
        let save = flags0
        var head: String
        var c = next()
        if c == ch("?") {
            c = skip()
            switch c {
            case ch(":"):
                frames.append(.other)
                head = "(?:" + (try expr()) + ")"
            case ch("="), ch("!"):
                frames.append(.lookahead)
                // ICU does not allow quantifying a lookaround directly (`(?=a)*`), Java does.
                head = "(?:" + (c == ch("=") ? "(?=" : "(?!") + (try expr()) + "))"
            case ch(">"):
                frames.append(.other)
                head = "(?>" + (try expr()) + ")"
            case ch("<"):
                c = read()
                if c != ch("=") && c != ch("!") {
                    let name = try groupname(c)
                    if namedGroups[name] != nil {
                        throw error("Named capturing group <\(name)> is already defined")
                    }
                    capturingGroupCount += 1
                    namedGroups[name] = capturingGroupCount - 1
                    frames.append(.other)
                    head = "(" + (try expr()) + ")"
                } else {
                    frames.append(.lookbehind(hasBackref: false))
                    head = "(?:" + (c == ch("=") ? "(?<=" : "(?<!") + (try expr()) + "))"
                    if case .lookbehind(true) = frames.last {
                        // Java `TreeInfo.maxValid == false`: a backreference has no known length.
                        throw error("Look-behind group does not have an obvious maximum length")
                    }
                }
            case ch("$"), ch("@"):
                throw error("Unknown group type")
            default:
                unread()
                try addFlag()
                c = read()
                if c == ch(")") {
                    try checkFlags()
                    return nil
                }
                if c != ch(":") {
                    throw error("Unknown inline modifier")
                }
                try checkFlags()
                frames.append(.other)
                head = "(?:" + (try expr()) + ")"
            }
        } else {
            capturingGroupCount += 1
            frames.append(.other)
            head = "(" + (try expr()) + ")"
        }
        try accept(")", "Unclosed group")
        frames.removeLast()
        flags0 = save
        return try closure(head, isGroup: true)
    }

    private mutating func groupname(_ first: Int32) throws(JavaRegexError) -> String {
        var c = first
        guard Self.isAsciiAlpha(c) else {
            throw error("capturing group name does not start with a Latin letter")
        }
        var name = ""
        repeat {
            name.unicodeScalars.append(Unicode.Scalar(UInt8(c)))
            c = read()
        } while Self.isAsciiAlpha(c) || Self.isAsciiDigit(c)
        if c != ch(">") {
            throw error("named capturing group is missing trailing '>'")
        }
        return name
    }

    private mutating func addFlag() throws(JavaRegexError) {
        var c = peek()
        while true {
            switch c {
            case ch("i"): flags0 |= Self.caseInsensitive
            case ch("m"): flags0 |= Self.multiline
            case ch("s"): flags0 |= Self.dotall
            case ch("d"): flags0 |= Self.unixLines
            case ch("u"): flags0 |= Self.unicodeCase
            case ch("c"): flags0 |= Self.canonEq
            case ch("x"):
                // COMMENTS also changes how the pattern is read (spaces and `#`); not converted.
                cursor += 1
                throw unsupported("příznak (?x) (COMMENTS) adaptér nepodporuje")
            case ch("U"): flags0 |= (Self.unicodeCharacterClass | Self.unicodeCase)
            case ch("-"):
                c = next()
                subFlag()
                return
            default:
                return
            }
            c = next()
        }
    }

    private mutating func subFlag() {
        var c = peek()
        while true {
            switch c {
            case ch("i"): flags0 &= ~Self.caseInsensitive
            case ch("m"): flags0 &= ~Self.multiline
            case ch("s"): flags0 &= ~Self.dotall
            case ch("d"): flags0 &= ~Self.unixLines
            case ch("u"): flags0 &= ~Self.unicodeCase
            case ch("c"): flags0 &= ~Self.canonEq
            case ch("x"): flags0 &= ~Self.comments
            case ch("U"): flags0 &= ~(Self.unicodeCharacterClass | Self.unicodeCase)
            default: return
            }
            c = next()
        }
    }

    /// Flags whose meaning the adapter does not express are rejected as soon as they are turned on.
    private func checkFlags() throws(JavaRegexError) {
        if has(Self.unicodeCharacterClass) {
            throw unsupported("příznak (?U) (UNICODE_CHARACTER_CLASS) adaptér nepodporuje")
        }
        if has(Self.unicodeCase) {
            throw unsupported("příznak (?u) (UNICODE_CASE) adaptér nepodporuje")
        }
        if has(Self.canonEq) {
            throw unsupported("příznak (?c) (CANON_EQ) adaptér nepodporuje")
        }
    }

    // MARK: - Quantifiers

    private mutating func closure(_ node: String, isGroup: Bool) throws(JavaRegexError) -> String {
        let c = peek()
        switch c {
        case ch("?"):
            return node + "?" + qtype()
        case ch("*"):
            try refuseQuantifiedGroupInLookbehind(isGroup)
            return node + "*" + qtype()
        case ch("+"):
            try refuseQuantifiedGroupInLookbehind(isGroup)
            return node + "+" + qtype()
        case ch("{"):
            var c = skip()
            guard Self.isAsciiDigit(c) else {
                throw error("Illegal repetition")
            }
            var cmin = 0
            var cmax = 0
            var unbounded = false
            // Java counts in `int` via `Math.multiplyExact/addExact`.
            repeat {
                cmin = cmin * 10 + Int(c - ch("0"))
                if cmin > Int(Int32.max) { throw error("Illegal repetition range") }
                c = read()
            } while Self.isAsciiDigit(c)
            if c == ch(",") {
                c = read()
                if c == ch("}") {
                    unbounded = true
                } else {
                    while Self.isAsciiDigit(c) {
                        cmax = cmax * 10 + Int(c - ch("0"))
                        if cmax > Int(Int32.max) { throw error("Illegal repetition range") }
                        c = read()
                    }
                }
            } else {
                cmax = cmin
            }
            if !unbounded {
                if c != ch("}") {
                    throw error("Unclosed counted closure")
                }
                if cmax < cmin {
                    throw error("Illegal repetition range")
                }
            }
            unread()
            if cmin > Self.icuMaxRepetition || (!unbounded && cmax > Self.icuMaxRepetition) {
                throw unsupported("počet opakování nad \(Self.icuMaxRepetition) ICU neumí")
            }
            if cmin == 0 && cmax == 1 && !unbounded {
                return node + "?" + qtype()
            }
            try refuseQuantifiedGroupInLookbehind(isGroup)
            let count = unbounded ? "{\(cmin),}" : (cmin == cmax ? "{\(cmin)}" : "{\(cmin),\(cmax)}")
            return node + count + qtype()
        default:
            return node
        }
    }

    /// Java `qtype()`: suffix `?` (lazy) or `+` (possessive).
    private mutating func qtype() -> String {
        let c = next()
        if c == ch("?") {
            _ = next()
            return "?"
        } else if c == ch("+") {
            _ = next()
            return "+"
        }
        return ""
    }

    /// A repeated group inside a look-behind: from it Java makes, according to a heuristic,
    /// `GroupCurly` (passes) or `Loop` (maximum-length error).
    /// The adapter does not port that analysis and therefore rejects such a group entirely.
    private func refuseQuantifiedGroupInLookbehind(_ isGroup: Bool) throws(JavaRegexError) {
        guard isGroup else { return }
        for frame in frames {
            if case .lookbehind = frame {
                throw unsupported("opakovaná skupina uvnitř look-behindu adaptér nepodporuje")
            }
        }
    }

    // MARK: - Escape sequences

    /// Java `escape()`: the character code (≥ 0), or −1 and a node in `root` / a set
    /// in `predicate`.
    private mutating func escape(inClass: Bool, create: Bool, isRange: Bool) throws(JavaRegexError) -> Int32 {
        let c = skip()
        switch c {
        case ch("0"):
            return try octal()
        case ch("1")...ch("9"):
            if inClass { break }
            if create { root = try ref(Int(c - ch("0"))) }
            return -1
        case ch("A"):
            if inClass { break }
            if create { root = Self.begin }
            return -1
        case ch("B"):
            if inClass { break }
            if create { root = Self.boundNone }
            return -1
        case ch("C"):
            break
        case ch("D"):
            if create { setPredicate(Self.asciiDigit.inverted, inClass) }
            return -1
        case ch("E"), ch("F"):
            break
        case ch("G"):
            if inClass { break }
            if create { throw unsupported("\\G (konec předchozí shody) adaptér nepodporuje") }
            return -1
        case ch("H"):
            if create { setPredicate(Self.horizontalSpace.inverted, inClass) }
            return -1
        case ch("I"), ch("J"), ch("K"), ch("L"), ch("M"):
            break
        case ch("N"):
            throw unsupported("\\N{…} (znak podle jména) adaptér nepodporuje")
        case ch("O"), ch("P"), ch("Q"):
            break
        case ch("R"):
            if inClass { break }
            if create { root = Self.lineEnding }
            return -1
        case ch("S"):
            if create { setPredicate(Self.asciiSpace.inverted, inClass) }
            return -1
        case ch("T"), ch("U"):
            break
        case ch("V"):
            if create { setPredicate(Self.verticalSpace.inverted, inClass) }
            return -1
        case ch("W"):
            if create { setPredicate(Self.asciiWord.inverted, inClass) }
            return -1
        case ch("X"):
            if inClass { break }
            if create { throw unsupported("\\X (grafémový cluster) adaptér nepodporuje") }
            return -1
        case ch("Y"):
            break
        case ch("Z"):
            if inClass { break }
            if create { root = Self.dollar(multiline: false, unixLines: has(Self.unixLines)) }
            return -1
        case ch("a"):
            return 0x07
        case ch("b"):
            if inClass { break }
            if create {
                if peek() == ch("{") {
                    if skip() == ch("g") {
                        if read() == ch("}") {
                            throw unsupported("\\b{g} (hranice grafému) adaptér nepodporuje")
                        }
                        break
                    }
                    unread()
                    unread()
                }
                root = Self.boundBoth
            }
            return -1
        case ch("c"):
            if cursor < patternLength {
                return read() ^ 64
            }
            throw error("Illegal control escape sequence")
        case ch("d"):
            if create { setPredicate(Self.asciiDigit, inClass) }
            return -1
        case ch("e"):
            return 0x1B
        case ch("f"):
            return 0x0C
        case ch("g"):
            break
        case ch("h"):
            if create { setPredicate(Self.horizontalSpace, inClass) }
            return -1
        case ch("i"), ch("j"):
            break
        case ch("k"):
            if inClass { break }
            if read() != ch("<") {
                throw error("\\k is not followed by '<' for named capturing group")
            }
            let name = try groupname(read())
            guard let number = namedGroups[name] else {
                throw error("named capturing group <\(name)> does not exist")
            }
            if create { root = try backref(number) }
            return -1
        case ch("l"), ch("m"):
            break
        case ch("n"):
            return 0x0A
        case ch("o"), ch("p"), ch("q"):
            break
        case ch("r"):
            return 0x0D
        case ch("s"):
            if create { setPredicate(Self.asciiSpace, inClass) }
            return -1
        case ch("t"):
            return 0x09
        case ch("u"):
            return try unicodeEscape()
        case ch("v"):
            if isRange { return 0x0B }
            if create { setPredicate(Self.verticalSpace, inClass) }
            return -1
        case ch("w"):
            if create { setPredicate(Self.asciiWord, inClass) }
            return -1
        case ch("x"):
            return try hexEscape()
        case ch("y"):
            break
        case ch("z"):
            if inClass { break }
            if create { root = "(?:\\z)" }
            return -1
        default:
            return c
        }
        throw error("Illegal/unsupported escape sequence")
    }

    private mutating func setPredicate(_ set: CodePointSet, _ inClass: Bool) {
        predicate = set
        if !inClass { root = Self.classText(set) }
    }

    /// Java `ref()`: the first digit is always a backreference, further ones only if
    /// such a group already exists at that moment.
    private mutating func ref(_ first: Int) throws(JavaRegexError) -> String {
        var refNum = first
        while true {
            let c = peek()
            guard c >= ch("0") && c <= ch("9") else { break }
            let newRefNum = refNum * 10 + Int(c - ch("0"))
            if capturingGroupCount - 1 < newRefNum { break }
            refNum = newRefNum
            _ = read()
        }
        return try backref(refNum)
    }

    private mutating func backref(_ number: Int) throws(JavaRegexError) -> String {
        if has(Self.caseInsensitive) {
            throw unsupported("zpětný odkaz pod (?i) adaptér nepodporuje")
        }
        // The nearest lookaround determines whether the reference lies directly in a look-behind.
        if let index = frames.lastIndex(where: {
            if case .other = $0 { return false }
            return true
        }), case .lookbehind = frames[index] {
            frames[index] = .lookbehind(hasBackref: true)
        }
        return "(?:" + Self.backrefMarker(number) + ")"
    }

    private mutating func octal() throws(JavaRegexError) -> Int32 {
        let n = read()
        if n >= ch("0") && n <= ch("7") {
            let m = read()
            if m >= ch("0") && m <= ch("7") {
                let o = read()
                if o >= ch("0") && o <= ch("7") && n <= ch("3") {
                    return (n - ch("0")) * 64 + (m - ch("0")) * 8 + (o - ch("0"))
                }
                unread()
                return (n - ch("0")) * 8 + (m - ch("0"))
            }
            unread()
            return n - ch("0")
        }
        throw error("Illegal octal escape sequence")
    }

    private mutating func hexEscape() throws(JavaRegexError) -> Int32 {
        var n = read()
        if Self.isHexDigit(n) {
            let m = read()
            if Self.isHexDigit(m) {
                return Self.hexValue(n) * 16 + Self.hexValue(m)
            }
        } else if n == ch("{") && Self.isHexDigit(peek()) {
            var value: Int32 = 0
            n = read()
            while Self.isHexDigit(n) {
                value = (value << 4) + Self.hexValue(n)
                if value > 0x10FFFF {
                    throw error("Hexadecimal codepoint is too big")
                }
                n = read()
            }
            if n != ch("}") {
                throw error("Unclosed hexadecimal escape sequence")
            }
            return value
        }
        throw error("Illegal hexadecimal escape sequence")
    }

    private mutating func uxxxx() throws(JavaRegexError) -> Int32 {
        var n: Int32 = 0
        for _ in 0..<4 {
            let c = read()
            if !Self.isHexDigit(c) {
                throw error("Illegal Unicode escape sequence")
            }
            n = n * 16 + Self.hexValue(c)
        }
        return n
    }

    private mutating func unicodeEscape() throws(JavaRegexError) -> Int32 {
        let n = try uxxxx()
        if n >= 0xD800 && n <= 0xDBFF {
            let saved = cursor
            if read() == ch("\\") && read() == ch("u") {
                let n2 = try uxxxx()
                if n2 >= 0xDC00 && n2 <= 0xDFFF {
                    return 0x10000 + ((n - 0xD800) << 10) + (n2 - 0xDC00)
                }
            }
            cursor = saved
        }
        return n
    }

    // MARK: - Character classes

    /// Java `BitClass`: shared and mutable — Java's `prev.union(bits)` holds
    /// a reference, so a later addition to `bits` is reflected back in `prev`.
    private final class Bits {
        var set = CodePointSet.empty
    }

    /// One operand of Java's `CharPredicate`: a finished set, or shared
    /// `bits` that may still be added to.
    private enum Leaf {
        case set(CodePointSet)
        case bits(Bits)

        var value: CodePointSet {
            switch self {
            case .set(let s): return s
            case .bits(let b): return b.set
            }
        }
    }

    /// Java `CharPredicate` (`prev.union(x)`, `prev.and(x)`); evaluated only
    /// at the end of `clazz`, when `bits` no longer changes.
    ///
    /// Java always composes the predicate from the **left** (`prev = prev.union(curr)`)
    /// and the right operand is a single node, so a flat list of operations suffices instead of
    /// a tree. A tree of `indirect enum` had depth equal to the number of class items
    /// and its recursive evaluation (and deallocation) overflowed the stack at around
    /// 1,750 ranges (`[a-bc-d…]`, debug build, 512 KB).
    private struct Pred {
        var head: Leaf
        var tail: [(isAnd: Bool, leaf: Leaf)] = []

        init(_ leaf: Leaf) {
            head = leaf
        }

        /// `prev = prev.union(leaf)` in place.
        mutating func union(_ leaf: Leaf) {
            tail.append((false, leaf))
        }

        /// `prev = prev.and(leaf)` in place.
        mutating func and(_ leaf: Leaf) {
            tail.append((true, leaf))
        }

        func evaluate() -> CodePointSet {
            var result = head.value
            for (isAnd, leaf) in tail {
                result = isAnd ? result.intersection(leaf.value) : result.union(leaf.value)
            }
            return result
        }
    }

    private mutating func clazz(consume: Bool) throws(JavaRegexError) -> CodePointSet {
        try enterNesting(at: cursor)
        defer { nesting -= 1 }
        var prev: Pred?
        var curr: Leaf?
        let bits = Bits()
        var isNeg = false
        var hasBits = false
        var c = next()
        if c == ch("^") && at(cursor - 1) == ch("[") {
            c = next()
            isNeg = true
        }
        while true {
            switch c {
            case ch("["):
                let nested = Leaf.set(try clazz(consume: true))
                curr = nested
                if prev == nil { prev = Pred(nested) } else { prev!.union(nested) }
                c = peek()
                continue
            case ch("&"):
                c = next()
                if c == ch("&") {
                    c = next()
                    // The right side of `&&` is only finished sets, so they are
                    // united immediately (Java's `union` tree would give the same).
                    var right: CodePointSet?
                    while c != ch("]") && c != ch("&") {
                        let part: CodePointSet
                        if c == ch("[") {
                            part = try clazz(consume: true)
                        } else {
                            unread()
                            part = try clazz(consume: false)
                        }
                        right = right.map { $0.union(part) } ?? part
                        c = peek()
                    }
                    if hasBits {
                        if prev == nil {
                            prev = Pred(.bits(bits))
                            curr = .bits(bits)
                        } else {
                            prev!.union(.bits(bits))
                        }
                        hasBits = false
                    }
                    if let right {
                        curr = .set(right)
                    }
                    if prev == nil {
                        guard let right else { throw error("Bad class syntax") }
                        prev = Pred(.set(right))
                    } else {
                        guard let curr else { throw error("Bad intersection syntax") }
                        prev!.and(curr)
                    }
                    continue
                }
                unread()
            case 0:
                if cursor >= patternLength {
                    throw error("Unclosed character class")
                }
            case ch("]"):
                if prev != nil || hasBits {
                    if consume { _ = next() }
                    if prev == nil {
                        prev = Pred(.bits(bits))
                    } else if hasBits {
                        prev!.union(.bits(bits))
                    }
                    let result = prev!.evaluate()
                    return isNeg ? result.inverted : result
                }
            default:
                break
            }
            curr = try range(bits)
            if let got = curr {
                if prev == nil { prev = Pred(got) } else { prev!.union(got) }
            } else {
                hasBits = true
            }
            c = peek()
        }
    }

    /// Java `range()`: a single character (into `bits`, returns `nil`), a range, an escape
    /// or a property.
    private mutating func range(_ bits: Bits) throws(JavaRegexError) -> Leaf? {
        var c = peek()
        if c == ch("\\") {
            c = nextEscaped()
            if c == ch("p") || c == ch("P") {
                let complement = c == ch("P")
                var oneLetter = true
                c = next()
                if c != ch("{") {
                    unread()
                } else {
                    oneLetter = false
                }
                return .set(try family(singleLetter: oneLetter, complement: complement))
            } else {
                let isRange = at(cursor + 1) == ch("-")
                unread()
                c = try escape(inClass: true, create: true, isRange: isRange)
                if c == -1 {
                    return .set(predicate)
                }
            }
        } else {
            _ = next()
        }
        if c >= 0 {
            if peek() == ch("-") {
                let endRange = at(cursor + 1)
                if endRange == ch("[") {
                    return bitsOrSingle(bits, c)
                }
                if endRange != ch("]") {
                    _ = next()
                    var m = peek()
                    if m == ch("\\") {
                        m = try escape(inClass: true, create: false, isRange: true)
                    } else {
                        _ = next()
                    }
                    if m < c {
                        throw error("Illegal character range")
                    }
                    let plain = CodePointSet(UInt32(c)...UInt32(m))
                    return .set(has(Self.caseInsensitive) ? Self.asciiCaseClosure(plain) : plain)
                }
            }
            return bitsOrSingle(bits, c)
        }
        throw error("Unexpected character '\(Self.scalarText(c))'")
    }

    /// Java `bitsOrSingle` (without `UNICODE_CASE`, which is rejected): a character below 256
    /// goes into `bits` together with its ASCII case counterpart, otherwise a separate predicate.
    private func bitsOrSingle(_ bits: Bits, _ c: Int32) -> Leaf? {
        if c < 256 {
            bits.set = bits.set.union(single(c))
            return nil
        }
        return .set(single(c))
    }

    /// Java `single()` without `UNICODE_CASE`: under `(?i)` an ASCII letter takes
    /// its other case as well, everything else only itself.
    private func single(_ c: Int32) -> CodePointSet {
        let set = CodePointSet(UInt32(c)...UInt32(c))
        return has(Self.caseInsensitive) ? Self.asciiCaseClosure(set) : set
    }

    // MARK: - Properties \p{…}

    private mutating func family(singleLetter: Bool, complement: Bool) throws(JavaRegexError) -> CodePointSet {
        _ = next()
        var name: String
        if singleLetter {
            name = Self.scalarText(at(cursor))
            _ = read()
        } else {
            let start = cursor
            mark(ch("}"))
            while read() != ch("}") {}
            mark(0)
            let end = cursor
            if end > patternLength {
                throw error("Unclosed character family")
            }
            if start + 1 >= end {
                throw error("Empty character family")
            }
            name = temp[start..<(end - 1)].map(Self.scalarText).joined()
        }
        var result: CodePointSet
        if let eq = name.firstIndex(of: "=") {
            let value = String(name[name.index(after: eq)...])
            let key = name[..<eq].lowercased()
            switch key {
            case "sc", "script", "blk", "block":
                throw unsupported("vlastnost \\p{\(name)} (písmo nebo blok Unicode) adaptér nepodporuje")
            case "gc", "general_category":
                switch Self.forProperty(value, caseInsensitive: has(Self.caseInsensitive)) {
                case .set(let s): result = s
                case .javaMethod:
                    throw unsupported("vlastnost \\p{\(name)} (metoda Character.*) adaptér nepodporuje")
                case .unknown:
                    throw error("Unknown Unicode property {name=<\(key)>, value=<\(value)>}")
                }
            default:
                throw error("Unknown Unicode property {name=<\(key)>, value=<\(value)>}")
            }
        } else if name.hasPrefix("In") {
            throw unsupported("vlastnost \\p{\(name)} (blok Unicode) adaptér nepodporuje")
        } else if name.hasPrefix("Is") {
            let short = String(name.dropFirst(2))
            if Self.unicodeAndPosixNames.contains(short.uppercased()) {
                throw unsupported("vlastnost \\p{\(name)} (binární vlastnost Unicode) adaptér nepodporuje")
            }
            switch Self.forProperty(short, caseInsensitive: has(Self.caseInsensitive)) {
            case .set(let s): result = s
            case .javaMethod:
                throw unsupported("vlastnost \\p{\(name)} (metoda Character.*) adaptér nepodporuje")
            case .unknown:
                // Java would try the script name; the adapter has no script table.
                throw unsupported("vlastnost \\p{\(name)} (písmo Unicode, nebo neznámé jméno) adaptér nepodporuje")
            }
        } else {
            switch Self.forProperty(name, caseInsensitive: has(Self.caseInsensitive)) {
            case .set(let s): result = s
            case .javaMethod:
                throw unsupported("vlastnost \\p{\(name)} (metoda Character.*) adaptér nepodporuje")
            case .unknown:
                throw error("Unknown character property name {\(name)}")
            }
        }
        if complement {
            result = result.inverted
        }
        return result
    }

    private enum PropertyLookup {
        case set(CodePointSet)
        case javaMethod
        case unknown
    }

    /// Names from `CharPredicates.getUnicodePredicate` and `getPosixPredicate`
    /// (uppercase). With the `Is` prefix they take precedence over categories.
    private static let unicodeAndPosixNames: Set<String> = [
        "ALPHABETIC", "ASSIGNED", "CONTROL", "EMOJI", "EMOJI_PRESENTATION", "EMOJI_MODIFIER",
        "EMOJI_MODIFIER_BASE", "EMOJI_COMPONENT", "EXTENDED_PICTOGRAPHIC", "HEXDIGIT", "HEX_DIGIT",
        "IDEOGRAPHIC", "JOINCONTROL", "JOIN_CONTROL", "LETTER", "LOWERCASE", "NONCHARACTERCODEPOINT",
        "NONCHARACTER_CODE_POINT", "TITLECASE", "PUNCTUATION", "UPPERCASE", "WHITESPACE", "WHITE_SPACE",
        "WORD", "ALPHA", "LOWER", "UPPER", "SPACE", "PUNCT", "XDIGIT", "ALNUM", "CNTRL", "DIGIT",
        "BLANK", "GRAPH", "PRINT",
    ]

    /// Java `CharPredicates.forProperty(name, caseIns)`.
    private static func forProperty(_ name: String, caseInsensitive ci: Bool) -> PropertyLookup {
        let cased: [Unicode.GeneralCategory] = [.uppercaseLetter, .lowercaseLetter, .titlecaseLetter]
        func cat(_ categories: [Unicode.GeneralCategory]) -> PropertyLookup {
            .set(UnicodeTables.categories(categories))
        }
        switch name {
        case "Cn": return cat([.unassigned])
        case "Lu": return cat(ci ? cased : [.uppercaseLetter])
        case "Ll": return cat(ci ? cased : [.lowercaseLetter])
        case "Lt": return cat(ci ? cased : [.titlecaseLetter])
        case "Lm": return cat([.modifierLetter])
        case "Lo": return cat([.otherLetter])
        case "Mn": return cat([.nonspacingMark])
        case "Me": return cat([.enclosingMark])
        case "Mc": return cat([.spacingMark])
        case "Nd": return cat([.decimalNumber])
        case "Nl": return cat([.letterNumber])
        case "No": return cat([.otherNumber])
        case "Zs": return cat([.spaceSeparator])
        case "Zl": return cat([.lineSeparator])
        case "Zp": return cat([.paragraphSeparator])
        case "Cc": return cat([.control])
        case "Cf": return cat([.format])
        case "Co": return cat([.privateUse])
        case "Cs": return cat([.surrogate])
        case "Pd": return cat([.dashPunctuation])
        case "Ps": return cat([.openPunctuation])
        case "Pe": return cat([.closePunctuation])
        case "Pc": return cat([.connectorPunctuation])
        case "Po": return cat([.otherPunctuation])
        case "Sm": return cat([.mathSymbol])
        case "Sc": return cat([.currencySymbol])
        case "Sk": return cat([.modifierSymbol])
        case "So": return cat([.otherSymbol])
        case "Pi": return cat([.initialPunctuation])
        case "Pf": return cat([.finalPunctuation])
        case "L": return cat(cased + [.modifierLetter, .otherLetter])
        case "M": return cat([.nonspacingMark, .enclosingMark, .spacingMark])
        case "N": return cat([.decimalNumber, .letterNumber, .otherNumber])
        case "Z": return cat([.spaceSeparator, .lineSeparator, .paragraphSeparator])
        case "C": return cat([.control, .format, .privateUse, .surrogate, .unassigned])
        case "P": return cat([.dashPunctuation, .openPunctuation, .closePunctuation, .connectorPunctuation,
                              .otherPunctuation, .initialPunctuation, .finalPunctuation])
        case "S": return cat([.mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol])
        case "LC": return cat(cased)
        case "LD": return cat(cased + [.modifierLetter, .otherLetter, .decimalNumber])
        case "L1": return .set(CodePointSet(0...0xFF))
        case "all": return .set(.all)
        case "ASCII": return .set(CodePointSet(0...0x7F))
        case "Alnum": return .set(asciiAlnum)
        case "Alpha": return .set(asciiAlpha)
        case "Blank": return .set(CodePointSet([0x09...0x09, 0x20...0x20]))
        case "Cntrl": return .set(CodePointSet([0...0x1F, 0x7F...0x7F]))
        case "Digit": return .set(asciiDigit)
        case "Graph": return .set(CodePointSet(0x21...0x7E))
        case "Lower": return .set(ci ? asciiAlpha : CodePointSet(0x61...0x7A))
        case "Print": return .set(CodePointSet(0x20...0x7E))
        case "Punct": return .set(CodePointSet([0x21...0x2F, 0x3A...0x40, 0x5B...0x60, 0x7B...0x7E]))
        case "Space": return .set(asciiSpace)
        case "Upper": return .set(ci ? asciiAlpha : CodePointSet(0x41...0x5A))
        case "XDigit": return .set(CodePointSet([0x30...0x39, 0x41...0x46, 0x61...0x66]))
        case "javaLowerCase", "javaUpperCase", "javaAlphabetic", "javaIdeographic", "javaTitleCase",
             "javaDigit", "javaDefined", "javaLetter", "javaLetterOrDigit", "javaJavaIdentifierStart",
             "javaJavaIdentifierPart", "javaUnicodeIdentifierStart", "javaUnicodeIdentifierPart",
             "javaIdentifierIgnorable", "javaSpaceChar", "javaWhitespace", "javaISOControl", "javaMirrored":
            return .javaMethod
        default:
            return .unknown
        }
    }

    // MARK: - Fixed sets and anchors

    static let asciiDigit = CodePointSet(0x30...0x39)
    static let asciiAlpha = CodePointSet([0x41...0x5A, 0x61...0x7A])
    static let asciiAlnum = CodePointSet([0x30...0x39, 0x41...0x5A, 0x61...0x7A])
    static let asciiWord = CodePointSet([0x30...0x39, 0x41...0x5A, 0x5F...0x5F, 0x61...0x7A])
    static let asciiSpace = CodePointSet([0x09...0x0D, 0x20...0x20])
    static let horizontalSpace = CodePointSet([
        0x09...0x09, 0x20...0x20, 0xA0...0xA0, 0x1680...0x1680, 0x180E...0x180E,
        0x2000...0x200A, 0x202F...0x202F, 0x205F...0x205F, 0x3000...0x3000,
    ])
    static let verticalSpace = CodePointSet([0x0A...0x0D, 0x85...0x85, 0x2028...0x2029])
    /// Java `.` without `(?s)`: everything except `\n \r \u0085    `.
    static let dotSet = CodePointSet([0x0A...0x0A, 0x0D...0x0D, 0x85...0x85, 0x2028...0x2029]).inverted
    /// Java `.` under `(?d)`: everything except `\n`.
    static let unixDotSet = CodePointSet(0x0A...0x0A).inverted

    /// Java `Begin` (`^` without `(?m)` and `\A`).
    static let begin = "(?:\\A)"
    /// Java `Caret` (`(?m)^`): not at the end of input, otherwise at the start or after
    /// a line terminator — but not between `\r` and `\n`.
    static let caret = "(?:(?!\\z)(?:\\A|(?<=[\\x{A}\\x{85}\\x{2028}\\x{2029}])|(?<=\\x{D})(?!\\x{A})))"
    /// Java `UnixCaret` (`(?md)^`).
    static let unixCaret = "(?:(?!\\z)(?:\\A|(?<=\\x{A})))"

    /// Java `Dollar` and `UnixDollar`.
    static func dollar(multiline: Bool, unixLines: Bool) -> String {
        switch (multiline, unixLines) {
        case (false, false):
            return "(?:\\z|(?=\\x{D}\\x{A}\\z)|(?=[\\x{D}\\x{85}\\x{2028}\\x{2029}]\\z)|(?<!\\x{D})(?=\\x{A}\\z))"
        case (true, false):
            return "(?:\\z|(?=[\\x{D}\\x{85}\\x{2028}\\x{2029}])|(?<!\\x{D})(?=\\x{A}))"
        case (false, true):
            return "(?:\\z|(?=\\x{A}\\z))"
        case (true, true):
            return "(?:\\z|(?=\\x{A}))"
        }
    }

    /// Java `\R` (`LineEnding`) — including backtracking from `\r\n` to a bare `\r`.
    static let lineEnding = "(?:\\x{D}\\x{A}|[\\x{A}-\\x{D}\\x{85}\\x{2028}\\x{2029}])"

    /// Java `Bound` without `UNICODE_CHARACTER_CLASS`. A word character is ASCII `\w`,
    /// **or** a nonspacing mark (`Mn`) preceded (across further `Mn`) by a letter
    /// or digit per `Character.isLetterOrDigit`. Java looks for that base by
    /// UTF-16 units, so a non-BMP character (a surrogate pair) can be neither base
    /// nor an intermediate mark — except a mark directly to the right of the position.
    private static let boundParts: (left: String, notLeft: String, right: String, notRight: String) = {
        let word = classText(asciiWord)
        let bmp = CodePointSet(0...0xFFFF)
        let base = classText(UnicodeTables.categories([
            .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber,
        ]).intersection(bmp))
        let marks = UnicodeTables.categories([.nonspacingMark])
        let bmpMarks = classText(marks.intersection(bmp))
        let anyMark = classText(marks)
        let run = boundMarkRun
        let left = "(?:(?<=\(word))|(?<=\(base)\(bmpMarks){1,\(run)}))"
        let notLeft = "(?<!\(word))(?<!\(base)\(bmpMarks){1,\(run)})"
        let right = "(?:(?=\(word))|(?=\(anyMark))(?<=\(base)\(bmpMarks){0,\(run)}))"
        let notRight = "(?!\(word))(?:(?!\(anyMark))|(?<!\(base)\(bmpMarks){0,\(run)}))"
        return (left, notLeft, right, notRight)
    }()

    /// `\b`: wordness on the left and right differ. Computed once (the text has
    /// tens of kB), not at every `\b` in the translated pattern.
    static let boundBoth: String = {
        let p = boundParts
        return "(?:\(p.left)\(p.notRight)|\(p.notLeft)\(p.right))"
    }()

    /// `\B`: wordness on the left and right is the same. Computed once, like `boundBoth`.
    static let boundNone: String = {
        let p = boundParts
        return "(?:\(p.left)\(p.right)|\(p.notLeft)\(p.notRight))"
    }()

    // MARK: - Backreferences

    /// Backreference marker in the text under construction; the group count is known only
    /// at the end (a reference may also point to a group defined later).
    private static func backrefMarker(_ number: Int) -> String {
        "\u{E000}\(number)\u{E001}"
    }

    /// Java translates a reference to a nonexistent group and never satisfies it; ICU would
    /// reject it, so it becomes `(?!)`.
    private static func resolveBackrefs(_ text: String, groupCount: Int) -> String {
        guard text.contains("\u{E000}") else { return text }
        var out = ""
        var scalars = text.unicodeScalars.makeIterator()
        while let s = scalars.next() {
            guard s == "\u{E000}" else {
                out.unicodeScalars.append(s)
                continue
            }
            var digits = ""
            while let d = scalars.next(), d != "\u{E001}" {
                digits.unicodeScalars.append(d)
            }
            let number = Int(digits) ?? 0
            out += number >= 1 && number <= groupCount ? "\\\(number)" : "(?!)"
        }
        return out
    }

    // MARK: - Output and character helpers

    /// A set as an ICU class. An empty set is a class that matches nothing
    /// (it can be quantified just like in Java).
    static func classText(_ set: CodePointSet) -> String {
        if set.isEmpty {
            return "[^\\x{0}-\\x{10FFFF}]"
        }
        var out = "["
        for r in set.ranges {
            out += "\\x{" + String(r.lowerBound, radix: 16) + "}"
            if r.upperBound != r.lowerBound {
                out += "-\\x{" + String(r.upperBound, radix: 16) + "}"
            }
        }
        return out + "]"
    }

    /// A single character as a literal (`\x{…}`, ASCII alphanumerics directly), or a class.
    private static func classOrLiteral(_ set: CodePointSet) -> String {
        if set.ranges.count == 1, let r = set.ranges.first, r.lowerBound == r.upperBound {
            let v = r.lowerBound
            if (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) {
                return String(Unicode.Scalar(UInt8(v)))
            }
            return "\\x{" + String(v, radix: 16) + "}"
        }
        return classText(set)
    }

    /// Java `CIRange`/`BitClass.add` under `(?i)` without `(?u)`: adds ASCII characters
    /// whose ASCII case counterpart is in the set.
    static func asciiCaseClosure(_ set: CodePointSet) -> CodePointSet {
        var extra: [ClosedRange<UInt32>] = []
        for c in UInt32(0x41)...0x5A where set.contains(c + 0x20) && !set.contains(c) {
            extra.append(c...c)
        }
        for c in UInt32(0x61)...0x7A where set.contains(c - 0x20) && !set.contains(c) {
            extra.append(c...c)
        }
        return extra.isEmpty ? set : set.union(CodePointSet(extra))
    }

    private static func isAscii(_ c: Int32) -> Bool { c >= 0 && c < 0x80 }
    private static func isAsciiDigit(_ c: Int32) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isAsciiAlpha(_ c: Int32) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
    private static func isHexDigit(_ c: Int32) -> Bool {
        isAsciiDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }
    private static func hexValue(_ c: Int32) -> Int32 {
        if isAsciiDigit(c) { return c - 0x30 }
        if c >= 0x61 { return c - 0x61 + 10 }
        return c - 0x41 + 10
    }

    /// Pattern character as text (a lone half of a surrogate pair → U+FFFD).
    private static func scalarText(_ c: Int32) -> String {
        guard c >= 0, let scalar = Unicode.Scalar(UInt32(c)) else { return "\u{FFFD}" }
        return String(Character(scalar))
    }
}

/// Set of code points as sorted, disjoint, non-adjacent intervals.
struct CodePointSet: Equatable, Sendable {
    private(set) var ranges: [ClosedRange<UInt32>]

    static let empty = CodePointSet(ranges: [])
    static let all = CodePointSet(ranges: [0...0x10FFFF])

    private init(ranges: [ClosedRange<UInt32>]) {
        self.ranges = ranges
    }

    init(_ range: ClosedRange<UInt32>) {
        self.ranges = [range]
    }

    /// Any intervals; sorts them and merges overlaps and neighbors.
    init(_ input: [ClosedRange<UInt32>]) {
        let sorted = input.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<UInt32>] = []
        for r in sorted {
            if let last = merged.last, r.lowerBound <= last.upperBound &+ 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        self.ranges = merged
    }

    var isEmpty: Bool { ranges.isEmpty }

    func contains(_ value: UInt32) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if ranges[mid].upperBound < value {
                low = mid + 1
            } else if ranges[mid].lowerBound > value {
                high = mid - 1
            } else {
                return true
            }
        }
        return false
    }

    func union(_ other: CodePointSet) -> CodePointSet {
        CodePointSet(ranges + other.ranges)
    }

    /// Complement in the range 0…U+10FFFF.
    var inverted: CodePointSet {
        var out: [ClosedRange<UInt32>] = []
        var start: UInt32 = 0
        for r in ranges {
            if r.lowerBound > start {
                out.append(start...(r.lowerBound - 1))
            }
            start = r.upperBound + 1
        }
        if start <= 0x10FFFF {
            out.append(start...0x10FFFF)
        }
        return CodePointSet(ranges: out)
    }

    func intersection(_ other: CodePointSet) -> CodePointSet {
        inverted.union(other.inverted).inverted
    }
}

/// Unicode general categories as seen by **JDK 21 (Unicode 15.0)**.
///
/// Swift's library carries a newer Unicode (measured: 10,615 points added after
/// 15.0). Points with an `age` newer than 15.0 are therefore treated as unassigned
/// (`Cn`), as Java sees them. After this masking categories differ only
/// for two points whose category the newer Unicode **changed** (measured with the probe
/// `ProbeTypes.java` over all 1,114,112 code points) — these are corrected
/// manually in `javaOverrides`.
enum UnicodeTables {

    /// Points where `Character.getType` from JDK 21 differs from Swift's category
    /// even after masking the newer points.
    private static let javaOverrides: [UInt32: Unicode.GeneralCategory] = [
        0x0295: .lowercaseLetter,   // ʕ: Java `Ll`, newer Unicode `Lo`
        0x1171E: .nonspacingMark,   // Java `Mn`, newer Unicode `Mc`
    ]

    private static let table: [Unicode.GeneralCategory: CodePointSet] = {
        var buckets: [Unicode.GeneralCategory: [ClosedRange<UInt32>]] = [:]
        var currentCategory: Unicode.GeneralCategory?
        var runStart: UInt32 = 0
        func flush(_ end: UInt32) {
            if let category = currentCategory {
                buckets[category, default: []].append(runStart...end)
            }
        }
        for value in UInt32(0)...0x10FFFF {
            let category: Unicode.GeneralCategory
            if let override = javaOverrides[value] {
                category = override
            } else if let scalar = Unicode.Scalar(value) {
                if let age = scalar.properties.age, age.major > 15 || (age.major == 15 && age.minor > 0) {
                    category = .unassigned
                } else {
                    category = scalar.properties.generalCategory
                }
            } else {
                category = .surrogate
            }
            if category != currentCategory {
                if value > 0 { flush(value - 1) }
                currentCategory = category
                runStart = value
            }
        }
        flush(0x10FFFF)
        return buckets.mapValues { CodePointSet($0) }
    }()

    /// Union of categories.
    static func categories(_ list: [Unicode.GeneralCategory]) -> CodePointSet {
        list.reduce(CodePointSet.empty) { $0.union(table[$1] ?? .empty) }
    }
}
