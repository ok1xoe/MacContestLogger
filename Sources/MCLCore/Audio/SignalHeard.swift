/// N1MM's speaker column of the Available window: a spot whose frequency lies in the receiver's audio passband and
/// shows a signal in the waterfall's newest rows is "heard". Pure functions over the normalized rows of `Waterfall`
/// (0 = the noise floor, 1 = 40 dB above it); the waterfall window holds the receiver audio, so without it nothing is
/// heard.
public enum SignalHeard {

    /// A bin at least this bright (0…1 of the 40 dB range, ≈ 14 dB above the noise floor) is a signal.
    public static let threshold: Float = 0.35
    /// How many of the newest rows are looked at (≈ 0.5 s at 12 kHz with 50 % overlap).
    public static let rowsToCheck = 6
    /// Bins either side of the spot's bin that count (a spot is rarely exactly on frequency).
    public static let binTolerance = 3

    /// The audio tone of a frequency on the band: the inverse of `AudioToRf.rfHz` (CW is heard at the pitch, LSB,
    /// CW-R and RTTY are inverted).
    public static func audioHz(rfHz: Int64, dialHz: Int64, rawMode: String?, cwPitch: Int32) -> Double {
        let mode: String = (rawMode ?? "").uppercased()
        let offset = Double(rfHz - dialHz)
        let pitch = Double(cwPitch)
        switch mode {
        case "CW": return offset + pitch
        case "CWR": return pitch - offset
        case "LSB", "PKTLSB", "RTTY": return -offset
        default: return offset
        }
    }

    /// A tone `audioHz` is seen in `rows` (newest first, every row `bins` wide covering 0…`maxHz`): one of the
    /// newest `rowsToCheck` rows has a bin within `binTolerance` of it at `threshold` or above. Outside the passband
    /// (below 0 or at `maxHz` and above) nothing is heard.
    public static func isHeard(rows: [[Float]], audioHz: Double, maxHz: Double) -> Bool {
        guard maxHz > 0, audioHz >= 0, audioHz < maxHz else { return false }
        for row in rows.prefix(rowsToCheck) where !row.isEmpty {
            let bin = Int((audioHz / maxHz * Double(row.count)).rounded())
            let lo: Int = Swift.max(0, bin - binTolerance)
            let hi: Int = Swift.min(row.count - 1, bin + binTolerance)
            guard lo <= hi else { continue }
            for i in lo...hi where row[i] >= threshold {
                return true
            }
        }
        return false
    }

    /// What a waterfall shows now, for a spot list to ask about many spots.
    public struct Spectrum: Sendable {
        public let rows: [[Float]]
        public let maxHz: Double
        public let dialHz: Int64
        public let rawMode: String
        public let cwPitch: Int32

        public init(rows: [[Float]], maxHz: Double, dialHz: Int64, rawMode: String, cwPitch: Int32) {
            self.rows = rows
            self.maxHz = maxHz
            self.dialHz = dialHz
            self.rawMode = rawMode
            self.cwPitch = cwPitch
        }

        /// The spot on `freqHz` is heard (no dial frequency = nothing is).
        public func hears(freqHz: Int) -> Bool {
            guard dialHz > 0 else { return false }
            let tone: Double = SignalHeard.audioHz(rfHz: Int64(freqHz), dialHz: dialHz, rawMode: rawMode,
                                                   cwPitch: cwPitch)
            return SignalHeard.isHeard(rows: rows, audioHz: tone, maxHz: maxHz)
        }
    }
}
