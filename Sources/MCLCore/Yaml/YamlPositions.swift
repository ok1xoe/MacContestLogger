import Foundation

// MARK: - Path to a node

/// Path from the document root to a node: mapping keys and sequence indices.
///
/// Serves as the key into `YamlPositions` — the `YamlValue` tree does not carry
/// positions (and must not: they would break tree equality in the gate against Java),
/// so they are reached via a path. A literal is convenient to write:
/// `["meta", "name"]`, `["bands", 0]`.
public struct YamlPath: Hashable, Sendable, CustomStringConvertible, ExpressibleByArrayLiteral {

    public enum Component: Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
        /// The value of a mapping key — for a duplicate key the **last** one that
        /// remained in the mapping (Jackson and `YamlMapping` both let the last one win).
        case key(String)
        /// A sequence item, zero-based.
        case index(Int)
        /// An **earlier** occurrence of a duplicate key that a later occurrence overwrote;
        /// `occurrence` is the index among the overwritten occurrences (0 = first in the document).
        ///
        /// The value is no longer in the tree, but when mapping to a record Java
        /// **still reads it** (streaming, before it sees the later occurrence), so
        /// a type error in it fails the whole load (measured: `i: x` + `i: 1` -> error
        /// 1:4). The value is held by `YamlDocument.shadowedValues(of:)`; the positions of its
        /// subtree live under this component.
        case shadowedKey(String, occurrence: Int)

        public init(stringLiteral value: String) { self = .key(value) }
        public init(integerLiteral value: Int) { self = .index(value) }
    }

    public private(set) var components: [Component]

    public init(_ components: [Component] = []) { self.components = components }

    public init(arrayLiteral elements: Component...) { self.components = elements }

    /// Document root.
    public static let root = YamlPath()

    public func appending(_ component: Component) -> YamlPath {
        YamlPath(components + [component])
    }

    public func appending(key: String) -> YamlPath { appending(.key(key)) }

    public func appending(index: Int) -> YamlPath { appending(.index(index)) }

    /// Parent path; the root is its own parent.
    public var parent: YamlPath { YamlPath(Array(components.dropLast())) }

    public var isRoot: Bool { components.isEmpty }

    /// Does this path start with the path `prefix` (including equality)?
    public func hasPrefix(_ prefix: YamlPath) -> Bool {
        components.count >= prefix.components.count
            && Array(components.prefix(prefix.components.count)) == prefix.components
    }

    /// Notation in JSON Pointer form (`/meta/name`, `/bands/0`, root `/`), as
    /// Jackson prints it; an overwritten occurrence is `/i#0`.
    public var description: String {
        guard !components.isEmpty else { return "/" }
        return components.map { component -> String in
            switch component {
            case .key(let key): return "/" + key
            case .index(let index): return "/\(index)"
            case .shadowedKey(let key, let occurrence): return "/\(key)#\(occurrence)"
            }
        }.joined()
    }
}

// MARK: - Position

/// Position in the document text — line and column, 1-based.
///
/// **The column is counted in Unicode code points**, because that is how
/// SnakeYAML counts it (`Mark.column`), and hence Jackson (measured: `{name: "😀", n: x}`
/// reports `x` at column 20, `"e\u{301}"` takes four columns). Not in graphemes
/// (Swift `Character`) and not in UTF-16 units.
public struct YamlPosition: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let line: Int
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static func < (lhs: YamlPosition, rhs: YamlPosition) -> Bool {
        (lhs.line, lhs.column) < (rhs.line, rhs.column)
    }

    public var description: String { "\(line):\(column)" }
}

/// Positions of the document nodes, as the parser collected them while building the tree.
///
/// Two positions per node, both as reported by Jackson:
/// - **start** (`position(of:)`) = `JsonParser.currentTokenLocation()`, i.e. the
///   start of the SnakeYAML event. For a scalar it is its first character, for a flow
///   collection `{`/`[`, for a block mapping the first key, for a block sequence the first `-`.
///   If the node has a tag or anchor, it starts at **that** (`a: !!int 42` -> column 4,
///   `c: !!map` + indented mapping -> the tag's column). Almost all type errors
///   point at the start.
/// - **end** (`endPosition(of:)`) = `JsonParser.currentLocation()`, i.e. the
///   position right after the last character of a scalar (after the closing quote). Jackson
///   points at the end for numbers outside the `int` range (`i: 99999999999` -> 1:15).
///   The parser records it for plain and quoted scalars, i.e. all those that
///   can be a number; for block scalars and collections it is `nil`.
///
/// A `null` node from an omitted value (`a:` with nothing) has no position — `null`
/// never causes a type error.
public struct YamlPositions: Sendable {

    struct Span: Sendable {
        var start: YamlPosition
        var end: YamlPosition?
    }

    var spans: [YamlPath: Span] = [:]

    /// Position after the last character of the input. Jackson reports an empty input there
    /// ("No content to map due to end-of-input": `""` -> 1:1, `# c\n` -> 2:1).
    public internal(set) var endOfInput = YamlPosition(line: 1, column: 1)

    public init() {}

    /// Start of the value token at `path` (1-based), or `nil` when there is no
    /// node there (or it is an omitted value).
    public func position(of path: YamlPath) -> (line: Int, column: Int)? {
        spans[path].map { ($0.start.line, $0.start.column) }
    }

    /// Position right after the end of the scalar at `path` (1-based), or `nil`.
    public func endPosition(of path: YamlPath) -> (line: Int, column: Int)? {
        spans[path]?.end.map { ($0.line, $0.column) }
    }

    /// All recorded paths — for tests and debugging.
    public var paths: [YamlPath] { Array(spans.keys) }

    func start(_ path: YamlPath) -> YamlPosition? { spans[path]?.start }

    func end(_ path: YamlPath) -> YamlPosition? { spans[path]?.end }

    /// Records the start if the node does not have one yet. The outer token wins: a tag
    /// or anchor is recorded before the value that follows it.
    mutating func recordStart(_ path: YamlPath, _ position: YamlPosition) {
        if spans[path] == nil { spans[path] = Span(start: position, end: nil) }
    }

    /// Records the end if the node does not have one yet.
    mutating func recordEnd(_ path: YamlPath, _ position: YamlPosition) {
        guard var span = spans[path], span.end == nil else { return }
        span.end = position
        spans[path] = span
    }

    /// Renames the subtree `from` (inclusive) to `to` — when a duplicate key is overwritten,
    /// the positions of the previous value move under `.shadowedKey`.
    mutating func move(_ from: YamlPath, to: YamlPath) {
        let moved = spans.filter { $0.key.hasPrefix(from) }
        for (path, span) in moved {
            spans[path] = nil
            spans[YamlPath(to.components + path.components.dropFirst(from.components.count))] = span
        }
    }
}

// MARK: - Document

/// Result of `YamlParser.parseDocument(_:)`: the value tree and, alongside it, positions.
public struct YamlDocument: Sendable {

    /// The value tree — **the same** as from `YamlParser.parse(_:)`.
    public let root: YamlValue

    public let positions: YamlPositions

    /// Does the input contain no document? True for empty text and text made only
    /// of blank lines and comments. `---` or `~` **are** documents (with a `null`
    /// root) — Java distinguishes them: empty input is an error ("No content to map
    /// due to end-of-input"), whereas `---` and `~` return `null` from `readValue`.
    public let isEmptyStream: Bool

    /// Overwritten occurrences of duplicate keys: path of the **winning** key -> earlier
    /// values in document order.
    let shadowed: [YamlPath: [YamlValue]]

    init(root: YamlValue, positions: YamlPositions, isEmptyStream: Bool,
         shadowed: [YamlPath: [YamlValue]]) {
        self.root = root
        self.positions = positions
        self.isEmptyStream = isEmptyStream
        self.shadowed = shadowed
    }

    /// Earlier occurrences of the key at `path` (the path ends with `.key`) that a
    /// later occurrence of the same key in the same mapping overwrote; in document order. Occurrence
    /// number `n` has positions under `path.parent.appending(.shadowedKey(key, occurrence: n))`.
    public func shadowedValues(of path: YamlPath) -> [YamlValue] {
        shadowed[path] ?? []
    }
}
