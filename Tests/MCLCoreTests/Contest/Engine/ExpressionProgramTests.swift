import Foundation
import Testing
@testable import MCLCore

/// A compiled expression (tree) and its cache. An expression is parsed once by text
/// and the tree is evaluated; the result and the error (kind, text, **order** — Java evaluates during
/// parsing and `&&`/`||` do not short-circuit) must be identical to the original evaluator that works during
/// parsing (`ExpressionReference`), which is measured against Java (`ExpressionMeasured`).
@Suite struct ExpressionProgramTests {

    static let variables: JavaLinkedMap<ExpressionValue> = {
        var map = JavaLinkedMap<ExpressionValue>()
        for key in ExpressionMeasured.variables.keys.sorted() {
            map.put(key, ExpressionMeasured.variables[key])
        }
        return map
    }()

    enum Outcome: Equatable, CustomStringConvertible {
        case value(UInt64)
        case error(ExpressionError.Kind, String)

        var description: String {
            switch self {
            case .value(let bits): return "hodnota \(Double(bitPattern: bits))"
            case .error(let kind, let message): return "chyba \(kind): \(message)"
            }
        }

        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            switch (lhs, rhs) {
            case (.value(let a), .value(let b)): return a == b
            case (.error(let k1, let m1), .error(let k2, let m2)):
                return k1 == k2 && m1.utf16.elementsEqual(m2.utf16)
            default: return false
            }
        }
    }

    static func outcome(_ body: () throws(ExpressionError) -> Double) -> Outcome {
        do throws(ExpressionError) {
            return .value(try body().bitPattern)
        } catch {
            return .error(error.kind, error.message)
        }
    }

    static func compare(_ expression: String) -> (mine: Outcome, reference: Outcome) {
        let mine = outcome { () throws(ExpressionError) in try Expression.eval(expression, variables) }
        let reference = outcome { () throws(ExpressionError) in try ExpressionReference.eval(expression, variables) }
        return (mine, reference)
    }

    // MARK: - error order as in Java

    /// An evaluation error (regex in `matches`) on the left precedes a parse error on the right, because
    /// Java evaluates during parsing; an unknown function name is reported only after the arguments
    /// and the parenthesis; `&&`/`||` do not short-circuit.
    @Test(arguments: [
        ("matches('a', '(') + )", ExpressionError.Kind.patternSyntax),
        ("foo(matches('a', '('))", .patternSyntax),
        ("foo(1", .illegalArgument),
        ("foo(1, 2) + 3", .illegalArgument),
        ("matches('a', '(') 1", .patternSyntax),
        ("1 || matches('a', '(')", .patternSyntax),
        ("0 && matches('a', '(')", .patternSyntax),
        ("matches('a', '(') + 1..2", .patternSyntax),
        ("1..2 + matches('a', '(')", .numberFormat),
        ("matches('a', '(') == 'x", .patternSyntax),
        ("max(1, matches('a', '[')", .patternSyntax),
        ("(matches('a', '(')", .patternSyntax),
        ("-matches('a', '(') #", .patternSyntax),
    ])
    func errorOrderFollowsJava(_ expression: String, _ kind: ExpressionError.Kind) {
        let (mine, reference) = Self.compare(expression)
        #expect(mine == reference, "\(expression.debugDescription): \(mine) × \(reference)")
        if case .error(let actual, _) = mine {
            #expect(actual == kind, "\(expression.debugDescription)")
        } else {
            Issue.record("\(expression.debugDescription): an error was expected")
        }
        // The second evaluation comes from the cache and must end the same.
        #expect(Self.compare(expression).mine == mine)
    }

    @Test func unknownFunctionMessageAfterArguments() {
        let (mine, _) = Self.compare("foo(1, 2) + 3")
        #expect(mine == .error(.illegalArgument, "Neznámá funkce: foo"))
        #expect(Self.compare("foo(1").mine == .error(.illegalArgument, "Očekáváno ')' ve výrazu: foo(1"))
    }

    // MARK: - differential fuzz against the reference

    static let tokens: [String] = [
        "1", "2", "0", "2.5", ".5", "1..2", ".", "10", "007",
        "'a'", "'EU'", "'28'", "''", "'", "'[A-Z]+'", "'('", "'['", "'a{'", "'\\\\p{L}'",
        "a", "b", "five", "zero", "nan", "inf", "s28", "sNaN", "sAbc", "sEU", "exch", "band",
        "sRegex", "sBadRegex", "mult.zones", "mult.", "a.b.c", "missing", "_x", "\u{E9}", "\u{212B}",
        "min(", "max(", "round(", "floor(", "ceil(", "matches(", "foo(", "min (",
        "+", "-", "*", "/", "==", "!=", "<", ">", "<=", ">=", "&&", "||", "!", ",", "(", ")",
        " ", "  ", "\t", "\u{2003}", "\u{A0}", "#", "=", "&", "|", "@", "\u{661}", "😀",
    ]

    static let atoms = ["1", "2.5", "0", "'EU'", "'28'", "a", "five", "zero", "nan", "s28", "sNaN",
                        "sEU", "exch", "missing", "mult.zones", "sRegex", "sBadRegex", "'('", "'[A-Z]'"]
    static let binary = [" + ", " - ", " * ", " / ", " == ", " != ", " < ", " > ", " <= ", " >= ", " && ", " || "]
    static let functions = ["min", "max", "round", "floor", "ceil", "matches", "foo"]

    static func valid(depth: Int, _ next: (Int) -> Int) -> String {
        func operand() -> String {
            switch depth > 3 ? 0 : next(6) {
            case 1: return "(" + valid(depth: depth + 1, next) + ")"
            case 2: return ["-", "!"][next(2)] + operand()
            case 3:
                let name = functions[next(functions.count)]
                let second = next(2) == 0 ? "" : ", " + valid(depth: depth + 1, next)
                return name + "(" + valid(depth: depth + 1, next) + second + ")"
            default: return atoms[next(atoms.count)]
            }
        }
        var out = operand()
        for _ in 0..<next(4) {
            out += binary[next(binary.count)] + operand()
        }
        return out
    }

    /// Deterministic random expressions (own LCG) from the tokens above — valid and broken, with
    /// nesting around the limit. The value must match bit for bit, the error by kind and text.
    @Test func randomExpressionsMatchReference() {
        var seed: UInt64 = 2026
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var mismatches: [String] = []
        var errors = 0
        let cases = 30_000
        for i in 0..<cases {
            var expression = ""
            if i % 50 == 0 {
                // Nesting around the limit (parentheses, unary operators, functions).
                let depth = Expression.maxNestingDepth - 2 + next(5)
                let open = ["(", "-", "!", "max(1, ", "matches('x', "][next(5)]
                expression = String(repeating: open, count: depth) + Self.tokens[next(Self.tokens.count)]
                if next(2) == 0 { expression += String(repeating: ")", count: depth) }
            } else if i % 2 == 0 {
                for _ in 0..<(1 + next(12)) {
                    expression += Self.tokens[next(Self.tokens.count)]
                }
            } else {
                // A grammatically valid expression, occasionally with one random token inserted.
                expression = Self.valid(depth: 0, next)
                if next(4) == 0 {
                    let units = Array(expression.utf16)
                    let at = next(units.count + 1)
                    expression = JavaChar.string(Array(units[..<at])) + Self.tokens[next(Self.tokens.count)]
                        + JavaChar.string(Array(units[at...]))
                }
            }
            let (mine, reference) = Self.compare(expression)
            if case .error = reference { errors += 1 }
            if mine != reference {
                mismatches.append("\(expression.debugDescription): \(mine) × \(reference)")
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(20).joined(separator: "\n"))")
        // The fuzz must cover both branches, otherwise it would verify nothing.
        #expect(errors > cases / 10)
        #expect(errors < cases * 9 / 10)
    }

    /// A table measured against Java, also through the cache: each row twice (the second time from the tree in the cache).
    @Test func measuredRowsTwiceThroughCache() {
        for row in ExpressionMeasured.rows {
            let first = Self.compare(row.expression)
            let second = Self.compare(row.expression)
            #expect(first.mine == first.reference, "\(row.expression.debugDescription)")
            #expect(second.mine == first.mine, "\(row.expression.debugDescription)")
        }
    }

    // MARK: - cache

    @Test func sameTextIsParsedOnce() throws {
        let cache = ExpressionProgramCache(capacity: 16)
        let first = cache.program("a + b * 2")
        let second = cache.program("a + b * 2")
        #expect(cache.count == 1)
        #expect(try first.evaluate(Self.variables) == 5)
        #expect(try second.evaluate(Self.variables) == 5)
    }

    /// An erroneous expression is remembered too; the error is reported on every evaluation.
    @Test func brokenExpressionIsCachedAndThrowsEveryTime() {
        let cache = ExpressionProgramCache(capacity: 16)
        for _ in 0..<2 {
            let program = cache.program("1 +")
            #expect(throws: ExpressionError(kind: .illegalArgument, message: "Neočekávaný konec výrazu: 1 +")) {
                try program.evaluate(Self.variables)
            }
        }
        #expect(cache.count == 1)
    }

    /// The key is text by UTF-16 like a Java `String`: `'\u{C5}' == '\u{C5}'` and
    /// `'A\u{30A}' == '\u{C5}'` are two different expressions with different results.
    @Test func canonicallyEquivalentTextsAreDistinctPrograms() throws {
        let cache = ExpressionProgramCache(capacity: 16)
        let precomposed = cache.program("'\u{C5}' == '\u{C5}'")
        let decomposed = cache.program("'A\u{30A}' == '\u{C5}'")
        #expect(cache.count == 2)
        #expect(try precomposed.evaluate(Self.variables) == 1)
        #expect(try decomposed.evaluate(Self.variables) == 0)
    }

    @Test func capacityBoundsTheCache() throws {
        let cache = ExpressionProgramCache(capacity: 4)
        for i in 0..<10 {
            #expect(try cache.program("\(i) + 1").evaluate(Self.variables) == Double(i + 1))
            #expect(cache.count <= 4)
        }
    }

    @Test func concurrentUseYieldsSameResults() async {
        let cache = ExpressionProgramCache(capacity: 64)
        let expressions = (0..<32).map { "a * \($0) + matches(exch, '[A-Z]') + max(\($0), five)" }
        let expected = expressions.map { text in Self.outcome { () throws(ExpressionError) in
            try ExpressionReference.eval(text, Self.variables) } }
        let results = await withTaskGroup(of: [Outcome].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    expressions.map { text in Self.outcome { () throws(ExpressionError) in
                        try cache.program(text).evaluate(Self.variables) } }
                }
            }
            var all: [[Outcome]] = []
            for await result in group { all.append(result) }
            return all
        }
        for result in results {
            #expect(result == expected)
        }
    }
}
