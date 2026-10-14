import Foundation
import os

/// N1MM Config → Change Exchange Abbreviations: the user's table of alternative spellings of received exchange values
/// (`ALA` → `AL`). The file `<data>/ExchangeAbbreviations.txt` has one pair per line, `ALA=AL` (also `ALA,AL`,
/// `ALA AL` or a tab); `#` starts a comment, case does not matter. A typed value equal to an abbreviation is logged as
/// its replacement in the text fields (state, province, district, text…); reports, numbers, zones and locators are
/// never changed.
public struct ExchangeAbbreviations: Equatable, Sendable {

    public static let fileName = "ExchangeAbbreviations.txt"

    /// Upper-case abbreviation → upper-case replacement.
    public let table: [String: String]

    public init(table: [String: String] = [:]) {
        self.table = table
    }

    public static func parse(_ text: String) -> ExchangeAbbreviations {
        var table: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line: String = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: { $0 == "=" || $0 == "," || $0 == ";" || $0 == "\t" || $0 == " " })
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
            guard parts.count == 2, parts[0] != parts[1], table[parts[0]] == nil else { continue }
            table[parts[0]] = parts[1]
        }
        return ExchangeAbbreviations(table: table)
    }

    /// The field types whose values may be replaced.
    static let textTypes: Set<ContestDefinition.FieldType> = [.TEXT, .STATE, .PROVINCE, .DISTRICT, .NATIONAL, .HQ,
                                                               .DXCC, .PREFIX]

    /// The exchange with every text field's value replaced when it is an abbreviation.
    public func apply(_ exchange: JavaLinkedMap<String>,
                      fields: [ContestDefinition.ExchangeField]) -> JavaLinkedMap<String> {
        guard !table.isEmpty else { return exchange }
        var out = exchange
        for field in fields {
            guard let type = field.type, Self.textTypes.contains(type), let id = field.id,
                  let value = exchange[id] else { continue }
            if let replacement = table[value.trimmingCharacters(in: .whitespaces).uppercased()] {
                out.put(id, replacement)
            }
        }
        return out
    }

    private struct Cached: Sendable {
        var path: String = ""
        var modified: Date?
        var value = ExchangeAbbreviations()
    }

    private static let cache = OSAllocatedUnfairLock(initialState: Cached())

    /// The table of `<dataDir>/ExchangeAbbreviations.txt`, read again only when the file changed (a missing or
    /// unreadable file = an empty table).
    public static func load(dataDir: URL) -> ExchangeAbbreviations {
        let url: URL = dataDir.appendingPathComponent(fileName)
        let modified: Date? = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let hit = cache.withLock({ $0.path == url.path && $0.modified == modified ? $0.value : nil }) {
            return hit
        }
        let value: ExchangeAbbreviations = modified == nil ? ExchangeAbbreviations()
            : (try? String(contentsOf: url, encoding: .utf8)).map(parse) ?? ExchangeAbbreviations()
        cache.withLock { $0 = Cached(path: url.path, modified: modified, value: value) }
        return value
    }

    /// The text a new file starts with.
    public static let template: String = """
        # Exchange abbreviations (N1MM „Change Exchange Abbreviations")
        # One pair per line: what is typed = what is logged, e.g.
        # ALA=AL
        # ONT=ON

        """
}
