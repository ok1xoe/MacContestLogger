/// The lit F-key of the CW / digital keyer and its cancellation token (`AppState.cwSendingKey`, `cwToken`,
/// `digitalSending` — `AS:1443-1536`, `AS:1580-1642`, `AS:1714-1755`). A pure value; the model owns one on the main
/// actor and hands the token to the lane, so a late result of an older send never clears a newer lamp.
public struct SendLamp: Sendable, Equatable {

    /// A send started by `begin`.
    public struct Begin: Equatable, Sendable {
        public let token: Int64
        /// A message was lit before (`wasSending`): the keyer is aborted before sending (`AS:1720`).
        public let wasSending: Bool
    }

    /// `cwSendingKey`: the lit F-key (0 = F1, the last index of an ESM pair), `-1` = free text, `nil` = nothing.
    public private(set) var key: Int?
    /// `cwToken` (Kotlin `Long`, wrapping).
    public private(set) var token: Int64 = 0
    /// `digitalSending`.
    public private(set) var digitalSending = false

    public init() {}

    /// `sendCw` (`AS:1714-1735`): `wasSending = cwSendingKey != null`, `++cwToken`, light `key`.
    public mutating func begin(key: Int) -> Begin {
        let wasSending = self.key != nil
        token &+= 1
        self.key = key
        return Begin(token: token, wasSending: wasSending)
    }

    /// `sendDigitalText` (`AS:1580-1586`): `++cwToken`, light `key`, `digitalSending = true`.
    public mutating func beginDigital(key: Int) -> Int64 {
        token &+= 1
        self.key = key
        digitalSending = true
        return token
    }

    /// The end of a send — the CW estimate elapsed, a CW failure, or the end of the digital TX watch: the lamp goes
    /// out only when `token` is still current. `true` = it went out.
    @discardableResult
    public mutating func finish(_ token: Int64) -> Bool {
        guard token == self.token else { return false }
        key = nil
        return true
    }

    /// The end of the digital TX watch (`AS:1606-1609`): lamp and `digitalSending` only for the current token.
    public mutating func finishDigital(_ token: Int64) {
        guard token == self.token else { return }
        key = nil
        digitalSending = false
    }

    /// A failed fldigi transmit (`AS:1591-1594`): the lamp only for the current token, `digitalSending` always.
    public mutating func failDigital(_ token: Int64) {
        if token == self.token {
            key = nil
        }
        digitalSending = false
    }

    /// `abortCw` with an open keyer (`AS:1748-1754`): `wasSending`, `cwToken++`, lamp out. (Without an open keyer
    /// Kotlin returns `false` and touches nothing — the model does not call this then.)
    public mutating func abortCw() -> Bool {
        let wasSending = key != nil
        token &+= 1
        key = nil
        return wasSending
    }

    /// `abortDigital` (`AS:1611-1618`): only while `digitalSending`; then `cwToken++`, lamp out, `true`.
    public mutating func abortDigital() -> Bool {
        guard digitalSending else { return false }
        digitalSending = false
        token &+= 1
        key = nil
        return true
    }

    /// How long the lamp stays lit after the keyer accepted the message (`CwTiming.estimateMillis`,: only an
    /// estimate).
    public static func estimateMillis(_ message: CwMessage, wpm: Int) -> Int64 {
        CwTiming.estimateMillis(message, wpm: wpm)
    }
}
