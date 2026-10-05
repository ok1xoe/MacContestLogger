/// Exchange parse error. Neither Java `ExchangeEngine` nor `ExchangeGrab` catches it — it propagates to the UI.
/// `message` is verbatim Java `getMessage()`.
public struct ExchangeError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable {
        /// `NumberFormatException` from `Integer.parseInt` in a numeric field above 2³¹−1
        /// („For input string: "2147483648"“).
        case numberFormat
        /// `PatternSyntaxException` from a syntactically broken `validation.regex` in `ExchangeGrab.route`
        /// (there Java does not swallow it); `message` is Java `getMessage()` including the caret line.
        case patternSyntax
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var description: String { message }
}

/// Handler of one exchange field type — parsing and normalization. Port of Java
/// `exchange/ExchangeFieldHandler.java`. The handler registry in `ExchangeEngine` is an extension point:
/// a new type = a new handler, a new contest just composes existing types through configuration.
///
/// The Java default method `format(ExchangeValue)` is dead code (nobody calls it) and is not ported.
public protocol ExchangeFieldHandler: Sendable {

    /// Parses and type-validates the input (without applying `field.validation`).
    func parse(_ raw: String?) throws(ExchangeError) -> ExchangeValue
}
