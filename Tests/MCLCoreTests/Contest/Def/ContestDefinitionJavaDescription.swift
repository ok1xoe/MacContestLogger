import Foundation
@testable import MCLCore

// MARK: - Output like Java's `toString()` of records
//
// A Swift definition printed exactly like Java's `ContestDefinition.toString()`
// (record: `Name[field=value, …]`, `null`, `List` as `[a, b]`, `Map` as
// `{k=v}`, `double` as `Double.toString`). A table `.ok` row thus compares
// **all** fields including nested records and the element order.

extension ContestDefinition {
    var javaDescription: String {
        record("ContestDefinition", [
            ("schemaVersion", String(schemaVersion)), ("id", j(id)), ("metadata", j(metadata?.javaDescription)),
            ("period", j(period?.javaDescription)), ("bands", list(bands) { j($0) }),
            ("modes", list(modes) { j($0) }), ("categories", list(categories) { $0.javaDescription }),
            ("stationClasses", list(stationClasses) { $0.javaDescription }),
            ("exchange", j(exchange?.javaDescription)), ("scoring", j(scoring?.javaDescription)),
            ("multipliers", list(multipliers) { $0.javaDescription }), ("dupe", j(dupe?.javaDescription)),
            ("cabrillo", j(cabrillo?.javaDescription)), ("ui", j(ui?.javaDescription)),
            ("operating", j(operating?.javaDescription)),
        ])
    }
}

extension ContestDefinition.Operating {
    var javaDescription: String {
        record("Operating", [("offTime", j(offTime?.javaDescription)), ("bandChange", j(bandChange?.javaDescription)),
                             ("rules", list(rules) { $0.javaDescription })])
    }
}

extension ContestDefinition.OperatingRule {
    var javaDescription: String {
        record("OperatingRule", [("when", map(when) { j($0) }), ("offTime", j(offTime?.javaDescription)),
                                 ("bandChange", j(bandChange?.javaDescription))])
    }
}

extension ContestDefinition.OffTime {
    var javaDescription: String {
        record("OffTime", [("minimumMinutes", j(minimumMinutes)), ("requiredMinutes", j(requiredMinutes))])
    }
}

extension ContestDefinition.BandChange {
    var javaDescription: String {
        record("BandChange", [("minimumMinutes", j(minimumMinutes)), ("perHour", j(perHour))])
    }
}

extension ContestDefinition.Metadata {
    var javaDescription: String {
        record("Metadata", [("name", j(name)), ("organizer", j(organizer)), ("description", j(description)),
                            ("officialUrl", j(officialUrl))])
    }
}

extension ContestDefinition.Period {
    var javaDescription: String {
        record("Period", [("durationHours", j(durationHours)), ("sessions", j(sessions?.javaDescription))])
    }
}

extension ContestDefinition.Sessions {
    var javaDescription: String {
        record("Sessions", [("start", j(start)), ("minutes", j(minutes))])
    }
}

extension ContestDefinition.Category {
    var javaDescription: String {
        record("Category", [("id", j(id)), ("label", j(label))])
    }
}

extension ContestDefinition.StationClass {
    var javaDescription: String {
        record("StationClass", [("id", j(id)), ("when", j(when?.javaDescription))])
    }
}

extension ContestDefinition.Exchange {
    var javaDescription: String {
        record("Exchange", [("sent", list(sent) { $0.javaDescription }),
                            ("received", list(received) { $0.javaDescription })])
    }
}

extension ContestDefinition.ExchangeField {
    var javaDescription: String {
        record("ExchangeField", [
            ("id", j(id)), ("type", j(type?.rawValue)), ("required", String(required)),
            ("source", j(source?.rawValue)), ("appliesWhen", j(appliesWhen?.javaDescription)),
            ("validation", j(validation?.javaDescription)), ("estimate", j(estimate)),
        ])
    }
}

extension ContestDefinition.AppliesWhen {
    var javaDescription: String {
        record("AppliesWhen", [("workedClass", j(workedClass))])
    }
}

extension ContestDefinition.FieldValidation {
    var javaDescription: String {
        record("FieldValidation", [("regex", j(regex)), ("min", j(min)), ("max", j(max)), ("length", j(length))])
    }
}

extension ContestDefinition.Condition {
    var javaDescription: String {
        record("Condition", [
            ("allOf", list(allOf) { $0.javaDescription }), ("anyOf", list(anyOf) { $0.javaDescription }),
            ("not", j(not?.javaDescription)), ("ownDxcc", j(ownDxcc)), ("sameDxcc", j(sameDxcc)),
            ("sameContinent", j(sameContinent)), ("otherContinent", j(otherContinent)),
            ("continentIs", j(continentIs)), ("ownContinentIs", j(ownContinentIs)),
            ("workedClass", j(workedClass)), ("dxccIn", list(dxccIn) { j($0) }), ("bandIn", list(bandIn) { j($0) }),
            ("mode", j(mode)), ("fieldEquals", j(fieldEquals?.javaDescription)), ("fieldPresent", j(fieldPresent)),
            ("expr", j(expr)), ("bonusStation", j(bonusStation)),
        ])
    }
}

extension ContestDefinition.FieldEquals {
    var javaDescription: String {
        record("FieldEquals", [("field", j(field)), ("value", j(value))])
    }
}

extension ContestDefinition.Scoring {
    var javaDescription: String {
        record("Scoring", [("qsoPoints", j(qsoPoints?.javaDescription)), ("bonuses", list(bonuses) { $0.javaDescription }),
                           ("total", j(total)), ("qtc", j(qtc?.javaDescription))])
    }
}

extension ContestDefinition.Qtc {
    var javaDescription: String {
        record("Qtc", [("points", j(points)), ("maxPerStation", j(maxPerStation)), ("groupSize", j(groupSize))])
    }
}

extension ContestDefinition.QsoPoints {
    var javaDescription: String {
        record("QsoPoints", [("mode", j(mode?.rawValue)), ("defaultValue", String(defaultValue)),
                             ("rules", list(rules) { $0.javaDescription })])
    }
}

extension ContestDefinition.PointRule {
    var javaDescription: String {
        record("PointRule", [("when", j(when?.javaDescription)), ("value", j(value?.javaDescription))])
    }
}

extension ContestDefinition.PointValue {
    var javaDescription: String {
        record("PointValue", [("fixed", j(fixed)), ("expr", j(expr)), ("perKm", j(perKm?.javaDescription))])
    }
}

extension ContestDefinition.PerKm {
    var javaDescription: String {
        record("PerKm", [("field", j(field)), ("factor", javaDouble(factor)), ("round", j(round)),
                         ("min", j(min)), ("max", j(max))])
    }
}

extension ContestDefinition.Bonus {
    var javaDescription: String {
        record("Bonus", [("id", j(id)), ("when", j(when?.javaDescription)), ("value", j(value?.javaDescription)),
                         ("scope", j(scope?.rawValue))])
    }
}

extension ContestDefinition.MultiplierBinding {
    var javaDescription: String {
        record("MultiplierBinding", [
            ("id", j(id)), ("set", j(set)), ("from", j(from)), ("scope", j(scope?.rawValue)), ("label", j(label)),
            ("appliesWhen", j(appliesWhen?.javaDescription)), ("bandWeights", map(bandWeights) { j($0) }),
        ])
    }
}

extension ContestDefinition.Dupe {
    var javaDescription: String {
        record("Dupe", [("scope", j(scope?.rawValue)), ("dupeWorthZero", j(dupeWorthZero))])
    }
}

extension ContestDefinition.Cabrillo {
    var javaDescription: String {
        record("Cabrillo", [("contestName", j(contestName)), ("sentOrder", list(sentOrder) { j($0) }),
                            ("receivedOrder", list(receivedOrder) { j($0) })])
    }
}

extension ContestDefinition.Ui {
    var javaDescription: String {
        record("Ui", [("entryOrder", list(entryOrder) { j($0) }), ("logColumns", list(logColumns) { j($0) })])
    }
}

// MARK: - helpers

private func record(_ name: String, _ fields: [(String, String)]) -> String {
    name + "[" + fields.map { "\($0.0)=\($0.1)" }.joined(separator: ", ") + "]"
}

private func j(_ value: String?) -> String { value ?? "null" }
private func j(_ value: Int?) -> String { value.map { String($0) } ?? "null" }
private func j(_ value: Bool?) -> String { value.map { String($0) } ?? "null" }

/// Java `List.toString()`: a `null` element is printed as `null`.
private func list<T>(_ items: [T?]?, _ describe: (T) -> String) -> String {
    guard let items else { return "null" }
    return "[" + items.map { $0.map(describe) ?? "null" }.joined(separator: ", ") + "]"
}

/// Java `LinkedHashMap.toString()`: `{k=v, …}` in insertion order.
private func map<V>(_ map: YamlOrderedMap<V>?, _ describe: (V?) -> String) -> String {
    guard let map else { return "null" }
    return "{" + map.pairs.map { "\($0.key)=\(describe($0.value))" }.joined(separator: ", ") + "}"
}

/// Java `Double.toString` (JDK 19+: the shortest representation that reads back):
/// in the range 10⁻³ ≤ |x| < 10⁷ decimal with at least one digit after the point,
/// otherwise scientific `d.dddE±n`. Digits are taken from Swift's shortest representation.
func javaDouble(_ value: Double) -> String {
    if value == 0 { return value.sign == .minus ? "-0.0" : "0.0" }
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    let text = "\(Swift.abs(value))"
    var mantissa = Substring(text)
    var exponent = 0
    if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
        mantissa = text[..<e]
        exponent = Int(text[text.index(after: e)...].replacingOccurrences(of: "+", with: "")) ?? 0
    }
    let parts = mantissa.split(separator: ".", omittingEmptySubsequences: false)
    let integer = String(parts[0])
    var digits = integer + (parts.count > 1 ? String(parts[1]) : "")
    // value = 0.digits × 10^point
    var point = integer.count + exponent
    while digits.count > 1 && digits.first == "0" {
        digits.removeFirst()
        point -= 1
    }
    while digits.count > 1 && digits.last == "0" {
        digits.removeLast()
    }
    let magnitude = Swift.abs(value)
    let body: String
    if magnitude >= 1e-3 && magnitude < 1e7 {
        if point <= 0 {
            body = "0." + String(repeating: "0", count: -point) + digits
        } else if point >= digits.count {
            body = digits + String(repeating: "0", count: point - digits.count) + ".0"
        } else {
            body = digits.prefix(point) + "." + digits.dropFirst(point)
        }
    } else {
        let head = String(digits.first!)
        let tail = digits.count > 1 ? String(digits.dropFirst()) : "0"
        body = head + "." + tail + "E" + String(point - 1)
    }
    return (value < 0 ? "-" : "") + body
}
