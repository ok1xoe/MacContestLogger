import Foundation

/// Which raw `rigctld` commands a plugin may send with the `cat` permission: an exact grammar per command — every
/// allowed command has a fixed number of words and each argument is checked. `rigctld` reads a stream of words, so a
/// command with an extra word (`f T 1`) or a missing one (a bare `L` that would swallow the app's next command) is
/// refused, as is any `;`, `|`, `\` (other than the leading `\` of the long form), control character or non-ASCII.
///
/// Allowed: reading (frequency, mode, VFO, split, RIT/XIT, PTT state, antenna, a listed level) and setting the
/// frequency (inside an amateur band, never with a transverter configured), the mode, the VFO, split, RIT/XIT and a
/// few receive levels; the antenna only while not transmitting. Never anything that keys the transmitter, changes
/// its power, sends bytes straight to the rig, starts a tuner or ends the daemon. Transmitting is the `transmit`
/// permission's, through the app's own keyer and PTT paths.
public enum PluginCatPolicy {

    /// What the check needs to know about the rig now.
    public struct Context: Equatable, Sendable {
        /// The rig is transmitting (a message, a PTT).
        public var transmitting: Bool
        /// A transverter is configured for the active rig (its frequencies are not the operating ones).
        public var transverter: Bool

        public init(transmitting: Bool = false, transverter: Bool = false) {
            self.transmitting = transmitting
            self.transverter = transverter
        }
    }

    /// The longest command accepted.
    public static let maxLength = 120

    /// Hamlib mode names a plugin may set.
    static let modes: Set<String> = ["USB", "LSB", "CW", "CWR", "RTTY", "RTTYR", "AM", "FM", "PKTUSB", "PKTLSB",
                                     "PKTFM", "DSB"]
    /// VFO names.
    static let vfos: Set<String> = ["VFOA", "VFOB", "currVFO", "Main", "Sub"]
    /// Levels a plugin may read.
    static let readableLevels: Set<String> = ["AF", "RF", "SQL", "NR", "KEYSPD", "CWPITCH", "STRENGTH", "RFPOWER",
                                              "SWR", "ALC", "PREAMP", "ATT", "AGC"]
    /// Levels a plugin may set, with their range. No transmit power, no VOX, no tuner.
    static let settableLevels: [String: ClosedRange<Double>] = [
        "AF": 0...1, "RF": 0...1, "SQL": 0...1, "NR": 0...1, "KEYSPD": 10...60, "CWPITCH": 300...1_000,
    ]

    /// Why `command` is refused (`nil` = allowed).
    public static func refusal(_ command: String, context: Context = Context()) -> String? {
        guard !command.isEmpty, command.count <= maxLength else { return "empty or longer than \(maxLength)" }
        guard command.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) else {
            return "only printable ASCII"
        }
        let words: [String] = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // The canonical form only: single spaces, none leading or trailing (hamlib reads `+ f` differently).
        guard words.joined(separator: " ") == command else { return "only single spaces between words" }
        guard let head = words.first else { return "empty command" }
        let rest: [String] = Array(words.dropFirst())
        // `;`, `|` and `\` only as the long form's leading `\`.
        let body: String = head.hasPrefix("\\") ? String(command.dropFirst()) : command
        guard !body.contains(";"), !body.contains("|"), !body.contains("\\"), !command.hasPrefix("+") else {
            return "separators and other response forms are not allowed"
        }
        func count(_ n: Int) -> String? {
            rest.count == n ? nil : "\(head) takes \(n) argument\(n == 1 ? "" : "s")"
        }
        switch head {
        case "f", "m", "v", "s", "i", "x", "j", "z", "t", "y", "\\get_freq", "\\get_mode", "\\get_vfo",
             "\\get_split_vfo", "\\get_split_freq", "\\get_split_mode", "\\get_rit", "\\get_xit", "\\get_ptt",
             "\\get_ant":
            return count(0)
        case "l", "\\get_level":
            return count(1) ?? (readableLevels.contains(rest[0]) ? nil : "level \(rest[0]) is not readable")
        case "F", "I":
            if let wrong = count(1) { return wrong }
            if context.transverter { return "frequencies are not set raw with a transverter configured" }
            return frequency(rest[0])
        case "M", "X":
            if let wrong = count(2) { return wrong }
            guard modes.contains(rest[0]) else { return "mode \(rest[0]) is not allowed" }
            return integer(rest[1], 0...20_000)
        case "V":
            return count(1) ?? (vfos.contains(rest[0]) ? nil : "VFO \(rest[0]) is not allowed")
        case "S":
            if let wrong = count(2) { return wrong }
            guard rest[0] == "0" || rest[0] == "1" else { return "split is 0 or 1" }
            return vfos.contains(rest[1]) ? nil : "VFO \(rest[1]) is not allowed"
        case "J", "Z":
            return count(1) ?? integer(rest[0], -99_999...99_999)
        case "L":
            if let wrong = count(2) { return wrong }
            guard let range = settableLevels[rest[0]] else { return "level \(rest[0]) cannot be set" }
            guard let value = Double(rest[1]), value.isFinite, range.contains(value) else {
                return "level \(rest[0]) must be within \(range.lowerBound)…\(range.upperBound)"
            }
            return nil
        case "Y":
            if let wrong = count(2) { return wrong }
            if context.transmitting { return "the antenna is not switched while transmitting" }
            return integer(rest[0], 1...8) ?? integer(rest[1], 0...255)
        default:
            return "command \(head) is not allowed"
        }
    }

    private static func frequency(_ text: String) -> String? {
        guard let hz = Int64(text), hz > 0, Band.from(frequencyHz: Int(clamping: hz)) != nil else {
            return "the frequency must be inside an amateur band (Hz)"
        }
        return nil
    }

    private static func integer(_ text: String, _ range: ClosedRange<Int>) -> String? {
        guard let value = Int(text), range.contains(value) else {
            return "\(text) must be a whole number within \(range.lowerBound)…\(range.upperBound)"
        }
        return nil
    }
}
