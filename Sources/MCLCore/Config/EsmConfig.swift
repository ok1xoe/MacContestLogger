import Foundation

/// ESM – Enter Sends Message (N1MM Config → ESM, Configurer → Function Keys).
public struct EsmConfig: Codable, Equatable, Sendable {
    /// ESM enabled: Enter transmits a message according to the entry window state.
    public var enabled: Bool = false
    /// „Big Gun": in S&P, Enter sends my callsign only once and the cursor goes to the exchange.
    public var spCallOnce: Bool = false
    /// In Run a dupe is worked as a new QSO (N1MM recommends enabled).
    public var workDupes: Bool = true
    /// N1MM „Next Call Key": the F-key (index from 0) ESM sends instead of TU while a call waits on the call stack —
    /// it should hold `{LOGTHENPOP}`; `-1` = none. Swift-only key.
    public var nextCallKey: Int = -1
    /// The order calls come off the call stack (`CallStack.Order` raw value). Swift-only key.
    public var callStackOrder: String = CallStack.Order.multsFirst.rawValue
    /// A band change drops the stacked calls (they called on the old run frequency). Swift-only key.
    public var callStackClearOnBandChange: Bool = true
    /// N1MM „Function Key Assignments for ESM": the keys of CQ, Exch, End of QSO, My call, His call, QSO B4 and Again
    /// (index from 0, `EsmKeyMap.keys` order). Swift-only key.
    public var keyMap: [Int] = EsmKeyMap.n1mm.keys {
        didSet {
            let normalized: [Int] = EsmKeyMap(keys: keyMap).keys
            if normalized != keyMap { keyMap = normalized }
        }
    }

    /// N1MM „Send partial calls": a corrected call is resent only in the part that changed. Swift-only key.
    public var sendPartialCalls: Bool = false
    /// N1MM „String between his call and exchange (CW)": what joins his call and the exchange sent together
    /// (F5+F2); a space by default. Swift-only key.
    public var callExchangeSeparator: String = " "

    /// The ESM key map.
    public var keys: EsmKeyMap {
        EsmKeyMap(keys: keyMap)
    }

    enum CodingKeys: String, CodingKey {
        case enabled, spCallOnce, workDupes, nextCallKey, callStackOrder, callStackClearOnBandChange, keyMap
        case sendPartialCalls, callExchangeSeparator
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EsmConfig()
        enabled = c.value(.enabled, default: d.enabled)
        spCallOnce = c.value(.spCallOnce, default: d.spCallOnce)
        workDupes = c.value(.workDupes, default: d.workDupes)
        let key: Int = c.value(.nextCallKey, default: d.nextCallKey)
        nextCallKey = (0..<VoiceKeyerConfig.keyCount).contains(key) ? key : -1
        callStackOrder = CallStack.Order.from(c.value(.callStackOrder, default: d.callStackOrder)).rawValue
        callStackClearOnBandChange = c.value(.callStackClearOnBandChange, default: d.callStackClearOnBandChange)
        keyMap = EsmKeyMap(keys: c.value(.keyMap, default: d.keyMap)).keys
        sendPartialCalls = c.value(.sendPartialCalls, default: d.sendPartialCalls)
        callExchangeSeparator = c.value(.callExchangeSeparator, default: d.callExchangeSeparator)
    }
}
