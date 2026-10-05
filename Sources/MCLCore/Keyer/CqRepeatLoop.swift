/// The CQ repeat loop (N1MM Alt+R) of the entry window, `EP:757-768`, as a state machine over injected time (the runner
/// performs the waits with its scheduler):
///
/// ```
/// LaunchedEffect(cqRepeat, call.isBlank(), phone || cw || digi) {
///     if (!cqRepeat || call.isNotBlank() || !(phone || cw || digi)) return
///     while (true) {
///         while (isSending()) delay(100)
///         functionKeys(listOf(F1), refocus = false)
///         delay(250)
///         while (isSending()) delay(100)
///         delay((repeatSeconds * 1000).toLong())
///     }
/// }
/// ```
///
/// A change of any of the three keys cancels the loop and starts it again from the top (typing a call stops it,
/// clearing the call starts it again; Esc switches `cqRepeat` off).
///
/// **Safety — no transmission without an operator action:** the loop **stops** (the runner
/// switches `cqRepeat` off and shows the reason) where Kotlin goes on:
/// - the TX lockout blocks transmitting, or the entry is in post-contest mode — Kotlin keeps pressing F1 and shows the
///   error status again and again; here the check is made when F1 would go out;
/// - the mode is not keyable (call blank, `cqRepeat` on) — Kotlin only pauses and starts calling CQ by itself as soon as
///   the mode becomes keyable again (a CAT poll, a mode change); here the operator must switch the repeat on again;
/// - sending F1 failed (keyer off, no Winkeyer port, fldigi unreachable…) — Kotlin retries after every pause; here the
///   runner reports the failure (`sendFailed`) and the loop stops.
/// Typing a call still only pauses the loop (clearing the call resumes it), as in Kotlin.
public struct CqRepeatLoop: Sendable, Equatable {

    public static let idlePollMillis: Int64 = 100
    public static let afterSendMillis: Int64 = 250

    /// Why the loop stopped instead of sending F1.
    public enum StopReason: Equatable, Sendable {
        /// The multi-op TX interlock blocks transmitting.
        case txLockout
        /// Post-contest entry — the F-keys send nothing.
        case postContest
        /// The mode cannot be keyed (no voice/CW, digital without fldigi).
        case notKeyable
        /// The F1 send failed (the keyer reported an error).
        case sendFailed
    }

    /// What the runner does next.
    public enum Action: Equatable, Sendable {
        /// The loop does not run (`cqRepeat` off or a call typed) — wait for a key change.
        case idle
        /// Wait this long, then ask again.
        case wait(milliseconds: Int64)
        /// Press F1 (`functionKeys(listOf(F1), refocus = false)`), then ask again.
        case sendF1
        /// Switch `cqRepeat` off and show the reason.
        case stop(StopReason)
    }

    /// What the loop reads on every step.
    public struct Inputs: Equatable, Sendable {
        /// `state.cqRepeat`.
        public var enabled: Bool
        /// `call.isBlank()`.
        public var callBlank: Bool
        /// `phone || cw || digi` (`isKeyable`).
        public var keyable: Bool
        /// `state.isSending()` (voice or CW lamp lit).
        public var isSending: Bool
        /// `state.postContest`.
        public var postContest: Bool
        /// The TX interlock blocks transmitting (`txGate`; `false` until one is installed).
        public var txLocked: Bool
        /// `config.runMode.repeatSeconds`.
        public var repeatSeconds: Double

        public init(enabled: Bool, callBlank: Bool, keyable: Bool, isSending: Bool, postContest: Bool = false,
                    txLocked: Bool = false, repeatSeconds: Double) {
            self.enabled = enabled
            self.callBlank = callBlank
            self.keyable = keyable
            self.isSending = isSending
            self.postContest = postContest
            self.txLocked = txLocked
            self.repeatSeconds = repeatSeconds
        }
    }

    enum Phase: Equatable, Sendable {
        case waitBeforeSend
        case gap
        case waitAfterSend
    }

    private(set) var phase: Phase = .waitBeforeSend

    public init() {}

    /// `phone || cw || digi` (`EP:673-676`): SSB/AM/FM, CW, or a digital mode with fldigi configured.
    public static func isKeyable(mode: Mode, digitalReady: Bool) -> Bool {
        switch mode {
        case .ssb, .am, .fm, .cw: return true
        default: return mode.isDigital && digitalReady
        }
    }

    /// The effect gate: `cqRepeat && call blank && keyable`.
    public static func shouldRun(enabled: Bool, callBlank: Bool, keyable: Bool) -> Bool {
        enabled && callBlank && keyable
    }

    /// `(repeatSeconds * 1000).toLong()` (truncation, NaN → 0, saturating).
    public static func pauseMillis(_ seconds: Double) -> Int64 {
        JavaMath.d2l(seconds * 1000)
    }

    /// A key (`cqRepeat`, call blank, keyable) changed: the effect restarts from the top.
    public mutating func restart() {
        phase = .waitBeforeSend
    }

    /// The runner's F1 send (after `.sendF1`) failed: the loop stops instead of retrying after the pause.
    public mutating func sendFailed() -> Action {
        phase = .waitBeforeSend
        return .stop(.sendFailed)
    }

    /// The next step of the loop.
    public mutating func next(_ inputs: Inputs) -> Action {
        guard inputs.enabled, inputs.callBlank else {
            phase = .waitBeforeSend
            return .idle
        }
        guard inputs.keyable else {
            phase = .waitBeforeSend
            return .stop(.notKeyable)
        }
        switch phase {
        case .waitBeforeSend:
            if inputs.isSending {
                return .wait(milliseconds: Self.idlePollMillis)
            }
            if inputs.postContest {
                return .stop(.postContest)
            }
            if inputs.txLocked {
                return .stop(.txLockout)
            }
            phase = .gap
            return .sendF1
        case .gap:
            phase = .waitAfterSend
            return .wait(milliseconds: Self.afterSendMillis)
        case .waitAfterSend:
            if inputs.isSending {
                return .wait(milliseconds: Self.idlePollMillis)
            }
            phase = .waitBeforeSend
            return .wait(milliseconds: Self.pauseMillis(inputs.repeatSeconds))
        }
    }
}
