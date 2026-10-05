import Foundation

/// One QTC (WAE): a report of an earlier QSO (`time call serial`) handed to station
/// `partnerCall` in series `groupNr/groupSize`. A literal port of Java
/// `record QtcRecord` — the fields are therefore var (a record is immutable, but all
/// fields are constructor parameters with no special logic), types 1:1.
public struct QtcRecord: Equatable, Sendable {
    /// `nil` until saved (`id` is the `AUTOINCREMENT` column `qtc.id`).
    public var id: Int64?
    public var contestId: String?
    /// `true` = I sent the QTC (non-EU), `false` = received (EU).
    public var sent: Bool
    public var partnerCall: String
    public var groupNr: Int
    public var groupSize: Int
    /// Time of the reported QSO `HHmm`.
    public var qsoTime: String
    public var qsoCall: String
    public var qsoSerial: Int
    /// When the QTC was handed over.
    public var at: Date
    public var freqHz: Int64
    public var mode: String?

    public init(
        id: Int64? = nil,
        contestId: String?,
        sent: Bool,
        partnerCall: String,
        groupNr: Int,
        groupSize: Int,
        qsoTime: String,
        qsoCall: String,
        qsoSerial: Int,
        at: Date,
        freqHz: Int64,
        mode: String?
    ) {
        self.id = id
        self.contestId = contestId
        self.sent = sent
        self.partnerCall = partnerCall
        self.groupNr = groupNr
        self.groupSize = groupSize
        self.qsoTime = qsoTime
        self.qsoCall = qsoCall
        self.qsoSerial = qsoSerial
        self.at = at
        self.freqHz = freqHz
        self.mode = mode
    }
}

extension QtcRecord {
    /// Encodes `at` into the text form of the column `qtc.at_utc` the same way as
    /// Java `Instant.toString()` (ISO-8601 UTC) — `LogbookRepository.insertQtc`
    /// writes `q.at().toString()`, `findQtcs` reads `Instant.parse(...)`.
    ///
    /// Java `Instant.toString()` has a **variable width** of the fraction of a second, not just
    /// "nothing, or three digits": for a whole second it omits the fraction entirely, otherwise it
    /// picks the smallest width that expresses the value exactly — 3 digits
    /// (milliseconds, `nanoOfSecond % 1_000_000 == 0`), 6 (microseconds,
    /// `% 1_000 == 0`), or 9 (nanoseconds, anything else). The six-digit
    /// form is not theoretical — `Instant.now()` on this machine gave
    /// `"...T08:38:26.420028Z"` (6 digits) and the Kotlin UI builds every real
    /// `QtcRecord.at` exactly via `Instant.now()` (`AppState.kt:613`), so
    /// microsecond precision is common in live operation.
    ///
    /// **What this implementation really guarantees — verified by a test, not just
    /// computed:** `Date` is a `Double` (seconds since the reference date) — at
    /// today's date it has a resolution of the order of 100–250 ns (ULP around 2⁻²² s for numbers
    /// of today's epoch magnitude), not arbitrary precision. That **safely**
    /// distinguishes only a whole second (0 digits) and a millisecond (3 — the ULP error is
    /// three orders of magnitude smaller than the 10⁶ ns step, both cases round-trip byte-exact,
    /// see `formatAtUtcForWholeSecond`/`formatAtUtcForMillisecond`).
    ///
    /// **A microsecond (6 digits) or a nanosecond (9) is not guaranteed byte-exact** —
    /// and this is not extra theoretical caution, it is measured: the real
    /// six-digit text from `Instant.now()` on this machine,
    /// `"2026-09-29T08:38:26.420028Z"`, comes back via `Date` as
    /// `"...420027971Z"` — nine digits, the last six different from what was
    /// on input (an error of 29 ns). The reason: adding a large number (seconds since the epoch,
    /// ~1.8 × 10⁹) and a small fraction (hundredths of a microsecond) in one `Double`
    /// necessarily rounds the fraction to the ~22 remaining mantissa bits —
    /// regardless of how many digits the input text had. `formatAtUtc` then
    /// derives the fraction width again from such an already inexact value (according to whether the
    /// rounded nanosecond is a multiple of 1000 or 10⁶) — an originally six-digit
    /// input therefore usually comes out as nine-digit, with different last
    /// digits than it had on input. Only this is guaranteed: the error is of the order of units
    /// to hundreds of nanoseconds (see `microsecondPrecisionRoundTripsWithinAMicrosecond`,
    /// `nanosecondPrecisionRoundTripsWithinAMicrosecond`) — for the order of rows
    /// in `qtc` (`ORDER BY at_utc`) between different instants this does not matter, it just does not
    /// match byte for byte what Java would write for the same instant.
    static func formatAtUtc(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        let wholeSeconds = interval.rounded(.down)
        let fractionalSeconds = interval - wholeSeconds
        var nanos = Int64((fractionalSeconds * 1_000_000_000).rounded())
        var seconds = wholeSeconds
        if nanos >= 1_000_000_000 { // rounding the fraction up to a whole second
            nanos -= 1_000_000_000
            seconds += 1
        }

        let baseFormatter = ISO8601DateFormatter()
        baseFormatter.formatOptions = [.withInternetDateTime]
        let base = baseFormatter.string(from: Date(timeIntervalSince1970: seconds))
        guard nanos != 0 else { return base }

        let digits: Int
        let fractionValue: Int64
        if nanos % 1_000_000 == 0 {
            digits = 3
            fractionValue = nanos / 1_000_000
        } else if nanos % 1_000 == 0 {
            digits = 6
            fractionValue = nanos / 1_000
        } else {
            digits = 9
            fractionValue = nanos
        }
        let fractionText = String(format: "%0\(digits)ld", fractionValue)
        let withoutTrailingZ = base.dropLast() // "...ssZ" → "...ss"
        return "\(withoutTrailingZ).\(fractionText)Z"
    }

    /// Decodes `at_utc` back to `Date`. The fraction of a second is parsed by hand —
    /// **not** via `ISO8601DateFormatter` with `.withFractionalSeconds`, which
    /// silently truncates anything above three digits after the decimal point (a six-
    /// or nine-digit notation would thus lose precision without any error).
    /// Accepts any number of fraction digits (Java writes 0, 3, 6 or 9, but the
    /// parser does not insist — more than 9 digits are truncated, fewer are padded
    /// with zeros on the right, which never happens for valid input from `formatAtUtc`/Java).
    /// nenastane).
    static func parseAtUtc(_ text: String) -> Date? {
        guard text.hasSuffix("Z") else { return nil }
        let body = text.dropLast() // without "Z"
        let baseFormatter = ISO8601DateFormatter()
        baseFormatter.formatOptions = [.withInternetDateTime]

        guard let dotIndex = body.firstIndex(of: ".") else {
            return baseFormatter.date(from: text) // without a fraction, as before
        }
        guard let base = baseFormatter.date(from: String(body[..<dotIndex]) + "Z") else { return nil }

        let fractionDigits = body[body.index(after: dotIndex)...]
        guard !fractionDigits.isEmpty else { return base }
        let padded = fractionDigits.count >= 9
            ? String(fractionDigits.prefix(9))
            : fractionDigits + String(repeating: "0", count: 9 - fractionDigits.count)
        guard let nanos = Int64(padded) else { return base }
        return base.addingTimeInterval(Double(nanos) / 1_000_000_000)
    }
}
