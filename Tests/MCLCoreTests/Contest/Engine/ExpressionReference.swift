@testable import MCLCore

/// The original Java evaluator **during parsing** (the earlier state), copied here
/// unchanged as a reference: the compiled `Expression` tree must on any text
/// give the same value (bit for bit) or the same error (kind and text) — see `ExpressionProgramTests`.
enum ExpressionReference {
    static let maxNestingDepth = Expression.maxNestingDepth

    static func eval(_ expression: String?,
                     _ variables: JavaLinkedMap<ExpressionValue>) throws(ExpressionError) -> Double {
        guard let expression, !JavaText.isBlank(expression) else { return 0 }
        var parser = Parser(source: expression, variables: variables)
        let result = try parser.parseOr()
        parser.skipWhitespace()
        if parser.position < parser.units.count {
            throw ExpressionError(kind: .illegalArgument, message: "Neočekávaný znak ve výrazu: " + expression)
        }
        return number(result)
    }

    static func number(_ value: ExpressionValue) -> Double { Expression.number(value) }
    static func text(_ value: ExpressionValue) -> String { Expression.text(value) }
    static func equal(_ left: ExpressionValue, _ right: ExpressionValue) -> Bool { Expression.equal(left, right) }
    static func truthy(_ value: ExpressionValue) -> Bool { Expression.truthy(value) }
    static func bool(_ flag: Bool) -> ExpressionValue { Expression.bool(flag) }

    struct Parser {
        let source: String
        let units: [UInt16]
        let variables: JavaLinkedMap<ExpressionValue>
        var position = 0
        var depth = 0

        init(source: String, variables: JavaLinkedMap<ExpressionValue>) {
            self.source = source
            self.units = Array(source.utf16)
            self.variables = variables
        }

        mutating func parseOr() throws(ExpressionError) -> ExpressionValue {
            var value = try parseAnd()
            while true {
                skipWhitespace()
                guard peekOperator(0x7C, 0x7C) else { return value } // ||
                position += 2
                let right = try parseAnd()
                value = bool(truthy(value) || truthy(right))
            }
        }

        mutating func parseAnd() throws(ExpressionError) -> ExpressionValue {
            var value = try parseComparison()
            while true {
                skipWhitespace()
                guard peekOperator(0x26, 0x26) else { return value } // &&
                position += 2
                let right = try parseComparison()
                value = bool(truthy(value) && truthy(right))
            }
        }

        /// At most one comparison (`1 < 2 < 3` ends in "Neočekávaný znak").
        mutating func parseComparison() throws(ExpressionError) -> ExpressionValue {
            let value = try parseAdd()
            skipWhitespace()
            if peekOperator(0x3D, 0x3D) { // ==
                position += 2
                return bool(equal(value, try parseAdd()))
            }
            if peekOperator(0x21, 0x3D) { // !=
                position += 2
                return bool(!equal(value, try parseAdd()))
            }
            if peekOperator(0x3C, 0x3D) { // <=
                position += 2
                return bool(number(value) <= number(try parseAdd()))
            }
            if peekOperator(0x3E, 0x3D) { // >=
                position += 2
                return bool(number(value) >= number(try parseAdd()))
            }
            if peek(0x3C) { // <
                position += 1
                return bool(number(value) < number(try parseAdd()))
            }
            if peek(0x3E) { // >
                position += 1
                return bool(number(value) > number(try parseAdd()))
            }
            return value
        }

        mutating func parseAdd() throws(ExpressionError) -> ExpressionValue {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if peek(0x2B) { // +
                    position += 1
                    let left = number(value)
                    value = .number(left + number(try parseTerm()))
                } else if peek(0x2D) { // -
                    position += 1
                    let left = number(value)
                    value = .number(left - number(try parseTerm()))
                } else {
                    return value
                }
            }
        }

        mutating func parseTerm() throws(ExpressionError) -> ExpressionValue {
            var value = try parseUnary()
            while true {
                skipWhitespace()
                if peek(0x2A) { // *
                    position += 1
                    let left = number(value)
                    value = .number(left * number(try parseUnary()))
                } else if peek(0x2F) { // /
                    position += 1
                    let divisor = number(try parseUnary())
                    // Java: a divisor of 0 (also −0, also invalid text) gives 0.0, not ∞/NaN.
                    value = .number(divisor == 0 ? 0.0 : number(value) / divisor)
                } else {
                    return value
                }
            }
        }

        mutating func parseUnary() throws(ExpressionError) -> ExpressionValue {
            skipWhitespace()
            if peek(0x2D) { // -
                position += 1
                try enter()
                defer { depth -= 1 }
                // Java `dneg` only flips the sign bit, even for NaN (`-NaN` → `fff8…`).
                // Swift unary minus does not guarantee that on an older toolchain (CI, Xcode 16) for NaN
                // and returns the canonical `7ff8…`, so we flip the bit by hand.
                let operand = number(try parseUnary())
                return .number(Double(bitPattern: operand.bitPattern ^ (1 << 63)))
            }
            if peek(0x21) { // !
                position += 1
                try enter()
                defer { depth -= 1 }
                return bool(!truthy(try parseUnary()))
            }
            return try parseFactor()
        }

        mutating func parseFactor() throws(ExpressionError) -> ExpressionValue {
            skipWhitespace()
            if peek(0x28) { // (
                position += 1
                let value = try nestedOr()
                skipWhitespace()
                try expectClosingParen()
                return value
            }
            let unit = try current()
            if unit == 0x27 { // '
                return try parseString()
            }
            if JavaChar.isDigit(unit) || unit == 0x2E {
                return try parseNumber()
            }
            if JavaChar.isLetter(unit) || unit == 0x5F {
                return try parseIdentifierOrFunction()
            }
            throw illegal("Neplatný znak '" + JavaChar.string([unit]) + "' ve výrazu: " + source)
        }

        mutating func parseString() throws(ExpressionError) -> ExpressionValue {
            position += 1 // opening '
            let start = position
            while position < units.count && units[position] != 0x27 {
                position += 1
            }
            if position >= units.count {
                throw illegal("Neuzavřený řetězec ve výrazu: " + source)
            }
            let text = JavaChar.string(Array(units[start..<position]))
            position += 1 // closing '
            return .text(text)
        }

        mutating func parseNumber() throws(ExpressionError) -> ExpressionValue {
            let start = position
            while position < units.count && (JavaChar.isDigit(units[position]) || units[position] == 0x2E) {
                position += 1
            }
            do {
                return .number(try JavaDouble.parse(JavaChar.string(Array(units[start..<position]))))
            } catch {
                throw ExpressionError(kind: .numberFormat, message: error.message)
            }
        }

        mutating func parseIdentifierOrFunction() throws(ExpressionError) -> ExpressionValue {
            let start = position
            while position < units.count {
                let unit = units[position]
                guard JavaChar.isLetterOrDigit(unit) || unit == 0x5F || unit == 0x2E else { break }
                position += 1
            }
            let name = JavaChar.string(Array(units[start..<position]))
            skipWhitespace()
            guard peek(0x28) else { return variable(name) }
            position += 1
            // Both arguments are evaluated before the name is checked (as in Java);
            // without a second argument the second equals the first.
            let first = try nestedOr()
            var second = first
            skipWhitespace()
            if peek(0x2C) { // ,
                position += 1
                second = try nestedOr()
            }
            skipWhitespace()
            try expectClosingParen()
            switch name {
            case "min": return .number(JavaMath.min(number(first), number(second)))
            case "max": return .number(JavaMath.max(number(first), number(second)))
            case "round": return .number(Double(JavaMath.round(number(first))))
            case "floor": return .number(number(first).rounded(.down))
            case "ceil": return .number(number(first).rounded(.up))
            case "matches": return bool(try find(pattern: text(second), in: text(first)))
            default: throw illegal("Neznámá funkce: " + name)
            }
        }

        /// Java `vars.get(name)`, missing (also `null`) = 0.0. `JavaLinkedMap` looks up by
        /// UTF-16 like a Java map (`Å` U+00C5 ≠ U+212B), not canonically like a Swift dictionary.
        func variable(_ name: String) -> ExpressionValue {
            variables[name] ?? .number(0)
        }

        /// `Pattern.compile(pattern).matcher(text).find()`. The compiled pattern (and the compile error)
        /// is taken from the shared `JavaRegexCache` — the result is the same as compiling every time.
        func find(pattern: String, in text: String) throws(ExpressionError) -> Bool {
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

        // MARK: helpers

        /// `parseOr` one level deeper (a parenthesis, a function argument).
        mutating func nestedOr() throws(ExpressionError) -> ExpressionValue {
            try enter()
            defer { depth -= 1 }
            return try parseOr()
        }

        mutating func enter() throws(ExpressionError) {
            if depth >= maxNestingDepth {
                throw ExpressionError(kind: .nestingTooDeep, message: "Příliš hluboké zanoření ve výrazu: " + source)
            }
            depth += 1
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

        func current() throws(ExpressionError) -> UInt16 {
            if position >= units.count {
                throw illegal("Neočekávaný konec výrazu: " + source)
            }
            return units[position]
        }

        mutating func expectClosingParen() throws(ExpressionError) {
            if !peek(0x29) {
                throw illegal("Očekáváno ')' ve výrazu: " + source)
            }
            position += 1
        }

        func illegal(_ message: String) -> ExpressionError {
            ExpressionError(kind: .illegalArgument, message: message)
        }
    }
}
