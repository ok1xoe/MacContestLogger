import Foundation

/// Loads a `MultiplierSetDefinition` from YAML.
///
/// Port of Java `multiplier/MultiplierSetLoader.java` (Jackson
/// `readValue(in, MultiplierSetDefinition.class)`); type conversion is done by the strict
/// `YamlDecoder`, so a type error deep in the definition rejects the whole file
/// with line and column like Java.
///
/// A difference from Java in one place only, per plan decision no. 3: Java returns a
/// `~`/`---` document as `null` and only the registry crashes (`NullPointerException`);
/// here it throws `MultiplierError.emptyDefinition` right away. The external consequence is the same.
public enum MultiplierSetLoader {

    /// Java `load(InputStream)`.
    ///
    /// - Throws: `MultiplierError.invalidDefinition` (invalid UTF-8 — always at 1:1,
    ///   which matches Java only up to ~1 kB, see below —, a syntax or type error,
    ///   empty input — Java: "Nelze načíst definici sady: …"),
    ///   `MultiplierError.emptyDefinition` (`null` root).
    public static func load(_ data: Data) throws(MultiplierError) -> MultiplierSetDefinition {
        // A leading BOM is stripped explicitly (like SnakeYAML), not by Foundation.
        guard let text = Utf8Text.decodeStrippingBom(data) else {
            // Swift decodes the whole file up front and always reports 1:1. Java decodes
            // as a stream in ~1 kB chunks: an invalid byte in the first chunk also gives 1:1, but further
            // into the file a different position, or it hits a type error
            // before the invalid byte — a deliberate divergence from
            // Java v1.1.1, pinned in `MultiplierSetLoaderTests.invalidUtf8PastFirstKilobyte`.
            throw .invalidDefinition(YamlError(kind: .syntax, message: "vstup není platné UTF-8",
                                               line: 1, column: 1))
        }
        let definition: MultiplierSetDefinition?
        do {
            definition = try YamlDecoder.decode(MultiplierSetDefinition.self, from: text)
        } catch let error as YamlError {
            throw .invalidDefinition(error)
        } catch {
            throw .failure("Nelze načíst definici sady: \(error)")
        }
        guard let definition else { throw .emptyDefinition }
        return definition
    }

    /// Java `loadFile(Path)`.
    ///
    /// An error **opening** the file → `failure("Nelze načíst sadu: <path>")`.
    /// An error **reading** an opened file (a directory `d.yaml` opens in Java
    /// and only `read` inside `load` fails) → `failure("Nelze načíst definici
    /// sady: …")`. Errors from `load` pass through unchanged (in Java they are not
    /// `IOException`, so `loadFile` does not rewrap them).
    public static func loadFile(_ url: URL) throws(MultiplierError) -> MultiplierSetDefinition {
        // Path as a Java `Path`: a relative one stays relative, `..` is not resolved.
        try loadFile(at: RawPath(RawFileSystem.javaPath(of: url)))
    }

    /// `loadFile` over the raw path bytes (from `readdir` in `loadDir`).
    static func loadFile(at path: RawPath) throws(MultiplierError) -> MultiplierSetDefinition {
        // POSIX `open` like Java `Files.newInputStream`: a directory opens
        // and only the read fails.
        switch RawFileSystem.readFile(path) {
        case .openFailed:
            throw .failure("Nelze načíst sadu: " + path.display)
        case .readFailed(let reason):
            // Java: "Nelze načíst definici sady: java.io.IOException: Is a directory"
            throw .failure("Nelze načíst definici sady: " + reason)
        case .data(let data):
            return try load(data)
        }
    }
}
