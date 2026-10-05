import Foundation

/// Loads a `ContestDefinition` from YAML. Ignores unknown keys (forward
/// compatibility); version migrations do not exist yet, only `schemaVersion` is checked.
///
/// Port of Java `contest/def/ContestDefinitionLoader.java` (Jackson
/// `readValue(in, ContestDefinition.class)` + `checkVersion`). Type conversion is done by the
/// strict `YamlDecoder`, so a type error deep in the definition rejects the whole
/// file with a line and column like Java.
///
/// `loadResource` (classpath) is not ported — nobody calls it in production.
public enum ContestDefinitionLoader {

    /// Currently supported DSL schema version.
    public static let currentSchemaVersion = 1

    /// Java `load(InputStream)`.
    ///
    /// - Throws: `.invalidDefinition` (a syntax or type error, empty
    ///   input, broken UTF-8 — always at 1:1, which matches Java only up to ~1 kB,
    ///   see `MultiplierSetLoader.load`), `.emptyDefinition` (root `~`/`---`,
    ///   Java NPE), `.newerSchema` (`schemaVersion > 1`).
    public static func load(_ data: Data) throws(ContestDefinitionError) -> ContestDefinition {
        // A leading BOM is stripped explicitly as in SnakeYAML (measured:
        // `\u{FEFF}id: t` + a type error on line 2 → Java 2:15, columns without the BOM).
        guard let text = Utf8Text.decodeStrippingBom(data) else {
            // Swift decodes the whole file up front and always reports 1:1; Java decodes
            // in a stream by ~1 kB — a deliberate divergence from
            // Java v1.1.1 (like `MultiplierSetLoader.load`).
            throw .invalidDefinition(YamlError(kind: .syntax, message: "vstup není platné UTF-8",
                                               line: 1, column: 1))
        }
        let definition: ContestDefinition?
        do {
            definition = try YamlDecoder.decode(ContestDefinition.self, from: text)
        } catch let error as YamlError {
            throw .invalidDefinition(error)
        } catch {
            throw .failure("Nelze načíst definici závodu: \(error)")
        }
        // Java: `readValue` returns `null` and `checkVersion` crashes with an NPE
        // (plan decision no. 3: Swift throws right away, the outward consequence is the same).
        guard let definition else { throw .emptyDefinition }
        // `checkVersion`: only a higher version is an error; a lower, 0 and a negative one pass.
        if definition.schemaVersion > currentSchemaVersion {
            throw .newerSchema(definition.schemaVersion)
        }
        return definition
    }

    /// Java `loadFile(Path)`.
    ///
    /// An **open** error (missing file, dead link) → `failure("Nelze
    /// načíst definici: <path>")`, the path as it was passed. A **read** error
    /// (directory `d.yaml`) → `failure("Nelze načíst definici závodu: Is a
    /// directory")` — in Java Jackson reports it inside `load`. Errors from `load`
    /// pass through unchanged.
    public static func loadFile(_ url: URL) throws(ContestDefinitionError) -> ContestDefinition {
        try loadFile(at: RawPath(RawFileSystem.javaPath(of: url)))
    }

    /// `loadFile` over the raw bytes of the path (from `readdir` in the catalog).
    static func loadFile(at path: RawPath) throws(ContestDefinitionError) -> ContestDefinition {
        switch RawFileSystem.readFile(path) {
        case .openFailed:
            throw .failure("Nelze načíst definici: " + path.display)
        case .readFailed(let reason):
            // Java: „Nelze načíst definici závodu: java.io.IOException: Is a directory"
            throw .failure("Nelze načíst definici závodu: " + reason)
        case .data(let data):
            return try load(data)
        }
    }
}
