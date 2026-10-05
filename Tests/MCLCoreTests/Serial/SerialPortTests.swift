import Darwin
import Foundation
import Testing
@testable import MCLCore

/// `SerialPort` over a **pseudo-terminal** (`openpty`) — no real serial port. A pseudo-terminal carries
/// `termios` and `VMIN`/`VTIME`, but does not support modem lines (`ENOTTY`), so their logic is verified over a
/// `ModemControl` stand-in and over the pty only the error path.
@Suite(.ioSafetyNet) struct SerialPortTests {

    /// A pty pair: `master` (the "device" side) and the path to the slave (the side opened by `SerialPort`).
    final class Pty: @unchecked Sendable {
        let master: Int32
        let slave: Int32
        let path: String

        init() throws {
            var m: Int32 = 0
            var s: Int32 = 0
            guard openpty(&m, &s, nil, nil, nil) == 0 else { throw POSIXError(.EIO) }
            // `ttyname` returns a static buffer — concurrent tests would overwrite each other's paths (and open someone else's pty).
            var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            guard ttyname_r(s, &name, name.count) == 0 else {
                _ = Darwin.close(m)
                _ = Darwin.close(s)
                throw POSIXError(.EIO)
            }
            master = m
            slave = s
            path = String(cString: name)
        }

        deinit {
            _ = Darwin.close(master)
            _ = Darwin.close(slave)
        }

        func write(_ bytes: [UInt8]) {
            _ = bytes.withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
        }

        /// Reads exactly `count` bytes from the device side; if they do not arrive within `timeoutMs`, returns what it has (the test
        /// then fails on a mismatch instead of hanging forever in `read` and with it the waiting test).
        func read(_ count: Int, timeoutMs: Int = 20_000) -> [UInt8] {
            var out: [UInt8] = []
            var buf = [UInt8](repeating: 0, count: 256)
            let deadline = Date(timeIntervalSinceNow: Double(timeoutMs) / 1_000)
            while out.count < count {
                let left = Int(deadline.timeIntervalSinceNow * 1_000)
                if left <= 0 { break }
                var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pfd, 1, Int32(min(left, 1_000)))
                if ready < 0 && errno == EINTR { continue }
                if ready <= 0 { continue }
                let n = buf.withUnsafeMutableBytes { Darwin.read(master, $0.baseAddress, min($0.count, count - out.count)) }
                if n <= 0 { break }
                out.append(contentsOf: buf[0..<n])
            }
            return out
        }
    }

    /// A stand-in for `ioctl` of modem lines: a record of calls and scripted `TIOCMGET` bits.
    final class FakeModem: SerialPort.ModemControl, @unchecked Sendable {
        private let lock = NSLock()
        private var log: [String] = []
        var bits: Int32 = 0

        func set(fd: Int32, bits: Int32, on: Bool) throws(ByteTransportError) {
            let name = bits == TIOCM_DTR ? "DTR" : bits == TIOCM_RTS ? "RTS" : String(bits)
            lock.lock()
            log.append(name + (on ? " on" : " off"))
            lock.unlock()
        }

        func get(fd: Int32) throws(ByteTransportError) -> Int32 {
            lock.lock()
            defer { lock.unlock() }
            log.append("get")
            return bits
        }

        var calls: [String] {
            lock.lock()
            defer { lock.unlock() }
            return log
        }
    }

    static let winkeyer = SerialPort.Settings(baud: 1_200, dataBits: 8, stopBits: 2, parity: .none, dtr: true, rts: false)

    @Test func winkeyerTermios() throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer)
        defer { try? port.close() }
        let t = try port.currentTermios()
        #expect(t.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8))
        #expect(t.c_cflag & tcflag_t(CSTOPB) != 0)
        #expect(t.c_cflag & tcflag_t(PARENB) == 0)
        #expect(t.c_cflag & tcflag_t(CRTSCTS) == 0)
        #expect(t.c_cflag & tcflag_t(CLOCAL | CREAD) == tcflag_t(CLOCAL | CREAD))
        #expect(t.c_lflag & tcflag_t(ICANON | ECHO | ISIG) == 0)
        #expect(t.c_oflag & tcflag_t(OPOST) == 0)
        #expect(t.c_iflag & tcflag_t(IXON | IXOFF | ICRNL) == 0)
        var copy = t
        #expect(cfgetospeed(&copy) == 1_200)
        #expect(cfgetispeed(&copy) == 1_200)
        let cc = withUnsafeBytes(of: t.c_cc) { Array($0) }
        #expect(cc[Int(VMIN)] == 0)
        #expect(cc[Int(VTIME)] == 2)
    }

    @Test func parityAndDataBits() throws {
        let pty = try Pty()
        let even = try SerialPort.open(path: pty.path, settings: .init(baud: 9_600, dataBits: 7, stopBits: 1, parity: .even))
        var t = try even.currentTermios()
        try even.close()
        #expect(t.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS7))
        #expect(t.c_cflag & tcflag_t(PARENB | PARODD) == tcflag_t(PARENB))
        #expect(t.c_cflag & tcflag_t(CSTOPB) == 0)
        #expect(t.c_iflag & tcflag_t(INPCK) != 0)
        #expect(cfgetospeed(&t) == 9_600)
        let odd = try SerialPort.open(path: pty.path, settings: .init(parity: .odd))
        t = try odd.currentTermios()
        try odd.close()
        #expect(t.c_cflag & tcflag_t(PARENB | PARODD) == tcflag_t(PARENB | PARODD))
        #expect(t.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8))
    }

    @Test func openErrors() throws {
        #expect(throws: ByteTransportError("No such file or directory")) {
            try SerialPort.open(path: "/dev/cu.mcl-test-does-not-exist")
        }
        // An exclusive lock (jSerialComm `flock`): a second open of the same port fails.
        let pty = try Pty()
        let first = try SerialPort.open(path: pty.path)
        defer { try? first.close() }
        #expect(throws: ByteTransportError("Resource temporarily unavailable")) {
            try SerialPort.open(path: pty.path)
        }
    }

    @Test func writeAndReadBytes() async throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer)
        defer { try? port.close() }
        try await onOwnThread { try port.write([0x00, 0x02, 0x80, 0xFF]) }
        #expect(await onOwnThread { pty.read(4) } == [0x00, 0x02, 0x80, 0xFF])
        pty.write([31, 0xC0, 0xC4])
        let got: [Int] = try await onOwnThread { [try port.read(), try port.read(), try port.read()] }
        #expect(got == [31, 0xC0, 0xC4])
    }

    /// Debt 1: 200 ms of silence → Java `SerialPortTimeoutException` (the Winkeyer read loop ends by it).
    @Test func silenceTimesOut() async throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer)
        defer { try? port.close() }
        let error: ByteTransportError? = await onOwnThread {
            do {
                _ = try port.read()
                return nil
            } catch {
                return error as? ByteTransportError
            }
        }
        #expect(error == ByteTransportError("The read operation timed out before any data was returned."))
    }

    /// The closing contract: `close` from another thread waits until the reader leaves `read(2)`, then closes the fd; the reader
    /// gets a close error, further calls throw the same, a second `close` does nothing.
    @Test func closeWaitsForReaderThenClosesFd() async throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer)
        async let reader: String = onOwnThread {
            while true {
                do {
                    _ = try port.read()
                } catch let e as ByteTransportError {
                    if e.message != SerialPort.timeoutMessage { return e.description }
                } catch {
                    return String(describing: error)
                }
            }
        }
        // `closeWaitedForReader` is not asserted: the reader may stand outside the syscall in the microsecond window between two `read(2)`.
        // `fdClosedWhileInUse` decides (the mutation "close the fd at once" lights it up).
        let fdInUse: Bool = try await onOwnThread {
            while !port.isReading {
                Thread.sleep(forTimeInterval: 0.005)
            }
            try port.close()
            try port.close()
            return port.fdClosedWhileInUse
        }
        #expect(!fdInUse)
        #expect(await reader == SerialPort.closedMessage)
        #expect(!port.isOpen)
        #expect(throws: ByteTransportError(SerialPort.closedMessage)) { try port.read() }
        #expect(throws: ByteTransportError(SerialPort.closedMessage)) { try port.write([1]) }
        #expect(throws: ByteTransportError(SerialPort.closedMessage)) { try port.setDTR(true) }
    }

    /// Winkeyer over a real (pty) transport: `close` during the reader thread does not hang.
    @Test func winkeyerCloseOverSerialPort() async throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer)
        let keyer = WinkeyerKeyer(transport: port)
        await onOwnThread { keyer.close() }
        #expect(await onOwnThread { pty.read(2) } == [0x00, 0x03])
        #expect(!port.isOpen)
    }

    // MARK: - Modem lines

    @Test func openRaisesConfiguredModemLines() throws {
        let pty = try Pty()
        let modem = FakeModem()
        let port = try SerialPort.open(path: pty.path, settings: Self.winkeyer, modem: modem)
        defer { try? port.close() }
        #expect(modem.calls == ["DTR on", "RTS off"])
        try port.setRTS(true)
        try port.setDTR(false)
        #expect(modem.calls == ["DTR on", "RTS off", "RTS on", "DTR off"])
    }

    @Test func modemStatusBits() throws {
        let pty = try Pty()
        let modem = FakeModem()
        let port = try SerialPort.open(path: pty.path, settings: .init(), modem: modem)
        defer { try? port.close() }
        modem.bits = TIOCM_CTS | TIOCM_CAR
        #expect(try port.modemStatus() == SerialPort.ModemStatus(cts: true, dsr: false, dcd: true))
        modem.bits = TIOCM_DSR | TIOCM_DTR | TIOCM_RTS
        #expect(try port.modemStatus() == SerialPort.ModemStatus(cts: false, dsr: true, dcd: false))
        modem.bits = 0
        #expect(try port.modemStatus() == SerialPort.ModemStatus(cts: false, dsr: false, dcd: false))
    }

    /// A real `ioctl` over a pty: a pty has no modem lines — the open passes (like jSerialComm), the calls throw.
    @Test func posixModemIoctlOnPtyFails() throws {
        let pty = try Pty()
        let port = try SerialPort.open(path: pty.path)
        defer { try? port.close() }
        #expect(throws: ByteTransportError("Inappropriate ioctl for device")) { try port.setDTR(true) }
        #expect(throws: ByteTransportError("Inappropriate ioctl for device")) { try port.modemStatus() }
    }
}
