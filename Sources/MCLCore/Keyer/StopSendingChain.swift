/// Esc in the entry window (`AppState.stopSending`, `AS:1757-1765`): tuning first (`setTune(false)`, the CQ repeat
/// stays as it is); otherwise the CQ repeat is switched off and `stopVoice() || abortDigital() || abortCw() ||
/// repeating` — short-circuit, so only the first active one is stopped.
public enum StopSendingChain {

    public struct Result: Equatable, Sendable {
        /// The return value of `stopSending` (`true` = Esc does not go on to clear the fields).
        public let stopped: Bool
        /// Call `setTune(false)`.
        public let stopTuning: Bool
        /// Set `cqRepeat = false`.
        public let clearCqRepeat: Bool
    }

    /// Runs the chain; the closures are called in Kotlin order and only as far as the first `true`.
    public static func run(tuning: Bool, cqRepeat: Bool, voice: () -> Bool, digital: () -> Bool,
                           cw: () -> Bool) -> Result {
        if tuning {
            return Result(stopped: true, stopTuning: true, clearCqRepeat: false)
        }
        let stopped = voice() || digital() || cw() || cqRepeat
        return Result(stopped: stopped, stopTuning: false, clearCqRepeat: true)
    }
}
