import Foundation

/// `CountyListImport.write` error — Java `IOException` (invalid set id,
/// empty list or a write failure). `message` is the message text.
public struct CountyListImportError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Import of a list of counties / sections (QSO party, contest counties) into a multiplier set:
/// from text `CODE,Name`, `CODE;Name`, `CODE<tab>Name` or `CODE Name` it creates
/// `multipliers/<id>.yaml` (FIXED, enumerated) and `<id>.csv`.
///
/// Port of Java `contest/def/CountyListImport.java`. Java's `LinkedHashMap`
/// is an ordered array of pairs here; `putIfAbsent` = **the first occurrence wins**.
public enum CountyListImport {

    /// Column names in the table header (the row is skipped).
    private static let header: Set<String> = ["CODE", "KEY", "ABBR", "ABBREV", "ZKRATKA", "KOD"]

    // The patterns are constant and valid; `try!` would hide a possible error until runtime,
    // hence `precondition` with a clear message.
    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("Neplatný vnitřní regex \(pattern): \(error)")
        }
    }

    private static let separator = compile("\\s*[,;\\t]\\s*")
    private static let whitespaceRun = compile("\\s+")
    private static let codePattern = compile("[A-Z0-9/-]{1,10}")
    private static let setIdPattern = compile("[a-z0-9_]+")

    /// Parsing the lines; duplicate codes are merged (the first wins), `#` comments
    /// and empty lines are skipped.
    public static func parse(_ lines: [String]) -> [(code: String, label: String)] {
        var out: [(code: String, label: String)] = []
        var seen: Set<[UInt16]> = []
        for raw in lines {
            let line = JavaText.strip(raw)
            // `startsWith("#")` by UTF-16 units, not by graphemes.
            if line.isEmpty || line.utf16.first == 0x23 {
                continue
            }
            var parts = JavaText.split(line, regex: separator, limit: 2)
            if parts.count < 2 {
                parts = JavaText.split(line, regex: whitespaceRun, limit: 2)
            }
            let code = JavaText.trim(parts[0]).uppercased()
            if !codePattern.matches(code) || header.contains(code) {
                continue // table header etc.
            }
            let key = Array(code.utf16)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            out.append((code: code, label: parts.count > 1 ? replaceCommas(JavaText.trim(parts[1])) : code))
        }
        return out
    }

    private static func replaceCommas(_ text: String) -> String {
        replaceScalar(text, ",", " ")
    }

    /// Java `replace(char, char)` — by code points, not by graphemes
    /// (a comma or quote followed by a combining character is a single `Character`
    /// in Swift, which `replacing` would not find).
    private static func replaceScalar(_ text: String, _ from: Unicode.Scalar, _ to: Unicode.Scalar) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            scalars.append(scalar == from ? to : scalar)
        }
        return String(scalars)
    }

    /// Writes the set to `multipliersDir` (non-atomically, overwrites existing files —
    /// like Java `Files.write`); returns the number of values.
    @discardableResult
    public static func write(_ multipliersDir: URL, setId: String, name: String,
                             values: [(code: String, label: String)]) throws(CountyListImportError) -> Int {
        if !setIdPattern.matches(setId) {
            throw CountyListImportError(message: "Id sady smí mít jen malá písmena, číslice a _: " + setId)
        }
        if values.isEmpty {
            throw CountyListImportError(message: "Seznam neobsahuje žádný kód")
        }
        do {
            try FileManager.default.createDirectory(at: multipliersDir, withIntermediateDirectories: true)
        } catch {
            throw CountyListImportError(message: RawFileSystem.javaPath(of: multipliersDir) + ": "
                                        + error.localizedDescription)
        }
        let dir = RawFileSystem.javaPath(of: multipliersDir)
        var csv = "# " + name + " (key,label) — importováno\n"
        for value in values {
            csv += value.code + "," + value.label + "\n"
        }
        try writeFile(RawFileSystem.resolve(dir, setId + ".csv"), csv)
        let yaml = """
            schemaVersion: 1
            id: \(setId)
            kind: FIXED
            keyType: TEXT
            enumerable: true
            metadata: { name: "\(replaceScalar(name, "\"", "'"))" }
            valuesFile: \(setId).csv

            """
        try writeFile(RawFileSystem.resolve(dir, setId + ".yaml"), yaml)
        return values.count
    }

    private static func writeFile(_ path: String, _ text: String) throws(CountyListImportError) {
        do {
            try Data(text.utf8).write(to: URL(fileURLWithPath: path))
        } catch {
            throw CountyListImportError(message: path + ": " + error.localizedDescription)
        }
    }

    /// QSO party template: I send my county (ROVERQTH), I receive a county
    /// (in-state) or a state.
    public static func qsoPartyTemplate(_ id: String, _ name: String, _ countySet: String) -> String {
        let safeName = replaceScalar(name, "\"", "'")
        let contestName = id.uppercased()
        return """
            schemaVersion: 1
            id: \(id)
            metadata:
              name: "\(safeName)"
              description: "QSO party: stanice ze státu posílají okres, ostatní stát/provincii. ROVERQTH = můj okres."
            period: { durationHours: 24 }
            bands: [160m, 80m, 40m, 20m, 15m, 10m]
            modes: [CW, SSB]

            stationClasses:
              - { id: instate, when: { dxccIn: [US, K] } }
              - { id: other,   when: { not: { dxccIn: [US, K] } } }

            exchange:
              sent:
                - { id: rst,    type: RST,      source: AUTO_RST }
                - { id: county, type: DISTRICT, source: ROVER_QTH }
              received:
                - { id: rst, type: RST,      required: true }
                - { id: qth, type: DISTRICT, required: true }   # okres (stanice ze státu) nebo stát

            scoring:
              qsoPoints:
                mode: FIRST_MATCH
                default: 1
                rules:
                  - { when: { mode: CW }, value: { fixed: 2 } }
              total: "qsoPoints * multTotal"

            multipliers:
              - { id: counties, set: \(countySet),     from: qth, scope: ONCE }
              - { id: states,   set: na_areas, from: qth, scope: ONCE }

            dupe: { scope: PER_BAND_MODE }

            cabrillo: { contestName: \(contestName), sentOrder: [rst, county], receivedOrder: [rst, qth] }
            ui:
              entryOrder: [call, qth]
              logColumns: [time, call, band, mode, rst, qth, points, mult]

            """
    }
}
