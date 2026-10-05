import Foundation

/// Row 1 of the Hardware tab — the overview of the real rig (`HW:` = `ui/configurer/HardwareTab.kt` of v1.1.1,
/// lines 107-118). Takes the draft's rig fields (the draft keeps the rigctld port as text).
public enum HardwareSummary {

    /// The "Port" and "Radio" cells: Kotlin `ifBlank { "None" }` (Kotlin whitespace, U+00A0 is blank).
    public static func cell(_ text: String) -> String {
        KotlinText.isBlank(text) ? "None" : text
    }

    /// The "Linka / IP" cell: `"host:port"` for `CONNECT_RUNNING`, otherwise `"baud,<parity.hamlib>,data,stop"`.
    public static func line(
        mode: ConnectionMode, host: String, port: String, baud: Int, parity: SerialParity, dataBits: Int, stopBits: Int
    ) -> String {
        if mode == .connectRunning {
            return host + ":" + port
        }
        let fields: [String] = [String(baud), parity.hamlib, String(dataBits), String(stopBits)]
        return fields.joined(separator: ",")
    }
}
