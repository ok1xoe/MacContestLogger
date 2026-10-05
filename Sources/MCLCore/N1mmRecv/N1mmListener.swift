import os

/// UDP reception of the N1MM `<contactinfo>` broadcast — port of `n1mmrecv/N1mmListener.java` (v1.1.1). Own thread
/// `n1mm-listener`; passes to the handler only a datagram containing `<contactinfo` (case-sensitive,
/// `N1MM.caseSensitive`), silently discards the rest. A bind address in the multicast range → Java
/// `MulticastSocket(port)` + `joinGroup` (wildcard bind with `SO_REUSEADDR`/`SO_REUSEPORT`, also accepts unicast
/// to the port, `N1MM.mcastUnicastToPort`), otherwise unicast (`UdpReceiver`). The handler runs on the reader thread.
public final class N1mmListener: Sendable {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "N1mmListener")
    private static let contactInfoTag: [UInt16] = Array("<contactinfo".utf16)

    let receiver: UdpReceiver
    private let handler: @Sendable (String) -> Void

    /// Java order: `InetAddress.getByName(bindHost)` (`UnknownHostException`, `N1MM.unresolved`), then
    /// the port check (`IllegalArgumentException: port out of range:<n>`), then bind/join. Blocking (DNS).
    public convenience init(bindHost: String, bindPort: Int, handler: @escaping @Sendable (String) -> Void) throws {
        try self.init(bindHost: bindHost, bindPort: bindPort, multicastInterface: nil, handler: handler)
    }

    /// `multicastInterface` only for tests (interface index for the join; default = Java's default interface).
    init(bindHost: String, bindPort: Int, multicastInterface: UInt32?,
         handler: @escaping @Sendable (String) -> Void) throws {
        let address: JavaInetAddress = try JavaInetAddress.byName(bindHost)
        if address.isMulticast {
            let index: UInt32 = multicastInterface ?? DefaultMulticastInterface.index
            self.receiver = try UdpReceiver.multicast(group: address, port: bindPort, interfaceIndex: index)
        } else {
            self.receiver = try UdpReceiver.unicast(address: address, port: bindPort)
        }
        self.handler = handler
    }

    public var boundPort: Int {
        receiver.boundPort
    }

    /// Datagram text (`new String(bytes, UTF_8)`) if it contains `<contactinfo` (search by UTF-16); otherwise `nil`.
    static func contactInfo(from datagram: [UInt8]) -> String? {
        let text: String = JavaUtf8.decode(datagram)
        guard JavaText.indexOf(Array(text.utf16), contactInfoTag) >= 0 else { return nil }
        return text
    }

    public func start() {
        let handler = self.handler
        receiver.start(name: "n1mm-listener", onDatagram: { data, _ in
            if let xml = Self.contactInfo(from: data) {
                handler(xml)
            }
        }, onError: { error in
            Self.log.warning("N1MM: vadný datagram zahozen: \(error.description, privacy: .public)")
        })
    }

    public func close() {
        receiver.close()
    }

    public func waitUntilStopped() async {
        await receiver.waitUntilReaderExits()
    }
}
