/// Selection of band notes (DXLog Band notes) for the bandmap and the entry window.
/// Mirrors the Java `radio.BandNotes`.
public enum BandNotes {

    /// Band of a note: from the frequency (`freqKHz > 0`, `Math.round(kHz × 1000)`), otherwise from the
    /// given band (Java `trim().toLowerCase(ROOT)` → `Band.fromAdif`; a no-break
    /// space is not trimmed and the band is not recognised). `NaN` is not `> 0`, so it goes via `band`.
    public static func bandOf(_ note: BandNote) -> Band? {
        if note.freqKHz > 0 {
            return Band.from(frequencyHz: Int(JavaMath.round(note.freqKHz * 1000)))
        }
        return Band.from(adif: JavaText.toLowerCase(JavaText.trim(note.band)))
    }

    /// The Bandmap's mark of a frequency note (`Math.round(freqKHz * 1000)`); `nil` for a note without a frequency
    /// (`freqKHz > 0` is false).
    public static func markHz(_ note: BandNote) -> Int64? {
        note.freqKHz > 0 ? JavaMath.round(note.freqKHz * 1000) : nil
    }

    /// Band notes sorted by frequency (whole-band notes first).
    /// The sort is Java `Comparator.comparingDouble` (= `Double.compare`: `-0.0 < 0.0`,
    /// `NaN` at the end) and **stable** like `Stream.sorted`.
    public static func forBand(_ all: [BandNote], band: Band) -> [BandNote] {
        let matching: [BandNote] = all.filter { bandOf($0) == band }
        let indexed = matching.enumerated().sorted { left, right in
            let order = javaDoubleCompare(left.element.freqKHz, right.element.freqKHz)
            return order != 0 ? order < 0 : left.offset < right.offset
        }
        return indexed.map(\.element)
    }

    /// Nearest frequency note within `toleranceHz` (to display at the tuned frequency);
    /// on a tie of distance the first in list order (`Stream.min`). The distance is a Java
    /// `long`: `Math.round` saturates, the difference wraps, `Math.abs(Long.MIN_VALUE)` is negative
    /// (measured, rows `BN.near` in a maintainer-only probe).
    public static func near(_ all: [BandNote], freqHz: Int, toleranceHz: Int) -> BandNote? {
        var best: BandNote?
        var bestDistance: Int64 = 0
        for note in all where note.freqKHz > 0 {
            let distance = JavaMath.abs(JavaMath.round(note.freqKHz * 1000) &- Int64(freqHz))
            if distance > Int64(toleranceHz) { continue }
            if best == nil || distance < bestDistance {
                best = note
                bestDistance = distance
            }
        }
        return best
    }

    /// Java `Double.compare(a, b)`.
    private static func javaDoubleCompare(_ a: Double, _ b: Double) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let canonicalNaN: Int64 = 0x7FF8_0000_0000_0000
        let aBits: Int64 = a.isNaN ? canonicalNaN : Int64(bitPattern: a.bitPattern)
        let bBits: Int64 = b.isNaN ? canonicalNaN : Int64(bitPattern: b.bitPattern)
        return aBits == bBits ? 0 : (aBits < bBits ? -1 : 1)
    }
}
