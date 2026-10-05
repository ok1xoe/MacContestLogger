import Foundation

/// Manages the directory of named database files (`{name}.sqlite`)
/// from which the operator picks a logbook. Corresponds to Java `DatabaseCatalog`.
public final class DatabaseCatalog {

    private static let defaultName = "Deník"
    private static let suffix = ".sqlite"

    private let dir: URL

    /// Opens the catalog over the given directory; creates the directory if it does not exist yet.
    public init(databasesDir: URL) throws {
        self.dir = databasesDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw LogbookError("Nelze vytvořit adresář databází: \(dir.path) (\(error))")
        }
    }

    /// Database names (without the `.sqlite` extension), sorted. The criterion is purely by
    /// file name — just as Java does not check that it is a regular file
    /// or that it contains a valid SQLite database; a subdirectory or symlink named
    /// `x.sqlite` thus shows up too.
    public func list() throws -> [String] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        } catch {
            throw LogbookError("Nelze vypsat databáze v \(dir.path): \(error)")
        }
        return names
            .filter { $0.hasSuffix(Self.suffix) }
            .map { String($0.dropLast(Self.suffix.count)) }
            .sorted()
    }

    /// Path to the database file of the given name (only composes the path, verifies nothing).
    public func pathFor(_ name: String) -> URL {
        dir.appendingPathComponent(name + Self.suffix)
    }

    /// Creates an empty DB (the schema is created by `LogbookRepository`) and returns its path.
    @discardableResult
    public func create(_ name: String) throws -> URL {
        let path = pathFor(name)
        let repository = try LogbookRepository(url: path)
        repository.close()
        return path
    }

    /// Ensures the default DB „Deník" (creates it if missing) and returns its name.
    /// It never overwrites an existing database — existence is checked before
    /// calling `create`.
    @discardableResult
    public func ensureDefault() throws -> String {
        if !FileManager.default.fileExists(atPath: pathFor(Self.defaultName).path) {
            try create(Self.defaultName)
        }
        return Self.defaultName
    }
}
