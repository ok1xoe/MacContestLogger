import Foundation

/// Spot of the own station caught in the DX cluster stream (Java record `dxcluster.SelfSpot`) — the report
/// „you were spotted, and by whom" into the Info window's message window. For Reverse Beacon Network spots it also carries the signal
/// margin and speed.
public struct SelfSpot: Equatable, Sendable {
    /// Who sent the spot (for RBN the skimmer).
    public let spotter: String
    /// Spot frequency in Hz.
    public let freqHz: Int
    /// `true` for a spot from an RBN skimmer.
    public let rbn: Bool
    /// Signal-to-noise ratio in dB, or `nil` (RBN only).
    public let snrDb: Int?
    /// Speed in WPM, or `nil` (RBN only).
    public let wpm: Int?
    /// When the spot arrived.
    public let at: Date

    public init(spotter: String, freqHz: Int, rbn: Bool, snrDb: Int?, wpm: Int?, at: Date) {
        self.spotter = spotter
        self.freqHz = freqHz
        self.rbn = rbn
        self.snrDb = snrDb
        self.wpm = wpm
        self.at = at
    }

    /// RBN skimmers report to the network with a callsign ending in `-#` (Java `matches`, `.` does not match line terminators).
    private static let skimmerCall: JavaRegex = DxClusterRegex.compile(".*-#$")
    /// Skimmer comment: `CW 21 dB 25 WPM CQ`; the SNR can be negative.
    private static let snrPattern: JavaRegex = DxClusterRegex.compile("(?i)(-?\\d+)\\s*dB")
    private static let wpmPattern: JavaRegex = DxClusterRegex.compile("(?i)(\\d+)\\s*WPM")

    /// Recognizes a spot of the own callsign. Compared exactly (Java `trim()` + `equalsIgnoreCase`) —
    /// `OK1K/P` is a different station.
    ///
    /// - Throws: `JavaNumberFormatError` like Java (`Integer.valueOf`) when the number before `dB` or `WPM`
    ///   overflows `int` (`99999999999 dB`). In Java the exception escapes `detect` into the telnet read loop
    ///   and the connection drops —: preserve (a Java defect to be fixed in both versions).
    ///   Both numbers are always read (even for a human spot), so the exception occurs then too.
    public static func detect(_ spot: DxSpot?, myCall: String?, at: Date) throws(JavaNumberFormatError) -> SelfSpot? {
        guard let spot, let myCall, !JavaText.isBlank(myCall) else { return nil }
        guard JavaChar.equalsIgnoreCase(JavaText.trim(myCall), spot.dxCall) else { return nil }
        let comment = spot.comment
        let snr: Int? = try firstInt(snrPattern, comment)
        let wpm: Int? = try firstInt(wpmPattern, comment)
        // We recognize a skimmer by its callsign, or — when the node does not send the suffix — by the comment,
        // which for RBN always carries both the SNR and the speed.
        let rbn = skimmerCall.matches(spot.spotter) || (snr != nil && wpm != nil)
        return SelfSpot(spotter: spot.spotter, freqHz: spot.freqHz, rbn: rbn,
                        snrDb: rbn ? snr : nil, wpm: rbn ? wpm : nil, at: at)
    }

    private static func firstInt(_ pattern: JavaRegex, _ text: String) throws(JavaNumberFormatError) -> Int? {
        guard let match = pattern.firstMatch(in: text) else { return nil }
        return Int(try JavaInteger.valueOf(match.group(1) ?? ""))
    }
}
