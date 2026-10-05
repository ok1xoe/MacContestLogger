import Foundation

/// Error while reading YAML. It always carries a position in the text (line and
/// column, both 1-based) so the user knows where to look in the file.
///
/// The reader never swallows a construct it does not understand: it either
/// returns the whole document or throws this error. A half-built tree would only
/// show up later as a wrong contest score.
public struct YamlError: Error, Sendable, Equatable, CustomStringConvertible {

    /// Druh chyby.
    ///
    /// - `syntax`: malformed YAML — missing separator, mismatched indentation,
    ///   unterminated quotes…
    /// - `unsupported`: a construct our YAML subset **deliberately** does not
    ///   support (anchors, aliases, block scalars, multiple documents…).
    ///
    /// - `type`: the YAML is fine, but the value cannot be read as the type the
    ///   caller expects (`scope: per_band`, `required: ano`, `bands: 20m`).
    ///   Reported by `YamlDecoder`, never by the parser — in Java this is the
    ///   mapping layer (`JsonMappingException`), not SnakeYAML.
    ///
    /// The distinction lets the caller tell "the file is broken" from "the file
    /// uses something we do not support" — different advice for the user.
    public enum Kind: String, Sendable, Equatable {
        case syntax
        case unsupported
        case type
    }

    public let kind: Kind
    /// Description in Czech, without the position — `description` adds that.
    public let message: String
    /// Line, 1-based.
    public let line: Int
    /// Column, 1-based.
    public let column: Int

    public init(kind: Kind = .syntax, message: String, line: Int, column: Int) {
        self.kind = kind
        self.message = message
        self.line = line
        self.column = column
    }

    public var description: String {
        let uvod: String
        switch kind {
        case .syntax: uvod = "Chyba YAML"
        case .unsupported: uvod = "Nepodporovaná konstrukce YAML"
        case .type: uvod = "Chybný typ hodnoty v YAML"
        }
        return "\(uvod) (řádek \(line), sloupec \(column)): \(message)"
    }
}
