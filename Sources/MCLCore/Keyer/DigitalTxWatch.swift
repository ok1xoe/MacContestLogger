/// Watching fldigi after a digital transmit (`AppState.sendDigitalText`, `AS:1596-1609`): wait 500 ms, then poll
/// `trxState` every 500 ms at most 240 times (2 minutes); the lamp goes out when fldigi reports anything but `TX`
/// (a failed poll counts as `"RX"`) or after the 240th poll. Every poll first checks that the send is still the current
/// one (`cwToken == token`), otherwise the watch ends without touching the lamp.
///
/// **Deliberate difference:** Kotlin's `return@repeat` after the first non-`TX` only skips the delay and keeps polling — up to
/// ~240 quick XML-RPC calls in a row. The visible behaviour is kept (the lamp goes out at the first non-`TX`), the burst
/// of polls after it is dropped.
public struct DigitalTxWatch: Sendable, Equatable {

    public static let initialDelayMillis: Int64 = 500
    public static let pollIntervalMillis: Int64 = 500
    public static let maxPolls = 240

    /// What the runner does next.
    public enum Step: Equatable, Sendable {
        /// Wait this long, then call `next` again.
        case wait(milliseconds: Int64)
        /// Ask fldigi for `trxState` (on the keyer lane) and hand the answer to `record`.
        case poll
        /// The watch is over: put the lamp out if the token is still current (`SendLamp.finishDigital`).
        case finish
        /// The send is no longer current (aborted or superseded) — end without touching the lamp.
        case abandon
    }

    enum Phase: Equatable, Sendable {
        case start
        case ready
        case polled
        case waited
        case done
    }

    private(set) var phase: Phase = .start
    /// Polls made so far.
    public private(set) var polls = 0

    public init() {}

    /// The next step; `tokenCurrent` = `cwToken == token` at this moment.
    public mutating func next(tokenCurrent: Bool) -> Step {
        switch phase {
        case .start:
            phase = .ready
            return .wait(milliseconds: Self.initialDelayMillis)
        case .polled:
            phase = .waited
            return .wait(milliseconds: Self.pollIntervalMillis)
        case .done:
            return .finish
        case .ready, .waited:
            if polls >= Self.maxPolls {
                phase = .done
                return .finish
            }
            guard tokenCurrent else { return .abandon }
            return .poll
        }
    }

    /// The answer of a poll: `trxState()`, or `nil` when it failed (`getOrDefault("RX")`).
    public mutating func record(state: String?) {
        polls += 1
        phase = (state ?? "RX") == "TX" ? .polled : .done
    }
}
