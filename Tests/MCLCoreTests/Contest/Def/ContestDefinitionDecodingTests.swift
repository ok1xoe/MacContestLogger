import Foundation
import Testing
@testable import MCLCore

/// `ContestDefinitionLoader.load` against Java. The `cases` table is **generated
/// from running Java**: probe `ProbeContest` (maintainer-only probe,
/// generators `gen_cases.py` → `ProbeContest` → `gen_swift.py`, procedure in
/// a maintainer-only probe, section "Decoder table") called
/// `new ContestDefinitionLoader().load(…)` (Jackson 2.22.0 + SnakeYAML 2.5,
/// Java v1.1.1) and printed either the `toString()` of the returned record, the line and column
/// from the `JsonProcessingException` in the cause of `ContestDefinitionException`, the
/// `checkVersion` message, or a `NullPointerException` (document `~`/`---`).
/// `javaDescription` prints the Swift definition the same way as Java's `toString`,
/// so an `.ok` row compares **all** fields of all nested records.
///
/// The "wrong types" sections put a wrong type into **every field of every record**
/// (26 records, `Condition` in four nestings), always at a different line
/// and column than the root: Jackson checks the type even for fields nobody
/// reads afterwards, and a field that the Swift `init` did not read would stay green
/// here only by accident — hence every field has its own row.
@Suite struct ContestDefinitionDecodingTests {

    enum Expected: Sendable {
        /// Java `toString()` of the loaded record.
        case ok(String)
        /// `ContestDefinitionException` with a YAML/Jackson cause at a line and column.
        case error(Int, Int)
        /// Java NPE (root `~`/`---`); Swift throws "definice je prázdná" (the definition is empty).
        case empty
        /// `checkVersion`: "Novější formát definice (schemaVersion=N)…" (newer definition format).
        case newer(Int)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let yaml: String
        let expected: Expected

        init(_ yaml: String, _ expected: Expected) {
            self.yaml = yaml
            self.expected = expected
        }

        var testDescription: String { String(reflecting: yaml) }
    }

    // The comment next to an error = the Java message (Swift has its own Czech one).
    static let cases: [Case] = [
        // ── root
        // No content to map due to end-of-input
        .init("", .error(1, 1)),
        // No content to map due to end-of-input
        .init("\n# c\n", .error(3, 1)),
        .init("~\n", .empty),
        .init("---\n", .empty),
        .init("--- ~\n", .empty),
        // Cannot construct instance of `ContestDefinition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('hello')
        .init("hello\n", .error(1, 1)),
        // Cannot deserialize value of type `ContestDefinition` from Array value (token `JsonToken.START_ARRAY`)
        .init("- a\n", .error(1, 1)),
        // Cannot deserialize value of type `ContestDefinition` from Array value (token `JsonToken.START_ARRAY`)
        .init("[]\n", .error(1, 1)),
        .init("{}\n", .ok("ContestDefinition[schemaVersion=0, id=null, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // ── schemaVersion
        .init("id: t\nschemaVersion: 1\n", .ok("ContestDefinition[schemaVersion=1, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Novější formát definice (schemaVersion=2), aktualizuj aplikaci. Podporováno: 1
        .init("id: t\nschemaVersion: 2\n", .newer(2)),
        .init("id: t\nschemaVersion: 0\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nschemaVersion: -5\n", .ok("ContestDefinition[schemaVersion=-5, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Novější formát definice (schemaVersion=2), aktualizuj aplikaci. Podporováno: 1
        .init("id: t\nschemaVersion: \"2\"\n", .newer(2)),
        .init("id: t\nschemaVersion: 1.9\n", .ok("ContestDefinition[schemaVersion=1, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Novější formát definice (schemaVersion=2), aktualizuj aplikaci. Podporováno: 1
        .init("id: t\nschemaVersion: 2.1\n", .newer(2)),
        .init("id: t\nschemaVersion: ~\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nschemaVersion: \"\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nschemaVersion: x\n", .error(2, 16)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nschemaVersion: 99999999999\n", .error(2, 27)),
        // Novější formát definice (schemaVersion=2147483647), aktualizuj aplikaci. Podporováno: 1
        .init("id: t\nschemaVersion: 2147483647\n", .newer(2147483647)),
        // ── period
        .init("id: t\nperiod: 24\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: \"24\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no double/Double-argument constructor/factory method to deserialize from Number value (1.5)
        .init("id: t\nperiod: 1.5\n", .error(2, 9)),
        // Cannot coerce empty String ("") to `ContestDefinition$Period` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nperiod: \"\"\n", .error(2, 9)),
        // Cannot coerce empty String ("") to `ContestDefinition$Period` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nperiod: \" \"\n", .error(2, 9)),
        // Cannot deserialize value of type `int` from String "null": not a valid `int` value
        .init("id: t\nperiod: \"null\"\n", .error(2, 9)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nperiod: \"x\"\n", .error(2, 9)),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no boolean/Boolean-argument constructor/factory method to deserialize from boolean value (true)
        .init("id: t\nperiod: true\n", .error(2, 9)),
        // Cannot deserialize value of type `ContestDefinition$Period` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nperiod: [24]\n", .error(2, 9)),
        .init("id: t\nperiod: {}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=null, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: ~\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: \" 24 \"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: \"+24\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: 0x18\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no long/Long-argument constructor/factory method to deserialize from Number value (99999999999)
        .init("id: t\nperiod: 99999999999\n", .error(2, 9)),
        // Cannot deserialize value of type `int` from String "99999999999": Overflow: numeric value (99999999999) out of range of int (-2147483648 -2147483647)
        .init("id: t\nperiod: \"99999999999\"\n", .error(2, 9)),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no double/Double-argument constructor/factory method to deserialize from Number value (-1.9)
        .init("id: t\nperiod: -1.9\n", .error(2, 9)),
        // Cannot deserialize value of type `int` from String "1e3": not a valid `int` value
        .init("id: t\nperiod: \"1e3\"\n", .error(2, 9)),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no double/Double-argument constructor/factory method to deserialize from Number value (1000.0)
        .init("id: t\nperiod: 1e3\n", .error(2, 9)),
        // Cannot deserialize value of type `int` from String "1.5": not a valid `int` value
        .init("id: t\nperiod: \"1.5\"\n", .error(2, 9)),
        .init("id: t\nperiod: 0\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=0, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nperiod: -3\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=-3, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no boolean/Boolean-argument constructor/factory method to deserialize from boolean value (true)
        .init("id: t\nperiod: yes\n", .error(2, 9)),
        .init("id: t\nperiod: \"٣\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=3, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `ContestDefinition$Period` (although at least one Creator exists): no double/Double-argument constructor/factory method to deserialize from Number value (2.1474836485E9)
        .init("id: t\nperiod: 2147483648.5\n", .error(2, 9)),
        .init("id: t\nperiod: {durationHours: 24, sessions: {start: \"1200\", minutes: 30}}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=Sessions[start=1200, minutes=30]], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `ContestDefinition$Sessions` (although at least one Creator exists): no int/Int-argument constructor/factory method to deserialize from Number value (5)
        .init("id: t\nperiod: {sessions: 5}\n", .error(2, 20)),
        .init("id: t\nperiod: {durationHours: \"48\"}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=48, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nperiod: {durationHours: x}\n", .error(2, 25)),
        .init("id: t\nperiod: !!str 24\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=Period[durationHours=24, sessions=null], bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot coerce empty String ("") to `ContestDefinition$Period` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nperiod: \"  \"\n", .error(2, 9)),
        // Cannot construct instance of `ContestDefinition$Sessions` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nperiod:\n  durationHours: 24\n  sessions: x\n", .error(4, 13)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nperiod: 24\nperiod: x\n", .error(3, 9)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nperiod: x\nperiod: 24\n", .error(2, 9)),
        // ── enums — order and names
        .init("id: t\ndupe:\n  scope: 0\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=PER_BAND, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        .init("id: t\ndupe:\n  scope: 1\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=PER_BAND_MODE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        .init("id: t\ndupe:\n  scope: 2\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=PER_MODE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        .init("id: t\ndupe:\n  scope: 3\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=ONCE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$Scope` from number 4: index value outside legal index range [0..3]
        .init("id: t\ndupe:\n  scope: 4\n", .error(3, 10)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from number -1: index value outside legal index range [0..3]
        .init("id: t\ndupe:\n  scope: -1\n", .error(3, 10)),
        .init("id: t\ndupe:\n  scope: PER_MODE\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=PER_MODE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\ndupe:\n  scope: per_band\n", .error(3, 10)),
        .init("id: t\ndupe:\n  scope: \" ONCE \"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=ONCE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        // Cannot coerce empty String ("") to `ContestDefinition$Scope` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\ndupe:\n  scope: \"\"\n", .error(3, 10)),
        .init("id: t\ndupe:\n  scope: \"3\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=Dupe[scope=ONCE, dupeWorthZero=null], cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$Scope` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\ndupe:\n  scope: 1.0\n", .error(3, 10)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "ONCE_": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\ndupe:\n  scope: ONCE_\n", .error(3, 10)),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: 16\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=QTC, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from number 17: index value outside legal index range [0..16]
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: 17\n", .error(5, 13)),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: QTC\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=QTC, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from String "qtc": not one of the values accepted for Enum class: [QTC, RS, HQ, TEXT, DISTRICT, PROVINCE, STATE, NATIONAL, IOTA, SERIAL, LOCATOR, CQ_ZONE, INTEGER, ITU_ZONE, RST, DXCC, PREFIX]
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: qtc\n", .error(5, 13)),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: \"16\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=QTC, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from String "Rst": not one of the values accepted for Enum class: [QTC, RS, HQ, TEXT, DISTRICT, PROVINCE, STATE, NATIONAL, IOTA, SERIAL, LOCATOR, CQ_ZONE, INTEGER, ITU_ZONE, RST, DXCC, PREFIX]
        .init("id: t\nexchange:\n  received:\n    - id: a\n      type: Rst\n", .error(5, 13)),
        .init("id: t\nexchange:\n  sent:\n    - id: a\n      source: 5\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=[ExchangeField[id=a, type=null, required=false, source=ROVER_QTH, appliesWhen=null, validation=null, estimate=null]], received=null], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from number 6: index value outside legal index range [0..5]
        .init("id: t\nexchange:\n  sent:\n    - id: a\n      source: 6\n", .error(5, 15)),
        .init("id: t\nexchange:\n  sent:\n    - id: a\n      source: ROVER_QTH\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=[ExchangeField[id=a, type=null, required=false, source=ROVER_QTH, appliesWhen=null, validation=null, estimate=null]], received=null], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from String "manual": not one of the values accepted for Enum class: [AUTO_RST, AUTO_SERIAL, MANUAL, ROVER_QTH, DERIVED, FROM_STATION]
        .init("id: t\nexchange:\n  sent:\n    - id: a\n      source: manual\n", .error(5, 15)),
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: 1\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=SUM, defaultValue=0, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$PointsMode` from number 2: index value outside legal index range [0..1]
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: 2\n", .error(4, 11)),
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: SUM\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=SUM, defaultValue=0, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$PointsMode` from String "sum": not one of the values accepted for Enum class: [SUM, FIRST_MATCH]
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: sum\n", .error(4, 11)),
        // ── primitiva
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: ~\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: \"\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: yes\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=true, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: 1\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=true, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: 0\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=false, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `boolean` from String "yes": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: \"yes\"\n", .error(5, 17)),
        // Cannot deserialize value of type `boolean` from String "ano": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: ano\n", .error(5, 17)),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: on\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=true, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: \"true\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=Exchange[sent=null, received=[ExchangeField[id=a, type=null, required=true, source=null, appliesWhen=null, validation=null, estimate=null]]], scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    default: 3\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=3, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    default: ~\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    default: \"\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    default: \"3\"\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=3, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nscoring:\n  qsoPoints:\n    default: x\n", .error(4, 14)),
        .init("id: t\nscoring:\n  qsoPoints:\n    default: 1.9\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=1, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    defaultValue: 3\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=null], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: 0.5}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=0.5, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: \"0.5\"}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=0.5, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: 1}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=1.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: ~}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=0.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `double` from String "abc": not a valid `double` value (as String to convert)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: abc}\n", .error(6, 39)),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: \"\"}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=0.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: 1e3}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=1000.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc, factor: 2}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=2.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: {field: loc}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=Scoring[qsoPoints=QsoPoints[mode=null, defaultValue=0, rules=[PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=loc, factor=0.0, round=null, min=null, max=null]]]]], bonuses=null, total=null, qtc=null], multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // ── lists and maps
        .init("id: t\nbands: [~, 160m]\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=[null, 160m], modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nbands: [160, yes, 1.50]\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=[160, yes, 1.50], modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nbands: 20m\n", .error(2, 8)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nbands: \"\"\n", .error(2, 8)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nbands: [[a]]\n", .error(2, 9)),
        // Cannot deserialize value of type `java.util.ArrayList<java.lang.String>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nbands: {a: 1}\n", .error(2, 8)),
        .init("id: t\nbands: []\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=[], modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\ncategories: [~, {id: a}]\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=[null, Category[id=a, label=null]], stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf: [~, {ownDxcc: true}]\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=[StationClass[id=a, when=Condition[allOf=[null, Condition[allOf=null, anyOf=null, not=null, ownDxcc=true, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]], anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]]], exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        .init("id: t\noperating:\n  rules:\n    - when: {OPERATOR: SINGLE-OP, n: 1, x: ~}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=Operating[offTime=null, bandChange=null, rules=[OperatingRule[when={OPERATOR=SINGLE-OP, n=1, x=null}, offTime=null, bandChange=null]]]]")),
        .init("id: t\nmultipliers:\n  - id: m\n    bandWeights: {80m: 4, 40m: \"3\", 20m: ~, 15m: 1.9}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=[MultiplierBinding[id=m, set=null, from=null, scope=null, label=null, appliesWhen=null, bandWeights={80m=4, 40m=3, 20m=null, 15m=1}]], dupe=null, cabrillo=null, ui=null, operating=null]")),
        // ── unknown keys and duplicates
        .init("id: t\nzzz: {deep: [1, 2]}\nmetadata: {name: N, bogus: [x]}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=Metadata[name=N, organizer=null, description=null, officialUrl=null], period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: [a]\nid: t\n", .error(1, 5)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "x": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\ndupe: {scope: x}\ndupe: {scope: ONCE}\n", .error(2, 15)),
        .init("id: t\nmetadata: {name: a}\nmetadata: {organizer: b}\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=Metadata[name=null, organizer=b, description=null, officialUrl=null], period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // ── wrong types: root
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nschemaVersion: x\n", .error(2, 16)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nid: [a]\n", .error(2, 5)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nid: {a: 1}\n", .error(2, 5)),
        // Cannot construct instance of `ContestDefinition$Metadata` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nmetadata: x\n", .error(2, 11)),
        // Cannot deserialize value of type `ContestDefinition$Metadata` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata: []\n", .error(2, 11)),
        // Cannot coerce empty String ("") to `ContestDefinition$Metadata` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nmetadata: \"\"\n", .error(2, 11)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nperiod: x\n", .error(2, 9)),
        // Cannot deserialize value of type `ContestDefinition$Period` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nperiod: [1]\n", .error(2, 9)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nbands: 20m\n", .error(2, 8)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nbands: \"\"\n", .error(2, 8)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nbands: [[a]]\n", .error(2, 9)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nmodes: 20m\n", .error(2, 8)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nmodes: \"\"\n", .error(2, 8)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmodes: [[a]]\n", .error(2, 9)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Category>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\ncategories: x\n", .error(2, 13)),
        // Cannot construct instance of `ContestDefinition$Category` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\ncategories: [x]\n", .error(2, 14)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Category>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\ncategories: {a: 1}\n", .error(2, 13)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$StationClass>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nstationClasses: x\n", .error(2, 17)),
        // Cannot construct instance of `ContestDefinition$StationClass` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses: [x]\n", .error(2, 18)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$StationClass>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses: {a: 1}\n", .error(2, 17)),
        // Cannot construct instance of `ContestDefinition$Exchange` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange: x\n", .error(2, 11)),
        // Cannot deserialize value of type `ContestDefinition$Exchange` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange: []\n", .error(2, 11)),
        // Cannot coerce empty String ("") to `ContestDefinition$Exchange` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nexchange: \"\"\n", .error(2, 11)),
        // Cannot construct instance of `ContestDefinition$Scoring` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring: x\n", .error(2, 10)),
        // Cannot deserialize value of type `ContestDefinition$Scoring` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring: []\n", .error(2, 10)),
        // Cannot coerce empty String ("") to `ContestDefinition$Scoring` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring: \"\"\n", .error(2, 10)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$MultiplierBinding>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nmultipliers: x\n", .error(2, 14)),
        // Cannot construct instance of `ContestDefinition$MultiplierBinding` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nmultipliers: [x]\n", .error(2, 15)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$MultiplierBinding>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers: {a: 1}\n", .error(2, 14)),
        // Cannot construct instance of `ContestDefinition$Dupe` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\ndupe: x\n", .error(2, 7)),
        // Cannot deserialize value of type `ContestDefinition$Dupe` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ndupe: []\n", .error(2, 7)),
        // Cannot coerce empty String ("") to `ContestDefinition$Dupe` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\ndupe: \"\"\n", .error(2, 7)),
        // Cannot construct instance of `ContestDefinition$Cabrillo` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\ncabrillo: x\n", .error(2, 11)),
        // Cannot deserialize value of type `ContestDefinition$Cabrillo` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncabrillo: []\n", .error(2, 11)),
        // Cannot coerce empty String ("") to `ContestDefinition$Cabrillo` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\ncabrillo: \"\"\n", .error(2, 11)),
        // Cannot construct instance of `ContestDefinition$Ui` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nui: x\n", .error(2, 5)),
        // Cannot deserialize value of type `ContestDefinition$Ui` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nui: []\n", .error(2, 5)),
        // Cannot coerce empty String ("") to `ContestDefinition$Ui` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nui: \"\"\n", .error(2, 5)),
        // Cannot construct instance of `ContestDefinition$Operating` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating: x\n", .error(2, 12)),
        // Cannot deserialize value of type `ContestDefinition$Operating` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating: []\n", .error(2, 12)),
        // Cannot coerce empty String ("") to `ContestDefinition$Operating` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\noperating: \"\"\n", .error(2, 12)),
        // ── wrong types: Operating
        // Cannot construct instance of `ContestDefinition$OffTime` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  offTime: x\n", .error(3, 12)),
        // Cannot deserialize value of type `ContestDefinition$OffTime` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating:\n  offTime: []\n", .error(3, 12)),
        // Cannot coerce empty String ("") to `ContestDefinition$OffTime` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\noperating:\n  offTime: \"\"\n", .error(3, 12)),
        // Cannot construct instance of `ContestDefinition$BandChange` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  bandChange: x\n", .error(3, 15)),
        // Cannot deserialize value of type `ContestDefinition$BandChange` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating:\n  bandChange: []\n", .error(3, 15)),
        // Cannot coerce empty String ("") to `ContestDefinition$BandChange` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\noperating:\n  bandChange: \"\"\n", .error(3, 15)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$OperatingRule>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\noperating:\n  rules: x\n", .error(3, 10)),
        // Cannot construct instance of `ContestDefinition$OperatingRule` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  rules: [x]\n", .error(3, 11)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$OperatingRule>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\noperating:\n  rules: {a: 1}\n", .error(3, 10)),
        // ── wrong types: OperatingRule
        // Cannot construct instance of `java.util.LinkedHashMap` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  rules:\n    - when: x\n", .error(4, 13)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating:\n  rules:\n    - when: {a: [b]}\n", .error(4, 17)),
        // Cannot construct instance of `ContestDefinition$OffTime` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  rules:\n    - offTime: x\n", .error(4, 16)),
        // Cannot deserialize value of type `ContestDefinition$OffTime` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating:\n  rules:\n    - offTime: []\n", .error(4, 16)),
        // Cannot coerce empty String ("") to `ContestDefinition$OffTime` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\noperating:\n  rules:\n    - offTime: \"\"\n", .error(4, 16)),
        // Cannot construct instance of `ContestDefinition$BandChange` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\noperating:\n  rules:\n    - bandChange: x\n", .error(4, 19)),
        // Cannot deserialize value of type `ContestDefinition$BandChange` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\noperating:\n  rules:\n    - bandChange: []\n", .error(4, 19)),
        // Cannot coerce empty String ("") to `ContestDefinition$BandChange` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\noperating:\n  rules:\n    - bandChange: \"\"\n", .error(4, 19)),
        // ── wrong types: OffTime
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  offTime:\n    minimumMinutes: x\n", .error(4, 21)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  offTime:\n    minimumMinutes: 99999999999\n", .error(4, 32)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  offTime:\n    requiredMinutes: x\n", .error(4, 22)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  offTime:\n    requiredMinutes: 99999999999\n", .error(4, 33)),
        // ── wrong types: OffTime(rule)
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  rules:\n    - when: {OPERATOR: SINGLE-OP}\n      offTime:\n        minimumMinutes: x\n", .error(6, 25)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  rules:\n    - when: {OPERATOR: SINGLE-OP}\n      offTime:\n        minimumMinutes: 99999999999\n", .error(6, 36)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  rules:\n    - when: {OPERATOR: SINGLE-OP}\n      offTime:\n        requiredMinutes: x\n", .error(6, 26)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  rules:\n    - when: {OPERATOR: SINGLE-OP}\n      offTime:\n        requiredMinutes: 99999999999\n", .error(6, 37)),
        // ── wrong types: BandChange
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  bandChange:\n    minimumMinutes: x\n", .error(4, 21)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  bandChange:\n    minimumMinutes: 99999999999\n", .error(4, 32)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  bandChange:\n    perHour: x\n", .error(4, 14)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  bandChange:\n    perHour: 99999999999\n", .error(4, 25)),
        // ── wrong types: BandChange(rule)
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  rules:\n    - bandChange:\n        minimumMinutes: x\n", .error(5, 25)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  rules:\n    - bandChange:\n        minimumMinutes: 99999999999\n", .error(5, 36)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\noperating:\n  rules:\n    - bandChange:\n        perHour: x\n", .error(5, 18)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\noperating:\n  rules:\n    - bandChange:\n        perHour: 99999999999\n", .error(5, 29)),
        // ── wrong types: Metadata
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata:\n  name: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmetadata:\n  name: {a: 1}\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata:\n  organizer: [a]\n", .error(3, 14)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmetadata:\n  organizer: {a: 1}\n", .error(3, 14)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata:\n  description: [a]\n", .error(3, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmetadata:\n  description: {a: 1}\n", .error(3, 16)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata:\n  officialUrl: [a]\n", .error(3, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmetadata:\n  officialUrl: {a: 1}\n", .error(3, 16)),
        // ── wrong types: Period
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nperiod:\n  durationHours: x\n", .error(3, 18)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nperiod:\n  durationHours: 99999999999\n", .error(3, 29)),
        // Cannot construct instance of `ContestDefinition$Sessions` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nperiod:\n  sessions: x\n", .error(3, 13)),
        // Cannot deserialize value of type `ContestDefinition$Sessions` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nperiod:\n  sessions: []\n", .error(3, 13)),
        // Cannot coerce empty String ("") to `ContestDefinition$Sessions` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nperiod:\n  sessions: \"\"\n", .error(3, 13)),
        // ── wrong types: Sessions
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nperiod:\n  durationHours: 24\n  sessions:\n    start: [a]\n", .error(5, 12)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nperiod:\n  durationHours: 24\n  sessions:\n    start: {a: 1}\n", .error(5, 12)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nperiod:\n  durationHours: 24\n  sessions:\n    minutes: x\n", .error(5, 14)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nperiod:\n  durationHours: 24\n  sessions:\n    minutes: 99999999999\n", .error(5, 25)),
        // ── wrong types: Category
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncategories:\n  - id: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\ncategories:\n  - id: {a: 1}\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncategories:\n  - label: [a]\n", .error(3, 12)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\ncategories:\n  - label: {a: 1}\n", .error(3, 12)),
        // ── wrong types: StationClass
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: {a: 1}\n", .error(3, 9)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - when: x\n", .error(3, 11)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - when: []\n", .error(3, 11)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - when: \"\"\n", .error(3, 11)),
        // ── wrong types: Exchange
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$ExchangeField>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nexchange:\n  sent: x\n", .error(3, 9)),
        // Cannot construct instance of `ContestDefinition$ExchangeField` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  sent: [x]\n", .error(3, 10)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$ExchangeField>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  sent: {a: 1}\n", .error(3, 9)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$ExchangeField>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nexchange:\n  received: x\n", .error(3, 13)),
        // Cannot construct instance of `ContestDefinition$ExchangeField` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  received: [x]\n", .error(3, 14)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$ExchangeField>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  received: {a: 1}\n", .error(3, 13)),
        // ── wrong types: ExchangeField(sent)
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - id: [a]\n", .error(4, 11)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  sent:\n    - id: {a: 1}\n", .error(4, 11)),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from String "rst": not one of the values accepted for Enum class: [QTC, RS, HQ, TEXT, DISTRICT, PROVINCE, STATE, NATIONAL, IOTA, SERIAL, LOCATOR, CQ_ZONE, INTEGER, ITU_ZONE, RST, DXCC, PREFIX]
        .init("id: t\nexchange:\n  sent:\n    - type: rst\n", .error(4, 13)),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - type: [x]\n", .error(4, 13)),
        // Cannot deserialize value of type `boolean` from String "ano": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\nexchange:\n  sent:\n    - required: ano\n", .error(4, 17)),
        // Cannot deserialize value of type `boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nexchange:\n  sent:\n    - required: 1.5\n", .error(4, 17)),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from String "manual": not one of the values accepted for Enum class: [AUTO_RST, AUTO_SERIAL, MANUAL, ROVER_QTH, DERIVED, FROM_STATION]
        .init("id: t\nexchange:\n  sent:\n    - source: manual\n", .error(4, 15)),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - source: [x]\n", .error(4, 15)),
        // Cannot construct instance of `ContestDefinition$AppliesWhen` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  sent:\n    - appliesWhen: x\n", .error(4, 20)),
        // Cannot deserialize value of type `ContestDefinition$AppliesWhen` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - appliesWhen: []\n", .error(4, 20)),
        // Cannot coerce empty String ("") to `ContestDefinition$AppliesWhen` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nexchange:\n  sent:\n    - appliesWhen: \"\"\n", .error(4, 20)),
        // Cannot construct instance of `ContestDefinition$FieldValidation` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  sent:\n    - validation: x\n", .error(4, 19)),
        // Cannot deserialize value of type `ContestDefinition$FieldValidation` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - validation: []\n", .error(4, 19)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldValidation` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nexchange:\n  sent:\n    - validation: \"\"\n", .error(4, 19)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  sent:\n    - estimate: [a]\n", .error(4, 17)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  sent:\n    - estimate: {a: 1}\n", .error(4, 17)),
        // ── wrong types: ExchangeField(received)
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - id: [a]\n", .error(4, 11)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  received:\n    - id: {a: 1}\n", .error(4, 11)),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from String "rst": not one of the values accepted for Enum class: [QTC, RS, HQ, TEXT, DISTRICT, PROVINCE, STATE, NATIONAL, IOTA, SERIAL, LOCATOR, CQ_ZONE, INTEGER, ITU_ZONE, RST, DXCC, PREFIX]
        .init("id: t\nexchange:\n  received:\n    - type: rst\n", .error(4, 13)),
        // Cannot deserialize value of type `ContestDefinition$FieldType` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - type: [x]\n", .error(4, 13)),
        // Cannot deserialize value of type `boolean` from String "ano": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\nexchange:\n  received:\n    - required: ano\n", .error(4, 17)),
        // Cannot deserialize value of type `boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nexchange:\n  received:\n    - required: 1.5\n", .error(4, 17)),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from String "manual": not one of the values accepted for Enum class: [AUTO_RST, AUTO_SERIAL, MANUAL, ROVER_QTH, DERIVED, FROM_STATION]
        .init("id: t\nexchange:\n  received:\n    - source: manual\n", .error(4, 15)),
        // Cannot deserialize value of type `ContestDefinition$FieldSource` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - source: [x]\n", .error(4, 15)),
        // Cannot construct instance of `ContestDefinition$AppliesWhen` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  received:\n    - appliesWhen: x\n", .error(4, 20)),
        // Cannot deserialize value of type `ContestDefinition$AppliesWhen` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - appliesWhen: []\n", .error(4, 20)),
        // Cannot coerce empty String ("") to `ContestDefinition$AppliesWhen` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nexchange:\n  received:\n    - appliesWhen: \"\"\n", .error(4, 20)),
        // Cannot construct instance of `ContestDefinition$FieldValidation` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nexchange:\n  received:\n    - validation: x\n", .error(4, 19)),
        // Cannot deserialize value of type `ContestDefinition$FieldValidation` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - validation: []\n", .error(4, 19)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldValidation` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nexchange:\n  received:\n    - validation: \"\"\n", .error(4, 19)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - estimate: [a]\n", .error(4, 17)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  received:\n    - estimate: {a: 1}\n", .error(4, 17)),
        // ── wrong types: AppliesWhen
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      appliesWhen:\n        workedClass: [a]\n", .error(6, 22)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      appliesWhen:\n        workedClass: {a: 1}\n", .error(6, 22)),
        // ── wrong types: FieldValidation
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        regex: [a]\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        regex: {a: 1}\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        min: x\n", .error(6, 14)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        min: 99999999999\n", .error(6, 25)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        max: x\n", .error(6, 14)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        max: 99999999999\n", .error(6, 25)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        length: x\n", .error(6, 17)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nexchange:\n  received:\n    - id: a\n      validation:\n        length: 99999999999\n", .error(6, 28)),
        // ── wrong types: Condition
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf: x\n", .error(5, 14)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf: [x]\n", .error(5, 15)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf: {a: 1}\n", .error(5, 14)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      anyOf: x\n", .error(5, 14)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      anyOf: [x]\n", .error(5, 15)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      anyOf: {a: 1}\n", .error(5, 14)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      not: x\n", .error(5, 12)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      not: []\n", .error(5, 12)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      not: \"\"\n", .error(5, 12)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      ownDxcc: ano\n", .error(5, 16)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      ownDxcc: 1.5\n", .error(5, 16)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      sameDxcc: ano\n", .error(5, 17)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      sameDxcc: 1.5\n", .error(5, 17)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      sameContinent: ano\n", .error(5, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      sameContinent: 1.5\n", .error(5, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      otherContinent: ano\n", .error(5, 23)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      otherContinent: 1.5\n", .error(5, 23)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      continentIs: [a]\n", .error(5, 20)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      continentIs: {a: 1}\n", .error(5, 20)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      ownContinentIs: [a]\n", .error(5, 23)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      ownContinentIs: {a: 1}\n", .error(5, 23)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      workedClass: [a]\n", .error(5, 20)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      workedClass: {a: 1}\n", .error(5, 20)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      dxccIn: 20m\n", .error(5, 15)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      dxccIn: \"\"\n", .error(5, 15)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      dxccIn: [[a]]\n", .error(5, 16)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      bandIn: 20m\n", .error(5, 15)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      bandIn: \"\"\n", .error(5, 15)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      bandIn: [[a]]\n", .error(5, 16)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      mode: [a]\n", .error(5, 13)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      mode: {a: 1}\n", .error(5, 13)),
        // Cannot construct instance of `ContestDefinition$FieldEquals` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals: x\n", .error(5, 20)),
        // Cannot deserialize value of type `ContestDefinition$FieldEquals` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals: []\n", .error(5, 20)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldEquals` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals: \"\"\n", .error(5, 20)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldPresent: [a]\n", .error(5, 21)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldPresent: {a: 1}\n", .error(5, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      expr: [a]\n", .error(5, 13)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      expr: {a: 1}\n", .error(5, 13)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      bonusStation: ano\n", .error(5, 21)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      bonusStation: 1.5\n", .error(5, 21)),
        // ── wrong types: Condition(allOf)
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - allOf: x\n", .error(6, 18)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - allOf: [x]\n", .error(6, 19)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - allOf: {a: 1}\n", .error(6, 18)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - anyOf: x\n", .error(6, 18)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - anyOf: [x]\n", .error(6, 19)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - anyOf: {a: 1}\n", .error(6, 18)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - not: x\n", .error(6, 16)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - not: []\n", .error(6, 16)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - not: \"\"\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - ownDxcc: ano\n", .error(6, 20)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - ownDxcc: 1.5\n", .error(6, 20)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - sameDxcc: ano\n", .error(6, 21)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - sameDxcc: 1.5\n", .error(6, 21)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - sameContinent: ano\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - sameContinent: 1.5\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - otherContinent: ano\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - otherContinent: 1.5\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - continentIs: [a]\n", .error(6, 24)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - continentIs: {a: 1}\n", .error(6, 24)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - ownContinentIs: [a]\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - ownContinentIs: {a: 1}\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - workedClass: [a]\n", .error(6, 24)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - workedClass: {a: 1}\n", .error(6, 24)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - dxccIn: 20m\n", .error(6, 19)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - dxccIn: \"\"\n", .error(6, 19)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - dxccIn: [[a]]\n", .error(6, 20)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - bandIn: 20m\n", .error(6, 19)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - bandIn: \"\"\n", .error(6, 19)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - bandIn: [[a]]\n", .error(6, 20)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - mode: [a]\n", .error(6, 17)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - mode: {a: 1}\n", .error(6, 17)),
        // Cannot construct instance of `ContestDefinition$FieldEquals` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - fieldEquals: x\n", .error(6, 24)),
        // Cannot deserialize value of type `ContestDefinition$FieldEquals` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - fieldEquals: []\n", .error(6, 24)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldEquals` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - fieldEquals: \"\"\n", .error(6, 24)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - fieldPresent: [a]\n", .error(6, 25)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - fieldPresent: {a: 1}\n", .error(6, 25)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - expr: [a]\n", .error(6, 17)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - expr: {a: 1}\n", .error(6, 17)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - bonusStation: ano\n", .error(6, 25)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      allOf:\n        - bonusStation: 1.5\n", .error(6, 25)),
        // ── wrong types: Condition(anyOf)
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - allOf: x\n", .error(6, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - allOf: [x]\n", .error(6, 21)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - allOf: {a: 1}\n", .error(6, 20)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - anyOf: x\n", .error(6, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - anyOf: [x]\n", .error(6, 21)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - anyOf: {a: 1}\n", .error(6, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - not: x\n", .error(6, 18)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - not: []\n", .error(6, 18)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - not: \"\"\n", .error(6, 18)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - ownDxcc: ano\n", .error(6, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - ownDxcc: 1.5\n", .error(6, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - sameDxcc: ano\n", .error(6, 23)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - sameDxcc: 1.5\n", .error(6, 23)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - sameContinent: ano\n", .error(6, 28)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - sameContinent: 1.5\n", .error(6, 28)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - otherContinent: ano\n", .error(6, 29)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - otherContinent: 1.5\n", .error(6, 29)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - continentIs: [a]\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - continentIs: {a: 1}\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - ownContinentIs: [a]\n", .error(6, 29)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - ownContinentIs: {a: 1}\n", .error(6, 29)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - workedClass: [a]\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - workedClass: {a: 1}\n", .error(6, 26)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - dxccIn: 20m\n", .error(6, 21)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - dxccIn: \"\"\n", .error(6, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - dxccIn: [[a]]\n", .error(6, 22)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - bandIn: 20m\n", .error(6, 21)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - bandIn: \"\"\n", .error(6, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - bandIn: [[a]]\n", .error(6, 22)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - mode: [a]\n", .error(6, 19)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - mode: {a: 1}\n", .error(6, 19)),
        // Cannot construct instance of `ContestDefinition$FieldEquals` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - fieldEquals: x\n", .error(6, 26)),
        // Cannot deserialize value of type `ContestDefinition$FieldEquals` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - fieldEquals: []\n", .error(6, 26)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldEquals` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - fieldEquals: \"\"\n", .error(6, 26)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - fieldPresent: [a]\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - fieldPresent: {a: 1}\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - expr: [a]\n", .error(6, 19)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - expr: {a: 1}\n", .error(6, 19)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - bonusStation: ano\n", .error(6, 27)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  bonuses:\n    - when:\n        anyOf:\n          - bonusStation: 1.5\n", .error(6, 27)),
        // ── wrong types: Condition(not)
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            allOf: x\n", .error(7, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            allOf: [x]\n", .error(7, 21)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            allOf: {a: 1}\n", .error(7, 20)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            anyOf: x\n", .error(7, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            anyOf: [x]\n", .error(7, 21)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Condition>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            anyOf: {a: 1}\n", .error(7, 20)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            not: x\n", .error(7, 18)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            not: []\n", .error(7, 18)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            not: \"\"\n", .error(7, 18)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            ownDxcc: ano\n", .error(7, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            ownDxcc: 1.5\n", .error(7, 22)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            sameDxcc: ano\n", .error(7, 23)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            sameDxcc: 1.5\n", .error(7, 23)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            sameContinent: ano\n", .error(7, 28)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            sameContinent: 1.5\n", .error(7, 28)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            otherContinent: ano\n", .error(7, 29)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            otherContinent: 1.5\n", .error(7, 29)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            continentIs: [a]\n", .error(7, 26)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            continentIs: {a: 1}\n", .error(7, 26)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            ownContinentIs: [a]\n", .error(7, 29)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            ownContinentIs: {a: 1}\n", .error(7, 29)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            workedClass: [a]\n", .error(7, 26)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            workedClass: {a: 1}\n", .error(7, 26)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            dxccIn: 20m\n", .error(7, 21)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            dxccIn: \"\"\n", .error(7, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            dxccIn: [[a]]\n", .error(7, 22)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            bandIn: 20m\n", .error(7, 21)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            bandIn: \"\"\n", .error(7, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            bandIn: [[a]]\n", .error(7, 22)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            mode: [a]\n", .error(7, 19)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            mode: {a: 1}\n", .error(7, 19)),
        // Cannot construct instance of `ContestDefinition$FieldEquals` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            fieldEquals: x\n", .error(7, 26)),
        // Cannot deserialize value of type `ContestDefinition$FieldEquals` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            fieldEquals: []\n", .error(7, 26)),
        // Cannot coerce empty String ("") to `ContestDefinition$FieldEquals` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            fieldEquals: \"\"\n", .error(7, 26)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            fieldPresent: [a]\n", .error(7, 27)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            fieldPresent: {a: 1}\n", .error(7, 27)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            expr: [a]\n", .error(7, 19)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            expr: {a: 1}\n", .error(7, 19)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            bonusStation: ano\n", .error(7, 27)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when:\n          not:\n            bonusStation: 1.5\n", .error(7, 27)),
        // ── wrong types: FieldEquals
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals:\n        field: [a]\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals:\n        field: {a: 1}\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals:\n        value: [a]\n", .error(6, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nstationClasses:\n  - id: a\n    when:\n      fieldEquals:\n        value: {a: 1}\n", .error(6, 16)),
        // ── wrong types: Scoring
        // Cannot construct instance of `ContestDefinition$QsoPoints` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints: x\n", .error(3, 14)),
        // Cannot deserialize value of type `ContestDefinition$QsoPoints` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints: []\n", .error(3, 14)),
        // Cannot coerce empty String ("") to `ContestDefinition$QsoPoints` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints: \"\"\n", .error(3, 14)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Bonus>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  bonuses: x\n", .error(3, 12)),
        // Cannot construct instance of `ContestDefinition$Bonus` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses: [x]\n", .error(3, 13)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$Bonus>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses: {a: 1}\n", .error(3, 12)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  total: [a]\n", .error(3, 10)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  total: {a: 1}\n", .error(3, 10)),
        // Cannot construct instance of `ContestDefinition$Qtc` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qtc: x\n", .error(3, 8)),
        // Cannot deserialize value of type `ContestDefinition$Qtc` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qtc: []\n", .error(3, 8)),
        // Cannot coerce empty String ("") to `ContestDefinition$Qtc` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qtc: \"\"\n", .error(3, 8)),
        // ── wrong types: Qtc
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qtc:\n    points: x\n", .error(4, 13)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qtc:\n    points: 99999999999\n", .error(4, 24)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qtc:\n    maxPerStation: x\n", .error(4, 20)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qtc:\n    maxPerStation: 99999999999\n", .error(4, 31)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qtc:\n    groupSize: x\n", .error(4, 16)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qtc:\n    groupSize: 99999999999\n", .error(4, 27)),
        // ── wrong types: QsoPoints
        // Cannot deserialize value of type `ContestDefinition$PointsMode` from String "first_match": not one of the values accepted for Enum class: [SUM, FIRST_MATCH]
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: first_match\n", .error(4, 11)),
        // Cannot deserialize value of type `ContestDefinition$PointsMode` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    mode: [x]\n", .error(4, 11)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nscoring:\n  qsoPoints:\n    default: x\n", .error(4, 14)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$PointRule>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules: x\n", .error(4, 12)),
        // Cannot construct instance of `ContestDefinition$PointRule` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules: [x]\n", .error(4, 13)),
        // Cannot deserialize value of type `java.util.ArrayList<ContestDefinition$PointRule>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules: {a: 1}\n", .error(4, 12)),
        // ── wrong types: PointRule
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when: x\n", .error(5, 15)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when: []\n", .error(5, 15)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - when: \"\"\n", .error(5, 15)),
        // Cannot construct instance of `ContestDefinition$PointValue` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value: x\n", .error(5, 16)),
        // Cannot deserialize value of type `ContestDefinition$PointValue` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value: []\n", .error(5, 16)),
        // Cannot coerce empty String ("") to `ContestDefinition$PointValue` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value: \"\"\n", .error(5, 16)),
        // ── wrong types: PointValue
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          fixed: x\n", .error(6, 18)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          fixed: 99999999999\n", .error(6, 29)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          expr: [a]\n", .error(6, 17)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          expr: {a: 1}\n", .error(6, 17)),
        // Cannot construct instance of `ContestDefinition$PerKm` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: x\n", .error(6, 18)),
        // Cannot deserialize value of type `ContestDefinition$PerKm` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: []\n", .error(6, 18)),
        // Cannot coerce empty String ("") to `ContestDefinition$PerKm` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm: \"\"\n", .error(6, 18)),
        // ── wrong types: PointValue(bonus)
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        fixed: x\n", .error(5, 16)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        fixed: 99999999999\n", .error(5, 27)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        expr: [a]\n", .error(5, 15)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        expr: {a: 1}\n", .error(5, 15)),
        // Cannot construct instance of `ContestDefinition$PerKm` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        perKm: x\n", .error(5, 16)),
        // Cannot deserialize value of type `ContestDefinition$PerKm` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        perKm: []\n", .error(5, 16)),
        // Cannot coerce empty String ("") to `ContestDefinition$PerKm` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - value:\n        perKm: \"\"\n", .error(5, 16)),
        // ── wrong types: PerKm
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            field: [a]\n", .error(7, 20)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            field: {a: 1}\n", .error(7, 20)),
        // Cannot deserialize value of type `double` from String "abc": not a valid `double` value (as String to convert)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            factor: abc\n", .error(7, 21)),
        // Cannot deserialize value of type `double` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            factor: [1]\n", .error(7, 21)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            round: [a]\n", .error(7, 20)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            round: {a: 1}\n", .error(7, 20)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            min: x\n", .error(7, 18)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            min: 99999999999\n", .error(7, 29)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            max: x\n", .error(7, 18)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nscoring:\n  qsoPoints:\n    rules:\n      - value:\n          perKm:\n            max: 99999999999\n", .error(7, 29)),
        // ── wrong types: Bonus
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - id: [a]\n", .error(4, 11)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nscoring:\n  bonuses:\n    - id: {a: 1}\n", .error(4, 11)),
        // Cannot construct instance of `ContestDefinition$Condition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - when: x\n", .error(4, 13)),
        // Cannot deserialize value of type `ContestDefinition$Condition` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - when: []\n", .error(4, 13)),
        // Cannot coerce empty String ("") to `ContestDefinition$Condition` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - when: \"\"\n", .error(4, 13)),
        // Cannot construct instance of `ContestDefinition$PointValue` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nscoring:\n  bonuses:\n    - value: x\n", .error(4, 14)),
        // Cannot deserialize value of type `ContestDefinition$PointValue` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - value: []\n", .error(4, 14)),
        // Cannot coerce empty String ("") to `ContestDefinition$PointValue` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nscoring:\n  bonuses:\n    - value: \"\"\n", .error(4, 14)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\nscoring:\n  bonuses:\n    - scope: per_band\n", .error(4, 14)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nscoring:\n  bonuses:\n    - scope: [x]\n", .error(4, 14)),
        // ── wrong types: MultiplierBinding
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - id: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers:\n  - id: {a: 1}\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - set: [a]\n", .error(3, 10)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers:\n  - set: {a: 1}\n", .error(3, 10)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - from: [a]\n", .error(3, 11)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers:\n  - from: {a: 1}\n", .error(3, 11)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\nmultipliers:\n  - scope: per_band\n", .error(3, 12)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - scope: [x]\n", .error(3, 12)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - label: [a]\n", .error(3, 12)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers:\n  - label: {a: 1}\n", .error(3, 12)),
        // Cannot construct instance of `ContestDefinition$AppliesWhen` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nmultipliers:\n  - appliesWhen: x\n", .error(3, 18)),
        // Cannot deserialize value of type `ContestDefinition$AppliesWhen` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - appliesWhen: []\n", .error(3, 18)),
        // Cannot coerce empty String ("") to `ContestDefinition$AppliesWhen` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nmultipliers:\n  - appliesWhen: \"\"\n", .error(3, 18)),
        // Cannot construct instance of `java.util.LinkedHashMap` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nmultipliers:\n  - bandWeights: x\n", .error(3, 18)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nmultipliers:\n  - bandWeights: {a: x}\n", .error(3, 22)),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nmultipliers:\n  - bandWeights: {a: 99999999999}\n", .error(3, 33)),
        // ── wrong types: AppliesWhen(mult)
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmultipliers:\n  - id: m\n    appliesWhen:\n      workedClass: [a]\n", .error(5, 20)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmultipliers:\n  - id: m\n    appliesWhen:\n      workedClass: {a: 1}\n", .error(5, 20)),
        // ── wrong types: Dupe
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\ndupe:\n  scope: per_band\n", .error(3, 10)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ndupe:\n  scope: [x]\n", .error(3, 10)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\ndupe:\n  dupeWorthZero: ano\n", .error(3, 18)),
        // Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `JsonToken.VALUE_NUMBER_FLOAT`)
        .init("id: t\ndupe:\n  dupeWorthZero: 1.5\n", .error(3, 18)),
        // ── wrong types: Cabrillo
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncabrillo:\n  contestName: [a]\n", .error(3, 16)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\ncabrillo:\n  contestName: {a: 1}\n", .error(3, 16)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\ncabrillo:\n  sentOrder: 20m\n", .error(3, 14)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\ncabrillo:\n  sentOrder: \"\"\n", .error(3, 14)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncabrillo:\n  sentOrder: [[a]]\n", .error(3, 15)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\ncabrillo:\n  receivedOrder: 20m\n", .error(3, 18)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\ncabrillo:\n  receivedOrder: \"\"\n", .error(3, 18)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\ncabrillo:\n  receivedOrder: [[a]]\n", .error(3, 19)),
        // ── wrong types: Ui
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nui:\n  entryOrder: 20m\n", .error(3, 15)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nui:\n  entryOrder: \"\"\n", .error(3, 15)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nui:\n  entryOrder: [[a]]\n", .error(3, 16)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nui:\n  logColumns: 20m\n", .error(3, 15)),
        // Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nui:\n  logColumns: \"\"\n", .error(3, 15)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nui:\n  logColumns: [[a]]\n", .error(3, 16)),
        // ── CRLF a BOM
        .init("schemaVersion: 1\nid: full-test\nmetadata:\n  name: Plný závod\n  organizer: ORG\n  description: \"popis: s dvojtečkou\"\n  officialUrl: https://example.org/x\nperiod:\n  durationHours: 48\n  sessions:\n    start: \"1200\"\n    minutes: 30\nbands: [160m, 80m, ~]\nmodes: [CW, SSB]\ncategories:\n  - id: SO\n    label: Single\n  - ~\nstationClasses:\n  - id: wve\n    when:\n      anyOf:\n        - dxccIn: [K, VE]\n        - continentIs: NA\n          ownContinentIs: EU\n      not:\n        ownDxcc: false\n      allOf:\n        - sameDxcc: yes\n          sameContinent: no\n          otherContinent: true\n          workedClass: dx\n          bandIn: [20m]\n          mode: CW\n          fieldEquals: {field: state, value: ON}\n          fieldPresent: zone\n          expr: \"zone > 3\"\n          bonusStation: 1\nexchange:\n  sent:\n    - id: rst\n      type: RST\n      required: true\n      source: AUTO_RST\n    - id: nr\n      type: 2\n      source: AUTO_SERIAL\n      estimate: \"001\"\n  received:\n    - id: zone\n      type: CQ_ZONE\n      required: yes\n      source: MANUAL\n      appliesWhen: {workedClass: wve}\n      validation: {regex: \"^[0-9]+$\", min: 1, max: 40, length: 2}\n      estimate: cqZone\nscoring:\n  qsoPoints:\n    mode: SUM\n    default: 2\n    rules:\n      - when: {sameDxcc: true}\n        value: {fixed: 0}\n      - when: {otherContinent: true}\n        value: {expr: \"3 * n\"}\n      - value:\n          perKm: {field: locator, factor: 0.5, round: floor, min: 1, max: 1000}\n  bonuses:\n    - id: b1\n      when: {bonusStation: true}\n      value: {fixed: 100}\n      scope: ONCE\n  total: qsoPoints * multTotal\n  qtc: {points: 1, maxPerStation: 10, groupSize: 5}\nmultipliers:\n  - id: zones\n    set: cq_zones\n    from: zone\n    scope: PER_BAND\n    label: Zóny\n    appliesWhen: {workedClass: dx}\n    bandWeights: {80m: 4, 40m: 3}\n  - id: dxcc\n    set: dxcc_entities\n    from: callsign\n    scope: 1\ndupe:\n  scope: PER_BAND_MODE\n  dupeWorthZero: false\ncabrillo:\n  contestName: CQ-WW-CW\n  sentOrder: [rst, nr]\n  receivedOrder: [rst, zone]\nui:\n  entryOrder: [call, rst, zone]\n  logColumns: [time, call]\noperating:\n  offTime: {minimumMinutes: 60, requiredMinutes: 720}\n  bandChange: {minimumMinutes: 10, perHour: 8}\n  rules:\n    - when: {OPERATOR: MULTI-OP, TRANSMITTER: ONE}\n      offTime: {minimumMinutes: 30}\n      bandChange: {perHour: 10}\n    - {}\n", .ok("ContestDefinition[schemaVersion=1, id=full-test, metadata=Metadata[name=Plný závod, organizer=ORG, description=popis: s dvojtečkou, officialUrl=https://example.org/x], period=Period[durationHours=48, sessions=Sessions[start=1200, minutes=30]], bands=[160m, 80m, null], modes=[CW, SSB], categories=[Category[id=SO, label=Single], null], stationClasses=[StationClass[id=wve, when=Condition[allOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=false, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=dx, dxccIn=null, bandIn=[20m], mode=CW, fieldEquals=FieldEquals[field=state, value=ON], fieldPresent=zone, expr=zone > 3, bonusStation=true]], anyOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=[K, VE], bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=NA, ownContinentIs=EU, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]], not=Condition[allOf=null, anyOf=null, not=null, ownDxcc=false, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]]], exchange=Exchange[sent=[ExchangeField[id=rst, type=RST, required=true, source=AUTO_RST, appliesWhen=null, validation=null, estimate=null], ExchangeField[id=nr, type=SERIAL, required=false, source=AUTO_SERIAL, appliesWhen=null, validation=null, estimate=001]], received=[ExchangeField[id=zone, type=CQ_ZONE, required=true, source=MANUAL, appliesWhen=AppliesWhen[workedClass=wve], validation=FieldValidation[regex=^[0-9]+$, min=1, max=40, length=2], estimate=cqZone]]], scoring=Scoring[qsoPoints=QsoPoints[mode=SUM, defaultValue=2, rules=[PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=0, expr=null, perKm=null]], PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=null, expr=3 * n, perKm=null]], PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=locator, factor=0.5, round=floor, min=1, max=1000]]]]], bonuses=[Bonus[id=b1, when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=true], value=PointValue[fixed=100, expr=null, perKm=null], scope=ONCE]], total=qsoPoints * multTotal, qtc=Qtc[points=1, maxPerStation=10, groupSize=5]], multipliers=[MultiplierBinding[id=zones, set=cq_zones, from=zone, scope=PER_BAND, label=Zóny, appliesWhen=AppliesWhen[workedClass=dx], bandWeights={80m=4, 40m=3}], MultiplierBinding[id=dxcc, set=dxcc_entities, from=callsign, scope=PER_BAND_MODE, label=null, appliesWhen=null, bandWeights=null]], dupe=Dupe[scope=PER_BAND_MODE, dupeWorthZero=false], cabrillo=Cabrillo[contestName=CQ-WW-CW, sentOrder=[rst, nr], receivedOrder=[rst, zone]], ui=Ui[entryOrder=[call, rst, zone], logColumns=[time, call]], operating=Operating[offTime=OffTime[minimumMinutes=60, requiredMinutes=720], bandChange=BandChange[minimumMinutes=10, perHour=8], rules=[OperatingRule[when={OPERATOR=MULTI-OP, TRANSMITTER=ONE}, offTime=OffTime[minimumMinutes=30, requiredMinutes=null], bandChange=BandChange[minimumMinutes=null, perHour=10]], OperatingRule[when=null, offTime=null, bandChange=null]]]]")),
        .init("schemaVersion: 1\r\nid: full-test\r\nmetadata:\r\n  name: Plný závod\r\n  organizer: ORG\r\n  description: \"popis: s dvojtečkou\"\r\n  officialUrl: https://example.org/x\r\nperiod:\r\n  durationHours: 48\r\n  sessions:\r\n    start: \"1200\"\r\n    minutes: 30\r\nbands: [160m, 80m, ~]\r\nmodes: [CW, SSB]\r\ncategories:\r\n  - id: SO\r\n    label: Single\r\n  - ~\r\nstationClasses:\r\n  - id: wve\r\n    when:\r\n      anyOf:\r\n        - dxccIn: [K, VE]\r\n        - continentIs: NA\r\n          ownContinentIs: EU\r\n      not:\r\n        ownDxcc: false\r\n      allOf:\r\n        - sameDxcc: yes\r\n          sameContinent: no\r\n          otherContinent: true\r\n          workedClass: dx\r\n          bandIn: [20m]\r\n          mode: CW\r\n          fieldEquals: {field: state, value: ON}\r\n          fieldPresent: zone\r\n          expr: \"zone > 3\"\r\n          bonusStation: 1\r\nexchange:\r\n  sent:\r\n    - id: rst\r\n      type: RST\r\n      required: true\r\n      source: AUTO_RST\r\n    - id: nr\r\n      type: 2\r\n      source: AUTO_SERIAL\r\n      estimate: \"001\"\r\n  received:\r\n    - id: zone\r\n      type: CQ_ZONE\r\n      required: yes\r\n      source: MANUAL\r\n      appliesWhen: {workedClass: wve}\r\n      validation: {regex: \"^[0-9]+$\", min: 1, max: 40, length: 2}\r\n      estimate: cqZone\r\nscoring:\r\n  qsoPoints:\r\n    mode: SUM\r\n    default: 2\r\n    rules:\r\n      - when: {sameDxcc: true}\r\n        value: {fixed: 0}\r\n      - when: {otherContinent: true}\r\n        value: {expr: \"3 * n\"}\r\n      - value:\r\n          perKm: {field: locator, factor: 0.5, round: floor, min: 1, max: 1000}\r\n  bonuses:\r\n    - id: b1\r\n      when: {bonusStation: true}\r\n      value: {fixed: 100}\r\n      scope: ONCE\r\n  total: qsoPoints * multTotal\r\n  qtc: {points: 1, maxPerStation: 10, groupSize: 5}\r\nmultipliers:\r\n  - id: zones\r\n    set: cq_zones\r\n    from: zone\r\n    scope: PER_BAND\r\n    label: Zóny\r\n    appliesWhen: {workedClass: dx}\r\n    bandWeights: {80m: 4, 40m: 3}\r\n  - id: dxcc\r\n    set: dxcc_entities\r\n    from: callsign\r\n    scope: 1\r\ndupe:\r\n  scope: PER_BAND_MODE\r\n  dupeWorthZero: false\r\ncabrillo:\r\n  contestName: CQ-WW-CW\r\n  sentOrder: [rst, nr]\r\n  receivedOrder: [rst, zone]\r\nui:\r\n  entryOrder: [call, rst, zone]\r\n  logColumns: [time, call]\r\noperating:\r\n  offTime: {minimumMinutes: 60, requiredMinutes: 720}\r\n  bandChange: {minimumMinutes: 10, perHour: 8}\r\n  rules:\r\n    - when: {OPERATOR: MULTI-OP, TRANSMITTER: ONE}\r\n      offTime: {minimumMinutes: 30}\r\n      bandChange: {perHour: 10}\r\n    - {}\r\n", .ok("ContestDefinition[schemaVersion=1, id=full-test, metadata=Metadata[name=Plný závod, organizer=ORG, description=popis: s dvojtečkou, officialUrl=https://example.org/x], period=Period[durationHours=48, sessions=Sessions[start=1200, minutes=30]], bands=[160m, 80m, null], modes=[CW, SSB], categories=[Category[id=SO, label=Single], null], stationClasses=[StationClass[id=wve, when=Condition[allOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=false, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=dx, dxccIn=null, bandIn=[20m], mode=CW, fieldEquals=FieldEquals[field=state, value=ON], fieldPresent=zone, expr=zone > 3, bonusStation=true]], anyOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=[K, VE], bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=NA, ownContinentIs=EU, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]], not=Condition[allOf=null, anyOf=null, not=null, ownDxcc=false, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]]], exchange=Exchange[sent=[ExchangeField[id=rst, type=RST, required=true, source=AUTO_RST, appliesWhen=null, validation=null, estimate=null], ExchangeField[id=nr, type=SERIAL, required=false, source=AUTO_SERIAL, appliesWhen=null, validation=null, estimate=001]], received=[ExchangeField[id=zone, type=CQ_ZONE, required=true, source=MANUAL, appliesWhen=AppliesWhen[workedClass=wve], validation=FieldValidation[regex=^[0-9]+$, min=1, max=40, length=2], estimate=cqZone]]], scoring=Scoring[qsoPoints=QsoPoints[mode=SUM, defaultValue=2, rules=[PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=0, expr=null, perKm=null]], PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=null, expr=3 * n, perKm=null]], PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=locator, factor=0.5, round=floor, min=1, max=1000]]]]], bonuses=[Bonus[id=b1, when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=true], value=PointValue[fixed=100, expr=null, perKm=null], scope=ONCE]], total=qsoPoints * multTotal, qtc=Qtc[points=1, maxPerStation=10, groupSize=5]], multipliers=[MultiplierBinding[id=zones, set=cq_zones, from=zone, scope=PER_BAND, label=Zóny, appliesWhen=AppliesWhen[workedClass=dx], bandWeights={80m=4, 40m=3}], MultiplierBinding[id=dxcc, set=dxcc_entities, from=callsign, scope=PER_BAND_MODE, label=null, appliesWhen=null, bandWeights=null]], dupe=Dupe[scope=PER_BAND_MODE, dupeWorthZero=false], cabrillo=Cabrillo[contestName=CQ-WW-CW, sentOrder=[rst, nr], receivedOrder=[rst, zone]], ui=Ui[entryOrder=[call, rst, zone], logColumns=[time, call]], operating=Operating[offTime=OffTime[minimumMinutes=60, requiredMinutes=720], bandChange=BandChange[minimumMinutes=10, perHour=8], rules=[OperatingRule[when={OPERATOR=MULTI-OP, TRANSMITTER=ONE}, offTime=OffTime[minimumMinutes=30, requiredMinutes=null], bandChange=BandChange[minimumMinutes=null, perHour=10]], OperatingRule[when=null, offTime=null, bandChange=null]]]]")),
        .init("\u{FEFF}schemaVersion: 1\nid: full-test\nmetadata:\n  name: Plný závod\n  organizer: ORG\n  description: \"popis: s dvojtečkou\"\n  officialUrl: https://example.org/x\nperiod:\n  durationHours: 48\n  sessions:\n    start: \"1200\"\n    minutes: 30\nbands: [160m, 80m, ~]\nmodes: [CW, SSB]\ncategories:\n  - id: SO\n    label: Single\n  - ~\nstationClasses:\n  - id: wve\n    when:\n      anyOf:\n        - dxccIn: [K, VE]\n        - continentIs: NA\n          ownContinentIs: EU\n      not:\n        ownDxcc: false\n      allOf:\n        - sameDxcc: yes\n          sameContinent: no\n          otherContinent: true\n          workedClass: dx\n          bandIn: [20m]\n          mode: CW\n          fieldEquals: {field: state, value: ON}\n          fieldPresent: zone\n          expr: \"zone > 3\"\n          bonusStation: 1\nexchange:\n  sent:\n    - id: rst\n      type: RST\n      required: true\n      source: AUTO_RST\n    - id: nr\n      type: 2\n      source: AUTO_SERIAL\n      estimate: \"001\"\n  received:\n    - id: zone\n      type: CQ_ZONE\n      required: yes\n      source: MANUAL\n      appliesWhen: {workedClass: wve}\n      validation: {regex: \"^[0-9]+$\", min: 1, max: 40, length: 2}\n      estimate: cqZone\nscoring:\n  qsoPoints:\n    mode: SUM\n    default: 2\n    rules:\n      - when: {sameDxcc: true}\n        value: {fixed: 0}\n      - when: {otherContinent: true}\n        value: {expr: \"3 * n\"}\n      - value:\n          perKm: {field: locator, factor: 0.5, round: floor, min: 1, max: 1000}\n  bonuses:\n    - id: b1\n      when: {bonusStation: true}\n      value: {fixed: 100}\n      scope: ONCE\n  total: qsoPoints * multTotal\n  qtc: {points: 1, maxPerStation: 10, groupSize: 5}\nmultipliers:\n  - id: zones\n    set: cq_zones\n    from: zone\n    scope: PER_BAND\n    label: Zóny\n    appliesWhen: {workedClass: dx}\n    bandWeights: {80m: 4, 40m: 3}\n  - id: dxcc\n    set: dxcc_entities\n    from: callsign\n    scope: 1\ndupe:\n  scope: PER_BAND_MODE\n  dupeWorthZero: false\ncabrillo:\n  contestName: CQ-WW-CW\n  sentOrder: [rst, nr]\n  receivedOrder: [rst, zone]\nui:\n  entryOrder: [call, rst, zone]\n  logColumns: [time, call]\noperating:\n  offTime: {minimumMinutes: 60, requiredMinutes: 720}\n  bandChange: {minimumMinutes: 10, perHour: 8}\n  rules:\n    - when: {OPERATOR: MULTI-OP, TRANSMITTER: ONE}\n      offTime: {minimumMinutes: 30}\n      bandChange: {perHour: 10}\n    - {}\n", .ok("ContestDefinition[schemaVersion=1, id=full-test, metadata=Metadata[name=Plný závod, organizer=ORG, description=popis: s dvojtečkou, officialUrl=https://example.org/x], period=Period[durationHours=48, sessions=Sessions[start=1200, minutes=30]], bands=[160m, 80m, null], modes=[CW, SSB], categories=[Category[id=SO, label=Single], null], stationClasses=[StationClass[id=wve, when=Condition[allOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=false, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=dx, dxccIn=null, bandIn=[20m], mode=CW, fieldEquals=FieldEquals[field=state, value=ON], fieldPresent=zone, expr=zone > 3, bonusStation=true]], anyOf=[Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=[K, VE], bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=NA, ownContinentIs=EU, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]], not=Condition[allOf=null, anyOf=null, not=null, ownDxcc=false, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null]]], exchange=Exchange[sent=[ExchangeField[id=rst, type=RST, required=true, source=AUTO_RST, appliesWhen=null, validation=null, estimate=null], ExchangeField[id=nr, type=SERIAL, required=false, source=AUTO_SERIAL, appliesWhen=null, validation=null, estimate=001]], received=[ExchangeField[id=zone, type=CQ_ZONE, required=true, source=MANUAL, appliesWhen=AppliesWhen[workedClass=wve], validation=FieldValidation[regex=^[0-9]+$, min=1, max=40, length=2], estimate=cqZone]]], scoring=Scoring[qsoPoints=QsoPoints[mode=SUM, defaultValue=2, rules=[PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=true, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=0, expr=null, perKm=null]], PointRule[when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=true, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=null], value=PointValue[fixed=null, expr=3 * n, perKm=null]], PointRule[when=null, value=PointValue[fixed=null, expr=null, perKm=PerKm[field=locator, factor=0.5, round=floor, min=1, max=1000]]]]], bonuses=[Bonus[id=b1, when=Condition[allOf=null, anyOf=null, not=null, ownDxcc=null, sameDxcc=null, sameContinent=null, otherContinent=null, continentIs=null, ownContinentIs=null, workedClass=null, dxccIn=null, bandIn=null, mode=null, fieldEquals=null, fieldPresent=null, expr=null, bonusStation=true], value=PointValue[fixed=100, expr=null, perKm=null], scope=ONCE]], total=qsoPoints * multTotal, qtc=Qtc[points=1, maxPerStation=10, groupSize=5]], multipliers=[MultiplierBinding[id=zones, set=cq_zones, from=zone, scope=PER_BAND, label=Zóny, appliesWhen=AppliesWhen[workedClass=dx], bandWeights={80m=4, 40m=3}], MultiplierBinding[id=dxcc, set=dxcc_entities, from=callsign, scope=PER_BAND_MODE, label=null, appliesWhen=null, bandWeights=null]], dupe=Dupe[scope=PER_BAND_MODE, dupeWorthZero=false], cabrillo=Cabrillo[contestName=CQ-WW-CW, sentOrder=[rst, nr], receivedOrder=[rst, zone]], ui=Ui[entryOrder=[call, rst, zone], logColumns=[time, call]], operating=Operating[offTime=OffTime[minimumMinutes=60, requiredMinutes=720], bandChange=BandChange[minimumMinutes=10, perHour=8], rules=[OperatingRule[when={OPERATOR=MULTI-OP, TRANSMITTER=ONE}, offTime=OffTime[minimumMinutes=30, requiredMinutes=null], bandChange=BandChange[minimumMinutes=null, perHour=10]], OperatingRule[when=null, offTime=null, bandChange=null]]]]")),
        // No content to map due to end-of-input
        .init("\u{FEFF}", .error(1, 1)),
        .init("\u{FEFF}id: t\n", .ok("ContestDefinition[schemaVersion=0, id=t, metadata=null, period=null, bands=null, modes=null, categories=null, stationClasses=null, exchange=null, scoring=null, multipliers=null, dupe=null, cabrillo=null, ui=null, operating=null]")),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "x": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("\u{FEFF}id: t\ndupe: {scope: x}\n", .error(2, 15)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\r\ndupe:\r\n  scope: per_band\r\n", .error(3, 10)),
        // Cannot deserialize value of type `boolean` from String "ano": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\r\nexchange:\r\n  received:\r\n    - id: a\r\n      required: ano\r\n", .error(5, 17)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\r\nbands: 20m\r\n", .error(2, 8)),
        // Cannot deserialize value of type `boolean` from String "ano": only "true"/"True"/"TRUE" or "false"/"False"/"FALSE" recognized
        .init("id: t\nexchange:\n  received:\n    - id: a\n      required: ano\n", .error(5, 17)),
        // Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('20m')
        .init("id: t\nbands: 20m\n", .error(2, 8)),
        // Cannot deserialize value of type `ContestDefinition$Scope` from String "per_band": not one of the values accepted for Enum class: [ONCE, PER_BAND_MODE, PER_MODE, PER_BAND]
        .init("id: t\ndupe:\n  scope: per_band\n", .error(3, 10)),
    ]

    @Test(arguments: cases)
    func loadMatchesJava(_ testCase: Case) {
        let result = Result { () throws(ContestDefinitionError) in
            try ContestDefinitionLoader.load(Data(testCase.yaml.utf8))
        }
        switch (testCase.expected, result) {
        case (.ok(let java), .success(let definition)):
            #expect(definition.javaDescription == java)
        case (.error(let line, let column), .failure(.invalidDefinition(let yaml))):
            #expect(yaml.line == line && yaml.column == column, "Java \(line):\(column), Swift \(yaml)")
        case (.empty, .failure(.emptyDefinition)):
            break
        case (.newer(let version), .failure(.newerSchema(let actual))):
            #expect(actual == version)
        default:
            Issue.record("Java \(testCase.expected), Swift \(result)")
        }
    }

    // MARK: - Three places where Jackson does something unexpected (source 3.1)

    /// `period` also accepts a scalar (Java constructor `Period(Integer)`): a number
    /// and numeric text. **A decimal number does not** — source 3.1 and the task
    /// assignment claim `1.5` → 1, the probe showed an error at 2:9.
    @Test func periodAcceptsIntegerScalar() throws {
        for yaml in ["period: 24\n", "period: \"24\"\n", "period: \" 24 \"\n", "period: 0x18\n", "period: !!str 24\n"] {
            let definition = try ContestDefinitionLoader.load(Data(("id: t\n" + yaml).utf8))
            #expect(definition.period == ContestDefinition.Period(durationHours: 24, sessions: nil), "\(yaml)")
        }
        for yaml in ["period: 1.5\n", "period: \"\"\n", "period: \"null\"\n", "period: true\n", "period: [24]\n",
                     "period: 99999999999\n"] {
            #expect(throws: ContestDefinitionError.self, "\(yaml)") {
                try ContestDefinitionLoader.load(Data(("id: t\n" + yaml).utf8))
            }
        }
    }

    /// An enum can also be given by ordinal (`FAIL_ON_NUMBERS_FOR_ENUMS` disabled).
    @Test func enumAcceptsOrdinal() throws {
        let yaml = """
            id: t
            dupe: { scope: 1 }
            exchange: { received: [ { id: a, type: 16, source: 5 } ] }
            scoring: { qsoPoints: { mode: 1 } }
            """
        let definition = try ContestDefinitionLoader.load(Data(yaml.utf8))
        #expect(definition.dupe?.scope == .PER_BAND_MODE)
        #expect(definition.exchange?.received?.first??.type == .QTC)
        #expect(definition.exchange?.received?.first??.source == .ROVER_QTH)
        #expect(definition.scoring?.qsoPoints?.mode == .SUM)
    }

    /// `schemaVersion > 1` is an error, a lower one (including 0 and negatives) passes.
    @Test func newerSchemaVersionIsRejected() throws {
        #expect(throws: ContestDefinitionError.newerSchema(2)) {
            try ContestDefinitionLoader.load(Data("id: t\nschemaVersion: 2\n".utf8))
        }
        #expect(ContestDefinitionError.newerSchema(2).message
                    == "Novější formát definice (schemaVersion=2), aktualizuj aplikaci. Podporováno: 1")
        for version in [1, 0, -5] {
            #expect(try ContestDefinitionLoader.load(Data("id: t\nschemaVersion: \(version)\n".utf8)).schemaVersion
                        == version)
        }
    }

    // MARK: - Review focus

    /// Focus 4: a type error deep in the definition rejects the **whole** definition
    /// with the line and column of the token (Java), it is never loaded with a default value.
    @Test func deepTypeErrorRejectsWholeDefinition() {
        let rows: [(String, Int, Int)] = [
            ("id: t\ndupe:\n  scope: per_band\n", 3, 10),
            ("id: t\nexchange:\n  received:\n    - id: a\n      required: ano\n", 5, 17),
            ("id: t\nbands: 20m\n", 2, 8),
        ]
        for (yaml, line, column) in rows {
            do {
                _ = try ContestDefinitionLoader.load(Data(yaml.utf8))
                Issue.record("\(yaml) should have failed")
            } catch {
                guard case .invalidDefinition(let cause) = error else {
                    Issue.record("expected .invalidDefinition, got \(error)")
                    continue
                }
                #expect(cause.kind == .type && cause.line == line && cause.column == column, "\(cause)")
            }
        }
    }

    /// Focus 2: a definition with CRLF (sent by e-mail from Windows) gives the same as LF,
    /// and error positions are counted the same (Java 3:10 / 5:17 / 2:8 — table rows).
    @Test func crlfDefinitionEqualsLf() throws {
        let lf = """
            schemaVersion: 1
            id: crlf
            metadata:
              name: "Závod: test"
              description: víceslovný popis
            period: { durationHours: 24, sessions: { start: "1200", minutes: 30 } }
            bands: [160m, 80m]
            exchange:
              received:
                - id: zone
                  type: CQ_ZONE
                  required: true
                  validation: { regex: "^[0-9]+$" }
            scoring:
              qsoPoints:
                mode: FIRST_MATCH
                default: 1
                rules:
                  - when: { sameDxcc: true }
                    value: { fixed: 0 }
            operating:
              rules:
                - when: { OPERATOR: SINGLE-OP }
                  offTime: { minimumMinutes: 60 }

            """
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let fromLf = try ContestDefinitionLoader.load(Data(lf.utf8))
        let fromCrlf = try ContestDefinitionLoader.load(Data(crlf.utf8))
        #expect(fromCrlf == fromLf)
        #expect(fromCrlf.metadata?.description == "víceslovný popis")
        #expect(fromCrlf.exchange?.received?.first??.validation?.regex == "^[0-9]+$")
    }

    /// Focus 3: Java (SnakeYAML) drops a BOM at the start of YAML and counts columns
    /// without it (`\u{FEFF}id: t` + `dupe: {scope: x}` → 2:15); a lone BOM is
    /// empty input at 1:1. Rows of the table `CRLF a BOM`; here additionally equality
    /// of the model with the BOM-less version.
    @Test func byteOrderMarkIsIgnored() throws {
        let text = "id: bom\nbands: [20m]\n"
        let withBom = try ContestDefinitionLoader.load(Data([0xEF, 0xBB, 0xBF] + Array(text.utf8)))
        #expect(withBom == (try ContestDefinitionLoader.load(Data(text.utf8))))
        #expect(withBom.id == "bom")
    }

    /// Decision no. 3 of the plan: a `~`/`---` document Java returns as `null`
    /// and `checkVersion` fails with an NPE → Swift "definice je prázdná". Empty
    /// text (even just a comment) is Java's "No content to map" with the position of the end of input.
    @Test func emptyDocuments() {
        for yaml in ["~\n", "---\n", "--- ~\n", "~"] {
            #expect(throws: ContestDefinitionError.emptyDefinition, "\(yaml)") {
                try ContestDefinitionLoader.load(Data(yaml.utf8))
            }
        }
        #expect(ContestDefinitionError.emptyDefinition.message == "definice je prázdná")
        for (yaml, line, column) in [("", 1, 1), ("\n# c\n", 3, 1)] {
            do {
                _ = try ContestDefinitionLoader.load(Data(yaml.utf8))
                Issue.record("empty input should have failed")
            } catch {
                guard case .invalidDefinition(let cause) = error else {
                    Issue.record("expected .invalidDefinition, got \(error)")
                    continue
                }
                #expect(cause.line == line && cause.column == column)
            }
        }
    }

    /// The model holds `nil`, not `""` (source 7.4): the validator and editing distinguish them.
    @Test func nullAndEmptyTextStayDistinct() throws {
        let definition = try ContestDefinitionLoader.load(Data("id: \"\"\nmetadata: { name: ~ }\nbands: [~, \"\"]\n".utf8))
        #expect(definition.id == "")
        #expect(definition.metadata?.name == nil)
        #expect(definition.bands == [nil, ""])
    }

    /// Java secondary constructors = default arguments `nil`; `Qtc.*OrDefault`.
    @Test func secondaryConstructorsAndQtcDefaults() {
        #expect(ContestDefinition.Period(durationHours: 24).sessions == nil)
        #expect(ContestDefinition.Operating(offTime: nil, bandChange: nil).rules == nil)
        #expect(ContestDefinition.Scoring(qsoPoints: nil, bonuses: nil, total: "x").qtc == nil)
        #expect(ContestDefinition.ExchangeField(id: "a", type: .RST, required: true, source: nil,
                                                appliesWhen: nil, validation: nil).estimate == nil)
        #expect(ContestDefinition.MultiplierBinding(id: "m", set: "s", from: "callsign", scope: .PER_BAND,
                                                    label: nil, appliesWhen: nil).bandWeights == nil)
        #expect(ContestDefinition.Condition(mode: "CW").bonusStation == nil)
        let empty = ContestDefinition.Qtc(points: nil, maxPerStation: nil, groupSize: nil)
        #expect(empty.pointsOrDefault == 1 && empty.maxPerStationOrDefault == 10 && empty.groupSizeOrDefault == 10)
        let set = ContestDefinition.Qtc(points: 2, maxPerStation: 5, groupSize: 3)
        #expect(set.pointsOrDefault == 2 && set.maxPerStationOrDefault == 5 && set.groupSizeOrDefault == 3)
    }

    /// A recursive `Condition.not` is read and written as an ordinary property.
    @Test func conditionNotIsRecursive() throws {
        let yaml = "id: t\nstationClasses:\n  - id: a\n    when: { not: { not: { ownDxcc: true } } }\n"
        let definition = try ContestDefinitionLoader.load(Data(yaml.utf8))
        let when = try #require(definition.stationClasses?.first??.when)
        #expect(when.not?.not?.ownDxcc == true)
        var changed = when
        changed.not = nil
        #expect(changed.not == nil && when.not != nil)
    }

    /// `javaDouble` = Java's `Double.toString` (a test helper only).
    @Test func javaDoubleFormatting() {
        let rows: [(Double, String)] = [
            (0, "0.0"), (1, "1.0"), (0.5, "0.5"), (1000, "1000.0"), (3.333333333e-4, "3.333333333E-4"),
            (0.001, "0.001"), (1e7, "1.0E7"), (1234567.5, "1234567.5"), (-2.5, "-2.5"), (1e-5, "1.0E-5"),
        ]
        for (value, java) in rows {
            #expect(javaDouble(value) == java)
        }
    }
}
