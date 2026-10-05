import Foundation
import os

/// Catalog of contest definitions loaded from an external directory (each `*.yaml`).
/// The directory path is configurable in Settings; the definitions are not part of
/// the application.
///
/// Port of Java `contest/def/ContestCatalog.java` (baseline 3.4). Unlike
/// the set registry it **isolates errors**: a file that fails to load is skipped,
/// logged and loading continues. It also copies Java's properties:
/// - files non-recursively, **including hidden ones** (`.x.yaml` is loaded, AppleDouble
///   `._x.yaml` from a FAT/SMB disk is skipped as unreadable), the `.yaml` filter
///   case-sensitive, order **by bytes** of the name (`B.yaml` before
///   `a.yaml`) — the listing is shared with the registry via `RawFileSystem`,
/// - it does not validate (`ContestValidator` is not called): "invalid" = unreadable,
///   unparsable, empty (`~`) or a newer version,
/// - a duplicate `id` in two files → both definitions are in the list.
public enum ContestCatalog {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "ContestCatalog")

    /// Java `fromDir(Path)`: definitions from the directory in file order.
    /// `nil`, a nonexistent path or a file → an empty list; a file that
    /// fails to load is skipped with a warning in the log (Java `System.Logger` WARNING).
    ///
    /// - Throws: `.failure("Nelze projít adresář závodů: <dir>")` when the directory
    ///   cannot be walked (Java `Files.list` → `IOException`).
    public static func fromDir(_ url: URL?) throws(ContestDefinitionError) -> [ContestDefinition] {
        try fromDir(url) { path, error in
            log.warning("\(skipMessage(path: path, error: error), privacy: .public)")
        }
    }

    /// `fromDir` with a custom receiver of skipped files (the path as
    /// Java prints it, and the reason) — for tests.
    static func fromDir(_ url: URL?,
                        onSkip: (_ path: String, _ error: ContestDefinitionError) -> Void)
        throws(ContestDefinitionError) -> [ContestDefinition] {
        guard let url else { return [] }
        // The path as Java received it (a relative one stays relative).
        let dirPath = RawFileSystem.javaPath(of: url)
        guard RawFileSystem.isDirectory(dirPath) else { return [] }
        guard let files = RawFileSystem.yamlFiles(in: dirPath) else {
            throw .failure("Nelze projít adresář závodů: " + dirPath)
        }
        var out: [ContestDefinition] = []
        for file in files {
            do {
                // Raw bytes of the name all the way to `open()` — without `URL`, which would convert them to NFD.
                out.append(try ContestDefinitionLoader.loadFile(at: file))
            } catch {
                // Java catches `RuntimeException` — including an NPE from the `~` document.
                onSkip(file.display, error)
            }
        }
        return out
    }

    /// Warning text as in Java: „Přeskakuji nevalidní definici <p>: <msg>".
    static func skipMessage(path: String, error: ContestDefinitionError) -> String {
        "Přeskakuji nevalidní definici " + path + ": " + error.message
    }
}
