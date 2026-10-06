import Foundation

/// Everything a contest needs from disk, loaded once: DXCC, the multiplier set registry, the contest catalog, the
/// band plan and digi frequencies. Port of the Kotlin `AppState.buildContestController` (v1.1.1) without the
/// controller itself (that is `ContestRuntime`).
///
/// Kotlin behaviour that is kept:
/// - DXCC from `<dxccDir>/cty.dat` when it is readable and can be read (with DXCC numbers from
///   `<dxccDir>/dxcc.json` via `DxccCodeIndex`, `nil` index when that fails), otherwise from `dxcc.json`; the result
///   wrapped in `DxccSpecialCases`;
/// - the registry only with DXCC and an existing `<root>/multipliers` directory; a set that fails to load → no
///   registry (the engine is then unavailable);
/// - definitions from `<root>/contests` when it is a directory, otherwise from the root itself (a flat `convertDxlog`
///   output); an unreadable directory → no definitions;
/// - the data root is the configured directory unless it is Kotlin-blank (`isNotBlank`, so also NBSP), otherwise
///   the fallback (the default contest data directory). Kotlin repeats this fallback in five places; here it is one
///   function (`dataRoot(configured:fallback:)`) with the same result.
///
/// Kotlin swallows every load error silently; `problems` additionally names what is missing so the UI can say why
/// the engine is unavailable (texts are existing translation keys or Java exception messages).
/// **Blocking file I/O** — call off the main thread.
public struct ContestEnvironment: Sendable {

    public let dxcc: (any DxccLookup)?
    public let registry: MultiplierSetRegistry?
    /// Contest definitions (Kotlin `ContestController.available`).
    public let catalog: [ContestDefinition]
    /// The resolved data root (`contests/`, `multipliers/`, band plan).
    public let dataRoot: URL
    /// `contests/` under the root, or the root itself.
    public let contestsDir: URL
    public let bandPlan: BandPlan
    public let digiFrequencies: DigiFrequencies
    public let problems: [ContestMessage]

    public var engineAvailable: Bool {
        dxcc != nil && registry != nil
    }

    /// Kotlin `ContestController.reloadBandData(bp, df)` (`CC:100-106`): the same environment with a new band plan
    /// and digi frequency table (after the Settings edit them), everything else kept.
    public func replacingBandData(bandPlan: BandPlan, digiFrequencies: DigiFrequencies) -> ContestEnvironment {
        ContestEnvironment(dxcc: dxcc, registry: registry, catalog: catalog, dataRoot: dataRoot,
                           contestsDir: contestsDir, bandPlan: bandPlan, digiFrequencies: digiFrequencies,
                           problems: problems)
    }

    /// Kotlin `(config.contestDataDir?.takeIf { it.isNotBlank() } ?: fallback).let { Path.of(it) }`.
    public static func dataRoot(configured: String?, fallback: String) -> URL {
        if let configured, !KotlinText.isBlank(configured) {
            return URL(fileURLWithPath: configured)
        }
        return URL(fileURLWithPath: fallback)
    }

    /// Loads the environment. `dxccDir` is the DXCC data directory (Kotlin `~/dxcc-json`); `nil` = no DXCC.
    ///
    /// `clubLog` = the cached Club Log `cty.xml` (Settings → Score Reporting, on by default once a copy exists): when
    /// given, it is the DXCC source (`ClubLogCtyResolver`, names and ITU zones from the `dxccDir` data where it knows
    /// the entity); `nil` leaves the `dxccDir` source exactly as before.
    public static func load(dataRoot configured: String?, dxccDir: String?, fallbackDataRoot: String,
                            clubLog: ClubLogCtyData? = nil) -> ContestEnvironment {
        var problems: [ContestMessage] = []
        let local: (any DxccLookup)? = dxccDir.flatMap { loadDxcc(URL(fileURLWithPath: $0)) }
        let dxcc: (any DxccLookup)? = clubLog.map {
            ClubLogCtyResolver($0, localNames: ClubLogCtyResolver.localNames(from: local))
        } ?? local
        let root: URL = dataRoot(configured: configured, fallback: fallbackDataRoot)
        let multipliers: URL = root.appendingPathComponent("multipliers")
        var registry: MultiplierSetRegistry?
        if let dxcc, isDirectory(multipliers) {
            registry = try? MultiplierSetRegistry(dxcc: dxcc).loadDir(multipliers)
        }
        let contests: URL = root.appendingPathComponent("contests")
        let contestsDir: URL = isDirectory(contests) ? contests : root
        var catalog: [ContestDefinition] = []
        do {
            catalog = try ContestCatalog.fromDir(contestsDir)
        } catch {
            problems.append(.verbatim(error.message))
        }
        if dxcc == nil {
            problems.append(ContestMessage("Contest engine není dostupný."))
        } else if registry == nil {
            problems.append(ContestMessage("Multiplikátorové sady nejsou načtené."))
        }
        return ContestEnvironment(dxcc: dxcc, registry: registry, catalog: catalog, dataRoot: root,
                                  contestsDir: contestsDir, bandPlan: BandPlan.fromDir(root),
                                  digiFrequencies: DigiFrequencies.fromDir(root), problems: problems)
    }

    /// Kotlin: `cty.dat` (readable and read) with the `dxcc.json` code index, otherwise `dxcc.json`; wrapped in
    /// `DxccSpecialCases`. `nil` when neither loads.
    static func loadDxcc(_ dir: URL) -> (any DxccLookup)? {
        let json: URL = dir.appendingPathComponent("dxcc.json")
        let cty: URL = dir.appendingPathComponent("cty.dat")
        let codes: DxccCodeIndex? = (try? Data(contentsOf: json)).flatMap { try? DxccCodeIndex.fromData($0) }
        if FileManager.default.isReadableFile(atPath: cty.path), let data = try? Data(contentsOf: cty) {
            return DxccSpecialCases(CtyDxccResolver.fromData(data, codes: codes))
        }
        guard let data = try? Data(contentsOf: json), let resolver = try? DxccResolver.fromData(data) else {
            return nil
        }
        return DxccSpecialCases(resolver)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }
}
