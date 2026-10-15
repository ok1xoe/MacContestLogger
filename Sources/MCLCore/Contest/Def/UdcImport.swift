import Foundation

/// N1MM+ user defined contest (`.udc`) → a contest definition in the YAML language (best effort). The `.udc` file is
/// INI-like (`key = value`, `[section]` headers and `;` / `#` comments are skipped, keys are case-insensitive); the
/// parameters are those of the N1MM UDC editor. What has no equivalent is listed as a `# UDC:` comment at the top of
/// the generated text, so nothing is dropped silently. The definition editor opens the result for review.
///
/// Mapped: names, mode, bands (`MultiplierBands`, VHF names), `DupeType`, `DupeQSOMinutesAgo`, `DupeSqlString`, the
/// exchange from `CabrilloString`, `DefaultContestExchange` (`Last2L`, `LastCallSuff`), `QsoErrorString` (numeric),
/// up to three multipliers (`MultSqlString*` / `Multiplier*Name`, `IsMult*Per`, `DoNotCountMeAsMult*`,
/// `CountMultOnlyFor*`, `DoNotCountMultOnlyFor*`, `MultMult*`), `PointsPerContact` (fixed, band, mode, continent,
/// country, own country / continent, `IsMisc`, `Exch…`, `Exchange, *`), `PointsMultAtTimeGMT`, `PointsMultBy…`,
/// `PowerMult`, `BonusPoints` (calls), `MultipleSessions`, `ResetMultsEverySession`, `QsoNumbersByBand`, `IsWorkable`,
/// `StartOfContest` / `EndOfContest`, `MinimumOffTime`, `WebAddress`, `AuthorName`. Point rules for listed countries
/// and my own country come before the continent rules (N1MM documents the reverse priority, which would score a listed
/// country of my continent as the continent).
public enum UdcImport {

    public struct Result: Equatable, Sendable {
        public let id: String
        public let yaml: String
        /// Open multiplier sets the definition needs and that are generated with it (`id` → YAML).
        public let sets: [String: String]
        /// What could not be mapped (also in the YAML's top comment).
        public let notes: [String]
    }

    /// Key → value of a `.udc` text (lower-case keys; the last one wins).
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line: String = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") || line.hasPrefix("[") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key: String = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            if !key.isEmpty {
                out[key] = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }

    /// A `.udc` file's text: UTF-8 when it decodes, otherwise Windows-1252 (the N1MM files are ANSI).
    public static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Maps the parsed file. `entity` resolves a country prefix of the file (`G`, `UA9`) to its ADIF DXCC number
    /// (`nil` = unknown, the country rule is then left as a note).
    public static func convert(_ udc: [String: String], entity: @escaping (String) -> Int? = { _ in nil }) -> Result {
        var c = Converter(udc, entity)
        return c.run()
    }

    // MARK: - converter

    private struct Field {
        let id: String
        let type: String
        var source: String?
        var derive: String?
        var regex: String?
    }

    private struct Converter {
        let udc: [String: String]
        let entity: (String) -> Int?
        var notes: [String] = []
        var sets: [String: String] = [:]
        var id: String = "udc-contest"
        var modes: [String] = []
        var sent: [Field] = []
        var received: [Field] = []

        init(_ udc: [String: String], _ entity: @escaping (String) -> Int?) {
            self.udc = udc
            self.entity = entity
        }

        func value(_ key: String) -> String {
            udc[key.lowercased()]?.trimmingCharacters(in: .whitespaces) ?? ""
        }

        func has(_ key: String) -> Bool {
            !value(key).isEmpty
        }

        func list(_ key: String) -> [String] {
            value(key).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }

        func isTrue(_ key: String) -> Bool {
            let text = value(key).lowercased()
            return text == "true" || text == "1" || text == "yes"
        }

        mutating func note(_ text: String) {
            notes.append(text)
        }

        mutating func run() -> Result {
            let name: String = first(value("DisplayName"), value("Name"), value("CabrilloName"), "UDC contest")
            id = slug(first(value("Name"), value("CabrilloName"), value("DisplayName"), "udc-contest"))
            modes = mapModes()
            let bands: [String] = mapBands()
            exchange()
            // Everything that may add a received field runs before the exchange is written.
            let workable: String? = mapWorkable()
            let (multLines, multIds) = multipliers()
            let scoringLines: [String] = scoring(multIds: multIds)
            let dupeLines: [String] = dupe()
            let periodLines: [String] = period()
            var lines: [String] = []
            lines.append("schemaVersion: 1")
            lines.append("id: " + id)
            lines.append("metadata:")
            lines.append("  name: " + quote(name))
            if has("AuthorName") {
                lines.append("  organizer: " + quote(value("AuthorName")))
            }
            lines.append("  description: " + quote("Imported from the N1MM UDC file" +
                                                    (has("Description") ? ": " + value("Description") : ".")))
            if has("WebAddress") {
                lines.append("  officialUrl: " + quote(value("WebAddress")))
            }
            lines += periodLines
            lines.append("bands: [" + bands.joined(separator: ", ") + "]")
            lines.append("modes: [" + modes.joined(separator: ", ") + "]")
            lines.append("")
            lines += exchangeLines()
            if let workable {
                lines.append("workable: " + workable)
            }
            lines.append("")
            lines += scoringLines
            lines.append("")
            lines += multLines
            lines += dupeLines
            lines += numbering()
            lines += operating()
            lines.append("")
            lines.append("cabrillo: { contestName: " + quote(first(value("CabrilloName"), value("Name"), id.uppercased()))
                         + ", sentOrder: [" + sent.map(\.id).joined(separator: ", ") + "], receivedOrder: ["
                         + received.map(\.id).joined(separator: ", ") + "] }")
            let entry: [String] = ["call"] + received.filter { $0.type != "RST" && $0.type != "RS" }.map(\.id)
            lines.append("ui:")
            lines.append("  entryOrder: [" + entry.joined(separator: ", ") + "]")
            lines.append("  logColumns: [time, call, band, mode, " + received.map(\.id).joined(separator: ", ")
                         + ", points, mult]")
            var header: [String] = ["# Imported from an N1MM UDC file — review it, then save."]
            for text in notes {
                header.append("# UDC: " + text)
            }
            let yaml: String = (header + lines).joined(separator: "\n") + "\n"
            return Result(id: id, yaml: yaml, sets: sets, notes: notes)
        }

        // MARK: modes, bands, period

        mutating func mapModes() -> [String] {
            switch value("Mode").uppercased() {
            case "CW": return ["CW"]
            case "SSB", "PH", "PHONE": return ["SSB"]
            case "RTTY", "DIGI", "DIGITAL", "PSK": return ["RTTY"]
            case "BOTH", "MIXED": return ["CW", "SSB"]
            case "": return ["CW"]
            default:
                note("Mode '\(value("Mode"))' is unknown; CW and SSB are used.")
                return ["CW", "SSB"]
            }
        }

        func mapBands() -> [String] {
            let hfContest = ["160m", "80m", "40m", "20m", "15m", "10m"]
            let vhf = ["6m", "2m", "70cm", "23cm", "13cm", "9cm", "6cm", "3cm"]
            if value("Name").uppercased().hasPrefix("VHF") {
                return vhf
            }
            switch value("MultiplierBands") {
            case "2": return ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
            case "3": return hfContest + ["6m", "2m"]
            case "4": return vhf
            default: return hfContest
            }
        }

        mutating func period() -> [String] {
            var parts: [String] = []
            let days = ["SAT", "SUN", "MON", "TUE", "WED", "THU", "FRI"]
            func moment(_ key: String) -> (day: Int, minutes: Int)? {
                let items = list(key)
                guard items.count == 2, let day = Int(items[0]), (1...7).contains(day),
                      let hours = Double(items[1].replacingOccurrences(of: ",", with: ".")) else { return nil }
                return (day - 1, Int((hours * 60).rounded()))
            }
            if let start = moment("StartOfContest") {
                parts.append("startWeekday: " + days[start.day])
                parts.append("startTime: \"" + String(format: "%02d%02d", start.minutes / 60 % 24, start.minutes % 60)
                             + "\"")
                if let end = moment("EndOfContest") {
                    var minutes = (end.day * 1_440 + end.minutes) - (start.day * 1_440 + start.minutes)
                    if minutes <= 0 { minutes += 7 * 1_440 }
                    parts.insert("durationHours: " + String(Int((Double(minutes) / 60).rounded(.up))), at: 0)
                }
            } else if has("StartOfContest") {
                note("StartOfContest '\(value("StartOfContest"))' is not understood.")
            }
            let session = value("MultipleSessions")
            if !session.isEmpty {
                let pieces = session.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) }
                if pieces.count == 2, pieces[0].count == 4, let length = Int(pieces[1]), length > 0 {
                    // N1MM: "0000/200" = 2 hours; up to 3 digits are minutes or hmm.
                    let minutes = pieces[1].count >= 3 ? length / 100 * 60 + length % 100 : length
                    var text = "sessions: { start: \"\(pieces[0])\", minutes: \(minutes)"
                    if value("ResetMultsEverySession") == "1" {
                        text += ", resetMultipliers: true"
                    }
                    parts.append(text + " }")
                    if value("ResetSNEverySession") == "1" {
                        note("ResetSNEverySession: serial numbers do not restart in every session.")
                    }
                } else {
                    note("MultipleSessions '\(session)' is not understood.")
                }
            }
            if parts.isEmpty {
                return ["period: { durationHours: 24 }"]
            }
            if !parts.contains(where: { $0.hasPrefix("durationHours") }) {
                parts.insert("durationHours: 24", at: 0)
                note("The contest duration is not in the file; 24 hours is used.")
            }
            return ["period:"] + parts.map { "  " + $0 }
        }

        // MARK: exchange

        mutating func exchange() {
            let rst: String = modes == ["SSB"] ? "RS" : "RST"
            let tokens: [String] = value("CabrilloString").split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && Int($0) == nil }
            let callIndex: Int? = tokens.firstIndex { $0.lowercased() == "callsign" }
            let sentTokens: [String]
            let receivedTokens: [String]
            if let callIndex {
                sentTokens = Array(tokens[..<callIndex])
                receivedTokens = Array(tokens[(callIndex + 1)...])
            } else {
                if !tokens.isEmpty || has("CabrilloString") {
                    note("CabrilloString has no CallSign column; the exchange is RST + serial.")
                }
                sentTokens = ["SNT", "SentNr"]
                receivedTokens = ["RCV", "RcvNr"]
            }
            let defaults: String = value("DefaultContestExchange").uppercased()
            for token in sentTokens {
                addSent(token, rst: rst, defaults: defaults)
            }
            if defaults.contains("LAST2L") && !sent.contains(where: { $0.derive != nil }) {
                sent.append(Field(id: "last", type: "TEXT", source: "DERIVED", derive: "lastCall2L"))
            } else if defaults.contains("LASTCALLSUFF") && !sent.contains(where: { $0.derive != nil }) {
                sent.append(Field(id: "last", type: "TEXT", source: "DERIVED", derive: "lastCallSuffix"))
            }
            for token in receivedTokens {
                addReceived(token, rst: rst)
            }
            if received.isEmpty {
                received.append(Field(id: "rst", type: rst))
            }
            let check = value("QsoErrorString").lowercased()
            if check.hasPrefix("numeric") || check.contains("exchange1text_numeric") {
                for index in received.indices where received[index].id == "exch" {
                    received[index].regex = "^[0-9]+$"
                }
            }
        }

        mutating func addSent(_ token: String, rst: String, defaults: String) {
            let lower = token.lowercased()
            let field: Field
            if lower == "snt" || lower.contains("rst") {
                field = Field(id: "rst", type: rst, source: "AUTO_RST")
            } else if lower == "sentnr" || lower.contains("serial") {
                field = Field(id: "nr", type: "SERIAL", source: "AUTO_SERIAL")
            } else if lower.hasPrefix("sentexch") {
                if defaults.contains("LAST2L") {
                    field = Field(id: "last", type: "TEXT", source: "DERIVED", derive: "lastCall2L")
                } else if defaults.contains("LASTCALLSUFF") {
                    field = Field(id: "last", type: "TEXT", source: "DERIVED", derive: "lastCallSuffix")
                } else {
                    let index = sent.filter { $0.id.hasPrefix("exch") }.count
                    field = Field(id: index == 0 ? "exch" : "exch\(index + 1)", type: "TEXT", source: "FROM_STATION")
                }
            } else if lower == "space" || lower == "comment" || lower == "name" {
                return
            } else {
                note("Sent Cabrillo column '\(token)' is a text field.")
                field = Field(id: "s" + slug(lower).replacingOccurrences(of: "-", with: ""), type: "TEXT",
                              source: "FROM_STATION")
            }
            if !sent.contains(where: { $0.id == field.id }) {
                sent.append(field)
            }
        }

        mutating func addReceived(_ token: String, rst: String) {
            let lower = token.lowercased()
            let field: Field
            switch lower {
            case "rcv": field = Field(id: "rst", type: rst)
            case "rcvnr", "nr": field = Field(id: "nr", type: "SERIAL")
            case "gridsquare", "grid": field = Field(id: "grid", type: "LOCATOR")
            case "exchange1", "exchange", "exch": field = Field(id: "exch", type: "TEXT")
            case "misc", "misctext", "lastexch": field = Field(id: "misc", type: "TEXT")
            case "name": field = Field(id: "name", type: "TEXT")
            case "comment": field = Field(id: "comment", type: "TEXT")
            case "sect", "section", "sectiontext": field = Field(id: "sect", type: "TEXT")
            case "space", "freq", "date", "time":
                return
            default:
                note("Received Cabrillo column '\(token)' is a text field.")
                field = Field(id: slug(lower).replacingOccurrences(of: "-", with: ""), type: "TEXT")
            }
            if !received.contains(where: { $0.id == field.id }) {
                received.append(field)
            }
        }

        func exchangeLines() -> [String] {
            func render(_ field: Field, sent isSent: Bool) -> String {
                var parts: [String] = ["id: " + field.id, "type: " + field.type]
                if isSent {
                    parts.append("source: " + (field.source ?? "MANUAL"))
                    if let derive = field.derive {
                        parts.append("derive: " + derive)
                    }
                } else {
                    parts.append("required: " + (field.id == "comment" ? "false" : "true"))
                    if let regex = field.regex {
                        parts.append("validation: { regex: " + quote(regex) + " }")
                    }
                }
                return "    - { " + parts.joined(separator: ", ") + " }"
            }
            return ["exchange:", "  sent:"] + sent.map { render($0, sent: true) }
                + ["  received:"] + received.map { render($0, sent: false) }
        }

        // MARK: multipliers

        /// The multiplier lines and the ids that count in the score.
        mutating func multipliers() -> ([String], [String]) {
            guard value("NumMults") != "0", value("IsMultPer") != "0" || has("IsMult1Per") else { return ([], []) }
            var lines: [String] = []
            var counted: [String] = []
            for index in 1...3 {
                let suffix: String = index == 1 ? "" : String(index)
                let sql: String = value("MultSqlString" + suffix)
                let named: String = value("Multiplier\(index)Name")
                let token: String = meaningful(sql) ? sql : named
                guard meaningful(token) else { continue }
                guard var binding = mapMultiplier(token, index: index) else { continue }
                let scope: String = multScope(value("IsMult\(index)Per").isEmpty ? value("IsMultPer")
                                              : value("IsMult\(index)Per"))
                var conditions: [String] = []
                if isTrue("DoNotCountMeAsMult" + suffix) {
                    conditions.append("not: { ownDxcc: true }")
                }
                let only: [Int] = list("CountMultOnlyFor" + suffix).compactMap { resolveCountry($0, key: "CountMultOnlyFor") }
                if !only.isEmpty {
                    conditions.append("entityIn: [" + only.map(String.init).joined(separator: ", ") + "]")
                }
                let except: [String] = list("DoNotCountMultOnlyFor" + suffix)
                let continents: [String] = except.filter { ["NA", "SA", "EU", "AF", "AS", "OC"].contains($0.uppercased()) }
                let countries: [Int] = except.filter { !continents.contains($0) }
                    .compactMap { resolveCountry($0, key: "DoNotCountMultOnlyFor") }
                if !countries.isEmpty {
                    conditions.append("not: { entityIn: [" + countries.map(String.init).joined(separator: ", ") + "] }")
                }
                for continent in continents {
                    conditions.append("not: { continentIs: \(continent.uppercased()) }")
                }
                if has("CountMultOnlyForSec" + suffix) {
                    note("CountMultOnlyForSec\(suffix) (sections) is not mapped.")
                }
                if let continent = binding.continent {
                    conditions.append("continentIs: " + continent)
                }
                var text = "  - { id: \(binding.id), set: \(binding.set), from: \(binding.from), scope: \(scope)"
                if !conditions.isEmpty {
                    let when: String = conditions.count == 1 ? "{ " + conditions[0] + " }"
                        : "{ allOf: [" + conditions.map { "{ " + $0 + " }" }.joined(separator: ", ") + "] }"
                    text += ", when: " + when
                }
                lines.append(text + " }")
                binding.counted = value("MultMult" + suffix) != "0"
                if binding.counted {
                    counted.append(binding.id)
                }
            }
            return (lines.isEmpty ? [] : ["multipliers:"] + lines + [""], counted)
        }

        struct Binding {
            let id: String
            let set: String
            let from: String
            var continent: String?
            var counted = true
        }

        mutating func mapMultiplier(_ token: String, index: Int) -> Binding? {
            let lower = token.lowercased().trimmingCharacters(in: .whitespaces)
            let id = "mult\(index)"
            if let underscore = lower.firstIndex(of: "_"), lower.hasSuffix("_country") {
                let continent = String(lower[..<underscore]).uppercased()
                return Binding(id: id, set: "dxcc_entities", from: "callsign", continent: continent)
            }
            if lower.contains("country") || lower == "dxcc" {
                return Binding(id: id, set: "dxcc_entities", from: "callsign")
            }
            if lower.contains("wpx") || lower == "prefix" {
                return Binding(id: id, set: "wpx_prefixes", from: "callsign")
            }
            if lower == "cqzone" || lower == "zn" || lower.contains("zone") && !lower.contains("iaru") {
                return Binding(id: id, set: "cq_zones", from: field("exch"))
            }
            if lower.contains("iaru") {
                return Binding(id: id, set: "itu_zones", from: field("misc"))
            }
            if lower == "grid" || lower == "gridsquare" {
                return Binding(id: id, set: "grid_squares", from: field("grid", type: "LOCATOR"))
            }
            if lower == "field" {
                return Binding(id: id, set: "grid_fields", from: field("grid", type: "LOCATOR"))
            }
            if lower.contains("sect") {
                let window = value("MultWindowType").lowercased()
                if window.isEmpty || window.hasPrefix("section") || window.contains("s14p") || window.contains("sdc") {
                    return Binding(id: id, set: "arrl_sections", from: field("exch"))
                }
                if window.contains("state") || window.contains("province") {
                    return Binding(id: id, set: "na_areas", from: field("exch"))
                }
                return openSet(id, "\(self.id.replacingOccurrences(of: "-", with: "_"))_\(slug(window).replacingOccurrences(of: "-", with: "_"))",
                               from: field("exch"), name: "Sections (\(value("MultWindowType")))")
            }
            if lower == "callsign" {
                return Binding(id: id, set: "worked_calls", from: "callsign")
            }
            if lower == "lastletter" {
                return Binding(id: id, set: "last_letters", from: "callsign")
            }
            if lower == "misc" || lower == "misctext" {
                return openSet(id, "\(self.id.replacingOccurrences(of: "-", with: "_"))_misc", from: field("misc"),
                               name: "Misc values")
            }
            if lower == "exchange" || lower == "exchange1" {
                return openSet(id, "\(self.id.replacingOccurrences(of: "-", with: "_"))_exch", from: field("exch"),
                               name: "Exchange values")
            }
            note("Multiplier \(index) '\(token)' has no equivalent and is left out.")
            return nil
        }

        /// The id of a received field, added when the exchange lacks it.
        mutating func field(_ id: String, type: String = "TEXT") -> String {
            if received.contains(where: { $0.id == id }) {
                return id
            }
            if id == "exch", let other = received.first(where: { !["rst", "nr", "grid"].contains($0.id) }) {
                return other.id
            }
            received.append(Field(id: id, type: type))
            note("A received field '\(id)' was added for a multiplier.")
            return id
        }

        mutating func openSet(_ id: String, _ setId: String, from: String, name: String) -> Binding {
            sets[setId] = """
                schemaVersion: 1
                id: \(setId)
                kind: FIXED
                keyType: TEXT
                enumerable: false
                metadata: { name: \(quote(name)), description: "Open set generated by the UDC import; replace it with the list of valid values when you have one." }
                validation: { keyPattern: "^[A-Z0-9/]{1,12}$" }

                """
            return Binding(id: id, set: setId, from: from)
        }

        func multScope(_ text: String) -> String {
            switch text {
            case "2": return "PER_MODE"
            case "3": return "PER_BAND_MODE"
            case "4": return "ONCE"
            default: return "PER_BAND"
            }
        }

        mutating func resolveCountry(_ prefix: String, key: String) -> Int? {
            let wanted = prefix.uppercased()
            if let number = entity(wanted) {
                return number
            }
            note("\(key): country '\(prefix)' is unknown and left out.")
            return nil
        }

        // MARK: scoring

        mutating func scoring(multIds: [String]) -> [String] {
            var rules: [String] = []
            var defaultPoints = 1
            let points: [String] = list("PointsPerContact")
            if points.count == 1, let fixed = Int(points[0]) {
                defaultPoints = fixed
            } else if value("PointsPerContact").contains("/") && value("PointsPerContact").contains(";") {
                note("Distance table points '\(value("PointsPerContact"))' are not mapped; 1 point per QSO.")
            } else if !points.isEmpty {
                var pairs: [(String, String)] = []
                var index = 0
                while index + 1 < points.count {
                    pairs.append((points[index], points[index + 1]))
                    index += 2
                }
                // N1MM priority: band, mode, continent, country.
                var byBand: [String] = []
                var byMode: [String] = []
                var byContinent: [String] = []
                var byCountry: [String] = []
                var other: [String] = []
                var ownCountry: [String] = []
                for (key, raw) in pairs {
                    let upper = key.uppercased()
                    let value: String
                    if raw == "*" {
                        value = "{ expr: \"\(upper.hasPrefix("MISC") ? "misc" : "exch")\" }"
                    } else if let fixed = Int(raw.replacingOccurrences(of: "+", with: "")) {
                        value = "{ fixed: \(fixed) }"
                    } else {
                        note("PointsPerContact '\(key), \(raw)' is not understood.")
                        continue
                    }
                    if let band = Self.band(upper) {
                        byBand.append("      - { when: { bandIn: [\(band)] }, value: \(value) }")
                    } else if let mode = Self.mode(upper) {
                        byMode.append("      - { when: { mode: \(mode) }, value: \(value) }")
                    } else if ["EU", "AF", "AS", "NA", "SA", "OC", "AN"].contains(upper) {
                        byContinent.append("      - { when: { continentIs: \(upper) }, value: \(value) }")
                    } else if upper == "MYCOUNTRY" {
                        ownCountry.append("      - { when: { ownDxcc: true }, value: \(value) }")
                    } else if upper == "SAMECONTINENT" || upper == "MYCONTINENT" {
                        byContinent.append("      - { when: { sameContinent: true }, value: \(value) }")
                    } else if upper == "OTHERCONTINENT" {
                        byContinent.append("      - { when: { otherContinent: true }, value: \(value) }")
                    } else if upper == "ISMISC" {
                        other.append("      - { when: { fieldPresent: \(field("misc")) }, value: \(value) }")
                    } else if upper == "EXCH" || upper == "EXCHANGE" && raw != "*" {
                        other.append("      - { when: { fieldPresent: \(field("exch")) }, value: \(value) }")
                    } else if upper == "EXCHANGE" || upper == "MISC" {
                        other.append("      - { when: {}, value: \(value) }")
                    } else if upper == "EXCHISNUM" {
                        other.append("      - { when: { expr: \"matches(\(field("exch")), '[0-9]+')\" }, value: \(value) }")
                    } else if upper == "EXCHISNOTNUM" {
                        other.append("      - { when: { not: { expr: \"matches(\(field("exch")), '[0-9]+')\" } }, value: \(value) }")
                    } else if upper.hasPrefix("EXCHIS_") {
                        let text = String(upper.dropFirst(7))
                        other.append("      - { when: { fieldEquals: { field: \(field("exch")), value: \(quote(text)) } }, value: \(value) }")
                    } else if upper.hasPrefix("/") {
                        let suffix = String(upper.dropFirst())
                        other.append("      - { when: { expr: \"matches(call, '.*/\(suffix)')\" }, value: \(value) }")
                    } else if let number = entity(upper) {
                        byCountry.append("      - { when: { entityIn: [\(number)] }, value: \(value) }")
                    } else if upper.count <= 4, upper.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                        // A country prefix the DXCC data do not know as such: the calls that start with it.
                        byCountry.append("      - { when: { expr: \"matches(call, '\(upper).*')\" }, value: \(value) }")
                    } else {
                        note("PointsPerContact '\(key)' is not understood.")
                    }
                }
                // N1MM orders band, mode, continent, country; a named country and my own country come before the
                // continents here, otherwise a QSO with a listed country would score as its continent.
                rules = other + byBand + byMode + byCountry + ownCountry + byContinent
                defaultPoints = rules.isEmpty ? 1 : 0
                if rules.isEmpty {
                    note("PointsPerContact '\(value("PointsPerContact"))' is not understood; 1 point per QSO.")
                }
            }
            var factors: [String] = []
            let time = list("PointsMultAtTimeGMT")
            if time.count >= 2 {
                let factor = time.count >= 3 ? time[2] : "2"
                factors.append("      - { when: { timeBetween: \"\(time[0])-\(time[1])\" }, factor: \(factor) }")
            }
            if has("PointsMultAtTimeLocal") {
                note("PointsMultAtTimeLocal (local time) is not mapped; use timeBetween in UTC.")
            }
            factors += pairsFactors("PointsMultByBand") { key in
                Self.bandFromMHz(key).map { "bandIn: [\($0)]" }
            }
            factors += pairsFactors("PointsMultByMode") { key in
                Self.mode(key.uppercased()).map { "mode: \($0)" }
            }
            factors += pairsFactors("PointsMultByContinent") { key in
                switch key.uppercased() {
                case "MYCONTINENT": return "sameContinent: true"
                case "OTHERCONTINENT": return "otherContinent: true"
                case let continent where ["EU", "AF", "AS", "NA", "SA", "OC"].contains(continent):
                    return "continentIs: " + continent
                default: return nil
                }
            }
            let resolve: (String) -> Int? = entity
            factors += pairsFactors("PointsMultByCountry") { key in
                resolve(key.uppercased()).map { "entityIn: [\($0)]" }
            }
            var lines: [String] = ["scoring:", "  qsoPoints:", "    mode: FIRST_MATCH", "    default: \(defaultPoints)"]
            if !rules.isEmpty {
                lines.append("    rules:")
                lines += rules
            }
            if !factors.isEmpty {
                lines.append("    factors:")
                lines += factors
            }
            let bonuses = bonusLines()
            if !bonuses.isEmpty {
                lines.append("  bonuses:")
                lines += bonuses
            }
            let mult: String = multIds.isEmpty ? "" : multIds.count == (multiplierCount()) ? " * multTotal"
                : " * (" + multIds.map { "mult." + $0 }.joined(separator: " + ") + ")"
            lines.append("  total: \"" + (bonuses.isEmpty ? "qsoPoints" : "(qsoPoints + bonusPoints)") + mult + "\"")
            let power = list("PowerMult")
            if power.count >= 2 {
                var entries: [String] = []
                var index = 0
                while index + 1 < power.count {
                    let key: String
                    switch power[index].uppercased() {
                    case "HP", "HIGH": key = "HIGH"
                    case "LP", "LOW": key = "LOW"
                    case "QRP": key = "QRP"
                    default:
                        note("PowerMult category '\(power[index])' has no Cabrillo power category.")
                        index += 2
                        continue
                    }
                    if let factor = Int(power[index + 1]) {
                        entries.append("\(key): \(factor)")
                    }
                    index += 2
                }
                if !entries.isEmpty {
                    lines.append("  powerFactor: { " + entries.joined(separator: ", ") + " }")
                }
            }
            return lines
        }

        func multiplierCount() -> Int {
            (1...3).filter { index in
                let suffix = index == 1 ? "" : String(index)
                return meaningful(value("MultSqlString" + suffix)) || meaningful(value("Multiplier\(index)Name"))
            }.count
        }

        mutating func pairsFactors(_ key: String, _ condition: (String) -> String?) -> [String] {
            let items = list(key)
            var out: [String] = []
            var index = 0
            while index + 1 < items.count {
                if let when = condition(items[index]), let factor = Double(items[index + 1]) {
                    out.append("      - { when: { \(when) }, factor: \(Self.number(factor)) }")
                } else {
                    note("\(key) '\(items[index]), \(items[index + 1])' is not mapped.")
                }
                index += 2
            }
            return out
        }

        mutating func bonusLines() -> [String] {
            let items = list("BonusPoints")
            var out: [String] = []
            var index = 0
            while index + 1 < items.count {
                let key = items[index].uppercased()
                let raw = items[index + 1].replacingOccurrences(of: "+", with: "")
                if let points = Int(raw), key.contains(where: \.isNumber), key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" }) {
                    out.append("    - { id: b\(out.count + 1), when: { expr: \"matches(call, '\(key)(/.*)?')\" }, value: { fixed: \(points) }, scope: ONCE }")
                } else {
                    note("BonusPoints '\(items[index]), \(items[index + 1])' is not mapped (only calls are).")
                }
                index += 2
            }
            if has("BonusPoints2") {
                note("BonusPoints2 (a file of bonus calls) is not mapped; use the BONUS command.")
            }
            return out
        }

        // MARK: dupe, numbering, operating, workable

        mutating func dupe() -> [String] {
            var parts: [String] = []
            let rework = list("DupeQSOMinutesAgo")
            let minutes: Int? = rework.first.flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            switch value("DupeType") {
            case "1": parts.append("scope: ONCE")
            case "3": parts.append("scope: PER_BAND_MODE")
            case "4":
                if let minutes {
                    let ignoreBand = rework.count > 2 && rework[2].lowercased() == "true"
                    let thisMode = rework.count > 4 && rework[4].lowercased() == "true"
                    parts.append("scope: " + (ignoreBand ? (thisMode ? "PER_MODE" : "ONCE")
                                              : (thisMode ? "PER_BAND_MODE" : "PER_BAND")))
                    parts.append("reworkMinutes: \(minutes)")
                } else {
                    parts.append("scope: PER_BAND")
                    parts.append("none: true")
                }
            default: parts.append("scope: PER_BAND")
            }
            switch value("DupeSqlString") {
            case "1": parts.append("byField: " + field("sect"))
            case "2": parts.append("byField: " + field("exch"))
            case "3": if !parts.contains("scope: PER_BAND_MODE") { parts[0] = "scope: PER_BAND_MODE" }
            case "4": parts.append("byField: " + field("grid", type: "LOCATOR"))
            default: break
            }
            return ["dupe: { " + parts.joined(separator: ", ") + " }"]
        }

        func numbering() -> [String] {
            switch value("QsoNumbersByBand") {
            case "1": return ["numbering: { perBand: true }"]
            case "2": return ["numbering: { perBand: true, multiOpOnly: true }"]
            default: return []
            }
        }

        func operating() -> [String] {
            guard let minutes = Int(value("MinimumOffTime")), minutes > 0 else { return [] }
            return ["operating: { offTime: { minimumMinutes: \(minutes) } }"]
        }

        mutating func mapWorkable() -> String? {
            let text = value("IsWorkable")
            switch text.lowercased() {
            case "", "any": return nil
            case "mycontinentonly": return "{ sameContinent: true }"
            case "mycountryonly": return "{ ownDxcc: true }"
            case "exceptmycountry": return "{ not: { ownDxcc: true } }"
            case "naonly": return "{ continentIs: NA }"
            case "saonly": return "{ continentIs: SA }"
            case "euonly": return "{ continentIs: EU }"
            case "asiaonly": return "{ continentIs: AS }"
            case "afonly": return "{ continentIs: AF }"
            case "oconly": return "{ continentIs: OC }"
            default:
                let numbers: [Int] = list("IsWorkable").compactMap { resolveCountry($0, key: "IsWorkable") }
                return numbers.isEmpty ? nil : "{ entityIn: [" + numbers.map(String.init).joined(separator: ", ") + "] }"
            }
        }

        // MARK: helpers

        static func band(_ text: String) -> String? {
            let bands = ["160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M",
                         "1.25M", "70CM", "33CM", "23CM", "13CM", "9CM", "6CM", "3CM", "1.25CM", "6MM", "4MM", "2.5MM", "2MM", "1MM"]
            return bands.contains(text) ? text.lowercased() : nil
        }

        static func bandFromMHz(_ text: String) -> String? {
            let map: [String: String] = ["1.8": "160m", "3.5": "80m", "5": "60m", "7": "40m", "10": "30m",
                                         "14": "20m", "18": "17m", "21": "15m", "24": "12m", "28": "10m",
                                         "50": "6m", "144": "2m", "222": "1.25m", "420": "70cm", "432": "70cm",
                                         "902": "33cm", "903": "33cm", "1240": "23cm",
                                         "1296": "23cm", "2300": "13cm", "3300": "9cm", "5650": "6cm",
                                         "10000": "3cm", "10368": "3cm", "24000": "1.25cm", "24048": "1.25cm",
                                         "47000": "6mm", "47088": "6mm", "76000": "4mm", "75500": "4mm",
                                         "122250": "2.5mm", "134000": "2mm", "241000": "1mm"]
            return map[text]
        }

        static func mode(_ text: String) -> String? {
            switch text {
            case "CW": return "CW"
            case "SSB", "USB", "LSB", "PH": return "SSB"
            case "RTTY", "DIGI": return "RTTY"
            case "PSK": return "PSK"
            case "FM": return "FM"
            case "AM": return "AM"
            default: return nil
            }
        }

        static func number(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }

        func meaningful(_ text: String) -> Bool {
            let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
            return !lower.isEmpty && lower != "n/a" && lower != "na" && lower != "none" && lower != "0"
        }

        func first(_ values: String...) -> String {
            values.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        }

        func slug(_ text: String) -> String {
            var out = ""
            var dash = false
            for scalar in text.lowercased().unicodeScalars {
                if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                    out.unicodeScalars.append(scalar)
                    dash = false
                } else if !dash && !out.isEmpty {
                    out += "-"
                    dash = true
                }
            }
            while out.hasSuffix("-") { out.removeLast() }
            return out.isEmpty ? "udc-contest" : out
        }

        func quote(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
}
