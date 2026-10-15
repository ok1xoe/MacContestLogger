import Foundation
import os

/// The rotors broadcast on the network by the N1MM Rotor program (UDP port 13010): each datagram is one line
/// `<rotor name> @ <heading in tenths of a degree>` (`Tribander @ 2250` = 225.0°). Receiving only — nothing is sent.
public enum RotorNetwork {

    public static let defaultPort = 13010

    /// The rotor name and heading of a datagram, `nil` for anything else.
    public static func parse(_ text: String) -> (name: String, heading: Double)? {
        let line: String = KotlinStrings.trim(text)
        guard let at = line.range(of: " @ ", options: .backwards) else { return nil }
        let name: String = KotlinStrings.trim(String(line[..<at.lowerBound]))
        let value: String = KotlinStrings.trim(String(line[at.upperBound...]))
        guard !name.isEmpty, !value.isEmpty, value.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }),
              let tenths = Int(value) else {
            return nil
        }
        return (name, RotctldClient.normalize(Double(tenths) / 10))
    }
}

/// Receives the N1MM Rotor heading broadcast on its own thread (`UdpReceiver`, the port shared with other programs)
/// and passes each parsed rotor to the handler on that thread.
public final class RotorNetworkListener: Sendable {

    private static let log = Logger(subsystem: "cz.ok1xoe.maccontestlogger", category: "RotorNetworkListener")

    let receiver: UdpReceiver
    private let handler: @Sendable (String, Double) -> Void

    /// Blocking (DNS). `bindHost` `""` is the loopback, `0.0.0.0` every interface.
    public init(bindHost: String, port: Int, handler: @escaping @Sendable (String, Double) -> Void) throws {
        receiver = try UdpReceiver.unicast(host: bindHost, port: port, share: true)
        self.handler = handler
    }

    public var boundPort: Int {
        receiver.boundPort
    }

    public func start() {
        let handler = self.handler
        receiver.start(name: "rotor-network-listener", onDatagram: { data, _ in
            if let rotor = RotorNetwork.parse(String(decoding: data, as: UTF8.self)) {
                handler(rotor.name, rotor.heading)
            }
        }, onError: { error in
            Self.log.warning("Rotor network: datagram dropped: \(error.description, privacy: .public)")
        })
    }

    public func close() {
        receiver.close()
    }

    public func waitUntilStopped() async {
        await receiver.waitUntilReaderExits()
    }
}
