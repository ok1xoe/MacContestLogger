/// Checks whether something already listens on the port (Java `cat/RigctldPort`).
///
/// Needed before launching our own `rigctld`: an orphaned daemon after an app crash keeps holding the port, a new one
/// would not take it and would die silently — and the station would then talk to the old daemon (adoption in `CatSession`).
/// Blocks up to 300 ms (connect timeout) — call off Swift's shared pool.
public enum RigctldPort {

    static let connectTimeoutMs = 300

    /// `true` when a connection to `host:port` can be opened. `nil`/empty (`isBlank`) host, port outside 1…65535,
    /// an unresolvable name and any connect error → `false`.
    public static func isListening(host: String?, port: Int) -> Bool {
        guard let host, !JavaText.isBlank(host), port > 0, port <= 65_535 else {
            return false
        }
        do {
            let socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: connectTimeoutMs, readTimeoutMs: 0)
            socket.close()
            return true
        } catch {
            return false
        }
    }
}
