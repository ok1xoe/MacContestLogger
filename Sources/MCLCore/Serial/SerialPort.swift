import Darwin
import Foundation

/// Serial port via POSIX `termios` (replacement for jSerialComm 2.11 — `WinkeyerKeyer`, `Otrsp`, `Footswitch`).
///
/// Opening like jSerialComm `openPort()`: `open(O_RDWR | O_NOCTTY | O_NONBLOCK)`, exclusive `flock` lock
/// (`LOCK_EX | LOCK_NB`), return to blocking mode, `cfmakeraw`, speed (`cfsetspeed`, non-standard
/// via `IOSSIOSPEED`), `CS5`–`CS8`, `CSTOPB`, parity, `CLOCAL | CREAD`, no flow control, `tcflush`; DTR and RTS
/// raised (jSerialComm turns them on at open — an `ioctl` error does not stop the open, as there).
///
/// Reading **semi-blocking 200 ms** (Winkeyer's Java `TIMEOUT_READ_SEMI_BLOCKING, 200`): `VMIN=0, VTIME=2`.
/// `read()` returns a byte as soon as there is one; after 200 ms of silence it throws `ByteTransportError("The read operation
/// timed out before any data was returned.")` (Java `SerialPortTimeoutException`) — the Winkeyer read loop
/// then ends as in Java (a defect preserved from Java). End of stream (−1) is never returned by the port.
///
/// **Closing:** `close()` sets a flag and **waits until the reading and writing calls leave `read(2)`/`write(2)`**
/// (thanks to `VTIME` a read returns within 200 ms at most), only then closes the descriptor — macOS `close(fd)` from another
/// thread does not reliably unblock a blocking `read(2)` and the closed fd number could be reused by another file.
/// `close` waits for a writer in `write(2)` without an upper bound — with `CLOCAL` and no flow control a write practically
/// does not block. `close` is blocking: do not call it from the main thread or the shared pool.
/// A read interrupted by closing and every call after closing throw `ByteTransportError("This port appears to have been
/// shutdown or disconnected.")`. A second `close()` does nothing.
///
/// Modem lines: DTR/RTS via `TIOCMBIS`/`TIOCMBIC`, CTS/DSR/CD via `TIOCMGET` (`ModemControl`, replaced
/// in tests — a pseudoterminal does not support them, `ENOTTY`).
///
/// Calls block — they belong on their own thread, not in Swift's shared thread pool.
public final class SerialPort: ByteTransport, @unchecked Sendable {

    public enum Parity: Equatable, Sendable {
        case none, odd, even
    }

    /// Line parameters (Java `setComPortParameters`; default like jSerialComm 9600 8N1).
    public struct Settings: Equatable, Sendable {
        public var baud: Int
        public var dataBits: Int
        public var stopBits: Int
        public var parity: Parity
        /// State of DTR and RTS after opening (jSerialComm: both up).
        public var dtr: Bool
        public var rts: Bool

        public init(baud: Int = 9_600, dataBits: Int = 8, stopBits: Int = 1, parity: Parity = .none,
                    dtr: Bool = true, rts: Bool = true) {
            self.baud = baud
            self.dataBits = dataBits
            self.stopBits = stopBits
            self.parity = parity
            self.dtr = dtr
            self.rts = rts
        }
    }

    /// State of the input modem lines.
    public struct ModemStatus: Equatable, Sendable {
        public let cts: Bool
        public let dsr: Bool
        public let dcd: Bool

        public init(cts: Bool, dsr: Bool, dcd: Bool) {
            self.cts = cts
            self.dsr = dsr
            self.dcd = dcd
        }

        /// From the `TIOCMGET` bits.
        init(bits: Int32) {
            self.init(cts: bits & TIOCM_CTS != 0, dsr: bits & TIOCM_DSR != 0, dcd: bits & TIOCM_CAR != 0)
        }
    }

    /// Modem line `ioctl`s — separated for tests (a pseudoterminal does not support them).
    protocol ModemControl: Sendable {
        /// `TIOCMBIS` (`on`) / `TIOCMBIC` with the mask `bits`.
        func set(fd: Int32, bits: Int32, on: Bool) throws(ByteTransportError)
        /// `TIOCMGET`.
        func get(fd: Int32) throws(ByteTransportError) -> Int32
    }

    struct PosixModemControl: ModemControl {
        func set(fd: Int32, bits: Int32, on: Bool) throws(ByteTransportError) {
            var mask: Int32 = bits
            if ioctl(fd, on ? TIOCMBIS : TIOCMBIC, &mask) != 0 {
                throw SerialPort.errnoError(errno)
            }
        }

        func get(fd: Int32) throws(ByteTransportError) -> Int32 {
            var bits: Int32 = 0
            if ioctl(fd, TIOCMGET, &bits) != 0 {
                throw SerialPort.errnoError(errno)
            }
            return bits
        }
    }

    static let timeoutMessage = "The read operation timed out before any data was returned."
    static let closedMessage = "This port appears to have been shutdown or disconnected."
    /// `IOSSIOSPEED` from `<IOKit/serial/ioss.h>` (`_IOW('T', 2, speed_t)`).
    static let iossioSpeed: UInt = 0x8008_5402

    public let path: String
    private let fd: Int32
    private let modem: any ModemControl

    private let state = NSCondition()
    private var closed = false
    private var reading = false
    private var writing = false
    private var fdClosed = false
    /// `close` caught a reader inside `read(2)` (for tests of the closing contract).
    private(set) var closeWaitedForReader = false
    /// The descriptor was closed while someone was reading or writing on it — the closing contract forbids this (tests).
    private(set) var fdClosedWhileInUse = false

    private let readLock = NSLock()
    private var buffer: [UInt8] = []
    private var position = 0
    private let writeLock = NSLock()

    init(path: String, fd: Int32, modem: any ModemControl) {
        self.path = path
        self.fd = fd
        self.modem = modem
    }

    deinit {
        if !fdClosed {
            _ = Darwin.close(fd)
        }
    }

    /// Opens and configures the port (Java `getCommPort` + `setComPortParameters` + `setComPortTimeouts` +
    /// `openPort`). An error (the port does not exist, is busy, `termios` fails) → `ByteTransportError(strerror)`.
    public static func open(path: String, settings: Settings = Settings()) throws(ByteTransportError) -> SerialPort {
        try open(path: path, settings: settings, modem: PosixModemControl())
    }

    static func open(path: String, settings: Settings, modem: any ModemControl) throws(ByteTransportError) -> SerialPort {
        let fd: Int32 = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            throw errnoError(errno)
        }
        do throws(ByteTransportError) {
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                throw errnoError(errno)
            }
            let flags: Int32 = fcntl(fd, F_GETFL, 0)
            if fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) != 0 {
                throw errnoError(errno)
            }
            try configure(fd: fd, settings: settings)
        } catch {
            _ = Darwin.close(fd)
            throw error
        }
        let port = SerialPort(path: path, fd: fd, modem: modem)
        try? port.setDTR(settings.dtr)
        try? port.setRTS(settings.rts)
        return port
    }

    /// `termios` for `settings` (raw, `VMIN=0`, `VTIME=2`).
    static func configure(fd: Int32, settings: Settings) throws(ByteTransportError) {
        var t = termios()
        if tcgetattr(fd, &t) != 0 {
            throw errnoError(errno)
        }
        cfmakeraw(&t)
        var cflag: tcflag_t = t.c_cflag & ~tcflag_t(CSIZE | PARENB | PARODD | CSTOPB | CRTSCTS)
        switch settings.dataBits {
        case 5: cflag |= tcflag_t(CS5)
        case 6: cflag |= tcflag_t(CS6)
        case 7: cflag |= tcflag_t(CS7)
        default: cflag |= tcflag_t(CS8)
        }
        if settings.stopBits == 2 {
            cflag |= tcflag_t(CSTOPB)
        }
        switch settings.parity {
        case .none: break
        case .even: cflag |= tcflag_t(PARENB)
        case .odd: cflag |= tcflag_t(PARENB | PARODD)
        }
        cflag |= tcflag_t(CLOCAL | CREAD)
        t.c_cflag = cflag
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY | INPCK)
        if settings.parity != .none {
            t.c_iflag |= tcflag_t(INPCK)
        }
        withUnsafeMutableBytes(of: &t.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 2
        }
        // tcsetattr rejects a non-standard speed — it is set separately via IOSSIOSPEED (like jSerialComm).
        let standard: Bool = isStandardBaud(settings.baud)
        if cfsetspeed(&t, speed_t(standard ? settings.baud : 9_600)) != 0 {
            throw errnoError(errno)
        }
        if tcsetattr(fd, TCSANOW, &t) != 0 {
            throw errnoError(errno)
        }
        if !standard {
            var speed = speed_t(settings.baud)
            if ioctl(fd, iossioSpeed, &speed) != 0 {
                throw errnoError(errno)
            }
        }
        _ = tcflush(fd, TCIOFLUSH)
    }

    static func isStandardBaud(_ baud: Int) -> Bool {
        [50, 75, 110, 134, 150, 200, 300, 600, 1_200, 1_800, 2_400, 4_800, 9_600, 19_200, 38_400, 57_600,
         115_200, 230_400].contains(baud)
    }

    static func errnoError(_ code: Int32) -> ByteTransportError {
        ByteTransportError(String(cString: strerror(code)))
    }

    /// Current `termios` (tests).
    func currentTermios() throws(ByteTransportError) -> termios {
        var t = termios()
        if tcgetattr(fd, &t) != 0 {
            throw Self.errnoError(errno)
        }
        return t
    }

    /// The reader thread is currently inside `read(2)` (tests of the closing contract).
    var isReading: Bool {
        state.lock()
        defer { state.unlock() }
        return reading
    }

    public var isOpen: Bool {
        state.lock()
        defer { state.unlock() }
        return !closed
    }

    public func read() throws -> Int {
        readLock.lock()
        defer { readLock.unlock() }
        if isClosedNow {
            throw ByteTransportError(Self.closedMessage)
        }
        if position < buffer.count {
            let b = buffer[position]
            position += 1
            return Int(b)
        }
        try begin(reader: true)
        defer { end(reader: true) }
        var chunk = [UInt8](repeating: 0, count: 64)
        while true {
            let n: Int = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if isClosedNow {
                throw ByteTransportError(Self.closedMessage)
            }
            if n > 0 {
                buffer = Array(chunk[1..<n])
                position = 0
                return Int(chunk[0])
            }
            if n == 0 {
                throw ByteTransportError(Self.timeoutMessage)
            }
            let code: Int32 = errno
            if code == EINTR {
                continue
            }
            throw Self.errnoError(code)
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        try begin(reader: false)
        defer { end(reader: false) }
        var offset = 0
        while offset < bytes.count {
            let n: Int = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n >= 0 {
                offset += n
                continue
            }
            let code: Int32 = errno
            if code == EINTR {
                continue
            }
            throw Self.errnoError(code)
        }
    }

    public func close() throws {
        state.lock()
        defer { state.unlock() }
        if closed {
            return
        }
        closed = true
        if reading {
            closeWaitedForReader = true
        }
        while reading || writing {
            state.wait()
        }
        fdClosedWhileInUse = reading || writing
        fdClosed = true
        _ = Darwin.close(fd)
    }

    /// DTR up/down (Java `setDTR`/`clearDTR`).
    public func setDTR(_ on: Bool) throws(ByteTransportError) {
        try withOpenFd { fd throws(ByteTransportError) in try modem.set(fd: fd, bits: TIOCM_DTR, on: on) }
    }

    /// RTS up/down (Java `setRTS`/`clearRTS`).
    public func setRTS(_ on: Bool) throws(ByteTransportError) {
        try withOpenFd { fd throws(ByteTransportError) in try modem.set(fd: fd, bits: TIOCM_RTS, on: on) }
    }

    /// CTS/DSR/CD (Java `getCTS`/`getDSR`/`getDCD`).
    public func modemStatus() throws(ByteTransportError) -> ModemStatus {
        var bits: Int32 = 0
        try withOpenFd { fd throws(ByteTransportError) in bits = try modem.get(fd: fd) }
        return ModemStatus(bits: bits)
    }

    private var isClosedNow: Bool {
        state.lock()
        defer { state.unlock() }
        return closed
    }

    private func withOpenFd(_ body: (Int32) throws(ByteTransportError) -> Void) throws(ByteTransportError) {
        state.lock()
        defer { state.unlock() }
        if closed {
            throw ByteTransportError(Self.closedMessage)
        }
        try body(fd)
    }

    private func begin(reader: Bool) throws(ByteTransportError) {
        state.lock()
        defer { state.unlock() }
        if closed {
            throw ByteTransportError(Self.closedMessage)
        }
        if reader {
            reading = true
        } else {
            writing = true
        }
    }

    private func end(reader: Bool) {
        state.lock()
        if reader {
            reading = false
        } else {
            writing = false
        }
        state.broadcast()
        state.unlock()
    }
}
