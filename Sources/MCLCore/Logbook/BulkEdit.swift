import Foundation

/// Bulk edits of selected QSOs (N1MM Log window → right click: change of
/// operator, mode, frequency, time shift, time interpolation). Modifies the passed
/// QSOs in place; saving and score recomputation are done by the caller.
///
/// Mirrors the Java `final class BulkEdit` (private constructor, only static
/// methods) — a stateless utility, hence a caseless enum, the same pattern as
/// `WorkedBefore`/`Interlock`. Port of `BulkEdit.java`.
public enum BulkEdit {

    /// Operator on all QSOs. An empty/`nil` input clears the operator (here an empty
    /// string — the same convention as the rest of the port, see `Qso.operator`).
    public static func setOperator(_ qsos: inout [Qso], operator text: String?) {
        let op = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for i in qsos.indices {
            qsos[i].operator = op
        }
    }

    /// Mode on all QSOs.
    public static func setMode(_ qsos: inout [Qso], mode: Mode?) {
        for i in qsos.indices {
            qsos[i].mode = mode
        }
    }

    /// Frequency (and from it the band, via `Qso.freqHz`) on all QSOs.
    public static func setFrequencyHz(_ qsos: inout [Qso], freqHz: Int) {
        for i in qsos.indices {
            qsos[i].freqHz = freqHz
        }
    }

    /// kHz with a dot or comma → Hz; empty when it is not a frequency in a band
    /// (or when the text is not exactly representable in Hz — for plain and decimal
    /// numbers the same result as Java's `BigDecimal(...).longValueExact()`,
    /// but without a detour through floating point, which with more than
    /// three decimal places could round instead of failing).
    ///
    /// It deliberately does not accept exponential notation (`"1.4025e4"`), which
    /// `BigDecimal` accepts and `longValueExact()` would compute the same
    /// 14,025,000 Hz from as from `"14025"` — an operator never types an
    /// exponent into the on-screen kHz field, so exact manual decimal arithmetic would only
    /// risk an error on inputs that really occur. Covered by the test
    /// `exponentialNotationIsRejected`.
    public static func parseFrequencyKHz(_ text: String) -> Int? {
        guard let hz = exactHz(fromKHzText: text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return Band.from(frequencyHz: hz) != nil ? hz : nil
    }

    /// Exact conversion of textual kHz to Hz (shift by three decimal places). `nil`
    /// when the text is not a number, or when the result would not be a whole number of Hz.
    ///
    /// It understands only plain and decimal notation (optional sign, digits,
    /// one optional decimal point) — unlike Java's `BigDecimal(String)` it
    /// **does not understand exponential notation** (`"1e4"`, `"1.4025e4"`).
    /// A decimal part with an exponent contains the letter `e`, which `allSatisfy
    /// (\.isNumber)` below rejects — that is intended, not a gap; see the comment at
    /// `parseFrequencyKHz`.
    private static func exactHz(fromKHzText text: String) -> Int? {
        var s = Substring(text)
        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s = s.dropFirst()
        } else if s.hasPrefix("+") {
            s = s.dropFirst()
        }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let intPart = String(parts[0])
        let fracPart = parts.count == 2 ? String(parts[1]) : ""
        guard !(intPart.isEmpty && fracPart.isEmpty) else { return nil }
        guard intPart.allSatisfy(\.isNumber), fracPart.allSatisfy(\.isNumber) else { return nil }
        if fracPart.count > 3 {
            guard fracPart.dropFirst(3).allSatisfy({ $0 == "0" }) else { return nil }
        }
        let usedFrac = String(fracPart.prefix(3))
        let paddedFrac = usedFrac + String(repeating: "0", count: 3 - usedFrac.count)
        let digits = (intPart.isEmpty ? "0" : intPart) + paddedFrac
        guard let value = Int(digits) else { return nil }
        return negative ? -value : value
    }

    /// Shifts the times of all QSOs (N1MM „Shift all timestamps").
    public static func shiftTime(_ qsos: inout [Qso], by seconds: TimeInterval) {
        for i in qsos.indices {
            if let t = qsos[i].timestampUtc {
                qsos[i].timestampUtc = t.addingTimeInterval(seconds)
            }
        }
    }

    private static let shiftPattern = try! NSRegularExpression(
        pattern: "^([+-])?(?:(\\d+):)?(\\d+)\\s*([hm]?)$"
    )

    /// Time shift from text: `+5` / `-5` minutes, `+1:30` hours:minutes, `+2h`,
    /// `-90m`. Without a sign = forward. Returns seconds (`TimeInterval`) —
    /// Java's `Duration` has no everyday equivalent in Swift
    /// (adding to a `Date`), hence seconds like the rest of the port.
    public static func parseShift(_ text: String?) -> TimeInterval? {
        guard let text else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = shiftPattern.firstMatch(in: normalized, range: range) else { return nil }

        func group(_ idx: Int) -> String? {
            guard let r = Range(match.range(at: idx), in: normalized) else { return nil }
            return String(normalized[r])
        }

        let sign = group(1)
        let hoursGroup = group(2)
        guard let bText = group(3), let b = Int64(bText) else { return nil }
        let unit = group(4) ?? ""

        let minutes: Int64
        if let hoursGroup, let a = Int64(hoursGroup) {
            minutes = a * 60 + b
        } else if unit == "h" {
            minutes = b * 60
        } else {
            minutes = b
        }
        guard minutes != 0 else { return nil }
        let signed = sign == "-" ? -minutes : minutes
        return TimeInterval(signed * 60)
    }

    /// Time interpolation (N1MM, a paper log entered after the fact): the first and
    /// last QSO (in write order, i.e. by `id`) keep their time, the others
    /// get evenly distributed times between them, rounded to whole
    /// minutes.
    ///
    /// - Returns: `false` when there are fewer than three QSOs or the boundary times are missing.
    @discardableResult
    public static func interpolateTime(_ qsos: inout [Qso]) -> Bool {
        guard qsos.count >= 3 else { return false }

        let orderedIndices = qsos.indices.sorted { a, b in
            (qsos[a].id ?? Int64.max) < (qsos[b].id ?? Int64.max)
        }
        guard let firstIndex = orderedIndices.first, let lastIndex = orderedIndices.last,
              let first = qsos[firstIndex].timestampUtc,
              let last = qsos[lastIndex].timestampUtc,
              last >= first else {
            return false
        }

        let spanSeconds = Int64(last.timeIntervalSince(first).rounded(.towardZero))
        let n = orderedIndices.count - 1
        guard n > 0 else { return false }
        for i in 1..<n {
            let sec = spanSeconds * Int64(i) / Int64(n)
            let t = first.addingTimeInterval(TimeInterval(sec))
            let roundedEpoch = (t.timeIntervalSince1970 / 60.0).rounded() * 60.0
            qsos[orderedIndices[i]].timestampUtc = Date(timeIntervalSince1970: roundedEpoch)
        }
        return true
    }
}
