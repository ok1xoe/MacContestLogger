import Foundation
import os

/// DX cluster telnet client error (Java `dxcluster.DxClusterException`, a `RuntimeException` with a message
/// and an optional cause). Kotlin status lines show `message`.
public struct DxClusterException: Error, Sendable, CustomStringConvertible {
    public let message: String
    /// Java `getCause()` — `JavaSocketError` for connect, read and write errors.
    public let cause: (any Error)?

    public init(_ message: String, cause: (any Error)? = nil) {
        self.message = message
        self.cause = cause
    }

    public var description: String { message }
}

/// Telnet client for a DX cluster (Java `dxcluster.DxClusterClient`). The protocol is purely line-based ASCII text
/// with a login prompt — no IAC negotiation, `LineSocket` is enough (4.1).
///
/// Behaviour as in Java v1.1.1:
/// - **Connect** in the constructor: `LineSocket.connect` with timeout `timeoutMs` (default 8,000 ms) and **no
///   read timeout** (the cluster stays silent for long). Socket error → `DxClusterException("Nelze se připojit
///   k DX clusteru na <host>:<port>")` with a cause; argument errors (`port out of range:<n>`, negative timeout)
///   pass through as `JavaIllegalArgumentError` unwrapped (Java catches only `IOException`).
/// - **Read loop** on its own thread `dxcluster-reader` (not in Swift's shared pool): each line →
///   `onLine` synchronously on that thread; EOF → `onError(DxClusterException("DX cluster ukončil spojení"))`;
///   read error → `onError(DxClusterException("Chyba čtení z DX clusteru", cause))`; an error thrown
///   from `onLine` (Java `RuntimeException`, e.g. `JavaNumberFormatError` from `WwvMessage.parse`) → `onError`
///   with itself. In all three cases the loop ends, but the socket stays open (the caller closes it)
///   and `isConnected` keeps returning `true`. After `close()` `onError` is no longer called.
/// - **`send`**: `line + "\r\n"` in US-ASCII (non-ASCII → `?`); error → `DxClusterException("Chyba zápisu
///   příkazu '<line>' do DX clusteru")` with a cause. Blocks — call off the main thread and off the pool.
/// - **`close`**: first clears the running flag, then closes the socket (unblocks a waiting `readLine`).
///
/// The client does not hop callbacks to the main thread — the caller does (`DxClusterSession`, the UI layer).
public final class DxClusterClient: @unchecked Sendable {

    /// Java default connect timeout.
    public static let defaultTimeoutMs = 8_000

    private let socket: LineSocket
    private let onLine: @Sendable (String) throws -> Void
    private let onError: @Sendable (any Error) -> Void
    /// Java `volatile boolean running`.
    private let running = OSAllocatedUnfairLock(initialState: true)

    /// Connects and starts the reader thread. Blocks up to `timeoutMs` — call off the main thread and off the pool.
    ///
    /// - Throws: `DxClusterException` (socket) or `JavaIllegalArgumentError` (port, timeout).
    public init(host: String, port: Int, timeoutMs: Int = DxClusterClient.defaultTimeoutMs,
                onLine: @escaping @Sendable (String) throws -> Void,
                onError: @escaping @Sendable (any Error) -> Void) throws {
        self.onLine = onLine
        self.onError = onError
        do {
            socket = try LineSocket.connect(host: host, port: port, connectTimeoutMs: timeoutMs, readTimeoutMs: 0)
        } catch let e as JavaSocketError {
            throw DxClusterException("Nelze se připojit k DX clusteru na \(host):\(port)", cause: e)
        }
        let thread = Thread { [self] in
            loop()
        }
        thread.name = "dxcluster-reader"
        thread.start()
    }

    private var isRunning: Bool {
        running.withLock { $0 }
    }

    private func loop() {
        while isRunning {
            let line: String?
            do {
                line = try socket.readLine()
            } catch {
                if isRunning {
                    onError(DxClusterException("Chyba čtení z DX clusteru", cause: error))
                }
                return
            }
            guard let line else {
                if isRunning {
                    onError(DxClusterException("DX cluster ukončil spojení"))
                }
                return
            }
            do {
                try onLine(line)
            } catch {
                if isRunning {
                    onError(error)
                }
                return
            }
        }
    }

    /// Sends a line command (the cluster expects CRLF). A line with a CR or LF inside is refused — it would be
    /// several commands (never a caller's intention; a guard against injected text).
    public func send(_ line: String) throws(DxClusterException) {
        guard !line.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" }) else {
            throw DxClusterException("Příkaz pro DX cluster obsahuje konec řádku")
        }
        do {
            try socket.writeAscii(line + "\r\n")
        } catch {
            throw DxClusterException("Chyba zápisu příkazu '\(line)' do DX clusteru", cause: error)
        }
    }

    /// Java `running && socket.isConnected() && !socket.isClosed()`.
    public var isConnected: Bool {
        isRunning && !socket.isClosed
    }

    /// Ends the connection; closing the socket unblocks a waiting `readLine`.
    public func close() {
        running.withLock { $0 = false }
        socket.close()
    }
}
