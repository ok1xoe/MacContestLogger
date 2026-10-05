/// What has already been transmitted in a QSO in progress — input for `EsmEngine`. Immutable:
/// each transmission returns a new state. Reset by clearing the fields and logging the QSO.
/// Mirrors the Java `cz.ok1xoe.maccontestlogger.esm.EsmProgress` (record).
public struct EsmProgress: Hashable, Sendable {
    /// Exchange (F2) transmitted.
    public let exchangeSent: Bool
    /// My call (F4) transmitted.
    public let myCallSent: Bool
    /// The call as it was when F5 was transmitted (`nil` = F5 was not sent).
    public let sentCall: String?

    public init(exchangeSent: Bool, myCallSent: Bool, sentCall: String?) {
        self.exchangeSent = exchangeSent
        self.myCallSent = myCallSent
        self.sentCall = sentCall
    }

    public static let empty = EsmProgress(exchangeSent: false, myCallSent: false, sentCall: nil)

    /// State after transmitting keys (whether by Enter or manually by an F-key).
    public func afterSent(_ keys: [Int], _ call: String?) -> EsmProgress {
        EsmProgress(
            exchangeSent: exchangeSent || keys.contains(EsmEngine.f2),
            myCallSent: myCallSent || keys.contains(EsmEngine.f4),
            sentCall: keys.contains(EsmEngine.f5) ? EsmProgress.normalize(call) : sentCall)
    }

    /// Exchange spoken live (phone, N2IC): space from the call field to the exchange in Run
    /// means "I have already said the exchange", the next Enter then sends TU and logs.
    public func withExchangeSent() -> EsmProgress {
        EsmProgress(exchangeSent: true, myCallSent: myCallSent, sentCall: sentCall)
    }

    /// Did the call change since F5 was transmitted? (N1MM "Send corrected call"). Java
    /// `equals` — by UTF-16 units, not canonically.
    public func callCorrected(_ call: String?) -> Bool {
        guard let sentCall else {
            return false
        }
        return !JavaText.equals(sentCall, EsmProgress.normalize(call))
    }

    /// Input for the ESM decision.
    public func state(run: Bool, call: String?, dupe: Bool, exchangeValid: Bool) -> EsmEngine.State {
        let empty: Bool = call.map(JavaText.isBlank) ?? true
        return EsmEngine.State(run: run, callEmpty: empty, dupe: dupe, exchangeValid: exchangeValid,
                               exchangeSent: exchangeSent, myCallSent: myCallSent,
                               callCorrected: callCorrected(call))
    }

    /// Equality of a Java record: `sentCall` by UTF-16 units.
    public static func == (lhs: EsmProgress, rhs: EsmProgress) -> Bool {
        guard lhs.exchangeSent == rhs.exchangeSent, lhs.myCallSent == rhs.myCallSent else {
            return false
        }
        return JavaStringKey(lhs.sentCall) == JavaStringKey(rhs.sentCall)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(exchangeSent)
        hasher.combine(myCallSent)
        hasher.combine(JavaStringKey(sentCall))
    }

    private static func normalize(_ call: String?) -> String {
        guard let call else {
            return ""
        }
        return JavaText.toUpperCase(JavaText.trim(call))
    }
}
