import os

/// UDP reception of WSJT-X packets (unicast) — port of `wsjtx/WsjtxListener.java` (v1.1.1). Own thread
/// `wsjtx-listener` reads the socket and passes "Logged ADIF" (type 12) and optionally decodes, status and clear
/// (Decode List) to the handler; other types and bad datagrams are silently dropped (bad ones to the log `WSJT-X: vadný datagram
/// zahozen`). The handler runs synchronously on the reader thread (the UI hops it to the main thread itself).
/// The reply to the WSJT-X address goes through the same socket (`send`). For the socket see `UdpReceiver` (without
/// `SO_REUSEADDR` — a second listener on 2237 gets `BindException`).
public final class WsjtxListener: Sendable {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "WsjtxListener")

    /// Java interface `Handler` with default empty methods.
    public struct Handler: Sendable {
        public var onLoggedAdif: @Sendable (String?) -> Void
        /// A decode from the band; the second parameter = the WSJT-X address for the reply (Reply).
        public var onDecode: @Sendable (WsjtxMessages.Decode, UdpEndpoint) -> Void
        public var onStatus: @Sendable (WsjtxMessages.Status) -> Void
        public var onClear: @Sendable (WsjtxMessages.Clear) -> Void

        public init(onLoggedAdif: @escaping @Sendable (String?) -> Void,
                    onDecode: @escaping @Sendable (WsjtxMessages.Decode, UdpEndpoint) -> Void = { _, _ in },
                    onStatus: @escaping @Sendable (WsjtxMessages.Status) -> Void = { _ in },
                    onClear: @escaping @Sendable (WsjtxMessages.Clear) -> Void = { _ in }) {
            self.onLoggedAdif = onLoggedAdif
            self.onDecode = onDecode
            self.onStatus = onStatus
            self.onClear = onClear
        }
    }

    let receiver: UdpReceiver
    private let handler: Handler

    /// Java `new DatagramSocket(new InetSocketAddress(bindHost, bindPort))`: `IllegalArgumentException` for
    /// a port out of range, `SocketException: Unresolved address`, `BindException: Address already in use`.
    /// Blocking (DNS).
    public init(bindHost: String, bindPort: Int, handler: Handler) throws {
        self.receiver = try UdpReceiver.unicast(host: bindHost, port: bindPort)
        self.handler = handler
    }

    /// Java `boundPort()` (`-1` after closing).
    public var boundPort: Int {
        receiver.boundPort
    }

    public func start() {
        let handler = self.handler
        receiver.start(name: "wsjtx-listener", onDatagram: { data, from in
            Self.dispatch(data, from, handler)
        }, onError: { error in
            Self.log.warning("WSJT-X: vadný datagram zahozen: \(error.description, privacy: .public)")
        })
    }

    static func dispatch(_ data: [UInt8], _ from: UdpEndpoint, _ handler: Handler) {
        let message: WsjtxMessages.Message?
        do {
            message = try WsjtxMessages.decode(data)
        } catch {
            log.warning("WSJT-X: vadný datagram zahozen: \(String(describing: error), privacy: .public)")
            return
        }
        switch message {
        case .loggedAdif(let la):
            handler.onLoggedAdif(la.adif)
        case .decode(let d):
            handler.onDecode(d, from)
        case .status(let s):
            handler.onStatus(s)
        case .clear(let c):
            handler.onClear(c)
        case .qsoLogged, nil:
            break
        }
    }

    /// Sends a datagram (e.g. Reply) to the WSJT-X address from the listener's socket.
    public func send(_ data: [UInt8], to target: UdpEndpoint) throws(JavaSocketError) {
        try receiver.send(data, to: target)
    }

    public func close() {
        receiver.close()
    }

    /// Waits for the reader thread to end (tests and the quit).
    public func waitUntilStopped() async {
        await receiver.waitUntilReaderExits()
    }
}
