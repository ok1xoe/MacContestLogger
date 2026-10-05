/// Reading tables of the Java probes embedded in tests (`VoiceAudioMeasured`): TSV rows
/// `id<TAB>column…`, probe escaping (`esc` in `ProbeP6`/`ProbeVoiceAudio`) unpacked.
enum ProbeRows {

    /// Columns of rows with the given `id` (without it), escaping unpacked into a `String`.
    static func rows(_ table: String, _ id: String) -> [[String]] {
        rawRows(table, id).map { $0.map(unescape) }
    }

    /// Columns of rows with the given `id` verbatim (without unpacking).
    static func rawRows(_ table: String, _ id: String) -> [[String]] {
        var result: [[String]] = []
        for line in table.split(separator: "\n", omittingEmptySubsequences: false) {
            let cols: [Substring] = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.first.map(String.init) == id else { continue }
            result.append(cols.dropFirst().map(String.init))
        }
        return result
    }

    /// The inverse of the probe's `esc` by UTF-16 units: `\uXXXX`, `\t`, `\n`, `\r`, `\\`. A lone half
    /// of a surrogate pair stays a unit (for comparison with `[UInt16]`).
    static func unescapeUnits(_ text: String) -> [UInt16] {
        let units: [UInt16] = Array(text.utf16)
        var out: [UInt16] = []
        var i = 0
        while i < units.count {
            let unit = units[i]
            guard unit == 0x5C, i + 1 < units.count else {
                out.append(unit)
                i += 1
                continue
            }
            switch units[i + 1] {
            case 0x75: // u
                let hex = String(decoding: units[(i + 2)..<(i + 6)], as: UTF16.self)
                out.append(UInt16(hex, radix: 16)!)
                i += 6
            case 0x74: out.append(0x09); i += 2 // t
            case 0x6E: out.append(0x0A); i += 2 // n
            case 0x72: out.append(0x0D); i += 2 // r
            default: out.append(units[i + 1]); i += 2
            }
        }
        return out
    }

    /// The inverse of the probe's `esc` into a `String`.
    static func unescape(_ text: String) -> String {
        String(decoding: unescapeUnits(text), as: UTF16.self)
    }

    /// Java `List.toString()` of strings: `[a, b]`.
    static func javaList(_ items: [String]) -> String {
        "[" + items.joined(separator: ", ") + "]"
    }
}
