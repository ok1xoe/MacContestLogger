import Foundation
import Testing
@testable import MCLCore

/// A strict decoder against Java. The `coercionCases` table is **generated
/// from a running Java**: probe `ProbeT1` (Jackson 2.22.0 + SnakeYAML 2.5,
/// `YamlObjectMapper.create()` from the Java application v1.1.1) mapped every input
/// onto a record
///
/// ```java
/// record R(String s, int i, Integer ii, boolean b, Boolean bb, Scope e,
///          List<String> l, Map<String,String> ms, Map<String,Integer> mi,
///          double d, Inner in, List<Inner> li)
/// record Inner(String name, int n)
/// enum Scope { PER_BAND, PER_BAND_MODE, PER_CONTEST }
/// ```
///
/// and printed either the result (the record's `toString`) or the line and column that
/// Jackson reports for the exception (`JsonProcessingException.getLocation()`). The Swift
/// `Probe` below is the same record and `javaDescription` prints it the same as the
/// Java `toString`, so a `.ok` row compares the **whole** result, not just
/// one field. The comment at `.error` is the Java message (Swift has its own Czech one,
/// only the position must match).
///
/// Omitted inputs that the reader rejects already when reading the tree (`.inf`,
/// `.nan`, `1:30.5`, integers beyond `Int64`) are in `parserRejectsWhatJavaMapsLazily`.
@Suite struct YamlDecoderTests {

    enum Scope: String, YamlEnum, Equatable {
        case PER_BAND, PER_BAND_MODE, PER_CONTEST
    }

    struct Inner: YamlRecord, Equatable {
        var name: String?
        var n: Int32

        init(yaml object: YamlObject) {
            name = object.string("name")
            n = object.int("n") ?? 0
        }

        init(name: String?, n: Int32) {
            self.name = name
            self.n = n
        }

        var javaDescription: String { "Inner[name=\(name ?? "null"), n=\(n)]" }
    }

    /// The same record as the Java `ProbeT1.R` (without the `long lg` field).
    struct Probe: YamlRecord {
        var s: String?
        var i: Int32
        var ii: Int32?
        var b: Bool
        var bb: Bool?
        var e: Scope?
        var l: [String?]?
        var ms: YamlOrderedMap<String>?
        var mi: YamlOrderedMap<Int32>?
        var d: Double
        var inner: Inner?
        var li: [Inner?]?

        init(yaml object: YamlObject) {
            s = object.string("s")
            i = object.int("i") ?? 0
            ii = object.int("ii")
            b = object.bool("b") ?? false
            bb = object.bool("bb")
            e = object.decode("e", as: Scope.self)
            l = object.list("l", of: String.self)
            ms = object.map("ms", of: String.self)
            mi = object.map("mi", of: Int32.self)
            d = object.double("d") ?? 0
            inner = object.decode("in", as: Inner.self)
            li = object.list("li", of: Inner.self)
        }

        /// Output in the shape of the Java `toString` (fields only, without the record name).
        var javaDescription: String {
            func list<T>(_ items: [T?]?, _ show: (T) -> String) -> String {
                guard let items else { return "null" }
                return "[" + items.map { $0.map(show) ?? "null" }.joined(separator: ", ") + "]"
            }
            func map<T>(_ map: YamlOrderedMap<T>?, _ show: (T) -> String) -> String {
                guard let map else { return "null" }
                return "{" + map.pairs.map { "\($0.key)=" + ($0.value.map(show) ?? "null") }
                    .joined(separator: ", ") + "}"
            }
            return [
                "s=" + (s.map { "\"\($0)\"" } ?? "null"),
                "i=\(i)",
                "ii=" + (ii.map { "\($0)" } ?? "null"),
                "b=\(b)",
                "bb=" + (bb.map { "\($0)" } ?? "null"),
                "e=" + (e?.rawValue ?? "null"),
                "l=" + list(l) { $0 },
                "ms=" + map(ms) { $0 },
                "mi=" + map(mi) { "\($0)" },
                "d=" + JavaDouble.toString(d),
                "in=" + (inner?.javaDescription ?? "null"),
                "li=" + list(li) { $0.javaDescription },
            ].joined(separator: " ")
        }
    }

    struct Case: Sendable, CustomTestStringConvertible {
        enum Expected: Sendable {
            case ok(String)
            case error(line: Int, column: Int)
        }

        let yaml: String
        let expected: Expected

        static func ok(_ yaml: String, _ java: String) -> Case { Case(yaml: yaml, expected: .ok(java)) }

        static func error(_ yaml: String, _ line: Int, _ column: Int) -> Case {
            Case(yaml: yaml, expected: .error(line: line, column: column))
        }

        var testDescription: String { yaml.debugDescription }
    }

    static let coercionCases: [Case] = [
        .ok("s: 48\n", "s=\"48\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: 1e3\n", "s=\"1e3\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: 007\n", "s=\"007\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: yes\n", "s=\"yes\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: 0030\n", "s=\"0030\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: TRUE\n", "s=\"TRUE\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: 2.50\n", "s=\"2.50\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: \"\"\n", "s=\"\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\ns: {a: 1}\n", 2, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("x: 1\ns:\n  a: 1\n", 3, 3), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("x: 1\ns: [a]\n", 2, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("x: 1\ns:\n  - a\n", 3, 3), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .ok("i: \"24\"\n", "s=null i=24 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 1.7\n", "s=null i=1 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 1.9\n", "s=null i=1 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: -1.9\n", "s=null i=-1 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\ni: abc\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "abc": not a valid `int` value
        .error("x: 1\ni: 99999999999\n", 2, 15), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .ok("i: 2147483647\n", "s=null i=2147483647 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 2147483648\n", 1, 14), // JsonMappingException: Numeric value (2147483648) out of range of int (-2147483648 - 2147483647)
        .ok("i: -2147483648\n", "s=null i=-2147483648 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: -2147483649\n", 1, 15), // JsonMappingException: Numeric value (-2147483649) out of range of int (-2147483648 - 2147483647)
        .ok("i: 0x1\n", "s=null i=1 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 2_4\n", "s=null i=24 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 0o17\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "0o17": not a valid `int` value
        .ok("i: 017\n", "s=null i=15 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 0b11\n", "s=null i=3 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 1:30\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "1:30": not a valid `int` value
        .ok("i: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: \"abc\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "abc": not a valid `int` value
        .ok("i: \"\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \" 5\"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"+5\"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: \"1.9\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "1.9": not a valid `int` value
        .error("i: \"1e3\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "1e3": not a valid `int` value
        .ok("i: 1e3\n", "s=null i=1000 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 3e9\n", 1, 7), // JsonMappingException: Numeric value (3e9) out of range of int (-2147483648 - 2147483647)
        .error("i: 1.0e+10\n", 1, 11), // JsonMappingException: Numeric value (1.0e+10) out of range of int (-2147483648 - 2147483647)
        .error("i: true\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `int` from Boolean value (token `JsonToken.VALUE_TRUE`)
        .error("i: [1]\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `int` from Array value (token `JsonToken.START_ARRAY`)
        .error("i: {a: 1}\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `int` from Object value (token `JsonToken.START_OBJECT`)
        .ok("ii: \"24\"\n", "s=null i=0 ii=24 b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("ii: 1.9\n", "s=null i=0 ii=1 b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("ii: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("ii: abc\n", 1, 5), // InvalidFormatException: Cannot deserialize value of type `java.lang.Integer` from String "abc": not a valid `java.
        .error("ii: true\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.Integer` from Boolean value (token `JsonToken.
        .ok("ii: \"\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: yes\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: True\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: TRUE\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"true\"\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"True\"\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"TRUE\"\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("b: \"yes\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `boolean` from String "yes": only "true"/"True"/"TRUE" or
        .ok("b: 1\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 2\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 0\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: -1\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("b: 1.0\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `boolean` from Floating-point value (token `JsonToken.VAL
        .ok("b: no\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: off\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: on\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\nb: abc\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `boolean` from String "abc": only "true"/"True"/"TRUE" or
        .ok("b: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"false\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("b: \"1\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `boolean` from String "1": only "true"/"True"/"TRUE" or "
        .error("b: [true]\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `boolean` from Array value (token `JsonToken.START_ARRAY`
        .ok("bb: yes\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("bb: \"yes\"\n", 1, 5), // InvalidFormatException: Cannot deserialize value of type `java.lang.Boolean` from String "yes": only "true" or "fa
        .ok("bb: \"true\"\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"True\"\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"TRUE\"\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"false\"\n", "s=null i=0 ii=null b=false bb=false e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("bb: \"1\"\n", 1, 5), // InvalidFormatException: Cannot deserialize value of type `java.lang.Boolean` from String "1": only "true" or "fals
        .ok("bb: 1\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: 0\n", "s=null i=0 ii=null b=false bb=false e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: 2\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("bb: 1.0\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.Boolean` from Floating-point value (token `Jso
        .ok("bb: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("bb: abc\n", 1, 5), // InvalidFormatException: Cannot deserialize value of type `java.lang.Boolean` from String "abc": only "true" or "fa
        .ok("e: PER_BAND\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: per_band\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "per_band": not one of the va
        .error("x: 1\ne: FOO\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "FOO": not one of the values 
        .error("e: \"\"\n", 1, 4), // InvalidFormatException: Cannot coerce empty String ("") to `ProbeT1$Scope` value (but could if coercion was enable
        .ok("e: 1\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: 0\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: 3\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from number 3: index value outside legal 
        .error("e: -1\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from number -1: index value outside legal
        .ok("e: \"1\"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: 1.0\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Scope` from Floating-point value (token `JsonTok
        .error("e: true\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Scope` from Boolean value (token `JsonToken.VALU
        .ok("e: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: \" PER_BAND\"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: [PER_BAND]\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Scope` from Array value (token `JsonToken.START_
        .ok("l: [a, b]\n", "s=null i=0 ii=null b=false bb=null e=null l=[a, b] ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\nl: 20m\n", 2, 4), // MismatchedInputException: Cannot construct instance of `java.util.ArrayList` (although at least one Creator exists):
        .error("l: \"\"\n", 1, 4), // InvalidFormatException: Cannot coerce empty String ("") to element of `java.util.ArrayList` (but could if coercion
        .ok("l: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("l: []\n", "s=null i=0 ii=null b=false bb=null e=null l=[] ms=null mi=null d=0.0 in=null li=null"),
        .ok("l: [~, 160m]\n", "s=null i=0 ii=null b=false bb=null e=null l=[null, 160m] ms=null mi=null d=0.0 in=null li=null"),
        .ok("l: [160, yes, 1.50]\n", "s=null i=0 ii=null b=false bb=null e=null l=[160, yes, 1.50] ms=null mi=null d=0.0 in=null li=null"),
        .error("l: [[a]]\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("l: [{a: 1}]\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("l:\n  - a\n  - [b]\n", 3, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("l: {a: 1}\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.util.ArrayList<java.lang.String>` from Object value
        .error("l: 5\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.util.ArrayList<java.lang.String>` from Integer valu
        .ok("ms: {n: 1, b: true, c: ~, d: 1.50}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={n=1, b=true, c=null, d=1.50} mi=null d=0.0 in=null li=null"),
        .error("ms: {n: [1]}\n", 1, 9), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("ms: []\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.util.LinkedHashMap<java.lang.String,java.lang.Strin
        .error("ms: x\n", 1, 5), // MismatchedInputException: Cannot construct instance of `java.util.LinkedHashMap` (although at least one Creator exis
        .ok("ms: {~: 1}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={~=1} mi=null d=0.0 in=null li=null"),
        .ok("ms: {1: a}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={1=a} mi=null d=0.0 in=null li=null"),
        .ok("mi: {40m: \"3\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={40m=3} d=0.0 in=null li=null"),
        .ok("mi: {a: 1.9}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={a=1} d=0.0 in=null li=null"),
        .error("mi: {a: x}\n", 1, 9), // InvalidFormatException: Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.la
        .ok("mi: {a: ~}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={a=null} d=0.0 in=null li=null"),
        .error("mi: {a: 99999999999}\n", 1, 20), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("mi: {a: true}\n", 1, 9), // MismatchedInputException: Cannot deserialize value of type `java.lang.Integer` from Boolean value (token `JsonToken.
        .ok("d: \"0.5\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.5 in=null li=null"),
        .ok("d: 5\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=5.0 in=null li=null"),
        .ok("d: 1e3\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1000.0 in=null li=null"),
        .error("d: abc\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "abc": not a valid `double` value (a
        .ok("d: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("d: \"NaN\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=NaN in=null li=null"),
        .error("d: true\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `double` from Boolean value (token `JsonToken.VALUE_TRUE`
        .ok("d: \"\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("in: {name: a, n: 3}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=a, n=3] li=null"),
        .error("in:\n  name: a\n  n: x\n", 3, 6), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: []\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Inner` from Array value (token `JsonToken.START_
        .error("in: x\n", 1, 5), // MismatchedInputException: Cannot construct instance of `ProbeT1$Inner` (although at least one Creator exists): no St
        .ok("in: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("in: \"\"\n", 1, 5), // InvalidFormatException: Cannot coerce empty String ("") to `ProbeT1$Inner` value (but could if coercion was enable
        .ok("li: [{name: a}, {name: b, n: 2}]\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=[Inner[name=a, n=0], Inner[name=b, n=2]]"),
        .error("li:\n  - name: a\n  - name: b\n    n: zz\n", 4, 8), // InvalidFormatException: Cannot deserialize value of type `int` from String "zz": not a valid `int` value
        .error("li: {name: a}\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.util.ArrayList<ProbeT1$Inner>` from Object value (t
        .ok("li: [~, {name: b}]\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=[null, Inner[name=b, n=0]]"),
        .error("li: [x]\n", 1, 6), // MismatchedInputException: Cannot construct instance of `ProbeT1$Inner` (although at least one Creator exists): no St
        .ok("s: a\nzzz: {deep: [1, 2]}\nin: {name: a, bogus: 1, n: 2}\n", "s=\"a\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=a, n=2] li=null"),
        .ok("s: a\ns: b\n", "s=\"b\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("in: {name: a}\nin: {n: 2}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=null, n=2] li=null"),
        .error("i: 1\ni: x\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("i: 99999999999   # komentar\n", 1, 15), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("i: !!int 99999999999\n", 1, 21), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("i: !!int \"99999999999\"\n", 1, 23), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("i: \"99999999999\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "99999999999": Overflow: numeric value 
        .error("ii: \"99999999999\"\n", 1, 5), // InvalidFormatException: Cannot deserialize value of type `java.lang.Integer` from String "99999999999": Overflow: 
        .error("i: \"2147483648\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "2147483648": Overflow: numeric value (
        .ok("i: \" 5 \"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"\\t5\"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"05\"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"-0\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: \"+-5\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "+-5": not a valid `int` value
        .error("i: \"1_000\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "1_000": not a valid `int` value
        .error("i: \"0x10\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "0x10": not a valid `int` value
        .ok("i: \"\u{663}\"\n", "s=null i=3 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: \"1.0\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "1.0": not a valid `int` value
        .ok("i: \"  \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"null\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("ii: \"null\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("ii: \"  \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 1.5e2\n", "s=null i=150 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 2147483647.9\n", 1, 16), // JsonMappingException: Numeric value (2147483647.9) out of range of int (-2147483648 - 2147483647)
        .error("i: 2147483648.0\n", 1, 16), // JsonMappingException: Numeric value (2147483648.0) out of range of int (-2147483648 - 2147483647)
        .error("i: -2147483648.9\n", 1, 17), // JsonMappingException: Numeric value (-2147483648.9) out of range of int (-2147483648 - 2147483647)
        .ok("i: 1e-5\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 0.0\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: -0.5\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\nli:\n  - n: 99999999999\n", 3, 19), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("x: 1\nl:\n  - a\n  - {b: 1}\n", 4, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .ok("b: \"  true \"\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \" true\"\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"null\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"null\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: \"01\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "01": not one of the values a
        .ok("e: \" 1\"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: \"3\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "3": not one of the values ac
        .error("e: \"-1\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "-1": not one of the values a
        .ok("e: \"PER_BAND \"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: \"  \"\n", 1, 4), // InvalidFormatException: Cannot coerce empty String ("") to `ProbeT1$Scope` value (but could if coercion was enable
        .ok("e: 0x1\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: 99999999999\n", 1, 15), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("e: yes\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Scope` from Boolean value (token `JsonToken.VALU
        .error("e: \"null\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "null": not one of the values
        .ok("d: \" 0.5 \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.5 in=null li=null"),
        .error("d: \"1_000\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "1_000": not a valid `double` value 
        .error("d: \"0x10\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "0x10": not a valid `double` value (
        .ok("d: \"Infinity\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .ok("d: \"-Infinity\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=-Infinity in=null li=null"),
        .error("d: \"inf\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "inf": not a valid `double` value (a
        .ok("d: \"1e3\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1000.0 in=null li=null"),
        .ok("d: \"1d\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1.0 in=null li=null"),
        .ok("d: \"0x1p3\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=8.0 in=null li=null"),
        .ok("d: \"  \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("d: 1:30\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "1:30": not a valid `double` value (
        .ok("d: 0x1F\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=31.0 in=null li=null"),
        .ok("d: 017\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=15.0 in=null li=null"),
        .ok("d: 2_4.5\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=24.5 in=null li=null"),
        .error("d: [1]\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `double` from Array value (token `JsonToken.START_ARRAY`)
        .error("d: {a: 1}\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `double` from Object value (token `JsonToken.START_OBJECT
        .ok("d: \"null\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("l: [a, ~, \"\", b]\n", "s=null i=0 ii=null b=false bb=null e=null l=[a, null, , b] ms=null mi=null d=0.0 in=null li=null"),
        .ok("l: [1:30, 0x1, 017]\n", "s=null i=0 ii=null b=false bb=null e=null l=[1:30, 0x1, 017] ms=null mi=null d=0.0 in=null li=null"),
        .ok("ms: {a: \"\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={a=} mi=null d=0.0 in=null li=null"),
        .ok("ms: {a: 0x1}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={a=0x1} mi=null d=0.0 in=null li=null"),
        .ok("mi: {a: \"\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={a=null} d=0.0 in=null li=null"),
        .ok("mi: {a: \" 5\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={a=5} d=0.0 in=null li=null"),
        .error("mi: {a: \"1.9\"}\n", 1, 9), // InvalidFormatException: Cannot deserialize value of type `java.lang.Integer` from String "1.9": not a valid `java.
        .error("mi: {a: [1]}\n", 1, 9), // MismatchedInputException: Cannot deserialize value of type `java.lang.Integer` from Array value (token `JsonToken.ST
        .ok("mi: {a: 0x1}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi={a=1} d=0.0 in=null li=null"),
        .error("mi: 5\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.util.LinkedHashMap<java.lang.String,java.lang.Integ
        .ok("ms: ~\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("ms: \"\"\n", 1, 5), // InvalidFormatException: Cannot coerce empty String ("") to element of `java.util.LinkedHashMap` (but could if coer
        .error("mi: \"\"\n", 1, 5), // InvalidFormatException: Cannot coerce empty String ("") to element of `java.util.LinkedHashMap` (but could if coer
        .ok("in: {n: \"\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=null, n=0] li=null"),
        .ok("in: {}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=null, n=0] li=null"),
        .ok("li: []\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=[]"),
        .error("li: [[a]]\n", 1, 6), // MismatchedInputException: Cannot deserialize value of type `ProbeT1$Inner` from Array value (token `JsonToken.START_
        .error("li: \"\"\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.util.ArrayList<ProbeT1$Inner>` from String value (t
        .error("li: [\"\"]\n", 1, 6), // InvalidFormatException: Cannot coerce empty String ("") to `ProbeT1$Inner` value (but could if coercion was enable
        .ok("l: [\"\"]\n", "s=null i=0 ii=null b=false bb=null e=null l=[] ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: PER_BAND_MODE\ne: 1\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: \"PER_BAND\\n\"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("in: {n: 1}\nin: x\n", 2, 5), // MismatchedInputException: Cannot construct instance of `ProbeT1$Inner` (although at least one Creator exists): no St
        .ok("i:\n  5\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"5\n  \"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: x\ni: 1\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: {n: x}\nin: {n: 1}\n", 1, 9), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("l: [[a]]\nl: [b]\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("i: 99999999999\ni: 1\n", 1, 15), // JsonMappingException: Numeric value (99999999999) out of range of int (-2147483648 - 2147483647)
        .error("i: !!str abc\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "abc": not a valid `int` value
        .error("s: !!map {a: 1}\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("s: &x {a: 1}\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("s: &x\n  a: 1\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("s: !!map\n  a: 1\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Object value (token `JsonToken.ST
        .error("s:\n- a\n", 2, 1), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .ok("ms: {s: \"\u{1F600}\u{E9}\", i: x}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms={s=\u{1F600}\u{E9}, i=x} mi=null d=0.0 in=null li=null"),
        .error("x: 1\nin: {name: \"\u{1F600}\", n: x}\n", 2, 20), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: {name: \"\u{E9}\", n: x}\n", 1, 20), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: {name: \"e\u{301}\", n: x}\n", 1, 21), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: {name: \"\u{FF21}\", n: x}\n", 1, 20), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("in: {name: \"a\tb\", n: x}\n", 1, 22), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("i: \"a\n  b\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "a b": not a valid `int` value
        .error("i: >\n  abc\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "abc": not a valid `int` value
        .error("i: |\n  99999999999\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "99999999999": Overflow: numeric value 
        .error("i: !!int \"12\n  3\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "12 3": not a valid `int` value
        .error("i: ~\ni: x\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("i: 1.5\ni: x\n", 2, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("l:\n  - [a]\n  - b\n", 2, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("in:\n  n: 1\n  n: [x]\n", 3, 6), // MismatchedInputException: Cannot deserialize value of type `int` from Array value (token `JsonToken.START_ARRAY`)
        .error("ms: {a: [1], a: b}\n", 1, 9), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("mi: {a: x, a: 1}\n", 1, 9), // InvalidFormatException: Cannot deserialize value of type `java.lang.Integer` from String "x": not a valid `java.la
        .error("li: [{n: x}]\nli: ~\n", 1, 10), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .ok("b: 0x000000000\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 0x00000000\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 000000000000\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 00000000000\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: -0x000000000\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 0b000000000000000000000000000000000\n", "s=null i=0 ii=null b=true bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: 0x000000000\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("d: \"INF\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .ok("d: \"-INF\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=-Infinity in=null li=null"),
        .ok("d: \"+INF\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .ok("d: \"+Infinity\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .error("d: \" INF\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "INF": not a valid `double` value (a
        .ok("d: \" Infinity\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .ok("d: \"1.\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1.0 in=null li=null"),
        .ok("d: \".5\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.5 in=null li=null"),
        .ok("d: \"0x.8p1\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1.0 in=null li=null"),
        .ok("d: \"0x1.8p1\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=3.0 in=null li=null"),
        .error("d: \"0x10p\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "0x10p": not a valid `double` value 
        .error("d: \"1e\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "1e": not a valid `double` value (as
        .ok("d: \"+NaN\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=NaN in=null li=null"),
        .ok("d: \"-NaN\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=NaN in=null li=null"),
        .ok("d: \"1f\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1.0 in=null li=null"),
        .ok("d: \"0x1P-2d\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.25 in=null li=null"),
        .ok("d: \"1e400\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=Infinity in=null li=null"),
        .error("d: \".\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String ".": not a valid `double` value (as 
        .error("d: \"e5\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "e5": not a valid `double` value (as
        .error("d: \"1e5.5\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "1e5.5": not a valid `double` value 
        .error("d: \"\u{661}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "١": not a valid `double` value (as 
        .ok("d: \"0X1p1\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=2.0 in=null li=null"),
        .error("d: \"++1\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "++1": not a valid `double` value (a
        .error("d: \"1 2\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "1 2": not a valid `double` value (a
        .ok("i: \"\u{FF11}\u{FF12}\"\n", "s=null i=12 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: \"+\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "+": not a valid `int` value
        .error("i: \"-\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "-": not a valid `int` value
        .error("i: \"\u{1D7CE}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "𝟎": not a valid `int` value
        .error("i: \"\u{663}\u{663}\u{663}\u{663}\u{663}\u{663}\u{663}\u{663}\u{663}\u{663}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "٣٣٣٣٣٣٣٣٣٣": Overflow: numeric value (
        .ok("i: \"-2147483648\"\n", "s=null i=-2147483648 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"0000000000000005\"\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: \"1 \"\n", "s=null i=1 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("e: \"\u{FF11}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "１": not one of the values ac
        .error("e: \"1\u{661}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "1١": not one of the values a
        .error("e: \"1\u{663}\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "1٣": not one of the values a
        .error("e: \"+1\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "+1": not one of the values a
        .ok("e: \" 2 \"\n", "s=null i=0 ii=null b=false bb=null e=PER_CONTEST l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"  TRUE\"\n", "s=null i=0 ii=null b=false bb=true e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: \"false \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("b: \"tRUE\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `boolean` from String "tRUE": only "true"/"True"/"TRUE" o
        .error("i: 0b11111111111111111111111111111111\n", 1, 38), // JsonMappingException: Numeric value (0b11111111111111111111111111111111) out of range of int (-2147483648 - 2147
        .ok("i: -0x80000000\n", "s=null i=-2147483648 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: 0x7FFFFFFF\n", "s=null i=2147483647 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 0x80000000\n", 1, 14), // JsonMappingException: Numeric value (0x80000000) out of range of int (-2147483648 - 2147483647)
        .ok("i: 017777777777\n", "s=null i=2147483647 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("i: 020000000000\n", 1, 16), // JsonMappingException: Numeric value (020000000000) out of range of int (-2147483648 - 2147483647)
        .ok("i: 1_000_000\n", "s=null i=1000000 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("i: +5\n", "s=null i=5 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: +0\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("b: 0b0\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: +1\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: 0b10\n", "s=null i=0 ii=null b=false bb=null e=PER_CONTEST l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: 1_000\n", "s=\"1_000\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("s: +5\n", "s=\"+5\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("d: 1_000\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=1000.0 in=null li=null"),
        .ok("d: -0x10\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=-16.0 in=null li=null"),
        .ok("d: 9223372036854775807\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=9.223372036854776E18 in=null li=null"),
        .error("l: [1, [2]]\n", 1, 8), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .ok("l:\n- a\n- b\n", "s=null i=0 ii=null b=false bb=null e=null l=[a, b] ms=null mi=null d=0.0 in=null li=null"),
        .error("x: 1\nin:\n  n:\n    - 1\n", 4, 5), // MismatchedInputException: Cannot deserialize value of type `int` from Array value (token `JsonToken.START_ARRAY`)
        .error("x: 1\nli:\n  - n: 1\n  - x\n", 4, 5), // MismatchedInputException: Cannot construct instance of `ProbeT1$Inner` (although at least one Creator exists): no St
        .ok("in: {n: !!str 5}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=null, n=5] li=null"),
        .ok("in: {n: !!int \"5\"}\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=Inner[name=null, n=5] li=null"),
        .error("in: !!map {n: x}\n", 1, 15), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .ok("s: !!binary aGVsbG8=\n", "s=\"aGVsbG8=\" i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .error("l: [[a]]\ni: x\n", 1, 5), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("i: x\nl: [[a]]\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("li: [{n: x}]\ni: y\n", 1, 10), // InvalidFormatException: Cannot deserialize value of type `int` from String "x": not a valid `int` value
        .error("li: [{n: 1}, {name: [1], n: y}]\n", 1, 21), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("in: {n: 1, name: [a]}\n", 1, 18), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("in: {name: [a], n: x}\n", 1, 12), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("e: FOO\ns: [x]\nb: nope\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `ProbeT1$Scope` from String "FOO": not one of the values 
        .error("ms: {b: [1], a: x}\nmi: {z: q}\n", 1, 9), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
        .error("d: abc\nbb: \"yes\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `double` from String "abc": not a valid `double` value (a
        .ok("b: \"  \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \"  \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("bb: \" null \"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("e: \" PER_BAND_MODE \"\n", "s=null i=0 ii=null b=false bb=null e=PER_BAND_MODE l=null ms=null mi=null d=0.0 in=null li=null"),
        .ok("d: \" NaN\"\n", "s=null i=0 ii=null b=false bb=null e=null l=null ms=null mi=null d=NaN in=null li=null"),
        .error("i: \"\\u00a05\"\n", 1, 4), // InvalidFormatException: Cannot deserialize value of type `int` from String " 5": not a valid `int` value
        .error("s: [a]\ns: b\n", 1, 4), // MismatchedInputException: Cannot deserialize value of type `java.lang.String` from Array value (token `JsonToken.STA
    ]

    /// Each row of the measured table: a result, or a type error at the **same
    /// line and column** as in Java.
    @Test(arguments: coercionCases)
    func coercionMatchesJava(_ testCase: Case) throws {
        switch testCase.expected {
        case .ok(let java):
            let probe = try #require(try YamlDecoder.decode(Probe.self, from: testCase.yaml))
            #expect(probe.javaDescription == java)
        case .error(let line, let column):
            do {
                _ = try YamlDecoder.decode(Probe.self, from: testCase.yaml)
                Issue.record("a type error was expected at \(line):\(column)")
            } catch let error as YamlError {
                #expect(error.kind == .type, "\(error)")
                #expect(error.line == line && error.column == column, "\(error)")
            }
        }
    }

    // MARK: - Document root

    /// An empty input is an error "No content to map due to end-of-input" in Java
    /// at the end of input; `~` and `---` return `null` (measured `ProbeRoot`).
    @Test(arguments: [("", 1, 1), ("# c\n", 2, 1), ("\n\n", 3, 1), ("# c", 1, 4), ("%YAML 1.1\n", 2, 1)])
    func emptyInputIsErrorAtEndOfInput(_ text: String, _ line: Int, _ column: Int) {
        #expect(throws: YamlError(kind: .type, message: "vstup neobsahuje žádný dokument",
                                  line: line, column: column)) {
            _ = try YamlDecoder.decode(Probe.self, from: text)
        }
    }

    @Test(arguments: ["~\n", "---\n", "--- ~\n", "---\n# c\n", "%YAML 1.1\n---\n"])
    func nullDocumentDecodesToNil(_ text: String) throws {
        #expect(try YamlDecoder.decode(Probe.self, from: text) == nil)
    }

    /// A root that is not a map: an error at 1:1 (measured for a scalar, sequence,
    /// `[]`, `""` and a number).
    @Test(arguments: ["hello\n", "- a\n", "[]\n", "\"\"\n", "5\n"])
    func nonMappingRootIsTypeError(_ text: String) {
        do {
            _ = try YamlDecoder.decode(Probe.self, from: text)
            Issue.record("an error was expected")
        } catch let error as YamlError {
            #expect(error.kind == .type)
            #expect(error.line == 1 && error.column == 1)
        } catch {
            Issue.record("a different error: \(error)")
        }
    }

    // MARK: - Keys

    /// An unknown key is ignored at the root and nested — even its content is not
    /// checked (`FAIL_ON_UNKNOWN_PROPERTIES` is off). The Java test of
    /// the same is misleadingly named `unknownFieldIsParseError`.
    @Test func unknownKeyIsIgnoredAtRootAndNested() throws {
        let yaml = "zzz: [1, {a: [b]}]\nin: {name: a, bogus: {x: [1]}, n: 2}\nli: [{n: 1, q: [z]}]\n"
        let probe = try #require(try YamlDecoder.decode(Probe.self, from: yaml))
        #expect(probe.inner == Inner(name: "a", n: 2))
        #expect(probe.li == [Inner(name: nil, n: 1)])
    }

    /// A duplicate key: the last occurrence wins — but Java reads the earlier occurrence
    /// during mapping too, so its type error fails the load
    /// (measured: `i: x` + `i: 1` → 1:4, `in: {n: x}` + `in: {n: 1}` → 1:9).
    @Test func duplicateKeyLastWinsButEarlierOccurrenceIsChecked() throws {
        let probe = try #require(try YamlDecoder.decode(Probe.self, from: "i: 1\ni: 2\nin: {name: a}\nin: {n: 3}\n"))
        #expect(probe.i == 2)
        #expect(probe.inner == Inner(name: nil, n: 3))
        #expect(throws: YamlError.self) { _ = try YamlDecoder.decode(Probe.self, from: "i: x\ni: 1\n") }
        // An unknown key is not read even in a duplicate.
        #expect(try YamlDecoder.decode(Probe.self, from: "zzz: [x]\nzzz: 1\n") != nil)
    }

    /// Several errors at once: the **first in document order** is reported (Jackson reads
    /// as a stream and stops at the first), regardless of the order in which the Swift
    /// `init` reads the fields. `Probe` reads `i` before `l`, Java reports `l`.
    @Test func earliestErrorInDocumentOrderWins() {
        do {
            _ = try YamlDecoder.decode(Probe.self, from: "l: [[a]]\ni: x\n")
            Issue.record("an error was expected")
        } catch let error as YamlError {
            #expect(error.line == 1 && error.column == 5)
        } catch {
            Issue.record("a different error: \(error)")
        }
    }

    /// The error carries a Czech message and a `description` with line and column —
    /// the Java test wants the substring "řádek" in the message.
    @Test func typeErrorDescriptionHasPosition() {
        do {
            _ = try YamlDecoder.decode(Probe.self, from: "x: 1\ne: per_band\n")
            Issue.record("an error was expected")
        } catch {
            let text = "\(error)"
            #expect(text.contains("řádek 2"))
            #expect(text.contains("sloupec 4"))
            #expect(text.contains("per_band"))
        }
    }

    // MARK: - Map

    /// `YamlOrderedMap` keeps document order, `null` values and duplicates like the
    /// Java `LinkedHashMap` (last value, original key position).
    @Test func orderedMapKeepsOrderNullsAndDuplicates() throws {
        let probe = try #require(try YamlDecoder.decode(Probe.self, from: "ms: {b: 1, a: ~, c: x, b: 2}\n"))
        let map = try #require(probe.ms)
        #expect(map.keys == ["b", "a", "c"])
        #expect(map["b"] == "2")
        #expect(map["a"] == nil)
        #expect(map.containsKey("a"))
        #expect(!map.containsKey("zzz"))
        #expect(map.count == 3)
    }

    // MARK: - Custom type

    /// A type that takes a scalar **and** a map (a pattern for a Java record with another
    /// single-parameter constructor, e.g. `Period(Integer)`): it implements
    /// `YamlDecodable` directly and reports a wrong shape via `node.typeMismatch`.
    struct Hours: YamlDecodable, Equatable {
        var hours: Int32?
        var note: String?

        init?(yamlNode node: YamlNode) {
            switch node.value {
            case .mapping:
                guard let object = node.object() else { return nil }
                hours = object.int("hours")
                note = object.string("note")
            case .int, .double, .string:
                hours = node.decode(Int32.self)
            default:
                node.typeMismatch("expected a number of hours or a map")
                return nil
            }
        }

        init(hours: Int32?, note: String?) {
            self.hours = hours
            self.note = note
        }
    }

    struct HoursHolder: YamlRecord {
        var period: Hours?
        init(yaml object: YamlObject) { period = object.decode("period", as: Hours.self) }
    }

    @Test func customDecodableAcceptsScalarOrMapping() throws {
        #expect(try YamlDecoder.decode(HoursHolder.self, from: "period: 24\n")?.period == Hours(hours: 24, note: nil))
        #expect(try YamlDecoder.decode(HoursHolder.self, from: "period: 1.5\n")?.period == Hours(hours: 1, note: nil))
        #expect(try YamlDecoder.decode(HoursHolder.self, from: "period: {hours: 3, note: x}\n")?.period
                == Hours(hours: 3, note: "x"))
        #expect(throws: YamlError(kind: .type, message: "expected a number of hours or a map", line: 2, column: 9)) {
            _ = try YamlDecoder.decode(HoursHolder.self, from: "x: 1\nperiod: true\n")
        }
    }

    // MARK: - Deliberate divergence from Java v1.1.1

    /// Jackson types `.inf`, `.nan` and sexagesimal `1:30.5` as a floating-point
    /// number, but converts it **only when the value is read**: into a `String`, `int`
    /// and `double` field it fails with a position after the end of the token (`s: .inf` → 1:8),
    /// under an unknown key it passes (`zzz: .inf`). The same for an integer beyond `Int64`:
    /// Java has `BigInteger`, into `double` it passes. The reader rejects these scalars
    /// already when building the tree (a deliberate divergence from Java v1.1.1:
    /// "integer outside Int64", `.inf`), so they never reach the decoder.
    @Test(arguments: ["s: .inf\n", "zzz: .inf\ns: a\n", "d: 1:30.5\n", "d: 99999999999999999999\n"])
    func parserRejectsWhatJavaMapsLazily(_ text: String) {
        #expect(throws: YamlError.self) { _ = try YamlParser.parseDocument(text) }
    }
}

