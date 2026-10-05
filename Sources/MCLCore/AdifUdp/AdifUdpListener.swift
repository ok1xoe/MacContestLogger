import os

/// UDP reception of a bare ADIF record (fldigi etc.) — port of `adifudp/AdifUdpListener.java` (v1.1.1). Own
/// thread `adif-udp-listener`; passes to the handler only a datagram that looks like ADIF (`AdifUdpFilter`),
/// silently discards the rest. Unicast bind like `WsjtxListener` (`UdpReceiver`). The handler runs on the reader thread.
public final class AdifUdpListener: Sendable {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "AdifUdpListener")

    let receiver: UdpReceiver
    private let handler: @Sendable (String) -> Void

    /// Errors as in `WsjtxListener.init`. Blocking (DNS).
    public init(bindHost: String, bindPort: Int, handler: @escaping @Sendable (String) -> Void) throws {
        self.receiver = try UdpReceiver.unicast(host: bindHost, port: bindPort)
        self.handler = handler
    }

    public var boundPort: Int {
        receiver.boundPort
    }

    public func start() {
        let handler = self.handler
        receiver.start(name: "adif-udp-listener", onDatagram: { data, _ in
            if let adif = AdifUdpFilter.adif(from: data) {
                handler(adif)
            }
        }, onError: { error in
            Self.log.warning("ADIF/UDP: vadný datagram zahozen: \(error.description, privacy: .public)")
        })
    }

    public func close() {
        receiver.close()
    }

    public func waitUntilStopped() async {
        await receiver.waitUntilReaderExits()
    }
}
