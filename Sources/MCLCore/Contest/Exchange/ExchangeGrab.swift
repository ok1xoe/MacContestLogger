/// Where a word picked from decoded text belongs (Digital Interface, N1MM „grab"). Port of Java
/// `exchange/ExchangeGrab.java`. Decided by the contest definition: first `validation` from YAML, then the shape
/// by field type. Of several matching fields the first empty one wins — a half-typed exchange is thus
/// not overwritten by a click while there is somewhere to write.
///
/// Java properties that are copied (table `GrabMeasured`, maintainer-only probe):
/// - `normalize`: first `toUpperCase()`, then Java `trim()`, then from both ends by UTF-16
///   units characters are cut off that are not a letter/digit (`Character.isLetterOrDigit`), `/` or `-`;
/// - `accepts` is evaluated **for all fields** (Java `toList()` is eager), so a syntactically
///   broken `validation.regex` of any field **throws** (`ExchangeError.patternSyntax`, Java's
///   uncaught `PatternSyntaxException`) — unlike `ExchangeEngine`, which swallows it;
/// - order of checks `regex` (whole string) → `length` (UTF-16) → `min`/`max` (`Integer.valueOf`) → the type's shape;
/// - emptiness of a value in `current` is Java `isBlank()` (NBSP and U+0001 are not blank).
///
/// Leniency versus Java (a deliberate divergence from Java v1.1.1): a `nil` element of the fields is skipped and a field
/// with `type == nil` accepts nothing (Java NPE); a regex that the `JavaRegex` adapter does not convert is ignored.
/// `current` is a Java `HashMap` — `route` only reads from it, the iteration order does not leak into the result.
public enum ExchangeGrab {

    /// Where and what to insert. Equality like a Java record: texts by UTF-16.
    public struct Grab: Equatable, Sendable {
        public let fieldId: String?
        public let value: String

        public init(fieldId: String?, value: String) {
            self.fieldId = fieldId
            self.value = value
        }

        public static func == (lhs: Grab, rhs: Grab) -> Bool {
            let sameId = lhs.fieldId.map { JavaText.equals($0, rhs.fieldId) } ?? (rhs.fieldId == nil)
            return sameId && JavaText.equals(lhs.value, rhs.value)
        }
    }

    /// - Parameters:
    ///   - fields: received exchange fields by the contest definition (`nil` → no grab)
    ///   - current: typed values (id → value)
    ///   - token: the word from the decoded text
    public static func route(_ fields: [ContestDefinition.ExchangeField?]?, _ current: JavaLinkedMap<String>,
                             _ token: String?) throws(ExchangeError) -> Grab? {
        let value = normalize(token)
        guard !value.isEmpty, let fields else {
            return nil
        }
        var accepting: [ContestDefinition.ExchangeField] = []
        for field in fields {
            guard let field else { continue }   // Java NPE — a recorded leniency
            if try accepts(field, value) {
                accepting.append(field)
            }
        }
        let chosen = accepting.first { isBlank(current[$0.id]) } ?? accepting.first
        return chosen.map { Grab(fieldId: $0.id, value: value) }
    }

    /// Trims surrounding punctuation and uppercases; if only junk remains, returns empty.
    static func normalize(_ token: String?) -> String {
        guard let token else {
            return ""
        }
        let units = Array(JavaText.trim(token.uppercased()).utf16)
        var from = 0
        var to = units.count
        while from < to && !isValueChar(units[from]) {
            from += 1
        }
        while to > from && !isValueChar(units[to - 1]) {
            to -= 1
        }
        // At the edge of the result there is always a letter/digit, `/` or `-`, never half of a surrogate pair.
        return JavaChar.string(Array(units[from..<to]))
    }

    private static func isValueChar(_ unit: UInt16) -> Bool {
        JavaChar.isLetterOrDigit(unit) || unit == 0x2F || unit == 0x2D   // '/' '-'
    }

    private static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return JavaText.isBlank(text)
    }

    private static func accepts(_ field: ContestDefinition.ExchangeField, _ value: String) throws(ExchangeError) -> Bool {
        if let rule = field.validation {
            if let regex = rule.regex {
                // Java `value.matches(regex)` = `Pattern.compile` on every call; here
                // from the shared cache (`JavaRegexCache`), the result and the error are the same.
                let pattern: JavaRegex?
                do throws(JavaRegexError) {
                    pattern = try JavaRegexCache.shared.regex(regex)
                } catch {
                    guard error.kind == .unsupported else {
                        throw ExchangeError(kind: .patternSyntax, message: error.message)
                    }
                    pattern = nil   // Java translates and uses the pattern — a recorded divergence
                }
                if let pattern, !pattern.matches(value) {
                    return false
                }
            }
            if let length = rule.length, value.utf16.count != length {
                return false
            }
            if rule.min != nil || rule.max != nil {
                guard let number = JavaInteger.parseInt(value) else {
                    return false
                }
                if let min = rule.min, Int(number) < min {
                    return false
                }
                if let max = rule.max, Int(number) > max {
                    return false
                }
            }
        }
        return matchesType(field.type, value)
    }

    private static func fixed(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor '\(pattern)' musí jít zkompilovat: \(error)")
        }
    }

    private static let rst = fixed("[1-5][1-9][1-9]")
    private static let rs = fixed("[1-5][1-9]")
    private static let number = fixed("\\d{1,4}")
    private static let locator = fixed("[A-R]{2}\\d{2}([A-X]{2})?")
    private static let iota = fixed("[A-Z]{2}-?\\d{1,3}")
    private static let state = fixed("[A-Z]{1,4}")
    private static let alnum = fixed("[A-Z0-9]{1,6}")
    private static let hasLetter = fixed(".*[A-Z].*")
    private static let text = fixed("[A-Z0-9/\\-]{1,10}")

    /// Rough shape of a value by field type — so that a number does not fall into a state and vice versa.
    /// All Java `String.matches` (whole string, ASCII classes). `type == nil` is an NPE in Java.
    private static func matchesType(_ type: ContestDefinition.FieldType?, _ value: String) -> Bool {
        switch type {
        case nil: false
        case .RST: rst.matches(value)
        case .RS: rs.matches(value)
        case .SERIAL, .INTEGER, .CQ_ZONE, .ITU_ZONE: number.matches(value)
        case .LOCATOR: locator.matches(value)
        case .IOTA: iota.matches(value)
        // State/province are letter abbreviations — otherwise every number would fall into them.
        case .STATE, .PROVINCE: state.matches(value)
        case .NATIONAL, .HQ, .DXCC, .PREFIX: alnum.matches(value) && hasLetter.matches(value)
        case .DISTRICT: alnum.matches(value)
        case .TEXT: text.matches(value)
        case .QTC: false
        }
    }
}
