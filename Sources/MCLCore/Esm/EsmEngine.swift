/// ESM – Enter Sends Message (N1MM+ "ESM Mode Enter Key Actions", DXLog ESM).
/// Based on the contents of the entry window it decides which F-keys Enter transmits, whether
/// to log the QSO and where to move the cursor. A pure function: the same decision serves
/// also to highlight the keys that Enter will send. Mirrors the Java
/// `cz.ok1xoe.maccontestlogger.esm.EsmEngine`.
///
/// Table (keys F1 = CQ, F2 exchange, F3 TU, F4 my call, F5 his call,
/// F6 QSO B4, F8 again?):
///
///     call               exchange          Run                 S&P
///     empty              –                 F1                  F4
///     new (first time)   empty/invalid     F5+F2               F4 (Big Gun: F4, cursor to exchange)
///     new (again)        empty/invalid     F8                  F4 (Big Gun: F8)
///     new                valid, not sent   F5+F2               F2 + log
///     new                valid, sent       F3 + log            log
///     dupe               empty/invalid     F6 (Work dupes: as new)   nothing
///     dupe               valid             as new              as new
///
/// In Run a corrected call (changed after F5 was sent) is sent again before F3
/// ("Send corrected call").
public enum EsmEngine {

    /// F-key index (0 = F1). F7 is missing in Java.
    public static let f1 = 0
    public static let f2 = 1
    public static let f3 = 2
    public static let f4 = 3
    public static let f5 = 4
    public static let f6 = 5
    public static let f8 = 7

    /// Where to move the cursor after the step (Java `enum Focus`; `rawValue` = Java `name()`).
    public enum Focus: String, CaseIterable, Sendable {
        /// Leave where it is.
        case none = "NONE"
        /// To the call field.
        case call = "CALL"
        /// To the first exchange field.
        case exchange = "EXCHANGE"
    }

    /// State of the entry window (Java `record State`, component order preserved).
    public struct State: Hashable, Sendable {
        /// Run mode (otherwise S&P).
        public var run: Bool
        /// The call field is empty.
        public var callEmpty: Bool
        /// The call is a dupe.
        public var dupe: Bool
        /// The received exchange is complete and valid (the QSO can be logged).
        public var exchangeValid: Bool
        /// The exchange (F2) has already been sent for this QSO.
        public var exchangeSent: Bool
        /// My call (F4) has already been sent for this QSO.
        public var myCallSent: Bool
        /// The call changed after F5 was sent (Run).
        public var callCorrected: Bool

        public init(run: Bool, callEmpty: Bool, dupe: Bool, exchangeValid: Bool,
                    exchangeSent: Bool, myCallSent: Bool, callCorrected: Bool) {
            self.run = run
            self.callEmpty = callEmpty
            self.dupe = dupe
            self.exchangeValid = exchangeValid
            self.exchangeSent = exchangeSent
            self.myCallSent = myCallSent
            self.callCorrected = callCorrected
        }

        /// Number of distinct states (2⁷) — for exhaustive enumeration (`init(index:)`).
        public static let count = 128

        /// State from an index `0..<128`: bit `i` = the `i`-th component in Java
        /// order (bit 0 `run`, 1 `callEmpty`, 2 `dupe`, 3 `exchangeValid`, 4 `exchangeSent`,
        /// 5 `myCallSent`, 6 `callCorrected`).
        public init(index: Int) {
            precondition(index >= 0 && index < State.count, "index stavu ESM mimo 0..<128: \(index)")
            self.init(run: index & 1 != 0, callEmpty: index & 2 != 0, dupe: index & 4 != 0,
                      exchangeValid: index & 8 != 0, exchangeSent: index & 16 != 0,
                      myCallSent: index & 32 != 0, callCorrected: index & 64 != 0)
        }
    }

    /// ESM options (N1MM Configurer → Function Keys).
    public struct Options: Hashable, Sendable {
        /// "ESM sends your call once in S&P, then ready to copy exchange" (Big Gun).
        public var spCallOnce: Bool
        /// "Work dupes when running" — a dupe in Run is worked as a new QSO.
        public var workDupes: Bool

        public init(spCallOnce: Bool, workDupes: Bool) {
            self.spCallOnce = spCallOnce
            self.workDupes = workDupes
        }

        /// Options from the configuration (`EsmConfig.spCallOnce`, `workDupes`).
        public init(_ config: EsmConfig) {
            self.init(spCallOnce: config.spCallOnce, workDupes: config.workDupes)
        }

        /// Number of distinct options (2²) — for exhaustive enumeration (`init(index:)`).
        public static let count = 4

        /// Options from an index `0..<4`: bit 0 `spCallOnce`, bit 1 `workDupes`.
        public init(index: Int) {
            precondition(index >= 0 && index < Options.count, "index voleb ESM mimo 0..<4: \(index)")
            self.init(spCallOnce: index & 1 != 0, workDupes: index & 2 != 0)
        }
    }

    /// Decision for Enter.
    public struct Step: Hashable, Sendable {
        /// F-keys to transmit in order (0 = F1); empty = transmit nothing.
        public let keys: [Int]
        /// Log the QSO.
        public let log: Bool
        /// Where to move the cursor.
        public let focus: Focus

        public init(keys: [Int], log: Bool, focus: Focus) {
            self.keys = keys
            self.log = log
            self.focus = focus
        }

        static func send(_ focus: Focus, _ keys: Int...) -> Step {
            Step(keys: keys, log: false, focus: focus)
        }

        static func sendAndLog(_ keys: Int...) -> Step {
            Step(keys: keys, log: true, focus: .call)
        }

        /// Transmit and log nothing (S&P dupe).
        public var isNothing: Bool {
            keys.isEmpty && !log
        }
    }

    public static func decide(_ state: State, _ options: Options) -> Step {
        state.run ? run(state, options) : searchAndPounce(state, options)
    }

    private static func run(_ s: State, _ o: Options) -> Step {
        if s.callEmpty {
            return .send(.call, f1)
        }
        if s.exchangeValid {
            if !s.exchangeSent {
                return .send(.exchange, f5, f2)
            }
            return s.callCorrected ? .sendAndLog(f5, f3) : .sendAndLog(f3)
        }
        if s.dupe && !o.workDupes {
            return .send(.call, f6)
        }
        return s.exchangeSent ? .send(.exchange, f8) : .send(.exchange, f5, f2)
    }

    private static func searchAndPounce(_ s: State, _ o: Options) -> Step {
        if s.callEmpty {
            return .send(.call, f4)
        }
        if s.exchangeValid {
            return s.exchangeSent ? .sendAndLog() : .sendAndLog(f2)
        }
        if s.dupe {
            return Step(keys: [], log: false, focus: .none)
        }
        if o.spCallOnce {
            return s.myCallSent ? .send(.exchange, f8) : .send(.exchange, f4)
        }
        return .send(.call, f4)
    }
}
