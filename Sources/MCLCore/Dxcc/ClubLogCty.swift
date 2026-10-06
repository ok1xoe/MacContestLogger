import Foundation

/// The contents of Club Log's country file `cty.xml` (`https://cdn.clublog.org/cty.php?api=<key>`), in the compact
/// form the app caches next to the raw file.
///
/// The documented layout is a `<clublog date="…">` root with five sections:
/// - `<entities>` / `<entity>`: `adif`, `name`, `prefix`, `deleted`, `cqz`, `cont`, `long`, `lat`, `start`, `end`;
/// - `<exceptions>` / `<exception record="…">`: one exact callsign (`call`) mapped to an entity (`entity`, `adif`,
///   `cqz`, `cont`, `long`, `lat`) for a period (`start`, `end`);
/// - `<prefixes>` / `<prefix record="…">`: the same fields for a prefix;
/// - `<invalid_operations>` / `<invalid record="…">`: a callsign (`call`) that counts for no DXCC entity during a
///   period (`start`, `end`);
/// - `<zone_exceptions>` / `<zone_exception record="…">`: a callsign (`call`) with its own CQ zone (`zone`) for a
///   period (`start`, `end`).
///
/// Every field may be written as a child element (the published file) or as an attribute; both are read. Dates are
/// ISO 8601 with an offset (`1991-03-30T23:59:59+00:00`); a missing `start`/`end` is an open end of the period.
public struct ClubLogCtyData: Codable, Equatable, Sendable {

    public struct Entity: Codable, Equatable, Sendable {
        public var adif: Int
        public var name: String
        public var prefix: String
        public var deleted: Bool
        public var cqz: Int?
        public var cont: String?
        public var lat: Double?
        public var lon: Double?
        public var start: Date?
        public var end: Date?

        public init(adif: Int, name: String, prefix: String, deleted: Bool = false, cqz: Int? = nil,
                    cont: String? = nil, lat: Double? = nil, lon: Double? = nil, start: Date? = nil,
                    end: Date? = nil) {
            self.adif = adif
            self.name = name
            self.prefix = prefix
            self.deleted = deleted
            self.cqz = cqz
            self.cont = cont
            self.lat = lat
            self.lon = lon
            self.start = start
            self.end = end
        }
    }

    /// An exception (`call` is a whole callsign) or a prefix record (`call` is a prefix).
    public struct Mapping: Codable, Equatable, Sendable {
        public var record: Int?
        public var call: String
        public var entity: String?
        public var adif: Int
        public var cqz: Int?
        public var cont: String?
        public var lat: Double?
        public var lon: Double?
        public var start: Date?
        public var end: Date?

        public init(record: Int? = nil, call: String, entity: String? = nil, adif: Int, cqz: Int? = nil,
                    cont: String? = nil, lat: Double? = nil, lon: Double? = nil, start: Date? = nil,
                    end: Date? = nil) {
            self.record = record
            self.call = call
            self.entity = entity
            self.adif = adif
            self.cqz = cqz
            self.cont = cont
            self.lat = lat
            self.lon = lon
            self.start = start
            self.end = end
        }
    }

    public struct InvalidOperation: Codable, Equatable, Sendable {
        public var record: Int?
        public var call: String
        public var start: Date?
        public var end: Date?

        public init(record: Int? = nil, call: String, start: Date? = nil, end: Date? = nil) {
            self.record = record
            self.call = call
            self.start = start
            self.end = end
        }
    }

    public struct ZoneException: Codable, Equatable, Sendable {
        public var record: Int?
        public var call: String
        public var zone: Int
        public var start: Date?
        public var end: Date?

        public init(record: Int? = nil, call: String, zone: Int, start: Date? = nil, end: Date? = nil) {
            self.record = record
            self.call = call
            self.zone = zone
            self.start = start
            self.end = end
        }
    }

    /// The `date` attribute of `<clublog>` (when Club Log generated the file), verbatim.
    public var fileDate: String?
    public var entities: [Entity]
    public var exceptions: [Mapping]
    public var prefixes: [Mapping]
    public var invalidOperations: [InvalidOperation]
    public var zoneExceptions: [ZoneException]

    public init(fileDate: String? = nil, entities: [Entity] = [], exceptions: [Mapping] = [],
                prefixes: [Mapping] = [], invalidOperations: [InvalidOperation] = [],
                zoneExceptions: [ZoneException] = []) {
        self.fileDate = fileDate
        self.entities = entities
        self.exceptions = exceptions
        self.prefixes = prefixes
        self.invalidOperations = invalidOperations
        self.zoneExceptions = zoneExceptions
    }

    /// `true` when `date` lies in the closed period `start…end` (a missing end is open).
    static func isValid(at date: Date, start: Date?, end: Date?) -> Bool {
        if let start, date < start { return false }
        if let end, date > end { return false }
        return true
    }
}

/// Reading `cty.xml`.
public enum ClubLogCtyParser {

    public struct Error: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        public let reason: String
        public var description: String { reason }
    }

    /// Parses the XML. A record without its key fields (an entity without `adif`, a mapping without `call` or `adif`,
    /// a zone exception without `zone`) is skipped; a document that is not XML, or has no `<clublog>` root, or not a
    /// single entity and prefix, is an error (the cached copy is kept then).
    public static func parse(_ xml: Data) throws(ClubLogCtyParser.Error) -> ClubLogCtyData {
        let delegate = Delegate()
        let parser = XMLParser(data: xml)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else {
            let message: String = parser.parserError.map { ($0 as NSError).localizedDescription } ?? "XML"
            throw Error(reason: "cty.xml: " + message)
        }
        guard delegate.sawRoot else {
            throw Error(reason: "cty.xml: chybí element <clublog>")
        }
        guard !delegate.data.entities.isEmpty, !delegate.data.prefixes.isEmpty else {
            throw Error(reason: "cty.xml: žádné entity nebo prefixy")
        }
        return delegate.data
    }

    /// ISO 8601 with an offset, the format Club Log writes (`2019-03-01T00:00:00+00:00`); also without seconds'
    /// offset (`Z`) and a bare date (start of that day, UTC).
    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let date = isoFormatter.date(from: text) {
            return date
        }
        return dayFormatter.date(from: text)
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let dayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    private static let sections: Set<String> = [
        "entities", "exceptions", "prefixes", "invalid_operations", "zone_exceptions",
    ]
    private static let recordElements: [String: String] = [
        "entity": "entities", "exception": "exceptions", "prefix": "prefixes", "invalid": "invalid_operations",
        "zone_exception": "zone_exceptions",
    ]

    private final class Delegate: NSObject, XMLParserDelegate {
        var data = ClubLogCtyData()
        var sawRoot = false
        private var section: String?
        private var record: String?
        private var fields: [String: String] = [:]
        private var field: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = elementName.lowercased()
            if name == "clublog", !sawRoot, section == nil {
                sawRoot = true
                data.fileDate = attributeDict["date"]
                return
            }
            guard sawRoot else { return }
            if record != nil {
                field = name
                text = ""
                return
            }
            if section == nil, ClubLogCtyParser.sections.contains(name) {
                section = name
                return
            }
            if let section, ClubLogCtyParser.recordElements[name] == section {
                record = name
                fields = [:]
                for (key, value) in attributeDict {
                    fields[key.lowercased()] = value
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if field != nil {
                text += string
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let name = elementName.lowercased()
            if let current = field, current == name {
                fields[current] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                field = nil
                return
            }
            if let current = record, current == name {
                finishRecord(current)
                record = nil
                return
            }
            if let current = section, current == name {
                section = nil
            }
        }

        private func int(_ key: String) -> Int? {
            fields[key].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        private func double(_ key: String) -> Double? {
            fields[key].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }

        private func string(_ key: String) -> String? {
            guard let value = fields[key]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }

        private func date(_ key: String) -> Date? {
            ClubLogCtyParser.parseDate(fields[key])
        }

        private func finishRecord(_ kind: String) {
            switch kind {
            case "entity":
                guard let adif = int("adif") else { return }
                data.entities.append(ClubLogCtyData.Entity(
                    adif: adif, name: string("name") ?? "", prefix: string("prefix")?.uppercased() ?? "",
                    deleted: string("deleted")?.uppercased() == "TRUE", cqz: int("cqz"), cont: string("cont"),
                    lat: double("lat"), lon: double("long"), start: date("start"), end: date("end")))
            case "exception", "prefix":
                guard let call = string("call")?.uppercased(), let adif = int("adif") else { return }
                let mapping = ClubLogCtyData.Mapping(
                    record: int("record"), call: call, entity: string("entity"), adif: adif, cqz: int("cqz"),
                    cont: string("cont"), lat: double("lat"), lon: double("long"), start: date("start"),
                    end: date("end"))
                if kind == "exception" {
                    data.exceptions.append(mapping)
                } else {
                    data.prefixes.append(mapping)
                }
            case "invalid":
                guard let call = string("call")?.uppercased() else { return }
                data.invalidOperations.append(ClubLogCtyData.InvalidOperation(
                    record: int("record"), call: call, start: date("start"), end: date("end")))
            case "zone_exception":
                guard let call = string("call")?.uppercased(), let zone = int("zone") else { return }
                data.zoneExceptions.append(ClubLogCtyData.ZoneException(
                    record: int("record"), call: call, zone: zone, start: date("start"), end: date("end")))
            default:
                break
            }
        }
    }
}
