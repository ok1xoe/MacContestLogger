import Foundation

/// Error while loading or building a multiplier set.
///
/// Port of Java `multiplier/MultiplierException.java` — but **not only of it**.
/// The Java package does not funnel everything through `MultiplierException` and the contract
/// "what kills `loadDir`" must match (1.5):
/// - `failure` and `invalidDefinition` = Java `MultiplierException`,
/// - `emptyDefinition` = Java `NullPointerException`: the loader returns `null` for a
///   `~`/`---` document and the registry crashes on it (plan decision no. 3 —
///   Swift throws already in the loader, with the same external consequence),
/// - `invalidPattern` = Java `PatternSyntaxException` from the `FixedMultiplierSet`
///   constructor (`Pattern.compile` of a faulty `keyPattern`).
public enum MultiplierError: Error, Equatable, Sendable, CustomStringConvertible {

    /// `MultiplierException(message)` — a ready-made Czech message as in Java
    /// ("Nelze načíst sadu: <path>", "sada 'x' nemá kind"…).
    case failure(String)

    /// `MultiplierException("Nelze načíst definici sady: " + …)` with a YAML cause.
    /// Position (line, column) matches Java, the text is Czech (a deliberate divergence
    /// from Java v1.1.1).
    case invalidDefinition(YamlError)

    /// The document root is `null` (`~`, a bare `---`). Java: `load` returns `null`,
    /// the registry crashes with `NullPointerException`.
    case emptyDefinition

    /// Faulty `keyPattern` (`PatternSyntaxException` from the constructor). For syntax errors `message`
    /// is verbatim Java `getMessage()`; for constructs
    /// that the `JavaRegex` adapter rejects, it is Czech (a deliberate divergence from Java v1.1.1).
    case invalidPattern(pattern: String, message: String)

    /// Error text as Java shows it (for `invalidDefinition` with a Czech cause).
    public var message: String {
        switch self {
        case .failure(let message):
            return message
        case .invalidDefinition(let cause):
            return "Nelze načíst definici sady: " + cause.description
        case .emptyDefinition:
            return "definice je prázdná"
        case .invalidPattern(_, let message):
            return message
        }
    }

    public var description: String { message }
}
