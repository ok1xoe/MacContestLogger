/// N1MM Configurer → Function Keys → „Function Key Assignments for ESM": which F-key plays each ESM role. `EsmEngine`
/// decides by role (its `f1`…`f8` are the roles); the map turns them into the keys sent. The default is N1MM's: F1 CQ,
/// F2 exchange, F3 end of QSO (TU), F4 my call, F5 his call, F6 QSO B4, F8 again.
public struct EsmKeyMap: Equatable, Sendable {
    public var cq: Int
    public var exchange: Int
    public var end: Int
    public var myCall: Int
    public var hisCall: Int
    public var qsoB4: Int
    public var again: Int

    public init(cq: Int, exchange: Int, end: Int, myCall: Int, hisCall: Int, qsoB4: Int, again: Int) {
        self.cq = cq
        self.exchange = exchange
        self.end = end
        self.myCall = myCall
        self.hisCall = hisCall
        self.qsoB4 = qsoB4
        self.again = again
    }

    public static let n1mm = EsmKeyMap(cq: EsmEngine.f1, exchange: EsmEngine.f2, end: EsmEngine.f3,
                                       myCall: EsmEngine.f4, hisCall: EsmEngine.f5, qsoB4: EsmEngine.f6,
                                       again: EsmEngine.f8)

    /// The keys in the order of `roles` (as stored: CQ, Exch, End, My call, His call, QSO B4, Again).
    public var keys: [Int] {
        [cq, exchange, end, myCall, hisCall, qsoB4, again]
    }

    /// The stored list (7 keys, index from 0); a missing or out-of-range entry keeps N1MM's key.
    public init(keys: [Int]) {
        let d: [Int] = Self.n1mm.keys
        func at(_ i: Int) -> Int {
            i < keys.count && (0..<VoiceKeyerConfig.keyCount).contains(keys[i]) ? keys[i] : d[i]
        }
        self.init(cq: at(0), exchange: at(1), end: at(2), myCall: at(3), hisCall: at(4), qsoB4: at(5), again: at(6))
    }

    /// The key of an `EsmEngine` role (`EsmEngine.f1`…); another index stays as it is.
    public func key(_ role: Int) -> Int {
        switch role {
        case EsmEngine.f1: return cq
        case EsmEngine.f2: return exchange
        case EsmEngine.f3: return end
        case EsmEngine.f4: return myCall
        case EsmEngine.f5: return hisCall
        case EsmEngine.f6: return qsoB4
        case EsmEngine.f8: return again
        default: return role
        }
    }

    public func keys(_ roles: [Int]) -> [Int] {
        roles.map(key)
    }
}
