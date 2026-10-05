import Foundation
import Testing
@testable import MCLCore

/// `MultiplierSetLoader` against Java. The `cases` table is **generated from a running
/// Java**: the `ProbeDef` probe called `new MultiplierSetLoader().load(…)` (Jackson
/// 2.22.0 + SnakeYAML 2.5, Java v1.1.1) and printed either the `toString()` of the returned
/// record, `null`, or the line and column reported by `JsonProcessingException`
/// in the cause of `MultiplierException`. `javaDescription` below prints the Swift
/// definition the same way as Java `toString`, so the `.ok` row compares **all**
/// fields including unread ones (`schemaVersion`, `enumerable`, `metadata`,
/// `provider.data`) and nested records.
///
/// The "wrong types" section puts a wrong type into **every field of every record**
/// (`MultiplierSetDefinition`, `Meta`, `Range`, `Validation`, `ValueDef`,
/// `Provider`, `Algorithm`): Jackson checks the type even for fields nobody
/// reads afterwards (`enumerable: ano` fails even though `enumerable` is ignored).
@Suite struct MultiplierSetLoaderTests {

    enum Expected: Sendable {
        /// Java `toString()` of the loaded record.
        case ok(String)
        /// `MultiplierException` with a YAML/Jackson cause at line and column.
        case error(Int, Int)
        /// Java returns `null` (root `~`/`---`); Swift throws "definice je prázdná".
        case empty
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

    static let cases: [Case] = [
        // Sections in probe order: root, casts from, full record,
        // wrong root types, Meta, Range, Validation, ValueDef, Provider,
        // Algorithm, unknown keys and duplicates, error order, CRLF and BOM.
        // The comment at an error = the Java message (Swift has its own Czech one).
        // No content to map due to end-of-input
        .init("", .error(1, 1)),
        .init("~\n", .empty),
        .init("---\n", .empty),
        .init("--- ~\n", .empty),
        // Cannot construct instance of `MultiplierSetDefinition` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('hello')
        .init("hello\n", .error(1, 1)),
        // Cannot deserialize value of type `MultiplierSetDefinition` from Array value (token `JsonToken.START_ARRAY`)
        .init("- a\n", .error(1, 1)),
        .init("id: t\nkind: FIXED\nrange: { min: \"1\", max: 3 }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=Range[min=1, max=3], validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nkind: FIXED\nkeyLength: \"2\"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=2]")),
        .init("id: t\nkind: FIXED\nvalues:\n  - key: a\n    attributes: { n: 1, b: true, c: ~, d: 1.50 }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=[ValueDef[key=a, label=null, attributes={n=1, b=true, c=null, d=1.50}]], valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `MultiplierSetDefinition$SetKind` from String "fixed": not one of the values accepted for Enum class: [FIXED, EXTERNAL_DATA, ALGORITHM]
        .init("id: t\nkind: fixed\n", .error(2, 7)),
        .init("kind: FIXED\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=null, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nkind: 1\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=ALGORITHM, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nkind: \" FIXED \"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$SetKind` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nkind: \"\"\n", .error(2, 7)),
        .init("id: t\nkind: ~\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `MultiplierSetDefinition$KeyType` from String "text": not one of the values accepted for Enum class: [TEXT, CALLSIGN_PREFIX, INTEGER]
        .init("id: t\nkeyType: text\n", .error(2, 10)),
        .init("id: t\nkeyType: 2\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=CALLSIGN_PREFIX, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("schemaVersion: 1\nid: full\nkind: EXTERNAL_DATA\nkeyType: INTEGER\nenumerable: false\nmetadata: { name: N, description: D }\nrange: { min: 1, max: 40 }\nvalidation: { keyPattern: \"^[0-9]+$\" }\nvalues: [ { key: a, label: A }, ~, { key: b } ]\nvaluesFile: x.csv\nprovider: { type: dxcc-json, data: \"~/dxcc-json/dxcc.json\" }\nalgorithm: { type: wpx }\nkeyLength: 2\n", .ok("MultiplierSetDefinition[schemaVersion=1, id=full, kind=EXTERNAL_DATA, keyType=INTEGER, enumerable=false, metadata=Meta[name=N, description=D], range=Range[min=1, max=40], validation=Validation[keyPattern=^[0-9]+$], values=[ValueDef[key=a, label=A, attributes=null], null, ValueDef[key=b, label=null, attributes=null]], valuesFile=x.csv, provider=Provider[type=dxcc-json, data=~/dxcc-json/dxcc.json], algorithm=Algorithm[type=wpx], keyLength=2]")),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nschemaVersion: x\n", .error(2, 16)),
        .init("id: t\nschemaVersion: \"\"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nschemaVersion: ~\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nschemaVersion: 99999999999\n", .error(2, 27)),
        .init("id: t\nschemaVersion: 1.9\n", .ok("MultiplierSetDefinition[schemaVersion=1, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nid: [a]\n", .error(2, 5)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: [a]\n", .error(1, 5)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: {a: 1}\n", .error(1, 5)),
        .init("id: 5\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=5, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `MultiplierSetDefinition$SetKind` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nkind: [FIXED]\n", .error(2, 7)),
        // Cannot deserialize value of type `MultiplierSetDefinition$KeyType` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nkeyType: [TEXT]\n", .error(2, 10)),
        // Cannot deserialize value of type `MultiplierSetDefinition$KeyType` from String "CALLSIGN": not one of the values accepted for Enum class: [TEXT, CALLSIGN_PREFIX, INTEGER]
        .init("id: t\nkeyType: CALLSIGN\n", .error(2, 10)),
        // Cannot deserialize value of type `java.lang.Boolean` from String "ano": only "true" or "false" recognized
        .init("id: t\nenumerable: ano\n", .error(2, 13)),
        .init("id: t\nenumerable: \"\"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.Boolean` from String "yes": only "true" or "false" recognized
        .init("id: t\nenumerable: \"yes\"\n", .error(2, 13)),
        .init("id: t\nenumerable: 1\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=true, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.Boolean` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nenumerable: [true]\n", .error(2, 13)),
        // Cannot construct instance of `MultiplierSetDefinition$Meta` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nmetadata: x\n", .error(2, 11)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$Meta` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nmetadata: \"\"\n", .error(2, 11)),
        // Cannot deserialize value of type `MultiplierSetDefinition$Meta` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata: [a]\n", .error(2, 11)),
        // Cannot construct instance of `MultiplierSetDefinition$Range` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nrange: x\n", .error(2, 8)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$Range` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nrange: \"\"\n", .error(2, 8)),
        // Cannot deserialize value of type `MultiplierSetDefinition$Range` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nrange: [1, 2]\n", .error(2, 8)),
        // Cannot construct instance of `MultiplierSetDefinition$Validation` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nvalidation: x\n", .error(2, 13)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$Validation` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nvalidation: \"\"\n", .error(2, 13)),
        // Cannot deserialize value of type `MultiplierSetDefinition$Validation` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalidation: [a]\n", .error(2, 13)),
        // Cannot deserialize value of type `java.util.ArrayList<MultiplierSetDefinition$ValueDef>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nvalues: x\n", .error(2, 9)),
        // Cannot deserialize value of type `java.util.ArrayList<MultiplierSetDefinition$ValueDef>` from String value (token `JsonToken.VALUE_STRING`)
        .init("id: t\nvalues: \"\"\n", .error(2, 9)),
        // Cannot deserialize value of type `java.util.ArrayList<MultiplierSetDefinition$ValueDef>` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nvalues: {key: a}\n", .error(2, 9)),
        // Cannot construct instance of `MultiplierSetDefinition$ValueDef` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nvalues: [x]\n", .error(2, 10)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$ValueDef` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nvalues: [\"\"]\n", .error(2, 10)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvaluesFile: [a]\n", .error(2, 13)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nvaluesFile: {a: 1}\n", .error(2, 13)),
        .init("id: t\nvaluesFile: 5\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=5, provider=null, algorithm=null, keyLength=null]")),
        // Cannot construct instance of `MultiplierSetDefinition$Provider` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nprovider: x\n", .error(2, 11)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$Provider` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nprovider: \"\"\n", .error(2, 11)),
        // Cannot deserialize value of type `MultiplierSetDefinition$Provider` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nprovider: [a]\n", .error(2, 11)),
        // Cannot construct instance of `MultiplierSetDefinition$Algorithm` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nalgorithm: x\n", .error(2, 12)),
        // Cannot coerce empty String ("") to `MultiplierSetDefinition$Algorithm` value (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nalgorithm: \"\"\n", .error(2, 12)),
        // Cannot deserialize value of type `MultiplierSetDefinition$Algorithm` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nalgorithm: [wpx]\n", .error(2, 12)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nkeyLength: x\n", .error(2, 12)),
        .init("id: t\nkeyLength: \"\"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nkeyLength: \"  \"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nkeyLength: 1.9\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=1]")),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nkeyLength: 99999999999\n", .error(2, 23)),
        // Cannot deserialize value of type `java.lang.Integer` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nkeyLength: [2]\n", .error(2, 12)),
        .init("id: t\nkeyLength: -1\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=-1]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nmetadata:\n  name: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nmetadata:\n  description: {a: 1}\n", .error(3, 16)),
        .init("id: t\nmetadata: { name: 5, description: true }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=Meta[name=5, description=true], range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nrange:\n  min: x\n", .error(3, 8)),
        // Cannot deserialize value of type `int` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nrange:\n  max: [1]\n", .error(3, 8)),
        .init("id: t\nrange:\n  min: \"\"\n  max: 3\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=Range[min=0, max=3], validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nrange:\n  min: 1\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=Range[min=1, max=0], validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .init("id: t\nrange:\n  max: 99999999999\n", .error(3, 19)),
        .init("id: t\nrange: { min: 1.9, max: \"٣\" }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=Range[min=1, max=3], validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalidation:\n  keyPattern: [a]\n", .error(3, 15)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nvalidation:\n  keyPattern: {a: 1}\n", .error(3, 15)),
        .init("id: t\nvalidation:\n  keyPattern: 12\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=Validation[keyPattern=12], values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nvalidation:\n  keyPattern: \"[\"\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=Validation[keyPattern=[], values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalues:\n  - key: [a]\n", .error(3, 10)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalues:\n  - key: a\n    label: [a]\n", .error(4, 12)),
        // Cannot construct instance of `java.util.LinkedHashMap` (although at least one Creator exists): no String-argument constructor/factory method to deserialize from String value ('x')
        .init("id: t\nvalues:\n  - key: a\n    attributes: x\n", .error(4, 17)),
        // Cannot deserialize value of type `java.util.LinkedHashMap<java.lang.String,java.lang.String>` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalues:\n  - key: a\n    attributes: [a]\n", .error(4, 17)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalues:\n  - key: a\n    attributes: { n: [1] }\n", .error(4, 22)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nvalues:\n  - key: a\n    attributes: { n: {m: 1} }\n", .error(4, 22)),
        .init("id: t\nvalues:\n  - key: 7\n    label: 1.50\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=[ValueDef[key=7, label=1.50, attributes=null]], valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nvalues:\n  - label: bez klíče\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=[ValueDef[key=null, label=bez klíče, attributes=null]], valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot coerce empty String ("") to element of `java.util.LinkedHashMap` (but could if coercion was enabled using `CoercionConfig`)
        .init("id: t\nvalues:\n  - key: a\n    attributes: \"\"\n", .error(4, 17)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nprovider:\n  type: [a]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nprovider:\n  data: [a]\n", .error(3, 9)),
        .init("id: t\nprovider: { type: 5, data: ~ }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=Provider[type=5, data=null], algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nalgorithm:\n  type: [wpx]\n", .error(3, 9)),
        // Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.START_OBJECT`)
        .init("id: t\nalgorithm:\n  type: {a: 1}\n", .error(3, 9)),
        .init("id: t\nfoo: [1, {a: 2}]\nrange: { min: 1, max: 2, step: 5 }\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=Range[min=1, max=2], validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: a\nid: b\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=b, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nkeyLength: x\nkeyLength: 2\n", .error(2, 12)),
        // Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .init("id: t\nrange: { min: x }\nrange: { min: 1 }\n", .error(2, 15)),
        // Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.lang.Integer` value
        .init("id: t\nkeyLength: x\nschemaVersion: y\n", .error(2, 12)),
        // Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.START_ARRAY`)
        .init("id: t\nvalues:\n  - key: a\n    label: [b]\nkind: fixed\n", .error(4, 12)),
        .init("id: t\r\nkind: FIXED\r\nkeyLength: 2\r\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=2]")),
        .init("\u{FEFF}id: t\nkind: FIXED\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=FIXED, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=null, valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Cannot deserialize value of type `MultiplierSetDefinition$SetKind` from String "fixed": not one of the values accepted for Enum class: [FIXED, EXTERNAL_DATA, ALGORITHM]
        .init("\u{FEFF}id: t\nkind: fixed\n", .error(2, 7)),
        // `nil` items of the `values` list remain (the registry depends on them).
        .init("id: t\nvalues: [~]\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=[null], valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        .init("id: t\nvalues:\n  - ~\n  - key: a\n", .ok("MultiplierSetDefinition[schemaVersion=0, id=t, kind=null, keyType=null, enumerable=null, metadata=null, range=null, validation=null, values=[null, ValueDef[key=a, label=null, attributes=null]], valuesFile=null, provider=null, algorithm=null, keyLength=null]")),
        // Comment only (measured with the file ` # c\n` by the `ProbeFile` probe).
        .init(" # c\n", .error(2, 1)),
    ]

    @Test(arguments: cases)
    func loadMatchesJava(_ testCase: Case) {
        let data = Data(testCase.yaml.utf8)
        switch testCase.expected {
        case .ok(let description):
            do {
                let definition = try MultiplierSetLoader.load(data)
                #expect(definition.javaDescription == description)
            } catch {
                Issue.record("expected a definition, got \(error)")
            }
        case .error(let line, let column):
            do {
                let definition = try MultiplierSetLoader.load(data)
                Issue.record("expected error \(line):\(column), got \(definition.javaDescription)")
            } catch {
                guard case .invalidDefinition(let yaml) = error else {
                    Issue.record("expected .invalidDefinition, got \(error)")
                    return
                }
                #expect(yaml.line == line && yaml.column == column, "\(yaml)")
                #expect(error.message.hasPrefix("Nelze načíst definici sady: "))
            }
        case .empty:
            do {
                let definition = try MultiplierSetLoader.load(data)
                Issue.record("expected an empty definition, got \(definition.javaDescription)")
            } catch {
                #expect(error == .emptyDefinition)
                #expect(error.message == "definice je prázdná")
            }
        }
    }

    // MARK: - Files (probe `ProbeFile`)

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiplierSetLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ bytes: [UInt8], to name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    @Test func loadFileReadsDefinition() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try write(Array("id: t\nkind: FIXED\n".utf8), to: "ok.yaml", in: dir)
        let definition = try MultiplierSetLoader.loadFile(url)
        #expect(definition.id == "t")
        #expect(definition.kind == .FIXED)
    }

    /// Open error → "Nelze načíst sadu: <cesta>" (Java `loadFile`).
    @Test func missingFileFailsToOpen() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("missing.yaml")
        do {
            _ = try MultiplierSetLoader.loadFile(url)
            Issue.record("a missing file should have failed")
        } catch {
            #expect(error == .failure("Nelze načíst sadu: " + url.path))
        }
    }

    /// The directory `d.yaml` is **opened** in Java and fails only on reading inside `load` →
    /// "Nelze načíst definici sady: java.io.IOException: Is a directory".
    @Test func directoryFailsWhileReading() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sub = dir.appendingPathComponent("d.yaml")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        do {
            _ = try MultiplierSetLoader.loadFile(sub)
            Issue.record("a directory should have failed")
        } catch {
            guard case .failure(let message) = error else {
                Issue.record("expected .failure, got \(error)")
                return
            }
            #expect(message == "Nelze načíst definici sady: Is a directory")
        }
    }

    /// Invalid UTF-8: Java `CharConversionException` in the cause, position 1:1.
    @Test func invalidUtf8IsDefinitionError() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try write(Array("id: t".utf8) + [0xFF, 0xFE] + Array("\nkind: FIXED\n".utf8),
                            to: "bad.yaml", in: dir)
        do {
            _ = try MultiplierSetLoader.loadFile(url)
            Issue.record("invalid UTF-8 should have failed")
        } catch {
            guard case .invalidDefinition(let yaml) = error else {
                Issue.record("expected .invalidDefinition, got \(error)")
                return
            }
            #expect(yaml.line == 1 && yaml.column == 1)
        }
    }

    /// Bad UTF-8 after the first ~1 kB: a **deliberate divergence from Java v1.1.1**. Java decodes as a stream in ~1 kB chunks and reports 5:10 (bad byte
    /// in the label after 2000 bytes), or the type error 2:12 that it hits
    /// before a bad byte 20 kB further on (probes `ProbeLate`/`ProbeLate2`).
    /// Swift decodes the whole file up front and always reports 1:1. The test pins the Swift
    /// behaviour so that a change does not go unnoticed.
    @Test func invalidUtf8PastFirstKilobyte() {
        let late = Array("id: t\nkind: FIXED\nvalues:\n  - key: a\n    label: ".utf8)
            + [UInt8](repeating: 0x78, count: 2000) + [0xE9] + Array("\n  - key: b\n".utf8)
        let typeErrorFirst = Array("id: t\nkeyLength: x\n# ".utf8)
            + [UInt8](repeating: 0x61, count: 20_000) + [0xFF] + Array("\n".utf8)
        for (bytes, java) in [(late, "5:10"), (typeErrorFirst, "2:12")] {
            do {
                _ = try MultiplierSetLoader.load(Data(bytes))
                Issue.record("invalid UTF-8 should have failed")
            } catch {
                guard case .invalidDefinition(let yaml) = error else {
                    Issue.record("expected .invalidDefinition, got \(error)")
                    continue
                }
                // Java: \(java) — divergence
                #expect(yaml.kind == .syntax && yaml.line == 1 && yaml.column == 1, "Java \(java), Swift \(yaml)")
                #expect(yaml.message == "vstup není platné UTF-8")
            }
        }
    }

    /// BOM: Java discards it and counts columns without it.
    @Test func byteOrderMarkIsIgnored() throws {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let ok = try MultiplierSetLoader.load(Data(bom + Array("id: t\nkind: FIXED\n".utf8)))
        #expect(ok.id == "t")
        do {
            _ = try MultiplierSetLoader.load(Data(bom))
            Issue.record("a lone BOM should have failed")
        } catch {
            guard case .invalidDefinition(let yaml) = error else {
                Issue.record("expected .invalidDefinition, got \(error)")
                return
            }
            #expect(yaml.line == 1 && yaml.column == 1)
        }
        do {
            _ = try MultiplierSetLoader.load(Data(bom + Array("id: t\nkind: fixed\n".utf8)))
            Issue.record("kind: fixed should have failed")
        } catch {
            guard case .invalidDefinition(let yaml) = error else {
                Issue.record("expected .invalidDefinition, got \(error)")
                return
            }
            #expect(yaml.line == 2 && yaml.column == 7)
        }
    }

    /// All sets from `contest-data/multipliers/` load (gate against
    /// the real data; file by file, without the registry).
    @Test func bundledDefinitionsLoad() throws {
        let root = try #require(Bundle.module.url(forResource: "contest-data", withExtension: nil))
        let dir = root.appendingPathComponent("multipliers")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(".yaml") }
        #expect(files.count == 10)
        for name in files {
            let definition = try MultiplierSetLoader.loadFile(dir.appendingPathComponent(name))
            #expect(definition.id != nil, "\(name)")
            #expect(definition.kind != nil, "\(name)")
        }
    }
}

// MARK: - Output like Java `toString()` of a record

extension MultiplierSetDefinition {
    var javaDescription: String {
        "MultiplierSetDefinition[schemaVersion=\(schemaVersion), id=\(j(id)), kind=\(j(kind?.rawValue)), "
            + "keyType=\(j(keyType?.rawValue)), enumerable=\(j(enumerable.map { String($0) })), "
            + "metadata=\(j(metadata.map { "Meta[name=\(j($0.name)), description=\(j($0.description))]" })), "
            + "range=\(j(range.map { "Range[min=\($0.min), max=\($0.max)]" })), "
            + "validation=\(j(validation.map { "Validation[keyPattern=\(j($0.keyPattern))]" })), "
            + "values=\(j(values.map { list in "[" + list.map { j($0?.javaDescription) }.joined(separator: ", ") + "]" })), "
            + "valuesFile=\(j(valuesFile)), "
            + "provider=\(j(provider.map { "Provider[type=\(j($0.type)), data=\(j($0.data))]" })), "
            + "algorithm=\(j(algorithm.map { "Algorithm[type=\(j($0.type))]" })), "
            + "keyLength=\(j(keyLength.map { String($0) }))]"
    }
}

extension MultiplierSetDefinition.ValueDef {
    var javaDescription: String {
        let attrs = attributes.map { map in
            "{" + map.pairs.map { "\($0.key)=\(j($0.value))" }.joined(separator: ", ") + "}"
        }
        return "ValueDef[key=\(j(key)), label=\(j(label)), attributes=\(j(attrs))]"
    }
}

private func j(_ value: String?) -> String { value ?? "null" }
