extension JavaText {

    /// Java `text.replace(target, replacement)` (`CharSequence`): all occurrences from the left, without
    /// overlap, compared by **UTF-16 units** (Swift's `replacingOccurrences` compares
    /// canonically and by grapheme — `!` + U+0301 would not match `!` in it). An empty `target` inserts
    /// the replacement before every unit and at the end (`"ab"` → `"-a-b-"`).
    static func replace(_ text: String, _ target: String, _ replacement: String) -> String {
        let units = Array(text.utf16)
        let needle = Array(target.utf16)
        let insert = Array(replacement.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        if needle.isEmpty {
            for unit in units {
                out.append(contentsOf: insert)
                out.append(unit)
            }
            out.append(contentsOf: insert)
            return String(decoding: out, as: UTF16.self)
        }
        var index = 0
        var found = false
        while index < units.count {
            let next = indexOf(units, needle, from: index)
            if next < 0 { break }
            found = true
            out.append(contentsOf: units[index..<next])
            out.append(contentsOf: insert)
            index = next + needle.count
        }
        if !found { return text }
        out.append(contentsOf: units[index...])
        return String(decoding: out, as: UTF16.self)
    }

    /// Java `text.split(String.valueOf(c))` for a single character that is not a regex metacharacter (the fast
    /// path of `String.split`): splits by UTF-16 units and **drops empty strings at the end**
    /// (`",a,,"` → `["", "a"]`, `""` → `[""]`, `","` → `[]`).
    static func split(_ text: String, unit separator: UInt16) -> [String] {
        if text.isEmpty { return [""] }
        var parts: [String] = []
        var current: [UInt16] = []
        for unit in text.utf16 {
            if unit == separator {
                parts.append(String(decoding: current, as: UTF16.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(unit)
            }
        }
        parts.append(String(decoding: current, as: UTF16.self))
        while let last = parts.last, last.isEmpty {
            parts.removeLast()
        }
        return parts
    }
}
