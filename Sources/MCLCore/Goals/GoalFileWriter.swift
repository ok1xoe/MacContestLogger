/// Writing a goal set in the shape of the N1MM `Edit Goals` dialog export — the header `Type=GOAL  SubType=` (two
/// spaces) and pairs `dhh goal` (Java `goals/GoalFileWriter`). The same shape is read by `GoalFileParser`.
/// Plus conversion to/from the form in the configuration (`AppConfig.goals`, keys as strings because of JSON).
public enum GoalFileWriter {

    static let header: String = "Type=GOAL  SubType="

    /// File lines; keys ascending numerically (`TreeMap<Integer, …>`).
    public static func format(_ goals: GoalSet) -> [String] {
        var lines: [String] = [header]
        for key in goals.entries.keys.sorted() {
            let value: Int32 = goals.entries[key] ?? 0
            lines.append(String(key) + " " + String(value))
        }
        return lines
    }

    /// The whole file content: lines joined by `System.lineSeparator()` (`\n` on macOS) and one at the end.
    public static func toText(_ goals: GoalSet) -> String {
        var text = ""
        for line in format(goals) {
            text += line
            text += "\n"
        }
        return text
    }

    /// Set from the stored form in the configuration. Key `Integer.valueOf(k.trim())` (Unicode digits, sign);
    /// a bad key is skipped. `nil` or an empty map → an empty set.
    ///
    /// Divergences (a deliberate divergence from Java v1.1.1):
    /// - **a `null` value**: Java crashes here with an NPE (`Map.copyOf`) — and with it the Rate window/goal editor. The Swift
    ///   `[String: Int]` has no `null`; the `AppConfig` decoder on `null` (or another value it cannot read as
    ///   `Int`) drops the **whole** `goals` map (`[:]` → default goal 50), the rest of the configuration stays;
    /// - **a value outside `int`** (Jackson would reject the whole `config.json`): the entry is skipped;
    /// - **two keys with the same number** (`"101"`, `"0101"`, `" 101"`): Java takes the last in JSON order,
    ///   the Swift dictionary carries no order — the last in key order by UTF-16 wins (deterministically).
    public static func fromConfigMap(_ stored: [String: Int]?) -> GoalSet {
        guard let stored, !stored.isEmpty else { return GoalSet.empty() }
        var byKey: [Int32: Int32] = [:]
        let ordered: [String] = stored.keys.sorted { JavaText.compare($0, $1) < 0 }
        for k in ordered {
            guard let key = JavaInteger.parseInt(JavaText.trim(k)),
                  let raw = stored[k], let value = Int32(exactly: raw)
            else { continue }
            byKey[key] = value
        }
        return GoalSet.of(byKey)
    }

    /// Form for storing in the configuration (`String.valueOf(key)` → value).
    public static func toConfigMap(_ goals: GoalSet) -> [String: Int] {
        var out: [String: Int] = [:]
        for (key, value) in goals.entries {
            out[String(key)] = Int(value)
        }
        return out
    }
}
