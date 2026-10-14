/// The ESM flow of the entry window over `EsmEngine`/`EsmProgress` (`EP:168-176, 672-684, 816-861, 873-884, 983-989`
/// of v1.1.1). Pure decisions; the app sends the keys (`FunctionKeyRouter`), logs and moves the focus.
public enum EsmFlow {

    /// Kotlin `phone = SSB || AM || FM`.
    public static func isPhone(_ mode: Mode) -> Bool {
        mode == .ssb || mode == .am || mode == .fm
    }

    /// Kotlin `phone || cw || digi` (`digi = mode.isDigital && digitalReady`): the F-keys can transmit.
    public static func canTransmit(mode: Mode, digitalReady: Bool) -> Bool {
        isPhone(mode) || mode == .cw || (mode.isDigital && digitalReady)
    }

    /// Kotlin `esmActive` (`EP:679`): ESM on, a transmitting mode, not post-contest entry.
    public static func isActive(esmEnabled: Bool, mode: Mode, digitalReady: Bool, postContest: Bool) -> Bool {
        esmEnabled && canTransmit(mode: mode, digitalReady: digitalReady) && !postContest
    }

    /// Kotlin `exchangeValid` (`EP:678`): a complete exchange in a contest, a non-blank call outside one.
    public static func exchangeValid(contestActive: Bool, contestReady: Bool, call: String) -> Bool {
        contestActive ? contestReady : !KotlinStrings.isBlank(call)
    }

    /// The window state ESM decides on.
    public struct Input: Equatable, Sendable {
        public var progress: EsmProgress
        public var run: Bool
        public var call: String
        public var dupe: Bool
        public var exchangeValid: Bool
        public var options: EsmEngine.Options
        /// The Next Call key (N1MM Configurer → Function Keys → Next Call Key): set only while a call waits on the call
        /// stack and that key holds `{LOGTHENPOP}`; the end of a Run QSO then sends it instead of TU (F3), and the
        /// macro logs the QSO and starts the next one.
        public var nextCallKey: Int?
        /// The ESM key assignments.
        public var keyMap: EsmKeyMap

        public init(progress: EsmProgress, run: Bool, call: String, dupe: Bool, exchangeValid: Bool,
                    options: EsmEngine.Options, nextCallKey: Int? = nil, keyMap: EsmKeyMap = .n1mm) {
            self.nextCallKey = nextCallKey
            self.keyMap = keyMap
            self.progress = progress
            self.run = run
            self.call = call
            self.dupe = dupe
            self.exchangeValid = exchangeValid
            self.options = options
        }

        var step: EsmEngine.Step {
            let base: EsmEngine.Step = EsmEngine.decide(
                progress.state(run: run, call: call, dupe: dupe, exchangeValid: exchangeValid), options)
            let mapped = EsmEngine.Step(keys: keyMap.keys(base.keys), log: base.log, focus: base.focus)
            return EsmFlow.withNextCallKey(mapped, run: run, nextCallKey: nextCallKey, endKey: keyMap.end)
        }
    }

    /// N1MM ESM with call stacking: a Run step that ends the QSO with TU (F3) and logs sends the Next Call key in
    /// place of F3 and does not log itself (`{LOGTHENPOP}` in that key logs and moves on to the next call).
    public static func withNextCallKey(_ step: EsmEngine.Step, run: Bool, nextCallKey: Int?,
                                       endKey: Int = EsmEngine.f3) -> EsmEngine.Step {
        guard run, step.log, let key = nextCallKey, let last = step.keys.last, last == endKey else {
            return step
        }
        return EsmEngine.Step(keys: Array(step.keys.dropLast()) + [key], log: false, focus: .exchange)
    }

    /// Kotlin `esmStep` (`EP:680-684`): what the next Enter does — highlights the F-keys and "Log It"; `nil` when ESM
    /// is not active.
    public static func nextStep(_ input: Input, active: Bool) -> EsmEngine.Step? {
        active ? input.step : nil
    }

    /// What Enter in ESM does (`esmEnter`, `EP:817-835`).
    public struct Outcome: Equatable, Sendable {
        /// Set when nothing is sent (S&P dupe): `tr("DUPE — v S&P ESM nic nevysílá")`.
        public let status: EntryStatus?
        /// Keys to send first (`functionKeys(keys, refocus = false)`); empty = none.
        public let keys: [Int]
        /// Log the QSO afterwards (`logQso()`), which wipes and refocuses the call — the focus is then ignored.
        public let log: Bool
        /// Where the cursor goes when not logging.
        public let focus: EsmEngine.Focus
    }

    public static func enter(_ input: Input) -> Outcome {
        let step: EsmEngine.Step = input.step
        if step.isNothing {
            return Outcome(status: .tr("DUPE — v S&P ESM nic nevysílá"), keys: [], log: false, focus: .none)
        }
        return Outcome(status: nil, keys: step.keys, log: step.log, focus: step.focus)
    }

    /// Space in the call field (`jumpToExchange`, `EP:856-861`): with ESM on, phone, Run and a non-blank call the
    /// exchange counts as said live (the next Enter sends TU and logs, N2IC). The focus always goes to the exchange.
    /// Note: Kotlin checks `esmEnabled`, not `esmActive` (post-contest entry does not matter here).
    public static func jumpToExchange(_ progress: EsmProgress, esmEnabled: Bool, mode: Mode, run: Bool,
                                      call: String) -> EsmProgress {
        if esmEnabled && isPhone(mode) && run && !KotlinStrings.isBlank(call) {
            return progress.withExchangeSent()
        }
        return progress
    }

    /// Kotlin `LaunchedEffect(call.isBlank()) { if (call.isBlank()) esm = EMPTY }` (`EP:176`): the effect re-runs
    /// only when `call.isBlank()` changes, so the progress resets on the transition filled → blank (a cleared call
    /// starts a new QSO); edits that keep the call blank or non-blank leave it alone.
    public static func afterCallChange(_ progress: EsmProgress, previousCall: String, call: String) -> EsmProgress {
        let wasBlank: Bool = KotlinStrings.isBlank(previousCall)
        return KotlinStrings.isBlank(call) && !wasBlank ? .empty : progress
    }

    /// What `=` does (`EP:983-989`).
    public enum RepeatKey: Equatable, Sendable {
        /// ESM is not active: the key is not ESM's (it goes on to the field).
        case notEsm
        /// Consumed without sending (the release, or nothing was sent yet).
        case consume
        /// Consumed; resend these keys (`functionKeys(lastSentKeys, refocus = false)`).
        case send([Int])
    }

    /// `=` is consumed in both phases while ESM is active; on the press it resends the last sent keys.
    public static func repeatLast(esmActive: Bool, lastSentKeys: [Int], pressed: Bool) -> RepeatKey {
        guard esmActive else { return .notEsm }
        return pressed && !lastSentKeys.isEmpty ? .send(lastSentKeys) : .consume
    }

    /// The keys a send-and-log shortcut sends before it acts (`runShortcut`, `EP:875-884`); `nil` = send nothing.
    /// `SEND_CALL_EXCHANGE` sends F5+F2 when the mode transmits (and does not log); `TU_AND_LOG` sends F3 when the
    /// exchange is valid, then logs; `LOG_WITHOUT_SENDING` does the same only outside ESM.
    public static func shortcutKeys(_ action: ShortcutAction, canTransmit: Bool, esmActive: Bool,
                                    exchangeValid: Bool, keyMap: EsmKeyMap = .n1mm) -> [Int]? {
        switch action {
        case .sendCallExchange:
            return canTransmit ? [keyMap.hisCall, keyMap.exchange] : nil
        case .tuAndLog:
            return canTransmit && exchangeValid ? [keyMap.end] : nil
        case .logWithoutSending:
            return !esmActive && canTransmit && exchangeValid ? [keyMap.end] : nil
        default:
            return nil
        }
    }

    /// Enter on release (`EP:968-980`): a highlighted suggestion is taken first, then a call-field command (it beats
    /// ESM, otherwise "CW" would be sent as a call; Ctrl+Enter = split), then ESM, then plain logging.
    public enum EnterRoute: Equatable, Sendable {
        case takeSuggestion(Int)
        case command(ctrlEnter: Bool)
        case esm
        case log
    }

    public static func enterRoute(scpPick: Int, isCommand: Bool, ctrlEnter: Bool, esmActive: Bool) -> EnterRoute {
        if scpPick >= 0 {
            return .takeSuggestion(scpPick)
        }
        if isCommand {
            return .command(ctrlEnter: ctrlEnter)
        }
        return esmActive ? .esm : .log
    }
}
