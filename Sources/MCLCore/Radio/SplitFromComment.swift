/// Transmit frequency from a spot's split comment (N1MM "Split Mode and Frequencies Set
/// Automatically from Cluster Spots", DXLog DX cluster → auto split): `UP 5`, `UP5`,
/// `up 2-4`, `DOWN 3`/`DN 3`, `QSX 14025.5` and the shortened `QSX 025` (completed from the spot
/// frequency). A bare `UP` means the default shift. Mirrors the Java `radio.SplitFromComment`.
///
/// Java edge cases (measured in a maintainer-only probe, rows `SPLIT.parse`):
/// `\d`, `\s` and `\b` are ASCII (`UP٥`, `UP` + NBSP + `5` = a bare `UP`); `Math.round`
/// saturates to `Long.MAX_VALUE` and the sum **wraps** (`UP 99999999999999999999` → `nil`,
/// not a crash —); the first match wins (`dn5 up3` → down).
public enum SplitFromComment {

    /// A split farther than this from the spot is not one (typo, another band).
    static let maxOffsetHz: Int64 = 100_000

    private static let qsxPattern: JavaRegex = compile("\\bQSX\\s*(\\d+(?:\\.\\d+)?)")
    private static let upDownPattern: JavaRegex =
        compile("\\b(UP|DOWN|DN)\\s*(\\d+(?:\\.\\d+)?)?(?:\\s*-\\s*\\d+(?:\\.\\d+)?)?\\b")

    private static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor split komentáře musí jít zkompilovat: \(error)")
        }
    }

    /// - Parameters:
    ///   - spotFreqHz: spot frequency (where the DX listens = my RX)
    ///   - defaultUpHz: shift for a bare "UP" (typically 1 kHz CW, 5 kHz phone)
    /// - Returns: transmit frequency in Hz, or `nil` (the comment gives no split)
    public static func parse(_ comment: String?, spotFreqHz: Int, defaultUpHz: Int) -> Int? {
        guard let comment, !JavaText.isBlank(comment), spotFreqHz > 0 else {
            return nil
        }
        // port convention: `uppercased()` = Java `toUpperCase(Locale.ROOT)`
        let c = comment.uppercased()
        let spot = Int64(spotFreqHz)
        if let q = qsxPattern.firstMatch(in: c), let digits = q.group(1) {
            return sane(qsx(digits, spot), spot)
        }
        guard let m = upDownPattern.firstMatch(in: c), let word = m.group(1) else {
            return nil
        }
        let sign: Int64 = word == "UP" ? 1 : -1
        let offset: Int64
        if let amount = m.group(2) {
            offset = JavaMath.round(number(amount) * 1000)
        } else {
            if sign < 0 {
                return nil // a bare DOWN is ambiguous
            }
            offset = Int64(defaultUpHz)
        }
        return sane(spot &+ (sign &* offset), spot)
    }

    /// QSX: the full frequency in kHz, or trailing digits completed from the spot frequency.
    private static func qsx(_ text: String, _ spotFreqHz: Int64) -> Int64 {
        let intPart: Substring = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let value = number(text)
        let spotKHz = spotFreqHz / 1000
        if intPart.utf16.count >= 4 || value >= 1000 {
            return JavaMath.round(value * 1000)
        }
        // `(long) Math.pow(10, length)` for a length of 1–3
        var mod: Int64 = 1
        for _ in 0..<intPart.utf16.count {
            mod *= 10
        }
        let baseKHz = spotKHz / mod * mod
        return JavaMath.round((Double(baseKHz) + value) * 1000)
    }

    /// `Double.parseDouble` over what the regex caught (`\d+(\.\d+)?` in ASCII) — always succeeds.
    private static func number(_ text: String) -> Double {
        JavaDouble.parseDouble(text) ?? .nan
    }

    private static func sane(_ txHz: Int64, _ spotFreqHz: Int64) -> Int? {
        let d = JavaMath.abs(txHz &- spotFreqHz)
        return d > 0 && d <= maxOffsetHz ? Int(txHz) : nil
    }
}
