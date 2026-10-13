/// N1MM's Grab window of the Digital Interface: the last calls recognised in the received text, the one to grab
/// highlighted. LIFO (default) shows and grabs the newest first, FIFO the oldest. A call seen again keeps its place
/// (the list does not jump under the pointer); at most `cap` calls, the oldest falls out.
public struct GrabList: Sendable, Equatable {

    public static let cap = 10

    public enum Order: String, CaseIterable, Sendable {
        case lifo = "LIFO"
        case fifo = "FIFO"

        public static func from(_ raw: String) -> Order {
            Order(rawValue: raw) ?? .lifo
        }
    }

    /// Oldest first.
    public private(set) var calls: [String] = []
    /// The selected call (Grab, `{DELSEL}`); `nil` = the top of the list.
    public private(set) var selected: String?

    public init() {}

    /// The calls as shown, the top (grabbed next) first.
    public func shown(_ order: Order) -> [String] {
        order == .lifo ? calls.reversed() : calls
    }

    /// The highlighted call: the selected one, else the top.
    public func highlighted(_ order: Order) -> String? {
        if let selected, calls.contains(selected) {
            return selected
        }
        return shown(order).first
    }

    /// A call seen in the text; `true` = it is new in the list.
    @discardableResult
    public mutating func offer(_ call: String) -> Bool {
        let normalized: String = JavaText.toUpperCase(KotlinText.trim(call))
        guard !normalized.isEmpty, !calls.contains(normalized) else { return false }
        calls.append(normalized)
        if calls.count > Self.cap {
            calls.removeFirst(calls.count - Self.cap)
        }
        return true
    }

    public mutating func select(_ call: String?) {
        selected = call
    }

    /// Takes the highlighted call out of the list (Alt+G, `{GRAB}`, the Grab button).
    public mutating func grab(_ order: Order) -> String? {
        guard let call = highlighted(order) else { return nil }
        remove(call)
        return call
    }

    public mutating func remove(_ call: String) {
        let normalized: String = JavaText.toUpperCase(KotlinText.trim(call))
        calls.removeAll { $0 == normalized }
        if selected == normalized {
            selected = nil
        }
    }

    /// `{DELTOP}`.
    public mutating func removeTop(_ order: Order) {
        if let top = shown(order).first {
            remove(top)
        }
    }

    /// `{DELSEL}`.
    public mutating func removeSelected(_ order: Order) {
        if let call = highlighted(order) {
            remove(call)
        }
    }

    /// `{DELALL}`, CLR.
    public mutating func clear() {
        calls.removeAll()
        selected = nil
    }
}

/// N1MM's Insert key in the digital modes (also `;`): an empty call field takes the call from the Grab window, then
/// the keys by Run/S&P, ESM and the dupe state (N1MM „Insert Key Assignments").
public enum InsertKey {

    /// The F-keys to send (index from 0); empty = nothing (a dupe without ESM).
    public static func keys(run: Bool, esm: Bool, dupe: Bool, workDupes: Bool, exchangeValid: Bool) -> [Int] {
        let callAndExchange: [Int] = [EsmEngine.f5, EsmEngine.f2]
        guard esm else {
            return dupe ? [] : callAndExchange
        }
        if dupe {
            return workDupes ? callAndExchange : [EsmEngine.f6]
        }
        if run || exchangeValid {
            return callAndExchange
        }
        return [EsmEngine.f4]
    }
}
