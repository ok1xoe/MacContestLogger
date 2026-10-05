/// Port of Java `contest/category/EntryGridPolicy.java`: which columns (modes) and which bands
/// of the entry grid are available for a given contest — by the BAND/MODE category selection
/// (`ContestSetup.category`) and the definition's modes/bands. Pure logic without UI.
///
/// A `nil` definition list in the MIXED/ALL branches makes Java fail with an NPE; Swift treats it as empty
/// (a deliberate divergence from Java v1.1.1).
public enum EntryGridPolicy {

    /// Entry grid column = mode category.
    public enum ModeColumn: CaseIterable, Hashable, Sendable { case CW, PH, RY, DI }

    /// Keywords of the Java `switch`. Compared byte by byte in UTF-8, not by Swift `==`:
    /// that is canonical and KELVIN SIGN U+212A decomposes to „K", so „PS\u{212A}" would
    /// wrongly come out as „PSK" (Java `switch` compares exactly).
    private static let keywords: [(String, ModeColumn)] = [
        ("CW", .CW),
        ("SSB", .PH), ("FM", .PH), ("AM", .PH), ("PH", .PH), ("PHONE", .PH), ("FONE", .PH),
        ("RTTY", .RY), ("RY", .RY),
        ("DIGITAL", .DI), ("DIGI", .DI), ("DI", .DI), ("PSK", .DI), ("FT8", .DI), ("FT4", .DI),
    ]

    /// Column for one mode (a string from the definition/category); `nil` if it does not know it.
    public static func columnOf(_ mode: String?) -> ModeColumn? {
        guard let mode else { return nil }
        let key = JavaText.trim(mode).uppercased()
        return keywords.first { $0.0.utf8.elementsEqual(key.utf8) }?.1
    }

    /// Which columns to show for a given MODE selection and the definition's modes. `MIXED` → the union of
    /// columns of all the definition's modes; one mode → its column; empty/unknown → all.
    public static func columnsFor(_ modeCategory: String?, _ defModes: [String?]?) -> Set<ModeColumn> {
        let trimmed = JavaText.trim(modeCategory ?? "")
        if JavaChar.equalsIgnoreCase(trimmed, "MIXED") {
            var out: Set<ModeColumn> = []
            for mode in defModes ?? [] {
                if let column = columnOf(mode) { out.insert(column) }
            }
            return out.isEmpty ? Set(ModeColumn.allCases) : out
        }
        if let column = columnOf(trimmed) { return [column] }
        return Set(ModeColumn.allCases)
    }

    /// Which bands are allowed (clickable) for a given BAND selection and the definition's bands.
    /// `ALL`/empty → the definition's bands; a specific band → only that one.
    public static func bandsFor(_ bandCategory: String?, _ defBands: [String?]?) -> Set<Band> {
        let trimmed = JavaText.trim(bandCategory ?? "")
        var out: Set<Band> = []
        if trimmed.isEmpty || JavaChar.equalsIgnoreCase(trimmed, "ALL") {
            for band in defBands ?? [] {
                if let found = Band.from(adif: band) { out.insert(found) }
            }
            return out
        }
        if let found = Band.from(adif: trimmed) { out.insert(found) }
        return out
    }
}
