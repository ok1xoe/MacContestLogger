import Foundation

/// The band notes window logic (Kotlin `BandNotesWindow.kt`, `AS:2531-2543`): parsing the add form, the sort order and
/// the list rows. Pure: the caller stores the notes.
public enum BandNotesEditing {

    /// The initial value of the frequency field: the tuned frequency in kHz, `%.1f` (US).
    public static func frequencyFieldText(tunedFreqHz: Int64) -> String {
        JavaFormat.format("%.1f", .double(Double(tunedFreqHz) / 1000.0))
    }

    /// Builds a note from the form: a number (comma allowed) is a frequency in kHz, anything else a band name
    /// (`trim().lowercase()`); the text is trimmed. `nil` when the text is blank or the note has no band — the caller
    /// then shows `invalidText`.
    public static func parse(freq: String, text: String) -> BandNote? {
        let khz: Double? = JavaDouble.parseDouble(freq.replacingOccurrences(of: ",", with: "."))
        let trimmed: String = KotlinText.trim(text)
        let note: BandNote
        if let khz {
            note = BandNote(band: "", freqKHz: khz, text: trimmed)
        } else {
            note = BandNote(band: JavaText.toLowerCase(KotlinText.trim(freq)), freqKHz: 0, text: trimmed)
        }
        guard !KotlinText.isBlank(text), BandNotes.bandOf(note) != nil else { return nil }
        return note
    }

    /// Status text for a rejected form.
    public static func invalidText(_ translator: Translator) -> String {
        translator.translate("Poznámka: zadej frekvenci v pásmu (kHz) nebo pásmo (20m) a text")
    }

    /// Notes by the band's lower edge (no band = 0), then by frequency (`Double.compareTo` order); stable.
    public static func sorted(_ notes: [BandNote]) -> [BandNote] {
        let keyed: [(index: Int, low: Int64, note: BandNote)] = notes.enumerated().map {
            (index: $0.offset, low: BandNotes.bandOf($0.element).map { Int64($0.lowHz) } ?? 0, note: $0.element)
        }
        let ordered = keyed.sorted { left, right in
            if left.low != right.low { return left.low < right.low }
            let order: Int = compare(left.note.freqKHz, right.note.freqKHz)
            return order != 0 ? order < 0 : left.index < right.index
        }
        return ordered.map(\.note)
    }

    /// A list row: ADIF band padded to 5 (`?` without a band), the frequency (`%.1f`) or band padded to 10, the text.
    public static func rowText(_ note: BandNote) -> String {
        let where_: String = note.freqKHz > 0 ? JavaFormat.format("%.1f", .double(note.freqKHz)) : note.band
        let band: String = BandNotes.bandOf(note)?.adif ?? "?"
        return "\(ToolsFormat.padEnd(band, 5)) \(ToolsFormat.padEnd(where_, 10)) \(note.text)"
    }

    /// The list without one note (Kotlin removes by identity; equal duplicates are interchangeable, the first goes).
    public static func removing(_ note: BandNote, from notes: [BandNote]) -> [BandNote] {
        guard let index = notes.firstIndex(of: note) else { return notes }
        var out = notes
        out.remove(at: index)
        return out
    }

    /// Kotlin `Double.compareTo`: `-0.0 < 0.0`, `NaN` greatest and equal to itself.
    static func compare(_ a: Double, _ b: Double) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let aBits: Int64 = a.isNaN ? 0x7FF8_0000_0000_0000 : Int64(bitPattern: a.bitPattern)
        let bBits: Int64 = b.isNaN ? 0x7FF8_0000_0000_0000 : Int64(bitPattern: b.bitPattern)
        return aBits == bBits ? 0 : (aBits < bBits ? -1 : 1)
    }
}
