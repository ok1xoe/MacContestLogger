import Foundation

/// N1MM „Import country list from downloaded file": a `cty.dat` (AD1C / country-files.com format, e.g. a contest's
/// own `wl_cty.dat`) the user picked, kept as `<data>/country/cty.dat`. While it exists it is the DXCC source —
/// before Club Log's `cty.xml` and the local `~/dxcc-json` data, which stay untouched; removing it returns to them.
/// The `dxcc.json` of the local data still gives the entity codes.
public enum UserCountryFile {

    public static let folderName = "country"
    public static let fileName = "cty.dat"

    /// What makes a file unusable.
    public enum Failure: Error, Equatable, Sendable {
        /// The file could not be read or written (the system's text).
        case io(String)
        /// No country record was found (not a `cty.dat`).
        case noEntities
    }

    /// `<data>/country/cty.dat`.
    public static func url(dataDir: URL) -> URL {
        dataDir.appendingPathComponent(folderName).appendingPathComponent(fileName)
    }

    /// The imported file's bytes, `nil` when there is none.
    public static func load(dataDir: URL) -> Data? {
        let file: URL = url(dataDir: dataDir)
        guard FileManager.default.isReadableFile(atPath: file.path) else { return nil }
        return try? Data(contentsOf: file)
    }

    /// How many countries the data hold (0 = not a `cty.dat`).
    public static func entityCount(_ data: Data) -> Int {
        CtyDxccResolver.fromData(data).entities().count
    }

    /// Checks `source` and copies it to `url(dataDir:)` (replacing an earlier import); returns the number of
    /// countries. A file without any country record is refused and the earlier import stays.
    @discardableResult
    public static func install(from source: URL, dataDir: URL) throws(Failure) -> Int {
        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw .io(error.localizedDescription)
        }
        let count: Int = entityCount(data)
        guard count > 0 else { throw .noEntities }
        let target: URL = url(dataDir: dataDir)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw .io(error.localizedDescription)
        }
        return count
    }

    /// Removes the imported file; `true` when there was one.
    @discardableResult
    public static func remove(dataDir: URL) throws(Failure) -> Bool {
        let target: URL = url(dataDir: dataDir)
        guard FileManager.default.fileExists(atPath: target.path) else { return false }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw .io(error.localizedDescription)
        }
        return true
    }
}
