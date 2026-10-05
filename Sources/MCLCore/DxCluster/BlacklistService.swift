/// Operations on the blacklist (`BlacklistEntry`) — Java `dxcluster.BlacklistService`. Dedup is case-insensitive
/// (Java `equalsIgnoreCase`) by value; values are normalized with Java `trim()`
/// and uppercasing. Stateless — works on the passed list (the Java `List` is modified in place, here `inout`).
public enum BlacklistService {

    /// Adds the value if it is not already in the list; returns `true` on an actual change.
    @discardableResult
    public static func add(_ list: inout [BlacklistEntry], _ value: String?, note: String?, nowUtc: String?) -> Bool {
        let v = norm(value)
        if v.isEmpty || find(list, v) != nil {
            return false
        }
        list.append(BlacklistEntry(value: v, addedAtUtc: nowUtc ?? "", note: note ?? ""))
        return true
    }

    /// Removes entries by value (case-insensitive); returns `true` if it removed anything.
    ///
    /// Java trap preserved: `removeIf` runs **even for an empty value** — `remove(list, "  ")` deletes
    /// all entries with an empty value and returns `false`.
    @discardableResult
    public static func remove(_ list: inout [BlacklistEntry], _ value: String?) -> Bool {
        let v = norm(value)
        let before = list.count
        list.removeAll { JavaChar.equalsIgnoreCase($0.value, v) }
        return list.count != before && !v.isEmpty
    }

    /// Renames an entry's value (time and note stay). `false` when the entry does not exist, the new
    /// value is empty, or it collides with another entry.
    @discardableResult
    public static func updateValue(_ list: inout [BlacklistEntry], _ oldValue: String?, _ newValue: String?) -> Bool {
        let nv = norm(newValue)
        if nv.isEmpty {
            return false
        }
        guard let target = find(list, oldValue) else {
            return false
        }
        if !JavaChar.equalsIgnoreCase(list[target].value, nv) && find(list, nv) != nil {
            return false // collision with another entry
        }
        list[target].value = nv
        return true
    }

    /// Sets an entry's note; `true` if the entry exists.
    @discardableResult
    public static func setNote(_ list: inout [BlacklistEntry], _ value: String?, _ note: String?) -> Bool {
        guard let target = find(list, value) else {
            return false
        }
        list[target].note = note ?? ""
        return true
    }

    /// Uppercased values for `SpotBuffer.setBlacklist` — Java `LinkedHashSet`: order of first occurrence,
    /// no duplicates (by UTF-16 units), empty values omitted.
    public static func values(_ list: [BlacklistEntry]?) -> [String] {
        var out: [String] = []
        var seen: Set<JavaStringKey> = []
        for entry in list ?? [] where !entry.value.isEmpty {
            let upper = entry.value.uppercased()
            if seen.insert(JavaStringKey(upper)).inserted {
                out.append(upper)
            }
        }
        return out
    }

    /// Merges the old string blacklist into the entry list. Existing ones are not overwritten (they keep
    /// note/time), new ones are added with an empty time and note. (`nowUtc` is not used by Java.)
    public static func migrate(_ legacy: [String]?, _ existing: [BlacklistEntry]?, nowUtc: String?) -> [BlacklistEntry] {
        var out: [BlacklistEntry] = existing ?? []
        for item in legacy ?? [] {
            let v = norm(item)
            if !v.isEmpty && find(out, v) == nil {
                out.append(BlacklistEntry(value: v, addedAtUtc: "", note: ""))
            }
        }
        return out
    }

    /// Reconciles the entry list with the list of values from the Settings dialog: what is not in it is dropped; what
    /// was added is added; what stays keeps its time and note. Returns `true` when the list changed.
    ///
    /// Removal is by **exact** match of the normalized value (Java `List.contains`), adding via
    /// `add` (case-insensitive).
    @discardableResult
    public static func sync(_ list: inout [BlacklistEntry], _ wanted: [String]?, nowUtc: String?) -> Bool {
        var normalized: [String] = []
        var normalizedKeys: Set<JavaStringKey> = []
        for item in wanted ?? [] {
            let v = norm(item)
            if !v.isEmpty && normalizedKeys.insert(JavaStringKey(v)).inserted {
                normalized.append(v)
            }
        }
        let before = list.count
        list.removeAll { !normalizedKeys.contains(JavaStringKey(norm($0.value))) }
        var changed = list.count != before
        for v in normalized {
            changed = add(&list, v, note: "", nowUtc: nowUtc) || changed
        }
        return changed
    }

    private static func norm(_ value: String?) -> String {
        guard let value else { return "" }
        return JavaText.trim(value).uppercased()
    }

    /// Index of the first entry whose value equals (case-insensitively) the normalized `value`.
    private static func find(_ list: [BlacklistEntry], _ value: String?) -> Int? {
        let v = norm(value)
        if v.isEmpty {
            return nil
        }
        return list.firstIndex { JavaChar.equalsIgnoreCase($0.value, v) }
    }
}
