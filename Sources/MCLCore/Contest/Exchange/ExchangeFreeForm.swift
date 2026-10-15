import Foundation

/// N1MM's free-form exchange (ARRL Sweepstakes): the whole exchange is typed into one box, in any order, and every
/// word goes to the received field it fits (`exchange.freeForm: true`).
///
/// Rules, applied to each word from left to right:
/// 1. the fields with a definite shape (report, number, zone, locator or a `validation`) that accept the word;
/// 2. a word shaped like a callsign is a correction of the logged call (N1MM SS: the call in the exchange wins);
/// 3. a word mixing digits and letters (`123A`, `72OH`) is split at the digit/letter boundaries when every part fits;
/// 4. the free text fields (no shape) that accept the word.
///
/// Of several fields the first one not yet filled by this text wins; when all of them already have a value, the
/// last one is overwritten — typing a value again later in the box corrects it (`123 A 72 OH 73` → check 73).
public enum ExchangeFreeForm {

    /// The entry window's key of the one exchange box (not a valid definition id, so it cannot clash).
    public static let boxId = "~exchange"

    public struct Result: Equatable, Sendable {
        /// Field id → value, in the order the fields were filled.
        public var values: JavaLinkedMap<String>
        /// A callsign typed in the exchange (corrects the logged call), `nil` = none.
        public var call: String?
        /// Words that fit no field.
        public var unparsed: [String]

        public init(values: JavaLinkedMap<String> = JavaLinkedMap(), call: String? = nil, unparsed: [String] = []) {
            self.values = values
            self.call = call
            self.unparsed = unparsed
        }
    }

    public static func parse(_ text: String, fields: [ContestDefinition.ExchangeField]) -> Result {
        var result = Result()
        var filled: Set<String> = []
        let words: [String] = text.uppercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
            .map(String.init)
        for word in words {
            assign(word, fields: fields, filled: &filled, result: &result)
        }
        return result
    }

    private static func assign(_ word: String, fields: [ContestDefinition.ExchangeField], filled: inout Set<String>,
                               result: inout Result) {
        let specific: [ContestDefinition.ExchangeField] = fields.filter { isSpecific($0) && accepts($0, word) }
        if !specific.isEmpty {
            put(word, into: specific, filled: &filled, result: &result)
            return
        }
        if looksLikeCall(word) {
            result.call = word
            return
        }
        let parts: [String] = digitLetterRuns(word)
        if parts.count > 1, parts.allSatisfy({ part in fields.contains { accepts($0, part) } }) {
            for part in parts {
                assign(part, fields: fields, filled: &filled, result: &result)
            }
            return
        }
        let generic: [ContestDefinition.ExchangeField] = fields.filter { !isSpecific($0) && accepts($0, word) }
        if !generic.isEmpty {
            put(word, into: generic, filled: &filled, result: &result)
            return
        }
        result.unparsed.append(word)
    }

    private static func put(_ word: String, into candidates: [ContestDefinition.ExchangeField],
                            filled: inout Set<String>, result: inout Result) {
        guard let chosen = candidates.first(where: { !filled.contains($0.id ?? "") }) ?? candidates.last else { return }
        let id: String = chosen.id ?? ""
        filled.insert(id)
        result.values.put(chosen.id, word)
    }

    /// A field whose values have a shape of their own: a report, a number, a zone, a locator or a `validation`.
    static func isSpecific(_ field: ContestDefinition.ExchangeField) -> Bool {
        if field.validation != nil {
            return true
        }
        switch field.type {
        case .RST, .RS, .SERIAL, .INTEGER, .CQ_ZONE, .ITU_ZONE, .LOCATOR: return true
        default: return false
        }
    }

    static func accepts(_ field: ContestDefinition.ExchangeField, _ word: String) -> Bool {
        guard let value = try? ExchangeEngine().parse(field, word) else { return false }
        return value.valid
    }

    /// A callsign: letters and digits (optionally `/suffix`), at least one of each, ending with a letter, a digit in
    /// the first four characters and not starting with two digits (`72OH` is a check and a section, `4X1AB` a call).
    static func looksLikeCall(_ word: String) -> Bool {
        let base: Substring = word.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
        let chars: [Character] = Array(base)
        guard chars.count >= 3, chars.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let last = chars.last, last.isLetter, chars.contains(where: \.isLetter) else { return false }
        if chars[0].isNumber && chars[1].isNumber {
            return false
        }
        guard let digit = chars.firstIndex(where: \.isNumber), digit <= 3 else { return false }
        // Some letter must come before the last digit, or the first digit be followed by more call (K1A, 4X1AB, 1A not).
        let letterBefore: Bool = chars[..<digit].contains(where: \.isLetter)
        let digitAfterLetter: Bool = chars[(digit + 1)...].contains(where: \.isNumber)
            && chars[(digit + 1)...].contains(where: \.isLetter)
        return letterBefore || digitAfterLetter
    }

    /// `123A` → `123`, `A`; `1A72OH` → `1`, `A`, `72`, `OH`.
    static func digitLetterRuns(_ word: String) -> [String] {
        var runs: [String] = []
        var current: String = ""
        var currentIsDigit: Bool?
        for char in word {
            let isDigit: Bool = char.isASCII && char.isNumber
            if let kind = currentIsDigit, kind != isDigit {
                runs.append(current)
                current = ""
            }
            current.append(char)
            currentIsDigit = isDigit
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    /// The box text for values filled in elsewhere (call history, a spot, QuickEdit): the values in field order.
    public static func text(_ values: JavaLinkedMap<String>, fields: [ContestDefinition.ExchangeField]) -> String {
        fields.compactMap { field -> String? in
            guard let value = values[field.id], !KotlinText.isBlank(value) else { return nil }
            return KotlinText.trim(value)
        }.joined(separator: " ")
    }

    /// The interpretation shown under the box: `nr 123 · prec A · ck 72 · sec OH · call K1ABC · ? XYZ`.
    public static func preview(_ result: Result, fields: [ContestDefinition.ExchangeField]) -> String {
        var parts: [String] = fields.compactMap { field -> String? in
            guard let value = result.values[field.id] else { return nil }
            return (field.id ?? "") + " " + value
        }
        if let call = result.call {
            parts.append("call " + call)
        }
        parts.append(contentsOf: result.unparsed.map { "? " + $0 })
        return parts.joined(separator: " · ")
    }
}

/// N1MM 7QP county line on the received side: `split: true` fields take `A/B/C`, one QSO per part.
public enum ExchangeSplit {

    /// The parts of a split value, upper case; a part shorter than the first one takes the first one's leading
    /// characters (`ORDES/JEF` → `ORDES`, `ORJEF`; `IDFRA/UTCAC` stays). A value without `/` is one part.
    public static func parts(_ value: String) -> [String] {
        let raw: [String] = KotlinText.trim(value).uppercased().split(separator: "/").map {
            KotlinText.trim(String($0))
        }.filter { !$0.isEmpty }
        guard let first = raw.first else { return [] }
        return raw.enumerated().map { index, part in
            guard index > 0, part.count < first.count else { return part }
            return String(first.prefix(first.count - part.count)) + part
        }
    }

    /// The forms to log for one entry: one per combination of the parts of the split fields (usually one field).
    public static func forms(_ form: EntryForm, fields: [ContestDefinition.ExchangeField]) -> [EntryForm] {
        var forms: [EntryForm] = [form]
        for field in fields where field.split {
            guard let value = form.contestExchange[field.id] else { continue }
            let split: [String] = parts(value)
            guard split.count > 1 else { continue }
            forms = forms.flatMap { base in
                split.map { part in
                    var copy = base
                    copy.contestExchange.put(field.id, part)
                    return copy
                }
            }
        }
        return forms
    }
}
