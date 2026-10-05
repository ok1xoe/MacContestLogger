/// Result of evaluating one multiplier binding for a QSO. Port of Java
/// `engine/MultiplierEvalResult.java` (record + enum); pure data, freely shared between threads.
///
/// - `bindingId`, `setId`: id of the binding and its `set` from the definition (may be missing from YAML → `nil`),
/// - `key`: canonical key; `nil` for `suspicious`/`invalidFormat`,
/// - `scopeKey`: scope key (band / mode / `band|mode` / `*`; a missing band or mode is the text `null`),
/// - `countsAsMultiplier`: counts (for a valid key always, even for `unknownAccepted`),
/// - `isNew`: not yet worked in this scope (even for `unknownAccepted`).
///
/// `==` is Java `record.equals`: texts are compared **by UTF-16 units**, not canonically.
public struct MultiplierEvalResult: Equatable, Sendable {

    /// Classification for the UI; `rawValue` is the Java constant name.
    public enum MultiplierState: String, Sendable {
        case knownAlreadyWorked = "KNOWN_ALREADY_WORKED"
        case knownNewMultiplier = "KNOWN_NEW_MULTIPLIER"
        case unknownAccepted = "UNKNOWN_ACCEPTED"
        case suspicious = "SUSPICIOUS"
        case invalidFormat = "INVALID_FORMAT"
    }

    public let bindingId: String?
    public let setId: String?
    public let key: String?
    public let scopeKey: String
    public let state: MultiplierState
    public let countsAsMultiplier: Bool
    public let isNew: Bool

    public init(bindingId: String?, setId: String?, key: String?, scopeKey: String, state: MultiplierState,
                countsAsMultiplier: Bool, isNew: Bool) {
        self.bindingId = bindingId
        self.setId = setId
        self.key = key
        self.scopeKey = scopeKey
        self.state = state
        self.countsAsMultiplier = countsAsMultiplier
        self.isNew = isNew
    }

    public static func == (left: MultiplierEvalResult, right: MultiplierEvalResult) -> Bool {
        left.state == right.state && left.countsAsMultiplier == right.countsAsMultiplier
            && left.isNew == right.isNew && same(left.bindingId, right.bindingId)
            && same(left.setId, right.setId) && same(left.key, right.key)
            && JavaText.equals(left.scopeKey, right.scopeKey)
    }

    /// Java `Objects.equals` over texts (by UTF-16).
    private static func same(_ left: String?, _ right: String?) -> Bool {
        guard let left else { return right == nil }
        return JavaText.equals(left, right)
    }
}
