import Foundation

/// N1MM „Edit Section List" / „Import Section List" in the contest dialog: the list (`CODE,Name` lines) of a
/// multiplier set the contest uses, edited in place. The first save keeps the shipped list as `<set>.csv.orig`;
/// restoring puts it back. The definition updater does not overwrite an edited list (its hash differs).
public enum SectionListFile {

    public struct Failure: Error, Equatable, Sendable {
        public let message: String
    }

    /// The sets of the definition's multipliers whose values are a CSV file in `dir` (`valuesFile`), in order.
    public static func editableSets(_ definition: ContestDefinition?, multipliersDir dir: URL) -> [String] {
        var out: [String] = []
        for binding in definition?.multipliers ?? [] {
            guard let id = binding?.set, !out.contains(id), csvURL(id, dir) != nil else { continue }
            out.append(id)
        }
        return out
    }

    /// The set's CSV file (`valuesFile` of `<id>.yaml`), `nil` = not a CSV-backed set in `dir`.
    static func csvURL(_ setId: String, _ dir: URL) -> URL? {
        let yaml: URL = dir.appendingPathComponent(setId + ".yaml")
        guard FileManager.default.fileExists(atPath: yaml.path),
              let definition = try? MultiplierSetLoader.loadFile(yaml),
              let file = definition.valuesFile, !KotlinText.isBlank(file), !file.contains("/") else { return nil }
        let csv: URL = dir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: csv.path) ? csv : nil
    }

    /// The list as `CODE,Name` lines (comments dropped).
    public static func read(_ setId: String, multipliersDir dir: URL) throws(Failure) -> String {
        guard let csv = csvURL(setId, dir), let data = FileManager.default.contents(atPath: csv.path),
              let text = String(data: data, encoding: .utf8) else {
            throw Failure(message: setId)
        }
        let values = MultiplierSetRegistry.parseCsv(text)
        return values.map { ($0.key ?? "") + "," + ($0.label ?? "") }.joined(separator: "\n") + "\n"
    }

    /// Writes the edited list (parsed like a county import: `CODE,Name`, `;`, tab or space). Returns the number of
    /// entries; an empty list is refused.
    @discardableResult
    public static func save(_ setId: String, text: String, multipliersDir dir: URL) throws(Failure) -> Int {
        guard let csv = csvURL(setId, dir) else { throw Failure(message: setId) }
        let lines: [String] = text.components(separatedBy: .newlines)
        let values = CountyListImport.parse(lines)
        guard !values.isEmpty else { throw Failure(message: setId) }
        let backup: URL = backupURL(csv)
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: csv, to: backup)
            }
            var body = "# " + setId + " (key,label) — edited in the contest dialog\n"
            for value in values {
                body += value.code + "," + value.label + "\n"
            }
            try Data(body.utf8).write(to: csv, options: .atomic)
        } catch {
            throw Failure(message: csv.lastPathComponent + ": " + error.localizedDescription)
        }
        return values.count
    }

    /// Has the list been edited (a shipped copy is kept)?
    public static func hasBackup(_ setId: String, multipliersDir dir: URL) -> Bool {
        guard let csv = csvURL(setId, dir) else { return false }
        return FileManager.default.fileExists(atPath: backupURL(csv).path)
    }

    /// Puts the shipped list back; `false` when it was never edited.
    @discardableResult
    public static func restore(_ setId: String, multipliersDir dir: URL) throws(Failure) -> Bool {
        guard let csv = csvURL(setId, dir) else { return false }
        let backup: URL = backupURL(csv)
        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.path) else { return false }
        do {
            _ = try fm.replaceItemAt(csv, withItemAt: backup)
        } catch {
            throw Failure(message: csv.lastPathComponent + ": " + error.localizedDescription)
        }
        return true
    }

    private static func backupURL(_ csv: URL) -> URL {
        csv.deletingLastPathComponent().appendingPathComponent(csv.lastPathComponent + ".orig")
    }
}
