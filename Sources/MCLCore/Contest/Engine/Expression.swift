import os

/// Value of an expression variable and an intermediate result: a number or text. Mirrors Java's
/// `Object` in `Expression` (`Double`/`Number` or `String`).
///
/// A Java variable map may carry other types too (a `Boolean` and the like is read as the number 0),
/// but no caller in the app passes them — hence only two cases. A missing
/// variable is, as in Java, the number 0 (not empty text).
public enum ExpressionValue: Equatable, Sendable,
                             ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    case number(Double)
    case text(String)

    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(stringLiteral value: String) { self = .text(value) }
}

/// Expression evaluation error. `message` is verbatim Java `getMessage()` (the user
/// sees it in the UI), `kind` distinguishes the Java exception class.
public struct ExpressionError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        /// `IllegalArgumentException` — six language messages („Neočekávaný znak…" etc.).
        case illegalArgument
        /// `NumberFormatException` from a number in the expression text (`1..2`, `١٤`).
        case numberFormat
        /// `PatternSyntaxException` from `matches` — a multi-line Java message.
        case patternSyntax
        /// A pattern in `matches` that Java may accept but the `JavaRegex` adapter
        /// does not convert (`JavaRegexError.Kind.unsupported`, a Czech message). Swift only.
        case unsupportedPattern
        /// Nesting above `Expression.maxNestingDepth`. Java (much deeper) fails here with
        /// `StackOverflowError`; Swift only, documented as a deliberate divergence from Java v1.1.1.
        case nestingTooDeep
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { message }
}

/// Safe evaluator of scoring-rule expressions (`scoring.total`, `value.expr`,
/// `when.expr`) — a rewrite of Java `contest.engine.Expression` including its quirks.
///
/// Grammar (precedence from lowest): `||`, `&&`, one non-associative comparison
/// `== != <= >= < >`, `+ -`, `* /`, unary `- !`, factor (a number of digits and dots,
/// `'text'` without escapes, an identifier with dots, parentheses, functions `min max round floor
/// ceil matches` with one or two arguments). The result is a `Double`, true = ≠ 0.
///
/// What is deliberately copied from Java:
/// - evaluation happens **during** parsing left to right — `&&`/`||` do not short-circuit and an error
///   is reported in the order Java runs into it (function arguments before the function name,
///   the regex in `matches` before the next text);
/// - text is read as a number by Java `Double.parseDouble` (with `trim()`), error = 0;
/// - `==`/`!=` with text on either side compares texts (a number via Java
///   `String.valueOf`, whole ones without `.0`, huge ones saturated to `long`), by UTF-16 units;
/// - division by zero gives 0; `round` = `Math.round`, `min`/`max` = `Math.min/max`;
/// - the text is walked by UTF-16 units (`charAt`) and characters are classified the Java way
///   (`Character.isWhitespace/isDigit/isLetter/isLetterOrDigit`).
///
/// Extra versus Java: the nesting depth is limited (`maxNestingDepth`), so that an expression
/// from a definition cannot overflow the thread stack.
///
/// **Translate once, evaluate many times**: Java parses the text on every
/// evaluation; here the text is translated once into a tree (`Program`, a shared `ExpressionProgramCache`
/// keyed by the text by UTF-16) and the tree is evaluated. Behaviour does not change, including the error order:
/// a parse error is written into the tree as a `fail` node **at the place where Java runs into it**,
/// with the preceding siblings, so all the parts that Java managed to evaluate before it
/// are evaluated first (and may fail on a regex). This is guarded by a differential test against the original
/// evaluator (`ExpressionProgramTests`).
public enum Expression {

    /// Maximum allowed nesting (parentheses, unary `-`/`!` and function arguments together).
    ///
    /// Java on the default thread (2 MB) fails with `StackOverflowError` only at ~1,350 parentheses,
    /// ~2,300 nested functions and ~10,000 unary operators (JDK 21, varies with the JIT);
    /// real expressions have nesting 1–3.
    ///
    /// The limit is set for the **worst composite shape** on a 512 KB thread (Swift
    /// concurrency threads) in a debug build: nested functions and at the bottom `matches` with a regex
    /// nested to the `JavaRegex` limit (16 groups of any kind). Regex translation
    /// runs at the deepest point and itself consumes ~245 KB; a function level costs ~8.6 KB,
    /// a parenthesis ~7 KB, a unary operator ~0.9 KB (release roughly ten times less).
    /// Such a shape failed from 27 levels; 12 gives a 2.25× margin and at the limit ~120 KB
    /// of stack remains for callers (the `ConditionEvaluator` recursion).
    public static let maxNestingDepth = 12

    /// Java `Expression.eval(expr, vars)`. A `nil` or empty (Java `isBlank`)
    /// expression is 0.
    ///
    /// A dictionary cannot carry two canonically equal keys (`K` / `K`), so the conversion to
    /// `JavaLinkedMap` loses nothing; a variable is looked up by UTF-16 as in Java.
    public static func eval(_ expression: String?,
                            _ variables: [String: ExpressionValue]) throws(ExpressionError) -> Double {
        guard let expression, !JavaText.isBlank(expression) else { return 0 }
        var map = JavaLinkedMap<ExpressionValue>()
        for (name, value) in variables { map.put(name, value) }
        return try eval(expression, map)
    }

    /// Java `Expression.eval(expr, vars)` over an ordered map with keys by UTF-16
    /// (Java `LinkedHashMap`, e.g. `QsoVariables.of`). A missing variable and a `nil`
    /// value = 0.
    public static func eval(_ expression: String?,
                            _ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> Double {
        guard let expression, !JavaText.isBlank(expression) else { return 0 }
        return try ExpressionProgramCache.shared.program(expression).evaluate(variables)
    }

    /// Translates the expression text into a tree (without a cache). A parse error is not thrown right away — it is
    /// part of the tree and surfaces on evaluation at the Java place.
    static func compile(_ expression: String) -> Program {
        var compiler = Compiler(source: expression)
        let root = compiler.parseOr()
        if compiler.failed {
            return Program(root: root)
        }
        compiler.skipWhitespace()
        if compiler.position < compiler.units.count {
            return Program(root: .fail([root], ExpressionError(
                kind: .illegalArgument, message: "Neočekávaný znak ve výrazu: " + expression)))
        }
        return Program(root: root)
    }

    // MARK: - conversions (Java `toNum`, `str`, `equalsVal`, `truthy`, `bool`)

    /// Java `toNum`: a number unchanged, text via `Double.parseDouble(s.trim())`, error = 0.
    static func number(_ value: ExpressionValue) -> Double {
        switch value {
        case .number(let number):
            return number
        case .text(let text):
            return JavaDouble.parseDouble(text) ?? 0
        }
    }

    /// Java `str`: text unchanged; a number that is whole (`d == Math.rint(d)`, so also
    /// infinity), as `String.valueOf((long) d)` with saturation; otherwise `Double.toString`.
    static func text(_ value: ExpressionValue) -> String {
        switch value {
        case .text(let text):
            return text
        case .number(let number):
            // `.toNearestOrEven` is exactly Java `Math.rint`.
            if number == number.rounded(.toNearestOrEven) {
                return String(JavaMath.d2l(number))
            }
            return JavaDouble.toString(number)
        }
    }

    /// Java `equalsVal`: with text on either side `Objects.equals(str(a), str(b))`
    /// (by UTF-16 units, without canonical equivalence), otherwise numeric `==`.
    static func equal(_ left: ExpressionValue, _ right: ExpressionValue) -> Bool {
        switch (left, right) {
        case (.number(let a), .number(let b)):
            return a == b
        default:
            return text(left).utf16.elementsEqual(text(right).utf16)
        }
    }

    static func truthy(_ value: ExpressionValue) -> Bool {
        number(value) != 0
    }

    static func bool(_ flag: Bool) -> ExpressionValue {
        .number(flag ? 1 : 0)
    }


    // MARK: - translated tree

    /// Translated expression: a tree of nodes over texts and numbers, without binding to variables. Immutable,
    /// shared between threads.
    struct Program: Sendable {
        fileprivate let root: Node

        /// Java `Expression.eval(text, vars)` over the translated tree.
        func evaluate(_ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> Double {
            number(try root.evaluate(variables))
        }
    }

    /// Chain operator `+ - * /` (precedence is carried by the tree shape, not the operator).
    fileprivate enum ArithmeticOperator: Sendable {
        case add, subtract, multiply, divide
    }

    fileprivate enum ComparisonOperator: Sendable {
        case equal, notEqual, lessOrEqual, greaterOrEqual, less, greater
    }

    fileprivate enum Function: Sendable {
        case min, max, round, floor, ceil, matches
    }

    /// Tree node. Chains (`||`, `&&`, `+ -`, `* /`) are arrays, not left-nested binary
    /// nodes — the tree depth thus grows only with nesting (parentheses, unary operators,
    /// function arguments), which `maxNestingDepth` guards, not with the expression length.
    ///
    /// All children are evaluated left to right and **all** of them (no short-circuiting), i.e.
    /// in the order Java parses and evaluates them.
    fileprivate indirect enum Node: Sendable {
        case constant(ExpressionValue)
        /// Variable name as a ready map key (Java `vars.get(name)`, missing = 0).
        case variable(JavaStringKey)
        /// `a || b || …` — one member is that member unchanged, more members give 0/1.
        case or([Node])
        case and([Node])
        case comparison(ComparisonOperator, Node, Node)
        case arithmetic(Node, [(ArithmeticOperator, Node)])
        case negate(Node)
        case not(Node)
        /// Without a second argument the second equals the first (evaluated once).
        case function(Function, Node, Node?)
        /// A parse error (also an unknown function): `prefix` is evaluated first — what Java
        /// managed to evaluate before it ran into the error — and then the error is thrown.
        case fail([Node], ExpressionError)

        func evaluate(_ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> ExpressionValue {
            switch self {
            case .constant(let value):
                return value
            case .variable(let key):
                return variables[key] ?? .number(0)
            case .or(let nodes):
                return try Self.logical(nodes, variables, isOr: true)
            case .and(let nodes):
                return try Self.logical(nodes, variables, isOr: false)
            case .comparison(let op, let left, let right):
                return try Self.compare(op, left, right, variables)
            case .arithmetic(let first, let rest):
                return try Self.arithmetic(first, rest, variables)
            case .negate(let operand):
                // Java `dneg` only flips the sign bit, even for NaN (`-NaN` → `fff8…`).
                // Swift's unary minus does not guarantee that on an older toolchain (CI, Xcode 16) for NaN
                // and returns the canonical `7ff8…`, so we flip the bit by hand.
                let value = number(try operand.evaluate(variables))
                return .number(Double(bitPattern: value.bitPattern ^ (1 << 63)))
            case .not(let operand):
                return bool(!truthy(try operand.evaluate(variables)))
            case .function(let function, let first, let second):
                return try Self.call(function, first, second, variables)
            case .fail(let prefix, let error):
                for node in prefix {
                    _ = try node.evaluate(variables)
                }
                throw error
            }
        }

        @inline(never)
        private static func logical(_ nodes: [Node], _ variables: JavaLinkedMap<ExpressionValue>,
                                    isOr: Bool) throws(ExpressionError) -> ExpressionValue {
            var value = try nodes[0].evaluate(variables)
            for node in nodes.dropFirst() {
                let right = try node.evaluate(variables)
                value = bool(isOr ? (truthy(value) || truthy(right)) : (truthy(value) && truthy(right)))
            }
            return value
        }

        @inline(never)
        private static func compare(_ op: ComparisonOperator, _ left: Node, _ right: Node,
                                    _ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> ExpressionValue {
            let a = try left.evaluate(variables)
            let b = try right.evaluate(variables)
            switch op {
            case .equal: return bool(equal(a, b))
            case .notEqual: return bool(!equal(a, b))
            case .lessOrEqual: return bool(number(a) <= number(b))
            case .greaterOrEqual: return bool(number(a) >= number(b))
            case .less: return bool(number(a) < number(b))
            case .greater: return bool(number(a) > number(b))
            }
        }

        @inline(never)
        private static func arithmetic(_ first: Node, _ rest: [(ArithmeticOperator, Node)],
                                       _ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> ExpressionValue {
            var value = try first.evaluate(variables)
            for (op, node) in rest {
                let right = number(try node.evaluate(variables))
                switch op {
                case .add: value = .number(number(value) + right)
                case .subtract: value = .number(number(value) - right)
                case .multiply: value = .number(number(value) * right)
                case .divide:
                    // Java: a divisor of 0 (also −0, also invalid text) gives 0.0, not ∞/NaN.
                    value = .number(right == 0 ? 0.0 : number(value) / right)
                }
            }
            return value
        }

        @inline(never)
        private static func call(_ function: Function, _ firstNode: Node, _ secondNode: Node?,
                                 _ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> ExpressionValue {
            let first = try firstNode.evaluate(variables)
            let second = try secondNode?.evaluate(variables) ?? first
            switch function {
            case .min: return .number(JavaMath.min(number(first), number(second)))
            case .max: return .number(JavaMath.max(number(first), number(second)))
            case .round: return .number(Double(JavaMath.round(number(first))))
            case .floor: return .number(number(first).rounded(.down))
            case .ceil: return .number(number(first).rounded(.up))
            case .matches: return bool(try find(pattern: text(second), in: text(first)))
            }
        }

        /// `Pattern.compile(pattern).matcher(text).find()`. The translated pattern (also a translation error)
        /// is taken from the shared `JavaRegexCache` — the result is the same as translating every time.
        private static func find(pattern: String, in text: String) throws(ExpressionError) -> Bool {
            let regex: JavaRegex
            do {
                regex = try JavaRegexCache.shared.regex(pattern)
            } catch {
                switch error.kind {
                case .syntax: throw ExpressionError(kind: .patternSyntax, message: error.message)
                case .unsupported: throw ExpressionError(kind: .unsupportedPattern, message: error.message)
                }
            }
            return regex.firstMatch(in: text) != nil
        }
    }

    // MARK: - translation (recursive descent)

    /// Translator of text into a tree — the grammar and error positions exactly like the Java parser. On the first
    /// error it sets `failed`, returns a `fail` node and every parent level ends immediately
    /// with what it already has (the faulty node is always the last one evaluated in it).
    private struct Compiler {
        let source: String
        let units: [UInt16]
        var position = 0
        var depth = 0
        var failed = false

        init(source: String) {
            self.source = source
            self.units = Array(source.utf16)
        }

        mutating func parseOr() -> Node {
            let first = parseAnd()
            var nodes = [first]
            while !failed {
                skipWhitespace()
                guard peekOperator(0x7C, 0x7C) else { break } // ||
                position += 2
                nodes.append(parseAnd())
            }
            return nodes.count == 1 ? first : .or(nodes)
        }

        mutating func parseAnd() -> Node {
            let first = parseComparison()
            var nodes = [first]
            while !failed {
                skipWhitespace()
                guard peekOperator(0x26, 0x26) else { break } // &&
                position += 2
                nodes.append(parseComparison())
            }
            return nodes.count == 1 ? first : .and(nodes)
        }

        /// At most one comparison (`1 < 2 < 3` ends with „Neočekávaný znak").
        mutating func parseComparison() -> Node {
            let left = parseAdd()
            if failed { return left }
            skipWhitespace()
            let op: ComparisonOperator
            if peekOperator(0x3D, 0x3D) { // ==
                position += 2
                op = .equal
            } else if peekOperator(0x21, 0x3D) { // !=
                position += 2
                op = .notEqual
            } else if peekOperator(0x3C, 0x3D) { // <=
                position += 2
                op = .lessOrEqual
            } else if peekOperator(0x3E, 0x3D) { // >=
                position += 2
                op = .greaterOrEqual
            } else if peek(0x3C) { // <
                position += 1
                op = .less
            } else if peek(0x3E) { // >
                position += 1
                op = .greater
            } else {
                return left
            }
            return .comparison(op, left, parseAdd())
        }

        mutating func parseAdd() -> Node {
            let first = parseTerm()
            var rest: [(ArithmeticOperator, Node)] = []
            while !failed {
                skipWhitespace()
                if peek(0x2B) { // +
                    position += 1
                    rest.append((.add, parseTerm()))
                } else if peek(0x2D) { // -
                    position += 1
                    rest.append((.subtract, parseTerm()))
                } else {
                    break
                }
            }
            return rest.isEmpty ? first : .arithmetic(first, rest)
        }

        mutating func parseTerm() -> Node {
            let first = parseUnary()
            var rest: [(ArithmeticOperator, Node)] = []
            while !failed {
                skipWhitespace()
                if peek(0x2A) { // *
                    position += 1
                    rest.append((.multiply, parseUnary()))
                } else if peek(0x2F) { // /
                    position += 1
                    rest.append((.divide, parseUnary()))
                } else {
                    break
                }
            }
            return rest.isEmpty ? first : .arithmetic(first, rest)
        }

        mutating func parseUnary() -> Node {
            skipWhitespace()
            if peek(0x2D) { // -
                position += 1
                if let tooDeep = enter() { return tooDeep }
                defer { depth -= 1 }
                return .negate(parseUnary())
            }
            if peek(0x21) { // !
                position += 1
                if let tooDeep = enter() { return tooDeep }
                defer { depth -= 1 }
                return .not(parseUnary())
            }
            return parseFactor()
        }

        mutating func parseFactor() -> Node {
            skipWhitespace()
            if peek(0x28) { // (
                position += 1
                let inner = nestedOr()
                if failed { return inner }
                skipWhitespace()
                if let missing = expectClosingParen([inner]) { return missing }
                return inner
            }
            guard position < units.count else {
                return fail([], illegal("Neočekávaný konec výrazu: " + source))
            }
            let unit = units[position]
            if unit == 0x27 { // '
                return parseString()
            }
            if JavaChar.isDigit(unit) || unit == 0x2E {
                return parseNumber()
            }
            if JavaChar.isLetter(unit) || unit == 0x5F {
                return parseIdentifierOrFunction()
            }
            return fail([], illegal("Neplatný znak '" + JavaChar.string([unit]) + "' ve výrazu: " + source))
        }

        mutating func parseString() -> Node {
            position += 1 // opening '
            let start = position
            while position < units.count && units[position] != 0x27 {
                position += 1
            }
            if position >= units.count {
                return fail([], illegal("Neuzavřený řetězec ve výrazu: " + source))
            }
            let text = JavaChar.string(Array(units[start..<position]))
            position += 1 // closing '
            return .constant(.text(text))
        }

        mutating func parseNumber() -> Node {
            let start = position
            while position < units.count && (JavaChar.isDigit(units[position]) || units[position] == 0x2E) {
                position += 1
            }
            do {
                return .constant(.number(try JavaDouble.parse(JavaChar.string(Array(units[start..<position])))))
            } catch {
                return fail([], ExpressionError(kind: .numberFormat, message: error.message))
            }
        }

        mutating func parseIdentifierOrFunction() -> Node {
            let start = position
            while position < units.count {
                let unit = units[position]
                guard JavaChar.isLetterOrDigit(unit) || unit == 0x5F || unit == 0x2E else { break }
                position += 1
            }
            let name = JavaChar.string(Array(units[start..<position]))
            skipWhitespace()
            guard peek(0x28) else { return .variable(JavaStringKey(name)) }
            position += 1
            // Both arguments are evaluated before the name is verified (as in Java);
            // without a second argument the second equals the first.
            let first = nestedOr()
            if failed { return first }
            var arguments = [first]
            skipWhitespace()
            if peek(0x2C) { // ,
                position += 1
                arguments.append(nestedOr())
                if failed { return .fail(arguments, Self.unreachable) }
            }
            skipWhitespace()
            if let missing = expectClosingParen(arguments) { return missing }
            let second = arguments.count > 1 ? arguments[1] : nil
            switch name {
            case "min": return .function(.min, first, second)
            case "max": return .function(.max, first, second)
            case "round": return .function(.round, first, second)
            case "floor": return .function(.floor, first, second)
            case "ceil": return .function(.ceil, first, second)
            case "matches": return .function(.matches, first, second)
            default: return .fail(arguments, illegal("Neznámá funkce: " + name))
            }
        }

        /// Error of a `fail` node whose last child itself fails — evaluation does not get here.
        static let unreachable = ExpressionError(kind: .illegalArgument, message: "")

        // MARK: helpers

        /// `parseOr` one level deeper (a parenthesis, a function argument).
        mutating func nestedOr() -> Node {
            if let tooDeep = enter() { return tooDeep }
            defer { depth -= 1 }
            return parseOr()
        }

        /// Nesting above the limit → a `fail` node (and `depth` is not increased), otherwise `nil`.
        mutating func enter() -> Node? {
            if depth >= maxNestingDepth {
                return fail([], ExpressionError(kind: .nestingTooDeep,
                                                message: "Příliš hluboké zanoření ve výrazu: " + source))
            }
            depth += 1
            return nil
        }

        mutating func fail(_ prefix: [Node], _ error: ExpressionError) -> Node {
            failed = true
            return .fail(prefix, error)
        }

        mutating func skipWhitespace() {
            while position < units.count && Self.isWhitespace(units[position]) {
                position += 1
            }
        }

        /// Java `Character.isWhitespace(char)`; half of a surrogate pair is not white.
        static func isWhitespace(_ unit: UInt16) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return false }
            return JavaText.isWhitespace(scalar)
        }

        func peek(_ unit: UInt16) -> Bool {
            position < units.count && units[position] == unit
        }

        /// Java `src.regionMatches(pos, op, 0, 2)` for a two-character operator.
        func peekOperator(_ first: UInt16, _ second: UInt16) -> Bool {
            position + 1 < units.count && units[position] == first && units[position + 1] == second
        }

        /// If `)` is missing, a `fail` node with the already translated siblings `prefix`; otherwise it skips it.
        mutating func expectClosingParen(_ prefix: [Node]) -> Node? {
            if !peek(0x29) {
                return fail(prefix, illegal("Očekáváno ')' ve výrazu: " + source))
            }
            position += 1
            return nil
        }

        func illegal(_ message: String) -> ExpressionError {
            ExpressionError(kind: .illegalArgument, message: message)
        }
    }
}

/// Thread-safe cache of translated expressions (`Expression.Program`) keyed by the expression **text**.
///
/// The key is text by UTF-16 like a Java `String` (`JavaStringKey`), not canonical. The capacity is
/// bounded (the expression comes from a definition, but arbitrarily many definitions are loaded at runtime); once full
/// the cache is emptied and filled again. Translation is deterministic and runs outside the lock — concurrent
/// translation of the same text gives the same tree and either one is stored. A broken expression
/// is remembered too (the error is part of the tree).
final class ExpressionProgramCache: Sendable {

    static let shared = ExpressionProgramCache(capacity: 1024)

    private let capacity: Int
    private let entries = OSAllocatedUnfairLock<[JavaStringKey: Expression.Program]>(initialState: [:])

    /// - Parameter capacity: at most how many expressions are remembered (at least 1).
    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func program(_ expression: String) -> Expression.Program {
        let key = JavaStringKey(expression)
        if let cached = entries.withLock({ $0[key] }) {
            return cached
        }
        let program = Expression.compile(expression)
        let capacity = self.capacity
        entries.withLock { entries in
            if entries.count >= capacity && entries[key] == nil {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key] = program
        }
        return program
    }

    /// Number of remembered expressions (for tests).
    var count: Int {
        entries.withLock { $0.count }
    }
}
