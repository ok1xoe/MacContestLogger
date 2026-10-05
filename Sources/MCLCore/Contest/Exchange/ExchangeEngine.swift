/// Universal configuration-driven exchange engine. Port of Java `exchange/ExchangeEngine.java`.
/// It has a handler for every built-in `FieldType`; a new contest just composes types in YAML. It provides
/// the active fields (by the other station's class — `appliesWhen`), parsing of individual fields and whole
/// lines, default values of sent fields and validation by `field.validation`.
///
/// Java properties that are copied (table `ExchangeMeasured`, probe
/// a maintainer-only probe):
/// - a numeric field above 2³¹−1 **throws** (`ExchangeError.numberFormat`, Java's uncaught
///   `NumberFormatException`) — the caller must handle it;
/// - `ExchangeValue.raw` holds the **original** untrimmed input; trimming is Java `trim()` (≤ U+0020,
///   NBSP stays), emptiness Java `isBlank()` (EM SPACE is blank, NBSP is not);
/// - a syntactically broken `validation.regex` is silently ignored.
///
/// Leniency versus Java (a deliberate divergence from Java v1.1.1): a `nil` element in the field list
/// (Java NPE) is skipped; a regex that the `JavaRegex` adapter does not convert is ignored as broken.
public struct ExchangeEngine: Sendable {

    private static let text = TextHandler()
    private static let numeric = NumericHandler()
    private static let rst = RstHandler()
    private static let locator = LocatorHandler()

    /// Java `"\\s+"` for `parseLine` (ASCII whitespace).
    private static let whitespace: JavaRegex = {
        do {
            return try JavaRegex("\\s+")
        } catch {
            preconditionFailure("pevný vzor '\\s+' musí jít zkompilovat: \(error)")
        }
    }()

    public init() {}

    /// Java `EnumMap` of handlers; other types **and `type == nil`** → the text handler (fallback).
    private func handler(for type: ContestDefinition.FieldType?) -> any ExchangeFieldHandler {
        switch type {
        case .RST, .RS: Self.rst
        case .SERIAL, .INTEGER, .CQ_ZONE, .ITU_ZONE: Self.numeric
        case .LOCATOR: Self.locator
        default: Self.text
        }
    }

    /// Received fields active for the given other-station class (`appliesWhen`): without `appliesWhen`,
    /// with `appliesWhen.workedClass == nil`, or a matching class (Java `equals`, by UTF-16).
    public func activeReceivedFields(_ definition: ContestDefinition,
                                     _ workedClass: String?) -> [ContestDefinition.ExchangeField] {
        guard let received = definition.exchange?.received else {
            return []
        }
        var out: [ContestDefinition.ExchangeField] = []
        for field in received {
            guard let field else { continue }   // Java NPE — a recorded leniency
            guard let fieldClass = field.appliesWhen?.workedClass else {
                out.append(field)
                continue
            }
            if JavaText.equals(fieldClass, workedClass) {
                out.append(field)
            }
        }
        return out
    }

    /// Parses and validates a field value (type + `field.validation`).
    public func parse(_ field: ContestDefinition.ExchangeField, _ raw: String?) throws(ExchangeError) -> ExchangeValue {
        let value = try handler(for: field.type).parse(raw)
        if !value.valid {
            return value
        }
        return Self.applyValidation(field, value)
    }

    /// Order of checks as in Java: `regex` (whole string) → `length` (UTF-16) → `min`/`max`
    /// (`Integer.parseInt`; the error here is only "expected a number").
    private static func applyValidation(_ field: ContestDefinition.ExchangeField,
                                        _ value: ExchangeValue) -> ExchangeValue {
        guard let rule = field.validation else {
            return value
        }
        // A valid value always has a canonical form (all handlers fill it in).
        let canonical = value.canonical ?? ""
        if let regex = rule.regex {
            // Java `PatternSyntaxException` is swallowed (the definition validator reveals it);
            // `.unsupported` (Java may accept the pattern) likewise — a recorded divergence.
            // Java `matches(regex)` compiles on every call; here the translated pattern
            // is taken from the shared cache (`JavaRegexCache`) — the result is the same.
            if let pattern = try? JavaRegexCache.shared.regex(regex), !pattern.matches(canonical) {
                return .invalid(value.raw, "neodpovídá formátu")
            }
        }
        if let length = rule.length, canonical.utf16.count != length {
            return .invalid(value.raw, "očekávaná délka \(length)")
        }
        if rule.min != nil || rule.max != nil {
            guard let number = JavaInteger.parseInt(canonical) else {
                return .invalid(value.raw, "očekáváno číslo")
            }
            if let min = rule.min, Int(number) < min {
                return .invalid(value.raw, "menší než \(min)")
            }
            if let max = rule.max, Int(number) > max {
                return .invalid(value.raw, "větší než \(max)")
            }
        }
        return value
    }

    /// Parses a whole exchange string (CW/phone/paste) positionally onto the given fields: Java
    /// `line.trim().split("\\s+")`; a missing token is `""` (→ "empty"), excess ones are dropped.
    /// Duplicate id: the later value at the position of the first.
    ///
    /// A `nil` element (Java NPE) is skipped, but **consumes its token** — the next fields get
    /// tokens by position in the definition.
    public func parseLine(_ fields: [ContestDefinition.ExchangeField?],
                          _ line: String?) throws(ExchangeError) -> JavaLinkedMap<ExchangeValue> {
        let tokens = line.map { JavaText.split(JavaText.trim($0), regex: Self.whitespace, limit: 0) } ?? []
        var out = JavaLinkedMap<ExchangeValue>()
        for (index, field) in fields.enumerated() {
            guard let field else { continue }
            let token = index < tokens.count ? tokens[index] : ""
            out.put(field.id, try parse(field, token))
        }
        return out
    }

    /// Default values of sent fields (RST by mode, serial, my station values) in
    /// definition order; a `nil` element of `exchange.sent` (Java NPE) is skipped.
    public func sentDefaults(_ definition: ContestDefinition, _ context: ExchangeContext) -> JavaLinkedMap<String> {
        var out = JavaLinkedMap<String>()
        guard let sent = definition.exchange?.sent else {
            return out
        }
        for field in sent {
            guard let field else { continue }
            out.put(field.id, Self.defaultFor(field, context))
        }
        return out
    }

    /// `nil` = Java `null` (`FROM_STATION` with the key present but with a `null` value).
    private static func defaultFor(_ field: ContestDefinition.ExchangeField, _ context: ExchangeContext) -> String? {
        switch field.source {
        case nil:
            return ""
        case .AUTO_RST:
            return context.mode?.defaultRst ?? "599"
        case .AUTO_SERIAL:
            return String(context.nextSerial)
        case .FROM_STATION:
            // Java `getOrDefault(id, "")`: a present key also returns a `null` value
            return context.station.containsKey(field.id) ? context.station[field.id] : ""
        case .ROVER_QTH:
            return context.roverQth ?? ""
        case .MANUAL, .DERIVED:
            return ""
        }
    }
}

// MARK: - built-in handlers

/// Java `raw == null || raw.isBlank()` → `invalid(raw ?? "", "prázdné")`.
private func blank(_ raw: String?) -> ExchangeValue? {
    guard let raw else { return .invalid("", "prázdné") }
    return JavaText.isBlank(raw) ? .invalid(raw, "prázdné") : nil
}

/// Is the text entirely made of characters in the intervals (by UTF-16 units, ASCII classes of the Java regex)?
private func units(_ text: String, count: ClosedRange<Int>,
                   _ allowed: (_ position: Int, _ unit: UInt16) -> Bool) -> Bool {
    let units = Array(text.utf16)
    guard count.contains(units.count) else { return false }
    for (position, unit) in units.enumerated() where !allowed(position, unit) {
        return false
    }
    return true
}

/// `STATE`, `PROVINCE`, `DISTRICT`, `TEXT`, `HQ`, `IOTA`, `DXCC`, `PREFIX`, `NATIONAL`, `QTC`
/// and `type == nil`: `trim().toUpperCase()`.
private struct TextHandler: ExchangeFieldHandler {
    func parse(_ raw: String?) throws(ExchangeError) -> ExchangeValue {
        if let empty = blank(raw) { return empty }
        let raw = raw ?? ""
        return .valid(raw, JavaText.trim(raw).uppercased())
    }
}

/// `SERIAL`, `INTEGER`, `CQ_ZONE`, `ITU_ZONE`: `trim()`, `\d+` (ASCII), `Integer.parseInt` —
/// removes leading zeros, above 2³¹−1 throws like Java.
private struct NumericHandler: ExchangeFieldHandler {
    func parse(_ raw: String?) throws(ExchangeError) -> ExchangeValue {
        if let empty = blank(raw) { return empty }
        let raw = raw ?? ""
        let trimmed = JavaText.trim(raw)
        guard units(trimmed, count: 1...Int.max, { _, unit in (0x30...0x39).contains(unit) }) else {
            return .invalid(raw, "očekáváno číslo")
        }
        guard let number = JavaInteger.parseInt(trimmed) else {
            throw ExchangeError(kind: .numberFormat, message: "For input string: \"" + trimmed + "\"")
        }
        return .valid(raw, String(number))
    }
}

/// `RST`, `RS`: `trim()` and `[1-5][1-9][1-9]?` (RS also takes three digits).
private struct RstHandler: ExchangeFieldHandler {
    func parse(_ raw: String?) throws(ExchangeError) -> ExchangeValue {
        if let empty = blank(raw) { return empty }
        let raw = raw ?? ""
        let trimmed = JavaText.trim(raw)
        let matches = units(trimmed, count: 2...3) { position, unit in
            position == 0 ? (0x31...0x35).contains(unit) : (0x31...0x39).contains(unit)
        }
        return matches ? .valid(raw, trimmed) : .invalid(raw, "neplatný RST/RS")
    }
}

/// `LOCATOR`: `trim().toUpperCase()` and `[A-R]{2}[0-9]{2}([A-X]{2})?`.
private struct LocatorHandler: ExchangeFieldHandler {
    func parse(_ raw: String?) throws(ExchangeError) -> ExchangeValue {
        if let empty = blank(raw) { return empty }
        let raw = raw ?? ""
        let canonical = JavaText.trim(raw).uppercased()
        let matches = canonical.utf16.count != 5 && units(canonical, count: 4...6) { position, unit in
            switch position {
            case 0, 1: (0x41...0x52).contains(unit)    // A–R
            case 2, 3: (0x30...0x39).contains(unit)    // 0–9
            default: (0x41...0x58).contains(unit)      // A–X
            }
        }
        return matches ? .valid(raw, canonical) : .invalid(raw, "neplatný lokátor")
    }
}
