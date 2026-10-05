/// Parsed value of one exchange field. Port of Java `exchange/ExchangeValue.java`
/// (`record`); texts are optional because a Java record validates nothing.
///
/// - `raw`: original input
/// - `canonical`: canonical form (e.g. a zone without leading zeros, a code in upper case)
/// - `valid`: did it pass the format/validation?
/// - `error`: reason when `valid == false`
///
/// `==` is Java `record.equals`: texts are compared **by UTF-16 units**, not canonically
/// (`A` + U+030A ≠ U+00C5, Kelvin `K` ≠ `K`) — a synthesized `==` would consider them equal.
public struct ExchangeValue: Equatable, Sendable {
    public let raw: String?
    public let canonical: String?
    public let valid: Bool
    public let error: String?

    public init(raw: String?, canonical: String?, valid: Bool, error: String?) {
        self.raw = raw
        self.canonical = canonical
        self.valid = valid
        self.error = error
    }

    /// Java `ExchangeValue.valid(raw, canonical)` — error `null`.
    public static func valid(_ raw: String?, _ canonical: String?) -> ExchangeValue {
        ExchangeValue(raw: raw, canonical: canonical, valid: true, error: nil)
    }

    /// Java `ExchangeValue.invalid(raw, error)` — canonical form `null`.
    public static func invalid(_ raw: String?, _ error: String?) -> ExchangeValue {
        ExchangeValue(raw: raw, canonical: nil, valid: false, error: error)
    }

    /// Java `ExchangeValue.empty()` — nobody calls it in Java, ported for completeness of the record.
    public static func empty() -> ExchangeValue {
        ExchangeValue(raw: "", canonical: nil, valid: false, error: "prázdné")
    }

    public static func == (left: ExchangeValue, right: ExchangeValue) -> Bool {
        left.valid == right.valid && same(left.raw, right.raw) && same(left.canonical, right.canonical)
            && same(left.error, right.error)
    }

    /// Java `Objects.equals` over texts (by UTF-16).
    private static func same(_ left: String?, _ right: String?) -> Bool {
        guard let left else { return right == nil }
        return JavaText.equals(left, right)
    }
}
