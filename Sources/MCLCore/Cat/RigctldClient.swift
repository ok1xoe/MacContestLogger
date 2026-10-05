import Foundation
import os

/// CAT client speaking the text protocol of the hamlib daemon `rigctld` (default TCP port 4532) — Java
/// `cat/RigctldClient` (measured on Java v1.1.1).
///
/// Commands: `f` (frequency), `m` (mode + passband), `F <Hz>`, `M <mode> 0`, `s`/`i` (split and TX frequency),
/// `S 1 VFOB`/`S 0 VFOA`, `I <Hz>`, `V VFOB|VFOA`, `G XCHG`, `J <Hz>` + `U RIT 0|1`, `Y <n> 0`, `T 0|1`,
/// `b <text>`, `\stop_morse`, `L KEYSPD <wpm>`; set-command responses `RPRT <code>` (`startsWith("RPRT 0")` = OK).
///
/// Concurrency like Java `synchronized`: every command method holds the (recursive) lock for the whole sequence —
/// `setOtherVfoFrequencyHz` (`V VFOB`, `F`, `V VFOA` in `finally`) and `read` (`f`, `m`, `s`, `i`) are atomic
/// with respect to polling. Calls **block** the calling thread (POSIX socket, `LineSocket`) — they belong on their own thread or
/// a serial queue, not in Swift's shared pool. `isConnected` and `close` do not take the lock (neither does Java);
/// `close` from another thread ends an in-progress read with the error `Socket closed`.
///
/// Errors as in Java: socket I/O errors (`JavaSocketError`) are wrapped in `CatException` with a cause, end of
/// stream mid-response is `CatException("rigctld ukončil spojení")` a CAT log error
/// (`UncheckedIOError`) and `JavaIllegalArgumentError` from connecting propagate unchanged. After a timeout the client
/// **does not resynchronize** — the late response is read as the response to the next command (R7; measured `desync`).
public final class RigctldClient: RigController, @unchecked Sendable {

    public static let defaultPort = 4532

    private let socket: LineSocket
    private let modes: HamlibModeProvider
    private let log: CatTrafficLog
    /// Java `synchronized` (reentrant — a CAT log listener may call back into the client).
    private let lock = NSRecursiveLock()
    /// Java `volatile boolean closed` (outside `lock`, so `close` does not wait for a blocked read).
    private let closedFlag = OSAllocatedUnfairLock(initialState: false)
    /// The rig answered the split query with an error — we stop asking (under `lock`).
    private var splitUnsupported = false

    /// Connects (Java `new RigctldClient(host, port[, timeoutMs])`; default timeout 2,000 ms for connecting
    /// and every read). `modes` is read on every `read`/`setMode` (replacement for global `HamlibModes`).
    ///
    /// - Throws: `CatException("Nelze se připojit k rigctld na <host>:<port>")` with cause `JavaSocketError`;
    ///   `JavaIllegalArgumentError` (port out of range, negative timeout, `nil` host) unchanged as in Java.
    public init(host: String?, port: Int, timeoutMs: Int = 2000,
                modes: @escaping HamlibModeProvider = { HamlibModeMapping.default },
                log: CatTrafficLog = .shared) throws {
        do {
            socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: timeoutMs, readTimeoutMs: timeoutMs)
        } catch let error as JavaSocketError {
            throw CatException("Nelze se připojit k rigctld na " + (host ?? "null") + ":" + String(port), cause: error)
        }
        self.modes = modes
        self.log = log
    }

    /// Connects to the local `rigctld` on the default port (Java `connectLocal()`).
    public static func connectLocal(modes: @escaping HamlibModeProvider = { HamlibModeMapping.default },
                                    log: CatTrafficLog = .shared) throws -> RigctldClient {
        try RigctldClient(host: "localhost", port: defaultPort, modes: modes, log: log)
    }

    public func read() throws -> RigState {
        lock.lock()
        defer { lock.unlock() }
        let freqHz = try readFrequency()
        try send("m")
        let rawMode = try readLine()
        let passbandLine = try readLine()
        let passband = parseLongSafe(passbandLine, 0)
        var split = false
        var txHz: Int64 = 0
        if !splitUnsupported {
            try send("s")
            let on = try readLine()
            if Self.startsWith(on, "RPRT") {
                splitUnsupported = true
            } else {
                _ = try readLine() // TX VFO
                split = JavaText.trim(on) == "1"
                if split {
                    try send("i")
                    let tx = try readLine()
                    txHz = Self.startsWith(tx, "RPRT") ? 0 : parseLongSafe(tx, 0)
                }
            }
        }
        return RigState(freqHz: freqHz, mode: modes().toMode(rawMode), rawMode: rawMode, passband: passband,
                        split: split, txFreqHz: txHz)
    }

    public func setSplit(_ on: Bool, txFreqHz: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        if on {
            try send("S 1 VFOB")
            try expectRprtOk("zapnutí splitu")
            if txFreqHz > 0 {
                try send("I " + String(txFreqHz))
                try expectRprtOk("nastavení vysílací frekvence")
            }
        } else {
            try send("S 0 VFOA")
            try expectRprtOk("vypnutí splitu")
        }
        splitUnsupported = false // the rig evidently supports split, so let polling read it again
    }

    public func setOtherVfoFrequencyHz(_ freqHz: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        // Atomically: a poll between VFO switches must not read the frequency of B as A.
        try send("V VFOB")
        try expectRprtOk("výběr VFO B")
        // Java try/finally: always return to VFO A; its error overrides the error from `F`.
        let failure: (any Error)?
        do {
            try send("F " + String(freqHz))
            try expectRprtOk("nastavení frekvence VFO B")
            failure = nil
        } catch {
            failure = error
        }
        try send("V VFOA")
        try expectRprtOk("návrat na VFO A")
        if let failure {
            throw failure
        }
    }

    public func setAntenna(_ antenna: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("Y " + String(antenna) + " 0")
        try expectRprtOk("přepnutí antény")
    }

    public func selectVfo(_ vfoB: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("V " + (vfoB ? "VFOB" : "VFOA"))
        try expectRprtOk("výběr VFO " + (vfoB ? "B" : "A"))
    }

    public func setRit(_ offsetHz: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("J " + String(offsetHz))
        try expectRprtOk("nastavení RIT")
        // Not every rig can toggle the RIT function — a rejection does not block, only the response is read.
        try send("U RIT " + (offsetHz != 0 ? "1" : "0"))
        _ = try readLine()
    }

    public func swapVfo() throws {
        lock.lock()
        defer { lock.unlock() }
        try send("G XCHG")
        try expectRprtOk("prohození VFO")
    }

    public func setFrequencyHz(_ freqHz: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("F " + String(freqHz))
        try expectRprtOk("nastavení frekvence")
    }

    public func setMode(_ mode: Mode?, freqHz: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("M " + modes().toHamlib(mode, freqHz: freqHz) + " 0")
        try expectRprtOk("nastavení módu")
    }

    public func setPtt(_ on: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("T " + (on ? "1" : "0"))
        try expectRprtOk(on ? "zaklíčování (PTT)" : "odklíčování (PTT)")
    }

    public func sendMorse(_ text: String) throws {
        lock.lock()
        defer { lock.unlock() }
        // rigctld takes the rest of the line after „b" as text, so spaces go through.
        try send("b " + text)
        // Hamlib rejects send_morse (RPRT -1) when the rig is not in CW/CWR mode.
        try expectRprtOk("odeslání CW (rig musí být v módu CW)")
    }

    public func stopMorse() throws {
        lock.lock()
        defer { lock.unlock() }
        try send("\\stop_morse")
        try expectRprtOk("zastavení CW")
    }

    public func setCwSpeed(_ wpm: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        try send("L KEYSPD " + String(wpm))
        try expectRprtOk("nastavení rychlosti CW")
    }

    /// Java `!closed && socket.isConnected() && !socket.isClosed()` — closing by the peer is not seen (R8).
    public func isConnected() -> Bool {
        !closedFlag.withLock { $0 } && !socket.isClosed
    }

    public func close() {
        closedFlag.withLock { $0 = true }
        socket.close()
    }

    // MARK: - Protokol

    private func readFrequency() throws -> Int64 {
        try send("f")
        let line = try readLine()
        if Self.startsWith(line, "RPRT") {
            throw CatException("rigctld vrátil chybu při čtení frekvence: " + line)
        }
        return parseLongSafe(line, 0)
    }

    private func expectRprtOk(_ action: String) throws {
        let line = try readLine()
        if !Self.startsWith(line, "RPRT 0") {
            throw CatException("rigctld odmítl " + action + ": " + line)
        }
    }

    /// Writes `command\n` (US-ASCII, non-ASCII char → `?`), then `→ command` to the CAT log (its error propagates).
    private func send(_ command: String) throws {
        do {
            try socket.writeAscii(command + "\n")
        } catch {
            throw CatException("Chyba zápisu příkazu '" + command + "' do rigctld", cause: error)
        }
        try log.tx(command)
    }

    /// Response line after Java `trim()`, written to the CAT log as `← …`.
    private func readLine() throws -> String {
        let line: String?
        do {
            line = try socket.readLine()
        } catch {
            throw CatException("Chyba čtení odpovědi z rigctld", cause: error)
        }
        guard let line else {
            throw CatException("rigctld ukončil spojení")
        }
        let trimmed = JavaText.trim(line)
        try log.rx(trimmed)
        return trimmed
    }

    /// Java `Long.parseLong(s.trim())`, error → `fallback` (`+14074000` passes, `14.074e6` → 0; R5).
    private func parseLongSafe(_ text: String, _ fallback: Int64) -> Int64 {
        (try? JavaInteger.parseLong(JavaText.trim(text))) ?? fallback
    }

    /// Java `startsWith` over UTF-16 units (not over graphemes like Swift `hasPrefix`).
    private static func startsWith(_ text: String, _ prefix: String) -> Bool {
        text.utf16.starts(with: prefix.utf16)
    }
}
