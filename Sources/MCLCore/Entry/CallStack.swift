/// The call stack of the entry window (N1MM „Single Operator Call Stacking" and partner call stacking): calls heard
/// in a pileup waiting to be worked one after the other. One stack serves the operator's own entries (Ctrl+Alt+G,
/// `{SOCALLSTACK}`, `{STACKANOTHER}`, Alt+click in the Digital Interface) and the calls a partner sends over the
/// network. Pure value logic: the caller decides dupes and multiplier values (`Evaluation`) and the band.
///
/// - At most `cap` calls; the oldest falls out when a new one comes. A call already on the stack is not added again.
/// - Every entry remembers the band it was stacked on; with `clearOnBandChange` the calls of another band are dropped
///   (`prune`) — they called on the old run frequency.
/// - The order in which calls come off the stack is `Order`: FIFO, LIFO, or FIFO with multipliers first (more new
///   multipliers first, ties in FIFO order) — N1MM's „Enable using FIFO Mults First".
public struct CallStack: Sendable, Equatable {

    public static let cap = 10

    /// The order in which calls come off the stack (N1MM Digital Interface → Setup → Digital Call Stacking).
    public enum Order: String, Codable, CaseIterable, Sendable {
        /// First in, first out: the call stacked first is worked first.
        case fifo = "FIFO"
        /// Last in, first out: the call stacked last is worked first.
        case lifo = "LIFO"
        /// FIFO, but calls bringing more new multipliers first (N1MM's CW/SSB behaviour).
        case multsFirst = "FIFO_MULTS_FIRST"

        /// The configured value, `multsFirst` for anything unknown.
        public static func from(_ raw: String) -> Order {
            Order(rawValue: raw) ?? .multsFirst
        }
    }

    /// Who put the call on the stack.
    public enum Source: String, Sendable, Equatable {
        case own
        case partner
    }

    public struct Entry: Sendable, Equatable {
        public let call: String
        public let source: Source
        /// The band (ADIF name) the call was stacked on, `""` when unknown.
        public let band: String
        /// Insertion counter (FIFO order).
        let seq: Int
    }

    /// What the caller knows about a call now: a dupe is never stacked or popped; `newMults` orders `multsFirst`.
    public struct Evaluation: Sendable, Equatable {
        public let dupe: Bool
        public let newMults: Int

        public init(dupe: Bool, newMults: Int) {
            self.dupe = dupe
            self.newMults = newMults
        }

        public static let neutral = Evaluation(dupe: false, newMults: 0)
    }

    /// The outcome of a push.
    public enum PushResult: Sendable, Equatable {
        case added
        /// The call is already on the stack.
        case alreadyStacked
        /// The call is a dupe: not stacked.
        case dupe
        /// Nothing to stack.
        case blank
    }

    public private(set) var entries: [Entry] = []
    private var nextSeq: Int = 0

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    /// The normalised call (trimmed, upper case).
    public static func normalize(_ call: String) -> String {
        JavaText.toUpperCase(KotlinText.trim(call))
    }

    /// Puts a call on the stack (a dupe, a blank call and a call already there are refused).
    @discardableResult
    public mutating func push(_ call: String, source: Source = .own, band: String,
                              evaluation: Evaluation = .neutral) -> PushResult {
        let normalized: String = Self.normalize(call)
        if normalized.isEmpty {
            return .blank
        }
        if evaluation.dupe {
            return .dupe
        }
        if entries.contains(where: { JavaText.equals($0.call, normalized) }) {
            return .alreadyStacked
        }
        entries.append(Entry(call: normalized, source: source, band: band, seq: nextSeq))
        nextSeq += 1
        if entries.count > Self.cap {
            entries.removeFirst(entries.count - Self.cap)
        }
        return .added
    }

    /// The entries in the order they come off the stack. Dupes (worked since they were stacked) are left out.
    public func ordered(_ order: Order, evaluate: (String) -> Evaluation) -> [Entry] {
        var rated: [(entry: Entry, eval: Evaluation)] = entries.map { ($0, evaluate($0.call)) }
        rated.removeAll { $0.eval.dupe }
        switch order {
        case .fifo:
            return rated.map(\.entry)
        case .lifo:
            return rated.reversed().map(\.entry)
        case .multsFirst:
            // A stable sort: more new multipliers first, then the insertion order.
            rated.sort { lhs, rhs in
                if lhs.eval.newMults != rhs.eval.newMults {
                    return lhs.eval.newMults > rhs.eval.newMults
                }
                return lhs.entry.seq < rhs.entry.seq
            }
            return rated.map(\.entry)
        }
    }

    /// The call that comes off the stack next, `nil` for an empty stack.
    public func peek(_ order: Order, evaluate: (String) -> Evaluation) -> String? {
        ordered(order, evaluate: evaluate).first?.call
    }

    /// Takes the next call off the stack; dupes met on the way are dropped too.
    public mutating func pop(_ order: Order, evaluate: (String) -> Evaluation) -> String? {
        let live: [Entry] = ordered(order, evaluate: evaluate)
        let next: Entry? = live.first
        let kept: Set<Int> = Set(live.dropFirst().map(\.seq))
        entries.removeAll { !kept.contains($0.seq) }
        return next?.call
    }

    /// Removes a call (it was logged, or the operator deleted it); `true` = it was there.
    @discardableResult
    public mutating func remove(_ call: String) -> Bool {
        let normalized: String = Self.normalize(call)
        let before: Int = entries.count
        entries.removeAll { JavaText.equals($0.call, normalized) }
        return entries.count != before
    }

    /// Alt+D: deletes the call that would come off next; returns it.
    @discardableResult
    public mutating func removeTop(_ order: Order, evaluate: (String) -> Evaluation) -> String? {
        guard let top = peek(order, evaluate: evaluate) else { return nil }
        remove(top)
        return top
    }

    public mutating func clear() {
        entries.removeAll()
    }

    /// Drops the calls stacked on a band other than `band` (a band change: they called on the old run frequency);
    /// `true` = something was dropped. An unknown band (`""`) drops nothing.
    @discardableResult
    public mutating func prune(band: String) -> Bool {
        guard !band.isEmpty else { return false }
        let before: Int = entries.count
        entries.removeAll { !$0.band.isEmpty && $0.band != band }
        return entries.count != before
    }
}

/// The stack macros of a message (N1MM): `{LOGTHENPOP}` / `{LOGTHENNEXT}` log the QSO and continue with the next
/// call from the stack, `{SOCALLSTACK}` exchanges the call field with the stack, `{STACKANOTHER}` pushes the call
/// field, `{CLRSTACK}` clears the stack.
public enum CallStackMacro {

    public static let logThenPop = "{LOGTHENPOP}"
    public static let logThenNext = "{LOGTHENNEXT}"
    /// `{LOGTHENGRAB}`: the same, with the next call from the Digital Interface's Grab window.
    public static let logThenGrab = "{LOGTHENGRAB}"
    public static let soCallStack = "{SOCALLSTACK}"
    public static let stackAnother = "{STACKANOTHER}"
    public static let clearStack = "{CLRSTACK}"

    /// The macros an SSB message performs before it is played (`VoiceMessagePlanner` skips them).
    public static let handledBeforeVoice: Set<String> = [logThenPop, logThenNext, soCallStack, stackAnother, clearStack]

    /// The Grab window macros (digital): `{GRAB}`, `{DELALL}`, `{DELTOP}`, `{DELSEL}`, `{SCQ}`.
    public static let grab = "{GRAB}"

    /// The stack macros of a voice message, in order (comma-separated items, ASCII case-insensitive).
    public static func voiceMacros(_ text: String) -> [String] {
        JavaText.split(text, unit: 0x2C).map { JavaText.toUpperCase(JavaText.trim($0)) }
            .filter { handledBeforeVoice.contains($0) }
    }

    /// A message split at its first `{LOGTHENPOP}` / `{LOGTHENNEXT}` (ASCII case-insensitive): the text sent to the
    /// station being logged, and the text sent after the next call came off the stack.
    public struct Split: Equatable, Sendable {
        public let prefix: String
        public let suffix: String
        /// `{LOGTHENNEXT}`: the same, but ESM never picks the key on its own.
        public let next: Bool
        /// `{LOGTHENGRAB}`: the next call comes from the Grab window.
        public var grab: Bool = false
    }

    /// `nil` when the text has neither macro.
    public static func split(_ text: String) -> Split? {
        let upper: String = JavaText.toUpperCase(text)
        let units: [UInt16] = Array(upper.utf16)
        var best: (index: Int, length: Int, next: Bool, grab: Bool)?
        for (macro, next, grab) in [(logThenPop, false, false), (logThenNext, true, false), (logThenGrab, true, true)] {
            let index: Int = JavaText.indexOf(units, Array(macro.utf16))
            if index >= 0, best == nil || index < best!.index {
                best = (index, macro.utf16.count, next, grab)
            }
        }
        guard let best else { return nil }
        let all: [UInt16] = Array(text.utf16)
        let prefix: String = String(decoding: all[0..<best.index], as: UTF16.self)
        let suffix: String = String(decoding: all[(best.index + best.length)...], as: UTF16.self)
        return Split(prefix: prefix, suffix: suffix, next: best.next, grab: best.grab)
    }

    /// The text holds `{LOGTHENPOP}` (the key ESM may send as the Next Call key; `{LOGTHENNEXT}` does not count).
    public static func hasLogThenPop(_ text: String) -> Bool {
        JavaText.toUpperCase(text).contains(logThenPop)
    }

    /// The F-keys a text refers to with `{F1}`…`{F12}` (index from 0), in order — the ESM progress of the next QSO
    /// after `{LOGTHENPOP} TU {F5}{F2}`.
    public static func functionKeys(in text: String) -> [Int] {
        var keys: [Int] = []
        let units: [UInt16] = Array(JavaText.toUpperCase(text).utf16)
        var index = 0
        while index < units.count {
            guard units[index] == 0x7B, index + 3 < units.count, units[index + 1] == 0x46 else {
                index += 1
                continue
            }
            var end: Int = index + 2
            var number = 0
            while end < units.count, units[end] >= 0x30, units[end] <= 0x39, end - index < 5 {
                number = number * 10 + Int(units[end] - 0x30)
                end += 1
            }
            if end < units.count, units[end] == 0x7D, end > index + 2, (1...12).contains(number) {
                keys.append(number - 1)
                index = end + 1
            } else {
                index += 1
            }
        }
        return keys
    }
}
