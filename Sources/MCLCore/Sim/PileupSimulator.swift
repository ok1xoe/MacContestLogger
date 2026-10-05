import Foundation

/// Pileup simulator (Java `sim/PileupSimulator`, like Morse Runner in DXLog): callers answer a CQ, on their
/// callsign they reply with the exchange "5NN number", on "?"/"AGN" they repeat, on a callsign part with a question mark
/// those that match it answer, and on a wrongly sent callsign they correct it. A logged QSO is compared with what the
/// station actually sent.
///
/// Pure logic without sound and time — sound and delays are handled by the caller according to `Transmission`. Deterministic with respect to the
/// sequence of `PileupRandom` calls in the same order as Java (`poisson`, fallback arrival, `wpm`, tone shift,
/// serial number, patience, reply delays in listing order). Java `int` is `Int32` with wraparound
/// (`2 * spread + 1` overflows the same). Text: `toUpperCase(Locale.ROOT)`, `trim()`, `split("\\s+")` and equality by
/// UTF-16 units like Java. A `final class` without `Sendable` — owned by the main thread.
public final class PileupSimulator {

    /// Simulation settings (Java `record Settings` including clamping in the compact constructor).
    public struct Settings: Equatable, Sendable {
        /// Average number of callers per CQ (1–6).
        public let activity: Int32
        /// Lowest speed of the callers (at least 10).
        public let minWpm: Int32
        /// Highest speed of the callers (at least `minWpm`).
        public let maxWpm: Int32
        /// Spread of the callers' tones around the CW pitch (±, at least 0).
        public let pitchSpreadHz: Int32

        public init(activity: Int32, minWpm: Int32, maxWpm: Int32, pitchSpreadHz: Int32) {
            self.activity = Swift.max(1, Swift.min(6, activity))
            let low: Int32 = Swift.max(10, minWpm)
            self.minWpm = low
            self.maxWpm = Swift.max(low, maxWpm)
            self.pitchSpreadHz = Swift.max(0, pitchSpreadHz)
        }
    }

    /// Calling station: callsign, its serial number, speed, tone shift and patience (how many CQs it endures).
    public struct Caller: Equatable, Sendable {
        public let call: String
        public let serial: Int32
        public let wpm: Int32
        public let pitchOffsetHz: Int32
        public let patience: Int32

        public init(call: String, serial: Int32, wpm: Int32, pitchOffsetHz: Int32, patience: Int32) {
            self.call = call
            self.serial = serial
            self.wpm = wpm
            self.pitchOffsetHz = pitchOffsetHz
            self.patience = patience
        }

        func withPatience(_ p: Int32) -> Caller {
            Caller(call: call, serial: serial, wpm: wpm, pitchOffsetHz: pitchOffsetHz, patience: p)
        }

        public var exchange: String {
            "5NN " + String(serial)
        }

        /// Java record equality (`String.equals` by UTF-16 units).
        public static func == (lhs: Caller, rhs: Caller) -> Bool {
            JavaText.equals(lhs.call, rhs.call) && lhs.serial == rhs.serial && lhs.wpm == rhs.wpm
                && lhs.pitchOffsetHz == rhs.pitchOffsetHz && lhs.patience == rhs.patience
        }
    }

    /// What the station transmits and how many ms after the end of my message.
    public struct Transmission: Equatable, Sendable {
        public let from: Caller
        public let text: String
        public let delayMs: Int64

        public init(from: Caller, text: String, delayMs: Int64) {
            self.from = from
            self.text = text
            self.delayMs = delayMs
        }

        /// Java record equality (texts by UTF-16 units).
        public static func == (lhs: Transmission, rhs: Transmission) -> Bool {
            lhs.from == rhs.from && JavaText.equals(lhs.text, rhs.text) && lhs.delayMs == rhs.delayMs
        }
    }

    /// Result of checking a logged QSO.
    public struct Check: Equatable, Sendable {
        public let loggedCall: String
        public let expectedCall: String
        public let callOk: Bool
        public let exchangeOk: Bool
        public let expectedExchange: String

        public init(loggedCall: String, expectedCall: String, callOk: Bool, exchangeOk: Bool,
                    expectedExchange: String) {
            self.loggedCall = loggedCall
            self.expectedCall = expectedCall
            self.callOk = callOk
            self.exchangeOk = exchangeOk
            self.expectedExchange = expectedExchange
        }

        public var ok: Bool {
            callOk && exchangeOk
        }

        /// Java record equality (texts by UTF-16 units).
        public static func == (lhs: Check, rhs: Check) -> Bool {
            let calls: Bool = JavaText.equals(lhs.loggedCall, rhs.loggedCall)
                && JavaText.equals(lhs.expectedCall, rhs.expectedCall)
            return calls && lhs.callOk == rhs.callOk && lhs.exchangeOk == rhs.exchangeOk
                && JavaText.equals(lhs.expectedExchange, rhs.expectedExchange)
        }
    }

    private static let whitespace: JavaRegex = {
        do {
            return try JavaRegex("\\s+")
        } catch {
            preconditionFailure("pevný vzor musí jít zkompilovat: \(error)")
        }
    }()

    private let settings: Settings
    private let callSource: () -> String?
    private let random: any PileupRandom
    private var list: [Caller] = []
    /// Station currently being worked.
    public private(set) var current: Caller?
    private var lastWorked: Caller?
    public private(set) var qsos: Int32 = 0
    public private(set) var errors: Int32 = 0

    /// - Parameters:
    ///   - callSource: callsign source (`Supplier<String>`; `nil` or an empty callsign is skipped)
    ///   - random: randomness source (in production `SystemPileupRandom`; may be shared with the callsign source)
    public init(settings: Settings, callSource: @escaping () -> String?, random: any PileupRandom) {
        self.settings = settings
        self.callSource = callSource
        self.random = random
    }

    /// Waiting callers (a copy).
    public var callers: [Caller] {
        list
    }

    /// The operator transmitted `text`; returns the stations' replies.
    ///
    /// Throws like Java `IllegalArgumentException("bound must be positive")` when `2 * pitchSpreadHz + 1`
    /// overflows `int` (spread ≥ 2^30 Hz) and a new caller arrives — the state (patience, callers added before
    /// the error, finished QSO) stays changed as in Java. The UI should call `try?`.
    public func onSent(_ text: String?) throws(JavaIllegalArgumentError) -> [Transmission] {
        let t: String = text.map { JavaText.trim(JavaText.toUpperCase($0)) } ?? ""
        let words: [String] = JavaText.split(t, regex: Self.whitespace, limit: 0)
        var out: [Transmission] = []

        // A caller's callsign exactly → QSO with it, sends the exchange.
        for (index, c) in list.enumerated() where Self.contains(words, c.call) {
            current = c
            list.remove(at: index)
            out.append(Transmission(from: c, text: c.exchange, delayMs: try replyDelay()))
            return out
        }
        if let cur = current, Self.contains(words, cur.call), !Self.isEndOfQso(words) {
            out.append(Transmission(from: cur, text: cur.exchange, delayMs: try replyDelay()))
            return out
        }
        let question: Bool = words.contains { w in
            JavaText.equals(w, "?") || JavaText.equals(w, "AGN") || JavaText.equals(w, "NR?")
                || JavaText.equals(w, "CALL?")
        }
        if let cur = current, question {
            out.append(Transmission(from: cur, text: cur.exchange, delayMs: try replyDelay()))
            return out
        }
        if Self.isEndOfQso(words) {
            if current != nil {
                lastWorked = current
                current = nil
            }
            try refillCallers()
            for c in list {
                out.append(Transmission(from: c, text: c.call, delayMs: try replyDelay()))
            }
            return out
        }
        // A callsign part with a question mark ("OK1?"), or a callsign with one error → the matching ones answer.
        for w in words {
            let partial: String = JavaText.replace(w, "?", "")
            if partial.utf16.count < 2 {
                continue
            }
            let asked: Bool = w.utf16.last == 0x3F
            for c in list {
                if asked && JavaText.indexOf(Array(c.call.utf16), Array(partial.utf16)) >= 0 {
                    let reply: String = c.call + " " + c.call
                    out.append(Transmission(from: c, text: reply, delayMs: try replyDelay()))
                } else if !asked && Self.editDistance(partial, c.call) == 1 {
                    let reply: String = "DE " + c.call + " " + c.call
                    out.append(Transmission(from: c, text: reply, delayMs: try replyDelay()))
                }
            }
        }
        if out.isEmpty && question {
            for c in list {
                out.append(Transmission(from: c, text: c.call, delayMs: try replyDelay()))
            }
        }
        return out
    }

    /// Compares the logged QSO with the station just worked.
    public func onLogged(call: String?, exchange: String?) -> Check {
        let worked: Caller? = current ?? lastWorked
        if current != nil {
            lastWorked = current
            current = nil
        }
        let logged: String = call.map { JavaText.trim(JavaText.toUpperCase($0)) } ?? ""
        qsos &+= 1
        guard let worked else {
            errors &+= 1
            return Check(loggedCall: logged, expectedCall: "", callOk: false, exchangeOk: false, expectedExchange: "")
        }
        let callOk: Bool = JavaText.equals(worked.call, logged)
        let digits: String = exchange.map { JavaText.trim(Self.digitsOnly($0)) } ?? ""
        let parts: [String] = JavaText.split(digits, regex: Self.whitespace, limit: 0)
        let exchOk: Bool = Self.contains(parts, String(worked.serial))
        if !callOk || !exchOk {
            errors &+= 1
        }
        lastWorked = nil
        return Check(loggedCall: logged, expectedCall: worked.call, callOk: callOk, exchangeOk: exchOk,
                     expectedExchange: worked.exchange)
    }

    /// `replaceAll("[^0-9]", " ")`: every code point outside ASCII digits → one space.
    private static func digitsOnly(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            out.append(("0"..."9").contains(scalar) ? scalar : " ")
        }
        return String(out)
    }

    /// `List.contains` of strings (Java `equals`).
    private static func contains(_ words: [String], _ word: String) -> Bool {
        words.contains { JavaText.equals($0, word) }
    }

    private static func isEndOfQso(_ words: [String]) -> Bool {
        contains(words, "CQ") || contains(words, "TU") || contains(words, "QRZ") || contains(words, "QRZ?")
            || contains(words, "TEST")
    }

    /// Java `nextInt(bound)` including the bound check (the exception before any randomness is consumed).
    private func nextInt(_ bound: Int32) throws(JavaIllegalArgumentError) -> Int32 {
        guard bound > 0 else {
            throw JavaIllegalArgumentError(message: "bound must be positive")
        }
        return random.nextInt(bound: bound)
    }

    /// The impatient leave, new ones arrive (Poisson around the activity), at most 8 at a time.
    private func refillCallers() throws(JavaIllegalArgumentError) {
        list = list.map { $0.withPatience($0.patience &- 1) }
        list.removeAll { $0.patience <= 0 }
        let lambda: Double = Double(settings.activity) / 2.0 + 0.5
        var arrivals: Int32 = poisson(lambda)
        if list.isEmpty && arrivals == 0 {
            arrivals = random.nextDouble() < 0.7 ? 1 : 0
        }
        var i: Int32 = 0
        while i < arrivals && list.count < 8 {
            defer { i &+= 1 }
            guard let call = callSource(), !JavaText.isBlank(call),
                  !list.contains(where: { JavaText.equals($0.call, call) }) else {
                continue
            }
            let span: Int32 = settings.maxWpm &- settings.minWpm &+ 1
            let wpm: Int32 = settings.minWpm &+ (try nextInt(span))
            let spread: Int32 = settings.pitchSpreadHz
            let offset: Int32 = spread == 0 ? 0 : (try nextInt(2 &* spread &+ 1)) &- spread
            let upper: String = JavaText.toUpperCase(call)
            let serial: Int32 = 1 &+ (try nextInt(1500))
            let patience: Int32 = 2 &+ (try nextInt(4))
            list.append(Caller(call: upper, serial: serial, wpm: wpm, pitchOffsetHz: offset, patience: patience))
        }
    }

    /// Knuth's method; `Math.exp(-λ)` for λ ∈ {1; 1.5; …; 3.5} is bitwise identical in HotSpot and Darwin libm
    /// (measured, `SimMeasuredTests`).
    private func poisson(_ lambda: Double) -> Int32 {
        let l: Double = exp(-lambda)
        var p = 1.0
        var k: Int32 = 0
        repeat {
            k &+= 1
            p *= random.nextDouble()
        } while p > l
        return k &- 1
    }

    private func replyDelay() throws(JavaIllegalArgumentError) -> Int64 {
        150 + Int64(try nextInt(900))
    }

    /// Levenshtein distance by UTF-16 units (Java `charAt`).
    static func editDistance(_ a: String, _ b: String) -> Int32 {
        let x: [UInt16] = Array(a.utf16)
        let y: [UInt16] = Array(b.utf16)
        var prev: [Int32] = (0...y.count).map { Int32($0) }
        var cur = [Int32](repeating: 0, count: y.count + 1)
        if !x.isEmpty {
            for i in 1...x.count {
                cur[0] = Int32(i)
                if !y.isEmpty {
                    for j in 1...y.count {
                        let cost: Int32 = x[i - 1] == y[j - 1] ? 0 : 1
                        let insert: Int32 = cur[j - 1] + 1
                        let delete: Int32 = prev[j] + 1
                        cur[j] = Swift.min(Swift.min(insert, delete), prev[j - 1] + cost)
                    }
                }
                swap(&prev, &cur)
            }
        }
        return prev[y.count]
    }

    private static let prefixes: [String] = [
        "OK", "OL", "OM", "DL", "DK", "SP", "HA", "S5", "9A", "G", "F", "I", "EA", "K", "W", "N", "VE", "JA", "UA",
        "LY", "YL", "ES", "OH", "SM", "LA", "PA", "ON", "OE", "HB9", "YO", "LZ",
    ]

    /// Callsign source: from a database (`master.scp`), otherwise made-up callsigns of the form prefix + digit + 1–3 letters
    /// (without `master.scp` they are not real). An empty or missing `pool` = made-up.
    public static func callSource(pool: [String]?, random: any PileupRandom) -> () -> String? {
        if let pool, !pool.isEmpty {
            return callSource(count: pool.count, element: { pool[$0] }, random: random)
        }
        return {
            var sb: String = prefixes[Int(random.nextInt(bound: Int32(prefixes.count)))]
            sb += String(random.nextInt(bound: 10))
            let n: Int32 = 1 + random.nextInt(bound: 3)
            var letters = String.UnicodeScalarView()
            for _ in 0..<n {
                let code: UInt32 = 0x41 + UInt32(random.nextInt(bound: 26))
                letters.append(Unicode.Scalar(code) ?? "A")
            }
            return sb + String(letters)
        }
    }

    /// Callsign source over the SCP database without copying (Kotlin wraps it in an `AbstractList`); empty = made-up.
    public static func callSource(scp: ScpDatabase, random: any PileupRandom) -> () -> String? {
        let size: Int = scp.size
        if size == 0 {
            return callSource(pool: nil, random: random)
        }
        return callSource(count: size, element: { scp.get($0) }, random: random)
    }

    private static func callSource(count: Int, element: @escaping (Int) -> String,
                                   random: any PileupRandom) -> () -> String? {
        let bound = Int32(truncatingIfNeeded: count)
        return { element(Int(random.nextInt(bound: bound))) }
    }
}
