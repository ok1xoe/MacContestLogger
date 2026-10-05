import Foundation
import os

/// Registry of multiplier sets loaded from an external directory
/// (`multipliers/*.yaml`). It builds sets by `MultiplierSetDefinition.kind`
/// through internal providers (FIXED / EXTERNAL_DATA(DXCC) / ALGORITHM(WPX)).
///
/// Port of Java `multiplier/MultiplierSetRegistry.java`.
/// It also copies Java properties that look like defects (global limitations):
/// - `loadDir` has **no error isolation** — the first faulty file (even a hidden
///   `._x.yaml` from a FAT/SMB disk) fails the whole load and the registry stays half
///   populated (plan decision no. 4),
/// - files are taken non-recursively, including hidden ones, the `.yaml` filter is
///   case-sensitive, the order is **by UTF-8 bytes** of the name
///   (`Path.compareTo`), so `B.yaml` goes before `a.yaml`,
/// - the same id overwrites the earlier set **at its original position** — even the built-in
///   `wpx_prefixes`; `id: null` is registered under key `nil`,
/// - CSV is read strictly as UTF-8 and the **BOM is not stripped** (the key of the first
///   line then carries U+FEFF).
///
/// ## Concurrency
///
/// The registry is shared by a live session with background replay (Java `ContestSession` is created on
/// `Dispatchers.Default` with the same registry). Java is safe only because the registry is only read
/// after `loadDir`. Swift enforces this by type: the registry is `Sendable`
/// (checked, without `@unchecked`), the sets are immutable (`MultiplierSet: Sendable`)
/// and their list (`Contents`, a value) sits behind an `OSAllocatedUnfairLock`.
///
/// The API shape stays Java's — `loadDir` mutates **the same** instance and returns it (fluent,
/// `===`), because the measured behaviour depends on it: after an error, the sets
/// loaded before it stay in the registry. Each file is registered with a single write under the lock, so reads
/// (`get`/`contains`/`ids`) always see whole sets, never a half-built one. Loading
/// belongs to building the registry (as in Java); afterwards the registry is in practice read-only
/// and the lock merely cheaply confirms that sharing between threads is safe.
public final class MultiplierSetRegistry: Sendable {

    /// Registry contents: a Java `LinkedHashMap` — first-insertion order, overwriting keeps the position.
    private struct Contents: Sendable {
        var order: [String?] = []
        var sets: [String?: any MultiplierSet] = [:]

        mutating func put(_ id: String?, _ set: any MultiplierSet) {
            if sets.updateValue(set, forKey: id) == nil {
                order.append(id)
            }
        }
    }

    private let dxcc: (any DxccLookup)?
    private let contents: OSAllocatedUnfairLock<Contents>

    /// Java `String.split(",", 3)` on a CSV line.
    private static let csvSeparator: JavaRegex = {
        do {
            return try JavaRegex(",")
        } catch {
            preconditionFailure("pevný vzor ',' musí jít zkompilovat: \(error)")
        }
    }()

    /// - Parameter dxcc: resolver for EXTERNAL_DATA(DXCC) sets; `nil` → such
    ///   sets fail on `loadDir`.
    public init(dxcc: (any DxccLookup)?) {
        self.dxcc = dxcc
        self.contents = OSAllocatedUnfairLock(initialState: Self.builtins())
    }

    /// Built-in algorithmic sets that need no data file — the engine
    /// computes them itself (WPX prefixes from the callsign). They are always available (even without
    /// an external directory); a set with the same id from the directory overrides them.
    private static func builtins() -> Contents {
        var contents = Contents()
        contents.put("wpx_prefixes", WpxMultiplierSet(id: "wpx_prefixes"))
        return contents
    }

    /// Loads sets from an external directory (each `*.yaml`); `valuesFile` is resolved
    /// relative to it. `nil`, a nonexistent path or a file → nothing (silently).
    ///
    /// - Throws: the first error of any file; sets loaded before it
    ///   stay in the registry (as in Java):
    ///   `.failure` (Java `MultiplierException` and Java NPE on an element
    ///   `values: [~]`), `.invalidDefinition`, `.emptyDefinition` (document
    ///   `~`), `.invalidPattern` (faulty `validation.keyPattern`).
    @discardableResult
    public func loadDir(_ url: URL?) throws(MultiplierError) -> Self {
        guard let url else { return self }
        // Path as Java passed it (relative stays relative).
        let dirPath = RawFileSystem.javaPath(of: url)
        guard RawFileSystem.isDirectory(dirPath) else { return self }
        // POSIX `readdir`, filter and byte ordering like Java (`RawFileSystem`);
        // a hidden AppleDouble `._x.yaml` is seen here and fails the load as in Java.
        guard let files = RawFileSystem.yamlFiles(in: dirPath) else {
            throw .failure("Nelze projít adresář sad: " + dirPath)
        }
        for file in files {
            // Raw name bytes all the way to `open()` — no `URL`, which would convert them to NFD.
            let definition = try MultiplierSetLoader.loadFile(at: file)
            try register(definition, baseDir: dirPath)
        }
        return self
    }

    /// A set is built outside the lock (reads CSV, compiles the pattern) and written in one step.
    private func register(_ definition: MultiplierSetDefinition, baseDir: String) throws(MultiplierError) {
        let set = try build(definition, baseDir: baseDir)
        contents.withLock { $0.put(definition.id, set) }
    }

    private func build(_ definition: MultiplierSetDefinition,
                       baseDir: String) throws(MultiplierError) -> any MultiplierSet {
        guard let kind = definition.kind else {
            throw .failure("sada '\(Self.show(definition.id))' nemá kind")
        }
        switch kind {
        case .FIXED:
            // Values are built before the constructor (and pattern compilation) as in Java.
            let values = try buildValues(definition, baseDir: baseDir)
            return try FixedMultiplierSet(id: definition.id, keyType: definition.keyType, values: values,
                                          keyPattern: definition.validation?.keyPattern,
                                          keyLength: definition.keyLength)
        case .EXTERNAL_DATA:
            return try buildExternal(definition)
        case .ALGORITHM:
            return try buildAlgorithm(definition)
        }
    }

    private func buildExternal(_ definition: MultiplierSetDefinition) throws(MultiplierError) -> any MultiplierSet {
        let type = definition.provider?.type
        if type == nil || JavaChar.equalsIgnoreCase("dxcc-json", type) || JavaChar.equalsIgnoreCase("cty", type) {
            guard let dxcc else {
                throw .failure("sada '\(Self.show(definition.id))' vyžaduje DXCC data, ale resolver chybí")
            }
            return DxccMultiplierSet(id: definition.id, resolver: dxcc)
        }
        throw .failure("neznámý provider '\(Self.show(type))' u sady '\(Self.show(definition.id))'")
    }

    private func buildAlgorithm(_ definition: MultiplierSetDefinition) throws(MultiplierError) -> any MultiplierSet {
        let type = definition.algorithm?.type
        if JavaChar.equalsIgnoreCase("wpx", type) {
            return WpxMultiplierSet(id: definition.id)
        }
        throw .failure("neznámý algoritmus '\(Self.show(type))' u sady '\(Self.show(definition.id))'")
    }

    /// Priority `range` > `values` > `valuesFile`; other sources are ignored.
    private func buildValues(_ definition: MultiplierSetDefinition,
                             baseDir: String) throws(MultiplierError) -> [MultiplierValue] {
        if let range = definition.range {
            // Java `for (i = min; i <= max; i++)`: `min > max` (even a missing
            // `max` = 0) gives an empty set; Swift `min...max` would crash.
            return stride(from: range.min, through: range.max, by: 1).map {
                MultiplierValue(key: String($0), label: String($0))
            }
        }
        if let values = definition.values {
            var out: [MultiplierValue] = []
            for value in values {
                // Java: `v.key()` on a `null` element → NullPointerException, which
                // fails the whole `loadDir` (external behaviour like Java).
                guard let value else {
                    throw .failure("sada '\(Self.show(definition.id))' má ve values prázdnou položku")
                }
                // A Java map may carry a `null` value (`{c: ~}`); consumers read
                // only `get(key)`, where that is the same as a missing key → omit.
                var attributes: [String: String] = [:]
                for pair in value.attributes?.pairs ?? [] {
                    if let text = pair.value { attributes[pair.key] = text }
                }
                out.append(MultiplierValue(key: value.key, label: value.label ?? value.key, attributes: attributes))
            }
            return out
        }
        if let valuesFile = definition.valuesFile {
            return try loadCsvFile(RawFileSystem.resolve(baseDir, valuesFile))
        }
        return []
    }

    /// Java `loadCsvFile`: `Files.newBufferedReader(path, UTF_8)` — a missing
    /// or unreadable file (even a directory with `valuesFile: ""`) and invalid UTF-8
    /// anywhere in the file → "Nelze načíst valuesFile: <path>".
    private func loadCsvFile(_ path: String) throws(MultiplierError) -> [MultiplierValue] {
        let failure = MultiplierError.failure("Nelze načíst valuesFile: " + path)
        // Java: NUL in the path → `InvalidPathException` already in `resolve`; the C API would
        // silently truncate the path at the NUL and open a different file.
        guard !path.utf8.contains(0),
              let data = FileManager.default.contents(atPath: path),
              String(data: data, encoding: .utf8) != nil else {
            throw failure
        }
        // Validation above, decoding here: `String(decoding:)`, unlike
        // `String(data:encoding:)`, does **not** strip a leading BOM — like the Java reader.
        return Self.parseCsv(String(decoding: data, as: UTF8.self))
    }

    /// Format: `key[,label[,calls]]` — `calls` (optional, 3rd column) =
    /// callsigns separated by `;`. Empty lines and lines starting with `#` (after `trim`)
    /// are skipped.
    static func parseCsv(_ text: String) -> [MultiplierValue] {
        var out: [MultiplierValue] = []
        // `BufferedReader.readLine` splits on `\n`, `\r` and `\r\n`; the extra empty
        // line that arises here from `\r\n` is skipped anyway.
        let lines = text.unicodeScalars.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
        for scalars in lines {
            let line = JavaText.trim(String(String.UnicodeScalarView(scalars)))
            if line.isEmpty || line.utf16.first == 0x23 /* # */ {
                continue
            }
            let parts = JavaText.split(line, regex: csvSeparator, limit: 3)
            // port convention: `uppercased()` = Java `toUpperCase()` (see FixedMultiplierSet)
            let key = JavaText.trim(parts[0]).uppercased()
            let label = parts.count > 1 ? JavaText.trim(parts[1]) : key
            var attributes: [String: String] = [:]
            if parts.count > 2 {
                let calls = JavaText.trim(parts[2])
                if !calls.isEmpty { attributes["calls"] = calls }
            }
            out.append(MultiplierValue(key: key, label: label, attributes: attributes))
        }
        return out
    }

    /// Java `get(id)`.
    ///
    /// - Throws: `.failure("multiplikátorová sada '<id>' není v registru")`.
    public func get(_ id: String?) throws(MultiplierError) -> any MultiplierSet {
        guard let set = contents.withLock({ $0.sets[id] }) else {
            throw .failure("multiplikátorová sada '\(Self.show(id))' není v registru")
        }
        return set
    }

    public func contains(_ id: String?) -> Bool {
        contents.withLock { $0.sets[id] != nil }
    }

    /// Ids in registration order (`wpx_prefixes` first). Java returns a live view
    /// of the `keySet`, Swift a copy in the same order.
    public var ids: [String?] { contents.withLock { $0.order } }

    // MARK: - helpers

    /// Java concatenation `"…" + id`: `null` prints as `null`.
    private static func show(_ text: String?) -> String {
        text ?? "null"
    }
}
