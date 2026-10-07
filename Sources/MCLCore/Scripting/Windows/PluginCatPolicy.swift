import Foundation

/// Which raw `rigctld` commands a plugin may send with the `cat` permission. Only reading and the set commands of
/// frequency, mode, VFO, split, RIT/XIT, levels and the antenna; never anything that keys the transmitter
/// (`T`/`set_ptt`, `b`/`send_morse`, voice memories, DTMF, tuner and VFO operations like `TUNE`), sends bytes
/// straight to the rig (`w`/`W`), switches its power or ends the daemon (`q`, `\halt`). Transmitting is the
/// `transmit` permission's, through the app's own keyer and PTT paths.
public enum PluginCatPolicy {

    /// The longest command accepted.
    public static let maxLength = 120

    /// Single-letter commands allowed (`rigctld` short form).
    static let allowedShort: Set<String> = [
        "f", "F", "m", "M", "v", "V", "s", "S", "i", "I", "x", "X", "j", "J", "z", "Z", "l", "L", "y", "Y", "t",
        "1", "_",
    ]

    /// Level names that are refused even for `L` (they start a tuning cycle or a voice/keyer action).
    static let refusedLevels: Set<String> = ["TUNE", "BKINDL", "VOXDELAY", "VOXGAIN"]

    /// Why `command` is refused (`nil` = allowed).
    public static func refusal(_ command: String) -> String? {
        let trimmed: String = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "empty command" }
        guard trimmed.count <= maxLength else { return "command longer than \(maxLength) characters" }
        guard trimmed.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7F }) else {
            return "only printable ASCII"
        }
        guard !trimmed.hasPrefix("+"), !trimmed.hasPrefix(";"), !trimmed.hasPrefix("|") else {
            return "the response form is chosen by the app"
        }
        let words: [Substring] = trimmed.split(separator: " ")
        let head = String(words[0])
        if head.hasPrefix("\\") {
            let name = String(head.dropFirst())
            // Long forms: reading only.
            guard name.hasPrefix("get_") || name == "dump_state" || name == "dump_caps" || name == "chk_vfo" else {
                return "only \\get_… long commands"
            }
            return nil
        }
        guard allowedShort.contains(head) else {
            return "command \(head) is not allowed"
        }
        if head == "L", words.count > 1, refusedLevels.contains(words[1].uppercased()) {
            return "level \(words[1]) is not allowed"
        }
        return nil
    }
}
