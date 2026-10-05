/// Callsign suggestions over the decoded text (Java `digital/RecentCalls`). Keeps them in order of first
/// occurrence and never reorders them — in a pileup they would otherwise shift under the cursor each round of polling
/// fldigi and a click would hit someone else's callsign. They vanish only when pushed out by new ones.
///
/// Equality is Java's (by UTF-16 units, not Swift canonical): `" A "`, `A`, `a` are three different ones;
/// empty and blank (Java `isBlank`) ones are ignored; `max ≤ 0` → the list is always empty (after adding the
/// oldest is removed, one item per addition).
public final class RecentCalls {

    private let max: Int32
    public private(set) var calls: [String] = []

    public init(max: Int32) {
        self.max = max
    }

    /// Adds a callsign if new; otherwise leaves its place alone.
    public func offer(_ call: String?) {
        guard let call, !JavaText.isBlank(call), !calls.contains(where: { JavaText.equals($0, call) }) else {
            return
        }
        calls.append(call)
        if calls.count > Int(max) {
            calls.removeFirst()
        }
    }

    public func clear() {
        calls.removeAll()
    }
}
