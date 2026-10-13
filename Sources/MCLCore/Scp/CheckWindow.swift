import Foundation

/// A pane of the Check window (N1MM: Log, master.scp, Telnet, Call History; the exchange pane of QSO parties and
/// Field Day; the reverse call history lookup results).
public enum CheckPane: String, CaseIterable, Sendable {
    case log
    case scp
    case telnet
    case callHistory
    case exchange
    case reverse

    /// The panes Alt+Y can take a call from (the exchange pane fills an exchange field instead).
    public static let callPanes: [CheckPane] = [.log, .scp, .telnet, .callHistory, .reverse]

    /// The Czech caption (translated by the UI).
    public var caption: String {
        switch self {
        case .log: return "Deník"
        case .scp: return "master.scp"
        case .telnet: return "Telnet"
        case .callHistory: return "Call history"
        case .exchange: return "Výměna"
        case .reverse: return "Zpětné hledání"
        }
    }
}

/// What the Check window's right-click menu sets (Swift-only keys of the root configuration).
public struct CheckSettings: Equatable, Sendable {
    /// Panes hidden with "Hide this pane" or unchecked.
    public var hidden: Set<CheckPane>
    /// "Proportional width this pane": the multiplier of a pane's width (1 = normal).
    public var weights: [CheckPane: Int]
    /// "Yank: configuration": the order Alt+Y goes through the panes.
    public var yankOrder: [CheckPane]
    /// "Yank: allow dupes".
    public var yankAllowsDupes: Bool
    /// "Sorting: Favor end-character differences".
    public var favorEnd: Bool
    /// A spotted call shows from this many spots (N1MM: 3).
    public var telnetMinSpots: Int
    /// Reverse call history lookup on.
    public var reverseEnabled: Bool
    /// "Set Reverse Lookup Threshold": characters of an exchange value before it is searched (N1MM default 2).
    public var reverseThreshold: Int
    /// Exchange values must match from their first character (off = anywhere in the value).
    public var reverseFromStart: Bool

    public init(hidden: Set<CheckPane> = [], weights: [CheckPane: Int] = [:],
                yankOrder: [CheckPane] = CheckSettings.defaultYankOrder, yankAllowsDupes: Bool = false,
                favorEnd: Bool = false, telnetMinSpots: Int = 3, reverseEnabled: Bool = true,
                reverseThreshold: Int = 2, reverseFromStart: Bool = true) {
        self.hidden = hidden
        self.weights = weights
        self.yankOrder = yankOrder
        self.yankAllowsDupes = yankAllowsDupes
        self.favorEnd = favorEnd
        self.telnetMinSpots = telnetMinSpots
        self.reverseEnabled = reverseEnabled
        self.reverseThreshold = reverseThreshold
        self.reverseFromStart = reverseFromStart
    }

    public static let defaultYankOrder: [CheckPane] = [.log, .scp, .telnet, .callHistory, .reverse]

    /// The settings of a configuration; unknown pane names are ignored, a yank order is completed with the panes it
    /// leaves out (in the default order), the numbers are clamped.
    public init(_ config: AppConfig) {
        hidden = Set(config.checkHiddenPanes.compactMap(CheckPane.init(rawValue:)))
        var weights: [CheckPane: Int] = [:]
        for (name, weight) in config.checkPaneWeights {
            if let pane = CheckPane(rawValue: name) {
                weights[pane] = Self.clampedWeight(weight)
            }
        }
        self.weights = weights
        yankOrder = Self.completedYankOrder(config.checkYankOrder.compactMap(CheckPane.init(rawValue:)))
        yankAllowsDupes = config.checkYankAllowDupes
        favorEnd = config.checkFavorEndDifferences
        telnetMinSpots = max(1, config.checkTelnetMinSpots)
        reverseEnabled = config.checkReverseEnabled
        reverseThreshold = max(1, config.checkReverseThreshold)
        reverseFromStart = config.checkReverseFromStart
    }

    /// Writes the settings back into a configuration.
    public func apply(to config: inout AppConfig) {
        config.checkHiddenPanes = CheckPane.allCases.filter { hidden.contains($0) }.map(\.rawValue)
        var names: [String: Int] = [:]
        for (pane, weight) in weights where weight != 1 {
            names[pane.rawValue] = Self.clampedWeight(weight)
        }
        config.checkPaneWeights = names
        config.checkYankOrder = yankOrder.map(\.rawValue)
        config.checkYankAllowDupes = yankAllowsDupes
        config.checkFavorEndDifferences = favorEnd
        config.checkTelnetMinSpots = max(1, telnetMinSpots)
        config.checkReverseEnabled = reverseEnabled
        config.checkReverseThreshold = max(1, reverseThreshold)
        config.checkReverseFromStart = reverseFromStart
    }

    public func weight(_ pane: CheckPane) -> Int {
        weights[pane] ?? 1
    }

    public static func clampedWeight(_ weight: Int) -> Int {
        min(10, max(1, weight))
    }

    /// The call panes in `order` (duplicates dropped) followed by those it leaves out.
    public static func completedYankOrder(_ order: [CheckPane]) -> [CheckPane] {
        var out: [CheckPane] = []
        for pane in order + defaultYankOrder where CheckPane.callPanes.contains(pane) && !out.contains(pane) {
            out.append(pane)
        }
        return out
    }

    /// Moves a pane one place earlier (`-1`) or later (`+1`) in the yank order.
    public mutating func moveInYankOrder(_ pane: CheckPane, by delta: Int) {
        guard let index = yankOrder.firstIndex(of: pane) else { return }
        let target: Int = index + delta
        guard yankOrder.indices.contains(target) else { return }
        yankOrder.swapAt(index, target)
    }
}

/// The reverse call history lookup (N1MM: "Search logged QSOs and Call History files for callsigns matching a partial
/// exchange"): the calls whose record has every entered exchange value — from the threshold's number of characters,
/// matching from the value's first character or anywhere in it, case-insensitive. A partly typed call narrows the
/// result to the calls containing it. Sorted, at most `limit` (N1MM: 100).
public enum CheckReverseLookup {

    /// A call and the exchange values it is known with (field id → value).
    public struct Record: Equatable, Sendable {
        public let call: String
        public let values: [String: String]

        public init(call: String, values: [String: String]) {
            self.call = call
            self.values = values
        }
    }

    public static let defaultLimit = 100

    /// The ids of the fields the lookup searches (not the report or the serial number).
    public static func searchedFields(_ fields: [ContestDefinition.ExchangeField]) -> Set<String> {
        Set(fields.filter { !CallHistory.isSkipped($0.type) }.compactMap(\.id))
    }

    /// - Parameter entered: field id → the value typed (blank values and those shorter than `threshold` are not
    ///   searched; with no value long enough there is no result).
    public static func search(entered: [String: String], records: [Record], partialCall: String,
                              threshold: Int, fromStart: Bool, limit: Int = defaultLimit) -> [String] {
        let wanted: [(id: String, value: String)] = entered.compactMap { id, raw in
            let value: String = raw.trimmingCharacters(in: .whitespaces).uppercased()
            return value.count >= max(1, threshold) ? (id, value) : nil
        }
        guard !wanted.isEmpty, limit > 0 else { return [] }
        let partial: String = CheckMatcher.normalized(partialCall)
        var calls: Set<String> = []
        for record in records {
            let call: String = CheckMatcher.normalized(record.call)
            guard !call.isEmpty, partial.isEmpty || call.contains(partial) else { continue }
            let all: Bool = wanted.allSatisfy { want in
                guard let have = record.values[want.id]?.trimmingCharacters(in: .whitespaces).uppercased(),
                      !have.isEmpty else { return false }
                return fromStart ? have.hasPrefix(want.value) : have.contains(want.value)
            }
            if all {
                calls.insert(call)
            }
        }
        return Array(calls.sorted().prefix(limit))
    }

    /// The records of a call history for the received fields (the columns that would prefill each field).
    public static func records(_ history: CallHistory, fields: [ContestDefinition.ExchangeField]) -> [Record] {
        let open: [ContestDefinition.ExchangeField] = fields.filter { !CallHistory.isSkipped($0.type) }
        var out: [Record] = []
        for (key, record) in history.byCall.entries {
            guard let call = key, let record else { continue }
            var values: [String: String] = [:]
            for field in open {
                guard let id = field.id else { continue }
                if let value = CallHistory.value(record, id: id, type: field.type, openFields: open.count) {
                    values[id] = value
                }
            }
            out.append(Record(call: call, values: values))
        }
        return out
    }

    /// The records of the log: each QSO's received exchange (without deleted QSOs and blank calls; a later QSO's
    /// value of the same call is another record, so either value finds the call).
    public static func records(_ session: ContestSession, qsos: [Qso]) -> [Record] {
        var out: [Record] = []
        for qso in qsos where !qso.deleted && !JavaText.isBlank(qso.call) {
            guard let received = try? session.receivedFromFlat(call: qso.call, exchangeRcvdFlat: qso.exchangeRcvd,
                                                               serialRcvd: qso.serialRcvd) else { continue }
            var values: [String: String] = [:]
            for (id, value) in received.entries {
                if let id, let value, id != "nr" {
                    values[id] = value
                }
            }
            if !values.isEmpty {
                out.append(Record(call: qso.call, values: values))
            }
        }
        return out
    }
}

/// The exchange pane (N1MM shows the expected exchange values of QSO parties and Field Day): the values of the
/// multiplier list behind the exchange field being typed that contain the typed text, those starting with it first.
public enum CheckExchange {

    public struct Value: Equatable, Sendable {
        public let key: String
        public let label: String?

        public init(key: String, label: String?) {
            self.key = key
            self.label = label
        }
    }

    /// The values of the enumerable multiplier sets fed from the field `fieldId` (`multipliers[].from`).
    public static func values(for fieldId: String, definition: ContestDefinition?,
                              registry: MultiplierSetRegistry?) -> [Value] {
        guard let definition, let registry else { return [] }
        var out: [Value] = []
        var seen: Set<String> = []
        for binding in definition.multipliers ?? [] {
            guard let binding, let from = binding.from, from.caseInsensitiveCompare(fieldId) == .orderedSame,
                  let set = try? registry.get(binding.set), set.enumerable else { continue }
            for value in set.values {
                guard let key = value.key, !key.isEmpty, seen.insert(key.uppercased()).inserted else { continue }
                out.append(Value(key: key, label: value.label))
            }
        }
        return out
    }

    /// The values matching the typed text (key or label), best first, at most `limit`; from one character.
    public static func matches(_ typed: String, values: [Value], limit: Int = 50) -> [Value] {
        let query: String = typed.trimmingCharacters(in: .whitespaces).uppercased()
        guard !query.isEmpty, limit > 0 else { return [] }
        var ranked: [(rank: Int, value: Value)] = []
        for value in values {
            let key: String = value.key.uppercased()
            let label: String = value.label?.uppercased() ?? ""
            let rank: Int
            if key == query {
                rank = 0
            } else if key.hasPrefix(query) {
                rank = 1
            } else if label.hasPrefix(query) {
                rank = 2
            } else if key.contains(query) || label.contains(query) {
                rank = 3
            } else {
                continue
            }
            ranked.append((rank, value))
        }
        ranked.sort { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            return left.value.key < right.value.key
        }
        return ranked.prefix(limit).map(\.value)
    }
}

/// Alt+Y (N1MM "yank"): each press takes the next call of the Check window's panes in the yank order, skipping
/// dupes unless allowed. The cycle continues while the call field still holds the call the last press put there;
/// any other text starts a new cycle from it.
public struct CheckYank: Equatable, Sendable {

    /// The text the cycle started from.
    public private(set) var query: String = ""
    /// The calls of the cycle, in order.
    public private(set) var calls: [String] = []
    /// The index of the call put in last; -1 = none yet.
    public private(set) var index: Int = -1

    public init() {}

    /// The calls Alt+Y goes through: the panes' calls in `order`, without duplicates, without the typed text itself
    /// and (unless `allowDupes`) without dupes.
    public static func candidates(panes: [CheckPane: [String]], order: [CheckPane], typed: String,
                                  allowDupes: Bool, isDupe: (String) -> Bool) -> [String] {
        let current: String = CheckMatcher.normalized(typed)
        var out: [String] = []
        var seen: Set<String> = [current]
        for pane in order {
            for call in panes[pane] ?? [] {
                let normalized: String = CheckMatcher.normalized(call)
                guard !normalized.isEmpty, !seen.contains(normalized) else { continue }
                if !allowDupes && isDupe(normalized) { continue }
                seen.insert(normalized)
                out.append(normalized)
            }
        }
        return out
    }

    /// Whether `typed` continues the running cycle (it is the call the last press put in).
    public func continues(_ typed: String) -> Bool {
        index >= 0 && calls.indices.contains(index) && CheckMatcher.normalized(typed) == calls[index]
    }

    /// The next call: the following one of the running cycle (wrapping round), or the first of `candidates` for a
    /// new one started from `typed`. `nil` = nothing to take.
    public mutating func next(typed: String, candidates: () -> [String]) -> String? {
        if continues(typed) {
            index = (index + 1) % calls.count
            return calls[index]
        }
        let fresh: [String] = candidates()
        query = CheckMatcher.normalized(typed)
        calls = fresh
        index = fresh.isEmpty ? -1 : 0
        return fresh.first
    }

    public mutating func reset() {
        self = CheckYank()
    }
}

extension CallHistory {

    /// The callsigns of the history (upper case, in file order).
    public var calls: [String] {
        byCall.keys.compactMap { $0 }
    }
}
