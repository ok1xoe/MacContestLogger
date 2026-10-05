import Foundation

/// One file of an export: its name in the chosen directory and its bytes, encoded as Kotlin writes them.
public struct ExportFile: Equatable, Sendable {
    public let name: String
    public let bytes: Data

    public init(name: String, bytes: Data) {
        self.name = name
        self.bytes = bytes
    }
}

/// The EDI export and the other exports (CSV, text listing, summary) of the Kotlin UI v1.1.1 (`AS:4038-4074`) as
/// pure jobs: the caller reads the log and the setup, runs the job off the main thread and writes the files with
/// `write` (`Files.writeString`, a file that fails is left out silently, like Kotlin's `runCatching`).
public enum ExportJobs {

    /// `AppState.exportEdi` (`AS:4055-4074`) without the write.
    ///
    /// Checks in Kotlin order (the caller has already shown the directory panel): no definition →
    /// `ediNoContest`, the station locator `trim()` shorter than 6 → `ediNoLocator`, no band among the
    /// non-deleted QSOs → `ediEmpty`. Then one file per band, the bands sorted by `lowHz`:
    /// - header `section` = `MULTI` when the setup's `OPERATOR` category starts with `MULTI`, otherwise (or with no
    ///   setup or category) `SINGLE`; power and antenna from the station; operators `ifBlank { null } ?: call`;
    ///   remarks = the soapbox;
    /// - `EdiExporter.export(def, station, header, qsos, band, grid, fields)` — all QSOs, the exporter filters;
    /// - name `ExportNames.ediFileName`, bytes ISO-8859-1: a text with a character above U+00FF is **left out**
    ///   (Java `Files.writeString(…, ISO_8859_1)` throws `UnmappableCharacterException` before creating the file
    ///   and Kotlin's `runCatching` drops the band — kept, a deliberate divergence from Java v1.1.1).
    ///
    /// An error of `fields` (the station class expression) propagates — Kotlin does not catch it either.
    public static func edi(definition: ContestDefinition?, station: StationConfig, setup: ContestSetup?,
                           qsos: [Qso],
                           fields: (String) throws -> [ContestDefinition.ExchangeField]) rethrows
        -> Result<[ExportFile], ContestMessage> {
        guard let definition else {
            return .failure(IoTexts.ediNoContest)
        }
        let grid: String = KotlinText.trim(station.gridSquare)
        if grid.utf16.count < 6 {
            return .failure(IoTexts.ediNoLocator)
        }
        let bands: [Band] = ediBands(qsos)
        if bands.isEmpty {
            return .failure(IoTexts.ediEmpty)
        }
        let header: EdiExporter.Header = ediHeader(station: station, setup: setup)
        var files: [ExportFile] = []
        for band in bands {
            let text: String = try EdiExporter.export(definition, station, header, qsos, band, grid, fields)
            guard let bytes = latin1(text) else {
                continue
            }
            files.append(ExportFile(name: ExportNames.ediFileName(call: station.call, band: band), bytes: bytes))
        }
        return .success(files)
    }

    /// `qsos.filter { !it.isDeleted }.mapNotNull { it.band }.distinct().sortedBy { it.lowHz() }`.
    static func ediBands(_ qsos: [Qso]) -> [Band] {
        var seen: [Band] = []
        for q in qsos where !q.deleted {
            if let band = q.band, !seen.contains(band) {
                seen.append(band)
            }
        }
        // Stable like Kotlin `sortedBy`; band ranges never share `lowHz`.
        return seen.enumerated().sorted { a, b in
            a.element.lowHz != b.element.lowHz ? a.element.lowHz < b.element.lowHz : a.offset < b.offset
        }.map(\.element)
    }

    /// `AS:4063-4067`.
    static func ediHeader(station: StationConfig, setup: ContestSetup?) -> EdiExporter.Header {
        var section = "SINGLE"
        if let category = setup?.category["OPERATOR"], category.utf16.starts(with: "MULTI".utf16) {
            section = "MULTI"
        }
        let operators: String
        if let setup, !KotlinText.isBlank(setup.operators) {
            operators = setup.operators
        } else {
            operators = station.call
        }
        return EdiExporter.Header(section: section, power: station.power, antenna: station.antenna,
                                  operators: operators, remarks: setup?.soapbox ?? "")
    }

    /// Java `ISO_8859_1` encoding without replacement: every UTF-16 unit must be ≤ U+00FF, otherwise `nil`.
    static func latin1(_ text: String) -> Data? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf16.count)
        for unit in text.utf16 {
            guard unit <= 0xFF else { return nil }
            bytes.append(UInt8(unit))
        }
        return Data(bytes)
    }

    /// `AppState.exportOther` (`AS:4038-4052`) without the write: `<base>.csv`, `<base>.txt` (the listing titled
    /// `"<name> — <call>"`) and `<base>-summary.txt`, UTF-8, base `ExportNames.otherBase(call:)`.
    ///
    /// - Parameters:
    ///   - contestName: `metadata.name` of the active definition, otherwise `tr("Deník")` (`IoTexts.defaultLogName`)
    ///   - score: `contest.freshScore(qsos)` in an active contest, otherwise `nil` — computed by the caller before
    ///     any file is written
    /// - Throws: the summary's `LogExportsError` (unreachable from the app); Kotlin builds all three texts before
    ///   writing, so nothing is written then.
    public static func other(contestName: String, call: String, score: ScoreState?,
                             qsos: [Qso]) throws(LogExportsError) -> [ExportFile] {
        let base: String = ExportNames.otherBase(call: call)
        let title: String = PrintLayout.title(definitionName: contestName, call: call)
        let summary: String = try LogExports.summary(contestName, call, score, qsos)
        return [
            ExportFile(name: base + ".csv", bytes: Data(LogExports.csv(qsos).utf8)),
            ExportFile(name: base + ".txt", bytes: Data(LogExports.text(title, qsos).utf8)),
            ExportFile(name: base + "-summary.txt", bytes: Data(summary.utf8)),
        ]
    }

    /// Writes the files into `directory` in order like Kotlin `Files.writeString` (create or truncate, not atomic)
    /// and returns the names written; a file that fails is left out without a message (`runCatching { … }
    /// .getOrNull()`). Blocking I/O — call off the main thread and off the shared pool.
    public static func write(_ files: [ExportFile], to directory: URL) -> [String] {
        var written: [String] = []
        for file in files {
            let target: URL = directory.appendingPathComponent(file.name, isDirectory: false)
            do {
                try file.bytes.write(to: target)
                written.append(file.name)
            } catch {
                continue
            }
        }
        return written
    }
}
