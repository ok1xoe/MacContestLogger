import Foundation
import Testing
@testable import MCLCore

/// The contest expression language (`scoring.total`, `value.expr`, `when.expr`). The first ten
/// tests are a port of the Java `ExpressionTest`; the rest is a table measured against Java
/// (`ExpressionMeasured`) and safeguards Java does not have (nesting depth).
@Suite struct ExpressionTests {

    // MARK: - port of the Java ExpressionTest (10)

    @Test func multiplication() throws {
        #expect(try Expression.eval("qsoPoints * multTotal", ["qsoPoints": 5.0, "multTotal": 4.0]) == 20.0)
    }

    @Test func parenthesesAndAddition() throws {
        #expect(try Expression.eval("(a + b) * c", ["a": 1.0, "b": 2.0, "c": 3.0]) == 9.0)
    }

    @Test func dottedIdentifiers() throws {
        #expect(try Expression.eval("mult.zones + mult.countries",
                                    ["mult.zones": 2.0, "mult.countries": 3.0]) == 5.0)
    }

    @Test func functionsAndMissingVarIsZero() throws {
        #expect(try Expression.eval("max(qsoPoints, 1)", ["qsoPoints": 0.0]) == 1.0)
        #expect(try Expression.eval("unknownVar", [:]) == 0.0)
    }

    @Test func divisionByZeroIsSafe() throws {
        #expect(try Expression.eval("a / b", ["a": 5.0, "b": 0.0]) == 0.0)
    }

    @Test func numberComparisons() throws {
        #expect(try Expression.eval("5 == 5", [:]) == 1.0)
        #expect(try Expression.eval("5 != 3", [:]) == 1.0)
        #expect(try Expression.eval("3 < 5", [:]) == 1.0)
        #expect(try Expression.eval("5 <= 5", [:]) == 1.0)
        #expect(try Expression.eval("6 > 9", [:]) == 0.0)
        #expect(try Expression.eval("9 >= 9", [:]) == 1.0)
    }

    @Test func stringComparisons() throws {
        #expect(try Expression.eval("'EU' == 'EU'", [:]) == 1.0)
        #expect(try Expression.eval("'EU' == 'NA'", [:]) == 0.0)
        #expect(try Expression.eval("'EU' != 'NA'", [:]) == 1.0)
        // a string variable from the context
        let vars: [String: ExpressionValue] = ["exch": "28", "ownItuZone": "28"]
        #expect(try Expression.eval("exch == ownItuZone", vars) == 1.0)
        #expect(try Expression.eval("exch == '14'", vars) == 0.0)
    }

    @Test func logicalOperators() throws {
        #expect(try Expression.eval("1 && 0", [:]) == 0.0)
        #expect(try Expression.eval("1 || 0", [:]) == 1.0)
        #expect(try Expression.eval("!0", [:]) == 1.0)
        #expect(try Expression.eval("!5", [:]) == 0.0)
        // precedence: && binds tighter than ||
        #expect(try Expression.eval("1 || 0 && 0", [:]) == 1.0)
    }

    @Test func matchesFunction() throws {
        #expect(try Expression.eval("matches('ARRL', '[A-Za-z]')", [:]) == 1.0)
        #expect(try Expression.eval("matches('14', '[A-Za-z]')", [:]) == 0.0)
        #expect(try Expression.eval("matches(exch, '[A-Za-z]')", ["exch": "DARC"]) == 1.0)
    }

    @Test func comparisonComposedWithLogic() throws {
        let vars: [String: ExpressionValue] = ["workedContinent": "NA", "ownContinent": "EU"]
        #expect(try Expression.eval("workedContinent != ownContinent", vars) == 1.0)
        #expect(try Expression.eval("workedContinent == ownContinent", vars) == 0.0)
    }

    // MARK: - table measured against Java

    @Test(arguments: ExpressionMeasured.rows)
    func measuredAgainstJava(_ row: (expression: String, outcome: ExpressionMeasured.Outcome)) {
        let result = Result { () throws(ExpressionError) in
            try Expression.eval(row.expression, ExpressionMeasured.variables)
        }
        switch (row.outcome, result) {
        case (.ok(let bits), .success(let value)):
            #expect(value.bitPattern == bits,
                    "\(row.expression.debugDescription): \(value) instead of \(Double(bitPattern: bits))")
        case (.error(let kind, let message), .failure(let error)):
            #expect(error.kind == kind, "\(row.expression.debugDescription)")
            // By UTF-16 units like Java `String.equals`, not canonically.
            #expect(error.message.utf16.elementsEqual(message.utf16), "\(row.expression.debugDescription)")
        case (.ok(let bits), .failure(let error)):
            Issue.record("\(row.expression.debugDescription): error \(error.message), Java \(Double(bitPattern: bits))")
        case (.error(_, let message), .success(let value)):
            Issue.record("\(row.expression.debugDescription): \(value), Java error \(message)")
        }
    }

    /// Review focus 1: user text as a number is read with Java
    /// `Double.parseDouble` (with `trim()`), invalid text is 0. The values are from the table
    /// measured against Java; they are spelled out here so it is visible what this is about.
    @Test func userTextAsNumberFollowsJava() throws {
        let cases: [(exch: String, expression: String, java: Double)] = [
            ("NaN", "exch == 5", 0), ("NaN", "exch > 4", 0), ("NaN", "exch < 4", 0),
            ("NaN", "exch && 1", 1),        // NaN is true
            ("nan", "exch + 0", 0), ("NAN", "exch + 0", 0), ("inf", "exch + 0", 0),
            ("1e400", "exch > 1000", 1), ("1e400", "exch == 5", 0),
            ("0x1p3", "exch + 1 == 9", 1),
            ("0x1p3", "exch == 8", 0),      // `==` with text compares texts
            (" 7 ", "exch + 1 == 8", 1), (" 7 ", "exch == '7'", 0),
            ("1d", "exch + 0 == 1", 1), ("\u{A0}5", "exch > 4", 0),
            ("\u{661}\u{664}", "exch + 0", 0), ("1_000", "exch + 0", 0), ("0x10", "exch + 0", 0),
        ]
        for c in cases {
            #expect(try Expression.eval(c.expression, ["exch": .text(c.exch)]) == c.java,
                    "\(c.exch.debugDescription): \(c.expression)")
        }
        #expect(try Expression.eval("exch", ["exch": "Infinity"]) == .infinity)
        #expect(try Expression.eval("exch", ["exch": "NaN"]).isNaN)
    }

    @Test func nilOrBlankExpressionIsZero() throws {
        #expect(try Expression.eval(nil, [:]) == 0)
        #expect(try Expression.eval("", [:]) == 0)
        #expect(try Expression.eval(" \u{2003}\t", [:]) == 0)
    }

    @Test func textValueOfNumberVariableIsTextComparison() throws {
        // A variable's value can be a number or text — equality with text compares via Java
        // `String.valueOf`: an integer without `.0`, otherwise `Double.toString`.
        #expect(try Expression.eval("z == '28'", ["z": 28]) == 1)
        #expect(try Expression.eval("z == '1.0E-5'", ["z": 1e-5]) == 1)
    }

    @Test func errorDescriptionIsJavaMessage() {
        #expect(throws: ExpressionError(kind: .illegalArgument, message: "Neznámá funkce: foo")) {
            try Expression.eval("foo(1)", [:])
        }
        let error = ExpressionError(kind: .numberFormat, message: "multiple points")
        #expect(error.description == "multiple points")
    }

    // MARK: - nesting depth (an expression from a definition is user data)

    static func evalOnSmallStack(_ expression: String) async -> Result<Double, ExpressionError> {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: Result { () throws(ExpressionError) in
                    try Expression.eval(expression, [:])
                })
            }
            thread.stackSize = 512 * 1024
            thread.start()
        }
    }

    static let limit = Expression.maxNestingDepth

    static let shapes: [(name: String, make: @Sendable (Int) -> String)] = [
        ("parentheses", { String(repeating: "(", count: $0) + "1" + String(repeating: ")", count: $0) }),
        ("unary minus", { String(repeating: "-", count: $0) + "1" }),
        ("negation", { String(repeating: "!", count: $0) + "1" }),
        ("function", { String(repeating: "max(", count: $0) + "1" + String(repeating: ")", count: $0) }),
        // "-(" are two levels (a unary operator and a parenthesis)
        ("minus and parenthesis", { String(repeating: "-(", count: ($0 + 1) / 2) + "1"
                                  + String(repeating: ")", count: ($0 + 1) / 2) }),
    ]

    @Test func nestingAtLimitEvaluatesLikeJava() async throws {
        // Java (JDK 21) evaluates these shapes to a depth of ~1,000 and more. With an even limit
        // (12) the result of all shapes is 1 (an even number of minuses and negations).
        for shape in Self.shapes {
            let value = try await Self.evalOnSmallStack(shape.make(Self.limit)).get()
            #expect(value == 1, "\(shape.name)")
        }
    }

    @Test func nestingOverLimitThrowsInsteadOfCrashing() async {
        for shape in Self.shapes {
            for depth in [Self.limit + 1, 100_000] {
                let expression = shape.make(depth)
                let result = await Self.evalOnSmallStack(expression)
                #expect(throws: ExpressionError(
                    kind: .nestingTooDeep,
                    message: "Příliš hluboké zanoření ve výrazu: " + expression)) {
                    try result.get()
                }
            }
        }
    }

    @Test func limitLeavesRoomForRealExpressions() {
        // Real expressions have nesting 1–3; Java fails only around 1,000 levels.
        #expect(Self.limit == 12)
    }

    /// A regex nested to the `JavaRegex` limit (16) of the given kind, inside `a`
    /// (`b` for a negative lookahead).
    static func deepRegex(_ open: String) -> String {
        let depth = 16
        if open == "[a" {
            return String(repeating: "[a", count: depth) + String(repeating: "]", count: depth)
        }
        let opens = open == "(?<g"
            ? (0..<depth).map { "(?<g\($0)>" }.joined()
            : String(repeating: open, count: depth)
        return opens + (open == "(?!" ? "b" : "a") + String(repeating: ")", count: depth)
    }

    /// The worst composite shapes at the limit: a function (in the first and second argument),
    /// parentheses and `matches` in `matches`, at the bottom a regex nested 16 levels. For each
    /// regex kind the results of shapes A–D measured in Java (`ProbeExpr` over the same expressions).
    /// Without a limit calibrated to these shapes the debug build crashed on 512 KB (SIGBUS).
    @Test func combinedWorstShapesAtLimitMatchJava() async throws {
        // The shapes are built exactly to the limit depth (results do not depend on depth),
        // so a higher limit would crash here — the test guards the calibration.
        let outer = Self.limit - 1
        let java: [(open: String, results: [Double])] = [
            ("(", [1, 1, 1, 0]), ("(?:", [1, 1, 1, 0]), ("(?=", [1, 1, 1, 0]),
            ("(?<=", [1, 1, 1, 0]), ("(?!", [0, 1, 0, 0]), ("(?>", [1, 1, 1, 0]),
            ("(?<g", [1, 1, 1, 0]), ("[a", [1, 1, 1, 0]),
        ]
        for kind in java {
            let regex = Self.deepRegex(kind.open)
            let leaf = "matches('aaaa', '\(regex)')"
            let close = String(repeating: ")", count: outer)
            let shapes = [
                String(repeating: "max(", count: outer) + leaf + close,     // A: function + argument
                String(repeating: "max(1, ", count: outer) + leaf + close,  // B: second argument
                String(repeating: "(", count: outer) + leaf + close,        // C: parentheses
                String(repeating: "max(", count: outer - 1)                  // D: matches inside matches
                    + "matches(matches('aaaa', '\(regex)'), '\(regex)')"
                    + String(repeating: ")", count: outer - 1),
            ]
            for (index, shape) in shapes.enumerated() {
                let value = try await Self.evalOnSmallStack(shape).get()
                #expect(value == kind.results[index], "\(kind.open) tvar \(index)")
            }
            // One level deeper it is an error, not a crash.
            let over = "max(" + shapes[0] + ")"
            let result = await Self.evalOnSmallStack(over)
            #expect(throws: ExpressionError(
                kind: .nestingTooDeep, message: "Příliš hluboké zanoření ve výrazu: " + over)) {
                try result.get()
            }
        }
    }
}
