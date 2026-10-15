import Foundation

/// N1MM „Mute mic on supported radios": while a voice message from the computer keys the rig over CAT, the rig's
/// microphone gain is set to 0 (hamlib level `MICGAIN`) so the microphone does not mix into the message, and the
/// previous gain is restored afterwards. Works on the rigs whose hamlib backend supports `MICGAIN` (e.g. Elecraft
/// K3, Ten-Tec Orion); any other rig answers with an error code and nothing changes. Every command is best effort:
/// an error never stops the voice message or its PTT release.
public enum MicMute {

    /// The command that reads the gain.
    public static let readCommand = "l MICGAIN"
    /// The command that mutes the microphone.
    public static let muteCommand = "L MICGAIN 0"

    /// The command that restores `gain` (as it was read).
    public static func restoreCommand(_ gain: String) -> String {
        "L MICGAIN " + gain
    }

    /// The gain in an extended (`+l`) reply: the last line whose text after its last `:` is a number
    /// (`get_level: MICGAIN` / `0.500000`, or `Level Value: 0.500000`). `nil` when there is none.
    public static func gain(in lines: [String]) -> String? {
        for line in lines.reversed() {
            let value: String = line.split(separator: ":").last.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            if let number = Double(value), number.isFinite, number >= 0 {
                return value
            }
        }
        return nil
    }

    /// Reads the gain and mutes the microphone; the gain to restore, `nil` when the rig cannot do it (nothing was
    /// muted). Blocks on rig I/O.
    public static func mute(_ rig: any RigController) -> String? {
        guard let read = try? rig.sendRaw(readCommand), read.code == 0, let saved = gain(in: read.lines) else {
            return nil
        }
        guard let set = try? rig.sendRaw(muteCommand), set.code == 0 else { return nil }
        return saved
    }

    /// Restores the gain `mute` returned. Blocks on rig I/O; an error is ignored.
    public static func restore(_ rig: any RigController, gain: String) {
        _ = try? rig.sendRaw(restoreCommand(gain))
    }
}
