/// N1MM: „SH/DX entered in the Entry window callsign field will be passed through to the active packet window". The
/// call field text that is such a cluster command.
public enum CallFieldClusterCommand {

    /// The command to send to the DX cluster (trimmed, uppercased), `nil` for any other text.
    public static func command(_ callText: String) -> String? {
        let text: String = KotlinStrings.uppercase(KotlinStrings.trim(callText))
        guard text.hasPrefix("SH/DX") else { return nil }
        let rest: Substring = text.dropFirst(5)
        // SH/DX alone or with its arguments (`SH/DX/30`, `SH/DX 25`), not a callsign that merely starts so.
        guard rest.isEmpty || rest.first == "/" || rest.first == " " else { return nil }
        return text
    }
}
