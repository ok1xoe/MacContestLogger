import Foundation
import Testing
@testable import MCLCore

/// Table `ExchangeMeasured` (maintainer-only probe, JDK 21.0.2):
/// `ExchangeEngine.parse` for each `FieldType` (17 + `type: ~`) over 46 inputs (empty, NBSP,
/// EM SPACE, control character, lowercase, `ß`, `ı`, ligature, Kelvin, emoji, zeros, signs, Unicode
/// digits, RST/locator boundaries, `int` max and overflow) and validation (`regex` → `length` →
/// `min`/`max`, bad regex), `parseLine`, `sentDefaults` and `activeReceivedFields`.
///
/// The result is composed as in the probe: value `valid,raw,canonical,error`, map `key=value;…`,
/// error `EXC NumberFormatException: message`; texts via `esc`.
@Suite struct ExchangeMeasuredTests {

    // MARK: - same result notation as the probe

    /// Java `esc`: UTF-16 units outside 0x21–0x7E and the characters `\ , ; = ~ |` → `\uXXXX`, `nil` → `~`.
    static func esc(_ text: String?) -> String {
        guard let text else { return "~" }
        var out = ""
        for unit in text.utf16 {
            let special = unit == 0x5C || unit == 0x2C || unit == 0x3B || unit == 0x3D || unit == 0x7E || unit == 0x7C
            if unit <= 0x20 || unit > 0x7E || special {
                out += "\\u" + String(format: "%04X", unit)
            } else {
                out += String(UnicodeScalar(UInt8(unit)))
            }
        }
        return out
    }

    static func value(_ value: ExchangeValue?) -> String {
        guard let value else { return "~" }
        return "\(value.valid)," + esc(value.raw) + "," + esc(value.canonical) + "," + esc(value.error)
    }

    static func map<V>(_ map: JavaLinkedMap<V>, _ describe: (V?) -> String) -> String {
        map.entries.map { esc($0.key) + "=" + describe($0.value) }.joined(separator: ";")
    }

    static func exception(_ error: ExchangeError) -> String {
        switch error.kind {
        case .numberFormat: return "EXC NumberFormatException: " + esc(error.message)
        case .patternSyntax: return "EXC PatternSyntaxException: " + esc(error.message)
        }
    }

    static func definition(_ yaml: String) throws -> ContestDefinition {
        if yaml.hasPrefix("@") {
            let file = try PointsCalculatorTests.contestsDirectory().appendingPathComponent(String(yaml.dropFirst()))
            return try ContestDefinitionLoader.loadFile(file)
        }
        return try ContestDefinitionLoader.load(Data(yaml.utf8))
    }

    private static func outcome(_ body: () throws(ExchangeError) -> String) -> String {
        do {
            return try body()
        } catch {
            return exception(error)
        }
    }

    // MARK: - divergences

    /// Rows where Java fails with an NPE; Swift is lenient (a `nil` element is skipped, a `nil` station
    /// cannot be expressed by the type, a `nil` key over an empty map is missing).
    static let lenient: [String: String] = [
        // a `nil` element of the received fields is skipped, its token is consumed (positions still apply)
        "L/null-element": "a=true,q,Q,~",
        // `station` is a non-optional map in Swift — the test passes an empty one (like `Map.of()`)
        "S/station-null": "a=599;b=1;zone=;q=;m=;d=;n=",
        // `Map.of().getOrDefault(null, "")` → NPE; JavaLinkedMap does not know a nil key → ""
        "S/null-id-from-station-empty": "~=",
        "S/null-element": "a=599",
        "A/null-element": "a",
    ]

    /// Rows where Swift returns a different result than Java: a regex the `JavaRegex` adapter
    /// does not translate (`.unsupported`) is ignored like a bad Java regex.
    static let divergent: [String: String] = [
        "P/text-regex-unsupported/0": "true,abc,ABC,~",
        "P/text-regex-unsupported-x/1": "true,abd,ABD,~",
    ]

    private static func expected(_ kind: String, _ label: String, _ java: ExchangeMeasured.Outcome) -> String? {
        if let swift = divergent[kind + "/" + label] {
            return swift
        }
        switch java {
        case .text(let text): return text
        case .npe: return lenient[kind + "/" + label]
        }
    }

    // MARK: - tables

    @Test(arguments: ExchangeMeasured.parse)
    func parseMatchesJava(_ row: ExchangeMeasured.ParseRow) throws {
        let definition = try Self.definition("{exchange: {received: [" + row.field + "]}}")
        let field = try #require(definition.exchange?.received?.first ?? nil)
        let swift = Self.outcome { () throws(ExchangeError) in
            Self.value(try ExchangeEngine().parse(field, row.raw))
        }
        let expected = try #require(Self.expected("P", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }

    @Test(arguments: ExchangeMeasured.lines)
    func parseLineMatchesJava(_ row: ExchangeMeasured.LineRow) throws {
        let fields = try Self.definition(row.yaml).exchange?.received ?? []
        let swift = Self.outcome { () throws(ExchangeError) in
            Self.map(try ExchangeEngine().parseLine(fields, row.line), Self.value)
        }
        let expected = try #require(Self.expected("L", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }

    @Test(arguments: ExchangeMeasured.sent)
    func sentDefaultsMatchJava(_ row: ExchangeMeasured.SentRow) throws {
        let station = JavaLinkedMap<String>(row.station ?? [])
        let context: ExchangeContext
        switch row.rover {
        case .defaultRover:
            context = ExchangeContext(mode: row.mode, nextSerial: row.serial, station: station)
        case .rover(let rover):
            context = ExchangeContext(mode: row.mode, nextSerial: row.serial, station: station, roverQth: rover)
        }
        let swift = Self.map(ExchangeEngine().sentDefaults(try Self.definition(row.yaml), context), Self.esc)
        let expected = try #require(Self.expected("S", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }

    @Test(arguments: ExchangeMeasured.active)
    func activeReceivedFieldsMatchJava(_ row: ExchangeMeasured.ActiveRow) throws {
        let fields = ExchangeEngine().activeReceivedFields(try Self.definition(row.yaml), row.workedClass)
        let swift = fields.map { Self.esc($0.id) }.joined(separator: ";")
        let expected = try #require(Self.expected("A", row.label, row.java), "NPE row without a pinned value")
        #expect(swift == expected)
    }

    /// Each of the 17 types (and `type: ~`) has the same set of inputs in the table.
    @Test func everyFieldTypeIsMeasured() {
        let types = ContestDefinition.FieldType.allCases.map(\.rawValue)
        #expect(types.count == 17)
        let inputs = ExchangeMeasured.parse.filter { $0.label.hasPrefix("TEXT/") }.map { $0.label.dropFirst(5) }
        #expect(inputs.count == 46)
        for type in types + ["~"] {
            let rows = ExchangeMeasured.parse.filter { $0.label.hasPrefix(type + "/") }
            #expect(rows.map { $0.label.dropFirst(type.count + 1) } == inputs, "\(type)")
        }
    }

    /// Pinned divergences point to existing rows (and all NPE rows have a value).
    @Test func pinnedDivergencesReferToRows() {
        var labels: [String: ExchangeMeasured.Outcome] = [:]
        for row in ExchangeMeasured.parse { labels["P/" + row.label] = row.java }
        for row in ExchangeMeasured.lines { labels["L/" + row.label] = row.java }
        for row in ExchangeMeasured.sent { labels["S/" + row.label] = row.java }
        for row in ExchangeMeasured.active { labels["A/" + row.label] = row.java }
        let npe = Set(labels.filter { $0.value == .npe }.keys)
        #expect(npe == Set(Self.lenient.keys))
        for key in Self.divergent.keys {
            #expect(labels[key] != nil && labels[key] != .text(Self.divergent[key]!), "\(key)")
        }
    }
}
