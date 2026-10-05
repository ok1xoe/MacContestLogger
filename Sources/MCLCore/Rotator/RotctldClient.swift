import Foundation

/// Hamlib `rotctld` client (Java `rotator/RotctldClient`; a text protocol like rigctld): `P az el`
/// turn, `p` position, `S` stop. The rotator is started separately (`rotctld -m 603 -r /dev/cu.… -t 4533`).
///
/// `normalize` is Java `azimuth % 360` (= `fmod`, Swift `truncatingRemainder`; the sign of zero matches)
/// and adding 360 for negatives: `-0.0` and `-360` stay `-0.0`, `360` and `720` → `0.0`, `-1e-20` → `360.0`,
/// `NaN`/`±∞` → `NaN`. The Java comment "360 stays 360" **does not hold** — the behaviour is replicated, not the comment.
/// The turn command is formatted by Java `%.1f` (HALF_UP of the decimal expansion:
/// `12.25` → `P 12.3 0`, `359.95` → `P 360.0 0`, `-0.0` → `P -0.0 0`).
///
/// Connection (measured by the maintainer-only probe, rows `rot.*`): `LineSocket` with a timeout
/// for connecting and for each read of **3 000 ms** (Java `connect(…, 3000)` + `setSoTimeout(3000)`); connect
/// and socket errors (`JavaSocketError`, `JavaIllegalArgumentError`) unchanged as the Java constructor
/// exceptions. Each response is read with `readLine` + Java `trim`; end of stream →
/// `JavaIOError("rotctld ukončil spojení")`. `azimuth`: the first line starting with `RPRT` →
/// `JavaIOError("rotctld vrátil chybu: …")` (the second line is then not read), otherwise the elevation line is read
/// and the azimuth is `Double.parseDouble` (`JavaNumberFormatError`). `turnTo`/`stop`: the line must start with `RPRT 0`,
/// otherwise `JavaIOError("rotctld odmítl natočení|zastavení: …")`. No resynchronisation — after a timeout or
/// error the late lines are read as responses to the next queries (as in Java).
///
/// `azimuth`/`turnTo`/`stop` are serialised (Java `synchronized`); `close` from any thread
/// (a read in progress ends with `Socket closed`). All calls block — call from your own thread or
/// a serial queue, not from Swift's shared thread pool.
public final class RotctldClient: @unchecked Sendable {

    /// Java `3000` for connecting and reading.
    static let timeoutMs = 3_000

    private let socket: LineSocket
    /// Java monitor `this`.
    private let lock = NSLock()

    /// Connects (Java `new RotctldClient(host, port)`).
    public convenience init(host: String?, port: Int) throws {
        try self.init(host: host, port: port, timeoutMs: Self.timeoutMs)
    }

    /// For tests: a timeout other than Java's 3 000 ms.
    init(host: String?, port: Int, timeoutMs: Int) throws {
        socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: timeoutMs, readTimeoutMs: timeoutMs)
    }

    /// Current azimuth (°).
    public func azimuth() throws -> Double {
        lock.lock()
        defer { lock.unlock() }
        try send("p")
        let az = try readLine()
        if az.utf16.starts(with: "RPRT".utf16) {
            throw JavaIOError("rotctld vrátil chybu: " + az)
        }
        _ = try readLine() // elevation
        return try JavaDouble.parse(az)
    }

    /// Turns to an azimuth (0–360°), elevation 0.
    public func turnTo(_ azimuth: Double) throws {
        lock.lock()
        defer { lock.unlock() }
        try send(Self.turnCommand(azimuth))
        try expectOk("natočení")
    }

    public func stop() throws {
        lock.lock()
        defer { lock.unlock() }
        try send("S")
        try expectOk("zastavení")
    }

    /// Closes the connection (Java `close`, errors are ignored); a repeated call does nothing.
    public func close() {
        socket.close()
    }

    /// Azimuth to 0–360.
    public static func normalize(_ azimuth: Double) -> Double {
        let a = azimuth.truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// The long path = the opposite direction.
    public static func longPath(_ azimuth: Double) -> Double {
        normalize(azimuth + 180)
    }

    /// Turn command line (without `\n`): `String.format(Locale.US, "P %.1f 0", normalize(azimuth))`.
    static func turnCommand(_ azimuth: Double) -> String {
        JavaFormat.format("P %.1f 0", .double(normalize(azimuth)))
    }

    private func send(_ command: String) throws {
        try socket.writeAscii(command + "\n")
    }

    private func readLine() throws -> String {
        guard let line = try socket.readLine() else {
            throw JavaIOError("rotctld ukončil spojení")
        }
        return JavaText.trim(line)
    }

    private func expectOk(_ what: String) throws {
        let line = try readLine()
        if !line.utf16.starts(with: "RPRT 0".utf16) {
            throw JavaIOError("rotctld odmítl " + what + ": " + line)
        }
    }
}
