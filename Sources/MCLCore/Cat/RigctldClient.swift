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

    /// The connection; a plugin PTT command reopens it when it is out of step (`reopen`).
    private let socketBox: OSAllocatedUnfairLock<LineSocket>
    private var socket: LineSocket {
        socketBox.withLock { $0 }
    }
    private let timeoutMs: Int
    /// The host and port connected to.
    public let endpoint: RigEndpoint?
    private let modes: HamlibModeProvider
    private let log: CatTrafficLog
    /// Java `synchronized` (reentrant — a CAT log listener may call back into the client).
    private let lock = NSRecursiveLock()
    /// Java `volatile boolean closed` (outside `lock`, so `close` does not wait for a blocked read).
    private let closedFlag = OSAllocatedUnfairLock(initialState: false)
    /// Something failed after a command was written and before its whole reply was read (a write, read or CAT log
    /// error): a reply may still be unread or on its way, so the connection may be out of step (under `lock`; plugin
    /// PTT commands reopen such a connection first).
    private var outOfStep = false
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
        let opened: LineSocket
        do {
            opened = try LineSocket.connect(host: host, port: port, connectTimeoutMs: timeoutMs, readTimeoutMs: timeoutMs)
        } catch let error as JavaSocketError {
            throw CatException("Nelze se připojit k rigctld na " + (host ?? "null") + ":" + String(port), cause: error)
        }
        socketBox = OSAllocatedUnfairLock(uncheckedState: opened)
        self.timeoutMs = timeoutMs
        self.modes = modes
        self.log = log
        endpoint = RigEndpoint(host: host ?? "localhost", port: port)
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

    public func keyPtt(unless cancelled: () -> Bool) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Under the lock: nothing else is written to this connection between the check and `T 1`.
        if cancelled() {
            return false
        }
        try requireInStep()
        try send("T 1")
        let line: String = try readInStep()
        if Self.startsWith(line, "RPRT 0") {
            return true
        }
        if Self.startsWith(line, "RPRT -") {
            // rigctld answered with an error — the rig may still have acted on it (hamlib reports some errors after
            // the command reached the rig), so the caller releases anyway.
            throw CatRefusal(message: "rigctld odmítl zaklíčování (PTT): " + line)
        }
        throw CatException("rigctld odmítl zaklíčování (PTT): " + line)
    }

    public func releasePtt() throws {
        lock.lock()
        defer { lock.unlock() }
        try requireInStep()
        try send("T 0")
        let line: String = try readInStep()
        if !Self.startsWith(line, "RPRT 0") {
            throw CatException("rigctld odmítl odklíčování (PTT): " + line)
        }
    }

    /// A plugin PTT command never goes over a connection that may be out of step (see `outOfStep`: an unread or late
    /// reply would be read as this command's): the connection is reopened first, transparently for the poller (the
    /// operator's own commands keep the measured behaviour). If it cannot be reopened, the client closes.
    private func requireInStep() throws {
        if outOfStep {
            try reopen()
        }
    }

    /// A plugin PTT reply: an error reopens the connection (its reply may still come and must never be read as the
    /// reply to a later command).
    private func readInStep() throws -> String {
        do {
            return try readLine()
        } catch {
            try? reopen()
            throw error
        }
    }

    /// A fresh connection to the same `rigctld` in place of one that may be out of step (under `lock`).
    private func reopen() throws {
        socket.close()
        let fresh: LineSocket
        do {
            let target: RigEndpoint = endpoint ?? RigEndpoint(host: "localhost", port: Self.defaultPort)
            fresh = try LineSocket.connect(host: target.host, port: target.port, connectTimeoutMs: timeoutMs,
                                           readTimeoutMs: timeoutMs)
        } catch {
            close()
            throw CatException("Spojení s rigctld bylo mimo krok a nepodařilo se ho obnovit", cause: error)
        }
        socketBox.withLock { $0 = fresh }
        if closedFlag.withLock({ $0 }) {
            // Closed meanwhile from another thread: the fresh connection goes too.
            fresh.close()
            throw CatException("rigctld klient je zavřený")
        }
        outOfStep = false
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

    /// The most a raw command's reply may hold (bytes) before the connection is given up.
    public static let maxRawReplyBytes = 16 * 1024

    /// The extended response form (`+` before the command): reply lines up to `RPRT <code>`; both directions go
    /// to the CAT log as every command does. A reply longer than `maxRawReplyBytes` closes the connection (its rest
    /// would otherwise be read as the answers to the next commands) and throws.
    public func sendRaw(_ command: String) throws -> RigRawReply {
        lock.lock()
        defer { lock.unlock() }
        var lines: [String] = []
        var bytes = 0
        // Any failure (a timeout above all) closes the connection: a reply read later would answer the next command.
        do {
            try send("+" + command)
        } catch {
            close()
            throw error
        }
        while true {
            let line: String
            do {
                line = try readLine()
            } catch {
                close()
                throw error
            }
            if Self.startsWith(line, "RPRT") {
                let code: Int = Int(JavaText.trim(String(line.dropFirst(4)))) ?? -1
                return RigRawReply(lines: lines, code: code)
            }
            bytes += line.utf8.count + 1
            guard bytes <= Self.maxRawReplyBytes else {
                close()
                throw CatException("rigctld: odpověď na surový příkaz je příliš dlouhá")
            }
            lines.append(line)
        }
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
            outOfStep = true
            throw CatException("Chyba zápisu příkazu '" + command + "' do rigctld", cause: error)
        }
        do {
            try log.tx(command)
        } catch {
            // The command went out and its reply stays unread.
            outOfStep = true
            throw error
        }
    }

    /// Response line after Java `trim()`, written to the CAT log as `← …`.
    private func readLine() throws -> String {
        let line: String?
        do {
            line = try socket.readLine()
        } catch {
            outOfStep = true
            throw CatException("Chyba čtení odpovědi z rigctld", cause: error)
        }
        guard let line else {
            outOfStep = true
            throw CatException("rigctld ukončil spojení")
        }
        let trimmed = JavaText.trim(line)
        do {
            try log.rx(trimmed)
        } catch {
            // Further lines of a multi-line reply stay unread.
            outOfStep = true
            throw error
        }
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
