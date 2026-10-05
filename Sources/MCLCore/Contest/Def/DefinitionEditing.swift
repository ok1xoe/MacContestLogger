import Foundation

/// `DefinitionEditing.save` error — Java `IOException` (invalid id, a failure
/// to write or move). `message` is the text for the message „Uložení selhalo: …".
public struct DefinitionEditingError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Logic of the contest definition editor (analogous to the N1MM UDC Editor): live YAML check
/// (parse + `ContestValidator` + references to multiplier sets), a summary for the preview,
/// a new-contest template, duplication under a new id and safe saving.
///
/// Port of Java `contest/def/DefinitionEditing.java`. The editor is **textual**:
/// the YAML is never re-serialized (`YamlWriter` would delete the user's comments
/// and reformat the file) — `withId` is a regex replacement of one line,
/// `template` a fixed text template and `save` writes the text as it is.
public enum DefinitionEditing {

    /// Java record `Check`: the definition (`nil` on a load error) + findings.
    public struct Check: Equatable, Sendable {
        public let definition: ContestDefinition?
        public let issues: [ValidationReport.Issue]

        public init(definition: ContestDefinition?, issues: [ValidationReport.Issue]) {
            self.definition = definition
            self.issues = issues
        }

        /// The definition did not load, or there is at least one ERROR among the findings.
        public var hasErrors: Bool {
            definition == nil || issues.contains { $0.severity == .error }
        }
    }

    /// Allowed shape of a contest id = file name without extension (Java `ID`, ASCII).
    private static let idPattern = compile("[a-z0-9][a-z0-9_-]*")

    /// Java `ID_LINE`. `\s` also skips a line break (`"id:\nid: 2\n"` eats
    /// two lines) and `.`/`$` do not include `\r` — both are copied.
    private static let idLine = compile(#"(?m)^id:\s*.*$"#)

    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor editoru musí jít zkompilovat: \(error)")
        }
    }

    // MARK: - check

    /// Checks the definition text.
    ///
    /// - Parameters:
    ///   - yaml: the definition text; `nil` = empty text (Java `null → ""`)
    ///   - fileId: id by file name (`nil` = new, unsaved)
    ///   - knownSets: ids of the available multiplier sets (empty = do not check).
    ///     The message lists them **in the passed order** (Java: `Set` iteration,
    ///     in production a `TreeSet`) — pass the result of `knownSets(_:)`.
    public static func check(_ yaml: String?, fileId: String?, knownSets: [String]) -> Check {
        var issues: [ValidationReport.Issue] = []
        let definition: ContestDefinition
        do {
            definition = try ContestDefinitionLoader.load(Data((yaml ?? "").utf8))
        } catch {
            // Root `~`/`---`: Java falls through here with the NPE text; plan
            // — "the definition is empty" (Java branch `def == null`).
            issues.append(.init(severity: .error, message: parseMessage(error)))
            return Check(definition: nil, issues: issues)
        }
        issues += ContestValidator.validate(definition).issues
        if let id = definition.id, !idPattern.matches(id) {
            issues.append(.init(severity: .error,
                                message: "id '\(id)' smí obsahovat jen malá písmena, číslice, - a _"))
        }
        if let fileId, let id = definition.id, !javaEquals(fileId, id) {
            issues.append(.init(severity: .warning,
                                message: "id '\(id)' se liší od názvu souboru '\(fileId).yaml'"))
        }
        if !knownSets.isEmpty, let multipliers = definition.multipliers {
            // `nil` element: Java crashes here with an NPE out of `check` (`m.set()`); Swift
            // skips it — the validator already reports "multiplier without id" (a deliberate divergence from Java v1.1.1).
            for case let multiplier? in multipliers {
                if let set = multiplier.set, !knownSets.contains(where: { javaEquals($0, set) }) {
                    issues.append(.init(severity: .error, message:
                        "multiplier '\(text(multiplier.id))' odkazuje na neexistující sadu '\(set)'"
                        + " (dostupné: " + knownSets.joined(separator: ", ") + ")"))
                }
            }
        }
        return Check(definition: definition, issues: issues)
    }

    /// Java `parseMessage`: the first line of the message without surrounding spaces
    /// + " (řádek L, sloupec C)" for errors with a position. The cause text is our Czech
    /// (an allowed divergence), the line and column are Java's.
    static func parseMessage(_ error: ContestDefinitionError) -> String {
        switch error {
        case .invalidDefinition(let cause):
            return firstLine(cause.message) + " (řádek \(cause.line), sloupec \(cause.column))"
        case .emptyDefinition, .newerSchema, .failure:
            return firstLine(error.message)
        }
    }

    /// Java `msg.lines().findFirst().orElse(msg).trim()`.
    private static func firstLine(_ message: String) -> String {
        var line = String.UnicodeScalarView()
        for scalar in message.unicodeScalars {
            if scalar == "\n" || scalar == "\r" { break }
            line.append(scalar)
        }
        return JavaText.trim(String(line))
    }

    // MARK: - summary

    /// Short definition summary for the editor preview. `nil` values are printed
    /// as `null` (Java concatenation), a `nil` contest name as `—`.
    public static func summary(_ definition: ContestDefinition) -> [String] {
        var out: [String] = []
        out.append("Název: " + (definition.metadata?.name ?? "—"))
        out.append("Pásma: " + join(definition.bands))
        out.append("Módy: " + join(definition.modes))
        if let hours = definition.period?.durationHours {
            out.append("Délka: \(hours) h")
        }
        if let exchange = definition.exchange {
            out.append("Výměna odeslaná: " + fields(exchange.sent))
            out.append("Výměna přijatá: " + fields(exchange.received))
        }
        if let multipliers = definition.multipliers, !multipliers.isEmpty {
            // `nil` element: Java NPE (`m.id()`), Swift `null` (a deliberate divergence from Java v1.1.1).
            out.append("Násobiče: " + multipliers.map { m in
                guard let m else { return "null" }
                return "\(text(m.id)) (\(text(m.set)), \(text(m.scope?.rawValue)))"
            }.joined(separator: ", "))
        } else {
            out.append("Násobiče: žádné")
        }
        if let scoring = definition.scoring {
            out.append("Skóre: " + text(scoring.total))
        }
        if let dupe = definition.dupe {
            out.append("Dupe: " + text(dupe.scope?.rawValue))
        }
        if let cabrillo = definition.cabrillo {
            out.append("Cabrillo: " + text(cabrillo.contestName))
        }
        return out
    }

    private static func fields(_ fields: [ContestDefinition.ExchangeField?]?) -> String {
        guard let fields, !fields.isEmpty else { return "—" }
        // `nil` element: Java NPE (`f.id()`), Swift `null` (a deliberate divergence from Java v1.1.1).
        return fields.map { f in
            guard let f else { return "null" }
            return text(f.id) + ":" + text(f.type?.rawValue)
        }.joined(separator: " ")
    }

    private static func join(_ items: [String?]?) -> String {
        guard let items, !items.isEmpty else { return "—" }
        return items.map(text).joined(separator: " ")
    }

    /// Java string joining: `null` → the text "null".
    private static func text(_ value: String?) -> String {
        value ?? "null"
    }

    // MARK: - template and copy

    /// Minimal valid definition of a new contest (report + serial number,
    /// QSO × DXCC multipliers). Nothing is escaped except `"` → `'` in the name
    /// (by units, like Java `replace`); `contestName` = id in upper
    /// case (`Locale.ROOT`). Byte-identical to Java.
    public static func template(_ id: String, _ name: String) -> String {
        let safeName = String(String.UnicodeScalarView(name.unicodeScalars.map { $0 == "\"" ? "'" : $0 }))
        return """
            schemaVersion: 1
            id: \(id)
            metadata:
              name: "\(safeName)"
              organizer: ""
              officialUrl: ""
            period: { durationHours: 24 }
            bands: [160m, 80m, 40m, 20m, 15m, 10m]
            modes: [CW, SSB]

            exchange:
              sent:
                - { id: rst, type: RST, source: AUTO_RST }
                - { id: nr, type: SERIAL, source: AUTO_SERIAL }
              received:
                - { id: rst, type: RST, required: true }
                - { id: nr, type: SERIAL, required: true }

            scoring:
              qsoPoints: { mode: FIRST_MATCH, default: 1 }
              total: "qsoPoints * multTotal"

            multipliers:
              - { id: countries, set: dxcc_entities, from: callsign, scope: PER_BAND }

            dupe: { scope: PER_BAND_MODE, dupeWorthZero: true }

            cabrillo: { contestName: \(id.uppercased()), sentOrder: [rst, nr], receivedOrder: [rst, nr] }
            ui:
              entryOrder: [call, rst, nr]
              logColumns: [time, call, band, mode, rst, nr]

            """
    }

    /// Copy of a definition under a new id: the first `id:` line from column 0 is replaced with
    /// the text `id: <newId>` (literally, `$` and `\` are not interpreted); without it the
    /// line is prepended. `newId` is neither checked nor quoted.
    public static func withId(_ yaml: String, _ newId: String) -> String {
        if idLine.firstMatch(in: yaml) != nil {
            return idLine.replaceFirst(in: yaml, with: "id: " + newId)
        }
        return "id: " + newId + "\n" + yaml
    }

    /// An id may contain only `[a-z0-9][a-z0-9_-]*` (ASCII).
    public static func isValidId(_ id: String?) -> Bool {
        guard let id else { return false }
        return idPattern.matches(id)
    }

    // MARK: - files

    /// Definition files in a directory (id = name without `.yaml`), sorted by
    /// UTF-16 units (Java `String.compareTo`). A nonexistent directory
    /// and a listing error → an empty list.
    public static func listIds(_ contestsDir: URL?) -> [String] {
        yamlStems(contestsDir)
    }

    /// Ids of the available multiplier sets (names of `*.yaml` in the `multipliers` directory) —
    /// Java `TreeSet`: sorted by UTF-16 and without duplicates. It does not parse the content:
    /// the set id is the file name, not the `id:` inside (the registry takes the `id:` inside).
    public static func knownSets(_ multipliersDir: URL?) -> [String] {
        var out: [String] = []
        for stem in yamlStems(multipliersDir) where !(out.last.map { javaEquals($0, stem) } ?? false) {
            out.append(stem)
        }
        return out
    }

    /// Java `yamlStems`: `Files.list` (non-recursively, including hidden files
    /// and subdirectories), `endsWith(".yaml")` case-sensitive, without the extension,
    /// `sorted()`. Names from `readdir` without normalization (Java does not normalize them either,
    /// measured on an NFD name).
    private static func yamlStems(_ dir: URL?) -> [String] {
        guard let dir else { return [] }
        let path = RawFileSystem.javaPath(of: dir)
        guard RawFileSystem.isDirectory(path), let names = RawFileSystem.listDirectory(path) else { return [] }
        let suffix = Array(".yaml".utf16)
        return names
            .map { Array(String(decoding: $0, as: UTF8.self).utf16) }
            .filter { $0.count >= suffix.count && $0.suffix(suffix.count).elementsEqual(suffix) }
            .map { Array($0.dropLast(suffix.count)) }
            .sorted { $0.lexicographicallyPrecedes($1) }
            .map { String(decoding: $0, as: UTF16.self) }
    }

    /// Saves the definition atomically (a temp file in the same directory + `rename`),
    /// so a half-written file never remains. Adds a trailing `\n`. The temp
    /// file has, as in Java (`Files.createTempFile`), permissions 0600 and the target
    /// keeps them after the move. After an error no temp file remains.
    ///
    /// - Returns: the path `<contestsDir>/<id>.yaml`
    /// - Throws: `DefinitionEditingError` — „Neplatné id souboru: <id>", or
    ///   a failure to create the directory, write or move.
    @discardableResult
    public static func save(_ contestsDir: URL, id: String, yaml: String) throws(DefinitionEditingError) -> URL {
        guard isValidId(id) else {
            throw DefinitionEditingError(message: "Neplatné id souboru: " + id)
        }
        do {
            try FileManager.default.createDirectory(at: contestsDir, withIntermediateDirectories: true)
        } catch {
            throw DefinitionEditingError(message: RawFileSystem.javaPath(of: contestsDir) + ": "
                                         + error.localizedDescription)
        }
        let dir = RawFileSystem.javaPath(of: contestsDir)
        let target = RawFileSystem.resolve(dir, id + ".yaml")
        // Java `endsWith("\n")` by UTF-16 units — Swift `hasSuffix`
        // takes whole graphemes and `"\r\n"` is one, so a CRLF text would get an extra `\n`.
        let bytes = Array((yaml.utf16.last == 0x0A ? yaml : yaml + "\n").utf8)
        do {
            try RawFileSystem.writeAtomically(bytes, to: target, temporaryIn: dir, prefix: id)
        } catch {
            switch error {
            case .createTemporary(let code):
                throw DefinitionEditingError(message: dir + ": " + String(cString: strerror(code)))
            case .write(let temporary, let code):
                throw DefinitionEditingError(message: temporary + ": " + String(cString: strerror(code)))
            case .rename(let temporary, let code):
                throw DefinitionEditingError(message: temporary + " -> " + target + ": "
                                             + String(cString: strerror(code)))
            }
        }
        return URL(fileURLWithPath: target)
    }

    /// Java `String.equals` — by UTF-16 units, not canonically.
    private static func javaEquals(_ left: String, _ right: String) -> Bool {
        left.utf16.elementsEqual(right.utf16)
    }
}
