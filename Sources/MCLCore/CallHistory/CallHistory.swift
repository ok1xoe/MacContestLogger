import Foundation

/// Call history in the N1MM+ format (a text CSV file), Java `callhistory/CallHistory` v1.1.1:
/// the line `!!Order!!,Call,Name,…` defines the columns, `#` lines are comments, further lines are data.
/// Pre-fills the received exchange by callsign (N1MM Call History Lookup, DXLog Prefill database).
///
/// Columns are named per N1MM (Call, Name, Loc1, Loc2, Sect, State, CK, BirthDate, Exch1, Misc,
/// UserText, CQZone, ITUZone, …) and stored in lower case (`toLowerCase(Locale.ROOT)`).
///
/// Faithful to Java: **a UTF-8 BOM breaks the header** —
/// `strip()` does not remove U+FEFF, `!!Order!!` is not recognised, the default column order applies and the header is
/// stored as a callsign record `\u{FEFF}!!ORDER!!`. Text is compared by UTF-16 units
/// (`JavaLinkedMap`, `JavaText`), not canonically.
public struct CallHistory: Sendable {

    /// Default column order when the file has no `!!Order!!` line.
    static let defaultOrder: [String] = ["call", "name", "loc1", "loc2", "sect", "state", "ck",
                                         "birthdate", "exch1", "misc", "usertext"]

    /// Columns in file order, lower case (also an empty name from `!!Order!!,Call,,Name`).
    public let columns: [String]
    /// Callsign (upper case) → record (column → value), in order of first occurrence (Java
    /// `LinkedHashMap`); a later line of the same callsign replaces the whole record.
    let byCall: JavaLinkedMap<JavaLinkedMap<String>>
    /// The N1MM import directives of the file (`!!MapStateToSect!!`…); the defaults when it has none.
    public let options: ImportOptions
    /// The comment lines of the file (stripped, with their `#`), in file order: N1MM's `#CONTEST` association lines
    /// among them (`contestTags`). Written back by `toLines()`.
    public let comments: [String]

    init(columns: [String], byCall: JavaLinkedMap<JavaLinkedMap<String>>, options: ImportOptions = ImportOptions(),
         comments: [String] = []) {
        self.columns = columns
        self.byCall = byCall
        self.options = options
        self.comments = comments
    }

    /// Empty history with the default column order (Java `empty()`).
    public static let empty = CallHistory(columns: defaultOrder, byCall: JavaLinkedMap())

    /// Number of callsigns.
    public var size: Int { byCall.count }

    // MARK: - Loading

    /// Loads the file; missing or unreadable = empty history. The content is read as UTF-8;
    /// if it is invalid UTF-8 (even a single bad sequence), the whole file again as ISO-8859-1. Lines are split by
    /// `\n`, `\r` and `\r\n` (`Files.readAllLines`).
    public static func load(_ path: String?) -> CallHistory {
        guard let path, access(path, R_OK) == 0 else {
            return empty
        }
        guard case .data(let data) = RawFileSystem.readFile(RawPath(path)) else {
            return empty
        }
        let bytes = [UInt8](data)
        let text: String = JavaUtf8.strict(bytes) ?? latin1(bytes)
        return parse(JavaLines.split(text))
    }

    /// Parsing the file lines (Java `parse(List<String>)`).
    ///
    /// N1MM extensions (Swift-only; a file without them parses exactly like Java v1.1.1):
    /// - comment lines are kept (`comments`, the `#CONTEST` association);
    /// - an `!!Order!!` line whose first separator is `;` makes `;` the delimiter of the lines that follow;
    /// - directive lines (`!!MapStateToSect!!`…, several on a line separated by `,` or `;`) set `options`. A file
    ///   with any directive follows N1MM's import rules: a repeated callsign overlays the non-empty fields of its
    ///   earlier record (UserText appended, an alternate Loc1 moved into Loc2) instead of replacing the record, and
    ///   every record is normalised by the directives.
    public static func parse(_ lines: [String]) -> CallHistory {
        var order: [String] = defaultOrder
        var map = JavaLinkedMap<JavaLinkedMap<String>>()
        var comments: [String] = []
        var options = ImportOptions()
        for line in lines {
            if let names = directiveNames(JavaText.strip(line)) {
                options.apply(names)
            }
        }
        var delimiter: UInt16 = 0x2C
        for line in lines {
            let stripped: String = JavaText.strip(line)
            if stripped.isEmpty {
                continue
            }
            if stripped.utf16.first == 0x23 {
                comments.append(stripped)
                continue
            }
            if isOrderHeader(stripped) {
                delimiter = orderDelimiter(stripped)
                let parts: [String] = splitKeepingEmpty(stripped, delimiter: delimiter)
                order = parts.dropFirst().map { JavaText.toLowerCase(JavaText.trim($0)) }
                continue
            }
            if directiveNames(stripped) != nil {
                continue
            }
            let parts: [String] = splitKeepingEmpty(stripped, delimiter: delimiter)
            guard let callIndex = indexOf(order, "call"), callIndex < parts.count else {
                continue
            }
            let call: String = JavaText.toUpperCase(JavaText.trim(parts[callIndex]))
            if call.isEmpty {
                continue
            }
            var record = JavaLinkedMap<String>()
            for index in 0..<min(order.count, parts.count) {
                let value: String = JavaText.trim(parts[index])
                if !value.isEmpty && !order[index].isEmpty {
                    record.put(order[index], value)
                }
            }
            if options.present {
                record = normalized(record, options: options, order: &order)
                map.put(call, overlay(map[call], record, options: options, order: &order))
            } else {
                map.put(call, record)
            }
        }
        return CallHistory(columns: order, byCall: map, options: options, comments: comments)
    }

    // MARK: - Lookup

    /// Callsign record (lower-case column → value); the callsign is trimmed (`trim`) and upper-cased.
    public func lookup(_ call: String?) -> JavaLinkedMap<String>? {
        guard let call else { return nil }
        return byCall[JavaText.toUpperCase(JavaText.trim(call))]
    }

    /// Values for the received exchange fields (upper case): the column named like the field (id), otherwise by
    /// field type (CQ_ZONE → CQZone, STATE → State/Sect, LOCATOR → Loc1…), otherwise Exch1 for the only
    /// "free" field. RST, RS and the serial number are not pre-filled.
    ///
    /// Java cannot handle a field without `id` (NPE); here it is skipped (a deliberate divergence from Java v1.1.1).
    public func prefill(_ call: String?, _ received: [ContestDefinition.ExchangeField]?) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        guard let record = lookup(call), let received else {
            return out
        }
        let open: [ContestDefinition.ExchangeField] = received.filter { !Self.isSkipped($0.type) }
        for field in open {
            guard let id = field.id else { continue }
            if let value = Self.value(record, id: id, type: field.type, openFields: open.count) {
                out.put(id, JavaText.toUpperCase(value))
            }
        }
        return out
    }

    /// Reverse lookup (N1MM Reverse Call History Lookup): callsigns whose record contains the
    /// given exchange values (`equalsIgnoreCase` after `trim`). A field value is looked up in the
    /// column that would pre-fill the field; blank (`isBlank`) fields are ignored. Everything must match.
    /// The result is sorted by UTF-16 (`TreeSet`), at most `limit` callsigns.
    ///
    /// - Parameter exchange: field id → entered value
    public func reverse(_ exchange: JavaLinkedMap<String>, _ received: [ContestDefinition.ExchangeField]?,
                        limit: Int) -> [String] {
        var wanted: [(id: String, type: ContestDefinition.FieldType?, value: String)] = []
        for field in received ?? [] {
            guard let id = field.id, !Self.isSkipped(field.type),
                  let value = exchange[id], !JavaText.isBlank(value) else { continue }
            wanted.append((id: id, type: field.type, value: JavaText.trim(value)))
        }
        guard !wanted.isEmpty, limit > 0 else {
            return []
        }
        let openCount: Int = (received ?? []).filter { !Self.isSkipped($0.type) }.count
        var calls: [String] = []
        for (key, record) in byCall.entries {
            guard let call = key, let record else { continue }
            let all: Bool = wanted.allSatisfy { want in
                guard let have = Self.value(record, id: want.id, type: want.type, openFields: openCount) else {
                    return false
                }
                return JavaChar.equalsIgnoreCase(have, want.value)
            }
            if all {
                calls.append(call)
            }
        }
        let sorted: [String] = calls.sorted { JavaText.compare($0, $1) < 0 }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Update from the log

    /// Which column to write a field value to when updating from the log: an existing column named like
    /// the field, otherwise the typical column of the type (CQ_ZONE → CQZone…), otherwise the field id (lower case). A field without `id`
    /// (Java NPE) → `nil`.
    public func columnFor(_ field: ContestDefinition.ExchangeField) -> String? {
        guard let rawId = field.id else { return nil }
        let id: String = JavaText.toLowerCase(rawId)
        if Self.indexOf(columns, id) != nil {
            return id
        }
        let byType: [String] = Self.columns(for: field.type)
        guard let first = byType.first, first != "exch1" else {
            return id
        }
        return first
    }

    /// New history with added / overwritten values (N1MM Update Call History from log).
    /// New columns are appended to the end of the order, new callsigns to the end; blank (`isBlank`) values
    /// are skipped, the others are trimmed and commas replaced by a space. If the `call` column is missing, it is added
    /// at the beginning.
    ///
    /// - Parameters:
    ///   - updates: callsign → (column → value); a `nil` callsign, column or value map (Java NPE) is skipped.
    ///   - rotatingGrids: Swift-only, N1MM's rule for a grid written to Loc1 (the app's update from the log): a
    ///     different grid moves the previous Loc1 into Loc2 (the older Loc2 is dropped) unless the file has
    ///     `!!NoLoc2AltGrid!!`; a 4-character grid is overwritten by a 6-character one of the same square without
    ///     moving it, and never replaces a 6-character one of its square. `false` = Java v1.1.1 (overwrite).
    public func withUpdates(_ updates: JavaLinkedMap<JavaLinkedMap<String>>,
                            rotatingGrids: Bool = false) -> CallHistory {
        var order: [String] = columns
        if Self.indexOf(order, "call") == nil {
            order.insert("call", at: 0)
        }
        var map: JavaLinkedMap<JavaLinkedMap<String>> = byCall
        for (rawCall, values) in updates.entries {
            guard let rawCall else { continue }
            let call: String = JavaText.toUpperCase(JavaText.trim(rawCall))
            if call.isEmpty {
                continue
            }
            var record: JavaLinkedMap<String> = map[call] ?? JavaLinkedMap()
            record.put("call", call)
            for (rawColumn, value) in values?.entries ?? [] {
                guard let rawColumn else { continue }
                let column: String = JavaText.toLowerCase(rawColumn)
                guard let value, !JavaText.isBlank(value) else { continue }
                if Self.indexOf(order, column) == nil {
                    order.append(column)
                }
                let cleaned: String = JavaText.replace(JavaText.trim(value), ",", " ")
                if rotatingGrids && column == "loc1" {
                    // N1MM: a different grid moves the previous Loc1 into Loc2 (Swift-only; Java overwrote it).
                    Self.putGrid(cleaned, into: &record, altGrid: options.loc2AltGrid, order: &order)
                } else {
                    record.put(column, cleaned)
                }
            }
            map.put(call, record)
        }
        return CallHistory(columns: order, byCall: map, options: options, comments: comments)
    }

    /// File content in the N1MM format: a comment, the `!!Order!!` header with N1MM column names, callsigns
    /// sorted by UTF-16 (`sorted()`).
    ///
    /// - Parameter keepingFileLines: Swift-only — the file's own comments (the `#CONTEST` association) and directives
    ///   follow the header, so they survive the app's saves; `false` writes exactly what Java v1.1.1 writes.
    public func toLines(keepingFileLines: Bool = false) -> [String] {
        var out: [String] = [Self.savedHeader]
        if keepingFileLines {
            out += comments.filter { !$0.hasPrefix(Self.savedHeader) }
            if !options.directives.isEmpty {
                out.append(options.directives.map { "!!" + $0 + "!!" }.joined(separator: ","))
            }
        }
        let names: [String] = columns.map { Self.n1mmNames[JavaStringKey($0)] ?? $0 }
        out.append("!!Order!!," + names.joined(separator: ","))
        let calls: [String] = byCall.keys.compactMap { $0 }.sorted { JavaText.compare($0, $1) < 0 }
        for call in calls {
            let record: JavaLinkedMap<String> = byCall[call] ?? JavaLinkedMap()
            out.append(columns.map { record[$0] ?? "" }.joined(separator: ","))
        }
        return out
    }

    // MARK: - Helpers

    /// The first line `toLines()` writes.
    static let savedHeader: String = "# Call history \u{2014} MacContestLogger (form\u{E1}t N1MM+)"

    /// N1MM column names for writing the header (lower-case keys, equality by UTF-16).
    static let n1mmNames: [JavaStringKey: String] = {
        let pairs: [(String, String)] = [
            ("call", "Call"), ("name", "Name"), ("loc1", "Loc1"), ("loc2", "Loc2"), ("sect", "Sect"),
            ("state", "State"), ("ck", "CK"), ("birthdate", "BirthDate"), ("exch1", "Exch1"),
            ("misc", "Misc"), ("usertext", "UserText"), ("cqzone", "CQZone"), ("ituzone", "ITUZone"),
            ("district", "District"), ("iota", "IOTA"),
        ]
        var names: [JavaStringKey: String] = [:]
        for (key, value) in pairs {
            names[JavaStringKey(key)] = value
        }
        return names
    }()

    /// RST, RS and SERIAL are not pre-filled (fields without a type are).
    static func isSkipped(_ type: ContestDefinition.FieldType?) -> Bool {
        type == .RST || type == .RS || type == .SERIAL
    }

    /// Record value for a field — column `id` (lower case), otherwise the type's columns, otherwise Exch1 for
    /// the only free field (Java `valueFor`, the same rules as `prefill`).
    static func value(_ record: JavaLinkedMap<String>, id: String, type: ContestDefinition.FieldType?,
                      openFields: Int) -> String? {
        if let direct = record[JavaText.toLowerCase(id)] {
            return direct
        }
        for column in columns(for: type) {
            if let found = record[column] {
                return found
            }
        }
        return openFields == 1 ? record["exch1"] : nil
    }

    /// Typical N1MM columns for a field type (Java `columnsFor`); a `nil` type → none.
    static func columns(for type: ContestDefinition.FieldType?) -> [String] {
        guard let type else { return [] }
        switch type {
        case .CQ_ZONE: return ["cqzone", "zone", "exch1"]
        case .ITU_ZONE: return ["ituzone", "zone", "exch1"]
        case .STATE, .PROVINCE: return ["state", "sect", "exch1"]
        case .LOCATOR: return ["loc1", "grid", "exch1"]
        case .DISTRICT: return ["district", "loc2", "exch1"]
        case .IOTA: return ["iota", "exch1"]
        case .TEXT: return ["name", "exch1"]
        default: return ["exch1"]
        }
    }

    /// Java `list.indexOf(text)` — equality by UTF-16.
    static func indexOf(_ list: [String], _ text: String) -> Int? {
        list.firstIndex { JavaText.equals($0, text) }
    }

    /// Java `line.regionMatches(true, 0, "!!Order!!", 0, 9)`: the first 9 UTF-16 units regardless
    /// of case (`Character.toUpperCase`, then `toLowerCase`), a shorter line does not match.
    static func isOrderHeader(_ line: String) -> Bool {
        let expected: [UInt16] = Array("!!Order!!".utf16)
        let units: [UInt16] = Array(line.utf16.prefix(expected.count))
        guard units.count == expected.count else { return false }
        for index in expected.indices where units[index] != expected[index] {
            let left: UInt16 = JavaChar.toUpperCase(units[index])
            let right: UInt16 = JavaChar.toUpperCase(expected[index])
            if left != right && JavaChar.toLowerCase(left) != JavaChar.toLowerCase(right) {
                return false
            }
        }
        return true
    }

    /// Java `line.split(",", -1)`: by UTF-16 units, empty parts (also trailing) remain. N1MM's `;` files pass
    /// `delimiter` 0x3B.
    static func splitKeepingEmpty(_ line: String, delimiter: UInt16 = 0x2C) -> [String] {
        var parts: [String] = []
        var current: [UInt16] = []
        for unit in line.utf16 {
            if unit == delimiter {
                parts.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(unit)
            }
        }
        parts.append(String(decoding: current, as: UTF16.self))
        return parts
    }

    /// ISO-8859-1: byte = code point.
    static func latin1(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            scalars.append(Unicode.Scalar(byte))
        }
        return String(scalars)
    }
}

// MARK: - Export and clearing

extension CallHistory {

    /// The same columns without any callsign: what „Vymazat call history" leaves in the file.
    public func emptied() -> CallHistory {
        CallHistory(columns: columns, byCall: JavaLinkedMap(), options: options, comments: comments)
    }

    /// The history as CSV (RFC 4180: a field with a comma, quote or line break is quoted, `"` doubled), UTF-8, one
    /// header line with the N1MM column names, callsigns sorted like the N1MM file. Unlike the N1MM file (whose
    /// values have commas replaced), nothing is altered.
    public func csvText() -> String {
        let names: [String] = columns.map { Self.n1mmNames[JavaStringKey($0)] ?? $0 }
        var lines: [String] = [names.map(Self.csvField).joined(separator: ",")]
        let calls: [String] = byCall.keys.compactMap { $0 }.sorted { JavaText.compare($0, $1) < 0 }
        for call in calls {
            let record: JavaLinkedMap<String> = byCall[call] ?? JavaLinkedMap()
            lines.append(columns.map { column in
                Self.csvField(record[column] ?? (column == "call" ? call : ""))
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
