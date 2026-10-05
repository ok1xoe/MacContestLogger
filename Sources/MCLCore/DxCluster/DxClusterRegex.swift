/// Fixed Java patterns of the `dxcluster/` package (DX spots, WWV, skimmer, modes, grid).
enum DxClusterRegex {

    /// Java `Pattern.compile(pattern)` over a source literal — an error is a program defect.
    static func compile(_ pattern: String) -> JavaRegex {
        do {
            return try JavaRegex(pattern)
        } catch {
            preconditionFailure("pevný vzor dxcluster musí jít zkompilovat: \(error)")
        }
    }

    /// Java `String.endsWith(suffix)` by UTF-16 units (Swift `hasSuffix` goes by graphemes).
    static func endsWith(_ text: String, _ suffix: String) -> Bool {
        let units: [UInt16] = Array(text.utf16)
        let tail: [UInt16] = Array(suffix.utf16)
        guard units.count >= tail.count else { return false }
        return Array(units[(units.count - tail.count)...]) == tail
    }

    /// Java `String.startsWith(prefix)` by UTF-16 units.
    static func startsWith(_ text: String, _ prefix: String) -> Bool {
        let units: [UInt16] = Array(text.utf16)
        let head: [UInt16] = Array(prefix.utf16)
        guard units.count >= head.count else { return false }
        return Array(units[..<head.count]) == head
    }
}
