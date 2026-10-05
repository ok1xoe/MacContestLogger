import Foundation

/// Error while loading a contest definition.
///
/// Port of Java `contest/def/ContestDefinitionException.java` — but **not only
/// of it**, because the catalog skips every `RuntimeException` and the warning text depends
/// on what the loader throws (baseline 3.2–3.4):
/// - `failure`, `invalidDefinition`, `newerSchema` = Java
///   `ContestDefinitionException`,
/// - `emptyDefinition` = Java `NullPointerException`: for a `~`/`---` document
///   Jackson returns `null` and only `checkVersion` crashes (plan decision no. 3 —
///   Swift throws right away, the outward consequence is the same: the loader fails, the catalog skips
///   the file).
public enum ContestDefinitionError: Error, Equatable, Sendable, CustomStringConvertible {

    /// `ContestDefinitionException(message)` — a ready-made Czech message as in Java
    /// („Nelze načíst definici: <path>", „Nelze projít adresář závodů: <path>"…).
    case failure(String)

    /// `ContestDefinitionException("Nelze načíst definici závodu: " + …)`
    /// with a YAML cause (a syntax or type error, empty input, broken
    /// UTF-8). Positions match Java, the text is Czech (a deliberate divergence
    /// from Java v1.1.1).
    case invalidDefinition(YamlError)

    /// The document root is `null` (`~`, a bare `---`). Java: `NullPointerException`
    /// in `checkVersion`.
    case emptyDefinition

    /// `schemaVersion` higher than supported (`checkVersion`). A lower, zero
    /// or negative version passes — only the validator rejects it.
    case newerSchema(Int)

    /// Error text as Java shows it (for `invalidDefinition` with a Czech cause).
    public var message: String {
        switch self {
        case .failure(let message):
            return message
        case .invalidDefinition(let cause):
            return "Nelze načíst definici závodu: " + cause.description
        case .emptyDefinition:
            return "definice je prázdná"
        case .newerSchema(let version):
            return "Novější formát definice (schemaVersion=\(version)), aktualizuj aplikaci. Podporováno: "
                + String(ContestDefinitionLoader.currentSchemaVersion)
        }
    }

    public var description: String { message }
}
