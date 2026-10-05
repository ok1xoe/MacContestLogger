import Foundation

/// K1EL Winkeyer (WK2/WK3) over a serial line: 1200 Bd, 8N2. Mirrors Java `keyer.WinkeyerKeyer`.
/// From the host protocol it uses:
/// - `00 02` host open (the keyer answers with the version), `00 03` host close;
/// - `02 nn` speed WPM, `0A` immediate buffer clear (Esc), `0B 01/00` key immediate (tuning);
/// - `1C nn` buffered speed change, `1E` its cancellation — `<`/`>` changes inside a message;
/// - `1B c1 c2` merging two characters into a prosign (AR, SK…);
/// - text as ASCII (Java `getBytes(US_ASCII)`: every code point outside ASCII → `?`).
///
/// From incoming bytes the status is tracked (0xC0–0xFF, bit 0x04 = keyer transmitting); character echo and potentiometer
/// position are ignored. **The first received byte is the version** — even if it is a status byte (as in Java).
///
/// Read by the `winkeyer-reader` thread (a Java daemon thread) until the transport returns end of stream or an error,
/// or until the keyer is closed. `open(portPath:wpm:)` opens the serial port like Java (1200 Bd 8N2, read
/// semi-blocking 200 ms, DTR high, RTS low); `open(transport:wpm:)` does the rest of Java `open` — host
/// open, speed, close on error.
///
/// **Flaw preserved from Java ** reading the serial port after 200 ms of silence throws a timeout
/// (`SerialPort`, jSerialComm `TIMEOUT_READ_SEMI_BLOCKING`) and the read loop ends. If the keyer answers
/// host open later than ~200 ms, nobody reads the version and `open` fails after 2 s with "Winkeyer neodpovídá";
/// after a successful open the state (`isBusy`) stops being tracked after the first 200 ms pause. Fix only on the
/// user's decision (then in both versions).
public final class WinkeyerKeyer: CwKeyer, @unchecked Sendable {

    static let admin: UInt8 = 0x00
    static let adminOpen: UInt8 = 0x02
    static let adminClose: UInt8 = 0x03
    static let setSpeedCommand: UInt8 = 0x02
    static let clearBuffer: UInt8 = 0x0A
    static let keyImmediate: UInt8 = 0x0B
    static let merge: UInt8 = 0x1B
    static let bufferedSpeed: UInt8 = 0x1C
    static let cancelBufferedSpeed: UInt8 = 0x1E

    private let transport: any ByteTransport
    /// Java monitor `this` (`send`, `setSpeed`, `write` are `synchronized`; `send` calls `write`).
    private let monitor = NSRecursiveLock()
    /// Java `volatile` fields + `CountDownLatch` for the version.
    private let state = NSCondition()
    private var version = -1
    private var busy = false
    private var closed = false
    /// The read loop has ended (for tests).
    private var readerEnded = false

    /// Keyer over a transport; immediately starts the read thread (Java package-private constructor).
    public init(transport: any ByteTransport) {
        self.transport = transport
        let reader = Thread { [self] in readLoop() }
        reader.name = "winkeyer-reader"
        reader.start()
    }

    /// Opens the Winkeyer on a serial port, sends host open and waits for the version (Java `open(portPath, wpm)`).
    ///
    /// - Throws: `SerialPortInvalidPortError` (path does not exist — Java `getCommPort`),
    ///   `CwKeyerError(.io, "Nelze otevřít port <portPath>")` (opening failed), errors of `open(transport:…)`
    ///   (keyer does not answer, write failed — the port is then closed).
    ///
    /// Blocks up to ~2 s — call from your own thread or a serial queue, not from the shared pool.
    public static func open(portPath: String, wpm: Int) throws -> WinkeyerKeyer {
        try open(portPath: portPath, wpm: wpm, modem: SerialPort.PosixModemControl(), timeoutMs: hostOpenTimeoutMs)
    }

    /// Java `hostOpen(2_000)` in `open`.
    static let hostOpenTimeoutMs = 2_000

    /// Winkeyer line setup (Java `setComPortParameters(1200, 8, TWO_STOP_BITS, NO_PARITY)`; DTR and RTS
    /// high after opening like jSerialComm `openPort`).
    static let serialSettings = SerialPort.Settings(baud: 1_200, dataBits: 8, stopBits: 2, parity: .none)

    /// For tests: replacement for the modem lines (a pseudoterminal does not support them) and the host open timeout.
    static func open(portPath: String, wpm: Int, modem: any SerialPort.ModemControl, timeoutMs: Int) throws -> WinkeyerKeyer {
        guard let port = try SerialPort.openLikeJSerialComm(portPath: portPath, settings: serialSettings, modem: modem) else {
            throw CwKeyerError(.io, "Nelze otevřít port " + portPath)
        }
        // The Winkeyer is powered from DTR; RTS must be low (Java `setDTR()`/`clearRTS()`, the result is ignored).
        try? port.setDTR(true)
        try? port.setRTS(false)
        return try open(transport: port, wpm: wpm, timeoutMs: timeoutMs)
    }

    /// Host open and speed setup over an open transport; on error closes the keyer and passes the error on
    /// (Java `open` without opening the port). `timeoutMs` = wait for the version (Java 2 000 ms).
    public static func open(transport: any ByteTransport, wpm: Int, timeoutMs: Int = 2_000) throws -> WinkeyerKeyer {
        let keyer = WinkeyerKeyer(transport: transport)
        do {
            _ = try keyer.hostOpen(timeoutMs: timeoutMs)
            try keyer.setSpeed(wpm)
        } catch {
            keyer.close()
            throw error
        }
        return keyer
    }

    /// Host open; returns the firmware version. Without an answer within `timeoutMs` throws `IOException`. The deadline is measured
    /// monotonically (`DispatchTime`, Java `CountDownLatch.await` = `nanoTime`), a wall-clock jump does not change it.
    func hostOpen(timeoutMs: Int) throws -> Int {
        try write([Self.admin, Self.adminOpen])
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        let deadline: UInt64 = start &+ UInt64(max(timeoutMs, 0)) &* 1_000_000
        state.lock()
        defer { state.unlock() }
        while version < 0 {
            let now: UInt64 = DispatchTime.now().uptimeNanoseconds
            if now >= deadline {
                throw CwKeyerError(.io, "Winkeyer neodpovídá (žádná verze po host open)")
            }
            let left: Double = Double(deadline - now) / 1_000_000_000
            _ = state.wait(until: Date(timeIntervalSinceNow: left))
        }
        return version
    }

    private var isClosed: Bool {
        state.lock()
        defer { state.unlock() }
        return closed
    }

    /// The read loop ended (end of stream, read error including serial port timeout, close).
    var hasReaderEnded: Bool {
        state.lock()
        defer { state.unlock() }
        return readerEnded
    }

    /// Waits until the read loop ends; `false` = the `timeoutMs` safety expired (tests).
    func waitForReaderEnd(timeoutMs: Int) -> Bool {
        let deadline = Date(timeIntervalSinceNow: Double(timeoutMs) / 1_000)
        state.lock()
        defer { state.unlock() }
        while !readerEnded {
            if !state.wait(until: deadline) {
                return readerEnded
            }
        }
        return true
    }

    private func readLoop() {
        defer {
            state.lock()
            readerEnded = true
            state.broadcast()
            state.unlock()
        }
        while !isClosed {
            let b: Int
            do {
                b = try transport.read()
            } catch {
                return // port closed / disconnected / 200 ms of silence
            }
            if b < 0 {
                return
            }
            state.lock()
            if version < 0 {
                version = b
                state.broadcast()
            } else if b & 0xC0 == 0xC0 {
                busy = b & 0x04 != 0
            }
            // 0x80–0xBF = speed potentiometer, < 0x80 = character echo — we do not care
            state.unlock()
        }
    }

    public func send(_ message: CwMessage, wpm: Int) throws {
        monitor.lock()
        defer { monitor.unlock() }
        let base = Int32(truncatingIfNeeded: wpm)
        var buf: [UInt8] = []
        var delta: Int32 = 0
        var hasSpeed = false
        for part in message.parts {
            switch part {
            case .text(let text):
                for scalar in text.unicodeScalars {
                    buf.append(scalar.isASCII ? UInt8(scalar.value) : 0x3F)
                }
            case .prosign(let letters):
                let units = Array(letters.utf16)
                if units.count == 2 {
                    buf.append(Self.merge)
                    buf.append(UInt8(truncatingIfNeeded: units[0]))
                    buf.append(UInt8(truncatingIfNeeded: units[1]))
                }
            case .speed(let d):
                hasSpeed = true
                delta = delta &+ Int32(truncatingIfNeeded: d)
                buf.append(Self.bufferedSpeed)
                buf.append(UInt8(Self.clamp(base &+ delta)))
            }
        }
        if delta != 0 || hasSpeed {
            buf.append(Self.cancelBufferedSpeed)
        }
        if !buf.isEmpty {
            setBusy(true)
            try write(buf)
        }
    }

    public func abort() throws {
        try write([Self.clearBuffer])
        setBusy(false)
    }

    /// Key immediate (0B 01 / 0B 00): continuous carrier for tuning.
    public func tune(_ on: Bool) throws {
        try write([Self.keyImmediate, on ? 1 : 0])
    }

    public func setSpeed(_ wpm: Int) throws {
        monitor.lock()
        defer { monitor.unlock() }
        try write([Self.setSpeedCommand, UInt8(Self.clamp(Int32(truncatingIfNeeded: wpm)))])
    }

    /// Is the keyer transmitting right now (by the last status byte)?
    public func isBusy() -> Bool {
        state.lock()
        defer { state.unlock() }
        return busy
    }

    public func name() -> String {
        state.lock()
        defer { state.unlock() }
        return version > 0 ? "Winkeyer v" + String(version) : "Winkeyer"
    }

    /// Host close (`00 03`) and closing the port; errors are swallowed, a second close does nothing.
    ///
    /// `ByteTransport.close` contract: over `SerialPort` the read thread may be in `read(2)` right now; `transport.close()`
    /// then waits (at most the 200 ms read timeout) until it leaves it, and only then closes the descriptor. The read thread
    /// gets an error (or sees `closed` after a byte) and ends. Blocking — like Java `closePort`.
    public func close() {
        if isClosed {
            return
        }
        do {
            try write([Self.admin, Self.adminClose])
        } catch {
            // disconnected keyer — close the port anyway
        }
        state.lock()
        closed = true
        state.unlock()
        do {
            try transport.close()
        } catch {
            // nothing else can be done
        }
    }

    /// The Winkeyer accepts a speed of 5–99 WPM.
    static func clampWpm(_ wpm: Int) -> Int {
        max(5, min(99, wpm))
    }

    private static func clamp(_ wpm: Int32) -> Int32 {
        max(5, min(99, wpm))
    }

    private func setBusy(_ value: Bool) {
        state.lock()
        busy = value
        state.unlock()
    }

    private func write(_ bytes: [UInt8]) throws {
        monitor.lock()
        defer { monitor.unlock() }
        do {
            try transport.write(bytes)
        } catch {
            let message = (error as? ByteTransportError)?.description ?? String(describing: error)
            throw CwKeyerError(.uncheckedIO, "Zápis do Winkeyeru selhal: " + message)
        }
    }
}
