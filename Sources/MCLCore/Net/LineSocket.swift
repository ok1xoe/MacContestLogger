import Darwin
import Foundation

/// Blocking line-oriented TCP client (POSIX) — Java `Socket` + `BufferedReader(InputStreamReader(…, US_ASCII))`
/// + `OutputStream`, as used by `RigctldClient` and `RotctldClient` (measured on Java v1.1.1).
/// Measured by the maintainer-only probe (rows `RL.`, `CONN.`, `CLOSE.`, `WRITE.`, `RESET.`):
///
/// - **Connect** with a timeout (non-blocking `connect` + `poll`; `0` = no limit as in Java). Order of
///   checks like `InetSocketAddress` + `Socket.connect`: `nil` host → `IllegalArgumentException: hostname
///   can't be null`, port outside 0…65535 → `port out of range:<n>`, negative timeout → `connect: timeout can't be
///   negative`, then `UnknownHostException`, `ConnectException: Connection refused`, `SocketTimeoutException:
///   Connect timed out`; port 0 → `BindException: Can't assign requested address`. A negative read timeout
///   (Java `setSoTimeout` after connecting) → `timeout can't be negative`.
/// - **`readLine`** = `BufferedReader.readLine`: terminators `\n`, `\r`, `\r\n`; `\r` returns the line at once (does not wait
///   for the next byte) and a possible `\n` at the start of the **next** read is skipped — even after a timeout in between;
///   bytes ≥ 0x80 → U+FFFD (US-ASCII decoder), control characters stay; the line is not trimmed (the client does
///   the `trim`). End of stream: an unfinished line is returned, then `nil` (also repeatedly). **A read timeout discards
///   the partially read line** (the Java `StringBuilder` is local to `readLine`): `AB` · timeout · `CD\n` → timeout,
///   `"CD"`; bytes after the terminator stay in the buffer. The timeout applies to each single wait for data
///   (`SO_TIMEOUT`), not to the whole line; the socket stays usable after it (a late answer is read as the
///   answer to the next query — R7). Peer RST → `SocketException: Connection reset`, also on every
///   further read.
/// - **`write`** = `write` + `flush` of the socket's unbuffered `OutputStream`; after the peer closes, the first write
///   succeeds and the next throws `SocketException: Broken pipe` (`SO_NOSIGPIPE`, no `SIGPIPE`).
/// - **`close`** from any thread, repeatedly without error: an in-progress `readLine` ends with `SocketException:
///   Socket closed` (`shutdown` + flag check; waits in `poll` of at most 200 ms), further calls throw
///   the same. The descriptor is closed only once no call reads or writes it (no reuse of the fd number
///   under a reader's hands).
///
/// All calls block — they belong on their own thread or a serial queue, not in the shared Swift thread
/// pool. `readLine` and `write` may run concurrently (one thread reads, another writes); concurrent
/// `readLine`s are serialized.
public final class LineSocket: @unchecked Sendable {

    /// Read buffer capacity (Java `BufferedReader`/`StreamDecoder` 8 192).
    static let bufferSize = 8_192
    /// Longest single wait in `poll`, so that `close` from another thread takes effect even without `shutdown`.
    static let pollSliceMs: Int32 = 200

    private let fd: Int32
    /// Java `SO_TIMEOUT` (under `readLock`).
    private var readTimeoutMs: Int

    private let state = NSLock()
    private var closed = false
    private var active = 0
    private var fdClosed = false
    /// The descriptor was closed while someone was reading or writing it — the close contract forbids that (tests).
    private(set) var fdClosedWhileInUse = false

    private let readLock = NSLock()
    private var buffer: [UInt8] = []
    private var position = 0
    private var skipLF = false
    /// After RST every further read throws `Connection reset` again (Java `NioSocketImpl.connectionReset`).
    private var resetSeen = false

    private let writeLock = NSLock()

    private init(fd: Int32, readTimeoutMs: Int) {
        self.fd = fd
        self.readTimeoutMs = readTimeoutMs
    }

    deinit {
        if !fdClosed {
            _ = Darwin.close(fd)
        }
    }

    /// Connects (Java `new Socket()` + `connect(new InetSocketAddress(host, port), connectTimeoutMs)` +
    /// `setSoTimeout(readTimeoutMs)`). Throws `JavaIllegalArgumentError` or `JavaSocketError`.
    public static func connect(host: String?, port: Int, connectTimeoutMs: Int, readTimeoutMs: Int) throws -> LineSocket {
        guard let host else {
            throw JavaIllegalArgumentError(message: "hostname can't be null")
        }
        let resolved: Result<JavaInetAddress, JavaSocketError>
        do {
            resolved = .success(try JavaInetAddress.byName(host))
        } catch where error.kind == .unknownHost {
            // Java `new InetSocketAddress(host, port)` discards the `getByName` text (the address stays unresolved)
            // and `Socket.connect` throws `UnknownHostException(host)` — also for a bad IPv6 literal `[::1`.
            resolved = .failure(.unknownHost(host))
        } catch {
            resolved = .failure(error)
        }
        guard port >= 0 && port <= 65_535 else {
            throw JavaIllegalArgumentError(message: "port out of range:" + String(port))
        }
        guard connectTimeoutMs >= 0 else {
            throw JavaIllegalArgumentError(message: "connect: timeout can't be negative")
        }
        let address: JavaInetAddress = try resolved.get()
        let fd: Int32 = try openConnected(address, port: UInt16(port), timeoutMs: connectTimeoutMs)
        guard readTimeoutMs >= 0 else {
            _ = Darwin.close(fd)
            throw JavaIllegalArgumentError(message: "timeout can't be negative")
        }
        return LineSocket(fd: fd, readTimeoutMs: readTimeoutMs)
    }

    private static func openConnected(_ address: JavaInetAddress, port: UInt16, timeoutMs: Int) throws(JavaSocketError) -> Int32 {
        let fd: Int32 = socket(address.family, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw .connectFailure(errno)
        }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let flags: Int32 = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc: Int32 = address.withSockAddr(port: port) { sa, len in Darwin.connect(fd, sa, len) }
        if rc != 0 {
            let code: Int32 = errno
            guard code == EINPROGRESS || code == EINTR else {
                _ = Darwin.close(fd)
                throw .connectFailure(code)
            }
            do {
                try waitWritable(fd, timeoutMs: timeoutMs)
            } catch {
                _ = Darwin.close(fd)
                throw error
            }
            var soError: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
            if soError != 0 {
                _ = Darwin.close(fd)
                throw .connectFailure(soError)
            }
        }
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        return fd
    }

    private static func waitWritable(_ fd: Int32, timeoutMs: Int) throws(JavaSocketError) {
        let deadline = Deadline(timeoutMs: timeoutMs)
        while true {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let rc: Int32 = poll(&pfd, 1, deadline.remainingMs)
            if rc > 0 {
                return
            }
            if rc < 0 && errno != EINTR {
                throw .connectFailure(errno)
            }
            if rc == 0 && deadline.expired {
                throw .connectTimedOut
            }
        }
    }

    /// Closed by this side (Java `isClosed()`).
    public var isClosed: Bool {
        state.lock()
        defer { state.unlock() }
        return closed
    }

    /// Next line without the terminator, `nil` = end of stream (Java `BufferedReader.readLine`).
    public func readLine() throws(JavaSocketError) -> String? {
        readLock.lock()
        defer { readLock.unlock() }
        try enter()
        defer { leave() }
        var line: [UInt8] = []
        while true {
            if position >= buffer.count {
                let n: Int = try fill()
                if n == 0 {
                    return line.isEmpty ? nil : Self.decodeAscii(line)
                }
            }
            if skipLF && buffer[position] == 0x0A {
                position += 1
            }
            skipLF = false
            var i = position
            while i < buffer.count && buffer[i] != 0x0A && buffer[i] != 0x0D {
                i += 1
            }
            line.append(contentsOf: buffer[position..<i])
            if i < buffer.count {
                skipLF = buffer[i] == 0x0D
                position = i + 1
                return Self.decodeAscii(line)
            }
            position = i
        }
    }

    /// Next available raw bytes (at most `max`; first the rest of the buffer, otherwise one wait for data with the read
    /// timeout), `nil` = end of stream — Java `InputStream.read(byte[])` over the socket. Shares the buffer with `readLine`
    /// (a possible `\n` after a `\r` from a previous `readLine` is not skipped).
    public func readBytes(max: Int = 8_192) throws(JavaSocketError) -> [UInt8]? {
        readLock.lock()
        defer { readLock.unlock() }
        try enter()
        defer { leave() }
        if position >= buffer.count {
            let n: Int = try fill()
            if n == 0 {
                return nil
            }
        }
        let end: Int = min(buffer.count, position + Swift.max(1, max))
        let chunk = Array(buffer[position..<end])
        position = end
        skipLF = false
        return chunk
    }

    /// Changes the timeout of every further wait for data (Java `setSoTimeout`; 0 = no limit, negative →
    /// `timeout can't be negative`).
    public func setReadTimeout(_ ms: Int) throws(JavaIllegalArgumentError) {
        guard ms >= 0 else {
            throw JavaIllegalArgumentError(message: "timeout can't be negative")
        }
        readLock.lock()
        readTimeoutMs = ms
        readLock.unlock()
    }

    /// Writes the bytes whole (Java `out.write(bytes)` + `flush()`).
    public func write(_ bytes: [UInt8]) throws(JavaSocketError) {
        writeLock.lock()
        defer { writeLock.unlock() }
        try enter()
        defer { leave() }
        var offset = 0
        while offset < bytes.count {
            let n: Int = bytes[offset...].withUnsafeBytes { raw in
                Darwin.send(fd, raw.baseAddress, raw.count, 0)
            }
            if n >= 0 {
                offset += n
                continue
            }
            let code: Int32 = errno
            if code == EINTR {
                continue
            }
            throw isClosed ? .socketClosed : .writeFailure(code)
        }
    }

    /// Text as US-ASCII (Java `getBytes(US_ASCII)`: every code point outside ASCII → `?`).
    public func writeAscii(_ text: String) throws(JavaSocketError) {
        try write(Self.encodeAscii(text))
    }

    /// Closes the socket (Java `Socket.close`); a repeated call does nothing.
    public func close() {
        state.lock()
        defer { state.unlock() }
        if closed {
            return
        }
        closed = true
        _ = shutdown(fd, SHUT_RDWR)
        if active == 0 {
            closeFd()
        }
    }

    /// Number of `readLine`/`write` calls in progress (tests of the close contract).
    var activeOperations: Int {
        state.lock()
        defer { state.unlock() }
        return active
    }

    /// Call under the `state` lock.
    private func closeFd() {
        fdClosedWhileInUse = active > 0
        fdClosed = true
        _ = Darwin.close(fd)
    }

    static func encodeAscii(_ text: String) -> [UInt8] {
        text.unicodeScalars.map { $0.isASCII ? UInt8($0.value) : 0x3F }
    }

    static func decodeAscii(_ bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for b in bytes {
            scalars.append(b < 0x80 ? Unicode.Scalar(b) : "\u{FFFD}")
        }
        return String(scalars)
    }

    private func enter() throws(JavaSocketError) {
        state.lock()
        defer { state.unlock() }
        if closed {
            throw .socketClosed
        }
        active += 1
    }

    private func leave() {
        state.lock()
        defer { state.unlock() }
        active -= 1
        if closed && active == 0 && !fdClosed {
            closeFd()
        }
    }

    /// One Java `read` with `SO_TIMEOUT`: waits for data at most `readTimeoutMs` (0 = no limit);
    /// returns the byte count, 0 = end of stream.
    private func fill() throws(JavaSocketError) -> Int {
        if resetSeen {
            throw .readFailure(ECONNRESET)
        }
        let deadline = Deadline(timeoutMs: readTimeoutMs)
        var chunk = [UInt8](repeating: 0, count: Self.bufferSize)
        while true {
            if isClosed {
                throw .socketClosed
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining: Int32 = deadline.remainingMs
            let wait: Int32 = remaining < 0 ? Self.pollSliceMs : min(remaining, Self.pollSliceMs)
            let rc: Int32 = poll(&pfd, 1, wait)
            if rc < 0 {
                let code: Int32 = errno
                if code == EINTR {
                    continue
                }
                throw isClosed ? .socketClosed : .readFailure(code)
            }
            if rc == 0 {
                if deadline.expired {
                    throw .readTimedOut
                }
                continue
            }
            if isClosed {
                throw .socketClosed
            }
            let n: Int = chunk.withUnsafeMutableBytes { raw in
                Darwin.recv(fd, raw.baseAddress, raw.count, 0)
            }
            if n > 0 {
                buffer = Array(chunk[0..<n])
                position = 0
                return n
            }
            if n == 0 {
                if isClosed {
                    throw .socketClosed
                }
                buffer = []
                position = 0
                return 0
            }
            let code: Int32 = errno
            if code == EINTR || code == EAGAIN {
                continue
            }
            if isClosed {
                throw .socketClosed
            }
            resetSeen = code == ECONNRESET
            throw .readFailure(code)
        }
    }
}

/// Monotonic deadline in ms (`0` = no limit, `remainingMs` is then −1 for `poll`).
struct Deadline {
    private let end: UInt64?

    init(timeoutMs: Int) {
        if timeoutMs <= 0 {
            end = nil
        } else {
            end = DispatchTime.now().uptimeNanoseconds &+ UInt64(timeoutMs) &* 1_000_000
        }
    }

    var expired: Bool {
        guard let end else { return false }
        return DispatchTime.now().uptimeNanoseconds >= end
    }

    /// Remaining ms rounded up (for `poll`); −1 = no limit.
    var remainingMs: Int32 {
        guard let end else { return -1 }
        let now: UInt64 = DispatchTime.now().uptimeNanoseconds
        if now >= end {
            return 0
        }
        let ms: UInt64 = (end - now + 999_999) / 1_000_000
        return Int32(min(ms, UInt64(Int32.max)))
    }
}
